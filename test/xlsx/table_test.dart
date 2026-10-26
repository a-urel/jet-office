import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:jet_office/src/xlsx/defined_name.dart' show checkNameSyntax;
import 'package:jet_office/src/xlsx/sheet_writer.dart';
import 'package:jet_office/src/xlsx/table.dart';
import 'package:jet_office/src/xlsx/workbook_context.dart';
import 'package:jet_office/src/zip/archive_adapter.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../support/read_xlsx.dart';
import '../support/xlsx_checker.dart';

const String _decl = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
const String _table1 = 'xl/tables/table1.xml';
const String _sheet1 = 'xl/worksheets/sheet1.xml';

/// The parts of a workbook whose one sheet, `S`, [script] fills; the file
/// must pass the checker.
Map<String, String> _parts(void Function(XlsxSheetWriter sheet) script) {
  final XlsxWriter book = XlsxWriter();
  script(book.addSheet('S'));
  final XlsxResult result = book.close();
  expect(checkXlsx(result.bytes), isEmpty);
  return readXlsx(result.bytes);
}

/// The `Sales` table of the M4 plan over [ref]: `Region` with the label
/// `Total`, `Amount` summed and `Note`.
XlsxTable _sales({
  String ref = 'A1:C5',
  bool headerRow = true,
  bool totalsRow = true,
  bool autoFilter = true,
  XlsxTableStyle? style = XlsxTableStyle.defaultStyle,
  String name = 'Sales',
}) => XlsxTable(
  name,
  XlsxRange.parse(ref),
  const <XlsxTableColumn>[
    XlsxTableColumn('Region', totalsLabel: 'Total'),
    XlsxTableColumn('Amount', totalsFunction: XlsxTotalsFunction.sum),
    XlsxTableColumn('Note'),
  ],
  headerRow: headerRow,
  totalsRow: totalsRow,
  autoFilter: autoFilter,
  style: style,
);

/// A table of the plain columns `A`, `B` and `C` over [ref].
XlsxTable _plain(String name, String ref, {bool headerRow = true}) =>
    XlsxTable(name, XlsxRange.parse(ref), const <XlsxTableColumn>[
      XlsxTableColumn('A'),
      XlsxTableColumn('B'),
      XlsxTableColumn('C'),
    ], headerRow: headerRow);

/// The table part `xl/tables/table{id}.xml` with [attributes] after `ref`
/// and [body] inside.
String _tablePart(
  int id,
  String name,
  String ref,
  String attributes,
  String body,
) =>
    '$_decl<table xmlns="${Ns.main}" id="$id" name="$name" '
    'displayName="$name" ref="$ref"$attributes>$body</table>';

const String _salesColumns =
    '<tableColumns count="3"><tableColumn id="1" name="Region" '
    'totalsRowLabel="Total"/><tableColumn id="2" name="Amount" '
    'totalsRowFunction="sum"/><tableColumn id="3" name="Note"/>'
    '</tableColumns>';

const String _mediumStyle =
    '<tableStyleInfo name="TableStyleMedium2" showFirstColumn="0" '
    'showLastColumn="0" showRowStripes="1" showColumnStripes="0"/>';

/// The cells of the sheet part [sheet]: each written cell's reference to
/// its text (shared strings resolved through [parts]), its formula as
/// `=<text>`, or its `<v>`; and the style id of each, under the key
/// `<ref>.s`.
Map<String, String> _cells(Map<String, String> parts, String sheet) {
  final List<String> strings = <String>[
    for (final XmlElement si in XmlDocument.parse(
      parts['xl/sharedStrings.xml']!,
    ).findAllElements('si'))
      si.findAllElements('t').map((XmlElement t) => t.innerText).join(),
  ];
  final Map<String, String> cells = <String, String>{};
  for (final XmlElement c in XmlDocument.parse(
    parts[sheet]!,
  ).findAllElements('c')) {
    final String ref = c.getAttribute('r')!;
    final String v = c.getElement('v')?.innerText ?? '';
    final XmlElement? f = c.getElement('f');
    cells[ref] = f != null
        ? '=${f.innerText}'
        : c.getAttribute('t') == 's'
        ? strings[int.parse(v)]
        : v;
    final String? s = c.getAttribute('s');
    if (s != null) cells['$ref.s'] = s;
  }
  return cells;
}

/// Matches an [ArgumentError] named [name].
TypeMatcher<ArgumentError> _argumentError(String name) =>
    isA<ArgumentError>().having((ArgumentError e) => e.name, 'name', name);

const XlsxStyle _bold = XlsxStyle(font: XlsxFont(bold: true));

void main() {
  group('XlsxTotalsFunction', () {
    test('has the XML names of ST_TotalsRowFunction', () {
      expect(
        <String>[
          for (final XlsxTotalsFunction f in XlsxTotalsFunction.values)
            totalsFunctionXml(f),
        ],
        <String>[
          'none',
          'sum',
          'min',
          'max',
          'average',
          'count',
          'countNums',
          'stdDev',
          'var',
          'custom',
        ],
      );
    });
    test('has the SUBTOTAL codes that skip hidden rows', () {
      expect(
        <XlsxTotalsFunction, int?>{
          for (final XlsxTotalsFunction f in XlsxTotalsFunction.values)
            f: subtotalCode(f),
        },
        <XlsxTotalsFunction, int?>{
          XlsxTotalsFunction.none: null,
          XlsxTotalsFunction.sum: 109,
          XlsxTotalsFunction.min: 105,
          XlsxTotalsFunction.max: 104,
          XlsxTotalsFunction.average: 101,
          XlsxTotalsFunction.count: 103,
          XlsxTotalsFunction.countNums: 102,
          XlsxTotalsFunction.stdDev: 107,
          XlsxTotalsFunction.variance: 110,
          XlsxTotalsFunction.custom: null,
        },
      );
    });
  });

  group('value types', () {
    test('XlsxTableColumn has value equality and a toString', () {
      const XlsxTableColumn a = XlsxTableColumn(
        'Amount',
        totalsFunction: XlsxTotalsFunction.custom,
        totalsFormula: 'SUM(B2:B4)',
      );
      expect(
        a,
        const XlsxTableColumn(
          'Amount',
          totalsFunction: XlsxTotalsFunction.custom,
          totalsFormula: 'SUM(B2:B4)',
        ),
      );
      expect(
        a.hashCode,
        const XlsxTableColumn(
          'Amount',
          totalsFunction: XlsxTotalsFunction.custom,
          totalsFormula: 'SUM(B2:B4)',
        ).hashCode,
      );
      expect(a, isNot(const XlsxTableColumn('Amount')));
      expect(
        const XlsxTableColumn('A', totalsLabel: 'x'),
        isNot(const XlsxTableColumn('A', totalsLabel: 'y')),
      );
      expect(
        a.toString(),
        'XlsxTableColumn(Amount, totalsFunction: custom, totalsLabel: null, '
        'totalsFormula: SUM(B2:B4))',
      );
    });

    test('XlsxTableStyle builds the built-in names', () {
      expect(XlsxTableStyle.defaultStyle.name, 'TableStyleMedium2');
      expect(XlsxTableStyle.light(9).name, 'TableStyleLight9');
      expect(XlsxTableStyle.medium(28).name, 'TableStyleMedium28');
      expect(XlsxTableStyle.dark(11).name, 'TableStyleDark11');
      const XlsxTableStyle plain = XlsxTableStyle('TableStyleLight1');
      expect(plain.showFirstColumn, isFalse);
      expect(plain.showLastColumn, isFalse);
      expect(plain.showRowStripes, isTrue);
      expect(plain.showColumnStripes, isFalse);
      expect(
        XlsxTableStyle.light(
          9,
          showFirstColumn: true,
          showLastColumn: true,
          showRowStripes: false,
          showColumnStripes: true,
        ),
        const XlsxTableStyle(
          'TableStyleLight9',
          showFirstColumn: true,
          showLastColumn: true,
          showRowStripes: false,
          showColumnStripes: true,
        ),
      );
      expect(
        XlsxTableStyle.dark(1).hashCode,
        const XlsxTableStyle('TableStyleDark1').hashCode,
      );
      expect(
        XlsxTableStyle.dark(1),
        isNot(XlsxTableStyle.dark(1, showColumnStripes: true)),
      );
      expect(
        XlsxTableStyle.light(9, showColumnStripes: true).toString(),
        'XlsxTableStyle(TableStyleLight9, showFirstColumn: false, '
        'showLastColumn: false, showRowStripes: true, '
        'showColumnStripes: true)',
      );
    });

    test('XlsxTable has list-aware value equality and a toString', () {
      expect(_sales(), _sales());
      expect(_sales().hashCode, _sales().hashCode);
      expect(_sales(), isNot(_sales(totalsRow: false)));
      expect(_sales(), isNot(_sales(headerRow: false)));
      expect(_sales(), isNot(_sales(autoFilter: false)));
      expect(_sales(), isNot(_sales(style: null)));
      expect(_sales(), isNot(_sales(name: 'Other')));
      expect(_sales(), isNot(_sales(ref: 'A1:C6')));
      expect(
        _plain('T', 'A1:C3'),
        isNot(
          XlsxTable('T', XlsxRange.parse('A1:C3'), const <XlsxTableColumn>[
            XlsxTableColumn('A'),
            XlsxTableColumn('B'),
            XlsxTableColumn('D'),
          ]),
        ),
      );
      expect(
        _plain('T', 'A1:B2').toString(),
        'XlsxTable(T, XlsxRange(A1:B2), [XlsxTableColumn(A, totalsFunction: '
        'none, totalsLabel: null, totalsFormula: null), XlsxTableColumn(B, '
        'totalsFunction: none, totalsLabel: null, totalsFormula: null), '
        'XlsxTableColumn(C, totalsFunction: none, totalsLabel: null, '
        'totalsFormula: null)], headerRow: true, totalsRow: false, '
        'autoFilter: true, style: XlsxTableStyle(TableStyleMedium2, '
        'showFirstColumn: false, showLastColumn: false, showRowStripes: '
        'true, showColumnStripes: false))',
      );
    });

    test('XlsxTable keeps an unmodifiable copy of its columns', () {
      final List<XlsxTableColumn> columns = <XlsxTableColumn>[
        const XlsxTableColumn('A'),
      ];
      final XlsxTable table = XlsxTable('T', XlsxRange.parse('A1:A2'), columns);
      columns.add(const XlsxTableColumn('B'));
      expect(table.columns, hasLength(1));
      expect(
        () => table.columns.add(const XlsxTableColumn('C')),
        throwsUnsupportedError,
      );
    });
  });

  group('WorkbookContext', () {
    test('takeTableId counts from 1', () {
      final WorkbookContext context = WorkbookContext(ZipWriter());
      expect(context.takeTableId(), 1);
      expect(context.takeTableId(), 2);
      expect(context.takeTableId(), 3);
    });

    test('checkNameFree refuses a table or defined name, ignoring case', () {
      final WorkbookContext context = WorkbookContext(ZipWriter());
      context.checkNameFree('Sales', 'name');
      context.reserveTableName('Sales');
      expect(
        () => context.checkNameFree('SALES', 'name'),
        throwsA(_argumentError('name')),
      );
      context.reserveDefinedName('Rate');
      expect(
        () => context.checkNameFree('rate', 'name'),
        throwsA(_argumentError('name')),
      );
      context.checkNameFree('Other', 'name');
    });

    test('checkNotTableName refuses only a table name', () {
      final WorkbookContext context = WorkbookContext(ZipWriter());
      context
        ..reserveTableName('Sales')
        ..reserveDefinedName('Rate');
      expect(
        () => context.checkNotTableName('sales', 'name'),
        throwsA(_argumentError('name')),
      );
      // Defined names may repeat across scopes.
      context.checkNotTableName('Rate', 'name');
    });
  });

  group('checkNameSyntax', () {
    test('accepts names and refuses shapes, reserved names and cells', () {
      checkNameSyntax('Sales_2026', 'name');
      checkNameSyntax('Şube.Gelir', 'name');
      for (final String bad in <String>[
        '',
        'Sales Q1',
        '1st',
        'A1',
        'R1C1',
        'R',
        'c',
        '_xlnm.Print_Area',
        'Print_Area',
      ]) {
        expect(
          () => checkNameSyntax(bad, 'field'),
          throwsA(_argumentError('field')),
          reason: bad,
        );
      }
    });

    test('tells a table name by its own limit and advice', () {
      expect(
        () => checkNameSyntax('a' * 256, 'name', table: true),
        throwsA(
          _argumentError('name').having(
            (ArgumentError e) => e.message,
            'message',
            contains('A table name has at most 255'),
          ),
        ),
      );
      checkNameSyntax('a' * 255, 'name', table: true);
      expect(
        () => checkNameSyntax('Print_Area', 'name', table: true),
        throwsA(
          _argumentError('name').having(
            (ArgumentError e) => e.message,
            'message',
            '"Print_Area" is a built-in name Excel reserves; a table '
                'cannot take it.',
          ),
        ),
      );
      // A defined name keeps the advice of the sheet setting.
      expect(
        () => checkNameSyntax('Print_Area', 'name'),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            contains('printArea'),
          ),
        ),
      );
    });
  });

  group('the table part', () {
    test('writes the Sales table of the plan', () {
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s.table(_sales());
      });
      expect(
        parts[_table1],
        _tablePart(
          1,
          'Sales',
          'A1:C5',
          ' totalsRowCount="1"',
          '<autoFilter ref="A1:C4"/>$_salesColumns$_mediumStyle',
        ),
      );
    });

    test('without a totals row, filters the whole ref', () {
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s.table(_plain('Plain', 'A1:C4'));
      });
      expect(
        parts[_table1],
        _tablePart(
          1,
          'Plain',
          'A1:C4',
          ' totalsRowShown="0"',
          '<autoFilter ref="A1:C4"/><tableColumns count="3">'
              '<tableColumn id="1" name="A"/><tableColumn id="2" name="B"/>'
              '<tableColumn id="3" name="C"/></tableColumns>$_mediumStyle',
        ),
      );
    });

    test('without a header row, writes headerRowCount and no filter', () {
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s.table(_sales(ref: 'A1:C3', headerRow: false));
      });
      expect(
        parts[_table1],
        _tablePart(
          1,
          'Sales',
          'A1:C3',
          ' headerRowCount="0" totalsRowCount="1"',
          '$_salesColumns$_mediumStyle',
        ),
      );
    });

    test('without a filter or a style, writes neither', () {
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s.table(_sales(autoFilter: false, style: null));
      });
      expect(
        parts[_table1],
        _tablePart(1, 'Sales', 'A1:C5', ' totalsRowCount="1"', _salesColumns),
      );
    });

    test('writes the style and its flags', () {
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s.table(
          _sales(
            style: XlsxTableStyle.light(
              9,
              showFirstColumn: true,
              showRowStripes: false,
              showColumnStripes: true,
            ),
          ),
        );
      });
      expect(
        parts[_table1],
        endsWith(
          '<tableStyleInfo name="TableStyleLight9" showFirstColumn="1" '
          'showLastColumn="0" showRowStripes="0" showColumnStripes="1"/>'
          '</table>',
        ),
      );
    });

    test('writes a custom total with its formula, escaped', () {
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s.table(
          XlsxTable('T', XlsxRange.parse('A1:B5'), const <XlsxTableColumn>[
            XlsxTableColumn(
              'Amount',
              totalsFunction: XlsxTotalsFunction.custom,
              totalsFormula: '=SUM(A2:A4)',
            ),
            XlsxTableColumn(
              'Flag',
              totalsFunction: XlsxTotalsFunction.custom,
              totalsFormula: 'IF(B2<0,"_x0041_",1)',
            ),
          ], totalsRow: true),
        );
      });
      expect(
        parts[_table1],
        contains(
          '<tableColumns count="2"><tableColumn id="1" name="Amount" '
          'totalsRowFunction="custom"><totalsRowFormula>SUM(A2:A4)'
          '</totalsRowFormula></tableColumn><tableColumn id="2" name="Flag" '
          'totalsRowFunction="custom"><totalsRowFormula>'
          'IF(B2&lt;0,"_x005F_x0041_",1)</totalsRowFormula></tableColumn>'
          '</tableColumns>',
        ),
      );
    });

    test('writes every totals function by its XML name', () {
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s.table(
          XlsxTable('T', XlsxRange.parse('A1:H4'), <XlsxTableColumn>[
            for (final XlsxTotalsFunction f in <XlsxTotalsFunction>[
              XlsxTotalsFunction.sum,
              XlsxTotalsFunction.min,
              XlsxTotalsFunction.max,
              XlsxTotalsFunction.average,
              XlsxTotalsFunction.count,
              XlsxTotalsFunction.countNums,
              XlsxTotalsFunction.stdDev,
              XlsxTotalsFunction.variance,
            ])
              XlsxTableColumn(f.name, totalsFunction: f),
          ], totalsRow: true),
        );
      });
      for (final String xml in <String>[
        'sum',
        'min',
        'max',
        'average',
        'count',
        'countNums',
        'stdDev',
        'var',
      ]) {
        expect(parts[_table1], contains('totalsRowFunction="$xml"/>'));
      }
    });

    test('escapes names, column names and labels as ST_Xstring', () {
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s.table(
          XlsxTable(
            '_x0041_',
            XlsxRange.parse('A1:A3'),
            const <XlsxTableColumn>[
              XlsxTableColumn('a_x0042_&<b>', totalsLabel: '_x0043_ "Total"'),
            ],
            totalsRow: true,
          ),
        );
      });
      expect(
        parts[_table1],
        contains(
          'name="_x005F_x0041_" displayName="_x005F_x0041_" ref="A1:A3"',
        ),
      );
      expect(
        parts[_table1],
        contains(
          '<tableColumn id="1" name="a_x005F_x0042_&amp;&lt;b&gt;" '
          'totalsRowLabel="_x005F_x0043_ &quot;Total&quot;"/>',
        ),
      );
    });

    test('the sheet refers to its table parts', () {
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s.table(_sales());
      });
      expect(
        parts[_sheet1],
        endsWith(
          '<tableParts count="1"><tablePart r:id="rId1"/></tableParts>'
          '</worksheet>',
        ),
      );
      expect(
        parts['xl/worksheets/_rels/sheet1.xml.rels'],
        contains(
          '<Relationship Id="rId1" Type="${RelType.table}" '
          'Target="../tables/table1.xml"/>',
        ),
      );
      expect(
        parts['[Content_Types].xml'],
        contains(
          '<Override PartName="/xl/tables/table1.xml" '
          'ContentType="${ContentType.table}"/>',
        ),
      );
    });

    test('numbers tables across the workbook in registration order', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('One')
        ..table(_plain('First', 'A1:C3'))
        ..table(_plain('Second', 'E1:G3'));
      book.addSheet('Two').table(_plain('Third', 'B2:D4'));
      final XlsxResult result = book.close();
      expect(checkXlsx(result.bytes), isEmpty);
      final Map<String, String> parts = readXlsx(result.bytes);
      expect(
        parts[_sheet1],
        endsWith(
          '<tableParts count="2"><tablePart r:id="rId1"/>'
          '<tablePart r:id="rId2"/></tableParts></worksheet>',
        ),
      );
      expect(parts['xl/tables/table1.xml'], contains('id="1" name="First"'));
      expect(parts['xl/tables/table2.xml'], contains('id="2" name="Second"'));
      expect(parts['xl/tables/table3.xml'], contains('id="3" name="Third"'));
      expect(
        parts['xl/worksheets/_rels/sheet2.xml.rels'],
        contains(
          'Id="rId1" Type="${RelType.table}" '
          'Target="../tables/table3.xml"/>',
        ),
      );
      // The worksheet, its rels, then the table parts in id order.
      final List<String> names = parts.keys.toList();
      expect(names.indexOf(_sheet1), lessThan(names.indexOf(_table1)));
      expect(
        names.indexOf('xl/worksheets/_rels/sheet1.xml.rels'),
        lessThan(names.indexOf(_table1)),
      );
      expect(
        names.indexOf(_table1),
        lessThan(names.indexOf('xl/tables/table2.xml')),
      );
    });

    test('holds its tables until the sheet finishes', () {
      final XlsxWriter book = XlsxWriter();
      final WorksheetWriter sheet = book.addSheet('S') as WorksheetWriter;
      expect(sheet.holdsTrailerData, isFalse);
      sheet.table(_plain('T', 'A1:C2', headerRow: false));
      expect(sheet.holdsTrailerData, isTrue);
      book.addSheet('U');
      expect(sheet.holdsTrailerData, isFalse);
      expect(readXlsx(book.close().bytes), contains(_table1));
    });
  });

  group('registration refuses', () {
    /// Expects [register] on a fresh sheet, after [before] (which adds at
    /// most one table, named `U`), to throw [ArgumentError] named [field],
    /// and that nothing was recorded: a valid table registered afterwards
    /// under the same name still gets the next id.
    void expectRefused(
      void Function(XlsxSheetWriter sheet) register,
      String field, {
      void Function(XlsxSheetWriter sheet)? before,
    }) {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter sheet = book.addSheet('S');
      before?.call(sheet);
      expect(() => register(sheet), throwsA(_argumentError(field)));
      sheet.table(_plain('Sales', 'K10:M12'));
      final XlsxResult result = book.close();
      expect(checkXlsx(result.bytes), isEmpty);
      final Map<String, String> parts = readXlsx(result.bytes);
      final bool hadOne = parts[_table1]!.contains('name="U"');
      final int id = hadOne ? 2 : 1;
      expect(
        parts['xl/tables/table$id.xml'],
        contains('id="$id" name="Sales"'),
      );
      expect(parts.keys, isNot(contains('xl/tables/table${id + 1}.xml')));
    }

    test('a bad name', () {
      for (final String name in <String>[
        'Sales Q1',
        'A1',
        'R',
        'a' * 256,
        '',
        '1st',
      ]) {
        expectRefused(
          (XlsxSheetWriter s) => s.table(_sales(name: name)),
          'name',
        );
      }
    });

    test('a built-in name, with advice for a table', () {
      for (final String name in <String>[
        'Print_Area',
        'print_titles',
        '_FilterDatabase',
      ]) {
        expect(
          () => XlsxWriter().addSheet('S').table(_sales(name: name)),
          throwsA(
            _argumentError('name').having(
              (ArgumentError e) => e.message,
              'message',
              allOf(
                contains('is a built-in name Excel reserves'),
                isNot(contains('instead')),
              ),
            ),
          ),
          reason: name,
        );
      }
    });

    test('a long name is told against the table name limit', () {
      expect(
        () => XlsxWriter().addSheet('S').table(_sales(name: 'a' * 256)),
        throwsA(
          _argumentError('name').having(
            (ArgumentError e) => e.message,
            'message',
            'A table name has at most ${XlsxLimits.maxTableNameLength} '
                'characters.',
          ),
        ),
      );
    });

    test('a name of 255 characters is fine', () {
      _parts((XlsxSheetWriter s) => s.table(_sales(name: 'a' * 255)));
    });

    test('a name another table has, ignoring case', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('One').table(_plain('Sales', 'A1:C3'));
      final XlsxSheetWriter two = book.addSheet('Two');
      expect(
        () => two.table(_plain('SALES', 'A1:C3')),
        throwsA(_argumentError('name')),
      );
      two.table(_plain('Other', 'A1:C3'));
      expect(
        readXlsx(book.close().bytes)['xl/tables/table2.xml'],
        contains('id="2" name="Other"'),
      );
    });

    test('a name a defined name has, in either order and scope', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter sheet = book.addSheet('S');
      book.defineName(const XlsxDefinedName('Rate', '0.18'));
      sheet.defineName(const XlsxDefinedName('Local', '1'));
      expect(
        () => sheet.table(_plain('rate', 'A1:C3')),
        throwsA(_argumentError('name')),
      );
      expect(
        () => sheet.table(_plain('LOCAL', 'A1:C3')),
        throwsA(_argumentError('name')),
      );
      sheet.table(_plain('Sales', 'A1:C3'));
      expect(
        () => book.defineName(const XlsxDefinedName('sales', '1')),
        throwsA(_argumentError('name')),
      );
      expect(
        () => sheet.defineName(const XlsxDefinedName('SALES', '1')),
        throwsA(_argumentError('name')),
      );
      final XlsxSheetWriter other = book.addSheet('Other');
      expect(
        () => other.defineName(const XlsxDefinedName('Sales', '1')),
        throwsA(_argumentError('name')),
      );
      // The refused names were not recorded; the same spelling in two
      // scopes is still fine for defined names.
      other.defineName(const XlsxDefinedName('Local', '2'));
      final String workbook = readXlsx(book.close().bytes)['xl/workbook.xml']!;
      expect(workbook, isNot(contains('"sales"')));
      expect(workbook, isNot(contains('"SALES"')));
    });

    test('a column count other than the width', () {
      expectRefused(
        (XlsxSheetWriter s) => s.table(
          XlsxTable('T', XlsxRange.parse('A1:C3'), const <XlsxTableColumn>[
            XlsxTableColumn('A'),
            XlsxTableColumn('B'),
          ]),
        ),
        'columns',
      );
    });

    test('a bad column name', () {
      for (final (String name, int index) in <(String, int)>[
        ('', 0),
        ('x' * 256, 0),
        ('a\nb', 0),
        ('a\rb', 0),
        ('a\tb', 0),
        ('a\u0001b', 0),
        ('a', 1),
        ('A', 1),
      ]) {
        expectRefused(
          (XlsxSheetWriter s) => s.table(
            XlsxTable('T', XlsxRange.parse('A1:B3'), <XlsxTableColumn>[
              XlsxTableColumn(index == 0 ? name : 'a'),
              XlsxTableColumn(index == 1 ? name : 'b'),
            ]),
          ),
          'columns[$index].name',
        );
      }
    });

    test('a column name of 255 characters is fine', () {
      _parts(
        (XlsxSheetWriter s) => s.table(
          XlsxTable('T', XlsxRange.parse('A1:A2'), <XlsxTableColumn>[
            XlsxTableColumn('x' * 255),
          ]),
        ),
      );
    });

    test('a range outside the sheet or in reverse', () {
      expectRefused(
        (XlsxSheetWriter s) => s.table(
          XlsxTable(
            'T',
            const XlsxRange(1048575, 0, 1048576, 0),
            const <XlsxTableColumn>[XlsxTableColumn('A')],
          ),
        ),
        'range',
      );
      expectRefused(
        (XlsxSheetWriter s) => s.table(
          XlsxTable('T', const XlsxRange(3, 0, 1, 0), const <XlsxTableColumn>[
            XlsxTableColumn('A'),
          ]),
        ),
        'range',
      );
    });

    test('too few rows', () {
      // A header row and no data row.
      expectRefused(
        (XlsxSheetWriter s) => s.table(_plain('T', 'A1:C1')),
        'range',
      );
      // A header, a totals row and no data row.
      expectRefused(
        (XlsxSheetWriter s) => s.table(_sales(ref: 'A1:C2')),
        'range',
      );
      // A totals row and no data row.
      expectRefused(
        (XlsxSheetWriter s) => s.table(_sales(ref: 'A1:C1', headerRow: false)),
        'range',
      );
      // The least: one data row.
      _parts((XlsxSheetWriter s) {
        s
          ..table(_plain('T', 'A1:C1', headerRow: false))
          ..table(_sales(ref: 'A3:C5'))
          ..table(_sales(name: 'U', ref: 'A7:C8', headerRow: false));
      });
    });

    test('a range overlapping a table, the filter or a merge', () {
      expectRefused(
        (XlsxSheetWriter s) => s.table(_plain('T', 'C3:E5')),
        'range',
        before: (XlsxSheetWriter s) => s.table(_plain('U', 'A1:C3')),
      );
      expectRefused(
        (XlsxSheetWriter s) => s.table(_plain('T', 'B2:D4')),
        'range',
        before: (XlsxSheetWriter s) => s.autoFilter(XlsxRange.parse('D4:E9')),
      );
      expectRefused(
        (XlsxSheetWriter s) => s.table(_plain('T', 'B2:D4')),
        'range',
        before: (XlsxSheetWriter s) => s.merge(XlsxRange.parse('A4:B4')),
      );
    });

    test('a filter or a merge that overlaps a table, afterwards', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter sheet = book.addSheet('S')
        ..table(_plain('T', 'B2:D4'));
      expect(
        () => sheet.autoFilter(XlsxRange.parse('D4:E9')),
        throwsA(_argumentError('range')),
      );
      expect(
        () => sheet.merge(XlsxRange.parse('A2:B2')),
        throwsA(_argumentError('range')),
      );
      sheet
        ..autoFilter(XlsxRange.parse('F1:G9'))
        ..merge(XlsxRange.parse('A6:B6'));
      final Uint8List bytes = book.close().bytes;
      expect(checkXlsx(bytes), isEmpty);
      final String xml = readXlsx(bytes)[_sheet1]!;
      expect(xml, contains('<autoFilter ref="F1:G9"/>'));
      expect(xml, contains('<mergeCell ref="A6:B6"/>'));
    });

    test('totals settings that do not go together', () {
      for (final (XlsxTableColumn column, String field)
          in <(XlsxTableColumn, String)>[
            (
              const XlsxTableColumn(
                'A',
                totalsFunction: XlsxTotalsFunction.sum,
                totalsLabel: 'Total',
              ),
              'columns[0].totalsLabel',
            ),
            (
              const XlsxTableColumn(
                'A',
                totalsFunction: XlsxTotalsFunction.custom,
                totalsLabel: 'Total',
                totalsFormula: '1',
              ),
              'columns[0].totalsLabel',
            ),
            (
              const XlsxTableColumn(
                'A',
                totalsFunction: XlsxTotalsFunction.custom,
              ),
              'columns[0].totalsFormula',
            ),
            (
              const XlsxTableColumn('A', totalsFormula: 'SUM(A2:A3)'),
              'columns[0].totalsFormula',
            ),
            (
              const XlsxTableColumn(
                'A',
                totalsFunction: XlsxTotalsFunction.sum,
                totalsFormula: 'SUM(A2:A3)',
              ),
              'columns[0].totalsFormula',
            ),
            (
              const XlsxTableColumn(
                'A',
                totalsFunction: XlsxTotalsFunction.custom,
                totalsFormula: '=',
              ),
              'columns[0].totalsFormula',
            ),
            (
              const XlsxTableColumn('A', totalsLabel: 'a\u0001'),
              'columns[0].totalsLabel',
            ),
          ]) {
        expectRefused(
          (XlsxSheetWriter s) => s.table(
            XlsxTable('T', XlsxRange.parse('A1:A4'), <XlsxTableColumn>[
              column,
            ], totalsRow: true),
          ),
          field,
        );
      }
    });

    test('a style that is not built in', () {
      for (final XlsxTableStyle style in <XlsxTableStyle>[
        XlsxTableStyle.light(0),
        XlsxTableStyle.light(22),
        XlsxTableStyle.medium(29),
        XlsxTableStyle.dark(12),
        const XlsxTableStyle('Fancy'),
        const XlsxTableStyle('TableStyleMedium02'),
        const XlsxTableStyle('tablestylemedium2'),
      ]) {
        expectRefused(
          (XlsxSheetWriter s) => s.table(_sales(style: style)),
          'style',
        );
      }
    });

    test('every built-in style is accepted', () {
      _parts((XlsxSheetWriter s) {
        int row = 0;
        for (final (XlsxTableStyle Function(int) style, int count)
            in <(XlsxTableStyle Function(int), int)>[
              (XlsxTableStyle.light, 21),
              (XlsxTableStyle.medium, 28),
              (XlsxTableStyle.dark, 11),
            ]) {
          for (int n = 1; n <= count; n++) {
            s.table(
              XlsxTable(
                'Style_$row',
                XlsxRange(row, 0, row, 0),
                const <XlsxTableColumn>[XlsxTableColumn('A')],
                headerRow: false,
                style: style(n),
              ),
            );
            row += 1;
          }
        }
      });
    });

    test('a table whose header row is written (Decision 1)', () {
      expectRefused(
        (XlsxSheetWriter s) => s.table(_plain('T', 'A1:C3')),
        'range',
        before: (XlsxSheetWriter s) => s.row(<Object?>['A', 'B', 'C']),
      );
      expectRefused(
        (XlsxSheetWriter s) => s.table(_plain('T', 'A1:C3')),
        'range',
        before: (XlsxSheetWriter s) => s.blankRow(),
      );
      // Without a header row, data rows may come first.
      _parts((XlsxSheetWriter s) {
        s
          ..row(<Object?>[1, 2, 3])
          ..table(_plain('T', 'A1:C2', headerRow: false));
      });
    });

    test('a table on a finished sheet', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter first = book.addSheet('First');
      book.addSheet('Second');
      expect(() => first.table(_plain('T', 'A1:C3')), throwsStateError);
    });
  });

  group('the header row', () {
    test('fills null and missing values with the column names', () {
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s
          ..table(_sales(totalsRow: false))
          ..row(<Object?>['Region', null], style: _bold);
      });
      final Map<String, String> cells = _cells(parts, _sheet1);
      expect(cells['A1'], 'Region');
      expect(cells['B1'], 'Amount');
      expect(cells['C1'], 'Note');
      // The filled cells take the row's style.
      expect(cells['B1.s'], cells['A1.s']);
      expect(cells['C1.s'], cells['A1.s']);
      expect(cells['A1.s'], isNotNull);
    });

    test('writes a name given as text or in an XlsxCell as given', () {
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s
          ..table(_sales(totalsRow: false))
          ..row(<Object?>[
            'Region',
            const XlsxCell('Amount', style: _bold),
            'Note',
          ]);
      });
      final Map<String, String> cells = _cells(parts, _sheet1);
      expect(cells['B1'], 'Amount');
      expect(cells['B1.s'], isNotNull);
      expect(cells['A1.s'], isNull);
    });

    test('fills an XlsxCell(null, style: s) with the name in s', () {
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s
          ..table(_sales(totalsRow: false))
          ..row(<Object?>['Region', const XlsxCell(null, style: _bold)]);
      });
      final Map<String, String> cells = _cells(parts, _sheet1);
      expect(cells['B1'], 'Amount');
      expect(cells['B1.s'], isNotNull);
      expect(cells['A1.s'], isNull);
      expect(cells['C1'], 'Note');
      expect(cells['C1.s'], isNull);
    });

    test('leaves cells outside the table alone', () {
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s
          ..table(_plain('T', 'B1:D2'))
          ..row(<Object?>[42, null, null, null, 'x']);
      });
      final Map<String, String> cells = _cells(parts, _sheet1);
      expect(cells['A1'], '42');
      expect(
        <String?>[cells['B1'], cells['C1'], cells['D1']],
        <String>['A', 'B', 'C'],
      );
      expect(cells['E1'], 'x');
    });

    test('refuses any other value before anything is written', () {
      for (final Object value in <Object>[
        'amount',
        1,
        const XlsxFormula('"Amount"'),
        const XlsxCell(1),
        XlsxRichText(const <XlsxTextRun>[XlsxTextRun('Amount')]),
      ]) {
        final XlsxWriter book = XlsxWriter();
        final XlsxSheetWriter sheet = book.addSheet('S')
          ..table(_sales(ref: 'B1:D3', totalsRow: false));
        expect(
          () => sheet.row(<Object?>['before', 'Region', value]),
          throwsA(_argumentError('values[2]')),
          reason: '$value',
        );
        expect(sheet.rowCount, 0);
        sheet.row(<Object?>['after']);
        final XlsxResult result = book.close();
        expect(checkXlsx(result.bytes), isEmpty);
        final Map<String, String> cells = _cells(
          readXlsx(result.bytes),
          _sheet1,
        );
        expect(cells['A1'], 'after');
        expect(cells['B1'], 'Region');
        expect(cells['C1'], 'Amount');
      }
    });

    test('blankRow() at the header row writes the names (ruling R12)', () {
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s
          ..table(_sales(ref: 'A2:C4', totalsRow: false))
          ..blankRow()
          ..blankRow(height: 20);
      });
      final Map<String, String> cells = _cells(parts, _sheet1);
      expect(
        <String?>[cells['A2'], cells['B2'], cells['C2']],
        <String>['Region', 'Amount', 'Note'],
      );
      expect(parts[_sheet1], contains('<row r="2" ht="20" customHeight="1">'));
    });

    test('a header row the sheet never reaches is written at the end', () {
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s
          ..row(<Object?>['first'])
          ..table(_plain('Late', 'A6:C7'))
          ..table(_plain('Early', 'E3:G4'));
      });
      final Map<String, String> cells = _cells(parts, _sheet1);
      expect(
        <String?>[cells['E3'], cells['F3'], cells['G3']],
        <String>['A', 'B', 'C'],
      );
      expect(
        <String?>[cells['A6'], cells['B6'], cells['C6']],
        <String>['A', 'B', 'C'],
      );
      expect(
        RegExp(
          '<row r="([0-9]+)"',
        ).allMatches(parts[_sheet1]!).map((RegExpMatch m) => m.group(1)),
        <String>['1', '3', '6'],
      );
    });
  });

  group('the totals row', () {
    test('fills labels and SUBTOTAL formulas of the data rows', () {
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s
          ..table(_sales())
          ..row(<Object?>[])
          ..row(<Object?>['North', 1])
          ..row(<Object?>['South', 2])
          ..row(<Object?>['East', 3])
          ..row(<Object?>[null, null, null], style: _bold);
      });
      final Map<String, String> cells = _cells(parts, _sheet1);
      expect(cells['A5'], 'Total');
      expect(cells['B5'], '=SUBTOTAL(109,B2:B4)');
      expect(cells.containsKey('C5'), isFalse);
      expect(cells['A5.s'], isNotNull);
      expect(cells['B5.s'], cells['A5.s']);
    });

    test('uses each function\'s code and a custom formula', () {
      final List<XlsxTotalsFunction> functions = <XlsxTotalsFunction>[
        XlsxTotalsFunction.average,
        XlsxTotalsFunction.countNums,
        XlsxTotalsFunction.count,
        XlsxTotalsFunction.max,
        XlsxTotalsFunction.min,
        XlsxTotalsFunction.stdDev,
        XlsxTotalsFunction.sum,
        XlsxTotalsFunction.variance,
      ];
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s.table(
          XlsxTable('T', XlsxRange.parse('A1:I4'), <XlsxTableColumn>[
            for (final XlsxTotalsFunction f in functions)
              XlsxTableColumn(f.name, totalsFunction: f),
            const XlsxTableColumn(
              'Custom',
              totalsFunction: XlsxTotalsFunction.custom,
              totalsFormula: '=1+1',
            ),
          ], totalsRow: true),
        );
      });
      final Map<String, String> cells = _cells(parts, _sheet1);
      expect(
        <String?>[
          for (final String c in <String>[
            'A',
            'B',
            'C',
            'D',
            'E',
            'F',
            'G',
            'H',
          ])
            cells['${c}4'],
        ],
        <String>[
          '=SUBTOTAL(101,A2:A3)',
          '=SUBTOTAL(102,B2:B3)',
          '=SUBTOTAL(103,C2:C3)',
          '=SUBTOTAL(104,D2:D3)',
          '=SUBTOTAL(105,E2:E3)',
          '=SUBTOTAL(107,F2:F3)',
          '=SUBTOTAL(109,G2:G3)',
          '=SUBTOTAL(110,H2:H3)',
        ],
      );
      expect(cells['I4'], '=1+1');
    });

    test('writes a given value as given', () {
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s
          ..table(_sales())
          ..blankRow()
          ..blankRow()
          ..blankRow()
          ..blankRow()
          ..row(<Object?>['All', 99, 'n']);
      });
      final Map<String, String> cells = _cells(parts, _sheet1);
      expect(cells['A5'], 'All');
      expect(cells['B5'], '99');
      expect(cells['C5'], 'n');
    });

    test('fills an XlsxCell(null, style: s) with its total in s', () {
      final XlsxTable table =
          XlsxTable('T', XlsxRange.parse('A1:D3'), const <XlsxTableColumn>[
            XlsxTableColumn('Region', totalsLabel: 'Total'),
            XlsxTableColumn('Amount', totalsFunction: XlsxTotalsFunction.sum),
            XlsxTableColumn(
              'Custom',
              totalsFunction: XlsxTotalsFunction.custom,
              totalsFormula: 'SUM(C2)',
            ),
            XlsxTableColumn('Note'),
          ], totalsRow: true);
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s
          ..table(table)
          ..blankRow()
          ..blankRow()
          ..row(<Object?>[
            for (int i = 0; i < 4; i++) const XlsxCell(null, style: _bold),
          ]);
      });
      final Map<String, String> cells = _cells(parts, _sheet1);
      expect(cells['A3'], 'Total');
      expect(cells['B3'], '=SUBTOTAL(109,B2)');
      expect(cells['C3'], '=SUM(C2)');
      // None keeps the styled empty cell.
      expect(cells['D3'], '');
      final String? bold = cells['A3.s'];
      expect(bold, isNotNull);
      expect(
        <String?>[cells['B3.s'], cells['C3.s'], cells['D3.s']],
        <String?>[bold, bold, bold],
      );
    });

    test('blankRow() at the totals row fills it', () {
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s.table(_sales());
        for (int i = 0; i < 5; i++) {
          s.blankRow();
        }
      });
      final Map<String, String> cells = _cells(parts, _sheet1);
      expect(cells['A5'], 'Total');
      expect(cells['B5'], '=SUBTOTAL(109,B2:B4)');
    });

    test('without a header row, the data starts at the first row', () {
      final Map<String, String> parts = _parts((XlsxSheetWriter s) {
        s.table(_sales(ref: 'B3:D4', headerRow: false));
      });
      final Map<String, String> cells = _cells(parts, _sheet1);
      expect(cells['B4'], 'Total');
      expect(cells['C4'], '=SUBTOTAL(109,C3)');
    });
  });
}
