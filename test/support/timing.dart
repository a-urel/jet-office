/// Test helper: timing bounds that compare a run with a baseline measured in
/// the same test, so a slow or busy machine does not fail a test that an
/// absolute bound would.
library;

import 'package:test/test.dart';

/// The shortest of three runs of [body], each timed from start to finish.
Duration bestOfThree(void Function() body) {
  Duration? best;
  for (int i = 0; i < 3; i++) {
    final Stopwatch watch = Stopwatch()..start();
    body();
    watch.stop();
    if (best == null || watch.elapsed < best) best = watch.elapsed;
  }
  return best!;
}

/// Expects [measured] to be at most [factor] times [baseline] plus [slack].
///
/// The slack absorbs a baseline too short to measure; a quadratic slowdown
/// of the measured run still exceeds the bound by far.
void expectWithinRatio(
  Duration measured,
  Duration baseline, {
  int factor = 4,
  Duration slack = const Duration(milliseconds: 250),
}) {
  final Duration limit = baseline * factor + slack;
  expect(
    measured,
    lessThanOrEqualTo(limit),
    reason: 'took $measured, baseline $baseline: limit $limit',
  );
}

/// Expects [measured] to run within [expectWithinRatio]'s bound of
/// [baseline], each timed by [bestOfThree], in one of [attempts] attempts.
///
/// A busy machine can slow one side's runs and not the other's, and a load
/// spike of a few hundred milliseconds is enough to fail a single
/// comparison; a new attempt times both sides again. A quadratic slowdown
/// of [measured] exceeds the bound in every attempt, so it still fails.
void expectScales(
  void Function() measured,
  void Function() baseline, {
  int attempts = 3,
  int factor = 4,
  Duration slack = const Duration(milliseconds: 250),
}) {
  for (int attempt = 1; ; attempt++) {
    final Duration many = bestOfThree(measured);
    final Duration one = bestOfThree(baseline);
    if (attempt == attempts || many <= one * factor + slack) {
      expectWithinRatio(many, one, factor: factor, slack: slack);
      return;
    }
  }
}
