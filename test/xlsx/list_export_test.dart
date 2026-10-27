import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../support/read_xlsx.dart';
import '../support/xlsx_checker.dart';

const String _sheet1 = 'xl/worksheets/sheet1.xml';

const XlsxStyle _money = XlsxStyle(numFmt: XlsxNumFmt.thousands2);

/// `Code`, and `Amount` summed in the money style.
const List<XlsxListColumn> _codeAmount = <XlsxListColumn>[
  XlsxListColumn('Code'),
  XlsxListColumn(
    'Amount',
    style: _money,
    totalsFunction: XlsxTotalsFunction.sum,
  ),
];

/// The rows of the plan: `A` 1.5 and `B` 2.
const List<List<Object?>> _twoRows = <List<Object?>>[
  <Object?>['A', 1.5],
  <Object?>['B', 2],
];

/// The parts of a workbook whose one sheet, named [sheetName], [export]
/// fills with [rows]; the file must pass the checker. [range] receives what
/// `writeTo` returns.
Map<String, String> _parts(
  XlsxListExport export,
  Iterable<List<Object?>> rows, {
  String sheetName = 'S',
  void Function(XlsxRange range)? range,
}) {
  final XlsxWriter book = XlsxWriter();
  final XlsxRange written = export.writeTo(book.addSheet(sheetName), rows);
  range?.call(written);
  final Uint8List bytes = book.close().bytes;
  expect(checkXlsx(bytes), isEmpty);
  return readXlsx(bytes);
}

/// The `<c>` element of [ref] in sheet 1, or `null` when there is none.
XmlElement? _cell(Map<String, String> parts, String ref) {
  for (final XmlElement c in XmlDocument.parse(
    parts[_sheet1]!,
  ).findAllElements('c')) {
    if (c.getAttribute('r') == ref) return c;
  }
  return null;
}

/// The text of the shared-string cell [ref] of sheet 1.
String _text(Map<String, String> parts, String ref) {
  final XmlElement c = _cell(parts, ref)!;
  expect(c.getAttribute('t'), 's', reason: ref);
  final int index = int.parse(c.getElement('v')!.innerText);
  return XmlDocument.parse(parts['xl/sharedStrings.xml']!)
      .findAllElements('si')
      .elementAt(index)
      .findAllElements('t')
      .map((XmlElement t) => t.innerText)
      .join();
}

/// The `<font>` of the cell [ref] of sheet 1.
XmlElement _font(Map<String, String> parts, String ref) {
  final int s = int.parse(_cell(parts, ref)!.getAttribute('s') ?? '0');
  final XmlDocument styles = XmlDocument.parse(parts['xl/styles.xml']!);
  final XmlElement xf = styles
      .findAllElements('cellXfs')
      .single
      .findElements('xf')
      .elementAt(s);
  return styles
      .findAllElements('fonts')
      .single
      .findElements('font')
      .elementAt(int.parse(xf.getAttribute('fontId')!));
}

bool _bold(Map<String, String> parts, String ref) =>
    _font(parts, ref).getElement('b') != null;

/// The `numFmtId` of the cell [ref] of sheet 1 (0 for a cell with no style).
int _numFmtId(Map<String, String> parts, String ref) {
  final int s = int.parse(_cell(parts, ref)!.getAttribute('s') ?? '0');
  return int.parse(
    XmlDocument.parse(parts['xl/styles.xml']!)
        .findAllElements('cellXfs')
        .single
        .findElements('xf')
        .elementAt(s)
        .getAttribute('numFmtId')!,
  );
}

/// The formula text of the cell [ref] of sheet 1.
String? _formula(Map<String, String> parts, String ref) =>
    _cell(parts, ref)?.getElement('f')?.innerText;

/// The rows of sheet 1 by number, as `r` attributes.
List<String> _rowNumbers(Map<String, String> parts) => <String>[
  for (final XmlElement r in XmlDocument.parse(
    parts[_sheet1]!,
  ).findAllElements('row'))
    r.getAttribute('r')!,
];

/// The `topLeftCell` of the frozen pane of sheet 1.
String? _frozenAt(Map<String, String> parts) {
  final XmlElement pane = XmlDocument.parse(
    parts[_sheet1]!,
  ).findAllElements('pane').single;
  expect(pane.getAttribute('state'), 'frozen');
  return pane.getAttribute('topLeftCell');
}

/// Matches a function that throws an [ArgumentError] named [name].
Matcher _argumentError(String name) => throwsA(
  isA<ArgumentError>().having((ArgumentError e) => e.name, 'name', name),
);

void main() {
  test('writes the header, rows and a SUBTOTAL totals row', () {
    late XlsxRange range;
    final Map<String, String> parts = _parts(
      XlsxListExport(_codeAmount),
      _twoRows,
      sheetName: 'List',
      range: (XlsxRange r) => range = r,
    );
    expect(_text(parts, 'A1'), 'Code');
    expect(_text(parts, 'B1'), 'Amount');
    expect(_bold(parts, 'A1'), isTrue);
    expect(_bold(parts, 'B1'), isTrue);
    expect(_text(parts, 'A2'), 'A');
    expect(_bold(parts, 'A2'), isFalse);
    expect(_text(parts, 'A4'), 'Total');
    expect(_bold(parts, 'A4'), isTrue);
    expect(parts[_sheet1], contains('<f>SUBTOTAL(109,B2:B3)</f>'));
    expect(_formula(parts, 'B4'), 'SUBTOTAL(109,B2:B3)');
    expect(_bold(parts, 'B4'), isTrue);
    expect(parts[_sheet1], contains('<autoFilter ref="A1:B3"/>'));
    expect(_frozenAt(parts), 'A2');
    expect(
      parts['xl/workbook.xml'],
      contains(
        '<definedName name="_xlnm.Print_Titles" localSheetId="0">'
        r"'List'!$1:$1</definedName>",
      ),
    );
    expect(range, XlsxRange.parse('A1:B4'));
  });

  test('a caption takes row 1 and moves the list down', () {
    late XlsxRange range;
    final Map<String, String> parts = _parts(
      XlsxListExport(_codeAmount, caption: 'Accounts'),
      _twoRows,
      range: (XlsxRange r) => range = r,
    );
    expect(_text(parts, 'A1'), 'Accounts');
    final XmlElement font = _font(parts, 'A1');
    expect(font.getElement('b'), isNotNull);
    expect(font.getElement('sz')!.getAttribute('val'), '14');
    expect(parts[_sheet1], isNot(contains('mergeCell')));
    expect(_text(parts, 'A2'), 'Code');
    expect(_bold(parts, 'A2'), isTrue);
    expect(parts[_sheet1], contains('<autoFilter ref="A2:B4"/>'));
    expect(_text(parts, 'A5'), 'Total');
    expect(_formula(parts, 'B5'), 'SUBTOTAL(109,B3:B4)');
    expect(_frozenAt(parts), 'A3');
    expect(parts['xl/workbook.xml'], contains(r"'S'!$2:$2"));
    expect(range, XlsxRange.parse('A2:B5'));
  });

  test('a caption keeps the style it is given', () {
    final Map<String, String> parts = _parts(
      XlsxListExport(
        _codeAmount,
        caption: 'Accounts',
        captionStyle: const XlsxStyle(font: XlsxFont(italic: true)),
        headerStyle: const XlsxStyle(font: XlsxFont(underline: null)),
        totalsStyle: const XlsxStyle(font: XlsxFont(italic: true)),
      ),
      _twoRows,
    );
    expect(_font(parts, 'A1').getElement('i'), isNotNull);
    expect(_font(parts, 'A1').getElement('b'), isNull);
    expect(_bold(parts, 'A2'), isFalse);
    expect(_font(parts, 'A5').getElement('i'), isNotNull);
    expect(_bold(parts, 'A5'), isFalse);
  });

  test('no totals row when no column has a function or a label', () {
    late XlsxRange range;
    final Map<String, String> parts = _parts(
      XlsxListExport(const <XlsxListColumn>[
        XlsxListColumn('Code'),
        XlsxListColumn('Amount', style: _money),
      ]),
      _twoRows,
      range: (XlsxRange r) => range = r,
    );
    expect(parts[_sheet1], contains('<autoFilter ref="A1:B3"/>'));
    expect(_rowNumbers(parts), <String>['1', '2', '3']);
    expect(parts[_sheet1], isNot(contains('SUBTOTAL')));
    expect(range, XlsxRange.parse('A1:B3'));
  });

  group('labels and the default Total', () {
    test('a label replaces the default', () {
      final Map<String, String> parts = _parts(
        XlsxListExport(const <XlsxListColumn>[
          XlsxListColumn('Code', totalsLabel: 'Sum'),
          XlsxListColumn(
            'Amount',
            style: _money,
            totalsFunction: XlsxTotalsFunction.sum,
          ),
        ]),
        _twoRows,
      );
      expect(_text(parts, 'A4'), 'Sum');
      expect(_formula(parts, 'B4'), 'SUBTOTAL(109,B2:B3)');
    });

    test('a label on another column suppresses the default', () {
      final Map<String, String> parts = _parts(
        XlsxListExport(const <XlsxListColumn>[
          XlsxListColumn('Code'),
          XlsxListColumn('Note', totalsLabel: 'n/a'),
        ]),
        _twoRows,
      );
      expect(_cell(parts, 'A4'), isNull);
      expect(_text(parts, 'B4'), 'n/a');
    });

    test('a first column with a function has no label', () {
      final Map<String, String> parts = _parts(
        XlsxListExport(const <XlsxListColumn>[
          XlsxListColumn('Code', totalsFunction: XlsxTotalsFunction.count),
          XlsxListColumn(
            'Amount',
            style: _money,
            totalsFunction: XlsxTotalsFunction.sum,
          ),
        ]),
        _twoRows,
      );
      expect(_formula(parts, 'A4'), 'SUBTOTAL(103,A2:A3)');
      expect(parts['xl/sharedStrings.xml'], isNot(contains('Total')));
    });
  });

  test('an empty list keeps one empty data row', () {
    late XlsxRange range;
    final Map<String, String> parts = _parts(
      XlsxListExport(_codeAmount),
      const <List<Object?>>[],
      range: (XlsxRange r) => range = r,
    );
    expect(_text(parts, 'A1'), 'Code');
    expect(_cell(parts, 'A2'), isNull);
    expect(_cell(parts, 'B2'), isNull);
    expect(_text(parts, 'A3'), 'Total');
    expect(_formula(parts, 'B3'), 'SUBTOTAL(109,B2:B2)');
    expect(parts[_sheet1], contains('<autoFilter ref="A1:B2"/>'));
    expect(range, XlsxRange.parse('A1:B3'));
  });

  group('excelTable writes a table', () {
    test('excelTable writes a table instead of a filter', () {
      late XlsxRange range;
      final Map<String, String> parts = _parts(
        XlsxListExport(_codeAmount, excelTable: true),
        _twoRows,
        sheetName: 'List',
        range: (XlsxRange r) => range = r,
      );
      expect(parts[_sheet1], isNot(contains('<autoFilter')));
      final String table = parts['xl/tables/table1.xml']!;
      expect(table, contains('name="List"'));
      expect(table, contains('ref="A1:B4"'));
      expect(table, contains('totalsRowCount="1"'));
      expect(table, contains('name="Amount" totalsRowFunction="sum"'));
      expect(_text(parts, 'A1'), 'Code');
      expect(_text(parts, 'B1'), 'Amount');
      expect(_bold(parts, 'A1'), isFalse);
      expect(_bold(parts, 'B1'), isFalse);
      expect(_text(parts, 'A4'), 'Total');
      expect(_bold(parts, 'A4'), isFalse);
      expect(_formula(parts, 'B4'), 'SUBTOTAL(109,B2:B3)');
      expect(_frozenAt(parts), 'A2');
      expect(range, XlsxRange.parse('A1:B4'));
    });

    test('a caller-given header style still applies', () {
      final Map<String, String> parts = _parts(
        XlsxListExport(
          _codeAmount,
          excelTable: true,
          headerStyle: const XlsxStyle(font: XlsxFont(bold: true)),
        ),
        _twoRows,
      );
      expect(_bold(parts, 'A1'), isTrue);
      expect(_bold(parts, 'A4'), isFalse);
    });

    test('a table below a caption starts at the header row', () {
      final Map<String, String> parts = _parts(
        XlsxListExport(_codeAmount, caption: 'Accounts', excelTable: true),
        _twoRows,
      );
      expect(_text(parts, 'A1'), 'Accounts');
      expect(parts['xl/tables/table1.xml'], contains('ref="A2:B5"'));
    });

    test('tableStyle and tableName are passed through', () {
      final Map<String, String> parts = _parts(
        XlsxListExport(
          _codeAmount,
          excelTable: true,
          tableName: 'Accounts',
          tableStyle: XlsxTableStyle.light(9),
        ),
        _twoRows,
      );
      expect(parts['xl/tables/table1.xml'], contains('name="Accounts"'));
      expect(parts['xl/tables/table1.xml'], contains('TableStyleLight9'));
    });

    test('no tableStyle means Medium 2', () {
      final Map<String, String> parts = _parts(
        XlsxListExport(_codeAmount, excelTable: true),
        _twoRows,
      );
      expect(parts['xl/tables/table1.xml'], contains('TableStyleMedium2'));
    });

    test('an empty table keeps one data row', () {
      late XlsxRange range;
      final Map<String, String> parts = _parts(
        XlsxListExport(_codeAmount, excelTable: true),
        const <List<Object?>>[],
        range: (XlsxRange r) => range = r,
      );
      expect(parts['xl/tables/table1.xml'], contains('ref="A1:B3"'));
      expect(_formula(parts, 'B3'), 'SUBTOTAL(109,B2)');
      expect(range, XlsxRange.parse('A1:B3'));
    });

    test('a table without totals has no totals row', () {
      final Map<String, String> parts = _parts(
        XlsxListExport(const <XlsxListColumn>[
          XlsxListColumn('Code'),
        ], excelTable: true),
        const <List<Object?>>[
          <Object?>['A'],
          <Object?>['B'],
        ],
      );
      expect(parts['xl/tables/table1.xml'], contains('ref="A1:A3"'));
      expect(parts['xl/tables/table1.xml'], isNot(contains('totalsRowCount')));
    });

    test('the same table name twice in a workbook throws the writer error', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxListExport export = XlsxListExport(
        _codeAmount,
        excelTable: true,
      );
      export.writeTo(book.addSheet('One'), _twoRows);
      final XlsxSheetWriter two = book.addSheet('Two');
      expect(
        () => XlsxListExport(
          _codeAmount,
          caption: 'C',
          excelTable: true,
        ).writeTo(two, _twoRows),
        _argumentError('name'),
      );
      // The writer's own check comes after the settings and the caption.
      expect(two.rowCount, 1);
    });

    test('a bad table name does not read a lazy rows', () {
      int pulled = 0;
      Iterable<List<Object?>> lazy() sync* {
        pulled++;
        yield <Object?>['A', 1];
      }

      final XlsxSheetWriter sheet = XlsxWriter().addSheet('S');
      expect(
        () => XlsxListExport(
          _codeAmount,
          excelTable: true,
          tableName: '1st',
        ).writeTo(sheet, lazy()),
        _argumentError('tableName'),
      );
      expect(pulled, 0);
      expect(sheet.rowCount, 0);
    });

    test('a lazy rows is read once and a List works', () {
      int pulled = 0;
      Iterable<List<Object?>> lazy() sync* {
        for (final List<Object?> r in _twoRows) {
          pulled++;
          yield r;
        }
      }

      final XlsxListExport export = XlsxListExport(
        _codeAmount,
        excelTable: true,
      );
      final Map<String, String> fromLazy = _parts(export, lazy());
      expect(pulled, 2);
      expect(fromLazy['xl/tables/table1.xml'], contains('ref="A1:B4"'));
      expect(
        _parts(export, _twoRows)['xl/tables/table1.xml'],
        contains('ref="A1:B4"'),
      );
    });

    test('a caller totalsStyle applies to the totals row', () {
      final Map<String, String> parts = _parts(
        XlsxListExport(
          _codeAmount,
          excelTable: true,
          totalsStyle: const XlsxStyle(font: XlsxFont(bold: true)),
        ),
        _twoRows,
      );
      expect(_bold(parts, 'A4'), isTrue);
      expect(_bold(parts, 'B4'), isTrue);
      expect(_bold(parts, 'A1'), isFalse);
    });

    test('a bad table name throws before the sheet is touched', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter sheet = book.addSheet('S');
      expect(
        () => XlsxListExport(
          _codeAmount,
          excelTable: true,
          tableName: '1st',
        ).writeTo(sheet, _twoRows),
        _argumentError('tableName'),
      );
      expect(sheet.rowCount, 0);
    });

    test('a row longer than the columns throws before anything is written', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter sheet = book.addSheet('S');
      expect(
        () => XlsxListExport(_codeAmount, excelTable: true).writeTo(
          sheet,
          const <List<Object?>>[
            <Object?>['A', 1],
            <Object?>[1, 2, 3],
          ],
        ),
        _argumentError('rows[1]'),
      );
      expect(sheet.rowCount, 0);
    });

    test('tableName is not checked in plain mode', () {
      final Map<String, String> parts = _parts(
        XlsxListExport(_codeAmount, tableName: '1st'),
        _twoRows,
      );
      expect(parts.containsKey('xl/tables/table1.xml'), isFalse);
    });
  });

  group('short rows are padded, long rows throw', () {
    test('a row of one value writes A only', () {
      final Map<String, String> parts = _parts(
        XlsxListExport(_codeAmount),
        const <List<Object?>>[
          <Object?>['A'],
          <Object?>['B', 2],
        ],
      );
      expect(_text(parts, 'A2'), 'A');
      expect(_cell(parts, 'B2'), isNull);
      expect(_formula(parts, 'B4'), 'SUBTOTAL(109,B2:B3)');
    });

    test('a row longer than the columns throws, the rows before stay', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter sheet = book.addSheet('S');
      expect(
        () => XlsxListExport(_codeAmount).writeTo(sheet, <List<Object?>>[
          <Object?>['A', 1],
          <Object?>['B', 2, 'extra'],
        ]),
        _argumentError('rows[1]'),
      );
      expect(sheet.rowCount, 2);
      final Uint8List bytes = book.close().bytes;
      expect(checkXlsx(bytes), isEmpty);
      final Map<String, String> parts = readXlsx(bytes);
      expect(_text(parts, 'A2'), 'A');
      expect(_cell(parts, 'A3'), isNull);
    });
  });

  group('bad arguments throw before the sheet is touched', () {
    final Map<String, XlsxListExport> cases = <String, XlsxListExport>{
      'columns': XlsxListExport(const <XlsxListColumn>[]),
      'columns[0].header': XlsxListExport(const <XlsxListColumn>[
        XlsxListColumn(''),
      ]),
      'columns[1].header': XlsxListExport(const <XlsxListColumn>[
        XlsxListColumn('Amount'),
        XlsxListColumn('amount'),
      ]),
      'columns[0].totalsFunction': XlsxListExport(const <XlsxListColumn>[
        XlsxListColumn('A', totalsFunction: XlsxTotalsFunction.custom),
      ]),
      'columns[0].totalsLabel': XlsxListExport(const <XlsxListColumn>[
        XlsxListColumn(
          'A',
          totalsFunction: XlsxTotalsFunction.sum,
          totalsLabel: 'Sum',
        ),
      ]),
    };
    cases.forEach((String field, XlsxListExport export) {
      test(field, () {
        final XlsxWriter book = XlsxWriter();
        final XlsxSheetWriter sheet = book.addSheet('S');
        expect(() => export.writeTo(sheet, _twoRows), _argumentError(field));
        expect(sheet.rowCount, 0);
        sheet.columns(const <XlsxColumn?>[XlsxColumn(width: 5)]);
        sheet.freeze(rows: 3);
        final Map<String, String> parts = readXlsx(book.close().bytes);
        expect(parts[_sheet1], isNot(contains('Print_Titles')));
        expect(parts['xl/workbook.xml'], isNot(contains('Print_Titles')));
        expect(parts[_sheet1], isNot(contains('autoFilter')));
      });
    });
  });

  group('a header or style the table refuses fails before the sheet', () {
    /// Runs [export] over a counting lazy rows and checks that it throws
    /// an [ArgumentError] named [field], reads no row and records nothing.
    void refused(XlsxListExport export, String field) {
      int pulled = 0;
      Iterable<List<Object?>> lazy() sync* {
        pulled++;
        yield <Object?>['A', 1];
      }

      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter sheet = book.addSheet('S');
      expect(() => export.writeTo(sheet, lazy()), _argumentError(field));
      expect(pulled, 0);
      expect(sheet.rowCount, 0);
      sheet.columns(const <XlsxColumn?>[XlsxColumn(width: 5)]);
      sheet.freeze(rows: 3);
      final Map<String, String> parts = readXlsx(book.close().bytes);
      expect(parts[_sheet1], isNot(contains('Print_Titles')));
      expect(parts['xl/workbook.xml'], isNot(contains('Print_Titles')));
    }

    test('a header with a line break, in table mode', () {
      refused(
        XlsxListExport(const <XlsxListColumn>[
          XlsxListColumn('Opening\nbalance'),
          XlsxListColumn('Amount'),
        ], excelTable: true),
        'columns[0].header',
      );
    });

    test('a header over 255 characters, in table mode', () {
      refused(
        XlsxListExport(<XlsxListColumn>[
          const XlsxListColumn('Code'),
          XlsxListColumn('x' * 256),
        ], excelTable: true),
        'columns[1].header',
      );
    });

    test('the error keeps the value and the message', () {
      expect(
        () => XlsxListExport(const <XlsxListColumn>[
          XlsxListColumn('Opening\nbalance'),
        ], excelTable: true).writeTo(XlsxWriter().addSheet('S'), _twoRows),
        throwsA(
          isA<ArgumentError>()
              .having(
                (ArgumentError e) => e.invalidValue,
                'value',
                'Opening\nbalance',
              )
              .having(
                (ArgumentError e) => e.message,
                'message',
                contains('line break'),
              ),
        ),
      );
    });

    test('a table style the writer refuses, in table mode', () {
      refused(
        XlsxListExport(
          _codeAmount,
          excelTable: true,
          tableStyle: const XlsxTableStyle('Fancy'),
        ),
        'tableStyle',
      );
    });

    test('plain mode keeps a header with a line break', () {
      final Map<String, String> parts = _parts(
        XlsxListExport(const <XlsxListColumn>[
          XlsxListColumn('Opening\nbalance'),
          XlsxListColumn('Amount'),
        ]),
        _twoRows,
      );
      expect(parts['xl/sharedStrings.xml'], contains('Opening'));
    });
  });

  test('a width out of range throws columns[i].width and records nothing', () {
    final XlsxWriter book = XlsxWriter();
    final XlsxSheetWriter sheet = book.addSheet('S');
    expect(
      () => XlsxListExport(const <XlsxListColumn>[
        XlsxListColumn('Code'),
        XlsxListColumn('Amount', width: 1000),
      ]).writeTo(sheet, _twoRows),
      _argumentError('columns[1].width'),
    );
    expect(sheet.rowCount, 0);
    final Map<String, String> parts = readXlsx(book.close().bytes);
    expect(parts[_sheet1], isNot(contains('Print_Titles')));
    expect(parts[_sheet1], isNot(contains('<pane')));
    expect(parts['xl/workbook.xml'], isNot(contains('Print_Titles')));
  });

  test('writeTo needs a sheet without rows', () {
    final XlsxWriter book = XlsxWriter();
    final XlsxSheetWriter sheet = book.addSheet('S')..row(<Object?>['x']);
    expect(
      () => XlsxListExport(_codeAmount).writeTo(sheet, _twoRows),
      throwsStateError,
    );
    expect(sheet.rowCount, 1);
    final Map<String, String> parts = readXlsx(book.close().bytes);
    expect(parts[_sheet1], isNot(contains('autoFilter')));
    expect(parts[_sheet1], isNot(contains('<pane')));
    expect(parts['xl/workbook.xml'], isNot(contains('Print_Titles')));
  });

  test('toXlsx writes a one-sheet workbook', () {
    final XlsxListExport export = XlsxListExport(
      _codeAmount,
      caption: 'Accounts',
    );
    final XlsxResult result = export.toXlsx(
      _twoRows,
      properties: const XlsxProperties(title: 'Accounts'),
    );
    expect(checkXlsx(result.bytes), isEmpty);
    expect(result.warnings, isEmpty);
    final Map<String, String> parts = readXlsx(result.bytes);
    final List<String> names = <String>[
      for (final XmlElement s in XmlDocument.parse(
        parts['xl/workbook.xml']!,
      ).findAllElements('sheet'))
        s.getAttribute('name')!,
    ];
    expect(names, <String>['List']);
    expect(parts['docProps/core.xml'], contains('Accounts'));
    expect(
      parts[_sheet1],
      _parts(export, _twoRows, sheetName: 'List')[_sheet1],
    );
    expect(
      readXlsx(
        export.toXlsx(_twoRows, sheetName: 'Konten').bytes,
      )['xl/workbook.xml'],
      contains('name="Konten"'),
    );
  });

  group('XlsxListColumn and XlsxListExport compare by value', () {
    test('XlsxListColumn', () {
      const XlsxListColumn a = XlsxListColumn(
        'Amount',
        width: 12,
        style: _money,
        totalsFunction: XlsxTotalsFunction.sum,
      );
      const XlsxListColumn same = XlsxListColumn(
        'Amount',
        width: 12,
        style: _money,
        totalsFunction: XlsxTotalsFunction.sum,
      );
      expect(a, same);
      expect(a.hashCode, same.hashCode);
      for (final XlsxListColumn other in const <XlsxListColumn>[
        XlsxListColumn(
          'Amounts',
          width: 12,
          style: _money,
          totalsFunction: XlsxTotalsFunction.sum,
        ),
        XlsxListColumn(
          'Amount',
          width: 13,
          style: _money,
          totalsFunction: XlsxTotalsFunction.sum,
        ),
        XlsxListColumn(
          'Amount',
          width: 12,
          totalsFunction: XlsxTotalsFunction.sum,
        ),
        XlsxListColumn('Amount', width: 12, style: _money),
        XlsxListColumn('Amount', width: 12, style: _money, totalsLabel: 'x'),
      ]) {
        expect(a, isNot(other));
      }
      expect(
        a.toString(),
        allOf(
          contains('Amount'),
          contains('width: 12'),
          contains('style: '),
          contains('totalsFunction: sum'),
          contains('totalsLabel: null'),
        ),
      );
    });

    test('XlsxListExport', () {
      XlsxListExport make({
        String header = 'Code',
        String? caption = 'C',
        XlsxStyle? captionStyle = _money,
        XlsxStyle? headerStyle = _money,
        XlsxStyle? totalsStyle = _money,
        bool excelTable = true,
        String tableName = 'T',
        XlsxTableStyle? tableStyle = const XlsxTableStyle('TableStyleDark1'),
      }) => XlsxListExport(
        <XlsxListColumn>[XlsxListColumn(header)],
        caption: caption,
        captionStyle: captionStyle,
        headerStyle: headerStyle,
        totalsStyle: totalsStyle,
        excelTable: excelTable,
        tableName: tableName,
        tableStyle: tableStyle,
      );
      final XlsxListExport a = make();
      expect(a, make());
      expect(a.hashCode, make().hashCode);
      for (final XlsxListExport other in <XlsxListExport>[
        make(header: 'Name'),
        make(caption: null),
        make(captionStyle: null),
        make(headerStyle: null),
        make(totalsStyle: null),
        make(excelTable: false),
        make(tableName: 'U'),
        make(tableStyle: null),
      ]) {
        expect(a, isNot(other));
      }
      expect(
        a.toString(),
        allOf(<Matcher>[
          contains('XlsxListColumn(Code'),
          contains('caption: C'),
          contains('captionStyle: '),
          contains('headerStyle: '),
          contains('totalsStyle: '),
          contains('excelTable: true'),
          contains('tableName: T'),
          contains('tableStyle: '),
        ]),
      );
    });

    test('the columns are an unmodifiable copy', () {
      final List<XlsxListColumn> columns = <XlsxListColumn>[
        const XlsxListColumn('Code'),
      ];
      final XlsxListExport export = XlsxListExport(columns);
      columns.add(const XlsxListColumn('Name'));
      expect(export.columns, hasLength(1));
      expect(
        () => export.columns.add(const XlsxListColumn('Name')),
        throwsUnsupportedError,
      );
    });
  });

  group('a count total is a plain number (General format)', () {
    const List<XlsxListColumn> columns = <XlsxListColumn>[
      XlsxListColumn(
        'Opened',
        style: XlsxStyle(numFmt: XlsxNumFmt.localeShortDate),
        totalsFunction: XlsxTotalsFunction.count,
      ),
      XlsxListColumn(
        'Numbers',
        style: XlsxStyle(numFmt: XlsxNumFmt.localeShortDate),
        totalsFunction: XlsxTotalsFunction.countNums,
      ),
      XlsxListColumn(
        'Amount',
        style: _money,
        totalsFunction: XlsxTotalsFunction.sum,
      ),
    ];
    const List<List<Object?>> rows = <List<Object?>>[
      <Object?>[XlsxDate(2024, 1, 15), XlsxDate(2024, 1, 16), 1.5],
    ];

    void expectFormats(Map<String, String> parts) {
      // The data cells keep the date format; the count totals are General.
      expect(_numFmtId(parts, 'A2'), 14);
      expect(_numFmtId(parts, 'B2'), 14);
      expect(_numFmtId(parts, 'A3'), 0);
      expect(_numFmtId(parts, 'B3'), 0);
      expect(_formula(parts, 'A3'), 'SUBTOTAL(103,A2)');
      expect(_formula(parts, 'B3'), 'SUBTOTAL(102,B2)');
      // A sum keeps the column's money format.
      expect(_numFmtId(parts, 'C3'), _numFmtId(parts, 'C2'));
      expect(_numFmtId(parts, 'C3'), isNot(0));
    }

    test('in plain mode', () {
      final Map<String, String> parts = _parts(XlsxListExport(columns), rows);
      expect(_formula(parts, 'A3'), 'SUBTOTAL(103,A2:A2)');
      expect(_numFmtId(parts, 'A2'), 14);
      expect(_numFmtId(parts, 'A3'), 0);
      expect(_numFmtId(parts, 'B3'), 0);
      expect(_numFmtId(parts, 'C3'), _numFmtId(parts, 'C2'));
      expect(_numFmtId(parts, 'C3'), isNot(0));
      expect(_bold(parts, 'A3'), isTrue);
    });

    test('in table mode', () {
      final Map<String, String> parts = _parts(
        XlsxListExport(columns, excelTable: true),
        rows,
      );
      expectFormats(parts);
    });
  });
}
