// Tests building hyperlinks: `DocxParagraph.addHyperlink` makes a link of one
// run in the `Hyperlink` character style (the document's own id, Word's
// definition added on demand), an external one gets a relationship from its
// part at each save and none is stored in the model (plan D5, Rulings 9, 12
// and A), an anchor link writes `w:anchor`, bad targets throw and change
// nothing, and a failed transaction or an undo leaves no relationship and no
// style. They build documents in memory, so they run on the web as well.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart'
    show changeLogOf, editsOf;
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../support/docx_builder.dart';
import '../support/localized_document.dart';
import '../support/styles_documents.dart';

const String _decls = 'xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}"';

String _main(String body) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document $_decls><w:body>$body</w:body></w:document>';

/// The text parts of [bytes], by ZIP entry name.
Map<String, String> _parts(Uint8List bytes) => readDocxText(bytes);

/// The `Relationship` elements of [rels] of the hyperlink type, each as its
/// id and target.
List<(String, String)> _links(String rels) => <(String, String)>[
  for (final Match m in RegExp(
    r'<Relationship [^>]*Id="([^"]*)"[^>]*Type="'
    '${RegExp.escape(RelType.hyperlink)}'
    r'"[^>]*Target="([^"]*)"[^>]*TargetMode="External"',
  ).allMatches(rels))
    (m[1]!, m[2]!),
];

/// The `r:id` of each `w:hyperlink` of [xml].
List<String> _linkIds(String xml) => <String>[
  for (final Match m in RegExp(
    r'<w:hyperlink [^>]*r:id="([^"]*)"',
  ).allMatches(xml))
    m[1]!,
];

/// A Turkish-like package whose `Hyperlink` style is `Kpr`.
Uint8List _turkish() => docxWithStyles(
  styles: stylesXmlOf(<String>[
    styleXml('paragraph', 'Normal', 'Normal', attributes: ' w:default="1"'),
    styleXml(
      'character',
      'VarsaylanParagrafYazTipi',
      'Default Paragraph Font',
      attributes: ' w:default="1"',
    ),
    styleXml('character', 'Kpr', 'Hyperlink'),
  ]),
);

/// A package whose last section has the header part `word/header1.xml` and
/// the footer part `word/footer1.xml`, each with a relationships part
/// ([headerRels], [footerRels], written as given), in that ZIP order;
/// [footer] is the footer's blocks.
Uint8List _withStories({
  required String headerRels,
  required String footerRels,
  String footer = '<w:p><w:r><w:t>Foot</w:t></w:r></w:p>',
}) => buildDocx(
  document: _main(
    '<w:p><w:r><w:t>Body</w:t></w:r></w:p><w:sectPr>'
    '<w:headerReference w:type="default" r:id="rId1"/>'
    '<w:footerReference w:type="default" r:id="rId2"/></w:sectPr>',
  ),
  extra: <String, List<int>>{
    '[Content_Types].xml': utf8.encode(
      '<Types xmlns="$contentTypesNs">'
      '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
      '<Override PartName="/word/document.xml" '
      'ContentType="${ContentType.wmlDocument}"/>'
      '<Override PartName="/word/header1.xml" '
      'ContentType="${ContentType.wmlHeader}"/>'
      '<Override PartName="/word/footer1.xml" '
      'ContentType="${ContentType.wmlFooter}"/>'
      '<Override PartName="/word/styles.xml" '
      'ContentType="${ContentType.wmlStyles}"/></Types>',
    ),
    'word/_rels/document.xml.rels': utf8.encode(
      '<Relationships xmlns="$packageRelsNs">'
      '<Relationship Id="rId1" Type="${RelType.header}" '
      'Target="header1.xml"/>'
      '<Relationship Id="rId2" Type="${RelType.footer}" '
      'Target="footer1.xml"/>'
      '<Relationship Id="rId3" Type="${RelType.styles}" '
      'Target="styles.xml"/></Relationships>',
    ),
    'word/styles.xml': utf8.encode(
      stylesXmlOf(<String>[styleXml('character', 'Hyperlink', 'Hyperlink')]),
    ),
    'word/header1.xml': utf8.encode(
      '<w:hdr $_decls><w:p><w:r><w:t>Head</w:t></w:r></w:p></w:hdr>',
    ),
    'word/_rels/header1.xml.rels': utf8.encode(headerRels),
    'word/footer1.xml': utf8.encode('<w:ftr $_decls>$footer</w:ftr>'),
    'word/_rels/footer1.xml.rels': utf8.encode(footerRels),
  },
);

const String _someRels =
    '<Relationships xmlns="$packageRelsNs">'
    '<Relationship Id="rId9" Type="${RelType.hyperlink}" '
    'Target="https://old.test/" TargetMode="External"/></Relationships>';

void main() {
  group('an external link', () {
    test('saves a relationship of the main part and the Hyperlink style', () {
      final DocxDocument doc = DocxDocument();
      final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
      final DocxHyperlink link = p.addHyperlink(
        'site',
        url: 'https://example.com/fiyat?a=1&b=2',
      );
      expect(link.url, 'https://example.com/fiyat?a=1&b=2');
      expect(link.anchor, isNull);
      expect(link.tooltip, isNull);
      expect(link.text, 'site');
      expect(p.inlines.single, same(link));
      final DocxRun run = link.inlines.single as DocxRun;
      expect(run.style, 'Hyperlink');
      expect(doc.styles.byId('Hyperlink'), isNotNull);

      final Map<String, String> parts = _parts(doc.save().bytes);
      final List<(String, String)> rels = _links(
        parts['word/_rels/document.xml.rels']!,
      );
      expect(rels, hasLength(1));
      expect(rels.single.$2, 'https://example.com/fiyat?a=1&amp;b=2');
      final String main = parts['word/document.xml']!;
      expect(_linkIds(main), <String>[rels.single.$1]);
      expect(
        main,
        contains(
          'w:history="1"><w:r><w:rPr><w:rStyle w:val="Hyperlink"/></w:rPr>'
          '<w:t>site</w:t></w:r></w:hyperlink>',
        ),
      );
      expect(parts['word/styles.xml'], contains('w:styleId="Hyperlink"'));

      final DocxDocument again = DocxDocument.open(doc.save().bytes);
      final DocxHyperlink read =
          (again.body.blocks.single as DocxParagraph).inlines.single
              as DocxHyperlink;
      expect(read.url, 'https://example.com/fiyat?a=1&b=2');
      expect(read.text, 'site');
      expect((read.inlines.single as DocxRun).style, 'Hyperlink');
    });

    test('a tooltip is written as w:tooltip', () {
      final DocxDocument doc = DocxDocument();
      final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
      final DocxHyperlink link = p.addHyperlink(
        'site',
        url: 'https://x.test/',
        tooltip: 'Fiyat "listesi"',
      );
      expect(link.tooltip, 'Fiyat "listesi"');
      final DocxDocument again = DocxDocument.open(doc.save().bytes);
      final DocxHyperlink read =
          (again.body.blocks.single as DocxParagraph).inlines.single
              as DocxHyperlink;
      expect(read.tooltip, 'Fiyat "listesi"');
      expect(read.url, 'https://x.test/');
    });

    test('in a Turkish file the run takes Kpr and no style is added', () {
      final Uint8List input = _turkish();
      final DocxDocument doc = DocxDocument.open(input);
      final DocxParagraph p = doc.body.addParagraph();
      final DocxRun run =
          p.addHyperlink('site', url: 'https://x.test/').inlines.single
              as DocxRun;
      expect(run.style, 'Kpr');
      final Map<String, String> parts = _parts(doc.save().bytes);
      expect(parts['word/document.xml'], contains('<w:rStyle w:val="Kpr"/>'));
      expect(parts['word/styles.xml'], _parts(input)['word/styles.xml']);
    });

    test('two links to one URL make two relationships, as Word does', () {
      final DocxDocument doc = DocxDocument();
      final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
      p
        ..addHyperlink('a', url: 'https://x.test/')
        ..addHyperlink('b', url: 'https://x.test/');
      final Map<String, String> parts = _parts(doc.save().bytes);
      final List<(String, String)> rels = _links(
        parts['word/_rels/document.xml.rels']!,
      );
      expect(rels, hasLength(2));
      expect(rels[0].$1, isNot(rels[1].$1));
      expect(_linkIds(parts['word/document.xml']!), <String>[
        for (final (String, String) r in rels) r.$1,
      ]);
    });

    test('a link in a table cell is related from the main part', () {
      final DocxDocument doc = DocxDocument();
      final DocxTable table = doc.body.addTable(columns: 1);
      table.addRow(<String?>[null]);
      doc.body.addParagraph();
      final DocxParagraph cell =
          table.rows.single.cells.single.blocks.single as DocxParagraph;
      cell.addHyperlink('in cell', url: 'https://cell.test/');
      final Map<String, String> parts = _parts(doc.save().bytes);
      final List<(String, String)> rels = _links(
        parts['word/_rels/document.xml.rels']!,
      );
      expect(rels.single.$2, 'https://cell.test/');
      expect(_linkIds(parts['word/document.xml']!), <String>[rels.single.$1]);
    });

    test('a new id takes none a reference of the file names', () {
      final DocxDocument doc = DocxDocument.open(
        buildDocx(
          document: _main(
            '<w:p><w:hyperlink r:id="rId1"><w:r><w:t>x</w:t></w:r>'
            '</w:hyperlink></w:p>',
          ),
        ),
      );
      (doc.body.blocks.single as DocxParagraph).addHyperlink(
        'new',
        url: 'https://new.test/',
      );
      final Map<String, String> parts = _parts(doc.save().bytes);
      final List<String> ids = _linkIds(parts['word/document.xml']!);
      expect(ids.first, 'rId1');
      expect(ids.last, isNot('rId1'));
      expect(
        _links(parts['word/_rels/document.xml.rels']!).single.$1,
        ids.last,
      );
    });

    test('a link in a nested table cell is related from the main part', () {
      final DocxDocument doc = DocxDocument();
      final DocxTable outer = doc.body.addTable(columns: 1);
      outer.addRow(<String?>[null]);
      doc.body.addParagraph();
      final DocxTable inner = outer.rows.single.cells.single.addTable(
        columns: 1,
      );
      inner.addRow(<String?>[null]);
      final DocxParagraph cell =
          inner.rows.single.cells.single.blocks.single as DocxParagraph;
      cell.addHyperlink('deep', url: 'https://deep.test/');
      final Map<String, String> parts = _parts(doc.save().bytes);
      final List<(String, String)> rels = _links(
        parts['word/_rels/document.xml.rels']!,
      );
      expect(rels.single.$2, 'https://deep.test/');
      expect(_linkIds(parts['word/document.xml']!), <String>[rels.single.$1]);
    });

    test('a url with a scheme and a backslash is written as given', () {
      final DocxDocument doc = DocxDocument();
      final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
      expect(p.addHyperlink('c', url: r'C:\x').url, r'C:\x');
      expect(
        _links(
          _parts(doc.save().bytes)['word/_rels/document.xml.rels']!,
        ).single.$2,
        r'C:\x',
      );
    });

    test('saving twice gives the same file and stores no id', () {
      final DocxDocument doc = DocxDocument();
      final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
      p.addHyperlink('a', url: 'https://x.test/');
      final Uint8List first = doc.save().bytes;
      final Uint8List second = doc.save().bytes;
      expect(second, first);
      expect(
        _links(_parts(second)['word/_rels/document.xml.rels']!),
        hasLength(1),
      );
    });

    test('a removed link leaves no relationship at the next save', () {
      final Uint8List input = DocxDocument().save().bytes;
      final DocxDocument doc = DocxDocument.open(input);
      final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
      p.addHyperlink('a', url: 'https://x.test/');
      doc.save();
      p.removeInlineAt(0);
      final Map<String, String> parts = _parts(doc.save().bytes);
      expect(_links(parts['word/_rels/document.xml.rels']!), isEmpty);
      expect(
        parts['word/_rels/document.xml.rels'],
        _parts(input)['word/_rels/document.xml.rels'],
      );
    });
  });

  group('a link in a header or footer', () {
    test('a new header gets the relationship in its own rels', () {
      final DocxDocument doc = DocxDocument();
      final DocxParagraph p = doc.sections.single.header.addParagraph();
      p.addHyperlink('head', url: 'https://head.test/');
      final Map<String, String> parts = _parts(doc.save().bytes);
      final List<(String, String)> rels = _links(
        parts['word/_rels/header1.xml.rels']!,
      );
      expect(rels.single.$2, 'https://head.test/');
      expect(_linkIds(parts['word/header1.xml']!), <String>[rels.single.$1]);
      expect(_links(parts['word/_rels/document.xml.rels']!), isEmpty);
      // Opened again, it reads its url from the header's relationships.
      final DocxDocument again = DocxDocument.open(doc.save().bytes);
      final DocxParagraph read =
          again.sections.single.header.blocks.single as DocxParagraph;
      expect((read.inlines.single as DocxHyperlink).url, 'https://head.test/');
    });

    test('a footer read keeps its relationships and gets one more', () {
      const String footerRels =
          '<?xml version="1.0"?>\r\n<Relationships '
          'xmlns="$packageRelsNs">'
          '<Relationship Id="rId1" Type="${RelType.hyperlink}" '
          'Target="https://old.test/" TargetMode="External"/>'
          '</Relationships>';
      final Uint8List input = buildDocx(
        document: _main(
          '<w:p><w:r><w:t>Body</w:t></w:r></w:p><w:sectPr>'
          '<w:footerReference w:type="default" r:id="rId1"/></w:sectPr>',
        ),
        extra: <String, List<int>>{
          '[Content_Types].xml': utf8.encode(
            '<Types xmlns="$contentTypesNs">'
            '<Default Extension="rels" '
            'ContentType="${ContentType.relationships}"/>'
            '<Override PartName="/word/document.xml" '
            'ContentType="${ContentType.wmlDocument}"/>'
            '<Override PartName="/word/footer1.xml" '
            'ContentType="${ContentType.wmlFooter}"/></Types>',
          ),
          'word/_rels/document.xml.rels': utf8.encode(
            '<Relationships xmlns="$packageRelsNs">'
            '<Relationship Id="rId1" Type="${RelType.footer}" '
            'Target="footer1.xml"/></Relationships>',
          ),
          'word/footer1.xml': utf8.encode(
            '<w:ftr $_decls><w:p><w:hyperlink r:id="rId1"><w:r><w:t>old</w:t>'
            '</w:r></w:hyperlink><w:hyperlink r:id="rId2"><w:r><w:t>none</w:t>'
            '</w:r></w:hyperlink></w:p></w:ftr>',
          ),
          'word/_rels/footer1.xml.rels': utf8.encode(footerRels),
        },
      );
      final DocxDocument doc = DocxDocument.open(input);
      final DocxParagraph p =
          doc.sections.single.footer.blocks.single as DocxParagraph;
      p.addHyperlink('new', url: 'https://new.test/');
      final Map<String, String> parts = _parts(doc.save().bytes);
      final List<(String, String)> rels = _links(
        parts['word/_rels/footer1.xml.rels']!,
      );
      // rId2 names nothing in the file and stays dangling.
      expect(rels, <(String, String)>[
        ('rId1', 'https://old.test/'),
        ('rId3', 'https://new.test/'),
      ]);
      expect(_linkIds(parts['word/footer1.xml']!), <String>[
        'rId1',
        'rId2',
        'rId3',
      ]);
      // Taken out again, the footer's relationships go out as read.
      p.removeInlineAt(2);
      expect(
        _parts(doc.save().bytes)['word/_rels/footer1.xml.rels'],
        footerRels,
      );
    });
  });

  group('saves that add and take back relationships', () {
    test('save, link, save, undo, save gives the first file again', () {
      final DocxDocument doc = DocxDocument.open(
        _withStories(headerRels: _someRels, footerRels: _someRels),
      );
      final DocxHeaderFooter header = doc.sections.single.header;
      expect(header.blocks, hasLength(1));
      expect(doc.sections.single.footer.blocks, hasLength(1));
      final Uint8List first = doc.save().bytes;
      final ChangeSet set = editsOf(doc).transaction(() {
        (header.blocks.single as DocxParagraph).addHyperlink(
          'new',
          url: 'https://new.test/',
        );
      });
      expect(
        _links(_parts(doc.save().bytes)['word/_rels/header1.xml.rels']!),
        hasLength(2),
      );
      changeLogOf(doc).revertSet(set);
      expect(doc.save().bytes, first);
    });

    test('a save that fails on a broken footer rels part adds nothing', () {
      const String broken = '<Relationships';
      final DocxDocument doc = DocxDocument.open(
        _withStories(headerRels: _someRels, footerRels: broken),
      );
      final DocxParagraph foot =
          doc.sections.single.footer.blocks.single as DocxParagraph;
      (doc.body.blocks.first as DocxParagraph).addHyperlink(
        'body',
        url: 'https://body.test/',
      );
      foot.addHyperlink('foot', url: 'https://foot.test/');
      expect(doc.save, throwsA(isA<DocxReadException>()));
      foot.removeInlineAt(foot.inlines.length - 1);
      final Map<String, String> parts = _parts(doc.save().bytes);
      expect(
        _links(parts['word/_rels/document.xml.rels']!).single.$2,
        'https://body.test/',
      );
      expect(parts['word/_rels/footer1.xml.rels'], broken);
    });
  });

  group('an anchor link', () {
    test('links to a built bookmark with w:anchor and no relationship', () {
      final DocxDocument doc = DocxDocument();
      final DocxParagraph target = doc.body.blocks.single as DocxParagraph;
      final DocxBookmarkStart start = target.addBookmarkStart('Totals');
      target
        ..addRun('Totals')
        ..addBookmarkEnd(start);
      final DocxHyperlink link = doc.body.addParagraph().addHyperlink(
        'see the totals',
        anchor: start.name,
      );
      expect(link.anchor, 'Totals');
      expect(link.url, isNull);
      final Map<String, String> parts = _parts(doc.save().bytes);
      expect(
        parts['word/document.xml'],
        contains('<w:hyperlink w:anchor="Totals" w:history="1">'),
      );
      expect(_links(parts['word/_rels/document.xml.rels']!), isEmpty);
      final DocxDocument again = DocxDocument.open(doc.save().bytes);
      final DocxHyperlink read =
          (again.body.blocks.last as DocxParagraph).inlines.single
              as DocxHyperlink;
      expect(read.anchor, 'Totals');
      expect(read.text, 'see the totals');
    });
  });

  group('bad arguments', () {
    final Map<String, void Function(DocxParagraph p)> cases =
        <String, void Function(DocxParagraph p)>{
          'a url that is not a URI': (DocxParagraph p) =>
              p.addHyperlink('x', url: 'not a uri'),
          'a url with a space in its host': (DocxParagraph p) =>
              p.addHyperlink('x', url: 'https://a b/'),
          'a url with a space in its path': (DocxParagraph p) =>
              p.addHyperlink('x', url: 'https://x.test/a b'),
          'a url with a tab': (DocxParagraph p) =>
              p.addHyperlink('x', url: 'https://x.test/a\tb'),
          'a url with a C1 control': (DocxParagraph p) =>
              p.addHyperlink('x', url: 'https://x.test/\u0085'),
          'a relative url': (DocxParagraph p) =>
              p.addHyperlink('x', url: 'page.html'),
          'a url XML cannot hold': (DocxParagraph p) =>
              p.addHyperlink('x', url: 'https://x.test/\u0001'),
          'both targets': (DocxParagraph p) =>
              p.addHyperlink('x', url: 'https://x.test/', anchor: 'A'),
          'neither target': (DocxParagraph p) => p.addHyperlink('x'),
          'an empty anchor': (DocxParagraph p) =>
              p.addHyperlink('x', anchor: ''),
          'an anchor XML cannot hold': (DocxParagraph p) =>
              p.addHyperlink('x', anchor: 'A￾'),
          'a tooltip XML cannot hold': (DocxParagraph p) =>
              p.addHyperlink('x', url: 'https://x.test/', tooltip: '\u0002'),
        };
    for (final MapEntry<String, void Function(DocxParagraph)> c
        in cases.entries) {
      test('${c.key} throws ArgumentError and changes nothing', () {
        final Uint8List input = DocxDocument().save().bytes;
        final DocxDocument doc = DocxDocument.open(input);
        final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
        expect(() => c.value(p), throwsArgumentError);
        expect(p.inlines, isEmpty);
        expect(changeLogOf(doc).hasChanges, isFalse);
        expect(doc.save().bytes, input);
      });
    }
  });

  group('undo', () {
    test('a transaction that throws leaves no relationship and no style', () {
      final Uint8List input = DocxDocument().save().bytes;
      final DocxDocument doc = DocxDocument.open(input);
      final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
      expect(
        () => editsOf(doc).transaction(() {
          p.addHyperlink('a', url: 'https://x.test/');
          throw StateError('stop');
        }),
        throwsStateError,
      );
      expect(p.inlines, isEmpty);
      expect(doc.styles.byId('Hyperlink'), isNull);
      expect(comparePackages(input, doc.save().bytes), isEmpty);
    });

    test('an undo leaves no relationship and no style', () {
      final Uint8List input = DocxDocument().save().bytes;
      final DocxDocument doc = DocxDocument.open(input);
      final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
      final ChangeSet set = editsOf(doc).transaction(() {
        p.addHyperlink('a', url: 'https://x.test/');
      });
      expect(doc.styles.byId('Hyperlink'), isNotNull);
      changeLogOf(doc).revertSet(set);
      expect(p.inlines, isEmpty);
      expect(doc.styles.byId('Hyperlink'), isNull);
      expect(comparePackages(input, doc.save().bytes), isEmpty);
      changeLogOf(doc).reapplySet(set);
      expect(
        _links(_parts(doc.save().bytes)['word/_rels/document.xml.rels']!),
        hasLength(1),
      );
    });
  });

  group('a link built in a paragraph of no document', () {
    test('keeps Hyperlink until it goes in, then resolves there', () {
      final DocxParagraph p = DocxParagraph();
      final DocxHyperlink link = p.addHyperlink('site', url: 'https://x.test/');
      final DocxRun run = link.inlines.single as DocxRun;
      expect(run.style, 'Hyperlink');
      final DocxDocument doc = DocxDocument.open(_turkish());
      doc.body.insertBlock(0, p);
      expect(run.style, 'Kpr');
      final Map<String, String> parts = _parts(doc.save().bytes);
      expect(_links(parts['word/_rels/document.xml.rels']!), hasLength(1));
    });

    test('adds Word\'s Hyperlink style to a document that lacks it', () {
      final DocxParagraph p = DocxParagraph();
      p.addHyperlink('site', url: 'https://x.test/');
      final DocxDocument doc = DocxDocument();
      expect(doc.styles.byId('Hyperlink'), isNull);
      doc.body.insertBlock(0, p);
      expect(doc.styles.byId('Hyperlink'), isNotNull);
      expect(
        _parts(doc.save().bytes)['word/styles.xml'],
        contains('w:styleId="Hyperlink"'),
      );
    });

    test('a built link works in a second document after a save', () {
      final DocxDocument one = DocxDocument();
      final DocxParagraph p = one.body.addParagraph();
      final DocxHyperlink link = p.addHyperlink('a', url: 'https://x.test/');
      one.save();
      p.removeInlineAt(0);
      final DocxDocument two = DocxDocument();
      two.sections.single.footer.addParagraph().insertInline(0, link);
      final Map<String, String> parts = _parts(two.save().bytes);
      expect(
        _links(parts['word/_rels/footer1.xml.rels']!).single.$2,
        'https://x.test/',
      );
      expect(_links(parts['word/_rels/document.xml.rels']!), isEmpty);
    });
  });
}
