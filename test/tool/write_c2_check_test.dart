// Tests tool/write_c2_check.dart: the files of the owner's C2 Excel check.
// It writes files and reads the owner's workbooks, so it runs on the VM only.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';
import '../../tool/write_c2_check.dart';

void main() {
  late Directory temp;
  late List<String> written;

  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('c2_check');
    written = writeC2Check('${temp.path}/c2');
  });
  tearDownAll(() => temp.deleteSync(recursive: true));

  String path(String name) => '${temp.path}/c2/$name';
  XlsxWorkbook open(String name) =>
      XlsxWorkbook.open(File(path(name)).readAsBytesSync());
  Uint8List owner(String name) =>
      File('test/fixtures/owner/charts/$name').readAsBytesSync();

  test('writes the five workbooks and the c2_edited folder', () {
    expect(
      <String>[
        for (final String p in written) p.substring(temp.path.length + 4),
      ],
      <String>[
        'c2_kinds.xlsx',
        'c2_data.xlsx',
        'c1_kinds.xlsx',
        'c1_options.xlsx',
        'c2_dashboard.xlsx',
        'c2_edited/chart_reference.xlsx',
        'c2_edited/chart_reference_undone.xlsx',
        'c2_edited/chart_reference_j4.xlsx',
        'c2_edited/chart_reference_j4_undone.xlsx',
      ],
    );
  });

  test('every written workbook opens with the model and lists its charts', () {
    for (final String p in written) {
      final XlsxWorkbook book = XlsxWorkbook.open(File(p).readAsBytesSync());
      expect(
        book.sheets.expand((XlsxSheet s) => s.charts),
        isNotEmpty,
        reason: p,
      );
    }
  });

  test('the fixtures are written as the fixture list builds them', () {
    final XlsxWorkbook kinds = open('c2_kinds.xlsx');
    expect(kinds.sheet('Data').charts, hasLength(7));
    expect(open('c1_kinds.xlsx').sheet('Data').charts, hasLength(12));
    expect(open('c1_options.xlsx').sheet("O'Brien").charts, hasLength(6));
    expect(open('c2_data.xlsx').sheet('Pano').charts, hasLength(3));
  });

  group('c2_dashboard', () {
    late XlsxWorkbook book;
    setUpAll(() => book = open('c2_dashboard.xlsx'));

    test('has Veri and Pano, opening on Pano', () {
      expect(book.sheets.map((XlsxSheet s) => s.name), <String>[
        'Veri',
        'Pano',
      ]);
      expect(book.activeSheet.name, 'Pano');
      expect(book.sheet('Veri').charts, isEmpty);
    });

    test('Pano holds the eight charts, bound to Veri', () {
      final List<XlsxSheetChart> charts = book.sheet('Pano').charts;
      expect(charts.map((XlsxSheetChart c) => c.view!.kind), <ChartKind>[
        ChartKind.column,
        ChartKind.bar,
        ChartKind.line,
        ChartKind.area,
        ChartKind.pie,
        ChartKind.donut,
        ChartKind.scatter,
        ChartKind.combination,
      ]);
      expect(charts[1].view!.grouping, ChartGrouping.stacked);
      final Chart combo = charts[7].view!;
      expect(combo.series.map((ChartSeries s) => s.kind), <ChartKind?>[
        ChartKind.column,
        ChartKind.line,
      ]);
      expect(combo.series[1].axis, ChartAxisBinding.secondary);
      for (final XlsxSheetChart c in charts) {
        for (final ChartSeries s in c.view!.series) {
          expect(s.values.reference, startsWith(r'Veri!$'), reason: c.name);
        }
      }
    });

    test('the cells hold the data the charts show', () {
      final XlsxSheet veri = book.sheet('Veri');
      final Chart column = book.sheet('Pano').charts.first.view!;
      expect(column.series.first.values.reference, r'Veri!$B$2:$B$5');
      expect(veri.cellAt(0, 1)?.value, 'North');
      expect(veri.cellAt(1, 0)?.value, 'Q1');
      expect((veri.cellAt(1, 1)?.value as XlsxDecimal?)?.toIntOrNull(), 12);
    });

    test('every chart but the app theme one lists typed in the Office '
        'theme', () {
      final List<XlsxSheetChart> charts = book.sheet('Pano').charts;
      for (final (int i, XlsxSheetChart c) in charts.indexed) {
        if (i == 2) continue; // The app theme with fixed colours.
        expect(c.typed, isNotNull, reason: c.name);
      }
    });
  });

  group('c2_edited', () {
    for (final (String name, int count) in <(String, int)>[
      ('chart_reference', 23),
      ('chart_reference_j4', 7),
    ]) {
      test('$name: chart 1 a pie, chart 2 moved, chart 3 removed, rows '
          'inserted, the sheet renamed, a chart added', () {
        final XlsxWorkbook before = XlsxWorkbook.open(owner('$name.xlsx'));
        final List<XlsxSheetChart> old = before.sheet('Veri').charts;
        final XlsxWorkbook book = open('c2_edited/$name.xlsx');
        expect(book.sheets.map((XlsxSheet s) => s.name), contains('Veri 2026'));
        final List<XlsxSheetChart> charts = book.sheet('Veri 2026').charts;
        expect(charts, hasLength(count));
        expect(charts.first.view!.kind, ChartKind.pie);
        expect(charts.first.typed, isNotNull);
        expect(
          charts.first.view!.series.single.values.reference,
          startsWith("'Veri 2026'!"),
        );
        // Chart 2 moved ten rows down, then two more with the inserted rows
        // (they are above it).
        expect(charts[1].anchor.from.row, old[1].anchor.from.row + 10 + 2);
        // Chart 3 is gone: chart 4 is now the third.
        expect(charts[2].name, old[3].name);
        expect(charts.last.name, 'Eklenen grafik');
        expect(charts.last.typed, isNotNull);
        for (final ChartSeries s in charts.last.view!.series) {
          expect(s.values.reference, startsWith("'Veri 2026'!"));
        }
      });

      test('$name: the undone file equals the original but its spans', () {
        expect(
          comparePackages(
            owner('$name.xlsx'),
            File(path('c2_edited/${name}_undone.xlsx')).readAsBytesSync(),
            ignoreBookkeeping: true,
          ),
          isEmpty,
        );
      });
    }
  });

  test('runC2Check: exit 2 on bad arguments', () {
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();
    expect(runC2Check(<String>[], out: out, err: err), 2);
    expect(err.toString(), contains('usage'));
    expect(runC2Check(<String>['a', 'b'], out: out, err: err), 2);
  });

  test('runC2Check: exit 0 and the paths printed', () {
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();
    expect(
      runC2Check(<String>['${temp.path}/again'], out: out, err: err),
      0,
      reason: '$err',
    );
    expect(out.toString(), contains('c2_dashboard.xlsx'));
    expect(err.toString(), isEmpty);
  });
}
