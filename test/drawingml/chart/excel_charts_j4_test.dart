@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../../support/read_xlsx.dart';
import 'support/excel_charts_j4.dart';

void main() {
  final Map<String, Uint8List> parts = readXlsxBytes(
    File(
      'test/fixtures/owner/charts/chart_reference_j4.xlsx',
    ).readAsBytesSync(),
  );

  test('chart_reference_j4.xlsx holds seven charts', () {
    expect(
      parts.keys.where(
        (String n) => RegExp(r'^xl/charts/chart\d+\.xml$').hasMatch(n),
      ),
      hasLength(excelJ4Charts.length),
    );
    expect(excelJ4Charts, hasLength(7));
  });

  for (int n = 1; n <= excelJ4Charts.length; n++) {
    test(
      'excelJ4Charts[${n - 1}] is chart$n.xml of chart_reference_j4.xlsx',
      () {
        expect(
          utf8.encode(excelJ4Charts[n - 1]),
          parts['xl/charts/chart$n.xml'],
        );
      },
    );
  }
}
