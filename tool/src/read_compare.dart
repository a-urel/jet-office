/// Compares what `XlsxReader` reads from a re-saved fixture with the
/// fixture's expected values.
///
/// New in jet_office; the counterpart of `csv_compare.dart` for the reader
/// (phase 2, ruling 10 of the R3 plan). The expected rows are
/// `Fixture.expectedValues` (what a calculating program shows, written by
/// `tool/write_fixtures.dart` as `<name>.expected.json`); the read rows are
/// what the reader finds in the file LibreOffice saved after recalculating.
/// The contract is the one in `Fixture.expectedValues`, applied to typed
/// values instead of CSV text:
///
/// * a number matches an `XlsxDecimal` within a relative tolerance of 1e-12;
/// * a number also matches a `DateTime` when it is the date's serial (1900
///   date system, or the 1904 system less 1462 days) within one second, and
///   a `Duration` when it is the duration in days within one second: a
///   re-saved number in a date or time format reads as one of those;
/// * a `bool` matches a `bool` only;
/// * a string matches a string exactly, and an `XlsxErrorValue` when it is
///   the error's code (`#DIV/0!`);
/// * `null` matches a missing cell, a cell without a value and an empty
///   string;
/// * trailing empty cells and trailing empty rows are ignored on both sides.
///
/// A value LibreOffice is known to write differently is allowed by name
/// only: `resaveAllowedValues` names the fixture, the cell and the one read
/// value, each with its reason, and nothing else at that cell passes.
///
/// Reader warnings are not compared here: `resaveAllowedWarnings` lists the
/// ones a re-save may legitimately cause, and `tool/compare_resaved.dart`
/// reports every other warning as a mismatch.
library;

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/cell_ref.dart';
import 'package:jet_office/src/xlsx/date_serial.dart';

export 'csv_compare.dart' show decodeXstring;

/// Known LibreOffice differences: fixture name to the warning codes the
/// reader may report on that fixture's re-save, each with its reason.
///
/// Empty: no re-save is known to differ. A line is added only with a reason
/// a reader of this file can check against the spec of the format, and the
/// reason says why the warning is LibreOffice's doing and not a reader
/// defect.
const Map<String, Map<XlsxWarningCode, String>> resaveAllowedWarnings =
    <String, Map<XlsxWarningCode, String>>{};

/// Known LibreOffice value differences: fixture name to `Sheet!A1` to the
/// one value the reader may read there and the reason.
///
/// `m2_formula_xstring` `Probe!A1`: the formula is `"_x005F_x0041_"`.
/// LibreOffice does not decode `_xHHHH_` in `<f>` (decision 0005), so its
/// result is `_x005F_x0041_`, which the expected value records; Excel
/// shows `_x0041_`. LibreOffice then writes that result in the `t="str"`
/// `<v>` without escaping it, where ST_Xstring (ECMA-376 Part 1, 22.9.2.19)
/// makes `_x005F_` an escape for `_`; the reader decodes it, correctly, to
/// `_x0041_`. Its shared strings are escaped and need no line.
const Map<String, Map<String, (String, String)>> resaveAllowedValues =
    <String, Map<String, (String, String)>>{
      'm2_formula_xstring': <String, (String, String)>{
        'Probe!A1': (
          '_x0041_',
          'LibreOffice does not decode _xHHHH_ in <f> (decision 0005) and '
              'writes the resulting _x005F_x0041_ in a t="str" <v> without '
              'escaping it, so the reader decodes it to _x0041_ as '
              'ST_Xstring requires.',
        ),
      },
    };

/// The values allowed on [sheet] of [fixture]: cell reference to the one
/// value, from [allowed] (default `resaveAllowedValues`).
Map<String, String> allowedValuesFor(
  String fixture,
  String sheet, {
  Map<String, Map<String, (String, String)>> allowed = resaveAllowedValues,
}) => <String, String>{
  for (final MapEntry<String, (String, String)> e
      in (allowed[fixture] ?? const <String, (String, String)>{}).entries)
    if (e.key.startsWith('$sheet!'))
      e.key.substring(sheet.length + 1): e.value.$1,
};

/// The mismatches of the [read] rows of one sheet against the [expected]
/// rows, under the contract in the library comment.
///
/// [expected] holds `String`, `num`, `bool` or `null` cells and is indexed
/// by row then column; a [read] row is placed by its `index`, so rows the
/// file leaves out count as empty. [date1904] is the workbook's date system
/// (`XlsxReader.date1904`). Returns one message per mismatching cell, such
/// as `B2: expected 42, got 41` or `C4: expected nothing, got 5`, in row
/// then column order; a cell of [allowedValues] (reference to value) also
/// matches that exact read string; an empty list means the sheet matches. Throws an
/// [ArgumentError] for an expected cell of any other type.
List<String> compareReadSheet(
  List<List<Object?>> expected,
  Iterable<XlsxReadRow> read, {
  required bool date1904,
  Map<String, String> allowedValues = const <String, String>{},
}) {
  final Map<int, Map<int, Object?>> want = <int, Map<int, Object?>>{};
  for (int r = 0; r < expected.length; r++) {
    for (int c = 0; c < expected[r].length; c++) {
      final Object? cell = expected[r][c];
      if (cell != null && cell is! String && cell is! num && cell is! bool) {
        throw ArgumentError.value(
          cell,
          'expected',
          'Expected cells are String, num, bool or null, not '
              '${cell.runtimeType}.',
        );
      }
      if (cell != null && cell != '') (want[r] ??= <int, Object?>{})[c] = cell;
    }
  }
  final Map<int, Map<int, Object?>> got = <int, Map<int, Object?>>{};
  for (final XlsxReadRow row in read) {
    for (final XlsxReadCell cell in row.cells) {
      final Object? value = cell.value;
      if (value != null && value != '') {
        (got[row.index] ??= <int, Object?>{})[cell.column] = value;
      }
    }
  }
  final Set<int> rows = <int>{...want.keys, ...got.keys};
  final List<String> messages = <String>[];
  for (final int r in rows.toList()..sort()) {
    final Map<int, Object?> wantRow = want[r] ?? const <int, Object?>{};
    final Map<int, Object?> gotRow = got[r] ?? const <int, Object?>{};
    final Set<int> columns = <int>{...wantRow.keys, ...gotRow.keys};
    for (final int c in columns.toList()..sort()) {
      final Object? w = wantRow[c];
      final Object? g = gotRow[c];
      if (g is String &&
          allowedValues[cellRef(r, c)] == g &&
          !_matches(w, g, date1904: date1904)) {
        continue;
      }
      if (!_matches(w, g, date1904: date1904)) {
        messages.add(
          '${cellRef(r, c)}: expected ${_describe(w, 'nothing')}, '
          'got ${_describe(g, 'nothing')}',
        );
      }
    }
  }
  return messages;
}

bool _matches(Object? want, Object? got, {required bool date1904}) {
  if (want == null || got == null) return want == null && got == null;
  if (want is String) {
    return got is String
        ? got == want
        : got is XlsxErrorValue && got.code == want;
  }
  if (want is bool) return got is bool && got == want;
  final double w = (want as num).toDouble();
  if (got is XlsxDecimal) return _closeEnough(w, got.toDouble());
  if (got is DateTime) {
    final double? serial = dateTimeSerial(got);
    if (serial == null) return false;
    return ((date1904 ? serial - 1462 : serial) - w).abs() <= _oneSecond;
  }
  if (got is Duration) {
    return (got.inMicroseconds / Duration.microsecondsPerDay - w).abs() <=
        _oneSecond;
  }
  return false;
}

bool _closeEnough(double a, double b) {
  if (a == b) return true;
  final double scale = a.abs() > b.abs() ? a.abs() : b.abs();
  return (a - b).abs() <= 1e-12 * scale;
}

/// One second in days, with room for floating-point error.
const double _oneSecond = 1 / 86400 + 1e-9;

String _describe(Object? value, String none) {
  if (value == null) return none;
  if (value is String) return '"$value"';
  if (value is XlsxDecimal) return value.digits;
  if (value is XlsxErrorValue) return value.code;
  if (value is DateTime) return value.toIso8601String();
  if (value is num && value == value.truncateToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return '$value';
}
