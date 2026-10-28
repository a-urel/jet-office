/// Test helper: XLSX packages in the style of producers other than Excel and
/// `XlsxWriter`, each with the values the reader must return for it.
///
/// [producerFiles] lists them and [expectProducerFile] reads one and compares
/// everything: the date system, the sheets, every cell's value, hidden rows,
/// merges and the warnings.
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

/// A package written in the style of one producer, and what the reader must
/// return for it.
final class ProducerFile {
  /// The package [bytes] of producer [name], whose [sheets] are expected in
  /// workbook order, with [warnings] in total per code and the date system
  /// [date1904].
  const ProducerFile(
    this.name,
    this.bytes,
    this.sheets, {
    this.warnings = const <XlsxWarningCode, int>{},
    this.date1904 = false,
  });

  /// The producer, such as `libreoffice` or `google_sheets`; also the test
  /// name.
  final String name;

  /// The XLSX package.
  final Uint8List bytes;

  /// The expected sheets, in workbook order.
  final List<ProducerSheet> sheets;

  /// The expected warnings: for each code, the sum of [XlsxWarning.count]
  /// over all sheets. A code not listed must not occur.
  final Map<XlsxWarningCode, int> warnings;

  /// Whether the workbook uses the 1904 date system.
  final bool date1904;
}

/// One expected sheet of a [ProducerFile].
final class ProducerSheet {
  /// The sheet [name] holding [rows], with its [visibility], [merges] in
  /// file order and the 0-based indexes of its [hiddenRows].
  const ProducerSheet(
    this.name,
    this.rows, {
    this.visibility = XlsxSheetVisibility.visible,
    this.merges = const <XlsxRange>[],
    this.hiddenRows = const <int>{},
  });

  /// The sheet name.
  final String name;

  /// The values, dense: `rows[0]` is sheet row 1, `rows[r][c]` column `c`.
  /// `null` means no cell, and a row past the end holds no cell.
  final List<List<Object?>> rows;

  /// Whether the sheet is visible, hidden or very hidden.
  final XlsxSheetVisibility visibility;

  /// The merged ranges, in file order.
  final List<XlsxRange> merges;

  /// The 0-based indexes of the rows the file hides. A hidden row is
  /// yielded by the reader even when it has no cell.
  final Set<int> hiddenRows;
}

/// Every producer package, for the tests that read each one and for the
/// fuzz corpus.
List<ProducerFile> producerFiles() => <ProducerFile>[];

/// Reads [f] and fails with a [TestFailure] listing every difference from
/// what it expects.
///
/// Values compare with `==`: an [XlsxDecimal] by its digits, a `DateTime`
/// exactly, an [XlsxErrorValue] by its code. A read row is densified to the
/// expected width; a cell beyond it, or a row beyond the expected rows, is a
/// difference. Warnings compare as `{code: total count}`.
void expectProducerFile(ProducerFile f) {
  final XlsxReader reader = XlsxReader(f.bytes);
  final List<String> problems = <String>[];
  if (reader.date1904 != f.date1904) {
    problems.add('date1904: expected ${f.date1904}, got ${reader.date1904}');
  }
  final List<XlsxReadSheet> sheets = reader.sheets;
  if (sheets.length != f.sheets.length) {
    problems.add(
      'sheets: expected ${f.sheets.map((ProducerSheet s) => s.name)}, '
      'got ${sheets.map((XlsxReadSheet s) => s.name)}',
    );
  }
  for (int i = 0; i < sheets.length && i < f.sheets.length; i++) {
    _compareSheet(reader, i, f.sheets[i], problems);
  }
  final Map<XlsxWarningCode, int> warnings = <XlsxWarningCode, int>{};
  for (final XlsxWarning w in reader.warnings) {
    warnings[w.code] = (warnings[w.code] ?? 0) + w.count;
  }
  for (final XlsxWarningCode code in <XlsxWarningCode>{
    ...warnings.keys,
    ...f.warnings.keys,
  }) {
    if (warnings[code] != f.warnings[code]) {
      problems.add(
        'warning ${code.name}: expected ${f.warnings[code] ?? 0}, '
        'got ${warnings[code] ?? 0}',
      );
    }
  }
  if (problems.isNotEmpty) {
    fail('${f.name} reads differently:\n  ${problems.join('\n  ')}');
  }
}

/// Compares sheet [index] of [reader] with [expected], adding each
/// difference to [problems].
void _compareSheet(
  XlsxReader reader,
  int index,
  ProducerSheet expected,
  List<String> problems,
) {
  final XlsxReadSheet sheet = reader.sheets[index];
  final String at = 'sheet ${expected.name}';
  if (sheet.name != expected.name) {
    problems.add('$at: name is ${sheet.name}');
  }
  if (sheet.visibility != expected.visibility) {
    problems.add(
      '$at: expected ${expected.visibility.name}, got '
      '${sheet.visibility.name}',
    );
  }
  final Map<int, XlsxReadRow> read = <int, XlsxReadRow>{};
  final Set<int> hidden = <int>{};
  for (final XlsxReadRow row in reader.rowsAt(index)) {
    if (read.containsKey(row.index)) {
      problems.add('$at: row ${row.index + 1} read twice');
    }
    read[row.index] = row;
    if (row.hidden) hidden.add(row.index);
  }
  for (final int row in hidden.difference(expected.hiddenRows)) {
    problems.add('$at: row ${row + 1} hidden, expected visible');
  }
  for (final int row in expected.hiddenRows.difference(hidden)) {
    problems.add('$at: row ${row + 1} expected hidden, not read as hidden');
  }
  final int height = <int>[
    expected.rows.length,
    for (final int row in read.keys) row + 1,
  ].reduce((int a, int b) => a > b ? a : b);
  for (int r = 0; r < height; r++) {
    final List<Object?> want = r < expected.rows.length
        ? expected.rows[r]
        : const <Object?>[];
    final List<XlsxReadCell> cells = read[r]?.cells ?? const <XlsxReadCell>[];
    final List<Object?> got = List<Object?>.filled(want.length, null);
    final Set<int> present = <int>{};
    for (final XlsxReadCell cell in cells) {
      if (cell.column >= want.length) {
        problems.add(
          '$at ${_cellName(r, cell.column)}: expected nothing, '
          'got ${_show(cell.value)}',
        );
      } else {
        got[cell.column] = cell.value;
        present.add(cell.column);
      }
    }
    for (int c = 0; c < want.length; c++) {
      if (want[c] == null && present.contains(c)) {
        problems.add(
          '$at ${_cellName(r, c)}: expected nothing, got ${_show(got[c])}',
        );
      } else if (want[c] != null && got[c] != want[c]) {
        problems.add(
          '$at ${_cellName(r, c)}: expected ${_show(want[c])}, '
          'got ${present.contains(c) ? _show(got[c]) : 'nothing'}',
        );
      }
    }
  }
  final List<XlsxRange> merges = reader.mergesAt(index);
  if (!_sameList(merges, expected.merges)) {
    problems.add('$at: merges expected ${expected.merges}, got $merges');
  }
}

/// Whether [a] and [b] hold equal elements in the same order.
bool _sameList(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The A1 name of the cell at 0-based [row] and [column].
String _cellName(int row, int column) {
  String letters = '';
  for (int c = column + 1; c > 0; c = (c - 1) ~/ 26) {
    letters = String.fromCharCode(0x41 + (c - 1) % 26) + letters;
  }
  return '$letters${row + 1}';
}

/// [value] with its type, so `'5'` and `XlsxDecimal(5)` read apart.
String _show(Object? value) => switch (value) {
  null => 'null',
  final String s => "'$s'",
  final DateTime d => 'DateTime($d)',
  _ => '$value',
};
