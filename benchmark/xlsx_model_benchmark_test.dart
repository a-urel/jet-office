/// The workbook model benchmark: open, load a sheet, set one cell and save,
/// on the 100,000 × 12 file the write benchmark makes.
///
/// Not ported from Quds; written for jet_office. It records figures, it does
/// not judge them (docs/benchmark.md). The file is made as the read benchmark
/// makes it (`src/workload_file.dart`), so each platform reads its own bytes
/// (decision 0006). `XlsxWorkbook.open` inflates every entry once to check it,
/// and a part the model did not load is inflated again when saving, so the
/// phases are timed apart: open, loading the sheet, setting a cell, saving
/// with the sheet loaded and edited, and saving without loading it. Run it
/// with `dart test benchmark` and `dart test -p chrome benchmark`; the quality
/// gate does not.
@Tags(<String>['benchmark'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show ArchiveFile, ZipDecoder;
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/model/cell_store.dart';
import 'package:jet_office/src/xlsx/model/worksheet_part.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/zip/archive_adapter.dart';
import 'package:test/test.dart';

import 'src/memory_probe.dart';
import 'src/workload_file.dart';

const int _rows = 100000;
const int _timedRuns = 3;

/// The part `XlsxWriter` writes the first sheet to.
const String _sheetPart = 'xl/worksheets/sheet1.xml';

/// The cells the workload writes: a header of 12, then 12 per data row but
/// for the `Note` column, which is `null` when `r % 3 == 0`.
int _expectedCells() {
  int cells = 12;
  for (int r = 1; r <= _rows; r++) {
    cells += r % 3 == 0 ? 11 : 12;
  }
  return cells;
}

/// The median of [_timedRuns] runs of [body], each timed alone, in
/// microseconds. [setUp] runs before each and is not timed; its result goes
/// to [body].
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
  final MemoryProbe peakProbe = probe();
  const String platform = _isWeb ? 'chrome' : 'vm';

  void line(String text) {
    // ignore: avoid_print
    print('$platform | $text');
  }

  late final Uint8List file;
  late final int sheetBytes;
  late final int cells;

  setUpAll(() {
    file = workloadFile(_rows);
    cells = _expectedCells();
    // The ZIP directory only: nothing is inflated before the memory runs.
    final ArchiveFile? sheet = ZipDecoder()
        .decodeBytes(file)
        .findFile(_sheetPart);
    expect(sheet, isNotNull, reason: 'the sheet is $_sheetPart');
    sheetBytes = sheet!.size;
    line(
      'input | ${file.length} bytes | $_sheetPart $sheetBytes bytes XML | '
      '$cells cells',
    );
  });

  test('retained store bytes', () {
    // The same load `XlsxSheet` does, so the store can be measured by what
    // it holds, not by what the process shows: `CellStore.
    // retainedBytesEstimate` sums the typed lists (capacity included), the
    // pooled strings and a constant per map entry. It is the same on every
    // platform, and it is the figure to compare with N, the sheet's XML.
    const XlsxReadLimits limits = XlsxReadLimits();
    final Uint8List xml = ZipReader(
      file,
      maxEntries: limits.maxEntries,
      maxEntryBytes: limits.maxEntryBytes,
      maxTotalBytes: limits.maxTotalBytes,
      maxCompressionRatio: limits.maxCompressionRatio,
    ).read(_sheetPart);
    final WorksheetPart part = WorksheetPart.read(
      XmlPullReader(utf8.decode(xml)),
      part: _sheetPart,
      limits: limits,
      warn: (XlsxWarningCode code, String? cell, {String? detail}) {},
    );
    final CellStore store = part.cells;
    expect(store.cellCount, cells);
    final int bytes = store.retainedBytesEstimate;
    line(
      'retained store | $bytes bytes | ${(bytes / cells).toStringAsFixed(1)} '
      'bytes/cell | store/N ${(bytes / sheetBytes).toStringAsFixed(3)} | N '
      '$sheetBytes bytes',
    );
  });

  test('memory of the loaded sheet', () {
    // A secondary figure: the loaded workbook's process memory above the
    // memory before it opened. It folds in the sheet's XML and decoded text,
    // garbage once parsed, and whatever the collector has not freed (the
    // VM's RSS does not fall when it does), so it is an upper bound on what
    // the store keeps; 'retained store bytes' is the figure that counts. The
    // workbook is held until after the last sample.
    final List<int> above = <int>[];
    final List<int> peakAbove = <int>[];
    final List<XlsxWorkbook> held = <XlsxWorkbook>[];
    for (int run = 0; run <= _timedRuns; run++) {
      final int? baseline = memory.sample();
      final int? peakBefore = peakProbe.sample();
      final XlsxWorkbook book = XlsxWorkbook.open(file);
      final int? opened = memory.sample();
      expect(book.sheets[0].cellAt(0, 0)?.value, 'Id');
      final int? loaded = memory.sample();
      final int? peak = peakProbe.sample();
      held.add(book);
      if (baseline != null && loaded != null) above.add(loaded - baseline);
      if (peak != null && baseline != null) peakAbove.add(peak - baseline);
      line(
        'model | ${run == 0 ? 'warm-up' : 'run $run'} | ${memory.unit} '
        'baseline ${baseline ?? 'n/a'} | after open ${opened ?? 'n/a'} | '
        'after load ${loaded ?? 'n/a'} | above baseline '
        '${baseline == null || loaded == null ? 'n/a' : loaded - baseline} '
        'bytes${_isWeb ? '' : ' | ${peakProbe.unit} ${peak ?? 'n/a'} '
                  '(was ${peakBefore ?? 'n/a'})'}',
      );
    }
    expect(held, hasLength(_timedRuns + 1));
    if (above.isEmpty) {
      line('memory/N | n/a');
      return;
    }
    // The largest reading of the runs, which includes the sheet's XML and
    // whatever the collector has not yet freed; the later runs, whose
    // baseline holds the earlier workbooks, read lower.
    final int most = above.reduce((int a, int b) => a > b ? a : b);
    line(
      'process | $most bytes above baseline (largest of ${above.length}) | '
      '${(most / cells).toStringAsFixed(1)} bytes/cell | memory/N '
      '${(most / sheetBytes).toStringAsFixed(2)} | N $sheetBytes bytes',
    );
    if (!_isWeb && peakAbove.isNotEmpty) {
      final int peakMost = peakAbove.reduce((int a, int b) => a > b ? a : b);
      line(
        'process peak | ${peakProbe.unit} above baseline $peakMost bytes | memory/N '
        '${(peakMost / sheetBytes).toStringAsFixed(2)}',
      );
    }
  });

  test('phases', () {
    final int open = _medianMicros<void>(() {}, (_) {
      XlsxWorkbook.open(file);
    });
    line('phase | open (verifies every entry) | ${_ms(open)} ms');

    final int load = _medianMicros<XlsxWorkbook>(
      () => XlsxWorkbook.open(file),
      (XlsxWorkbook book) => book.sheets[0].cellAt(0, 0),
    );
    line('phase | load the sheet (cellAt) | ${_ms(load)} ms');

    final int set = _medianMicros<XlsxSheet>(() {
      final XlsxSheet sheet = XlsxWorkbook.open(file).sheets[0];
      sheet.cellAt(0, 0);
      return sheet;
    }, (XlsxSheet sheet) => sheet.setCell(50000, 3, 'edited'));
    line('phase | set one cell (sheet loaded) | ${_ms(set)} ms');

    late Uint8List saved;
    final int save = _medianMicros<XlsxWorkbook>(() {
      final XlsxWorkbook book = XlsxWorkbook.open(file);
      book.sheets[0].setCell(50000, 3, 'edited');
      return book;
    }, (XlsxWorkbook book) => saved = book.save().bytes);
    line(
      'phase | save (sheet loaded and edited) | ${_ms(save)} ms | '
      '${saved.length} bytes',
    );

    final int untouched = _medianMicros<XlsxWorkbook>(
      () => XlsxWorkbook.open(file),
      (XlsxWorkbook book) => book.save(),
    );
    line('phase | save (sheet never loaded) | ${_ms(untouched)} ms');

    final int total = _medianMicros<void>(() {}, (_) {
      final XlsxWorkbook book = XlsxWorkbook.open(file);
      book.sheets[0].setCell(50000, 3, 'edited');
      book.save();
    });
    line('phase | open, set one cell, save | ${_ms(total)} ms');

    // The measured edit is the one the file holds.
    final XlsxReader reader = XlsxReader(saved);
    final XlsxReadRow row = reader
        .rowsAt(0)
        .firstWhere((XlsxReadRow r) => r.index == 50000);
    expect(
      row.cells.firstWhere((XlsxReadCell c) => c.column == 3).value,
      'edited',
    );
  });
}
