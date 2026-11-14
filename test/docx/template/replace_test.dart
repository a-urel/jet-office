// Tests replacing one template tag Word split over several runs: the run at
// the first brace keeps its formatting, the runs wholly inside go, the marks
// between them and every other inline stay. Every test saves, reopens the
// bytes and checks there. Documents are built in memory, so they run on the
// web as well.
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/template/paragraph_text.dart';
import 'package:jet_office/src/docx/template/replace.dart';
import 'package:test/test.dart';

import '../support/styles_documents.dart' show readDocxText;
import '../support/template_documents.dart';

/// Replaces `tag` in [paragraph] by [value], last occurrence first.
void _fill(DocxParagraph paragraph, String tag, String value) {
  final ParagraphText map = paragraphTextOf(paragraph);
  final int at = map.text.indexOf(tag);
  expect(at, isNonNegative, reason: 'tag $tag in ${map.text}');
  replaceSpan(map, at, at + tag.length, value);
}

DocxParagraph _first(DocxDocument doc) =>
    doc.body.blocks.whereType<DocxParagraph>().first;

DocxDocument _reopen(DocxDocument doc) => DocxDocument.open(doc.save().bytes);

List<DocxRun> _runs(DocxParagraph p) => p.inlines.whereType<DocxRun>().toList();

void main() {
  group('replaceSpan', () {
    test('split tag in a header keeps bold and marks', () {
      final DocxDocument doc = DocxDocument.open(
        templateWithHeader(
          headerInline: wordSplitTag('{{firma.ad}}', boldFirstBrace: true),
        ),
      );
      final DocxParagraph header = doc.sections.first.header.blocks
          .whereType<DocxParagraph>()
          .first;
      _fill(header, '{{firma.ad}}', 'Acme A.Ş.');
      final DocxDocument saved = _reopen(doc);
      final DocxParagraph p = saved.sections.first.header.blocks
          .whereType<DocxParagraph>()
          .first;
      expect(p.text, 'Acme A.Ş.');
      final int valueAt = p.inlines.indexWhere(
        (DocxInline i) => i is DocxRun && i.text == 'Acme A.Ş.',
      );
      expect((p.inlines[valueAt] as DocxRun).properties.bold, isTrue);
      final List<DocxInline> after = p.inlines.sublist(valueAt + 1);
      expect(
        after.whereType<DocxOpaqueInline>().map((DocxInline i) => i).length,
        2,
      );
      expect(after.whereType<DocxBookmarkStart>(), hasLength(1));
      expect(after.whereType<DocxBookmarkEnd>(), hasLength(1));
      expect(after.whereType<DocxRun>(), isEmpty);
      final String xml = readDocxText(doc.save().bytes)['word/header1.xml']!;
      expect(xml, contains('<w:proofErr w:type="spellStart"/>'));
      expect(xml, contains('<w:proofErr w:type="spellEnd"/>'));
      expect(xml, isNot(contains('{{')));
    });

    test('adjacent tags sharing a run', () {
      final DocxDocument doc = DocxDocument.open(
        templateDocument(<String>[
          '<w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">Sayın {{a</w:t></w:r>'
              '<w:r><w:rPr><w:i/></w:rPr><w:t xml:space="preserve">}} ve {{b</w:t></w:r>'
              '<w:r><w:rPr><w:u w:val="single"/></w:rPr><w:t xml:space="preserve">}}, hoş geldiniz</w:t></w:r>',
        ]),
      );
      final DocxParagraph p = _first(doc);
      final ParagraphText map = paragraphTextOf(p);
      // Positions are computed once; replace the last tag first.
      final int b = map.text.indexOf('{{b}}');
      final int a = map.text.indexOf('{{a}}');
      replaceSpan(map, b, b + 5, 'Y');
      replaceSpan(map, a, a + 5, 'X');
      final DocxParagraph saved = _first(_reopen(doc));
      expect(saved.text, 'Sayın X ve Y, hoş geldiniz');
      final List<DocxRun> runs = _runs(saved);
      expect(runs.map((DocxRun r) => r.text), <String>[
        'Sayın X',
        ' ve Y',
        ', hoş geldiniz',
      ]);
      expect(runs[0].properties.bold, isTrue);
      expect(runs[1].properties.italic, isTrue);
      expect(runs[2].properties.underline, isNotNull);
    });

    test('text around the tag in one run', () {
      final DocxDocument doc = DocxDocument.open(
        templateDocument(<String>['<w:r><w:tab/><w:t>x{{a}}y</w:t></w:r>']),
      );
      _fill(_first(doc), '{{a}}', 'V');
      final DocxRun run = _runs(_first(_reopen(doc))).single;
      expect(run.content.map((DocxRunContent c) => c.runtimeType), <Type>[
        DocxTab,
        DocxText,
      ]);
      expect((run.content[1] as DocxText).text, 'xVy');
    });

    test('value with line break and tab', () {
      final DocxDocument doc = DocxDocument.open(
        templateDocument(<String>[wordSplitTag('{{a.b}}')]),
      );
      _fill(_first(doc), '{{a.b}}', 'a\nb\tc');
      final DocxRun run = _runs(_first(_reopen(doc))).single;
      expect(run.content.map((DocxRunContent c) => c.runtimeType), <Type>[
        DocxText,
        DocxBreak,
        DocxText,
        DocxTab,
        DocxText,
      ]);
      expect(run.text, 'a\nb\tc');
    });

    test('forbidden characters removed', () {
      final DocxDocument doc = DocxDocument.open(
        templateDocument(<String>[wordSplitTag('{{a}}')]),
      );
      _fill(_first(doc), '{{a}}', 'a\u0001b');
      final DocxResult result = doc.save();
      expect(
        result.warnings.map((DocxWarning w) => w.code),
        contains(DocxWarningCode.invalidCharactersRemoved),
      );
      expect(_first(DocxDocument.open(result.bytes)).text, 'ab');
    });

    test('tag in a hyperlink', () {
      final DocxDocument doc = DocxDocument.open(
        templateDocument(<String>[
          hyperlinkOf(<String>['{{a', '}}']),
        ]),
      );
      _fill(_first(doc), '{{a}}', 'Z');
      final Uint8List bytes = doc.save().bytes;
      final DocxParagraph p = _first(DocxDocument.open(bytes));
      final DocxHyperlink link = p.inlines.single as DocxHyperlink;
      expect(link.inlines, hasLength(1));
      expect((link.inlines.single as DocxRun).text, 'Z');
      expect(
        readDocxText(bytes)['word/document.xml'],
        contains('w:anchor="x"'),
      );
    });

    test('a span that is not fillable throws', () {
      final DocxDocument doc = DocxDocument.open(
        templateDocument(<String>[
          tagInHyperlink('{{', <String>['a'], '}}'),
        ]),
      );
      final ParagraphText map = paragraphTextOf(_first(doc));
      expect(
        () => replaceSpan(map, 0, map.text.length, 'v'),
        throwsArgumentError,
      );
    });

    test('forbidden characters of two spans in one run are all counted', () {
      final DocxDocument doc = DocxDocument.open(
        templateDocument(<String>[
          '<w:r><w:t xml:space="preserve">{{a}} {{b}}</w:t></w:r>',
        ]),
      );
      final DocxParagraph p = _first(doc);
      final ParagraphText map = paragraphTextOf(p);
      replaceSpan(map, 6, 11, 'x\u0001');
      replaceSpan(map, 0, 5, 'y');
      final DocxResult result = doc.save();
      expect(_first(DocxDocument.open(result.bytes)).text, 'y x');
      final DocxWarning w = result.warnings.singleWhere(
        (DocxWarning w) => w.code == DocxWarningCode.invalidCharactersRemoved,
      );
      expect(w.count, 1);
    });

    test('forbidden characters in the later tag of adjacent runs', () {
      final DocxDocument doc = DocxDocument.open(
        templateDocument(<String>[
          '<w:r><w:t xml:space="preserve">{{a</w:t></w:r>'
              '<w:r><w:t xml:space="preserve">}} {{b</w:t></w:r>'
              '<w:r><w:t>}}</w:t></w:r>',
        ]),
      );
      final ParagraphText map = paragraphTextOf(_first(doc));
      replaceSpan(map, 6, 11, 'x\u0001\u0002');
      replaceSpan(map, 0, 5, 'y');
      final DocxResult result = doc.save();
      expect(_first(DocxDocument.open(result.bytes)).text, 'y x');
      final DocxWarning w = result.warnings.singleWhere(
        (DocxWarning w) => w.code == DocxWarningCode.invalidCharactersRemoved,
      );
      expect(w.count, 2);
    });

    test('every other inline untouched', () {
      const String picture =
          '<w:r w:rsidR="00112233"><w:rPr><w:noProof/></w:rPr><w:drawing>'
          '<wp:inline xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">'
          '<wp:extent cx="10" cy="10"/><wp:docPr id="1" name="P"/></wp:inline>'
          '</w:drawing></w:r>';
      const String field =
          '<w:fldSimple w:instr=" PAGE "><w:r><w:rPr><w:i/></w:rPr>'
          '<w:t>1</w:t></w:r></w:fldSimple>';
      const String comment =
          '<w:commentRangeStart w:id="3"/><w:r w:rsidR="00445566"><w:t>c</w:t>'
          '</w:r><w:commentRangeEnd w:id="3"/>';
      final DocxDocument unedited = DocxDocument.open(
        templateDocument(<String>[
          '$picture$field$comment${wordSplitTag('{{a.b}}', boldFirstBrace: true)}$picture',
        ]),
      );
      final DocxDocument doc = DocxDocument.open(
        templateDocument(<String>[
          '$picture$field$comment${wordSplitTag('{{a.b}}', boldFirstBrace: true)}$picture',
        ]),
      );
      // Touch the unedited model the same way, with no change, so both are
      // written from the model.
      _first(unedited).addRun('');
      final DocxParagraph p = _first(doc);
      _first(doc).addRun('');
      _fill(p, '{{a.b}}', 'V');
      final String original = readDocxText(
        unedited.save().bytes,
      )['word/document.xml']!;
      final String edited = readDocxText(
        doc.save().bytes,
      )['word/document.xml']!;
      final RegExp tagRuns = RegExp(
        r'<w:r [^>]*w:rsidR="00B7C8D9"[^>]*>.*?</w:r>|'
        r'<w:r [^>]*w:rsidR="00A1B2C3"[^>]*>.*?</w:r>',
      );
      // Everything but the tag's runs is equal; the value run takes the
      // first brace's place with its w:rPr (bold) and attributes.
      final String valueRun = RegExp(
        r'<w:r [^>]*w:rsidR="00B7C8D9"[^>]*>.*?</w:r>',
      ).firstMatch(edited)!.group(0)!;
      expect(valueRun, contains('<w:rPr><w:b/></w:rPr>'));
      expect(valueRun, contains('>V<'));
      expect(edited.replaceAll(tagRuns, ''), original.replaceAll(tagRuns, ''));
    });
  });
}
