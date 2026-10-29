/// Test helper: compare `XlsxNumberFormatter` with a spreadsheet
/// application's CSV of the same cases.
///
/// New in jet_office. Shared by the oracle test, which reads the owner's
/// Excel for Mac CSVs, and the LibreOffice tool, which reads LibreOffice's
/// CSV exported "as shown". [parseCsv] reads either CSV with the
/// separator the caller names ([defaultCsvSeparator] when the file set
/// says none), [compareOracle]
/// formats each [OracleCase] and compares it with its row, and
/// [oracleReport] prints the outcomes.
///
/// Pure Dart with no `dart:io`, so its tests run in a browser too: the
/// caller reads the files.
///
/// Excel for Mac's "CSV UTF-8" starts with a byte order mark, ends lines
/// with CRLF and, in a locale whose decimal separator is a comma (de-DE,
/// tr-TR), separates fields with `;`; LibreOffice uses `,` and LF. Texts
/// are compared exactly: the trailing space of `_)` padding is part of what
/// Excel shows, so neither side is trimmed.
library;

import 'package:jet_office/jet_office.dart';

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

/// The field separator assumed for [locale]'s CSV when the file set
/// names none: `,` for en-US, `;` for de-DE and tr-TR, chosen by
/// [XlsxFormatLocale.lcid].
///
/// An assumption, to be confirmed by the owner's files: Excel for Mac
/// takes the separator from the system's list separator, which is `;`
/// where the decimal separator is a comma. The separator is never guessed
/// from the text, since an unquoted code such as `0;-0;;@` or a decimal
/// comma would mislead any guess. Throws [ArgumentError] for a locale
/// other than these three.
String defaultCsvSeparator(XlsxFormatLocale locale) => switch (locale.lcid) {
  0x409 => ',',
  0x407 || 0x41F => ';',
  _ => throw ArgumentError.value(
    locale.lcid,
    'locale.lcid',
    'No CSV separator is known for this locale',
  ),
};

/// One value formatted with one number format, and the CSV row that holds
/// what the application showed for it.
final class OracleCase {
  /// Creates a case; [code] or [builtinId] (or both) names the format.
  ///
  /// Throws [ArgumentError] when both are null.
  OracleCase({
    required this.id,
    required this.row,
    required this.value,
    this.code,
    this.builtinId,
    this.date1904 = false,
    this.byEye,
  }) {
    if (code == null && builtinId == null) {
      throw ArgumentError('Case $id needs a code or a builtinId');
    }
  }

  /// The stable case id from the case file.
  final String id;

  /// The 0-based index of the CSV record holding this case, as [parseCsv]
  /// returns the records: a line break inside a quoted field does not
  /// start a new record, so this can differ from the file's line number.
  final int row;

  /// The number format code as written, or null for [builtinId] alone.
  final String? code;

  /// The built-in number format id, passed as `numberFormatId`.
  final int? builtinId;

  /// The value: an [XlsxDecimal], a [bool], a [String], an
  /// [XlsxErrorValue] or anything else `XlsxNumberFormatter.format` takes.
  final Object? value;

  /// Whether the case is formatted in the 1904 date system.
  final bool date1904;

  /// Why a CSV cannot show this case (a colour, a fill), so it is checked
  /// by eye and not compared; null when it is compared.
  final String? byEye;

  @override
  String toString() => 'OracleCase($id)';
}

/// What [compareOracle] found for one [OracleCase].
sealed class OracleOutcome {
  const OracleOutcome(this.kase);

  /// The case compared.
  final OracleCase kase;
}

/// The formatter showed exactly [text], as the CSV does.
final class OracleMatch extends OracleOutcome {
  /// Creates a match of [kase] showing [text].
  const OracleMatch(super.kase, this.text);

  /// The text both show.
  final String text;

  @override
  String toString() => 'OracleMatch(${kase.id}, «$text»)';
}

/// The CSV shows [expected] and the formatter [actual].
final class OracleMismatch extends OracleOutcome {
  /// Creates a mismatch of [kase].
  const OracleMismatch(super.kase, this.expected, this.actual);

  /// The CSV's text: what the application showed.
  final String expected;

  /// The formatter's text.
  final String actual;

  @override
  String toString() =>
      'OracleMismatch(${kase.id}, excel=«$expected», ours=«$actual»)';
}

/// The case is checked by eye ([OracleCase.byEye]) and was not compared.
final class OracleByEye extends OracleOutcome {
  /// Creates a by-eye outcome of [kase].
  const OracleByEye(super.kase);

  @override
  String toString() => 'OracleByEye(${kase.id})';
}

/// The CSV has no row [OracleCase.row], or the row has no such column.
final class OracleMissingRow extends OracleOutcome {
  /// Creates a missing-row outcome of [kase].
  const OracleMissingRow(super.kase);

  @override
  String toString() => 'OracleMissingRow(${kase.id})';
}

/// Formats each case with an `XlsxNumberFormatter(locale:, date1904:)`
/// and compares `text` with column [column] of its CSV row, exact string.
///
/// Returns one outcome per case, in the order of [cases]. A by-eye case is
/// [OracleByEye] without being formatted. A case whose row is past the end
/// of [rows], or whose row is shorter than [column] + 1, is
/// [OracleMissingRow], so a CSV the application stopped writing early fails
/// on every case it lacks.
List<OracleOutcome> compareOracle(
  List<OracleCase> cases,
  List<List<String>> rows,
  XlsxFormatLocale locale, {
  int column = 0,
}) {
  final XlsxNumberFormatter formatter1900 = XlsxNumberFormatter(locale: locale);
  final XlsxNumberFormatter formatter1904 = XlsxNumberFormatter(
    locale: locale,
    date1904: true,
  );
  return <OracleOutcome>[
    for (final OracleCase kase in cases)
      if (kase.byEye != null)
        OracleByEye(kase)
      else if (kase.row < 0 ||
          kase.row >= rows.length ||
          column >= rows[kase.row].length)
        OracleMissingRow(kase)
      else
        _compare(
          kase,
          rows[kase.row][column],
          (kase.date1904 ? formatter1904 : formatter1900)
              .format(
                kase.value,
                numberFormatId: kase.builtinId ?? 0,
                numberFormat: kase.code,
              )
              .text,
        ),
  ];
}

OracleOutcome _compare(OracleCase kase, String expected, String actual) =>
    expected == actual
    ? OracleMatch(kase, actual)
    : OracleMismatch(kase, expected, actual);

/// One line per mismatch, by-eye case and missing row
/// (`id  code  value  excel=«..»  ours=«..»`), then the counts per outcome
/// kind.
///
/// The first line names [label] (the locale or the CSV), and the last is
/// `match <n>, mismatch <n>, by eye <n>, missing row <n>`. A missing row
/// ends in `missing row` and a by-eye case in `by eye: <reason>` instead
/// of the two texts. A case with no code
/// shows `builtin <id>` for it.
String oracleReport(String label, List<OracleOutcome> outcomes) {
  final StringBuffer out = StringBuffer('number format oracle: $label\n');
  int matches = 0;
  int mismatches = 0;
  int byEye = 0;
  int missing = 0;
  for (final OracleOutcome outcome in outcomes) {
    final OracleCase kase = outcome.kase;
    final String head =
        '${kase.id}  ${_describeCode(kase)}  ${_describeValue(kase.value)}';
    switch (outcome) {
      case OracleMatch():
        matches++;
      case OracleMismatch(:final String expected, :final String actual):
        mismatches++;
        out.writeln('$head  excel=«$expected»  ours=«$actual»');
      case OracleByEye():
        byEye++;
        out.writeln('$head  by eye: ${kase.byEye}');
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

String _describeCode(OracleCase kase) {
  final String? code = kase.code;
  final int? id = kase.builtinId;
  if (code == null) return 'builtin $id';
  return id == null ? code : '$code (builtin $id)';
}

String _describeValue(Object? value) => switch (value) {
  XlsxDecimal(:final String digits) => digits,
  XlsxErrorValue(:final String code) => code,
  String() => '"$value"',
  DateTime() => value.toIso8601String(),
  _ => '$value',
};
