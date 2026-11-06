/// The number format benchmark: `NumberFormatter` on 100,000 values of one
/// kind each.
///
/// Moved from jet_office's benchmark/xlsx_format_benchmark_test.dart at
/// commit 632115d; its run on the cells of a read workbook stayed there. It
/// records figures, it does not judge them (docs/benchmark.md). Three runs
/// of 100,000 values: a number, a serial date given as a `FormatDecimal`
/// (the `BigInt` serial rounding) and a `DateTime`. Run it with
/// `dart test benchmark` and `dart test -p chrome benchmark`; the quality
/// gate does not.
@Tags(<String>['benchmark'])
@Timeout(Duration(minutes: 10))
library;

import 'package:jet_core/jet_core.dart';
import 'package:test/test.dart';

const int _values = 100000;
const int _timedRuns = 3;

/// One warm-up run of [body], then the median of three timed runs, in
/// microseconds. [body] returns the total length of the texts it made, so
/// the work is used; every run must return the same.
int _medianMicros(int Function() body) {
  final int expected = body();
  final List<int> times = <int>[];
  for (int i = 0; i < _timedRuns; i++) {
    final Stopwatch watch = Stopwatch()..start();
    final int length = body();
    watch.stop();
    expect(length, expected);
    times.add(watch.elapsedMicroseconds);
  }
  times.sort();
  return times[times.length ~/ 2];
}

String _ms(int micros) => (micros / 1000).toStringAsFixed(1);

String _ns(int micros, int count) => (micros * 1000 / count).toStringAsFixed(0);

// A double 0.0 is the integer 0 on JavaScript only.
const bool _isWeb = identical(0, 0.0);

void main() {
  const String platform = _isWeb ? 'chrome' : 'vm';

  void line(String text) {
    // ignore: avoid_print
    print('$platform | $text');
  }

  test('per kind, $_values values each', () {
    final NumberFormatter formatter = NumberFormatter();
    const String money = '#,##0.00';
    const String stamp = 'yyyy-mm-dd hh:mm:ss';

    final List<FormatDecimal> numbers = <FormatDecimal>[
      for (int r = 0; r < _values; r++) FormatDecimal('$r.25'),
    ];
    final List<FormatDecimal> serials = <FormatDecimal>[
      for (int r = 0; r < _values; r++)
        FormatDecimal('${46000 + r % 3000}.${r % 86400}'),
    ];
    final DateTime start = DateTime(2026, 1, 1);
    final List<DateTime> dates = <DateTime>[
      for (int r = 0; r < _values; r++) start.add(Duration(seconds: r * 37)),
    ];

    String text(Object value, String code) =>
        formatter.format(value, numberFormat: code).text;
    expect(text(numbers[1000], money), '1,000.25');
    // 46001 is 2025-12-10; .1 of a day is 02:24:00.
    expect(text(serials[1], stamp), '2025-12-10 02:24:00');
    // 100 × 37 s is 1 h 1 min 40 s.
    expect(text(dates[100], stamp), '2026-01-01 01:01:40');

    int run(List<Object> values, String code) => _medianMicros(() {
      int length = 0;
      for (final Object value in values) {
        length += formatter.format(value, numberFormat: code).text.length;
      }
      return length;
    });

    final int number = run(numbers, money);
    final int serial = run(serials, stamp);
    final int date = run(dates, stamp);
    String ratio(int micros) => (micros / number).toStringAsFixed(2);
    line(
      'number | FormatDecimal $money | median ${_ms(number)} ms | '
      '${_ns(number, _values)} ns/value | ratio 1.00',
    );
    line(
      'serial date | FormatDecimal $stamp | median ${_ms(serial)} ms | '
      '${_ns(serial, _values)} ns/value | ratio ${ratio(serial)}',
    );
    line(
      'DateTime | $stamp | median ${_ms(date)} ms | '
      '${_ns(date, _values)} ns/value | ratio ${ratio(date)}',
    );
  });
}
