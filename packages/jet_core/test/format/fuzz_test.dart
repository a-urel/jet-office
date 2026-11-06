import 'package:jet_core/jet_core.dart';
import 'package:test/test.dart';

import 'support/fuzz.dart';

/// The seeds the quality gate fuzzes, each with [_cases] cases.
const List<int> _seeds = <int>[1, 2, 3, 4];

/// The cases per seed in the quality gate.
const int _cases = 200;

/// The size and hash of the corpus jet_office's fuzzer built, frozen at the
/// extraction (jet_office commit 632115d): `formatFuzzCorpus()` must go on
/// returning exactly those codes in that order, or a seed no longer gives
/// the cases it gave there. A deliberate change of the corpus changes both
/// numbers, in the same commit as the change.
const int _corpusLength = 538;
const int _corpusHash = 430290639;

/// FNV-1a over every code's length and UTF-16 code units, in order, with
/// 32-bit arithmetic only, so the VM and the web agree.
int corpusHash(List<String> corpus) {
  int hash = 0x811C9DC5;
  void mix(int value) {
    // hash * 0x01000193 as a shift and a small product: the full product
    // passes 2^53, which JavaScript cannot hold exactly.
    final int x = hash ^ (value & 0xFFFF);
    hash = ((x << 24) + x * 0x193) & 0xFFFFFFFF;
  }

  for (final String code in corpus) {
    mix(code.length);
    for (final int unit in code.codeUnits) {
      mix(unit);
    }
  }
  return hash;
}

void main() {
  test('the corpus holds the built-in, fixture and test codes', () {
    final List<String> corpus = formatFuzzCorpus();
    expect(
      corpus,
      containsAll(<String>[
        'General',
        '0.00',
        'm/d/yyyy',
        FormatLocale.deDE.builtinCodes[14]!,
        FormatLocale.trTR.longDateCode,
        '[\$-F800]dddd, mmmm dd, yyyy',
      ]),
    );
    expect(corpus.length, greaterThan(200));
  });

  test('the corpus is the one jet_office built: same length and hash', () {
    final List<String> corpus = formatFuzzCorpus();
    expect(corpus, hasLength(_corpusLength));
    expect(corpusHash(corpus), _corpusHash);
  });

  test('a seed gives the same cases twice', () {
    expect(
      formatFuzzCases(7, 50).map(describeCase).toList(),
      formatFuzzCases(7, 50).map(describeCase).toList(),
    );
  });

  for (final int seed in _seeds) {
    test('seed $seed: $_cases cases format without breaking a rule', () {
      final FormatFuzzFormatters formatters = FormatFuzzFormatters();
      final List<String> failures = <String>[];
      for (final FormatFuzzCase c in formatFuzzCases(seed, _cases)) {
        final String? problem = checkFormatCase(formatters, c);
        if (problem != null) failures.add(describeFormatFailure(c, problem));
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}

String describeCase(FormatFuzzCase c) =>
    '${c.code}|${describeFuzzValue(c.value)}|${c.generalWidth}|'
    '${describeFuzzSettings(c)}';
