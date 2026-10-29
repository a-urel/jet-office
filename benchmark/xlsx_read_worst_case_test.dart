/// The XLSX reader's worst case under its default limits for one sheet: the
/// largest single sheet they accept, about 250 MiB of XML, under
/// `maxEntryBytes` (256 MiB) and under `maxCompressionRatio` (1,000).
///
/// New in jet_office. It records figures, it does not judge them
/// (docs/benchmark.md, "Worst case"). It runs in its own file so that a
/// browser tab running out of memory cannot hide the other read figures.
/// On the VM a child process builds the package (`src/workload_file.dart`);
/// in Chrome it is built in the page, and the sheet's XML is garbage, but
/// perhaps not yet collected, when the baseline is sampled. Run it with
/// `dart test benchmark/xlsx_read_worst_case_test.dart` and the same with
/// `-p chrome`; the quality gate does not.
@Tags(<String>['benchmark'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:typed_data';

import 'package:archive/archive.dart' show ArchiveFile, ZipDecoder, ZipFile;
import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../test/xlsx/read/support/workbook_builder.dart' show sheetEntry;
import 'src/memory_probe.dart';
import 'src/workload_file.dart';
import 'src/worst_case.dart';

const int _sampleEvery = 100000;

/// What a `<v>1</v>` cell reads as.
final XlsxDecimal _one = XlsxDecimal('1');

// A double 0.0 is the integer 0 on JavaScript only.
const bool _isWeb = identical(0, 0.0);

void main() {
  final MemoryProbe memory = currentProbe();
  // On the VM, the process's peak RSS: the child process built the input,
  // so a rise during the read is the read's own peak, unsampled.
  final MemoryProbe peakProbe = probe();
  const String platform = _isWeb ? 'chrome' : 'vm';
  const XlsxReadLimits limits = XlsxReadLimits();
  final String sheetPart = sheetEntry(0);

  void line(String text) {
    // ignore: avoid_print
    print('$platform | $text');
  }

  late final Uint8List file;
  late final int sheetBytes;

  setUpAll(() {
    final Stopwatch watch = Stopwatch()..start();
    file = worstCaseFile();
    watch.stop();
    // The ZIP directory only: nothing is inflated before the read.
    final ArchiveFile? sheet = ZipDecoder()
        .decodeBytes(file)
        .findFile(sheetPart);
    expect(sheet, isNotNull, reason: 'the sheet is $sheetPart');
    final int deflated = (sheet!.rawContent! as ZipFile).getRawContent().length;
    sheetBytes = sheet.size;
    final double ratio = sheetBytes / deflated;
    line(
      'input | built in ${watch.elapsedMilliseconds} ms | ${file.length} '
      'bytes | $sheetPart $deflated bytes deflated, $sheetBytes bytes XML | '
      'ratio ${ratio.toStringAsFixed(1)} | k n/a (no row varied) | rows '
      '${worstCaseRows()}',
    );
    // Otherwise the reader would refuse the file unread.
    expect(sheetBytes, lessThanOrEqualTo(limits.maxEntryBytes));
    expect(ratio, lessThan(limits.maxCompressionRatio));
  });

  test('XlsxReader reads the worst case under the default limits', () {
    int? peak;
    int? firstRow;
    void sample() {
      final int? now = memory.sample();
      if (now != null && (peak == null || now > peak!)) peak = now;
    }

    final int? peakBefore = _isWeb ? null : peakProbe.sample();
    final int? baseline = memory.sample();
    final Stopwatch watch = Stopwatch()..start();
    final XlsxReader reader = XlsxReader(file, limits: limits);
    int rows = 0;
    int cells = 0;
    int ones = 0;
    for (final XlsxReadRow row in reader.rowsAt(0)) {
      for (final XlsxReadCell cell in row.cells) {
        cells++;
        if (cell.value == _one) ones++;
      }
      rows++;
      if (rows == 1) {
        // The part has just been inflated and decoded.
        sample();
        firstRow = peak;
      } else if (rows % _sampleEvery == 0) {
        sample();
      }
    }
    watch.stop();
    sample();
    final int? peakAfter = _isWeb ? null : peakProbe.sample();

    String bytes(int? value) => value == null ? 'n/a' : '$value bytes';
    String perN(int? value) =>
        value == null ? 'n/a' : (value / sheetBytes).toStringAsFixed(2);
    final int? above = peak == null || baseline == null
        ? null
        : peak! - baseline;
    final int? firstAbove = firstRow == null || baseline == null
        ? null
        : firstRow - baseline;
    final List<XlsxWarning> warnings = reader.warnings;
    line(
      'XlsxReader | ${watch.elapsedMilliseconds} ms | ${file.length} bytes | '
      '${memory.unit} peak ${bytes(peak)} | baseline ${bytes(baseline)} | '
      'above ${bytes(above)} (${perN(above)} N) | after the first row above '
      '${bytes(firstAbove)} (${perN(firstAbove)} N) | rows $rows | cells '
      '$cells | warnings ${warnings.length} (${warnings.map((XlsxWarning w) => '${w.code.name} ×${w.count}').join(', ')})',
    );
    if (!_isWeb) {
      final int? rssAbove = peakAfter == null || baseline == null
          ? null
          : peakAfter - baseline;
      line(
        '${peakProbe.unit} | before ${bytes(peakBefore)} | after '
        '${bytes(peakAfter)} | above the baseline ${bytes(rssAbove)} '
        '(${perN(rssAbove)} N) | rose during the read: '
        '${peakAfter != null && peakBefore != null && peakAfter > peakBefore ? 'yes' : 'no'}',
      );
    }

    // Rows past Excel's last are not yielded; their cells are warned about.
    final int sheetRows = worstCaseRows();
    final int yielded = sheetRows < XlsxLimits.maxRows
        ? sheetRows
        : XlsxLimits.maxRows;
    expect(rows, yielded);
    expect(cells, yielded * 12);
    expect(ones, cells);
    // The one warning gathers every cell of those rows.
    final int outside = (sheetRows - yielded) * 12;
    expect(
      warnings.map((XlsxWarning w) => (code: w.code, count: w.count)).toList(),
      outside == 0
          ? isEmpty
          : <({XlsxWarningCode code, int count})>[
              (code: XlsxWarningCode.cellOutsideSheet, count: outside),
            ],
    );
  });
}
