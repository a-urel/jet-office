// Tests building a table with `addTable` and `addRow`, and how the styles of
// what goes in a document resolve on every route in: a block, a row or a cell,
// from no document or from another one. They build documents in memory, so they
// run on the web as well; the comparison with Word's own table is in
// `test/docx/table_build_oracle_test.dart`.
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart'
    show changeLogOf, editsOf;
import 'package:jet_office/src/docx/model/primitives.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../support/docx_builder.dart';
import '../support/localized_document.dart';
import '../support/styles_documents.dart';

const String _decls = 'xmlns:w="${Ns.w}"';

/// The main part of a document whose body holds [body].
String _documentXml(String body) =>
    '<w:document $_decls><w:body>$body</w:body></w:document>';

/// Opens the document without a styles part whose body holds [body].
DocxDocument _open(String body) =>
    DocxDocument.open(buildDocx(document: _documentXml(body)));

/// The bytes of a document with [body] and a Turkish styles part: `Balk1`
/// named `heading 1`, `Guclu` named `Strong`, `NormalTablo` and `TabloKlavuzu`
/// named `Table Grid`.
Uint8List _turkishBytes([String body = '<w:p/>']) => docxWithStyles(
  document: _documentXml(body),
  styles: stylesXmlOf(<String>[
    styleXml('paragraph', 'Normal', 'Normal', attributes: ' w:default="1"'),
    styleXml('paragraph', 'Balk1', 'heading 1'),
    styleXml('character', 'Guclu', 'Strong'),
    styleXml(
      'table',
      'NormalTablo',
      'Normal Table',
      attributes: ' w:default="1"',
    ),
    styleXml(
      'table',
      'TabloKlavuzu',
      'Table Grid',
      children: '<w:basedOn w:val="NormalTablo"/>',
    ),
  ]),
);

/// A document as [_turkishBytes] gives it.
DocxDocument _turkish([String body = '<w:p/>']) =>
    DocxDocument.open(_turkishBytes(body));

/// A document whose styles part cannot be read, with a table of one cell.
DocxDocument _brokenStyles() => DocxDocument.open(
  docxWithStyles(
    document: _documentXml(
      '<w:tbl><w:tblGrid><w:gridCol w:w="100"/></w:tblGrid>'
      '<w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl>',
    ),
    styles: '<w:styles $_decls><w:style>',
  ),
);

/// The main part of [doc] as saved.
XmlDocument _saved(DocxDocument doc) =>
    XmlDocument.parse(readDocxText(doc.save().bytes)['word/document.xml']!);

/// The elements `w:<name>` of [xml], in document order.
List<XmlElement> _all(XmlNode xml, String name) =>
    xml.findAllElements(name, namespaceUri: Ns.w).toList();

/// The value of `w:<name>` on [element].
String? _w(XmlElement element, String name) =>
    element.getAttribute(name, namespaceUri: Ns.w);

/// The text of each row of [table], its cells joined by `|`.
List<String> _rows(DocxTable table) => <String>[
  for (final DocxTableRow row in table.rows)
    row.cells.map((DocxTableCell c) => c.text).join('|'),
];

/// The first cell of the first row of [table].
DocxTableCell _first(DocxTable table) => table.rows.first.cells.first;

/// The first paragraph of [cell].
DocxParagraph _paragraph(DocxTableCell cell) =>
    cell.blocks.first as DocxParagraph;

/// A new paragraph of the style [style], with a run of the style [runStyle].
DocxParagraph _styled(String style, String runStyle) {
  final DocxParagraph paragraph = DocxParagraph()..style = style;
  paragraph.addRun('x').style = runStyle;
  return paragraph;
}

/// A new table with the style `TableGrid`, holding in its first cell a nested
/// table of the same style, whose first cell holds [paragraph].
DocxTable _treeOf(DocxParagraph paragraph) {
  final DocxTable inner = DocxTable(columns: 1);
  inner.properties.style = 'TableGrid';
  _first(inner).replaceBlockAt(0, paragraph);
  final DocxTable outer = DocxTable(columns: 1);
  outer.properties.style = 'TableGrid';
  _first(outer).replaceBlockAt(0, inner);
  return outer;
}

/// What a read table holds to count as set in another document: the table
/// style `Yok`, in its cell a paragraph of the style `Eksik` in the list 7, a
/// run of the style `Kayip`, and a nested table of the style `Hic`.
const String _foreignTable =
    '<w:tbl><w:tblPr><w:tblStyle w:val="Yok"/></w:tblPr>'
    '<w:tblGrid><w:gridCol w:w="2000"/></w:tblGrid><w:tr><w:tc>'
    '<w:p><w:pPr><w:pStyle w:val="Eksik"/>'
    '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="7"/></w:numPr></w:pPr>'
    '<w:r><w:rPr><w:rStyle w:val="Kayip"/></w:rPr><w:t>a</w:t></w:r></w:p>'
    '<w:tbl><w:tblPr><w:tblStyle w:val="Hic"/></w:tblPr>'
    '<w:tblGrid><w:gridCol w:w="1000"/></w:tblGrid>'
    '<w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl><w:p/>'
    '</w:tc></w:tr></w:tbl>';

/// The locations a save of [doc] reports for [code] with the detail [detail].
List<String> _locations(
  DocxDocument doc,
  DocxWarningCode code,
  String detail,
) => <String>[
  for (final DocxWarning w in doc.save().warnings)
    if (w.code == code && w.detail == detail) ...w.locations,
];

void main() {
  group('the sample of the spec', () {
    test('addTable and addRow build the price list', () {
      final DocxDocument doc = DocxDocument();
      final DocxBody body = doc.body;
      final int before = body.blocks.length;

      final DocxTable table = body.addTable(columns: 3);
      expect(body.blocks, hasLength(before + 1));
      expect(body.blocks.last, same(table));
      expect(table.rows, isEmpty);

      final DocxTableRow head = table.addRow(<String?>[
        'Ürün',
        'Adet',
        'Fiyat',
      ], header: true);
      expect(head.isHeader, isTrue);
      expect(head.properties.cantSplit, isTrue);

      final DocxTableRow line = table.addRow(<String?>['Kalem', '12', '4,50']);
      expect(line.isHeader, isFalse);
      expect(line.properties.cantSplit, isNull);
      expect(table.rows, <DocxTableRow>[head, line]);

      final DocxDocument again = DocxDocument.open(doc.save().bytes);
      final DocxTable read = again.body.blocks.last as DocxTable;
      expect(_rows(read), <String>['Ürün|Adet|Fiyat', 'Kalem|12|4,50']);
      expect(read.rows.first.isHeader, isTrue);
      expect(read.rows.first.properties.cantSplit, isTrue);
      expect(read.properties.style, 'TableGrid');
    });
  });

  group('addTable', () {
    test('writes the properties of Insert Table, in schema order', () {
      final DocxDocument doc = DocxDocument();
      doc.body.addTable(columns: 3).addRow(<String?>['a']);
      final XmlElement tbl = _all(_saved(doc), 'tbl').single;
      final XmlElement tblPr = tbl.childElements.first;
      expect(tblPr.localName, 'tblPr');
      expect(tblPr.childElements.map((XmlElement e) => e.localName), <String>[
        'tblStyle',
        'tblW',
        'tblLook',
      ]);
      expect(_w(_all(tblPr, 'tblStyle').single, 'val'), 'TableGrid');
      final XmlElement width = _all(tblPr, 'tblW').single;
      expect(_w(width, 'w'), '0');
      expect(_w(width, 'type'), 'auto');
      final XmlElement look = _all(tblPr, 'tblLook').single;
      expect(_w(look, 'val'), '04A0');
      expect(
        <String?>[
          for (final String flag in <String>[
            'firstRow',
            'lastRow',
            'firstColumn',
            'lastColumn',
            'noHBand',
            'noVBand',
          ])
            _w(look, flag),
        ],
        <String>['1', '0', '1', '0', '0', '1'],
      );
    });

    test('shares the width of a blank A4 page, in whole twips', () {
      final DocxDocument doc = DocxDocument();
      final DocxTable table = doc.body.addTable(columns: 7);
      table.addRow(<String?>[]);
      expect(table.gridColumnsPt, List<double>.filled(7, 64.7));
      final XmlDocument xml = _saved(doc);
      expect(
        _all(xml, 'gridCol').map((XmlElement e) => _w(e, 'w')),
        List<String>.filled(7, '1294'),
      );
      expect(
        _all(xml, 'tcW').map((XmlElement e) => _w(e, 'w')),
        List<String>.filled(7, '1294'),
      );
      expect(
        _all(xml, 'tcW').map((XmlElement e) => _w(e, 'type')),
        List<String>.filled(7, 'dxa'),
      );
    });

    test('columnWidthsPt sets the grid and the cells of each row', () {
      final DocxDocument doc = DocxDocument();
      final DocxTable table = doc.body.addTable(
        columns: 2,
        columnWidthsPt: <double>[100, 50.5],
      );
      table.addRow(<String?>['a', 'b']);
      expect(table.gridColumnsPt, <double>[100, 50.5]);
      expect(
        table.rows.single.cells.map(
          (DocxTableCell c) => c.properties.width?.widthPt,
        ),
        <double>[100, 50.5],
      );
      expect(
        _all(_saved(doc), 'gridCol').map((XmlElement e) => _w(e, 'w')),
        <String>['2000', '1010'],
      );
    });

    test('a bad argument throws and changes nothing', () {
      final DocxDocument doc = DocxDocument();
      final DocxBody body = doc.body;
      final int before = body.blocks.length;
      expect(() => body.addTable(columns: 0), throwsRangeError);
      expect(() => body.addTable(columns: 64), throwsRangeError);
      expect(
        () => body.addTable(columns: 2, columnWidthsPt: <double>[10]),
        throwsArgumentError,
      );
      expect(
        () => body.addTable(columns: 1, columnWidthsPt: <double>[10, 20]),
        throwsArgumentError,
      );
      expect(
        () => body.addTable(columns: 1, columnWidthsPt: <double>[-1]),
        throwsRangeError,
      );
      expect(
        () => body.addTable(columns: 1, columnWidthsPt: <double>[1585]),
        throwsRangeError,
      );
      expect(
        () => body.addTable(columns: 1, columnWidthsPt: <double>[double.nan]),
        throwsArgumentError,
      );
      expect(body.blocks, hasLength(before));
      expect(changeLogOf(doc).hasChanges, isFalse);
    });

    test('a Turkish document gets TabloKlavuzu', () {
      final DocxDocument doc = _turkish();
      final int styles = doc.styles.styles.length;
      final DocxTable table = doc.body.addTable(columns: 2);
      expect(table.properties.style, 'TabloKlavuzu');
      expect(doc.styles.styles, hasLength(styles));
    });

    test('a document with the normal table only gets TableGrid on it', () {
      final DocxDocument doc = DocxDocument.open(localizedWordDocx());
      final DocxTable table = doc.body.addTable(columns: 2);
      expect(table.properties.style, 'TableGrid');
      expect(doc.styles.byId('TableGrid')?.basedOn, 'NormalTablo');
    });

    test('a blank document gets TableGrid and TableNormal', () {
      final DocxDocument blank = DocxDocument();
      expect(blank.styles.byId('TableGrid'), isNull);
      blank.body.addTable(columns: 2).addRow(<String?>['a']);
      expect(blank.styles.byId('TableGrid')?.basedOn, 'TableNormal');
      expect(blank.styles.byId('TableNormal')?.type, DocxStyleType.table);

      final DocxDocument bare = _open('<w:p/>');
      bare.body.addTable(columns: 2).addRow(<String?>['a']);
      expect(bare.styles.byId('TableGrid')?.basedOn, 'TableNormal');
      expect(bare.styles.byId('TableNormal')?.type, DocxStyleType.table);
      final Map<String, String> text = readDocxText(bare.save().bytes);
      expect(text['word/styles.xml'], contains('w:styleId="TableGrid"'));
      expect(bare.save().warnings, isEmpty);
    });

    test('is one transaction, with the style it adds', () {
      final DocxDocument doc = DocxDocument();
      final DocxEdits edits = editsOf(doc);
      final int before = doc.body.blocks.length;
      final ChangeSet set = edits.transaction(
        () => doc.body.addTable(columns: 2),
      );
      expect(doc.styles.byId('TableGrid'), isNotNull);
      edits.log.revertSet(set);
      expect(doc.body.blocks, hasLength(before));
      expect(doc.styles.byId('TableGrid'), isNull);
    });

    test('a failure after the insert takes it all back', () {
      final DocxDocument doc = DocxDocument();
      final DocxEdits edits = editsOf(doc);
      final int before = doc.body.blocks.length;
      edits.afterRecord = () {
        if (doc.body.blocks.length > before) throw StateError('hook');
      };
      expect(() => doc.body.addTable(columns: 2), throwsStateError);
      edits.afterRecord = null;
      expect(doc.body.blocks, hasLength(before));
      expect(doc.styles.byId('TableGrid'), isNull);
      expect(changeLogOf(doc).hasChanges, isFalse);
    });

    test('on an unreadable styles part throws and changes nothing', () {
      final DocxDocument doc = _brokenStyles();
      final int before = doc.body.blocks.length;
      expect(
        () => doc.body.addTable(columns: 2),
        throwsA(
          isA<DocxReadException>().having(
            (DocxReadException e) => e.part,
            'part',
            '/word/styles.xml',
          ),
        ),
      );
      expect(doc.body.blocks, hasLength(before));
      expect(changeLogOf(doc).hasChanges, isFalse);
    });

    test('adds no paragraph between two tables or after the last', () {
      final DocxDocument doc = DocxDocument();
      final int before = doc.body.blocks.length;
      doc.body.addTable(columns: 1).addRow(<String?>['a']);
      doc.body.addTable(columns: 1).addRow(<String?>['b']);
      expect(doc.body.blocks, hasLength(before + 2));
      final XmlElement body = _all(_saved(doc), 'body').single;
      expect(
        body.childElements
            .map((XmlElement e) => e.localName)
            .toList()
            .sublist(before, before + 2),
        <String>['tbl', 'tbl'],
      );
    });
  });

  group('addRow', () {
    test('null is an empty cell, and fewer values leave empty cells', () {
      final DocxTable table = DocxDocument().body.addTable(columns: 3);
      final DocxTableRow row = table.addRow(<String?>[null, 'b']);
      expect(row.cells.map((DocxTableCell c) => c.text), <String>['', 'b', '']);
      for (final DocxTableCell cell in row.cells) {
        expect(cell.blocks.single, isA<DocxParagraph>());
      }
      expect((row.cells.first.blocks.single as DocxParagraph).inlines, isEmpty);
    });

    test('more values than columns throw and change nothing', () {
      final DocxDocument doc = DocxDocument();
      final DocxTable table = doc.body.addTable(columns: 2);
      expect(() => table.addRow(<String?>['a', 'b', 'c']), throwsArgumentError);
      expect(table.rows, isEmpty);
    });

    test('text is scrubbed and split as a run does it', () {
      final DocxDocument doc = DocxDocument();
      final DocxTable table = doc.body.addTable(columns: 1);
      table.addRow(<String?>['a\tb\u0001']);
      expect(_first(table).text, 'a\tb');
      expect(
        doc.save().warnings.single.code,
        DocxWarningCode.invalidCharactersRemoved,
      );
      expect(
        doc.save().warnings.single.locations.single,
        'body/tbl[0]/tr[0]/tc[0]/p[0]/r[0]',
      );
    });

    test('is one change that undoes and redoes', () {
      final DocxDocument doc = _open('<w:p/>');
      final DocxEdits edits = editsOf(doc);
      final DocxTable table = doc.body.addTable(columns: 2);
      final ChangeSet set = edits.transaction(
        () => table.addRow(<String?>['a'], header: true),
      );
      expect(set.changes, hasLength(1));
      edits.log.revertSet(set);
      expect(table.rows, isEmpty);
      edits.log.reapplySet(set);
      expect(_rows(table), <String>['a|']);
      expect(table.rows.single.isHeader, isTrue);
    });

    test('works on a table in no document', () {
      final DocxTable table = DocxTable(columns: 2);
      final DocxTableRow row = table.addRow(<String?>['a', 'b']);
      expect(_rows(table), <String>['|', 'a|b']);
      expect(row.cells.first.properties.width?.widthPt, 226.55);
    });

    test('on a table read takes the width of its grid, after its rows', () {
      final DocxDocument doc = _open(
        '<w:tbl><w:tblGrid><w:gridCol w:w="2000"/><w:gridCol w:w="1000"/>'
        '</w:tblGrid><w:tr><w:tc><w:p/></w:tc><w:tc><w:p/></w:tc></w:tr>'
        '<w:bookmarkStart w:id="1" w:name="b"/></w:tbl>',
      );
      final DocxTable table = doc.body.blocks.single as DocxTable;
      final DocxTableRow row = table.addRow(<String?>['x']);
      expect(row.cells, hasLength(2));
      expect(
        row.cells.map((DocxTableCell c) => c.properties.width?.widthPt),
        <double>[100, 50],
      );
      final XmlElement tbl = _all(_saved(doc), 'tbl').single;
      expect(tbl.childElements.last.localName, 'tr');
    });

    test('a column without a usable width gives a cell without one', () {
      final DocxDocument doc = _open(
        '<w:tbl><w:tblGrid><w:gridCol/><w:gridCol w:w="0"/>'
        '<w:gridCol w:w="99999"/><w:gridCol w:w="100"/></w:tblGrid>'
        '<w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl>',
      );
      final DocxTable table = doc.body.blocks.single as DocxTable;
      final DocxTableRow row = table.addRow(<String?>[]);
      expect(
        row.cells.map((DocxTableCell c) => c.properties.width?.widthPt),
        <double?>[null, null, null, 5],
      );
    });

    test('a grid past 63 columns gives a row of its width', () {
      final DocxDocument doc = _open(
        '<w:tbl><w:tblGrid>${'<w:gridCol w:w="100"/>' * 70}</w:tblGrid>'
        '<w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl>',
      );
      final DocxTable table = doc.body.blocks.single as DocxTable;
      expect(table.addRow(<String?>[]).cells, hasLength(70));
    });

    test('a table without a grid throws: it has no width', () {
      for (final String grid in <String>['', '<w:tblGrid/>']) {
        final DocxDocument doc = _open(
          '<w:tbl>$grid<w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl>',
        );
        final DocxTable table = doc.body.blocks.single as DocxTable;
        expect(() => table.addRow(<String?>['a']), throwsArgumentError);
        expect(table.rows, hasLength(1));
      }
    });
  });

  group('a table without rows', () {
    test('a save names it, and writes nothing', () {
      final DocxDocument doc = DocxDocument();
      doc.body.addTable(columns: 2).addRow(<String?>['a']);
      doc.body.addTable(columns: 2);
      expect(
        doc.save,
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('body/tbl[1]'),
          ),
        ),
      );
      final List<List<int>> chunks = <List<int>>[];
      expect(() => doc.saveTo(_Chunks(chunks)), throwsStateError);
      expect(chunks, isEmpty);
    });

    test('a save names one nested in a cell', () {
      final DocxDocument doc = DocxDocument();
      final DocxTable table = doc.body.addTable(columns: 2);
      table.addRow(<String?>['a']);
      table.addRow(<String?>['b']);
      table.rows.last.cells.last.addTable(columns: 1);
      expect(
        doc.save,
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('body/tbl[0]/tr[1]/tc[1]/tbl[0]'),
          ),
        ),
      );
    });

    test('the first row, or removing the table, makes it saveable', () {
      final DocxDocument doc = DocxDocument();
      final DocxTable table = doc.body.addTable(columns: 2);
      expect(doc.save, throwsStateError);
      table.addRow(<String?>['a']);
      expect(doc.save().bytes, isNotEmpty);

      final DocxDocument other = DocxDocument();
      other.body.addTable(columns: 2);
      other.body.removeBlockAt(other.body.blocks.length - 1);
      expect(other.save().bytes, isNotEmpty);
    });

    test('an undone first row leaves it unsaveable again', () {
      final DocxDocument doc = DocxDocument();
      final DocxEdits edits = editsOf(doc);
      final DocxTable table = doc.body.addTable(columns: 1);
      final ChangeSet set = edits.transaction(
        () => table.addRow(<String?>['a']),
      );
      edits.log.revertSet(set);
      expect(doc.save, throwsStateError);
    });

    test('a table read with no rows is kept, edited or not', () {
      const String body = '<w:tbl><w:tblPr/><w:tblGrid/></w:tbl><w:p/>';
      final DocxDocument doc = _open(body);
      doc.body.addParagraph('x');
      final XmlDocument xml = _saved(doc);
      expect(_all(xml, 'tbl'), hasLength(1));
      expect(_all(xml, 'tr'), isEmpty);
    });

    test('the last row of a built table still cannot be removed', () {
      final DocxTable table = DocxDocument().body.addTable(columns: 1);
      table.addRow(<String?>['a']);
      expect(() => table.removeRowAt(0), throwsStateError);
      expect(table.rows, hasLength(1));
    });

    test('the constructor still refuses it', () {
      expect(() => DocxTable(columns: 1, rows: 0), throwsRangeError);
    });
  });

  group('DocxTableCell.addTable', () {
    test('in a document behaves as the body does', () {
      final DocxDocument doc = _turkish();
      final DocxTable outer = doc.body.addTable(columns: 2);
      outer.addRow(<String?>['a', 'b']);
      final DocxTableCell cell = _first(outer);
      final DocxTable inner = cell.addTable(
        columns: 2,
        columnWidthsPt: <double>[40, 60],
      );
      expect(cell.blocks.last, same(inner));
      expect(inner.rows, isEmpty);
      expect(inner.properties.style, 'TabloKlavuzu');
      expect(inner.properties.width, const DocxTableWidth.auto());
      expect(
        inner.properties.look,
        const DocxTableLook(
          firstRow: true,
          firstColumn: true,
          noVerticalBands: true,
        ),
      );
      expect(inner.gridColumnsPt, <double>[40, 60]);
      inner.addRow(<String?>['x', 'y']);
      final XmlDocument xml = _saved(doc);
      final XmlElement tc = _all(xml, 'tc').first;
      expect(tc.childElements.map((XmlElement e) => e.localName), <String>[
        'tcPr',
        'p',
        'tbl',
        'p',
      ]);
    });

    test('in a document adds the style a document lacks', () {
      final DocxDocument doc = _open(
        '<w:tbl><w:tblGrid><w:gridCol w:w="100"/></w:tblGrid>'
        '<w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl>',
      );
      final DocxTable outer = doc.body.blocks.single as DocxTable;
      final DocxEdits edits = editsOf(doc);
      late DocxTable inner;
      final ChangeSet set = edits.transaction(
        () => inner = _first(outer).addTable(columns: 1),
      );
      expect(inner.properties.style, 'TableGrid');
      expect(doc.styles.byId('TableGrid'), isNotNull);
      edits.log.revertSet(set);
      expect(_first(outer).blocks, hasLength(1));
      expect(doc.styles.byId('TableGrid'), isNull);
    });

    test('finds the built-in by name, as the body does, past a squatter', () {
      final DocxDocument doc = DocxDocument.open(
        docxWithStyles(
          document: _documentXml(
            '<w:tbl><w:tblGrid><w:gridCol w:w="100"/></w:tblGrid>'
            '<w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl>',
          ),
          styles: stylesXmlOf(<String>[
            styleXml('paragraph', 'TableGrid', 'My paragraph'),
            styleXml('table', 'TabloKlavuzu', 'Table Grid'),
          ]),
        ),
      );
      final DocxTable outer = doc.body.blocks.single as DocxTable;
      expect(doc.body.addTable(columns: 1).properties.style, 'TabloKlavuzu');
      expect(
        _first(outer).addTable(columns: 1).properties.style,
        'TabloKlavuzu',
      );
    });

    group('default widths', () {
      /// A cell with the `w:tcW` [tcW], in a document.
      DocxTableCell cellOf(String tcW) {
        final DocxDocument doc = _open(
          '<w:tbl><w:tblGrid><w:gridCol w:w="3001"/></w:tblGrid><w:tr><w:tc>'
          '<w:tcPr>$tcW</w:tcPr><w:p/></w:tc></w:tr></w:tbl>',
        );
        return (doc.body.blocks.single as DocxTable).rows.single.cells.single;
      }

      test('share a cell width in twips, rounded down', () {
        final DocxTable inner = cellOf(
          '<w:tcW w:w="3001" w:type="dxa"/>',
        ).addTable(columns: 2);
        expect(inner.gridColumnsPt, <double>[75, 75]);
      });

      test('share a new cell\'s width, so the table fits in it', () {
        final DocxTable outer = DocxDocument().body.addTable(columns: 2);
        final DocxTable inner = outer
            .addRow(<String?>['a', 'b'])
            .cells
            .first
            .addTable(columns: 2);
        expect(inner.gridColumnsPt, <double>[113.25, 113.25]);
      });

      test('share the page without a width in twips', () {
        for (final String tcW in <String>[
          '',
          '<w:tcW w:w="0" w:type="auto"/>',
          '<w:tcW w:w="2500" w:type="pct"/>',
          '<w:tcW w:w="1" w:type="dxa"/>',
          '<w:tcW w:w="99999" w:type="dxa"/>',
          '<w:tcW w:w="-5" w:type="dxa"/>',
        ]) {
          expect(cellOf(tcW).addTable(columns: 2).gridColumnsPt, <double>[
            226.55,
            226.55,
          ], reason: tcW);
        }
      });

      test('give way to the widths asked for', () {
        final DocxTable inner = cellOf(
          '<w:tcW w:w="3000" w:type="dxa"/>',
        ).addTable(columns: 2, columnWidthsPt: <double>[10, 20]);
        expect(inner.gridColumnsPt, <double>[10, 20]);
      });
    });

    test(
      'in no document sets no style, and the caller\'s resolves on insert',
      () {
        final DocxTableCell cell = DocxTableCell('a');
        final DocxTable inner = cell.addTable(columns: 2);
        expect(inner.properties.style, isNull);
        expect(inner.gridColumnsPt, hasLength(2));
        inner.addRow(<String?>['x', 'y']);
        inner.properties.style = 'TableGrid';
        expect(inner.properties.style, 'TableGrid');

        final DocxDocument doc = _turkish();
        doc.body.addTable(columns: 1).insertRowAt(0, _rowOf(cell));
        expect(inner.properties.style, 'TabloKlavuzu');
      },
    );

    test('on an unreadable styles part throws and changes nothing', () {
      final DocxDocument doc = _brokenStyles();
      final DocxTableCell cell = _first(doc.body.blocks.single as DocxTable);
      expect(
        () => cell.addTable(columns: 2),
        throwsA(isA<DocxReadException>()),
      );
      expect(cell.blocks, hasLength(1));
      expect(changeLogOf(doc).hasChanges, isFalse);
    });

    test('a bad argument throws and changes nothing', () {
      final DocxTableCell cell = DocxTableCell();
      expect(() => cell.addTable(columns: 0), throwsRangeError);
      expect(
        () => cell.addTable(columns: 2, columnWidthsPt: <double>[1]),
        throwsArgumentError,
      );
      expect(cell.blocks, hasLength(1));
    });

    test('past the nesting the API builds throws and changes nothing', () {
      final DocxDocument doc = DocxDocument();
      DocxTable at = doc.body.addTable(columns: 1);
      at.addRow(<String?>[]);
      for (int i = 1; i < 80; i++) {
        at = _first(at).addTable(columns: 1)..addRow(<String?>[]);
      }
      final int styles = doc.styles.styles.length;
      expect(() => _first(at).addTable(columns: 1), throwsArgumentError);
      expect(_first(at).blocks, hasLength(1));
      expect(doc.styles.styles, hasLength(styles));
    });
  });

  group('the styles of what goes in', () {
    // Every route in, each putting a tree in a document of `body`, below.
    final Map<String, void Function(DocxDocument doc, DocxTable tree)> routes =
        <String, void Function(DocxDocument, DocxTable)>{
          'DocxBody.insertBlock': (DocxDocument doc, DocxTable tree) =>
              doc.body.insertBlock(0, tree),
          'DocxBody.replaceBlockAt': (DocxDocument doc, DocxTable tree) =>
              doc.body.replaceBlockAt(0, tree),
          'DocxTableCell.insertBlock': (DocxDocument doc, DocxTable tree) =>
              _first(doc.body.blocks.last as DocxTable).insertBlock(0, tree),
          'DocxTableCell.replaceBlockAt': (DocxDocument doc, DocxTable tree) =>
              _first(doc.body.blocks.last as DocxTable).replaceBlockAt(0, tree),
          'DocxTable.insertRowAt': (DocxDocument doc, DocxTable tree) {
            final DocxTableRow row = DocxTableRow();
            _rowCell(row).insertBlock(0, tree);
            (doc.body.blocks.last as DocxTable).insertRowAt(0, row);
          },
          'DocxTableRow.insertCellAt': (DocxDocument doc, DocxTable tree) {
            final DocxTableCell cell = DocxTableCell()..insertBlock(0, tree);
            (doc.body.blocks.last as DocxTable).rows.first.insertCellAt(
              0,
              cell,
            );
          },
        };

    const String body =
        '<w:p/><w:tbl><w:tblGrid><w:gridCol w:w="100"/>'
        '<w:gridCol w:w="100"/></w:tblGrid>'
        '<w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl>';

    routes.forEach((String name, void Function(DocxDocument, DocxTable) route) {
      test('$name resolves everything in the tree', () {
        final DocxDocument doc = _turkish(body);
        final DocxParagraph paragraph = _styled('Heading1', 'Strong');
        final DocxTable tree = _treeOf(paragraph);
        final DocxTable inner = _first(tree).blocks.first as DocxTable;
        route(doc, tree);
        expect(tree.properties.style, 'TabloKlavuzu');
        expect(inner.properties.style, 'TabloKlavuzu');
        expect(paragraph.style, 'Balk1');
        expect((paragraph.inlines.single as DocxRun).style, 'Guclu');
      });

      test('$name on an unreadable styles part changes nothing', () {
        final DocxDocument doc = DocxDocument.open(
          docxWithStyles(
            document: _documentXml(body),
            styles: '<w:styles $_decls><w:style>',
          ),
        );
        final DocxTable tree = _treeOf(_styled('Heading1', 'Strong'));
        expect(() => route(doc, tree), throwsA(isA<DocxReadException>()));
        final DocxTable table = doc.body.blocks.last as DocxTable;
        expect(doc.body.blocks, hasLength(2));
        expect(table.rows, hasLength(1));
        expect(table.rows.single.cells, hasLength(1));
        expect(_first(table).blocks.single, isA<DocxParagraph>());
        expect(changeLogOf(doc).hasChanges, isFalse);
      });
    });

    test('a style set on a table in a document resolves as it is set', () {
      final DocxDocument doc = _turkish();
      final DocxTable table = doc.body.addTable(columns: 1);
      table.properties.style = null;
      table.properties.style = 'TableGrid';
      expect(table.properties.style, 'TabloKlavuzu');
    });

    test('an insert in no document stores the id as given', () {
      final DocxTableCell cell = DocxTableCell();
      final DocxTable table = DocxTable(columns: 1);
      table.properties.style = 'TableGrid';
      cell.insertBlock(0, table);
      expect(table.properties.style, 'TableGrid');
    });

    test('the styles a route adds undo with it', () {
      final DocxDocument doc = _open(body);
      final DocxEdits edits = editsOf(doc);
      final DocxTable table = doc.body.blocks.last as DocxTable;
      final DocxTableRow row = DocxTableRow();
      _paragraph(_rowCell(row)).style = 'Heading1';
      final ChangeSet set = edits.transaction(() => table.insertRowAt(1, row));
      expect(doc.styles.byId('Heading1'), isNotNull);
      edits.log.revertSet(set);
      expect(table.rows, hasLength(1));
      expect(doc.styles.byId('Heading1'), isNull);
      edits.log.reapplySet(set);
      expect(table.rows, hasLength(2));
      expect(doc.styles.byId('Heading1'), isNotNull);
    });

    test('a read table moved within its document stays as read', () {
      final DocxDocument doc = _open(_foreignTable);
      final DocxBlock table = doc.body.blocks.single;
      doc.body.removeBlockAt(0);
      doc.body.insertBlock(0, table);
      expect(doc.save().warnings, isEmpty);
    });
  });

  group('a table read in one document and inserted in another', () {
    test('its w:tblStyle and the deep references count as set, and a missing '
        'one warns at its full path', () {
      final DocxDocument from = _open(_foreignTable);
      final DocxBlock table = from.body.blocks.single;
      from.body.removeBlockAt(0);
      final DocxDocument into = DocxDocument();
      into.body.insertBlock(0, table);

      expect(_locations(into, DocxWarningCode.styleNotFound, 'Yok'), <String>[
        'body/tbl[0]',
      ]);
      expect(_locations(into, DocxWarningCode.styleNotFound, 'Hic'), <String>[
        'body/tbl[0]/tr[0]/tc[0]/tbl[0]',
      ]);
      expect(_locations(into, DocxWarningCode.styleNotFound, 'Eksik'), <String>[
        'body/tbl[0]/tr[0]/tc[0]/p[0]',
      ]);
      expect(_locations(into, DocxWarningCode.styleNotFound, 'Kayip'), <String>[
        'body/tbl[0]/tr[0]/tc[0]/p[0]/r[0]',
      ]);
      expect(_locations(into, DocxWarningCode.numberingNotFound, '7'), <String>[
        'body/tbl[0]/tr[0]/tc[0]/p[0]',
      ]);
    });

    test('a built-in it names resolves to this document\'s id', () {
      final DocxDocument from = _open(
        '<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/></w:tblPr>'
        '<w:tblGrid><w:gridCol w:w="100"/></w:tblGrid><w:tr><w:tc><w:p>'
        '<w:pPr><w:pStyle w:val="Heading1"/></w:pPr></w:p></w:tc></w:tr>'
        '</w:tbl>',
      );
      final DocxTable table = from.body.blocks.single as DocxTable;
      from.body.removeBlockAt(0);
      final DocxDocument into = _turkish();
      into.body.insertBlock(0, table);
      expect(table.properties.style, 'TabloKlavuzu');
      expect(_paragraph(_first(table)).style, 'Balk1');
      expect(into.save().warnings, isEmpty);
    });

    test('a row or a cell read there joins the same way', () {
      const String tables =
          '<w:tbl><w:tblGrid><w:gridCol w:w="100"/></w:tblGrid>'
          '<w:tr><w:tc><w:p/></w:tc></w:tr><w:tr><w:tc><w:p><w:pPr>'
          '<w:pStyle w:val="Eksik"/></w:pPr></w:p></w:tc>'
          '<w:tc><w:p><w:pPr><w:pStyle w:val="Kayip"/></w:pPr></w:p></w:tc>'
          '</w:tr></w:tbl>';
      final DocxDocument from = _open(tables);
      final DocxTable source = from.body.blocks.single as DocxTable;
      final DocxTableRow row = source.rows.last;
      final DocxTableCell cell = row.cells.last;
      row.removeCellAt(1);
      source.removeRowAt(1);

      final DocxDocument into = DocxDocument();
      final DocxTable table = into.body.addTable(columns: 1);
      table.insertRowAt(0, row);
      table.insertRowAt(1, _rowOf(cell));
      expect(_locations(into, DocxWarningCode.styleNotFound, 'Eksik'), <String>[
        'body/tbl[0]/tr[0]/tc[0]/p[0]',
      ]);
      expect(_locations(into, DocxWarningCode.styleNotFound, 'Kayip'), <String>[
        'body/tbl[0]/tr[1]/tc[0]/p[0]',
      ]);
    });

    test('undoing the insert takes the count back', () {
      final DocxDocument from = _open(_foreignTable);
      final DocxTable table = from.body.blocks.single as DocxTable;
      from.body.removeBlockAt(0);
      final DocxDocument into = DocxDocument();
      final DocxEdits edits = editsOf(into);
      final ChangeSet set = edits.transaction(
        () => into.body.insertBlock(0, table),
      );
      edits.log.revertSet(set);
      from.body.insertBlock(0, table);
      expect(from.save().warnings, isEmpty);
    });

    test('a style read in a table of this document is not reported', () {
      final DocxDocument doc = _open(_foreignTable);
      // Loading the styles makes the check run at the save.
      expect(doc.styles, isNotNull);
      doc.body.addParagraph('x');
      expect(doc.save().warnings, isEmpty);
    });
  });
}

/// The only cell of [row].
DocxTableCell _rowCell(DocxTableRow row) => row.cells.single;

/// A new row of [cell] only.
DocxTableRow _rowOf(DocxTableCell cell) => DocxTableRow()
  ..insertCellAt(0, cell)
  ..removeCellAt(1);

/// A sink that keeps what it is given.
final class _Chunks implements Sink<List<int>> {
  _Chunks(this._chunks);

  final List<List<int>> _chunks;

  @override
  void add(List<int> data) => _chunks.add(data);

  @override
  void close() {}
}
