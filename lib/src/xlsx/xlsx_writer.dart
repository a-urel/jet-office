/// The streaming XLSX writers: [XlsxWriter] (in memory) and
/// [XlsxStreamWriter] (to a sink).
///
/// Ported from quds_office_engine `lib/src/builders/xlsx_io.dart` at commit 15c5d29.
/// Ported: `XlsxWorkbookBuilder.addSheet` and `build`, and the row loop,
/// `colWidth` and row heights of `XlsxSheetBuilder` and `_sheetXml`. What
/// changed: Quds kept every sheet as a list of rows and serialized the whole
/// workbook in `build`; here rows are encoded as they arrive, one sheet is
/// open at a time, and a finished sheet goes straight to the ZIP, its header
/// (`worksheet_parts.dart`) assembled around the row chunks without joining
/// them, so memory is bounded by one sheet's buffer. Header settings
/// (columns, default sizes) are frozen at the first row; rows carry a
/// height, visibility and outline level. Tab order is independent of
/// creation order, the active tab is chosen by the caller, a workbook
/// without sheets is an error instead of silently gaining `Sheet1`, Excel's
/// row and column limits are enforced, and data problems are returned as
/// warnings. A sheet has a view (zoom, gridlines, frozen or split panes), a
/// tab color, an outline summary position and a visibility. Merged ranges
/// and the auto filter are trailer settings, checked when set: Quds accepted
/// overlapping merges and any filter text, and wrote no filter database
/// name. Charts and pictures are not ported yet.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../xml/utf8_buffer.dart';
import '../xml/xml_number.dart';
import '../xml/xml_writer.dart';
import '../zip/archive_adapter.dart';
import 'cell_encoder.dart';
import 'color.dart';
import 'column.dart';
import 'limits.dart';
import 'properties.dart';
import 'range.dart';
import 'shared_strings.dart';
import 'sheet_name.dart';
import 'sheet_view.dart';
import 'style.dart';
import 'style_registry.dart';
import 'values.dart';
import 'warnings.dart';
import 'workbook_parts.dart';
import 'worksheet_parts.dart';

/// Writes a part with [write] and returns its UTF-8 bytes.
Uint8List _render(void Function(XmlWriter w) write) {
  final Utf8Buffer buffer = Utf8Buffer();
  write(XmlWriter(buffer));
  return buffer.takeBytes();
}

/// What the two XLSX writers share: adding sheets, ordering their tabs and
/// choosing the active one.
///
/// Use [XlsxWriter] to get the file as bytes, or [XlsxStreamWriter] to send
/// it to a sink as it is written. Both are synchronous: cells are encoded in
/// [XlsxSheetWriter.row], and `close()` writes the workbook-level parts and
/// finishes the ZIP.
///
/// One sheet is open at a time. [addSheet] finishes the open sheet, whose
/// part is then compressed and handed to the ZIP, so memory holds one sheet's
/// XML plus the workbook's distinct strings and styles, not the whole file.
/// The same calls always produce the same bytes.
sealed class XlsxWriterBase {
  XlsxWriterBase._(XlsxProperties properties, ZipWriter Function() createZip)
    : _coreXml = _render((XmlWriter w) => writeCoreProperties(w, properties)),
      _appXml = _render((XmlWriter w) => writeAppProperties(w, properties)),
      _zip = createZip();

  final Uint8List _coreXml;
  final Uint8List _appXml;
  final ZipWriter _zip;
  final WarningCollector _warnings = WarningCollector();
  late final SheetNamer _namer = SheetNamer(_warnings);
  final SharedStrings _strings = SharedStrings();
  final StyleRegistry _styles = StyleRegistry();
  late final CellEncoder _encoder = CellEncoder(
    strings: _strings,
    styles: _styles,
    warnings: _warnings,
  );

  /// The sheets in tab order.
  final List<_SheetWriter> _tabs = <_SheetWriter>[];
  _SheetWriter? _open;
  _SheetWriter? _active;
  bool _closed = false;

  /// What the ZIP work threw, once it has failed; the writer is then dead.
  Object? _failure;

  /// Finishes the open sheet and starts a new one named [name].
  ///
  /// The name is made valid and unique as Excel requires; a changed name is
  /// reported as a warning and is the one [XlsxSheetWriter.name] returns.
  ///
  /// The sheet is placed at index [position] of the tab order, `0` being the
  /// first tab; by default it goes last. Tab order is independent of the
  /// order sheets are written in, so a summary can be written last and still
  /// come first.
  ///
  /// A sheet that is [XlsxSheetVisibility.hidden] or
  /// [XlsxSheetVisibility.veryHidden] gets no visible tab but takes rows as
  /// any other; a workbook needs at least one visible sheet by `close()`.
  ///
  /// Throws [RangeError] when [position] is outside `0` to the number of
  /// sheets so far, and [StateError] after `close()` or after a failure.
  /// Rethrows what the sink throws while the open sheet is finished; the
  /// writer has then failed (see [XlsxStreamWriter]).
  XlsxSheetWriter addSheet(
    String name, {
    int? position,
    XlsxSheetVisibility visibility = XlsxSheetVisibility.visible,
  }) {
    _checkOpen();
    if (position != null) {
      RangeError.checkValueInInterval(position, 0, _tabs.length, 'position');
    }
    final _SheetWriter? open = _open;
    if (open != null) _zipWork(open._finish);
    final _SheetWriter sheet = _SheetWriter(
      this,
      _namer.assign(name),
      _tabs.length + 1,
      visibility,
    );
    _tabs.insert(position ?? _tabs.length, sheet);
    _open = sheet;
    return sheet;
  }

  /// Makes [sheet] the tab Excel shows when the file is opened.
  ///
  /// Without a call, the first visible tab in tab order is active. The tab
  /// index is resolved at `close()`, so later inserts before [sheet] keep it
  /// active.
  ///
  /// Throws [ArgumentError] when [sheet] was not added to this writer or is
  /// hidden (a hidden sheet cannot be the one Excel opens on), and
  /// [StateError] after `close()` or after a failure.
  void setActiveSheet(XlsxSheetWriter sheet) {
    _checkOpen();
    if (sheet is! _SheetWriter || !identical(sheet._book, this)) {
      throw ArgumentError.value(
        sheet.name,
        'sheet',
        'Not a sheet of this writer.',
      );
    }
    if (sheet.visibility != XlsxSheetVisibility.visible) {
      throw ArgumentError.value(
        sheet.name,
        'sheet',
        'A ${sheet.visibility.name} sheet cannot be the active sheet.',
      );
    }
    _active = sheet;
  }

  void _checkOpen() {
    _checkNotFailed();
    if (_closed) {
      throw StateError('The XLSX writer is already closed.');
    }
  }

  void _checkNotFailed() {
    final Object? failure = _failure;
    if (failure != null) {
      throw StateError(
        'The writer failed earlier and cannot continue: $failure',
      );
    }
  }

  /// Runs [work], which hands bytes to the ZIP; if it throws, the writer
  /// has failed and every later call throws a [StateError].
  T _zipWork<T>(T Function() work) {
    try {
      return work();
    } on Object catch (error) {
      _failure = error;
      rethrow;
    }
  }

  /// Finishes the open sheet, writes the workbook-level parts and finishes
  /// the ZIP, returning its bytes in memory mode.
  Uint8List? _close() {
    _checkOpen();
    if (_tabs.isEmpty) {
      throw StateError('A workbook needs at least one sheet; add one first.');
    }
    if (_activeTab() < 0) {
      throw StateError(
        'A workbook needs at least one visible sheet; every sheet is hidden. '
        'Add a visible sheet first.',
      );
    }
    return _zipWork(() {
      _open?._finish();
      _open = null;
      final Uint8List? bytes = _writeWorkbookParts();
      _closed = true;
      return bytes;
    });
  }

  /// The tab index Excel opens on: the sheet chosen with [setActiveSheet],
  /// else the first visible tab; -1 when no tab is visible.
  int _activeTab() {
    final _SheetWriter? chosen = _active;
    if (chosen != null) return _tabs.indexOf(chosen);
    return _tabs.indexWhere(
      (_SheetWriter s) => s.visibility == XlsxSheetVisibility.visible,
    );
  }

  /// Writes the workbook-level parts and finishes the ZIP.
  Uint8List? _writeWorkbookParts() {
    final int sheetCount = _tabs.length;
    _zip
      ..add('xl/sharedStrings.xml', _render(_strings.writeXml))
      ..add('xl/styles.xml', _render(_styles.writeStylesXml))
      ..add(
        'xl/workbook.xml',
        _render(
          (XmlWriter w) => writeWorkbook(
            w,
            tabs: <WorkbookSheet>[
              for (final _SheetWriter s in _tabs)
                (
                  name: s.name,
                  number: s._number,
                  visibility: s.visibility,
                  autoFilter: s._autoFilter,
                ),
            ],
            activeTab: _activeTab(),
            fullCalcOnLoad: _encoder.wroteFormula,
          ),
        ),
      )
      ..add(
        'xl/_rels/workbook.xml.rels',
        _render((XmlWriter w) => writeWorkbookRelationships(w, sheetCount)),
      )
      ..add('docProps/core.xml', _coreXml)
      ..add('docProps/app.xml', _appXml)
      ..add('_rels/.rels', _render(writeRootRelationships))
      ..add(
        '[Content_Types].xml',
        _render((XmlWriter w) => writeContentTypes(w, sheetCount)),
      );
    return _zip.close();
  }
}

/// Writes an XLSX file in memory and returns it from [close].
///
/// ```dart
/// final XlsxWriter book = XlsxWriter();
/// final XlsxSheetWriter sheet = book.addSheet('Accounts');
/// sheet.row(<Object?>['Code', 'Balance']);
/// sheet.row(<Object?>['A-1', XlsxDecimal('1234.50')]);
/// final XlsxResult out = book.close();
/// ```
final class XlsxWriter extends XlsxWriterBase {
  /// Creates a writer whose document properties are [properties].
  ///
  /// Throws [ArgumentError] when a property holds characters XML forbids.
  XlsxWriter({XlsxProperties properties = const XlsxProperties()})
    : super._(properties, ZipWriter.new);

  /// Finishes the open sheet and the file, and returns the file with the
  /// warnings about data that had to be changed.
  ///
  /// Throws [StateError] when no sheet was added or when called twice.
  XlsxResult close() => XlsxResult._(_close()!, _warnings.warnings);
}

/// Writes an XLSX file to a sink as it goes.
///
/// Each finished sheet is compressed, and the compressed bytes reach the sink
/// in chunks of about 64 KiB as parts finish; the writer keeps none of the
/// bytes it has sent. The bytes that reach the sink are identical to what
/// [XlsxWriter] returns for the same calls.
///
/// When the sink throws, the call that was writing to it (`addSheet` or
/// `close()`) rethrows the error, the sink is closed and the writer has
/// failed: every later call throws a [StateError]. The file in the sink is
/// then incomplete and should be discarded.
final class XlsxStreamWriter extends XlsxWriterBase {
  /// Creates a writer that sends the file to [sink], with the document
  /// properties [properties].
  ///
  /// Throws [ArgumentError] when a property holds characters XML forbids;
  /// nothing has been sent to [sink] then.
  XlsxStreamWriter(
    Sink<List<int>> sink, {
    XlsxProperties properties = const XlsxProperties(),
  }) : super._(properties, () => ZipWriter(sink: sink));

  /// Finishes the open sheet and the file, closes the sink and returns the
  /// warnings about data that had to be changed.
  ///
  /// Throws [StateError] when no sheet was added (the sink then stays open),
  /// when called twice or after a failure. Rethrows what the sink throws.
  List<XlsxWarning> close() {
    _close();
    return _warnings.warnings;
  }
}

/// A finished XLSX file and what the writer had to change to produce it.
final class XlsxResult {
  XlsxResult._(this.bytes, this.warnings);

  /// The XLSX file.
  final Uint8List bytes;

  /// Data problems the writer repaired, in first-occurrence order. Empty
  /// when the data was written exactly as given. Unmodifiable, and final once
  /// `close()` has returned.
  final List<XlsxWarning> warnings;
}

/// Writes the rows of one worksheet.
///
/// Obtained from [XlsxWriterBase.addSheet], the only way to get one: the
/// class cannot be implemented or extended outside this package. A sheet
/// accepts rows until the next `addSheet` or `close()` finishes it.
///
/// The header settings, [columns], [defaultSizes], [view], [freeze],
/// [split], [tabColor] and [outlineSummary], describe the sheet as a whole
/// and must come before the first [row] or [blankRow]; after that they throw
/// [StateError]. Calling one again before the first row replaces
/// what the earlier call set.
abstract final class XlsxSheetWriter {
  /// The sheet's name in the file, after any renaming (see
  /// [XlsxWriterBase.addSheet]).
  String get name;

  /// The number of rows written so far, blank rows included. The next row
  /// is row `rowCount + 1` in Excel.
  int get rowCount;

  /// Sets the widths, styles, visibility and outline levels of the columns.
  ///
  /// Index `i` of [columns] describes column `i`, A being 0; a `null` entry,
  /// like an [XlsxColumn] that sets nothing, keeps the column at its
  /// default. A column's style applies to its cells beneath the row and cell
  /// styles (see [row]) and to its empty cells. Equal adjacent columns are
  /// written as one range.
  ///
  /// Throws [StateError] after the first [row] or [blankRow], when the sheet
  /// is finished or the writer has failed; [XlsxLimitError] for more than
  /// [XlsxLimits.maxColumns] entries; [ArgumentError] for a width outside 0
  /// to [XlsxLimits.maxColumnWidth], an outline level outside 0 to
  /// [XlsxLimits.maxOutlineLevel], or an invalid style (as [row] describes);
  /// and `XlsxLimitError('cell formats', ...)` like [row]. When it throws,
  /// nothing is recorded: the earlier columns, if any, stay in force and no
  /// style is registered.
  void columns(List<XlsxColumn?> columns);

  /// Sets the sheet's default row height in points and default column width
  /// in characters; `null` keeps Excel's default (15 points and 9.140625
  /// characters for Calibri 11).
  ///
  /// Throws [StateError] like [columns], and [ArgumentError] for a
  /// [rowHeight] outside 0 to [XlsxLimits.maxRowHeight] or a [columnWidth]
  /// outside 0 to [XlsxLimits.maxColumnWidth]; nothing is recorded then.
  void defaultSizes({double? rowHeight, double? columnWidth});

  /// Whether the sheet is shown as a tab; set by
  /// [XlsxWriterBase.addSheet].
  XlsxSheetVisibility get visibility;

  /// Sets how the sheet is shown: zoom, gridlines, headings, right-to-left
  /// and its panes. Replaces the whole earlier view, its pane included.
  ///
  /// Throws [StateError] like [columns], and [ArgumentError] for a zoom
  /// outside [XlsxLimits.minZoom] to [XlsxLimits.maxZoom] or an invalid pane
  /// (see [freeze] and [split]); nothing is recorded then.
  void view(XlsxSheetView view);

  /// Freezes the first [rows] rows and [columns] columns, so they stay in
  /// view while the rest scrolls. The rest of the current view (zoom and so
  /// on) is kept; the earlier pane, if any, is replaced. Freezing 0 rows and
  /// 0 columns writes no pane, so a header count computed from the data may
  /// be 0.
  ///
  /// Throws [StateError] like [columns], and [ArgumentError] for [rows]
  /// outside 0 to 1,048,575 or [columns] outside 0 to 16,383; nothing is
  /// recorded then.
  void freeze({int rows = 0, int columns = 0});

  /// Splits the sheet into panes [x] points from the left edge and [y]
  /// points from the top. The rest of the current view is kept; the earlier
  /// pane, if any, is replaced. A split of 0 on both axes writes no pane.
  ///
  /// Throws [StateError] like [columns], and [ArgumentError] for an offset
  /// that is negative, NaN or infinite; nothing is recorded then.
  void split({double x = 0, double y = 0});

  /// Colors the sheet's tab. A later call replaces the earlier one.
  ///
  /// Throws [StateError] like [columns], and [ArgumentError] for a color out
  /// of range (see [XlsxColor]); nothing is recorded then.
  void tabColor(XlsxColor color);

  /// Sets where the summary row and column of an outline group (see
  /// [row]'s `outlineLevel` and [columns]) sit: [below] its detail rows and
  /// [right] of its detail columns, as Excel does by default.
  ///
  /// Throws [StateError] like [columns].
  void outlineSummary({bool below = true, bool right = true});

  /// Merges the cells of [range] into one, which shows the top-left cell.
  ///
  /// A trailer setting: allowed after rows, until the next `addSheet` or
  /// `close()` finishes the sheet. Merges are written in the order made.
  /// Excel keeps only the top-left cell's value, so write the value there;
  /// the other cells of the range should be empty.
  ///
  /// Throws [StateError] when the sheet is finished or the writer has failed;
  /// [ArgumentError] when [range] is a single cell, lies outside the sheet,
  /// has its first corner after its last, or overlaps an earlier merge (the
  /// message names both ranges). When it throws, nothing is recorded.
  void merge(XlsxRange range);

  /// Puts an auto filter, the drop-down buttons of a header row, on [range],
  /// whose first row is the header. A later call replaces the earlier one.
  ///
  /// A trailer setting like [merge]. The workbook also gets the hidden
  /// `_xlnm._FilterDatabase` name Excel keeps for the filter. A single-cell
  /// [range] is accepted.
  ///
  /// Throws [StateError] like [merge], and [ArgumentError] when [range] lies
  /// outside the sheet or has its first corner after its last; the earlier
  /// filter, if any, stays in force then.
  void autoFilter(XlsxRange range);

  /// Appends a row whose cells hold [values], from column A on.
  ///
  /// A value is `null` (no cell), a `String`, `int`, `double`, `bool`,
  /// [DateTime], [XlsxDate], [XlsxDecimal], [XlsxFormula], or an [XlsxCell]
  /// wrapping one of those with its own style. [style] applies to every cell
  /// of the row. The effective style of a cell is its column's style (see
  /// [columns]), with [style] merged over it and the cell's own style over
  /// that, field by field: a field a higher layer sets wins, one it leaves
  /// `null` is inherited.
  ///
  /// `XlsxCell(null, style: s)` with a non-null `s` writes an empty cell
  /// that carries the effective style, for example a border across a
  /// totals row; it writes nothing when the effective style is the
  /// default. A bare `null` and `XlsxCell(null)` write no cell, even under
  /// a row or column style.
  ///
  /// [height] is the row's height in points, `null` for the default.
  /// [hidden] hides the row. [outlineLevel] groups it, from 0 (not grouped)
  /// to [XlsxLimits.maxOutlineLevel]. [collapsed] marks the row that carries
  /// the expand button of a collapsed group next to it. A row in which no
  /// cell is written (only `null`s, or styled empties whose effective style
  /// is the default) writes nothing unless it has one of these attributes,
  /// but it still counts; a row whose only cells are styled empties is
  /// written.
  ///
  /// Data problems are repaired and reported as warnings. Throws
  /// [XlsxLimitError] for more than [XlsxLimits.maxColumns] values or a row
  /// past [XlsxLimits.maxRows], and [ArgumentError] for a [height] outside 0
  /// to [XlsxLimits.maxRowHeight] or an [outlineLevel] out of range, all
  /// before anything is written. It also throws
  /// `XlsxLimitError('cell formats', ...)` for a style that would make the
  /// workbook hold more than [XlsxLimits.maxCellFormats] cell formats; that
  /// one can happen in the middle of a row. Further, it throws [StateError]
  /// when the sheet is finished or the writer has failed, and
  /// [ArgumentError] for a value the writer cannot store or an invalid style
  /// (a built-in number format id outside `0..163`, or an empty custom
  /// format code or one with characters XML forbids). After an
  /// [ArgumentError] or a cell-format [XlsxLimitError] in the middle of a
  /// row, the cells before the failing one are kept, the row keeps its
  /// attributes and still counts.
  void row(
    List<Object?> values, {
    XlsxStyle? style,
    double? height,
    bool hidden = false,
    int outlineLevel = 0,
    bool collapsed = false,
  });

  /// Appends a row without cells, with the attributes [row] describes. A
  /// blank row without attributes writes nothing but counts. Throws like
  /// [row].
  void blankRow({
    double? height,
    bool hidden = false,
    int outlineLevel = 0,
    bool collapsed = false,
  });
}

/// The sheet writer of [XlsxWriterBase]: one worksheet part being written.
///
/// Rows are encoded into a body buffer as they arrive. The header, which
/// depends on settings and on the deepest row outline level, is rendered
/// when the sheet is finished and handed to the ZIP with the body's chunks
/// and the trailer, so the body is never joined into one array.
final class _SheetWriter implements XlsxSheetWriter {
  _SheetWriter(this._book, this.name, this._number, this.visibility) {
    final Utf8Buffer body = Utf8Buffer();
    _body = body;
    _xml = XmlWriter(body);
  }

  final XlsxWriterBase _book;

  /// The 1-based creation order: part name, `sheetId` and relationship id.
  final int _number;

  @override
  final String name;

  @override
  final XlsxSheetVisibility visibility;

  /// The rows so far and their writer; null once the sheet is finished.
  Utf8Buffer? _body;
  XmlWriter? _xml;
  int _rowCount = 0;

  /// Whether any `<row>` element was written.
  bool _wroteRow = false;

  /// The columns as set, their styles (the same objects on every row, so
  /// the encoder's per-column cache holds) and their header form.
  List<XlsxStyle?> _columnStyles = const <XlsxStyle?>[];
  List<WorksheetColumn?> _columns = const <WorksheetColumn?>[];
  double? _defaultRowHeight;
  double? _defaultColumnWidth;
  int _outlineLevelRow = 0;
  XlsxSheetView _view = const XlsxSheetView();
  XlsxColor? _tabColor;
  bool _summaryBelow = true;
  bool _summaryRight = true;
  final List<XlsxRange> _merges = <XlsxRange>[];
  XlsxRange? _autoFilter;

  @override
  int get rowCount => _rowCount;

  @override
  void columns(List<XlsxColumn?> columns) {
    _checkHeaderOpen('columns');
    if (columns.length > XlsxLimits.maxColumns) {
      throw XlsxLimitError('columns', XlsxLimits.maxColumns);
    }
    for (int i = 0; i < columns.length; i++) {
      final XlsxColumn? column = columns[i];
      if (column == null) continue;
      final double? width = column.width;
      if (width != null) checkColumnWidth(width, 'columns[$i].width');
      checkOutlineLevel(column.outlineLevel, 'columns[$i].outlineLevel');
    }
    final List<XlsxStyle?> styles = <XlsxStyle?>[
      for (final XlsxColumn? column in columns) column?.style,
    ];
    // Atomic: a style that throws leaves none of the others registered.
    final List<int> ids = _book._styles.idsFor(styles);
    _columnStyles = List<XlsxStyle?>.unmodifiable(styles);
    _columns = List<WorksheetColumn?>.unmodifiable(<WorksheetColumn?>[
      for (int i = 0; i < columns.length; i++)
        if (columns[i] case final XlsxColumn c)
          (
            width: c.width,
            style: ids[i],
            hidden: c.hidden,
            outlineLevel: c.outlineLevel,
            collapsed: c.collapsed,
          )
        else
          null,
    ]);
  }

  @override
  void defaultSizes({double? rowHeight, double? columnWidth}) {
    _checkHeaderOpen('defaultSizes');
    if (rowHeight != null) checkRowHeight(rowHeight, 'rowHeight');
    if (columnWidth != null) checkColumnWidth(columnWidth, 'columnWidth');
    _defaultRowHeight = rowHeight;
    _defaultColumnWidth = columnWidth;
  }

  @override
  void view(XlsxSheetView view) {
    _checkHeaderOpen('view');
    checkSheetView(view);
    _view = view;
  }

  @override
  void freeze({int rows = 0, int columns = 0}) {
    _checkHeaderOpen('freeze');
    final XlsxPane pane = XlsxPane.frozen(rows: rows, columns: columns);
    checkPane(pane);
    _view = _view.copyWith(pane: pane);
  }

  @override
  void split({double x = 0, double y = 0}) {
    _checkHeaderOpen('split');
    final XlsxPane pane = XlsxPane.split(x: x, y: y);
    checkPane(pane);
    _view = _view.copyWith(pane: pane);
  }

  @override
  void tabColor(XlsxColor color) {
    _checkHeaderOpen('tabColor');
    validateColor(color, 'color');
    _tabColor = color;
  }

  @override
  void outlineSummary({bool below = true, bool right = true}) {
    _checkHeaderOpen('outlineSummary');
    _summaryBelow = below;
    _summaryRight = right;
  }

  @override
  void merge(XlsxRange range) {
    _checkOpenSheet();
    validateRange(range, 'range');
    if (range.isSingleCell) {
      throw ArgumentError.value(
        range,
        'range',
        'A merged range must cover at least two cells.',
      );
    }
    for (final XlsxRange earlier in _merges) {
      if (earlier.overlaps(range)) {
        throw ArgumentError.value(
          range,
          'range',
          'The range ${range.ref} overlaps the merged range ${earlier.ref}.',
        );
      }
    }
    _merges.add(range);
  }

  @override
  void autoFilter(XlsxRange range) {
    _checkOpenSheet();
    validateRange(range, 'range');
    _autoFilter = range;
  }

  @override
  void row(
    List<Object?> values, {
    XlsxStyle? style,
    double? height,
    bool hidden = false,
    int outlineLevel = 0,
    bool collapsed = false,
  }) {
    final XmlWriter xml = _checkWritable();
    if (values.length > XlsxLimits.maxColumns) {
      throw XlsxLimitError('columns', XlsxLimits.maxColumns);
    }
    _checkRowAttributes(height, outlineLevel);
    final int row = _rowCount;
    _rowCount++;
    bool opened = false;
    if (height != null || hidden || outlineLevel != 0 || collapsed) {
      _startRow(xml, row, height, hidden, outlineLevel, collapsed);
      opened = true;
    }
    // Without attributes, the row is opened by its first written cell, so
    // cells that write nothing (an XlsxCell of null, a styled empty whose
    // style is the default, a cell that throws) leave no empty element.
    void open() {
      if (opened) return;
      _startRow(xml, row, null, false, 0, false);
      opened = true;
    }

    try {
      for (int column = 0; column < values.length; column++) {
        final Object? value = values[column];
        if (value == null) continue;
        _book._encoder.encode(
          xml,
          sheet: name,
          row: row,
          column: column,
          value: value,
          rowStyle: style,
          columnStyle: column < _columnStyles.length
              ? _columnStyles[column]
              : null,
          beforeWrite: open,
        );
      }
    } finally {
      if (opened) xml.end();
    }
  }

  @override
  void blankRow({
    double? height,
    bool hidden = false,
    int outlineLevel = 0,
    bool collapsed = false,
  }) {
    final XmlWriter xml = _checkWritable();
    _checkRowAttributes(height, outlineLevel);
    final int row = _rowCount;
    _rowCount++;
    if (height != null || hidden || outlineLevel != 0 || collapsed) {
      _startRow(xml, row, height, hidden, outlineLevel, collapsed);
      xml.end();
    }
  }

  static void _checkRowAttributes(double? height, int outlineLevel) {
    if (height != null) checkRowHeight(height, 'height');
    checkOutlineLevel(outlineLevel, 'outlineLevel');
  }

  /// Opens the `<row>` of zero-based [row] with its attributes, in `CT_Row`
  /// order, and records its outline level for `sheetFormatPr`.
  void _startRow(
    XmlWriter xml,
    int row,
    double? height,
    bool hidden,
    int outlineLevel,
    bool collapsed,
  ) {
    xml.start('row');
    xml.attribute('r', '${row + 1}');
    if (height != null) xml.attribute('ht', formatXmlDouble(height));
    if (hidden) xml.attribute('hidden', '1');
    if (height != null) xml.attribute('customHeight', '1');
    if (outlineLevel != 0) xml.attribute('outlineLevel', '$outlineLevel');
    if (collapsed) xml.attribute('collapsed', '1');
    if (outlineLevel > _outlineLevelRow) _outlineLevelRow = outlineLevel;
    _wroteRow = true;
  }

  /// Throws unless a header setting named [setting] may still be changed:
  /// the writer has not failed, the sheet is open and has no rows yet.
  void _checkHeaderOpen(String setting) {
    _checkOpenSheet();
    if (_rowCount > 0) {
      throw StateError(
        'Sheet "$name" already has rows; $setting must be set before the '
        'first row() or blankRow().',
      );
    }
  }

  /// The XML writer, after checking the writer has not failed and the sheet
  /// is open.
  XmlWriter _checkOpenSheet() {
    _book._checkNotFailed();
    final XmlWriter? xml = _xml;
    if (xml == null) {
      throw StateError(
        'Sheet "$name" is finished; rows and settings can only be added to '
        'the sheet added last, before close().',
      );
    }
    return xml;
  }

  /// The XML writer, after checking the writer has not failed and the sheet
  /// is open and has room for a row.
  XmlWriter _checkWritable() {
    final XmlWriter xml = _checkOpenSheet();
    if (_rowCount >= XlsxLimits.maxRows) {
      throw XlsxLimitError('rows', XlsxLimits.maxRows);
    }
    return xml;
  }

  /// Assembles the part, header, body chunks and trailer, and hands it to
  /// the ZIP, keeping no bytes. The body is never joined into one array.
  ///
  /// The sheet is detached first, so it is finished even when the ZIP
  /// throws and never takes a row after `</worksheet>`.
  void _finish() {
    final Utf8Buffer body = _body!;
    _xml = null;
    _body = null;
    final WorksheetSettings settings = WorksheetSettings(
      columns: _columns,
      defaultColumnWidth: _defaultColumnWidth,
      defaultRowHeight: _defaultRowHeight,
      outlineLevelRow: _outlineLevelRow,
      view: _view,
      tabColor: _tabColor,
      summaryBelow: _summaryBelow,
      summaryRight: _summaryRight,
      autoFilter: _autoFilter,
      merges: _merges,
    );
    _book._zip.addChunks(worksheetPartName(_number), <Uint8List>[
      utf8.encode(worksheetHeader(settings, hasRows: _wroteRow)),
      ...body.takeChunks(),
      utf8.encode(worksheetTrailer(settings, hasRows: _wroteRow)),
    ]);
  }
}
