/// The workbook model's generation benchmark: a workbook made from nothing
/// with `XlsxWorkbook()` and saved, as `XlsxWriter` and `XlsxStreamWriter`
/// write the same workload.
///
/// Not ported from Quds; written for jet_office. It records figures, it does
/// not judge them (docs/benchmark.md). The workload is the write benchmark's
/// (`src/workload.dart`): every cell goes in with `setCell`, the header and
/// its style with `setStyle`, the widths and column styles with `setColumn`.
/// Phases: filling the sheet, saving, both; the saved file is read back with
/// `XlsxReader` and must hold the last row's values. The 1,000,000-row case
/// runs once; in Chrome a failure for memory is printed and is not a test
/// failure. The writers run on the 100,000 workload in the same file, for the
/// side-by-side table; links and rules are added to a fresh sheet; structural
/// edits and their undos run on the generated sheet. Run it with
/// `dart test benchmark` and `dart test -p chrome benchmark`; the quality
/// gate does not.
@Tags(<String>['benchmark'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:typed_data';

import 'package:archive/archive.dart' show ZipDecoder;
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/model/xlsx_sheet.dart' show cellStoreOf;
import 'package:test/test.dart';

import '../test/support/event_loop.dart';
import 'src/memory_probe.dart';
import 'src/workload.dart';

const int _rows = 100000;
const int _bigRows = 1000000;
const int _timedRuns = 3;

// A double 0.0 is the integer 0 on JavaScript only.
const bool _isWeb = identical(0, 0.0);

/// The cells the workload writes: a header of 12, then 12 per data row but
/// for the `Note` column, which is `null` when `r % 3 == 0`.
int _expectedCells(int rows) {
  int cells = 12;
  for (int r = 1; r <= rows; r++) {
    cells += r % 3 == 0 ? 11 : 12;
  }
  return cells;
}

/// Stops [watch], gives the event loop a turn when one is due, and restarts
/// [watch]: the turn is not timed. In Chrome every suite shares one thread,
/// so a long loop must leave it now and then (AGENTS.md, "Fuzzing").
Future<void> _pause(Stopwatch watch, EventLoopBreather breather) async {
  watch.stop();
  await breather.breathe();
  watch.start();
}

/// Fills [sheet] with the workload's header and [rows] data rows, timed by
/// [watch], which the caller started.
Future<void> _fill(
  XlsxSheet sheet,
  int rows,
  Stopwatch watch,
  EventLoopBreather breather,
) async {
  for (int c = 0; c < workloadColumns.length; c++) {
    sheet.setColumn(c, workloadColumns[c]);
  }
  for (int c = 0; c < workloadHeader.length; c++) {
    sheet.setCell(0, c, workloadHeader[c]);
    sheet.setStyle(0, c, workloadHeaderStyle);
  }
  for (int r = 1; r <= rows; r++) {
    final List<Object?> values = workloadRow(r);
    for (int c = 0; c < values.length; c++) {
      final Object? value = values[c];
      if (value != null) sheet.setCell(r, c, value);
    }
    if (r % 1000 == 0) await _pause(watch, breather);
  }
}

/// One generated workbook and what it took.
typedef _Generated = ({
  XlsxWorkbook book,
  XlsxSheet sheet,
  Uint8List bytes,
  int fillMicros,
  int saveMicros,
});

/// Generates [rows] data rows and saves. The save is one synchronous call, so
/// it cannot give the thread back; at 1,000,000 rows it holds Chrome's for
/// 38 seconds.
Future<_Generated> _generate(int rows) async {
  final EventLoopBreather breather = EventLoopBreather();
  final Stopwatch watch = Stopwatch()..start();
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet sheet = book.addSheet('Data');
  await _fill(sheet, rows, watch, breather);
  final int fill = watch.elapsedMicroseconds;
  watch.reset();
  final Uint8List bytes = book.save().bytes;
  return (
    book: book,
    sheet: sheet,
    bytes: bytes,
    fillMicros: fill,
    saveMicros: watch.elapsedMicroseconds,
  );
}

int _median(List<int> values) {
  final List<int> sorted = List<int>.of(values)..sort();
  return sorted[sorted.length ~/ 2];
}

String _ms(int micros) => (micros / 1000).toStringAsFixed(1);

/// Reads [bytes] back and checks the last of [rows] data rows holds the
/// workload's values, and that no row follows it.
Future<void> _expectLastRow(Uint8List bytes, int rows) async {
  final EventLoopBreather breather = EventLoopBreather();
  int seen = 0;
  XlsxReadRow? last;
  // The 1,000,000-row sheet is 468,436,661 bytes of XML, past the default
  // limit of 256 MiB for one entry, so the limits are raised for the read.
  const XlsxReadLimits limits = XlsxReadLimits(
    maxEntryBytes: 1024 * 1024 * 1024,
    maxTotalBytes: 2 * 1024 * 1024 * 1024,
  );
  for (final XlsxReadRow row in XlsxReader(bytes, limits: limits).rowsAt(0)) {
    last = row;
    if (++seen % 10000 == 0) await breather.breathe();
  }
  expect(last, isNotNull);
  expect(last!.index, rows);
  XlsxReadCell cell(int column) =>
      last!.cells.firstWhere((XlsxReadCell c) => c.column == column);
  expect(cell(0).value, 'C-$rows');
  // The reader gives a number as an XlsxDecimal. The rows are multiples of 4,
  // so `rows * 1.25` is a whole number.
  expect(cell(2).value, XlsxDecimal('$rows'));
  expect(cell(3).value, XlsxDecimal('${rows * 5 ~/ 4}'));
  expect(cell(11).value, XlsxDecimal('${rows * 3}'));
}

/// A sink that keeps no bytes, only their number.
final class _CountingSink implements Sink<List<int>> {
  int bytes = 0;

  @override
  void add(List<int> data) => bytes += data.length;

  @override
  void close() {}
}

void main() {
  final MemoryProbe memory = currentProbe();
  const String platform = _isWeb ? 'chrome' : 'vm';

  void line(String text) {
    // ignore: avoid_print
    print('$platform | $text');
  }

  test('generate 100,000 x 12 with the model', () async {
    final int cells = _expectedCells(_rows);
    final List<int> fills = <int>[];
    final List<int> saves = <int>[];
    final List<int> totals = <int>[];
    late _Generated last;
    for (int run = 1; run <= _timedRuns; run++) {
      last = await _generate(_rows);
      fills.add(last.fillMicros);
      saves.add(last.saveMicros);
      totals.add(last.fillMicros + last.saveMicros);
      line(
        'generate | run $run | fill ${_ms(last.fillMicros)} ms | save '
        '${_ms(last.saveMicros)} ms | ${last.bytes.length} bytes',
      );
    }
    line(
      'phase | generate: fill (setCell of every cell) | ${_ms(_median(fills))} ms',
    );
    line('phase | generate: save | ${_ms(_median(saves))} ms');
    line(
      'phase | generate: fill and save | ${_ms(_median(totals))} ms | '
      '${last.bytes.length} bytes',
    );
    final int retained = cellStoreOf(last.sheet)!.retainedBytesEstimate;
    expect(cellStoreOf(last.sheet)!.cellCount, cells);
    line(
      'retained store | $retained bytes | '
      '${(retained / cells).toStringAsFixed(1)} bytes/cell | $cells cells',
    );
    await _expectLastRow(last.bytes, _rows);
    line('check | the saved file holds row $_rows');
  });

  test('memory of the generated workbook', () async {
    // As the model benchmark does: the reading before the workbook exists,
    // after the fill and after the save, the workbook still referenced; a
    // warm-up and three runs. It includes garbage the collector has not freed
    // (the VM's RSS never falls), so it is an upper bound.
    final List<int> above = <int>[];
    final List<_Generated> held = <_Generated>[];
    for (int run = 0; run <= _timedRuns; run++) {
      final int? baseline = memory.sample();
      final Stopwatch watch = Stopwatch()..start();
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('Data');
      await _fill(sheet, _rows, watch, EventLoopBreather());
      final int fill = watch.elapsedMicroseconds;
      final int? filled = memory.sample();
      final Uint8List bytes = book.save().bytes;
      final int? saved = memory.sample();
      held.add((
        book: book,
        sheet: sheet,
        bytes: bytes,
        fillMicros: fill,
        saveMicros: 0,
      ));
      if (baseline != null && saved != null) above.add(saved - baseline);
      line(
        'model | ${run == 0 ? 'warm-up' : 'run $run'} | ${memory.unit} '
        'baseline ${baseline ?? 'n/a'} | after fill ${filled ?? 'n/a'} | '
        'after save ${saved ?? 'n/a'} | above baseline '
        '${baseline == null || saved == null ? 'n/a' : saved - baseline} bytes',
      );
    }
    expect(held, hasLength(_timedRuns + 1));
    if (above.isEmpty) {
      line('process | n/a');
      return;
    }
    final int most = above.reduce((int a, int b) => a > b ? a : b);
    line(
      'process | $most bytes above baseline (largest of ${above.length}) | '
      '${(most / _expectedCells(_rows)).toStringAsFixed(1)} bytes/cell',
    );
  });

  test('the writers on the same 100,000 workload', () {
    final List<int> memoryTimes = <int>[];
    final List<int> streamTimes = <int>[];
    int memoryBytes = 0;
    int streamBytes = 0;
    for (int run = 1; run <= _timedRuns; run++) {
      final Stopwatch watch = Stopwatch()..start();
      final XlsxWriter writer = XlsxWriter();
      writeWorkload(writer.addSheet('Data'), _rows, (int _) {});
      memoryBytes = writer.close().bytes.length;
      memoryTimes.add(watch.elapsedMicroseconds);

      watch
        ..reset()
        ..start();
      // The writer closes the sink in close().
      // ignore: close_sinks
      final _CountingSink sink = _CountingSink();
      final XlsxStreamWriter stream = XlsxStreamWriter(sink);
      writeWorkload(stream.addSheet('Data'), _rows, (int _) {});
      stream.close();
      streamBytes = sink.bytes;
      streamTimes.add(watch.elapsedMicroseconds);
    }
    line(
      'phase | XlsxWriter, write and close | ${_ms(_median(memoryTimes))} ms '
      '| $memoryBytes bytes',
    );
    line(
      'phase | XlsxStreamWriter, write and close | '
      '${_ms(_median(streamTimes))} ms | $streamBytes bytes',
    );
  });

  test('links and rules on a fresh sheet', () async {
    final EventLoopBreather breather = EventLoopBreather();
    for (final int count in <int>[1000, 5000, 20000]) {
      final List<int> links = <int>[];
      final List<int> rules = <int>[];
      // The 20,000 rules take minutes each (the adds are quadratic), so that
      // size runs once.
      final int runs = count == 20000 ? 1 : _timedRuns;
      for (int run = 0; run < runs; run++) {
        XlsxSheet fresh() => XlsxWorkbook().addSheet('Links');
        XlsxSheet sheet = fresh();
        Stopwatch watch = Stopwatch()..start();
        for (int i = 0; i < count; i++) {
          sheet.setCell(
            i,
            0,
            XlsxHyperlink.url('https://example.com/item/$i', text: 'item $i'),
          );
          if (i % 100 == 99) await _pause(watch, breather);
        }
        links.add(watch.elapsedMicroseconds);
        expect(sheet.cellAt(count - 1, 0)?.value, 'item ${count - 1}');

        sheet = fresh();
        watch = Stopwatch()..start();
        for (int i = 0; i < count; i++) {
          sheet.addConditionalFormat(
            XlsxConditionalFormat(
              <XlsxRange>[XlsxRange(i, 0)],
              <XlsxConditionalRule>[
                XlsxCellValueRule(XlsxComparison.greaterThan, '$i'),
              ],
            ),
          );
          if (i % 100 == 99) await _pause(watch, breather);
        }
        rules.add(watch.elapsedMicroseconds);
        expect(sheet.conditionalFormats, hasLength(count));
      }
      line(
        'phase | $count links (setCell) | ${_ms(_median(links))} ms'
        '${runs == 1 ? ' (1 run)' : ''}',
      );
      line(
        'phase | $count rules (addConditionalFormat) | '
        '${_ms(_median(rules))} ms${runs == 1 ? ' (1 run)' : ''}',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 60)));

  test('structural edits on the generated sheet', () async {
    final _Generated generated = await _generate(_rows);
    final XlsxWorkbook book = generated.book;
    final XlsxSheet sheet = generated.sheet;
    final List<int> insert = <int>[];
    final List<int> undoInsert = <int>[];
    final List<int> delete = <int>[];
    final List<int> undoDelete = <int>[];
    for (int run = 0; run < _timedRuns; run++) {
      final Stopwatch watch = Stopwatch()..start();
      XlsxChangeSet set = book.transaction(() => sheet.insertRows(1));
      insert.add(watch.elapsedMicroseconds);
      watch
        ..reset()
        ..start();
      book.undo(set);
      undoInsert.add(watch.elapsedMicroseconds);
      watch
        ..reset()
        ..start();
      set = book.transaction(() => sheet.deleteColumns(0));
      delete.add(watch.elapsedMicroseconds);
      watch
        ..reset()
        ..start();
      book.undo(set);
      undoDelete.add(watch.elapsedMicroseconds);
    }
    line('phase | insertRows(1) | ${_ms(_median(insert))} ms');
    line('phase | undo of insertRows | ${_ms(_median(undoInsert))} ms');
    line('phase | deleteColumns(0) | ${_ms(_median(delete))} ms');
    line('phase | undo of deleteColumns | ${_ms(_median(undoDelete))} ms');
    // The edits and their undos leave the sheet as it was.
    await _expectLastRow(book.save().bytes, _rows);
    line('check | after the undos the saved file holds row $_rows');
  });

  test('generate 1,000,000 x 12 with the model', () async {
    // One run: in Chrome a failure for memory is the figure.
    try {
      final int cells = _expectedCells(_bigRows);
      final _Generated g = await _generate(_bigRows);
      final int retained = cellStoreOf(g.sheet)!.retainedBytesEstimate;
      expect(cellStoreOf(g.sheet)!.cellCount, cells);
      line(
        '1m | fill ${_ms(g.fillMicros)} ms | save ${_ms(g.saveMicros)} ms | '
        'total ${_ms(g.fillMicros + g.saveMicros)} ms | ${g.bytes.length} '
        'bytes | retained store $retained bytes | $cells cells',
      );
      // The ZIP directory only: the entry's declared size.
      line(
        '1m | sheet XML | ${ZipDecoder().decodeBytes(g.bytes).findFile('xl/worksheets/sheet1.xml')!.size} bytes',
      );
      await _expectLastRow(g.bytes, _bigRows);
      line('1m | check | the saved file holds row $_bigRows');
    } on TestFailure {
      rethrow;
    } catch (error) {
      if (!_isWeb) rethrow;
      line('1m | failed: $error');
    }
  }, timeout: const Timeout(Duration(minutes: 60)));
}
