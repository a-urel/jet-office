// Pins what the DOCX model does today with a shape (a text box written as
// Word writes one: `wps:wsp` in `mc:AlternateContent` with a VML fallback)
// and an icon (an inline `pic:pic` whose blip carries an SVG through the
// `asvg:svgBlip` extension), for the analysis in docs/shapes.md. The XML is
// written by hand from ECMA-376 and Microsoft's documentation; no owner file
// confirms it yet. They build bytes in memory, so they run on the web too.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

import '../fixtures/m4_fixtures.dart' show png4x2;
import '../support/read_xlsx.dart';
import 'support/docx_builder.dart';

const String _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const String _pic = 'http://schemas.openxmlformats.org/drawingml/2006/picture';
const String _wps =
    'http://schemas.microsoft.com/office/word/2010/wordprocessingShape';
const String _mc =
    'http://schemas.openxmlformats.org/markup-compatibility/2006';
const String _v = 'urn:schemas-microsoft-com:vml';
const String _asvg =
    'http://schemas.microsoft.com/office/drawing/2016/SVG/main';

/// A run holding a floating text box that says [text], with its fallback.
String _textBoxRun(String text) =>
    '<w:r><mc:AlternateContent><mc:Choice Requires="wps"><w:drawing>'
    '<wp:anchor distT="0" distB="0" distL="114300" distR="114300" '
    'simplePos="0" relativeHeight="251659264" behindDoc="0" locked="0" '
    'layoutInCell="1" allowOverlap="1"><wp:simplePos x="0" y="0"/>'
    '<wp:positionH relativeFrom="column"><wp:posOffset>0</wp:posOffset>'
    '</wp:positionH><wp:positionV relativeFrom="paragraph"><wp:posOffset>0'
    '</wp:posOffset></wp:positionV><wp:extent cx="1828800" cy="457200"/>'
    '<wp:effectExtent l="0" t="0" r="0" b="0"/><wp:wrapNone/>'
    '<wp:docPr id="7" name="Text Box 7"/><wp:cNvGraphicFramePr/>'
    '<a:graphic><a:graphicData uri="$_wps"><wps:wsp>'
    '<wps:cNvSpPr txBox="1"/><wps:spPr><a:xfrm><a:off x="0" y="0"/>'
    '<a:ext cx="1828800" cy="457200"/></a:xfrm><a:prstGeom prst="rect">'
    '<a:avLst/></a:prstGeom><a:solidFill><a:schemeClr val="lt1"/>'
    '</a:solidFill></wps:spPr><wps:txbx><w:txbxContent><w:p><w:r>'
    '<w:t>$text</w:t></w:r></w:p></w:txbxContent></wps:txbx>'
    '<wps:bodyPr rot="0" vert="horz" wrap="square"/></wps:wsp>'
    '</a:graphicData></a:graphic></wp:anchor></w:drawing></mc:Choice>'
    '<mc:Fallback><w:pict><v:shapetype id="_x0000_t202" coordsize="21600,21600"'
    ' path="m,l,21600r21600,l21600,xe"/><v:shape id="Text Box 7" '
    'type="#_x0000_t202" style="position:absolute;width:144pt;height:36pt">'
    '<v:textbox><w:txbxContent><w:p><w:r><w:t>$text</w:t></w:r></w:p>'
    '</w:txbxContent></v:textbox></v:shape></w:pict></mc:Fallback>'
    '</mc:AlternateContent></w:r>';

/// A run holding an inline icon: the PNG `rId4` with the SVG `rId5`.
const String _iconRun =
    '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
    '<wp:extent cx="914400" cy="914400"/><wp:docPr id="3" name="Graphic 3" '
    'descr="Heart"/><a:graphic><a:graphicData uri="$_pic"><pic:pic>'
    '<pic:nvPicPr><pic:cNvPr id="3" name="Graphic 3"/><pic:cNvPicPr/>'
    '</pic:nvPicPr><pic:blipFill><a:blip r:embed="rId4"><a:extLst>'
    '<a:ext uri="{96DAC541-7B7A-43D3-8B79-37D633B846F1}">'
    '<asvg:svgBlip xmlns:asvg="$_asvg" r:embed="rId5"/></a:ext></a:extLst>'
    '</a:blip><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
    '<pic:spPr><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
    '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';

final String _document =
    '<w:document xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}" xmlns:wp="${Ns.wp}" '
    'xmlns:a="$_a" xmlns:pic="$_pic" xmlns:wps="$_wps" xmlns:mc="$_mc" '
    'xmlns:v="$_v" mc:Ignorable="wps"><w:body>'
    '<w:p><w:r><w:t xml:space="preserve">Before </w:t></w:r>'
    '${_textBoxRun('Inside the box')}'
    '<w:r><w:t xml:space="preserve"> after</w:t></w:r></w:p>'
    '<w:p>$_iconRun</w:p><w:p><w:r><w:t>End</w:t></w:r></w:p>'
    '</w:body></w:document>';

Uint8List _input() => buildDocx(
  document: _document,
  extra: <String, List<int>>{
    '[Content_Types].xml': utf8.encode(
      '<Types xmlns="$contentTypesNs">'
      '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
      '<Default Extension="png" ContentType="${ContentType.png}"/>'
      '<Default Extension="svg" ContentType="image/svg+xml"/>'
      '<Override PartName="/word/document.xml" '
      'ContentType="${ContentType.wmlDocument}"/></Types>',
    ),
    'word/_rels/document.xml.rels': utf8.encode(
      '<Relationships xmlns="$packageRelsNs">'
      '<Relationship Id="rId4" Type="${Ns.rel}/image" '
      'Target="media/image1.png"/><Relationship Id="rId5" '
      'Type="${Ns.rel}/image" Target="media/image2.svg"/></Relationships>',
    ),
    'word/media/image1.png': png4x2,
    'word/media/image2.svg': utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg"/>',
    ),
  },
);

void main() {
  test('a text box and an icon round-trip byte for byte', () {
    final Uint8List input = _input();
    final DocxDocument doc = DocxDocument.open(input);
    expect(doc.body.blocks, hasLength(3));
    final Map<String, Uint8List> before = readXlsxBytes(input);
    final Map<String, Uint8List> after = readXlsxBytes(doc.save().bytes);
    expect(after['word/document.xml'], before['word/document.xml']);
    expect(after['word/media/image2.svg'], before['word/media/image2.svg']);
  });

  test("a text box's text is not in its paragraph's text", () {
    final DocxDocument doc = DocxDocument.open(_input());
    final DocxParagraph p = doc.body.blocks.first as DocxParagraph;
    expect(p.text, 'Before  after');
    final List<DocxRunContent> content = <DocxRunContent>[
      for (final DocxInline i in p.inlines)
        if (i is DocxRun) ...i.content,
    ];
    expect(content.whereType<DocxOpaqueRunContent>(), hasLength(1));
  });

  test('an inline icon reads as a picture of its PNG fallback', () {
    final DocxDocument doc = DocxDocument.open(_input());
    final DocxParagraph p = doc.body.blocks[1] as DocxParagraph;
    final DocxPicture icon =
        (p.inlines.single as DocxRun).content.single as DocxPicture;
    expect(icon.image, OfficeImage(png4x2));
    expect(icon.description, 'Heart');
  });

  test("a new picture's id passes the text box's docPr id", () {
    final DocxDocument doc = DocxDocument.open(_input());
    (doc.body.blocks.last as DocxParagraph).addPicture(OfficeImage(png4x2));
    final String main = utf8.decode(
      readXlsxBytes(doc.save().bytes)['word/document.xml']!,
    );
    expect(main, contains('<wp:docPr id="8"'));
  });
}
