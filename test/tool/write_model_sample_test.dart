// Tests tool/write_model_sample.dart: the generated workbook of the W1 Excel
// check. It writes a file, so it runs on the VM only.
@TestOn('vm')
library;

import 'dart:io';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/write_model_sample.dart';

void main() {
  test('writes a workbook the reader reads back, with the values listed', () {
    final Directory temp = Directory.systemTemp.createTempSync('model_sample');
    addTearDown(() => temp.deleteSync(recursive: true));
    final String path = writeModelSample('${temp.path}/out');
    expect(path, endsWith('w1_generated.xlsx'));
    final XlsxReader reader = XlsxReader(File(path).readAsBytesSync());
    expect(reader.sheets.map((XlsxReadSheet s) => s.name), <String>[
      'Values',
      'Second',
    ]);
    final List<XlsxReadRow> rows = reader.rows('Values').toList();
    expect(rows.first.cells.first.value, 'jet_office');
    expect(rows[1].cells.first.value, 'jet_office');
    // Each row's formula sums its own row.
    expect(rows[0].cells.last.formula, 'SUM(B1:C1)');
    expect(rows[1].cells.last.formula, 'SUM(B2:C2)');
    expect(reader.warnings, isEmpty);
  });
}
