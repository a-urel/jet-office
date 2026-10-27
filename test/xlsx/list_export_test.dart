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
  XlsxListColumn('Amount', style: _money, totals: XlsxTotalsFunction.sum),
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
            totals: XlsxTotalsFunction.sum,
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
          XlsxListColumn('Code', totals: XlsxTotalsFunction.count),
          XlsxListColumn(
            'Amount',
            style: _money,
            totals: XlsxTotalsFunction.sum,
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
      'columns[0].totals': XlsxListExport(const <XlsxListColumn>[
        XlsxListColumn('A', totals: XlsxTotalsFunction.custom),
      ]),
      'columns[0].totalsLabel': XlsxListExport(const <XlsxListColumn>[
        XlsxListColumn('A', totals: XlsxTotalsFunction.sum, totalsLabel: 'Sum'),
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
        totals: XlsxTotalsFunction.sum,
      );
      const XlsxListColumn same = XlsxListColumn(
        'Amount',
        width: 12,
        style: _money,
        totals: XlsxTotalsFunction.sum,
      );
      expect(a, same);
      expect(a.hashCode, same.hashCode);
      for (final XlsxListColumn other in const <XlsxListColumn>[
        XlsxListColumn(
          'Amounts',
          width: 12,
          style: _money,
          totals: XlsxTotalsFunction.sum,
        ),
        XlsxListColumn(
          'Amount',
          width: 13,
          style: _money,
          totals: XlsxTotalsFunction.sum,
        ),
        XlsxListColumn('Amount', width: 12, totals: XlsxTotalsFunction.sum),
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
          contains('totals: sum'),
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
      }) => XlsxListExport(
        <XlsxListColumn>[XlsxListColumn(header)],
        caption: caption,
        captionStyle: captionStyle,
        headerStyle: headerStyle,
        totalsStyle: totalsStyle,
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
      ]) {
        expect(a, isNot(other));
      }
      expect(
        a.toString(),
        allOf(
          contains('XlsxListColumn(Code'),
          contains('caption: C'),
          contains('captionStyle: '),
          contains('headerStyle: '),
          contains('totalsStyle: '),
        ),
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
}
