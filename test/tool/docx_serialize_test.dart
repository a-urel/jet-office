// Tests tool/src/docx_serialize.dart: the helpers that make a DOCX round trip
// serialize the styles and numbering parts (which a document saves as read
// when they are loaded and not changed) and read every typed property of a
// document. Web-safe: the packages are built in memory.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/src/docx_serialize.dart';
import '../docx/support/docx_builder.dart' show buildDocx, rewriteDocxPart;
import '../docx/support/numbering_documents.dart';
import '../docx/support/styles_documents.dart';
import '../fixtures/docx_fixtures.dart';

void main() {
  group('encodedParts', () {
    test('encodes the styles and the numbering part of a document', () {
      final Uint8List docx = docxWithStyles();
      final Map<String, Uint8List> parts = encodedParts(docx);
      expect(parts.keys, <String>['word/styles.xml']);
      final String xml = utf8.decode(parts['word/styles.xml']!);
      expect(xml, contains('<w:style '));
      final Map<String, Uint8List> both = encodedParts(docxWithNumbering());
      expect(both.keys, <String>['word/numbering.xml']);
    });

    test('is the model\'s own writing, not a copy of the input', () {
      // Word writes "\r\n" after the declaration; the model writes "\n", so
      // identical bytes would mean the part was copied, not encoded.
      final Uint8List docx = docxWithStyles();
      final String input = readDocxText(docx)['word/styles.xml']!;
      final String encoded = utf8.decode(
        encodedParts(docx)['word/styles.xml']!,
      );
      expect(input, contains('\r\n'));
      expect(encoded, isNot(input));
    });

    test('a document with neither part has nothing to encode', () {
      expect(encodedParts(buildDocx()), isEmpty);
      expect(encodedPartDifferences(buildDocx()), isEmpty);
    });

    test('a part that cannot be read is a difference, not an exception', () {
      final Uint8List docx = rewriteDocxPart(
        docxWithStyles(),
        'word/styles.xml',
        (String xml) => '<w:styles',
      );
      final List<String> differences = encodedPartDifferences(docx);
      expect(differences, hasLength(1));
      expect(differences.single, startsWith('word/styles.xml: '));
    });
  });

  group('encodedPartDifferences', () {
    test('finds none in what Word writes', () {
      expect(encodedPartDifferences(docxWithStyles()), isEmpty);
      expect(encodedPartDifferences(docxWithNumbering()), isEmpty);
    });

    test('finds none in the D2 fixtures', () {
      for (final DocxFixture f in docxFixtures()) {
        expect(
          encodedPartDifferences(f.build().bytes),
          isEmpty,
          reason: f.name,
        );
      }
    });
  });

  group('readTypedProperties', () {
    test('reads every typed property of a D2 fixture and counts them', () {
      final DocxFixture f = docxFixtures().singleWhere(
        (DocxFixture f) => f.name == 'd2_run_formatting',
      );
      final DocxDocument doc = DocxDocument.open(f.build().bytes);
      expect(readTypedProperties(doc), greaterThan(20));
    });

    test('a document without parts or content sets none', () {
      expect(readTypedProperties(DocxDocument.open(buildDocx())), 0);
    });
  });
}
