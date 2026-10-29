/// Compares `XlsxNumberFormatter` with a spreadsheet application's CSV of
/// the oracle cases (`tool/src/format_oracle.dart`).
///
/// New in jet_office (milestone N3 of decision 0008). Shared by the oracle
/// test (`test/xlsx/format/oracle_test.dart`), which reads the owner's
/// Excel for Mac CSVs, and the LibreOffice tool. [parseOracleCsv] reads a
/// CSV of an oracle workbook into case id to column A, [compareOracle]
/// formats each case of a workbook and compares it with that text (or, for
/// an eye-only case, with the owner's eye text), [oracleReport] prints the
/// outcomes, and [parseOracleManifest] reads `manifest.json`.
///
/// Pure Dart with no `dart:io`, so its tests run in a browser too: the
/// caller reads the files.
///
/// Excel for Mac's "CSV UTF-8" starts with a byte order mark, ends lines
/// with CRLF and, in a region whose decimal separator is a comma (de-DE,
/// tr-TR), separates fields with `;`. The separator is read from the
/// header row, which the workbooks write as `value`, `code`, `case`,
/// `note`. Texts are compared exactly, never trimmed (the trailing space of
/// `_)` padding is part of what Excel shows), with two tolerances for what
/// a CSV cannot show as the cell does ([oracleTextMatches]).
library;

import 'dart:convert';

import 'package:jet_office/jet_office.dart';

import 'format_oracle.dart';

const String _bom = '﻿';

/// Rows of a CSV [text], fields unquoted. A leading UTF-8 BOM is dropped.
///
/// A field that starts with `"` is quoted: it runs to the next lone `"`,
/// `""` inside it is one quote, and a [separator] or line break inside it is
/// kept; the closing quote must end the field. A `"` inside an unquoted
/// field is kept as it is. Rows end at CRLF,
/// LF or CR; a line break at the end of [text] adds no empty row, and empty
/// [text] has no rows. Fields are never trimmed.
///
/// Throws [FormatException] on a quoted field with no closing quote or
/// with text after its closing quote (`"a"b`), and
/// [ArgumentError] when [separator] is not one character other than `"`,
/// CR or LF.
List<List<String>> parseCsv(String text, {required String separator}) {
  if (separator.length != 1 ||
      separator == '"' ||
      separator == '\r' ||
      separator == '\n') {
    throw ArgumentError.value(
      separator,
      'separator',
      'Must be one character other than a quote or a line break',
    );
  }
  final String source = text.startsWith(_bom) ? text.substring(1) : text;
  final List<List<String>> rows = <List<String>>[];
  if (source.isEmpty) return rows;
  List<String> row = <String>[];
  final StringBuffer field = StringBuffer();
  int i = 0;
  while (true) {
    // At the start of a field.
    if (i < source.length && source[i] == '"') {
      final int opened = i;
      i++;
      while (true) {
        if (i >= source.length) {
          throw FormatException('Unterminated quoted field', source, opened);
        }
        final String char = source[i];
        if (char == '"') {
          if (i + 1 < source.length && source[i + 1] == '"') {
            field.write('"');
            i += 2;
            continue;
          }
          i++;
          break;
        }
        field.write(char);
        i++;
      }
      if (i < source.length &&
          source[i] != separator &&
          source[i] != '\r' &&
          source[i] != '\n') {
        throw FormatException('Text after a closing quote', source, i);
      }
    }
    // The unquoted rest of the field, up to a separator or a line break.
    while (i < source.length &&
        source[i] != separator &&
        source[i] != '\r' &&
        source[i] != '\n') {
      field.write(source[i]);
      i++;
    }
    row.add(field.toString());
    field.clear();
    if (i >= source.length) {
      rows.add(row);
      return rows;
    }
    final String char = source[i];
    if (char == separator) {
      i++;
      continue;
    }
    // A line break: CRLF counts as one.
    i += char == '\r' && i + 1 < source.length && source[i + 1] == '\n' ? 2 : 1;
    rows.add(row);
    if (i >= source.length) return rows;
    row = <String>[];
  }
}

/// The separator of an oracle CSV [text]: `,` or `;`, read from its header
/// row, which must be exactly `value<sep>code<sep>case<sep>note` after an
/// optional BOM.
///
/// Throws [FormatException] on any other first row. The separator is never
/// guessed from counts: a code such as `0;-0;;@` or a decimal comma would
/// mislead a guess.
String oracleCsvSeparator(String text) {
  final String source = text.startsWith(_bom) ? text.substring(1) : text;
  for (final String separator in const <String>[',', ';']) {
    final String header = _headers.join(separator);
    if (!source.startsWith(header)) continue;
    final String rest = source.substring(header.length);
    if (rest.isEmpty || rest.startsWith('\r') || rest.startsWith('\n')) {
      return separator;
    }
  }
  throw FormatException(
    'Expected the header row value,code,case,note (or with ;)',
    text,
    0,
  );
}

const List<String> _headers = <String>['value', 'code', 'case', 'note'];

/// Column A of each row of an oracle CSV [text], by its case id in column
/// C, without the header row.
///
/// The separator is [oracleCsvSeparator]'s. Throws [FormatException] on a
/// bad header, on a row with no case id (fewer than three fields, or an
/// empty column C) and on a case id that two rows hold.
Map<String, String> parseOracleCsv(String text) {
  final List<List<String>> rows = parseCsv(
    text,
    separator: oracleCsvSeparator(text),
  );
  final Map<String, String> values = <String, String>{};
  for (int i = 1; i < rows.length; i++) {
    final List<String> row = rows[i];
    if (row.length < 3 || row[2].isEmpty) {
      throw FormatException('Record $i has no case id in column C');
    }
    if (values.containsKey(row[2])) {
      throw FormatException('Record $i repeats case id ${row[2]}');
    }
    values[row[2]] = row[0];
  }
  return values;
}

/// The regions the oracle is run in, in report order.
const List<String> oracleRegions = <String>['en-US', 'de-DE', 'tr-TR'];

/// The [XlsxFormatLocale] a region's CSVs are compared with.
///
/// Throws [ArgumentError] for a region not in [oracleRegions].
XlsxFormatLocale oracleLocale(String region) => switch (region) {
  'en-US' => XlsxFormatLocale.enUS,
  'de-DE' => XlsxFormatLocale.deDE,
  'tr-TR' => XlsxFormatLocale.trTR,
  _ => throw ArgumentError.value(region, 'region', 'Not an oracle region'),
};

/// Whether [excel], the text Excel's CSV (or the owner's eye) gives for a
/// cell, is what [ours] shows.
///
/// Exact, with two tolerances for what a CSV cannot show as the cell does:
///
/// - When [ours] is an overflow (`#` across the cell), any non-empty run of
///   `#` matches: Excel writes `#` as many times as the column is wide.
/// - When [ours] has an [XlsxFormatFill], [excel] may hold zero or more of
///   the fill character where the fill stands, and the other parts exactly
///   (padding as one space).
bool oracleTextMatches(String excel, XlsxFormattedValue ours) {
  if (ours.overflow) return _allHashes.hasMatch(excel);
  if (!ours.parts.any((XlsxFormatPart p) => p is XlsxFormatFill)) {
    return excel == ours.text;
  }
  final StringBuffer pattern = StringBuffer('^');
  for (final XlsxFormatPart part in ours.parts) {
    pattern.write(switch (part) {
      XlsxFormatText(:final String text) => RegExp.escape(text),
      XlsxFormatPadding() => ' ',
      XlsxFormatFill(:final String char) => '(?:${RegExp.escape(char)})*',
    });
  }
  pattern.write(r'$');
  return RegExp(pattern.toString()).hasMatch(excel);
}

final RegExp _allHashes = RegExp(r'^#+$');

/// The error each manual formula of the case list shows, by its formula
/// as the case writes it: the case list says it only in its note.
const Map<String, String> _manualErrors = <String, String>{
  '=SEQUENCE(1,2)': '#SPILL!',
  '=FILTER(1,FALSE)': '#CALC!',
};

/// What [compareOracle] found for one [OracleCase].
sealed class OracleOutcome {
  const OracleOutcome(this.kase);

  /// The case compared.
  final OracleCase kase;
}

/// The application showed [text], and the formatter's result matches it.
final class OracleMatch extends OracleOutcome {
  /// Creates a match of [kase], whose CSV or eye text is [text].
  const OracleMatch(super.kase, this.text);

  /// The application's text.
  final String text;

  @override
  String toString() => 'OracleMatch(${kase.id}, «$text»)';
}

/// The application shows [expected] and the formatter [actual].
final class OracleMismatch extends OracleOutcome {
  /// Creates a mismatch of [kase].
  const OracleMismatch(super.kase, this.expected, this.actual);

  /// The application's text.
  final String expected;

  /// The formatter's text.
  final String actual;

  @override
  String toString() =>
      'OracleMismatch(${kase.id}, excel=«$expected», ours=«$actual»)';
}

/// An eye-only case with no eye text, or a manual formula whose error is
/// not known: not compared; [OracleCase.note] says what to look at.
final class OracleByEye extends OracleOutcome {
  /// Creates a by-eye outcome of [kase].
  const OracleByEye(super.kase);

  @override
  String toString() => 'OracleByEye(${kase.id})';
}

/// The CSV has no row for the case: the application stopped early or the
/// case list changed after the run.
final class OracleMissingRow extends OracleOutcome {
  /// Creates a missing-row outcome of [kase].
  const OracleMissingRow(super.kase);

  @override
  String toString() => 'OracleMissingRow(${kase.id})';
}

/// Compares each case of [workbook] (a key of [OracleCases.workbooks]),
/// in case order, with [csv] (case id to column A, [parseOracleCsv]) or,
/// for an eye-only case, with [eye] (case id to the text the owner saw).
///
/// Each case is formatted by an `XlsxNumberFormatter` of [locale] in the
/// case's date system: a code as `numberFormat`; a built-in id as
/// `numberFormatId`, with the workbook's [OracleWorkbook.numFmts] code for
/// it as `numberFormat`, as the reader passes them; a manual formula as the
/// error it shows; `General` at the default width of 11. The texts match by
/// [oracleTextMatches].
///
/// A case whose id [csv] lacks is [OracleMissingRow]. An eye-only case
/// without [eye] text, or a manual formula of no known error, is
/// [OracleByEye]. Throws [ArgumentError] when [workbook] is not a key of
/// [cases].
List<OracleOutcome> compareOracle(
  OracleCases cases,
  String workbook,
  XlsxFormatLocale locale, {
  required Map<String, String> csv,
  Map<String, String> eye = const <String, String>{},
}) {
  final OracleWorkbook? book = cases.workbooks[workbook];
  if (book == null) {
    throw ArgumentError.value(workbook, 'workbook', 'Not a workbook key');
  }
  final Map<bool, XlsxNumberFormatter> formatters = <bool, XlsxNumberFormatter>{
    false: XlsxNumberFormatter(locale: locale),
    true: XlsxNumberFormatter(locale: locale, date1904: true),
  };
  return <OracleOutcome>[
    for (final OracleCase kase in cases.cases)
      if (kase.workbook == workbook)
        _compareCase(
          kase,
          book,
          formatters[kase.date1904]!,
          kase.eyeOnly ? eye[kase.id] : csv[kase.id],
        ),
  ];
}

OracleOutcome _compareCase(
  OracleCase kase,
  OracleWorkbook book,
  XlsxNumberFormatter formatter,
  String? expected,
) {
  if (expected == null) {
    return kase.eyeOnly ? OracleByEye(kase) : OracleMissingRow(kase);
  }
  final Object value;
  switch (kase.value) {
    case OracleNumber(:final String digits):
      value = XlsxDecimal(digits);
    case OracleBool(value: final bool b):
      value = b;
    case OracleText(:final String text):
      value = text;
    case OracleManual(:final String formula):
      final String? error = _manualErrors[formula];
      if (error == null) return OracleByEye(kase);
      value = XlsxErrorValue(error);
  }
  final int? id = kase.builtinId;
  final XlsxFormattedValue ours = formatter.format(
    value,
    numberFormatId: id ?? 0,
    numberFormat: id == null ? kase.code : book.numFmts[id],
    generalWidth: 11,
  );
  return oracleTextMatches(expected, ours)
      ? OracleMatch(kase, expected)
      : OracleMismatch(kase, expected, ours.text);
}

/// One line per mismatch, by-eye case and missing row
/// (`id  code  value  excel=«..»  ours=«..»`), then the counts per outcome
/// kind.
///
/// The first line is `number format oracle: <label>` and the last
/// `match <n>, mismatch <n>, by eye <n>, missing row <n>`. A missing row
/// ends in `missing row` and a by-eye case in `by eye: <note>` instead of
/// the two texts. A built-in id shows as `builtin <id>`, a text value in
/// quotes and a manual value as its formula.
String oracleReport(String label, List<OracleOutcome> outcomes) {
  final StringBuffer out = StringBuffer('number format oracle: $label\n');
  int matches = 0;
  int mismatches = 0;
  int byEye = 0;
  int missing = 0;
  for (final OracleOutcome outcome in outcomes) {
    final OracleCase kase = outcome.kase;
    final String head =
        '${kase.id}  ${kase.code ?? 'builtin ${kase.builtinId}'}  '
        '${_describeValue(kase.value)}';
    switch (outcome) {
      case OracleMatch():
        matches++;
      case OracleMismatch(:final String expected, :final String actual):
        mismatches++;
        out.writeln('$head  excel=«$expected»  ours=«$actual»');
      case OracleByEye():
        byEye++;
        out.writeln('$head  by eye: ${kase.note}');
      case OracleMissingRow():
        missing++;
        out.writeln('$head  missing row');
    }
  }
  out.write(
    'match $matches, mismatch $mismatches, by eye $byEye, '
    'missing row $missing',
  );
  return out.toString();
}

String _describeValue(OracleValue value) => switch (value) {
  OracleNumber(:final String digits) => digits,
  OracleBool(value: final bool b) => '$b',
  OracleText(:final String text) => '"$text"',
  OracleManual(:final String formula) => formula,
};

/// One region's run of the oracle, as `manifest.json` records it (format in
/// `test/fixtures/owner/number_format/README.md`).
final class OracleManifestEntry {
  /// Creates an entry.
  const OracleManifestEntry({
    required this.region,
    required this.appleLocale,
    required this.excelLanguage,
    required this.excel,
    required this.macos,
    required this.confirmedBy,
    required this.csv,
    required this.eye,
    required this.notes,
  });

  /// One of [oracleRegions]: the locale the CSVs are compared with.
  final String region;

  /// What `defaults read -g AppleLocale` printed, such as `de_DE`.
  final String appleLocale;

  /// Excel's language in the run.
  final String excelLanguage;

  /// Excel's name, version and build.
  final String excel;

  /// The macOS version.
  final String macos;

  /// Always `owner`.
  final String confirmedBy;

  /// Workbook file to CSV file, for each workbook run in the region.
  final Map<String, String> csv;

  /// Eye-only case id to the text the cell showed.
  final Map<String, String> eye;

  /// What Excel said or did, or empty.
  final String notes;
}

/// Parses `manifest.json` [text]: a list of [OracleManifestEntry].
///
/// Every field must be present, and no other. `region` must be one of
/// [oracleRegions], at most once in the list; `confirmedBy` exactly
/// `owner`; each `csv` key a workbook file name (`<stem>.xlsx`, no `/`)
/// and its value `<stem>.<region>.csv`; `eye` values strings. Whether the
/// CSV files exist and the keys name real workbooks and cases is for the
/// caller, which has the files and the case list. Throws a
/// [FormatException] whose message starts with the path of the first
/// problem, such as `[0].region:`.
List<OracleManifestEntry> parseOracleManifest(String text) {
  final Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException catch (e) {
    throw FormatException(r'$: not JSON: ' + e.message);
  }
  if (root is! List<Object?>) _fail(r'$', 'expected a list');
  final Set<String> regions = <String>{};
  final List<OracleManifestEntry> entries = <OracleManifestEntry>[];
  for (int i = 0; i < root.length; i++) {
    final String path = '[$i]';
    final Object? raw = root[i];
    if (raw is! Map<String, Object?>) _fail(path, 'expected an object');
    final Set<String> extra = raw.keys.toSet().difference(_manifestKeys);
    if (extra.isNotEmpty) _fail(path, 'unknown field ${extra.first}');
    String string(String key) {
      final Object? value = raw[key];
      if (value is! String) _fail('$path.$key', 'expected a string');
      return value;
    }

    final String region = string('region');
    if (!oracleRegions.contains(region)) {
      _fail('$path.region', 'expected one of ${oracleRegions.join(', ')}');
    }
    if (!regions.add(region)) _fail('$path.region', 'repeats $region');
    final String confirmedBy = string('confirmedBy');
    if (confirmedBy != 'owner') _fail('$path.confirmedBy', 'expected owner');
    final Map<String, String> csv = _stringMap(raw['csv'], '$path.csv');
    for (final MapEntry<String, String> e in csv.entries) {
      final String key = e.key;
      if (!key.endsWith('.xlsx') || key.contains('/') || key == '.xlsx') {
        _fail('$path.csv.$key', 'expected a workbook file name');
      }
      final String want = '${key.substring(0, key.length - 5)}.$region.csv';
      if (e.value != want) _fail('$path.csv.$key', 'expected $want');
    }
    entries.add(
      OracleManifestEntry(
        region: region,
        appleLocale: string('appleLocale'),
        excelLanguage: string('excelLanguage'),
        excel: string('excel'),
        macos: string('macos'),
        confirmedBy: confirmedBy,
        csv: csv,
        eye: _stringMap(raw['eye'], '$path.eye'),
        notes: string('notes'),
      ),
    );
  }
  return entries;
}

const Set<String> _manifestKeys = <String>{
  'region',
  'appleLocale',
  'excelLanguage',
  'excel',
  'macos',
  'confirmedBy',
  'csv',
  'eye',
  'notes',
};

Map<String, String> _stringMap(Object? raw, String path) {
  if (raw is! Map<String, Object?>) _fail(path, 'expected an object');
  return <String, String>{
    for (final MapEntry<String, Object?> e in raw.entries)
      e.key: switch (e.value) {
        final String s => s,
        _ => _fail('$path.${e.key}', 'expected a string'),
      },
  };
}

Never _fail(String path, String message) =>
    throw FormatException('$path: $message');
