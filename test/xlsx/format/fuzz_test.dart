import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import 'support/fuzz.dart';

/// The seeds the quality gate fuzzes, each with [_cases] cases.
const List<int> _seeds = <int>[1, 2, 3, 4];

/// The cases per seed in the quality gate.
const int _cases = 200;

void main() {
  test('the corpus holds the built-in, fixture and test codes', () {
    final List<String> corpus = formatFuzzCorpus();
    expect(
      corpus,
      containsAll(<String>[
        'General',
        '0.00',
        'm/d/yyyy',
        XlsxFormatLocale.deDE.builtinCodes[14]!,
        XlsxFormatLocale.trTR.longDateCode,
        '[\$-F800]dddd, mmmm dd, yyyy',
      ]),
    );
    expect(corpus.length, greaterThan(200));
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
