/// [XlsxSheetWriter], the public face of one worksheet being written, and
/// [WorksheetWriter], its implementation.
///
/// Ported from quds_office_engine `lib/src/builders/xlsx_io.dart` at commit 15c5d29.
/// Ported: the row loop, `colWidth` and row heights of `XlsxSheetBuilder`
/// and `_sheetXml`. What changed: Quds kept every sheet as a list of rows
/// and serialized the whole workbook in `XlsxWorkbookBuilder.build`; here
/// rows are encoded as they arrive and a finished sheet goes straight to the
/// ZIP: its header (`worksheet_parts.dart`) is rendered and handed over with
/// the row chunks and the trailer, which `ZipWriter.addChunks` copies once
/// into one buffer for the encoder. Memory is bounded by one sheet's body,
/// held twice while it is handed over. Header settings (columns, default
/// sizes) are frozen at the first row; rows carry a height, visibility and
/// outline level. Excel's row and column limits are enforced, and data
/// problems are returned as warnings. A sheet has a view (zoom, gridlines,
/// frozen or split panes), a tab color, an outline summary position and a
/// visibility. Merged ranges and the auto filter are trailer settings,
/// checked when set: Quds accepted overlapping merges and any filter text.
/// Data validations are trailer settings too, checked when added, and so
/// are conditional formats, whose styles become differential styles and
/// whose rules take the sheet's next priorities.
/// A hyperlink is a cell value: the row checks it before its cell is
/// encoded, and the finished sheet writes its `hyperlinks` and, for the
/// external ones, a relationships part with one relationship per address.
/// The sheet reaches the workbook's encoder, styles and ZIP through a
/// [WorkbookContext].
library;

import 'dart:convert';
import 'dart:typed_data';

import '../xml/utf8_buffer.dart';
import '../xml/xml_number.dart';
import '../xml/xml_writer.dart';
import 'cell_encoder.dart';
import 'cell_ref.dart';
import 'color.dart';
import 'column.dart';
import 'conditional_format.dart';
import 'data_validation.dart';
import 'defined_name.dart';
import 'header_footer.dart';
import 'hyperlink.dart';
import 'limits.dart';
import 'page_setup.dart';
import 'range.dart';
import 'sheet_protection.dart';
import 'sheet_view.dart';
import 'style.dart';
import 'values.dart';
import 'workbook_context.dart';
import 'workbook_parts.dart';
import 'worksheet_parts.dart';
import 'xlsx_writer.dart';

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
  /// written as one range. A second call before the first row replaces the
  /// columns, but the first call's styles stay in `styles.xml` as unused
  /// cell formats, because styles are registered when the columns are set.
  ///
  /// Throws [StateError] after the first [row] or [blankRow], when the sheet
  /// is finished or the writer has failed; [XlsxLimitError] for more than
  /// [XlsxLimits.maxColumns] entries; [ArgumentError] for a width outside 0
  /// to [XlsxLimits.maxColumnWidth], an outline level outside 0 to
  /// [XlsxLimits.maxOutlineLevel], or an invalid style (as [row] describes;
  /// named `columns[i].style`, with the value and message of the style field
  /// at fault); and `XlsxLimitError('cell formats', ...)` like [row]. When
  /// it throws, nothing is recorded: the earlier columns, if any, stay in
  /// force and no style is registered.
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
  /// that is negative, NaN or infinite, or whose twips (`offset * 20`,
  /// rounded) exceed 2^31 - 1, that is above 107,374,182.35 points; nothing
  /// is recorded then.
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

  /// Defines [name] for this sheet only: it hides a workbook name of the
  /// same spelling on this sheet.
  ///
  /// A trailer setting like [merge]. Names are written in the order made;
  /// use `XlsxWriterBase.defineName` for a workbook-wide name. Reference
  /// this sheet in the formula as Excel does, quoting its name when it needs
  /// it.
  ///
  /// Throws [StateError] like [merge], and [ArgumentError] for an invalid
  /// name, comment or formula (see [XlsxDefinedName]) or a name this sheet
  /// already has, ignoring case; the earlier names stay then.
  void defineName(XlsxDefinedName name);

  /// Sets the cells printed, replacing an earlier call: each of [ranges]
  /// becomes one area of the print, on its own page.
  ///
  /// A trailer setting like [merge]. The workbook gets the `_xlnm.Print_Area`
  /// name of the sheet, with absolute references to this sheet's final name,
  /// quoted.
  ///
  /// Throws [StateError] like [merge], and [ArgumentError] when [ranges] is
  /// empty or a range lies outside the sheet or has its first corner after
  /// its last; the earlier print area stays then.
  void printArea(List<XlsxRange> ranges);

  /// Repeats rows and columns on every printed page, replacing an earlier
  /// call; a call with neither argument removes the titles.
  ///
  /// [rows] and [columns] are zero-based (first, last) pairs, both
  /// inclusive: `rows: (0, 0)` repeats the first row, `columns: (0, 1)` the
  /// columns A and B. A trailer setting like [merge].
  ///
  /// Throws [StateError] like [merge], and [ArgumentError] naming `rows` or
  /// `columns` for a span outside 0 to 1,048,575 rows or 0 to 16,383
  /// columns, or whose first is after its last; the earlier titles stay
  /// then.
  void printTitles({(int, int)? rows, (int, int)? columns});

  /// Adds [validation], a rule on what the cells of its ranges may hold.
  ///
  /// A trailer setting like [merge]. Validations are written in the order
  /// added.
  ///
  /// Throws [StateError] like [merge], and [ArgumentError] naming the field
  /// when [validation] is invalid (see [XlsxDataValidation]) or any of its
  /// ranges overlaps a range of an earlier validation or of itself (the
  /// message names both). When it throws, nothing is recorded.
  void dataValidation(XlsxDataValidation validation);

  /// Adds [format], rules that format the cells of its ranges when their
  /// conditions hold.
  ///
  /// A trailer setting like [merge]. Each rule gets the sheet's next
  /// priority, from 1 on, across every call: the rules of an earlier call
  /// take precedence over those of a later one. The rules' styles are
  /// registered as differential styles; equal styles share one. Formats are
  /// written in the order added, and their ranges may overlap. Data bars and
  /// the icon sets only Excel 2010 has ([XlsxIconSetType.isX14Only]) are
  /// written as Excel 2010 rules too; such an icon set takes a priority like
  /// any other rule.
  ///
  /// Throws [StateError] like [merge], and [ArgumentError] naming the field
  /// (`ranges[i]`, `rules[i].<field>`, `rules[i].style.<field>`) when
  /// [format] is invalid (see [XlsxConditionalFormat] and its rules); and
  /// `XlsxLimitError('number formats', ...)` when a style's number format
  /// does not fit. When it throws, nothing is recorded: no rule, priority
  /// or differential style.
  void conditionalFormat(XlsxConditionalFormat format);

  /// Sets how the sheet prints, replacing an earlier call: paper,
  /// orientation, scale or fit-to pages, margins, centering, gridlines and
  /// headings.
  ///
  /// A trailer setting like [merge]. A page setup always writes the page
  /// margins, Excel's "Normal" ones unless [setup] gives others; a setup that
  /// fits the sheet to pages also marks the sheet as such in its properties.
  ///
  /// Throws [StateError] like [merge], and [ArgumentError] naming the field
  /// (`scale`, `fitToWidth`, `fitToHeight`, `firstPageNumber`, `paperSize`,
  /// `margins.left`, ...) when [setup] is invalid (see [XlsxPageSetup]); the
  /// earlier setup stays then.
  void pageSetup(XlsxPageSetup setup);

  /// Sets the text printed in the top and bottom margins of the sheet,
  /// replacing an earlier call.
  ///
  /// A trailer setting like [merge]. An [XlsxHeaderFooter] with no text and
  /// no flag off its default writes nothing.
  ///
  /// Throws [StateError] like [merge], and [ArgumentError] naming the field
  /// (`oddHeader`, `oddFooter`, `evenHeader`, `evenFooter`, `firstHeader` or
  /// `firstFooter`) when a text is longer than 255 characters, holds a
  /// character XML forbids or ends in a lone `&` (see [XlsxHeaderFooter]);
  /// the earlier setting stays then.
  void headerFooter(XlsxHeaderFooter headerFooter);

  /// Protects the sheet, replacing an earlier call: [protection] says what
  /// users may still do and gives the password that lifts it.
  ///
  /// A trailer setting like [merge]. Protection locks the cells whose style
  /// does not set `XlsxProtection(locked: false)`. It is not security: the
  /// password hash is weak and nothing is encrypted.
  ///
  /// Throws [StateError] like [merge], and [ArgumentError] naming `password`
  /// when it is not 1 to 15 characters from U+0020 to U+007E; the earlier
  /// protection stays then.
  void protect(XlsxSheetProtection protection);

  /// Appends a row whose cells hold [values], from column A on.
  ///
  /// A value is `null` (no cell), a `String`, `int`, `double`, `bool`,
  /// [DateTime], [XlsxDate], [XlsxDecimal], [XlsxFormula], [XlsxHyperlink],
  /// or an [XlsxCell] wrapping one of those with its own style. [style]
  /// applies to every cell of the row. The effective style of a cell is its
  /// column's style (see [columns]), with [style] merged over it and the
  /// cell's own style over that, field by field: a field a higher layer
  /// sets wins, one it leaves `null` is inherited. Pass the same style
  /// object on every row that shares a style, a `const` or one built once
  /// before the loop: the encoder caches the merged style per column by the
  /// identity of its layers, and a style built afresh for each row misses
  /// that cache.
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
  /// [ArgumentError] for a value the writer cannot store, an invalid
  /// [XlsxHyperlink] (see there) or an invalid style (a built-in number
  /// format id outside `0..163`, or an empty custom format code or one with
  /// characters XML forbids), and `XlsxLimitError('hyperlinks', ...)` for a
  /// sheet's 65,531st link. After an [ArgumentError], a cell-format
  /// [XlsxLimitError] or a hyperlinks [XlsxLimitError] in the middle of a
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
/// and the trailer. The body is never built as one string; its chunks are
/// copied exactly once, by `ZipWriter.addChunks`, into the entry's buffer.
final class WorksheetWriter implements XlsxSheetWriter {
  /// Creates sheet [number] of the workbook that owns [context], named
  /// [name] (already made valid and unique) and shown as [visibility].
  WorksheetWriter(this.context, this.name, this.number, this.visibility) {
    final Utf8Buffer body = Utf8Buffer();
    _body = body;
    _xml = XmlWriter(body);
  }

  /// The workbook-level state this sheet shares with the writer that added
  /// it.
  final WorkbookContext context;

  /// The 1-based creation order: part name, `sheetId` and relationship id.
  final int number;

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
  List<XlsxRange> _printArea = const <XlsxRange>[];
  (int, int)? _printTitleRows;
  (int, int)? _printTitleColumns;
  final List<XlsxDefinedName> _names = <XlsxDefinedName>[];
  final List<XlsxDataValidation> _validations = <XlsxDataValidation>[];
  final List<WorksheetConditionalFormat> _conditionalFormats =
      <WorksheetConditionalFormat>[];

  XlsxPageSetup? _pageSetup;
  XlsxHeaderFooter? _headerFooter;
  XlsxSheetProtection? _protection;

  /// The priority the next conditional-format rule gets.
  int _nextPriority = 1;

  /// The hyperlinks written so far, with the reference of their cell.
  final List<(String, XlsxHyperlink)> _links = <(String, XlsxHyperlink)>[];

  /// The range of the auto filter, if [autoFilter] set one.
  XlsxRange? get autoFilterRange => _autoFilter;

  /// Whether the sheet still holds what its part is rendered from beyond
  /// what `close()` needs: links, merges, validations, conditional formats,
  /// columns, view and page settings. False once [finish] has run; tests
  /// use it to confirm a finished sheet lets that data go.
  bool get holdsTrailerData =>
      _links.isNotEmpty ||
      _merges.isNotEmpty ||
      _validations.isNotEmpty ||
      _conditionalFormats.isNotEmpty ||
      _columns.isNotEmpty ||
      _columnStyles.isNotEmpty ||
      _pageSetup != null ||
      _headerFooter != null ||
      _protection != null ||
      _tabColor != null ||
      _view != const XlsxSheetView();

  /// The defined names of this sheet that `workbook.xml` lists: its print
  /// area and titles and the names registered with [defineName].
  SheetNames get sheetNames => SheetNames(
    printArea: _printArea,
    printTitleRows: _printTitleRows,
    printTitleColumns: _printTitleColumns,
    defined: List<XlsxDefinedName>.unmodifiable(_names),
  );

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
    final List<int> ids = context.styles.idsFor(
      styles,
      fieldName: (int i) => 'columns[$i].style',
    );
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
  void defineName(XlsxDefinedName name) {
    _checkOpenSheet();
    _names.add(checkDefinedName(name, _names));
  }

  @override
  void dataValidation(XlsxDataValidation validation) {
    _checkOpenSheet();
    checkDataValidation(validation, _validations);
    _validations.add(validation);
  }

  @override
  void conditionalFormat(XlsxConditionalFormat format) {
    _checkOpenSheet();
    checkConditionalFormat(format);
    // Only after every rule is checked: dxfIdsFor is all or nothing, so a
    // throw here leaves no differential style behind either.
    final List<XlsxStyle?> styles = <XlsxStyle?>[
      for (final XlsxConditionalRule rule in format.rules)
        conditionalRuleStyle(rule),
    ];
    final Iterator<int> ids = context.styles
        .dxfIdsFor(
          styles.nonNulls.toList(),
          fields: <String>[
            for (int i = 0; i < styles.length; i++)
              if (styles[i] != null) 'rules[$i].style',
          ],
        )
        .iterator;
    final List<int?> dxfIds = <int?>[
      for (final XlsxStyle? style in styles)
        if (style == null) null else (ids..moveNext()).current,
    ];
    _conditionalFormats.add((
      format: format,
      dxfIds: List<int?>.unmodifiable(dxfIds),
      firstPriority: _nextPriority,
    ));
    _nextPriority += format.rules.length;
  }

  @override
  void pageSetup(XlsxPageSetup setup) {
    _checkOpenSheet();
    checkPageSetup(setup);
    _pageSetup = setup;
  }

  @override
  void headerFooter(XlsxHeaderFooter headerFooter) {
    _checkOpenSheet();
    checkHeaderFooter(headerFooter);
    _headerFooter = headerFooter;
  }

  @override
  void protect(XlsxSheetProtection protection) {
    _checkOpenSheet();
    checkProtectionPassword(protection.password);
    _protection = protection;
  }

  @override
  void printArea(List<XlsxRange> ranges) {
    _checkOpenSheet();
    if (ranges.isEmpty) {
      throw ArgumentError.value(
        ranges,
        'ranges',
        'A print area needs at least one range.',
      );
    }
    for (int i = 0; i < ranges.length; i++) {
      validateRange(ranges[i], 'ranges[$i]');
    }
    _printArea = List<XlsxRange>.unmodifiable(ranges);
  }

  @override
  void printTitles({(int, int)? rows, (int, int)? columns}) {
    _checkOpenSheet();
    if (rows != null) _checkSpan(rows, 'rows', XlsxLimits.maxRows);
    if (columns != null) _checkSpan(columns, 'columns', XlsxLimits.maxColumns);
    _printTitleRows = rows;
    _printTitleColumns = columns;
  }

  static void _checkSpan((int, int) span, String field, int count) {
    final (int first, int last) = span;
    if (first < 0 || last >= count) {
      throw ArgumentError.value(
        span,
        field,
        'The span lies outside the sheet: 0 to ${count - 1} are allowed.',
      );
    }
    if (first > last) {
      throw ArgumentError.value(
        span,
        field,
        'The first of the span must not be after its last.',
      );
    }
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
        final XlsxHyperlink? link = _linkOf(value);
        // Before the cell: a bad link, or the one past the limit, leaves
        // nothing of its cell behind.
        if (link != null) _checkLink(link);
        context.encoder.encode(
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
        if (link != null) _links.add((cellRef(row, column), link));
      }
    } finally {
      if (opened) xml.end();
    }
  }

  /// The hyperlink [value] is or wraps, or `null`.
  static XlsxHyperlink? _linkOf(Object value) {
    final Object? inner = value is XlsxCell ? value.value : value;
    return inner is XlsxHyperlink ? inner : null;
  }

  /// Throws unless [link] is valid and the sheet has room for one more.
  void _checkLink(XlsxHyperlink link) {
    checkHyperlink(link);
    if (_links.length >= XlsxLimits.maxHyperlinksPerSheet) {
      throw XlsxLimitError('hyperlinks', XlsxLimits.maxHyperlinksPerSheet);
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
    context.checkNotFailed();
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
  /// the ZIP, keeping no bytes. `ZipWriter.addChunks` copies the chunks
  /// once into one buffer for the encoder; nothing here joins them.
  ///
  /// The sheet is detached first, so it is finished even when the ZIP
  /// throws and never takes a row after `</worksheet>`. Then, even on a
  /// throw, it drops what the part was rendered from and keeps only what
  /// `close()` needs: the name, number and visibility, the filter range and
  /// the defined names (sheet names, print area and titles).
  void finish() {
    final Utf8Buffer body = _body!;
    _xml = null;
    _body = null;
    try {
      _writePart(body);
    } finally {
      _dropTrailerData();
    }
  }

  /// Empties everything [holdsTrailerData] reports, so a finished sheet no
  /// longer keeps its links (up to 65,530) and its other trailer data.
  void _dropTrailerData() {
    _links.clear();
    _merges.clear();
    _validations.clear();
    _conditionalFormats.clear();
    _columns = const <WorksheetColumn?>[];
    _columnStyles = const <XlsxStyle?>[];
    _pageSetup = null;
    _headerFooter = null;
    _protection = null;
    _tabColor = null;
    _view = const XlsxSheetView();
  }

  /// Renders the header, the trailer and the relationships part from the
  /// settings and hands them with [body]'s chunks to the ZIP.
  void _writePart(Utf8Buffer body) {
    // One relationship per distinct address, numbered in first-use order:
    // the one place ids are assigned. The links and the relationships part
    // both take them from this map.
    final Map<String, String> ids = <String, String>{};
    final List<WorksheetHyperlink> links = <WorksheetHyperlink>[];
    for (final (String ref, XlsxHyperlink link) in _links) {
      final String? address = link.address;
      links.add((
        ref: ref,
        relationshipId: address == null
            ? null
            : ids.putIfAbsent(address, () => 'rId${ids.length + 1}'),
        location: link.location,
        tooltip: link.tooltip,
        display: CellEncoder.truncateCellText(link.text),
      ));
    }
    final WorksheetSettings settings = WorksheetSettings(
      sheetNumber: number,
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
      conditionalFormats: _conditionalFormats,
      dataValidations: _validations,
      hyperlinks: links,
      pageSetup: _pageSetup,
      headerFooter: _headerFooter,
      protection: _protection,
    );
    context.zip.addChunks(worksheetPartName(number), <Uint8List>[
      utf8.encode(worksheetHeader(settings, hasRows: _wroteRow)),
      ...body.takeChunks(),
      utf8.encode(worksheetTrailer(settings, hasRows: _wroteRow)),
    ]);
    final String? rels = worksheetRelationshipsXml(ids);
    if (rels != null) {
      context.zip.addChunks(worksheetRelsPartName(number), <Uint8List>[
        utf8.encode(rels),
      ]);
    }
  }
}
