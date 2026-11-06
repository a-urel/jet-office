// Tests writing the main document part from the body model: an unchanged
// read writes back the same document, kept content keeps its namespace
// declarations, text set through the API follows the text rules, and the
// characters removed from it are reported at save with the run's final
// location. They build XML in memory, so they run on the web as well.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/document_part.dart';
import 'package:jet_office/src/docx/model/blocks.dart';
import 'package:jet_office/src/docx/model/primitives.dart';
import 'package:jet_office/src/docx/warnings.dart' show DocxWarningCollector;
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../../tool/src/part_compare.dart';

/// The part name every test reads and writes.
const String _part = '/word/document.xml';

/// The namespace declarations the documents of these tests carry.
const String _decls =
    'xmlns:w="${Ns.w}" xmlns:w14="${Ns.w14}" xmlns:mc="${Ns.mc}" '
    'mc:Ignorable="w14"';

/// The document whose body holds [body].
String _doc(String body) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document $_decls><w:body>$body</w:body></w:document>';

/// Reads the whole document [xml].
DocumentPart _read(String xml) => DocumentPart.read(
  XmlPullReader(xml),
  DocxWarningCollector(),
  _part,
  limits: const DocxReadLimits(),
);

/// The part's bytes, joined.
Uint8List _bytes(DocumentPart part) {
  final BytesBuilder out = BytesBuilder(copy: false);
  part.encode().forEach(out.add);
  return out.takeBytes();
}

/// The part as text.
String _encode(DocumentPart part) => utf8.decode(_bytes(part));

/// The differences between [xml] and what reading and writing it gives.
List<String> _roundTrip(String xml) =>
    compareXmlParts(_part, utf8.encode(xml), _bytes(_read(xml)));

/// [xml], an element, captured as it would be read.
OpaqueXml _capture(String xml) {
  final XmlPullReader r = XmlPullReader('<a xmlns:w="${Ns.w}">$xml</a>')
    ..next()
    ..next();
  return OpaqueXml.capture(r);
}

/// The paragraph at [index] of [part].
DocxParagraph _p(DocumentPart part, [int index = 0]) =>
    part.blocks[index] as DocxParagraph;

/// The run at [index] of the paragraph [p].
DocxRun _r(DocxParagraph p, [int index = 0]) => p.inlines[index] as DocxRun;

/// The `(code, locations, count)` of the warnings of the last encode.
List<String> _warnings(DocumentPart part) => <String>[
  for (final DocxWarning w in part.encodeWarnings.warnings)
    '${w.code.name} ${w.part} ${w.locations} ${w.count}',
];

/// The prefixes used in element and attribute names in [doc] that are not
/// declared on the element or an ancestor.
List<String> _unboundPrefixes(XmlDocument doc) {
  final List<String> unbound = <String>[];
  void visit(XmlElement e, Set<String> above) {
    final Set<String> scope = <String>{
      ...above,
      for (final XmlAttribute a in e.attributes)
        if (a.name.prefix == 'xmlns') a.name.local,
    };
    void check(XmlName name) {
      final String? prefix = name.prefix;
      if (prefix == null || prefix == 'xml' || prefix == 'xmlns') return;
      if (!scope.contains(prefix)) unbound.add('${e.name.qualified}: $prefix');
    }

    check(e.name);
    for (final XmlAttribute a in e.attributes) {
      check(a.name);
    }
    for (final XmlElement child in e.childElements) {
      visit(child, scope);
    }
  }

  visit(doc.rootElement, const <String>{});
  return unbound;
}

/// The elements of [doc] named [local] in the namespace [uri].
List<XmlElement> _elements(XmlDocument doc, String uri, String local) =>
    <XmlElement>[
      for (final XmlElement e in doc.descendantElements)
        if (e.name.local == local && e.name.namespaceUri == uri) e,
    ];

/// The value of the attribute [local] in the namespace [uri] on [e].
String? _attribute(XmlElement e, String uri, String local) {
  for (final XmlAttribute a in e.attributes) {
    if (a.name.local == local && a.name.namespaceUri == uri) return a.value;
  }
  return null;
}

/// The `w:t` elements of [xml], as written.
List<String> _texts(String xml) => <String>[
  for (final Match m in RegExp(r'<w:t[ />][^<]*(</w:t>)?').allMatches(xml))
    m.group(0)!,
];

void main() {
  test('read then encode is semantically equal', () {
    const String xml =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document $_decls '
        'xmlns:r="${Ns.rel}">'
        '<w:background w:color="FFFFFF"/>'
        '<w:body w14:x="1">'
        '<w:p w:rsidR="00A1" w14:paraId="1A2B3C4D" w14:textId="77777777">'
        '<w:pPr><w:pStyle w:val="Title"/><w:keepNext/><w:jc w:val="center"/>'
        '<w:rPr><w:b/></w:rPr></w:pPr>'
        '<w:bookmarkStart w:id="0" w:name="a"/>'
        '<w:r w:rsidR="00B2"><w:rPr><w:rStyle w:val="Emph"/><w:b/>'
        '<w14:ligatures w14:val="all"/></w:rPr>'
        '<w:t xml:space="preserve"> Hello  </w:t><w:tab/><w:t>world</w:t>'
        '<w:br w:type="page"/><w:br w:type="textWrapping" w:clear="all"/>'
        '<w:br/><w:cr/><w:t/>'
        '<mc:AlternateContent><mc:Choice Requires="w14"><w:drawing/>'
        '</mc:Choice><mc:Fallback><w:pict/></mc:Fallback>'
        '</mc:AlternateContent>'
        '<w:fldChar w:fldCharType="begin"/></w:r>'
        '<w:ins w:id="1" w:author="A"><w:r><w:t>c</w:t></w:r></w:ins>'
        '<w:bookmarkEnd w:id="0"/>'
        '<w:hyperlink r:id="rId4"><w:r><w:t>link</w:t></w:r></w:hyperlink>'
        '</w:p>'
        '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>cell</w:t></w:r></w:p></w:tc>'
        '</w:tr></w:tbl>'
        '<w:p/>'
        '<w:p><w:pPr><w:sectPr><w:pgSz w:w="12240"/></w:sectPr></w:pPr></w:p>'
        '<w:sectPr w:rsidR="00C3"><w:pgSz w:w="12240" w:h="15840"/>'
        '</w:sectPr>'
        '</w:body>'
        '<w:extra/>'
        '</w:document>';
    expect(_roundTrip(xml), isEmpty);
  });

  test('a document with another prefix or a default namespace round-trips', () {
    const String ns0 =
        '<ns0:document xmlns:ns0="${Ns.w}"><ns0:body>'
        '<ns0:p><ns0:pPr><ns0:pStyle ns0:val="T"/></ns0:pPr>'
        '<ns0:r><ns0:rPr><ns0:rStyle ns0:val="E"/></ns0:rPr>'
        '<ns0:t>a</ns0:t><ns0:br ns0:type="page"/></ns0:r></ns0:p>'
        '</ns0:body></ns0:document>';
    expect(_roundTrip(ns0), isEmpty);
    const String plain =
        '<document xmlns="${Ns.w}"><body>'
        '<p><r><t>a</t><tab/></r></p>'
        '</body></document>';
    expect(_roundTrip(plain), isEmpty);
    // A style set on a document whose WordprocessingML prefix is not `w`.
    final DocumentPart part = _read(plain);
    _p(part).style = 'Title';
    final XmlDocument doc = XmlDocument.parse(_encode(part));
    expect(_unboundPrefixes(doc), isEmpty);
    final XmlElement pStyle = _elements(doc, Ns.w, 'pStyle').single;
    expect(_attribute(pStyle, Ns.w, 'val'), 'Title');
  });

  group('tables', () {
    /// A table with attributes, properties out of no order, kept children
    /// between rows and cells, and a nested table.
    const String table =
        '<w:tbl w:rsidR="00A1"><w:bookmarkStart w:id="0" w:name="a"/>'
        '<w:tblPr w:rsidR="1"><w:tblStyle w:val="TableGrid"/>'
        '<w:tblW w:w="0" w:type="auto"/><w:tblCaption w:val="c"/></w:tblPr>'
        '<w:tblGrid><w:gridCol w:w="abc"/><w:gridCol w:w="20"/></w:tblGrid>'
        '<w:bookmarkEnd w:id="0"/>'
        '<w:tr w:rsidR="2" w14:paraId="3A"><w:tblPrEx><w:tblW w:w="0"/>'
        '</w:tblPrEx><w:trPr><w:cantSplit/><w:hidden/></w:trPr>'
        '<w:bookmarkStart w:id="1" w:name="b"/>'
        '<w:tc w:rsidR="5"><w:tcPr><w:tcW w:w="20" w:type="dxa"/>'
        '<w:noWrap/></w:tcPr><w:p w14:paraId="4B"><w:r><w:t>a</w:t></w:r></w:p>'
        '<w:tbl><w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl><w:p/></w:tc>'
        '<w:sdt><w:sdtContent><w:tc><w:p/></w:tc></w:sdtContent></w:sdt>'
        '<w:bookmarkEnd w:id="1"/></w:tr>'
        '<w:customXml w:element="x"><w:tr/></w:customXml>'
        '<w:tr/></w:tbl>';

    test('a table saves semantically equal', () {
      expect(_roundTrip(_doc('<w:p/>$table<w:p/>')), isEmpty);
    });

    test('a table saves semantically equal with odd prefixes', () {
      const String ns0 =
          '<ns0:document xmlns:ns0="${Ns.w}" xmlns:q="${Ns.w14}"><ns0:body>'
          '<ns0:tbl ns0:rsidR="1"><ns0:tblPr><ns0:tblW ns0:w="0" '
          'ns0:type="auto"/></ns0:tblPr><ns0:tblGrid><ns0:gridCol ns0:w="20"/>'
          '</ns0:tblGrid><ns0:tr q:paraId="2"><ns0:trPr><ns0:cantSplit/>'
          '</ns0:trPr><ns0:tc><ns0:tcPr><ns0:gridSpan ns0:val="2"/></ns0:tcPr>'
          '<ns0:p><ns0:r><ns0:t>a</ns0:t></ns0:r></ns0:p></ns0:tc></ns0:tr>'
          '</ns0:tbl></ns0:body></ns0:document>';
      expect(_roundTrip(ns0), isEmpty);
      const String plain =
          '<document xmlns="${Ns.w}"><body><tbl><tblGrid><gridCol w="20"/>'
          '</tblGrid><tr><tc><tcPr><gridSpan val="2"/></tcPr><p><r><t>a</t>'
          '</r></p></tc></tr></tbl></body></document>';
      expect(_roundTrip(plain), isEmpty);
      // A prefix declared on the table, its row or its cell.
      const String local =
          '<v:document xmlns:v="${Ns.w}"><v:body>'
          '<u:tbl xmlns:u="${Ns.w}" xmlns:x="urn:x" x:a="1"><u:tr x:b="2">'
          '<t:tc xmlns:t="${Ns.w}" x:c="3"><x:kept/><t:p x:d="4"/></t:tc>'
          '<x:kept/></u:tr><u:tblPr x:e="5"/></u:tbl>'
          '</v:body></v:document>';
      final List<String> differences = _roundTrip(local);
      expect(differences, isEmpty);
      expect(
        _unboundPrefixes(XmlDocument.parse(_encode(_read(local)))),
        isEmpty,
      );
    });

    test('w:tblPr, w:trPr and w:tcPr are written in place', () {
      // No schema allows this order, and a part read must keep what it read.
      expect(
        _roundTrip(
          _doc(
            '<w:tbl><w:tblGrid/><w:tblPr/><w:tr><w:tc><w:p/><w:tcPr/></w:tc>'
            '<w:trPr/></w:tr><w:tblPr/><w:tblGrid/></w:tbl>',
          ),
        ),
        isEmpty,
      );
    });

    test('a file with no w:tblPr, w:trPr or w:tcPr gets none', () {
      expect(
        _roundTrip(_doc('<w:tbl><w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl>')),
        isEmpty,
      );
    });

    test('empty properties are written as read', () {
      expect(
        _roundTrip(
          _doc(
            '<w:tbl><w:tblPr></w:tblPr><w:tr><w:trPr/><w:tc><w:tcPr/><w:p/>'
            '</w:tc></w:tr></w:tbl>',
          ),
        ),
        isEmpty,
      );
    });

    test('a table last in the body and before the final sectPr', () {
      expect(
        _roundTrip(
          _doc(
            '<w:tbl><w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl>'
            '<w:sectPr><w:pgSz w:w="12240"/></w:sectPr>',
          ),
        ),
        isEmpty,
      );
    });

    group('a cell without a closing paragraph', () {
      test('a read cell without a closing paragraph is written as read', () {
        for (final String inner in <String>[
          '',
          '<w:tcPr/>',
          '<w:p/><w:bookmarkEnd w:id="1"/>',
          '<w:tbl><w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl>',
          '<w:sdt><w:sdtContent><w:p/></w:sdtContent></w:sdt>',
        ]) {
          final String body = '<w:tbl><w:tr><w:tc>$inner</w:tc></w:tr></w:tbl>';
          expect(_roundTrip(_doc(body)), isEmpty, reason: inner);
        }
      });

      /// The document of one cell of [inner], with what is needed to edit
      /// the cell: its part, its log and the primitives' arguments.
      (DocumentPart, DocxEdits, DocxTableCell) cellOf(String inner) {
        final DocumentPart part = _read(
          _doc('<w:tbl><w:tr><w:tc>$inner</w:tc></w:tr></w:tbl>'),
        );
        final DocxEdits edits = DocxEdits();
        adoptBlocks(edits, Object(), part.blocks);
        final DocxTable table = part.blocks.single as DocxTable;
        return (part, edits, table.rows.single.cells.single);
      }

      /// How many `w:p` the cell of [part] holds directly.
      int closing(DocumentPart part) {
        final XmlElement tc = _elements(
          XmlDocument.parse(_encode(part)),
          Ns.w,
          'tc',
        ).first;
        return tc.childElements
            .where((XmlElement e) => e.localName == 'p')
            .length;
      }

      test('one whose last block was removed gets one, and undoing that '
          'restores the exception', () {
        final (DocumentPart part, DocxEdits edits, DocxTableCell cell) = cellOf(
          '<w:p/><w:bookmarkEnd w:id="1"/><w:bookmarkStart w:id="2"/>',
        );
        expect(closing(part), 1);
        final ChangeSet removal = edits.transaction(
          () => removeBlock(edits, cell, cellBlocksOf(cell), 2),
        );
        // The last is the bookmarkEnd, not the block read last.
        expect(closing(part), 2);
        // The added paragraph is not in blocks until the file is read again.
        expect(cell.blocks, hasLength(2));
        edits.log.revertSet(removal);
        expect(closing(part), 1);
      });

      /// The local name of the last child of the cell of [part].
      String last(DocumentPart part) => _elements(
        XmlDocument.parse(_encode(part)),
        Ns.w,
        'tc',
      ).first.childElements.last.localName;

      test('one read as p and bookmarkEnd gets one when the paragraph is '
          'removed, and undoing that restores the exception', () {
        final (DocumentPart part, DocxEdits edits, DocxTableCell cell) = cellOf(
          '<w:p/><w:bookmarkEnd w:id="1"/>',
        );
        expect(last(part), 'bookmarkEnd');
        final ChangeSet removal = edits.transaction(
          () => removeBlock(edits, cell, cellBlocksOf(cell), 0),
        );
        expect(cell.blocks.single, isA<DocxOpaqueBlock>());
        expect(last(part), 'p');
        edits.log.revertSet(removal);
        expect(last(part), 'bookmarkEnd');
        expect(closing(part), 1);
      });

      test('one read as p and bookmarkEnd gets one when the paragraph is '
          'replaced, and undoing that restores the exception', () {
        final (DocumentPart part, DocxEdits edits, DocxTableCell cell) = cellOf(
          '<w:p/><w:bookmarkEnd w:id="1"/>',
        );
        final ChangeSet replacement = edits.transaction(
          () => replaceBlock(
            edits,
            cell,
            cellBlocksOf(cell),
            0,
            DocxParagraph.text('b'),
          ),
        );
        expect(cell.blocks, hasLength(2));
        expect(last(part), 'p');
        expect(closing(part), 2);
        edits.log.revertSet(replacement);
        expect(last(part), 'bookmarkEnd');
        expect(closing(part), 1);
      });

      test('a block put before the one read last closes the cell', () {
        final (DocumentPart part, DocxEdits edits, DocxTableCell cell) = cellOf(
          '<w:bookmarkEnd w:id="1"/>',
        );
        final ChangeSet insertion = edits.transaction(
          () => insertBlock(
            edits,
            cell,
            cellBlocksOf(cell),
            0,
            DocxParagraph.text('b'),
          ),
        );
        expect(last(part), 'p');
        edits.log.revertSet(insertion);
        expect(last(part), 'bookmarkEnd');
      });

      test('a cell read empty is empty again once a block added goes', () {
        final (DocumentPart part, DocxEdits edits, DocxTableCell cell) = cellOf(
          '',
        );
        final ChangeSet insertion = edits.transaction(
          () => insertBlock(
            edits,
            cell,
            cellBlocksOf(cell),
            0,
            opaqueBlock(_capture('<w:bookmarkStart/>')),
          ),
        );
        expect(closing(part), 1);
        edits.log.revertSet(insertion);
        expect(closing(part), 0);
      });

      test('a cell emptied of its only block gets one', () {
        final (DocumentPart part, DocxEdits edits, DocxTableCell cell) = cellOf(
          '<w:p><w:r><w:t>a</w:t></w:r></w:p>',
        );
        edits.transaction(
          () => removeBlock(edits, cell, cellBlocksOf(cell), 0),
        );
        expect(cell.blocks, isEmpty);
        expect(closing(part), 1);
      });

      test('a cell read empty stays empty until a block goes in', () {
        final (DocumentPart part, DocxEdits edits, DocxTableCell cell) = cellOf(
          '',
        );
        expect(closing(part), 0);
        edits.transaction(
          () => insertBlock(
            edits,
            cell,
            cellBlocksOf(cell),
            0,
            opaqueBlock(_capture('<w:bookmarkStart/>')),
          ),
        );
        expect(closing(part), 1);
      });

      test('a paragraph that closes the cell needs no other', () {
        final (DocumentPart part, DocxEdits edits, DocxTableCell cell) = cellOf(
          '<w:bookmarkEnd w:id="1"/>',
        );
        edits.transaction(
          () => insertBlock(
            edits,
            cell,
            cellBlocksOf(cell),
            1,
            DocxParagraph.text('b'),
          ),
        );
        expect(closing(part), 1);
      });

      test('a table last in a cell gets one when it is not the one read', () {
        final (DocumentPart part, DocxEdits edits, DocxTableCell cell) = cellOf(
          '<w:tbl/><w:p/>',
        );
        expect(closing(part), 1);
        edits.transaction(
          () => removeBlock(edits, cell, cellBlocksOf(cell), 1),
        );
        expect(cell.blocks.single, isA<DocxTable>());
        expect(closing(part), 1);
      });
    });

    test('warnings name the path in the table', () {
      final DocumentPart part = _read(
        _doc(
          '<w:p/><w:tbl/><w:tbl><w:tr/><w:tr><w:tc/><w:tc><w:p/>'
          '<w:p><w:r/><w:r/></w:p><w:tbl/>'
          '<w:tbl><w:tr><w:tc><w:p><w:r/></w:p></w:tc></w:tr></w:tbl>'
          '</w:tc></w:tr></w:tbl><w:p><w:r/></w:p>',
        ),
      );
      final DocxTableCell cell = (part.blocks[2] as DocxTable).rows[1].cells[1];
      _r(cell.blocks[1] as DocxParagraph, 1).text = 'a\u0001';
      final DocxTable nested = cell.blocks[3] as DocxTable;
      _r(nested.rows.single.cells.single.blocks.single as DocxParagraph).text =
          'b\u0001';
      _r(_p(part, 3)).text = 'c\u0001';
      _encode(part);
      expect(_warnings(part), <String>[
        'invalidCharactersRemoved $_part '
            '[body/tbl[1]/tr[1]/tc[1]/p[1]/r[1], '
            'body/tbl[1]/tr[1]/tc[1]/tbl[1]/tr[0]/tc[0]/p[0]/r[0], '
            'body/p[1]/r[0]] 3',
      ]);
    });

    test('the checks of a list and a style name the path in the table', () {
      final DocumentPart part = _read(
        _doc('<w:tbl><w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl>'),
      );
      final DocxTable table = part.blocks.single as DocxTable;
      final DocxParagraph p =
          table.rows.single.cells.single.blocks.single as DocxParagraph;
      p.style = 'Missing';
      p.properties.numbering = DocxNumberingRef(7);
      part
        ..listDefined = ((int id) => false)
        ..styleDefined = ((String id, DocxStyleType type) => false);
      _encode(part);
      expect(
        part.encodeWarnings.warnings.map(
          (DocxWarning w) => '${w.code.name} ${w.locations}',
        ),
        <String>[
          'numberingNotFound [body/tbl[0]/tr[0]/tc[0]/p[0]]',
          'styleNotFound [body/tbl[0]/tr[0]/tc[0]/p[0]]',
        ],
      );
    });
  });

  test('a document without a body writes none', () {
    expect(
      _roundTrip('<w:document $_decls><w:background/></w:document>'),
      isEmpty,
    );
  });

  group('kept styles', () {
    // A pStyle or rStyle that is not exactly one non-empty w:val, with no
    // other w attribute and no content, is not typed, so it round-trips as
    // written.
    for (final String style in <String>[
      'w:val=""',
      '',
      'w:val="Title" w:x="1"',
    ]) {
      test('<pStyle $style/> and <rStyle $style/> round-trip', () {
        final String xml = _doc(
          '<w:p><w:pPr><w:pStyle $style/></w:pPr>'
          '<w:r><w:rPr><w:rStyle $style/></w:rPr><w:t>a</w:t></w:r></w:p>',
        );
        final DocumentPart part = _read(xml);
        expect(_p(part).style, isNull);
        expect(_r(_p(part)).style, isNull);
        expect(_roundTrip(xml), isEmpty);
      });
    }

    test('a style with a w14 attribute is typed and round-trips', () {
      // Attributes in other namespaces are ignored for typing (plan Ruling
      // 2); the element is written as read until the style is set.
      final String xml = _doc(
        '<w:p><w:pPr><w:pStyle w:val="Title" w14:x="1"/></w:pPr>'
        '<w:r><w:rPr><w:rStyle w:val="Strong" w14:x="1"/></w:rPr>'
        '<w:t>a</w:t></w:r></w:p>',
      );
      final DocumentPart part = _read(xml);
      expect(_p(part).style, 'Title');
      expect(_r(_p(part)).style, 'Strong');
      expect(_roundTrip(xml), isEmpty);
    });

    test('a style with child elements is not typed and round-trips as '
        'read', () {
      // The schema gives pStyle and rStyle no children, so the model cannot
      // type one that has them without dropping them.
      final String xml = _doc(
        '<w:p><w:pPr><w:pStyle w:val="Title"><w:x/></w:pStyle></w:pPr>'
        '<w:r><w:rPr><w:rStyle w:val="Strong"><w:y/></w:rStyle></w:rPr>'
        '<w:t>a</w:t></w:r></w:p>',
      );
      final DocumentPart part = _read(xml);
      expect(_p(part).style, isNull);
      expect(_r(_p(part)).style, isNull);
      expect(_roundTrip(xml), isEmpty);
      // Setting the style replaces the element and its children.
      _p(part).style = 'Heading1';
      final String out = _encode(part);
      expect(out, contains('<w:pStyle w:val="Heading1"/>'));
      expect(out, isNot(contains('<w:x')));
      expect(out, contains('<w:y/>'));
    });
  });

  test('mc:AlternateContent and w14 attributes keep their declarations', () {
    final String xml = _doc(
      '<w:p w14:paraId="1A2B3C4D" w14:textId="77777777">'
      '<w:pPr><w:pStyle w:val="Title"/></w:pPr>'
      '<w:r><w:t>a</w:t>'
      '<mc:AlternateContent><mc:Choice Requires="w14"><w:drawing/>'
      '</mc:Choice><mc:Fallback><w:pict/></mc:Fallback>'
      '</mc:AlternateContent></w:r><w:r><w:t>b</w:t></w:r></w:p>',
    );
    final DocumentPart part = _read(xml);
    // Edits next to the kept content.
    _p(part).style = 'Heading1';
    _r(_p(part), 1).text = 'c';
    final String out = _encode(part);
    final XmlDocument doc = XmlDocument.parse(out);
    expect(_unboundPrefixes(doc), isEmpty);
    // The root keeps every declaration, so each mc:Ignorable token resolves.
    final XmlElement root = doc.rootElement;
    final String ignorable = _attribute(root, Ns.mc, 'Ignorable')!;
    for (final String prefix in ignorable.split(' ')) {
      expect(root.getAttribute('xmlns:$prefix'), isNotNull, reason: prefix);
    }
    // Nothing below the root declares the root's namespaces again.
    for (final XmlElement e in root.descendantElements) {
      for (final XmlAttribute a in e.attributes) {
        expect(a.name.prefix, isNot('xmlns'), reason: e.name.qualified);
      }
    }
    final XmlElement p = _elements(doc, Ns.w, 'p').single;
    expect(_attribute(p, Ns.w14, 'paraId'), '1A2B3C4D');
    expect(_elements(doc, Ns.mc, 'AlternateContent'), hasLength(1));
  });

  test('a new document declares only w', () {
    final DocumentPart part = DocumentPart.create()
      ..blocks.add(DocxParagraph.text('Hello'));
    final XmlDocument doc = XmlDocument.parse(_encode(part));
    final XmlElement root = doc.rootElement;
    expect(root.name.qualified, 'w:document');
    expect(
      <String>[for (final XmlAttribute a in root.attributes) a.name.qualified],
      <String>['xmlns:w'],
    );
    expect(root.getAttribute('xmlns:w'), Ns.w);
    expect(_unboundPrefixes(doc), isEmpty);
    expect(
      _encode(part),
      endsWith(
        '<w:body><w:p><w:r><w:t>Hello</w:t></w:r></w:p></w:body>'
        '</w:document>',
      ),
    );
  });

  group('warnings at save', () {
    test('setting text with U+0001 removes it and warns at body/p[0]/r[0] on '
        'save', () {
      final DocumentPart part = _read(
        _doc('<w:p><w:r><w:t>x</w:t></w:r></w:p>'),
      );
      _r(_p(part)).text = 'a\u0001b';
      expect(part.encodeWarnings.warnings, isEmpty);
      final String out = _encode(part);
      expect(_texts(out), <String>['<w:t>ab</w:t>']);
      expect(_warnings(part), <String>[
        'invalidCharactersRemoved $_part [body/p[0]/r[0]] 1',
      ]);
    });

    test('a detached paragraph with U+0001 inserted at index 5 warns at '
        'body/p[5]/r[0]', () {
      final DocxParagraph detached = DocxParagraph.text('a\u0001\u0002b');
      final DocumentPart part = _read(
        _doc('<w:p/><w:tbl/><w:p/><w:p/><w:p/><w:p/><w:p/>'),
      );
      // Index 5 among the paragraphs: the table before them does not count.
      part.blocks.insert(6, detached);
      _encode(part);
      expect(_warnings(part), <String>[
        'invalidCharactersRemoved $_part [body/p[5]/r[0]] 2',
      ]);
    });

    test('r[j] counts runs only', () {
      final DocumentPart part = _read(
        _doc('<w:p><w:proofErr/><w:r/><w:ins/><w:r/></w:p>'),
      );
      _r(_p(part), 3).text = '\u0001';
      _encode(part);
      expect(_warnings(part), <String>[
        'invalidCharactersRemoved $_part [body/p[0]/r[1]] 1',
      ]);
    });

    test('a run removed before save does not warn', () {
      final DocumentPart part = _read(_doc('<w:p><w:r/></w:p>'));
      _r(_p(part)).text = 'a\u0001';
      _p(part).removeInlineAt(0);
      _encode(part);
      expect(part.encodeWarnings.warnings, isEmpty);
    });

    test('encoding twice does not double the warnings', () {
      final DocumentPart part = DocumentPart.create()
        ..blocks.add(DocxParagraph.text('a\u0001'));
      _encode(part);
      _encode(part);
      expect(_warnings(part), <String>[
        'invalidCharactersRemoved $_part [body/p[0]/r[0]] 1',
      ]);
    });
  });

  test('edge and double spaces get xml:space preserve', () {
    final DocumentPart part = DocumentPart.create();
    for (final String text in <String>[' a', 'a ', 'a  b', 'a b', 'ab']) {
      part.blocks.add(DocxParagraph.text(text));
    }
    expect(_texts(_encode(part)), <String>[
      '<w:t xml:space="preserve"> a</w:t>',
      '<w:t xml:space="preserve">a </w:t>',
      '<w:t xml:space="preserve">a  b</w:t>',
      '<w:t>a b</w:t>',
      '<w:t>ab</w:t>',
    ]);
  });

  test('tab and newline in set text write w:tab and w:br', () {
    final DocumentPart part = DocumentPart.create()
      ..blocks.add(DocxParagraph.text('a\tb\nc\r\nd\re'));
    expect(
      _encode(part),
      contains(
        '<w:r><w:t>a</w:t><w:tab/><w:t>b</w:t><w:br/><w:t>c</w:t><w:br/>'
        '<w:t>d</w:t><w:br/><w:t>e</w:t></w:r>',
      ),
    );
  });

  test('an opened w:t keeps xml:space as read', () {
    final DocumentPart part = _read(
      _doc(
        '<w:p><w:r><w:t xml:space="preserve">a</w:t><w:t> b </w:t>'
        '<w:t xml:space="default">c  d</w:t></w:r></w:p>',
      ),
    );
    expect(_texts(_encode(part)), <String>[
      '<w:t xml:space="preserve">a</w:t>',
      '<w:t> b </w:t>',
      '<w:t xml:space="default">c  d</w:t>',
    ]);
  });

  test('a read text set through the API gets the computed xml:space once', () {
    final DocumentPart part = _read(
      _doc(
        '<w:p><w:r><w:t xml:space="preserve">a</w:t></w:r>'
        '<w:r><w:t xml:space="default">b</w:t></w:r></w:p>',
      ),
    );
    _r(_p(part)).text = 'x';
    _r(_p(part), 1).text = ' y';
    expect(_texts(_encode(part)), <String>[
      '<w:t>x</w:t>',
      '<w:t xml:space="preserve"> y</w:t>',
    ]);
  });

  test('a set style is written in schema order', () {
    final DocumentPart part = _read(
      _doc(
        '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
        '<w:r><w:rPr><w:b/></w:rPr><w:t>a</w:t></w:r></w:p>',
      ),
    );
    _p(part).style = 'Title';
    _r(_p(part)).style = 'Emph';
    expect(
      _encode(part),
      contains(
        '<w:p><w:pPr><w:pStyle w:val="Title"/><w:jc w:val="center"/></w:pPr>'
        '<w:r><w:rPr><w:rStyle w:val="Emph"/><w:b/></w:rPr><w:t>a</w:t>'
        '</w:r></w:p>',
      ),
    );
  });

  group('run properties', () {
    const String rPr =
        '<w:rPr><w:rStyle w:val="Strong"/>'
        '<w:rFonts w:asciiTheme="minorHAnsi" w:hAnsiTheme="minorHAnsi" '
        'w:cs="Arial" w:cstheme="minorBidi" w:hint="eastAsia"/>'
        '<w:b w:val="on"/><w:bCs/><w:i w:val="1"/><w:color w:val="4472C4" '
        'w:themeColor="accent1" w:themeTint="BF"/><w:spacing w:val="024"/>'
        '<w:kern w:val="2"/><w:sz w:val="1in"/><w:szCs w:val="22"/>'
        '<w:highlight w:val="orange"/><w:u w:val="single" w:color="FF0000"/>'
        '<w:shd w:val="clear" w:color="auto" w:fill="FFFF00"/>'
        '<w:vertAlign w:val="superscript"/>'
        '<w:lang w:val="tr-TR" w:eastAsia="ja-JP" w:bidi="ar-SA"/>'
        '<w14:ligatures w14:val="standard"/></w:rPr>';

    test('a Word run round-trips and reads its typed properties', () {
      final String xml = _doc('<w:p><w:r>$rPr<w:t>a</w:t></w:r></w:p>');
      expect(_roundTrip(xml), isEmpty);
      final DocxRunProperties p = _r(_p(_read(xml))).properties;
      expect(p.style, 'Strong');
      expect(p.fonts?.asciiTheme, 'minorHAnsi');
      expect(p.bold, isTrue);
      expect(p.italic, isTrue);
      expect(p.color, DocxColor.theme(DocxThemeColor.accent1, tint: 0xBF));
      expect(p.characterSpacingPt, 1.2);
      expect(p.sizePt, isNull);
      expect(p.highlight, isNull);
      expect(p.underline?.color, DocxColor.rgb('FF0000'));
      expect(p.shading?.fill, DocxColor.rgb('FFFF00'));
      expect(p.verticalAlign, DocxVerticalAlign.superscript);
      expect(p.language, 'tr-TR');
    });

    test('a run with nothing set writes no rPr', () {
      final DocumentPart part = _read(
        _doc('<w:p><w:r><w:t>a</w:t></w:r></w:p>'),
      );
      _r(_p(part)).properties.bold = null;
      expect(_encode(part), isNot(contains('rPr')));
      _r(_p(part)).properties.bold = true;
      expect(_encode(part), contains('<w:rPr><w:b/></w:rPr>'));
    });

    test('a prefix other than w is used for the properties set', () {
      final DocumentPart part = _read(
        '<?xml version="1.0"?><x:document xmlns:x="${Ns.w}"><x:body><x:p>'
        '<x:r><x:t>a</x:t></x:r></x:p></x:body></x:document>',
      );
      _r(_p(part)).properties
        ..bold = true
        ..fonts = DocxFonts.all('Arial');
      expect(
        _encode(part),
        contains(
          '<x:rPr><x:rFonts x:ascii="Arial" x:hAnsi="Arial" '
          'x:eastAsia="Arial"/><x:b/></x:rPr>',
        ),
      );
    });
  });
}
