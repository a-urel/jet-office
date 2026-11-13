import 'package:test/test.dart';

import 'timing.dart';

/// Holds the thread for [duration], so a run takes at least that long.
void _busy(Duration duration) {
  final Stopwatch watch = Stopwatch()..start();
  while (watch.elapsed < duration) {}
}

void main() {
  group('expectScales', () {
    const Duration short = Duration(milliseconds: 1);
    const Duration long = Duration(milliseconds: 30);

    test('passes when the measured run is within the bound', () {
      expectScales(
        () => _busy(short),
        () => _busy(short),
        slack: Duration.zero,
      );
    });

    test('fails when every attempt is over the bound', () {
      int runs = 0;
      expect(
        () => expectScales(
          () {
            runs++;
            _busy(long);
          },
          () => _busy(short),
          slack: Duration.zero,
        ),
        throwsA(isA<TestFailure>()),
      );
      // Three attempts of three runs each.
      expect(runs, 9);
    });

    test('passes when a later attempt is within the bound', () {
      int runs = 0;
      expectScales(
        () {
          runs++;
          // The first attempt's three runs are slow, as on a busy machine.
          _busy(runs <= 3 ? long : short);
        },
        () => _busy(short),
        slack: Duration.zero,
      );
      expect(runs, 6);
    });
  });
}
