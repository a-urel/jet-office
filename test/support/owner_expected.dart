/// Test helper: the expected-values format of the owner's real Excel and
/// Google Sheets files, its parser, its comparison with `XlsxReader` and the
/// drafting of a first version from what the reader returns.
///
/// Web-safe on purpose (no `dart:io`), so `test/fixtures/owner_expected_test.dart`
/// runs on Chrome too; `test/xlsx/read/owner_files_test.dart` (VM only) reads
/// the files, and `tool/draft_expected.dart` writes the drafts. The format
/// is documented in `test/fixtures/owner/README.md`. In short, one
/// `<file>.expected.json` beside each `<file>.xlsx`:
///
/// - `rows[0]` is sheet row 1; a `null` or a missing trailing cell is no
///   cell. A JSON string is text, `true` and `false` are booleans.
/// - Object cells hold exactly one of `s` (text), `n` (decimal digits as a
///   string, compared by value with a relative tolerance of 1e-12), `b`
///   (boolean), `date` (`YYYY-MM-DD` or `YYYY-MM-DDTHH:MM:SS`, compared to
///   the second), `duration` (`[-]H:MM:SS`, to the second) or `error` (the
///   code), or none (a formula without a value). `formula` (exact text, no
///   `=`) and `format` (the number format code, exact) are optional on any
///   object cell. A cell with a formula in the file needs `formula`; a
///   missing `format` is not checked.
/// - `merges`, `hiddenRows` (0-based) and `visibility` default to none,
///   none and `visible`; `date1904` to false. `warnings` is a list of
///   `{"code": name, "count": n}`; the default means the file reads with
///   no warning at all.
library;

import 'dart:convert';

import 'package:jet_office/jet_office.dart';

/// What a cell holds in an expectation.
enum OwnerKind {
  /// Text; the value is a `String`.
  text,

  /// A number; the value is the digits as a `String`.
  number,

  /// A boolean; the value is a `bool`.
  boolean,

  /// A date or date and time; the value is a UTC `DateTime`.
  date,

  /// An elapsed time; the value is a `Duration`.
  duration,

  /// A formula error; the value is its code as a `String`.
  error,

  /// No value (a formula whose result the file does not store).
  empty,
}

/// One expected cell.
final class OwnerCell {
  /// Creates a cell of [kind] holding [value].
  const OwnerCell(this.kind, this.value, {this.formula, this.format});

  /// What the cell holds.
  final OwnerKind kind;

  /// The value; its type depends on [kind].
  final Object? value;

  /// The exact formula text without `=`, or null.
  final String? formula;

  /// The exact number format code, or null when it is not checked.
  final String? format;
}

/// One expected sheet.
final class OwnerSheet {
  /// Creates a sheet.
  const OwnerSheet(
    this.name,
    this.visibility,
    this.merges,
    this.hiddenRows,
    this.rows,
  );

  /// The sheet name.
  final String name;

  /// The sheet's visibility.
  final XlsxSheetVisibility visibility;

  /// The merged ranges.
  final List<XlsxRange> merges;

  /// The hidden rows, 0-based.
  final List<int> hiddenRows;

  /// The rows; `rows[0]` is sheet row 1.
  final List<List<OwnerCell?>> rows;
}

/// An expected warning: a code and how many occurrences, over all cells.
final class OwnerWarning {
  /// Creates an expected warning.
  const OwnerWarning(this.code, this.count);

  /// The warning code.
  final XlsxWarningCode code;

  /// The summed count of every warning with this code.
  final int count;
}

/// The parsed `<file>.expected.json`.
final class OwnerExpected {
  /// Creates an expectation.
  const OwnerExpected({
    required this.file,
    required this.producer,
    required this.confirmedBy,
    required this.date1904,
    required this.sheets,
    required this.warnings,
  });

  /// The `.xlsx` file name this expectation belongs to.
  final String file;

  /// Program, version and platform that saved the file.
  final String producer;

  /// `"owner"` once the owner has ticked every cell; null in a draft.
  final String? confirmedBy;

  /// Whether the workbook uses the 1904 date system.
  final bool date1904;

  /// The sheets, in workbook order.
  final List<OwnerSheet> sheets;

  /// The warnings the reader must give; none means no warning at all.
  final List<OwnerWarning> warnings;
}

const Set<String> _rootKeys = <String>{
  'file',
  'producer',
  'confirmedBy',
  'date1904',
  'sheets',
  'warnings',
};
const Set<String> _sheetKeys = <String>{
  'name',
  'visibility',
  'merges',
  'hiddenRows',
  'rows',
};
const Set<String> _valueKeys = <String>{
  's',
  'n',
  'b',
  'date',
  'duration',
  'error',
};
const Set<String> _cellKeys = <String>{..._valueKeys, 'formula', 'format'};

String _at(String path, String key) => path.isEmpty ? key : '$path.$key';

Never _bad(String path, String problem) =>
    throw FormatException(path.isEmpty ? problem : '$path: $problem');

Map<String, Object?> _object(Object? v, String path, Set<String> keys) {
  if (v is! Map<String, Object?>) _bad(path, 'expected an object');
  for (final String key in v.keys) {
    if (!keys.contains(key)) _bad(_at(path, key), 'unknown key');
  }
  return v;
}

String _string(Object? v, String path) {
  if (v is! String) _bad(path, 'expected a string');
  return v;
}

List<Object?> _list(Object? v, String path) {
  if (v is! List<Object?>) _bad(path, 'expected a list');
  return v;
}

Object? _required(Map<String, Object?> m, String key, String path) {
  if (!m.containsKey(key)) _bad(_at(path, key), 'missing');
  return m[key];
}

/// Parses the text of a `<file>.expected.json`.
///
/// Throws [FormatException] for invalid JSON, and for an unknown key or a
/// value of the wrong shape, with a message that starts with the path of
/// the offender, such as `sheets[0].rows[3][2].n`.
OwnerExpected parseOwnerExpected(String json) {
  final Object? decoded = jsonDecode(json);
  final Map<String, Object?> root = _object(decoded, '', _rootKeys);
  final Object? confirmed = _required(root, 'confirmedBy', '');
  if (confirmed != null && confirmed is! String) {
    _bad('confirmedBy', 'expected a string or null');
  }
  final Object date1904 = root['date1904'] ?? false;
  if (date1904 is! bool) _bad('date1904', 'expected true or false');
  final List<Object?> sheets = _list(_required(root, 'sheets', ''), 'sheets');
  final List<Object?> warnings = _list(
    root['warnings'] ?? <Object?>[],
    'warnings',
  );
  return OwnerExpected(
    file: _string(_required(root, 'file', ''), 'file'),
    producer: _string(_required(root, 'producer', ''), 'producer'),
    confirmedBy: confirmed as String?,
    date1904: date1904,
    sheets: <OwnerSheet>[
      for (int i = 0; i < sheets.length; i++)
        _parseSheet(sheets[i], 'sheets[$i]'),
    ],
    warnings: <OwnerWarning>[
      for (int i = 0; i < warnings.length; i++)
        _parseWarning(warnings[i], 'warnings[$i]'),
    ],
  );
}

OwnerWarning _parseWarning(Object? v, String path) {
  final Map<String, Object?> m = _object(v, path, const <String>{
    'code',
    'count',
  });
  final String name = _string(_required(m, 'code', path), _at(path, 'code'));
  XlsxWarningCode? code;
  for (final XlsxWarningCode c in XlsxWarningCode.values) {
    if (c.name == name) code = c;
  }
  if (code == null) _bad(_at(path, 'code'), 'unknown warning code "$name"');
  final Object? count = _required(m, 'count', path);
  if (count is! int || count < 1) {
    _bad(_at(path, 'count'), 'expected an integer of at least 1');
  }
  return OwnerWarning(code, count);
}

OwnerSheet _parseSheet(Object? v, String path) {
  final Map<String, Object?> m = _object(v, path, _sheetKeys);
  final String visibility = m.containsKey('visibility')
      ? _string(m['visibility'], _at(path, 'visibility'))
      : 'visible';
  XlsxSheetVisibility? parsed;
  for (final XlsxSheetVisibility c in XlsxSheetVisibility.values) {
    if (c.name == visibility) parsed = c;
  }
  if (parsed == null) {
    _bad(
      _at(path, 'visibility'),
      'expected ${XlsxSheetVisibility.values.map((XlsxSheetVisibility c) => c.name).join(', ')}',
    );
  }
  final List<Object?> merges = _list(
    m['merges'] ?? <Object?>[],
    _at(path, 'merges'),
  );
  final List<Object?> hidden = _list(
    m['hiddenRows'] ?? <Object?>[],
    _at(path, 'hiddenRows'),
  );
  final List<Object?> rows = _list(
    _required(m, 'rows', path),
    _at(path, 'rows'),
  );
  return OwnerSheet(
    _string(_required(m, 'name', path), _at(path, 'name')),
    parsed,
    <XlsxRange>[
      for (int i = 0; i < merges.length; i++)
        _parseRange(merges[i], '${_at(path, 'merges')}[$i]'),
    ],
    <int>[
      for (int i = 0; i < hidden.length; i++)
        _parseRow(hidden[i], '${_at(path, 'hiddenRows')}[$i]'),
    ],
    <List<OwnerCell?>>[
      for (int r = 0; r < rows.length; r++)
        _parseRowCells(rows[r], '${_at(path, 'rows')}[$r]'),
    ],
  );
}

XlsxRange _parseRange(Object? v, String path) {
  final String ref = _string(v, path);
  try {
    return XlsxRange.parse(ref);
  } on ArgumentError {
    _bad(path, 'not a cell range: "$ref"');
  }
}

int _parseRow(Object? v, String path) {
  if (v is! int || v < 0) _bad(path, 'expected a 0-based row number');
  return v;
}

List<OwnerCell?> _parseRowCells(Object? v, String path) {
  final List<Object?> cells = _list(v, path);
  return <OwnerCell?>[
    for (int c = 0; c < cells.length; c++) _parseCell(cells[c], '$path[$c]'),
  ];
}

final RegExp _digits = RegExp(r'^-?\d+(\.\d+)?$');
final RegExp _dateText = RegExp(
  r'^(\d{4})-(\d\d)-(\d\d)(?:T(\d\d):(\d\d):(\d\d))?$',
);
final RegExp _durationText = RegExp(r'^(-)?(\d+):([0-5]\d):([0-5]\d)$');

OwnerCell? _parseCell(Object? v, String path) {
  if (v == null) return null;
  if (v is String) return OwnerCell(OwnerKind.text, v);
  if (v is bool) return OwnerCell(OwnerKind.boolean, v);
  final Map<String, Object?> m = _object(v, path, _cellKeys);
  final List<String> present = <String>[
    for (final String key in _valueKeys)
      if (m.containsKey(key)) key,
  ];
  if (present.length > 1) {
    _bad(path, 'expected at most one of ${_valueKeys.join(', ')}');
  }
  final String? formula = m.containsKey('formula')
      ? _string(m['formula'], _at(path, 'formula'))
      : null;
  final String? format = m.containsKey('format')
      ? _string(m['format'], _at(path, 'format'))
      : null;
  if (present.isEmpty) {
    return OwnerCell(OwnerKind.empty, null, formula: formula, format: format);
  }
  final String key = present.single;
  final String where = _at(path, key);
  final Object? raw = m[key];
  final (OwnerKind, Object?) typed = switch (key) {
    's' => (OwnerKind.text, _string(raw, where)),
    'n' => (OwnerKind.number, _parseNumber(raw, where)),
    'b' => (OwnerKind.boolean, _parseBool(raw, where)),
    'date' => (OwnerKind.date, _parseDate(raw, where)),
    'duration' => (OwnerKind.duration, _parseDuration(raw, where)),
    _ => (OwnerKind.error, _string(raw, where)),
  };
  return OwnerCell(typed.$1, typed.$2, formula: formula, format: format);
}

String _parseNumber(Object? v, String path) {
  final String s = _string(v, path);
  if (!_digits.hasMatch(s)) {
    _bad(path, 'expected decimal digits in a string, such as "-12.50"');
  }
  return s;
}

bool _parseBool(Object? v, String path) {
  if (v is! bool) _bad(path, 'expected true or false');
  return v;
}

DateTime _parseDate(Object? v, String path) {
  final String s = _string(v, path);
  final RegExpMatch? m = _dateText.firstMatch(s);
  if (m == null) _bad(path, 'expected YYYY-MM-DD or YYYY-MM-DDTHH:MM:SS');
  int g(int i) => m[i] == null ? 0 : int.parse(m[i]!);
  final DateTime d = DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6));
  if (d.year != g(1) ||
      d.month != g(2) ||
      d.day != g(3) ||
      g(4) > 23 ||
      g(5) > 59 ||
      g(6) > 59) {
    _bad(path, 'not a real date or time: "$s"');
  }
  return d;
}

Duration _parseDuration(Object? v, String path) {
  final String s = _string(v, path);
  final RegExpMatch? m = _durationText.firstMatch(s);
  if (m == null) _bad(path, 'expected [-]H:MM:SS');
  final Duration d = Duration(
    hours: int.parse(m[2]!),
    minutes: int.parse(m[3]!),
    seconds: int.parse(m[4]!),
  );
  return m[1] == null ? d : -d;
}

// ---------------------------------------------------------------------------
// Comparison

/// The type name of a value the reader returns, as the review table shows.
String valueType(Object? value) => switch (value) {
  null => 'empty',
  String() => 'text',
  XlsxDecimal() => 'number',
  bool() => 'boolean',
  DateTime() => 'date',
  Duration() => 'duration',
  XlsxErrorValue() => 'error',
  _ => value.runtimeType.toString(),
};

/// The value the reader returned as one line of text: text quoted and
/// escaped (a line break shows as `\n`), numbers as their digits, dates in
/// the format of the expectation, durations as `H:MM:SS`.
String valueText(Object? value) => switch (value) {
  null => '',
  String() => jsonEncode(value),
  XlsxDecimal() => value.digits,
  bool() => '$value',
  DateTime() => _dateIso(value),
  Duration() => _durationText_(value),
  XlsxErrorValue() => value.code,
  _ => '$value',
};

String _two(int n) => n.toString().padLeft(2, '0');

String _dateIso(DateTime d) {
  final String day =
      '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';
  final bool midnight =
      d.hour == 0 && d.minute == 0 && d.second == 0 && d.millisecond == 0;
  return midnight
      ? day
      : '${day}T${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
}

String _durationText_(Duration d) {
  final int total = (d.inMilliseconds / 1000).round().abs();
  return '${d.isNegative ? '-' : ''}${total ~/ 3600}:'
      '${_two(total % 3600 ~/ 60)}:${_two(total % 60)}';
}

String _describeExpected(OwnerCell c) {
  final String value = switch (c.kind) {
    OwnerKind.text => jsonEncode(c.value),
    OwnerKind.number => 'number ${c.value}',
    OwnerKind.boolean => 'boolean ${c.value}',
    OwnerKind.date => 'date ${_dateIso(c.value! as DateTime)}',
    OwnerKind.duration => 'duration ${_durationText_(c.value! as Duration)}',
    OwnerKind.error => 'error ${c.value}',
    OwnerKind.empty => 'no value',
  };
  final String text = c.kind == OwnerKind.text ? 'text $value' : value;
  return '$text${c.formula == null ? '' : ' =${c.formula}'}'
      '${c.format == null ? '' : ' [${c.format}]'}';
}

String _describeActual(XlsxReadCell c) =>
    '${valueType(c.value)} ${valueText(c.value)}'
    '${c.formula == null ? '' : ' =${c.formula}'}'
    ' [${c.numberFormat}]';

bool _sameNumber(String expected, XlsxDecimal actual) {
  final double a = double.parse(expected);
  final double b = actual.toDouble();
  final double scale = a.abs() > b.abs() ? a.abs() : b.abs();
  return a == b || (a - b).abs() <= 1e-12 * scale;
}

bool _sameValue(OwnerCell e, Object? actual) {
  switch (e.kind) {
    case OwnerKind.text:
      return actual is String && actual == e.value;
    case OwnerKind.number:
      return actual is XlsxDecimal && _sameNumber(e.value! as String, actual);
    case OwnerKind.boolean:
      return actual is bool && actual == e.value;
    case OwnerKind.date:
      return actual is DateTime &&
          actual.difference(e.value! as DateTime).abs() <
              const Duration(seconds: 1);
    case OwnerKind.duration:
      return actual is Duration &&
          (actual - (e.value! as Duration)).abs() < const Duration(seconds: 1);
    case OwnerKind.error:
      return actual is XlsxErrorValue && actual.code == e.value;
    case OwnerKind.empty:
      return actual == null;
  }
}

/// Whether the reader sees a cell: a value or a formula. A styled empty
/// cell is no cell.
bool _present(XlsxReadCell? c) =>
    c != null && (c.value != null || c.formula != null);

void _compareCell(
  List<String> out,
  String where,
  OwnerCell? expected,
  XlsxReadCell? actual,
) {
  final bool present = _present(actual);
  if (expected == null) {
    if (present) {
      out.add('$where: expected no cell, got ${_describeActual(actual!)}');
    }
    return;
  }
  if (!present) {
    out.add('$where: expected ${_describeExpected(expected)}, got no cell');
    return;
  }
  if (!_sameValue(expected, actual!.value) ||
      expected.formula != actual.formula ||
      (expected.format != null && expected.format != actual.numberFormat)) {
    out.add(
      '$where: expected ${_describeExpected(expected)}, '
      'got ${_describeActual(actual)}',
    );
  }
}

/// Compares what [reader] returns with [expected] and lists the
/// mismatches, empty when they agree.
///
/// Reads every sheet's rows and merges, then compares the sheets (by
/// position and name), visibility, `date1904`, merges (as a set), hidden
/// rows, every cell of the union of both grids and finally the warnings,
/// summed by code. A file the reader refuses is a mismatch, not a throw.
List<String> compareOwnerFile(OwnerExpected expected, XlsxReader reader) {
  final List<String> out = <String>[];
  if (reader.date1904 != expected.date1904) {
    out.add('date1904: expected ${expected.date1904}, got ${reader.date1904}');
  }
  final List<XlsxReadSheet> sheets = reader.sheets;
  if (sheets.length != expected.sheets.length) {
    out.add(
      'sheets: expected ${expected.sheets.length} '
      '(${expected.sheets.map((OwnerSheet s) => s.name).join(', ')}), '
      'got ${sheets.length} (${sheets.map((XlsxReadSheet s) => s.name).join(', ')})',
    );
  }
  for (int i = 0; i < sheets.length && i < expected.sheets.length; i++) {
    try {
      _compareSheet(out, expected.sheets[i], reader, sheets[i]);
    } on XlsxReadException catch (e) {
      out.add('${sheets[i].name}: the reader refused the sheet: $e');
    }
  }
  _compareWarnings(out, expected, reader);
  return out;
}

void _compareSheet(
  List<String> out,
  OwnerSheet expected,
  XlsxReader reader,
  XlsxReadSheet sheet,
) {
  final String name = sheet.name;
  if (sheet.name != expected.name) {
    out.add(
      'sheets[${sheet.index}]: expected name "${expected.name}", got "$name"',
    );
  }
  if (sheet.visibility != expected.visibility) {
    out.add(
      '$name: expected ${expected.visibility.name}, got ${sheet.visibility.name}',
    );
  }
  final Map<int, XlsxReadRow> rows = <int, XlsxReadRow>{
    for (final XlsxReadRow row in reader.rowsAt(sheet.index)) row.index: row,
  };
  final List<String> merges = <String>[
    for (final XlsxRange r in reader.mergesAt(sheet.index)) r.ref,
  ]..sort();
  final List<String> wantMerges = <String>[
    for (final XlsxRange r in expected.merges) r.ref,
  ]..sort();
  if (merges.join(',') != wantMerges.join(',')) {
    out.add(
      '$name: merges expected [${wantMerges.join(', ')}], got [${merges.join(', ')}]',
    );
  }
  final List<int> hidden = <int>[
    for (final XlsxReadRow row in rows.values)
      if (row.hidden) row.index,
  ]..sort();
  final List<int> wantHidden = expected.hiddenRows.toSet().toList()..sort();
  if (hidden.join(',') != wantHidden.join(',')) {
    out.add(
      '$name: hidden rows (0-based) expected [${wantHidden.join(', ')}], '
      'got [${hidden.join(', ')}]',
    );
  }
  int rowCount = expected.rows.length;
  for (final int index in rows.keys) {
    if (_hasCells(rows[index]!) && index + 1 > rowCount) rowCount = index + 1;
  }
  for (int r = 0; r < rowCount; r++) {
    final List<OwnerCell?> want = r < expected.rows.length
        ? expected.rows[r]
        : const <OwnerCell?>[];
    final Map<int, XlsxReadCell> got = <int, XlsxReadCell>{
      for (final XlsxReadCell c in rows[r]?.cells ?? const <XlsxReadCell>[])
        c.column: c,
    };
    int columnCount = want.length;
    for (final int column in got.keys) {
      if (_present(got[column]) && column + 1 > columnCount) {
        columnCount = column + 1;
      }
    }
    for (int c = 0; c < columnCount; c++) {
      _compareCell(
        out,
        '$name!${XlsxRange(r, c).ref}',
        c < want.length ? want[c] : null,
        got[c],
      );
    }
  }
}

bool _hasCells(XlsxReadRow row) => row.cells.any(_present);

void _compareWarnings(
  List<String> out,
  OwnerExpected expected,
  XlsxReader reader,
) {
  final Map<String, int> got = <String, int>{};
  for (final XlsxWarning w in reader.warnings) {
    got[w.code.name] = (got[w.code.name] ?? 0) + w.count;
  }
  final Map<String, int> want = <String, int>{};
  for (final OwnerWarning w in expected.warnings) {
    want[w.code.name] = (want[w.code.name] ?? 0) + w.count;
  }
  for (final String code in <String>{...got.keys, ...want.keys}) {
    if (got[code] != want[code]) {
      out.add(
        'warnings: $code expected ${want[code] ?? 0}, got ${got[code] ?? 0}',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Drafting

Object? _cellJson(XlsxReadCell? cell) {
  if (!_present(cell)) return null;
  final Object? v = cell!.value;
  final String? format = cell.numberFormat == 'General'
      ? null
      : cell.numberFormat;
  final Map<String, Object?> extra = <String, Object?>{
    'formula': ?cell.formula,
    'format': ?format,
  };
  if (extra.isEmpty) {
    if (v is String || v is bool) return v;
  }
  final Map<String, Object?> m = <String, Object?>{
    if (v is String) 's': v,
    if (v is XlsxDecimal) 'n': v.digits,
    if (v is bool) 'b': v,
    if (v is DateTime) 'date': _dateIso(v),
    if (v is Duration) 'duration': _durationText_(v),
    if (v is XlsxErrorValue) 'error': v.code,
    ...extra,
  };
  return m;
}

/// The text of a first `<file>.expected.json` for [reader]: every value,
/// formula and number format it returns, with `"confirmedBy": null` and an
/// empty `producer` for the owner to fill in.
///
/// Reads every sheet's rows and merges. [file] is the `.xlsx` file name.
/// Throws what the reader throws (`XlsxReadException`).
String draftOwnerExpected(XlsxReader reader, {required String file}) {
  final StringBuffer out = StringBuffer()
    ..writeln('{')
    ..writeln('  "file": ${jsonEncode(file)},')
    ..writeln('  "producer": "",')
    ..writeln('  "confirmedBy": null,')
    ..writeln('  "date1904": ${reader.date1904},')
    ..writeln('  "sheets": [');
  final List<String> sheets = <String>[];
  for (final XlsxReadSheet sheet in reader.sheets) {
    final List<XlsxReadRow> rows = reader.rowsAt(sheet.index).toList();
    final List<List<Object?>> grid = <List<Object?>>[];
    final List<int> hidden = <int>[];
    for (final XlsxReadRow row in rows) {
      if (row.hidden) hidden.add(row.index);
      final List<Object?> cells = <Object?>[];
      for (final XlsxReadCell c in row.cells) {
        final Object? json = _cellJson(c);
        if (json == null) continue;
        while (cells.length < c.column) {
          cells.add(null);
        }
        cells.add(json);
      }
      if (cells.isEmpty) continue;
      while (grid.length < row.index) {
        grid.add(<Object?>[]);
      }
      grid.add(cells);
    }
    final List<String> merges = <String>[
      for (final XlsxRange r in reader.mergesAt(sheet.index)) r.ref,
    ];
    sheets.add(
      '    {\n'
      '      "name": ${jsonEncode(sheet.name)},\n'
      '      "visibility": "${sheet.visibility.name}",\n'
      '      "merges": ${jsonEncode(merges)},\n'
      '      "hiddenRows": ${jsonEncode(hidden)},\n'
      '      "rows": [${grid.isEmpty ? '' : '\n'}'
      '${grid.map((List<Object?> r) => '        ${jsonEncode(r)}').join(',\n')}'
      '${grid.isEmpty ? '' : '\n      '}]\n'
      '    }',
    );
  }
  out
    ..writeln(sheets.join(',\n'))
    ..writeln('  ],');
  final Map<String, int> warnings = <String, int>{};
  for (final XlsxWarning w in reader.warnings) {
    warnings[w.code.name] = (warnings[w.code.name] ?? 0) + w.count;
  }
  out.writeln(
    '  "warnings": ['
    '${warnings.entries.map((MapEntry<String, int> e) => '{"code": "${e.key}", "count": ${e.value}}').join(', ')}'
    ']',
  );
  out.writeln('}');
  return out.toString();
}

/// A table for the owner to tick against the producing program: one line
/// per cell, `Sheet!Cell  type  value  format  formula`, preceded by each
/// sheet's visibility, merges and hidden rows (as the program numbers
/// them, from 1) and followed by the warnings.
String reviewTable(XlsxReader reader) {
  final StringBuffer out = StringBuffer();
  out.writeln('date1904: ${reader.date1904}');
  for (final XlsxReadSheet sheet in reader.sheets) {
    final List<XlsxReadRow> rows = reader.rowsAt(sheet.index).toList();
    final List<String> lines = <String>[];
    final List<List<String>> table = <List<String>>[];
    for (final XlsxReadRow row in rows) {
      for (final XlsxReadCell c in row.cells) {
        if (!_present(c)) continue;
        table.add(<String>[
          '${sheet.name}!${XlsxRange(row.index, c.column).ref}',
          valueType(c.value),
          valueText(c.value),
          c.numberFormat ?? '',
          if (c.formula != null) '=${c.formula}',
        ]);
      }
    }
    final List<int> widths = <int>[0, 0, 0];
    for (final List<String> line in table) {
      for (int i = 0; i < 3; i++) {
        if (line[i].length > widths[i]) widths[i] = line[i].length;
      }
    }
    if (widths[2] > 40) widths[2] = 40;
    for (final List<String> line in table) {
      lines.add(
        '${line[0].padRight(widths[0])}  ${line[1].padRight(widths[1])}  '
                '${line[2].padRight(widths[2])}  ${line.skip(3).join('  ')}'
            .trimRight(),
      );
    }
    out
      ..writeln()
      ..writeln('Sheet "${sheet.name}" (${sheet.visibility.name})');
    final List<XlsxRange> merges = reader.mergesAt(sheet.index);
    if (merges.isNotEmpty) {
      out.writeln('  merged: ${merges.map((XlsxRange r) => r.ref).join(', ')}');
    }
    final List<int> hidden = <int>[
      for (final XlsxReadRow row in rows)
        if (row.hidden) row.index + 1,
    ];
    if (hidden.isNotEmpty) out.writeln('  hidden rows: ${hidden.join(', ')}');
    lines.forEach(out.writeln);
  }
  if (reader.warnings.isNotEmpty) {
    out
      ..writeln()
      ..writeln('Warnings');
    for (final XlsxWarning w in reader.warnings) {
      out.writeln('  ${w.code.name} x${w.count}: ${w.message()}');
    }
  }
  return out.toString();
}

// ---------------------------------------------------------------------------
// The directory

/// The problems with the file names in `test/fixtures/owner/` against the
/// names in `manifest.json` ([manifest] lists `.xlsx` file names).
///
/// Only `*.xlsx` and `*.expected.json` files count; every other name
/// (`README.md`, `manifest.json`, a stray `.DS_Store`) is ignored. An
/// `.xlsx` without its `.expected.json`, a JSON without its `.xlsx`, either
/// one missing from the manifest, a manifest entry without a file and a
/// duplicate or malformed entry are each a problem.
List<String> ownerDirectoryProblems(
  Iterable<String> fileNames,
  List<String> manifest,
) {
  const String jsonSuffix = '.expected.json';
  final Set<String> files = fileNames.toSet();
  final Set<String> listed = <String>{};
  final List<String> problems = <String>[];
  for (final String entry in manifest) {
    if (!entry.endsWith('.xlsx') ||
        entry.contains('/') ||
        entry.contains(r'\')) {
      problems.add('manifest.json: "$entry" is not an .xlsx file name');
    } else if (!listed.add(entry)) {
      problems.add('manifest.json: "$entry" is listed twice');
    } else if (!files.contains(entry)) {
      problems.add('manifest.json: "$entry" is not in the directory');
    }
  }
  for (final String name in files.toList()..sort()) {
    if (name.endsWith('.xlsx')) {
      if (!listed.contains(name)) problems.add('$name is not in manifest.json');
      final String json = '${name.substring(0, name.length - 5)}$jsonSuffix';
      if (!files.contains(json)) problems.add('$name has no $json');
    } else if (name.endsWith(jsonSuffix)) {
      final String xlsx =
          '${name.substring(0, name.length - jsonSuffix.length)}.xlsx';
      if (!files.contains(xlsx)) problems.add('$name has no $xlsx');
      if (!listed.contains(xlsx)) {
        problems.add('$xlsx (for $name) is not in manifest.json');
      }
    }
  }
  return problems;
}

/// The problems with [expected] as a confirmed file named [fileName]:
/// `confirmedBy` is not exactly `"owner"` (a draft has null), the
/// `producer` is empty, or `file` names another file.
List<String> ownerConfirmationProblems(
  OwnerExpected expected,
  String fileName,
) => <String>[
  if (expected.confirmedBy != 'owner')
    '$fileName: confirmedBy is ${jsonEncode(expected.confirmedBy)}, not '
        '"owner": the owner has not confirmed it',
  if (expected.producer.trim().isEmpty)
    '$fileName: producer is empty: name the program, version and platform',
  if (expected.file != fileName)
    '$fileName: "file" says ${jsonEncode(expected.file)}',
];
