// A chart the model holds (added this session) follows a structural edit:
// its references shift through the formula rewriter, it lists typed with
// them, its caches stay as written, and undo gives the file back.
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/formula/formula_rewrite.dart';
import 'package:jet_office/src/xlsx/formula/reference_shift.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';

/// A two-series column chart of four quarters, unbound.
final Chart _two = Chart(
  kind: ChartKind.column,
  series: <ChartSeries>[
    ChartSeries(
      name: ChartData<String>(values: const <String?>['Sales']),
      categories: ChartData<Object>(
        values: const <Object?>['Q1', 'Q2', 'Q3', 'Q4'],
      ),
      values: ChartData<double>(values: const <double?>[1, 2, 3, 4]),
    ),
    ChartSeries(
      name: ChartData<String>(values: const <String?>['Costs']),
      categories: ChartData<Object>(
        values: const <Object?>['Q1', 'Q2', 'Q3', 'Q4'],
      ),
      values: ChartData<double>(values: const <double?>[5, 6, 7, 8]),
    ),
  ],
);

const XlsxAnchor _anchor = XlsxTwoCellAnchor(
  XlsxAnchorPoint(4, 1),
  XlsxAnchorPoint(12, 16),
);

/// A new workbook whose sheet `Data` holds [_two]'s data at A1 and a chart
/// added on it, bound to that data.
({XlsxWorkbook book, XlsxSheet sheet}) _held() {
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet sheet = book.addSheet('Data');
  sheet.addChart(XlsxChart(sheet.writeChartData(_two, 0, 0), _anchor));
  return (book: book, sheet: sheet);
}

void main() {
  group('a chart the model holds', () {
    test('insertRows shifts an added chart; it lists typed, caches stay', () {
      final (:XlsxWorkbook book, :XlsxSheet sheet) = _held();
      // Listed before the edit, so the listing holds the part as added.
      expect(
        sheet.charts.single.typed!.chart.series[0].values.reference,
        r'Data!$B$2:$B$5',
      );
      final XlsxChangeSet insert = book.transaction(
        () => sheet.insertRows(0, 2),
      );
      final ChartSeries first = sheet.charts.single.typed!.chart.series[0];
      expect(first.values.reference, r'Data!$B$4:$B$7');
      expect(first.categories.reference, r'Data!$A$4:$A$7');
      expect(first.name.reference, r'Data!$B$3');
      expect(first.values.values, <double?>[1, 2, 3, 4]);
      expect(first.name.values, <String?>['Sales']);
      expect(
        sheet.charts.single.typed!.chart.series[1].values.reference,
        r'Data!$C$4:$C$7',
      );
      final String part = readXlsx(book.save().bytes)['xl/charts/chart1.xml']!;
      expect(part, contains(r'<c:f>Data!$B$4:$B$7</c:f>'));
      expect(part, contains('<c:v>Sales</c:v>'));
      expect(book.warnings, isEmpty);
      book.undo(insert);
      expect(
        sheet.charts.single.typed!.chart.series[0].values.reference,
        r'Data!$B$2:$B$5',
      );
      book.redo(insert);
      expect(
        sheet.charts.single.typed!.chart.series[0].values.reference,
        r'Data!$B$4:$B$7',
      );
    });

    test("renameSheet to 'Veri 2026' quotes the added chart's references", () {
      final (:XlsxWorkbook book, :XlsxSheet sheet) = _held();
      sheet.insertRows(0, 2);
      book.renameSheet(sheet, 'Veri 2026');
      expect(
        sheet.charts.single.typed!.chart.series[0].values.reference,
        r"'Veri 2026'!$B$4:$B$7",
      );
      expect(
        readXlsx(book.save().bytes)['xl/charts/chart1.xml'],
        contains(r"<c:f>'Veri 2026'!$B$4:$B$7</c:f>"),
      );
    });

    test("deleteRows over a series' values gives the rewriter's #REF!", () {
      final (:XlsxWorkbook book, :XlsxSheet sheet) = _held();
      final String expected = rewriteFormula(
        r'Data!$B$2:$B$5',
        ReferenceShift.delete('Data', ShiftAxis.rows, 2, 4),
        'Data',
      )!;
      expect(expected, r'Data!#REF!');
      sheet.deleteRows(1, 4);
      expect(sheet.charts, hasLength(1));
      expect(
        readXlsx(book.save().bytes)['xl/charts/chart1.xml'],
        contains('<c:f>$expected</c:f>'),
      );
      final XlsxChart typed = sheet.charts.single.typed!;
      expect(typed.chart.series[0].values.reference, expected);
      expect(typed.chart.series[0].values.values, <double?>[1, 2, 3, 4]);
      expect(book.warnings, isEmpty);
    });

    test('add, insertRows, replace, then undo in reverse gives the file '
        'back', () {
      final Uint8List bytes = allFixtures()
          .firstWhere((Fixture f) => f.name == 'c1_kinds')
          .build();
      final XlsxWorkbook book = XlsxWorkbook.open(bytes);
      final XlsxSheet sheet = book.sheet('Data');
      final XlsxChangeSet add = book.transaction(
        () => sheet.addChart(XlsxChart(_two, _anchor)),
      );
      final XlsxChangeSet insert = book.transaction(
        () => sheet.insertRows(0, 1),
      );
      expect(
        sheet.charts.first.typed!.chart.series.first.values.reference,
        r'Data!$B$3:$B$6',
      );
      final XlsxChangeSet replace = book.transaction(
        () => sheet.replaceChartAt(
          0,
          sheet.charts.first.typed!.chart.copyWith(
            title: const ChartTitle(text: 'Replaced'),
          ),
        ),
      );
      book
        ..undo(replace)
        ..undo(insert)
        ..undo(add);
      expect(
        comparePackages(bytes, book.save().bytes, ignoreBookkeeping: true),
        isEmpty,
      );
    });

    test('add, insertRows, then replace that added chart; undo all gives '
        'the file back', () {
      final Uint8List bytes = allFixtures()
          .firstWhere((Fixture f) => f.name == 'c1_kinds')
          .build();
      final XlsxWorkbook book = XlsxWorkbook.open(bytes);
      final XlsxSheet sheet = book.sheet('Data');
      final XlsxChangeSet add = book.transaction(
        () => sheet.addChart(
          XlsxChart(sheet.writeChartData(_two, 30, 10), _anchor),
        ),
      );
      expect(sheet.charts, hasLength(13));
      expect(
        sheet.charts.last.typed!.chart.series[0].values.reference,
        r'Data!$L$32:$L$35',
      );
      final XlsxChangeSet insert = book.transaction(
        () => sheet.insertRows(0, 1),
      );
      final Chart shifted = sheet.charts.last.typed!.chart;
      expect(shifted.series[0].values.reference, r'Data!$L$33:$L$36');
      final Chart replacement = shifted.copyWith(
        title: const ChartTitle(text: 'Replaced'),
      );
      final XlsxChangeSet replace = book.transaction(
        () => sheet.replaceChartAt(12, replacement),
      );
      expect(sheet.charts.last.typed!.chart, replacement);
      expect(
        readXlsx(book.save().bytes)['xl/charts/chart13.xml'],
        contains(r'<c:f>Data!$L$33:$L$36</c:f>'),
      );
      book.undo(replace);
      expect(sheet.charts.last.typed!.chart, shifted);
      book.undo(insert);
      expect(
        sheet.charts.last.typed!.chart.series[0].values.reference,
        r'Data!$L$32:$L$35',
      );
      book.undo(add);
      expect(sheet.charts, hasLength(12));
      expect(
        comparePackages(bytes, book.save().bytes, ignoreBookkeeping: true),
        isEmpty,
      );
    });
  });
}
