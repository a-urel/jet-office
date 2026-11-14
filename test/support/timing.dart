/// Test helper: a hang bound that a slow or busy machine does not trip, as
/// a single timed run would.
library;

/// The shortest run of a case that took [first], over [bound], when every
/// rerun of [body] is over [bound] too, or null when one stays within it.
///
/// [body] runs up to `attempts - 1` more times, and only after a first run
/// over [bound]; it must catch what the case may throw. A busy machine can
/// slow one run several times over, while a case that is truly slow is slow
/// in every run, so a hang is reported only when no run is within [bound].
Duration? confirmedHang(
  Duration first,
  void Function() body, {
  Duration bound = const Duration(seconds: 5),
  int attempts = 3,
}) {
  Duration shortest = first;
  for (int attempt = 1; shortest > bound; attempt++) {
    if (attempt == attempts) return shortest;
    final Stopwatch watch = Stopwatch()..start();
    body();
    watch.stop();
    if (watch.elapsed < shortest) shortest = watch.elapsed;
  }
  return null;
}
