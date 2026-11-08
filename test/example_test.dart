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

  test('the example document holds the same accounts as a Word list', () {
    final DocxResult out = buildExampleDocument();
    expect(out.warnings.map((DocxWarning w) => w.code), <DocxWarningCode>[
      DocxWarningCode.invalidCharactersRemoved,
    ]);
    final DocxDocument doc = DocxDocument.open(out.bytes);
    final DocxTable table = doc.body.blocks.whereType<DocxTable>().single;
    expect(
      <List<String>>[
        for (final DocxTableRow r in table.rows)
          <String>[for (final DocxTableCell c in r.cells) c.text],
      ],
      <List<String>>[
        <String>['Code', 'Customer', 'Balance', 'Opened'],
        <String>['A-1', 'Acme Ltd', '1,234.50', '1/5/26'],
        <String>['A-2', 'Birch & Co', '99.99', '3/17/26'],
        <String>['A-3', 'Cedar GmbH', '480.00', '6/2/26'],
        <String>['Total', '', '1,814.49', ''],
      ],
    );
    expect(table.rows.first.isHeader, isTrue);
    expect(doc.properties.title, 'Accounts');
  });
}
