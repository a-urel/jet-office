/// Test helper: a DOCX written by hand with every section child, headers
/// and footers of every type, broken references and broken fields, as the
/// fuzzer's corpus entry `sections_by_hand`.
///
/// Not ported from Quds. The references stand in the order Word writes
/// them; the mutations then take the file out of its schema.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/src/opc/ooxml.dart';

import 'docx_builder.dart';
import 'word_document.dart';

/// A paragraph holding [text].
String _p(String text) => '<w:p><w:r><w:t>$text</w:t></w:r></w:p>';

/// The parts of one field: begin, instruction, separate, result, end.
String _field(String instruction, String result) =>
    '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
    '<w:r><w:instrText xml:space="preserve"> $instruction </w:instrText></w:r>'
    '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
    '<w:r><w:t>$result</w:t></w:r>'
    '<w:r><w:fldChar w:fldCharType="end"/></w:r>';

/// The section properties of the first section: every child the model types
/// and some it keeps, with all six story references.
const String _firstSection =
    '<w:sectPr>'
    '<w:headerReference w:type="default" r:id="rId11"/>'
    '<w:headerReference w:type="first" r:id="rId12"/>'
    '<w:headerReference w:type="even" r:id="rId13"/>'
    '<w:footerReference w:type="default" r:id="rId21"/>'
    '<w:footerReference w:type="first" r:id="rId22"/>'
    '<w:footerReference w:type="even" r:id="rId23"/>'
    '<w:footnotePr><w:numFmt w:val="lowerRoman"/></w:footnotePr>'
    '<w:endnotePr><w:numFmt w:val="decimal"/></w:endnotePr>'
    '<w:type w:val="nextPage"/>'
    '<w:pgSz w:w="12240" w:h="15840" w:orient="landscape" w:code="1"/>'
    '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
    'w:header="720" w:footer="720" w:gutter="360"/>'
    '<w:paperSrc w:first="1" w:other="2"/>'
    '<w:pgBorders w:offsetFrom="page"><w:top w:val="single" w:sz="4" '
    'w:space="24" w:color="auto"/></w:pgBorders>'
    '<w:lnNumType w:countBy="5" w:start="1" w:distance="360" '
    'w:restart="newPage"/>'
    '<w:pgNumType w:fmt="upperRoman" w:start="3" w:chapStyle="1" '
    'w:chapSep="colon"/>'
    '<w:cols w:num="2" w:space="720" w:sep="1" w:equalWidth="0">'
    '<w:col w:w="3000" w:space="720"/><w:col w:w="5000"/></w:cols>'
    '<w:formProt w:val="false"/><w:vAlign w:val="center"/>'
    '<w:noEndnote/><w:titlePg/><w:textDirection w:val="lrTb"/>'
    '<w:bidi/><w:rtlGutter/><w:docGrid w:type="lines" w:linePitch="360"/>'
    '</w:sectPr>';

/// The second section: references that do not work, a missing `r:id`, an
/// external target, a relationship of the wrong type, a relationship that
/// names no part, and one type twice.
const String _brokenSection =
    '<w:sectPr>'
    '<w:headerReference w:type="default"/>'
    '<w:headerReference w:type="first" r:id="rId31"/>'
    '<w:headerReference w:type="even" r:id="rId32"/>'
    '<w:footerReference w:type="default" r:id="rId33"/>'
    '<w:footerReference w:type="first" r:id="rId999"/>'
    '<w:footerReference w:type="even" r:id="rId21"/>'
    '<w:footerReference w:type="even" r:id="rId22"/>'
    '<w:headerReference w:type="other" r:id="rId11"/>'
    '<w:pgSz w:w="abc" w:h="-"/><w:pgMar w:top="1in"/>'
    '<w:cols w:num="99999999999999999999"/>'
    '<w:pgNumType w:fmt="nonsense" w:start="x"/>'
    '<w:type w:val="sideways"/><w:titlePg w:val="maybe"/>'
    '</w:sectPr>';

/// The body of [sectionsByHandDocx]: the first section ends in a paragraph,
/// the second in another, and fields of every kind, well formed and broken,
/// stand between them.
final String _body =
    '${_p('One')}'
    '<w:p><w:pPr>$_firstSection</w:pPr><w:r><w:t>End of one</w:t></w:r></w:p>'
    // A section break in a paragraph with other properties, and a simple
    // field, a complex field with a nested one, a begin with no end.
    '<w:p><w:r><w:t>Two </w:t></w:r>'
    '<w:fldSimple w:instr=" PAGE "><w:r><w:t>1</w:t></w:r></w:fldSimple>'
    '${_field('IF { PAGE } = 1 "a" "b"', 'a')}'
    '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
    '<w:r><w:instrText> NUMPAGES </w:instrText></w:r>'
    '<w:r><w:t>never ended</w:t></w:r></w:p>'
    // An end alone, a separate alone, two marks in one run, a mark and its
    // instruction in one run, a result with a table and a break.
    '<w:p><w:r><w:fldChar w:fldCharType="end"/></w:r>'
    '<w:r><w:fldChar w:fldCharType="separate"/><w:t>x</w:t></w:r>'
    '<w:r><w:fldChar w:fldCharType="begin"/>'
    '<w:fldChar w:fldCharType="end"/></w:r>'
    '<w:r><w:fldChar w:fldCharType="begin"/>'
    '<w:instrText> DATE \\@ "d MMMM yyyy" </w:instrText>'
    '<w:fldChar w:fldCharType="separate"/><w:t>1 May 2026</w:t>'
    '<w:fldChar w:fldCharType="end"/></w:r>'
    '<w:r><w:fldChar w:fldCharType="begin" w:fldCharType2="x"/></w:r>'
    '<w:r><w:fldChar/></w:r>'
    '<w:r><w:fldChar w:fldCharType="sideways"/></w:r></w:p>'
    '<w:p><w:pPr>$_brokenSection</w:pPr><w:r><w:t>End of two</w:t></w:r></w:p>'
    '${_p('Three')}';

/// The main part: [_body] and the final section, which names the footers
/// and a header that no relationship has.
final String sectionsByHandDocumentXml = wordDocumentXml.replaceFirst(
  RegExp(r'<w:body>[\s\S]*</w:body>'),
  '<w:body>$_body'
  '<w:sectPr><w:headerReference w:type="default" r:id="rId11"/>'
  '<w:footerReference w:type="default" r:id="rId21"/>'
  '<w:footerReference w:type="first" r:id="rId24"/>'
  '<w:pgSz w:w="11906" w:h="16838"/><w:titlePg/></w:sectPr></w:body>',
);

/// A header or footer part holding [content].
String _story(String root, String content) =>
    '<w:$root xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}">$content</w:$root>';

/// The relationships of the main part: the settings, six stories, an external header, an
/// image where a footer is named and a header that names a missing part.
const String sectionsByHandRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    '<Relationships xmlns="$packageRelsNs">'
    '<Relationship Id="rId4" Type="${RelType.image}" '
    'Target="media/image1.png"/>'
    '<Relationship Id="rId5" Type="${RelType.settings}" '
    'Target="settings.xml"/>'
    '<Relationship Id="rId11" Type="${RelType.header}" Target="header1.xml"/>'
    '<Relationship Id="rId12" Type="${RelType.header}" Target="header2.xml"/>'
    '<Relationship Id="rId13" Type="${RelType.header}" Target="header3.xml"/>'
    '<Relationship Id="rId21" Type="${RelType.footer}" Target="footer1.xml"/>'
    '<Relationship Id="rId22" Type="${RelType.footer}" Target="footer2.xml"/>'
    '<Relationship Id="rId23" Type="${RelType.footer}" Target="footer3.xml"/>'
    '<Relationship Id="rId24" Type="${RelType.footer}" '
    'Target="footer-missing.xml"/>'
    '<Relationship Id="rId31" Type="${RelType.header}" '
    'Target="https://example.com/header.xml" TargetMode="External"/>'
    '<Relationship Id="rId32" Type="${RelType.image}" '
    'Target="media/image1.png"/>'
    '<Relationship Id="rId33" Type="${RelType.header}" Target="footer1.xml"/>'
    '</Relationships>';

/// A DOCX holding [sectionsByHandDocumentXml], six story parts (fields in
/// the footers, a table and a paragraph with a break in a header), settings
/// with odd and even headers, every entry stored.
Uint8List sectionsByHandDocx() => buildZip(<String, List<int>>{
  '[Content_Types].xml': utf8.encode(
    '<Types xmlns="$contentTypesNs">'
    '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Default Extension="png" ContentType="image/png"/>'
    '<Override PartName="/word/document.xml" '
    'ContentType="${ContentType.wmlDocument}"/>'
    '<Override PartName="/word/settings.xml" '
    'ContentType="${ContentType.wmlSettings}"/>'
    '<Override PartName="/word/header1.xml" '
    'ContentType="${ContentType.wmlHeader}"/>'
    '<Override PartName="/word/header2.xml" '
    'ContentType="${ContentType.wmlHeader}"/>'
    '<Override PartName="/word/header3.xml" '
    'ContentType="${ContentType.wmlHeader}"/>'
    '<Override PartName="/word/footer1.xml" '
    'ContentType="${ContentType.wmlFooter}"/>'
    '<Override PartName="/word/footer2.xml" '
    'ContentType="${ContentType.wmlFooter}"/>'
    '<Override PartName="/word/footer3.xml" '
    'ContentType="${ContentType.wmlFooter}"/>'
    '</Types>',
  ),
  '_rels/.rels': utf8.encode(rootRels('word/document.xml')),
  'word/document.xml': utf8.encode(sectionsByHandDocumentXml),
  'word/_rels/document.xml.rels': utf8.encode(sectionsByHandRels),
  'word/media/image1.png': <int>[0x89, 0x50, 0x4E, 0x47, 0, 1, 2, 3, 255],
  'word/settings.xml': utf8.encode(
    '<w:settings xmlns:w="${Ns.w}"><w:evenAndOddHeaders/></w:settings>',
  ),
  'word/header1.xml': utf8.encode(_story('hdr', _p('Header'))),
  'word/header2.xml': utf8.encode(
    _story(
      'hdr',
      '${_p('First header')}<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w="2000"/>'
          '</w:tblGrid><w:tr><w:tc>${_p('Cell')}</w:tc></w:tr></w:tbl><w:p/>',
    ),
  ),
  'word/header3.xml': utf8.encode(
    _story('hdr', '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'),
  ),
  'word/footer1.xml': utf8.encode(
    _story(
      'ftr',
      '<w:p><w:r><w:t>Page </w:t></w:r>${_field('PAGE', '1')}'
          '<w:r><w:t> of </w:t></w:r>${_field('NUMPAGES', '2')}</w:p>',
    ),
  ),
  'word/footer2.xml': utf8.encode(
    _story(
      'ftr',
      '<w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r>'
          '<w:r><w:instrText> PAGE </w:instrText></w:r></w:p>',
    ),
  ),
  'word/footer3.xml': utf8.encode(_story('ftr', '')),
}, store: true);
