import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/formula/reference_shift.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/m4_fixtures.dart' show png4x2;
import '../../support/read_xlsx.dart';
import '../read/support/workbook_builder.dart';
import '../read/support/zip_builder.dart';
import 'support/workbook_support.dart';

const String _sheetRels = 'xl/worksheets/_rels/sheet1.xml.rels';
const String _tablePart = 'xl/tables/table1.xml';
const String _drawingPart = 'xl/drawings/drawing1.xml';
const String _mcNs =
    'http://schemas.openxmlformats.org/markup-compatibility/2006';
const String _a14Ns = 'http://schemas.microsoft.com/office/drawing/2010/main';

const String _xdr =
    'xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="$relNs"';

/// A package of the sheet `S` whose worksheet holds [body] after an empty
/// `<sheetData>`, with [rels] (raw `<Relationship>`s) for the sheet and
/// [parts] added as they are.
Uint8List _package(
  String body, {
  String rels = '',
  Map<String, String> parts = const <String, String>{},
  String? otherSheet,
}) {
  final Map<String, Uint8List> all = readXlsxBytes(
    buildWorkbook(<String, String>{
      'S':
          '<worksheet xmlns="$mainNs" xmlns:r="$relNs"><sheetData/>$body'
          '</worksheet>',
      ?otherSheet: '<worksheet xmlns="$mainNs"><sheetData/></worksheet>',
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

/// A package whose sheet has the one table [table] (raw XML).
Uint8List _withTable(String table) => _package(
  '<tableParts count="1"><tablePart r:id="rId1"/></tableParts>',
  rels:
      '<Relationship Id="rId1" Type="$relNs/table" '
      'Target="../tables/table1.xml"/>',
  parts: <String, String>{_tablePart: table},
);

/// A package whose sheet draws [anchors] (raw anchors), with a PNG as
/// `rId1` of the drawing, and a sheet [otherSheet] without a drawing after
/// it when given.
Uint8List _withDrawing(String anchors, {String? otherSheet}) => _package(
  '<drawing r:id="rId1"/>',
  rels:
      '<Relationship Id="rId1" Type="$relNs/drawing" '
      'Target="../drawings/drawing1.xml"/>',
  parts: <String, String>{
    _drawingPart: '<xdr:wsDr $_xdr>$anchors</xdr:wsDr>',
    'xl/drawings/_rels/drawing1.xml.rels':
        '<Relationships xmlns="$pkgRelNs"><Relationship Id="rId1" '
        'Type="$relNs/image" Target="../media/image1.png"/></Relationships>',
  },
  otherSheet: otherSheet,
);

ChangeSet _edit(XlsxWorkbook book, ReferenceShift edit) => changeLogOf(
  book,
).transaction(() => referenceRegistryOf(book).apply(edit, edit));

ReferenceShift _insertRows(int index, int count) =>
    ReferenceShift.insert('S', ShiftAxis.rows, index, count);

ReferenceShift _deleteRows(int index, int count) =>
    ReferenceShift.delete('S', ShiftAxis.rows, index, count);

ReferenceShift _deleteColumns(int index, int count) =>
    ReferenceShift.delete('S', ShiftAxis.columns, index, count);

Map<String, String> _saved(XlsxWorkbook book) => readXlsx(book.save().bytes);

String _table({
  String ref = 'A1:B4',
  String columns =
      '<tableColumn id="1" name="A"/><tableColumn id="2" name="B">'
      '<calculatedColumnFormula>A4*2</calculatedColumnFormula>'
      '<totalsRowFormula>SUM(A2:A4)</totalsRowFormula></tableColumn>',
  int count = 2,
  String filter = '',
}) =>
    '<table xmlns="$mainNs" id="1" name="T" displayName="T" ref="$ref">'
    '<autoFilter ref="$ref">$filter</autoFilter>'
    '<tableColumns count="$count">$columns</tableColumns>'
    '<tableStyleInfo name="TableStyleMedium2" showRowStripes="1"/></table>';

String _marker(
  String name,
  int col,
  int row, {
  int colOff = 0,
  int rowOff = 0,
}) =>
    '<xdr:$name><xdr:col>$col</xdr:col><xdr:colOff>$colOff</xdr:colOff>'
    '<xdr:row>$row</xdr:row><xdr:rowOff>$rowOff</xdr:rowOff></xdr:$name>';

String _pic(int id) =>
    '<xdr:pic><xdr:nvPicPr><xdr:cNvPr id="$id" name="Picture $id"/>'
    '<xdr:cNvPicPr/></xdr:nvPicPr><xdr:blipFill><a:blip r:embed="rId1"/>'
    '</xdr:blipFill><xdr:spPr/></xdr:pic>';

void main() {
  test('table grows with an insert inside', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _withTable(
        _table(
          filter:
              '<sortState ref="A2:B4"><sortCondition ref="B2:B4"/></sortState>',
        ),
      ),
    );
    _edit(book, _insertRows(3, 2));
    expect(
      _saved(book)[_tablePart],
      '<table xmlns="$mainNs" id="1" name="T" displayName="T" ref="A1:B6">'
      '<autoFilter ref="A1:B6"><sortState ref="A2:B6">'
      '<sortCondition ref="B2:B6"/></sortState></autoFilter>'
      '<tableColumns count="2"><tableColumn id="1" name="A"/>'
      '<tableColumn id="2" name="B">'
      '<calculatedColumnFormula>A6*2</calculatedColumnFormula>'
      '<totalsRowFormula>SUM(A2:A6)</totalsRowFormula></tableColumn>'
      '</tableColumns>'
      '<tableStyleInfo name="TableStyleMedium2" showRowStripes="1"/></table>',
    );
    expect(book.sheets.single.tables.single.range, XlsxRange.parse('A1:B6'));
  });

  test('inserting right below a table does not grow it', () {
    final Uint8List input = _withTable(_table());
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    _edit(book, _insertRows(5, 3));
    expect(_saved(book)[_tablePart], readXlsx(input)[_tablePart]);
    _edit(book, _insertRows(1, 1));
    expect(book.sheets.single.tables.single.range, XlsxRange.parse('A2:B5'));
  });

  test('deleting every body row keeps one empty row', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_withTable(_table()));
    _edit(book, _deleteRows(2, 3));
    expect(book.sheets.single.tables.single.range, XlsxRange.parse('A1:B2'));
    expect(_saved(book)[_tablePart], contains('<autoFilter ref="A1:B2">'));
    // The header row cannot go while body rows stay (Excel refuses).
    expect(() => _edit(book, _deleteRows(1, 1)), throwsStateError);
    expect(book.sheets.single.tables.single.range, XlsxRange.parse('A1:B2'));
    // Every row of the table deleted: the table goes.
    _edit(book, _deleteRows(1, 2));
    expect(book.sheets.single.tables, isEmpty);
    final Map<String, String> saved = _saved(book);
    expect(saved.containsKey(_tablePart), isFalse);
    expect(saved['xl/worksheets/sheet1.xml'], isNot(contains('tablePart')));
  });

  test('deleting a table column drops tableColumn', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _withTable(
        _table(
          ref: 'A1:C3',
          count: 3,
          columns:
              '<tableColumn id="1" name="X"/><tableColumn id="2" name="Y"/>'
              '<tableColumn id="3" name="Z"/>',
          filter:
              '<filterColumn colId="2"><filters><filter val="1"/>'
              '</filters></filterColumn>',
        ),
      ),
    );
    _edit(book, _deleteColumns(2, 1));
    expect(
      _saved(book)[_tablePart],
      '<table xmlns="$mainNs" id="1" name="T" displayName="T" ref="A1:B3">'
      '<autoFilter ref="A1:B3"><filterColumn colId="1"><filters>'
      '<filter val="1"/></filters></filterColumn></autoFilter>'
      '<tableColumns count="2"><tableColumn id="1" name="X"/>'
      '<tableColumn id="3" name="Z"/></tableColumns>'
      '<tableStyleInfo name="TableStyleMedium2" showRowStripes="1"/></table>',
    );
    final XlsxTable table = book.sheets.single.tables.single;
    expect(table.columns.map((XlsxTableColumn c) => c.name), <String>[
      'X',
      'Z',
    ]);
  });

  test("notes move, VML anchor follows, a deleted cell's note goes", () {
    final XlsxWorkbook book = XlsxWorkbook.open(_package(''));
    final XlsxSheet sheet = book.sheets.single;
    sheet.setNote(1, 1, XlsxNote.plain('gone', author: 'a'));
    sheet.setNote(4, 1, XlsxNote.plain('moved', author: 'a'));
    final String before = _saved(book)['xl/drawings/vmlDrawing1.vml']!;
    final RegExp anchor = RegExp(r'<x:Anchor>([^<]*)</x:Anchor>');
    final List<int> moved = anchor
        .allMatches(before)
        .last[1]!
        .split(',')
        .map((String s) => int.parse(s.trim()))
        .toList();
    _edit(book, _deleteRows(2, 1));
    expect(
      sheet.notes.map((XlsxCellNote n) => (n.row, n.column, n.note.text.text)),
      <(int, int, String)>[(3, 1, 'moved')],
    );
    final Map<String, String> saved = _saved(book);
    expect(saved['xl/comments1.xml'], contains('ref="B4"'));
    expect(saved['xl/comments1.xml'], isNot(contains('gone')));
    final String vml = saved['xl/drawings/vmlDrawing1.vml']!;
    expect(vml, contains('<x:Row>3</x:Row>'));
    expect(vml, isNot(contains('<x:Row>1</x:Row>')));
    final List<int> after = anchor
        .firstMatch(vml)![1]!
        .split(',')
        .map((String s) => int.parse(s.trim()))
        .toList();
    expect(after, <int>[
      moved[0],
      moved[1],
      moved[2] - 1,
      moved[3],
      moved[4],
      moved[5],
      moved[6] - 1,
      moved[7],
    ]);
  });

  test('reverting a shift restores tables, notes and anchors', () {
    final Map<String, Uint8List> parts =
        readXlsxBytes(
            _withDrawing(
              '<xdr:oneCellAnchor>${_marker('from', 1, 2)}'
              '<xdr:ext cx="95250" cy="190500"/>${_pic(3)}<xdr:clientData/>'
              '</xdr:oneCellAnchor>',
            ),
          )
          ..[_tablePart] = Uint8List.fromList(utf8.encode(_table(ref: 'D1:E4')))
          ..[_sheetRels] = Uint8List.fromList(
            utf8.encode(
              '<Relationships xmlns="$pkgRelNs"><Relationship Id="rId1" '
              'Type="$relNs/drawing" Target="../drawings/drawing1.xml"/>'
              '<Relationship Id="rId2" Type="$relNs/table" '
              'Target="../tables/table1.xml"/></Relationships>',
            ),
          );
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildZip(<String, List<int>>{...parts}),
    );
    book.sheets.single.setNote(4, 0, XlsxNote.plain('n'));
    final Uint8List before = book.save().bytes;
    final ChangeSet set = _edit(book, _deleteRows(2, 2));
    expect(comparePackages(before, book.save().bytes), isNotEmpty);
    changeLogOf(book).revertSet(set);
    expect(comparePackages(before, book.save().bytes), isEmpty);
  });

  test('an insert that would push a one-cell anchor off the sheet refuses', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _withDrawing(
        '<xdr:oneCellAnchor>${_marker('from', 1, 2)}'
        '<xdr:ext cx="1" cy="1"/>${_pic(2)}<xdr:clientData/>'
        '</xdr:oneCellAnchor>'
        '<xdr:twoCellAnchor editAs="oneCell">'
        '${_marker('from', 0, XlsxLimits.maxRows - 3)}'
        '${_marker('to', 1, XlsxLimits.maxRows - 1)}${_pic(3)}'
        '<xdr:clientData/></xdr:twoCellAnchor>',
      ),
    );
    final Uint8List before = book.save().bytes;
    expect(() => _edit(book, _insertRows(1, 1)), throwsStateError);
    expect(comparePackages(before, book.save().bytes), isEmpty);
  });

  test('an insert that would push a two-cell anchor off the sheet refuses', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _withDrawing(
        '<xdr:twoCellAnchor>${_marker('from', 0, 0)}'
        '${_marker('to', XlsxLimits.maxColumns - 1, 3, colOff: 5)}${_pic(2)}'
        '<xdr:clientData/></xdr:twoCellAnchor>',
      ),
    );
    final Uint8List before = book.save().bytes;
    expect(
      () => _edit(book, ReferenceShift.insert('S', ShiftAxis.columns, 2, 1)),
      throwsStateError,
    );
    expect(comparePackages(before, book.save().bytes), isEmpty);
  });

  test('an offset that is not whole pixels is kept byte for byte', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      _withDrawing(
        '<xdr:oneCellAnchor>${_marker('from', 1, 2, colOff: 12345, rowOff: 7)}'
        '<xdr:ext cx="1" cy="1"/>${_pic(2)}<xdr:clientData/>'
        '</xdr:oneCellAnchor>',
      ),
    );
    _edit(book, _insertRows(1, 2));
    expect(
      _saved(book)[_drawingPart],
      contains(_marker('from', 1, 4, colOff: 12345, rowOff: 7)),
    );
  });

  test('an insert that would push a note off the sheet refuses', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_package(''));
    final XlsxSheet sheet = book.sheets.single;
    sheet.setNote(XlsxLimits.maxRows - 1, 0, XlsxNote.plain('last'));
    final Map<String, String> before = _saved(book);
    expect(() => _edit(book, _insertRows(5, 1)), throwsStateError);
    expect(_saved(book), before);
  });

  test('two-cell anchor resizes, one-cell moves, absolute stays', () {
    const String absolute =
        '<xdr:absoluteAnchor><xdr:pos x="0" y="0"/>'
        '<xdr:ext cx="1" cy="1"/><xdr:sp><xdr:nvSpPr><xdr:cNvPr id="9" '
        'name="Abs"/><xdr:cNvSpPr/></xdr:nvSpPr><xdr:spPr/></xdr:sp>'
        '<xdr:clientData/></xdr:absoluteAnchor>';
    final Uint8List input = _withDrawing(
      '<xdr:twoCellAnchor>${_marker('from', 0, 0)}'
      '${_marker('to', 3, 4, colOff: 5, rowOff: 5)}${_pic(2)}<xdr:clientData/>'
      '</xdr:twoCellAnchor>'
      '<xdr:oneCellAnchor>${_marker('from', 1, 2)}'
      '<xdr:ext cx="95250" cy="190500"/>${_pic(3)}<xdr:clientData/>'
      '</xdr:oneCellAnchor>'
      '<xdr:twoCellAnchor editAs="oneCell">${_marker('from', 0, 3)}'
      '${_marker('to', 1, 5)}${_pic(4)}<xdr:clientData/>'
      '</xdr:twoCellAnchor>'
      '$absolute',
    );
    final Map<String, Uint8List> parts = readXlsxBytes(input)
      ..['xl/media/image1.png'] = png4x2;
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildZip(<String, List<int>>{...parts}),
    );
    _edit(book, _insertRows(2, 2));
    String drawing = _saved(book)[_drawingPart]!;
    expect(
      drawing,
      contains(
        '<xdr:twoCellAnchor>${_marker('from', 0, 0)}'
        '${_marker('to', 3, 6, colOff: 5, rowOff: 5)}',
      ),
    );
    expect(drawing, contains('<xdr:oneCellAnchor>${_marker('from', 1, 4)}'));
    expect(
      drawing,
      contains(
        '<xdr:twoCellAnchor editAs="oneCell">${_marker('from', 0, 5)}'
        '${_marker('to', 1, 7)}',
      ),
    );
    expect(drawing, contains(absolute));
    // The rows of the two-cell picture's bottom part deleted: it shrinks.
    // Deleting every row under the editAs="oneCell" picture moves it whole.
    _edit(book, _deleteRows(3, 5));
    drawing = _saved(book)[_drawingPart]!;
    expect(
      drawing,
      contains(
        '<xdr:twoCellAnchor>${_marker('from', 0, 0)}${_marker('to', 3, 2, colOff: 5)}',
      ),
    );
    expect(drawing, contains('<xdr:oneCellAnchor>${_marker('from', 1, 2)}'));
    expect(
      drawing,
      contains(
        '<xdr:twoCellAnchor editAs="oneCell">${_marker('from', 0, 2)}'
        '${_marker('to', 1, 4)}',
      ),
    );
    expect(book.sheets.single.pictures, hasLength(3));
    // A picture whose cells are all deleted is kept, at zero height.
    _edit(book, _deleteRows(1, 2));
    drawing = _saved(book)[_drawingPart]!;
    expect(
      drawing,
      contains(
        '<xdr:twoCellAnchor>${_marker('from', 0, 0)}${_marker('to', 3, 0, colOff: 5)}',
      ),
    );
    expect(book.sheets.single.pictures, hasLength(3));
    expect(drawing, contains(absolute));
  });

  test('a shape and a chart anchor move like pictures', () {
    const String chartBody =
        '<xdr:graphicFrame macro=""><xdr:nvGraphicFramePr>'
        '<xdr:cNvPr id="5" name="Chart 1"/><xdr:cNvGraphicFramePr/>'
        '</xdr:nvGraphicFramePr><xdr:xfrm/><a:graphic><a:graphicData '
        'uri="urn:chart"><c:chart xmlns:c="urn:c" r:id="rId7"/>'
        '</a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/>';
    const String shapeBody =
        '<xdr:ext cx="1" cy="1"/><xdr:sp macro="" textlink="">'
        '<xdr:nvSpPr><xdr:cNvPr id="6" name="Rect"/><xdr:cNvSpPr/>'
        '</xdr:nvSpPr><xdr:spPr/></xdr:sp><xdr:clientData/>';
    final XlsxWorkbook book = XlsxWorkbook.open(
      _withDrawing(
        '<xdr:twoCellAnchor>${_marker('from', 2, 1)}${_marker('to', 4, 3)}'
        '$chartBody</xdr:twoCellAnchor>'
        '<xdr:oneCellAnchor>${_marker('from', 3, 5)}$shapeBody'
        '</xdr:oneCellAnchor>',
      ),
    );
    _edit(book, _deleteColumns(1, 1));
    expect(
      _saved(book)[_drawingPart],
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<xdr:wsDr $_xdr>'
      '<xdr:twoCellAnchor>${_marker('from', 1, 1)}${_marker('to', 3, 3)}'
      '$chartBody</xdr:twoCellAnchor>'
      '<xdr:oneCellAnchor>${_marker('from', 2, 5)}$shapeBody'
      '</xdr:oneCellAnchor></xdr:wsDr>',
    );
  });

  // The structure of an equation text box as ECMA-376 and Microsoft describe
  // it: the whole anchor wrapped in mc:AlternateContent, an a14 choice and a
  // fallback. Moved by the standard's rules; Excel's own behaviour is to be
  // confirmed by the owner's equations_shifted.xlsx (W6 check).
  group('anchors inside mc:AlternateContent', () {
    const String body =
        '<xdr:sp macro="" textlink=""><xdr:nvSpPr>'
        '<xdr:cNvPr id="7" name="TextBox 6"/><xdr:cNvSpPr txBox="1"/>'
        '</xdr:nvSpPr><xdr:spPr/></xdr:sp><xdr:clientData/>';
    String wrapped(int from, int to, {int toRow = 4}) =>
        '<mc:AlternateContent xmlns:mc="$_mcNs"><mc:Choice '
        'xmlns:a14="$_a14Ns" Requires="a14"><xdr:twoCellAnchor>'
        '${_marker('from', from, 2)}${_marker('to', to, toRow)}$body'
        '</xdr:twoCellAnchor></mc:Choice><mc:Fallback><xdr:twoCellAnchor>'
        '${_marker('from', from, 2)}${_marker('to', to, toRow)}$body'
        '</xdr:twoCellAnchor></mc:Fallback></mc:AlternateContent>';
    String saved(String anchors) =>
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<xdr:wsDr $_xdr>$anchors</xdr:wsDr>';

    test('an anchor inside mc:AlternateContent moves like a bare one', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_withDrawing(wrapped(4, 7)));
      _edit(book, ReferenceShift.insert('S', ShiftAxis.columns, 1, 1));
      expect(_saved(book)[_drawingPart], saved(wrapped(5, 8)));
    });

    test('a wrapped oneCellAnchor moves and keeps its extent', () {
      String oneCell(int row) =>
          '<mc:AlternateContent xmlns:mc="$_mcNs"><mc:Choice '
          'xmlns:a14="$_a14Ns" Requires="a14"><xdr:oneCellAnchor>'
          '${_marker('from', 1, row, rowOff: 12700)}'
          '<xdr:ext cx="914400" cy="457200"/>$body</xdr:oneCellAnchor>'
          '</mc:Choice><mc:Fallback><xdr:oneCellAnchor>'
          '${_marker('from', 1, row, rowOff: 12700)}'
          '<xdr:ext cx="914400" cy="457200"/>$body</xdr:oneCellAnchor>'
          '</mc:Fallback></mc:AlternateContent>';
      final XlsxWorkbook book = XlsxWorkbook.open(_withDrawing(oneCell(6)));
      _edit(book, _insertRows(2, 3));
      expect(_saved(book)[_drawingPart], saved(oneCell(9)));
      _edit(book, _deleteRows(1, 2));
      expect(_saved(book)[_drawingPart], saved(oneCell(7)));
    });

    test('a wrapped anchor pushed off the sheet refuses, nothing changed', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _withDrawing(wrapped(4, XlsxLimits.maxColumns - 1)),
      );
      final Uint8List before = book.save().bytes;
      expect(
        () => _edit(book, ReferenceShift.insert('S', ShiftAxis.columns, 1, 1)),
        throwsStateError,
      );
      expect(comparePackages(before, book.save().bytes), isEmpty);
    });

    test('an mc:AlternateContent holding no anchor warns referenceNotShifted '
        'once and stays', () {
      const String noAnchor =
          '<mc:AlternateContent xmlns:mc="$_mcNs"><mc:Choice '
          'xmlns:a14="$_a14Ns" Requires="a14"><a14:foo/></mc:Choice>'
          '</mc:AlternateContent>';
      // A choice holding an anchor and something else stays whole too.
      final String mixed =
          '<mc:AlternateContent xmlns:mc="$_mcNs"><mc:Choice '
          'xmlns:a14="$_a14Ns" Requires="a14"><xdr:twoCellAnchor>'
          '${_marker('from', 4, 2)}${_marker('to', 7, 4)}$body'
          '</xdr:twoCellAnchor><a14:foo/></mc:Choice></mc:AlternateContent>';
      final String anchors = '$noAnchor$mixed$noAnchor';
      final XlsxWorkbook book = XlsxWorkbook.open(_withDrawing(anchors));
      final List<XlsxWarning> warnings = referenceRegistryOf(
        book,
      ).apply(_insertRows(1, 1), _insertRows(1, 1));
      expect(warnings, hasLength(1));
      expect(warnings.single.code, XlsxWarningCode.referenceNotShifted);
      expect(warnings.single.sheet, 'S');
      expect(warnings.single.detail, '/$_drawingPart: insert S!1:1');
      expect(book.warnings, contains(warnings.single));
      expect(_saved(book)[_drawingPart], '<xdr:wsDr $_xdr>$anchors</xdr:wsDr>');
    });

    test('each branch moves by the bare rules: an absolute Choice stays, the '
        'Fallback moves', () {
      String branch(String editAs, int row) =>
          '<xdr:twoCellAnchor editAs="$editAs">'
          '${_marker('from', 1, row)}${_marker('to', 3, row + 2)}$body'
          '</xdr:twoCellAnchor>';
      String entry(String choice, String fallback) =>
          '<mc:AlternateContent xmlns:mc="$_mcNs"><mc:Choice '
          'xmlns:a14="$_a14Ns" Requires="a14">$choice</mc:Choice>'
          '<mc:Fallback>$fallback</mc:Fallback></mc:AlternateContent>';
      final XlsxWorkbook book = XlsxWorkbook.open(
        _withDrawing(entry(branch('absolute', 4), branch('twoCell', 4))),
      );
      _edit(book, _insertRows(1, 2));
      expect(
        _saved(book)[_drawingPart],
        saved(entry(branch('absolute', 4), branch('twoCell', 6))),
      );
    });

    test("undo of a wrapped anchor's move restores the drawing byte-equal", () {
      final String anchors =
          '${wrapped(4, 7)}<xdr:twoCellAnchor>'
          '${_marker('from', 0, 0)}${_marker('to', 2, 3)}${_pic(2)}'
          '<xdr:clientData/></xdr:twoCellAnchor>';
      final XlsxWorkbook book = XlsxWorkbook.open(_withDrawing(anchors));
      final Uint8List before = book.save().bytes;
      final ChangeSet set = _edit(
        book,
        ReferenceShift.delete('S', ShiftAxis.columns, 1, 1),
      );
      expect(_saved(book)[_drawingPart], contains(wrapped(3, 6)));
      changeLogOf(book).revertSet(set);
      expect(_saved(book)[_drawingPart], '<xdr:wsDr $_xdr>$anchors</xdr:wsDr>');
      expect(comparePackages(before, book.save().bytes), isEmpty);
    });
  });

  // Shapes and icons (docs/shapes.md). Hand-made XML as ECMA-376 and
  // Microsoft describe it; no owner file confirms these yet.
  group('shapes and icons', () {
    const String shapeBody =
        '<xdr:sp macro="" textlink=""><xdr:nvSpPr>'
        '<xdr:cNvPr id="2" name="Oval 1"/><xdr:cNvSpPr/></xdr:nvSpPr>'
        '<xdr:spPr><a:prstGeom prst="ellipse"><a:avLst/></a:prstGeom>'
        '<a:solidFill><a:srgbClr val="FF0000"/></a:solidFill></xdr:spPr>'
        '<xdr:txBody><a:bodyPr/><a:p><a:r><a:t>Oval</a:t></a:r></a:p>'
        '</xdr:txBody></xdr:sp><xdr:clientData/>';
    const String connectorBody =
        '<xdr:cxnSp macro=""><xdr:nvCxnSpPr>'
        '<xdr:cNvPr id="3" name="Straight Connector 2"/><xdr:cNvCxnSpPr>'
        '<a:stCxn id="2" idx="6"/></xdr:cNvCxnSpPr></xdr:nvCxnSpPr>'
        '<xdr:spPr><a:prstGeom prst="line"><a:avLst/></a:prstGeom>'
        '</xdr:spPr></xdr:cxnSp><xdr:clientData/>';
    const String groupBody =
        '<xdr:grpSp><xdr:nvGrpSpPr><xdr:cNvPr id="4" name="Group 3"/>'
        '<xdr:cNvGrpSpPr/></xdr:nvGrpSpPr><xdr:grpSpPr/>'
        '<xdr:sp macro="" textlink=""><xdr:nvSpPr>'
        '<xdr:cNvPr id="5" name="Rectangle 4"/><xdr:cNvSpPr/></xdr:nvSpPr>'
        '<xdr:spPr><a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
        '</xdr:spPr></xdr:sp></xdr:grpSp><xdr:clientData/>';
    const String iconBody =
        '<xdr:pic><xdr:nvPicPr><xdr:cNvPr id="6" name="Graphic 5"/>'
        '<xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr>'
        '</xdr:nvPicPr><xdr:blipFill><a:blip r:embed="rId1"><a:extLst>'
        '<a:ext uri="{96DAC541-7B7A-43D3-8B79-37D633B846F1}">'
        '<asvg:svgBlip xmlns:asvg='
        '"http://schemas.microsoft.com/office/drawing/2016/SVG/main" '
        'r:embed="rId2"/></a:ext></a:extLst></a:blip><a:stretch>'
        '<a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr>'
        '</xdr:pic><xdr:clientData/>';

    String anchors(int shift) =>
        '<xdr:twoCellAnchor>${_marker('from', 1, 2 + shift)}'
        '${_marker('to', 3, 5 + shift)}$shapeBody</xdr:twoCellAnchor>'
        '<xdr:twoCellAnchor>${_marker('from', 4, 2 + shift)}'
        '${_marker('to', 6, 3 + shift)}$connectorBody</xdr:twoCellAnchor>'
        '<xdr:twoCellAnchor>${_marker('from', 1, 8 + shift)}'
        '${_marker('to', 3, 10 + shift)}$groupBody</xdr:twoCellAnchor>'
        '<xdr:twoCellAnchor editAs="oneCell">'
        '${_marker('from', 5, 8 + shift)}${_marker('to', 6, 9 + shift)}'
        '$iconBody</xdr:twoCellAnchor>';

    test('a shape, a connector, a group and an icon move on an insert', () {
      final XlsxWorkbook book = XlsxWorkbook.open(_withDrawing(anchors(0)));
      _edit(book, _insertRows(1, 2));
      expect(
        _saved(book)[_drawingPart],
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<xdr:wsDr $_xdr>${anchors(2)}</xdr:wsDr>',
      );
    });

    test('an icon is listed as its PNG fallback, and removing it drops '
        'both media parts', () {
      final Map<String, Uint8List> all = readXlsxBytes(
        _withDrawing(anchors(0)),
      );
      all['xl/drawings/_rels/drawing1.xml.rels'] = Uint8List.fromList(
        utf8.encode(
          '<Relationships xmlns="$pkgRelNs"><Relationship Id="rId1" '
          'Type="$relNs/image" Target="../media/image1.png"/>'
          '<Relationship Id="rId2" Type="$relNs/image" '
          'Target="../media/image2.svg"/></Relationships>',
        ),
      );
      all['xl/media/image1.png'] = png4x2;
      all['xl/media/image2.svg'] = Uint8List.fromList(
        utf8.encode('<svg xmlns="http://www.w3.org/2000/svg"/>'),
      );
      final String types = utf8.decode(all['[Content_Types].xml']!);
      all['[Content_Types].xml'] = Uint8List.fromList(
        utf8.encode(
          types.replaceFirst(
            '<Default ',
            '<Default Extension="png" ContentType="image/png"/>'
                '<Default Extension="svg" ContentType="image/svg+xml"/>'
                '<Default ',
          ),
        ),
      );
      final XlsxWorkbook book = XlsxWorkbook.open(
        buildZip(<String, List<int>>{...all}),
      );
      final XlsxSheet sheet = book.sheets.single;
      expect(sheet.pictures.single.image.format, OfficeImageFormat.png);
      sheet.removePictureAt(0);
      final Map<String, Uint8List> saved = readXlsxBytes(book.save().bytes);
      expect(saved.keys, isNot(contains('xl/media/image1.png')));
      expect(saved.keys, isNot(contains('xl/media/image2.svg')));
    });

    // Excel stores a shape whose text is linked to a cell (select the
    // shape, type =A1 in the formula bar) as textlink="$A$1", by ECMA-376.
    // Moved by the standard's rules; Excel's own behaviour is to be
    // confirmed by the owner's shapes_shifted.xlsx (W6 check).
    String linked(String link, int row) =>
        '<xdr:twoCellAnchor>${_marker('from', 1, row)}'
        '${_marker('to', 3, row + 2)}<xdr:sp macro="" '
        'textlink="$link"><xdr:nvSpPr><xdr:cNvPr id="2" '
        'name="Rectangle 1"/><xdr:cNvSpPr/></xdr:nvSpPr><xdr:spPr>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr>'
        '</xdr:sp><xdr:clientData/></xdr:twoCellAnchor>';
    String saved(String anchors) =>
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<xdr:wsDr $_xdr>$anchors</xdr:wsDr>';

    test("a shape's textlink moves with the cell it names", () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _withDrawing(linked(r'$A$1', 4)),
      );
      _edit(book, _insertRows(1, 1));
      expect(_saved(book)[_drawingPart], saved(linked(r'$A$2', 5)));
    });

    test("a textlink to another sheet follows that sheet's insert and "
        'rename', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _withDrawing(linked(r"'Veri 2'!$B$2", 4), otherSheet: 'Veri 2'),
      );
      _edit(book, ReferenceShift.insert('Veri 2', ShiftAxis.rows, 1, 1));
      // The shape's own sheet did not change, so it stays where it is.
      expect(_saved(book)[_drawingPart], saved(linked(r"'Veri 2'!$B$3", 4)));
      book.renameSheet(book.sheet('Veri 2'), 'Veri 3');
      expect(_saved(book)[_drawingPart], saved(linked(r"'Veri 3'!$B$3", 4)));
    });

    test('a textlink whose cell is deleted becomes #REF!', () {
      final XlsxWorkbook book = XlsxWorkbook.open(
        _withDrawing(linked(r'$A$3', 4)),
      );
      _edit(book, _deleteRows(3, 1));
      expect(_saved(book)[_drawingPart], saved(linked('#REF!', 3)));
    });

    test('an empty textlink is left as written', () {
      final String drawing = anchors(0);
      final XlsxWorkbook book = XlsxWorkbook.open(_withDrawing(drawing));
      book.renameSheet(book.sheets.single, 'T');
      expect(_saved(book)[_drawingPart], '<xdr:wsDr $_xdr>$drawing</xdr:wsDr>');
      _edit(book, ReferenceShift.insert('T', ShiftAxis.columns, 10, 1));
      expect(_saved(book)[_drawingPart], '<xdr:wsDr $_xdr>$drawing</xdr:wsDr>');
    });

    test('an unlexable textlink stays and warns formulaUnlexable once', () {
      const String bad = r'$A$1+&quot;x';
      final XlsxWorkbook book = XlsxWorkbook.open(
        _withDrawing('${linked(bad, 4)}${linked(r'$A$1', 8)}'),
      );
      final List<XlsxWarning> warnings = referenceRegistryOf(
        book,
      ).apply(_insertRows(1, 1), _insertRows(1, 1));
      expect(
        _saved(book)[_drawingPart],
        saved('${linked(bad, 5)}${linked(r'$A$2', 9)}'),
      );
      final List<XlsxWarning> unlexable = warnings
          .where((XlsxWarning w) => w.code == XlsxWarningCode.formulaUnlexable)
          .toList();
      expect(unlexable, hasLength(1));
      expect(unlexable.single.detail, r'$A$1+"x');
      expect(unlexable.single.count, 1);
    });

    test('a textlink inside a wrapped anchor moves', () {
      String sp(String link) =>
          '<xdr:sp macro="" textlink="$link"><xdr:nvSpPr>'
          '<xdr:cNvPr id="7" name="TextBox 6"/><xdr:cNvSpPr txBox="1"/>'
          '</xdr:nvSpPr><xdr:spPr/></xdr:sp><xdr:clientData/>';
      String wrapped(String link, int row) =>
          '<mc:AlternateContent xmlns:mc="$_mcNs"><mc:Choice '
          'xmlns:a14="$_a14Ns" Requires="a14"><xdr:twoCellAnchor>'
          '${_marker('from', 1, row)}${_marker('to', 3, row + 2)}${sp(link)}'
          '</xdr:twoCellAnchor></mc:Choice><mc:Fallback><xdr:twoCellAnchor>'
          '${_marker('from', 1, row)}${_marker('to', 3, row + 2)}${sp(link)}'
          '</xdr:twoCellAnchor></mc:Fallback></mc:AlternateContent>';
      final XlsxWorkbook book = XlsxWorkbook.open(
        _withDrawing(wrapped(r'$A$1', 4)),
      );
      _edit(book, _insertRows(1, 2));
      expect(_saved(book)[_drawingPart], saved(wrapped(r'$A$3', 6)));
    });

    test('a textlink inside a group moves', () {
      String grouped(String link) =>
          '<xdr:absoluteAnchor><xdr:pos x="0" y="0"/>'
          '<xdr:ext cx="1" cy="1"/><xdr:grpSp><xdr:nvGrpSpPr>'
          '<xdr:cNvPr id="4" name="Group 3"/><xdr:cNvGrpSpPr/>'
          '</xdr:nvGrpSpPr><xdr:grpSpPr/><xdr:sp macro="" '
          'textlink="$link"><xdr:nvSpPr><xdr:cNvPr id="5" '
          'name="Rectangle 4"/><xdr:cNvSpPr/></xdr:nvSpPr><xdr:spPr/>'
          '</xdr:sp></xdr:grpSp><xdr:clientData/></xdr:absoluteAnchor>';
      final XlsxWorkbook book = XlsxWorkbook.open(
        _withDrawing(grouped(r'$C$5')),
      );
      _edit(book, _deleteColumns(1, 1));
      expect(_saved(book)[_drawingPart], saved(grouped(r'$B$5')));
    });

    test('a drawing that cannot be read does not block an edit of another '
        'sheet', () {
      final Uint8List input = _withDrawing(
        '<xdr:sp textlink="\$A\$1">',
        otherSheet: 'Veri 2',
      );
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final ReferenceShift insert = ReferenceShift.insert(
        'Veri 2',
        ShiftAxis.rows,
        1,
        1,
      );
      final List<XlsxWarning> warnings = referenceRegistryOf(
        book,
      ).apply(insert, insert);
      expect(warnings, hasLength(1));
      expect(warnings.single.code, XlsxWarningCode.referenceNotShifted);
      expect(warnings.single.sheet, 'Veri 2');
      expect(warnings.single.detail, '/$_drawingPart: insert Veri 2!1:1');
      book.renameSheet(book.sheet('Veri 2'), 'Veri 3');
      expect(_saved(book)[_drawingPart], readXlsx(input)[_drawingPart]);
      // An edit of the drawing's own sheet still refuses, keeping no warning.
      final List<XlsxWarning> kept = book.warnings.toList();
      expect(
        () => _edit(book, _insertRows(1, 1)),
        throwsA(isA<XlsxReadException>()),
      );
      expect(book.warnings, kept);
    });

    test('undo of a textlink rewrite restores the drawing byte-equal', () {
      final String drawing = linked(r"'Veri 2'!$B$2", 4);
      final XlsxWorkbook book = XlsxWorkbook.open(
        _withDrawing(drawing, otherSheet: 'Veri 2'),
      );
      final Uint8List before = book.save().bytes;
      final ChangeSet set = _edit(
        book,
        ReferenceShift.delete('Veri 2', ShiftAxis.columns, 1, 1),
      );
      expect(_saved(book)[_drawingPart], saved(linked(r"'Veri 2'!$A$2", 4)));
      changeLogOf(book).revertSet(set);
      expect(_saved(book)[_drawingPart], '<xdr:wsDr $_xdr>$drawing</xdr:wsDr>');
      expect(comparePackages(before, book.save().bytes), isEmpty);
    });
  });
}
