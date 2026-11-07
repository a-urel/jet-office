import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/xlsx_sheet.dart' show isLoadedSheet;
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart' show changeLogOf;
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';
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

const String _tableType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.table+xml';

/// A table as Excel writes one, with what the model does not type: `xr:uid`,
/// `dataDxfId`, a calculated column and an attribute it does not know.
const String _excelTable =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '$_tableOpen'
    'xmlns:xr="http://schemas.microsoft.com/office/spreadsheetml/2014/revision" '
    'xr:uid="{AAAA}" id="3" name="T" displayName="T" ref="A1:B3" '
    'totalsRowShown="0"><autoFilter ref="A1:B3" xr:uid="{BBBB}"/>'
    '<tableColumns count="2"><tableColumn id="1" xr3:uid="{CCCC}" name="A" '
    'dataDxfId="1" xmlns:xr3="urn:x"/><tableColumn id="2" name="B">'
    '<calculatedColumnFormula>A2*2</calculatedColumnFormula></tableColumn>'
    '</tableColumns><tableStyleInfo name="TableStyleLight1" '
    'showFirstColumn="0" showLastColumn="0" showRowStripes="1" '
    'showColumnStripes="0" other="kept"/></table>';

const String _excelRows =
    '<row r="1"><c r="A1" t="inlineStr"><is><t>A</t></is></c>'
    '<c r="B1" t="inlineStr"><is><t>B</t></is></c></row>'
    '<row r="2"><c r="A2"><v>1</v></c></row>'
    '<row r="3"><c r="A3"><v>2</v></c></row>';

/// A one-sheet package whose sheet lists one table per entry of [tables]
/// (raw XML) in its `<tableParts>`, with their content types; [rows] are its
/// rows and [after] follows the `<tableParts>`.
Uint8List _listed(
  List<String> tables, {
  String rows = _excelRows,
  String after = '',
  Map<String, String> extra = const <String, String>{},
  String extraTypes = '',
  bool calcChain = false,
}) => packageWith(
  rows: '',
  calcChain: calcChain,
  extraTypes:
      '${<String>[for (int i = 0; i < tables.length; i++) '<Override PartName="/xl/tables/table${i + 1}.xml" ContentType="$_tableType"/>'].join()}'
      '$extraTypes',
  extra: <String, String>{
    'xl/worksheets/sheet1.xml':
        '<worksheet xmlns="$mainNsForTables" xmlns:r="$relNs"><sheetData>$rows'
        '</sheetData><tableParts count="${tables.length}">'
        '${<String>[for (int i = 0; i < tables.length; i++) '<tablePart r:id="rId${i + 1}"/>'].join()}'
        '</tableParts>$after</worksheet>',
    'xl/worksheets/_rels/sheet1.xml.rels':
        '<Relationships xmlns="$pkgRelNs">'
        '${<String>[for (int i = 0; i < tables.length; i++) '<Relationship Id="rId${i + 1}" Type="$relNs/table" Target="../tables/table${i + 1}.xml"/>'].join()}</Relationships>',
    for (int i = 0; i < tables.length; i++)
      'xl/tables/table${i + 1}.xml': tables[i],
    ...extra,
  },
);

/// A table `Sales` over A1:B4 with a label and a sum in its totals row.
XlsxTable _sales({String name = 'Sales', String range = 'A1:B4'}) =>
    XlsxTable(name, XlsxRange.parse(range), const <XlsxTableColumn>[
      XlsxTableColumn('Region', totalsLabel: 'Total'),
      XlsxTableColumn('Amount', totalsFunction: XlsxTotalsFunction.sum),
    ], totalsRow: true);

/// A table `New` over [range], two columns, no totals.
XlsxTable _plain(String range, {String name = 'New'}) => XlsxTable(
  name,
  XlsxRange.parse(range),
  const <XlsxTableColumn>[XlsxTableColumn('P'), XlsxTableColumn('Q')],
);

Matcher _argument(String name, [Object? message]) => throwsA(
  isA<ArgumentError>()
      .having((ArgumentError e) => e.name, 'name', name)
      .having(
        (ArgumentError e) => '${e.message}',
        'message',
        message ?? anything,
      ),
);

Matcher _state(Object message) => throwsA(
  isA<StateError>().having((StateError e) => e.message, 'message', message),
);

/// Runs [edit], which writes cells, and checks that an undo before any save
/// restores the tables and the file (a save is not part of the change log, so
/// what it adds stays; `docs/xlsx-model.md`, "An undo after a save"), and that
/// a redo gives the tables back.
void _undoneUnsaved(Uint8List input, void Function(XlsxSheet sheet) edit) {
  final XlsxWorkbook book = XlsxWorkbook.open(input);
  final XlsxSheet sheet = book.sheets.first;
  final ChangeLog log = changeLogOf(book);
  final List<XlsxTable> before = sheet.tables;
  final ChangeSet set = log.transaction(() => edit(sheet));
  final List<XlsxTable> after = sheet.tables;
  log.revertSet(set);
  expect(sheet.tables, before);
  expect(
    comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
    isEmpty,
  );
  log.reapplySet(set);
  expect(sheet.tables, after);
  final Uint8List saved = book.save().bytes;
  expect(XlsxWorkbook.open(saved).sheets.first.tables, after);
}

/// Runs [edit], which writes no cell, and checks that an undo restores the
/// tables and the file, that a redo gives the edit back, and that a second
/// undo restores them.
void _undone(Uint8List input, void Function(XlsxSheet sheet) edit) {
  final XlsxWorkbook book = XlsxWorkbook.open(input);
  final XlsxSheet sheet = book.sheets.first;
  final ChangeLog log = changeLogOf(book);
  final List<XlsxTable> before = sheet.tables;
  final ChangeSet set = log.transaction(() => edit(sheet));
  final List<XlsxTable> after = sheet.tables;
  final Uint8List edited = book.save().bytes;
  log.revertSet(set);
  expect(sheet.tables, before);
  expect(
    comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
    isEmpty,
  );
  log.reapplySet(set);
  expect(sheet.tables, after);
  expect(
    comparePackages(edited, book.save().bytes, ignoreBookkeeping: true),
    isEmpty,
  );
  log.revertSet(set);
  expect(
    comparePackages(input, book.save().bytes, ignoreBookkeeping: true),
    isEmpty,
  );
}

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

  group('addTable', () {
    test('adds a table and writes its header and totals', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet.setCell(1, 0, 'North');
      sheet.setCell(1, 1, 120);
      sheet.setCell(2, 1, 80);
      sheet.addTable(_sales());
      expect(sheet.tables, <XlsxTable>[_sales()]);
      expect(sheet.cellAt(0, 0)!.value, 'Region');
      expect(sheet.cellAt(0, 1)!.value, 'Amount');
      expect(sheet.cellAt(3, 0)!.value, 'Total');
      expect(sheet.cellAt(3, 1)!.formula, 'SUBTOTAL(109,B2:B3)');
      final Uint8List saved = book.save().bytes;
      final Map<String, String> parts = readXlsx(saved);
      expect(
        parts['xl/tables/table1.xml'],
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<table xmlns="$mainNsForTables" id="1" name="Sales" '
        'displayName="Sales" ref="A1:B4" totalsRowCount="1"><autoFilter '
        'ref="A1:B3"/><tableColumns count="2"><tableColumn id="1" '
        'name="Region" totalsRowLabel="Total"/><tableColumn id="2" '
        'name="Amount" totalsRowFunction="sum"/></tableColumns>'
        '<tableStyleInfo name="TableStyleMedium2" showFirstColumn="0" '
        'showLastColumn="0" showRowStripes="1" showColumnStripes="0"/>'
        '</table>',
      );
      expect(
        parts['[Content_Types].xml'],
        contains(
          '<Override PartName="/xl/tables/table1.xml" '
          'ContentType="$_tableType"/>',
        ),
      );
      expect(
        parts['xl/worksheets/_rels/sheet1.xml.rels'],
        contains('Target="../tables/table1.xml"'),
      );
      expect(
        parts['xl/worksheets/sheet1.xml'],
        matches(RegExp(r'<tableParts count="1"><tablePart [^>]*r:id="rId\d+"')),
      );
      expect(XlsxWorkbook.open(saved).sheets.single.tables, <XlsxTable>[
        _sales(),
      ]);
    });

    test(
      'a file table part gains an entry, count recomputed, before extLst',
      () {
        final XlsxWorkbook book = XlsxWorkbook.open(
          _listed(<String>[_excelTable], after: '<extLst/>'),
        );
        final XlsxSheet sheet = book.sheets.single;
        sheet.addTable(_plain('D1:E2'));
        final String xml = partText(
          book.save().bytes,
          'xl/worksheets/sheet1.xml',
        );
        expect(
          xml,
          contains(
            '<tableParts count="2"><tablePart r:id="rId1"/><tablePart '
            'r:id="rId2"/></tableParts><extLst/>',
          ),
        );
      },
    );

    test('a prefixed sheet gets a prefixed tableParts', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        packageWith(
          rows: '',
          extra: <String, String>{
            'xl/worksheets/sheet1.xml':
                '<x:worksheet xmlns:x="$mainNsForTables"><x:sheetData/>'
                '</x:worksheet>',
          },
        ),
      );
      book.sheets.single.addTable(_plain('A1:B2'));
      final Uint8List saved = book.save().bytes;
      expect(
        partText(saved, 'xl/worksheets/sheet1.xml'),
        contains('<x:tableParts count="1">'),
      );
      expect(XlsxWorkbook.open(saved).sheets.single.tables, hasLength(1));
    });

    test('tableParts past the limit throws on load', () {
      final Uint8List input = _listed(<String>[
        _excelTable,
        _table('8', 'Other').replaceAll('A1:A3', 'D1:D3'),
      ]);
      final XlsxWorkbook book = XlsxWorkbook.open(
        input,
        limits: const XlsxReadLimits(maxMerges: 1),
      );
      expect(
        () => book.sheets.single.merges,
        throwsLimit('maxMerges', 1, 'xl/worksheets/sheet1.xml'),
      );
    });

    test('adding beside a query table leaves everything else', () {
      final Uint8List input = _listed(
        <String>[_excelTable],
        rows:
            '<row r="1"><c r="D1" t="inlineStr"><is><t>P</t></is></c>'
            '<c r="E1" t="inlineStr"><is><t>Q</t></is></c></row>',
        extra: <String, String>{
          'xl/tables/_rels/table1.xml.rels':
              '<Relationships xmlns="$pkgRelNs"><Relationship Id="rId1" '
              'Type="$relNs/queryTable" Target="../queryTables/queryTable1.xml"'
              '/></Relationships>',
          'xl/queryTables/queryTable1.xml':
              '<queryTable xmlns="$mainNsForTables" name="Q" connectionId="1"/>',
        },
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      book.sheets.single.addTable(_plain('D1:E2'));
      final Map<String, String> before = readXlsx(input);
      final Map<String, String> after = readXlsx(book.save().bytes);
      for (final String part in <String>[
        'xl/tables/table1.xml',
        'xl/tables/_rels/table1.xml.rels',
        'xl/queryTables/queryTable1.xml',
      ]) {
        expect(after[part], before[part], reason: part);
      }
    });

    test('tableParts is made in schema position', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        packageWith(
          rows: '',
          extra: <String, String>{
            'xl/worksheets/sheet1.xml':
                '<worksheet xmlns="$mainNsForTables"><sheetData/>'
                '<pageMargins left="1" right="1" top="1" bottom="1" '
                'header="1" footer="1"/><extLst/></worksheet>',
          },
        ),
      );
      book.sheets.single.addTable(_plain('A1:B2'));
      final String xml = partText(
        book.save().bytes,
        'xl/worksheets/sheet1.xml',
      );
      expect(
        xml.indexOf('<tableParts'),
        greaterThan(xml.indexOf('<pageMargins')),
      );
      expect(xml.indexOf('<tableParts'), lessThan(xml.indexOf('<extLst')));
    });

    test('an existing header text equal to the column name stays, another '
        'throws', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet.setCell(0, 0, 'Region');
      sheet.setCell(3, 1, 7);
      sheet.addTable(_sales());
      expect(sheet.cellAt(0, 0)!.value, 'Region');
      expect(sheet.cellAt(0, 1)!.value, 'Amount');
      // A totals cell that holds a value keeps it, as in the writer.
      expect(sheet.cellAt(3, 1)!.formula, isNull);

      final XlsxWorkbook other = XlsxWorkbook();
      final XlsxSheet refused = other.addSheet('S');
      refused.setCell(0, 1, 'Sum');
      refused.setCell(5, 5, 1);
      expect(() => refused.addTable(_sales()), _argument('values[1]'));
      expect(refused.tables, isEmpty);
      expect(refused.cellAt(0, 0), isNull);
      expect(refused.cellAt(0, 1)!.value, 'Sum');
      expect(
        readXlsx(other.save().bytes).keys,
        isNot(contains(contains('tables/'))),
      );
    });

    test('a formula in a header cell throws, whatever it shows', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        packageWith(
          rows: '<row r="1"><c r="A1" t="str"><f>"P"</f><v>P</v></c></row>',
        ),
      );
      expect(
        () => book.sheets.single.addTable(_plain('A1:B2')),
        _argument('values[0]'),
      );
    });

    test('a failed cell undoes the cells already written', () {
      // B1 is inside an array formula, and A1 is written first.
      final XlsxWorkbook book = XlsxWorkbook.open(
        packageWith(
          rows:
              '<row r="2"><c r="B2"><f t="array" ref="B1:B2">1</f><v>1</v></c>'
              '</row>',
        ),
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(() => sheet.addTable(_plain('A1:B2')), throwsStateError);
      expect(sheet.cellAt(0, 0), isNull);
      expect(sheet.tables, isEmpty);
      expect(changeLogOf(book).hasChanges, isFalse);
    });

    test('a name taken by a table on an unloaded sheet throws', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_tables'));
      final XlsxSheet first = book.sheets[0];
      first.merges; // Loads the first sheet only.
      expect(
        () => first.addTable(_plain('H1:I2', name: 'nUMBERS')),
        _argument('name', contains('Numbers')),
      );
      expect(isLoadedSheet(book.sheets[1]), isFalse);
    });

    test('a name an untypable part holds stays taken', () {
      const String broken =
          '$_tableOpen'
          'id="4" name="Hidden" displayName="Gone" ref="not a range">'
          '<tableColumns count="1"><tableColumn id="1" name="A"/>'
          '</tableColumns></table>';
      final XlsxWorkbook book = XlsxWorkbook.open(_listed(<String>[broken]));
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.tables, isEmpty);
      expect(
        () => sheet.addTable(_plain('D1:E2', name: 'gone')),
        _argument('name', contains('Gone')),
      );
      expect(
        () => sheet.addTable(_plain('D1:E2', name: 'HIDDEN')),
        _argument('name', contains('Hidden')),
      );
      expect(
        () => book.defineName(const XlsxDefinedName('Gone', 'S!\$A\$1')),
        _argument('name'),
      );
      sheet.addTable(_plain('D1:E2', name: 'Free'));
      expect(
        partText(book.save().bytes, 'xl/tables/table5.xml'),
        contains('id="5" name="Free"'),
      );
    });

    test('a part that does not parse keeps its name and id from the root', () {
      const String broken =
          '$_tableOpen'
          'id="7" name="Torn" displayName="Torn" ref="A1:A3"><tableColumns';
      final Uint8List input = _listed(<String>[broken]);
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.tables, isEmpty);
      expect(
        () => sheet.addTable(_plain('D1:E2', name: 'torn')),
        _argument('name', contains('Torn')),
      );
      sheet.addTable(_plain('D1:E2'));
      expect(
        partText(book.save().bytes, 'xl/tables/table8.xml'),
        contains('id="8"'),
      );
    });

    test('a defined name throws', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      final XlsxSheet other = book.addSheet('O');
      book.defineName(const XlsxDefinedName('Global', 'S!\$A\$1'));
      other.defineName(const XlsxDefinedName('Local', 'S!\$A\$1'));
      expect(
        () => sheet.addTable(_plain('A1:B2', name: 'GLOBAL')),
        _argument('name', contains('Global')),
      );
      expect(
        () => sheet.addTable(_plain('A1:B2', name: 'local')),
        _argument('name', contains('Local')),
      );
      expect(sheet.tables, isEmpty);
    });

    test('an overlap with merge, filter and table throw naming both', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet.merge(XlsxRange.parse('A1:B1'));
      sheet.autoFilter = XlsxRange.parse('D1:E5');
      sheet.addTable(_plain('G1:H2', name: 'First'));
      expect(
        () => sheet.addTable(_plain('A1:B2')),
        _argument('range', allOf(contains('A1:B2'), contains('A1:B1'))),
      );
      expect(
        () => sheet.addTable(_plain('E4:F5')),
        _argument('range', allOf(contains('E4:F5'), contains('D1:E5'))),
      );
      expect(
        () => sheet.addTable(_plain('H2:I3')),
        _argument('range', allOf(contains('"First"'), contains('G1:H2'))),
      );
    });

    test('checkTable runs first', () {
      final XlsxSheet sheet = XlsxWorkbook().addSheet('S');
      expect(
        () => sheet.addTable(_plain('A1:B2', name: '1 bad')),
        _argument('name'),
      );
      expect(() => sheet.addTable(_plain('A1:C2')), _argument('columns'));
    });

    test('merge and autoFilter refuse the new table', () {
      final XlsxSheet sheet = XlsxWorkbook().addSheet('S');
      sheet.addTable(_plain('A1:B3'));
      expect(
        () => sheet.merge(XlsxRange.parse('B2:C2')),
        _argument('range', contains('"New"')),
      );
      expect(
        () => sheet.autoFilter = XlsxRange.parse('A1:A2'),
        _argument('range', contains('"New"')),
      );
    });

    test('an undone table no longer blocks merge, filter or its name', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      final ChangeLog log = changeLogOf(book);
      log.revertSet(log.transaction(() => sheet.addTable(_plain('A1:B3'))));
      sheet.merge(XlsxRange.parse('A1:B1'));
      sheet.addTable(_plain('D1:E2'));
      expect(sheet.tables.single.range, XlsxRange.parse('D1:E2'));
    });

    test('setCell on the new header renames the column', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet.addTable(_plain('A1:B3'));
      sheet.setCell(0, 1, 'Renamed');
      expect(sheet.tables.single.columns.last.name, 'Renamed');
      expect(
        partText(book.save().bytes, 'xl/tables/table1.xml'),
        contains('name="Renamed"'),
      );
    });

    test('ids stay unique over the package', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _listed(<String>[
          _excelTable.replaceFirst('id="3"', 'id="40"'),
          '$_tableOpen'
              'id="9" displayName="Odd"/>',
        ]),
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.addTable(_plain('D1:E2', name: 'One'));
      sheet.addTable(_plain('G1:H2', name: 'Two'));
      final Map<String, String> parts = readXlsx(book.save().bytes);
      expect(parts['xl/tables/table41.xml'], contains('id="41" name="One"'));
      expect(parts['xl/tables/table42.xml'], contains('id="42" name="Two"'));
    });

    test('an id on an unloaded sheet counts, and a new sheet has room', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_tables'));
      final XlsxSheet added = book.addSheet('New');
      added.addTable(_plain('A1:B2'));
      final Map<String, String> parts = readXlsx(book.save().bytes);
      expect(parts['xl/tables/table4.xml'], contains('id="4"'));
    });

    test('a part name taken by another part is bumped', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _listed(<String>[
          _excelTable.replaceFirst('id="3"', 'id="1"'),
          _table('1', 'Other').replaceAll('A1:A3', 'D1:D3'),
        ]),
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.addTable(_plain('F1:G2'));
      final Uint8List saved = book.save().bytes;
      expect(partText(saved, 'xl/tables/table3.xml'), contains('id="2"'));
      expect(XlsxWorkbook.open(saved).sheets.single.tables, hasLength(3));
    });

    test('a sheet that is no worksheet throws', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        packageWith(
          rows: '',
          extra: <String, String>{
            'xl/worksheets/sheet1.xml':
                '<chartsheet xmlns="$mainNsForTables"/>',
          },
        ),
      );
      expect(
        () => book.sheets.single.addTable(_plain('A1:B2')),
        throwsStateError,
      );
    });
  });

  group('setTableStyle', () {
    test('restyle keeps xr:uid', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _listed(<String>[_excelTable]),
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.setTableStyle(
        't',
        XlsxTableStyle.dark(3, showRowStripes: true, showFirstColumn: true),
      );
      expect(
        sheet.tables.single.style,
        XlsxTableStyle.dark(3, showFirstColumn: true),
      );
      expect(
        partText(book.save().bytes, 'xl/tables/table1.xml'),
        _excelTable
            .replaceFirst('name="TableStyleLight1"', 'name="TableStyleDark3"')
            .replaceFirst('showFirstColumn="0"', 'showFirstColumn="1"'),
      );
    });

    test('flags alone leave the other attributes as written', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _listed(<String>[_excelTable]),
      );
      book.sheets.single.setTableStyle(
        'T',
        XlsxTableStyle.light(1, showRowStripes: false),
      );
      expect(
        partText(book.save().bytes, 'xl/tables/table1.xml'),
        _excelTable.replaceFirst('showRowStripes="1"', 'showRowStripes="0"'),
      );
    });

    test('null style removes tableStyleInfo', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _listed(<String>[_excelTable]),
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.setTableStyle('T', null);
      expect(sheet.tables.single.style, isNull);
      expect(
        partText(book.save().bytes, 'xl/tables/table1.xml'),
        _excelTable.replaceFirst(RegExp('<tableStyleInfo[^>]*>'), ''),
      );
    });

    test('an element written with an end tag is removed whole', () {
      final String table = _excelTable.replaceFirst(
        'other="kept"/>',
        'other="kept"></tableStyleInfo>',
      );
      final XlsxWorkbook book = XlsxWorkbook.open(_listed(<String>[table]));
      book.sheets.single.setTableStyle('T', null);
      expect(
        partText(book.save().bytes, 'xl/tables/table1.xml'),
        isNot(contains('tableStyleInfo')),
      );
    });

    test('a table without a style gains the element after its columns', () {
      final String table = _excelTable.replaceFirst(
        RegExp('<tableStyleInfo[^>]*>'),
        '<extLst/>',
      );
      final XlsxWorkbook book = XlsxWorkbook.open(_listed(<String>[table]));
      final XlsxSheet sheet = book.sheets.single;
      sheet.setTableStyle('T', XlsxTableStyle.defaultStyle);
      expect(sheet.tables.single.style, XlsxTableStyle.defaultStyle);
      expect(
        partText(book.save().bytes, 'xl/tables/table1.xml'),
        contains(
          '</tableColumns><tableStyleInfo name="TableStyleMedium2" '
          'showFirstColumn="0" showLastColumn="0" showRowStripes="1" '
          'showColumnStripes="0"/><extLst/>',
        ),
      );
    });

    test('a prefixed part gets a prefixed element', () {
      const String table =
          '<x:table xmlns:x="$mainNsForTables" id="1" name="T" displayName="T" '
          'ref="A1:A2"><x:tableColumns count="1"><x:tableColumn id="1" '
          'name="A"/></x:tableColumns></x:table>';
      final XlsxWorkbook book = XlsxWorkbook.open(_listed(<String>[table]));
      book.sheets.single.setTableStyle('T', XlsxTableStyle.light(2));
      expect(
        partText(book.save().bytes, 'xl/tables/table1.xml'),
        contains('</x:tableColumns><x:tableStyleInfo name="TableStyleLight2"'),
      );
    });

    test('an element without a name gets one and the flags', () {
      final String table = _excelTable.replaceFirst(
        RegExp('<tableStyleInfo[^>]*>'),
        '<tableStyleInfo other="kept"/>',
      );
      final XlsxWorkbook book = XlsxWorkbook.open(_listed(<String>[table]));
      final XlsxSheet sheet = book.sheets.single;
      sheet.setTableStyle('T', XlsxTableStyle.light(2));
      expect(sheet.tables.single.style, XlsxTableStyle.light(2));
      expect(
        partText(book.save().bytes, 'xl/tables/table1.xml'),
        contains('other="kept"'),
      );
    });

    test('a pending column rename survives', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _listed(<String>[_excelTable]),
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.setCell(0, 1, 'Renamed');
      sheet.setTableStyle('T', null);
      sheet.setCell(0, 0, 'Again');
      expect(
        sheet.tables.single.columns.map((XlsxTableColumn c) => c.name),
        <String>['Again', 'Renamed'],
      );
      final String xml = partText(book.save().bytes, 'xl/tables/table1.xml');
      expect(xml, contains('name="Renamed"'));
      expect(xml, contains('name="Again"'));
    });

    test('equal is no edit', () {
      final Uint8List input = _listed(<String>[_excelTable]);
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      book.sheets.single.setTableStyle('T', XlsxTableStyle.light(1));
      expect(changeLogOf(book).hasChanges, isFalse);
    });

    test('an unknown table and a style Excel lacks throw', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _listed(<String>[_excelTable]),
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(
        () => sheet.setTableStyle('Nope', null),
        _argument('name', contains('Nope')),
      );
      expect(
        () => sheet.setTableStyle('T', const XlsxTableStyle('Mine')),
        _argument('style'),
      );
      expect(changeLogOf(book).hasChanges, isFalse);
    });

    test('a custom style of the file takes new flags', () {
      final String table = _excelTable.replaceFirst('TableStyleLight1', 'Mine');
      final XlsxWorkbook book = XlsxWorkbook.open(_listed(<String>[table]));
      final XlsxSheet sheet = book.sheets.single;
      sheet.setTableStyle(
        'T',
        const XlsxTableStyle('Mine', showLastColumn: true),
      );
      expect(sheet.tables.single.style!.showLastColumn, isTrue);
    });
  });

  group('resizeTable', () {
    test('resize moves both refs', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _listed(<String>[_excelTable]),
      );
      final XlsxSheet sheet = book.sheets.single;
      sheet.resizeTable('t', XlsxRange.parse('A1:B9'));
      expect(sheet.tables.single.range, XlsxRange.parse('A1:B9'));
      expect(
        partText(book.save().bytes, 'xl/tables/table1.xml'),
        _excelTable.replaceAll('ref="A1:B3"', 'ref="A1:B9"'),
      );
      sheet.resizeTable('T', XlsxRange.parse('A1:B2'));
      expect(
        partText(book.save().bytes, 'xl/tables/table1.xml'),
        _excelTable.replaceAll('ref="A1:B3"', 'ref="A1:B2"'),
      );
    });

    test('a table without a filter has only its ref moved', () {
      final String table = _excelTable.replaceFirst(
        RegExp('<autoFilter[^>]*>'),
        '',
      );
      final XlsxWorkbook book = XlsxWorkbook.open(_listed(<String>[table]));
      book.sheets.single.resizeTable('T', XlsxRange.parse('A1:B9'));
      expect(
        partText(book.save().bytes, 'xl/tables/table1.xml'),
        table.replaceAll('ref="A1:B3"', 'ref="A1:B9"'),
      );
    });

    test('resize refuses totals, sortState, other corners and no data row', () {
      final XlsxWorkbook totals = XlsxWorkbook.open(_fixture('m4_tables'));
      expect(
        () => totals.sheets[0].resizeTable('Sales', XlsxRange.parse('A1:C9')),
        _state(contains('totals')),
      );
      final String sorted = _excelTable.replaceFirst(
        '<tableColumns',
        '<sortState ref="A2:B3"><sortCondition ref="A2:A3"/></sortState>'
            '<tableColumns',
      );
      final XlsxWorkbook book = XlsxWorkbook.open(_listed(<String>[sorted]));
      expect(
        () => book.sheets.single.resizeTable('T', XlsxRange.parse('A1:B9')),
        _state(contains('sort')),
      );
      final XlsxSheet sheet = XlsxWorkbook.open(
        _listed(<String>[_excelTable]),
      ).sheets.single;
      for (final String range in <String>['A2:B9', 'B1:B9', 'A1:C9']) {
        expect(
          () => sheet.resizeTable('T', XlsxRange.parse(range)),
          _argument('range'),
          reason: range,
        );
      }
      expect(
        () => sheet.resizeTable('T', XlsxRange.parse('A1:B1')),
        _argument('range', contains('data row')),
      );
      expect(
        () => sheet.resizeTable('Nope', XlsxRange.parse('A1:B9')),
        _argument('name'),
      );
      expect(sheet.tables.single.range, XlsxRange.parse('A1:B3'));
    });

    test('a table without a header needs one row', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet sheet = book.addSheet('S');
      sheet.addTable(
        XlsxTable('H', XlsxRange.parse('A1:A3'), const <XlsxTableColumn>[
          XlsxTableColumn('X'),
        ], headerRow: false),
      );
      sheet.resizeTable('H', XlsxRange.parse('A1:A1'));
      expect(sheet.tables.single.range, XlsxRange.parse('A1:A1'));
    });

    test('resize refuses an overlap with a table, a merge or the filter', () {
      final XlsxSheet sheet = XlsxWorkbook().addSheet('S');
      sheet.addTable(_plain('A1:B3'));
      sheet.addTable(_plain('A6:B7', name: 'Below'));
      sheet.merge(XlsxRange.parse('C1:D1'));
      expect(
        () => sheet.resizeTable('New', XlsxRange.parse('A1:B6')),
        _argument('range', contains('"Below"')),
      );
      sheet.removeTable('Below');
      sheet.merge(XlsxRange.parse('B5:C5'));
      expect(
        () => sheet.resizeTable('New', XlsxRange.parse('A1:B6')),
        _argument('range', contains('B5:C5')),
      );
      sheet.unmerge(XlsxRange.parse('B5:C5'));
      sheet.autoFilter = XlsxRange.parse('A5:B9');
      expect(
        () => sheet.resizeTable('New', XlsxRange.parse('A1:B6')),
        _argument('range', contains('A5:B9')),
      );
    });

    test('merge sees the new range at once', () {
      final XlsxSheet sheet = XlsxWorkbook().addSheet('S');
      sheet.addTable(_plain('A1:B3'));
      sheet.resizeTable('New', XlsxRange.parse('A1:B5'));
      expect(() => sheet.merge(XlsxRange.parse('A5:B5')), _argument('range'));
    });

    test('equal is no edit', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_tables'));
      book.sheets[0].resizeTable('Sales', XlsxRange.parse('A1:C5'));
      expect(changeLogOf(book).hasChanges, isFalse);
    });
  });

  group('removeTable', () {
    test('removes a table, cells stay, tableParts goes with the last', () {
      final Uint8List input = _listed(<String>[
        _excelTable,
        _table('8', 'Other').replaceAll('A1:A3', 'D1:D3'),
      ]);
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final XlsxSheet sheet = book.sheets.single;
      sheet.removeTable('t');
      expect(sheet.tables.single.name, 'Other');
      expect(sheet.cellAt(0, 0)!.value, 'A');
      Map<String, String> parts = readXlsx(book.save().bytes);
      expect(parts.keys, isNot(contains('xl/tables/table1.xml')));
      expect(parts['[Content_Types].xml'], isNot(contains('table1.xml')));
      expect(
        parts['xl/worksheets/_rels/sheet1.xml.rels'],
        isNot(contains('table1.xml')),
      );
      expect(
        parts['xl/worksheets/sheet1.xml'],
        contains('<tableParts count="1"><tablePart r:id="rId2"/></tableParts>'),
      );
      sheet.removeTable('Other');
      expect(sheet.tables, isEmpty);
      parts = readXlsx(book.save().bytes);
      expect(parts.keys, isNot(contains('xl/tables/table2.xml')));
      expect(parts['xl/worksheets/sheet1.xml'], isNot(contains('tablePart')));
      expect(sheet.cellAt(0, 0)!.value, 'A');
      // Its name and cells are free again.
      sheet.addTable(_plain('A5:B6', name: 'T'));
    });

    test('a formula using the table refuses removal, named cell in the '
        'message', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_fixture('m4_tables'));
      final XlsxSheet other = book.sheets[1];
      other.setCell(6, 3, const XlsxFormula('SUM(sALES[Amount])'));
      expect(
        () => book.sheets[0].removeTable('Sales'),
        _state(allOf(contains('D7'), contains(other.name))),
      );
      expect(book.sheets[0].tables, hasLength(2));
    });

    test('a shared formula is found in its master', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _listed(
          <String>[_excelTable],
          rows:
              '<row r="5"><c r="D5"><f t="shared" ref="D5:D6" si="0">'
              'SUM(T[A])</f><v>1</v></c></row>'
              '<row r="6"><c r="D6"><f t="shared" si="0"/><v>1</v></c></row>',
        ),
      );
      expect(() => book.sheets.single.removeTable('T'), _state(contains('D5')));
    });

    test('a string holding the text refuses too', () {
      final XlsxSheet sheet = XlsxWorkbook.open(
        _listed(<String>[_excelTable]),
      ).sheets.single;
      sheet.setCell(9, 0, const XlsxFormula('"T[x]"'));
      expect(() => sheet.removeTable('T'), _state(contains('A10')));
    });

    test('a name without the bracket does not refuse', () {
      final XlsxSheet sheet = XlsxWorkbook.open(
        _listed(<String>[_excelTable]),
      ).sheets.single;
      sheet.setCell(9, 0, const XlsxFormula('T+1'));
      sheet.removeTable('T');
      expect(sheet.tables, isEmpty);
    });

    test('a defined name using it refuses', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _listed(<String>[_excelTable]),
      );
      book.defineName(const XlsxDefinedName('Uses', 't[A]'));
      expect(
        () => book.sheets.single.removeTable('T'),
        _state(contains('"Uses"')),
      );
      book.removeName('Uses');
      book.sheets.single.defineName(const XlsxDefinedName('Local', 'T[B]'));
      expect(
        () => book.sheets.single.removeTable('T'),
        _state(contains('"Local"')),
      );
    });

    test('a query table refuses', () {
      final Uint8List input = _listed(
        <String>[_excelTable],
        extra: <String, String>{
          'xl/tables/_rels/table1.xml.rels':
              '<Relationships xmlns="$pkgRelNs"><Relationship Id="rId1" '
              'Type="$relNs/queryTable" Target="../queryTables/queryTable1.xml"'
              '/></Relationships>',
          'xl/queryTables/queryTable1.xml':
              '<queryTable xmlns="$mainNsForTables" name="Q" connectionId="1"/>',
        },
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      expect(
        () => book.sheets.single.removeTable('T'),
        _state(contains('relationships')),
      );
      expect(book.sheets.single.tables, hasLength(1));
      expect(changeLogOf(book).hasChanges, isFalse);
    });

    test('an unknown table throws', () {
      final XlsxSheet sheet = XlsxWorkbook().addSheet('S');
      expect(() => sheet.removeTable('Nope'), _argument('name'));
    });
  });

  group('undo of each restores the file', () {
    Uint8List excel() => _listed(<String>[_excelTable]);

    test('addTable', () {
      _undoneUnsaved(
        packageWith(rows: ''),
        (XlsxSheet s) => s.addTable(_sales()),
      );
      _undoneUnsaved(excel(), (XlsxSheet s) => s.addTable(_plain('D1:E2')));
      _undoneUnsaved(_fixture('m4_tables'), (XlsxSheet s) {
        s.addTable(_plain('H1:I2', name: 'One'));
        s.addTable(_plain('K1:L2', name: 'Two'));
      });
    });

    test('addTable over cells that hold the header writes no cell', () {
      const String rows =
          '<row r="1"><c r="D1" t="inlineStr"><is><t>P</t></is></c>'
          '<c r="E1" t="inlineStr"><is><t>Q</t></is></c></row>';
      _undone(
        _listed(<String>[_excelTable], rows: rows),
        (XlsxSheet s) => s.addTable(_plain('D1:E2')),
      );
    });

    test('setTableStyle', () {
      _undone(excel(), (XlsxSheet s) => s.setTableStyle('T', null));
      _undone(
        excel(),
        (XlsxSheet s) => s.setTableStyle('T', XlsxTableStyle.dark(1)),
      );
    });

    test('resizeTable', () {
      _undone(
        excel(),
        (XlsxSheet s) => s.resizeTable('T', XlsxRange.parse('A1:B7')),
      );
    });

    test('removeTable', () {
      _undone(excel(), (XlsxSheet s) => s.removeTable('T'));
      _undone(_fixture('m4_tables'), (XlsxSheet s) {
        s.removeTable('Costs');
      });
    });

    test('a header rename gives the bytes back', () {
      // A comment after the root is not in the typed part's splices only if
      // the file's bytes come back.
      final Uint8List input = _listed(<String>['$_excelTable<!-- kept -->']);
      _undoneUnsaved(input, (XlsxSheet s) => s.setCell(0, 0, 'Renamed'));
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final ChangeLog log = changeLogOf(book);
      log.revertSet(
        log.transaction(() => book.sheets.single.setCell(0, 0, 'Renamed')),
      );
      expect(
        partText(book.save().bytes, 'xl/tables/table1.xml'),
        '$_excelTable<!-- kept -->',
      );
    });

    test('an edit and a rename undone together', () {
      _undoneUnsaved(excel(), (XlsxSheet s) {
        s.setCell(0, 1, 'Renamed');
        s.resizeTable('T', XlsxRange.parse('A1:B9'));
        s.setCell(0, 0, 'Again');
        s.setTableStyle('T', null);
        s.removeTable('T');
      });
    });
  });

  group('a part name used again after a removal', () {
    /// A file with the table `T` in `xl/tables/table1.xml`, as the writer
    /// makes it, so a new table takes that name once `T` left.
    Uint8List made() {
      final XlsxWorkbook book = XlsxWorkbook();
      book.addSheet('S').addTable(_plain('A1:B3', name: 'T'));
      return book.save().bytes;
    }

    /// `T` removed, `X` added in its part, both undone.
    XlsxWorkbook undoneBoth() {
      final XlsxWorkbook book = XlsxWorkbook.open(made());
      final XlsxSheet sheet = book.sheets.single;
      final ChangeLog log = changeLogOf(book);
      final ChangeSet removed = log.transaction(() => sheet.removeTable('T'));
      final ChangeSet added = log.transaction(
        () => sheet.addTable(_plain('D1:E2', name: 'X')),
      );
      expect(
        partText(book.save().bytes, 'xl/tables/table1.xml'),
        contains('name="X"'),
      );
      log.revertSet(added);
      log.revertSet(removed);
      return book;
    }

    test('a later restyle reaches the file', () {
      final XlsxWorkbook book = undoneBoth();
      book.sheets.single.setTableStyle('T', XlsxTableStyle.dark(2));
      expect(
        XlsxWorkbook.open(book.save().bytes).sheets.single.tables.single.style,
        XlsxTableStyle.dark(2),
      );
    });

    test('a later header rename reaches the part', () {
      final XlsxWorkbook book = undoneBoth();
      book.sheets.single.setCell(0, 0, 'Renamed');
      final XlsxSheet saved = XlsxWorkbook.open(
        book.save().bytes,
      ).sheets.single;
      expect(saved.cellAt(0, 0)!.value, 'Renamed');
      expect(saved.tables.single.columns.first.name, 'Renamed');
    });

    test('the removed name is free, also after defineName read the parts', () {
      final XlsxWorkbook book = XlsxWorkbook.open(made());
      final XlsxSheet sheet = book.sheets.single;
      book.defineName(const XlsxDefinedName('Prime', 'S!\$A\$1'));
      sheet.removeTable('T');
      sheet.addTable(_plain('D1:E2', name: 'X'));
      sheet.addTable(_plain('G1:H2', name: 'T'));
      expect(sheet.tables.map((XlsxTable t) => t.name), <String>['X', 'T']);
    });

    test('defineName takes the removed name, and an undo takes it back', () {
      final XlsxWorkbook book = XlsxWorkbook.open(made());
      final XlsxSheet sheet = book.sheets.single;
      final ChangeLog log = changeLogOf(book);
      book.defineName(const XlsxDefinedName('Prime', 'S!\$A\$1'));
      final ChangeSet removed = log.transaction(() => sheet.removeTable('T'));
      final ChangeSet added = log.transaction(
        () => sheet.addTable(_plain('D1:E2', name: 'X')),
      );
      final ChangeSet named = log.transaction(
        () => book.defineName(const XlsxDefinedName('T', 'S!\$A\$1')),
      );
      log.revertSet(named);
      log.revertSet(added);
      log.revertSet(removed);
      expect(
        () => book.defineName(const XlsxDefinedName('T', 'S!\$A\$1')),
        _argument('name'),
      );
    });

    test('an unlisted name keeps a part that was not removed', () {
      // `Foo` is the name of a typed table whose displayName differs.
      final XlsxWorkbook book = XlsxWorkbook.open(
        _listed(<String>[_excelTable.replaceFirst('name="T" ', 'name="Foo" ')]),
      );
      expect(
        () => book.defineName(const XlsxDefinedName('Foo', 'S!\$A\$1')),
        _argument('name'),
      );
      book.sheets.single.removeTable('T');
      book.defineName(const XlsxDefinedName('Foo', 'S!\$A\$1'));
    });
  });

  group('what removeTable finds', () {
    Uint8List withColumn(String child) => _listed(<String>[
      _excelTable,
      '$_tableOpen'
          'id="8" name="Other" displayName="Other" ref="D1:D3"><tableColumns '
          'count="1"><tableColumn id="1" name="C">$child</tableColumn>'
          '</tableColumns></table>',
    ]);

    test('a longer name ending in the table name does not refuse', () {
      for (final String formula in <String>[
        'MyT[A]',
        '_T[A]',
        'A.T[A]',
        'a\\T[A]',
        'çT[A]',
        '1T[A]',
      ]) {
        final XlsxSheet sheet = XlsxWorkbook.open(
          _listed(<String>[_excelTable]),
        ).sheets.single;
        sheet.setCell(9, 0, XlsxFormula(formula));
        sheet.removeTable('T');
        expect(sheet.tables, isEmpty, reason: formula);
      }
    });

    test('what may stand before the name refuses', () {
      for (final String formula in <String>[
        'T[A]',
        '1+T[A]',
        'SUM(t[A])',
        '[1]!T[A]',
        'Book.xlsx!T[A]',
      ]) {
        final XlsxSheet sheet = XlsxWorkbook.open(
          _listed(<String>[_excelTable]),
        ).sheets.single;
        sheet.setCell(9, 0, XlsxFormula(formula));
        expect(
          () => sheet.removeTable('T'),
          _state(contains('A10')),
          reason: formula,
        );
      }
    });

    test('a name of a file with syntax characters is matched as text', () {
      final XlsxSheet sheet = XlsxWorkbook.open(
        _listed(<String>[
          _excelTable.replaceAll('displayName="T"', 'displayName="T(1"'),
        ]),
      ).sheets.single;
      sheet.setCell(9, 0, const XlsxFormula('T(1[A]'));
      expect(() => sheet.removeTable('T(1'), _state(contains('A10')));
    });

    test('a calculated column of another table refuses', () {
      final XlsxSheet sheet = XlsxWorkbook.open(
        withColumn(
          '<calculatedColumnFormula>SUM(T[A])</calculatedColumnFormula>',
        ),
      ).sheets.single;
      expect(
        () => sheet.removeTable('T'),
        _state(allOf(contains('"C"'), contains('"Other"'))),
      );
    });

    test('a totals formula of another table refuses', () {
      final XlsxSheet sheet = XlsxWorkbook.open(
        withColumn('<totalsRowFormula>SUM(T[A])</totalsRowFormula>'),
      ).sheets.single;
      expect(() => sheet.removeTable('T'), _state(contains('"Other"')));
    });

    test('a table on another sheet refuses', () {
      final XlsxWorkbook book = XlsxWorkbook();
      final XlsxSheet first = book.addSheet('S');
      final XlsxSheet second = book.addSheet('O');
      first.addTable(_plain('A1:B3', name: 'T'));
      second.setCell(2, 0, 1);
      second.addTable(
        XlsxTable('U', XlsxRange.parse('A1:A3'), const <XlsxTableColumn>[
          XlsxTableColumn(
            'C',
            totalsFunction: XlsxTotalsFunction.custom,
            totalsFormula: 'SUM(T[P])',
          ),
        ], totalsRow: true),
      );
      expect(() => first.removeTable('T'), _state(contains('"U"')));
    });

    test("the table's own column formula does not refuse", () {
      const String table =
          '$_tableOpen'
          'id="8" name="Own" displayName="Own" ref="D1:D3"><tableColumns '
          'count="1"><tableColumn id="1" name="C"><calculatedColumnFormula>'
          'Own[C]</calculatedColumnFormula></tableColumn></tableColumns>'
          '</table>';
      final XlsxSheet sheet = XlsxWorkbook.open(
        _listed(<String>[table]),
      ).sheets.single;
      sheet.removeTable('Own');
      expect(sheet.tables, isEmpty);
    });
  });

  group('calculation', () {
    const String formula = '<row r="9"><c r="A9"><f>1+1</f><v>2</v></c></row>';

    test('addTable drops calcChain, setTableStyle does not', () {
      final Uint8List input = _listed(
        <String>[_excelTable],
        rows: formula,
        calcChain: true,
      );
      final XlsxWorkbook styled = XlsxWorkbook.open(input);
      final XlsxSheet sheet = styled.sheets.single;
      sheet.setTableStyle('T', null);
      sheet.resizeTable('T', XlsxRange.parse('A1:B5'));
      sheet.removeTable('T');
      Map<String, String> parts = readXlsx(styled.save().bytes);
      expect(parts.keys, contains('xl/calcChain.xml'));
      expect(parts['xl/workbook.xml'], isNot(contains('fullCalcOnLoad')));

      final XlsxWorkbook added = XlsxWorkbook.open(input);
      added.sheets.single.addTable(_plain('D1:E2'));
      parts = readXlsx(added.save().bytes);
      expect(parts.keys, isNot(contains('xl/calcChain.xml')));
      expect(parts['xl/workbook.xml'], contains('fullCalcOnLoad="1"'));
    });
  });
}
