import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import 'support/feature_fuzz.dart';

/// The seeds the quality gate fuzzes, each with [_cases] cases.
const List<int> _seeds = <int>[1, 2, 3, 4];

/// The cases per seed in the quality gate.
const int _cases = 100;

/// Adler-32 of the first [_cases] cases of each of [_seeds]: their
/// descriptions and bytes' lengths, computed once on the VM. The Chrome leg
/// compares it, which proves a seed gives the same cases in a browser. A
/// changed `m3_*` or `m4_*` fixture changes it.
const int _casesDigest = 3657917492;

/// Adler-32 of [data], in arithmetic that stays exact in a browser.
int _adler32(List<int> data) {
  int a = 1;
  int b = 0;
  for (final int byte in data) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  return b * 65536 + a;
}

void main() {
  test('a seed gives the same cases everywhere', () {
    final StringBuffer all = StringBuffer();
    for (final int seed in _seeds) {
      for (final FuzzCase c in featureFuzzCases(seed, _cases)) {
        all.writeln('${c.mutation} ${c.bytes.length}');
      }
    }
    expect(_adler32(utf8.encode(all.toString())), _casesDigest);
  });

  test('the cases reach every feature part of the corpus', () {
    final Set<String> mutated = <String>{
      for (final int seed in _seeds)
        for (final FuzzCase c in featureFuzzCases(seed, _cases))
          ?mutatedPart(c.mutation),
    };
    expect(
      mutated,
      containsAll(<String>[
        'xl/workbook.xml',
        'xl/styles.xml',
        'xl/worksheets/sheet1.xml',
        'xl/worksheets/_rels/sheet1.xml.rels',
        'docProps/core.xml',
        'docProps/app.xml',
        'docProps/custom.xml',
        'xl/sharedStrings.xml',
        'xl/comments1.xml',
        'xl/drawings/drawing1.xml',
        'xl/drawings/vmlDrawing1.vml',
        'xl/drawings/_rels/drawing1.xml.rels',
        'xl/tables/table1.xml',
      ]),
    );
  });

  test('every corpus entry exercises cleanly', () {
    for (final ({String name, Uint8List bytes}) entry in featureCorpus()) {
      expect(() => exerciseFeatures(entry.bytes), returnsNormally);
    }
  });

  test('undo restores every corpus entry', () {
    for (final ({String name, Uint8List bytes}) entry in featureCorpus()) {
      expect(
        () => exerciseFeatures(entry.bytes, proveUndo: true),
        returnsNormally,
        reason: entry.name,
      );
    }
  });

  test('mutated files raise only XlsxReadException', () {
    final List<String> failures = <String>[];
    for (final int seed in _seeds) {
      for (final FuzzCase c in featureFuzzCases(seed, _cases)) {
        final Stopwatch watch = Stopwatch()..start();
        try {
          exerciseFeatureCase(c);
        } on XlsxReadException {
          // A file problem, reported as the model promises.
        } on Object catch (e) {
          failures.add('seed ${c.seed} case ${c.index} (${c.mutation}): $e');
        }
        if (watch.elapsed > const Duration(seconds: 5)) {
          failures.add(
            'seed ${c.seed} case ${c.index} (${c.mutation}): hang, '
            '${watch.elapsedMilliseconds} ms',
          );
        }
      }
    }
    expect(failures, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
