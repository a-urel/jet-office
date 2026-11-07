// Tests tool/src/docx_serialize.dart: the helpers that make a DOCX round trip
// serialize the styles and numbering parts (which a document saves as read
// when they are loaded and not changed) and read every typed property of a
// document. Web-safe: the packages are built in memory.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:test/test.dart';

import '../../tool/src/docx_serialize.dart';
import '../../tool/src/part_compare.dart';
import '../docx/support/docx_builder.dart' show buildDocx, rewriteDocxPart;
import '../docx/support/numbering_documents.dart';
import '../docx/support/styles_documents.dart';
import '../fixtures/docx_fixtures.dart';

/// The WordprocessingML namespace.
const String _w = Ns.w;

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

  group('encodedMainDifferences', () {
    const String w =
        'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';

    test('takes the properties in any order, as the model reorders them', () {
      final Uint8List docx = buildDocx(
        document:
            '<w:document $w><w:body><w:p><w:pPr><w:jc w:val="left"/>'
            '<w:keepNext/></w:pPr><w:r><w:rPr><w:sz w:val="20"/><w:b/>'
            '</w:rPr><w:t>a</w:t></w:r></w:p></w:body></w:document>',
      );
      expect(encodedMainDifferences(docx), isEmpty);
    });

    test('negative control: a difference elsewhere is found', () {
      final Uint8List docx = buildDocx(
        document:
            '<w:document $w><w:body><w:p><w:r><w:t>a</w:t>junk</w:r></w:p>'
            '</w:body></w:document>',
      );
      final List<String> differences = encodedMainDifferences(docx);
      expect(differences, isNotEmpty);
      expect(differences.first, startsWith('word/document.xml: '));
    });

    test('a broken main part is one line', () {
      final Uint8List docx = buildDocx(document: '<w:document');
      expect(encodedMainDifferences(docx), hasLength(1));
    });

    test('finds none in the fixtures', () {
      for (final DocxFixture f in docxFixtures()) {
        expect(
          encodedMainDifferences(f.build().bytes),
          isEmpty,
          reason: f.name,
        );
      }
    });
  });

  group('encodedPartDifferences', () {
    test('a broken numbering part is one line, naming only that part', () {
      final Uint8List docx = rewriteDocxPart(
        docxWithNumbering(),
        'word/numbering.xml',
        (String xml) => '<w:numbering',
      );
      final List<String> differences = encodedPartDifferences(docx);
      expect(differences, hasLength(1));
      expect(differences.single, startsWith('word/numbering.xml: '));
    });

    test('negative control: a part the model writes differently is found', () {
      // The model writes a style's children in schema order, so a file with
      // w:basedOn before w:name means the same but not the same element
      // sequence: the comparison must say so.
      final Uint8List docx = docxWithStyles(
        styles:
            '<w:styles xmlns:w="http://schemas.openxmlformats.org/'
            'wordprocessingml/2006/main">'
            '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
            '<w:name w:val="Normal"/></w:style>'
            '<w:style w:type="paragraph" w:styleId="Note">'
            '<w:basedOn w:val="Normal"/><w:name w:val="Note"/></w:style>'
            '</w:styles>',
      );
      final List<String> differences = encodedPartDifferences(docx);
      expect(differences, isNotEmpty);
      expect(differences.first, startsWith('word/styles.xml: '));
    });

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

  group('tables', () {
    Uint8List docx(String body) => buildDocx(
      document: '<w:document xmlns:w="$_w"><w:body>$body</w:body></w:document>',
    );

    test('the children of tblPr, trPr and tcPr compare in any order', () {
      expect(
        encodedMainDifferences(
          docx(
            '<w:tbl><w:tblPr><w:tblLook w:val="04A0"/>'
            '<w:tblStyle w:val="T"/></w:tblPr><w:tr><w:trPr><w:tblHeader/>'
            '<w:cantSplit/></w:trPr><w:tc><w:tcPr><w:vAlign w:val="top"/>'
            '<w:tcW w:w="20" w:type="dxa"/></w:tcPr><w:p/></w:tc></w:tr>'
            '</w:tbl>',
          ),
        ),
        isEmpty,
      );
    });

    test('readTypedProperties reads the paragraphs and runs of a cell, '
        'nested tables too', () {
      const String p =
          '<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/>'
          '</w:rPr></w:r></w:p>';
      final DocxDocument doc = DocxDocument.open(
        docx(
          '<w:tbl><w:tr><w:tc>$p<w:tbl><w:tr><w:tc>$p</w:tc></w:tr></w:tbl>'
          '<w:p/></w:tc></w:tr></w:tbl>',
        ),
      );
      expect(readTypedProperties(doc), 4);
    });

    test('readTypedProperties reads the properties of tables, rows and '
        'cells, and the grid', () {
      final DocxDocument doc = DocxDocument.open(
        docx(
          '<w:tbl><w:tblPr><w:tblStyle w:val="T"/><w:tblLayout '
          'w:type="fixed"/></w:tblPr><w:tblGrid><w:gridCol w:w="20"/>'
          '</w:tblGrid><w:tr><w:trPr><w:cantSplit/></w:trPr><w:tc><w:tcPr>'
          '<w:gridSpan w:val="1"/><w:vAlign w:val="top"/></w:tcPr><w:p/>'
          '</w:tc></w:tr></w:tbl>',
        ),
      );
      // Two of the table, the grid, one of the row, two of the cell.
      expect(readTypedProperties(doc), 6);
    });
  });

  group('sections and stories', () {
    Uint8List fixture(String name) => docxFixtures()
        .singleWhere((DocxFixture f) => f.name == name)
        .build()
        .bytes;

    test('the children of sectPr compare in any order', () {
      expect(
        encodedMainDifferences(
          buildDocx(
            document:
                '<w:document xmlns:w="$_w"><w:body><w:sectPr>'
                '<w:titlePg/><w:pgMar w:top="1" w:right="1" w:bottom="1" '
                'w:left="1" w:header="1" w:footer="1" w:gutter="0"/>'
                '<w:pgSz w:w="100" w:h="200"/></w:sectPr></w:body>'
                '</w:document>',
          ),
        ),
        isEmpty,
      );
    });

    test('encodedStoryDifferences finds none in the D4 fixtures', () {
      for (final String name in <String>['d4_headers', 'd4_fields']) {
        expect(encodedStoryDifferences(fixture(name)), isEmpty, reason: name);
      }
    });

    test('a document with no stories has nothing to compare', () {
      expect(encodedStoryDifferences(DocxDocument().save().bytes), isEmpty);
    });

    test('a broken footer is one line, naming the part', () {
      final List<String> differences = encodedStoryDifferences(
        rewriteDocxPart(
          fixture('d4_fields'),
          'word/footer1.xml',
          (String x) => x.replaceFirst('</w:ftr>', ''),
        ),
      );
      expect(differences, hasLength(1));
      expect(differences.single, startsWith('word/footer1.xml: '));
    });

    test('the children of a story\'s properties compare in any order', () {
      expect(
        encodedStoryDifferences(
          rewriteDocxPart(
            fixture('d4_fields'),
            'word/footer1.xml',
            (String x) => x.replaceFirst(
              '<w:p>',
              '<w:p><w:pPr><w:jc w:val="left"/><w:keepNext/></w:pPr>',
            ),
          ),
        ),
        isEmpty,
      );
    });

    test('readTypedProperties reads the values of a section', () {
      final DocxDocument bare = DocxDocument.open(buildDocx());
      final int none = readTypedProperties(bare);
      final DocxDocument doc = DocxDocument.open(fixture('d4_sections'));
      expect(readTypedProperties(doc), greaterThan(none + 20));
    });

    test('readTypedProperties loads the stories, and a bad one throws', () {
      final Uint8List broken = rewriteDocxPart(
        fixture('d4_fields'),
        'word/footer1.xml',
        (String x) => x.replaceFirst('</w:ftr>', ''),
      );
      expect(
        () => readTypedProperties(DocxDocument.open(broken)),
        throwsA(isA<DocxReadException>()),
      );
    });

    test('readTypedProperties leaves a document saving what it read', () {
      final Uint8List input = fixture('d4_headers');
      final DocxDocument doc = DocxDocument.open(input);
      readTypedProperties(doc);
      expect(comparePackages(input, doc.save().bytes), isEmpty);
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
