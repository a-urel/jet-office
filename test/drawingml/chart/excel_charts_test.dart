@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../support/read_xlsx.dart';
import 'support/excel_charts.dart';

void main() {
  final Map<String, Uint8List> parts = readXlsxBytes(
    File(
      'packages/jet_charts_core/test/fixtures/owner/axis_full/'
      'chart_defaults.xlsx',
    ).readAsBytesSync(),
  );

  test('excelColumnChart is chart1.xml of chart_defaults.xlsx', () {
    expect(utf8.encode(excelColumnChart), parts['xl/charts/chart1.xml']);
  });

  test('excelLineChart is chart2.xml of chart_defaults.xlsx', () {
    expect(utf8.encode(excelLineChart), parts['xl/charts/chart2.xml']);
  });
}
