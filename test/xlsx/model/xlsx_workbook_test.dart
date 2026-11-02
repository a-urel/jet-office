import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/package.dart';
import 'package:jet_office/src/xlsx/model/cell_store.dart';
import 'package:jet_office/src/xlsx/model/xlsx_sheet.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:jet_office/src/xlsx/raw_cell.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../support/read_xlsx.dart';
import '../read/support/workbook_builder.dart';
import '../read/support/zip_builder.dart';

const String _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _pkgRel =
    'http://schemas.openxmlformats.org/package/2006/relationships';
const String _ctNs =
    'http://schemas.openxmlformats.org/package/2006/content-types';
const String _wbType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml';
const String _wsType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml';

/// A styles part with the `<xf>`s [xfs] (raw XML) and the `<numFmt>`s
/// [numFmts].
String _styles(String xfs, {String numFmts = ''}) =>
    '<styleSheet xmlns="$mainNs">'
    '${numFmts.isEmpty ? '' : '<numFmts>$numFmts</numFmts>'}'
    '<cellXfs>$xfs</cellXfs></styleSheet>';

/// The text of the part [name] of [bytes].
String _part(Uint8List bytes, String name) => readXlsx(bytes)[name]!;

/// A one-sheet package with [rows] (raw XML) in its sheet, a calcChain
/// part when [calcChain] is true, and [extra] entries.
Uint8List _packageWith({
  required String rows,
  bool calcChain = false,
  String contentType = _wbType,
  Map<String, String> extra = const <String, String>{},
  String extraRels = '',
  String extraTypes = '',
}) {
  return buildZip(<String, List<int>>{
    '[Content_Types].xml': utf8.encode(
      '<Types xmlns="$_ctNs">'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="rels" ContentType="application/'
      'vnd.openxmlformats-package.relationships+xml"/>'
      '$extraTypes'
      '<Override PartName="/xl/workbook.xml" ContentType="$contentType"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" '
      'ContentType="$_wsType"/>'
      '${calcChain ? '<Override PartName="/xl/calcChain.xml" ContentType="'
                'application/vnd.openxmlformats-officedocument.spreadsheetml.'
                'calcChain+xml"/>' : ''}'
      '</Types>',
    ),
    '_rels/.rels': utf8.encode(
      '<Relationships xmlns="$_pkgRel"><Relationship Id="rId1" '
      'Type="$_rel/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>',
    ),
    'xl/workbook.xml': utf8.encode(
      '<workbook xmlns="$mainNs" xmlns:r="$_rel"><sheets>'
      '<sheet name="S" sheetId="1" r:id="rId1"/></sheets>'
      '<calcPr calcId="191029"/></workbook>',
    ),
    'xl/_rels/workbook.xml.rels': utf8.encode(
      '<Relationships xmlns="$_pkgRel"><Relationship Id="rId1" '
      'Type="$_rel/worksheet" Target="worksheets/sheet1.xml"/>'
      '${calcChain ? '<Relationship Id="rId2" Type="$_rel/calcChain" '
                'Target="calcChain.xml"/>' : ''}'
      '$extraRels</Relationships>',
    ),
    'xl/worksheets/sheet1.xml': utf8.encode(worksheet(rows)),
    if (calcChain)
      'xl/calcChain.xml': utf8.encode(
        '<calcChain xmlns="$mainNs"><c r="A1" i="1"/></calcChain>',
      ),
    for (final MapEntry<String, String> e in extra.entries)
      e.key: utf8.encode(e.value),
  });
}

/// Every cell of [store], as `(row, column, kind, style, value, formula)`.
List<Object?> _cells(CellStore store) => <Object?>[
  for (final int r in store.rowIndexes)
    ...() {
      final List<Object?> out = <Object?>[];
      store.forEachInRow(r, (int c, RawCell cell) {
        out.add((r, c, cell.kind, cell.style, cell.value, cell.formula?.text));
      });
      return out;
    }(),
];

void main() {
  test('a new workbook saves a sheet with values', () {
    final XlsxWorkbook book = XlsxWorkbook();
    final XlsxSheet sheet = book.addSheet('Liste');
    sheet
      ..setCell(0, 0, 'Ürün')
      ..setCell(0, 1, 12)
      ..setCell(0, 2, XlsxDecimal('12.50'))
      ..setCell(0, 3, true)
      ..setCell(0, 4, DateTime.utc(2026, 11, 2, 9, 30))
      ..setCell(0, 5, const XlsxFormula('A1&"!"'));
    final XlsxResult result = book.save();
    expect(result.warnings, isEmpty);
    final XlsxReader reader = XlsxReader(result.bytes);
    expect(reader.sheets.single.name, 'Liste');
    final List<XlsxReadCell> cells = reader.rowsAt(0).single.cells;
    expect(cells[0].value, 'Ürün');
    expect(cells[1].value, XlsxDecimal('12'));
    expect(cells[2].value, XlsxDecimal('12.50'));
    expect(cells[3].value, true);
    expect(cells[4].value, DateTime.utc(2026, 11, 2, 9, 30));
    expect(cells[4].isDate, isTrue);
    expect(cells[5].formula, 'A1&"!"');
    // The writer computes no result either.
    expect(reader.warnings.single.code, XlsxWarningCode.formulaWithoutValue);
    // The model's own view agrees with the reader.
    expect(sheet.rows.toList(), reader.rowsAt(0).toList());
    expect(sheet.cellAt(0, 4), cells[4]);
    expect(sheet.cellAt(5, 5), isNull);
  });

  test('a new workbook starts empty', () {
    final XlsxWorkbook book = XlsxWorkbook();
    expect(book.sheets, isEmpty);
    expect(book.date1904, isFalse);
    expect(book.warnings, isEmpty);
  });

  test('save without a sheet throws StateError', () {
    final XlsxWorkbook book = XlsxWorkbook();
    expect(
      book.save,
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          'A workbook needs at least one sheet; add one first.',
        ),
      ),
    );
    expect(
      () => book.saveTo(ByteConversionSink.withCallback((_) {})),
      throwsStateError,
    );
  });

  test('save with only hidden sheets throws StateError', () {
    final Uint8List bytes = buildZip(<String, List<int>>{
      ...readXlsxBytes(buildWorkbook(<String, String>{'S': worksheet('')})),
      'xl/workbook.xml': utf8.encode(
        '<workbook xmlns="$mainNs" xmlns:r="$_rel"><sheets>'
        '<sheet name="S" sheetId="1" state="hidden" r:id="rId1"/>'
        '</sheets></workbook>',
      ),
    });
    final XlsxWorkbook book = XlsxWorkbook.open(bytes);
    expect(book.sheets.single.visibility, XlsxSheetVisibility.hidden);
    expect(
      book.save,
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('every sheet is hidden'),
        ),
      ),
    );
  });

  test('saveTo writes the bytes save returns', () {
    final XlsxWorkbook book = XlsxWorkbook()..addSheet('A').setCell(0, 0, 1);
    final BytesBuilder sink = BytesBuilder();
    book.saveTo(ByteConversionSink.withCallback(sink.add));
    expect(sink.takeBytes(), book.save().bytes);
  });

  test('open then save with no change is semantically equal and loads '
      'nothing', () {
    final XlsxWriter writer = XlsxWriter();
    writer.addSheet('One').row(<Object?>['a', 1, DateTime.utc(2026)]);
    writer.addSheet('Two').row(<Object?>['b']);
    final Uint8List input = writer.close().bytes;
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    final Uint8List output = book.save().bytes;
    expect(comparePackages(input, output), isEmpty);
    final OpcPackage package = packageOf(book);
    expect(
      <String>[
        for (final String name in package.partNames)
          if (package.isLoaded(name)) name,
      ],
      <String>['/xl/workbook.xml'],
    );
  });

  test('sheets are listed in tab order and found ignoring case', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'Özet': worksheet(''),
        'Liste': worksheet(''),
      }),
    );
    expect(book.sheets.map((XlsxSheet s) => s.name), <String>['Özet', 'Liste']);
    expect(() => book.sheets.add(book.sheets.first), throwsUnsupportedError);
    expect(book.sheet('LISTE'), same(book.sheets[1]));
    expect(book.sheet('özet'), same(book.sheets[0]));
    expect(() => book.sheet('Nope'), throwsArgumentError);
  });

  test('open throws XlsxReadException for a file it cannot open', () {
    expect(
      () => XlsxWorkbook.open(Uint8List.fromList(<int>[1, 2, 3])),
      throwsA(isA<XlsxReadException>()),
    );
    expect(
      () => XlsxWorkbook.open(
        buildWorkbook(<String, String>{'S': worksheet('')}),
        limits: const XlsxReadLimits(maxSheets: 0),
      ),
      throwsArgumentError,
    );
  });

  test('an unloaded sheet keeps its strings', () {
    final XlsxWriter writer = XlsxWriter();
    writer.addSheet('One').row(<Object?>['alpha', 'beta']);
    writer.addSheet('Two').row(<Object?>['gamma', 'beta', 'delta']);
    final Uint8List input = writer.close().bytes;
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    book.sheets[0].setCell(1, 0, 'a new string');
    final Uint8List output = book.save().bytes;
    expect(isLoadedSheet(book.sheets[1]), isFalse);
    expect(
      XlsxReader(output).rowsAt(1).toList(),
      XlsxReader(input).rowsAt(1).toList(),
    );
    expect(
      XlsxReader(output).rowsAt(0).last.cells.single.value,
      'a new string',
    );
  });

  group('shared strings count', () {
    test('is left out while a sheet is unloaded', () {
      final XlsxWriter writer = XlsxWriter();
      writer.addSheet('One').row(<Object?>['alpha']);
      writer.addSheet('Two').row(<Object?>['alpha']);
      final XlsxWorkbook book = XlsxWorkbook.open(writer.close().bytes);
      book.sheets[0].setCell(0, 1, 'beta');
      final String sst = _part(book.save().bytes, 'xl/sharedStrings.xml');
      expect(sst, isNot(contains(' count=')));
      expect(sst, contains('uniqueCount="2"'));
    });

    test('is recounted when every sheet is loaded', () {
      final XlsxWriter writer = XlsxWriter();
      writer.addSheet('One').row(<Object?>['alpha', 'alpha']);
      writer.addSheet('Two').row(<Object?>['alpha']);
      final XlsxWorkbook book = XlsxWorkbook.open(writer.close().bytes);
      book.sheets[0].setCell(0, 1, 'beta');
      book.sheets[1].rows.toList();
      final String sst = _part(book.save().bytes, 'xl/sharedStrings.xml');
      expect(sst, contains('count="3"'));
      expect(sst, contains('uniqueCount="2"'));
    });
  });

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
    final String sheet = _part(output, 'xl/worksheets/sheet1.xml');
    // 1900 serial 46328.5 less the 1,462 days between the systems.
    expect(sheet, contains('<v>44866.5</v>'));
    expect(sheet, contains('<v>1</v>'));
  });

  test('addSheet in a file with unusual names', () {
    final Uint8List input = buildZip(<String, List<int>>{
      '[Content_Types].xml': utf8.encode(
        '<Types xmlns="$_ctNs"><Override PartName="/book/main.xml" '
        'ContentType="$_wbType"/><Override PartName="/book/ws/data.xml" '
        'ContentType="$_wsType"/></Types>',
      ),
      '_rels/.rels': utf8.encode(
        '<Relationships xmlns="$_pkgRel"><Relationship Id="rId1" '
        'Type="$_rel/officeDocument" Target="book/main.xml"/>'
        '</Relationships>',
      ),
      'book/main.xml': utf8.encode(
        '<workbook xmlns="$mainNs" xmlns:r="$_rel"><sheets>'
        '<sheet name="Sheet2" sheetId="7" r:id="rId7"/>'
        '<sheet name="history " sheetId="x" r:id="rId9"/></sheets>'
        '</workbook>',
      ),
      'book/_rels/main.xml.rels': utf8.encode(
        '<Relationships xmlns="$_pkgRel"><Relationship Id="rId7" '
        'Type="$_rel/worksheet" Target="ws/data.xml"/><Relationship '
        'Id="rId9" Type="$_rel/worksheet" Target="/book/worksheets/'
        'sheet3.xml"/></Relationships>',
      ),
      'book/ws/data.xml': utf8.encode(
        worksheet('<row r="1"><c r="A1"><v>1</v></c></row>'),
      ),
      'book/worksheets/sheet3.xml': utf8.encode(worksheet('')),
    });
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    final XlsxSheet added = book.addSheet('sheet2');
    expect(added.name, 'sheet2 (2)');
    expect(book.addSheet('').name, 'Sheet4');
    expect(book.addSheet('History').name, 'History (2)');
    expect(book.warnings.map((XlsxWarning w) => w.code), <XlsxWarningCode>[
      XlsxWarningCode.sheetNameDuplicated,
      XlsxWarningCode.sheetNameChanged,
      XlsxWarningCode.sheetNameDuplicated,
    ]);
    added.setCell(0, 0, 'new');
    final Uint8List output = book.save().bytes;
    final Map<String, String> parts = readXlsx(output);
    expect(parts['book/ws/data.xml'], isNotNull);
    expect(parts['book/worksheets/sheet3.xml'], isNotNull);
    expect(parts['book/worksheets/sheet4.xml'], contains('t="s"'));
    expect(parts['book/sharedStrings.xml'], contains('<t>new</t>'));
    expect(parts['book/main.xml'], contains('sheetId="7" r:id="rId7"'));
    expect(parts['book/main.xml'], contains('sheetId="x" r:id="rId9"'));
    expect(
      parts['book/main.xml'],
      contains('<sheet name="sheet2 (2)" sheetId="8" r:id="rId1"/>'),
    );
    expect(parts['book/_rels/main.xml.rels'], contains('Id="rId7"'));
    expect(
      parts['book/_rels/main.xml.rels'],
      contains('Target="worksheets/sheet4.xml"'),
    );
    expect(
      parts['[Content_Types].xml'],
      contains('/book/worksheets/sheet4.xml'),
    );
    final XlsxReader reader = XlsxReader(output);
    expect(reader.sheets.map((XlsxReadSheet s) => s.name), <String>[
      'Sheet2',
      'history ',
      'sheet2 (2)',
      'Sheet4',
      'History (2)',
    ]);
    expect(reader.rowsAt(0).single.cells.single.value, XlsxDecimal('1'));
    expect(reader.rowsAt(2).single.cells.single.value, 'new');
    expect(reader.warnings, isEmpty);
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
        styles: _styles(
          '<xf numFmtId="0"/><xf numFmtId="2" applyNumberFormat="1"/>',
        ),
      ),
    );
    book.sheets.single
      ..setCell(0, 0, null)
      ..setCell(0, 1, null)
      ..setCell(0, 2, 8)
      ..setCell(0, 3, null);
    final String sheet = _part(book.save().bytes, 'xl/worksheets/sheet1.xml');
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
      }, styles: _styles('<xf numFmtId="0"/><xf numFmtId="2"/>')),
    );
    book.sheets.single
      ..setCell(0, 0, 1)
      ..setCell(0, 1, 2);
    final String sheet = _part(book.save().bytes, 'xl/worksheets/sheet1.xml');
    expect(sheet, contains('<c r="A1" s="1"><v>1</v></c>'));
    expect(sheet, contains('<c r="B1"><v>2</v></c>'));
  });

  test('a date on a General cell gets the writer date formats', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet(''),
      }, styles: _styles('<xf numFmtId="0"/>')),
    );
    book.sheets.single
      ..setCell(0, 0, DateTime.utc(2026, 11, 2))
      ..setCell(0, 1, const XlsxDate(2026, 11, 2))
      ..setCell(0, 2, DateTime.utc(2026, 11, 3));
    final Uint8List output = book.save().bytes;
    final String styles = _part(output, 'xl/styles.xml');
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
      }, styles: _styles('<xf numFmtId="0"/><xf numFmtId="4"/>')),
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

  test('a change drops calcChain and sets fullCalcOnLoad', () {
    final Uint8List input = _packageWith(
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
      _packageWith(rows: '<row r="1"><c r="A1"><v>2</v></c></row>'),
    );
    book.sheets.single.setCell(1, 0, 5);
    expect(
      _part(book.save().bytes, 'xl/workbook.xml'),
      isNot(contains('full')),
    );
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

  test('a sheet without a part reads as empty and warns', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String?>{'A': worksheet(''), 'Gone': null}),
    );
    expect(book.warnings.single.code, XlsxWarningCode.sheetPartMissing);
    expect(book.sheets[1].rows, isEmpty);
    expect(() => book.sheets[1].setCell(0, 0, 1), throwsStateError);
  });

  test('a broken sheet throws on first access, not on open', () {
    final String broken =
        '<worksheet xmlns="$mainNs"><sheetData>'
        '${'<x>' * 300}${'</x>' * 300}</sheetData></worksheet>';
    final Uint8List input = buildWorkbook(<String, String>{
      'Good': worksheet('<row r="1"><c r="A1"><v>1</v></c></row>'),
      'Bad': broken,
    });
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    expect(
      () => book.sheets[1].cellAt(0, 0),
      throwsA(isA<XlsxReadException>()),
    );
    expect(() => book.sheets[1].rows, throwsA(isA<XlsxReadException>()));
    // A programmer error is one whatever the sheet holds.
    expect(() => book.sheets[1].setCell(0, 0, Object()), throwsArgumentError);
    expect(
      () => book.sheets[1].setCell(0, 0, const XlsxCell(1)),
      throwsUnsupportedError,
    );
    book.sheets[0].setCell(1, 0, 2);
    final Uint8List output = book.save().bytes;
    expect(
      readXlsxBytes(output)['xl/worksheets/sheet2.xml'],
      utf8.encode(broken),
    );
  });

  test('a failed setCell changes nothing', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(
        <String, String>{
          'S': worksheet('<row r="1"><c r="A1" t="s"><v>0</v></c></row>'),
        },
        sharedStrings: '<sst xmlns="$mainNs"><si><t>a</t></si></sst>',
        styles: _styles('<xf numFmtId="0"/>'),
      ),
    );
    final XlsxSheet sheet = book.sheets.single;
    sheet.rows.toList();
    final List<Object?> cells = _cells(cellStoreOf(sheet)!);
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
    expect(_cells(cellStoreOf(sheet)!), cells);
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

  test('an xlsm keeps vbaProject.bin and its content type', () {
    const String macroType =
        'application/vnd.ms-excel.sheet.macroEnabled.main+xml';
    final List<int> vba = List<int>.generate(64, (int i) => i * 7 % 256);
    final Uint8List input = _packageWith(
      rows: '<row r="1"><c r="A1"><v>1</v></c></row>',
      contentType: macroType,
      extraTypes:
          '<Default Extension="bin" '
          'ContentType="application/vnd.ms-office.vbaProject"/>',
      extraRels:
          '<Relationship Id="rId3" Type="http://schemas.microsoft.com/'
          'office/2006/relationships/vbaProject" Target="vbaProject.bin"/>',
    );
    final Uint8List withVba = buildZip(<String, List<int>>{
      ...readXlsxBytes(input),
      'xl/vbaProject.bin': vba,
    });
    final XlsxWorkbook book = XlsxWorkbook.open(withVba);
    book.sheets.single.setCell(0, 0, 2);
    final Uint8List output = book.save().bytes;
    final Map<String, Uint8List> parts = readXlsxBytes(output);
    expect(parts['xl/vbaProject.bin'], vba);
    final String types = utf8.decode(parts['[Content_Types].xml']!);
    expect(types, contains(macroType));
    expect(types, contains('application/vnd.ms-office.vbaProject'));
    expect(
      utf8.decode(parts['xl/_rels/workbook.xml.rels']!),
      contains('vbaProject.bin'),
    );
    expect(
      comparePackages(
        withVba,
        output,
        ignoreParts: const <String>{'xl/worksheets/sheet1.xml'},
      ),
      isEmpty,
    );
  });

  test('cellAt and rows show what the reader shows', () {
    final Uint8List input = buildWorkbook(
      <String, String>{
        'S': worksheet(
          '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" s="1">'
          '<v>46328</v></c><c r="C1" t="b"><v>1</v></c></row>'
          '<row r="3" hidden="1"/>'
          '<row r="4"><c r="A4" t="e"><v>#N/A</v></c><c r="B4" s="1"/>'
          '</row>',
        ),
      },
      sharedStrings: '<sst xmlns="$mainNs"><si><t>a</t></si></sst>',
      styles: _styles('<xf numFmtId="0"/><xf numFmtId="14"/>'),
    );
    final XlsxSheet sheet = XlsxWorkbook.open(input).sheets.single;
    final List<XlsxReadRow> expected = XlsxReader(input).rowsAt(0).toList();
    expect(sheet.rows.toList(), expected);
    expect(sheet.cellAt(0, 1), expected[0].cells[1]);
    expect(sheet.cellAt(3, 1), isNull);
  });

  test('reading the rows again reports nothing twice', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet(
          '<row r="1"><c r="A1"><f>1+1</f></c><c r="B1" t="s"><v>7</v></c>'
          '</row>',
        ),
      }),
    );
    final XlsxSheet sheet = book.sheets.single;
    List<(XlsxWarningCode, int)> seen() => <(XlsxWarningCode, int)>[
      for (final XlsxWarning w in book.warnings) (w.code, w.count),
    ];
    sheet.rows.toList();
    final List<(XlsxWarningCode, int)> first = seen();
    expect(first, hasLength(2));
    sheet.rows.toList();
    sheet.cellAt(0, 0);
    expect(seen(), first);
    // A new value is read afresh.
    sheet
      ..setCell(0, 0, const XlsxFormula('2+2'))
      ..rows.toList();
    expect(
      seen().firstWhere(
        ((XlsxWarningCode, int) w) =>
            w.$1 == XlsxWarningCode.formulaWithoutValue,
      ),
      (XlsxWarningCode.formulaWithoutValue, 2),
    );
  });

  test('loading the shared strings keeps the sst root and its extras', () {
    const String x14ac =
        'http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac';
    const String mc =
        'http://schemas.openxmlformats.org/markup-compatibility/2006';
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(
        <String, String>{
          'S': worksheet('<row r="1"><c r="A1" t="s"><v>0</v></c></row>'),
        },
        sharedStrings:
            '<sst xmlns="$mainNs" xmlns:mc="$mc" xmlns:x14ac="$x14ac" '
            'mc:Ignorable="x14ac" count="1" uniqueCount="1" x14ac:k="v">'
            '<si><t>a</t></si>'
            '<extLst><ext uri="u"><x14ac:z/></ext></extLst></sst>',
      ),
    );
    book.sheets.single.setCell(1, 0, 'b');
    final String sst = _part(book.save().bytes, 'xl/sharedStrings.xml');
    expect(sst, contains('xmlns:x14ac="$x14ac"'));
    expect(sst, contains('xmlns:mc="$mc"'));
    expect(sst, contains('mc:Ignorable="x14ac"'));
    expect(sst, contains('x14ac:k="v"'));
    expect(sst, contains('count="2"'));
    expect(sst, contains('uniqueCount="2"'));
    expect(
      sst,
      contains('<si><t>b</t></si><extLst><ext uri="u"><x14ac:z/></ext>'),
    );
    expect(RegExp(' count=').allMatches(sst), hasLength(1));
    expect(RegExp('uniqueCount=').allMatches(sst), hasLength(1));
  });

  test('cellAt reports a reading problem once, shared with rows', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet('<row r="1"><c r="A1" t="s"><v>7</v></c></row>'),
      }, sharedStrings: '<sst xmlns="$mainNs"><si><t>a</t></si></sst>'),
    );
    final XlsxSheet sheet = book.sheets.single;
    List<(XlsxWarningCode, int)> seen() => <(XlsxWarningCode, int)>[
      for (final XlsxWarning w in book.warnings) (w.code, w.count),
    ];
    const List<(XlsxWarningCode, int)> once = <(XlsxWarningCode, int)>[
      (XlsxWarningCode.sharedStringInvalid, 1),
    ];
    expect(sheet.cellAt(0, 0)?.value, isNull);
    expect(seen(), once);
    sheet.cellAt(0, 0);
    sheet.rows.toList();
    expect(seen(), once);
  });

  test('calcChain removal touches only the workbook relationships', () {
    const String bad = '<Relationships><Relationship';
    final Uint8List input = buildZip(<String, List<int>>{
      ...readXlsxBytes(
        _packageWith(
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
