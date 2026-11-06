// Tests of a new document, with the values of Word for Mac's blank one (spec
// 4.5, decision 0011): the parts it writes, its A4 section, and that it
// carries no locale, identifier or document property of the file it follows. They build everything in
// memory, so they run on the web as well; the comparison with `blank.docx`
// itself is in `blank_document_oracle_test.dart`.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/blank_document.dart';
import 'package:test/test.dart';

/// The parts of the ZIP [bytes] as text, by entry name.
Map<String, String> _parts(Uint8List bytes) => <String, String>{
  for (final ArchiveFile file in ZipDecoder().decodeBytes(bytes).files)
    if (file.isFile) file.name: utf8.decode(file.content),
};

/// A new document, saved.
Map<String, String> _saved() => _parts(DocxDocument().save().bytes);

void main() {
  group('a new document', () {
    test('writes the parts of Word\'s blank document, without docProps', () {
      expect(_saved().keys, <String>{
        '[Content_Types].xml',
        '_rels/.rels',
        'word/document.xml',
        'word/_rels/document.xml.rels',
        'word/styles.xml',
        'word/settings.xml',
        'word/webSettings.xml',
        'word/fontTable.xml',
        'word/theme/theme1.xml',
      });
    });

    test('saves, opens and has one empty paragraph', () {
      final DocxDocument doc = DocxDocument();
      expect(doc.body.blocks, hasLength(1));
      final DocxParagraph paragraph = doc.body.blocks.single as DocxParagraph;
      expect(paragraph.inlines, isEmpty);
      expect(doc.warnings, isEmpty);

      doc.body.addParagraph('Merhaba');
      final DocxResult result = doc.save();
      expect(result.warnings, isEmpty);
      final DocxDocument reopened = DocxDocument.open(result.bytes);
      expect(reopened.warnings, isEmpty);
      expect(reopened.body.blocks, hasLength(2));
      expect(
        (reopened.body.blocks.last as DocxParagraph).inlines.single,
        isA<DocxRun>().having((DocxRun r) => r.text, 'text', 'Merhaba'),
      );
    });

    test('opens, and saves unchanged with the same parts', () {
      final Map<String, String> first = _saved();
      final Map<String, String> again = _parts(
        DocxDocument.open(DocxDocument().save().bytes).save().bytes,
      );
      expect(again, first);
    });

    test('section is A4 portrait', () {
      final String document = _saved()['word/document.xml']!;
      expect(document, contains('<w:pgSz w:w="11906" w:h="16838"/>'));
      expect(
        document,
        contains(
          '<w:pgMar w:top="1417" w:right="1417" w:bottom="1417" '
          'w:left="1417" w:header="708" w:footer="708" w:gutter="0"/>',
        ),
      );
      expect(document, contains('<w:docGrid w:linePitch="360"/>'));
      expect(
        document,
        matches(RegExp(r'<w:p/><w:sectPr>.*</w:sectPr></w:body>')),
      );
    });

    test('has no docProps', () {
      final Map<String, String> parts = _saved();
      expect(
        parts.keys.where((String n) => n.startsWith('docProps/')),
        isEmpty,
      );
      expect(parts['[Content_Types].xml'], isNot(contains('docProps')));
      expect(parts['_rels/.rels'], isNot(contains('docProps')));
    });

    test('keeps compatibilityMode 15 and the web settings', () {
      final Map<String, String> parts = _saved();
      expect(
        parts['word/settings.xml'],
        contains('w:name="compatibilityMode"'),
      );
      expect(
        RegExp(
          r'w:name="compatibilityMode"[^>]*w:val="15"',
        ).hasMatch(parts['word/settings.xml']!),
        isTrue,
      );
      expect(parts['word/webSettings.xml'], contains('optimizeForBrowser'));
      expect(parts['word/_rels/document.xml.rels'], contains('webSettings'));
    });

    test('carries no locale of the file it comes from', () {
      final Map<String, String> parts = _saved();
      expect(
        parts['word/settings.xml'],
        contains('<w:themeFontLang w:val="en-US"/>'),
      );
      expect(parts['word/settings.xml'], isNot(contains('decimalSymbol')));
      expect(parts['word/settings.xml'], isNot(contains('listSeparator')));
      for (final MapEntry<String, String> part in parts.entries) {
        expect(part.value, isNot(contains('tr-TR')), reason: part.key);
        for (final RegExpMatch m in RegExp(
          r'<w:lang [^>]*/>',
        ).allMatches(part.value)) {
          expect(
            m.group(0),
            '<w:lang w:val="en-US" w:eastAsia="en-US" w:bidi="ar-SA"/>',
            reason: part.key,
          );
        }
      }
      expect(
        RegExp(r'<w:lang ').allMatches(parts['word/styles.xml']!),
        isNotEmpty,
      );
      final String styles = parts['word/styles.xml']!;
      final RegExp nonAscii = RegExp(r'[^\x00-\x7F]');
      for (final RegExpMatch m in RegExp(
        r'w:styleId="([^"]*)"|<w:name w:val="([^"]*)"',
      ).allMatches(styles)) {
        expect(nonAscii.hasMatch(m.group(0)!), isFalse, reason: m.group(0));
      }
      for (final String id in <String>[
        'Normal',
        'Heading1',
        'Heading9',
        'Heading1Char',
        'TableNormal',
        'ListParagraph',
        'DefaultParagraphFont',
        'NoList',
        'Title',
        'TitleChar',
      ]) {
        expect(styles, contains('w:styleId="$id"'));
      }
      for (final String id in <String>[
        'Balk1',
        'NormalTablo',
        'ListeParagraf',
        'KonuBal',
      ]) {
        expect(styles, isNot(contains('"$id"')));
      }
      expect(parts['word/theme/theme1.xml'], contains('name="jet_office"'));
    });

    test('carries no revision identifier, document id or proof state', () {
      final RegExp banned = RegExp(r'rsid|docId|proofState|attachedTemplate');
      for (final MapEntry<String, String> part in _saved().entries) {
        expect(banned.hasMatch(part.value), isFalse, reason: part.key);
      }
    });

    test('uses Aptos through the theme at 12 pt', () {
      final Map<String, String> parts = _saved();
      expect(parts['word/theme/theme1.xml'], contains('typeface="Aptos"'));
      expect(parts['word/styles.xml'], contains('<w:sz w:val="24"/>'));
    });

    test('writes its own theme and latent styles, not Word\'s text', () {
      final Map<String, String> parts = _saved();
      final String theme = parts['word/theme/theme1.xml']!;
      expect(theme, isNot(contains('themeFamily')));
      expect(theme, isNot(contains('gradFill')));
      expect(theme, isNot(contains('<a:font script=')));
      expect(theme, isNot(contains('Office Theme')));
      expect(
        RegExp('<w:lsdException ').allMatches(blankStyles).length,
        lessThan(30),
      );
      expect(parts['word/settings.xml'], isNot(contains('w16')));
      expect(parts['word/styles.xml'], isNot(contains('w16')));
      expect(parts['word/fontTable.xml'], isNot(contains('w16')));
      expect(parts['word/webSettings.xml'], isNot(contains('w16')));
    });

    test('the constants are the parts that are written', () {
      final Map<String, String> parts = _saved();
      expect(parts['word/styles.xml'], blankStyles);
      expect(parts['word/settings.xml'], blankSettings);
      expect(parts['word/fontTable.xml'], blankFontTable);
      expect(parts['word/webSettings.xml'], blankWebSettings);
      expect(parts['word/theme/theme1.xml'], blankTheme);
      expect(parts['word/document.xml'], blankDocument);
    });
  });
}
