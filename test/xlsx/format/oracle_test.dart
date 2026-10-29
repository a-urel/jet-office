/// Compares `XlsxNumberFormatter` with what Excel for Mac showed for each
/// case of the number format oracle, region by region
/// (`test/fixtures/owner/number_format/`, README there).
///
/// A region without a manifest entry is unverified: it prints so and adds
/// no failing test, so the gate is green before the owner's run. A region
/// with one gets a test per case of each workbook it ran (`<id> <region>`)
/// that requires a match ([compareOracle]); an eye-only case without eye
/// text, a case of a workbook not run in the region and a case in
/// [knownDifferences] are skipped with their reason. Excel wins (decision
/// 0008): a mismatch is fixed in the formatter with a test, or recorded in
/// [knownDifferences] with the ruling's reason. VM only: it reads files
/// from disk.
@TestOn('vm')
library;

import 'dart:io';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../../tool/src/format_oracle.dart';
import '../../../tool/src/format_oracle_compare.dart';

/// Cases where the formatter knowingly differs from Excel, by
/// `<case id> <region>`, with the reason (the ruling in the N3 ledger).
const Map<String, String> knownDifferences = <String, String>{};

void main() => defineOracleTests('test/fixtures/owner/number_format');

/// Defines the oracle tests for the case list, manifest and CSVs in
/// [folder] (`cases.json`, `manifest.json`, `<workbook>.<region>.csv`).
void defineOracleTests(
  String folder, {
  Map<String, String> known = knownDifferences,
}) {
  final OracleCases cases = parseOracleCases(
    File('$folder/cases.json').readAsStringSync(),
  );
  final List<OracleManifestEntry> manifest = parseOracleManifest(
    File('$folder/manifest.json').readAsStringSync(),
  );
  for (final String region in oracleRegions) {
    final OracleManifestEntry? entry = manifest
        .where((OracleManifestEntry e) => e.region == region)
        .firstOrNull;
    if (entry == null) {
      test('$region unverified', () {
        // ignore: avoid_print
        print('number format oracle: $region unverified');
      });
      continue;
    }
    _defineRegion(folder, cases, entry, known);
  }
}

void _defineRegion(
  String folder,
  OracleCases cases,
  OracleManifestEntry entry,
  Map<String, String> known,
) {
  final String region = entry.region;
  final XlsxFormatLocale locale = oracleLocale(region);
  final Map<String, OracleWorkbook> byFile = <String, OracleWorkbook>{
    for (final OracleWorkbook book in cases.workbooks.values) book.file: book,
  };

  test('$region manifest entry names real workbooks, CSVs and cases', () {
    for (final MapEntry<String, String> e in entry.csv.entries) {
      expect(byFile, contains(e.key), reason: 'workbook ${e.key}');
      expect(
        File('$folder/${e.value}').existsSync(),
        isTrue,
        reason: 'CSV ${e.value}',
      );
    }
    if (region == 'en-US') {
      expect(
        entry.csv,
        contains(cases.workbooks['invalid']!.file),
        reason: 'en-US runs the invalid workbook',
      );
    }
    final Set<String> eyeIds = <String>{
      for (final OracleCase kase in cases.cases)
        if (kase.eyeOnly && entry.csv.containsKey(_file(cases, kase))) kase.id,
    };
    expect(
      entry.eye.keys.where((String id) => !eyeIds.contains(id)),
      isEmpty,
      reason: 'eye texts for no eye-only case of a workbook run',
    );
  });

  for (final OracleWorkbook book in cases.workbooks.values) {
    final String? csvName = entry.csv[book.file];
    final List<OracleCase> ofBook = <OracleCase>[
      for (final OracleCase kase in cases.cases)
        if (kase.workbook == book.key) kase,
    ];
    if (csvName == null) {
      for (final OracleCase kase in ofBook) {
        test(
          '${kase.id} $region',
          () {},
          skip: '${book.file} not run in $region',
        );
      }
      continue;
    }
    final Map<String, String> csv;
    try {
      csv = parseOracleCsv(File('$folder/$csvName').readAsStringSync());
    } on Object catch (error) {
      test('$csvName reads', () => fail('$error'));
      continue;
    }
    final List<OracleOutcome> outcomes = compareOracle(
      cases,
      book.key,
      locale,
      csv: csv,
      eye: entry.eye,
    );

    test('$csvName holds only cases of ${book.file}', () {
      // ignore: avoid_print
      print(oracleReport('$region ${book.file}', outcomes));
      final Set<String> ids = <String>{
        for (final OracleCase kase in ofBook)
          if (!kase.eyeOnly) kase.id,
      };
      expect(csv.keys.where((String id) => !ids.contains(id)), isEmpty);
    });

    for (final OracleOutcome outcome in outcomes) {
      final String name = '${outcome.kase.id} $region';
      test(
        name,
        () => expect(outcome, isA<OracleMatch>(), reason: '$outcome'),
        skip:
            known[name] ??
            (outcome is OracleByEye ? 'by eye: ${outcome.kase.note}' : null),
      );
    }
  }
}

String _file(OracleCases cases, OracleCase kase) =>
    cases.workbooks[kase.workbook]!.file;
