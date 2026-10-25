// ignore_for_file: close_sinks
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

/// What [_ThrowingSink] throws.
final class _SinkFailure implements Exception {
  const _SinkFailure();

  @override
  String toString() => 'disk full';
}

/// A sink that throws on every add, like a full disk, and records close().
final class _ThrowingSink implements Sink<List<int>> {
  int adds = 0;
  bool closed = false;

  @override
  void add(List<int> data) {
    adds++;
    throw const _SinkFailure();
  }

  @override
  void close() => closed = true;
}

/// Fills [sheet] with enough poorly compressing numbers that finishing it
/// sends at least one chunk to the sink.
void _fillBig(XlsxSheetWriter sheet) {
  final Random random = Random(7);
  for (int r = 0; r < 5000; r++) {
    sheet.row(<Object?>[for (int c = 0; c < 10; c++) random.nextDouble()]);
  }
}

final Matcher _throwsFailedState = throwsA(
  isA<StateError>().having(
    (StateError e) => e.message,
    'message',
    allOf(contains('failed earlier'), contains('disk full')),
  ),
);

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

  test('ten or more sheets get matching ids, parts and relationships', () {
    final XlsxWriter book = XlsxWriter();
    for (int i = 1; i <= 12; i++) {
      book.addSheet('S$i').row(<Object?>[i]);
    }
    final Map<String, String> parts = readXlsx(book.close().bytes);
    final String wb = parts['xl/workbook.xml']!;
    final String rels = parts['xl/_rels/workbook.xml.rels']!;
    final String types = parts['[Content_Types].xml']!;
    for (int i = 1; i <= 12; i++) {
      expect(wb, contains('<sheet name="S$i" sheetId="$i" r:id="rId$i"/>'));
      expect(
        rels,
        contains(
          'Id="rId$i" Type="$_rel/worksheet" '
          'Target="worksheets/sheet$i.xml"',
        ),
      );
      expect(types, contains('PartName="/xl/worksheets/sheet$i.xml"'));
      expect(parts, contains('xl/worksheets/sheet$i.xml'));
    }
    // The styles and shared strings follow the twelve worksheets.
    expect(rels, contains('Id="rId13" Type="$_rel/styles"'));
    expect(rels, contains('Id="rId14" Type="$_rel/sharedStrings"'));
    expect(parts['xl/worksheets/sheet10.xml'], contains('<v>10</v>'));
  });

  test('the warnings of a result cannot be modified', () {
    final XlsxWriter book = XlsxWriter();
    book.addSheet('S').row(<Object?>['a\u0001b']);
    final XlsxResult out = book.close();
    expect(out.warnings, hasLength(1));
    expect(() => out.warnings.clear(), throwsUnsupportedError);
    expect(() => out.warnings.single.cells.add('Z9'), throwsUnsupportedError);
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

  test('a sink that fails while a sheet is finished stops the writer', () {
    final _ThrowingSink sink = _ThrowingSink();
    final XlsxStreamWriter book = XlsxStreamWriter(sink);
    final XlsxSheetWriter big = book.addSheet('Big');
    _fillBig(big);
    expect(() => book.addSheet('Next'), throwsA(isA<_SinkFailure>()));
    expect(sink.adds, 1);
    expect(sink.closed, isTrue);
    expect(() => big.row(<Object?>[1]), _throwsFailedState);
    expect(big.blankRow, _throwsFailedState);
    expect(() => book.addSheet('Other'), _throwsFailedState);
    expect(() => book.setActiveSheet(big), _throwsFailedState);
    expect(book.close, _throwsFailedState);
    expect(sink.adds, 1);
  });

  test('a sink that fails in close stops the writer', () {
    final _ThrowingSink sink = _ThrowingSink();
    final XlsxStreamWriter book = XlsxStreamWriter(sink);
    final XlsxSheetWriter sheet = book.addSheet('Small')..row(<Object?>[1]);
    expect(book.close, throwsA(isA<_SinkFailure>()));
    expect(sink.closed, isTrue);
    expect(book.close, _throwsFailedState);
    expect(() => sheet.row(<Object?>[2]), _throwsFailedState);
    expect(() => book.addSheet('Other'), _throwsFailedState);
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

  test('a sheet name that looks like an escape is written escaped', () {
    final XlsxWriter book = XlsxWriter();
    final XlsxSheetWriter sheet = book.addSheet('_x0041_');
    expect(sheet.name, '_x0041_');
    sheet.row(<Object?>['x']);
    final XlsxResult out = book.close();
    expect(out.warnings, isEmpty);
    expect(
      readXlsx(out.bytes)['xl/workbook.xml'],
      contains('<sheet name="_x005F_x0041_" sheetId="1" r:id="rId1"/>'),
    );
    expect(checkXlsx(out.bytes), isEmpty);
  });

  test('the 31-unit limit counts the original name, not the escaped one', () {
    final String name = '_x0041_${'a' * 24}';
    expect(name.length, 31);
    final XlsxWriter book = XlsxWriter();
    final XlsxSheetWriter sheet = book.addSheet(name);
    expect(sheet.name, name);
    sheet.row(<Object?>['x']);
    final XlsxResult out = book.close();
    expect(out.warnings, isEmpty);
    expect(
      readXlsx(out.bytes)['xl/workbook.xml'],
      contains('<sheet name="_x005F_x0041_${'a' * 24}"'),
    );
    expect(checkXlsx(out.bytes), isEmpty);
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

  group('columns, rows and default sizes', () {
    const XlsxStyle money = XlsxStyle(numFmt: XlsxNumFmt.thousands2);
    const XlsxStyle bold = XlsxStyle(font: XlsxFont(bold: true));

    /// The first worksheet of [book], after closing it.
    String sheet1(XlsxWriter book) =>
        readXlsx(book.close().bytes)['xl/worksheets/sheet1.xml']!;

    test('columns write joined <col> elements', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S')
        ..columns(const <XlsxColumn?>[
          XlsxColumn(width: 12),
          XlsxColumn(width: 12),
          null,
          XlsxColumn(hidden: true),
        ])
        ..row(<Object?>[1]);
      expect(
        sheet1(book),
        _sheetXml(
          '<cols><col min="1" max="2" width="12" customWidth="1"/>'
          '<col min="4" max="4" width="9.140625" hidden="1"/></cols>'
          '<sheetData><row r="1"><c r="A1"><v>1</v></c></row></sheetData>',
        ),
      );
    });

    test('a column with only a style writes its cell format', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S').columns(const <XlsxColumn?>[
        null,
        null,
        XlsxColumn(style: money),
      ]);
      final XlsxResult out = book.close();
      final Map<String, String> parts = readXlsx(out.bytes);
      expect(
        parts['xl/worksheets/sheet1.xml'],
        contains(
          '<cols><col min="3" max="3" width="9.140625" style="1"/></cols>',
        ),
      );
      expect(parts['xl/styles.xml'], contains('<cellXfs count="2">'));
      expect(checkXlsx(out.bytes), isEmpty);
    });

    test('default sizes write sheetFormatPr', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S').defaultSizes(rowHeight: 18, columnWidth: 10);
      expect(
        sheet1(book),
        contains(
          '<sheetViews><sheetView workbookViewId="0"/></sheetViews>'
          '<sheetFormatPr defaultColWidth="10" defaultRowHeight="18" '
          'customHeight="1"/><sheetData/>',
        ),
      );
    });

    test('a null column width takes the default column width', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S')
        ..columns(const <XlsxColumn?>[XlsxColumn(hidden: true)])
        ..defaultSizes(columnWidth: 11);
      expect(
        sheet1(book),
        contains(
          '<sheetFormatPr defaultColWidth="11" defaultRowHeight="15"/>'
          '<cols><col min="1" max="1" width="11" hidden="1"/></cols>',
        ),
      );
    });

    test('row attributes', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S')
        ..row(<Object?>['a'], height: 30)
        ..row(<Object?>['b'], hidden: true)
        ..row(<Object?>['c'], outlineLevel: 1)
        ..row(<Object?>['d'], collapsed: true)
        ..blankRow(height: 5)
        ..row(<Object?>[null, null], hidden: true)
        ..row(
          <Object?>['e'],
          height: 12.5,
          hidden: true,
          outlineLevel: 2,
          collapsed: true,
        );
      final String xml = sheet1(book);
      expect(
        xml,
        contains(
          '<sheetFormatPr defaultRowHeight="15" outlineLevelRow="2"/>'
          '<sheetData>'
          '<row r="1" ht="30" customHeight="1"><c r="A1" t="s"><v>0</v></c>'
          '</row>'
          '<row r="2" hidden="1"><c r="A2" t="s"><v>1</v></c></row>'
          '<row r="3" outlineLevel="1"><c r="A3" t="s"><v>2</v></c></row>'
          '<row r="4" collapsed="1"><c r="A4" t="s"><v>3</v></c></row>'
          '<row r="5" ht="5" customHeight="1"/>'
          '<row r="6" hidden="1"/>'
          '<row r="7" ht="12.5" hidden="1" customHeight="1" outlineLevel="2" '
          'collapsed="1"><c r="A7" t="s"><v>4</v></c></row>'
          '</sheetData>',
        ),
      );
    });

    test('rows that carry only attributes are written', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S')
        ..blankRow(height: 30)
        ..row(<Object?>[null, null], hidden: true)
        ..blankRow(outlineLevel: 3)
        ..blankRow(outlineLevel: 1)
        ..blankRow();
      final XlsxResult out = book.close();
      expect(
        readXlsx(out.bytes)['xl/worksheets/sheet1.xml'],
        contains(
          '<sheetFormatPr defaultRowHeight="15" outlineLevelRow="3"/>'
          '<sheetData>'
          '<row r="1" ht="30" customHeight="1"/>'
          '<row r="2" hidden="1"/>'
          '<row r="3" outlineLevel="3"/>'
          '<row r="4" outlineLevel="1"/>'
          '</sheetData>',
        ),
      );
      expect(checkXlsx(out.bytes), isEmpty);
    });

    test('heights and hidden rows alone write no sheetFormatPr', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S')
        ..row(<Object?>[1], height: 20)
        ..blankRow(hidden: true);
      expect(sheet1(book), isNot(contains('sheetFormatPr')));
    });

    test('a column style reaches the cells under the row style', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S')
        ..columns(const <XlsxColumn?>[null, null, XlsxColumn(style: money)])
        ..row(<Object?>['a', 'b', 1.5])
        ..row(<Object?>['c', 'd', 2.5], style: bold);
      final XlsxResult out = book.close();
      final Map<String, String> parts = readXlsx(out.bytes);
      final XmlDocument sheet = XmlDocument.parse(
        parts['xl/worksheets/sheet1.xml']!,
      );
      String styleOf(String ref) => sheet
          .findAllElements('c')
          .firstWhere((XmlElement c) => c.getAttribute('r') == ref)
          .getAttribute('s')!;
      final List<XmlElement> xfs = XmlDocument.parse(
        parts['xl/styles.xml']!,
      ).findAllElements('cellXfs').single.findElements('xf').toList();
      final XmlElement c1 = xfs[int.parse(styleOf('C1'))];
      expect(c1.getAttribute('numFmtId'), '4');
      expect(c1.getAttribute('fontId'), '0');
      final XmlElement c2 = xfs[int.parse(styleOf('C2'))];
      expect(c2.getAttribute('numFmtId'), '4');
      expect(c2.getAttribute('fontId'), '1');
      final XmlElement a2 = xfs[int.parse(styleOf('A2'))];
      expect(a2.getAttribute('numFmtId'), '0');
      expect(a2.getAttribute('fontId'), '1');
      expect(checkXlsx(out.bytes), isEmpty);
    });

    group('header settings are frozen at the first row', () {
      Matcher frozen(String setting) => throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          allOf(contains('"S"'), contains(setting)),
        ),
      );

      test('columns after row', () {
        final XlsxSheetWriter s = XlsxWriter().addSheet('S');
        s.row(<Object?>[1]);
        expect(
          () => s.columns(const <XlsxColumn?>[XlsxColumn(width: 5)]),
          frozen('columns'),
        );
      });

      test('columns after blankRow', () {
        final XlsxSheetWriter s = XlsxWriter().addSheet('S');
        s.blankRow();
        expect(
          () => s.columns(const <XlsxColumn?>[XlsxColumn(width: 5)]),
          frozen('columns'),
        );
      });

      test('defaultSizes after row', () {
        final XlsxSheetWriter s = XlsxWriter().addSheet('S');
        s.row(<Object?>[]);
        expect(() => s.defaultSizes(rowHeight: 20), frozen('defaultSizes'));
      });

      test('defaultSizes after blankRow', () {
        final XlsxSheetWriter s = XlsxWriter().addSheet('S');
        s.blankRow();
        expect(() => s.defaultSizes(rowHeight: 20), frozen('defaultSizes'));
      });

      test('a refused setting changes nothing', () {
        final XlsxWriter book = XlsxWriter();
        final XlsxSheetWriter s = book.addSheet('S');
        s.blankRow(height: 10);
        expect(
          () => s.columns(const <XlsxColumn?>[XlsxColumn(style: bold)]),
          throwsStateError,
        );
        expect(() => s.defaultSizes(columnWidth: 3), frozen('defaultSizes'));
        final XlsxResult out = book.close();
        final Map<String, String> parts = readXlsx(out.bytes);
        expect(parts['xl/worksheets/sheet1.xml'], isNot(contains('<cols')));
        expect(
          parts['xl/worksheets/sheet1.xml'],
          isNot(contains('sheetFormatPr')),
        );
        expect(parts['xl/styles.xml'], contains('<cellXfs count="1">'));
      });

      test('a later call before any row replaces the earlier one', () {
        final XlsxWriter book = XlsxWriter();
        book.addSheet('S')
          ..columns(const <XlsxColumn?>[XlsxColumn(width: 5)])
          ..columns(const <XlsxColumn?>[null, XlsxColumn(width: 6)])
          ..defaultSizes(rowHeight: 20)
          ..defaultSizes(columnWidth: 8)
          ..row(<Object?>[1, 2]);
        final String xml = sheet1(book);
        expect(
          xml,
          contains(
            '<sheetFormatPr defaultColWidth="8" defaultRowHeight="15"/>'
            '<cols><col min="2" max="2" width="6" customWidth="1"/></cols>',
          ),
        );
      });

      test('a finished sheet refuses settings', () {
        final XlsxWriter book = XlsxWriter();
        final XlsxSheetWriter s = book.addSheet('S');
        book.addSheet('T');
        expect(() => s.columns(const <XlsxColumn?>[]), throwsStateError);
        expect(s.defaultSizes, throwsStateError);
      });
    });

    group('invalid layout values throw and record nothing', () {
      /// Runs [bad], which must throw [ArgumentError] naming [field], on a
      /// fresh sheet, and checks that the file is as if it was never called.
      void expectRejected(void Function(XlsxSheetWriter s) bad, String field) {
        final XlsxWriter book = XlsxWriter();
        final XlsxSheetWriter s = book.addSheet('S');
        expect(
          () => bad(s),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              field,
            ),
          ),
        );
        expect(s.rowCount, 0);
        // Not frozen: a header setting is still accepted.
        s.defaultSizes();
        final XlsxResult out = book.close();
        final Map<String, String> parts = readXlsx(out.bytes);
        expect(parts['xl/worksheets/sheet1.xml'], _sheetXml('<sheetData/>'));
        expect(parts['xl/styles.xml'], contains('<cellXfs count="1">'));
        expect(parts['xl/styles.xml'], contains('<fonts count="1">'));
      }

      for (final double width in <double>[-1, 256, double.nan]) {
        test('column width $width', () {
          expectRejected(
            (XlsxSheetWriter s) => s.columns(<XlsxColumn?>[
              const XlsxColumn(style: bold),
              XlsxColumn(width: width),
            ]),
            'columns[1].width',
          );
        });
        test('default column width $width', () {
          expectRejected(
            (XlsxSheetWriter s) => s.defaultSizes(columnWidth: width),
            'columnWidth',
          );
        });
      }

      for (final double height in <double>[-1, 410]) {
        test('row height $height', () {
          expectRejected(
            (XlsxSheetWriter s) => s.row(<Object?>['x'], height: height),
            'height',
          );
        });
        test('blank row height $height', () {
          expectRejected(
            (XlsxSheetWriter s) => s.blankRow(height: height),
            'height',
          );
        });
        test('default row height $height', () {
          expectRejected(
            (XlsxSheetWriter s) => s.defaultSizes(rowHeight: height),
            'rowHeight',
          );
        });
      }

      for (final int level in <int>[-1, 8]) {
        test('row outline level $level', () {
          expectRejected(
            (XlsxSheetWriter s) => s.row(<Object?>['x'], outlineLevel: level),
            'outlineLevel',
          );
        });
        test('blank row outline level $level', () {
          expectRejected(
            (XlsxSheetWriter s) => s.blankRow(outlineLevel: level),
            'outlineLevel',
          );
        });
        test('column outline level $level', () {
          expectRejected(
            (XlsxSheetWriter s) => s.columns(<XlsxColumn?>[
              const XlsxColumn(style: bold),
              XlsxColumn(outlineLevel: level),
            ]),
            'columns[1].outlineLevel',
          );
        });
      }

      test('an invalid column style after a valid one', () {
        expectRejected(
          (XlsxSheetWriter s) => s.columns(const <XlsxColumn?>[
            XlsxColumn(style: bold),
            XlsxColumn(style: XlsxStyle(numFmt: XlsxNumFmt.builtin(200))),
          ]),
          'columns[1].style',
        );
      });
    });

    test('more than 16,384 columns', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter s = book.addSheet('S');
      expect(
        () => s.columns(
          List<XlsxColumn?>.filled(16385, const XlsxColumn(width: 1)),
        ),
        throwsA(
          isA<XlsxLimitError>()
              .having((XlsxLimitError e) => e.limit, 'limit', 'columns')
              .having((XlsxLimitError e) => e.max, 'max', 16384),
        ),
      );
      s.columns(List<XlsxColumn?>.filled(16384, const XlsxColumn(width: 1)));
      final XlsxResult out = book.close();
      expect(
        readXlsx(out.bytes)['xl/worksheets/sheet1.xml'],
        contains(
          '<cols><col min="1" max="16384" width="1" customWidth="1"/></cols>',
        ),
      );
      expect(checkXlsx(out.bytes), isEmpty);
    });

    group('styled empty cells (ruling R11)', () {
      const XlsxStyle bold = XlsxStyle(font: XlsxFont(bold: true));

      test('a row of only styled empties is written', () {
        final XlsxWriter book = XlsxWriter();
        book.addSheet('S').row(<Object?>[
          null,
          const XlsxCell(null),
          const XlsxCell(null, style: bold),
        ]);
        final XlsxResult out = book.close();
        expect(
          readXlsx(out.bytes)['xl/worksheets/sheet1.xml'],
          contains('<sheetData><row r="1"><c r="C1" s="1"/></row></sheetData>'),
        );
        expect(checkXlsx(out.bytes), isEmpty);
      });

      test('the row style and the column style merge into it', () {
        final XlsxWriter book = XlsxWriter();
        book.addSheet('S')
          ..columns(const <XlsxColumn?>[
            XlsxColumn(style: XlsxStyle(numFmt: XlsxNumFmt.custom('0.0'))),
          ])
          ..row(<Object?>[
            const XlsxCell(
              null,
              style: XlsxStyle(font: XlsxFont(italic: true)),
            ),
          ], style: bold);
        final Map<String, String> parts = readXlsx(book.close().bytes);
        // 1 is the column's own format; 2 merges all three layers.
        expect(
          parts['xl/worksheets/sheet1.xml'],
          contains('<row r="1"><c r="A1" s="2"/></row>'),
        );
        expect(parts['xl/styles.xml'], contains('<cellXfs count="3">'));
      });

      test('a styled empty that resolves to the default writes no row', () {
        final XlsxWriter book = XlsxWriter();
        final XlsxSheetWriter s = book.addSheet('S');
        s.row(<Object?>[const XlsxCell(null, style: XlsxStyle())]);
        expect(s.rowCount, 1);
        expect(
          readXlsx(book.close().bytes)['xl/worksheets/sheet1.xml'],
          _sheetXml('<sheetData/>'),
        );
      });

      test('an invalid style throws and records nothing', () {
        final XlsxWriter book = XlsxWriter();
        final XlsxSheetWriter s = book.addSheet('S');
        expect(
          () => s.row(<Object?>[
            const XlsxCell(
              null,
              style: XlsxStyle(numFmt: XlsxNumFmt.builtin(200)),
            ),
          ]),
          throwsArgumentError,
        );
        expect(s.rowCount, 1);
        final XlsxResult out = book.close();
        final Map<String, String> parts = readXlsx(out.bytes);
        expect(parts['xl/worksheets/sheet1.xml'], _sheetXml('<sheetData/>'));
        expect(parts['xl/styles.xml'], contains('<cellXfs count="1">'));
        expect(out.warnings, isEmpty);
        expect(checkXlsx(out.bytes), isEmpty);
      });
    });

    test('a row whose cell throws still closes, attributes kept', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter s = book.addSheet('S');
      expect(
        () => s.row(<Object?>['ok', Object()], height: 20),
        throwsArgumentError,
      );
      expect(
        () => s.row(<Object?>[Object()], hidden: true),
        throwsArgumentError,
      );
      expect(s.rowCount, 2);
      final XlsxResult out = book.close();
      expect(
        readXlsx(out.bytes)['xl/worksheets/sheet1.xml'],
        contains(
          '<sheetData>'
          '<row r="1" ht="20" customHeight="1"><c r="A1" t="s"><v>0</v></c>'
          '</row><row r="2" hidden="1"/></sheetData>',
        ),
      );
      expect(checkXlsx(out.bytes), isEmpty);
    });

    test('a sheet larger than one buffer chunk is assembled byte-exact', () {
      // The body buffer encodes every 16 KiB; 4,000 rows are about 200 KB,
      // so the part is a header, many body chunks and a trailer.
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter s = book.addSheet('S')
        ..columns(const <XlsxColumn?>[XlsxColumn(width: 20)])
        ..defaultSizes(rowHeight: 16);
      final StringBuffer rows = StringBuffer();
      for (int r = 1; r <= 4000; r++) {
        final int level = r % 3;
        s.row(<Object?>[r, r + 0.5], outlineLevel: level);
        rows.write('<row r="$r"');
        if (level > 0) rows.write(' outlineLevel="$level"');
        rows.write(
          '><c r="A$r"><v>$r</v></c><c r="B$r"><v>${r + 0.5}</v></c></row>',
        );
      }
      final String xml = sheet1(book);
      expect(xml.length, greaterThan(10 * 16384));
      expect(
        xml,
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="$_main" xmlns:r="$_rel">'
        '<sheetViews><sheetView workbookViewId="0"/></sheetViews>'
        '<sheetFormatPr defaultRowHeight="16" customHeight="1" '
        'outlineLevelRow="2"/>'
        '<cols><col min="1" max="1" width="20" customWidth="1"/></cols>'
        '<sheetData>$rows</sheetData></worksheet>',
      );
    });

    test('a styled, grouped workbook passes the checker', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S')
        ..columns(const <XlsxColumn?>[
          XlsxColumn(width: 30, style: bold, outlineLevel: 1),
          XlsxColumn(style: money, outlineLevel: 2, hidden: true),
        ])
        ..row(<Object?>['a', 1], outlineLevel: 2, hidden: true)
        ..row(<Object?>['b', 2], outlineLevel: 1, hidden: true)
        ..row(<Object?>['total', 3], collapsed: true);
      expect(checkXlsx(book.close().bytes), isEmpty);
    });
  });

  group('views, panes, tab color and visibility', () {
    String sheetXml(XlsxWriter book, [int n = 1]) =>
        readXlsx(book.close().bytes)['xl/worksheets/sheet$n.xml']!;

    String views(void Function(XlsxSheetWriter s) set) {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter s = book.addSheet('S');
      set(s);
      s.row(<Object?>[1]);
      final String xml = sheetXml(book);
      final int start = xml.indexOf('<sheetViews>');
      return xml.substring(start, xml.indexOf('</sheetViews>') + 13);
    }

    test('the default view is the M1 bytes, with no sheetPr', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S').row(<Object?>[1]);
      final String xml = sheetXml(book);
      expect(xml, isNot(contains('sheetPr')));
      expect(
        xml,
        contains(
          '<worksheet xmlns="$_main" xmlns:r="$_rel">'
          '<sheetViews><sheetView workbookViewId="0"/></sheetViews>'
          '<sheetData>',
        ),
      );
    });

    test('view writes every option', () {
      expect(
        views(
          (XlsxSheetWriter s) => s.view(
            const XlsxSheetView(
              zoom: 85,
              showGridLines: false,
              showHeadings: false,
              rightToLeft: true,
              showZeros: false,
              showFormulas: true,
            ),
          ),
        ),
        '<sheetViews><sheetView showFormulas="1" showGridLines="0" '
        'showRowColHeaders="0" showZeros="0" rightToLeft="1" '
        'zoomScale="85" workbookViewId="0"/></sheetViews>',
      );
    });

    test('freeze rows writes bottomLeft, not Quds\' bottomRight', () {
      expect(
        views((XlsxSheetWriter s) => s.freeze(rows: 1)),
        '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" '
        'topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
        '<selection pane="bottomLeft"/></sheetView></sheetViews>',
      );
    });

    test('freeze columns, and rows with columns', () {
      expect(
        views((XlsxSheetWriter s) => s.freeze(columns: 2)),
        contains(
          '<pane xSplit="2" topLeftCell="C1" activePane="topRight" '
          'state="frozen"/><selection pane="topRight"/>',
        ),
      );
      expect(
        views((XlsxSheetWriter s) => s.freeze(rows: 1, columns: 1)),
        contains(
          '<pane xSplit="1" ySplit="1" topLeftCell="B2" '
          'activePane="bottomRight" state="frozen"/>'
          '<selection pane="bottomRight"/>',
        ),
      );
    });

    test('freeze of zero rows and columns writes no pane', () {
      expect(
        views((XlsxSheetWriter s) => s.freeze()),
        '<sheetViews><sheetView workbookViewId="0"/></sheetViews>',
      );
    });

    test('split is written in twips', () {
      expect(
        views((XlsxSheetWriter s) => s.split(x: 100, y: 50)),
        contains(
          '<pane xSplit="2000" ySplit="1000" activePane="bottomRight"/>'
          '<selection pane="bottomRight"/>',
        ),
      );
    });

    test('freeze keeps the rest of the view; view replaces all of it', () {
      expect(
        views(
          (XlsxSheetWriter s) => s
            ..view(const XlsxSheetView(zoom: 85, showGridLines: false))
            ..freeze(rows: 1),
        ),
        '<sheetViews><sheetView showGridLines="0" zoomScale="85" '
        'workbookViewId="0"><pane ySplit="1" topLeftCell="A2" '
        'activePane="bottomLeft" state="frozen"/>'
        '<selection pane="bottomLeft"/></sheetView></sheetViews>',
      );
      expect(
        views(
          (XlsxSheetWriter s) => s
            ..freeze(rows: 1)
            ..view(const XlsxSheetView(zoom: 85)),
        ),
        '<sheetViews><sheetView zoomScale="85" workbookViewId="0"/>'
        '</sheetViews>',
      );
      expect(
        views(
          (XlsxSheetWriter s) => s
            ..freeze(rows: 1)
            ..split(x: 10),
        ),
        contains('<pane xSplit="200" activePane="topRight"/>'),
      );
    });

    test('tabColor and outlineSummary write sheetPr first', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S')
        ..tabColor(const XlsxColor.rgb(0xFF0000))
        ..outlineSummary(below: false)
        ..row(<Object?>[1]);
      final String xml = sheetXml(book);
      expect(
        xml,
        contains(
          '<worksheet xmlns="$_main" xmlns:r="$_rel">'
          '<sheetPr><tabColor rgb="FFFF0000"/>'
          '<outlinePr summaryBelow="0"/></sheetPr><sheetViews>',
        ),
      );
    });

    test('a later tabColor replaces an earlier one', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S')
        ..tabColor(const XlsxColor.rgb(0xFF0000))
        ..tabColor(const XlsxColor.rgb(0x00FF00))
        ..row(<Object?>[1]);
      final String xml = sheetXml(book);
      expect(xml, contains('<tabColor rgb="FF00FF00"/>'));
      expect(xml, isNot(contains('FFFF0000')));
    });

    test('outlineSummary with the defaults writes no sheetPr', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S')
        ..outlineSummary(below: false)
        ..outlineSummary()
        ..row(<Object?>[1]);
      expect(sheetXml(book), isNot(contains('sheetPr')));
    });

    test('a workbook with views passes the checker', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('A')
        ..freeze(rows: 1, columns: 2)
        ..tabColor(const XlsxColor.theme(3))
        ..row(<Object?>[1]);
      book.addSheet('B')
        ..split(x: 10, y: 20)
        ..row(<Object?>[1]);
      expect(checkXlsx(book.close().bytes), isEmpty);
    });

    group('settings are frozen at the first row', () {
      final Map<String, void Function(XlsxSheetWriter)> settings =
          <String, void Function(XlsxSheetWriter)>{
            'view': (XlsxSheetWriter s) => s.view(const XlsxSheetView()),
            'freeze': (XlsxSheetWriter s) => s.freeze(rows: 1),
            'split': (XlsxSheetWriter s) => s.split(x: 1),
            'tabColor': (XlsxSheetWriter s) =>
                s.tabColor(const XlsxColor.rgb(0xFF0000)),
            'outlineSummary': (XlsxSheetWriter s) =>
                s.outlineSummary(below: false),
          };
      settings.forEach((String name, void Function(XlsxSheetWriter) set) {
        test('$name after blankRow writes nothing', () {
          final XlsxWriter book = XlsxWriter();
          final XlsxSheetWriter s = book.addSheet('S')..blankRow();
          expect(
            () => set(s),
            throwsA(
              isA<StateError>().having(
                (StateError e) => e.message,
                'message',
                allOf(contains('"S"'), contains(name)),
              ),
            ),
          );
          final String xml = sheetXml(book);
          expect(xml, isNot(contains('sheetPr')));
          expect(xml, isNot(contains('<pane')));
          expect(xml, contains('<sheetView workbookViewId="0"/>'));
        });
        test('$name after row, and on a finished sheet', () {
          final XlsxWriter book = XlsxWriter();
          final XlsxSheetWriter s = book.addSheet('S')..row(<Object?>[1]);
          expect(() => set(s), throwsStateError);
          final XlsxSheetWriter fresh = book.addSheet('T');
          expect(() => set(s), throwsStateError);
          set(fresh);
        });
      });
    });

    group('invalid values throw and record nothing', () {
      void expectRejected(void Function(XlsxSheetWriter s) bad, String field) {
        final XlsxWriter book = XlsxWriter();
        final XlsxSheetWriter s = book.addSheet('S')
          ..view(const XlsxSheetView(zoom: 85));
        expect(
          () => bad(s),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.name,
              'name',
              field,
            ),
          ),
        );
        s.row(<Object?>[1]);
        final String xml = sheetXml(book);
        expect(xml, contains('zoomScale="85"'));
        expect(xml, isNot(contains('<pane')));
        expect(xml, isNot(contains('sheetPr')));
      }

      test('zoom', () {
        expectRejected(
          (XlsxSheetWriter s) => s.view(const XlsxSheetView(zoom: 9)),
          'zoom',
        );
        expectRejected(
          (XlsxSheetWriter s) => s.view(const XlsxSheetView(zoom: 401)),
          'zoom',
        );
      });

      test('a pane inside view', () {
        expectRejected(
          (XlsxSheetWriter s) =>
              s.view(const XlsxSheetView(pane: XlsxPane.frozen(rows: -1))),
          'rows',
        );
        expectRejected(
          (XlsxSheetWriter s) =>
              s.view(const XlsxSheetView(pane: XlsxPane.split(x: -1))),
          'x',
        );
      });

      test('freeze rows and columns', () {
        expectRejected((XlsxSheetWriter s) => s.freeze(rows: -1), 'rows');
        expectRejected((XlsxSheetWriter s) => s.freeze(rows: 1048576), 'rows');
        expectRejected((XlsxSheetWriter s) => s.freeze(columns: -1), 'columns');
        expectRejected(
          (XlsxSheetWriter s) => s.freeze(columns: 16384),
          'columns',
        );
      });

      test('the last row and column can be frozen', () {
        final XlsxWriter book = XlsxWriter();
        book.addSheet('S')
          ..freeze(rows: 1048575, columns: 16383)
          ..row(<Object?>[1]);
        expect(sheetXml(book), contains('topLeftCell="XFD1048576"'));
      });

      test('split', () {
        expectRejected((XlsxSheetWriter s) => s.split(x: -1), 'x');
        expectRejected((XlsxSheetWriter s) => s.split(y: -1), 'y');
        expectRejected((XlsxSheetWriter s) => s.split(x: double.nan), 'x');
        expectRejected((XlsxSheetWriter s) => s.split(y: double.nan), 'y');
        expectRejected((XlsxSheetWriter s) => s.split(x: double.infinity), 'x');
      });

      test('a split past 2^31 - 1 twips throws at the call (R12)', () {
        expectRejected((XlsxSheetWriter s) => s.split(x: 1e308), 'x');
        expectRejected((XlsxSheetWriter s) => s.split(y: 107374182.4), 'y');
      });

      test('a split of 2^31 - 1 twips is written', () {
        final XlsxWriter book = XlsxWriter();
        book.addSheet('S')
          ..split(x: 107374182.35)
          ..row(<Object?>[1]);
        expect(sheetXml(book), contains('<pane xSplit="2147483647" '));
      });

      test('a tab color that is out of range', () {
        expectRejected(
          (XlsxSheetWriter s) => s.tabColor(const XlsxColor.theme(99)),
          'color',
        );
      });
    });

    group('visibility', () {
      String workbookXml(XlsxWriter book) =>
          readXlsx(book.close().bytes)['xl/workbook.xml']!;

      test('a sheet is visible by default', () {
        final XlsxWriter book = XlsxWriter();
        expect(book.addSheet('S').visibility, XlsxSheetVisibility.visible);
        expect(workbookXml(book), contains('<sheet name="S" sheetId="1" r:id'));
        expect(
          workbookXml(XlsxWriter()..addSheet('S')),
          isNot(contains('state')),
        );
      });

      test('hidden and veryHidden are written as the state', () {
        final XlsxWriter book = XlsxWriter();
        book.addSheet('V');
        final XlsxSheetWriter h = book.addSheet(
          'H',
          visibility: XlsxSheetVisibility.hidden,
        );
        book.addSheet('X', visibility: XlsxSheetVisibility.veryHidden);
        expect(h.visibility, XlsxSheetVisibility.hidden);
        final String wb = workbookXml(book);
        expect(wb, contains('<sheet name="H" sheetId="2" state="hidden" '));
        expect(wb, contains('<sheet name="X" sheetId="3" state="veryHidden" '));
      });

      test('setActiveSheet on a hidden sheet throws and changes nothing', () {
        for (final XlsxSheetVisibility v in <XlsxSheetVisibility>[
          XlsxSheetVisibility.hidden,
          XlsxSheetVisibility.veryHidden,
        ]) {
          final XlsxWriter book = XlsxWriter();
          final XlsxSheetWriter a = book.addSheet('A');
          final XlsxSheetWriter b = book.addSheet('B');
          final XlsxSheetWriter hidden = book.addSheet('H', visibility: v);
          book.setActiveSheet(b);
          expect(() => book.setActiveSheet(hidden), throwsArgumentError);
          expect(a.name, 'A');
          expect(workbookXml(book), contains('<workbookView activeTab="1"/>'));
        }
      });

      test('the first visible tab is active when the first is hidden', () {
        final XlsxWriter book = XlsxWriter();
        book.addSheet('H', visibility: XlsxSheetVisibility.hidden);
        book.addSheet('X', visibility: XlsxSheetVisibility.veryHidden);
        book.addSheet('V');
        final String wb = workbookXml(book);
        expect(wb, contains('<workbookView activeTab="2"/>'));
      });

      test('tab order decides which visible tab is first', () {
        final XlsxWriter book = XlsxWriter();
        book.addSheet('H', visibility: XlsxSheetVisibility.hidden);
        book.addSheet('V');
        book.addSheet('First', position: 0);
        expect(workbookXml(book), contains('<workbookView activeTab="0"/>'));
      });

      test('close with every sheet hidden throws and can be retried', () {
        final XlsxWriter book = XlsxWriter();
        book.addSheet('H', visibility: XlsxSheetVisibility.hidden).row(
          <Object?>[1],
        );
        expect(
          book.close,
          throwsA(
            isA<StateError>().having(
              (StateError e) => e.message,
              'message',
              contains('visible'),
            ),
          ),
        );
        book.addSheet('V');
        final XlsxResult out = book.close();
        expect(checkXlsx(out.bytes), isEmpty);
        final Map<String, String> parts = readXlsx(out.bytes);
        expect(
          parts['xl/workbook.xml'],
          allOf(
            contains('state="hidden"'),
            matches(RegExp('name="H".*name="V"')),
            contains('<workbookView activeTab="1"/>'),
          ),
        );
        expect(parts['xl/worksheets/sheet1.xml'], contains('<row r="1">'));
      });

      test('the stream writer retries to the bytes XlsxWriter makes', () {
        void script(XlsxWriterBase book, void Function() tryClose) {
          book.addSheet('H', visibility: XlsxSheetVisibility.veryHidden).row(
            <Object?>['x'],
          );
          book.addSheet('H2', visibility: XlsxSheetVisibility.hidden);
          tryClose();
          book.addSheet('V').row(<Object?>[1]);
        }

        final _CollectingSink sink = _CollectingSink();
        final XlsxStreamWriter stream = XlsxStreamWriter(sink);
        script(stream, () {
          expect(stream.close, throwsStateError);
          expect(sink.closed, isFalse);
        });
        stream.close();
        expect(sink.closed, isTrue);

        final XlsxWriter memory = XlsxWriter();
        script(memory, () => expect(memory.close, throwsStateError));
        expect(sink.bytes, memory.close().bytes);
        expect(checkXlsx(sink.bytes), isEmpty);
      });

      test('a hidden sheet still takes rows', () {
        final XlsxWriter book = XlsxWriter();
        book.addSheet('V');
        book.addSheet('H', visibility: XlsxSheetVisibility.hidden).row(
          <Object?>['x'],
        );
        final XlsxResult out = book.close();
        expect(
          readXlsx(out.bytes)['xl/worksheets/sheet2.xml'],
          contains('<row'),
        );
        expect(checkXlsx(out.bytes), isEmpty);
      });
    });
  });

  group('merged cells and autofilter', () {
    String sheetXml(XlsxWriter book, [int n = 1]) =>
        readXlsx(book.close().bytes)['xl/worksheets/sheet$n.xml']!;

    String workbookXml(XlsxWriter book) =>
        readXlsx(book.close().bytes)['xl/workbook.xml']!;

    test('writes the filter and the merges in the trailer', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet("Bob's Data")
        ..row(<Object?>['Title'])
        ..autoFilter(XlsxRange.parse('A6:D20'))
        ..merge(XlsxRange.parse('A1:D1'))
        ..merge(XlsxRange.parse('B3:C4'));
      final XlsxResult out = book.close();
      final Map<String, String> parts = readXlsx(out.bytes);
      expect(
        parts['xl/worksheets/sheet1.xml'],
        endsWith(
          '</sheetData><autoFilter ref="A6:D20"/><mergeCells count="2">'
          '<mergeCell ref="A1:D1"/><mergeCell ref="B3:C4"/></mergeCells>'
          '</worksheet>',
        ),
      );
      expect(
        parts['xl/workbook.xml'],
        contains(
          '</sheets><definedNames><definedName name="_xlnm._FilterDatabase" '
          'localSheetId="0" hidden="1">\'Bob\'\'s Data\'!\$A\$6:\$D\$20'
          '</definedName></definedNames>',
        ),
      );
      expect(checkXlsx(out.bytes), isEmpty);
    });

    test('they work after rows, on a sheet with no rows too', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S')
        ..merge(XlsxRange.parse('A1:B1'))
        ..autoFilter(XlsxRange.parse('A1:B1'));
      final String xml = sheetXml(book);
      expect(
        xml,
        contains(
          '<sheetData/><autoFilter ref="A1:B1"/><mergeCells count="1">'
          '<mergeCell ref="A1:B1"/></mergeCells></worksheet>',
        ),
      );
    });

    test('a second autoFilter replaces the first', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S')
        ..autoFilter(XlsxRange.parse('A1:B2'))
        ..autoFilter(XlsxRange.parse('C3:D4'));
      final XlsxResult out = book.close();
      final Map<String, String> parts = readXlsx(out.bytes);
      expect(
        parts['xl/worksheets/sheet1.xml'],
        contains('<autoFilter ref="C3:D4"/>'),
      );
      expect(parts['xl/worksheets/sheet1.xml'], isNot(contains('A1:B2')));
      expect(parts['xl/workbook.xml'], contains(r"'S'!$C$3:$D$4"));
      expect(
        RegExp('_FilterDatabase').allMatches(parts['xl/workbook.xml']!),
        hasLength(1),
      );
    });

    test('localSheetId is the final tab index', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('Filtered').autoFilter(XlsxRange.parse('A1:B2'));
      book.addSheet('Front', position: 0);
      final String wb = workbookXml(book);
      expect(wb, contains('localSheetId="1"'));
      expect(wb, contains(r"'Filtered'!$A$1:$B$2"));
    });

    test(
      'a hidden filtered sheet keeps its localSheetId after a front sheet',
      () {
        final XlsxWriter book = XlsxWriter();
        book.addSheet('Shown').row(<Object?>[1]);
        book.addSheet('Hid', visibility: XlsxSheetVisibility.hidden)
          ..row(<Object?>[1])
          ..autoFilter(XlsxRange.parse('A1:B2'));
        book.addSheet('Front', position: 0);
        final String wb = workbookXml(book);
        // Tabs are Front, Shown, Hid.
        expect(wb, contains('localSheetId="2"'));
        expect(wb, contains(r"'Hid'!$A$1:$B$2"));
      },
    );

    test('only the filtered sheet gets a defined name', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('Plain').row(<Object?>[1]);
      book.addSheet('Filtered').autoFilter(XlsxRange.parse('A1:B2'));
      book.addSheet('Plain 2').row(<Object?>[1]);
      final String wb = workbookXml(book);
      expect(RegExp('<definedName ').allMatches(wb), hasLength(1));
      expect(wb, contains('localSheetId="1"'));
    });

    test('overlapping merges throw naming both ranges, the first stays', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter s = book.addSheet('S')
        ..merge(XlsxRange.parse('A1:B2'));
      expect(
        () => s.merge(XlsxRange.parse('B2:C3')),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.toString(),
            'message',
            allOf(contains('B2:C3'), contains('A1:B2')),
          ),
        ),
      );
      s.merge(XlsxRange.parse('C3:D4'));
      final String xml = sheetXml(book);
      expect(
        xml,
        contains(
          '<mergeCells count="2"><mergeCell ref="A1:B2"/>'
          '<mergeCell ref="C3:D4"/></mergeCells>',
        ),
      );
    });

    test('the same range twice overlaps', () {
      final XlsxSheetWriter s = XlsxWriter().addSheet('S')
        ..merge(XlsxRange.parse('A1:B2'));
      expect(() => s.merge(XlsxRange.parse('A1:B2')), throwsArgumentError);
    });

    test('touching merges do not overlap', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S')
        ..merge(XlsxRange.parse('A1:B2'))
        ..merge(XlsxRange.parse('C1:D2'))
        ..merge(XlsxRange.parse('A3:B4'));
      expect(checkXlsx(book.close().bytes), isEmpty);
    });

    test('invalid merges throw ArgumentError and record nothing', () {
      for (final XlsxRange bad in <XlsxRange>[
        const XlsxRange(0, 0),
        XlsxRange.parse('C3'),
        const XlsxRange(0, 0, 1048576, 1),
        const XlsxRange(0, 0, 1, 16384),
        const XlsxRange(-1, 0, 1, 1),
        const XlsxRange(5, 5, 1, 1),
        const XlsxRange(1, 1, 0, 3),
      ]) {
        final XlsxWriter book = XlsxWriter();
        final XlsxSheetWriter s = book.addSheet('S');
        expect(() => s.merge(bad), throwsArgumentError, reason: '$bad');
        expect(sheetXml(book), isNot(contains('mergeCell')), reason: '$bad');
      }
    });

    test('invalid autoFilter throws and keeps the earlier filter', () {
      for (final XlsxRange bad in <XlsxRange>[
        const XlsxRange(0, 0, 1048576, 1),
        const XlsxRange(0, 16384),
        const XlsxRange(5, 5, 1, 1),
      ]) {
        final XlsxWriter book = XlsxWriter();
        final XlsxSheetWriter s = book.addSheet('S')
          ..autoFilter(XlsxRange.parse('A1:B2'));
        expect(() => s.autoFilter(bad), throwsArgumentError, reason: '$bad');
        expect(sheetXml(book), contains('<autoFilter ref="A1:B2"/>'));
      }
      final XlsxWriter book = XlsxWriter();
      expect(
        () => book.addSheet('S').autoFilter(const XlsxRange(0, 0, 1048576, 0)),
        throwsArgumentError,
      );
      expect(workbookXml(book), isNot(contains('definedName')));
    });

    test('a single-cell autoFilter is allowed', () {
      final XlsxWriter book = XlsxWriter();
      book.addSheet('S').autoFilter(XlsxRange.parse('B2'));
      final XlsxResult out = book.close();
      expect(
        readXlsx(out.bytes)['xl/worksheets/sheet1.xml'],
        contains('<autoFilter ref="B2"/>'),
      );
      expect(checkXlsx(out.bytes), isEmpty);
    });

    test('after the next addSheet both throw StateError, nothing written', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter s = book.addSheet('S')..row(<Object?>[1]);
      book.addSheet('T');
      expect(() => s.merge(XlsxRange.parse('A1:B1')), throwsStateError);
      expect(() => s.autoFilter(XlsxRange.parse('A1:B1')), throwsStateError);
      final XlsxResult out = book.close();
      final Map<String, String> parts = readXlsx(out.bytes);
      expect(parts['xl/worksheets/sheet1.xml'], isNot(contains('merge')));
      expect(parts['xl/worksheets/sheet1.xml'], isNot(contains('autoFilter')));
      expect(parts['xl/workbook.xml'], isNot(contains('definedName')));
    });

    test('a state error wins over a bad range', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter s = book.addSheet('S');
      book.addSheet('T');
      expect(() => s.merge(const XlsxRange(0, 0)), throwsStateError);
    });

    test('both throw StateError after close()', () {
      final XlsxWriter book = XlsxWriter();
      final XlsxSheetWriter s = book.addSheet('S');
      book.close();
      expect(() => s.merge(XlsxRange.parse('A1:B1')), throwsStateError);
      expect(() => s.autoFilter(XlsxRange.parse('A1:B1')), throwsStateError);
    });
  });
}
