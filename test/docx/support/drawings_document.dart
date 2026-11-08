/// Test helper: a DOCX written by hand with inline, anchored and linked
/// pictures, broken picture references, external, anchor and broken
/// hyperlinks, bookmarks at block and paragraph level with bad ids, a header
/// with a picture and a hyperlink, and core, app and custom properties with
/// values that cannot be read, as the fuzzer's corpus entry
/// `drawings_by_hand`.
///
/// Not ported from Quds. The well-formed elements stand as Word writes them;
/// the broken ones and the mutations then take the file out of its schema.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/src/opc/ooxml.dart';

import '../../fixtures/m4_fixtures.dart' show png4x2;
import 'docx_builder.dart';

const String _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const String _pic = 'http://schemas.openxmlformats.org/drawingml/2006/picture';

/// The namespaces of a part holding pictures and hyperlinks.
const String _decls =
    'xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}" xmlns:wp="${Ns.wp}" '
    'xmlns:a="$_a" xmlns:pic="$_pic"';

/// A paragraph holding [text].
String _p(String text) => '<w:p><w:r><w:t>$text</w:t></w:r></w:p>';

/// A run holding a `w:drawing` of [kind] (`inline` or `anchor`): [extent] is
/// the `wp:extent`, [docPr] the `wp:docPr`, [cNvPr] the `pic:cNvPr` and
/// [blip] the attributes of `a:blip`.
String _drawing({
  String kind = 'inline',
  String extent = '<wp:extent cx="50800" cy="25400"/>',
  String docPr = '<wp:docPr id="1" name="Picture 1" descr="A logo"/>',
  String cNvPr = '<pic:cNvPr id="0" name="logo.png"/>',
  String blip = 'r:embed="rId4"',
}) =>
    '<w:r><w:drawing><wp:$kind distT="0" distB="0" distL="0" distR="0">'
    '${kind == 'anchor' ? '<wp:simplePos x="0" y="0"/>'
              '<wp:positionH relativeFrom="column"><wp:posOffset>0'
              '</wp:posOffset></wp:positionH><wp:positionV '
              'relativeFrom="paragraph"><wp:posOffset>0</wp:posOffset>'
              '</wp:positionV>' : ''}'
    '$extent${kind == 'anchor' ? '<wp:wrapNone/>' : ''}$docPr'
    '<a:graphic><a:graphicData uri="$_pic"><pic:pic>'
    '<pic:nvPicPr>$cNvPr<pic:cNvPicPr/></pic:nvPicPr>'
    '<pic:blipFill><a:blip $blip/><a:stretch><a:fillRect/></a:stretch>'
    '</pic:blipFill><pic:spPr><a:prstGeom prst="rect"><a:avLst/>'
    '</a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic>'
    '</wp:$kind></w:drawing></w:r>';

/// The body of [drawingsByHandDocx].
final String _body =
    // A block-level bookmark around the first paragraph.
    '<w:bookmarkStart w:id="0" w:name="Top"/>'
    '${_p('Pictures')}'
    '<w:bookmarkEnd w:id="0"/>'
    // A good inline picture, an anchored one, a linked one.
    '<w:p>${_drawing()}'
    '${_drawing(kind: 'anchor', docPr: '<wp:docPr id="2" name="Float"/>')}'
    '${_drawing(docPr: '<wp:docPr id="3" name="Linked"/>', blip: 'r:link="rId6"')}'
    '</w:p>'
    // A broken r:embed, a missing media part, an external image, a
    // relationship of the wrong type, no blip id, both embed and link.
    '<w:p>'
    '${_drawing(docPr: '<wp:docPr id="4" name="Broken"/>', blip: 'r:embed="rId999"')}'
    '${_drawing(docPr: '<wp:docPr id="5" name="Missing"/>', blip: 'r:embed="rId5"')}'
    '${_drawing(docPr: '<wp:docPr id="6" name="External"/>', blip: 'r:embed="rId6"')}'
    '${_drawing(docPr: '<wp:docPr id="7" name="Wrong"/>', blip: 'r:embed="rId7"')}'
    '${_drawing(docPr: '<wp:docPr id="8"/>', blip: '')}'
    '${_drawing(docPr: '<wp:docPr id="9" name="Both"/>', blip: 'r:embed="rId4" r:link="rId6"')}'
    '</w:p>'
    // Bad sizes, a bad docPr id, a missing docPr, a bad cNvPr id.
    '<w:p>'
    '${_drawing(extent: '<wp:extent cx="abc" cy="-1"/>')}'
    '${_drawing(extent: '<wp:extent/>', docPr: '<wp:docPr id="x" name="Bad id"/>')}'
    '${_drawing(docPr: '')}'
    '${_drawing(cNvPr: '<pic:cNvPr id="y" name="bad"/>')}'
    '${_drawing(extent: '<wp:extent cx="99999999999999999999" cy="1"/>')}'
    '</w:p>'
    // An external link, an anchor link, a link to a missing relationship, a
    // link of the wrong relationship type, a link with both, a link with a
    // field and a picture inside, an empty link.
    '<w:p>'
    '<w:hyperlink r:id="rId8" w:tooltip="Example" w:history="1">'
    '<w:r><w:rPr><w:rStyle w:val="Hyperlink"/></w:rPr><w:t>External</w:t>'
    '</w:r></w:hyperlink>'
    '<w:hyperlink w:anchor="Top"><w:r><w:t>Back to top</w:t></w:r>'
    '</w:hyperlink>'
    '<w:hyperlink r:id="rId998"><w:r><w:t>Nowhere</w:t></w:r></w:hyperlink>'
    '<w:hyperlink r:id="rId4"><w:r><w:t>An image</w:t></w:r></w:hyperlink>'
    '<w:hyperlink r:id="rId8" w:anchor="Top"><w:r><w:t>Both</w:t></w:r>'
    '</w:hyperlink>'
    '<w:hyperlink w:anchor="Top">'
    '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
    '<w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'
    '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
    '<w:r><w:t>1</w:t></w:r>'
    '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
    '${_drawing(docPr: '<wp:docPr id="10" name="In link"/>')}'
    '</w:hyperlink>'
    '<w:hyperlink/>'
    '</w:p>'
    // Paragraph bookmarks: bad ids, a duplicate, an end with no start, a
    // start with no end, a start with no name, an end with no id.
    '<w:p>'
    '<w:bookmarkStart w:id="abc" w:name="Bad"/><w:r><w:t>Marked</w:t></w:r>'
    '<w:bookmarkEnd w:id="abc"/>'
    '<w:bookmarkStart w:id="-1" w:name="Negative"/>'
    '<w:bookmarkStart w:id="99999999999999999999" w:name="Huge"/>'
    '<w:bookmarkStart w:id="0" w:name="Top"/>'
    '<w:bookmarkEnd w:id="42"/>'
    '<w:bookmarkStart w:id="7"/>'
    '<w:bookmarkEnd/>'
    '<w:bookmarkEnd w:id="-1"/>'
    '</w:p>'
    '${_p('End')}'
    '<w:sectPr><w:headerReference w:type="default" r:id="rId11"/>'
    '<w:pgSz w:w="11906" w:h="16838"/></w:sectPr>';

/// The main part: [_body].
final String drawingsByHandDocumentXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    '<w:document $_decls><w:body>$_body</w:body></w:document>';

/// A relationship of [type] with [id] to [target], external when [external].
String _rel(String id, String type, String target, {bool external = false}) =>
    '<Relationship Id="$id" Type="$type" Target="$target"'
    '${external ? ' TargetMode="External"' : ''}/>';

/// The relationships of the main part: an image, a missing media part, an
/// external image, a hyperlink where an image is named, an external
/// hyperlink and the header.
final String drawingsByHandRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    '<Relationships xmlns="$packageRelsNs">'
    '${_rel('rId4', RelType.image, 'media/image1.png')}'
    '${_rel('rId5', RelType.image, 'media/missing.png')}'
    '${_rel('rId6', RelType.image, 'https://example.com/i.png', external: true)}'
    '${_rel('rId7', RelType.hyperlink, 'https://example.com/', external: true)}'
    '${_rel('rId8', RelType.hyperlink, 'https://example.com/a?b=1&amp;c=2', external: true)}'
    '${_rel('rId11', RelType.header, 'header1.xml')}'
    '</Relationships>';

/// The root relationships: the main part and the three properties parts.
final String _rootRels =
    '<Relationships xmlns="$packageRelsNs">'
    '${_rel('rId1', RelType.officeDocument, 'word/document.xml')}'
    '${_rel('rId2', RelType.coreProperties, 'docProps/core.xml')}'
    '${_rel('rId3', RelType.extendedProperties, 'docProps/app.xml')}'
    '${_rel('rId4', RelType.customProperties, 'docProps/custom.xml')}'
    '</Relationships>';

/// Core properties: good text, a revision and dates that cannot be read, an
/// element twice.
const String _core =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    '<cp:coreProperties xmlns:cp="${Ns.core}" xmlns:dc="${Ns.dc}" '
    'xmlns:dcterms="${Ns.dcterms}" xmlns:dcmitype="${Ns.dcmitype}" '
    'xmlns:xsi="${Ns.xsi}">'
    '<dc:title>Drawings</dc:title><dc:title>Again</dc:title>'
    '<dc:creator>Ahmet</dc:creator><cp:lastModifiedBy></cp:lastModifiedBy>'
    '<cp:revision>abc</cp:revision>'
    '<dcterms:created xsi:type="dcterms:W3CDTF">yesterday</dcterms:created>'
    '<dcterms:modified xsi:type="dcterms:W3CDTF">2026-13-45T25:61:61Z'
    '</dcterms:modified>'
    '<cp:contentStatus>Draft</cp:contentStatus>'
    '</cp:coreProperties>';

/// Extended properties: an application, a company and values the model does
/// not type, one of them broken.
const String _app =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    '<Properties xmlns="${Ns.extendedProperties}" '
    'xmlns:vt="${Ns.docPropsVTypes}">'
    '<Template>Normal.dotm</Template><TotalTime>-</TotalTime>'
    '<Pages>x</Pages><Application>Microsoft Office Word</Application>'
    '<Company>Acme</Company><Manager/>'
    '<HeadingPairs><vt:vector size="2" baseType="variant">'
    '<vt:variant><vt:lpstr>Title</vt:lpstr></vt:variant>'
    '<vt:variant><vt:i4>abc</vt:i4></vt:variant></vt:vector></HeadingPairs>'
    '</Properties>';

/// Custom properties: one of each type, values that cannot be read, a name
/// twice ignoring case, a property without a name, a type the model does not
/// know and one without a value.
const String _custom =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    '<Properties xmlns="${Ns.customProperties}" '
    'xmlns:vt="${Ns.docPropsVTypes}">'
    '<property fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="2" '
    'name="Text"><vt:lpwstr>value</vt:lpwstr></property>'
    '<property fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="3" '
    'name="Count"><vt:i4>abc</vt:i4></property>'
    '<property fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="4" '
    'name="Ratio"><vt:r8>1in</vt:r8></property>'
    '<property fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="5" '
    'name="Done"><vt:bool>maybe</vt:bool></property>'
    '<property fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="6" '
    'name="When"><vt:filetime>soon</vt:filetime></property>'
    '<property fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="7" '
    'name="text"><vt:lpwstr>twice</vt:lpwstr></property>'
    '<property fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="8">'
    '<vt:lpwstr>no name</vt:lpwstr></property>'
    '<property fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="x" '
    'name="Blob"><vt:blob>AAAA</vt:blob></property>'
    '<property fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="10" '
    'name="Empty"/>'
    '</Properties>';

/// The header: a picture of its own media relationship, one whose
/// relationship is missing, an external link and a link with no
/// relationship.
final String _header =
    '<w:hdr $_decls>'
    '<w:p>${_drawing(docPr: '<wp:docPr id="11" name="Header logo"/>', blip: 'r:embed="rId1"')}'
    '${_drawing(docPr: '<wp:docPr id="12" name="Gone"/>', blip: 'r:embed="rId9"')}'
    '<w:hyperlink r:id="rId2"><w:r><w:t>Home</w:t></w:r></w:hyperlink>'
    '<w:hyperlink r:id="rId3"><w:r><w:t>Lost</w:t></w:r></w:hyperlink>'
    '<w:bookmarkStart w:id="1" w:name="Header"/><w:bookmarkEnd w:id="1"/>'
    '</w:p></w:hdr>';

/// The header's relationships: the shared image and an external link.
final String _headerRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    '<Relationships xmlns="$packageRelsNs">'
    '${_rel('rId1', RelType.image, 'media/image1.png')}'
    '${_rel('rId2', RelType.hyperlink, 'https://example.com/home', external: true)}'
    '</Relationships>';

/// A DOCX holding [drawingsByHandDocumentXml], a PNG media part, a header
/// with a picture and a hyperlink, and core, app and custom properties, every
/// entry stored.
Uint8List drawingsByHandDocx() => buildZip(<String, List<int>>{
  '[Content_Types].xml': utf8.encode(
    '<Types xmlns="$contentTypesNs">'
    '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Default Extension="png" ContentType="${ContentType.png}"/>'
    '<Override PartName="/word/document.xml" '
    'ContentType="${ContentType.wmlDocument}"/>'
    '<Override PartName="/word/header1.xml" '
    'ContentType="${ContentType.wmlHeader}"/>'
    '<Override PartName="/docProps/core.xml" '
    'ContentType="${ContentType.coreProperties}"/>'
    '<Override PartName="/docProps/app.xml" '
    'ContentType="${ContentType.extendedProperties}"/>'
    '<Override PartName="/docProps/custom.xml" '
    'ContentType="${ContentType.customProperties}"/>'
    '</Types>',
  ),
  '_rels/.rels': utf8.encode(_rootRels),
  'docProps/core.xml': utf8.encode(_core),
  'docProps/app.xml': utf8.encode(_app),
  'docProps/custom.xml': utf8.encode(_custom),
  'word/document.xml': utf8.encode(drawingsByHandDocumentXml),
  'word/_rels/document.xml.rels': utf8.encode(drawingsByHandRels),
  'word/media/image1.png': png4x2,
  'word/header1.xml': utf8.encode(_header),
  'word/_rels/header1.xml.rels': utf8.encode(_headerRels),
}, store: true);
