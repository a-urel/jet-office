// Tests the model copies the template fill's sections are made of (T2,
// decision 0024): `copyInlines`, `copyRows` and `copyBlocks` give detached,
// marked copies that leave annotations out and leave the source unchanged,
// and `splitRunAt` splits a run as one recorded change. They build documents
// in memory, so they run on the web as well.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart'
    show changeLogOf, documentTransaction;
import 'package:jet_office/src/docx/model/blocks.dart'
    show copyBlocks, copyRows, opaqueBlockXml;
import 'package:jet_office/src/docx/model/inlines.dart'
    show copyInlines, opaqueInlineXml, paragraphOf, splitRunAt;
import 'package:jet_office/src/docx/model/template_copies.dart'
    show CopyResult, copyDroppedNames, isTemplateCopy;
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

import '../../../tool/src/docx_serialize.dart' show encodedMainDifferences;
import '../../fixtures/m4_fixtures.dart' show png4x2;
import '../../support/read_xlsx.dart';
import '../support/docx_builder.dart';

const String _decls =
    'xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}" xmlns:w14="${Ns.w14}"';

Uint8List _docx(String body) => buildDocx(
  document:
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document $_decls><w:body>$body</w:body></w:document>',
);

DocxDocument _open(String body) => DocxDocument.open(_docx(body));

/// The XML of `w:body` in the main part of [bytes].
String _bodyXml(Uint8List bytes) {
  final String xml = utf8.decode(readXlsxBytes(bytes)['word/document.xml']!);
  return xml.substring(
    xml.indexOf('<w:body>') + '<w:body>'.length,
    xml.indexOf('</w:body>'),
  );
}

/// The `w:p` elements of [body], each as written.
List<String> _paragraphs(String body) => RegExp(
  r'<w:p(?:\s[^>]*)?>.*?</w:p>|<w:p(?:\s[^>]*)?/>',
).allMatches(body).map((Match m) => m[0]!).toList();

/// [xml] with every `w:id` value and `w14:` attribute taken out, which a save
/// renews in copies.
String _withoutIds(String xml) => xml
    .replaceAll(RegExp(r' w:id="[^"]*"'), '')
    .replaceAll(RegExp(r' w14:[A-Za-z]+="[^"]*"'), '');

DocxParagraph _p(DocxDocument doc, int index) =>
    doc.body.blocks[index] as DocxParagraph;

void _insertAll(DocxParagraph p, List<DocxInline> inlines) {
  for (final DocxInline inline in inlines) {
    p.insertInline(p.inlines.length, inline);
  }
}

const String _mixed =
    '<w:p>'
    '<w:r w:rsidR="00AB12CD"><w:rPr><w:b/></w:rPr><w:t>a</w:t></w:r>'
    '<w:hyperlink w:anchor="x" w:history="1"><w:r><w:t>b</w:t></w:r>'
    '</w:hyperlink>'
    '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
    '<w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'
    '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
    '<w:r><w:t>1</w:t></w:r>'
    '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
    '<w:ins w:id="5" w:author="A" w:date="2026-11-16T00:00:00Z">'
    '<w:r><w:t>c</w:t></w:r></w:ins>'
    '</w:p>'
    '<w:p/>';

/// The nesting a copy reads kept elements to, as the default read limits.
const int _depth = 256;

void main() {
  group('copyInlines', () {
    test('copies runs, hyperlinks, fields and opaque inlines, detached, '
        'source unchanged', () {
      final DocxDocument doc = _open(_mixed);
      final DocxParagraph source = _p(doc, 0);
      final String before = _bodyXml(doc.save().bytes);
      final List<DocxInline> originals = List<DocxInline>.of(source.inlines);
      expect(originals.map((DocxInline i) => i.runtimeType), <Type>[
        DocxRun,
        DocxHyperlink,
        DocxField,
        DocxOpaqueInline,
      ]);

      final CopyResult<DocxInline> copy = copyInlines(
        maxDepth: _depth,
        source.inlines,
      );

      expect(copy.items, hasLength(4));
      expect(copy.dropped, isEmpty);
      for (int i = 0; i < 4; i++) {
        expect(identical(copy.items[i], originals[i]), isFalse);
        expect(copy.items[i].runtimeType, originals[i].runtimeType);
        expect(copy.items[i].text, originals[i].text);
        expect(paragraphOf(copy.items[i]), isNull);
        expect(isTemplateCopy(copy.items[i]), isTrue);
        expect(isTemplateCopy(originals[i]), isFalse);
      }
      expect(source.inlines, originals);
      expect(_bodyXml(doc.save().bytes), before);

      _insertAll(_p(doc, 1), copy.items);
      final Uint8List saved = doc.save().bytes;
      final List<String> paragraphs = _paragraphs(_bodyXml(saved));
      expect(_bodyXml(doc.save().bytes), _bodyXml(saved));
      expect(_withoutIds(paragraphs[1]), _withoutIds(paragraphs[0]));
      expect(_p(doc, 1).text, source.text);
    });

    test('a copied run keeps its properties and set values; later sets do '
        'not reach the source', () {
      final DocxDocument doc = _open(_mixed);
      final DocxRun source = _p(doc, 0).inlines.first as DocxRun;
      source.properties.italic = true;

      final DocxRun copy =
          copyInlines(maxDepth: _depth, <DocxInline>[source]).items.single
              as DocxRun;

      expect(copy.properties.bold, isTrue);
      expect(copy.properties.italic, isTrue);
      copy.properties.bold = false;
      expect(source.properties.bold, isTrue);
      source.properties.italic = false;
      expect(copy.properties.italic, isTrue);
    });

    test('copies drop typed bookmarks and comment and permission marks, '
        'naming them', () {
      final DocxDocument doc = _open(
        '<w:p>'
        '<w:bookmarkStart w:id="1" w:name="b"/>'
        '<w:commentRangeStart w:id="2"/>'
        '<w:permStart w:id="3" w:edGrp="everyone"/>'
        '<w:r><w:t>x</w:t></w:r>'
        '<w:permEnd w:id="3"/>'
        '<w:commentRangeEnd w:id="2"/>'
        '<w:bookmarkEnd w:id="1"/>'
        '</w:p>',
      );
      final DocxParagraph source = _p(doc, 0);

      final CopyResult<DocxInline> copy = copyInlines(
        maxDepth: _depth,
        source.inlines,
      );

      expect(copy.dropped, <String>{
        'bookmarkStart',
        'bookmarkEnd',
        'commentRangeStart',
        'commentRangeEnd',
        'permStart',
        'permEnd',
      });
      expect(copy.items, hasLength(1));
      expect((copy.items.single as DocxRun).text, 'x');
      expect(source.inlines, hasLength(7));
      expect(copyDroppedNames, containsAll(copy.dropped));
    });

    test('copies drop comment and note references from runs, naming them', () {
      final DocxDocument doc = _open(
        '<w:p>'
        '<w:r><w:t>x</w:t><w:commentReference w:id="2"/></w:r>'
        '<w:r><w:rPr><w:vertAlign w:val="superscript"/></w:rPr>'
        '<w:footnoteReference w:id="1"/></w:r>'
        '</w:p>',
      );
      final DocxParagraph source = _p(doc, 0);

      final CopyResult<DocxInline> copy = copyInlines(
        maxDepth: _depth,
        source.inlines,
      );

      expect(copy.dropped, <String>{'commentReference', 'footnoteReference'});
      expect(copy.items, hasLength(2));
      final DocxRun first = copy.items[0] as DocxRun;
      final DocxRun second = copy.items[1] as DocxRun;
      expect(first.content, <DocxRunContent>[const DocxText('x')]);
      expect(second.content, isEmpty);
      expect(second.properties.verticalAlign, isNotNull);
      expect((source.inlines[0] as DocxRun).content, hasLength(2));
      expect((source.inlines[1] as DocxRun).content, hasLength(1));
    });

    test('copies drop custom XML range marks, naming them', () {
      final DocxDocument doc = _open(
        '<w:p><w:customXmlInsRangeStart w:id="1" w:author="A"/>'
        '<w:customXmlInsRangeEnd w:id="1"/>'
        '<w:customXmlDelRangeStart w:id="2" w:author="A"/>'
        '<w:customXmlDelRangeEnd w:id="2"/>'
        '<w:customXmlMoveFromRangeStart w:id="3" w:author="A"/>'
        '<w:customXmlMoveFromRangeEnd w:id="3"/>'
        '<w:customXmlMoveToRangeStart w:id="4" w:author="A"/>'
        '<w:customXmlMoveToRangeEnd w:id="4"/>'
        '<w:r><w:t>x</w:t></w:r></w:p>',
      );

      final CopyResult<DocxInline> copy = copyInlines(
        maxDepth: _depth,
        _p(doc, 0).inlines,
      );

      expect(copy.items, hasLength(1));
      expect(copy.dropped, <String>{
        'customXmlInsRangeStart',
        'customXmlInsRangeEnd',
        'customXmlDelRangeStart',
        'customXmlDelRangeEnd',
        'customXmlMoveFromRangeStart',
        'customXmlMoveFromRangeEnd',
        'customXmlMoveToRangeStart',
        'customXmlMoveToRangeEnd',
      });
    });

    test('copies read kept elements as deep as the document allows, and a '
        'deeper one throws DocxReadException', () {
      final String open = '<w:customXml w:element="x">' * 300;
      final String close = '</w:customXml>' * 300;
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '<w:p>$open<w:bookmarkStart w:id="1" w:name="b"/>'
          '<w:r><w:t>x</w:t></w:r>$close</w:p>',
        ),
        limits: const DocxReadLimits(maxDepth: 1000),
      );
      final List<DocxInline> source = _p(doc, 0).inlines;

      final CopyResult<DocxInline> copy = copyInlines(maxDepth: 1000, source);

      expect(copy.dropped, <String>{'bookmarkStart'});
      expect(copy.items.single.text, 'x');
      expect(
        () => copyInlines(maxDepth: 100, source),
        throwsA(
          isA<DocxReadException>().having(
            (DocxReadException e) => e.reason,
            'reason',
            DocxReadFailure.limitExceeded,
          ),
        ),
      );
    });

    test('copies drop annotations inside an opaque w:ins slice', () {
      final DocxDocument doc = _open(
        '<w:p><w:ins w:id="5" w:author="A">'
        '<w:bookmarkStart w:id="1" w:name="b"/><w:r><w:t>c</w:t></w:r>'
        '<w:bookmarkEnd w:id="1"/></w:ins></w:p>',
      );
      final DocxOpaqueInline source =
          _p(doc, 0).inlines.single as DocxOpaqueInline;

      final CopyResult<DocxInline> copy = copyInlines(
        maxDepth: _depth,
        <DocxInline>[source],
      );

      final DocxOpaqueInline ins = copy.items.single as DocxOpaqueInline;
      expect(copy.dropped, <String>{'bookmarkStart', 'bookmarkEnd'});
      expect(opaqueInlineXml(ins).xml, isNot(contains('bookmark')));
      expect(opaqueInlineXml(ins).xml, contains('<w:t>c</w:t>'));
      expect(ins.text, 'c');
      expect(opaqueInlineXml(source).xml, contains('w:bookmarkStart'));
    });

    test('copies of a built picture and a built hyperlink save valid', () {
      final DocxDocument doc = _open('<w:p/><w:p/>');
      final DocxParagraph source = _p(doc, 0);
      source.addPicture(OfficeImage(png4x2));
      source.addHyperlink('site', url: 'https://example.com/a');

      _insertAll(
        _p(doc, 1),
        copyInlines(maxDepth: _depth, source.inlines).items,
      );
      final Uint8List first = doc.save().bytes;
      final Uint8List second = doc.save().bytes;
      expect(second, first);
      expect(encodedMainDifferences(first), isEmpty);

      final DocxDocument back = DocxDocument.open(first);
      final List<DocxPicture> pictures = <DocxPicture>[];
      final List<DocxHyperlink> links = <DocxHyperlink>[];
      for (final DocxBlock block in back.body.blocks) {
        for (final DocxInline inline in (block as DocxParagraph).inlines) {
          if (inline is DocxHyperlink) links.add(inline);
          if (inline is DocxRun) {
            pictures.addAll(inline.content.whereType<DocxPicture>());
          }
        }
      }
      expect(pictures, hasLength(2));
      expect(pictures.every((DocxPicture p) => p.image != null), isTrue);
      expect(links.map((DocxHyperlink l) => l.url), <String>[
        'https://example.com/a',
        'https://example.com/a',
      ]);
    });

    test('inserting copies is undone with the transaction', () {
      final DocxDocument doc = _open(_mixed);
      final DocxParagraph target = _p(doc, 1);
      final ChangeSet set = documentTransaction(
        doc,
        () => _insertAll(
          target,
          copyInlines(maxDepth: _depth, _p(doc, 0).inlines).items,
        ),
      );
      expect(target.inlines, hasLength(4));

      changeLogOf(doc).undo(set);

      expect(target.inlines, isEmpty);
    });
  });

  group('copyRows and copyBlocks', () {
    test('copyRows keeps row and cell properties', () {
      final DocxDocument doc = _open(
        '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/></w:tblPr>'
        '<w:tblGrid><w:gridCol w:w="2000"/><w:gridCol w:w="2000"/>'
        '</w:tblGrid>'
        '<w:tr w14:paraId="1A2B3C4D" w:rsidR="00AB12CD">'
        '<w:trPr><w:cantSplit/><w:trHeight w:val="500"/></w:trPr>'
        '<w:tc><w:tcPr><w:tcW w:w="4000" w:type="dxa"/>'
        '<w:gridSpan w:val="2"/><w:vMerge w:val="restart"/>'
        '<w:tcBorders><w:top w:val="single" w:sz="4" w:space="0" '
        'w:color="auto"/></w:tcBorders>'
        '<w:shd w:val="clear" w:color="auto" w:fill="D9D9D9"/></w:tcPr>'
        '<w:p w14:paraId="2B3C4D5E"><w:r><w:t>x</w:t></w:r></w:p>'
        '</w:tc></w:tr></w:tbl>'
        '<w:p/>',
      );
      final DocxTable table = doc.body.blocks.first as DocxTable;

      final CopyResult<DocxTableRow> copy = copyRows(
        maxDepth: _depth,
        table.rows,
      );

      expect(copy.items, hasLength(1));
      expect(copy.dropped, isEmpty);
      expect(isTemplateCopy(copy.items.single), isTrue);
      expect(identical(copy.items.single, table.rows.single), isFalse);
      table.insertRow(1, copy.items.single);
      final String body = _bodyXml(doc.save().bytes);
      final List<String> rows = RegExp(
        r'<w:tr[ >].*?</w:tr>',
      ).allMatches(body).map((Match m) => m[0]!).toList();
      expect(rows, hasLength(2));
      expect(_withoutIds(rows[1]), _withoutIds(rows[0]));
      expect(table.rows[1].properties.cantSplit, isTrue);
      expect(table.rows[1].cells.single.properties.gridSpan, 2);
    });

    test('copyBlocks copies paragraphs, nested tables and opaque blocks', () {
      final DocxDocument doc = _open(
        '<w:p><w:r><w:t>one</w:t></w:r></w:p>'
        '<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w="2000"/></w:tblGrid>'
        '<w:tr><w:tc>'
        '<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w="1000"/></w:tblGrid>'
        '<w:tr><w:tc><w:p><w:r><w:t>inner</w:t></w:r></w:p></w:tc></w:tr>'
        '</w:tbl><w:p/></w:tc></w:tr></w:tbl>'
        '<w:sdt><w:sdtPr><w:id w:val="77"/></w:sdtPr><w:sdtContent>'
        '<w:p><w:r><w:t>sdt</w:t></w:r></w:p></w:sdtContent></w:sdt>'
        '<w:p/>',
      );
      final List<DocxBlock> source = doc.body.blocks.sublist(0, 3);
      final String before = _bodyXml(doc.save().bytes);

      final CopyResult<DocxBlock> copy = copyBlocks(maxDepth: _depth, source);

      expect(copy.items, hasLength(3));
      expect(copy.dropped, isEmpty);
      expect((copy.items[0] as DocxParagraph).text, 'one');
      final DocxTable table = copy.items[1] as DocxTable;
      expect(identical(table, source[1]), isFalse);
      final DocxTable nested =
          table.rows.single.cells.single.blocks.first as DocxTable;
      expect(
        identical(
          nested,
          (source[1] as DocxTable).rows.single.cells.single.blocks.first,
        ),
        isFalse,
      );
      expect(
        (nested.rows.single.cells.single.blocks.single as DocxParagraph).text,
        'inner',
      );
      expect(
        opaqueBlockXml(copy.items[2] as DocxOpaqueBlock).xml,
        opaqueBlockXml(source[2] as DocxOpaqueBlock).xml,
      );
      expect(_bodyXml(doc.save().bytes), before);

      for (int i = 0; i < copy.items.length; i++) {
        doc.body.insertBlock(3 + i, copy.items[i]);
      }
      final String after = _bodyXml(doc.save().bytes);
      final int sdt = after.indexOf('<w:sdt>');
      expect(after.indexOf('<w:sdt>', sdt + 1), greaterThan(sdt));
      expect(
        doc.body.blocks.whereType<DocxParagraph>().map(
          (DocxParagraph p) => p.text,
        ),
        <String>['one', 'one', ''],
      );
    });

    test('copies drop block-level annotations', () {
      final DocxDocument doc = _open(
        '<w:bookmarkStart w:id="1" w:name="b"/>'
        '<w:p><w:r><w:t>x</w:t></w:r></w:p>'
        '<w:bookmarkEnd w:id="1"/>'
        '<w:p/>',
      );
      final CopyResult<DocxBlock> copy = copyBlocks(
        maxDepth: _depth,
        doc.body.blocks.sublist(0, 3),
      );
      expect(copy.items, hasLength(1));
      expect(copy.dropped, <String>{'bookmarkStart', 'bookmarkEnd'});
    });

    test('a paragraph with a section break is not copied', () {
      final DocxDocument doc = _open(
        '<w:p><w:pPr><w:sectPr/></w:pPr></w:p><w:p/>',
      );
      expect(
        () => copyBlocks(maxDepth: _depth, <DocxBlock>[doc.body.blocks.first]),
        throwsArgumentError,
      );
    });
  });

  group('splitRunAt', () {
    test('splits a run and undoes as one change', () {
      final DocxDocument doc = _open(
        '<w:p><w:r w:rsidR="00AB12CD"><w:rPr><w:b/></w:rPr>'
        '<w:t xml:space="preserve">Durum: {{#a}}</w:t></w:r></w:p>',
      );
      final DocxParagraph p = _p(doc, 0);
      final DocxRun run = p.inlines.single as DocxRun;
      late DocxRun added;

      final ChangeSet set = documentTransaction(
        doc,
        () => added = splitRunAt(run, 0, 7),
      );

      expect(p.inlines, <DocxInline>[run, added]);
      expect(run.text, 'Durum: ');
      expect(added.text, '{{#a}}');
      expect(added.properties.bold, isTrue);
      expect(isTemplateCopy(added), isFalse);
      expect(_bodyXml(doc.save().bytes), contains('w:rsidR="00AB12CD"'));

      changeLogOf(doc).undo(set);

      expect(p.inlines, <DocxInline>[run]);
      expect(run.text, 'Durum: {{#a}}');
    });

    test('splits a run of a hyperlink in place', () {
      final DocxDocument doc = _open(
        '<w:p><w:hyperlink w:anchor="x"><w:r><w:t>abcd</w:t></w:r>'
        '</w:hyperlink></w:p>',
      );
      final DocxHyperlink link = _p(doc, 0).inlines.single as DocxHyperlink;
      final DocxRun run = link.inlines.single as DocxRun;

      final DocxRun added = splitRunAt(run, 0, 1);

      expect(link.inlines, <DocxInline>[run, added]);
      expect(run.text, 'a');
      expect(added.text, 'bcd');
    });

    test('the second half of a copied run is a copy too', () {
      final DocxDocument doc = _open(
        '<w:p><w:r><w:t>abcd</w:t></w:r></w:p><w:p/>',
      );
      final DocxRun copy =
          copyInlines(maxDepth: _depth, _p(doc, 0).inlines).items.single
              as DocxRun;
      _p(doc, 1).insertInline(0, copy);

      expect(isTemplateCopy(splitRunAt(copy, 0, 2)), isTrue);
    });

    test('the second half of a run whose properties hold a revision is '
        'renewed as a copy', () {
      final DocxDocument doc = _open(
        '<w:p><w:r><w:rPr><w:b/><w:rPrChange w:id="7" w:author="A">'
        '<w:rPr/></w:rPrChange></w:rPr><w:t>abcd</w:t></w:r></w:p>',
      );
      final DocxRun run = _p(doc, 0).inlines.single as DocxRun;

      expect(isTemplateCopy(splitRunAt(run, 0, 2)), isTrue);
      expect(isTemplateCopy(run), isFalse);
    });

    test('throws for an offset between the halves of a surrogate pair', () {
      final DocxDocument doc = _open(
        '<w:p><w:r><w:t>a\u{1F600}b</w:t></w:r></w:p>',
      );
      final DocxRun run = _p(doc, 0).inlines.single as DocxRun;

      expect(() => splitRunAt(run, 0, 2), throwsArgumentError);
      expect(run.text, 'a\u{1F600}b');
      expect(splitRunAt(run, 0, 3).text, 'b');
    });

    test(
      'throws for a run in no paragraph, and for an offset out of range',
      () {
        expect(() => splitRunAt(DocxRun('ab'), 0, 1), throwsStateError);
        final DocxDocument doc = _open('<w:p><w:r><w:t>ab</w:t></w:r></w:p>');
        final DocxRun run = _p(doc, 0).inlines.single as DocxRun;
        expect(() => splitRunAt(run, 0, 3), throwsRangeError);
        expect(() => splitRunAt(run, 1, 0), throwsRangeError);
        expect(run.text, 'ab');
      },
    );
  });
}
