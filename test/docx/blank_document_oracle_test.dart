// A new document against the owner's `blank.docx`, saved by Word for Mac
// 16.114.1 on a Turkish system (spec 4.5): its styles, theme, font table,
// settings and web settings are the file's with the identifiers and the
// locale removed, and nothing of the file's document properties is written.
// VM only: it reads the fixture from disk.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';

const String _fixture = 'test/fixtures/owner/docx/blank.docx';

/// The parts of the ZIP [bytes], by entry name.
Map<String, Uint8List> _parts(Uint8List bytes) => <String, Uint8List>{
  for (final ArchiveFile file in ZipDecoder().decodeBytes(bytes).files)
    if (file.isFile) file.name: Uint8List.fromList(file.content),
};

/// Turkish style ids and names of `blank.docx` and the English ones a new
/// document uses in their place.
final Map<String, String> _english = <String, String>{
  'VarsaylanParagrafYazTipi': 'DefaultParagraphFont',
  'NormalTablo': 'TableNormal',
  'ListeYok': 'NoList',
  'KonuBal': 'Title',
  'KonuBalChar': 'TitleChar',
  'Altyaz': 'Subtitle',
  'AltyazChar': 'SubtitleChar',
  'Alnt': 'Quote',
  'AlntChar': 'QuoteChar',
  'ListeParagraf': 'ListParagraph',
  'GlVurgulama': 'IntenseEmphasis',
  'GlAlnt': 'IntenseQuote',
  'GlAlntChar': 'IntenseQuoteChar',
  'GlBavuru': 'IntenseReference',
  for (int i = 1; i <= 9; i++) ...<String, String>{
    'Balk$i': 'Heading$i',
    'Balk${i}Char': 'Heading${i}Char',
    'Başlık $i Char': 'Heading $i Char',
  },
  'Konu Başlığı Char': 'Title Char',
  'Altyazı Char': 'Subtitle Char',
  'Alıntı Char': 'Quote Char',
  'Güçlü Alıntı Char': 'Intense Quote Char',
  'Office Teması': 'Office Theme',
};

/// [part] without what a new document leaves out: revision identifiers,
/// document ids, proof state, attached template, the decimal symbol and the
/// list separator; the language settings become Word's US defaults.
Uint8List _cleaned(Uint8List part) {
  String xml = utf8.decode(part);
  _english.forEach((String from, String to) {
    xml = xml.replaceAll('"$from"', '"$to"');
  });
  xml = xml
      .replaceAll(RegExp(r'<w:rsids>.*?</w:rsids>', dotAll: true), '')
      .replaceAll(RegExp(r'<w:rsid(Root)? [^>]*/>', dotAll: true), '')
      .replaceAll(RegExp(r' w:rsid\w*="[^"]*"', dotAll: true), '')
      .replaceAll(RegExp(r'<w1[45]:docId [^>]*/>', dotAll: true), '')
      .replaceAll(RegExp(r'<w:proofState [^>]*/>', dotAll: true), '')
      .replaceAll(RegExp(r'<w:attachedTemplate [^>]*/>', dotAll: true), '')
      .replaceAll(RegExp(r'<w:decimalSymbol [^>]*/>', dotAll: true), '')
      .replaceAll(RegExp(r'<w:listSeparator [^>]*/>', dotAll: true), '')
      .replaceAll(
        RegExp(r'<w:themeFontLang [^>]*/>', dotAll: true),
        '<w:themeFontLang w:val="en-US"/>',
      )
      .replaceAll(
        RegExp(r'<w:lang [^>]*/>', dotAll: true),
        '<w:lang w:val="en-US" w:eastAsia="en-US" w:bidi="ar-SA"/>',
      );
  return Uint8List.fromList(utf8.encode(xml));
}

void main() {
  late Map<String, Uint8List> blank;
  late Map<String, Uint8List> created;

  setUpAll(() {
    blank = _parts(File(_fixture).readAsBytesSync());
    created = _parts(DocxDocument().save().bytes);
  });

  test('styles, theme, fontTable and settings equal blank.docx after '
      'removing ids and locale', () {
    for (final String name in <String>[
      'word/styles.xml',
      'word/theme/theme1.xml',
      'word/fontTable.xml',
      'word/settings.xml',
      'word/webSettings.xml',
    ]) {
      expect(blank, contains(name));
      expect(
        compareXmlParts('/$name', _cleaned(blank[name]!), created[name]!),
        isEmpty,
        reason: name,
      );
    }
  });

  test('a new document carries no locale of blank.docx', () {
    // The fixture was saved under tr-TR, so the comparison above would not
    // hold if the new document kept its locale.
    final String settings = utf8.decode(blank['word/settings.xml']!);
    expect(settings, contains('<w:themeFontLang w:val="tr-TR"/>'));
    expect(settings, contains('<w:decimalSymbol w:val=","/>'));
    expect(settings, contains('<w:listSeparator w:val=";"/>'));
    for (final MapEntry<String, Uint8List> part in created.entries) {
      final String xml = utf8.decode(part.value);
      expect(xml, isNot(contains('tr-TR')), reason: part.key);
      expect(xml, isNot(contains('decimalSymbol')), reason: part.key);
      expect(xml, isNot(contains('listSeparator')), reason: part.key);
    }
    expect(
      utf8.decode(created['word/settings.xml']!),
      contains('<w:themeFontLang w:val="en-US"/>'),
    );
  });

  test('the section equals the section of blank.docx', () {
    String section(Uint8List document) {
      final String xml = utf8.decode(document);
      final RegExpMatch m = RegExp(
        r'<w:sectPr[^>]*>(.*)</w:sectPr>',
      ).firstMatch(xml)!;
      return m.group(1)!;
    }

    expect(
      section(created['word/document.xml']!),
      section(blank['word/document.xml']!),
    );
  });

  test('the package parts match blank.docx apart from docProps', () {
    expect(
      created.keys.toSet(),
      blank.keys.where((String n) => !n.startsWith('docProps/')).toSet(),
    );
    // Relationship ids differ by order; what they resolve to must not.
    Set<String> relationships(Uint8List rels) => <String>{
      for (final RegExpMatch m in RegExp(
        r'Type="([^"]*)" Target="([^"]*)"',
      ).allMatches(utf8.decode(rels)))
        '${m.group(1)} ${m.group(2)}',
    };
    expect(
      relationships(created['word/_rels/document.xml.rels']!),
      relationships(blank['word/_rels/document.xml.rels']!),
    );
  });

  test('nothing of the owner\'s document properties is written', () {
    final String core = utf8.decode(blank['docProps/core.xml']!);
    final Set<String> names = <String>{
      for (final RegExpMatch m in RegExp(
        r'<(?:dc:creator|cp:lastModifiedBy)>([^<]+)<',
      ).allMatches(core))
        m.group(1)!,
    };
    expect(names, isNotEmpty);
    for (final MapEntry<String, Uint8List> part in created.entries) {
      final String xml = utf8.decode(part.value);
      for (final String name in names) {
        expect(xml, isNot(contains(name)), reason: part.key);
      }
    }
  });
}
