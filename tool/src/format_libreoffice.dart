/// The logic of `tool/compare_format_libreoffice.dart`: which CSV holds a
/// workbook's `cases` sheet, and the report over every workbook
/// LibreOffice exported.
///
/// New in jet_office (milestone N3 of decision 0008). LibreOffice is a
/// second opinion, not Excel: its differences are listed, never failed.
/// Pure Dart with no `dart:io`, so its tests run in a browser too.
library;

import 'package:jet_office/jet_office.dart';

import 'format_oracle.dart';
import 'format_oracle_compare.dart';

/// The name in [names] of LibreOffice's CSV of [workbookFile]'s `cases`
/// sheet, or `null` when there is none.
///
/// `<stem>-cases.csv` is what `soffice --convert-to` writes when the
/// filter's sheet token names sheet 1, and is preferred; `<stem>.csv`, what
/// it writes without that token (the first sheet, which is `cases`), is
/// taken otherwise.
String? libreOfficeCsvName(String workbookFile, Set<String> names) {
  final String stem = workbookFile.endsWith('.xlsx')
      ? workbookFile.substring(0, workbookFile.length - 5)
      : workbookFile;
  for (final String name in <String>['$stem-cases.csv', '$stem.csv']) {
    if (names.contains(name)) return name;
  }
  return null;
}

/// The [oracleReport] of each workbook of [cases] that [csv] (workbook key
/// to the CSV text) holds, labelled `LibreOffice <region> <file>`, in
/// workbook order, then a line
/// `total: match <n>, mismatch <n>, by eye <n>, missing row <n> (<n> workbooks)`.
///
/// Each workbook is compared in [region]'s locale ([oracleLocale]) with no
/// eye texts, so its eye-only cases are by eye.
///
/// Throws [FormatException], its message starting with the workbook file
/// name, when a CSV cannot be read ([parseOracleCsv]) or has no case rows;
/// [ArgumentError] when [region] is not an oracle region or a key of [csv]
/// is not a workbook key.
String libreOfficeReport(
  OracleCases cases,
  String region,
  Map<String, String> csv,
) {
  final XlsxFormatLocale locale = oracleLocale(region);
  for (final String key in csv.keys) {
    if (!cases.workbooks.containsKey(key)) {
      throw ArgumentError.value(key, 'csv', 'Not a workbook key');
    }
  }
  final List<String> reports = <String>[];
  int matches = 0;
  int mismatches = 0;
  int byEye = 0;
  int missing = 0;
  for (final OracleWorkbook book in cases.workbooks.values) {
    final String? text = csv[book.key];
    if (text == null) continue;
    final Map<String, String> rows;
    try {
      rows = parseOracleCsv(text);
    } on FormatException catch (e) {
      throw FormatException('${book.file}: ${e.message}');
    }
    if (rows.isEmpty) throw FormatException('${book.file}: no case rows');
    final List<OracleOutcome> outcomes = compareOracle(
      cases,
      book.key,
      locale,
      csv: rows,
    );
    for (final OracleOutcome outcome in outcomes) {
      switch (outcome) {
        case OracleMatch():
          matches++;
        case OracleMismatch():
          mismatches++;
        case OracleByEye():
          byEye++;
        case OracleMissingRow():
          missing++;
      }
    }
    reports.add(oracleReport('LibreOffice $region ${book.file}', outcomes));
  }
  final int n = reports.length;
  reports.add(
    'total: match $matches, mismatch $mismatches, by eye $byEye, '
    'missing row $missing ($n workbook${n == 1 ? '' : 's'})',
  );
  return reports.join('\n');
}
