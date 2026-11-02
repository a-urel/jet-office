import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';
import '../../../tool/src/part_compare.dart';
import '../../support/read_xlsx.dart';
import '../read/support/zip_builder.dart';
import 'support/workbook_support.dart';

void main() {
  test('a change drops calcChain and sets fullCalcOnLoad', () {
    final Uint8List input = packageWith(
      rows: '<row r="1"><c r="A1"><f>1+1</f><v>2</v></c></row>',
      calcChain: true,
    );

    final Uint8List unchanged = XlsxWorkbook.open(input).save().bytes;
    expect(comparePackages(input, unchanged), isEmpty);

    final XlsxWorkbook book = XlsxWorkbook.open(input);
    book.sheets.single.setCell(1, 0, 5);
    final Uint8List output = book.save().bytes;
    final Map<String, String> parts = readXlsx(output);
    expect(parts.containsKey('xl/calcChain.xml'), isFalse);
    expect(parts['xl/_rels/workbook.xml.rels'], isNot(contains('calcChain')));
    expect(parts['[Content_Types].xml'], isNot(contains('calcChain')));
    expect(
      parts['xl/workbook.xml'],
      contains('<calcPr calcId="191029" fullCalcOnLoad="1"/>'),
    );
    expect(
      comparePackages(
        input,
        output,
        ignoreParts: const <String>{
          'xl/calcChain.xml',
          'xl/workbook.xml',
          'xl/worksheets/sheet1.xml',
          'xl/_rels/workbook.xml.rels',
          '[Content_Types].xml',
        },
        ignoreBookkeeping: true,
      ),
      isEmpty,
    );
  });

  test('a change to a formula-free, fully loaded workbook asks no '
      'recalculation', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      packageWith(rows: '<row r="1"><c r="A1"><v>2</v></c></row>'),
    );
    book.sheets.single.setCell(1, 0, 5);
    expect(
      partText(book.save().bytes, 'xl/workbook.xml'),
      isNot(contains('full')),
    );
  });

  test('calcChain removal touches only the workbook relationships', () {
    const String bad = '<Relationships><Relationship';
    final Uint8List input = buildZip(<String, List<int>>{
      ...readXlsxBytes(
        packageWith(
          rows: '<row r="1"><c r="A1"><f>1+1</f><v>2</v></c></row>',
          calcChain: true,
        ),
      ),
      'xl/worksheets/_rels/sheet1.xml.rels': utf8.encode(bad),
    });
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    book.sheets.single.setCell(1, 0, 5);
    final Map<String, Uint8List> parts = readXlsxBytes(book.save().bytes);
    expect(parts.containsKey('xl/calcChain.xml'), isFalse);
    expect(parts['xl/worksheets/_rels/sheet1.xml.rels'], utf8.encode(bad));
  });
}
