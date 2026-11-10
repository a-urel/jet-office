// Tests tool/write_w5_check.dart: the workbooks of the owner's W5 Excel
// check. It writes files, so it runs on the VM only.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/write_w5_check.dart';
import '../support/read_xlsx.dart';

void main() {
  late Directory temp;
  late Map<String, String> paths;

  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('w5_check');
    paths = <String, String>{
      for (final String p in writeW5Check('${temp.path}/w5'))
        p.split('/').last: p,
    };
  });
  tearDownAll(() => temp.deleteSync(recursive: true));

  XlsxReader read(String name) =>
      XlsxReader(File(paths[name]!).readAsBytesSync());

  /// The formula in [column] of each row of [sheet] by its label in A.
  Map<String, String?> formulas(XlsxReader reader, String sheet, int column) =>
      <String, String?>{
        for (final XlsxReadRow r in reader.rows(sheet).skip(1))
          '${r.cells.first.value}': <XlsxReadCell>[
            for (final XlsxReadCell c in r.cells)
              if (c.column == column) c,
          ].firstOrNull?.formula,
      };

  test('writes the six files', () {
    expect(paths.keys, <String>[
      'w5_generated.xlsx',
      'w5_rows.xlsx',
      'w5_charts.xlsx',
      'w5_rename.xlsx',
      'w5_chart_reference.xlsx',
      'w5_objects.xlsx',
    ]);
  });

  test('w5_rows: each formula equals the formula expected beside it', () {
    final XlsxReader reader = read('w5_rows.xlsx');
    final List<XlsxReadRow> rows = reader.rows('Checks').toList();
    expect(rows.first.cells.map((XlsxReadCell c) => c.value), <Object?>[
      'Case',
      'Formula',
      'Expected value',
      'Expected formula',
      'Excel?',
    ]);
    expect(rows.length, greaterThan(6));
    for (final XlsxReadRow r in rows.skip(1)) {
      final String? formula = r.cells[1].formula;
      expect('=$formula', r.cells[3].value, reason: '${r.cells.first.value}');
    }
    final Map<String, String?> byCase = formulas(reader, 'Checks', 1);
    expect(byCase['3D reference'], 'SUM(Data:Other!A5)');
    expect(byCase['Range to the last row'], r'SUM(Data!A7:A1048576)');
  });

  test('w5_rows: the inserted rows take the format of the row above', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      File(paths['w5_rows.xlsx']!).readAsBytesSync(),
    );
    final XlsxSheet data = book.sheet('Data');
    expect(data.rowFormat(2).height, 30);
    expect(data.rowFormat(3).height, 30);
    expect(book.sheet('Convert').tables, isEmpty);
    final Map<String, String?> converted = formulas(
      XlsxReader(book.save().bytes),
      'Convert',
      4,
    );
    expect(converted['Bolt'], r'$B2');
    expect(converted['Outside'], '#VALUE!');
    expect(converted['Sum'], r'SUM($C$2:$C$3)');
  });

  test('w5_rename: quoted names, moved tab and an undone edit', () {
    final XlsxReader reader = read('w5_rename.xlsx');
    expect(reader.sheets.map((XlsxReadSheet s) => s.name), <String>[
      '2026',
      'Q1 Sales',
      'Keep',
      'Checks',
    ]);
    for (final XlsxReadRow r in reader.rows('Checks').skip(1)) {
      expect('=${r.cells[1].formula}', r.cells[3].value);
    }
  });

  test('w5_charts: the chart series follow the inserted row', () {
    final String chart = utf8.decode(
      readXlsxBytes(
        File(paths['w5_charts.xlsx']!).readAsBytesSync(),
      )['xl/charts/chart1.xml']!,
    );
    expect(chart, contains(r'Data!$B$2:$B$6'));
  });

  test(
    'the owner and producer files have rows inserted and a sheet renamed',
    () {
      expect(read('w5_chart_reference.xlsx').sheets.first.name, 'Veri Yeni');
      expect(read('w5_objects.xlsx').sheets.first.name, 'Nesneler');
    },
  );
}
