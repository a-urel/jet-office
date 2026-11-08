/// Fuzzes `layoutChart` with seeded random charts, for runs longer than the
/// quality gate's.
///
/// ```bash
/// dart run tool/fuzz_layout.dart [--seeds 1-200] [--cases 1000]
/// ```
///
/// For every seed of the inclusive range `--seeds` (default `1-200`, or a
/// single seed such as `7`) it lays out `--cases` (default 1000) charts as
/// `test/layout/support/chart_fuzz.dart` generates them and checks each with
/// `checkLayoutCase`: no throw, every number finite, no overlap
/// `findOverlaps` reports, every primitive inside the size. Each failure is
/// printed as `seed <s> case <i>: <problem>` followed by the chart, which
/// `layoutFuzzCase(s, i)` reproduces. A summary line follows; the exit code
/// is 1 on any failure and 2 on arguments it does not understand.
///
/// The quality gate runs seeds 1 to 4 with 100 cases each
/// (`test/layout/fuzz_test.dart`).
library;

import 'dart:io';

import '../test/layout/support/chart_fuzz.dart';

void main(List<String> args) {
  final ({int first, int last, int cases})? options = _parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/fuzz_layout.dart [--seeds 1-200] [--cases 1000]',
    );
    exitCode = 2;
    return;
  }
  final Stopwatch total = Stopwatch()..start();
  int failures = 0;
  int cases = 0;
  for (int seed = options.first; seed <= options.last; seed++) {
    for (int i = 0; i < options.cases; i++) {
      final LayoutFuzzCase c = layoutFuzzCase(seed, i);
      final List<String> problems = checkLayoutCase(c);
      cases++;
      if (problems.isNotEmpty) {
        failures++;
        stdout
          ..writeln('seed $seed case $i: ${problems.join('\n  ')}')
          ..writeln(c.describe());
      }
    }
  }
  stdout.writeln(
    'seeds ${options.first}-${options.last}: $cases cases, '
    '$failures failures, ${total.elapsed.inMilliseconds} ms',
  );
  if (failures > 0) exitCode = 1;
}

/// The seed range and case count of [args], or `null` when they are not
/// understood.
({int first, int last, int cases})? _parse(List<String> args) {
  int first = 1;
  int last = 200;
  int cases = 1000;
  if (args.length.isOdd) return null;
  for (int i = 0; i < args.length; i += 2) {
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
