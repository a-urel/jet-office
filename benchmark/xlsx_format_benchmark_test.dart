/// The number format benchmark: `NumberFormatter` on the read workload.
///
/// New in jet_office. It records figures, it does not judge them
/// (docs/benchmark.md). It reads the 100,000 × 12 file the write benchmark
/// makes (`src/workload_file.dart`), untimed, and times formatting every
/// cell of it. The synthetic runs (a number, a serial date given as a
/// `FormatDecimal` and a `DateTime`, 100,000 values each) are in jet_core's
/// own benchmark, `benchmark/format_benchmark_test.dart`, because they need
/// no file. Run this one with `dart test benchmark` and
/// `dart test -p chrome benchmark`; the quality gate does not.
@Tags(<String>['benchmark'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import 'src/workload_file.dart';

const int _rows = 100000;
const int _timedRuns = 3;

/// The cells the workload writes: a header of 12, then 12 per data row but
/// for the `Note` column, which is `null`, and so not written, when
/// `r % 3 == 0` (`writeWorkload`).
int _expectedCells() {
  int cells = 12;
  for (int r = 1; r <= _rows; r++) {
    cells += r % 3 == 0 ? 11 : 12;
  }
  return cells;
}

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

  late final List<XlsxReadCell> cells;

  setUpAll(() {
    final Uint8List file = workloadFile(_rows);
    final XlsxReader reader = XlsxReader(file);
    cells = <XlsxReadCell>[
      for (final XlsxReadRow row in reader.rowsAt(0)) ...row.cells,
    ];
    expect(cells, hasLength(_expectedCells()));
    line('input | ${file.length} bytes | ${cells.length} cells');
  });

  test('formatCell on every cell of the workload', () {
    final NumberFormatter formatter = NumberFormatter();
    int warnings = 0;
    for (final XlsxReadCell cell in cells) {
      if (formatter.formatCell(cell).warning != null) warnings++;
    }
    final int micros = _medianMicros(() {
      int length = 0;
      for (final XlsxReadCell cell in cells) {
        length += formatter.formatCell(cell).text.length;
      }
      return length;
    });
    line(
      'formatCell | median ${_ms(micros)} ms | ${cells.length} cells | '
      '${_ns(micros, cells.length)} ns/cell | warnings $warnings',
    );
    expect(warnings, 0);
  });
}
