import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../support/event_loop.dart';
import 'support/fuzz.dart';

/// The seeds the quality gate fuzzes, each with [_cases] cases.
const List<int> _seeds = <int>[1, 2, 3, 4];

/// The cases per seed in the quality gate: enough that the fixed seeds
/// mutate every part name of the corpus (`every part name is mutated in some
/// corpus entry`). It was 100 until `c1_kinds` joined the corpus with its
/// twelve chart parts; 400 left `xl/charts/chart12.xml` unmutated.
const int _cases = 500;

/// The length and Adler-32 checksum of every stored corpus entry, computed
/// once on the VM. The Chrome leg compares them, which proves the corpus
/// (and so every seed's cases) is the same bytes in a browser. The two
/// `_deflated` entries are left out: their bytes depend on the platform's
/// deflater (decision 0006). The bytes are those of the `package:archive`
/// version resolved (4.6 added an extended timestamp to each central header),
/// so a release that changes its ZIP layout changes them.
const Map<String, ({int length, int adler32})> _storedCorpus =
    <String, ({int length, int adler32})>{
      'm1_values': (length: 6704, adler32: 3853013050),
      'm1_formulas': (length: 5599, adler32: 2780369878),
      'm1_dates': (length: 5963, adler32: 3931601365),
      'm2_style_precedence': (length: 7276, adler32: 148506124),
      'c1_kinds': (length: 120583, adler32: 1253100910),
      'libreoffice': (length: 17758, adler32: 3013262995),
      'google_sheets': (length: 10635, adler32: 3903365900),
      'dotnet_sdk': (length: 3072, adler32: 1661782054),
      'erp_export': (length: 4187, adler32: 3525780887),
      'excel_objects': (length: 20115, adler32: 263504902),
    };

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
        'm2_style_precedence',
        'c1_kinds',
        'libreoffice',
        'google_sheets',
        'dotnet_sdk',
        'erp_export',
        'excel_objects',
        'm1_values_deflated',
        'libreoffice_deflated',
      ],
    );
    for (int i = 0; i < first.length; i++) {
      expect(second[i].bytes, first[i].bytes, reason: first[i].name);
      exerciseReader(first[i].bytes);
    }
  });

  test('the stored corpus entries are the pinned bytes', () {
    final Set<String> seen = <String>{};
    for (final ({String name, Uint8List bytes}) entry in fuzzCorpus()) {
      if (entry.name.endsWith('_deflated')) continue;
      seen.add(entry.name);
      final ({int length, int adler32})? pinned = _storedCorpus[entry.name];
      expect(pinned, isNotNull, reason: entry.name);
      expect(entry.bytes.length, pinned!.length, reason: entry.name);
      expect(_adler32(entry.bytes), pinned.adler32, reason: entry.name);
    }
    expect(seen, _storedCorpus.keys.toSet());
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

  test('every part name is mutated in some corpus entry', () {
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

  test('mutated files raise only XlsxReadException', () async {
    final List<String> failures = <String>[];
    final EventLoopBreather breather = EventLoopBreather();
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
        // Chrome runs every suite on this thread: give the others a turn.
        await breather.breathe();
      }
    }
    expect(failures, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
