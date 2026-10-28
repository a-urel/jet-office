/// The case loop of `tool/fuzz_reader.dart`, apart from its arguments and
/// process exit code so a test can run it.
///
/// New in jet_office (phase 2, R4). It mutates and reads as
/// `tool/fuzz_reader.dart` documents: `XlsxReadException` is a refusal,
/// anything else thrown and any case taking more than 5 s is a failure.
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

import '../../test/xlsx/read/support/fuzz.dart';

/// The totals of one [runFuzz] call.
final class FuzzRunResult {
  /// Creates the totals of a run.
  const FuzzRunResult({
    required this.cases,
    required this.refused,
    required this.failures,
  });

  /// How many cases ran.
  final int cases;

  /// How many cases the reader refused with an `XlsxReadException`.
  final int refused;

  /// How many cases threw anything else or took longer than 5 s.
  final int failures;
}

/// Runs `cases` mutated files for each seed from [first] to [last] through
/// [exercise] (default [exerciseReader]) and returns the totals.
///
/// Each failure is written to [out] as
/// `seed <s> case <i> (<mutation>): <error>`. With [verbose], the line
/// `seed <s> case <i> (<mutation>)` is written to [err] before the case runs,
/// so the last line names a case that never returned.
FuzzRunResult runFuzz({
  required int first,
  required int last,
  required int cases,
  required bool verbose,
  required StringSink out,
  required StringSink err,
  void Function(Uint8List bytes) exercise = exerciseReader,
}) {
  int count = 0;
  int refused = 0;
  int failures = 0;
  for (int seed = first; seed <= last; seed++) {
    for (final FuzzCase c in fuzzCases(seed, cases)) {
      count++;
      if (verbose) {
        err.writeln('seed ${c.seed} case ${c.index} (${c.mutation})');
      }
      final Stopwatch watch = Stopwatch()..start();
      try {
        exercise(c.bytes);
      } on XlsxReadException {
        refused++;
      } on Object catch (e) {
        failures++;
        out.writeln('seed ${c.seed} case ${c.index} (${c.mutation}): $e');
      }
      if (watch.elapsed > const Duration(seconds: 5)) {
        failures++;
        out.writeln(
          'seed ${c.seed} case ${c.index} (${c.mutation}): hang, '
          '${watch.elapsedMilliseconds} ms',
        );
      }
    }
  }
  return FuzzRunResult(cases: count, refused: refused, failures: failures);
}
