/// The XLSX read benchmark: the 100,000 × 12 file the write benchmark makes.
///
/// New in jet_office. It records figures, it does not judge them
/// (docs/benchmark.md). The file is written with `XlsxWriter` once, before
/// anything is timed, so each platform reads its own bytes (decision 0006);
/// on the VM a child process writes it (`src/workload_file.dart`). The phase figures use the private `ZipReader` to time the
/// inflate alone. Run it with `dart test benchmark` and
/// `dart test -p chrome benchmark`; the quality gate does not.
@Tags(<String>['benchmark'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:typed_data';

import 'package:archive/archive.dart' show ZipDecoder, ZipFile;
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/zip/archive_adapter.dart';
import 'package:test/test.dart';

import 'src/memory_probe.dart';
import 'src/platform_inflate.dart';
import 'src/workload_file.dart';

const int _rows = 100000;
const int _sampleEvery = 10000;
const int _timedRuns = 3;

/// The part `XlsxWriter` writes the first sheet to.
const String _sheetPart = 'xl/worksheets/sheet1.xml';

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

/// One full read of a sheet: its cells, the cells with a non-null value, and
/// the rows taken.
typedef _Pass = ({int cells, int values, int rows});

/// Reads every row of the first sheet of [reader] and every cell's value,
/// calling [onRow] with the number of rows taken so far after each row.
_Pass _readAll(XlsxReader reader, [void Function(int rows)? onRow]) {
  int cells = 0;
  int values = 0;
  int rows = 0;
  for (final XlsxReadRow row in reader.rowsAt(0)) {
    for (final XlsxReadCell cell in row.cells) {
      cells++;
      if (cell.value != null) values++;
    }
    rows++;
    onRow?.call(rows);
  }
  return (cells: cells, values: values, rows: rows);
}

/// One timed run of the reader: its milliseconds, the sampled peak and the
/// baseline taken just before the reader opened, and what it read.
typedef _Run = ({
  int ms,
  int? peak,
  int? baseline,
  _Pass pass,
  List<XlsxWarning> warnings,
});

_Run _runReader(Uint8List file, MemoryProbe probe) {
  int? peak;
  void sample() {
    final int? now = probe.sample();
    if (now != null && (peak == null || now > peak!)) peak = now;
  }

  final int? baseline = probe.sample();
  final Stopwatch watch = Stopwatch()..start();
  final XlsxReader reader = XlsxReader(file);
  final _Pass pass = _readAll(reader, (int rows) {
    // The first row follows the inflate and the decode of the sheet part,
    // which is when the part's XML is held.
    if (rows == 1 || rows % _sampleEvery == 0) sample();
  });
  watch.stop();
  sample();
  return (
    ms: watch.elapsedMilliseconds,
    peak: peak,
    baseline: baseline,
    pass: pass,
    warnings: reader.warnings,
  );
}

/// The median of three runs of [body], each timed alone, in microseconds.
/// [setUp] runs before each and is not timed; its result goes to [body].
int _medianMicros<T>(T Function() setUp, void Function(T value) body) {
  final List<int> times = <int>[];
  for (int i = 0; i < _timedRuns; i++) {
    final T value = setUp();
    final Stopwatch watch = Stopwatch()..start();
    body(value);
    watch.stop();
    times.add(watch.elapsedMicroseconds);
  }
  times.sort();
  return times[times.length ~/ 2];
}

String _ms(int micros) => (micros / 1000).toStringAsFixed(1);

// A double 0.0 is the integer 0 on JavaScript only.
const bool _isWeb = identical(0, 0.0);

void main() {
  final MemoryProbe memory = currentProbe();
  // On the VM, the process's peak RSS: the child process wrote the input, so
  // after the warm-up it holds the reader's true peak, unsampled.
  final MemoryProbe peakProbe = probe();
  const String platform = _isWeb ? 'chrome' : 'vm';
  const XlsxReadLimits limits = XlsxReadLimits();

  void line(String text) {
    // ignore: avoid_print
    print('$platform | $text');
  }

  late final Uint8List file;
  late final Uint8List rawSheet;
  late final int sheetBytes;
  int? largestAbove;
  // The VM's peak RSS after the warm-up, and the baseline of the warm-up:
  // before the timed runs and the phases can lift the peak.
  int? warmUpPeak;
  int? warmUpBaseline;

  ZipReader openZip() => ZipReader(
    file,
    maxEntries: limits.maxEntries,
    maxEntryBytes: limits.maxEntryBytes,
    maxTotalBytes: limits.maxTotalBytes,
    maxCompressionRatio: limits.maxCompressionRatio,
  );

  setUpAll(() {
    file = workloadFile(_rows);
    final ZipFile? entry =
        ZipDecoder().decodeBytes(file).findFile(_sheetPart)?.rawContent
            as ZipFile?;
    expect(entry, isNotNull, reason: 'the sheet is $_sheetPart');
    rawSheet = entry!.getRawContent();
    sheetBytes = openZip().read(_sheetPart).length;
    line(
      'input | ${file.length} bytes | $_sheetPart ${rawSheet.length} '
      'bytes deflated, $sheetBytes bytes XML',
    );
  });

  test('XlsxReader reads $_rows rows', () {
    final int expected = _expectedCells();
    void report(int run, String label, _Run r) {
      final int? above = r.peak == null || r.baseline == null
          ? null
          : r.peak! - r.baseline!;
      if (above != null && (largestAbove == null || above > largestAbove!)) {
        largestAbove = above;
      }
      line(
        'XlsxReader | $label${run > 0 ? ' $run' : ''} | ${r.ms} ms | '
        '${file.length} bytes | ${memory.unit} '
        '${r.peak == null ? 'n/a' : 'peak ${r.peak} bytes'} | baseline '
        '${r.baseline == null ? 'n/a' : '${r.baseline} bytes'} | above '
        '${above == null ? 'n/a' : '$above bytes'} | cells '
        '${r.pass.cells} | warnings ${r.warnings.length} '
        '(${r.warnings.map((XlsxWarning w) => w.code.name).join(', ')})'
        '${_isWeb ? '' : ' | ${peakProbe.unit} ${peakProbe.sample()} bytes'}',
      );
      expect(r.pass.cells, expected);
      expect(r.pass.rows, _rows + 1);
      // The formulas carry no cached value, so they read as null.
      expect(r.pass.values, expected - _rows);
    }

    final _Run warmUp = _runReader(file, memory);
    warmUpBaseline = warmUp.baseline;
    warmUpPeak = peakProbe.sample();
    report(0, 'warm-up', warmUp);
    final List<int> times = <int>[];
    for (int i = 1; i <= _timedRuns; i++) {
      final _Run r = _runReader(file, memory);
      times.add(r.ms);
      report(i, 'run', r);
    }
    times.sort();
    line('XlsxReader | median ${times[times.length ~/ 2]} ms');
  });

  test('phases', () {
    final int open = _medianMicros<void>(() {}, (_) => XlsxReader(file));
    line('phase | open | ${_ms(open)} ms');

    final int inflate = _medianMicros<ZipReader>(
      openZip,
      (ZipReader zip) => zip.read(_sheetPart),
    );
    line(
      'phase | ZipReader.read (pure-Dart inflate) | ${_ms(inflate)} ms | '
      'N $sheetBytes bytes',
    );

    final Uint8List? native = platformInflate(rawSheet);
    if (native == null) {
      line('phase | platform inflate | n/a');
    } else {
      expect(native, openZip().read(_sheetPart));
      final int platformMicros = _medianMicros<void>(
        () {},
        (_) => platformInflate(rawSheet),
      );
      line('phase | platform inflate | ${_ms(platformMicros)} ms');
    }

    final int first = _medianMicros<XlsxReader>(
      () => XlsxReader(file),
      (XlsxReader reader) => _readAll(reader),
    );
    line('phase | first rows pass | ${_ms(first)} ms');

    final int second = _medianMicros<XlsxReader>(() {
      final XlsxReader reader = XlsxReader(file);
      _readAll(reader);
      return reader;
    }, (XlsxReader reader) => _readAll(reader));
    line(
      'phase | second rows pass (shared strings cached) | ${_ms(second)} ms',
    );

    final int merges = _medianMicros<XlsxReader>(
      () {
        final XlsxReader reader = XlsxReader(file);
        _readAll(reader);
        return reader;
      },
      (XlsxReader reader) {
        expect(reader.mergesAt(0), isEmpty);
      },
    );
    line('phase | mergesAt(0) after rows | ${_ms(merges)} ms');
  });

  test('memory per byte of sheet XML', () {
    String perN(int? bytes) =>
        bytes == null ? 'n/a' : (bytes / sheetBytes).toStringAsFixed(2);
    final int? above = largestAbove;
    line(
      'memory/N | ${perN(above)} | largest sampled peak above baseline '
      '${above == null ? 'n/a' : '$above bytes'} | N $sheetBytes bytes',
    );
    if (!_isWeb) {
      final int? peak = warmUpPeak;
      final int? base = warmUpBaseline;
      final int? peakAbove = peak == null || base == null ? null : peak - base;
      line(
        'memory/N (${peakProbe.unit}) | ${perN(peakAbove)} | '
        '${peakProbe.unit} after the warm-up above its baseline '
        '${peakAbove == null ? 'n/a' : '$peakAbove bytes'}',
      );
    }
  });
}
