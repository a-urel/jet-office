// The built-in style catalog against the owner's `builtins.docx`, saved by
// Word for Mac 16.114 on a Turkish system: every definition equals the
// file's style once the Turkish ids and names are mapped to Word's English
// ones and the revision identifiers are removed. VM only: it reads the
// fixture from disk.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/src/docx/builtin_styles.dart';
import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';

const String _fixture = 'test/fixtures/owner/docx/builtins.docx';

/// Turkish style ids and names of `builtins.docx` and Word's English ones.
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
  'AralkYok': 'NoSpacing',
  'Gl': 'Strong',
  'Vurgu': 'Emphasis',
  'TabloKlavuzu': 'TableGrid',
  'Kpr': 'Hyperlink',
  'stBilgi': 'Header',
  'stBilgiChar': 'HeaderChar',
  'AltBilgi': 'Footer',
  'AltBilgiChar': 'FooterChar',
  for (int i = 1; i <= 9; i++) ...<String, String>{
    'Balk$i': 'Heading$i',
    'Balk${i}Char': 'Heading${i}Char',
    'Başlık $i Char': 'Heading $i Char',
  },
  'Konu Başlığı Char': 'Title Char',
  'Altyazı Char': 'Subtitle Char',
  'Alıntı Char': 'Quote Char',
  'Güçlü Alıntı Char': 'Intense Quote Char',
  'Üst Bilgi Char': 'Header Char',
  'Alt Bilgi Char': 'Footer Char',
};

/// [element] with Word's English ids and names, no revision identifiers and
/// the `w` namespace declared.
String _cleaned(String element) {
  String xml = element;
  _english.forEach((String from, String to) {
    xml = xml.replaceAll('"$from"', '"$to"');
  });
  return xml
      .replaceAll(RegExp(r' w:rsid\w*="[^"]*"'), '')
      .replaceAll(RegExp(r'<w:rsid [^>]*/>'), '')
      .replaceFirst(
        '<w:style ',
        '<w:style xmlns:w="http://schemas.openxmlformats.org/'
            'wordprocessingml/2006/main" ',
      );
}

void main() {
  test('definitions equal builtins.docx after mapping ids and names', () {
    final ArchiveFile styles = ZipDecoder()
        .decodeBytes(File(_fixture).readAsBytesSync())
        .files
        .firstWhere((ArchiveFile f) => f.name == 'word/styles.xml');
    final String xml = utf8.decode(styles.content);
    final Map<String, String> fromFile = <String, String>{
      for (final RegExpMatch m in RegExp(
        r'<w:style [^>]*w:styleId="([^"]+)">.*?</w:style>',
        dotAll: true,
      ).allMatches(xml))
        _english[m.group(1)!] ?? m.group(1)!: _cleaned(m.group(0)!),
    };
    expect(builtInStyleIds, isNotEmpty);
    for (final String id in builtInStyleIds) {
      expect(fromFile, contains(id), reason: id);
      expect(
        compareXmlParts(
          'word/styles.xml#$id',
          Uint8List.fromList(utf8.encode(fromFile[id]!)),
          Uint8List.fromList(utf8.encode(builtInStyleXml(id))),
        ),
        isEmpty,
        reason: id,
      );
    }
  });
}
