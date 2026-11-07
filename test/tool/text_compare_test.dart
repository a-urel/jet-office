// Tests tool/src/text_compare.dart: the body text of a document, the
// reading of an exported or expected text file, and the line differences.
// Web-safe: documents are built in memory.
library;

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/src/text_compare.dart';
import '../docx/support/docx_builder.dart';

void main() {
  group('docxResavedText', () {
    const String ns =
        'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';

    test('leaves out an empty paragraph that only carries a break', () {
      final DocxDocument doc = DocxDocument.open(
        buildDocx(
          document:
              '<w:document $ns><w:body><w:p><w:r><w:t>One</w:t></w:r></w:p>'
              '<w:p><w:pPr><w:sectPr/></w:pPr></w:p><w:p/>'
              '<w:p><w:r><w:t>Two</w:t></w:r></w:p></w:body></w:document>',
        ),
      );
      expect(docxResavedText(doc), 'One\n\nTwo');
    });

    test('a paragraph with text and a break keeps its text', () {
      final DocxDocument doc = DocxDocument.open(
        buildDocx(
          document:
              '<w:document $ns><w:body><w:p><w:pPr><w:sectPr/></w:pPr>'
              '<w:r><w:t>One</w:t></w:r></w:p></w:body></w:document>',
        ),
      );
      expect(docxResavedText(doc), 'One');
    });

    test('takes a page break at the edge of a paragraph for no line', () {
      final DocxDocument doc = DocxDocument.open(
        buildDocx(
          document:
              '<w:document $ns><w:body><w:p><w:r><w:t>One</w:t></w:r>'
              '<w:r><w:br w:type="page"/></w:r></w:p>'
              '<w:p><w:r><w:t>Two</w:t><w:br/></w:r></w:p>'
              '<w:p><w:r><w:br w:type="page"/><w:t>Three</w:t></w:r></w:p>'
              '</w:body></w:document>',
        ),
      );
      expect(docxResavedText(doc), 'One\nTwo\n\nThree');
    });

    test('is docxFullText for a document with neither', () {
      final DocxDocument doc = DocxDocument();
      doc.body.addParagraph('After');
      doc.body.addTable(columns: 2).addRow(<String?>['a', 'b']);
      expect(docxResavedText(doc), docxFullText(doc));
    });
  });

  group('docxStoriesText', () {
    test('a document with no stories has no lines', () {
      expect(docxStoriesText(DocxDocument()), '');
    });

    test('names each story a section shows, by section, in order', () {
      final DocxDocument doc = DocxDocument();
      final DocxSection one = doc.sections.last;
      one.header.addParagraph('Default');
      one.firstHeader.addParagraph('First');
      one.footer.addParagraph('Foot');
      doc.body.addSection();
      expect(
        docxStoriesText(doc),
        <String>[
          '1 header: Default',
          '1 first header: First',
          '1 footer: Foot',
          '2 header: Default',
          '2 footer: Foot',
        ].join('\n'),
      );
    });

    test('an even story shows only when the document has them', () {
      final DocxDocument doc = DocxDocument();
      doc.sections.last.evenFooter.addParagraph('Even');
      expect(docxStoriesText(doc), '1 even footer: Even');
      doc.evenAndOddHeaders = false;
      expect(docxStoriesText(doc), '');
    });

    test('a first story shows only with a title page', () {
      final DocxDocument doc = DocxDocument();
      doc.sections.last.firstFooter.addParagraph('First');
      doc.sections.last.titlePage = false;
      expect(docxStoriesText(doc), '');
    });

    test('a field reads as its name, whatever its result and switches', () {
      final DocxDocument doc = DocxDocument();
      doc.sections.last.footer.addParagraph('Page ')
        ..addField(DocxField.page())
        ..addRun(' on ')
        ..addField(DocxField.date(result: '07.11.2026'));
      expect(docxStoriesText(doc), '1 footer: Page {PAGE} on {DATE}');
    });

    test('a story has a line for each paragraph, and none for a blank one', () {
      final DocxDocument doc = DocxDocument();
      final DocxHeaderFooter header = doc.sections.last.header;
      header.addParagraph('One');
      header.addParagraph(' ');
      header.addParagraph();
      header.addParagraph('Two');
      expect(docxStoriesText(doc), '1 header: One\n1 header: Two');
    });

    test('a table in a story has a line for each row', () {
      final DocxDocument doc = DocxDocument();
      doc.sections.last.header.addTable(columns: 2).addRow(<String?>['a', 'b']);
      expect(docxStoriesText(doc), '1 header: a\tb');
    });
  });

  group('docxBodyText', () {
    test('joins the paragraphs with a newline and leaves tables out', () {
      final DocxDocument doc = DocxDocument.open(
        buildDocx(
          document:
              '<w:document xmlns:w="http://schemas.openxmlformats.org/'
              'wordprocessingml/2006/main"><w:body>'
              '<w:p><w:r><w:t>One</w:t></w:r></w:p>'
              '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Cell</w:t></w:r></w:p>'
              '</w:tc></w:tr></w:tbl>'
              '<w:p/>'
              '<w:p><w:r><w:t>Two</w:t><w:tab/><w:t>x</w:t></w:r></w:p>'
              '</w:body></w:document>',
        ),
      );
      expect(docxBodyText(doc), 'One\n\nTwo\tx');
    });

    test('a new document reads as the empty text', () {
      expect(docxBodyText(DocxDocument()), '');
    });
  });

  group('docxFullText', () {
    DocxDocument open(String body) => DocxDocument.open(
      buildDocx(
        document:
            '<w:document xmlns:w="http://schemas.openxmlformats.org/'
            'wordprocessingml/2006/main"><w:body>$body</w:body></w:document>',
      ),
    );

    test('a table is a line for each row, its cells joined by a tab', () {
      final DocxDocument doc = open(
        '<w:p><w:r><w:t>One</w:t></w:r></w:p>'
        '<w:tbl><w:tr>'
        '<w:tc><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc>'
        '<w:tc><w:p><w:r><w:t>B</w:t></w:r></w:p></w:tc></w:tr>'
        '<w:tr><w:tc><w:p/></w:tc>'
        '<w:tc><w:p><w:r><w:t>D</w:t></w:r></w:p></w:tc></w:tr></w:tbl>'
        '<w:p><w:r><w:t>Two</w:t></w:r></w:p>',
      );
      expect(docxFullText(doc), 'One\nA\tB\n\tD\nTwo');
    });

    test('paragraphs of a cell are lines, as LibreOffice writes them', () {
      final DocxDocument doc = open(
        '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>A1</w:t></w:r></w:p>'
        '<w:p><w:r><w:t>A2</w:t></w:r></w:p></w:tc>'
        '<w:tc><w:p><w:r><w:t>B</w:t></w:r></w:p></w:tc></w:tr></w:tbl>',
      );
      expect(docxFullText(doc), 'A1\nA2\tB');
    });

    test('a nested table adds the lines of its rows in place', () {
      final DocxDocument doc = open(
        '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>A</w:t></w:r></w:p>'
        '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>x</w:t></w:r></w:p></w:tc>'
        '<w:tc><w:p><w:r><w:t>y</w:t></w:r></w:p></w:tc></w:tr></w:tbl>'
        '<w:p/></w:tc></w:tr></w:tbl>',
      );
      expect(docxFullText(doc), 'A\nx\ny\n');
    });

    test('a new document reads as the empty text', () {
      expect(docxFullText(DocxDocument()), '');
    });
  });

  group('readExpectedText', () {
    test('drops a leading BOM and one trailing newline', () {
      expect(readExpectedText('﻿a\nb\n'), 'a\nb');
      expect(readExpectedText('a\n\n'), 'a\n');
      expect(readExpectedText('a'), 'a');
      expect(readExpectedText('\n'), '');
      expect(readExpectedText(''), '');
    });
  });

  group('textDifferences', () {
    test('equal texts have none', () {
      expect(textDifferences('a\nb', 'a\nb'), isEmpty);
    });

    test('names the first lines that differ, by number', () {
      expect(textDifferences('a\nb\nc', 'a\nB\nc'), <String>[
        'line 2: expected "b", got "B"',
      ]);
    });

    test('reports a different number of lines', () {
      expect(textDifferences('a\nb', 'a'), <String>[
        'line 2: expected "b", got nothing',
        'expected 2 lines, got 1',
      ]);
    });

    test('shows tabs and edge spaces so they can be told apart', () {
      expect(textDifferences(' a\t', 'a'), <String>[
        r'line 1: expected " a\t", got "a"',
      ]);
    });

    test('a difference in a zero-width space is printed escaped', () {
      expect(textDifferences('a\u200Bb', 'ab'), <String>[
        r'line 1: expected "a\u{200b}b", got "ab"',
      ]);
      expect(textDifferences('a\u200Fb', 'a\u200Eb'), <String>[
        r'line 1: expected "a\u{200f}b", got "a\u{200e}b"',
      ]);
      expect(textDifferences('\uFEFFab', 'ab'), <String>[
        r'line 1: expected "\u{feff}ab", got "ab"',
      ]);
      expect(textDifferences('a\u2010b', 'ab'), <String>[
        'line 1: expected "a\u2010b", got "ab"',
      ]);
    });

    test('stops after ten differing lines', () {
      final String expected = List<String>.filled(20, 'x').join('\n');
      final String actual = List<String>.filled(20, 'y').join('\n');
      final List<String> lines = textDifferences(expected, actual);
      expect(lines, hasLength(11));
      expect(lines.last, '... and 10 more differing lines');
    });
  });
}
