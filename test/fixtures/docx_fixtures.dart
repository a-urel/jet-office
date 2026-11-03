/// The fixtures of DOCX milestone D1: new documents with paragraphs of text.
///
/// New in jet_office. Every fixture starts from `DocxDocument()`, the blank
/// document, so what LibreOffice and the Open XML SDK see is what the model
/// writes. `tool/write_fixtures.dart` writes each as `<name>.docx` with its
/// `<name>.expected.txt`; `test/docx/round_trip_test.dart` checks them.
library;

import 'package:jet_office/jet_office.dart';

import 'docx_fixture.dart';

export 'docx_fixture.dart';

/// The paragraphs of `d1_paragraphs`, as `(style, text)`: the first names
/// the `Normal` style, the others name none and so are `Normal` too.
/// `test/docx/support/producer_variants.dart` builds its variants from them.
const List<(String?, String)> d1Paragraphs = <(String?, String)>[
  ('Normal', 'The first paragraph.'),
  (null, 'A second paragraph, with a comma and a full stop.'),
  (null, ''),
  (null, 'The fourth paragraph follows an empty one.'),
  (null, 'Last.'),
];

/// The fixtures of D1, in a fixed order.
List<DocxFixture> docxFixtures() => <DocxFixture>[
  DocxFixture('d1_blank', '', () => DocxDocument().save()),
  DocxFixture(
    'd1_paragraphs',
    <String>[for (final (String?, String) p in d1Paragraphs) p.$2].join('\n'),
    () => _document(<DocxParagraph>[
      for (final (String? style, String text) in d1Paragraphs)
        DocxParagraph.text(text)..style = style,
    ]),
  ),
  DocxFixture(
    'd1_text_rules',
    <String>[
      'Tab\tseparated\tcolumns',
      '\tStarts with a tab',
      'Line one\nLine two',
      'Carriage return and line feed\nare one break',
      '  Leading and trailing spaces  ',
      'Double  spaces  inside',
      ' ',
      'A control character was here: [].',
      'Two runs, one paragraph.',
    ].join('\n'),
    () => _document(<DocxParagraph>[
      DocxParagraph.text('Tab\tseparated\tcolumns'),
      DocxParagraph.text('\tStarts with a tab'),
      DocxParagraph.text('Line one\nLine two'),
      DocxParagraph.text('Carriage return and line feed\r\nare one break'),
      DocxParagraph.text('  Leading and trailing spaces  '),
      DocxParagraph.text('Double  spaces  inside'),
      DocxParagraph.text(' '),
      DocxParagraph.text('A control character was here: [\u0001].'),
      DocxParagraph.text('Two runs, ')..addRun('one paragraph.'),
    ]),
    expectedWarnings: const <DocxWarningCode, int>{
      DocxWarningCode.invalidCharactersRemoved: 1,
    },
  ),
  DocxFixture(
    'd1_unicode',
    _unicode.join('\n'),
    () => _document(<DocxParagraph>[
      for (final String text in _unicode) DocxParagraph.text(text),
    ]),
  ),
  DocxFixture(
    'd1_large',
    <String>[for (int i = 1; i <= _large; i++) _largeParagraph(i)].join('\n'),
    () => _document(<DocxParagraph>[
      for (int i = 1; i <= _large; i++) DocxParagraph.text(_largeParagraph(i)),
    ]),
  ),
];

/// Turkish and German letters, emoji (one with a skin tone, one flag) and
/// supplementary-plane CJK characters (U+20000, U+2A6A5).
const List<String> _unicode = <String>[
  'Türkçe: İıĞğŞşÇçÖöÜü — Işık, iğne, şeker, çiçek.',
  'Deutsch: ÄäÖöÜüß ẞ — Größe, Übermaß, Ärger.',
  'Emoji: 😀 👍🏽 🇹🇷',
  'CJK, supplementary plane: 𠀀 𪚥',
  'Toplam: 1.234,50 ₺ · Summe: 1.234,50 €',
];

/// The number of paragraphs of `d1_large`.
const int _large = 2000;

String _largeParagraph(int i) =>
    'Paragraph $i of $_large: the quick brown fox jumps over the lazy dog.';

/// A new document whose body holds [paragraphs] in place of its one empty
/// paragraph, saved.
DocxResult _document(List<DocxParagraph> paragraphs) {
  final DocxDocument doc = DocxDocument();
  final DocxBody body = doc.body..removeBlockAt(0);
  for (final DocxParagraph p in paragraphs) {
    body.insertBlock(body.blocks.length, p);
  }
  return doc.save();
}
