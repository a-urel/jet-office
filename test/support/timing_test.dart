import 'package:test/test.dart';

import 'timing.dart';

/// Holds the thread for [duration], so a run takes at least that long.
void _busy(Duration duration) {
  final Stopwatch watch = Stopwatch()..start();
  while (watch.elapsed < duration) {}
}

void main() {
  group('confirmedHang', () {
    const Duration bound = Duration(milliseconds: 20);

    test('is null when the first run is within the bound', () {
      int reruns = 0;
      expect(
        confirmedHang(Duration.zero, () => reruns++, bound: bound),
        isNull,
      );
      expect(reruns, 0);
    });

    test('is null when a rerun is within the bound', () {
      int reruns = 0;
      expect(
        confirmedHang(const Duration(seconds: 1), () => reruns++, bound: bound),
        isNull,
      );
      expect(reruns, 1);
    });

    test('is the shortest run when every run is over the bound', () {
      int reruns = 0;
      final Duration? hang = confirmedHang(const Duration(seconds: 1), () {
        reruns++;
        _busy(const Duration(milliseconds: 30));
      }, bound: bound);
      expect(reruns, 2);
      expect(hang, isNotNull);
      expect(hang! > bound, isTrue);
      expect(hang < const Duration(seconds: 1), isTrue);
    });
  });
}
