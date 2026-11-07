import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import 'support/docx_fuzz.dart';

/// The seeds the quality gate fuzzes, each with [_cases] cases.
const List<int> _seeds = <int>[1, 2, 3, 4];

/// The cases per seed in the quality gate.
const int _cases = 400;

/// The length and Adler-32 checksum of every corpus entry, computed once on
/// the VM. The Chrome leg compares them, which proves the corpus (and so
/// every seed's cases) is the same bytes in a browser. Every entry is
/// rebuilt stored, so none depends on the platform's deflater (decision
/// 0006). The bytes are those of the `package:archive` version resolved, so
/// a release that changes its ZIP layout changes them.
const Map<String, ({int length, int adler32})> _corpus =
    <String, ({int length, int adler32})>{
      'word_like': (length: 8453, adler32: 2713099753),
      'localized_word': (length: 8747, adler32: 3839375278),
      'd1_blank': (length: 26844, adler32: 977744039),
      'd1_paragraphs': (length: 27133, adler32: 3186070677),
      'd1_text_rules': (length: 27528, adler32: 1424365293),
      'd1_unicode': (length: 27239, adler32: 4169520655),
      'd1_large': (length: 227731, adler32: 1592063295),
      'd2_run_formatting': (length: 28625, adler32: 445085634),
      'd2_paragraph_formatting': (length: 28931, adler32: 1867241301),
      'd2_styles': (length: 30934, adler32: 2382400719),
      'd2_lists': (length: 33284, adler32: 1929608764),
      'd3_basic': (length: 28845, adler32: 3066803131),
      'd3_header_row': (length: 70020, adler32: 3183794624),
      'd3_merges': (length: 30134, adler32: 2775992460),
      'd3_formatting': (length: 29861, adler32: 1727659781),
      'd3_nested': (length: 33071, adler32: 2162307222),
      'tables_by_hand': (length: 9996, adler32: 2530907752),
      'ns0_prefix': (length: 1407, adler32: 3668097186),
      'default_namespace': (length: 1344, adler32: 3335628311),
      'no_override': (length: 1259, adler32: 3490218517),
      'libreoffice': (length: 6318, adler32: 1326981182),
      'google_docs': (length: 4167, adler32: 3568252968),
      'docm': (length: 2695, adler32: 1708433424),
      'google_docs_no_numbering': (length: 3626, adler32: 4219505065),
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
  test('the corpus is the pinned bytes, the same on every run', () {
    final List<({String name, Uint8List bytes})> first = docxFuzzCorpus();
    final List<({String name, Uint8List bytes})> second = docxFuzzCorpus();
    expect(<String>[for (final c in first) c.name], _corpus.keys.toList());
    for (int i = 0; i < first.length; i++) {
      final ({String name, Uint8List bytes}) entry = first[i];
      expect(second[i].bytes, entry.bytes, reason: entry.name);
      final ({int length, int adler32}) pinned = _corpus[entry.name]!;
      expect(entry.bytes.length, pinned.length, reason: entry.name);
      expect(_adler32(entry.bytes), pinned.adler32, reason: entry.name);
    }
  });

  test('a seed gives the same cases every time', () {
    final List<FuzzCase> first = docxFuzzCases(3, 20).toList();
    final List<FuzzCase> second = docxFuzzCases(3, 20).toList();
    for (int i = 0; i < first.length; i++) {
      expect(second[i].index, i);
      expect(second[i].mutation, first[i].mutation);
      expect(second[i].bytes, first[i].bytes, reason: first[i].mutation);
    }
  });

  test('every corpus entry opens and saves unmutated', () {
    for (final ({String name, Uint8List bytes}) entry in docxFuzzCorpus()) {
      exerciseDocx(entry.bytes);
    }
  });

  test('typed attributes are replaced in the typed parts', () {
    final RegExp replacement = RegExp(r'replace w:(\w+) at \d+ with "(.*)"$');
    final Map<String, Map<String, int>> perPart = <String, Map<String, int>>{};
    final Set<String> values = <String>{};
    for (final int seed in _seeds) {
      final Set<String> hit = <String>{};
      for (final FuzzCase c in docxFuzzCases(seed, _cases)) {
        final RegExpMatch? m = replacement.firstMatch(c.mutation);
        if (m == null || !typedAttributes.contains(m.group(1))) continue;
        values.add(m.group(2)!);
        hit.add(mutatedPart(c.mutation)!);
        final Map<String, int> counts = perPart.putIfAbsent(
          mutatedPart(c.mutation)!,
          () => <String, int>{},
        );
        counts.update(m.group(1)!, (int n) => n + 1, ifAbsent: () => 1);
      }
      // Few corpus entries hold numbering, so it is required over all seeds.
      expect(
        hit,
        containsAll(<String>['word/document.xml', 'word/styles.xml']),
        reason: 'seed $seed',
      );
    }
    // The counts, for the report: replacements per part and attribute.
    printOnFailure('$perPart');
    expect(perPart.keys.toSet(), <String>{
      'word/document.xml',
      'word/styles.xml',
      'word/numbering.xml',
    });
    for (final MapEntry<String, Map<String, int>> e in perPart.entries) {
      expect(e.value['val'], greaterThan(0), reason: e.key);
      expect(e.value.length, greaterThanOrEqualTo(3), reason: e.key);
    }
    expect(values, <String>{'abc', '99999999999999999999', '-', '1in'});
  });

  test('every part name is mutated in some corpus entry', () {
    final Set<String> parts = <String>{
      for (final ({String name, Uint8List bytes}) entry in docxFuzzCorpus())
        ...docxCorpusPartNames(entry.bytes),
    };
    final Set<String> mutated = <String>{
      for (final int seed in _seeds)
        for (final FuzzCase c in docxFuzzCases(seed, _cases))
          ?mutatedPart(c.mutation),
    };
    expect(parts.difference(mutated), isEmpty);
  });

  test('mutated files raise only DocxReadException', () {
    final List<String> failures = <String>[];
    for (final int seed in _seeds) {
      for (final FuzzCase c in docxFuzzCases(seed, _cases)) {
        final Stopwatch watch = Stopwatch()..start();
        try {
          exerciseDocx(c.bytes);
        } on DocxReadException {
          // A file problem, reported as the document promises.
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
