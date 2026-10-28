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
