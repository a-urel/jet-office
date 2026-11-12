import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart' show changeLogOf;
import 'package:test/test.dart';

import '../../support/read_xlsx.dart';
import '../read/support/workbook_builder.dart';

ChartSeries _series(
  String name,
  List<Object?> categories,
  List<double?> values, {
  String? formatCode,
}) => ChartSeries(
  name: ChartData<String>(values: <String?>[name]),
  categories: ChartData<Object>(values: categories),
  values: ChartData<double>(values: values),
  formatCode: formatCode,
);

Chart _chart(
  List<ChartSeries> series, {
  ChartKind kind = ChartKind.column,
  ChartAxis categoryAxis = const ChartAxis(),
}) => Chart(kind: kind, series: series, categoryAxis: categoryAxis);

Object? _value(XlsxSheet sheet, int row, int column) {
  final Object? v = sheet.cellAt(row, column)?.value;
  return v is XlsxDecimal ? v.toDouble() : v;
}

void main() {
  final Chart two = _chart(<ChartSeries>[
    _series('Sales', <Object?>['Q1', 'Q2', 'Q3', 'Q4'], <double?>[1, 2, 3, 4]),
    _series('Costs', <Object?>['Q1', 'Q2', 'Q3', 'Q4'], <double?>[5, 6, 7, 8]),
  ]);

  group('writeChartData', () {
    test("writes names, categories and values, quoting O'Brien", () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet("O'Brien");
      final Chart bound = sheet.writeChartData(two, 0, 0);
      expect(_value(sheet, 0, 0), isNull);
      expect(_value(sheet, 0, 1), 'Sales');
      expect(_value(sheet, 0, 2), 'Costs');
      expect(
        <Object?>[for (int r = 1; r <= 4; r++) _value(sheet, r, 0)],
        <Object?>['Q1', 'Q2', 'Q3', 'Q4'],
      );
      expect(
        <Object?>[for (int r = 1; r <= 4; r++) _value(sheet, r, 2)],
        <Object?>[5, 6, 7, 8],
      );
      expect(bound.series[0].name.reference, r"'O''Brien'!$B$1");
      expect(bound.series[0].categories.reference, r"'O''Brien'!$A$2:$A$5");
      expect(bound.series[0].values.reference, r"'O''Brien'!$B$2:$B$5");
      expect(bound.series[1].name.reference, r"'O''Brien'!$C$1");
      expect(bound.series[1].values.reference, r"'O''Brien'!$C$2:$C$5");
      expect(bound.series[1].values.values, two.series[1].values.values);
      expect(bound.series[0].name.values, <String?>['Sales']);
    });

    test('leaves a plain name unquoted and honours the origin', () {
      final XlsxSheet sheet = XlsxWorkbook().addSheet('Data');
      final Chart bound = sheet.writeChartData(two, 2, 3);
      expect(_value(sheet, 2, 4), 'Sales');
      expect(_value(sheet, 3, 3), 'Q1');
      expect(bound.series[0].name.reference, r'Data!$E$3');
      expect(bound.series[0].categories.reference, r'Data!$D$4:$D$7');
      expect(bound.series[1].values.reference, r'Data!$F$4:$F$7');
    });

    test('a series format code styles its value cells', () {
      final XlsxSheet sheet = XlsxWorkbook().addSheet('Data');
      sheet.writeChartData(
        _chart(<ChartSeries>[
          _series('A', <Object?>['x'], <double?>[1], formatCode: '0.00'),
        ]),
        0,
        0,
      );
      expect(sheet.styleAt(1, 1)!.numFmt!.code, '0.00');
    });

    test('date categories are date cells in the axis format', () {
      final XlsxSheet sheet = XlsxWorkbook().addSheet('Data');
      final DateTime day = DateTime(2026, 1, 1);
      final DateTime next = DateTime(2026, 1, 2);
      sheet.writeChartData(
        _chart(<ChartSeries>[
          _series('A', <Object?>[day, next], <double?>[1, 2]),
        ], categoryAxis: const ChartAxis(formatCode: 'mmm d')),
        0,
        0,
      );
      expect(_value(sheet, 1, 0), DateTime.utc(2026, 1, 1));
      expect(sheet.styleAt(1, 0)!.numFmt!.code, 'mmm d');
      final XlsxSheet plain = XlsxWorkbook().addSheet('P');
      plain.writeChartData(
        _chart(<ChartSeries>[
          _series('A', <Object?>[day], <double?>[1]),
        ]),
        0,
        0,
      );
      expect(plain.styleAt(1, 0)!.numFmt!.code, 'm/d/yyyy');
    });

    test('a 1904 workbook gets 1904 serials in cells and in the cache', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        buildWorkbook(<String, String>{
          'S': '<worksheet xmlns="$mainNs"><sheetData/></worksheet>',
        }, date1904: true),
      );
      final XlsxSheet sheet = book.sheet('S');
      final Chart bound = sheet.writeChartData(
        _chart(<ChartSeries>[
          _series('A', <Object?>[DateTime(2026, 1, 1)], <double?>[1]),
        ]),
        0,
        0,
      );
      sheet.addChart(
        XlsxChart(
          bound,
          const XlsxTwoCellAnchor(
            XlsxAnchorPoint(5, 5),
            XlsxAnchorPoint(20, 12),
          ),
        ),
      );
      final Map<String, Uint8List> parts = readXlsxBytes(book.save().bytes);
      expect(
        utf8.decode(parts['xl/worksheets/sheet1.xml']!),
        contains('<v>44561</v>'),
      );
      expect(
        utf8.decode(parts['xl/charts/chart1.xml']!),
        contains('<c:v>44561</c:v>'),
      );
    });

    test('a scatter series takes an x column then a y column', () {
      final XlsxSheet sheet = XlsxWorkbook().addSheet('Data');
      final Chart bound = sheet.writeChartData(
        _chart(<ChartSeries>[
          _series('A', <Object?>[1.5, 2.5], <double?>[10, 20]),
          _series('B', <Object?>[3, 4], <double?>[30, 40]),
        ], kind: ChartKind.scatter),
        0,
        0,
      );
      expect(_value(sheet, 0, 0), isNull);
      expect(_value(sheet, 0, 1), 'A');
      expect(_value(sheet, 0, 3), 'B');
      expect(_value(sheet, 1, 0), 1.5);
      expect(_value(sheet, 2, 1), 20);
      expect(_value(sheet, 2, 2), 4);
      expect(_value(sheet, 1, 3), 30);
      expect(bound.series[0].categories.reference, r'Data!$A$2:$A$3');
      expect(bound.series[0].values.reference, r'Data!$B$2:$B$3');
      expect(bound.series[0].name.reference, r'Data!$B$1');
      expect(bound.series[1].categories.reference, r'Data!$C$2:$C$3');
      expect(bound.series[1].values.reference, r'Data!$D$2:$D$3');
    });

    test('a series with values only binds names and values', () {
      final XlsxSheet sheet = XlsxWorkbook().addSheet('Data');
      final Chart bound = sheet.writeChartData(
        _chart(<ChartSeries>[
          _series('A', const <Object?>[], <double?>[1, 2, 3]),
        ]),
        0,
        0,
      );
      expect(bound.series.single.categories.reference, isNull);
      expect(bound.series.single.values.reference, r'Data!$B$2:$B$4');
      expect(_value(sheet, 3, 1), 3);
    });

    test('a series longer than the categories extends the block', () {
      final XlsxSheet sheet = XlsxWorkbook().addSheet('Data');
      final Chart bound = sheet.writeChartData(
        _chart(<ChartSeries>[
          _series('A', <Object?>['a', 'b'], <double?>[1, 2, 3]),
        ]),
        0,
        0,
      );
      expect(bound.series.single.categories.reference, r'Data!$A$2:$A$3');
      expect(bound.series.single.values.reference, r'Data!$B$2:$B$4');
    });

    test(
      'a series whose categories are a prefix of the longest binds to it',
      () {
        final XlsxSheet sheet = XlsxWorkbook().addSheet('Data');
        final Chart bound = sheet.writeChartData(
          _chart(<ChartSeries>[
            _series('A', <Object?>['a', 'b', 'c'], <double?>[1, 2, 3]),
            _series('B', <Object?>['a', 'b'], <double?>[4, 5]),
            _series('C', <Object?>[], <double?>[6]),
          ]),
          0,
          0,
        );
        expect(
          <Object?>[for (int r = 1; r <= 3; r++) _value(sheet, r, 0)],
          <Object?>['a', 'b', 'c'],
        );
        expect(bound.series[0].categories.reference, r'Data!$A$2:$A$4');
        expect(bound.series[1].categories.reference, r'Data!$A$2:$A$3');
        expect(bound.series[2].categories.reference, isNull);
      },
    );

    test('categories that are not a prefix of the longest throw and change '
        'nothing', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('Data');
      sheet.setCell(0, 0, 'keep');
      final Uint8List before = book.save().bytes;
      final Chart other = _chart(<ChartSeries>[
        _series('A', <Object?>['a', 'b', 'c'], <double?>[1, 2, 3]),
        _series('B', <Object?>['x', 'y'], <double?>[4, 5]),
      ]);
      expect(
        () => sheet.writeChartData(other, 0, 0),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.toString(),
            'message',
            contains('chart.series[1].categories'),
          ),
        ),
      );
      expect(_value(sheet, 0, 0), 'keep');
      expect(_value(sheet, 1, 0), isNull);
      expect(book.save().bytes, before);
      // A scatter chart gives each series its own x column: no refusal.
      sheet.writeChartData(
        Chart(kind: ChartKind.scatter, series: other.series),
        5,
        0,
      );
    });

    test('a block leaving the sheet throws and changes nothing', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('Data');
      final int before = book.save().bytes.length;
      expect(() => sheet.writeChartData(two, 1048575, 0), throwsStateError);
      expect(() => sheet.writeChartData(two, 0, 16383), throwsStateError);
      expect(sheet.cellAt(1048575, 0), isNull);
      expect(sheet.cellAt(0, 16383), isNull);
      expect(book.save().bytes.length, before);
    });

    test('it is one change: undo restores the cells, redo writes them', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('Data');
      sheet.setCell(1, 1, 'old');
      final XlsxChangeSet set = book.transaction(
        () => sheet.writeChartData(two, 0, 0),
      );
      expect(_value(sheet, 1, 1), 1);
      book.undo(set);
      expect(_value(sheet, 1, 1), 'old');
      expect(_value(sheet, 0, 1), isNull);
      expect(_value(sheet, 4, 2), isNull);
      book.redo(set);
      expect(_value(sheet, 4, 2), 8);
      expect(changeLogOf(book), isNotNull);
    });
  });
}
