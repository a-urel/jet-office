import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_office/src/drawingml/chart/chart_reader.dart';
import 'package:test/test.dart';

import 'support/chart_fuzz.dart';

/// The seeds the quality gate fuzzes, each with [_cases] cases.
const List<int> _seeds = <int>[1, 2, 3, 4];

/// The cases per seed in the quality gate.
const int _cases = 100;

/// Adler-32 of the first [_cases] cases of each of [_seeds]: their
/// descriptions and the Adler-32 of their bytes, computed once on the VM. The
/// Chrome leg compares it, which proves a seed gives the same cases in a
/// browser. A change to the writer, to the C1 fixtures' charts or to the
/// mutations changes it.
const int _casesDigest = 81417766;

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
  test('the corpus holds the Excel charts and every C1 chart', () {
    final List<String> names = <String>[
      for (final ({String name, Uint8List bytes}) e in chartFuzzCorpus())
        e.name,
    ];
    expect(names, <String>[
      'excel_column',
      'excel_line',
      for (int i = 1; i <= 12; i++) 'c1_kinds_chart$i',
      for (int i = 1; i <= 6; i++) 'c1_options_chart$i',
    ]);
  });

  test('every corpus entry reads typed in its theme and exercises cleanly', () {
    for (final ({String name, Uint8List bytes}) entry in chartFuzzCorpus()) {
      final DrawingChartRead read = readDrawingChartSpace(
        entry.bytes,
        theme: chartFuzzTheme(entry.name),
      );
      expect(read.typed, isNotNull, reason: entry.name);
      expect(() => exerciseChart(entry.bytes, entry.name), returnsNormally);
    }
  });

  test('the Excel charts are read in the Office theme', () {
    expect(chartFuzzTheme('excel_column'), ChartTheme.office);
    expect(() => chartFuzzTheme('nope'), throwsArgumentError);
  });

  test('a seed gives the same cases every time', () {
    final List<FuzzCase> first = chartFuzzCases(3, 20).toList();
    final List<FuzzCase> second = chartFuzzCases(3, 20).toList();
    for (int i = 0; i < first.length; i++) {
      expect(second[i].index, i);
      expect(second[i].mutation, first[i].mutation);
      expect(second[i].bytes, first[i].bytes, reason: first[i].mutation);
    }
  });

  test('a seed gives the same cases everywhere', () {
    final StringBuffer all = StringBuffer();
    for (final int seed in _seeds) {
      for (final FuzzCase c in chartFuzzCases(seed, _cases)) {
        all.writeln('${c.mutation} ${_adler32(c.bytes)}');
      }
    }
    expect(_adler32(utf8.encode(all.toString())), _casesDigest);
  });

  test('the cases use every mutation and replace each value', () {
    final List<String> mutations = <String>[
      for (final int seed in _seeds)
        for (final FuzzCase c in chartFuzzCases(seed, _cases)) c.mutation,
    ];
    for (final String operation in <String>[
      'flip bits',
      'overwrite 4 bytes',
      'truncate',
      'delete',
      'duplicate',
      'insert',
      'replace digit',
      'replace text',
    ]) {
      expect(
        mutations.any((String m) => m.contains(': $operation')),
        isTrue,
        reason: operation,
      );
    }
    for (final String value in <String>[
      'abc',
      '99999999999999999999',
      '-',
      'NaN',
      '1e999',
    ]) {
      expect(
        mutations.any(
          (String m) =>
              RegExp(r': replace [\w:]+ at \d+ with ').hasMatch(m) &&
              m.endsWith('with "$value"'),
        ),
        isTrue,
        reason: value,
      );
    }
  });

  test('a case is checked in the theme of the entry its description names', () {
    expect(
      () => exerciseChartCase((
        seed: 0,
        index: 0,
        mutation: 'excel_column: none',
        bytes: Uint8List(0),
      )),
      returnsNormally,
    );
    expect(
      () => exerciseChartCase((
        seed: 0,
        index: 0,
        mutation: 'nope: none',
        bytes: Uint8List(0),
      )),
      throwsArgumentError,
    );
  });

  test('some mutated parts still read typed, some as a view only', () {
    int typed = 0;
    int view = 0;
    for (final int seed in _seeds) {
      for (final FuzzCase c in chartFuzzCases(seed, _cases)) {
        final String entry = c.mutation.substring(0, c.mutation.indexOf(':'));
        final DrawingChartRead read = readDrawingChartSpace(
          c.bytes,
          theme: chartFuzzTheme(entry),
        );
        if (read.typed != null) {
          typed++;
        } else if (read.chart != null) {
          view++;
        }
      }
    }
    expect(typed, greaterThan(20));
    expect(view, greaterThan(20));
  });

  for (final int seed in _seeds) {
    test('seed $seed: $_cases mutated parts read without a throw, a typed '
        'form writes a part that reads typed again, and an opened part '
        'encodes its bytes', () {
      final List<String> failures = <String>[];
      for (final FuzzCase c in chartFuzzCases(seed, _cases)) {
        final Stopwatch watch = Stopwatch()..start();
        try {
          exerciseChartCase(c);
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
      expect(failures, isEmpty, reason: failures.take(3).join('\n'));
    });
  }
}
