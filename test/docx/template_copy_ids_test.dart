// Tests the ids a save gives what the template fill's copies hold (T2,
// decision 0024; plan T2, Rulings 4 and 9): a copied drawing gets a new
// `wp:docPr` id, a copied revision a new `w:id` in the one id space of
// bookmarks, comments and revisions, a copied content control a new
// `w:sdtPr/w:id`, and a copied paragraph loses `w14:paraId` and `w14:textId`,
// while a document without copies saves byte for byte as before. They build
// documents in memory, so they run on the web as well.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/model/blocks.dart' show copyBlocks;
import 'package:jet_office/src/docx/model/inlines.dart' show copyInlines;
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

import '../fixtures/docx_fixtures.dart';
import '../support/read_xlsx.dart';
import 'support/docx_builder.dart';

const String _pic = 'http://schemas.openxmlformats.org/drawingml/2006/picture';
const String _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const String _wps =
    'http://schemas.microsoft.com/office/word/2010/wordprocessingShape';

const String _decls =
    'xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}" xmlns:wp="${Ns.wp}" '
    'xmlns:w14="${Ns.w14}" xmlns:mc="${Ns.mc}" xmlns:a="$_a" '
    'xmlns:pic="$_pic" xmlns:wps="$_wps"';

/// A run of an inline picture whose `wp:docPr` and `pic:cNvPr` ids are [id].
String _picture(String id) =>
    '<w:r><w:drawing><wp:inline><wp:extent cx="50800" cy="25400"/>'
    '<wp:docPr id="$id" name="Picture $id"/>'
    '<a:graphic><a:graphicData uri="$_pic"><pic:pic><pic:nvPicPr>'
    '<pic:cNvPr id="$id" name="Picture $id"/><pic:cNvPicPr/></pic:nvPicPr>'
    '<pic:blipFill><a:blip r:embed="rId9"/></pic:blipFill><pic:spPr/>'
    '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';

Uint8List _docx(String body, {String? header}) {
  if (header == null) {
    return buildDocx(
      document:
          '<w:document $_decls><w:body>$body<w:sectPr/></w:body>'
          '</w:document>',
    );
  }
  return buildDocx(
    document:
        '<w:document $_decls><w:body>$body<w:sectPr>'
        '<w:headerReference w:type="default" r:id="rId11"/></w:sectPr>'
        '</w:body></w:document>',
    extra: <String, List<int>>{
      '[Content_Types].xml': utf8.encode(
        '<Types xmlns="$contentTypesNs">'
        '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
        '<Override PartName="/word/document.xml" '
        'ContentType="${ContentType.wmlDocument}"/>'
        '<Override PartName="/word/header1.xml" '
        'ContentType="${ContentType.wmlHeader}"/></Types>',
      ),
      'word/_rels/document.xml.rels': utf8.encode(
        '<Relationships xmlns="$packageRelsNs">'
        '<Relationship Id="rId11" Type="${RelType.header}" '
        'Target="header1.xml"/></Relationships>',
      ),
      'word/header1.xml': utf8.encode('<w:hdr $_decls>$header</w:hdr>'),
    },
  );
}

DocxDocument _open(String body, {String? header}) =>
    DocxDocument.open(_docx(body, header: header));

/// One element of a saved part: its namespace, local name, attributes by
/// qualified name and its parent's local name.
typedef _Element = ({
  String ns,
  String name,
  Map<String, String> attributes,
  String parent,
});

/// Every element of [part] in the saved [bytes], in order.
List<_Element> _elements(Uint8List bytes, String part) {
  final XmlPullReader r = XmlPullReader(
    utf8.decode(readXlsxBytes(bytes)[part]!),
  );
  final List<String> open = <String>[''];
  final List<_Element> out = <_Element>[];
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement) {
      out.add((
        ns: r.namespaceUri,
        name: r.localName,
        attributes: <String, String>{
          for (int i = 0; i < r.attributeCount; i++)
            r.attributeQualifiedName(i): r.attributeValue(i),
        },
        parent: open.last,
      ));
      open.add(r.localName);
    } else if (r.eventType == XmlEventType.endElement) {
      open.removeLast();
    }
  }
  return out;
}

List<String> _docPrIds(Uint8List bytes, [String part = 'word/document.xml']) =>
    <String>[
      for (final _Element e in _elements(bytes, part))
        if (e.ns == Ns.wp && e.name == 'docPr') e.attributes['id']!,
    ];

List<String> _cNvPrIds(Uint8List bytes) => <String>[
  for (final _Element e in _elements(bytes, 'word/document.xml'))
    if (e.ns == _pic && e.name == 'cNvPr') e.attributes['id']!,
];

/// The `w:id` of every `w:<name>` of the main part.
List<String> _wIds(Uint8List bytes, String name) => <String>[
  for (final _Element e in _elements(bytes, 'word/document.xml'))
    if (e.ns == Ns.w && e.name == name) e.attributes['w:id']!,
];

List<String> _sdtIds(Uint8List bytes) => <String>[
  for (final _Element e in _elements(bytes, 'word/document.xml'))
    if (e.ns == Ns.w && e.name == 'id' && e.parent == 'sdtPr')
      e.attributes['w:val']!,
];

DocxParagraph _p(DocxStory story, int index) =>
    story.blocks[index] as DocxParagraph;

/// Inserts copies of the inlines of paragraph [from] of [story] at the end of
/// paragraph [to], [times] times.
void _copyInto(DocxStory story, int from, int to, {int times = 1}) {
  for (int t = 0; t < times; t++) {
    for (final DocxInline inline in copyInlines(
      _p(story, from).inlines,
    ).items) {
      _p(story, to).insertInline(_p(story, to).inlines.length, inline);
    }
  }
}

void main() {
  test('an unmarked document saves its parts byte-equal', () {
    for (final DocxFixture fixture in docxFixtures()) {
      final Uint8List bytes = fixture.build().bytes;
      final DocxDocument doc = DocxDocument.open(bytes);
      doc.body.blocks;
      final Map<String, Uint8List> saved = readXlsxBytes(doc.save().bytes);
      final Map<String, Uint8List> original = readXlsxBytes(bytes);
      expect(saved.keys, unorderedEquals(original.keys), reason: fixture.name);
      for (final String part in original.keys) {
        expect(saved[part], original[part], reason: '${fixture.name} $part');
      }
    }
  });

  test('copied pictures get new docPr ids, cNvPr equal to their docPr', () {
    final DocxDocument doc = _open(
      '<w:p>${_picture('7')}</w:p><w:p/>',
      header: '<w:p>${_picture('30')}</w:p>',
    );
    _copyInto(doc.body, 0, 1, times: 2);

    final Uint8List saved = doc.save().bytes;

    final List<String> ids = _docPrIds(saved);
    expect(ids, hasLength(3));
    expect(ids.first, '7');
    expect(ids.toSet(), hasLength(3));
    for (final String id in ids.skip(1)) {
      expect(int.parse(id), greaterThan(30));
    }
    expect(_cNvPrIds(saved), ids);
  });

  test('copied revisions get new w:id above every annotation id of the '
      'file', () {
    final DocxDocument doc = _open(
      '<w:p><w:bookmarkStart w:id="3" w:name="b"/>'
      '<w:commentRangeStart w:id="9"/>'
      '<w:ins w:id="5" w:author="A"><w:r><w:t>x</w:t></w:r></w:ins>'
      '<w:commentRangeEnd w:id="9"/><w:bookmarkEnd w:id="3"/></w:p><w:p/>',
    );
    _copyInto(doc.body, 0, 1);

    final Uint8List saved = doc.save().bytes;

    expect(_wIds(saved, 'ins'), <String>['5', '10']);
  });

  test('copied revisions inside runs and properties are renumbered', () {
    final DocxDocument doc = _open(
      '<w:p><w:pPr><w:rPr><w:ins w:id="2" w:author="A"/></w:rPr></w:pPr>'
      '<w:r><w:rPr><w:b/><w:rPrChange w:id="4" w:author="A"><w:rPr/>'
      '</w:rPrChange></w:rPr><w:t>x</w:t></w:r>'
      '<w:del w:id="6" w:author="A"><w:r><w:delText>y</w:delText></w:r>'
      '</w:del></w:p>',
    );
    doc.body.insertBlock(1, copyBlocks(<DocxBlock>[_p(doc.body, 0)]).items[0]);

    final Uint8List saved = doc.save().bytes;

    expect(_wIds(saved, 'ins').first, '2');
    expect(_wIds(saved, 'rPrChange').first, '4');
    expect(_wIds(saved, 'del').first, '6');
    final Set<String> all = <String>{
      ..._wIds(saved, 'ins'),
      ..._wIds(saved, 'rPrChange'),
      ..._wIds(saved, 'del'),
    };
    expect(all, hasLength(6));
    for (final String id in <String>[
      _wIds(saved, 'ins')[1],
      _wIds(saved, 'rPrChange')[1],
      _wIds(saved, 'del')[1],
    ]) {
      expect(int.parse(id), greaterThan(6));
    }
  });

  test('copied content controls get new w:sdtPr ids', () {
    final DocxDocument doc = _open(
      '<w:sdt><w:sdtPr><w:id w:val="-12345"/></w:sdtPr><w:sdtContent>'
      '<w:p><w:r><w:t>a</w:t></w:r></w:p></w:sdtContent></w:sdt>'
      '<w:sdt><w:sdtPr><w:id w:val="77"/></w:sdtPr><w:sdtContent>'
      '<w:p><w:r><w:t>b</w:t></w:r></w:p></w:sdtContent></w:sdt>'
      '<w:p/>',
    );
    final List<DocxBlock> copies = copyBlocks(
      doc.body.blocks.sublist(0, 2),
    ).items;
    for (int i = 0; i < copies.length; i++) {
      doc.body.insertBlock(2 + i, copies[i]);
    }

    final List<String> ids = _sdtIds(doc.save().bytes);

    expect(ids.take(2), <String>['-12345', '77']);
    expect(ids.toSet(), hasLength(4));
    for (final String id in ids.skip(2)) {
      expect(int.parse(id), greaterThan(77));
    }
  });

  test('copies lose w14:paraId and w14:textId', () {
    final DocxDocument doc = _open(
      '<w:p w14:paraId="1A2B3C4D" w14:textId="77777777" w:rsidR="00AB12CD">'
      '<w:r><w:t>x</w:t></w:r></w:p>',
    );
    doc.body.insertBlock(1, copyBlocks(<DocxBlock>[_p(doc.body, 0)]).items[0]);

    final List<Map<String, String>> paragraphs = <Map<String, String>>[
      for (final _Element e in _elements(doc.save().bytes, 'word/document.xml'))
        if (e.ns == Ns.w && e.name == 'p') e.attributes,
    ];

    expect(paragraphs, hasLength(2));
    expect(paragraphs[0]['w14:paraId'], '1A2B3C4D');
    expect(paragraphs[0]['w14:textId'], '77777777');
    expect(paragraphs[1].containsKey('w14:paraId'), isFalse);
    expect(paragraphs[1].containsKey('w14:textId'), isFalse);
    expect(paragraphs[1]['w:rsidR'], '00AB12CD');
  });

  test('one old id repeated in a copy maps to one new id', () {
    final DocxDocument doc = _open(
      '<w:p><w:r><mc:AlternateContent>'
      '<mc:Choice Requires="wps"><w:drawing><wp:anchor>'
      '<wp:docPr id="4" name="Shape 4"/></wp:anchor></w:drawing></mc:Choice>'
      '<mc:Fallback><w:drawing><wp:inline><wp:docPr id="4" name="Shape 4"/>'
      '</wp:inline></w:drawing></mc:Fallback>'
      '</mc:AlternateContent></w:r></w:p><w:p/>',
    );
    _copyInto(doc.body, 0, 1);

    final List<String> ids = _docPrIds(doc.save().bytes);

    expect(ids, hasLength(4));
    expect(ids.take(2), <String>['4', '4']);
    expect(ids[2], ids[3]);
    expect(ids[2], isNot('4'));
  });

  test('a copy inside a copy is renumbered once', () {
    final DocxDocument doc = _open(
      '<w:p><w:ins w:id="5" w:author="A"><w:r><w:t>x</w:t></w:r></w:ins>'
      '</w:p>',
    );
    final DocxBlock copy = copyBlocks(<DocxBlock>[_p(doc.body, 0)]).items[0];
    doc.body.insertBlock(1, copy);
    doc.body.insertBlock(2, copyBlocks(<DocxBlock>[copy]).items[0]);

    final List<String> ids = _wIds(doc.save().bytes, 'ins');

    expect(ids, hasLength(3));
    expect(ids.toSet(), hasLength(3));
    expect(ids, <Object>['5', '6', '7']);
  });

  test('an inline copy inside a block copy is renumbered by its own mark', () {
    final DocxDocument doc = _open(
      '<w:p><w:ins w:id="5" w:author="A"><w:r><w:t>x</w:t></w:r></w:ins>'
      '</w:p>',
    );
    final DocxParagraph copy =
        copyBlocks(<DocxBlock>[_p(doc.body, 0)]).items[0] as DocxParagraph;
    doc.body.insertBlock(1, copy);
    for (final DocxInline inline in copyInlines(
      _p(doc.body, 0).inlines,
    ).items) {
      copy.insertInline(copy.inlines.length, inline);
    }

    final List<String> ids = _wIds(doc.save().bytes, 'ins');

    expect(ids, hasLength(3));
    expect(ids.toSet(), hasLength(3));
  });

  test("a file's own processing instruction of the copy's name changes "
      'nothing', () {
    final DocxDocument doc = _open(
      '<w:p><w:ins w:id="5" w:author="A"><?jet-office-copy-end?>'
      '<w:r><w:t>x</w:t></w:r><?jet-office-copy?></w:ins></w:p><w:p/>',
    );
    _copyInto(doc.body, 0, 1);

    expect(_wIds(doc.save().bytes, 'ins'), <String>['5', '6']);
  });

  test('built bookmark ids and fresh revision ids never collide', () {
    final DocxDocument doc = _open(
      '<w:p><w:ins w:id="5" w:author="A"><w:r><w:t>x</w:t></w:r></w:ins>'
      '</w:p><w:p/>',
    );
    final DocxParagraph target = _p(doc.body, 1);
    final DocxBookmarkStart start = target.addBookmarkStart('mark');
    _copyInto(doc.body, 0, 1);
    target.addBookmarkEnd(start);

    final Uint8List saved = doc.save().bytes;

    final List<String> ins = _wIds(saved, 'ins');
    final List<String> bookmarks = _wIds(saved, 'bookmarkStart');
    expect(ins, hasLength(2));
    expect(bookmarks, hasLength(1));
    expect(<String>{...ins, ...bookmarks}, hasLength(3));
    expect(int.parse(bookmarks.single), greaterThan(5));
    expect(int.parse(ins[1]), greaterThan(5));
  });

  test("a built bookmark's id is above every revision id of the file", () {
    final DocxDocument doc = _open(
      '<w:p><w:bookmarkStart w:id="1" w:name="b"/>'
      '<w:ins w:id="40" w:author="A"><w:r><w:t>x</w:t></w:r></w:ins>'
      '<w:bookmarkEnd w:id="1"/></w:p><w:p/>',
    );
    final DocxParagraph target = _p(doc.body, 1);
    target.addBookmarkEnd(target.addBookmarkStart('mark'));

    expect(_wIds(doc.save().bytes, 'bookmarkStart'), <String>['1', '41']);
  });

  test('saving twice gives the same bytes', () {
    final DocxDocument doc = _open(
      '<w:p w14:paraId="1A2B3C4D">${_picture('7')}'
      '<w:ins w:id="5" w:author="A"><w:r><w:t>x</w:t></w:r></w:ins></w:p>'
      '<w:sdt><w:sdtPr><w:id w:val="77"/></w:sdtPr><w:sdtContent>'
      '<w:p/></w:sdtContent></w:sdt><w:p/>',
    );
    _copyInto(doc.body, 0, 2, times: 2);
    for (final DocxBlock block in copyBlocks(
      doc.body.blocks.sublist(0, 2),
    ).items.reversed) {
      doc.body.insertBlock(3, block);
    }

    expect(doc.save().bytes, doc.save().bytes);
  });

  test('ids in a header copy are unique across body and header', () {
    final DocxDocument doc = _open(
      '<w:p>${_picture('1')}</w:p><w:p/>',
      header: '<w:p>${_picture('2')}</w:p><w:p/>',
    );
    final DocxHeaderFooter header = doc.sections.first.header;
    _copyInto(doc.body, 0, 1);
    _copyInto(header, 0, 1);

    final Uint8List saved = doc.save().bytes;

    final List<String> ids = <String>[
      ..._docPrIds(saved),
      ..._docPrIds(saved, 'word/header1.xml'),
    ];
    expect(ids, hasLength(4));
    expect(ids.toSet(), hasLength(4));
  });
}
