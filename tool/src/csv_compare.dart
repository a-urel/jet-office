/// Compares a reader's CSV export of one sheet with a fixture's expected
/// values.
///
/// `tool/compare_csv.dart` runs this against LibreOffice's export of every
/// fixture of every milestone. The contract is the one
/// `Fixture.expectedValues` documents in `test/fixtures/fixture.dart`:
///
/// - Values are raw, not formatted.
/// - Numbers are equal within a relative tolerance of 1e-12, which absorbs a
///   reader that prints 15 significant digits.
/// - A `bool` matches `TRUE`/`FALSE` or `1`/`0`.
/// - Strings are equal exactly.
/// - `null` (and `''`) match an empty field.
/// - Trailing empty rows and trailing empty cells are ignored on both sides.
///
/// One addition: LibreOffice's raw CSV export still prints a date-formatted
/// number as date text (its edit form, such as `10/24/2026 13:45:00`), not as
/// a serial. An expected number therefore also matches date text in
/// `MM/DD/YYYY` or ISO `YYYY-MM-DD` form, optionally with a time, when the
/// text's serial is within one second of it. The serial counts days from
/// 1899-12-30 with no 29 February 1900, which is how LibreOffice reads a
/// 1900-system serial: serial 59 prints as 02/27/1900 there, while Excel
/// shows 28.02.1900. One second covers a reader that truncates a time to
/// whole seconds and one that rounds it.
///
/// Two more, for the same reason (ruling R9): LibreOffice also keeps a
/// percent format and an elapsed-time format in its raw export. An expected
/// number therefore also matches
///
/// - percent text, the number times 100 followed by `%` (`123450%` for
///   1234.5), within the numeric tolerance above; and
/// - `[h]:mm:ss` elapsed-time text, the number as days counted in hours,
///   minutes and seconds (`29628:00:00` for 1234.5), within one second.
///
/// Pure Dart with no `dart:io`, so its tests run on the web too.
library;

import 'dart:convert';

/// The rows of the CSV [text]: comma-separated, `"` as the text delimiter
/// (doubled inside a quoted field), LF or CRLF between records.
///
/// A quoted field may hold commas, quotes and line breaks. A quote that is
/// not the first character of a field is plain text, as LibreOffice writes
/// `a"b` for the text `a"b`. A final line break does not start another row,
/// and empty text has no rows. Throws a [FormatException] for a quote that
/// is never closed.
List<List<String>> parseCsv(String text) {
  final List<List<String>> rows = <List<String>>[];
  List<String> row = <String>[];
  final StringBuffer field = StringBuffer();
  bool quoted = false;
  bool atRowStart = true;
  bool atFieldStart = true;
  int i = 0;
  while (i < text.length) {
    final String ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        quoted = false;
      } else {
        field.write(ch);
      }
      i++;
      continue;
    }
    atRowStart = false;
    if (ch == '"' && atFieldStart) {
      quoted = true;
      atFieldStart = false;
    } else if (ch == ',') {
      row.add(field.toString());
      field.clear();
      atFieldStart = true;
    } else if (ch == '\n' || ch == '\r') {
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
      atRowStart = true;
      atFieldStart = true;
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
    } else {
      field.write(ch);
      atFieldStart = false;
    }
    i++;
  }
  if (quoted) {
    throw const FormatException('A quoted CSV field is never closed.');
  }
  if (!atRowStart) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

/// Decodes the CSV file [bytes] as UTF-8 and drops a leading byte order
/// mark.
///
/// Throws a [FormatException] for malformed UTF-8, so a reader that wrote
/// another character set is caught rather than compared as garbage.
String decodeCsv(List<int> bytes) {
  final String text = utf8.decode(bytes);
  return text.startsWith('\uFEFF') ? text.substring(1) : text;
}

/// One message, `no expectations for <name>.xlsx`, for each `.xlsx` in
/// [fileNames] that has no `<name>.expected.json` beside it.
///
/// `tool/compare_csv.dart` fails on these instead of skipping the file, so a
/// fixture written without expectations cannot pass unnoticed.
List<String> xlsxWithoutExpectations(Iterable<String> fileNames) {
  final Set<String> names = fileNames.toSet();
  return <String>[
    for (final String name in fileNames)
      if (name.endsWith('.xlsx') &&
          !names.contains(
            '${name.substring(0, name.length - '.xlsx'.length)}.expected.json',
          ))
        'no expectations for $name',
  ];
}

/// The comparison of one sheet of one fixture: `messages` are the
/// mismatches (empty when it matches) and `note`, when set, is a line of
/// explanation printed before the sheet's result.
typedef SheetResult = ({
  String name,
  String sheet,
  String? note,
  List<String> messages,
});

/// What `tool/compare_csv.dart` prints and how it exits.
///
/// `lines` go to standard output. `error`, when set, goes to standard error.
/// `exitCode` is 0, 1 on any mismatch, or 2 when there is nothing to compare.
typedef CsvReport = ({List<String> lines, String? error, int exitCode});

/// The report for the files in [fileNames] (the directory listing) and the
/// per-sheet [sheets] already compared, in order.
///
/// The order is part of the contract: a `.xlsx` with no expectations is
/// reported first, even when the report stops with exit code 2 because
/// `expectationCount`, the number of `.expected.json` files, is 0. Then each
/// sheet prints its `note`, if any, and `ok    <name> / <sheet>` or `FAIL  <name> / <sheet>` followed by its
/// indented messages. The last line is the verdict. `dir` only names the
/// directory in the error text.
CsvReport assembleReport({
  required Iterable<String> fileNames,
  required int expectationCount,
  required List<SheetResult> sheets,
  String dir = '.',
}) {
  final List<String> lines = <String>[];
  int mismatches = 0;
  for (final String message in xlsxWithoutExpectations(fileNames)) {
    lines.add('FAIL  $message');
    mismatches++;
  }
  if (expectationCount == 0) {
    return (
      lines: lines,
      error: 'No .expected.json files in $dir.',
      exitCode: 2,
    );
  }
  for (final SheetResult sheet in sheets) {
    final String at = '${sheet.name} / ${sheet.sheet}';
    if (sheet.note != null) lines.add('note  ${sheet.note}');
    if (sheet.messages.isEmpty) {
      lines.add('ok    $at');
    } else {
      mismatches += sheet.messages.length;
      lines.add('FAIL  $at');
      for (final String message in sheet.messages) {
        lines.add('      $message');
      }
    }
  }
  lines.add(mismatches > 0 ? '$mismatches mismatch(es).' : 'All sheets match.');
  return (lines: lines, error: null, exitCode: mismatches > 0 ? 1 : 0);
}

final RegExp _xstringEscape = RegExp(r'_x([0-9A-Fa-f]{4})_');

/// [text] with its `_xHHHH_` escapes decoded, left to right, as Excel and
/// LibreOffice read an ST_Xstring: `_x0041_` is `A` and `_x005F_x0041_` is
/// the text `_x0041_`.
///
/// The fixtures store text that looks like an escape in escaped form, so a
/// stored string is compared with an expected one after this decoding.
String decodeXstring(String text) => text.replaceAllMapped(
  _xstringEscape,
  (Match m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
);

/// Compares the [expected] rows of one sheet with the [csv] text a reader
/// exported for it, under the contract in the library comment.
///
/// [expected] holds `String`, `num`, `bool` or `null` cells. Returns one
/// message per mismatching cell, such as `B2: expected 42, got "41"`, in row
/// then column order; an empty list means the sheet matches. Throws an
/// [ArgumentError] for an expected cell of any other type.
List<String> compareSheet(List<List<Object?>> expected, String csv) {
  for (final List<Object?> row in expected) {
    for (final Object? cell in row) {
      if (cell != null && cell is! String && cell is! num && cell is! bool) {
        throw ArgumentError.value(
          cell,
          'expected',
          'Expected cells are String, num, bool or null, not '
              '${cell.runtimeType}.',
        );
      }
    }
  }
  final List<List<Object?>> want = _trim<Object?>(
    expected,
    (Object? cell) => cell == null || cell == '',
  );
  final List<List<String>> got = _trim<String>(
    parseCsv(csv),
    (String cell) => cell.isEmpty,
  );
  final List<String> messages = <String>[];
  final int rowCount = want.length > got.length ? want.length : got.length;
  for (int r = 0; r < rowCount; r++) {
    final List<Object?> wantRow = r < want.length ? want[r] : const <Object?>[];
    final List<String> gotRow = r < got.length ? got[r] : const <String>[];
    final int width = wantRow.length > gotRow.length
        ? wantRow.length
        : gotRow.length;
    for (int c = 0; c < width; c++) {
      final Object? w = c < wantRow.length ? wantRow[c] : null;
      final String g = c < gotRow.length ? gotRow[c] : '';
      if (!_matches(w, g)) {
        messages.add(
          '${_columnName(c)}${r + 1}: expected ${_describeExpected(w)}, '
          'got ${_describeGot(g)}',
        );
      }
    }
  }
  return messages;
}

/// [rows] without trailing empty cells in each row, then without trailing
/// empty rows.
List<List<T>> _trim<T>(List<List<T>> rows, bool Function(T cell) isEmpty) {
  final List<List<T>> trimmed = <List<T>>[
    for (final List<T> row in rows)
      row.sublist(0, row.lastIndexWhere((T cell) => !isEmpty(cell)) + 1),
  ];
  while (trimmed.isNotEmpty && trimmed.last.isEmpty) {
    trimmed.removeLast();
  }
  return trimmed;
}

bool _matches(Object? want, String got) {
  if (want == null) return got.isEmpty;
  if (want is String) return got == want;
  if (want is bool) {
    return want
        ? (got == 'TRUE' || got == '1')
        : (got == 'FALSE' || got == '0');
  }
  final double w = (want as num).toDouble();
  if (_number.hasMatch(got)) return _closeEnough(w, double.parse(got));
  if (got.endsWith('%')) {
    final String percent = got.substring(0, got.length - 1);
    return _number.hasMatch(percent) &&
        _closeEnough(w * 100, double.parse(percent));
  }
  final double? serial = _dateSerial(got) ?? _elapsedDays(got);
  return serial != null && (serial - w).abs() <= _oneSecond;
}

final RegExp _elapsed = RegExp(
  r'^(-?)(\d+):([0-5]\d):([0-5]\d)(?:[.,](\d+))?$',
);

/// The days of `[h]:mm:ss` elapsed-time text, such as `29628:00:00` for
/// 1234.5, or `null` when [text] is not such a time.
double? _elapsedDays(String text) {
  final RegExpMatch? m = _elapsed.firstMatch(text);
  if (m == null) return null;
  final double fraction = m[5] == null ? 0 : double.parse('0.${m[5]}');
  final double seconds =
      int.parse(m[2]!) * 3600 +
      int.parse(m[3]!) * 60 +
      int.parse(m[4]!) +
      fraction;
  return (m[1]!.isEmpty ? seconds : -seconds) / 86400;
}

final RegExp _number = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$');

bool _closeEnough(double a, double b) {
  if (a == b) return true;
  final double scale = a.abs() > b.abs() ? a.abs() : b.abs();
  return (a - b).abs() <= 1e-12 * scale;
}

/// One second in days, with room for floating-point error.
const double _oneSecond = 1 / 86400 + 1e-9;

final RegExp _isoDate = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})'
  r'(?:[ T](\d{1,2}):(\d{2})(?::(\d{2})(?:[.,](\d+))?)?)?$',
);

final RegExp _usDate = RegExp(
  r'^(\d{1,2})/(\d{1,2})/(\d{4})'
  r'(?: (\d{1,2}):(\d{2})(?::(\d{2})(?:[.,](\d+))?)?(?: ?([AaPp][Mm]))?)?$',
);

final DateTime _epoch = DateTime.utc(1899, 12, 30);

/// The serial of date text in ISO or US form, counted from 1899-12-30 with
/// no 29 February 1900, or `null` when [text] is not such a date.
double? _dateSerial(String text) {
  int year, month, day;
  RegExpMatch? m = _isoDate.firstMatch(text);
  String? meridiem;
  if (m != null) {
    year = int.parse(m[1]!);
    month = int.parse(m[2]!);
    day = int.parse(m[3]!);
  } else {
    m = _usDate.firstMatch(text);
    if (m == null) return null;
    month = int.parse(m[1]!);
    day = int.parse(m[2]!);
    year = int.parse(m[3]!);
    meridiem = m[8]?.toUpperCase();
  }
  final DateTime date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  int hour = m[4] == null ? 0 : int.parse(m[4]!);
  final int minute = m[5] == null ? 0 : int.parse(m[5]!);
  final int second = m[6] == null ? 0 : int.parse(m[6]!);
  final double fraction = m[7] == null ? 0 : double.parse('0.${m[7]}');
  if (meridiem != null) {
    if (hour < 1 || hour > 12) return null;
    hour = hour % 12 + (meridiem == 'PM' ? 12 : 0);
  }
  if (hour > 23 || minute > 59 || second > 59) return null;
  final int days = date.difference(_epoch).inDays;
  return days + (hour * 3600 + minute * 60 + second + fraction) / 86400;
}

/// The spreadsheet column name of the zero-based column [index]: A, B, ...,
/// Z, AA, AB, ...
String _columnName(int index) {
  String name = '';
  for (int n = index + 1; n > 0; n = (n - 1) ~/ 26) {
    name = String.fromCharCode(0x41 + (n - 1) % 26) + name;
  }
  return name;
}

String _describeExpected(Object? want) => switch (want) {
  null || '' => 'empty',
  final String s => _quote(s),
  true => 'TRUE',
  false => 'FALSE',
  _ => '$want',
};

String _describeGot(String got) => got.isEmpty ? 'empty' : _quote(got);

/// [s] in double quotes, shortened to its first 40 characters with its
/// length when it is longer than 60.
String _quote(String s) {
  if (s.length <= 60) return '"$s"';
  int end = 40;
  final int unit = s.codeUnitAt(end - 1);
  if (unit >= 0xD800 && unit <= 0xDBFF) end--; // keep a surrogate pair whole
  return '"${s.substring(0, end)}..." (${s.length} characters)';
}
