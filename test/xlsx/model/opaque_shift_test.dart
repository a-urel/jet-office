// Parts the model does not type but that hold references (W5, Ruling 9):
// what a text rewrite can fix is fixed, an edit through a pivot table
// refuses, and every other part with a reference warns
// `referenceNotShifted`, once per part per edit.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/formula/formula_rewrite.dart';
import 'package:jet_office/src/xlsx/formula/reference_shift.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';

import '../../support/read_xlsx.dart';
import '../read/support/workbook_builder.dart';
import '../read/support/zip_builder.dart';
import 'support/workbook_support.dart';

const String _sheetRels = 'xl/worksheets/_rels/sheet1.xml.rels';
const String _x14 =
    'http://schemas.microsoft.com/office/spreadsheetml/2009/9/main';
const String _xm = 'http://schemas.microsoft.com/office/excel/2006/main';
const String _tc =
    'http://schemas.microsoft.com/office/spreadsheetml/2018/threadedcomments';

/// A package of the sheet `S` (and `Other`) whose worksheet holds [body]
/// after `<sheetData>` [data], with [rels] (raw `<Relationship>`s) for the
/// sheet and [parts] added as they are.
Uint8List _package(
  String body, {
  String data = '',
  String rels = '',
  Map<String, String> parts = const <String, String>{},
}) {
  final Map<String, Uint8List> all = readXlsxBytes(
    buildWorkbook(<String, String>{
      'S':
          '<worksheet xmlns="$mainNs" xmlns:r="$relNs" xmlns:x14="$_x14" '
          'xmlns:xm="$_xm"><sheetData>$data</sheetData>$body</worksheet>',
      'Other': worksheet(''),
    }),
  );
  if (rels.isNotEmpty) {
    all[_sheetRels] = Uint8List.fromList(
      utf8.encode('<Relationships xmlns="$pkgRelNs">$rels</Relationships>'),
    );
  }
  parts.forEach((String name, String xml) {
    all[name] = Uint8List.fromList(utf8.encode(xml));
  });
  return buildZip(<String, List<int>>{...all});
}

String _rel(String id, String type, String target) =>
    '<Relationship Id="$id" Type="$type" Target="$target"/>';

({ChangeSet set, List<XlsxWarning> warnings}) _apply(
  XlsxWorkbook book,
  ReferenceMapper mapper, [
  ReferenceShift? edit,
]) {
  late List<XlsxWarning> warnings;
  final ChangeSet set = changeLogOf(
    book,
  ).transaction(() => warnings = referenceRegistryOf(book).apply(mapper, edit));
  return (set: set, warnings: warnings);
}

List<XlsxWarning> _edit(XlsxWorkbook book, ReferenceShift edit) =>
    _apply(book, edit, edit).warnings;

ReferenceShift _insertRows(int index, int count) =>
    ReferenceShift.insert('S', ShiftAxis.rows, index, count);

Map<String, String> _saved(XlsxWorkbook book) => readXlsx(book.save().bytes);

void main() {
  test('sparklines shift', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '<extLst><ext uri="{05C60535-1F16-4fd2-B633-F4F36F0B64E0}">'
        '<x14:sparklineGroups><x14:sparklineGroup displayEmptyCellsAs="gap">'
        '<x14:sparklines>'
        '<x14:sparkline><xm:f>S!A2:D2</xm:f><xm:sqref>E2</xm:sqref>'
        '</x14:sparkline>'
        '<x14:sparkline><xm:f>Other!A1:D1</xm:f><xm:sqref>E1</xm:sqref>'
        '</x14:sparkline>'
        '</x14:sparklines></x14:sparklineGroup></x14:sparklineGroups>'
        '</ext></extLst>',
      ),
    );
    expect(_edit(book, _insertRows(2, 1)), isEmpty);
    final String sheet = _saved(book)['xl/worksheets/sheet1.xml']!;
    expect(
      sheet,
      contains(
        '<x14:sparkline><xm:f>S!A3:D3</xm:f><xm:sqref>E3</xm:sqref>'
        '</x14:sparkline>'
        '<x14:sparkline><xm:f>Other!A1:D1</xm:f><xm:sqref>E1</xm:sqref>'
        '</x14:sparkline>',
      ),
    );
  });

  test('a sparkline whose cell is deleted goes, and its group with it', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '<extLst><ext uri="{05C60535-1F16-4fd2-B633-F4F36F0B64E0}">'
        '<x14:sparklineGroups><x14:sparklineGroup><x14:sparklines>'
        '<x14:sparkline><xm:f>S!A2:D2</xm:f><xm:sqref>E2</xm:sqref>'
        '</x14:sparkline></x14:sparklines></x14:sparklineGroup>'
        '<x14:sparklineGroup><x14:sparklines>'
        '<x14:sparkline><xm:f>S!A5:D5</xm:f><xm:sqref>E5</xm:sqref>'
        '</x14:sparkline></x14:sparklines></x14:sparklineGroup>'
        '</x14:sparklineGroups></ext></extLst>',
      ),
    );
    _edit(book, ReferenceShift.delete('S', ShiftAxis.rows, 2, 1));
    final String sheet = _saved(book)['xl/worksheets/sheet1.xml']!;
    expect(
      sheet,
      contains(
        '<x14:sparklineGroups><x14:sparklineGroup><x14:sparklines>'
        '<x14:sparkline><xm:f>S!A4:D4</xm:f><xm:sqref>E4</xm:sqref>'
        '</x14:sparkline></x14:sparklines></x14:sparklineGroup>'
        '</x14:sparklineGroups>',
      ),
    );
  });

  test('threaded comment ref moves with its note', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '',
        rels:
            _rel('rId1', '$relNs/comments', '../comments1.xml') +
            _rel(
              'rId2',
              'http://schemas.microsoft.com/office/2017/10/relationships/'
                  'threadedComment',
              '../threadedComments/threadedComment1.xml',
            ),
        parts: <String, String>{
          'xl/comments1.xml':
              '<comments xmlns="$mainNs"><authors><author>a</author>'
              '</authors><commentList><comment ref="B2" authorId="0"><text>'
              '<t>x</t></text></comment><comment ref="B5" authorId="0">'
              '<text><t>y</t></text></comment></commentList></comments>',
          'xl/threadedComments/threadedComment1.xml':
              '<ThreadedComments xmlns="$_tc"><threadedComment ref="B2" '
              'id="{1}" personId="{9}"><text>x</text></threadedComment>'
              '<threadedComment ref="B5" id="{2}" personId="{9}"><text>y'
              '</text></threadedComment></ThreadedComments>',
        },
      ),
    );
    expect(
      _edit(book, ReferenceShift.delete('S', ShiftAxis.rows, 2, 1)),
      isEmpty,
    );
    final Map<String, String> saved = _saved(book);
    expect(saved['xl/comments1.xml'], contains('ref="B4"'));
    expect(saved['xl/comments1.xml'], isNot(contains('ref="B2"')));
    expect(
      saved['xl/threadedComments/threadedComment1.xml'],
      '<ThreadedComments xmlns="$_tc">'
      '<threadedComment ref="B4" id="{2}" personId="{9}"><text>y'
      '</text></threadedComment></ThreadedComments>',
    );
  });

  test('ctrlProp fmlaLink shifts', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '',
        rels: _rel('rId1', '$relNs/ctrlProp', '../ctrlProps/ctrlProp1.xml'),
        parts: <String, String>{
          'xl/ctrlProps/ctrlProp1.xml':
              '<formControlPr xmlns="$_x14" objectType="Drop" '
              r'fmlaLink="$B$2" fmlaRange="Other!$A$1:$A$3" dropLines="8"/>',
        },
      ),
    );
    expect(_edit(book, _insertRows(1, 2)), isEmpty);
    expect(
      _saved(book)['xl/ctrlProps/ctrlProp1.xml'],
      '<formControlPr xmlns="$_x14" objectType="Drop" '
      r'fmlaLink="$B$4" fmlaRange="Other!$A$1:$A$3" dropLines="8"/>',
    );
  });

  test('pivot cache source shifts and renames', () {
    const String cache = 'xl/pivotCache/pivotCacheDefinition1.xml';
    String source(String ref, String sheet) =>
        '<pivotCacheDefinition xmlns="$mainNs" xmlns:r="$relNs" r:id="rId1">'
        '<cacheSource type="worksheet"><worksheetSource ref="$ref" '
        'sheet="$sheet"/></cacheSource><cacheFields count="0"/>'
        '</pivotCacheDefinition>';
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package('', parts: <String, String>{cache: source('A1:B5', 'S')}),
    );
    expect(_edit(book, _insertRows(3, 2)), isEmpty);
    expect(_saved(book)[cache], source('A1:B7', 'S'));
    expect(_apply(book, SheetRename('S', 'Sales 2')).warnings, isEmpty);
    expect(_saved(book)[cache], source('A1:B7', 'Sales 2'));
    // An edit of another sheet leaves it.
    _edit(book, ReferenceShift.insert('Other', ShiftAxis.rows, 1, 1));
    expect(_saved(book)[cache], source('A1:B7', 'Sales 2'));
  });

  group('pivot tables', () {
    const String pivot = 'xl/pivotTables/pivotTable1.xml';
    String table(String ref) =>
        '<pivotTableDefinition xmlns="$mainNs" name="P" cacheId="1">'
        '<location ref="$ref" firstHeaderRow="1" firstDataRow="1" '
        'firstDataCol="1"/></pivotTableDefinition>';
    XlsxWorkbook open() => XlsxWorkbook.open(
      _package(
        '',
        data: '<row r="1"><c r="A1"><f>SUM(A3:B7)</f></c></row>',
        rels: _rel(
          'rId1',
          '$relNs/pivotTable',
          '../pivotTables/pivotTable1.xml',
        ),
        parts: <String, String>{pivot: table('A3:B7')},
      ),
    );

    test('an edit through a pivot table refuses', () {
      final XlsxWorkbook book = open();
      final Map<String, String> before = _saved(book);
      for (final ReferenceShift edit in <ReferenceShift>[
        _insertRows(5, 1),
        ReferenceShift.delete('S', ShiftAxis.rows, 7, 2),
        ReferenceShift.delete('S', ShiftAxis.columns, 2, 1),
      ]) {
        expect(() => _edit(book, edit), throwsStateError);
        final Map<String, String> after = _saved(book);
        expect(after[pivot], before[pivot]);
        expect(after['xl/worksheets/sheet1.xml'], contains('SUM(A3:B7)'));
      }
    });

    test('an edit outside a pivot table moves it', () {
      final XlsxWorkbook book = open();
      expect(_edit(book, _insertRows(3, 1)), isEmpty);
      expect(_saved(book)[pivot], table('A4:B8'));
      _edit(book, ReferenceShift.delete('S', ShiftAxis.rows, 10, 3));
      expect(_saved(book)[pivot], table('A4:B8'));
      _edit(book, ReferenceShift.insert('S', ShiftAxis.columns, 1, 1));
      expect(_saved(book)[pivot], table('B4:C8'));
    });
  });

  test('an unknown part with a ref warns', () {
    const String thing = 'xl/custom/thing.xml';
    const String xml = '<thing xmlns="urn:x"><item ref="A1:B2"/></thing>';
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '',
        rels: _rel('rId1', 'urn:x/thing', '../custom/thing.xml'),
        parts: <String, String>{thing: xml},
      ),
    );
    final List<XlsxWarning> warnings = _edit(book, _insertRows(1, 1));
    expect(warnings, hasLength(1));
    expect(warnings.single.code, XlsxWarningCode.referenceNotShifted);
    expect(warnings.single.sheet, 'S');
    expect(warnings.single.detail, '/xl/custom/thing.xml: insert S!1:1');
    expect(book.warnings, contains(warnings.single));
    expect(_saved(book)[thing], xml);
    // An edit of another sheet does not reach it.
    expect(
      _edit(book, ReferenceShift.insert('Other', ShiftAxis.columns, 2, 2)),
      isEmpty,
    );
  });

  test('a workbook part naming the edited sheet warns', () {
    const String connections = 'xl/connections.xml';
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '',
        parts: <String, String>{
          connections:
              '<connections xmlns="$mainNs"><connection id="1" name="c">'
              '<rangePr sourceName="S!A1:B3"/><textPr sqref="S!A1"/>'
              '</connection></connections>',
        },
      ),
    );
    expect(
      _edit(
        book,
        ReferenceShift.delete('S', ShiftAxis.columns, 1, 1),
      ).map((XlsxWarning w) => w.detail),
      <String>['/xl/connections.xml: delete S!A:A'],
    );
    expect(
      _apply(
        book,
        SheetRename('S', 'T'),
      ).warnings.map((XlsxWarning w) => w.detail),
      <String>['/xl/connections.xml: rename S to T'],
    );
    expect(
      _edit(book, ReferenceShift.insert('Other', ShiftAxis.rows, 1, 1)),
      isEmpty,
    );
  });

  test('an unrelated opaque part warns nothing', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '',
        rels: _rel('rId1', 'urn:x/thing', '../custom/thing.xml'),
        parts: <String, String>{
          'xl/custom/thing.xml':
              '<thing xmlns="urn:x"><item name="A1"/></thing>',
          'xl/externalLinks/externalLink1.xml':
              '<externalLink xmlns="$mainNs"><externalBook><sheetNames>'
              '<sheetName val="S"/></sheetNames><sheetDataSet><sheetData '
              'sheetId="0"><row r="1"><cell r="A1"/></row></sheetData>'
              '</sheetDataSet></externalBook></externalLink>',
          'customXml/item1.xml': '<root ref="S!A1"/>',
        },
      ),
    );
    expect(_edit(book, _insertRows(1, 1)), isEmpty);
    expect(book.warnings, isEmpty);
  });

  test('a slicer cache naming a reshaped table warns', () {
    const String slicer = 'xl/slicerCaches/slicerCache1.xml';
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '<tableParts count="1"><tablePart r:id="rId1"/></tableParts>',
        rels: _rel('rId1', '$relNs/table', '../tables/table1.xml'),
        parts: <String, String>{
          'xl/tables/table1.xml':
              '<table xmlns="$mainNs" id="7" name="T" displayName="T" '
              'ref="A1:C4"><autoFilter ref="A1:C4"/><tableColumns count="3">'
              '<tableColumn id="1" name="A"/><tableColumn id="2" name="B"/>'
              '<tableColumn id="3" name="C"/></tableColumns></table>',
          slicer:
              '<slicerCacheDefinition xmlns="$_x14" '
              'xmlns:x15="http://schemas.microsoft.com/office/spreadsheetml/'
              '2010/11/main" name="Slicer_A" sourceName="A"><extLst>'
              '<x:ext xmlns:x="$mainNs" '
              'uri="{2F2917AC-EB37-4324-AD4E-5DD8C200BD13}">'
              '<x15:tableSlicerCache tableId="7" column="1"/></x:ext>'
              '</extLst></slicerCacheDefinition>',
        },
      ),
    );
    // A move of the table leaves the slicer's column where it was.
    expect(_edit(book, _insertRows(1, 1)), isEmpty);
    expect(
      _edit(
        book,
        ReferenceShift.delete('S', ShiftAxis.columns, 2, 1),
      ).map((XlsxWarning w) => w.detail),
      <String>['/xl/slicerCaches/slicerCache1.xml: delete S!B:B'],
    );
  });

  test('undo restores a fixed opaque part', () {
    const String ctrl = 'xl/ctrlProps/ctrlProp1.xml';
    const String xml = '<formControlPr xmlns="$_x14" fmlaLink="B2"/>';
    final XlsxWorkbook book = XlsxWorkbook.open(
      _package(
        '',
        rels: _rel('rId1', '$relNs/ctrlProp', '../ctrlProps/ctrlProp1.xml'),
        parts: <String, String>{ctrl: xml},
      ),
    );
    final ChangeSet one = _apply(
      book,
      _insertRows(1, 1),
      _insertRows(1, 1),
    ).set;
    final ChangeSet two = _apply(
      book,
      _insertRows(1, 1),
      _insertRows(1, 1),
    ).set;
    expect(_saved(book)[ctrl], contains('fmlaLink="B4"'));
    changeLogOf(book).revertSet(two);
    expect(_saved(book)[ctrl], contains('fmlaLink="B3"'));
    changeLogOf(book).revertSet(one);
    expect(_saved(book)[ctrl], xml);
  });
}
