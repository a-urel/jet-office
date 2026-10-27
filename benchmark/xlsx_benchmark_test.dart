/// The XLSX write benchmark: 100,000 rows of 12 mixed columns.
///
/// New in jet_office. It records figures, it does not judge them
/// (docs/benchmark.md). Run it with `dart test benchmark` and
/// `dart test -p chrome benchmark`; the quality gate does not.
@Tags(<String>['benchmark'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../test/support/xlsx_checker.dart';
import 'src/memory_probe.dart';
import 'src/workload.dart';

const int _rows = 100000;
const int _sampleEvery = 10000;
const int _timedRuns = 3;

/// A sink that keeps no bytes, only their number.
final class _CountingSink implements Sink<List<int>> {
  int bytes = 0;

  @override
  void add(List<int> data) => bytes += data.length;

  @override
  void close() {}
}

/// One run of a writer: its milliseconds, file bytes, peak memory, and the
/// file when the writer keeps it.
typedef _Run = ({int ms, int bytes, int? peak, Uint8List? file});

_Run _runMemory(MemoryProbe probe) {
  int? peak;
  void sample() {
    final int? now = probe.sample();
    if (now != null && (peak == null || now > peak!)) peak = now;
  }

  final Stopwatch watch = Stopwatch()..start();
  final XlsxWriter book = XlsxWriter();
  writeWorkload(book.addSheet('Data'), _rows, (int r) {
    if (r % _sampleEvery == 0) sample();
  });
  final XlsxResult result = book.close();
  watch.stop();
  sample();
  return (
    ms: watch.elapsedMilliseconds,
    bytes: result.bytes.length,
    peak: peak,
    file: result.bytes,
  );
}

_Run _runStream(MemoryProbe probe) {
  int? peak;
  void sample() {
    final int? now = probe.sample();
    if (now != null && (peak == null || now > peak!)) peak = now;
  }

  final Stopwatch watch = Stopwatch()..start();
  // The writer closes the sink in close().
  // ignore: close_sinks
  final _CountingSink sink = _CountingSink();
  final XlsxStreamWriter book = XlsxStreamWriter(sink);
  writeWorkload(book.addSheet('Data'), _rows, (int r) {
    if (r % _sampleEvery == 0) sample();
  });
  book.close();
  watch.stop();
  sample();
  return (
    ms: watch.elapsedMilliseconds,
    bytes: sink.bytes,
    peak: peak,
    file: null,
  );
}

// A double 0.0 is the integer 0 on JavaScript only.
const bool _isWeb = identical(0, 0.0);

void main() {
  final MemoryProbe memory = probe();
  const String platform = _isWeb ? 'chrome' : 'vm';

  void report(String writer, int run, String label, _Run r) {
    // ignore: avoid_print
    print(
      '$platform | $writer | $label${run > 0 ? ' $run' : ''} | ${r.ms} ms | '
      '${r.bytes} bytes | ${memory.unit} '
      '${r.peak == null ? 'n/a' : '${r.peak} bytes'}',
    );
  }

  Uint8List? lastFile;

  // maxRss only grows, so the streaming case runs first: its figure is not
  // lifted by the in-memory case's large buffers.
  for (final (String name, _Run Function(MemoryProbe) run)
      in <(String, _Run Function(MemoryProbe))>[
        ('XlsxStreamWriter', _runStream),
        ('XlsxWriter', _runMemory),
      ]) {
    test('$name writes $_rows rows', () {
      report(name, 0, 'warm-up', run(memory));
      final List<int> times = <int>[];
      for (int i = 1; i <= _timedRuns; i++) {
        final _Run r = run(memory);
        times.add(r.ms);
        report(name, i, 'run', r);
        if (r.file != null) lastFile = r.file;
      }
      times.sort();
      // ignore: avoid_print
      print('$platform | $name | median ${times[times.length ~/ 2]} ms');
    });
  }

  test('the measured file is a valid XLSX', () {
    expect(lastFile, isNotNull, reason: 'the XlsxWriter case runs before this');
    expect(checkXlsx(lastFile!), isEmpty);
  });
}
