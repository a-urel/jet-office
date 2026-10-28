/// The public XLSX reader: the sheet list and lazy rows of typed cells.
///
/// Not ported from Quds, whose `XlsxGridReader` read every sheet into a grid
/// of strings at once; written for jet_office on top of the ported package,
/// workbook, shared-string and row readers.
library;

import 'dart:typed_data';

import '../../opc/ooxml.dart';
import '../range.dart';
import '../sheet_view.dart';
import '../warnings.dart';
import 'merge_reader.dart';
import 'package_reader.dart';
import 'read_cell.dart';
import 'read_exception.dart';
import 'read_limits.dart';
import 'shared_strings_reader.dart';
import 'sheet_reader.dart';
import 'styles_reader.dart';
import 'workbook_reader.dart';

/// One sheet of a workbook opened by [XlsxReader].
final class XlsxReadSheet {
  /// A sheet called [name] at the 0-based [index], shown as [visibility].
  const XlsxReadSheet(this.name, this.index, this.visibility);

  /// The sheet name as written in the file.
  final String name;

  /// The 0-based position of the sheet in the workbook.
  final int index;

  /// Whether the sheet is visible, hidden or very hidden.
  final XlsxSheetVisibility visibility;

  @override
  String toString() => 'XlsxReadSheet($index, $name, ${visibility.name})';
}

/// Reads an XLSX file from bytes, one sheet at a time, row by row.
///
/// The file is treated as untrusted: a file that cannot be read at all
/// throws an [XlsxReadException], kept within [XlsxReadLimits]; a cell or
/// sheet that cannot be read exactly is reported in [warnings] and never
/// dropped silently.
///
/// Opening reads the ZIP directory, `[Content_Types].xml`, the root and
/// workbook relationships, the workbook part and the styles part, nothing
/// else. A sheet's part (and the shared strings, once per reader) is
/// decompressed when its [rows] are first iterated, and rows are parsed as
/// they are taken, so stopping early does no further work. A sheet's
/// merged ranges are read by a separate pass over its part, on the first
/// call to [merges], and kept. Every call is synchronous.
///
/// ```dart
/// final XlsxReader reader = XlsxReader(bytes);
/// for (final XlsxReadRow row in reader.rowsAt(0)) {
///   print(row.cells.map((XlsxReadCell c) => c.value));
/// }
/// ```
final class XlsxReader {
  /// Opens the XLSX file [bytes] within [limits].
  ///
  /// Throws an [ArgumentError] when a limit is below 1 and an
  /// [XlsxReadException] when the file is not a readable XLSX workbook,
  /// lists more than [XlsxReadLimits.maxSheets] sheets or has a styles part
  /// that cannot be read. A workbook without a styles part reads every cell
  /// as `General`. A sheet the workbook lists without a part is kept, reads
  /// as no rows and gets an [XlsxWarningCode.sheetPartMissing] warning.
  XlsxReader(Uint8List bytes, {XlsxReadLimits limits = const XlsxReadLimits()})
    : _limits = limits {
    limits.check();
    _package = PackageReader(bytes, limits);
    final WorkbookInfo workbook = readWorkbook(_package);
    _date1904 = workbook.date1904;
    _styles = _readStyles();
    _parts = <String?>[
      for (final WorkbookSheet sheet in workbook.sheets) sheet.part,
    ];
    _sheets = List<XlsxReadSheet>.unmodifiable(<XlsxReadSheet>[
      for (int i = 0; i < workbook.sheets.length; i++)
        XlsxReadSheet(
          workbook.sheets[i].name,
          i,
          workbook.sheets[i].visibility,
        ),
    ]);
    _generations = List<int>.filled(_sheets.length, 0);
    _merges = List<List<XlsxRange>?>.filled(_sheets.length, null);
    for (int i = 0; i < sheets.length; i++) {
      if (_parts[i] == null) _warnMissing(i);
    }
  }

  final XlsxReadLimits _limits;
  late final PackageReader _package;
  late final List<String?> _parts;
  final WarningCollector _warnings = WarningCollector();
  bool _sharedStringsRead = false;
  List<String>? _sharedStrings;
  late final StyleTable _styles;
  late final bool _date1904;

  /// Per sheet, the number of the latest pass over its rows; a pass adds
  /// warnings only while its number is the latest.
  late final List<int> _generations;

  /// Per sheet, the merged ranges once read; `null` before.
  late final List<List<XlsxRange>?> _merges;

  late final List<XlsxReadSheet> _sheets;

  /// Whether the workbook counts dates from 1904 (`date1904` of its
  /// `<workbookPr>`), as files from old Mac versions of Excel do; otherwise
  /// from 1900.
  ///
  /// The reader applies it: a date cell's `DateTime` is already the date
  /// the file means. It matters only to a caller that turns a raw serial,
  /// such as a number in a `General` cell, into a date itself.
  bool get date1904 => _date1904;

  /// The sheets of the workbook, in workbook order. Unmodifiable.
  List<XlsxReadSheet> get sheets => _sheets;

  /// What could not be read exactly, aggregated per sheet and
  /// [XlsxWarningCode].
  ///
  /// An unmodifiable live view: it grows as rows are read. Iterating a
  /// sheet's [rows] again replaces that sheet's warnings, and an older
  /// iteration of the same sheet adds none after the newer one starts.
  /// Sheets that share a name, which a damaged file may hold, keep separate
  /// warnings.
  List<XlsxWarning> get warnings => _warnings.warnings;

  /// The rows of the first sheet called [sheetName]; see [rowsAt].
  ///
  /// Throws an [ArgumentError] when no sheet has that name.
  Iterable<XlsxReadRow> rows(String sheetName) {
    for (final XlsxReadSheet sheet in sheets) {
      if (sheet.name == sheetName) return rowsAt(sheet.index);
    }
    throw ArgumentError.value(sheetName, 'sheetName', 'No such sheet.');
  }

  /// The rows of the sheet at the 0-based [index], in file order.
  ///
  /// A row is yielded when it holds a cell with data or is hidden. The sheet
  /// is read lazily: each iteration starts again from the top of the part,
  /// first clearing the sheet's [warnings] (those of [merges] stay); from
  /// then on an earlier iteration of the sheet still yields its rows but
  /// reports nothing. An [XlsxReadException] for the sheet or the shared
  /// strings is thrown out of the iteration.
  ///
  /// Throws a [RangeError] when [index] is not the index of a sheet.
  Iterable<XlsxReadRow> rowsAt(int index) {
    RangeError.checkValidIndex(index, sheets, 'index');
    return _rows(index);
  }

  Iterable<XlsxReadRow> _rows(int index) sync* {
    final int generation = ++_generations[index];
    final String name = sheets[index].name;
    final String? part = _parts[index];
    _warnings.removeSheet(
      index,
      keep: const <XlsxWarningCode>{XlsxWarningCode.mergeRangeInvalid},
    );
    if (part == null) {
      _warnMissing(index);
      return;
    }
    void warn(XlsxWarningCode code, String? cell, {String? detail}) {
      if (_generations[index] != generation) return;
      _warnings.add(code, sheet: name, cell: cell, detail: detail, key: index);
    }

    yield* readSheetRows(
      _package,
      part,
      sharedStrings: _loadSharedStrings(),
      styles: _styles,
      date1904: _date1904,
      limits: _limits,
      warn: warn,
    );
  }

  /// The merged ranges of the first sheet called [sheetName]; see
  /// [mergesAt].
  ///
  /// Throws an [ArgumentError] when no sheet has that name.
  List<XlsxRange> merges(String sheetName) {
    for (final XlsxReadSheet sheet in sheets) {
      if (sheet.name == sheetName) return mergesAt(sheet.index);
    }
    throw ArgumentError.value(sheetName, 'sheetName', 'No such sheet.');
  }

  /// The merged ranges of the sheet at the 0-based [index], in file order.
  ///
  /// Unmodifiable. Read from the sheet's part on the first call, by a pass
  /// of its own that skips the cells, and kept: later calls return the same
  /// list. A merge whose reference cannot be read is left out and reported
  /// once as [XlsxWarningCode.mergeRangeInvalid] in [warnings]; reading
  /// [rows] does not clear it. A sheet without a part has none.
  ///
  /// Throws a [RangeError] when [index] is not the index of a sheet, and an
  /// [XlsxReadException] when the part is Strict OOXML or not well-formed
  /// XML; nothing is kept then, so a later call tries again.
  List<XlsxRange> mergesAt(int index) {
    RangeError.checkValidIndex(index, sheets, 'index');
    final List<XlsxRange>? cached = _merges[index];
    if (cached != null) return cached;
    final String? part = _parts[index];
    if (part == null) return _merges[index] = const <XlsxRange>[];
    final String name = sheets[index].name;
    void warn(XlsxWarningCode code, String? cell, {String? detail}) => _warnings
        .add(code, sheet: name, cell: cell, detail: detail, key: index);
    return _merges[index] = List<XlsxRange>.unmodifiable(
      readMerges(_package, part, warn: warn),
    );
  }

  /// The cell formats of the workbook's styles part; [StyleTable.empty]
  /// when it has no styles relationship or its part is missing.
  StyleTable _readStyles() {
    for (final PartRelationship rel in _package.relationshipsOf(
      _package.workbookPart,
    )) {
      if (rel.type == RelType.styles && _package.hasPart(rel.target)) {
        return readStyles(_package, rel.target, _limits);
      }
    }
    return StyleTable.empty;
  }

  /// The shared strings, read on first use; `null` when the workbook has no
  /// shared-strings relationship or its part is missing.
  List<String>? _loadSharedStrings() {
    if (_sharedStringsRead) return _sharedStrings;
    for (final PartRelationship rel in _package.relationshipsOf(
      _package.workbookPart,
    )) {
      if (rel.type == RelType.sharedStrings && _package.hasPart(rel.target)) {
        _sharedStrings = readSharedStrings(_package, rel.target, _limits);
        break;
      }
    }
    _sharedStringsRead = true;
    return _sharedStrings;
  }

  void _warnMissing(int index) => _warnings.add(
    XlsxWarningCode.sheetPartMissing,
    sheet: sheets[index].name,
    key: index,
  );
}
