/// Checks the owner's Excel results of the axis oracle
/// (`test/fixtures/owner/axis/`, README there), region by region.
///
/// A region without a manifest entry is unverified: it prints so and passes,
/// so the gate is green before the owner's run. A region with one requires
/// its CSV to exist and to have no problems ([readAxisCsv]). One region's run
/// answers the question; the others may stay unverified. VM only: it reads
/// files from disk.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/axis_oracle.dart';
import 'tool/support/axis_cases.dart';

const String _folder = 'test/fixtures/owner/axis';

void main() {
  test('cases.json is the case list the tool tests use', () {
    expect(
      jsonDecode(File('$_folder/cases.json').readAsStringSync()),
      axisCasesDocument(),
    );
  });

  group('a manifest entry gets the check of its CSV', () {
    // Hand-made rows and entry, not Excel's: they exercise the check.
    final AxisOracleCases cases = parseAxisCases(
      File('$_folder/cases.json').readAsStringSync(),
    );
    const AxisManifestEntry entry = AxisManifestEntry(
      region: 'tr-TR',
      appleLocale: 'hand-made',
      excelLanguage: 'hand-made',
      excel: 'hand-made',
      macos: 'hand-made',
      confirmedBy: 'owner',
      csv: 'axis_oracle.tr-TR.csv',
      notes: '',
    );
    final String good = <String>[
      axisCsvHeader,
      for (final AxisCase kase in cases.cases)
        '${kase.id},${kase.height},${kase.font},0,10,2',
    ].join('\n');

    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('axis_oracle'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a good CSV has no problems', () {
      File('${dir.path}/${entry.csv}').writeAsStringSync(good);
      expect(_regionProblems(dir.path, cases, entry), isEmpty);
    });

    test('a bad CSV has', () {
      File('${dir.path}/${entry.csv}').writeAsStringSync(axisCsvHeader);
      expect(_regionProblems(dir.path, cases, entry), hasLength(60));
    });

    test('a missing CSV is a problem', () {
      expect(_regionProblems(dir.path, cases, entry), hasLength(1));
    });
  });

  defineAxisOracleTests(_folder);
}

/// Defines the oracle's tests for the case list, manifest and CSVs in
/// [folder] (`cases.json`, `manifest.json`, `axis_oracle.<region>.csv`).
void defineAxisOracleTests(String folder) {
  final AxisOracleCases cases = parseAxisCases(
    File('$folder/cases.json').readAsStringSync(),
  );
  final List<AxisManifestEntry> manifest = parseAxisManifest(
    File('$folder/manifest.json').readAsStringSync(),
  );
  for (final String region in axisOracleRegions) {
    final AxisManifestEntry? entry = manifest
        .where((AxisManifestEntry e) => e.region == region)
        .firstOrNull;
    if (entry == null) {
      test('$region unverified', () {
        // ignore: avoid_print
        print('axis oracle: $region unverified');
      });
      continue;
    }
    test('$region results are well formed', () {
      expect(_regionProblems(folder, cases, entry), isEmpty);
    });
  }
}

List<String> _regionProblems(
  String folder,
  AxisOracleCases cases,
  AxisManifestEntry entry,
) {
  final File file = File('$folder/${entry.csv}');
  if (!file.existsSync()) return <String>['${entry.csv} does not exist'];
  return readAxisCsv(cases, file.readAsStringSync()).problems;
}
