@TestOn('vm')
library;

import 'package:test/test.dart';

import '../example/jet_office_example.dart';
import 'support/read_xlsx.dart';
import 'support/xlsx_checker.dart';

void main() {
  test('the example workbook is clean and holds both sheets', () {
    final bytes = buildExampleWorkbook();
    expect(checkXlsx(bytes), isEmpty);
    final parts = readXlsx(bytes);
    final workbook = parts['xl/workbook.xml']!;
    expect(workbook, contains('name="Accounts"'));
    expect(workbook, contains('name="Summary"'));
    expect(
      workbook.indexOf('name="Summary"'),
      lessThan(workbook.indexOf('name="Accounts"')),
    );
  });
}
