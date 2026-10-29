/// Fuzzes `XlsxNumberFormatter` with seeded format codes and values, for
/// runs longer than the quality gate's.
///
/// ```bash
/// dart run tool/fuzz_formatter.dart [--seeds 1-20] [--cases 500]
/// ```
///
/// For every seed of the inclusive range `--seeds` (default `1-20`, or a
/// single seed such as `7`) it formats `--cases` (default 500) cases as
/// `test/xlsx/format/support/fuzz.dart` describes. A case breaks a rule when
/// the formatter throws, the code adds more than 1,000 characters or the
/// parts joined differ from the text; it is printed as
/// `seed <s> case <i>: <code> <value> width <w>: <problem>`, which
/// `formatFuzzCases(s, i + 1)` reproduces. A summary line follows; the exit
/// code is 1 on any failure and 64 on bad arguments.
///
/// The quality gate runs seeds 1 to 4 with 200 cases each
/// (`test/xlsx/format/fuzz_test.dart`).
library;

import 'dart:io';

import 'package:jet_office/jet_office.dart';

import '../test/xlsx/format/support/fuzz.dart';

void main(List<String> args) {
  final ({int first, int last, int cases})? options = _parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/fuzz_formatter.dart [--seeds 1-20] [--cases 500]',
    );
    exitCode = 64;
    return;
  }
  final Stopwatch total = Stopwatch()..start();
  int count = 0;
  int failures = 0;
  for (int seed = options.first; seed <= options.last; seed++) {
    final XlsxNumberFormatter formatter = XlsxNumberFormatter();
    for (final FormatFuzzCase c in formatFuzzCases(seed, options.cases)) {
      count++;
      final String? problem = checkFormatCase(formatter, c);
      if (problem != null) {
        failures++;
        stdout.writeln(describeFormatFailure(c, problem));
      }
    }
  }
  stdout.writeln(
    'seeds ${options.first}-${options.last}: $count cases, $failures '
    'failures, ${total.elapsed.inMilliseconds} ms',
  );
  if (failures > 0) exitCode = 1;
}

/// The seed range and case count of [args], or `null` when they are not
/// understood.
({int first, int last, int cases})? _parse(List<String> args) {
  int first = 1;
  int last = 20;
  int cases = 500;
  for (int i = 0; i < args.length; i += 2) {
    if (i + 1 >= args.length) return null;
    final String value = args[i + 1];
    switch (args[i]) {
      case '--seeds':
        final List<String> ends = value.split('-');
        if (ends.length > 2) return null;
        final int? from = int.tryParse(ends.first);
        final int? to = int.tryParse(ends.last);
        if (from == null || to == null || from < 0 || to < from) return null;
        first = from;
        last = to;
      case '--cases':
        final int? n = int.tryParse(value);
        if (n == null || n < 1) return null;
        cases = n;
      default:
        return null;
    }
  }
  return (first: first, last: last, cases: cases);
}
