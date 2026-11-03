/// Test helper: a Word-like DOCX package built in memory.
///
/// [wordDocx] holds [wordDocumentXml], a `document.xml` as Word writes it,
/// with a picture and a settings part the model never loads. [richWordDocx]
/// adds to it what Word writes around ordinary text: a `w15` namespace in
/// `mc:Ignorable`, tracked insertions and deletions, a hyperlink, a
/// bookmark, a simple and a complex field, and a table. Nothing touches the
/// file system, so it runs in Chrome.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/src/opc/ooxml.dart';

import 'docx_builder.dart';

const String _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const String _pic = 'http://schemas.openxmlformats.org/drawingml/2006/picture';
const String _wp14 =
    'http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing';
const String _wps =
    'http://schemas.microsoft.com/office/word/2010/wordprocessingShape';

/// A `document.xml` as Word writes it: the root declares every namespace
/// and `mc:Ignorable`, paragraphs carry w14 ids and rsids, and the body
/// holds a block-level and an inline content control, a picture whose
/// `a:` namespace is declared on `a:graphic` itself, and markup
/// compatibility content.
const String wordDocumentXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    '<w:document xmlns:wpc="http://schemas.microsoft.com/office/word/2010/'
    'wordprocessingCanvas" xmlns:mc="${Ns.mc}" '
    'xmlns:o="urn:schemas-microsoft-com:office:office" '
    'xmlns:r="${Ns.rel}" '
    'xmlns:v="urn:schemas-microsoft-com:vml" xmlns:wp14="$_wp14" '
    'xmlns:wp="${Ns.wp}" xmlns:w10="urn:schemas-microsoft-com:office:word" '
    'xmlns:w="${Ns.w}" xmlns:w14="${Ns.w14}" xmlns:wps="$_wps" '
    'mc:Ignorable="w14 wp14">'
    '<w:body>'
    '<w:p w14:paraId="1A2B3C4D" w14:textId="77777777" w:rsidR="00A13F2E" '
    'w:rsidRDefault="00A13F2E" w:rsidP="00B21C11">'
    '<w:pPr><w:pStyle w:val="Title"/><w:rPr><w:lang w:val="tr-TR"/></w:rPr>'
    '</w:pPr>'
    '<w:r w:rsidRPr="00C3D4E5"><w:rPr><w:lang w:val="tr-TR"/></w:rPr>'
    '<w:t>Fiyat listesi</w:t></w:r>'
    '<w:proofErr w:type="spellStart"/>'
    '<w:r><w:t xml:space="preserve">Ürün </w:t></w:r>'
    '<w:proofErr w:type="spellEnd"/>'
    '</w:p>'
    '<w:sdt><w:sdtPr><w:id w:val="-1523981"/><w:docPartObj>'
    '<w:docPartGallery w:val="Table of Contents"/><w:docPartUnique/>'
    '</w:docPartObj></w:sdtPr><w:sdtEndPr/><w:sdtContent>'
    '<w:p w14:paraId="2B3C4D5E" w14:textId="2B3C4D5E" w:rsidR="00A13F2E">'
    '<w:r><w:t>İçindekiler</w:t></w:r></w:p>'
    '</w:sdtContent></w:sdt>'
    '<w:p w14:paraId="3C4D5E6F" w14:textId="3C4D5E6F" w:rsidR="00A13F2E" '
    'w:rsidRDefault="00D4E5F6">'
    '<w:r><w:t xml:space="preserve">Kalem: </w:t></w:r>'
    '<w:sdt><w:sdtPr><w:alias w:val="Ad"/><w:tag w:val="name"/>'
    '<w:id w:val="88"/></w:sdtPr><w:sdtContent>'
    '<w:r w:rsidR="00D4E5F6"><w:t>Defter</w:t></w:r>'
    '</w:sdtContent></w:sdt>'
    '<w:r><w:tab/><w:t>12</w:t><w:br/><w:t>adet</w:t></w:r>'
    '</w:p>'
    '<w:p w14:paraId="4D5E6F70" w14:textId="4D5E6F70" w:rsidR="00A13F2E">'
    '<w:r><w:rPr><w:noProof/></w:rPr><w:drawing>'
    '<wp:inline distT="0" distB="0" distL="0" distR="0" '
    'wp14:anchorId="5E6F7081" wp14:editId="5E6F7081">'
    '<wp:extent cx="914400" cy="457200"/>'
    '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
    '<wp:docPr id="1" name="Picture 1"/>'
    '<wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="$_a" '
    'noChangeAspect="1"/></wp:cNvGraphicFramePr>'
    '<a:graphic xmlns:a="$_a">'
    '<a:graphicData uri="$_pic">'
    '<pic:pic xmlns:pic="$_pic"><pic:nvPicPr>'
    '<pic:cNvPr id="1" name="logo.png"/><pic:cNvPicPr/></pic:nvPicPr>'
    '<pic:blipFill><a:blip r:embed="rId4"/><a:stretch><a:fillRect/>'
    '</a:stretch></pic:blipFill>'
    '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="914400" cy="457200"/>'
    '</a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
    '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>'
    '</w:p>'
    '<w:p w14:paraId="5E6F7081" w14:textId="5E6F7081" w:rsidR="00A13F2E">'
    '<w:r><mc:AlternateContent><mc:Choice Requires="wps">'
    '<w:drawing><wp:anchor distT="0" distB="0" distL="114300" '
    'distR="114300" simplePos="0" relativeHeight="251659264" behindDoc="0" '
    'locked="0" layoutInCell="1" allowOverlap="1"><wp:simplePos x="0" y="0"/>'
    '<wp:positionH relativeFrom="column"><wp:posOffset>0</wp:posOffset>'
    '</wp:positionH><wp:positionV relativeFrom="paragraph">'
    '<wp:posOffset>0</wp:posOffset></wp:positionV>'
    '<wp:extent cx="914400" cy="457200"/><wp:wrapNone/>'
    '<wp:docPr id="2" name="Text Box 2"/><a:graphic xmlns:a="$_a">'
    '<a:graphicData uri="$_wps"><wps:wsp><wps:bodyPr/></wps:wsp>'
    '</a:graphicData></a:graphic></wp:anchor></w:drawing>'
    '</mc:Choice><mc:Fallback><w:pict><v:rect style="width:72pt"/></w:pict>'
    '</mc:Fallback></mc:AlternateContent></w:r>'
    '<w:r><w:t>Son</w:t></w:r>'
    '</w:p>'
    '<w:sectPr w:rsidR="00A13F2E"><w:pgSz w:w="11906" w:h="16838"/>'
    '<w:pgMar w:top="1417" w:right="1417" w:bottom="1417" w:left="1417" '
    'w:header="708" w:footer="708" w:gutter="0"/><w:cols w:space="708"/>'
    '<w:docGrid w:linePitch="360"/></w:sectPr>'
    '</w:body></w:document>';

/// The relationships of [wordDocumentXml]: its picture.
const String wordDocumentRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    '<Relationships xmlns="$packageRelsNs">'
    '<Relationship Id="rId4" Type="${RelType.image}" '
    'Target="media/image1.png"/>'
    '</Relationships>';

/// A small binary stand-in for a PNG.
final List<int> _png = <int>[0x89, 0x50, 0x4E, 0x47, 0, 1, 2, 3, 255];

/// A DOCX holding [document], with [documentRels] as its relationships
/// when given, a picture, and a settings part the model never loads.
Uint8List wordDocx({
  String document = wordDocumentXml,
  String? documentRels = wordDocumentRels,
  bool store = false,
}) => buildZip(<String, List<int>>{
  '[Content_Types].xml': utf8.encode(
    '<Types xmlns="$contentTypesNs">'
    '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Default Extension="png" ContentType="image/png"/>'
    '<Override PartName="/word/document.xml" '
    'ContentType="${ContentType.wmlDocument}"/>'
    '</Types>',
  ),
  '_rels/.rels': utf8.encode(rootRels('word/document.xml')),
  'word/document.xml': utf8.encode(document),
  if (documentRels != null)
    'word/_rels/document.xml.rels': utf8.encode(documentRels),
  'word/media/image1.png': _png,
  'word/settings.xml': utf8.encode(
    '<w:settings xmlns:w="${Ns.w}"><w:zoom w:percent="100"/></w:settings>',
  ),
}, store: store);

const String _w15 = 'http://schemas.microsoft.com/office/word/2012/wordml';

/// The blocks [richWordDocumentXml] adds before the final `w:sectPr`: a
/// heading with a bookmark, a paragraph with a deletion, an insertion and a
/// hyperlink, one with a simple and a complex field, a paragraph with a
/// `w15` content control, and a table followed by an empty paragraph.
const String _richBlocks =
    '<w:p w14:paraId="6F708192" w14:textId="6F708192" w:rsidR="00A13F2E">'
    '<w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
    '<w:bookmarkStart w:id="0" w:name="_Toc1"/>'
    '<w:r><w:t>Değişiklikler</w:t></w:r>'
    '<w:bookmarkEnd w:id="0"/>'
    '</w:p>'
    '<w:p w14:paraId="708192A3" w14:textId="708192A3" w:rsidR="00A13F2E" '
    'w:rsidRDefault="00E5F607">'
    '<w:r><w:t xml:space="preserve">Eski </w:t></w:r>'
    '<w:del w:id="1" w:author="Ayşe" w:date="2026-01-02T03:04:00Z">'
    '<w:r w:rsidDel="00E5F607"><w:delText>fiyat</w:delText></w:r></w:del>'
    '<w:ins w:id="2" w:author="Ayşe" w:date="2026-01-02T03:04:00Z">'
    '<w:r w:rsidR="00E5F607"><w:t>tutar</w:t></w:r></w:ins>'
    '<w:r><w:t xml:space="preserve">, bkz. </w:t></w:r>'
    '<w:hyperlink r:id="rId5" w:history="1"><w:r>'
    '<w:rPr><w:rStyle w:val="Hyperlink"/></w:rPr><w:t>site</w:t></w:r>'
    '</w:hyperlink>'
    '</w:p>'
    '<w:p w14:paraId="8192A3B4" w14:textId="8192A3B4" w:rsidR="00A13F2E">'
    '<w:r><w:t xml:space="preserve">Sayfa </w:t></w:r>'
    '<w:fldSimple w:instr=" PAGE   \\* MERGEFORMAT "><w:r><w:t>1</w:t></w:r>'
    '</w:fldSimple>'
    '<w:r><w:t xml:space="preserve"> / </w:t></w:r>'
    '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
    '<w:r><w:instrText xml:space="preserve"> NUMPAGES </w:instrText></w:r>'
    '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
    '<w:r><w:t>2</w:t></w:r>'
    '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
    '</w:p>'
    '<w:p w14:paraId="92A3B4C5" w14:textId="92A3B4C5" w:rsidR="00A13F2E">'
    '<w:sdt><w:sdtPr><w:id w:val="99"/><w15:appearance w15:val="hidden"/>'
    '</w:sdtPr><w:sdtContent><w:r><w:t>Gizli</w:t></w:r></w:sdtContent>'
    '</w:sdt>'
    '</w:p>'
    '<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/>'
    '<w:tblW w:w="0" w:type="auto"/><w:tblLook w:val="04A0"/></w:tblPr>'
    '<w:tblGrid><w:gridCol w:w="4531"/><w:gridCol w:w="4531"/></w:tblGrid>'
    '<w:tr w:rsidR="00A13F2E" w14:paraId="A3B4C5D6" w14:textId="A3B4C5D6">'
    '<w:tc><w:tcPr><w:tcW w:w="4531" w:type="dxa"/></w:tcPr>'
    '<w:p w14:paraId="B4C5D6E7" w14:textId="B4C5D6E7" w:rsidR="00A13F2E">'
    '<w:r><w:t>Ürün</w:t></w:r></w:p></w:tc>'
    '<w:tc><w:tcPr><w:tcW w:w="4531" w:type="dxa"/></w:tcPr>'
    '<w:p w14:paraId="C5D6E7F8" w14:textId="C5D6E7F8" w:rsidR="00A13F2E">'
    '<w:r><w:t>Fiyat</w:t></w:r></w:p></w:tc>'
    '</w:tr></w:tbl>'
    '<w:p w14:paraId="D6E7F809" w14:textId="D6E7F809" w:rsidR="00A13F2E"/>';

/// [wordDocumentXml] with the root also declaring `w15`, which
/// `mc:Ignorable` names, and the blocks of `_richBlocks` before the final
/// `w:sectPr`.
final String richWordDocumentXml = wordDocumentXml
    .replaceFirst(
      'xmlns:w14="${Ns.w14}"',
      'xmlns:w14="${Ns.w14}" '
          'xmlns:w15="$_w15"',
    )
    .replaceFirst('mc:Ignorable="w14 wp14"', 'mc:Ignorable="w14 w15 wp14"')
    .replaceFirst('<w:sectPr w:rsidR=', '$_richBlocks<w:sectPr w:rsidR=');

/// The relationships of [richWordDocumentXml]: its picture and its
/// external hyperlink.
const String richWordDocumentRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    '<Relationships xmlns="$packageRelsNs">'
    '<Relationship Id="rId4" Type="${RelType.image}" '
    'Target="media/image1.png"/>'
    '<Relationship Id="rId5" Type="${RelType.hyperlink}" '
    'Target="https://example.com/fiyat" TargetMode="External"/>'
    '</Relationships>';

/// A DOCX holding [richWordDocumentXml], its relationships, a picture and a
/// settings part, every entry stored, not deflated, so its bytes are the
/// same on every platform.
Uint8List richWordDocx() => wordDocx(
  document: richWordDocumentXml,
  documentRels: richWordDocumentRels,
  store: true,
);
