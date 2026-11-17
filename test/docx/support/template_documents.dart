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

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/ooxml.dart';

import '../../fixtures/m4_fixtures.dart' show png4x2;
import '../../support/read_xlsx.dart';
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

/// A DOCX whose body is [body] (block XML: paragraphs and tables, ending in
/// a paragraph), with a header part of [header] and a footer part of [footer]
/// (block XML too) that its only section references as `default`, A4 with
/// Word's margins, columns and document grid, with their relationships and
/// content types.
///
/// The other parts are those of `DocxDocument()`, the blank document (styles,
/// settings, web settings, font table and theme), so LibreOffice reads the
/// document as it reads the D fixtures: without the styles' defaults, its
/// re-save writes `w:charSpace="4294963199"`, which the Open XML SDK refuses.
Uint8List templateWithStories({
  required String body,
  required String header,
  required String footer,
}) => templateDocx(body: body, header: header, footer: footer);

/// A DOCX as [templateWithStories] builds it, its header and footer each
/// left out when `null`, with a comments part of [comments] (`w:comment`
/// elements) when given, and with `word/media/image1.png` (a 4 by 2 PNG,
/// relationship `rId14`, for [inlinePictureRun]) when [picture] is true.
Uint8List templateDocx({
  required String body,
  String? header,
  String? footer,
  String? comments,
  bool picture = false,
}) {
  final Map<String, Uint8List> blank = readXlsxBytes(
    DocxDocument().save().bytes,
  );
  String text(String name) => utf8.decode(blank[name]!);
  final StringBuffer types = StringBuffer();
  final StringBuffer rels = StringBuffer();
  final StringBuffer refs = StringBuffer();
  if (picture) {
    types.write('<Default Extension="png" ContentType="${ContentType.png}"/>');
    rels.write(
      '<Relationship Id="rId14" Type="${RelType.image}" '
      'Target="media/image1.png"/>',
    );
  }
  if (header != null) {
    types.write(
      '<Override PartName="/word/header1.xml" '
      'ContentType="${ContentType.wmlHeader}"/>',
    );
    rels.write(
      '<Relationship Id="rId11" Type="${RelType.header}" '
      'Target="header1.xml"/>',
    );
    refs.write('<w:headerReference w:type="default" r:id="rId11"/>');
  }
  if (footer != null) {
    types.write(
      '<Override PartName="/word/footer1.xml" '
      'ContentType="${ContentType.wmlFooter}"/>',
    );
    rels.write(
      '<Relationship Id="rId12" Type="${RelType.footer}" '
      'Target="footer1.xml"/>',
    );
    refs.write('<w:footerReference w:type="default" r:id="rId12"/>');
  }
  if (comments != null) {
    types.write(
      '<Override PartName="/word/comments.xml" '
      'ContentType="${ContentType.wmlComments}"/>',
    );
    rels.write(
      '<Relationship Id="rId13" Type="${RelType.comments}" '
      'Target="comments.xml"/>',
    );
  }
  const String declaration =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n';
  return buildZip(<String, List<int>>{
    ...blank,
    '[Content_Types].xml': utf8.encode(
      text('[Content_Types].xml').replaceFirst('</Types>', '$types</Types>'),
    ),
    'word/_rels/document.xml.rels': utf8.encode(
      text(
        'word/_rels/document.xml.rels',
      ).replaceFirst('</Relationships>', '$rels</Relationships>'),
    ),
    'word/document.xml': utf8.encode(
      _documentXml(
        body,
        '<w:sectPr>$refs<w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1417" w:right="1417" w:bottom="1417" w:left="1417" '
        'w:header="708" w:footer="708" w:gutter="0"/><w:cols w:space="708"/>'
        '<w:docGrid w:linePitch="360"/></w:sectPr>',
      ),
    ),
    if (header != null)
      'word/header1.xml': utf8.encode(
        '$declaration<w:hdr xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}">$header'
        '</w:hdr>',
      ),
    if (footer != null)
      'word/footer1.xml': utf8.encode(
        '$declaration<w:ftr xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}">$footer'
        '</w:ftr>',
      ),
    if (comments != null)
      'word/comments.xml': utf8.encode(
        '$declaration<w:comments xmlns:w="${Ns.w}">$comments</w:comments>',
      ),
    if (picture) 'word/media/image1.png': png4x2,
  });
}

/// A run holding an inline picture of `word/media/image1.png` (relationship
/// `rId14` of [templateDocx] with `picture: true`), 4 by 2 points, whose
/// `wp:docPr` and `pic:cNvPr` have the id [id], as Word writes one; the
/// DrawingML namespaces are declared on its `w:drawing`.
String inlinePictureRun({int id = 7}) =>
    '<w:r $_rsid><w:drawing xmlns:wp="${Ns.wp}" xmlns:a="$_a" '
    'xmlns:pic="$_pic"><wp:inline distT="0" distB="0" distL="0" distR="0">'
    '<wp:extent cx="50800" cy="25400"/><wp:effectExtent l="0" t="0" r="0" '
    'b="0"/><wp:docPr id="$id" name="Picture $id"/><wp:cNvGraphicFramePr>'
    '<a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
    '<a:graphic><a:graphicData uri="$_pic"><pic:pic><pic:nvPicPr>'
    '<pic:cNvPr id="$id" name="image1.png"/><pic:cNvPicPr/></pic:nvPicPr>'
    '<pic:blipFill><a:blip r:embed="rId14"/><a:stretch><a:fillRect/>'
    '</a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/>'
    '<a:ext cx="50800" cy="25400"/></a:xfrm><a:prstGeom prst="rect">'
    '<a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData>'
    '</a:graphic></wp:inline></w:drawing></w:r>';

/// [text] as a tracked insertion of the revision id [id], `w:ins`.
String insertion(String text, {required int id}) =>
    '<w:ins w:id="$id" w:author="Ada" w:date="2026-01-01T00:00:00Z">'
    '${_run(text)}</w:ins>';

/// [inner] (inline XML) inside the bookmark [name] of the id [id].
String bookmarkAround(String inner, {required int id, required String name}) =>
    '<w:bookmarkStart w:id="$id" w:name="$name"/>$inner'
    '<w:bookmarkEnd w:id="$id"/>';

/// [text] in an inline content control of the id [id], `w:sdt`.
String inlineSdt(String text, {required int id}) =>
    '<w:sdt><w:sdtPr><w:alias w:val="Kontrol"/><w:id w:val="$id"/>'
    '</w:sdtPr><w:sdtContent>${_run(text)}</w:sdtContent></w:sdt>';

/// The `w:comment` [id] of a comments part, by Ada, holding [text].
String commentOf(int id, String text) =>
    '<w:comment w:id="$id" w:author="Ada" w:date="2026-01-01T00:00:00Z" '
    'w:initials="A"><w:p><w:r><w:t>$text</w:t></w:r></w:p></w:comment>';

/// [inner] (inline XML) inside the range of comment [id], then the run of
/// its reference.
String commentAround(String inner, {required int id}) =>
    '<w:commentRangeStart w:id="$id"/>$inner<w:commentRangeEnd w:id="$id"/>'
    '<w:r $_rsid><w:commentReference w:id="$id"/></w:r>';

/// A complex field of [instruction] whose cached result is [result], as Word
/// writes a merge field (`«Ad»`): begin, instruction, separate, result and end,
/// each in a run of its own with `w:rsidR`.
String complexMergeField(String instruction, String result) =>
    tagInFieldResult(result, instruction: instruction);

/// A `w:fldSimple` of [instruction] whose cached result is [result], as Word
/// writes a merge field inserted by an older version.
String simpleMergeField(String instruction, String result) =>
    '<w:fldSimple w:instr="$instruction">${_run(result)}</w:fldSimple>';

/// [text] in a run of its own, with Word's `w:rsidR`; [rPr] is the content of
/// its `w:rPr` (such as `<w:color w:val="C00000"/>`), none when empty.
String templateRun(String text, {String rPr = ''}) =>
    '<w:r $_rsid>${rPr.isEmpty ? '' : '<w:rPr>$rPr</w:rPr>'}'
    '<w:t xml:space="preserve">$text</w:t></w:r>';

const String _wps =
    'http://schemas.microsoft.com/office/word/2010/wordprocessingShape';
const String _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const String _pic = 'http://schemas.openxmlformats.org/drawingml/2006/picture';

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
