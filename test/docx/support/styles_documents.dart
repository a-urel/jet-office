/// Test helper: DOCX packages in memory with a styles part as Word and
/// LibreOffice write it, wherever the main part's relationship puts it.
/// Nothing touches the file system, so it runs in Chrome.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/src/opc/ooxml.dart';

import '../../support/read_xlsx.dart';
import 'docx_builder.dart';
import 'word_document.dart';

/// A `styles.xml` as Word writes it: the root declares `mc`, `w14` and
/// `w15` with `mc:Ignorable`, the document defaults hold `w14:ligatures`,
/// the latent styles come before the styles, and the styles carry `w14`
/// attributes, an rsid, a table style with `w:tblPr` and a style Word does
/// not type (`w:tblStylePr`).
const String wordStylesXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    '<w:styles xmlns:mc="${Ns.mc}" xmlns:r="${Ns.rel}" xmlns:w="${Ns.w}" '
    'xmlns:w14="${Ns.w14}" '
    'xmlns:w15="http://schemas.microsoft.com/office/word/2012/wordml" '
    'mc:Ignorable="w14 w15">'
    '<w:docDefaults><w:rPrDefault><w:rPr>'
    '<w:rFonts w:asciiTheme="minorHAnsi" w:eastAsiaTheme="minorHAnsi" '
    'w:hAnsiTheme="minorHAnsi" w:cstheme="minorBidi"/>'
    '<w:kern w:val="2"/><w:sz w:val="24"/><w:szCs w:val="24"/>'
    '<w:lang w:val="tr-TR" w:eastAsia="en-US" w:bidi="ar-SA"/>'
    '<w14:ligatures w14:val="standardContextual"/></w:rPr></w:rPrDefault>'
    '<w:pPrDefault><w:pPr>'
    '<w:spacing w:after="160" w:line="278" w:lineRule="auto"/></w:pPr>'
    '</w:pPrDefault></w:docDefaults>'
    '<w:latentStyles w:defLockedState="0" w:defUIPriority="99" '
    'w:defSemiHidden="0" w:defUnhideWhenUsed="0" w:defQFormat="0" '
    'w:count="376">'
    '<w:lsdException w:name="Normal" w:uiPriority="0" w:qFormat="1"/>'
    '<w:lsdException w:name="heading 1" w:uiPriority="9" w:qFormat="1"/>'
    '</w:latentStyles>'
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
    '<w:name w:val="Normal"/><w:qFormat/></w:style>'
    '<w:style w:type="paragraph" w:styleId="Balk1">'
    '<w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>'
    '<w:next w:val="Normal"/><w:link w:val="Balk1Char"/>'
    '<w:uiPriority w:val="9"/><w:qFormat/><w:rsid w:val="00A13F2E"/>'
    '<w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="360" '
    'w:after="80"/><w:outlineLvl w:val="0"/></w:pPr>'
    '<w:rPr><w:rFonts w:asciiTheme="majorHAnsi" '
    'w:eastAsiaTheme="majorEastAsia" w:hAnsiTheme="majorHAnsi" '
    'w:cstheme="majorBidi"/>'
    '<w:color w:val="0F4761" w:themeColor="accent1" w:themeShade="BF"/>'
    '<w:sz w:val="40"/><w:szCs w:val="40"/></w:rPr></w:style>'
    '<w:style w:type="character" w:default="1" '
    'w:styleId="VarsaylanParagrafYazTipi">'
    '<w:name w:val="Default Paragraph Font"/><w:uiPriority w:val="1"/>'
    '<w:semiHidden/><w:unhideWhenUsed/></w:style>'
    '<w:style w:type="character" w:customStyle="1" w:styleId="Balk1Char">'
    '<w:name w:val="Başlık 1 Char"/>'
    '<w:basedOn w:val="VarsaylanParagrafYazTipi"/><w:link w:val="Balk1"/>'
    '<w:uiPriority w:val="9"/>'
    '<w:rPr><w:sz w:val="40"/></w:rPr></w:style>'
    '<w:style w:type="table" w:default="1" w:styleId="NormalTablo">'
    '<w:name w:val="Normal Table"/><w:uiPriority w:val="99"/><w:semiHidden/>'
    '<w:unhideWhenUsed/><w:tblPr><w:tblInd w:w="0" w:type="dxa"/>'
    '<w:tblCellMar><w:top w:w="0" w:type="dxa"/></w:tblCellMar></w:tblPr>'
    '</w:style>'
    '<w:style w:type="table" w:styleId="TabloKlavuzu" w14:x="1">'
    '<w:name w:val="Table Grid"/><w:basedOn w:val="NormalTablo"/>'
    '<w:uiPriority w:val="39"/><w:tblPr><w:tblBorders><w:top w:val="single" '
    'w:sz="4" w:space="0" w:color="auto"/></w:tblBorders></w:tblPr>'
    '<w:tblStylePr w:type="firstRow"><w:rPr><w:b/></w:rPr></w:tblStylePr>'
    '</w:style>'
    '<w:style w:type="numbering" w:default="1" w:styleId="ListeYok">'
    '<w:name w:val="No List"/><w:uiPriority w:val="99"/><w:semiHidden/>'
    '<w:unhideWhenUsed/></w:style>'
    '</w:styles>';

/// A `styles.xml` as LibreOffice writes it: no `mc:Ignorable`, a `w14`
/// declaration with a `w14` attribute on the root, the styles before the
/// latent styles and the defaults, and a child of another namespace.
const String libreOfficeStylesXml =
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<w:styles xmlns:w="${Ns.w}" xmlns:w14="${Ns.w14}" xmlns:mc="${Ns.mc}" '
    'w14:lo="1">'
    '<w:docDefaults><w:rPrDefault><w:rPr>'
    '<w:rFonts w:ascii="Liberation Serif" w:hAnsi="Liberation Serif" '
    'w:eastAsia="Noto Serif CJK SC" w:cs="Lohit Devanagari"/>'
    '<w:kern w:val="2"/><w:sz w:val="24"/><w:szCs w:val="24"/>'
    '<w:lang w:val="en-US" w:eastAsia="zh-CN" w:bidi="hi-IN"/></w:rPr>'
    '</w:rPrDefault><w:pPrDefault><w:pPr><w:suppressAutoHyphens w:val="true"/>'
    '</w:pPr></w:pPrDefault></w:docDefaults>'
    '<w:latentStyles w:count="376"/>'
    '<w:style w:type="paragraph" w:styleId="Normal">'
    '<w:name w:val="Normal"/><w:qFormat/>'
    '<w:pPr><w:widowControl/><w:bidi w:val="0"/></w:pPr>'
    '<w:rPr><w:rFonts w:ascii="Liberation Serif" w:hAnsi="Liberation Serif"/>'
    '<w:color w:val="auto"/><w:sz w:val="24"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading1">'
    '<w:name w:val="Heading 1"/><w:basedOn w:val="Heading"/>'
    '<w:next w:val="BodyText"/><w:qFormat/>'
    '<w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="0"/></w:numPr>'
    '<w:spacing w:before="240" w:after="120"/><w:outlineLvl w:val="0"/>'
    '</w:pPr><w:rPr><w:b/><w:bCs/><w:sz w:val="36"/></w:rPr></w:style>'
    '<w14:extra w14:val="1"/>'
    '</w:styles>';

/// The relationship of the main part to a styles part at [target].
String stylesRelationship(
  String target, {
  String id = 'rId9',
  bool external = false,
}) =>
    '<Relationship Id="$id" Type="${RelType.styles}" Target="$target"'
    '${external ? ' TargetMode="External"' : ''}/>';

/// A Word-like DOCX: [wordDocumentXml] with its picture and settings part,
/// and [styles] at [stylesPath] (a ZIP entry name, no leading `/`) when it
/// is not null, with a content type override of [stylesContentType] (none
/// when it is null, so the part has the `xml` default, `application/xml`).
/// The main part's relationships hold the picture's, the settings part's
/// and [relationships] (by default one to `styles.xml`; empty for none).
Uint8List docxWithStyles({
  String? styles = wordStylesXml,
  String stylesPath = 'word/styles.xml',
  String? stylesContentType = ContentType.wmlStyles,
  String? relationships,
}) => buildZip(<String, List<int>>{
  '[Content_Types].xml': utf8.encode(
    '<Types xmlns="$contentTypesNs">'
    '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Default Extension="png" ContentType="image/png"/>'
    '<Override PartName="/word/document.xml" '
    'ContentType="${ContentType.wmlDocument}"/>'
    '${styles == null || stylesContentType == null ? '' : '<Override PartName="/$stylesPath" '
              'ContentType="$stylesContentType"/>'}'
    '</Types>',
  ),
  '_rels/.rels': utf8.encode(rootRels('word/document.xml')),
  'word/document.xml': utf8.encode(wordDocumentXml),
  'word/_rels/document.xml.rels': utf8.encode(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    '<Relationships xmlns="$packageRelsNs">'
    '<Relationship Id="rId4" Type="${RelType.image}" '
    'Target="media/image1.png"/>'
    '<Relationship Id="rId5" Type="${RelType.settings}" '
    'Target="settings.xml"/>'
    '${relationships ?? stylesRelationship('styles.xml')}'
    '</Relationships>',
  ),
  'word/media/image1.png': <int>[0x89, 0x50, 0x4E, 0x47, 0, 1, 2, 3],
  'word/settings.xml': utf8.encode(
    '<w:settings xmlns:w="${Ns.w}"><w:zoom w:percent="100"/></w:settings>',
  ),
  if (styles != null) stylesPath: utf8.encode(styles),
});

/// The text parts of the DOCX file [bytes] by entry name, decoded as UTF-8;
/// the media parts (`word/media/`) are left out.
Map<String, String> readDocxText(Uint8List bytes) => <String, String>{
  for (final MapEntry<String, Uint8List> part in readXlsxBytes(bytes).entries)
    if (!part.key.startsWith('word/media/')) part.key: utf8.decode(part.value),
};
