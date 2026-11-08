// Tests reading hyperlinks: a `w:hyperlink` child of a paragraph reads as a
// typed inline whose url is the external target of its relationship (in the
// main part or in a story part, whose relationships stay unread), whose
// inlines are read as a paragraph's (fields grouped inside it alone), whose
// runs edit, report and undo as the paragraph's do, and which is written as
// read. They build documents in memory, so they run on the web as well;
// `owner_files_test.dart` reads the owner's `long.docx`.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart'
    show changeLogOf, editsOf;
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../support/read_xlsx.dart';
import '../support/docx_builder.dart';
import '../support/word_document.dart';

const String _decls = 'xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}"';

String _main(String body) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document $_decls><w:body>$body</w:body></w:document>';

/// A relationship of a relationships part.
String _rel(
  String id,
  String target, {
  String type = RelType.hyperlink,
  bool external = true,
}) =>
    '<Relationship Id="$id" Type="$type" Target="$target"'
    '${external ? ' TargetMode="External"' : ''}/>';

/// A package whose body holds [body], whose main part has the relationships
/// [rels], and which has [parts] (a ZIP entry name and its text), a footer
/// part typed as Word types it.
Uint8List _docx(
  String body, {
  String rels = '',
  Map<String, String> parts = const <String, String>{},
}) => buildDocx(
  document: _main(body),
  extra: <String, List<int>>{
    '[Content_Types].xml': utf8.encode(
      '<Types xmlns="$contentTypesNs">'
      '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
      '<Override PartName="/word/document.xml" '
      'ContentType="${ContentType.wmlDocument}"/>'
      '<Override PartName="/word/footer1.xml" '
      'ContentType="${ContentType.wmlFooter}"/></Types>',
    ),
    'word/_rels/document.xml.rels': utf8.encode(
      '<Relationships xmlns="$packageRelsNs">$rels</Relationships>',
    ),
    for (final MapEntry<String, String> e in parts.entries)
      e.key: utf8.encode(e.value),
  },
);

String _r(String text) => '<w:r><w:t>$text</w:t></w:r>';

const String _begin = '<w:r><w:fldChar w:fldCharType="begin"/></w:r>';
const String _separate = '<w:r><w:fldChar w:fldCharType="separate"/></w:r>';
const String _end = '<w:r><w:fldChar w:fldCharType="end"/></w:r>';

String _instr(String text) =>
    '<w:r><w:instrText xml:space="preserve">$text</w:instrText></w:r>';

String _page(String result) =>
    '$_begin${_instr(' PAGE ')}$_separate${_r(result)}$_end';

DocxParagraph _first(DocxDocument doc) =>
    doc.body.blocks.whereType<DocxParagraph>().first;

String _savedPart(DocxDocument doc, String name) =>
    utf8.decode(readXlsxBytes(Uint8List.fromList(doc.save().bytes))[name]!);

void main() {
  group('reading', () {
    test('the Word-like sample reads its external link', () {
      final Uint8List input = richWordDocx();
      final DocxDocument doc = DocxDocument.open(input);
      final DocxParagraph p = doc.body.blocks
          .whereType<DocxParagraph>()
          .firstWhere(
            (DocxParagraph p) => p.inlines.any((i) => i is DocxHyperlink),
          );
      final DocxHyperlink link = p.inlines.whereType<DocxHyperlink>().single;
      expect(link.url, 'https://example.com/fiyat');
      expect(link.anchor, isNull);
      expect(link.tooltip, isNull);
      expect(link.text, 'site');
      expect(link.inlines.single, isA<DocxRun>());
      expect((link.inlines.single as DocxRun).style, 'Hyperlink');
      expect(p.text, 'Eski tutar, bkz. site');
      expect(() => link.inlines.add(DocxRun()), throwsUnsupportedError);
      expect(comparePackages(input, doc.save().bytes), isEmpty);
    });

    test('an anchor link reads its anchor and tooltip, and no url', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '<w:p><w:hyperlink w:anchor="_Toc1" w:tooltip="Go" w:history="1">'
          '${_r('a')}<w:r><w:tab/></w:r></w:hyperlink></w:p>',
        ),
      );
      final DocxHyperlink link = _first(doc).inlines.single as DocxHyperlink;
      expect(link.anchor, '_Toc1');
      expect(link.tooltip, 'Go');
      expect(link.url, isNull);
      expect(link.text, 'a\t');
      expect(_first(doc).text, 'a\t');
    });

    test('an r:id naming nothing, an internal or another type reads null', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '<w:p><w:hyperlink r:id="rId9">${_r('a')}</w:hyperlink>'
          '<w:hyperlink r:id="rId1">${_r('b')}</w:hyperlink>'
          '<w:hyperlink r:id="rId2">${_r('c')}</w:hyperlink>'
          '<w:hyperlink r:id="rId3">${_r('d')}</w:hyperlink></w:p>',
          rels:
              '${_rel('rId1', 'media/x.png', external: false)}'
              '${_rel('rId2', 'https://x.test/', type: RelType.image)}'
              '${_rel('rId3', 'https://ok.test/')}',
        ),
      );
      final List<String?> urls = <String?>[
        for (final DocxHyperlink l in _first(
          doc,
        ).inlines.whereType<DocxHyperlink>())
          l.url,
      ];
      expect(urls, <String?>[null, null, null, 'https://ok.test/']);
    });

    test('a link in a footer reads its url; the footer rels stay as read', () {
      const String footerRels =
          '<?xml version="1.0"?>\r\n<Relationships   '
          'xmlns="$packageRelsNs">\r\n'
          '<Relationship Id="rId1" Type="${RelType.hyperlink}" '
          'Target="https://foot.test/" TargetMode="External" />\r\n'
          '</Relationships>';
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '<w:p>${_r('Body')}</w:p><w:sectPr>'
          '<w:footerReference w:type="default" r:id="rId1"/></w:sectPr>',
          rels: _rel(
            'rId1',
            'footer1.xml',
            type: RelType.footer,
            external: false,
          ),
          parts: <String, String>{
            'word/footer1.xml':
                '<w:ftr $_decls><w:p>'
                '<w:hyperlink r:id="rId1">${_r('Foot')}</w:hyperlink>'
                '</w:p></w:ftr>',
            'word/_rels/footer1.xml.rels': footerRels,
          },
        ),
      );
      final DocxParagraph p =
          doc.sections.single.footer.blocks.single as DocxParagraph;
      final DocxHyperlink link = p.inlines.single as DocxHyperlink;
      expect(link.url, 'https://foot.test/');
      (link.inlines.single as DocxRun).text = 'Changed';
      expect(_savedPart(doc, 'word/_rels/footer1.xml.rels'), footerRels);
      expect(_savedPart(doc, 'word/footer1.xml'), contains('Changed'));
    });

    test('a damaged relationships part of a story reads url null', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '<w:p>${_r('Body')}</w:p><w:sectPr>'
          '<w:footerReference w:type="default" r:id="rId1"/></w:sectPr>',
          rels: _rel(
            'rId1',
            'footer1.xml',
            type: RelType.footer,
            external: false,
          ),
          parts: <String, String>{
            'word/footer1.xml':
                '<w:ftr $_decls><w:p>'
                '<w:hyperlink r:id="rId1">${_r('Foot')}</w:hyperlink>'
                '</w:p></w:ftr>',
            'word/_rels/footer1.xml.rels': '<Relationships',
          },
        ),
      );
      final DocxParagraph p =
          doc.sections.single.footer.blocks.single as DocxParagraph;
      final DocxHyperlink link = p.inlines.single as DocxHyperlink;
      expect(link.url, isNull);
      expect(link.text, 'Foot');
    });

    test('bookmarks in a link are typed; a nested link stays opaque', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '<w:p><w:hyperlink w:anchor="a">'
          '<w:bookmarkStart w:id="1" w:name="B"/>${_r('x')}'
          '<w:bookmarkEnd w:id="1"/>'
          '<w:hyperlink w:anchor="b">${_r('y')}</w:hyperlink>'
          '</w:hyperlink>'
          '<w:ins w:id="2" w:author="A"><w:hyperlink w:anchor="c">${_r('z')}'
          '</w:hyperlink></w:ins></w:p>',
        ),
      );
      final DocxParagraph p = _first(doc);
      expect(p.inlines.map((DocxInline i) => i.runtimeType), <Type>[
        DocxHyperlink,
        DocxOpaqueInline,
      ]);
      final DocxHyperlink link = p.inlines.first as DocxHyperlink;
      expect(link.inlines.map((DocxInline i) => i.runtimeType), <Type>[
        DocxBookmarkStart,
        DocxRun,
        DocxBookmarkEnd,
        DocxOpaqueInline,
      ]);
      expect(link.text, 'xy');
      expect(p.text, 'xyz');
    });
  });

  group('fields', () {
    test('a PAGE field inside a link is a DocxField of its inlines', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '<w:p><w:hyperlink w:anchor="a">${_page('4')}</w:hyperlink></w:p>',
        ),
      );
      final DocxHyperlink link = _first(doc).inlines.single as DocxHyperlink;
      final DocxField field = link.inlines.single as DocxField;
      expect(field.name, 'PAGE');
      expect(link.text, '4');
    });

    test('a field whose begin is outside and end inside stays runs', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '<w:p>$_begin${_instr(' PAGE ')}$_separate${_r('1')}'
          '<w:hyperlink w:anchor="a">${_r('2')}$_end</w:hyperlink></w:p>',
        ),
      );
      final DocxParagraph p = _first(doc);
      expect(p.inlines.whereType<DocxField>(), isEmpty);
      final DocxHyperlink link = p.inlines.last as DocxHyperlink;
      expect(link.inlines.whereType<DocxField>(), isEmpty);
      expect(link.inlines, hasLength(2));
    });

    test('a link in the result of a field is one inline of the result', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '<w:p>$_begin${_instr(' TOC ')}$_separate'
          '<w:hyperlink w:anchor="a">${_page('4')}</w:hyperlink>$_end</w:p>',
        ),
      );
      final DocxField toc = _first(doc).inlines.single as DocxField;
      final DocxHyperlink link = toc.result.single as DocxHyperlink;
      expect(link.inlines.single, isA<DocxField>());
      expect(toc.text, '4');
    });
  });

  group('editing the runs of a link', () {
    final String body =
        '<w:p>${_r('a')}<w:hyperlink r:id="rId1" w:history="1">'
        '<w:r><w:rPr><w:rStyle w:val="Hyperlink"/></w:rPr><w:t>site</w:t>'
        '</w:r></w:hyperlink>${_r('c')}</w:p>';

    DocxDocument open() =>
        DocxDocument.open(_docx(body, rels: _rel('rId1', 'https://x.test/')));

    test('setting the text of a run saves only that run changed', () {
      final DocxDocument doc = open();
      final DocxHyperlink link = _first(doc).inlines[1] as DocxHyperlink;
      final ChangeSet set = editsOf(doc).transaction(() {
        (link.inlines.single as DocxRun).text = 'page';
      });
      expect(link.text, 'page');
      expect(
        _savedPart(doc, 'word/document.xml'),
        _main(body.replaceFirst('site', 'page')),
      );
      changeLogOf(doc).revertSet(set);
      expect(link.text, 'site');
      expect(_savedPart(doc, 'word/document.xml'), _main(body));
    });

    test('a run in a link counts in the run locations of its paragraph', () {
      final DocxDocument doc = open();
      final DocxHyperlink link = _first(doc).inlines[1] as DocxHyperlink;
      (link.inlines.single as DocxRun).text = 'a\u0001b';
      (_first(doc).inlines[2] as DocxRun).text = 'c\u0001';
      final DocxWarning w = doc.save().warnings.single;
      expect(w.code, DocxWarningCode.invalidCharactersRemoved);
      expect(w.locations, <String>['body/p[0]/r[1]', 'body/p[0]/r[2]']);
    });

    test('a run of a link goes with it, and stays in it', () {
      final DocxDocument doc = open();
      final DocxParagraph p = _first(doc);
      final DocxHyperlink link = p.inlines[1] as DocxHyperlink;
      final DocxRun run = link.inlines.single as DocxRun;
      expect(() => p.insertInline(0, run), throwsStateError);
      p.removeInlineAt(1);
      expect(() => p.insertInline(0, run), throwsStateError);
      p.insertInline(0, link);
      expect(p.inlines.first, same(link));
      run.text = 'moved';
      expect(_savedPart(doc, 'word/document.xml'), contains('moved'));
    });
  });
}
