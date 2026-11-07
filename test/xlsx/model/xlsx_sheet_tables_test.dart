import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import 'support/workbook_support.dart';

Uint8List _fixture(String name) =>
    allFixtures().firstWhere((Fixture f) => f.name == name).build();

const String _tableOpen = '<table xmlns="$mainNsForTables" ';
const String mainNsForTables =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

/// A one-sheet package whose sheet relates one table part per entry of
/// [tables] (raw XML), `xl/tables/table{n}.xml`.
Uint8List _package(List<String> tables) => packageWith(
  rows: '',
  extra: <String, String>{
    'xl/worksheets/_rels/sheet1.xml.rels':
        '<Relationships xmlns="$pkgRelNs">'
        '${<String>[for (int i = 0; i < tables.length; i++) '<Relationship Id="rId${i + 1}" Type="$relNs/table" Target="../tables/table${i + 1}.xml"/>'].join()}</Relationships>',
    for (int i = 0; i < tables.length; i++)
      'xl/tables/table${i + 1}.xml': tables[i],
  },
);

String _table(String id, String name, {String column = ''}) =>
    '$_tableOpen'
    'id="$id" name="$name" displayName="$name" ref="A1:A3"><autoFilter '
    'ref="A1:A3"/><tableColumns count="1"><tableColumn id="1" name="A" '
    '$column/></tableColumns><tableStyleInfo name="TableStyleMedium2" '
    'showRowStripes="1"/></table>';

int _invalid(XlsxWorkbook book, String detail) => book.warnings
    .where(
      (XlsxWarning w) =>
          w.code == XlsxWarningCode.featureEntryInvalid && w.detail == detail,
    )
    .fold<int>(0, (int s, XlsxWarning w) => s + w.count);

void main() {
  test("reads the fixture's tables", () {
    final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_tables'));
    expect(book.sheets[0].tables, <XlsxTable>[
      XlsxTable('Sales', XlsxRange.parse('A1:C5'), const <XlsxTableColumn>[
        XlsxTableColumn('Region', totalsLabel: 'Total'),
        XlsxTableColumn('Amount', totalsFunction: XlsxTotalsFunction.sum),
        XlsxTableColumn('Note'),
      ], totalsRow: true),
      XlsxTable('Costs', XlsxRange.parse('E1:F3'), const <XlsxTableColumn>[
        XlsxTableColumn('Item'),
        XlsxTableColumn('Cost'),
      ], style: XlsxTableStyle.light(9, showColumnStripes: true)),
    ]);
    // The writer gives a table without a header row no filter.
    expect(book.sheets[1].tables, <XlsxTable>[
      XlsxTable(
        'Numbers',
        XlsxRange.parse('A1:B2'),
        const <XlsxTableColumn>[XlsxTableColumn('X'), XlsxTableColumn('Y')],
        headerRow: false,
        autoFilter: false,
        style: null,
      ),
    ]);
    expect(book.warnings, isEmpty);
    expect(
      () => book.sheets[0].tables.add(book.sheets[0].tables.first),
      throwsUnsupportedError,
    );
  });

  test('reads the tables of m4_objects in relationship order', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_objects'));
    expect(book.sheets[0].tables.map((XlsxTable t) => t.name), <String>[
      'Stock',
      'Prices',
    ]);
    expect(book.sheets[1].tables, isEmpty);
  });

  test('a sheet without tables has none', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_notes'));
    expect(book.sheets.first.tables, isEmpty);
  });

  test('an untypable part stays unlisted and its name stays taken', () {
    final Uint8List input = _package(<String>[
      _table('1', 'Good'),
      '<other xmlns="$mainNsForTables"/>',
    ]);
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    expect(book.sheets.single.tables.map((XlsxTable t) => t.name), <String>[
      'Good',
    ]);
    expect(
      comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
      isEmpty,
    );
  });

  test('a bad function warns once and reads none', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(<String>[
        _table('1', 'T', column: 'totalsRowFunction="median"'),
      ]),
    );
    expect(
      book.sheets.single.tables.single.columns.single.totalsFunction,
      XlsxTotalsFunction.none,
    );
    expect(book.sheets.single.tables, hasLength(1));
    expect(_invalid(book, 'table'), 1);
  });

  test('reading saves the input unchanged', () {
    for (final String name in <String>['m4_tables', 'm4_objects']) {
      final Uint8List input = _fixture(name);
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      for (final XlsxSheet sheet in book.sheets) {
        sheet.tables;
      }
      expect(
        comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
        isEmpty,
        reason: name,
      );
    }
  });
}
