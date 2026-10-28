import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/cell_ref.dart';
import 'package:test/test.dart';

import 'support/workbook_builder.dart';

/// A reader over one sheet `S` holding [rows].
XlsxReader _reader(
  String rows, {
  String? sharedStrings,
  String? styles,
  XlsxReadLimits limits = const XlsxReadLimits(),
}) => XlsxReader(
  buildWorkbook(
    <String, String?>{'S': worksheet(rows)},
    sharedStrings: sharedStrings,
    styles: styles,
  ),
  limits: limits,
);

/// A styles part with the custom [numFmts] (id to code) and one `<xf>` per
/// id of [xfs], in order.
String _styles(Map<int, String> numFmts, List<int> xfs) =>
    '<styleSheet xmlns="$mainNs">'
    '<numFmts count="${numFmts.length}">'
    '${numFmts.entries.map((MapEntry<int, String> e) => '<numFmt numFmtId="${e.key}" formatCode="${e.value}"/>').join()}'
    '</numFmts><cellXfs count="${xfs.length}">'
    '${xfs.map((int id) => '<xf numFmtId="$id"/>').join()}'
    '</cellXfs></styleSheet>';

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
  test('formula text is returned as written, never stripped of "="', () {
    final XlsxReader r = _reader(
      '<row><c r="A1"><f>=SUM(A1)</f><v>1</v></c>'
      '<c r="B1"><f>SUM(A1)</f><v>1</v></c></row>',
    );
    final List<XlsxReadCell> cells = r.rows('S').single.cells;
    expect(cells[0].formula, '=SUM(A1)');
    expect(cells[1].formula, 'SUM(A1)');
  });

  test('a shared follower reads formula null with its group and value', () {
    final XlsxReader r = _reader(
      '<row r="1"><c r="A1"><f t="shared" ref="A1:A3" si="0">B1+1</f>'
      '<v>2</v></c></row>'
      '<row r="2"><c r="A2"><f t="shared" si="0"/><v>3</v></c></row>'
      '<row r="3"><c r="A3"><f t="shared" si="0">B3+1</f><v>4</v></c></row>',
    );
    const XlsxRange range = XlsxRange(0, 0, 2, 0);
    const XlsxFormulaGroup follower = XlsxFormulaGroup(
      XlsxFormulaGroupKind.shared,
      range,
      isMaster: false,
    );
    expect(r.rows('S').toList(), <XlsxReadRow>[
      XlsxReadRow(0, <XlsxReadCell>[
        XlsxReadCell(
          0,
          XlsxDecimal('2'),
          formula: 'B1+1',
          formulaGroup: const XlsxFormulaGroup(
            XlsxFormulaGroupKind.shared,
            range,
            isMaster: true,
          ),
        ),
      ]),
      XlsxReadRow(1, <XlsxReadCell>[
        XlsxReadCell(0, XlsxDecimal('3'), formulaGroup: follower),
      ]),
      XlsxReadRow(2, <XlsxReadCell>[
        XlsxReadCell(
          0,
          XlsxDecimal('4'),
          formula: 'B3+1',
          formulaGroup: follower,
        ),
      ]),
    ]);
    expect(r.warnings, isEmpty);
  });

  test('array continuation cells without <f>', () {
    final XlsxReader r = _reader(
      '<row r="1"><c r="A1"><v>0</v></c>'
      '<c r="B1"><f t="array" ref="B1:C2">A1:A2*2</f><v>1</v></c>'
      '<c r="C1"><v>2</v></c><c r="D1"><v>9</v></c></row>'
      '<row r="2"><c r="B2"><v>3</v></c><c r="C2"/></row>'
      '<row r="3"><c r="B3"><v>4</v></c></row>',
    );
    const XlsxRange range = XlsxRange(0, 1, 1, 2);
    const XlsxFormulaGroup follower = XlsxFormulaGroup(
      XlsxFormulaGroupKind.array,
      range,
      isMaster: false,
    );
    expect(r.rows('S').toList(), <XlsxReadRow>[
      XlsxReadRow(0, <XlsxReadCell>[
        XlsxReadCell(0, XlsxDecimal('0')),
        XlsxReadCell(
          1,
          XlsxDecimal('1'),
          formula: 'A1:A2*2',
          formulaGroup: const XlsxFormulaGroup(
            XlsxFormulaGroupKind.array,
            range,
            isMaster: true,
          ),
        ),
        XlsxReadCell(2, XlsxDecimal('2'), formulaGroup: follower),
        XlsxReadCell(3, XlsxDecimal('9')),
      ]),
      // C2 has no data, so it is not produced.
      XlsxReadRow(1, <XlsxReadCell>[
        XlsxReadCell(1, XlsxDecimal('3'), formulaGroup: follower),
      ]),
      XlsxReadRow(2, <XlsxReadCell>[XlsxReadCell(1, XlsxDecimal('4'))]),
    ]);
    expect(r.warnings, isEmpty);
  });

  test('a data table names its group on every cell', () {
    final XlsxReader r = _reader(
      '<row r="2"><c r="B2"><f t="dataTable" ref="B2:B3" dt2D="0" dtr="0" '
      'r1="A1"/><v>5</v></c></row>'
      '<row r="3"><c r="B3"><v>6</v></c></row>',
    );
    final List<XlsxReadRow> rows = r.rows('S').toList();
    expect(rows[0].cells.single.formulaGroup!.isMaster, isTrue);
    expect(rows[0].cells.single.formula, isNull);
    expect(
      rows[1].cells.single.formulaGroup,
      const XlsxFormulaGroup(
        XlsxFormulaGroupKind.dataTable,
        XlsxRange(1, 1, 2, 1),
        isMaster: false,
      ),
    );
    expect(r.warnings, isEmpty);
  });

  test('a cell with its own <f> inside an array range', () {
    final XlsxReader r = _reader(
      '<row r="1"><c r="A1"><f t="array" ref="A1:A3">B1:B3</f><v>1</v></c>'
      '</row>'
      '<row r="2"><c r="A2"><f>B2</f><v>2</v></c></row>'
      '<row r="3"><c r="A3"><f t="shared" ref="A3:A4" si="0">B3</f>'
      '<v>3</v></c></row>'
      '<row r="4"><c r="A4"><f t="shared" si="0"/><v>4</v></c></row>',
    );
    final List<XlsxReadRow> rows = r.rows('S').toList();
    expect(
      rows[1].cells.single,
      XlsxReadCell(0, XlsxDecimal('2'), formula: 'B2'),
    );
    expect(
      rows[2].cells.single,
      XlsxReadCell(0, XlsxDecimal('3'), formula: 'B3'),
    );
    // A3's shared formula was not defined, so A4 follows nothing.
    expect(rows[3].cells.single, XlsxReadCell(0, XlsxDecimal('4')));
    expect(_warnings(r), <String>['formulaGroupInvalid A2,A3,A4']);
  });

  test('invalid groups keep their values and name the cells', () {
    final XlsxReader r = _reader(
      '<row r="1"><c r="A1"><f t="shared" si="0">1</f><v>1</v></c>'
      '<c r="B1"><f t="shared" ref="B1:B2" si="-1">2</f><v>2</v></c>'
      '<c r="C1"><f t="array" ref="x">3</f><v>3</v></c>'
      '<c r="D1"><f t="unknown" ref="D1:D2">4</f><v>4</v></c></row>'
      '<row r="2"><c r="A2"><f t="shared" si="7"/><v>5</v></c></row>',
    );
    final List<XlsxReadRow> rows = r.rows('S').toList();
    expect(rows[0].cells, <XlsxReadCell>[
      XlsxReadCell(0, XlsxDecimal('1'), formula: '1'),
      XlsxReadCell(1, XlsxDecimal('2'), formula: '2'),
      XlsxReadCell(2, XlsxDecimal('3'), formula: '3'),
      XlsxReadCell(3, XlsxDecimal('4'), formula: '4'),
    ]);
    expect(rows[1].cells, <XlsxReadCell>[XlsxReadCell(0, XlsxDecimal('5'))]);
    // An unknown t is a normal formula: D1 is fine.
    expect(_warnings(r), <String>['formulaGroupInvalid A1,B1,C1,A2']);
  });

  test("a shared follower outside its master's ref is invalid", () {
    final XlsxReader r = _reader(
      '<row r="1"><c r="A1"><f t="shared" ref="A1:A2" si="0">B1</f>'
      '<v>1</v></c></row>'
      '<row r="2"><c r="A2"><f t="shared" si="0"/><v>2</v></c>'
      '<c r="B2"><f t="shared" si="0">C2</f><v>3</v></c></row>',
    );
    final List<XlsxReadCell> cells = r.rows('S').last.cells;
    expect(cells[0].formulaGroup!.range, XlsxRange.parse('A1:A2'));
    expect(cells[1], XlsxReadCell(1, XlsxDecimal('3'), formula: 'C2'));
    expect(_warnings(r), <String>['formulaGroupInvalid B2']);
  });

  test('formulaGroupInvalid comes with a content warning', () {
    final XlsxReader r = _reader(
      '<row r="1"><c r="A1"><f t="shared" si="3"/><v>abc</v></c>'
      '<c r="B1"><f t="shared" si="3"/></c></row>',
    );
    expect(r.rows('S').single.cells, <XlsxReadCell>[
      const XlsxReadCell(0, null),
      const XlsxReadCell(1, null),
    ]);
    expect(_warnings(r), <String>[
      'numberInvalid A1',
      'formulaGroupInvalid A1,B1',
      'formulaWithoutValue B1',
    ]);
  });

  test('formula groups start afresh on every pass', () {
    final XlsxReader r = _reader(
      '<row r="1"><c r="A1"><f t="array" ref="A1:A2">1</f><v>1</v></c></row>'
      '<row r="2"><c r="A2"><v>2</v></c></row>',
    );
    final List<XlsxReadRow> first = r.rows('S').toList();
    expect(r.rows('S').toList(), first);
    expect(first[1].cells.single.formulaGroup!.isMaster, isFalse);
    expect(r.warnings, isEmpty);
  });

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

  test('sorts a full row written right to left without quadratic cost', () {
    // Inserting each cell in place costs O(n²) on such a row: 16,384 cells
    // in 8 rows took seconds. Appending and sorting once takes milliseconds.
    final StringBuffer rows = StringBuffer();
    for (int r = 1; r <= 8; r++) {
      rows.write('<row r="$r">');
      for (int c = 16383; c >= 0; c--) {
        rows.write('<c r="${cellRef(r - 1, c)}"><v>$c</v></c>');
      }
      rows.write('</row>');
    }
    final XlsxReader r = _reader(rows.toString());
    final Stopwatch watch = Stopwatch()..start();
    final List<XlsxReadRow> read = r.rows('S').toList();
    watch.stop();
    expect(read, hasLength(8));
    for (final XlsxReadRow row in read) {
      expect(row.cells, hasLength(16384));
      for (int c = 0; c < 16384; c++) {
        expect(row.cells[c].column, c);
      }
      expect(row.cells.last.value, XlsxDecimal('16383'));
    }
    expect(r.warnings, isEmpty);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('a duplicate among out-of-order cells keeps the last and warns', () {
    final XlsxReader r = _reader(
      '<row r="1"><c r="C1"><v>1</v></c><c r="A1"><v>2</v></c>'
      '<c r="B1" t="b"><v>x</v></c><c r="A1"><v>3</v></c>'
      '<c r="C1"><v>4</v></c><c r="B1"><v>5</v></c></row>',
    );
    expect(r.rows('S').single.cells, <XlsxReadCell>[
      XlsxReadCell(0, XlsxDecimal('3')),
      XlsxReadCell(1, XlsxDecimal('5')),
      XlsxReadCell(2, XlsxDecimal('4')),
    ]);
    expect(_warnings(r), <String>[
      'booleanInvalid B1',
      'cellDuplicated A1,C1,B1',
    ]);
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
      const XlsxReadCell(1, 'x'),
      const XlsxReadCell(2, 'ab', formula: '"a"&"b"'),
      XlsxReadCell(3, XlsxDecimal('4')),
    ]);
    expect(_warnings(r), <String>['formulaWithoutValue A1']);
  });

  group('number formats', () {
    test("a cell's number format", () {
      final XlsxReader r = _reader(
        '<row r="1"><c r="A1" s="1"><v>46319</v></c></row>',
        styles: _styles(<int, String>{164: 'dd.mm.yyyy'}, <int>[0, 164]),
      );
      final XlsxReadCell cell = r.rows('S').single.cells.single;
      expect(cell.value, DateTime.utc(2026, 10, 24));
      expect(cell.numberFormatId, 164);
      expect(cell.numberFormat, 'dd.mm.yyyy');
      expect(cell.isDate, isTrue);
      expect(r.warnings, isEmpty);
    });

    test('a time format gives a Duration', () {
      final XlsxReader r = _reader(
        '<row r="1"><c r="A1" s="1"><v>1.5</v></c></row>',
        styles: _styles(<int, String>{165: '[h]:mm'}, <int>[0, 165]),
      );
      final XlsxReadCell cell = r.rows('S').single.cells.single;
      expect(cell.value, const Duration(hours: 36));
      expect(cell.numberFormatId, 165);
      expect(cell.numberFormat, '[h]:mm');
      expect(cell.isDate, isTrue);
      expect(r.warnings, isEmpty);
    });

    test('an s past cellXfs and s="1" without styles', () {
      for (final String? styles in <String?>[
        _styles(const <int, String>{}, <int>[0]),
        null,
      ]) {
        final XlsxReader r = _reader(
          '<row r="1"><c r="A1"><v>1</v></c>'
          '<c r="B1" s="1"><v>46319</v></c></row>',
          styles: styles,
        );
        expect(r.rows('S').single.cells, <XlsxReadCell>[
          XlsxReadCell(0, XlsxDecimal('1')),
          XlsxReadCell(1, XlsxDecimal('46319')),
        ], reason: '$styles');
        final XlsxReadCell cell = r.rows('S').single.cells[1];
        expect(cell.numberFormatId, 0);
        expect(cell.numberFormat, 'General');
        expect(cell.isDate, isFalse);
        expect(_warnings(r), <String>['styleInvalid B1'], reason: '$styles');
      }
    });

    test('a locale-dependent id', () {
      final XlsxReader r = _reader(
        '<row r="1"><c r="A1" s="1"><v>46319</v></c></row>',
        styles: _styles(const <int, String>{}, <int>[0, 27]),
      );
      final XlsxReadCell cell = r.rows('S').single.cells.single;
      expect(cell.value, XlsxDecimal('46319'));
      expect(cell.numberFormatId, 27);
      expect(cell.numberFormat, isNull);
      expect(cell.isDate, isFalse);
      expect(_warnings(r), <String>['unresolvedNumberFormat A1']);
      expect(r.warnings.single.detail, '27');
    });

    test('a format applies to numbers only', () {
      final XlsxReader r = _reader(
        '<row r="1"><c r="A1" s="1" t="str"><v>46319</v></c></row>',
        styles: _styles(<int, String>{164: 'dd.mm.yyyy'}, <int>[0, 164]),
      );
      final XlsxReadCell cell = r.rows('S').single.cells.single;
      expect(cell.value, '46319');
      expect(cell.numberFormatId, 164);
      expect(cell.isDate, isTrue);
      expect(r.warnings, isEmpty);
    });
  });

  group('inline strings', () {
    test('an <is> joins its <t> and runs, without phonetic text', () {
      final XlsxReader r = _reader(
        '<row r="1"><c r="A1" t="inlineStr"><is><t>a</t><r><t>b</t></r>'
        '<rPh><t>x</t></rPh></is></c></row>',
      );
      expect(r.rows('S').single.cells.single.value, 'ab');
      expect(r.warnings, isEmpty);
    });

    test('a whitespace-only <t> keeps its spaces', () {
      final XlsxReader r = _reader(
        '<row r="1"><c r="A1" t="inlineStr"><is>'
        '<t xml:space="preserve">  </t></is></c></row>',
      );
      expect(r.rows('S').single.cells.single.value, '  ');
    });

    test('an <is> past maxTextLength is limitExceeded', () {
      final XlsxReader r = _reader(
        '<row r="1"><c r="B1" t="inlineStr"><is><t>abc</t><r><t>de</t></r>'
        '</is></c></row>',
        limits: const XlsxReadLimits(maxTextLength: 4),
      );
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
                (XlsxReadException e) => e.message,
                'message',
                'Limit maxTextLength (4) exceeded by cell B1.',
              )
              .having((XlsxReadException e) => e.part, 'part', sheetEntry(0)),
        ),
      );
    });

    test('an inline string with a formula and no <v> is its value', () {
      final XlsxReader r = _reader(
        '<row r="1"><c r="A1" t="inlineStr"><f>"a"</f><is><t>a</t></is></c>'
        '</row>',
      );
      expect(
        r.rows('S').single.cells.single,
        const XlsxReadCell(0, 'a', formula: '"a"'),
      );
      expect(r.warnings, isEmpty);
    });
  });

  test('t="e" is an error value and t="d" a date', () {
    final XlsxReader r = _reader(
      '<row r="1"><c r="A1" t="e"><v>#N/A</v></c>'
      '<c r="B1" t="d"><v>2026-10-24T12:30:00</v></c></row>',
    );
    expect(r.rows('S').single.cells.map((XlsxReadCell c) => c.value), <Object>[
      XlsxErrorValue.na,
      DateTime.utc(2026, 10, 24, 12, 30),
    ]);
    expect(r.warnings, isEmpty);
  });

  group('conflicting children of one <c>', () {
    /// The value and formula of the single cell of [cell], and the warnings.
    (Object?, String?, List<String>) read(String cell) {
      final XlsxReader r = _reader('<row r="1">$cell</row>');
      final XlsxReadCell c = r.rows('S').single.cells.single;
      return (c.value, c.formula, _warnings(r));
    }

    test('a repeated <v> keeps the last and warns cellDuplicated', () {
      final (Object?, String?, List<String>) got = read(
        '<c r="A1" t="str"><v>first</v><v>second</v></c>',
      );
      expect(got.$1, 'second');
      expect(got.$3, <String>['cellDuplicated A1']);
    });

    test('a repeated <f> keeps the last and warns cellDuplicated', () {
      final (Object?, String?, List<String>) got = read(
        '<c r="A1"><f>A2</f><f>A3</f><v>1</v></c>',
      );
      expect(got.$2, 'A3');
      expect(got.$3, <String>['cellDuplicated A1']);
    });

    test('a repeated <is> keeps the last and warns cellDuplicated', () {
      final (Object?, String?, List<String>) got = read(
        '<c r="A1" t="inlineStr"><is><t>a</t></is><is><t>b</t></is></c>',
      );
      expect(got.$1, 'b');
      expect(got.$3, <String>['cellDuplicated A1']);
    });

    test('an <is> under t="str" warns cellTypeUnsupported', () {
      final (Object?, String?, List<String>) got = read(
        '<c r="A1" t="str"><is><t>lost</t></is></c>',
      );
      expect(got.$1, '');
      expect(got.$3, <String>['cellTypeUnsupported A1']);
    });

    test('an <is> next to a <v> warns cellTypeUnsupported', () {
      final (Object?, String?, List<String>) got = read(
        '<c r="A1"><v>1</v><is><t>lost</t></is></c>',
      );
      expect(got.$1, XlsxDecimal('1'));
      expect(got.$3, <String>['cellTypeUnsupported A1']);
    });

    test('both conditions give one cellTypeUnsupported', () {
      final (Object?, String?, List<String>) got = read(
        '<c r="A1" t="b"><v>1</v><v>x</v><is><t>lost</t></is></c>',
      );
      expect(got.$3, <String>['cellTypeUnsupported A1']);
    });

    test('a duplicate hides the decoder warning', () {
      final (Object?, String?, List<String>) got = read(
        '<c r="A1" t="b"><v>x</v><v>y</v></c>',
      );
      expect(got.$1, isNull);
      expect(got.$3, <String>['cellDuplicated A1']);
    });
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

  test('a worksheet in the Strict namespace is unsupportedFormat', () {
    final XlsxReader r = XlsxReader(
      buildWorkbook(<String, String?>{
        'S':
            '<worksheet xmlns="http://purl.oclc.org/ooxml/spreadsheetml/main">'
            '<sheetData><row r="1"><c><v>1</v></c></row></sheetData>'
            '</worksheet>',
      }),
    );
    expect(
      () => r.rows('S').toList(),
      throwsA(
        isA<XlsxReadException>()
            .having(
              (XlsxReadException e) => e.reason,
              'reason',
              XlsxReadFailure.unsupportedFormat,
            )
            .having((XlsxReadException e) => e.part, 'part', sheetEntry(0)),
      ),
    );
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
