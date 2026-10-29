@TestOn('vm')
library;

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../example/jet_office_example.dart';
import 'support/read_xlsx.dart';
import 'support/xlsx_checker.dart';

void main() {
  test('the example workbook is clean and holds both sheets', () {
    final bytes = buildExampleWorkbook();
    expect(checkXlsx(bytes), isEmpty);
    final parts = readXlsx(bytes);
    expect(
      parts.keys.where((k) => RegExp(r'^xl/comments\d+\.xml$').hasMatch(k)),
      hasLength(1),
    );
    final workbook = parts['xl/workbook.xml']!;
    expect(workbook, contains('name="Accounts"'));
    expect(workbook, contains('name="Summary"'));
    expect(
      workbook.indexOf('name="Summary"'),
      lessThan(workbook.indexOf('name="Accounts"')),
    );
  });

  test('the example reads its workbook back', () {
    final ExampleReadBack read = readExample(buildExampleWorkbook());
    expect(read.sheets, <String>['Summary', 'Accounts']);
    expect(read.rows, hasLength(4));
    expect(read.rows[0], <Object?>['Accounts']);
    expect(read.rows[1], <Object?>['Code', 'Customer', 'Balance', 'Opened']);
    expect(read.rows[2], <Object?>[
      'A-1',
      'Acme Ltd',
      XlsxDecimal('1234.50'),
      DateTime.utc(2026, 1, 5),
    ]);
    expect(read.rows[3], <Object?>[
      'A-2',
      'Birch & Co',
      XlsxDecimal('99.99'),
      DateTime.utc(2026, 3, 17),
    ]);
    expect(read.warnings.map((XlsxWarning w) => w.code), <XlsxWarningCode>[
      XlsxWarningCode.formulaWithoutValue,
    ]);
    expect(read.warnings.single.cells, <String>['C6']);
  });
}
