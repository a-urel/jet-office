/// Test helper: hand-made documents as Word for Mac writes them, for the
/// template fill's tests (decision 0024). Nothing touches the file system, so
/// it runs in Chrome.
///
/// The helpers named `wordSplitTag`, `tagInHyperlink`, `tagAroundTab`,
/// `tagInFieldResult`, `tagInInsertion` and `tagInInlineSdt` return inline
/// XML for [templateParagraph]; [templateDocument] and [templateWithHeader]
/// build the package. [textBoxDrawing] returns run content: an anchored
/// drawing whose text box the model keeps opaque.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/src/opc/ooxml.dart';

import 'docx_builder.dart';

const String _rsid = 'w:rsidR="00A1B2C3"';

String _run(String text, {bool bold = false, String? rsid}) =>
    '<w:r ${rsid ?? _rsid}>${bold ? '<w:rPr><w:b/></w:rPr>' : ''}'
    '<w:t xml:space="preserve">$text</w:t></w:r>';

/// [inner] (runs and other inlines) in one `w:p`.
String templateParagraph(String inner) => '<w:p>$inner</w:p>';

/// The inline XML of [tag] (such as `{{musteri.unvan}}`) split as Word for Mac
/// splits a typed tag: the braces and each word and dot in a run of their own
/// with `w:rsidR`, a `w:proofErr` of `spellStart` before the first word and
/// `spellEnd` after the last, and a `w:bookmarkStart` and `w:bookmarkEnd` pair
/// around the first dot. With [boldFirstBrace] the first run is bold.
///
/// [tag] must start with `{{` and end with `}}`.
String wordSplitTag(String tag, {bool boldFirstBrace = false}) {
  assert(tag.startsWith('{{') && tag.endsWith('}}'));
  final String body = tag.substring(2, tag.length - 2);
  final List<String> tokens = RegExp(
    r'[^.]+|\.',
  ).allMatches(body).map((Match m) => m[0]!).toList();
  final int firstWord = tokens.indexWhere((String t) => t != '.');
  final int lastWord = tokens.lastIndexWhere((String t) => t != '.');
  final int firstDot = tokens.indexOf('.');
  final StringBuffer out = StringBuffer(
    _run('{{', bold: boldFirstBrace, rsid: 'w:rsidR="00B7C8D9"'),
  );
  for (int i = 0; i < tokens.length; i++) {
    if (i == firstWord) out.write('<w:proofErr w:type="spellStart"/>');
    if (i == firstDot) {
      out.write('<w:bookmarkStart w:id="7" w:name="_GoBack"/>');
    }
    out.write(_run(tokens[i]));
    if (i == firstDot) out.write('<w:bookmarkEnd w:id="7"/>');
    if (i == lastWord) out.write('<w:proofErr w:type="spellEnd"/>');
  }
  out.write(_run('}}', rsid: 'w:rsidR="00B7C8D9"'));
  return out.toString();
}

/// A hyperlink to the bookmark `x` with one run for each of [parts].
String hyperlinkOf(List<String> parts) =>
    '<w:hyperlink w:anchor="x" w:history="1">'
    '${parts.map((String p) => _run(p)).join()}</w:hyperlink>';

/// [before] in a run, a hyperlink of [inside] runs and [after] in a run, so a
/// tag over the hyperlink's edge crosses a segment boundary.
String tagInHyperlink(String before, List<String> inside, String after) =>
    '${_run(before)}${hyperlinkOf(inside)}${_run(after)}';

/// `{{a`, a tab and `b}}`, each in a run of its own: a tag around a `w:tab`.
String tagAroundTab() =>
    '${_run('{{a')}<w:r $_rsid><w:tab/></w:r>${_run('b}}')}';

/// A complex field of [instruction] whose cached result is [result], as Word
/// writes it, in runs.
String tagInFieldResult(String result, {String instruction = ' PAGE '}) =>
    '<w:r $_rsid><w:fldChar w:fldCharType="begin"/></w:r>'
    '<w:r $_rsid><w:instrText xml:space="preserve">$instruction</w:instrText>'
    '</w:r><w:r $_rsid><w:fldChar w:fldCharType="separate"/></w:r>'
    '${_run(result)}<w:r $_rsid><w:fldChar w:fldCharType="end"/></w:r>';

/// [text] as a tracked insertion, `w:ins`.
String tagInInsertion(String text) =>
    '<w:ins w:id="1" w:author="Ada" w:date="2026-01-01T00:00:00Z">'
    '${_run(text)}</w:ins>';

/// [text] in an inline content control, `w:sdt`.
String tagInInlineSdt(String text) =>
    '<w:sdt><w:sdtPr><w:alias w:val="Field"/></w:sdtPr><w:sdtContent>'
    '${_run(text)}</w:sdtContent></w:sdt>';

String _documentXml(String body, String sectPr) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
    '<w:document xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}">'
    '<w:body>$body$sectPr</w:body></w:document>';

/// A DOCX whose body is [paragraphs], each wrapped by [templateParagraph].
Uint8List templateDocument(List<String> paragraphs) => buildDocx(
  document: _documentXml(paragraphs.map(templateParagraph).join(), ''),
);

/// A DOCX with a header part whose one paragraph is [headerInline] (by default
/// `{{firma.ad}}` split by [wordSplitTag]) and a body of [bodyInline]. The
/// document's only section references the header as `default`, with its
/// relationship and content type, so `sections.first.header` reads it.
Uint8List templateWithHeader({
  String? headerInline,
  String bodyInline = '',
}) => buildDocx(
  document: _documentXml(
    templateParagraph(bodyInline),
    '<w:sectPr><w:headerReference w:type="default" r:id="rId11"/>'
    '<w:pgSz w:w="11906" w:h="16838"/></w:sectPr>',
  ),
  extra: <String, List<int>>{
    '[Content_Types].xml': utf8.encode(
      '<Types xmlns="$contentTypesNs">'
      '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
      '<Override PartName="/word/document.xml" '
      'ContentType="${ContentType.wmlDocument}"/>'
      '<Override PartName="/word/header1.xml" '
      'ContentType="${ContentType.wmlHeader}"/>'
      '</Types>',
    ),
    'word/_rels/document.xml.rels': utf8.encode(
      '<Relationships xmlns="$packageRelsNs">'
      '<Relationship Id="rId11" Type="${RelType.header}" '
      'Target="header1.xml"/></Relationships>',
    ),
    'word/header1.xml': utf8.encode(
      '<w:hdr xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}">'
      '${templateParagraph(headerInline ?? wordSplitTag('{{firma.ad}}'))}'
      '</w:hdr>',
    ),
  },
);

const String _wps =
    'http://schemas.microsoft.com/office/word/2010/wordprocessingShape';
const String _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';

/// An anchored `w:drawing` whose text box holds [paragraphs], each a `w:p`
/// of one run.
String textBoxDrawing(List<String> paragraphs) =>
    '<w:drawing><wp:anchor xmlns:wp="${Ns.wp}" distT="0" distB="0" '
    'distL="0" distR="0" simplePos="0" relativeHeight="1" behindDoc="0" '
    'locked="0" layoutInCell="1" allowOverlap="1">'
    '<wp:simplePos x="0" y="0"/>'
    '<wp:positionH relativeFrom="column"><wp:posOffset>0</wp:posOffset>'
    '</wp:positionH><wp:positionV relativeFrom="paragraph">'
    '<wp:posOffset>0</wp:posOffset></wp:positionV>'
    '<wp:extent cx="914400" cy="457200"/><wp:wrapNone/>'
    '<wp:docPr id="1" name="Text Box 1"/>'
    '<a:graphic xmlns:a="$_a"><a:graphicData '
    'uri="http://schemas.microsoft.com/office/word/2010/wordprocessingShape">'
    '<wps:wsp xmlns:wps="$_wps"><wps:cNvSpPr txBox="1"/><wps:spPr/>'
    '<wps:txbx><w:txbxContent>'
    '${paragraphs.map((String p) => '<w:p><w:r><w:t>$p</w:t></w:r></w:p>').join()}'
    '</w:txbxContent></wps:txbx><wps:bodyPr/></wps:wsp>'
    '</a:graphicData></a:graphic></wp:anchor></w:drawing>';
