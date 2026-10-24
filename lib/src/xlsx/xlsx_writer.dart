/// The streaming XLSX writers: [XlsxWriter] (in memory) and
/// [XlsxStreamWriter] (to a sink).
///
/// Ported from quds_office_engine `lib/src/builders/xlsx_io.dart` at commit 15c5d29.
/// Ported: `XlsxWorkbookBuilder.addSheet` and `build`, and the row loop and
/// worksheet frame of `XlsxSheetBuilder` and `_sheetXml`. What changed: Quds
/// kept every sheet as a list of rows and serialized the whole workbook in
/// `build`; here rows are encoded as they arrive, one sheet is open at a
/// time, and a finished sheet goes straight to the ZIP, so memory is bounded
/// by one sheet's buffer. Tab order is independent of creation order, the
/// active tab is chosen by the caller, a workbook without sheets is an error
/// instead of silently gaining `Sheet1`, Excel's row and column limits are
/// enforced, and data problems are returned as warnings. Columns, merges,
/// panes, filters, charts and pictures are not ported in this phase.
library;

import 'dart:typed_data';

import '../opc/ooxml.dart';
import '../xml/utf8_buffer.dart';
import '../xml/xml_writer.dart';
import '../zip/archive_adapter.dart';
import 'cell_encoder.dart';
import 'limits.dart';
import 'properties.dart';
import 'shared_strings.dart';
import 'sheet_name.dart';
import 'style.dart';
import 'style_registry.dart';
import 'values.dart';
import 'warnings.dart';
import 'workbook_parts.dart';

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
  /// Throws [RangeError] when [position] is outside `0` to the number of
  /// sheets so far, and [StateError] after `close()` or after a failure.
  /// Rethrows what the sink throws while the open sheet is finished; the
  /// writer has then failed (see [XlsxStreamWriter]).
  XlsxSheetWriter addSheet(String name, {int? position}) {
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
    );
    _tabs.insert(position ?? _tabs.length, sheet);
    _open = sheet;
    return sheet;
  }

  /// Makes [sheet] the tab Excel shows when the file is opened.
  ///
  /// Without a call, the first tab in tab order is active. The tab index is
  /// resolved at `close()`, so later inserts before [sheet] keep it active.
  ///
  /// Throws [ArgumentError] when [sheet] was not added to this writer, and
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
    return _zipWork(() {
      _open?._finish();
      _open = null;
      final Uint8List? bytes = _writeWorkbookParts();
      _closed = true;
      return bytes;
    });
  }

  /// Writes the workbook-level parts and finishes the ZIP.
  Uint8List? _writeWorkbookParts() {
    final int sheetCount = _tabs.length;
    final _SheetWriter active = _active ?? _tabs.first;
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
                (name: s.name, number: s._number),
            ],
            activeTab: _tabs.indexOf(active),
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
  /// when the data was written exactly as given. Unmodifiable.
  final List<XlsxWarning> warnings;
}

/// Writes the rows of one worksheet.
///
/// Obtained from [XlsxWriterBase.addSheet]. A sheet accepts rows until the
/// next `addSheet` or `close()` finishes it.
abstract interface class XlsxSheetWriter {
  /// The sheet's name in the file, after any renaming (see
  /// [XlsxWriterBase.addSheet]).
  String get name;

  /// The number of rows written so far, blank rows included. The next row
  /// is row `rowCount + 1` in Excel.
  int get rowCount;

  /// Appends a row whose cells hold [values], from column A on.
  ///
  /// A value is `null` (no cell), a `String`, `int`, `double`, `bool`,
  /// [DateTime], [XlsxDate], [XlsxDecimal], [XlsxFormula], or an [XlsxCell]
  /// wrapping one of those with its own style. [style] applies to every cell
  /// that has no style of its own. A row of only `null`s writes nothing but
  /// still counts.
  ///
  /// Data problems are repaired and reported as warnings. Throws
  /// [XlsxLimitError] for more than [XlsxLimits.maxColumns] values or a row
  /// past [XlsxLimits.maxRows], [StateError] when the sheet is finished, and
  /// [ArgumentError] for a value the writer cannot store; in that last case
  /// the cells before it are kept and the row still counts.
  void row(List<Object?> values, {XlsxStyle? style});

  /// Appends an empty row. Throws like [row].
  void blankRow();
}

/// The sheet writer of [XlsxWriterBase]: one worksheet part being written.
final class _SheetWriter implements XlsxSheetWriter {
  _SheetWriter(this._book, this.name, this._number) {
    final XmlWriter xml = XmlWriter(_buffer!);
    _xml = xml;
    xml.declaration();
    xml.start('worksheet');
    xml.attribute('xmlns', Ns.main);
    xml.attribute('xmlns:r', Ns.rel);
    xml.raw('<sheetViews><sheetView workbookViewId="0"/></sheetViews>');
    xml.start('sheetData');
  }

  final XlsxWriterBase _book;

  /// The 1-based creation order: part name, `sheetId` and relationship id.
  final int _number;

  @override
  final String name;

  /// The sheet's XML so far; null once the sheet is finished.
  Utf8Buffer? _buffer = Utf8Buffer();
  XmlWriter? _xml;
  int _rowCount = 0;

  @override
  int get rowCount => _rowCount;

  @override
  void row(List<Object?> values, {XlsxStyle? style}) {
    final XmlWriter xml = _checkWritable();
    if (values.length > XlsxLimits.maxColumns) {
      throw XlsxLimitError('columns', XlsxLimits.maxColumns);
    }
    final int row = _rowCount;
    _rowCount++;
    bool opened = false;
    try {
      for (int column = 0; column < values.length; column++) {
        final Object? value = values[column];
        if (value == null || (value is XlsxCell && value.value == null)) {
          continue;
        }
        if (!opened) {
          xml.start('row');
          xml.attribute('r', '${row + 1}');
          opened = true;
        }
        _book._encoder.encode(
          xml,
          sheet: name,
          row: row,
          column: column,
          value: value,
          rowStyle: style,
        );
      }
    } finally {
      if (opened) xml.end();
    }
  }

  @override
  void blankRow() {
    _checkWritable();
    _rowCount++;
  }

  /// The XML writer, after checking the writer has not failed and the sheet
  /// is open and has room for a row.
  XmlWriter _checkWritable() {
    _book._checkNotFailed();
    final XmlWriter? xml = _xml;
    if (xml == null) {
      throw StateError(
        'Sheet "$name" is finished; rows can only be added to the sheet '
        'added last, before close().',
      );
    }
    if (_rowCount >= XlsxLimits.maxRows) {
      throw XlsxLimitError('rows', XlsxLimits.maxRows);
    }
    return xml;
  }

  /// Closes the XML and hands the part to the ZIP, keeping no bytes.
  ///
  /// The sheet is detached first, so it is finished even when the ZIP
  /// throws and never takes a row after `</worksheet>`.
  void _finish() {
    final XmlWriter xml = _xml!;
    final Utf8Buffer buffer = _buffer!;
    _xml = null;
    _buffer = null;
    xml
      ..end() // sheetData
      ..end(); // worksheet
    _book._zip.add(worksheetPartName(_number), buffer.takeBytes());
  }
}
