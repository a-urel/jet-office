/// Test helper: DOCX packages in memory with a numbering part as Word
/// writes it, wherever the main part's relationship puts it. Nothing
/// touches the file system, so it runs in Chrome.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/src/opc/ooxml.dart';

import 'docx_builder.dart';
import 'word_document.dart';

/// The `w15` namespace (Word 2012).
const String w15Ns = 'http://schemas.microsoft.com/office/word/2012/wordml';

/// The `w16cid` namespace (Word's durable ids).
const String w16cidNs =
    'http://schemas.microsoft.com/office/word/2016/wordml/cid';

const String _o = 'urn:schemas-microsoft-com:office:office';
const String _v = 'urn:schemas-microsoft-com:vml';

/// The root start tag Word writes for `numbering.xml`: `mc`, `o`, `r`,
/// `v`, `w`, `w14`, `w15` and `w16cid` declared, with `mc:Ignorable`.
const String wordNumberingRoot =
    '<w:numbering xmlns:mc="${Ns.mc}" xmlns:o="$_o" xmlns:r="${Ns.rel}" '
    'xmlns:v="$_v" xmlns:w="${Ns.w}" xmlns:w14="${Ns.w14}" '
    'xmlns:w15="$w15Ns" xmlns:w16cid="$w16cidNs" '
    'mc:Ignorable="w14 w15 w16cid">';

/// A `numbering.xml` as Word for Mac writes it: a picture bullet
/// (`w:numPicBullet`), a bullet list (abstract 0) and a numbered list
/// (abstract 1) with `w:nsid`, `w:tmpl`, `w:lvl/@w:tplc`, `@w:tentative`
/// and `@w15:restartNumberingAfterBreak`, two instances with
/// `@w16cid:durableId` (the second with a start override), and
/// `w:numIdMacAtCleanup`.
const String wordNumberingXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    '$wordNumberingRoot'
    '<w:numPicBullet w:numPicBulletId="0"><w:pict>'
    '<v:shape id="_x0000_i1026" type="#_x0000_t75" '
    'style="width:11.25pt;height:11.25pt" o:bullet="t">'
    '<v:imagedata r:id="rId1" o:title="mso"/></v:shape></w:pict>'
    '</w:numPicBullet>'
    '<w:abstractNum w:abstractNumId="0" w15:restartNumberingAfterBreak="0">'
    '<w:nsid w:val="1F2E3D4C"/><w:multiLevelType w:val="hybridMultilevel"/>'
    '<w:tmpl w:val="A1B2C3D4"/>'
    '<w:lvl w:ilvl="0" w:tplc="041F0001"><w:start w:val="1"/>'
    '<w:numFmt w:val="bullet"/><w:lvlText w:val=""/>'
    '<w:lvlJc w:val="left"/><w:pPr><w:ind w:left="720" w:hanging="360"/>'
    '</w:pPr><w:rPr><w:rFonts w:ascii="Symbol" w:hAnsi="Symbol" '
    'w:hint="default"/></w:rPr></w:lvl>'
    '<w:lvl w:ilvl="1" w:tplc="041F0003" w:tentative="1">'
    '<w:start w:val="1"/><w:numFmt w:val="bullet"/><w:lvlText w:val="o"/>'
    '<w:lvlJc w:val="left"/><w:pPr><w:ind w:left="1440" w:hanging="360"/>'
    '</w:pPr><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" '
    'w:cs="Courier New" w:hint="default"/></w:rPr></w:lvl>'
    '</w:abstractNum>'
    '<w:abstractNum w:abstractNumId="1" w15:restartNumberingAfterBreak="0">'
    '<w:nsid w:val="5A6B7C8D"/><w:multiLevelType w:val="hybridMultilevel"/>'
    '<w:tmpl w:val="E1F2A3B4"/>'
    '<w:lvl w:ilvl="0" w:tplc="041F000F"><w:start w:val="1"/>'
    '<w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/>'
    '<w:lvlJc w:val="left"/><w:pPr><w:ind w:left="720" w:hanging="360"/>'
    '</w:pPr></w:lvl>'
    '<w:lvl w:ilvl="1" w:tplc="041F0019" w:tentative="1">'
    '<w:start w:val="3"/><w:numFmt w:val="lowerLetter"/>'
    '<w:lvlText w:val="%2)"/><w:lvlJc w:val="center"/>'
    '<w:pPr><w:ind w:left="1440" w:hanging="360"/></w:pPr></w:lvl>'
    '<w:lvl w:ilvl="2" w:tplc="041F001B" w:tentative="1">'
    '<w:start w:val="1"/><w:numFmt w:val="lowerRoman"/>'
    '<w:lvlText w:val="%3."/><w:lvlJc w:val="right"/>'
    '<w:pPr><w:ind w:left="2160" w:hanging="180"/></w:pPr></w:lvl>'
    '</w:abstractNum>'
    '<w:num w:numId="1" w16cid:durableId="123456789">'
    '<w:abstractNumId w:val="0"/></w:num>'
    '<w:num w:numId="2" w16cid:durableId="987654321">'
    '<w:abstractNumId w:val="1"/>'
    '<w:lvlOverride w:ilvl="0"><w:startOverride w:val="5"/></w:lvlOverride>'
    '</w:num>'
    '<w:numIdMacAtCleanup w:val="1"/>'
    '</w:numbering>';

/// A `numbering.xml` whose root declares only `w` and holds [children].
String numberingXml(String children) =>
    '<w:numbering xmlns:w="${Ns.w}">$children</w:numbering>';

/// An abstract definition with the id [id] (as written) and one decimal
/// level 0.
String abstractNumXml(String id) =>
    '<w:abstractNum w:abstractNumId="$id">'
    '<w:multiLevelType w:val="singleLevel"/>'
    '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/>'
    '<w:lvlText w:val="%1."/></w:lvl></w:abstractNum>';

/// An instance with the id [id] (as written) of the abstract definition
/// [abstractId].
String numXml(String id, String abstractId) =>
    '<w:num w:numId="$id"><w:abstractNumId w:val="$abstractId"/></w:num>';

/// A one-level decimal list definition as a list helper hands it in: a
/// `w:abstractNum` without an id, whose prefix `w` is declared on it.
const String decimalTemplate =
    '<w:abstractNum xmlns:w="${Ns.w}">'
    '<w:multiLevelType w:val="hybridMultilevel"/>'
    '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/>'
    '<w:lvlText w:val="%1."/><w:lvlJc w:val="left"/>'
    '<w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>'
    '</w:abstractNum>';

/// The relationship of the main part to a numbering part at [target].
String numberingRelationship(String target, {String id = 'rId8'}) =>
    '<Relationship Id="$id" Type="${RelType.numbering}" Target="$target"/>';

/// A Word-like DOCX: [document] (by default [wordDocumentXml]) with its
/// picture and settings part, and [numbering] at `word/numbering.xml` when
/// it is not null, with its content type override and, when
/// [pictureTarget] is not null, a relationships part that relates the
/// picture bullet to [pictureTarget]. The main part's relationships hold
/// the picture's, the settings part's and [relationships] (by default one
/// to `numbering.xml`; empty for none).
Uint8List docxWithNumbering({
  String? numbering = wordNumberingXml,
  String document = wordDocumentXml,
  String? relationships,
  String? pictureTarget = 'media/image2.png',
}) => buildZip(<String, List<int>>{
  '[Content_Types].xml': utf8.encode(
    '<Types xmlns="$contentTypesNs">'
    '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Default Extension="png" ContentType="image/png"/>'
    '<Override PartName="/word/document.xml" '
    'ContentType="${ContentType.wmlDocument}"/>'
    '<Override PartName="/word/settings.xml" '
    'ContentType="${ContentType.wmlSettings}"/>'
    '${numbering == null ? '' : '<Override PartName="/word/numbering.xml" '
              'ContentType="${ContentType.wmlNumbering}"/>'}'
    '</Types>',
  ),
  '_rels/.rels': utf8.encode(rootRels('word/document.xml')),
  'word/document.xml': utf8.encode(document),
  'word/_rels/document.xml.rels': utf8.encode(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    '<Relationships xmlns="$packageRelsNs">'
    '<Relationship Id="rId4" Type="${RelType.image}" '
    'Target="media/image1.png"/>'
    '<Relationship Id="rId5" Type="${RelType.settings}" '
    'Target="settings.xml"/>'
    '${relationships ?? numberingRelationship('numbering.xml')}'
    '</Relationships>',
  ),
  'word/media/image1.png': <int>[0x89, 0x50, 0x4E, 0x47, 0, 1, 2, 3],
  'word/settings.xml': utf8.encode(
    '<w:settings xmlns:w="${Ns.w}"><w:zoom w:percent="100"/></w:settings>',
  ),
  if (numbering != null) 'word/numbering.xml': utf8.encode(numbering),
  if (numbering != null && pictureTarget != null)
    'word/_rels/numbering.xml.rels': utf8.encode(
      '<Relationships xmlns="$packageRelsNs">'
      '<Relationship Id="rId1" Type="${RelType.image}" '
      'Target="$pictureTarget"/></Relationships>',
    ),
  if (numbering != null && pictureTarget == 'media/image2.png')
    'word/media/image2.png': <int>[0x89, 0x50, 0x4E, 0x47, 9, 9],
});
