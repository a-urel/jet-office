import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/model/xlsx_sheet.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';
import '../read/support/workbook_builder.dart';
import 'support/workbook_support.dart';

void main() {
  test('dates in a 1904 workbook', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{'S': worksheet('')}, date1904: true),
    );
    expect(book.date1904, isTrue);
    book.sheets.single
      ..setCell(0, 0, DateTime.utc(2026, 11, 2, 12))
      ..setCell(0, 1, const XlsxDate(1904, 1, 2));
    final Uint8List output = book.save().bytes;
    final XlsxReader reader = XlsxReader(output);
    expect(reader.date1904, isTrue);
    final List<XlsxReadCell> cells = reader.rowsAt(0).single.cells;
    expect(cells[0].value, DateTime.utc(2026, 11, 2, 12));
    expect(cells[1].value, DateTime.utc(1904, 1, 2));
    final String sheet = partText(output, 'xl/worksheets/sheet1.xml');
    // 1900 serial 46328.5 less the 1,462 days between the systems.
    expect(sheet, contains('<v>44866.5</v>'));
    expect(sheet, contains('<v>1</v>'));
  });

  test('clearing keeps the style', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(
        <String, String>{
          'S': worksheet(
            '<row r="1"><c r="A1" s="1"><v>5</v></c><c r="B1"><v>6</v></c>'
            '<c r="C1" s="1"><v>7</v></c></row>',
          ),
        },
        styles: stylesPart(
          '<xf numFmtId="0"/><xf numFmtId="2" applyNumberFormat="1"/>',
        ),
      ),
    );
    book.sheets.single
      ..setCell(0, 0, null)
      ..setCell(0, 1, null)
      ..setCell(0, 2, 8)
      ..setCell(0, 3, null);
    final String sheet = partText(
      book.save().bytes,
      'xl/worksheets/sheet1.xml',
    );
    expect(sheet, contains('<c r="A1" s="1"/>'));
    expect(sheet, isNot(contains('r="B1"')));
    expect(sheet, contains('<c r="C1" s="1"><v>8</v></c>'));
    expect(sheet, isNot(contains('r="D1"')));
    expect(book.sheets.single.cellAt(0, 0), isNull);
    expect(book.sheets.single.cellAt(0, 2)?.numberFormatId, 2);
  });

  test('setCell replaces the value-tied attributes and keeps a valid '
      'style', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet(
          '<row r="1"><c r="A1" s="1" cm="1" vm="2" ph="1"><v>5</v></c>'
          '<c r="B1" s="x"><v>6</v></c></row>',
        ),
      }, styles: stylesPart('<xf numFmtId="0"/><xf numFmtId="2"/>')),
    );
    book.sheets.single
      ..setCell(0, 0, 1)
      ..setCell(0, 1, 2);
    final String sheet = partText(
      book.save().bytes,
      'xl/worksheets/sheet1.xml',
    );
    expect(sheet, contains('<c r="A1" s="1"><v>1</v></c>'));
    expect(sheet, contains('<c r="B1"><v>2</v></c>'));
  });

  test('a date on a General cell gets the writer date formats', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet(''),
      }, styles: stylesPart('<xf numFmtId="0"/>')),
    );
    book.sheets.single
      ..setCell(0, 0, DateTime.utc(2026, 11, 2))
      ..setCell(0, 1, const XlsxDate(2026, 11, 2))
      ..setCell(0, 2, DateTime.utc(2026, 11, 3));
    final Uint8List output = book.save().bytes;
    final String styles = partText(output, 'xl/styles.xml');
    expect(styles, contains('numFmtId="22"'));
    expect(styles, contains('numFmtId="14"'));
    final List<XlsxReadCell> cells = XlsxReader(output).rowsAt(0).single.cells;
    expect(cells.map((XlsxReadCell c) => c.numberFormatId), <int>[22, 14, 22]);
  });

  test('a date on a cell with a broken style counts it as General', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet(
          '<row r="1"><c r="A1" s="9"><v>1</v></c>'
          '<c r="B1" s="x"><v>1</v></c><c r="C1" s="1"><v>1</v></c></row>',
        ),
      }, styles: stylesPart('<xf numFmtId="0"/><xf numFmtId="4"/>')),
    );
    book.sheets.single
      ..setCell(0, 0, DateTime.utc(2026, 11, 2))
      ..setCell(0, 1, const XlsxDate(2026, 11, 2))
      ..setCell(0, 2, DateTime.utc(2026, 11, 2));
    final XlsxResult result = book.save();
    final List<XlsxReadCell> cells = XlsxReader(
      result.bytes,
    ).rowsAt(0).single.cells;
    expect(cells.map((XlsxReadCell c) => c.numberFormatId), <int>[22, 14, 4]);
    expect(result.warnings.single.code, XlsxWarningCode.dateInNonDateFormat);
  });

  test('a date where no date style can be added warns', () {
    // A styles part that is not a SpreadsheetML styleSheet loads untyped:
    // the model cannot append a date style to it, so the date keeps the
    // cell's style and says so.
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet('<row r="1"><c r="A1"><v>1</v></c></row>'),
      }, styles: '<other xmlns="$mainNs"/>'),
    );
    book.sheets.single
      ..setCell(0, 0, DateTime.utc(2026, 11, 2))
      ..setCell(0, 1, const XlsxDate(2026, 11, 2));
    final XlsxResult result = book.save();
    expect(
      result.warnings.map((XlsxWarning w) => (w.code, w.count)).toList(),
      <(XlsxWarningCode, int)>[(XlsxWarningCode.dateInNonDateFormat, 2)],
    );
    final List<XlsxReadCell> cells = XlsxReader(
      result.bytes,
    ).rowsAt(0).single.cells;
    expect(cells.map((XlsxReadCell c) => c.numberFormatId), <int>[0, 0]);
  });

  test('editing formula groups follows the rules', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet(
          '<row r="1"><c r="A1"><f t="shared" ref="A1:A3" si="0">B1</f>'
          '<v>1</v></c><c r="C1"><f t="array" ref="C1:C2">B1:B2</f>'
          '<v>1</v></c></row>'
          '<row r="2"><c r="A2"><f t="shared" si="0"/><v>2</v></c>'
          '<c r="C2"><v>2</v></c></row>'
          '<row r="3"><c r="A3"><f t="shared" si="0"/><v>3</v></c></row>',
        ),
      }),
    );
    final XlsxSheet sheet = book.sheets.single;
    // An array member, the master included.
    expect(
      () => sheet.setCell(1, 2, 9),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          'Cannot change part of an array or data table formula at C2.',
        ),
      ),
    );
    expect(() => sheet.setCell(0, 2, 9), throwsStateError);
    // A shared master.
    expect(
      () => sheet.setCell(0, 0, 9),
      throwsA(
        isA<UnsupportedError>().having(
          (UnsupportedError e) => e.message,
          'message',
          'Changing a shared formula master arrives in W5.',
        ),
      ),
    );
    // A shared child leaves the group; the others are unchanged.
    sheet.setCell(1, 0, 9);
    expect(sheet.cellAt(1, 0)?.formula, isNull);
    expect(sheet.cellAt(1, 0)?.value, XlsxDecimal('9'));
    expect(sheet.cellAt(1, 0)?.formulaGroup, isNull);
    expect(sheet.cellAt(2, 0)?.formulaGroup?.isMaster, isFalse);
    // A cell in no group.
    sheet.setCell(0, 3, 9);
    expect(sheet.cellAt(0, 3)?.value, XlsxDecimal('9'));
  });

  test('setting 10,000 cells on a sheet with a formula takes linear '
      'time', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet(
          '<row r="1"><c r="A1"><f>1+1</f><v>2</v></c></row>'
          '${List<String>.generate(2000, (int i) => '<row r="${i + 2}">${List<String>.generate(10, (int c) => '<c r="${String.fromCharCode(66 + c)}${i + 2}"><v>$c</v></c>').join()}</row>').join()}',
        ),
      }),
    );
    final XlsxSheet sheet = book.sheets.single;
    sheet.rows.toList();
    final Stopwatch watch = Stopwatch()..start();
    for (int i = 0; i < 10000; i++) {
      sheet.setCell(i ~/ 10 + 1, i % 10 + 1, i);
    }
    // A scan of every cell per set would visit 2 * 10^8 cells.
    expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
  });

  test('unsupported value types throw UnsupportedError naming the '
      'milestone', () {
    final XlsxSheet sheet = XlsxWorkbook().addSheet('S');
    expect(
      () => sheet.setCell(0, 0, const XlsxHyperlink(address: 'x', text: 'x')),
      throwsA(
        isA<UnsupportedError>().having(
          (UnsupportedError e) => e.message,
          'message',
          'XlsxHyperlink cells arrive in W3.',
        ),
      ),
    );
    expect(
      () => sheet.setCell(
        0,
        0,
        XlsxRichText(const <XlsxTextRun>[XlsxTextRun('x')]),
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (UnsupportedError e) => e.message,
          'message',
          'XlsxRichText cells arrive in W4.',
        ),
      ),
    );
    expect(
      () => sheet.setCell(0, 0, const XlsxCell(1)),
      throwsA(
        isA<UnsupportedError>().having(
          (UnsupportedError e) => e.message,
          'message',
          'XlsxCell (styled) cells arrive in W2.',
        ),
      ),
    );
    expect(() => sheet.setCell(0, 0, Object()), throwsArgumentError);
    expect(() => sheet.setCell(-1, 0, 1), throwsRangeError);
    expect(() => sheet.setCell(0, XlsxLimits.maxColumns, 1), throwsRangeError);
    expect(() => sheet.setCell(XlsxLimits.maxRows, 0, 1), throwsRangeError);
    expect(() => sheet.cellAt(XlsxLimits.maxRows, 0), throwsRangeError);
  });

  test('setCell on a sheet that is not a worksheet throws at the call', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{'Chart': '<chartsheet xmlns="$mainNs"/>'}),
    );
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.rows, isEmpty);
    expect(sheet.cellAt(0, 0), isNull);
    expect(
      () => sheet.setCell(0, 0, 1),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('"Chart"'),
        ),
      ),
    );
    expect(book.save().bytes, isNotEmpty);
  });

  test('an inline string deeper than 256 reads under a raised maxDepth', () {
    final String deep = '${'<x>' * 300}${'</x>' * 300}';
    final Uint8List input = buildWorkbook(<String, String>{
      'S': worksheet(
        '<row r="1"><c r="A1" t="inlineStr"><is><t>deep</t>$deep</is></c>'
        '</row>',
      ),
    });
    const XlsxReadLimits limits = XlsxReadLimits(maxDepth: 512);
    final XlsxWorkbook book = XlsxWorkbook.open(input, limits: limits);
    expect(book.sheets.single.cellAt(0, 0)?.value, 'deep');
    expect(
      XlsxReader(input, limits: limits).rowsAt(0).first.cells[0].value,
      'deep',
    );
  });

  test('a shared string with attributes saves as written', () {
    const String items =
        '<si xmlns:x="urn:x" x:meta="payload"><t>a</t></si>'
        '<si><t xmlns:x="urn:x" x:id="7">b</t></si>'
        '<si><t xml:space="preserve"> c </t></si>';
    final Uint8List input = buildWorkbook(<String, String>{
      'S': worksheet(
        '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c>'
        '<c r="C1" t="s"><v>2</v></c></row>',
      ),
    }, sharedStrings: '<sst xmlns="$mainNs">$items</sst>');
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    final XlsxSheet sheet = book.sheets.single;
    expect(sheet.cellAt(0, 0)?.value, 'a');
    sheet.setCell(1, 0, 'x');
    final String sst = partText(book.save().bytes, 'xl/sharedStrings.xml');
    expect(sst, contains('<si xmlns:x="urn:x" x:meta="payload"><t>a</t></si>'));
    expect(sst, contains('<si><t xmlns:x="urn:x" x:id="7">b</t></si>'));
    expect(sst, contains('<si><t xml:space="preserve"> c </t></si>'));
  });

  test('text escaping a character XML forbids saves as written', () {
    final Uint8List input = buildWorkbook(<String, String>{
      'S': worksheet(
        '<row r="1"><c r="A1" t="s"><v>0</v></c>'
        '<c r="B1" t="inlineStr"><is><t>c_x0001_d</t></is></c>'
        '<c r="C1" t="str"><v>e_x0002_</v></c></row>',
      ),
    }, sharedStrings: '<sst xmlns="$mainNs"><si><t>a_x0000_b</t></si></sst>');
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    final XlsxSheet sheet = book.sheets.single;
    sheet.rows.toList();
    sheet.setCell(1, 0, 'x');
    final Uint8List output = book.save().bytes;
    expect(
      partText(output, 'xl/sharedStrings.xml'),
      contains('<si><t>a_x0000_b</t></si>'),
    );
    List<Object?> firstRow(Uint8List bytes) => <Object?>[
      for (final XlsxReadCell c in XlsxReader(bytes).rowsAt(0).first.cells)
        c.value,
    ];
    expect(firstRow(output), firstRow(input));
  });

  test('a failed setCell changes nothing', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(
        <String, String>{
          'S': worksheet('<row r="1"><c r="A1" t="s"><v>0</v></c></row>'),
        },
        sharedStrings: '<sst xmlns="$mainNs"><si><t>a</t></si></sst>',
        styles: stylesPart('<xf numFmtId="0"/>'),
      ),
    );
    final XlsxSheet sheet = book.sheets.single;
    sheet.rows.toList();
    final List<Object?> cells = cellsOf(cellStoreOf(sheet)!);
    final int strings = sharedStringsOf(book)!.length;
    final String styles = utf8.decode(<int>[
      for (final Uint8List c in stylesPartOf(book)!.encode()) ...c,
    ]);
    List<(XlsxWarningCode, int)> seen() => <(XlsxWarningCode, int)>[
      for (final XlsxWarning w in book.warnings) (w.code, w.count),
    ];
    final List<(XlsxWarningCode, int)> warnings = seen();
    for (final Object? bad in <Object?>[double.nan, double.infinity]) {
      expect(() => sheet.setCell(0, 0, bad), throwsArgumentError);
    }
    expect(cellsOf(cellStoreOf(sheet)!), cells);
    expect(sharedStringsOf(book)!.length, strings);
    expect(
      utf8.decode(<int>[
        for (final Uint8List c in stylesPartOf(book)!.encode()) ...c,
      ]),
      styles,
    );
    expect(seen(), warnings);
    expect(changeLogOf(book).hasChanges, isFalse);
  });
}
