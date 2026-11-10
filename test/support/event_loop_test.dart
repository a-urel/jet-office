// Tests EventLoopBreather, which lets a long synchronous test loop give the
// event loop a turn. In Chrome every suite runs in a same-origin iframe of one
// page, so they share one thread: a loop that holds it for more than 30
// seconds makes the runner fail whatever suite is loading meanwhile ("Timed
// out waiting for browser to load test suite").
import 'dart:async';

import 'package:test/test.dart';

import 'event_loop.dart';

void main() {
  test('a timer fires during a busy loop that breathes', () async {
    bool fired = false;
    Timer.run(() => fired = true);
    final EventLoopBreather breather = EventLoopBreather(
      every: const Duration(milliseconds: 10),
    );
    final Stopwatch watch = Stopwatch()..start();
    while (!fired && watch.elapsed < const Duration(seconds: 5)) {
      await breather.breathe();
    }
    expect(fired, isTrue);
  });

  test('breathe does not leave the loop before the interval passes', () async {
    bool fired = false;
    Timer.run(() => fired = true);
    final EventLoopBreather breather = EventLoopBreather(
      every: const Duration(hours: 1),
    );
    for (int i = 0; i < 1000; i++) {
      await breather.breathe();
    }
    expect(fired, isFalse);
  });
}
