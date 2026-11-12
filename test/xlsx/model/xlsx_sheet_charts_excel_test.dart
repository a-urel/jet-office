/// `XlsxSheet.charts` on the owner's Excel workbooks with charts.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../support/read_xlsx.dart';

const String _reference = 'test/fixtures/owner/charts/chart_reference.xlsx';
const String _referenceJ4 =
    'test/fixtures/owner/charts/chart_reference_j4.xlsx';
const String _defaults =
    'packages/jet_charts_core/test/fixtures/owner/axis_full/'
    'chart_defaults.xlsx';

Uint8List _bytes(String path) => File(path).readAsBytesSync();

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
}
