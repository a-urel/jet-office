/// The case loop of `tool/fuzz_reader.dart` and `tool/fuzz_docx.dart`, apart
/// from their arguments and process exit code so a test can run it.
///
/// New in jet_office (phase 2, R4); generalised in phase 4 (D1) for the DOCX
/// fuzzer. By default it mutates and reads as `tool/fuzz_reader.dart`
/// documents: `XlsxReadException` is a refusal, anything else thrown and any
/// case taking more than 5 s in every one of three runs is a failure.
/// `tool/fuzz_docx.dart` passes the DOCX cases, exercise and refusal.
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

import '../../test/support/timing.dart';
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

  /// How many cases the reader refused with its read exception.
  final int refused;

  /// How many cases threw anything else or were hangs.
  final int failures;
}

/// Runs `cases` mutated files for each seed from [first] to [last] through
/// [exercise] (default [exerciseReader]) and returns the totals.
///
/// [exerciseCase], when given, takes the whole case in its place, for an
/// exercise that goes by the mutation. [generate] makes the cases of a seed
/// (default [fuzzCases]). A thrown
/// object for which [isRefusal] is true (default: an `XlsxReadException`) is
/// a refusal; any other is a failure.
///
/// A case that takes longer than [hangBound] runs up to twice more, as a
/// busy machine can slow one run; it is a hang, and a failure, only when
/// every run takes longer (`confirmedHang`, `test/support/timing.dart`).
/// The reruns count nothing else: what a case throws is counted once.
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
  void Function(FuzzCase c)? exerciseCase,
  Iterable<FuzzCase> Function(int seed, int count) generate = fuzzCases,
  bool Function(Object error) isRefusal = _isXlsxRefusal,
  Duration hangBound = const Duration(seconds: 5),
}) {
  int count = 0;
  int refused = 0;
  int failures = 0;
  for (int seed = first; seed <= last; seed++) {
    for (final FuzzCase c in generate(seed, cases)) {
      count++;
      if (verbose) {
        err.writeln('seed ${c.seed} case ${c.index} (${c.mutation})');
      }
      void run() {
        if (exerciseCase != null) {
          exerciseCase(c);
        } else {
          exercise(c.bytes);
        }
      }

      final Stopwatch watch = Stopwatch()..start();
      try {
        run();
      } on Object catch (e) {
        if (isRefusal(e)) {
          refused++;
        } else {
          failures++;
          out.writeln('seed ${c.seed} case ${c.index} (${c.mutation}): $e');
        }
      }
      final Duration? hang = confirmedHang(watch.elapsed, () {
        try {
          run();
        } on Object {
          // Counted by the first run.
        }
      }, bound: hangBound);
      if (hang != null) {
        failures++;
        out.writeln(
          'seed ${c.seed} case ${c.index} (${c.mutation}): hang, '
          '${hang.inMilliseconds} ms',
        );
      }
    }
  }
  return FuzzRunResult(cases: count, refused: refused, failures: failures);
}

bool _isXlsxRefusal(Object error) => error is XlsxReadException;
