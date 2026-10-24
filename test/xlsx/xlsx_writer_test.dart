// ignore_for_file: close_sinks (the writers close their sinks)
import 'dart:math';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../support/read_xlsx.dart';
import '../support/xlsx_checker.dart';

const String _main =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const String _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

/// Collects every chunk written to it, like a file or network sink would.
final class _CollectingSink implements Sink<List<int>> {
  final List<List<int>> chunks = <List<int>>[];
  bool closed = false;

  Uint8List get bytes =>
      Uint8List.fromList(chunks.expand((List<int> c) => c).toList());

  @override
  void add(List<int> data) {
    expect(closed, isFalse, reason: 'write after close');
    chunks.add(List<int>.of(data));
  }

  @override
  void close() => closed = true;
}

/// A workbook touching every value type, a style, a formula, a renamed sheet
/// and a dirty string, so it produces warnings.
void _mixedScript(XlsxWriterBase book) {
  final XlsxSheetWriter data = book.addSheet('Data');
  data.row(<Object?>['Kod', 'Ad', 'Tutar', 'Tarih', 'Aktif']);
  data.row(<Object?>[
    'A-1',
    'Şube Müdürü',
    XlsxDecimal('1234.50'),
    const XlsxDate(2026, 10, 24),
    true,
  ]);
  data.row(<Object?>[
    'A-2',
    'bad\u0001text',
    12.5,
    DateTime(2026, 10, 24, 13, 45),
    false,
  ], style: const XlsxStyle(numFmt: XlsxNumFmt.custom('#,##0.00')));
  data.blankRow();
  data.row(<Object?>[
    null,
    const XlsxCell('styled', style: XlsxStyle(numFmt: XlsxNumFmt.builtin(49))),
    const XlsxFormula('SUM(C2:C3)', cached: 1247),
  ]);
  final XlsxSheetWriter summary = book.addSheet('Sum/mary', position: 0);
  summary.row(<Object?>['Toplam', const XlsxFormula('=Data!C5')]);
  book.setActiveSheet(summary);
  book.addSheet('Empty');
}

String _sheetXml(String sheetData) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<worksheet xmlns="$_main" xmlns:r="$_rel">'
    '<sheetViews><sheetView workbookViewId="0"/></sheetViews>'
    '$sheetData</worksheet>';

void main() {
  test('minimal workbook has the expected parts', () {
    final XlsxWriter book = XlsxWriter();
    book.addSheet('Data').row(<Object?>['Kod', 1]);
    final Map<String, String> parts = readXlsx(book.close().bytes);
    expect(
      parts.keys,
      containsAll(<String>[
        '[Content_Types].xml',
        '_rels/.rels',
        'docProps/core.xml',
        'docProps/app.xml',
        'xl/workbook.xml',
        'xl/_rels/workbook.xml.rels',
        'xl/styles.xml',
        'xl/sharedStrings.xml',
        'xl/worksheets/sheet1.xml',
      ]),
    );
    expect(
      parts['xl/worksheets/sheet1.xml'],
      contains(
        '<sheetData><row r="1"><c r="A1" t="s"><v>0</v></c>'
        '<c r="B1"><v>1</v></c></row></sheetData>',
      ),
    );
  });

  test('a worksheet is the views, the rows and nothing else', () {
    final XlsxWriter book = XlsxWriter();
    final XlsxSheetWriter sheet = book.addSheet('S');
    sheet.row(<Object?>[1]);
    sheet.blankRow();
    sheet.row(<Object?>[2, 3]);
    final String xml = readXlsx(
      book.close().bytes,
    )['xl/worksheets/sheet1.xml']!;
    expect(
      xml,
      _sheetXml(
        '<sheetData>'
        '<row r="1"><c r="A1"><v>1</v></c></row>'
        '<row r="3"><c r="A3"><v>2</v></c><c r="B3"><v>3</v></c></row>'
        '</sheetData>',
      ),
    );
  });

  test('entries are written in a fixed order', () {
    final XlsxWriter book = XlsxWriter();
    book.addSheet('A');
    book.addSheet('B', position: 0);
    expect(readXlsx(book.close().bytes).keys.toList(), <String>[
      'xl/worksheets/sheet1.xml',
      'xl/worksheets/sheet2.xml',
      'xl/sharedStrings.xml',
      'xl/styles.xml',
      'xl/workbook.xml',
      'xl/_rels/workbook.xml.rels',
      'docProps/core.xml',
      'docProps/app.xml',
      '_rels/.rels',
      '[Content_Types].xml',
    ]);
  });

  test('tab order follows position, part names follow creation', () {
    final XlsxWriter book = XlsxWriter();
    final XlsxSheetWriter a = book.addSheet('Detail A');
    book.addSheet('Detail B');
    final XlsxSheetWriter summary = book.addSheet('Summary', position: 0);
    book.setActiveSheet(summary);
    final String wb = readXlsx(book.close().bytes)['xl/workbook.xml']!;
    expect(wb, contains('<workbookView activeTab="0"/>'));
    expect(
      wb.indexOf('name="Summary"'),
      lessThan(wb.indexOf('name="Detail A"')),
    );
    expect(wb, contains('<sheet name="Summary" sheetId="3"'));
    expect(() => a.row(<Object?>[1]), throwsStateError); // finished
  });

  test('the workbook lists sheets in tab order with matching ids', () {
    final XlsxWriter book = XlsxWriter();
    book.addSheet('One');
    book.addSheet('Two');
    book.addSheet('Three', position: 1);
    final Map<String, String> parts = readXlsx(book.close().bytes);
    expect(
      parts['xl/workbook.xml'],
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="$_main" xmlns:r="$_rel">'
      '<bookViews><workbookView activeTab="0"/></bookViews>'
      '<sheets>'
      '<sheet name="One" sheetId="1" r:id="rId1"/>'
      '<sheet name="Three" sheetId="3" r:id="rId3"/>'
      '<sheet name="Two" sheetId="2" r:id="rId2"/>'
      '</sheets></workbook>',
    );
    expect(
      parts['xl/_rels/workbook.xml.rels'],
      contains(
        'Id="rId3" Type="$_rel/worksheet" Target="worksheets/sheet3.xml"',
      ),
    );
  });

  test('the active tab defaults to the first tab and follows inserts', () {
    final XlsxWriter first = XlsxWriter();
    first.addSheet('A');
    first.addSheet('B', position: 0);
    expect(
      readXlsx(first.close().bytes)['xl/workbook.xml'],
      contains('<workbookView activeTab="0"/>'),
    );

    final XlsxWriter moved = XlsxWriter();
    final XlsxSheetWriter a = moved.addSheet('A');
    moved.setActiveSheet(a);
    moved.addSheet('Z', position: 0);
    final String wb = readXlsx(moved.close().bytes)['xl/workbook.xml']!;
    expect(wb, contains('<workbookView activeTab="1"/>'));
    expect(wb, isNot(contains('tabSelected')));
  });

  test('setActiveSheet rejects a sheet of another writer', () {
    final XlsxWriter one = XlsxWriter();
    final XlsxWriter other = XlsxWriter();
    one.addSheet('A');
    final XlsxSheetWriter foreign = other.addSheet('B');
    expect(() => one.setActiveSheet(foreign), throwsArgumentError);
  });

  test('streaming writer produces the same bytes as the in-memory writer', () {
    final XlsxWriter memory = XlsxWriter();
    _mixedScript(memory);
    final XlsxResult expected = memory.close();

    final _CollectingSink sink = _CollectingSink();
    final XlsxStreamWriter stream = XlsxStreamWriter(sink);
    _mixedScript(stream);
    final List<XlsxWarning> warnings = stream.close();

    expect(sink.closed, isTrue);
    expect(sink.bytes, expected.bytes);
    expect(warnings, isNotEmpty);
    expect(
      warnings.map((XlsxWarning w) => w.toString()).toList(),
      expected.warnings.map((XlsxWarning w) => w.toString()).toList(),
    );
  });

  test('a finished sheet goes to the sink before close', () {
    final _CollectingSink sink = _CollectingSink();
    final XlsxStreamWriter book = XlsxStreamWriter(sink);
    final XlsxSheetWriter sheet = book.addSheet('Big');
    final Random random = Random(7);
    for (int r = 0; r < 5000; r++) {
      sheet.row(<Object?>[for (int c = 0; c < 10; c++) random.nextDouble()]);
    }
    expect(sink.chunks, isEmpty, reason: 'the open sheet stays buffered');
    book.addSheet('Next');
    expect(sink.chunks, isNotEmpty);
    book.close();
  });

  test('deterministic output', () {
    final XlsxWriter first = XlsxWriter();
    _mixedScript(first);
    final XlsxWriter second = XlsxWriter();
    _mixedScript(second);
    expect(first.close().bytes, second.close().bytes);
  });

  test('empty shapes are valid', () {
    final XlsxWriter book = XlsxWriter();
    book.addSheet('Empty');
    final XlsxSheetWriter nulls = book.addSheet('Nulls');
    nulls.row(<Object?>[null, null, const XlsxCell(null)]);
    expect(nulls.rowCount, 1);
    final XlsxSheetWriter blank = book.addSheet('Blank');
    blank.row(<Object?>[]);
    blank.row(<Object?>['']);
    expect(blank.rowCount, 2);
    final Map<String, String> parts = readXlsx(book.close().bytes);
    for (final MapEntry<String, String> part in parts.entries) {
      expect(
        () => XmlDocument.parse(part.value),
        returnsNormally,
        reason: part.key,
      );
    }
    expect(parts['xl/worksheets/sheet1.xml'], _sheetXml('<sheetData/>'));
    expect(parts['xl/worksheets/sheet2.xml'], _sheetXml('<sheetData/>'));
    expect(
      parts['xl/worksheets/sheet3.xml'],
      contains('<sheetData><row r="2"><c r="A2" t="s"><v>0</v></c></row>'),
    );
    expect(
      parts['xl/sharedStrings.xml'],
      contains('count="1" uniqueCount="1"><si><t></t></si></sst>'),
    );
  });

  test('sharedStrings.xml is written even without strings', () {
    final XlsxWriter book = XlsxWriter();
    book.addSheet('N').row(<Object?>[1]);
    expect(
      readXlsx(book.close().bytes)['xl/sharedStrings.xml'],
      contains('count="0" uniqueCount="0"/>'),
    );
  });

  test('no sheets is a StateError; lifecycle errors', () {
    final XlsxWriter none = XlsxWriter();
    expect(none.close, throwsStateError);

    final XlsxWriter book = XlsxWriter();
    final XlsxSheetWriter sheet = book.addSheet('S');
    expect(() => book.addSheet('T', position: 5), throwsRangeError);
    expect(() => book.addSheet('T', position: -1), throwsRangeError);
    book.close();
    expect(book.close, throwsStateError);
    expect(() => book.addSheet('T'), throwsStateError);
    expect(() => book.setActiveSheet(sheet), throwsStateError);
    expect(() => sheet.row(<Object?>[1]), throwsStateError);
    expect(sheet.blankRow, throwsStateError);

    final _CollectingSink sink = _CollectingSink();
    final XlsxStreamWriter stream = XlsxStreamWriter(sink);
    expect(stream.close, throwsStateError);
    stream.addSheet('S');
    stream.close();
    expect(stream.close, throwsStateError);
  });

  test('a rejected position changes nothing', () {
    final XlsxWriter book = XlsxWriter();
    final XlsxSheetWriter first = book.addSheet('S');
    expect(() => book.addSheet('S', position: 2), throwsRangeError);
    first.row(<Object?>[1]); // still open
    final XlsxResult out = book.close();
    expect(out.warnings, isEmpty); // the rejected name was never assigned
    expect(
      readXlsx(out.bytes).keys,
      isNot(contains('xl/worksheets/sheet2.xml')),
    );
  });

  test('row and column limits', () {
    final XlsxSheetWriter s = XlsxWriter().addSheet('S');
    expect(
      () => s.row(List<Object?>.filled(16385, 1)),
      throwsA(
        isA<XlsxLimitError>()
            .having((XlsxLimitError e) => e.limit, 'limit', 'columns')
            .having((XlsxLimitError e) => e.max, 'max', 16384),
      ),
    );
    expect(s.rowCount, 0);
    s.row(List<Object?>.filled(16384, 1));
    for (int r = s.rowCount; r < 1048576; r++) {
      s.blankRow();
    }
    expect(s.rowCount, 1048576);
    final Matcher rowLimit = throwsA(
      isA<XlsxLimitError>()
          .having((XlsxLimitError e) => e.limit, 'limit', 'rows')
          .having((XlsxLimitError e) => e.max, 'max', 1048576),
    );
    expect(() => s.row(<Object?>[1]), rowLimit);
    expect(s.blankRow, rowLimit);
    expect(s.rowCount, 1048576);
  });

  test('100,000 dirty cells give one warning end to end', () {
    final XlsxWriter book = XlsxWriter();
    final XlsxSheetWriter s = book.addSheet('Data');
    for (int r = 0; r < 100000; r++) {
      s.row(<Object?>['x\u0001']);
    }
    final XlsxResult out = book.close();
    expect(out.warnings, hasLength(1));
    expect(out.warnings.single.count, 100000);
    expect(out.warnings.single.cells, hasLength(10));
  });

  test('sheet-name warnings use the final name', () {
    final XlsxWriter book = XlsxWriter();
    final XlsxSheetWriter sheet = book.addSheet('a/b');
    expect(sheet.name, 'a_b');
    final XlsxSheetWriter twin = book.addSheet('A_B');
    expect(twin.name, 'A_B (2)');
    final XlsxResult out = book.close();
    expect(
      out.warnings.map((XlsxWarning w) => (w.code, w.sheet, w.originalName)),
      <(XlsxWarningCode, String, String?)>[
        (XlsxWarningCode.sheetNameChanged, 'a_b', 'a/b'),
        (XlsxWarningCode.sheetNameDuplicated, 'A_B (2)', 'A_B'),
      ],
    );
    expect(
      readXlsx(out.bytes)['xl/workbook.xml'],
      contains('<sheet name="A_B (2)" sheetId="2" r:id="rId2"/>'),
    );
  });

  test('a row style applies to its cells', () {
    final XlsxWriter book = XlsxWriter();
    book.addSheet('S').row(<Object?>[
      1.5,
    ], style: const XlsxStyle(numFmt: XlsxNumFmt.custom('0.0')));
    final Map<String, String> parts = readXlsx(book.close().bytes);
    expect(
      parts['xl/worksheets/sheet1.xml'],
      contains('<row r="1"><c r="A1" s="1"><v>1.5</v></c></row>'),
    );
    expect(parts['xl/styles.xml'], contains('formatCode="0.0"'));
  });

  test('a cell that throws leaves the file well-formed', () {
    final XlsxWriter book = XlsxWriter();
    final XlsxSheetWriter s = book.addSheet('S');
    expect(() => s.row(<Object?>['ok', Object()]), throwsArgumentError);
    expect(s.rowCount, 1);
    s.row(<Object?>['next']);
    final String xml = readXlsx(
      book.close().bytes,
    )['xl/worksheets/sheet1.xml']!;
    expect(() => XmlDocument.parse(xml), returnsNormally);
    expect(
      xml,
      contains(
        '<row r="1"><c r="A1" t="s"><v>0</v></c></row>'
        '<row r="2"><c r="A2" t="s"><v>1</v></c></row>',
      ),
    );
  });

  test('a cell that throws on its style changes no string or warning', () {
    final XlsxWriter book = XlsxWriter();
    final XlsxSheetWriter s = book.addSheet('S');
    expect(
      () => s.row(<Object?>[
        const XlsxCell(
          'a\u0001b',
          style: XlsxStyle(numFmt: XlsxNumFmt.builtin(200)),
        ),
      ]),
      throwsArgumentError,
    );
    s.row(<Object?>['ok']);
    final XlsxResult out = book.close();
    expect(out.warnings, isEmpty);
    expect(checkXlsx(out.bytes), isEmpty);
  });

  test('a CR in cell text survives a conforming XML reader', () {
    final XlsxWriter book = XlsxWriter();
    book.addSheet('S').row(<Object?>[
      'a\rb',
      'c\r\nd',
      const XlsxFormula('A1', cached: 'e\rf'),
    ]);
    final Map<String, String> parts = readXlsx(book.close().bytes);
    // End-of-line handling (XML 1.0, 2.11): every literal CRLF and CR in
    // the document reaches the application as LF.
    String normalized(String xml) =>
        xml.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final XmlDocument sst = XmlDocument.parse(
      normalized(parts['xl/sharedStrings.xml']!),
    );
    expect(
      sst.findAllElements('t').map((XmlElement t) => t.innerText),
      <String>['a\rb', 'c\r\nd'],
    );
    final XmlDocument sheet = XmlDocument.parse(
      normalized(parts['xl/worksheets/sheet1.xml']!),
    );
    expect(sheet.findAllElements('v').last.innerText, 'e\rf');
  });

  test('formulas switch on full recalculation', () {
    final XlsxWriter withFormula = XlsxWriter();
    withFormula.addSheet('S').row(<Object?>[1, const XlsxFormula('A1*2')]);
    expect(
      readXlsx(withFormula.close().bytes)['xl/workbook.xml'],
      contains('</sheets><calcPr fullCalcOnLoad="1"/></workbook>'),
    );

    final XlsxWriter without = XlsxWriter();
    without.addSheet('S').row(<Object?>[1, 2]);
    expect(
      readXlsx(without.close().bytes)['xl/workbook.xml'],
      isNot(contains('calcPr')),
    );
  });

  test('properties reach the property parts', () {
    final XlsxWriter book = XlsxWriter(
      properties: const XlsxProperties(title: 'Accounts', company: 'Jet'),
    );
    book.addSheet('S');
    final Map<String, String> parts = readXlsx(book.close().bytes);
    expect(
      parts['docProps/core.xml'],
      contains('<dc:title>Accounts</dc:title>'),
    );
    expect(parts['docProps/app.xml'], contains('<Company>Jet</Company>'));
  });

  test('invalid properties throw before anything is written', () {
    final _CollectingSink sink = _CollectingSink();
    expect(
      () => XlsxStreamWriter(
        sink,
        properties: const XlsxProperties(title: 'bad\u0001'),
      ),
      throwsArgumentError,
    );
    expect(sink.chunks, isEmpty);
    expect(sink.closed, isFalse);
    expect(
      () => XlsxWriter(properties: const XlsxProperties(company: 'x\u0000')),
      throwsArgumentError,
    );
  });

  test('every part is well-formed XML', () {
    final XlsxWriter book = XlsxWriter(
      properties: XlsxProperties(
        title: 'T & <C>',
        creator: 'Ahmet',
        created: DateTime.utc(2026, 10, 24),
      ),
    );
    _mixedScript(book);
    final Map<String, String> parts = readXlsx(book.close().bytes);
    expect(parts, hasLength(11));
    for (final MapEntry<String, String> part in parts.entries) {
      expect(
        part.key.endsWith('.xml') || part.key.endsWith('.rels'),
        isTrue,
        reason: part.key,
      );
      expect(
        () => XmlDocument.parse(part.value),
        returnsNormally,
        reason: part.key,
      );
    }
  });
}
