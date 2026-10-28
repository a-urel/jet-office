/// The public XLSX reader: the sheet list and lazy rows of typed cells.
///
/// Not ported from Quds, whose `XlsxGridReader` read every sheet into a grid
/// of strings at once; written for jet_office on top of the ported package,
/// workbook, shared-string and row readers.
library;

import 'dart:typed_data';

import '../../opc/ooxml.dart';
import '../sheet_view.dart';
import '../warnings.dart';
import 'package_reader.dart';
import 'read_cell.dart';
import 'read_exception.dart';
import 'read_limits.dart';
import 'shared_strings_reader.dart';
import 'sheet_reader.dart';
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
/// workbook relationships and the workbook part, nothing else. A sheet's
/// part (and the shared strings, once per reader) is decompressed when its
/// [rows] are first iterated, and rows are parsed as they are taken, so
/// stopping early does no further work. Every call is synchronous.
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
  /// [XlsxReadException] when the file is not a readable XLSX workbook or
  /// lists more than [XlsxReadLimits.maxSheets] sheets. A
  /// sheet the workbook lists without a part is kept, reads as no rows and
  /// gets an [XlsxWarningCode.sheetPartMissing] warning.
  XlsxReader(Uint8List bytes, {XlsxReadLimits limits = const XlsxReadLimits()})
    : _limits = limits {
    limits.check();
    _package = PackageReader(bytes, limits);
    final WorkbookInfo workbook = readWorkbook(_package);
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
    for (int i = 0; i < sheets.length; i++) {
      if (_parts[i] == null) _warnMissing(sheets[i].name);
    }
  }

  final XlsxReadLimits _limits;
  late final PackageReader _package;
  late final List<String?> _parts;
  final WarningCollector _warnings = WarningCollector();
  bool _sharedStringsRead = false;
  List<String>? _sharedStrings;

  late final List<XlsxReadSheet> _sheets;

  /// The sheets of the workbook, in workbook order. Unmodifiable.
  List<XlsxReadSheet> get sheets => _sheets;

  /// What could not be read exactly, aggregated per sheet and
  /// [XlsxWarningCode].
  ///
  /// An unmodifiable live view: it grows as rows are read. Iterating a
  /// sheet's [rows] again replaces that sheet's warnings.
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
  /// first clearing the sheet's [warnings]. An [XlsxReadException] for the
  /// sheet or the shared strings is thrown out of the iteration.
  ///
  /// Throws a [RangeError] when [index] is not the index of a sheet.
  Iterable<XlsxReadRow> rowsAt(int index) {
    RangeError.checkValidIndex(index, sheets, 'index');
    return _rows(index);
  }

  Iterable<XlsxReadRow> _rows(int index) sync* {
    final String name = sheets[index].name;
    final String? part = _parts[index];
    _warnings.removeSheet(name);
    if (part == null) {
      _warnMissing(name);
      return;
    }
    yield* readSheetRows(
      _package,
      part,
      sheet: name,
      sharedStrings: _loadSharedStrings(),
      limits: _limits,
      warnings: _warnings,
    );
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

  void _warnMissing(String sheet) =>
      _warnings.add(XlsxWarningCode.sheetPartMissing, sheet: sheet);
}
