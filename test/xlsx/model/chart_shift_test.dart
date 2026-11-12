// The chart holder of a structural edit (W5, Ruling 10): every `c:f` (and
// chartex `cx:f`) follows the edit through the formula rewriter, and the
// caches stay as read for Excel to refresh.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/formula/formula_rewrite.dart';
import 'package:jet_office/src/xlsx/formula/reference_shift.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/workbook_builder.dart';
import '../read/support/zip_builder.dart';

final RegExp _f = RegExp('<c:f>([^<]*)</c:f>');

List<XlsxWarning> _apply(
  XlsxWorkbook book,
  ReferenceMapper mapper, [
  ReferenceShift? edit,
]) {
  late List<XlsxWarning> warnings;
  changeLogOf(
    book,
  ).transaction(() => warnings = referenceRegistryOf(book).apply(mapper, edit));
  return warnings;
}

Map<String, String> _charts(Map<String, String> parts) => <String, String>{
  for (final MapEntry<String, String> e in parts.entries)
    if (RegExp(r'^xl/charts/chart\d+\.xml$').hasMatch(e.key)) e.key: e.value,
};

/// [reference] (`Data!$A$2:$A$5`) with every row number one higher.
String _rowDown(String reference) => reference.replaceAllMapped(
  RegExp(r'(\$?[A-Z]+\$?)(\d+)'),
  (Match m) => '${m[1]}${int.parse(m[2]!) + 1}',
);

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
  test('every series formula of c1_kinds shifts and caches stay', () {
    final Uint8List bytes = allFixtures()
        .firstWhere((Fixture f) => f.name == 'c1_kinds')
        .build();
    final Map<String, String> before = _charts(readXlsx(bytes));
    expect(before, hasLength(12));
    final XlsxWorkbook book = XlsxWorkbook.open(bytes);
    final ReferenceShift edit = ReferenceShift.insert(
      'Data',
      ShiftAxis.rows,
      1,
      1,
    );
    expect(_apply(book, edit, edit), isEmpty);
    final Map<String, String> after = _charts(readXlsx(book.save().bytes));
    for (final String name in before.keys) {
      final String was = before[name]!;
      final String now = after[name]!;
      expect(_f.allMatches(was), isNotEmpty, reason: name);
      // Each formula moved one row down; everything else, caches included,
      // is as read.
      expect(
        now,
        was.replaceAllMapped(_f, (Match m) => '<c:f>${_rowDown(m[1]!)}</c:f>'),
        reason: name,
      );
    }
  });

  test("the owner's chart_reference.xlsx: a rename rewrites every c:f", () {
    final Uint8List bytes = File(
      'test/fixtures/owner/charts/chart_reference.xlsx',
    ).readAsBytesSync();
    final Map<String, String> before = _charts(readXlsx(bytes));
    final int count = before.values
        .map((String t) => _f.allMatches(t).length)
        .fold(0, (int a, int b) => a + b);
    expect(count, 138);
    final XlsxWorkbook book = XlsxWorkbook.open(bytes);
    expect(_apply(book, SheetRename('Veri', 'Yeni Veri')), isEmpty);
    final Map<String, String> after = _charts(readXlsx(book.save().bytes));
    int renamed = 0;
    for (final String name in before.keys) {
      final String now = after[name]!;
      for (final Match m in _f.allMatches(now)) {
        expect(m[1], startsWith("'Yeni Veri'!"), reason: name);
        renamed++;
      }
      expect(
        now,
        before[name]!.replaceAll('<c:f>Veri!', "<c:f>'Yeni Veri'!"),
        reason: name,
      );
    }
    expect(renamed, 138);
  });

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
  });

  group('parts built by hand', () {
    const String cNs = 'http://schemas.openxmlformats.org/drawingml/2006/chart';
    const String cxNs =
        'http://schemas.microsoft.com/office/drawing/2014/chartex';

    Uint8List withParts(Map<String, String> parts) {
      final Map<String, Uint8List> all = readXlsxBytes(
        buildWorkbook(<String, String>{'S': worksheet('')}),
      );
      parts.forEach((String name, String xml) {
        all[name] = Uint8List.fromList(utf8.encode(xml));
      });
      return buildZip(<String, List<int>>{...all});
    }

    test('a chartex cx:f follows the edit too', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        withParts(<String, String>{
          'xl/charts/chartEx1.xml':
              '<cx:chartSpace xmlns:cx="$cxNs"><cx:chartData><cx:data id="0">'
              '<cx:numDim type="val"><cx:f dir="row">S!\$A\$2:\$A\$5</cx:f>'
              '</cx:numDim></cx:data></cx:chartData></cx:chartSpace>',
        }),
      );
      final ReferenceShift edit = ReferenceShift.delete(
        'S',
        ShiftAxis.rows,
        1,
        1,
      );
      expect(_apply(book, edit, edit), isEmpty);
      expect(
        readXlsx(book.save().bytes)['xl/charts/chartEx1.xml'],
        contains(r'<cx:f dir="row">S!$A$1:$A$4</cx:f>'),
      );
    });

    test('an unreadable chart part warns and is kept', () {
      const String broken = '<c:chartSpace xmlns:c="$cNs"><c:f>S!A1</c:f>';
      final XlsxWorkbook book = XlsxWorkbook.open(
        withParts(<String, String>{'xl/charts/chart1.xml': broken}),
      );
      final ReferenceShift edit = ReferenceShift.insert(
        'S',
        ShiftAxis.rows,
        1,
        1,
      );
      final List<XlsxWarning> warnings = _apply(book, edit, edit);
      expect(warnings.map((XlsxWarning w) => w.code), <XlsxWarningCode>[
        XlsxWarningCode.referenceNotShifted,
      ]);
      expect(warnings.single.detail, startsWith('/xl/charts/chart1.xml: '));
      expect(readXlsx(book.save().bytes)['xl/charts/chart1.xml'], broken);
    });

    test('undo puts the chart part back as read', () {
      const String chart =
          '<c:chartSpace xmlns:c="$cNs"><c:f>S!\$B\$3</c:f></c:chartSpace>';
      final Uint8List bytes = withParts(<String, String>{
        'xl/charts/chart1.xml': chart,
      });
      final XlsxWorkbook book = XlsxWorkbook.open(bytes);
      final ReferenceShift edit = ReferenceShift.insert(
        'S',
        ShiftAxis.rows,
        1,
        2,
      );
      final set = changeLogOf(
        book,
      ).transaction(() => referenceRegistryOf(book).apply(edit, edit));
      expect(
        readXlsx(book.save().bytes)['xl/charts/chart1.xml'],
        contains(r'S!$B$5'),
      );
      changeLogOf(book).revertSet(set);
      expect(readXlsx(book.save().bytes)['xl/charts/chart1.xml'], chart);
      changeLogOf(book).reapplySet(set);
      expect(
        readXlsx(book.save().bytes)['xl/charts/chart1.xml'],
        contains(r'S!$B$5'),
      );
    });
  });
}
