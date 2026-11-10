/// Test helper: lets a long synchronous loop give the event loop a turn.
///
/// In Chrome the test runner loads every suite in a same-origin iframe of one
/// page, so all suites and the runner's host share one thread. A test that
/// holds it gives no other suite a turn, and a suite whose load began meanwhile
/// fails after 30 seconds with "Timed out waiting for browser to load test
/// suite", though nothing is wrong with it. The DOCX fuzz test's 3,600 cases
/// held it for about a minute and failed two loads that way. A fuzz loop calls
/// [EventLoopBreather.breathe] after each case.
library;

/// Leaves the event loop for one timer turn once [every] has passed since the
/// last turn, so a loop pays for a turn about once per [every], not per call.
final class EventLoopBreather {
  /// A breather that gives the event loop a turn about once per [every].
  EventLoopBreather({this.every = const Duration(seconds: 1)});

  /// The longest the loop holds the thread between two turns.
  final Duration every;

  final Stopwatch _sinceTurn = Stopwatch()..start();

  /// Completes after a timer turn when [every] has passed since the last one,
  /// at once otherwise.
  Future<void> breathe() async {
    if (_sinceTurn.elapsed < every) return;
    await Future<void>.delayed(Duration.zero);
    _sinceTurn.reset();
  }
}
