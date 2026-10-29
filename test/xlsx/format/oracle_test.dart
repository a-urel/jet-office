/// Compares `XlsxNumberFormatter` with what Excel for Mac showed for each
/// case of the number format oracle, region by region
/// (`test/fixtures/owner/number_format/`, README there).
///
/// A region without a manifest entry is unverified: it prints so and adds
/// no failing test, so the gate is green before the owner's run. A region
/// with one gets a test per case of each workbook it ran (`<id> <region>`)
/// that requires a match ([compareOracle]); an eye-only case without eye
/// text, a case of a workbook not run in the region and a case in
/// [knownDifferences] are skipped with their reason; a known difference
/// that now matches fails, so the map does not go stale. Excel wins (decision
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
  test('knownDifferences name real cases and regions', () {
    expect(knownDifferenceProblems(known, cases), isEmpty);
  });
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

  test('$region manifest entry is complete and its CSVs exist', () {
    expect(oracleManifestProblems(entry, cases), isEmpty);
    for (final String csv in entry.csv.values) {
      expect(File('$folder/$csv').existsSync(), isTrue, reason: 'CSV $csv');
    }
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
      final String? reason = known[name];
      if (reason != null && outcome is OracleMatch) {
        test(name, () => fail('known difference now matches: remove it'));
        continue;
      }
      test(
        name,
        () => expect(outcome, isA<OracleMatch>(), reason: '$outcome'),
        // A known difference excuses a mismatch only: a missing row still
        // fails, so a stale entry cannot hide it.
        skip: reason != null && outcome is OracleMismatch
            ? reason
            : (outcome is OracleByEye ? 'by eye: ${outcome.kase.note}' : null),
      );
    }
  }
}
