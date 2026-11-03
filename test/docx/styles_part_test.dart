// Tests the styles part of a document: it loads on the first access to
// DocxDocument.styles through the main part's relationship, wherever it
// lives; an untouched one is copied byte for byte, a loaded one is written
// from the model and means what it meant; a document without one gains it
// at save only when it holds something, once (plan Ruling 7). The packages
// are built in memory, so these tests run on the web as well.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';
import '../support/read_xlsx.dart';
import 'support/docx_builder.dart';
import 'support/styles_documents.dart';
import 'support/word_document.dart';

/// A new paragraph style named [name] with the id [id].
DocxStyle _style(String id, [String? name]) =>
    DocxStyle(type: DocxStyleType.paragraph, id: id, name: name ?? id);

/// The relationships of the main part of [docx] of the styles type.
List<String> _stylesTargets(Uint8List docx) {
  final String rels = readDocxText(docx)['word/_rels/document.xml.rels'] ?? '';
  return <String>[
    for (final RegExpMatch m in RegExp(
      r'<Relationship [^>]*Type="([^"]*)"[^>]*Target="([^"]*)"',
    ).allMatches(rels))
      if (m.group(1) == RelType.styles) m.group(2)!,
  ];
}

/// The content type overrides of [docx] for [part].
int _overridesOf(Uint8List docx, String part) => RegExp(
  '<Override PartName="${RegExp.escape(part)}" '
  'ContentType="${RegExp.escape(ContentType.wmlStyles)}"/>',
).allMatches(readDocxText(docx)['[Content_Types].xml']!).length;

void main() {
  group('open and save', () {
    for (final (String name, String xml) in <(String, String)>[
      ('Word', wordStylesXml),
      ('LibreOffice', libreOfficeStylesXml),
    ]) {
      test('open, access styles, save is semantically equal ($name)', () {
        final Uint8List input = docxWithStyles(styles: xml);
        final DocxDocument doc = DocxDocument.open(input);
        expect(doc.styles.styles, isNotEmpty);
        expect(isStylesLoaded(doc), isTrue);
        final Uint8List output = doc.save().bytes;
        expect(comparePackages(input, output), isEmpty);
        // The part was written from the model, not copied.
        expect(
          readXlsxBytes(output)['word/styles.xml'],
          isNot(readXlsxBytes(input)['word/styles.xml']),
        );
      });
    }

    test('open, access styles, save is semantically equal (blank)', () {
      final Uint8List input = DocxDocument().save().bytes;
      final DocxDocument doc = DocxDocument.open(input);
      expect(doc.styles.byId('Normal'), isNotNull);
      expect(comparePackages(input, doc.save().bytes), isEmpty);
    });

    test('latent styles and unknown root children stay in place', () {
      final DocxDocument doc = DocxDocument.open(
        docxWithStyles(styles: libreOfficeStylesXml),
      );
      doc.styles.add(_style('Note'));
      final String xml = readDocxText(doc.save().bytes)['word/styles.xml']!;
      expect(xml, contains('<w:latentStyles w:count="376"/>'));
      expect(
        xml,
        contains(
          '<w:name w:val="Note"/></w:style><w14:extra w14:val="1"/>'
          '</w:styles>',
        ),
      );
      expect(xml, contains('w14:lo="1"'));
    });

    test('open and save without access copies styles.xml byte for byte', () {
      final Uint8List input = docxWithStyles();
      final DocxDocument doc = DocxDocument.open(input);
      expect(doc.body.blocks, isNotEmpty);
      final Uint8List output = doc.save().bytes;
      expect(isStylesLoaded(doc), isFalse);
      expect(
        readXlsxBytes(output)['word/styles.xml'],
        readXlsxBytes(input)['word/styles.xml'],
      );
    });
  });

  group('where the part is', () {
    test('the styles part is found by relationship wherever it lives', () {
      final String external = stylesRelationship(
        'http://example.com/s.xml',
        id: 'rId7',
        external: true,
      );
      final Uint8List input = docxWithStyles(
        stylesPath: 'word/custom-styles.xml',
        relationships: '$external${stylesRelationship('custom-styles.xml')}',
      );
      final DocxDocument doc = DocxDocument.open(input);
      expect(doc.styles.byId('Balk1')?.name, 'heading 1');
      doc.styles.add(_style('Note'));
      final Uint8List output = doc.save().bytes;
      final Map<String, String> parts = readDocxText(output);
      expect(parts['word/custom-styles.xml'], contains('w:styleId="Note"'));
      expect(parts.containsKey('word/styles.xml'), isFalse);
      expect(_stylesTargets(output), <String>[
        'http://example.com/s.xml',
        'custom-styles.xml',
      ]);
    });

    test('a styles relationship to a missing part reads empty and the save '
        'creates the part at its target', () {
      final Uint8List input = docxWithStyles(
        styles: null,
        relationships: stylesRelationship('styles/gone.xml'),
      );
      final DocxDocument doc = DocxDocument.open(input);
      expect(doc.styles.styles, isEmpty);
      expect(doc.styles.defaults.runProperties.sizePt, isNull);
      doc.styles.add(_style('Note'));
      final Uint8List output = doc.save().bytes;
      expect(readDocxText(output)['word/styles/gone.xml'], contains('"Note"'));
      expect(_stylesTargets(output), <String>['styles/gone.xml']);
      expect(_overridesOf(output, '/word/styles/gone.xml'), 1);
      expect(DocxDocument.open(output).styles.byId('Note'), isNotNull);
    });

    for (final String target in <String>[
      '_rels/x.xml.rels',
      '../[Content_Types].xml',
      'media/',
      '',
    ]) {
      test('a missing target "$target" that is no legal part name is kept '
          'and the part goes to /word/styles.xml', () {
        final Uint8List input = docxWithStyles(
          styles: null,
          relationships: stylesRelationship(target),
        );
        final DocxDocument doc = DocxDocument.open(input);
        expect(doc.styles.styles, isEmpty);
        doc.styles.add(_style('Note'));
        final Uint8List output = doc.save().bytes;
        final List<String> names = readXlsxBytes(output).keys.toList();
        for (final String a in names) {
          for (final String b in names) {
            expect(b.startsWith('$a/'), isFalse, reason: '$a and $b');
          }
        }
        expect(readDocxText(output)['word/styles.xml'], contains('"Note"'));
        expect(_stylesTargets(output), <String>[target, 'styles.xml']);
        final DocxDocument back = DocxDocument.open(output);
        expect(back.styles.byId('Note'), isNotNull);
        expect(back.body.blocks, isNotEmpty);
      });
    }

    for (final String target in <String>['document.xml', 'settings.xml']) {
      test('a styles relationship to $target, which holds no styles, is '
          'kept and a new styles part is created', () {
        final Uint8List input = docxWithStyles(
          styles: null,
          relationships: stylesRelationship(target),
        );
        final DocxDocument doc = DocxDocument.open(input);
        expect(doc.styles.styles, isEmpty);
        doc.styles.add(_style('Note'));
        final Uint8List output = doc.save().bytes;
        final Map<String, Uint8List> before = readXlsxBytes(input);
        final Map<String, Uint8List> after = readXlsxBytes(output);
        expect(after['word/document.xml'], before['word/document.xml']);
        expect(after['word/settings.xml'], before['word/settings.xml']);
        expect(readDocxText(output)['word/styles.xml'], contains('"Note"'));
        expect(_stylesTargets(output), <String>[target, 'styles.xml']);
        final DocxDocument back = DocxDocument.open(output);
        expect(back.body.blocks, hasLength(doc.body.blocks.length));
        expect(back.styles.byId('Note'), isNotNull);
      });
    }

    test('an external styles relationship is ignored', () {
      final Uint8List input = docxWithStyles(
        relationships: stylesRelationship(
          'http://example.com/',
          external: true,
        ),
      );
      final DocxDocument doc = DocxDocument.open(input);
      expect(doc.styles.styles, isEmpty);
      doc.styles.add(_style('Note'));
      final Uint8List output = doc.save().bytes;
      expect(_stylesTargets(output), <String>[
        'http://example.com/',
        'styles2.xml',
      ]);
      expect(readDocxText(output)['word/styles2.xml'], contains('"Note"'));
      // The part without a relationship was not overwritten: the new one
      // got the next free name.
      expect(
        readXlsxBytes(output)['word/styles.xml'],
        readXlsxBytes(input)['word/styles.xml'],
      );
    });
  });

  group('a document without styles.xml', () {
    Uint8List bare() => wordDocx();

    test('a document without styles.xml that gets a style gains the part, '
        'its override and one relationship', () {
      final DocxDocument doc = DocxDocument.open(bare());
      expect(doc.styles.styles, isEmpty);
      doc.styles.add(_style('Note', 'My note'));
      final Uint8List output = doc.save().bytes;
      expect(readDocxText(output)['word/styles.xml'], contains('"My note"'));
      expect(_overridesOf(output, '/word/styles.xml'), 1);
      expect(_stylesTargets(output), <String>['styles.xml']);
      final DocxDocument back = DocxDocument.open(output);
      expect(back.styles.byName('my NOTE')?.id, 'Note');
      expect(back.body.blocks, hasLength(doc.body.blocks.length));
    });

    test('a second save adds no second part', () {
      final DocxDocument doc = DocxDocument.open(bare());
      doc.styles.add(_style('Note'));
      final Uint8List first = doc.save().bytes;
      doc.styles.add(_style('Other'));
      final Uint8List second = doc.save().bytes;
      expect(
        readDocxText(first).keys.toSet(),
        readDocxText(second).keys.toSet(),
      );
      expect(_stylesTargets(second), <String>['styles.xml']);
      expect(_overridesOf(second, '/word/styles.xml'), 1);
      expect(readDocxText(second)['word/styles.xml'], contains('"Other"'));
    });

    test('document defaults alone create the part', () {
      final DocxDocument doc = DocxDocument.open(bare());
      doc.styles.defaults.runProperties.sizePt = 11;
      final Uint8List output = doc.save().bytes;
      expect(
        DocxDocument.open(output).styles.defaults.runProperties.sizePt,
        11,
      );
    });

    test('a style added then rolled back leaves no styles part', () {
      final DocxDocument doc = DocxDocument.open(bare());
      editsOf(doc).afterRecord = () => throw StateError('fail');
      expect(() => doc.styles.add(_style('Note')), throwsStateError);
      editsOf(doc).afterRecord = null;
      expect(doc.styles.styles, isEmpty);
      final Uint8List output = doc.save().bytes;
      expect(readDocxText(output).containsKey('word/styles.xml'), isFalse);
      expect(_stylesTargets(output), isEmpty);
      expect(comparePackages(bare(), output), isEmpty);
    });

    test('a main part outside word/ gets /word/styles.xml by an absolute '
        'target', () {
      final DocxDocument doc = DocxDocument.open(
        buildDocx(mainPath: 'doc/main.xml'),
      );
      doc.styles.add(_style('Note'));
      final Uint8List output = doc.save().bytes;
      final Map<String, String> parts = readDocxText(output);
      expect(parts['word/styles.xml'], contains('"Note"'));
      expect(
        parts['doc/_rels/main.xml.rels'],
        contains('Target="/word/styles.xml"'),
      );
      expect(DocxDocument.open(output).styles.byId('Note'), isNotNull);
    });

    test('accessing the empty styles and saving changes nothing', () {
      final DocxDocument doc = DocxDocument.open(bare());
      expect(doc.styles.byName('Normal'), isNull);
      expect(comparePackages(bare(), doc.save().bytes), isEmpty);
    });
  });

  group('broken parts', () {
    test('a malformed styles.xml throws DocxReadException naming the part on '
        'access', () {
      final Uint8List input = docxWithStyles(
        styles: '<w:styles xmlns:w="${Ns.w}"><w:style>',
      );
      final DocxDocument doc = DocxDocument.open(input);
      for (int i = 0; i < 2; i++) {
        try {
          doc.styles;
          fail('No DocxReadException was thrown.');
        } on DocxReadException catch (e) {
          expect(e.reason, DocxReadFailure.malformedXml);
          expect(e.part, '/word/styles.xml');
        }
      }
      // A save copies the part as it was.
      expect(
        utf8.decode(readXlsxBytes(doc.save().bytes)['word/styles.xml']!),
        '<w:styles xmlns:w="${Ns.w}"><w:style>',
      );
    });

    test('a styles part whose root is not w:styles throws on access', () {
      final DocxDocument doc = DocxDocument.open(
        docxWithStyles(styles: '<w:document xmlns:w="${Ns.w}"/>'),
      );
      expect(
        () => doc.styles,
        throwsA(
          isA<DocxReadException>()
              .having(
                (DocxReadException e) => e.part,
                'part',
                '/word/styles.xml',
              )
              .having(
                (DocxReadException e) => e.reason,
                'reason',
                DocxReadFailure.malformedXml,
              ),
        ),
      );
    });

    test('a malformed document.xml.rels throws naming it on access', () {
      final Uint8List input = rewriteDocxPart(
        docxWithStyles(),
        'word/_rels/document.xml.rels',
        (String xml) => xml.replaceFirst('</Relationships>', ''),
      );
      final DocxDocument doc = DocxDocument.open(input);
      expect(
        () => doc.styles,
        throwsA(
          isA<DocxReadException>().having(
            (DocxReadException e) => e.part,
            'part',
            '/word/_rels/document.xml.rels',
          ),
        ),
      );
    });
  });
}
