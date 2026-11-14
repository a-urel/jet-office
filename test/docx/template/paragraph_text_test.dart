// Tests the searchable text of a paragraph: the mapping of each character to
// its run, the segments a tag may not cross and the regions. Pure Dart, so it
// runs on the web too.
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/template/paragraph_text.dart';
import 'package:test/test.dart';

import '../support/template_documents.dart';

ParagraphText _text(String inner) {
  final DocxDocument doc = DocxDocument.open(templateDocument(<String>[inner]));
  return paragraphTextOf(doc.body.blocks.whereType<DocxParagraph>().first);
}

void main() {
  group('paragraphTextOf', () {
    test('a Word-split tag is one text and one segment', () {
      final ParagraphText t = _text(wordSplitTag('{{musteri.unvan}}'));
      expect(t.text, '{{musteri.unvan}}');
      expect(t.positions, hasLength(t.text.length));
      expect(
        t.positions.map((TextPosition p) => p.segment).toSet(),
        hasLength(1),
      );
      final TextPosition m = t.positions[2];
      expect(m.region, Region.fillable);
      expect(m.run!.text, 'musteri');
      expect(m.contentIndex, 0);
      expect(m.offset, 0);
      expect(t.positions[3].offset, 1);
      expect(t.positions[0].run!.text, '{{');
      expect(t.spanOf(0, t.text.length), (
        region: Region.fillable,
        crossesBoundary: false,
      ));
    });

    test('a tab is a nonText that ends the segment', () {
      final ParagraphText t = _text(tagAroundTab());
      expect(t.text, '{{a${nonText}b}}');
      final TextPosition tab = t.positions[3];
      expect(tab.run, isNull);
      expect(tab.contentIndex, -1);
      expect(t.positions[2].segment, isNot(tab.segment));
      expect(t.positions[4].segment, isNot(tab.segment));
      expect(t.positions[2].segment, isNot(t.positions[4].segment));
      expect(t.spanOf(0, t.text.length).crossesBoundary, isTrue);
    });

    test('a hyperlink starts and ends a segment', () {
      final ParagraphText t = _text(tagInHyperlink('{{', <String>['x'], '}}'));
      expect(t.text, '{{x}}');
      expect(t.positions[0].segment, isNot(t.positions[2].segment));
      expect(t.positions[2].segment, isNot(t.positions[3].segment));
      expect(t.spanOf(0, 5), (region: Region.fillable, crossesBoundary: true));
      expect(t.spanOf(2, 3), (region: Region.fillable, crossesBoundary: false));
    });

    test('runs of one hyperlink are one segment', () {
      final ParagraphText t = _text(hyperlinkOf(<String>['{{a', '}}']));
      expect(t.text, '{{a}}');
      expect(
        t.positions.map((TextPosition p) => p.segment).toSet(),
        hasLength(1),
      );
      expect(t.positions[2].run!.text, '{{a');
      expect(t.positions[4].run!.text, '}}');
      expect(t.spanOf(0, 5).crossesBoundary, isFalse);
    });

    test('a field result is region fieldResult, the instruction is out', () {
      final ParagraphText t = _text(
        '<w:r><w:t>a</w:t></w:r>${tagInFieldResult('{{x}}', instruction: ' TITLE ')}',
      );
      expect(t.text, 'a{{x}}');
      expect(t.positions[0].region, Region.fillable);
      expect(t.positions[1].region, Region.fieldResult);
      expect(t.positions[1].run, isNull);
      expect(t.positions[1].offset, -1);
      expect(t.spanOf(1, 6), (
        region: Region.fieldResult,
        crossesBoundary: false,
      ));
      expect(t.spanOf(0, 6), (
        region: Region.fieldResult,
        crossesBoundary: true,
      ));
    });

    test('a nested field result is its own segment', () {
      final ParagraphText t = _text(
        '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
        '<w:r><w:instrText> IF </w:instrText></w:r>'
        '<w:r><w:fldChar w:fldCharType="separate"/></w:r>'
        '<w:r><w:t>ab</w:t></w:r>${tagInFieldResult('cd')}'
        '<w:r><w:fldChar w:fldCharType="end"/></w:r>',
      );
      expect(t.text, 'abcd');
      expect(t.positions[0].region, Region.fieldResult);
      expect(t.positions[2].region, Region.fieldResult);
      expect(t.positions[1].segment, isNot(t.positions[2].segment));
    });

    test('tracked insertion is region revision', () {
      final ParagraphText t = _text(
        '<w:r><w:t>a</w:t></w:r>${tagInInsertion('{{x}}')}',
      );
      expect(t.text, 'a{{x}}');
      expect(t.spanOf(1, 6), (region: Region.revision, crossesBoundary: false));
    });

    test('inline content control is region contentControl', () {
      final ParagraphText t = _text(tagInInlineSdt('{{x}}'));
      expect(t.text, '{{x}}');
      expect(t.spanOf(0, 5), (
        region: Region.contentControl,
        crossesBoundary: false,
      ));
    });

    test('other opaque text is region opaque', () {
      final ParagraphText t = _text(
        '<w:smartTag w:uri="u" w:element="e"><w:r><w:t>{{x}}</w:t></w:r>'
        '</w:smartTag>',
      );
      expect(t.text, '{{x}}');
      expect(t.spanOf(0, 5).region, Region.opaque);
    });

    test('an opaque inline without text is a boundary that adds none', () {
      final ParagraphText t = _text(
        '<w:r><w:t>{{a</w:t></w:r><w:customXml w:element="e"/>'
        '<w:r><w:t>b}}</w:t></w:r>',
      );
      expect(t.text, '{{ab}}');
      expect(t.spanOf(0, 6), (region: Region.fillable, crossesBoundary: true));
    });

    test('a deletion adds nothing and does not end the segment', () {
      final ParagraphText t = _text(
        '<w:r><w:t>{{a</w:t></w:r>'
        '<w:del w:id="2" w:author="Ada"><w:r><w:delText>{{</w:delText></w:r>'
        '</w:del><w:r><w:t>b}}</w:t></w:r>',
      );
      expect(t.text, '{{ab}}');
      expect(t.spanOf(0, 6), (region: Region.fillable, crossesBoundary: false));
    });

    test('bookmarks and proofErr are transparent', () {
      final ParagraphText t = _text(wordSplitTag('{{a.b}}'));
      expect(
        t.positions.map((TextPosition p) => p.segment).toSet(),
        hasLength(1),
      );
    });

    test('spanOf with several regions reports the first non-fillable', () {
      final ParagraphText t = _text(
        '${tagInInsertion('x')}${tagInInlineSdt('y')}',
      );
      expect(t.spanOf(0, 2), (region: Region.revision, crossesBoundary: true));
      expect(t.spanOf(1, 2), (
        region: Region.contentControl,
        crossesBoundary: false,
      ));
      expect(t.spanOf(1, 1), (region: Region.fillable, crossesBoundary: false));
      expect(() => t.spanOf(0, 3), throwsRangeError);
    });

    test('a run holding only an instruction cuts the segment', () {
      final ParagraphText t = _text(
        '<w:r><w:t>{{a</w:t></w:r>'
        '<w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'
        '<w:r><w:t>}}</w:t></w:r>',
      );
      expect(t.text, '{{a}}');
      expect(
        t.positions.map((TextPosition p) => p.segment).toSet(),
        hasLength(2),
      );
      expect(t.spanOf(0, 5).crossesBoundary, isTrue);
    });

    test('a header holds the split tag', () {
      final DocxDocument doc = DocxDocument.open(templateWithHeader());
      final DocxParagraph p = doc.sections.first.header.blocks
          .whereType<DocxParagraph>()
          .first;
      expect(paragraphTextOf(p).text, '{{firma.ad}}');
    });
  });
}
