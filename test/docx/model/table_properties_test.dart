// Tests the properties of tables, rows and cells: each member reads what a
// file holds, sets and writes the element the schema gives in its place,
// children the model does not type stay where they were, a set is one change
// that undoes and redoes, and setting what a member reads changes nothing.
// They build documents in memory, so they run on the web as well.
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:test/test.dart';

import '../../support/read_xlsx.dart';
import '../support/docx_builder.dart';
import '../support/localized_document.dart';
import '../support/styles_documents.dart';

const String _head = '<w:document xmlns:w="${Ns.w}"><w:body>';
const String _tail = '</w:body></w:document>';

/// A grid of three columns, for a span to fit.
const String _grid3 =
    '<w:tblGrid><w:gridCol w:w="100"/><w:gridCol w:w="100"/>'
    '<w:gridCol w:w="100"/></w:tblGrid>';

/// A document whose body holds [body].
DocxDocument _openBody(String body) =>
    DocxDocument.open(buildDocx(document: '$_head$body$_tail'));

/// A document of one table of one row and one cell, with the given
/// `w:tblPr`, grid, `w:trPr` and `w:tcPr` (as XML).
DocxDocument _open({
  String tblPr = '',
  String grid = '<w:tblGrid><w:gridCol w:w="100"/></w:tblGrid>',
  String trPr = '',
  String tcPr = '',
}) => _openBody(
  '<w:tbl>$tblPr$grid<w:tr>$trPr<w:tc>$tcPr<w:p/></w:tc></w:tr></w:tbl>',
);

DocxTable _table(DocxDocument doc) => doc.body.blocks.single as DocxTable;

DocxTableRow _row(DocxDocument doc) => _table(doc).rows.single;

DocxTableCell _cell(DocxDocument doc) => _row(doc).cells.single;

/// The saved `word/document.xml` of [doc] without the wrapper around the
/// table.
String _saved(DocxDocument doc) {
  final String xml = readXlsx(doc.save().bytes)['word/document.xml']!;
  final int start = xml.indexOf('<w:body>') + '<w:body>'.length;
  return xml.substring(start, xml.indexOf('</w:body>'));
}

/// The children of the element `w:<name>` of the saved document, or `''`.
String _inner(DocxDocument doc, String name) {
  final RegExpMatch? m = RegExp(
    '<w:$name(?: [^>]*)?>(.*?)</w:$name>',
  ).firstMatch(_saved(doc));
  return m == null ? '' : m.group(1)!;
}

DocxDocument _reopen(DocxDocument doc) => DocxDocument.open(doc.save().bytes);

void main() {
  group('table properties', () {
    test('read what a file holds', () {
      final DocxTableProperties p = _table(
        _open(
          tblPr:
              '<w:tblPr><w:tblStyle w:val="TableGrid"/>'
              '<w:tblW w:w="5000" w:type="pct"/><w:jc w:val="center"/>'
              '<w:tblInd w:w="108" w:type="dxa"/>'
              '<w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" '
              'w:color="auto"/></w:tblBorders>'
              '<w:tblLayout w:type="fixed"/>'
              '<w:tblCellMar><w:left w:w="108" w:type="dxa"/></w:tblCellMar>'
              '<w:tblLook w:val="04A0" w:firstRow="1" w:lastRow="0" '
              'w:firstColumn="1" w:lastColumn="0" w:noHBand="0" '
              'w:noVBand="1"/></w:tblPr>',
        ),
      ).properties;
      expect(p.style, 'TableGrid');
      expect(p.width, DocxTableWidth.percent(100));
      expect(p.alignment, DocxTableAlignment.center);
      expect(p.indentationPt, 5.4);
      expect(p.borders!.top, isNotNull);
      expect(p.layout, DocxTableLayout.fixed);
      expect(p.cellMargins, DocxTableMargins(leftPt: 5.4));
      expect(
        p.look,
        const DocxTableLook(
          firstRow: true,
          firstColumn: true,
          noVerticalBands: true,
        ),
      );
    });

    test('read null with no w:tblPr', () {
      final DocxTableProperties p = _table(_open()).properties;
      expect(p.style, isNull);
      expect(p.width, isNull);
      expect(p.layout, isNull);
      expect(p.alignment, isNull);
      expect(p.indentationPt, isNull);
      expect(p.borders, isNull);
      expect(p.cellMargins, isNull);
      expect(p.look, isNull);
    });

    test('is the same object every time', () {
      final DocxTable t = _table(_open());
      expect(identical(t.properties, t.properties), isTrue);
    });

    test('every member sets, writes in place and reads back', () {
      final DocxDocument doc = _open();
      final DocxTableProperties p = _table(doc).properties;
      p
        ..style = 'TableGrid'
        ..width = const DocxTableWidth.auto()
        ..layout = DocxTableLayout.autofit
        ..alignment = DocxTableAlignment.right
        ..indentationPt = -5
        ..borders = DocxTableBorders(top: DocxBorder())
        ..cellMargins = DocxTableMargins(topPt: 1)
        ..look = const DocxTableLook(firstRow: true);
      expect(
        _saved(doc).startsWith(
          '<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/>'
          '<w:tblW w:w="0" w:type="auto"/><w:jc w:val="right"/>'
          '<w:tblInd w:w="-100" w:type="dxa"/><w:tblBorders>',
        ),
        isTrue,
        reason: _saved(doc),
      );
      expect(_saved(doc), contains('</w:tblPr><w:tblGrid>'));
      final DocxTableProperties back = _table(_reopen(doc)).properties;
      expect(back.style, 'TableGrid');
      expect(back.width, const DocxTableWidth.auto());
      expect(back.layout, DocxTableLayout.autofit);
      expect(back.alignment, DocxTableAlignment.right);
      expect(back.indentationPt, -5);
      expect(back.borders, DocxTableBorders(top: DocxBorder()));
      expect(back.cellMargins, DocxTableMargins(topPt: 1));
      expect(back.look, const DocxTableLook(firstRow: true));
    });

    test('a w:tblPr is written before the grid and the rows', () {
      final DocxDocument doc = _open();
      _table(doc).properties.layout = DocxTableLayout.fixed;
      expect(
        _saved(doc),
        '<w:tbl><w:tblPr><w:tblLayout w:type="fixed"/></w:tblPr>'
        '<w:tblGrid><w:gridCol w:w="100"/></w:tblGrid>'
        '<w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl>',
      );
    });

    test('a w:tblPr is written before a row of a table with no grid', () {
      final DocxDocument doc = _open(grid: '');
      _table(doc).properties.layout = DocxTableLayout.fixed;
      expect(_saved(doc), startsWith('<w:tbl><w:tblPr>'));
    });

    test('style resolves as a table style in the document', () {
      final DocxDocument doc = DocxDocument.open(
        docxWithStyles(
          document:
              '$_head<w:tbl><w:tblGrid/><w:tr><w:tc><w:p/></w:tc></w:tr>'
              '</w:tbl>$_tail',
          styles: stylesXmlOf(<String>[
            styleXml('paragraph', 'Normal', 'Normal'),
            styleXml('table', 'NormalTablo', 'Normal Table'),
            styleXml('table', 'TabloKlavuzu', 'Table Grid'),
          ]),
        ),
      );
      final DocxTableProperties p = _table(doc).properties;
      p.style = 'TableGrid';
      expect(p.style, 'TabloKlavuzu');
      // A paragraph style's built-in id is not a table style.
      p.style = 'Heading1';
      expect(p.style, 'Heading1');
    });

    test('setting what it reads changes nothing', () {
      final DocxDocument doc = _open(
        tblPr:
            '<w:tblPr><w:tblStyle w:val="TableGrid"/>'
            '<w:tblW w:w="0" w:type="auto"/><w:jc w:val="center"/>'
            '<w:tblInd w:w="108" w:type="dxa"/><w:tblLayout w:type="fixed"/>'
            '</w:tblPr>',
      );
      final DocxTableProperties p = _table(doc).properties;
      p
        ..style = p.style
        ..width = p.width
        ..alignment = p.alignment
        ..indentationPt = p.indentationPt
        ..layout = p.layout
        ..borders = p.borders
        ..cellMargins = p.cellMargins
        ..look = p.look;
      expect(changeLogOf(doc).hasChanges, isFalse);
    });

    test('a set is one change and undoes', () {
      final DocxDocument doc = _open();
      final DocxTableProperties p = _table(doc).properties;
      final ChangeSet set = changeLogOf(doc).transaction(() {
        p.layout = DocxTableLayout.fixed;
      });
      expect(set.changes, hasLength(1));
      expect(p.layout, DocxTableLayout.fixed);
      changeLogOf(doc).revertSet(set);
      expect(p.layout, isNull);
      expect(_saved(doc), isNot(contains('tblPr')));
      changeLogOf(doc).reapplySet(set);
      expect(p.layout, DocxTableLayout.fixed);
      expect(_saved(doc), contains('<w:tblLayout w:type="fixed"/>'));
    });

    test('a style set is one change with the style it adds', () {
      final DocxDocument doc = DocxDocument.open(
        docxWithStyles(
          document:
              '$_head<w:tbl><w:tblGrid/><w:tr><w:tc><w:p/></w:tc></w:tr>'
              '</w:tbl>$_tail',
          styles: stylesXmlOf(<String>[
            styleXml('paragraph', 'Normal', 'Normal'),
          ]),
        ),
      );
      final ChangeSet set = changeLogOf(doc).transaction(() {
        _table(doc).properties.style = 'TableGrid';
      });
      expect(_table(doc).properties.style, 'TableGrid');
      changeLogOf(doc).revertSet(set);
      expect(_table(doc).properties.style, isNull);
      expect(doc.styles.byName('Table Grid'), isNull);
    });

    test('a child in schema order among kept ones', () {
      final DocxDocument doc = _open(
        tblPr:
            '<w:tblPr><w:tblW w:w="0" w:type="auto"/>'
            '<w:tblCellSpacing w:w="10" w:type="dxa"/>'
            '<w:tblCaption w:val="c"/></w:tblPr>',
      );
      _table(doc).properties.layout = DocxTableLayout.fixed;
      expect(
        _inner(doc, 'tblPr'),
        '<w:tblW w:w="0" w:type="auto"/>'
        '<w:tblCellSpacing w:w="10" w:type="dxa"/>'
        '<w:tblLayout w:type="fixed"/><w:tblCaption w:val="c"/>',
      );
    });

    test('a null removes the child and clear removes what it cannot read', () {
      final DocxDocument doc = _open(
        tblPr:
            '<w:tblPr><w:tblLayout w:type="fixed"/>'
            '<w:tblInd w:w="1in" w:type="dxa"/></w:tblPr>',
      );
      final DocxTableProperties p = _table(doc).properties;
      p.layout = null;
      expect(_inner(doc, 'tblPr'), '<w:tblInd w:w="1in" w:type="dxa"/>');
      p.indentationPt = null;
      expect(_inner(doc, 'tblPr'), '<w:tblInd w:w="1in" w:type="dxa"/>');
      p.clear(DocxTableProperty.indentation);
      expect(_inner(doc, 'tblPr'), '');
      expect(_saved(doc), contains('<w:tblPr/>'));
    });

    test('bad values throw before anything changes', () {
      final DocxDocument doc = _open();
      final DocxTableProperties p = _table(doc).properties;
      expect(() => p.style = '', throwsArgumentError);
      expect(() => p.indentationPt = double.nan, throwsArgumentError);
      expect(() => p.indentationPt = 5000, throwsRangeError);
      expect(changeLogOf(doc).hasChanges, isFalse);
    });

    test('a misplaced w:tblPr stays where it was', () {
      // Only a w:tblPr before the first row is the table's.
      final DocxDocument doc = _openBody(
        '<w:tbl><w:tblGrid/><w:tr><w:tc><w:p/></w:tc></w:tr>'
        '<w:tblPr><w:tblLayout w:type="fixed"/></w:tblPr></w:tbl>',
      );
      final DocxTableProperties p = _table(doc).properties;
      expect(p.layout, isNull);
      p.alignment = DocxTableAlignment.center;
      expect(
        _saved(doc),
        '<w:tbl><w:tblPr><w:jc w:val="center"/></w:tblPr><w:tblGrid/>'
        '<w:tr><w:tc><w:p/></w:tc></w:tr>'
        '<w:tblPr><w:tblLayout w:type="fixed"/></w:tblPr></w:tbl>',
      );
    });
  });

  group('row properties', () {
    test('read what a file holds', () {
      final DocxTableRowProperties p = _row(
        _open(
          trPr:
              '<w:trPr><w:cantSplit/><w:trHeight w:val="400" '
              'w:hRule="exact"/><w:tblHeader/></w:trPr>',
        ),
      ).properties;
      expect(p.cantSplit, isTrue);
      expect(p.height, DocxRowHeight(20, rule: DocxRowHeightRule.exact));
      expect(p.repeatAsHeader, isTrue);
    });

    test('isHeader is repeatAsHeader == true', () {
      final DocxDocument doc = _open();
      final DocxTableRow row = _row(doc);
      expect(row.isHeader, isFalse);
      row.properties.repeatAsHeader = false;
      expect(row.isHeader, isFalse);
      row.isHeader = true;
      expect(row.properties.repeatAsHeader, isTrue);
      expect(_inner(doc, 'trPr'), '<w:tblHeader/>');
      row.isHeader = false;
      expect(row.properties.repeatAsHeader, isNull);
    });

    test('every member sets, writes in place and reads back', () {
      final DocxDocument doc = _open();
      _row(doc).properties
        ..height = DocxRowHeight(30)
        ..cantSplit = true
        ..repeatAsHeader = true;
      expect(
        _inner(doc, 'tr'),
        startsWith(
          '<w:trPr><w:cantSplit/><w:trHeight w:val="600" '
          'w:hRule="atLeast"/><w:tblHeader/></w:trPr><w:tc>',
        ),
      );
      final DocxTableRowProperties back = _row(_reopen(doc)).properties;
      expect(back.height, DocxRowHeight(30));
      expect(back.cantSplit, isTrue);
      expect(back.repeatAsHeader, isTrue);
    });

    test('false is written w:val="off", the only word w:trPr takes', () {
      // The schema's type for these two is on or off, not ST_OnOff: the Open
      // XML SDK refuses `0`.
      final DocxDocument doc = _open();
      _row(doc).properties
        ..cantSplit = false
        ..repeatAsHeader = false;
      expect(
        _inner(doc, 'trPr'),
        '<w:cantSplit w:val="off"/><w:tblHeader w:val="off"/>',
      );
      final DocxTableRowProperties back = _row(_reopen(doc)).properties;
      expect(back.cantSplit, isFalse);
      expect(back.repeatAsHeader, isFalse);
    });

    test('a read w:val stays as read until it is set', () {
      const String trPr = '<w:cantSplit w:val="true"/><w:tblHeader w:val="0"/>';
      final DocxDocument doc = _open(trPr: '<w:trPr>$trPr</w:trPr>');
      final DocxTableRowProperties p = _row(doc).properties;
      p.height = DocxRowHeight(30);
      p.height = null;
      expect(p.cantSplit, isTrue);
      expect(p.repeatAsHeader, isFalse);
      expect(_inner(doc, 'trPr'), trPr);
      p.cantSplit = false;
      expect(
        _inner(doc, 'trPr'),
        '<w:cantSplit w:val="off"/><w:tblHeader w:val="0"/>',
      );
    });

    test('a w:trPr is written after a w:tblPrEx and before the cells', () {
      final DocxDocument doc = _openBody(
        '<w:tbl><w:tblGrid/><w:tr><w:tblPrEx><w:tblW w:w="0"/></w:tblPrEx>'
        '<w:bookmarkStart w:id="1" w:name="b"/>'
        '<w:tc><w:p/></w:tc></w:tr></w:tbl>',
      );
      _row(doc).properties.cantSplit = true;
      expect(
        _inner(doc, 'tr'),
        '<w:tblPrEx><w:tblW w:w="0"/></w:tblPrEx><w:trPr><w:cantSplit/>'
        '</w:trPr><w:bookmarkStart w:id="1" w:name="b"/>'
        '<w:tc><w:p/></w:tc>',
      );
    });

    test('setting what it reads changes nothing', () {
      final DocxDocument doc = _open(
        trPr: '<w:trPr><w:cantSplit/><w:trHeight w:val="400"/></w:trPr>',
      );
      final DocxTableRowProperties p = _row(doc).properties;
      p
        ..cantSplit = p.cantSplit
        ..height = p.height
        ..repeatAsHeader = p.repeatAsHeader;
      expect(changeLogOf(doc).hasChanges, isFalse);
    });

    test('a set is one change and undoes', () {
      final DocxDocument doc = _open();
      final DocxTableRowProperties p = _row(doc).properties;
      final ChangeSet set = changeLogOf(doc).transaction(() {
        p.cantSplit = true;
      });
      expect(set.changes, hasLength(1));
      changeLogOf(doc).revertSet(set);
      expect(p.cantSplit, isNull);
      expect(_saved(doc), isNot(contains('trPr')));
      changeLogOf(doc).reapplySet(set);
      expect(p.cantSplit, isTrue);
    });

    test('a child in schema order among kept ones', () {
      final DocxDocument doc = _open(
        trPr: '<w:trPr><w:cantSplit/><w:hidden/></w:trPr>',
      );
      _row(doc).properties.repeatAsHeader = true;
      expect(_inner(doc, 'trPr'), '<w:cantSplit/><w:tblHeader/><w:hidden/>');
    });

    test('clear removes a child the getter cannot read', () {
      final DocxDocument doc = _open(
        trPr: '<w:trPr><w:trHeight w:val="1in"/></w:trPr>',
      );
      final DocxTableRowProperties p = _row(doc).properties;
      expect(p.height, isNull);
      p.clear(DocxTableRowProperty.height);
      expect(_saved(doc), contains('<w:trPr/>'));
    });

    test('a row with nothing set writes no w:trPr', () {
      final DocxDocument doc = _open();
      _row(doc).properties.cantSplit = true;
      _row(doc).properties.cantSplit = null;
      expect(_saved(doc), isNot(contains('trPr')));
    });
  });

  group('cell properties', () {
    test('read what a file holds', () {
      final DocxTableCellProperties p = _cell(
        _open(
          tcPr:
              '<w:tcPr><w:tcW w:w="2000" w:type="dxa"/>'
              '<w:gridSpan w:val="2"/><w:vMerge w:val="restart"/>'
              '<w:tcBorders><w:top w:val="single" w:sz="4" w:space="0" '
              'w:color="auto"/></w:tcBorders>'
              '<w:shd w:val="clear" w:color="auto" w:fill="FFFF00"/>'
              '<w:textDirection w:val="btLr"/><w:vAlign w:val="center"/>'
              '</w:tcPr>',
        ),
      ).properties;
      expect(p.width, DocxTableWidth.points(100));
      expect(p.gridSpan, 2);
      expect(p.verticalMerge, DocxVerticalMerge.restart);
      expect(p.borders!.top, isNotNull);
      expect(p.shading!.fill, DocxColor.rgb('FFFF00'));
      expect(p.textDirection, DocxTextDirection.bottomToTopLeftToRight);
      expect(p.verticalAlignment, DocxCellAlignment.center);
    });

    test('every member sets, writes first in the cell and reads back', () {
      final DocxDocument doc = _open(grid: _grid3);
      _cell(doc).properties
        ..width = DocxTableWidth.points(50)
        ..gridSpan = 3
        ..verticalMerge = DocxVerticalMerge.restart
        ..borders = DocxCellBorders(bottom: DocxBorder())
        ..shading = DocxShading(fill: DocxColor.rgb('00FF00'))
        ..textDirection = DocxTextDirection.topToBottomRightToLeft
        ..verticalAlignment = DocxCellAlignment.bottom;
      expect(
        _inner(doc, 'tc'),
        startsWith(
          '<w:tcPr><w:tcW w:w="1000" w:type="dxa"/><w:gridSpan w:val="3"/>'
          '<w:vMerge w:val="restart"/><w:tcBorders>',
        ),
      );
      expect(_inner(doc, 'tc'), endsWith('</w:tcPr><w:p/>'));
      final DocxTableCellProperties back = _cell(_reopen(doc)).properties;
      expect(back.width, DocxTableWidth.points(50));
      expect(back.gridSpan, 3);
      expect(back.verticalMerge, DocxVerticalMerge.restart);
      expect(back.borders, DocxCellBorders(bottom: DocxBorder()));
      expect(back.shading, DocxShading(fill: DocxColor.rgb('00FF00')));
      expect(back.textDirection, DocxTextDirection.topToBottomRightToLeft);
      expect(back.verticalAlignment, DocxCellAlignment.bottom);
    });

    test('gridSpan checks 1 to 63', () {
      final DocxDocument doc = _open(grid: '');
      final DocxTableCellProperties p = _cell(doc).properties;
      expect(() => p.gridSpan = 0, throwsRangeError);
      expect(() => p.gridSpan = 64, throwsRangeError);
      expect(changeLogOf(doc).hasChanges, isFalse);
      p.gridSpan = 63;
      expect(p.gridSpan, 63);
      expect(maxTableColumns, 63);
    });

    test('a file may hold a gridSpan past 63 and it reads', () {
      final DocxDocument doc = _open(
        tcPr: '<w:tcPr><w:gridSpan w:val="200"/></w:tcPr>',
      );
      expect(_cell(doc).properties.gridSpan, 200);
    });

    test('a w:tcPr is first in the cell, before a kept child', () {
      final DocxDocument doc = _openBody(
        '<w:tbl><w:tblGrid/><w:tr><w:tc><w:bookmarkStart w:id="1" '
        'w:name="b"/><w:p/></w:tc></w:tr></w:tbl>',
      );
      _cell(doc).properties.verticalAlignment = DocxCellAlignment.top;
      expect(
        _inner(doc, 'tc'),
        '<w:tcPr><w:vAlign w:val="top"/></w:tcPr>'
        '<w:bookmarkStart w:id="1" w:name="b"/><w:p/>',
      );
    });

    test('setting what it reads changes nothing', () {
      final DocxDocument doc = _open(
        tcPr:
            '<w:tcPr><w:tcW w:w="2000" w:type="dxa"/><w:gridSpan w:val="2"/>'
            '<w:vAlign w:val="center"/></w:tcPr>',
      );
      final DocxTableCellProperties p = _cell(doc).properties;
      p
        ..width = p.width
        ..gridSpan = p.gridSpan
        ..verticalMerge = p.verticalMerge
        ..verticalAlignment = p.verticalAlignment
        ..borders = p.borders
        ..shading = p.shading
        ..textDirection = p.textDirection;
      expect(changeLogOf(doc).hasChanges, isFalse);
    });

    test('a set is one change and undoes', () {
      final DocxDocument doc = _open(grid: _grid3);
      final DocxTableCellProperties p = _cell(doc).properties;
      final ChangeSet set = changeLogOf(doc).transaction(() {
        p.gridSpan = 2;
      });
      expect(set.changes, hasLength(1));
      changeLogOf(doc).revertSet(set);
      expect(p.gridSpan, isNull);
      expect(_saved(doc), isNot(contains('tcPr')));
      changeLogOf(doc).reapplySet(set);
      expect(p.gridSpan, 2);
    });

    test('a child in schema order among w:tcMar and w:hideMark', () {
      final DocxDocument doc = _open(
        tcPr:
            '<w:tcPr><w:tcW w:w="100" w:type="dxa"/>'
            '<w:tcMar><w:top w:w="10" w:type="dxa"/></w:tcMar>'
            '<w:hideMark/></w:tcPr>',
      );
      _cell(doc).properties.verticalAlignment = DocxCellAlignment.center;
      expect(
        _inner(doc, 'tcPr'),
        '<w:tcW w:w="100" w:type="dxa"/>'
        '<w:tcMar><w:top w:w="10" w:type="dxa"/></w:tcMar>'
        '<w:vAlign w:val="center"/><w:hideMark/>',
      );
    });

    test('clear removes a child the getter cannot read', () {
      final DocxDocument doc = _open(
        tcPr: '<w:tcPr><w:vAlign w:val="both"/></w:tcPr>',
      );
      final DocxTableCellProperties p = _cell(doc).properties;
      expect(p.verticalAlignment, isNull);
      p.clear(DocxTableCellProperty.verticalAlignment);
      expect(_saved(doc), contains('<w:tcPr/>'));
    });

    test('a cell edited in a nested table reports to the document', () {
      final DocxDocument doc = _openBody(
        '<w:tbl><w:tblGrid/><w:tr><w:tc><w:tbl><w:tblGrid/><w:tr><w:tc>'
        '<w:p/></w:tc></w:tr></w:tbl><w:p/></w:tc></w:tr></w:tbl>',
      );
      final DocxTable inner = _cell(doc).blocks.first as DocxTable;
      final ChangeSet set = changeLogOf(doc).transaction(() {
        inner.rows.single.cells.single.properties.gridSpan = 2;
        inner.rows.single.properties.cantSplit = true;
        inner.properties.layout = DocxTableLayout.fixed;
      });
      expect(set.changes, hasLength(3));
    });
  });

  group('gridColumnsPt', () {
    test('a set replaces the grid in one change and undoes', () {
      final DocxDocument doc = _open(
        grid:
            '<w:tblGrid><w:gridCol w:w="100"/>'
            '<w:tblGridChange w:id="1"><w:tblGrid/></w:tblGridChange>'
            '</w:tblGrid>',
      );
      final DocxTable t = _table(doc);
      final ChangeSet set = changeLogOf(doc).transaction(() {
        t.gridColumnsPt = <double?>[72];
      });
      expect(set.changes, hasLength(1));
      expect(t.gridColumnsPt, <double>[72]);
      expect(
        _inner(doc, 'tblGrid'),
        '<w:gridCol w:w="1440"/>'
        '<w:tblGridChange w:id="1"><w:tblGrid/></w:tblGridChange>',
      );
      expect(_table(_reopen(doc)).gridColumnsPt, <double>[72]);
      changeLogOf(doc).revertSet(set);
      expect(t.gridColumnsPt, <double>[5]);
      expect(_inner(doc, 'tblGrid'), startsWith('<w:gridCol w:w="100"/>'));
      changeLogOf(doc).reapplySet(set);
      expect(t.gridColumnsPt, <double>[72]);
    });

    test('setting what it reads changes nothing', () {
      final DocxDocument doc = _open();
      final DocxTable t = _table(doc);
      t.gridColumnsPt = <double?>[5];
      expect(changeLogOf(doc).hasChanges, isFalse);
    });

    test('setting what it reads changes nothing, whatever it reads', () {
      for (final String grid in <String>[
        '',
        '<w:tblGrid/>',
        '<w:tblGrid><w:gridCol/><w:gridCol w:w="abc"/></w:tblGrid>',
      ]) {
        final DocxDocument doc = _open(grid: grid);
        final DocxTable t = _table(doc);
        t.gridColumnsPt = t.gridColumnsPt;
        expect(changeLogOf(doc).hasChanges, isFalse, reason: grid);
      }
    });

    test('a table with no grid takes no fewer columns than its widest row', () {
      final DocxDocument doc = _openBody(
        '<w:tbl><w:tr><w:tc><w:p/></w:tc></w:tr><w:tr><w:trPr>'
        '<w:gridBefore w:val="1"/></w:trPr><w:tc><w:tcPr>'
        '<w:gridSpan w:val="2"/></w:tcPr><w:p/></w:tc></w:tr></w:tbl>',
      );
      final DocxTable t = _table(doc);
      expect(() => t.gridColumnsPt = <double?>[1, 2], throwsArgumentError);
      expect(changeLogOf(doc).hasChanges, isFalse);
      t.gridColumnsPt = <double?>[1, 2, 3];
      expect(t.gridColumnsPt, <double>[1, 2, 3]);
    });

    test('an empty list throws, with or without rows and a grid', () {
      final DocxDocument gridless = _open(grid: '');
      expect(
        () => _table(gridless).gridColumnsPt = <double?>[],
        throwsArgumentError,
      );
      expect(changeLogOf(gridless).hasChanges, isFalse);
      final DocxTable rowless = DocxDocument().body.addTable(columns: 2);
      expect(() => rowless.gridColumnsPt = <double?>[], throwsArgumentError);
      expect(rowless.gridColumnsPt, hasLength(2));
    });

    test('a list of another length throws once the table has rows', () {
      final DocxDocument doc = _open();
      final DocxTable t = _table(doc);
      expect(() => t.gridColumnsPt = <double?>[1, 2], throwsArgumentError);
      expect(() => t.gridColumnsPt = <double?>[], throwsArgumentError);
      expect(() => t.gridColumnsPt = <double?>[null], throwsArgumentError);
      expect(() => t.gridColumnsPt = null, throwsArgumentError);
      expect(
        () => t.gridColumnsPt = <double?>[double.nan],
        throwsArgumentError,
      );
      expect(() => t.gridColumnsPt = <double?>[2000], throwsRangeError);
      expect(changeLogOf(doc).hasChanges, isFalse);
    });

    test('a table with no grid takes one before its rows', () {
      final DocxDocument doc = _open(grid: '');
      _table(doc).gridColumnsPt = <double?>[10, 20];
      expect(
        _saved(doc),
        '<w:tbl><w:tblGrid><w:gridCol w:w="200"/><w:gridCol w:w="400"/>'
        '</w:tblGrid><w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl>',
      );
    });

    test('the grid is written after a w:tblPr that was set', () {
      final DocxDocument doc = _open(grid: '');
      _table(doc).properties.layout = DocxTableLayout.fixed;
      _table(doc).gridColumnsPt = <double?>[10];
      expect(
        _saved(doc),
        '<w:tbl><w:tblPr><w:tblLayout w:type="fixed"/></w:tblPr>'
        '<w:tblGrid><w:gridCol w:w="200"/></w:tblGrid>'
        '<w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl>',
      );
    });
  });
}
