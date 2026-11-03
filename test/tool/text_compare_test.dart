// Tests tool/src/text_compare.dart: the body text of a document, the
// reading of an exported or expected text file, and the line differences.
// Web-safe: documents are built in memory.
library;

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/src/text_compare.dart';
import '../docx/support/docx_builder.dart';

void main() {
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

    test('stops after ten differing lines', () {
      final String expected = List<String>.filled(20, 'x').join('\n');
      final String actual = List<String>.filled(20, 'y').join('\n');
      final List<String> lines = textDifferences(expected, actual);
      expect(lines, hasLength(11));
      expect(lines.last, '... and 10 more differing lines');
    });
  });
}
