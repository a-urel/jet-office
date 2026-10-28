import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import 'support/fuzz.dart';

/// The seeds the quality gate fuzzes, each with [_cases] cases.
const List<int> _seeds = <int>[1, 2, 3, 4];

/// The cases per seed in the quality gate.
const int _cases = 100;

void main() {
  test('Xorshift32 is the same everywhere', () {
    final Xorshift32 random = Xorshift32(1);
    expect(
      <int>[for (int i = 0; i < 5; i++) random.nextInt(1000000)],
      <int>[394312, 190024, 8529, 899417, 559219],
    );
  });

  test('Xorshift32 refuses a bound outside 1 to 2^32', () {
    expect(() => Xorshift32(1).nextInt(0), throwsRangeError);
    expect(() => Xorshift32(1).nextInt(0x100000001), throwsRangeError);
  });

  test('the corpus is identical on every run', () {
    final List<({String name, Uint8List bytes})> first = fuzzCorpus();
    final List<({String name, Uint8List bytes})> second = fuzzCorpus();
    expect(
      <String>[for (final c in first) c.name],
      <String>[
        'm1_values',
        'm1_formulas',
        'm1_dates',
        'libreoffice',
        'google_sheets',
        'dotnet_sdk',
        'erp_export',
        'm1_values_deflated',
        'libreoffice_deflated',
      ],
    );
    for (int i = 0; i < first.length; i++) {
      expect(second[i].bytes, first[i].bytes, reason: first[i].name);
      exerciseReader(first[i].bytes);
    }
  });

  test('a seed gives the same cases every time', () {
    final List<FuzzCase> first = fuzzCases(3, 20).toList();
    final List<FuzzCase> second = fuzzCases(3, 20).toList();
    for (int i = 0; i < first.length; i++) {
      expect(second[i].index, i);
      expect(second[i].mutation, first[i].mutation);
      expect(second[i].bytes, first[i].bytes, reason: first[i].mutation);
    }
  });

  test('cases touch every part', () {
    final Set<String> parts = <String>{
      for (final ({String name, Uint8List bytes}) entry in fuzzCorpus())
        ...corpusPartNames(entry.bytes),
    };
    final Set<String> mutated = <String>{
      for (final int seed in _seeds)
        for (final FuzzCase c in fuzzCases(seed, _cases))
          ?mutatedPart(c.mutation),
    };
    expect(parts.difference(mutated), isEmpty);
  });

  test('mutated files raise only XlsxReadException', () {
    final List<String> failures = <String>[];
    for (final int seed in _seeds) {
      for (final FuzzCase c in fuzzCases(seed, _cases)) {
        final Stopwatch watch = Stopwatch()..start();
        try {
          exerciseReader(c.bytes);
        } on XlsxReadException {
          // A file problem, reported as the reader promises.
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
