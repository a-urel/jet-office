/// `XlsxSheet.charts` on the owner's Excel workbooks with charts.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/chart.dart' show xlsxChartIds;
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart' show changeLogOf;
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../support/read_xlsx.dart';

const String _reference = 'test/fixtures/owner/charts/chart_reference.xlsx';
const String _referenceJ4 =
    'test/fixtures/owner/charts/chart_reference_j4.xlsx';
const String _defaults =
    'packages/jet_charts_core/test/fixtures/owner/axis_full/'
    'chart_defaults.xlsx';

Uint8List _bytes(String path) => File(path).readAsBytesSync();

/// What a drawing's root holds, between its start and end tags.
String _drawingBody(String xml) {
  final int root = xml.indexOf('wsDr');
  final int start = xml.indexOf('>', root) + 1;
  return xml.substring(start, xml.lastIndexOf('</'));
}

/// Runs [edit] on the first sheet of [input] as one transaction and checks
/// its undo gives the input back.
void _undone(Uint8List input, void Function(XlsxSheet sheet) edit) {
  final XlsxWorkbook book = XlsxWorkbook.open(input);
  final ChangeLog log = changeLogOf(book);
  final ChangeSet set = log.transaction(() => edit(book.sheets.first));
  log.revertSet(set);
  expect(
    comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
    isEmpty,
  );
}

final Chart _pie = Chart(
  kind: ChartKind.pie,
  series: <ChartSeries>[
    ChartSeries(
      name: ChartData<String>(values: const <String?>['Share']),
      categories: ChartData<Object>(values: const <Object?>['a', 'b']),
      values: ChartData<double>(values: const <double?>[1, 2]),
    ),
  ],
);

void main() {
  test('chart_reference.xlsx lists 23 charts, all typed but chart 13', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_bytes(_reference));
    final List<XlsxSheetChart> charts = book.sheet('Veri').charts;
    expect(charts, hasLength(23));
    for (int i = 0; i < 23; i++) {
      expect(charts[i].name, 'Grafik ${i + 1}');
      expect(charts[i].view, isNotNull, reason: 'chart ${i + 1}');
      if (i == 12) {
        expect(charts[i].typed, isNull);
      } else {
        expect(charts[i].typed, isNotNull, reason: 'chart ${i + 1}');
        expect(charts[i].typed!.language, 'tr-TR');
      }
    }
    expect(
      charts.first.anchor,
      const XlsxTwoCellAnchor(XlsxAnchorPoint(0, 4), XlsxAnchorPoint(15, 12)),
    );
    expect(book.warnings, isEmpty);
  });

  test('chart_reference_j4.xlsx lists 7 charts, all typed but the '
      'combination with a negative value', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_bytes(_referenceJ4));
    final List<XlsxSheetChart> charts = book.sheet('Veri').charts;
    expect(charts, hasLength(7));
    for (int i = 0; i < 7; i++) {
      expect(charts[i].name, 'Grafik ${i + 1}');
      if (i == 4) {
        expect(charts[i].typed, isNull);
        expect(charts[i].view!.kind, ChartKind.combination);
      } else {
        expect(charts[i].typed, isNotNull, reason: 'chart ${i + 1}');
      }
    }
    // Chart 1 from A6 (rowOff 190500 EMU) to F20 (colOff 444500, rowOff
    // 88900).
    expect(
      charts.first.anchor,
      const XlsxTwoCellAnchor(
        XlsxAnchorPoint(5, 0, offsetY: 20),
        XlsxAnchorPoint(19, 5, offsetX: 444500 / 9525, offsetY: 88900 / 9525),
      ),
    );
    expect(book.warnings, isEmpty);
  });

  test('chart_defaults.xlsx lists 2 charts, both typed', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_bytes(_defaults));
    final List<XlsxSheetChart> charts = book.sheet('Sayfa1').charts;
    expect(charts, hasLength(2));
    expect(charts.map((XlsxSheetChart c) => c.view!.kind), <ChartKind>[
      ChartKind.column,
      ChartKind.line,
    ]);
    expect(charts.every((XlsxSheetChart c) => c.typed != null), isTrue);
    expect(book.warnings, isEmpty);
  });

  test('saving chart_reference.xlsx after reading its charts keeps every '
      'chart part', () {
    final Uint8List input = _bytes(_reference);
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    expect(book.sheet('Veri').charts, hasLength(23));
    final Map<String, Uint8List> before = readXlsxBytes(input);
    final Map<String, Uint8List> after = readXlsxBytes(book.save().bytes);
    int checked = 0;
    for (final String name in before.keys) {
      if (!name.startsWith('xl/charts/')) continue;
      expect(after[name], before[name], reason: name);
      checked++;
    }
    expect(checked, greaterThanOrEqualTo(23));
  });

  test('addChart on chart_reference.xlsx adds chart24.xml and keeps the 23 '
      'parts and every entry of the drawing', () {
    final Uint8List input = _bytes(_reference);
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    final XlsxSheet sheet = book.sheet('Veri');
    final XlsxChart first = sheet.charts.first.typed!;
    sheet.addChart(
      XlsxChart(
        first.chart,
        const XlsxTwoCellAnchor(XlsxAnchorPoint(60, 0), XlsxAnchorPoint(75, 8)),
      ),
    );
    final Map<String, Uint8List> before = readXlsxBytes(input);
    final Map<String, Uint8List> after = readXlsxBytes(book.save().bytes);
    expect(after.keys, contains('xl/charts/chart24.xml'));
    for (final String name in before.keys) {
      if (name.startsWith('xl/charts/')) {
        expect(after[name], before[name], reason: name);
      }
    }
    final String drawing = _drawingBody(
      utf8.decode(after['xl/drawings/drawing1.xml']!),
    );
    expect(
      drawing.startsWith(
        _drawingBody(utf8.decode(before['xl/drawings/drawing1.xml']!)),
      ),
      isTrue,
    );
    expect(drawing, contains('name="Chart 1"'));
    final List<XlsxSheetChart> charts = XlsxWorkbook.open(
      book.save().bytes,
    ).sheet('Veri').charts;
    expect(charts, hasLength(24));
    expect(charts.last.typed!.chart, first.chart);
    expect(charts.last.typed!.language, 'en-US');
    _undone(input, (XlsxSheet s) => s.addChart(first));
  });

  test('replaceChartAt(0, pie) on chart_reference.xlsx keeps the anchor and '
      'series ids and drops style1.xml and colors1.xml', () {
    final Uint8List input = _bytes(_reference);
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    final XlsxSheet sheet = book.sheet('Veri');
    final XlsxSheetChart old = sheet.charts.first;
    expect(old.view!.kind, isNot(ChartKind.pie));
    sheet.replaceChartAt(0, _pie);
    final Map<String, Uint8List> after = readXlsxBytes(book.save().bytes);
    expect(after.keys, isNot(contains('xl/charts/style1.xml')));
    expect(after.keys, isNot(contains('xl/charts/colors1.xml')));
    expect(after.keys, contains('xl/charts/style2.xml'));
    final XlsxSheetChart now = XlsxWorkbook.open(
      book.save().bytes,
    ).sheet('Veri').charts.first;
    expect(now.anchor, old.anchor);
    expect(now.name, old.name);
    expect(now.typed!.chart, _pie);
    expect(now.typed!.language, 'tr-TR');
    expect(
      xlsxChartIds(now.typed!)!.series,
      xlsxChartIds(old.typed!)!.series.take(1),
    );
    _undone(input, (XlsxSheet s) => s.replaceChartAt(0, _pie));
  });

  test('removing every chart of chart_defaults.xlsx removes the drawing and '
      '<drawing>', () {
    final Uint8List input = _bytes(_defaults);
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    final XlsxSheet sheet = book.sheet('Sayfa1');
    sheet
      ..removeChartAt(1)
      ..removeChartAt(0);
    final Map<String, Uint8List> after = readXlsxBytes(book.save().bytes);
    expect(
      after.keys.where(
        (String n) =>
            n.startsWith('xl/drawings/') || n.startsWith('xl/charts/'),
      ),
      isEmpty,
    );
    for (final String name in after.keys) {
      if (name.startsWith('xl/worksheets/sheet')) {
        expect(utf8.decode(after[name]!), isNot(contains('<drawing')));
      }
    }
    _undone(input, (XlsxSheet s) {
      s
        ..removeChartAt(1)
        ..removeChartAt(0);
    });
  });
}
