import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import 'support/workbook_builder.dart';

/// A reader over one sheet `S` holding [rows].
XlsxReader _reader(
  String rows, {
  String? sharedStrings,
  XlsxReadLimits limits = const XlsxReadLimits(),
}) => XlsxReader(
  buildWorkbook(<String, String?>{
    'S': worksheet(rows),
  }, sharedStrings: sharedStrings),
  limits: limits,
);

/// Each warning of [r] as its code name and cells: `cellDuplicated B1,C1`.
List<String> _warnings(XlsxReader r) => <String>[
  for (final XlsxWarning w in r.warnings) '${w.code.name} ${w.cells.join(',')}',
];

/// Each row of [rows] as its index and its cells' columns: `3:0,2`.
List<String> _layout(List<XlsxReadRow> rows) => <String>[
  for (final XlsxReadRow row in rows)
    '${row.index}:${row.cells.map((XlsxReadCell c) => c.column).join(',')}',
];

void main() {
  test('places cells and rows without r', () {
    final XlsxReader r = _reader(
      '<row><c><v>1</v></c><c><v>2</v></c></row>'
      '<row r="4"><c r="C4"><v>3</v></c><c><v>4</v></c></row>'
      '<row><c r="B5"><v>5</v></c></row>',
    );
    expect(_layout(r.rows('S').toList()), <String>['0:0,1', '3:2,3', '4:1']);
    expect(r.warnings, isEmpty);
  });

  test('a cell reference for another row or unparsable is positional', () {
    final XlsxReader r = _reader(
      '<row r="2"><c r="C2"><v>1</v></c><c r="E7"><v>2</v></c>'
      '<c r="?"><v>3</v></c><c r="A01"><v>4</v></c></row>',
    );
    expect(_layout(r.rows('S').toList()), <String>['1:2,3,4,5']);
    expect(_warnings(r), <String>['cellReferenceInvalid D2,E2,F2']);
  });

  test('an invalid row r is positional and warns on its first cell', () {
    for (final String bad in <String>['0', 'x', '-3', '1.5', '000']) {
      final XlsxReader r = _reader(
        '<row r="2"><c r="A2"><v>1</v></c></row>'
        '<row r="$bad"><c r="B3"><v>2</v></c><c r="C3"><v>3</v></c></row>',
      );
      expect(_layout(r.rows('S').toList()), <String>[
        '1:0',
        '2:1,2',
      ], reason: bad);
      expect(_warnings(r), <String>['cellReferenceInvalid B3'], reason: bad);
    }
  });

  test('a row r with leading zeros is that row', () {
    final XlsxReader r = _reader('<row r="007"><c r="A7"><v>1</v></c></row>');
    expect(r.rows('S').single.index, 6);
    expect(r.warnings, isEmpty);
  });

  test('keeps the last of two cells at one column, warns', () {
    final XlsxReader r = _reader(
      '<row r="1"><c r="B1"><v>1</v></c><c r="A1"><v>2</v></c>'
      '<c r="B1"><v>3</v></c></row>',
    );
    final XlsxReadRow row = r.rows('S').single;
    expect(row.cells, <XlsxReadCell>[
      XlsxReadCell(0, XlsxDecimal('2')),
      XlsxReadCell(1, XlsxDecimal('3')),
    ]);
    expect(_warnings(r), <String>['cellDuplicated B1']);
  });

  test('returns cells in column order whatever the file order', () {
    final XlsxReader r = _reader(
      '<row r="1"><c r="D1"><v>1</v></c><c r="B1"><v>2</v></c>'
      '<c r="C1"><v>3</v></c><c r="A1"><v>4</v></c></row>',
    );
    expect(_layout(r.rows('S').toList()), <String>['0:0,1,2,3']);
    expect(r.warnings, isEmpty);
  });

  test('skips a cell beyond XFD with cellOutsideSheet', () {
    final XlsxReader r = _reader(
      '<row r="1"><c r="XFD1"><v>1</v></c><c r="XFE1"><v>2</v></c>'
      '<c><v>3</v></c></row>',
    );
    expect(_layout(r.rows('S').toList()), <String>['0:16383']);
    expect(_warnings(r), <String>['cellOutsideSheet XFE1']);
    expect(r.warnings.single.count, 2);
  });

  test('skips the cells of a row beyond the last row', () {
    final XlsxReader r = _reader(
      '<row r="1048576"><c r="A1048576"><v>1</v></c></row>'
      '<row r="1048577"><c r="A1048577"><v>2</v></c><c/></row>'
      '<row r="99999999999999999999999"><c><v>3</v></c></row>'
      '<row><c><v>4</v></c></row>',
    );
    expect(_layout(r.rows('S').toList()), <String>['1048575:0']);
    expect(_warnings(r), <String>['cellOutsideSheet A1048577']);
    expect(r.warnings.single.count, 3);
  });

  test('yields an out-of-order row and warns', () {
    final XlsxReader r = _reader(
      '<row r="3"><c r="A3"><v>1</v></c></row>'
      '<row r="2"><c r="B2"><v>2</v></c></row>'
      '<row r="2"><c r="C2"><v>3</v></c></row>',
    );
    expect(_layout(r.rows('S').toList()), <String>['2:0', '1:1', '1:2']);
    expect(_warnings(r), <String>['rowOutOfOrder B2,C2']);
  });

  test('yields hidden rows and rows with data only', () {
    final XlsxReader r = _reader(
      '<row r="1"/>'
      '<row r="2" hidden="1"/>'
      '<row r="3" hidden="true"><c r="A3"/></row>'
      '<row r="4" hidden="0"><c r="A4" s="1"/></row>'
      '<row r="5" hidden="false"><c r="A5"><v>1</v></c></row>',
    );
    final List<XlsxReadRow> rows = r.rows('S').toList();
    expect(rows.map((XlsxReadRow row) => (row.index, row.hidden)), <Object>[
      (1, true),
      (2, true),
      (4, false),
    ]);
    expect(rows[0].cells, isEmpty);
    expect(r.warnings, isEmpty);
  });

  test('a cell with a formula or an inline string is data', () {
    final XlsxReader r = _reader(
      '<row r="1"><c r="A1"><f>1+1</f></c>'
      '<c r="B1" t="inlineStr"><is><t>x</t></is></c>'
      '<c r="C1" t="str"><f>"a"&amp;"b"</f><v>ab</v></c>'
      '<c r="D1"><f/><v>4</v></c></row>',
    );
    expect(r.rows('S').single.cells, <XlsxReadCell>[
      const XlsxReadCell(0, null, formula: '1+1'),
      const XlsxReadCell(1, null),
      const XlsxReadCell(2, 'ab', formula: '"a"&"b"'),
      XlsxReadCell(3, XlsxDecimal('4')),
    ]);
    expect(_warnings(r), <String>[
      'formulaWithoutValue A1',
      'cellTypeUnsupported B1',
    ]);
  });

  test('reads prefixed SpreadsheetML elements', () {
    final XlsxReader r = XlsxReader(
      buildWorkbook(<String, String?>{
        'S':
            '<x:worksheet xmlns:x="$mainNs"><x:sheetData>'
            '<x:row r="1"><x:c r="A1" t="s"><x:v>0</x:v></x:c></x:row>'
            '</x:sheetData></x:worksheet>',
      }, sharedStrings: '<sst xmlns="$mainNs"><si><t>hi</t></si></sst>'),
    );
    expect(r.rows('S').single.cells.single.value, 'hi');
  });

  test('ignores elements of other namespaces and outside sheetData', () {
    final XlsxReader r = XlsxReader(
      buildWorkbook(<String, String?>{
        'S':
            '<worksheet xmlns="$mainNs" xmlns:o="urn:other">'
            '<sheetPr><row r="9"><c><v>9</v></c></row></sheetPr>'
            '<sheetData><o:row r="1"><o:c><o:v>1</o:v></o:c></o:row>'
            '<row r="2"><c r="A2"><o:v>2</o:v><v>3</v><extLst/></c></row>'
            '</sheetData></worksheet>',
      }),
    );
    expect(r.rows('S').toList(), <XlsxReadRow>[
      XlsxReadRow(1, <XlsxReadCell>[XlsxReadCell(0, XlsxDecimal('3'))]),
    ]);
  });

  test('a part that is not a worksheet reads as no rows', () {
    for (final String xml in <String>[
      '<chartsheet xmlns="$mainNs"><sheetData><row r="1"><c><v>1</v></c>'
          '</row></sheetData></chartsheet>',
      '<worksheet xmlns="urn:other"><sheetData><row r="1"><c><v>1</v></c>'
          '</row></sheetData></worksheet>',
      '<worksheet xmlns="$mainNs"/>',
      '<worksheet xmlns="$mainNs"><sheetData/></worksheet>',
      '<worksheet xmlns="$mainNs"><dimension ref="A1"/></worksheet>',
    ]) {
      final XlsxReader r = XlsxReader(
        buildWorkbook(<String, String?>{'S': xml}),
      );
      expect(r.rows('S'), isEmpty, reason: xml);
      expect(r.warnings, isEmpty, reason: xml);
    }
  });

  test('a bad entity in a value throws malformedXml naming the part', () {
    final XlsxReader r = _reader(
      '<row r="1"><c r="A1"><v>&nope;</v></c></row>',
    );
    expect(
      () => r.rows('S').toList(),
      throwsA(
        isA<XlsxReadException>()
            .having(
              (XlsxReadException e) => e.reason,
              'reason',
              XlsxReadFailure.malformedXml,
            )
            .having(
              (XlsxReadException e) => e.part,
              'part',
              'xl/worksheets/sheet1.xml',
            ),
      ),
    );
  });

  test('truncated sheet XML throws malformedXml', () {
    final XlsxReader r = XlsxReader(
      buildWorkbook(<String, String?>{
        'S': '<worksheet xmlns="$mainNs"><sheetData><row r="1"><c r="A1">',
      }),
    );
    expect(
      () => r.rows('S').toList(),
      throwsA(
        isA<XlsxReadException>().having(
          (XlsxReadException e) => e.reason,
          'reason',
          XlsxReadFailure.malformedXml,
        ),
      ),
    );
  });

  test('a value or formula longer than maxTextLength throws', () {
    const XlsxReadLimits limits = XlsxReadLimits(maxTextLength: 4);
    for (final String cell in <String>[
      '<c r="A1" t="str"><v>abcde</v></c>',
      '<c r="A1" t="str"><v>ab<![CDATA[cde]]></v></c>',
      '<c r="A1"><f>SUM(A2)</f><v>1</v></c>',
    ]) {
      final XlsxReader r = _reader('<row r="1">$cell</row>', limits: limits);
      expect(
        () => r.rows('S').toList(),
        throwsA(
          isA<XlsxReadException>()
              .having(
                (XlsxReadException e) => e.reason,
                'reason',
                XlsxReadFailure.limitExceeded,
              )
              .having(
                (XlsxReadException e) => e.part,
                'part',
                'xl/worksheets/sheet1.xml',
              )
              .having(
                (XlsxReadException e) => e.message,
                'message',
                startsWith('Limit maxTextLength (4) exceeded'),
              ),
        ),
        reason: cell,
      );
    }
    final XlsxReader ok = _reader(
      '<row r="1"><c r="A1" t="str"><v>abcd</v></c></row>',
      limits: limits,
    );
    expect(ok.rows('S').single.cells.single.value, 'abcd');
  });

  test('value objects compare by value and print readably', () {
    final XlsxReadRow a = XlsxReadRow(2, <XlsxReadCell>[
      XlsxReadCell(1, XlsxDecimal('1'), formula: 'A1'),
    ], hidden: true);
    final XlsxReadRow b = XlsxReadRow(2, <XlsxReadCell>[
      XlsxReadCell(1, XlsxDecimal('1'), formula: 'A1'),
    ], hidden: true);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(XlsxReadRow(2, a.cells)));
    expect(a.cells, isA<List<XlsxReadCell>>());
    expect(() => a.cells.add(const XlsxReadCell(0, 1)), throwsUnsupportedError);
    expect(
      a.toString(),
      'XlsxReadRow(2, hidden, [XlsxReadCell(1, XlsxDecimal(1), formula: A1)])',
    );
    expect(const XlsxReadCell(0, 'x').toString(), 'XlsxReadCell(0, x)');
    expect(
      const XlsxReadSheet('S', 0, XlsxSheetVisibility.visible).toString(),
      'XlsxReadSheet(0, S, visible)',
    );
  });
}
