// Tests reading pictures: a `w:drawing` holding one `wp:inline` with a
// `pic:pic` reads as a typed `DocxPicture` (size in points, name,
// description, and the image its `r:embed` names in the relationships of its
// part), written as read; an anchor, a chart and anything else stays opaque.
// They build documents in memory, so they run on the web as well.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../support/read_xlsx.dart';
import '../support/docx_builder.dart';
import '../support/word_document.dart';

const String _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const String _pic = 'http://schemas.openxmlformats.org/drawingml/2006/picture';
const String _decls =
    'xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}" xmlns:wp="${Ns.wp}" '
    'xmlns:a="$_a" xmlns:pic="$_pic"';

final List<int> _png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, //
];

String _main(String body) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document $_decls><w:body>$body</w:body></w:document>';

/// A `w:drawing` of an inline picture; [blip] is the attributes of `a:blip`.
String _drawing({
  String extent = '<wp:extent cx="914400" cy="457200"/>',
  String docPr = '<wp:docPr id="1" name="Picture 1" descr="A logo"/>',
  String blip = 'r:embed="rId4"',
  String kind = 'inline',
}) =>
    '<w:drawing><wp:$kind>$extent$docPr'
    '<a:graphic><a:graphicData uri="$_pic"><pic:pic>'
    '<pic:nvPicPr><pic:cNvPr id="1" name="p.png"/><pic:cNvPicPr/></pic:nvPicPr>'
    '<pic:blipFill><a:blip $blip/></pic:blipFill>'
    '<pic:spPr/></pic:pic></a:graphicData></a:graphic></wp:$kind></w:drawing>';

String _rel(String id, String target, {String type = RelType.image}) =>
    '<Relationship Id="$id" Type="$type" Target="$target"/>';

Uint8List _docx(
  String body, {
  String rels = '',
  Map<String, List<int>> parts = const <String, List<int>>{},
}) => buildDocx(
  document: _main(body),
  extra: <String, List<int>>{
    '[Content_Types].xml': utf8.encode(
      '<Types xmlns="$contentTypesNs">'
      '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
      '<Default Extension="png" ContentType="image/png"/>'
      '<Override PartName="/word/document.xml" '
      'ContentType="${ContentType.wmlDocument}"/>'
      '<Override PartName="/word/header1.xml" '
      'ContentType="${ContentType.wmlHeader}"/></Types>',
    ),
    'word/_rels/document.xml.rels': utf8.encode(
      '<Relationships xmlns="$packageRelsNs">$rels</Relationships>',
    ),
    ...parts,
  },
);

DocxPicture _picture(DocxDocument doc, [int paragraph = 0]) {
  final DocxParagraph p = doc.body.blocks.whereType<DocxParagraph>().elementAt(
    paragraph,
  );
  return (p.inlines.whereType<DocxRun>().first.content.whereType<DocxPicture>())
      .first;
}

void main() {
  group('reading pictures', () {
    test('the Word-like sample: inline typed, anchored stays opaque', () {
      final Uint8List input = wordDocx();
      final DocxDocument doc = DocxDocument.open(input);
      final DocxPicture picture = doc.body.blocks
          .whereType<DocxParagraph>()
          .expand((DocxParagraph p) => p.inlines.whereType<DocxRun>())
          .expand((DocxRun r) => r.content)
          .whereType<DocxPicture>()
          .single;
      expect(picture.widthPt, 72);
      expect(picture.heightPt, 36);
      expect(picture.name, 'Picture 1');
      expect(picture.description, isNull);
      expect(picture.image, isNotNull);
      expect(picture.image!.bytes.length, 9);
      expect(picture.image!.bytes.first, 0x89);
      final DocxParagraph anchored = doc.body.blocks
          .whereType<DocxParagraph>()
          .firstWhere((DocxParagraph p) => p.text == 'Son');
      expect(
        anchored.inlines.whereType<DocxRun>().first.content.single,
        isA<DocxOpaqueRunContent>(),
      );
      final DocxParagraph holder = doc.body.blocks
          .whereType<DocxParagraph>()
          .firstWhere(
            (DocxParagraph p) => p.inlines.whereType<DocxRun>().any(
              (r) => r.content.any((c) => c is DocxPicture),
            ),
          );
      expect(holder.text, '');
      expect(comparePackages(input, doc.save().bytes), isEmpty);
    });

    test('size, name, description and image of a hand-built picture', () {
      final Uint8List input = _docx(
        '<w:p><w:r>${_drawing()}</w:r></w:p>',
        rels: _rel('rId4', 'media/image1.png'),
        parts: <String, List<int>>{'word/media/image1.png': _png},
      );
      final DocxDocument doc = DocxDocument.open(input);
      final DocxPicture picture = _picture(doc);
      expect(picture.widthPt, 72);
      expect(picture.heightPt, 36);
      expect(picture.name, 'Picture 1');
      expect(picture.description, 'A logo');
      expect(picture.image!.format, OfficeImageFormat.png);
      expect(picture.image!.bytes, _png);
      expect(picture.toString(), contains('Picture 1'));
      expect(comparePackages(input, doc.save().bytes), isEmpty);
    });

    test('no r:embed, a missing part, a link, a wrong type, external', () {
      final Uint8List input = _docx(
        '<w:p>'
        '<w:r>${_drawing(blip: '')}</w:r>'
        '<w:r>${_drawing(blip: 'r:embed="rId9"')}</w:r>'
        '<w:r>${_drawing(blip: 'r:embed="rId5"')}</w:r>'
        '<w:r>${_drawing(blip: 'r:link="rId4"')}</w:r>'
        '<w:r>${_drawing(blip: 'r:embed="rId6"')}</w:r>'
        '<w:r>${_drawing(blip: 'r:embed="rId7"')}</w:r>'
        '</w:p>',
        rels:
            '${_rel('rId4', 'media/image1.png')}'
            '${_rel('rId5', 'media/gone.png')}'
            '${_rel('rId6', 'media/image1.png', type: RelType.hyperlink)}'
            '<Relationship Id="rId7" Type="${RelType.image}" '
            'Target="https://x.test/a.png" TargetMode="External"/>',
        parts: <String, List<int>>{'word/media/image1.png': _png},
      );
      final DocxDocument doc = DocxDocument.open(input);
      final List<DocxPicture> pictures =
          (doc.body.blocks.single as DocxParagraph).inlines
              .whereType<DocxRun>()
              .expand((DocxRun r) => r.content)
              .whereType<DocxPicture>()
              .toList();
      expect(pictures, hasLength(6));
      for (final DocxPicture p in pictures) {
        expect(p.image, isNull);
        expect(p.widthPt, 72);
      }
      expect(comparePackages(input, doc.save().bytes), isEmpty);
    });

    test('a size that is not a non-negative whole number reads null', () {
      final Uint8List input = _docx(
        '<w:p>'
        '<w:r>${_drawing(extent: '<wp:extent cx="abc" cy="457200"/>')}</w:r>'
        '<w:r>${_drawing(extent: '<wp:extent cx="-5" cy="1.5"/>')}</w:r>'
        '<w:r>${_drawing(extent: '')}</w:r>'
        '<w:r>${_drawing(docPr: '')}</w:r>'
        '</w:p>',
      );
      final DocxDocument doc = DocxDocument.open(input);
      final List<DocxPicture> pictures =
          (doc.body.blocks.single as DocxParagraph).inlines
              .whereType<DocxRun>()
              .expand((DocxRun r) => r.content)
              .whereType<DocxPicture>()
              .toList();
      expect(pictures.map((p) => p.widthPt), <double?>[null, null, null, 72]);
      expect(pictures[0].heightPt, 36);
      expect(pictures[1].heightPt, isNull);
      expect(pictures[2].heightPt, isNull);
      expect(pictures[3].name, '');
      expect(pictures[3].description, isNull);
      expect(comparePackages(input, doc.save().bytes), isEmpty);
    });

    test('anchors, charts and several graphics stay opaque', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '<w:p><w:r>${_drawing(kind: 'anchor')}</w:r>'
          '<w:r><w:drawing><wp:inline><wp:extent cx="1" cy="1"/>'
          '<wp:docPr id="3" name="Chart"/><a:graphic><a:graphicData '
          'uri="http://schemas.openxmlformats.org/drawingml/2006/chart"/>'
          '</a:graphic></wp:inline></w:drawing></w:r>'
          '<w:r><w:drawing/></w:r></w:p>',
        ),
      );
      final List<DocxRunContent> content =
          (doc.body.blocks.single as DocxParagraph).inlines
              .whereType<DocxRun>()
              .expand((DocxRun r) => r.content)
              .toList();
      expect(content, everyElement(isA<DocxOpaqueRunContent>()));
    });

    test('a picture in a header reads through the header rels, untouched', () {
      const String headerRels =
          '<?xml version="1.0"?>\r\n<Relationships   '
          'xmlns="$packageRelsNs">\r\n'
          '<Relationship Id="rId1" Type="${RelType.image}" '
          'Target="media/image1.png" />\r\n</Relationships>';
      final Uint8List input = _docx(
        '<w:p><w:r><w:t>Body</w:t></w:r></w:p><w:sectPr>'
        '<w:headerReference w:type="default" r:id="rId1"/></w:sectPr>',
        rels: _rel('rId1', 'header1.xml', type: RelType.header),
        parts: <String, List<int>>{
          'word/header1.xml': utf8.encode(
            '<w:hdr $_decls><w:p><w:r>${_drawing(blip: 'r:embed="rId1"')}'
            '</w:r></w:p></w:hdr>',
          ),
          'word/_rels/header1.xml.rels': utf8.encode(headerRels),
          'word/media/image1.png': _png,
        },
      );
      final DocxDocument doc = DocxDocument.open(input);
      final DocxParagraph p =
          doc.sections.single.header.blocks.single as DocxParagraph;
      final DocxPicture picture = p.inlines
          .whereType<DocxRun>()
          .single
          .content
          .whereType<DocxPicture>()
          .single;
      expect(picture.image!.bytes, _png);
      final Map<String, Uint8List> saved = readXlsxBytes(
        Uint8List.fromList(doc.save().bytes),
      );
      expect(utf8.decode(saved['word/_rels/header1.xml.rels']!), headerRels);
      expect(comparePackages(input, doc.save().bytes), isEmpty);
    });

    test('a damaged rels part of a header reads image null', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '<w:p/><w:sectPr><w:headerReference w:type="default" r:id="rId1"/>'
          '</w:sectPr>',
          rels: _rel('rId1', 'header1.xml', type: RelType.header),
          parts: <String, List<int>>{
            'word/header1.xml': utf8.encode(
              '<w:hdr $_decls><w:p><w:r>${_drawing(blip: 'r:embed="rId1"')}'
              '</w:r></w:p></w:hdr>',
            ),
            'word/_rels/header1.xml.rels': utf8.encode('<Relationships'),
            'word/media/image1.png': _png,
          },
        ),
      );
      final DocxParagraph p =
          doc.sections.single.header.blocks.single as DocxParagraph;
      final DocxPicture picture = p.inlines
          .whereType<DocxRun>()
          .single
          .content
          .whereType<DocxPicture>()
          .single;
      expect(picture.image, isNull);
      expect(picture.name, 'Picture 1');
    });

    test('two pictures of one media part give the same image', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '<w:p><w:r>${_drawing()}</w:r><w:r>${_drawing()}</w:r></w:p>',
          rels: _rel('rId4', 'media/image1.png'),
          parts: <String, List<int>>{'word/media/image1.png': _png},
        ),
      );
      final List<DocxPicture> pictures =
          (doc.body.blocks.single as DocxParagraph).inlines
              .whereType<DocxRun>()
              .expand((DocxRun r) => r.content)
              .whereType<DocxPicture>()
              .toList();
      expect(identical(pictures[0].image, pictures[1].image), isTrue);
      expect(
        identical(pictures[0].image!.bytes, pictures[1].image!.bytes),
        isTrue,
      );
    });

    test('a picture has no text and a GIF reads with no format', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '<w:p><w:r><w:t>a</w:t>${_drawing()}<w:t>b</w:t></w:r></w:p>',
          rels: _rel('rId4', 'media/image1.gif'),
          parts: <String, List<int>>{
            'word/media/image1.gif': utf8.encode('GIF89a....'),
          },
        ),
      );
      expect((doc.body.blocks.single as DocxParagraph).text, 'ab');
      final DocxPicture picture = _picture(doc);
      expect(picture.image, isNotNull);
      expect(picture.image!.format, isNull);
    });
  });
}
