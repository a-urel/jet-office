/// The fixtures of DOCX milestones D1 to D6: new documents with paragraphs of
/// text (D1), with run and paragraph formatting, styles and lists (D2), with
/// tables (D3), with sections, headers, footers and fields (D4) and with
/// pictures, hyperlinks, bookmarks and document properties (D5) and with
/// lists written by `DocxListExport` (D6); and the template fill's of T1
/// (decision 0024): a template filled by `DocxTemplate` (`t1_values`,
/// `t1_merge_fields`) and those templates unfilled (`t1_template`,
/// `t1_merge_fields_template`).
///
/// New in jet_office. Every D fixture starts from `DocxDocument()`, the blank
/// document, so what LibreOffice and the Open XML SDK see is what the model
/// writes. A T1 template is written by hand
/// (`test/docx/support/template_documents.dart`), as Word for Mac writes one,
/// with its tags split over runs, so the fill meets them as it would in a
/// user's file; a filled one is what `DocxTemplate.fill` saves. `tool/write_fixtures.dart` writes each as `<name>.docx` with its
/// `<name>.expected.txt`; `test/docx/round_trip_test.dart` checks them.
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

import '../../tool/src/fill_data.dart';
import '../../tool/src/text_compare.dart' show docxFullText, docxStoriesText;
import '../docx/support/template_documents.dart';
import 'docx_fixture.dart';
import 'm4_fixtures.dart' show jpeg3x5, png4x2;

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

/// The fixtures of D1 to D6, in a fixed order.
///
/// No fixture may end in a table: LibreOffice's text export of a document
/// whose body ends in a table never ends, it writes the file without bound
/// (the model adds no paragraph after a last table), and the CI job converts
/// every fixture. End the body in a paragraph, and not in one that carries a
/// section break: `tool/write_table_last.dart` writes that document for the
/// Word check alone.
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
  DocxFixture(
    'd2_run_formatting',
    <String>[for (final (String text, _) in _runFormatting) text].join('\n'),
    () => _build((DocxDocument doc) {
      for (final (String text, void Function(DocxRunProperties) set)
          in _runFormatting) {
        set(doc.body.addParagraph().addRun(text).properties);
      }
    }),
  ),
  DocxFixture(
    'd2_paragraph_formatting',
    <String>[
      for (final (String text, _) in _paragraphFormatting) text,
    ].join('\n'),
    () => _build((DocxDocument doc) {
      for (final (String text, void Function(DocxParagraphProperties) set)
          in _paragraphFormatting) {
        final DocxParagraph paragraph = doc.body.addParagraph(text);
        set(paragraph.properties);
      }
    }),
  ),
  DocxFixture('d2_styles', _styleTexts.join('\n'), () => _build(_fillStyles)),
  DocxFixture(
    'd2_lists',
    _listTexts.join('\n'),
    () => _build(_fillLists),
    libreOfficeText: _listLibreOfficeTexts.join('\n'),
  ),
  _tableFixture('d3_basic', _fillBasic, expectedText: _basicText),
  _tableFixture('d3_header_row', _fillHeaderRow),
  _tableFixture('d3_merges', _fillMerges, expectedText: _mergesText),
  _tableFixture('d3_formatting', _fillFormatting),
  _tableFixture(
    'd3_nested',
    _fillNested,
    libreOfficeTextSkip:
        'LibreOffice repeats a paragraph in the text of nested tables; '
        'differs by version',
  ),
  DocxFixture(
    'd4_sections',
    _sectionsText.join('\n'),
    () => _build(_fillSections),
  ),
  DocxFixture(
    'd4_headers',
    _headersText.join('\n'),
    () => _build(_fillHeaders),
    headerFooterText: _headersStories.join('\n'),
  ),
  // LibreOffice's text export writes the cached result of the body's PAGE and
  // of the custom field, so its text is the expected text.
  DocxFixture(
    'd4_fields',
    _fieldsText.join('\n'),
    () => _build(_fillFields),
    headerFooterText: _fieldsStories.join('\n'),
  ),
  DocxFixture(
    'd5_pictures',
    _picturesText.join('\n'),
    () => _build(_fillPictures),
    headerFooterText: _picturesStories.join('\n'),
  ),
  DocxFixture(
    'd5_links',
    _linksText.join('\n'),
    () => _build(_fillLinks),
    headerFooterText: _linksStories.join('\n'),
  ),
  DocxFixture('d5_properties', _propertiesText, () => _build(_fillProperties)),
  _listFixture('d6_list', _tr, _trRows(), _trTotals),
  _listFixture('d6_list_landscape', _landscape, _landscapeRows(), null),
  DocxFixture(
    't1_values',
    t1ValuesText.join('\n'),
    () => _filled(t1ValuesTemplate()),
    headerFooterText: _t1ValuesStories.join('\n'),
    expectedWarnings: const <DocxWarningCode, int>{
      DocxWarningCode.templateValueMissing: 1,
    },
  ),
  DocxFixture(
    't1_merge_fields',
    _t1MergeFieldsText.join('\n'),
    () => _filled(t1MergeFieldsTemplate()),
    headerFooterText: '1 header: Teklif\n1 footer: Sayfa altı',
  ),
  DocxFixture(
    't1_merge_fields_template',
    _t1MergeFieldsTemplateText.join('\n'),
    () => DocxDocument.open(t1MergeFieldsTemplate()).save(),
    headerFooterText: '1 header: Teklif\n1 footer: Sayfa altı',
  ),
  DocxFixture(
    't1_template',
    _t1TemplateText.join('\n'),
    () => DocxDocument.open(t1ValuesTemplate()).save(),
    headerFooterText: _t1TemplateStories.join('\n'),
  ),
];

/// The text of `d3_basic`, written by hand from what `_fillBasic` adds: the
/// paragraphs as lines, each row of the table as a line of its cells joined by
/// tabs. Not read from the model, so a cell-text bug cannot hide in it.
final String _basicText = <String>[
  'Before the table.',
  'Name\tQuantity\tPrice',
  'Tea\t2\t3.50',
  'Coffee\t1\t4.25',
  'After the table.',
].join('\n');

/// The text of `d3_merges`, written by hand from the merges of `_fillMerges`
/// (the cell `rRcC` holds the text `rRcC`). A merged cell holds the text of
/// every cell it took, one paragraph each in reading order, so each of those
/// is a line of its own; a cell that continues a vertical merge holds an
/// empty paragraph. Rows:
///
/// - 0: `r0c0 r0c1` across, then `r0c2`, `r0c3`;
/// - 1: `r1c0 r2c0` down, `r1c1`, and `r1c2 r1c3 r2c2 r2c3` as a block;
/// - 2: the continued cell, `r2c1`, the continued block;
/// - 3: `r3c0`, then `r3c1 r3c2 r3c3` across;
/// - 4: `r4c0 r4c1 r5c0 r5c1` as a block, `r4c2`, `r4c3`;
/// - 5: the continued block (empty), `r5c2`, `r5c3`.
final String _mergesText = <String>[
  'r0c0',
  'r0c1\tr0c2\tr0c3',
  'r1c0',
  'r2c0\tr1c1\tr1c2',
  'r1c3',
  'r2c2',
  'r2c3',
  '\tr2c1\t',
  'r3c0\tr3c1',
  'r3c2',
  'r3c3',
  'r4c0',
  'r4c1',
  'r5c0',
  'r5c1\tr4c2\tr4c3',
  '\tr5c2\tr5c3',
  'After the merges.',
].join('\n');

/// A D3 fixture: built by [fill], whose expected text is [expectedText] when
/// given, else what `docxFullText` reads from the saved file (tables as lines
/// of cells joined by tabs).
DocxFixture _tableFixture(
  String name,
  void Function(DocxDocument doc) fill, {
  String? expectedText,
  String? libreOfficeTextSkip,
}) => DocxFixture(
  name,
  expectedText ?? docxFullText(DocxDocument.open(_build(fill).bytes)),
  () => _build(fill),
  libreOfficeTextSkip: libreOfficeTextSkip,
);

/// A new document whose body holds what [fill] adds in place of its one
/// empty paragraph, saved.
DocxResult _build(void Function(DocxDocument doc) fill) {
  final DocxDocument doc = DocxDocument();
  doc.body.removeBlockAt(0);
  fill(doc);
  return doc.save();
}

/// The paragraphs of `d2_run_formatting`: one run each, whose text names
/// the property it sets, and what sets it.
final List<(String, void Function(DocxRunProperties))>
_runFormatting = <(String, void Function(DocxRunProperties))>[
  ('Bold', (DocxRunProperties p) => p.bold = true),
  ('Italic', (DocxRunProperties p) => p.italic = true),
  (
    'Underline double red',
    (DocxRunProperties p) => p.underline = DocxUnderline(
      DocxUnderlineStyle.double,
      color: DocxColor.rgb('FF0000'),
    ),
  ),
  (
    'Underline words',
    (DocxRunProperties p) {
      p.underline = const DocxUnderline(DocxUnderlineStyle.words);
    },
  ),
  ('Strike', (DocxRunProperties p) => p.strike = true),
  ('Double strike', (DocxRunProperties p) => p.doubleStrike = true),
  ('Caps', (DocxRunProperties p) => p.caps = true),
  ('Small caps', (DocxRunProperties p) => p.smallCaps = true),
  ('Color 2E7D32', (DocxRunProperties p) => p.color = DocxColor.rgb('2E7D32')),
  (
    // A theme colour is written with w:val="auto" beside its theme
    // attributes, which the Open XML SDK has to accept.
    'Color theme accent1 shade',
    (DocxRunProperties p) =>
        p.color = DocxColor.theme(DocxThemeColor.accent1, shade: 191),
  ),
  ('Color auto', (DocxRunProperties p) => p.color = DocxColor.auto),
  ('Fonts Arial', (DocxRunProperties p) => p.fonts = DocxFonts.all('Arial')),
  ('Size 18', (DocxRunProperties p) => p.sizePt = 18),
  ('Size 9.5', (DocxRunProperties p) => p.sizePt = 9.5),
  (
    'Spacing expanded 2',
    (DocxRunProperties p) {
      p.characterSpacingPt = 2;
    },
  ),
  (
    'Spacing condensed 1',
    (DocxRunProperties p) {
      p.characterSpacingPt = -1;
    },
  ),
  (
    'Highlight yellow',
    (DocxRunProperties p) => p.highlight = DocxHighlight.yellow,
  ),
  (
    'Shading fill',
    (DocxRunProperties p) => p.shading = DocxShading(
      pattern: DocxShadingPattern.clear,
      fill: DocxColor.rgb('D9EAD3'),
    ),
  ),
  (
    'Subscript',
    (DocxRunProperties p) => p.verticalAlign = DocxVerticalAlign.subscript,
  ),
  (
    'Superscript',
    (DocxRunProperties p) => p.verticalAlign = DocxVerticalAlign.superscript,
  ),
  ('Language de-DE', (DocxRunProperties p) => p.language = 'de-DE'),
];

/// The paragraphs of `d2_paragraph_formatting`: the text names the
/// property, and what sets it.
final List<(String, void Function(DocxParagraphProperties))>
_paragraphFormatting = <(String, void Function(DocxParagraphProperties))>[
  // First, because LibreOffice's re-save writes a page break before a
  // paragraph as a break at the end of the paragraph before it, which the
  // model reads as a line break there and so changes the text compared.
  (
    'Page break before',
    (DocxParagraphProperties p) {
      p.pageBreakBefore = true;
    },
  ),
  (
    'Alignment center',
    (DocxParagraphProperties p) {
      p.alignment = DocxAlignment.center;
    },
  ),
  (
    'Alignment right',
    (DocxParagraphProperties p) {
      p.alignment = DocxAlignment.right;
    },
  ),
  (
    'Alignment justify',
    (DocxParagraphProperties p) {
      p.alignment = DocxAlignment.justify;
    },
  ),
  (
    'Indentation left 36 and right 18, first line 18',
    (DocxParagraphProperties p) {
      p.indentation = DocxIndentation(leftPt: 36, rightPt: 18, firstLinePt: 18);
    },
  ),
  (
    'Indentation left 54, hanging 27',
    (DocxParagraphProperties p) {
      p.indentation = DocxIndentation(leftPt: 54, hangingPt: 27);
    },
  ),
  (
    'Spacing before 12 after 6, line 1.5',
    (DocxParagraphProperties p) {
      p.spacing = DocxSpacing(
        beforePt: 12,
        afterPt: 6,
        line: DocxLineSpacing.multiple(1.5),
      );
    },
  ),
  (
    'Spacing line exactly 20',
    (DocxParagraphProperties p) {
      p.spacing = DocxSpacing(line: DocxLineSpacing.exactly(20));
    },
  ),
  (
    'Spacing line at least 16',
    (DocxParagraphProperties p) {
      p.spacing = DocxSpacing(line: DocxLineSpacing.atLeast(16));
    },
  ),
  ('Keep with next', (DocxParagraphProperties p) => p.keepWithNext = true),
  ('Keep lines together', (DocxParagraphProperties p) => p.keepLines = true),
  ('Widow control off', (DocxParagraphProperties p) => p.widowControl = false),
  ('Outline level 2', (DocxParagraphProperties p) => p.outlineLevel = 1),
  (
    'Borders: a red box and a rule between',
    (DocxParagraphProperties p) {
      final DocxBorder box = DocxBorder(
        widthPt: 1,
        spacePt: 4,
        color: DocxColor.rgb('C00000'),
      );
      p.borders = DocxParagraphBorders(
        top: box,
        left: box,
        bottom: DocxBorder(style: DocxBorderStyle.double, widthPt: 1.5),
        right: box,
        between: DocxBorder(style: DocxBorderStyle.dashed),
      );
    },
  ),
  (
    'Shading: a pale yellow fill',
    (DocxParagraphProperties p) {
      p.shading = DocxShading(fill: DocxColor.rgb('FFF2CC'));
    },
  ),
  (
    'Tab stops:\tleft\tcenter\tright',
    (DocxParagraphProperties p) {
      p.tabs = <DocxTabStop>[
        DocxTabStop(72),
        DocxTabStop(216, alignment: DocxTabAlignment.center),
        DocxTabStop(
          432,
          alignment: DocxTabAlignment.right,
          leader: DocxTabLeader.dot,
        ),
      ];
    },
  ),
];

/// The paragraphs of `d2_styles`, in order.
const List<String> _styleTexts = <String>[
  'A title',
  'A subtitle',
  'A first-level heading',
  'A second-level heading',
  'A third-level heading',
  'A quotation',
  'A note in the custom style',
  'Code in a character style',
  'Strong and emphasis',
];

/// Fills `d2_styles`: the built-ins, a custom paragraph style `Note`, a
/// custom character style `Code`, a document default size, and every other
/// built-in of the catalog, so that the Open XML SDK and Word see each.
void _fillStyles(DocxDocument doc) {
  final DocxStyles styles = doc.styles;
  styles.defaults.runProperties.sizePt = 11;
  styles.add(
    DocxStyle(
        type: DocxStyleType.paragraph,
        id: 'Note',
        name: 'Note',
        basedOn: 'Normal',
        next: 'Normal',
        uiPriority: 20,
        quickFormat: true,
      )
      ..paragraphProperties.indentation = DocxIndentation(leftPt: 18)
      ..paragraphProperties.borders = DocxParagraphBorders(
        left: DocxBorder(widthPt: 2.25, spacePt: 6),
      )
      ..runProperties.italic = true
      ..runProperties.color = DocxColor.rgb('595959'),
  );
  styles.add(
    DocxStyle(type: DocxStyleType.character, id: 'Code', name: 'Code')
      ..runProperties.fonts = DocxFonts.all('Courier New')
      ..runProperties.sizePt = 10
      ..runProperties.shading = DocxShading(fill: DocxColor.rgb('EEEEEE')),
  );
  // Every entry of the catalog, so that the SDK and Word see each.
  DocxBuiltInStyle.values.forEach(styles.ensure);
  void paragraph(String text, String style) {
    doc.body.addParagraph(text).style = style;
  }

  paragraph(_styleTexts[0], styles.ensure(DocxBuiltInStyle.title));
  paragraph(_styleTexts[1], styles.ensure(DocxBuiltInStyle.subtitle));
  paragraph(_styleTexts[2], styles.ensure(DocxBuiltInStyle.heading1));
  paragraph(_styleTexts[3], styles.ensure(DocxBuiltInStyle.heading2));
  paragraph(_styleTexts[4], styles.ensure(DocxBuiltInStyle.heading3));
  paragraph(_styleTexts[5], styles.ensure(DocxBuiltInStyle.quote));
  paragraph(_styleTexts[6], 'Note');
  final DocxParagraph code = doc.body.addParagraph();
  code.addRun('Code ').style = 'Code';
  code.addRun('in a character style');
  final DocxParagraph strong = doc.body.addParagraph();
  strong.addRun('Strong').style = styles.idOf(DocxBuiltInStyle.strong);
  strong.addRun(' and ');
  strong.addRun('emphasis').style = styles.idOf(DocxBuiltInStyle.emphasis);
}

/// The text of `d2_lists`, as the model reads it: no labels.
const List<String> _listTexts = <String>[
  'Bullets:',
  'Bullet one',
  'Bullet one, nested',
  'Bullet two',
  'Numbers:',
  'Num one',
  'Num one, nested',
  'Num two',
  'Restarted numbers:',
  'Restarted one',
  'Restarted two',
];

/// What LibreOffice's text export writes for `d2_lists`, pinned from a
/// LibreOffice 26.8 run: its list labels before the text of each item,
/// indented four spaces a level. It writes `•` for the Symbol bullet
/// U+F0B7 of level 0 and `◦` for the `o` of level 1.
const List<String> _listLibreOfficeTexts = <String>[
  'Bullets:',
  '    \u2022 Bullet one',
  '        \u25E6 Bullet one, nested',
  '    \u2022 Bullet two',
  'Numbers:',
  '    1. Num one',
  '        a. Num one, nested',
  '    2. Num two',
  'Restarted numbers:',
  '    1. Restarted one',
  '    2. Restarted two',
];

/// Fills `d2_lists`: a two-level bullet list, a two-level numbered list and
/// a second instance of the numbered list that starts again at 1.
void _fillLists(DocxDocument doc) {
  final DocxBody body = doc.body;
  body.addParagraph(_listTexts[0]);
  final DocxNumberingInstance bullets = doc.numbering.addBulletList();
  body.addListItem(bullets, _listTexts[1]);
  body.addListItem(bullets, _listTexts[2], level: 1);
  body.addListItem(bullets, _listTexts[3]);
  body.addParagraph(_listTexts[4]);
  final DocxNumberingInstance numbers = doc.numbering.addNumberedList();
  body.addListItem(numbers, _listTexts[5]);
  body.addListItem(numbers, _listTexts[6], level: 1);
  body.addListItem(numbers, _listTexts[7]);
  body.addParagraph(_listTexts[8]);
  final DocxNumberingInstance restarted = doc.numbering.addInstance(
    numbers.abstractNumbering!,
    startOverrides: const <int, int>{0: 1},
  );
  body.addListItem(restarted, _listTexts[9]);
  body.addListItem(restarted, _listTexts[10]);
}

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

/// Fills `d3_basic`: text, a 3 by 3 table in `Table Grid`, text.
void _fillBasic(DocxDocument doc) {
  doc.body.addParagraph('Before the table.');
  final DocxTable table = doc.body.addTable(columns: 3);
  table.addRow(<String?>['Name', 'Quantity', 'Price'], header: true);
  table.addRow(<String?>['Tea', '2', '3.50']);
  table.addRow(<String?>['Coffee', '1', '4.25']);
  doc.body.addParagraph('After the table.');
}

/// Fills `d3_header_row`: 120 rows over several pages under a repeating
/// header, no row split across pages and one row of an exact height.
void _fillHeaderRow(DocxDocument doc) {
  doc.body.addParagraph('A long table.');
  final DocxTable table = doc.body.addTable(columns: 3);
  table.addRow(<String?>['Number', 'Square', 'Text'], header: true);
  for (int i = 1; i <= 120; i++) {
    final DocxTableRow row = table.addRow(<String?>[
      '$i',
      '${i * i}',
      'Row $i of 120',
    ]);
    row.properties.cantSplit = true;
    if (i == 3) {
      row.properties.height = DocxRowHeight(36, rule: DocxRowHeightRule.exact);
    }
  }
  doc.body.addParagraph('The end.');
}

/// Fills `d3_merges`: each shape of merge, in a table of four columns.
void _fillMerges(DocxDocument doc) {
  final DocxTable table = doc.body.addTable(columns: 4);
  for (int r = 0; r < 6; r++) {
    table.addRow(<String?>[for (int c = 0; c < 4; c++) 'r${r}c$c']);
  }
  void merge(int r0, int c0, int r1, int c1) => table.mergeCells(
    firstRow: r0,
    firstColumn: c0,
    lastRow: r1,
    lastColumn: c1,
  );
  merge(0, 0, 0, 1); // across
  merge(1, 0, 2, 0); // down
  merge(1, 2, 2, 3); // a block
  merge(3, 1, 3, 3); // across three
  merge(4, 0, 5, 1); // a block at the edge
  doc.body.addParagraph('After the merges.');
}

/// Fills `d3_formatting`: a table with the properties of the table, its rows
/// and its cells that LibreOffice and the Open XML SDK should accept.
void _fillFormatting(DocxDocument doc) {
  final DocxTable table = doc.body.addTable(
    columns: 3,
    columnWidthsPt: <double>[100, 150, 200],
  );
  final DocxBorder box = DocxBorder(widthPt: 1, color: DocxColor.rgb('1F4E79'));
  table.properties
    ..layout = DocxTableLayout.fixed
    ..width = DocxTableWidth.points(450)
    ..alignment = DocxTableAlignment.center
    ..indentationPt = 12
    ..borders = DocxTableBorders(
      top: box,
      left: box,
      bottom: box,
      right: box,
      insideHorizontal: DocxBorder(style: DocxBorderStyle.dashed),
      insideVertical: DocxBorder(style: DocxBorderStyle.dotted),
    )
    ..cellMargins = DocxTableMargins(
      topPt: 2,
      leftPt: 6,
      bottomPt: 2,
      rightPt: 6,
    )
    ..look = const DocxTableLook(
      firstRow: true,
      noHorizontalBands: true,
      noVerticalBands: true,
    );
  table.addRow(<String?>['Top', 'Center', 'Bottom'], header: true);
  table.addRow(<String?>['Shaded', 'Vertical text', 'Bordered']);
  final DocxTableRow tall = table.addRow(<String?>['High', 'High', 'High']);
  tall.properties.height = DocxRowHeight(48);
  table.addRow(<String?>['Splits', 'Splits', 'Splits']).properties
    ..cantSplit = false
    ..repeatAsHeader = false;
  final DocxTableRow first = table.rows[0];
  first.cells[0].properties.verticalAlignment = DocxCellVerticalAlignment.top;
  first.cells[1].properties.verticalAlignment =
      DocxCellVerticalAlignment.center;
  first.cells[2].properties.verticalAlignment =
      DocxCellVerticalAlignment.bottom;
  final DocxTableRow second = table.rows[1];
  second.cells[0].properties.shading = DocxShading(
    fill: DocxColor.rgb('FFF2CC'),
  );
  second.cells[1].properties.textDirection =
      DocxTextDirection.bottomToTopLeftToRight;
  second.cells[2].properties.borders = DocxCellBorders(
    top: DocxBorder(style: DocxBorderStyle.double, widthPt: 1.5),
    bottom: DocxBorder(widthPt: 2.25, color: DocxColor.rgb('C00000')),
  );
  for (final DocxTableCell cell in tall.cells) {
    cell.properties.verticalAlignment = DocxCellVerticalAlignment.center;
  }
  doc.body.addParagraph('After the formatted table.');
}

/// Fills `d3_nested`: a nested table, a list in a cell, a cell whose last
/// block is a table, and a second table in the body.
void _fillNested(DocxDocument doc) {
  doc.body.addParagraph('Tables in tables.');
  final DocxTable outer = doc.body.addTable(columns: 2);
  outer.addRow(<String?>['Outer one', 'Outer two']);
  outer.addRow(<String?>['Holds a table', 'Holds a list']);
  outer.addRow(<String?>['Ends in a table', 'Plain']);

  final DocxTableCell host = outer.rows[1].cells[0];
  final DocxTable inner = host.addTable(columns: 2);
  inner.addRow(<String?>['Inner a', 'Inner b']);
  inner.addRow(<String?>['Inner c', 'Inner d']);

  final DocxTableCell listCell = outer.rows[1].cells[1];
  final DocxNumberingInstance bullets = doc.numbering.addBulletList();
  final String listStyle = doc.styles.ensure(DocxBuiltInStyle.listParagraph);
  for (final String item in <String>['First item', 'Second item']) {
    final DocxParagraph p = listCell.addParagraph(item);
    p.style = listStyle;
    p.properties.numbering = bullets.ref();
  }

  final DocxTableCell last = outer.rows[2].cells[0];
  final DocxTable tail = last.addTable(columns: 1);
  tail.addRow(<String?>['Last in the cell']);

  // Not a table last in the body: LibreOffice's text export never ends on a
  // document whose body ends in a table (it writes the file without bound),
  // so the fixtures the CI job converts all end in a paragraph. A body that
  // ends in a table is covered by `round_trip_test.dart` and the Word check.
  doc.body.addParagraph('After the tables.');
}

/// The text of `d4_sections`, written by hand from what `_fillSections` adds.
const List<String> _sectionsText = <String>[
  'Portrait, with wide margins, its pages numbered from 5.',
  'Its lines are numbered and it sits in the middle of the page.',
  'Landscape, in two columns with a line between them.',
  'The second paragraph of the columns.',
  'Continuous: this section starts on the same page, in one column.',
  'Letter, on a page of its own.',
  'Name\tValue',
  'Width\tThe text width less 10 twips',
  'After the table.',
];

/// Fills `d4_sections`: four sections, each changing what the one before it
/// left for it to copy.
void _fillSections(DocxDocument doc) {
  final DocxBody body = doc.body;
  doc.sections.last
    ..pageSize = DocxPageSize.a4()
    ..margins = _margins(108, gutter: 18)
    ..pageNumbering = DocxPageNumbering(start: 5)
    ..lineNumbering = DocxLineNumbering(
      countBy: 1,
      restart: DocxLineNumberRestart.newSection,
    )
    ..verticalAlignment = DocxSectionVerticalAlignment.center;
  body.addParagraph(_sectionsText[0]);
  body.addParagraph(_sectionsText[1]);
  body.addSection()
    ..pageSize = DocxPageSize.a4(landscape: true)
    ..margins = _margins(72)
    ..columns = DocxColumns(count: 2, separator: true)
    ..lineNumbering = null
    ..verticalAlignment = null;
  body.addParagraph(_sectionsText[2]);
  body.addParagraph(_sectionsText[3]);
  body.addSection(start: DocxSectionStart.continuous).columns = DocxColumns();
  body.addParagraph(_sectionsText[4]);
  body.addSection().pageSize = DocxPageSize.letter();
  body.addParagraph(_sectionsText[5]);
  body.addTable(columns: 2)
    ..addRow(<String?>['Name', 'Value'], header: true)
    ..addRow(<String?>['Width', 'The text width less 10 twips']);
  body.addParagraph(_sectionsText[8]);
}

/// Margins of [side] points on the four sides, with the header and footer at
/// half an inch.
DocxPageMargins _margins(double side, {double gutter = 0}) => DocxPageMargins(
  top: side,
  right: side,
  bottom: side,
  left: side,
  header: 36,
  footer: 36,
  gutter: gutter,
);

/// The text of `d4_headers`, written by hand from what `_fillHeaders` adds.
const List<String> _headersText = <String>[
  'Page one of section one: the first page stories.',
  'Page two of section one: the even stories.',
  'Page three of section one: the default stories.',
  'Section two inherits the stories of section one.',
  'Section three has its own header and footer.',
];

/// What the sections of `d4_headers` show: section one all six, section two
/// what it inherits but the first page's, as it has no title page, and section
/// three its own default stories and the even ones of section one.
const List<String> _headersStories = <String>[
  '1 header: Header one',
  '1 first header: First header one',
  '1 even header: Even header one',
  '1 footer: Footer one',
  '1 first footer: First footer one',
  '1 even footer: Even footer one',
  '2 header: Header one',
  '2 even header: Even header one',
  '2 footer: Footer one',
  '2 even footer: Even footer one',
  '3 header: Header three',
  '3 even header: Even header one',
  '3 footer: Footer three',
  '3 even footer: Even footer one',
];

/// Fills `d4_headers`: a first, an even and a default story of each kind in
/// section one, whose three pages show all three, then a section with none
/// of its own and a section with its own default ones.
void _fillHeaders(DocxDocument doc) {
  final DocxBody body = doc.body;
  final DocxSection one = doc.sections.last;
  one.header.addParagraph('Header one');
  one.firstHeader.addParagraph('First header one');
  one.evenHeader.addParagraph('Even header one');
  one.footer.addParagraph('Footer one');
  one.firstFooter.addParagraph('First footer one');
  one.evenFooter.addParagraph('Even footer one');
  body.addParagraph(_headersText[0]);
  body.addParagraph(_headersText[1]).properties.pageBreakBefore = true;
  body.addParagraph(_headersText[2]).properties.pageBreakBefore = true;
  body.addSection();
  body.addParagraph(_headersText[3]);
  final DocxSection three = body.addSection();
  three.ownHeader(DocxHeaderFooterType.primary).addParagraph('Header three');
  three.ownFooter(DocxHeaderFooterType.primary).addParagraph('Footer three');
  body.addParagraph(_headersText[4]);
}

/// The text of `d4_fields`, written by hand from what `_fillFields` adds: a
/// field's text is its cached result.
const List<String> _fieldsText = <String>[
  'This is page 1.',
  'A field the model has no helper for: Custom text.',
];

/// What the footer of `d4_fields` shows, each field by its name.
const List<String> _fieldsStories = <String>[
  '1 footer: Page {PAGE} of {NUMPAGES}, section pages: {SECTIONPAGES}',
  '1 footer: Printed on {DATE} at {TIME}',
];

/// Fills `d4_fields`: `PAGE`, `NUMPAGES` and `SECTIONPAGES` in the footer, and
/// `DATE` and `TIME` there with no result, which Word computes when it opens
/// the file; `PAGE` and a custom field in the body.
void _fillFields(DocxDocument doc) {
  final DocxHeaderFooter footer = doc.sections.last.footer;
  footer.addParagraph('Page ')
    ..addField(DocxField.page())
    ..addRun(' of ')
    ..addField(DocxField.numPages())
    ..addRun(', section pages: ')
    ..addField(DocxField.sectionPages());
  footer.addParagraph('Printed on ')
    ..addField(DocxField.date())
    ..addRun(' at ')
    ..addField(DocxField.time());
  doc.body.addParagraph('This is page ')
    ..addField(DocxField.page())
    ..addRun('.');
  doc.body.addParagraph('A field the model has no helper for: ')
    ..addField(DocxField(' QUOTE "Custom text" ', result: 'Custom text'))
    ..addRun('.');
}

/// The text of `d5_pictures`, written by hand from what `_fillPictures` adds:
/// a picture has no text, so a paragraph that holds only one is an empty line.
const List<String> _picturesText = <String>[
  'A PNG at its pixel size, 4 by 2 pixels, follows.',
  '',
  'Kind\tPicture',
  'JPEG, 144 points wide\tThe JPEG, 3 by 5 pixels',
  'After the pictures.',
];

/// What the header of `d5_pictures` shows: the logo has no text.
const List<String> _picturesStories = <String>[
  '1 header: Logo beside the header text',
];

/// Fills `d5_pictures`: the PNG [png4x2] in the body at its pixel size, the
/// JPEG [jpeg3x5] 144 points wide (240 high, its ratio kept) in a table cell,
/// and the same PNG as a logo in the header, beside text, which shares the
/// body's media part.
void _fillPictures(DocxDocument doc) {
  final DocxBody body = doc.body;
  body.addParagraph(_picturesText[0]);
  body.addParagraph().addPicture(
    OfficeImage(png4x2),
    name: 'PNG',
    description: 'A PNG of 4 by 2 pixels',
  );
  final DocxTable table = body.addTable(columns: 2)
    ..addRow(<String?>['Kind', 'Picture'], header: true)
    ..addRow(<String?>['JPEG, 144 points wide', null]);
  // `addRow` gives the cell one empty paragraph: the picture goes there,
  // followed by its caption.
  (table.rows[1].cells[1].blocks.single as DocxParagraph)
    ..addPicture(OfficeImage(jpeg3x5), widthPt: 144, name: 'JPEG')
    ..addRun('The JPEG, 3 by 5 pixels');
  doc.sections.last.header.addParagraph()
    ..addPicture(OfficeImage(png4x2), name: 'Logo')
    ..addRun('Logo beside the header text');
  body.addParagraph(_picturesText[4]);
}

/// The text of `d5_links`, written by hand from what `_fillLinks` adds: a
/// hyperlink's text is the text of its runs, a bookmark has none.
const List<String> _linksText = <String>[
  'Overview',
  'Visit the project page for more.',
  'Back to the overview.',
  'After the links.',
];

/// What the footer of `d5_links` shows: the text of its link.
const List<String> _linksStories = <String>[
  '1 footer: Footer link: example.com',
];

/// Fills `d5_links`: a heading inside the bookmark `Overview`, an external
/// link, an internal link to the bookmark, and an external link in the footer.
void _fillLinks(DocxDocument doc) {
  final DocxBody body = doc.body;
  final DocxParagraph heading = body.addParagraph()
    ..style = doc.styles.ensure(DocxBuiltInStyle.heading1);
  final DocxBookmarkStart start = heading.addBookmarkStart('Overview');
  heading
    ..addRun(_linksText[0])
    ..addBookmarkEnd(start);
  body.addParagraph('Visit ')
    ..addHyperlink(
      'the project page',
      url: 'https://example.com/jet-office',
      tooltip: 'The project page',
    )
    ..addRun(' for more.');
  body.addParagraph('Back to ')
    ..addHyperlink('the overview', anchor: 'Overview')
    ..addRun('.');
  doc.sections.last.footer
      .addParagraph('Footer link: ')
      .addHyperlink('example.com', url: 'https://example.com/');
  body.addParagraph(_linksText[3]);
}

/// The text of `d5_properties`.
const String _propertiesText = 'This document has its properties set.';

/// The properties of `d5_properties`: every core field, the company and the
/// application, at given UTC times.
final OfficeProperties d5Properties = OfficeProperties(
  title: 'The D5 properties',
  subject: 'Document properties',
  creator: 'jet_office',
  keywords: 'docx; properties; d5',
  description: 'Every core property, the company and the application.',
  lastModifiedBy: 'The fixture list',
  revision: 3,
  category: 'Fixtures',
  contentStatus: 'Final',
  created: DateTime.utc(2026, 11, 8, 9, 30),
  modified: DateTime.utc(2026, 11, 8, 10, 45, 15),
  company: 'Jet Office',
  application: 'jet_office',
);

/// Fills `d5_properties`: one paragraph and [d5Properties].
void _fillProperties(DocxDocument doc) {
  doc.body.addParagraph(_propertiesText);
  doc.properties = d5Properties;
}

/// The Turkish list of `d6_list`: a logo, a title, a date, a caption, five
/// columns (a date, an amount in lira and a share among them), a footer in
/// Turkish. 120 rows run over three A4 portrait pages.
final DocxListExport _tr = DocxListExport(
  const <DocxListColumn>[
    DocxListColumn('Kod', widthPt: 60),
    DocxListColumn('Müşteri'),
    DocxListColumn('Tarih', numberFormat: 'dd.mm.yyyy', widthPt: 70),
    DocxListColumn('Tutar', numberFormat: '#,##0.00 ₺', widthPt: 90),
    DocxListColumn('Pay', numberFormat: '0%', widthPt: 50),
  ],
  title: 'Müşteri listesi',
  logo: OfficeImage(png4x2),
  logoHeightPt: 20,
  date: DateTime(2026, 11, 8),
  caption: 'Kasım 2026 müşteri bakiyeleri',
  footerBefore: 'Sayfa ',
  footerMiddle: ' / ',
  locale: FormatLocale.trTR,
);

/// Names of `d6_list`, with the Turkish letters ç ğ ı İ ö ş ü among them.
const List<String> _trNames = <String>[
  'Çağlar Işık',
  'İpek Özdemir',
  'Gülşen Şahin',
  'Ümit Yıldız',
  'Ömer Çelik',
  'Şükrü Doğan',
];

/// The 120 rows of `d6_list`: a code, a name, a date, an amount and a share.
List<List<Object?>> _trRows() => <List<Object?>>[
  for (int i = 0; i < 120; i++)
    <Object?>[
      'M-${(1001 + i)}',
      _trNames[i % _trNames.length],
      DateTime(2026, 1 + i % 12, 1 + i % 28),
      1234.5 + i * 17.25,
      (i % 20) / 20,
    ],
];

/// The totals row of `d6_list`, given as the caller's own values.
const List<Object?> _trTotals = <Object?>['Toplam', null, null, 271305.0, null];

/// The English landscape list of `d6_list_landscape`: no logo, twelve
/// columns with a width for four, 1.27 cm (36 points) margins all round.
final DocxListExport _landscape = DocxListExport(
  <DocxListColumn>[
    const DocxListColumn('Code', widthPt: 50),
    const DocxListColumn('Name', widthPt: 90),
    const DocxListColumn('Started', numberFormat: 'yyyy-mm-dd', widthPt: 60),
    const DocxListColumn('Amount', numberFormat: '#,##0.00', widthPt: 70),
    for (int c = 1; c <= 8; c++)
      DocxListColumn('Month $c', numberFormat: '0.0'),
  ],
  title: 'Monthly figures',
  date: DateTime(2026, 11, 8),
  pageSize: DocxPageSize.a4(landscape: true),
  margins: DocxPageMargins(
    top: 36,
    right: 36,
    bottom: 36,
    left: 36,
    header: 35.4,
    footer: 35.4,
    gutter: 0,
  ),
);

/// The 40 rows of `d6_list_landscape`.
List<List<Object?>> _landscapeRows() => <List<Object?>>[
  for (int i = 0; i < 40; i++)
    <Object?>[
      'C${100 + i}',
      'Item ${i + 1}',
      DateTime(2026, 1 + i % 12, 1 + i % 28),
      10.5 + i * 1000.25,
      for (int c = 0; c < 8; c++) (i + 1) * (c + 1) / 4,
    ],
];

/// A D6 fixture: [export] written with [rows] and [totals]. Its expected
/// text is what the cells show, as the model reads them; its stories are the
/// header and footer, as `docxStoriesText` reads them.
DocxFixture _listFixture(
  String name,
  DocxListExport export,
  List<List<Object?>> rows,
  List<Object?>? totals,
) {
  DocxResult build() => export.toDocx(rows, totals: totals);
  final DocxDocument doc = DocxDocument.open(build().bytes);
  return DocxFixture(
    name,
    docxFullText(doc),
    build,
    headerFooterText: docxStoriesText(doc),
  );
}

/// [template] filled with `fillDocxData()` in Turkish, as
/// `tool/fill_docx.dart` fills every document.
DocxResult _filled(Uint8List template) => DocxTemplate(template).fill(
  fillDocxData(),
  options: const DocxTemplateOptions(locale: FormatLocale.trTR),
);

/// The format of the date tags of `t1_values`.
const String _t1Date = '{{tarih:dd.mm.yyyy}}';

/// The format of the amount tags of `t1_values`.
const String _t1Amount = '{{tutar:#,##0.00 ₺}}';

/// A paragraph of [inner] runs.
String _p(String inner) => templateParagraph(inner);

/// A table cell of one paragraph of [inner] runs, 4536 twentieths wide.
String _tc(String inner) =>
    '<w:tc><w:tcPr><w:tcW w:w="4536" w:type="dxa"/></w:tcPr>${_p(inner)}'
    '</w:tc>';

/// The template of `t1_values` and `t1_template`, as Word for Mac writes it:
/// `{{firma.unvan}}` split over runs with its first brace bold, a date and an
/// amount tag with a format, each split after its name, a coloured
/// `{{musteri.ad}}` split at its dot, a table of three rows of two cells with
/// a tag in each, the missing `{{yok}}`, and a header and a footer with a tag.
/// The body ends in a paragraph.
Uint8List t1ValuesTemplate() {
  const String red = '<w:color w:val="C00000"/>';
  return templateWithStories(
    body: <String>[
      _p(
        templateRun('Firma: ') +
            wordSplitTag('{{firma.unvan}}', boldFirstBrace: true),
      ),
      _p(templateRun('Adres: {{firma.adres}}')),
      _p(
        templateRun('Tarih: ') +
            templateRun('{{tarih') +
            templateRun(':dd.mm.yyyy}}'),
      ),
      _p(
        templateRun('Tutar: ') +
            templateRun('{{tutar') +
            templateRun(':#,##0.00 ₺}}'),
      ),
      _p(
        templateRun('Müşteri: ') +
            templateRun('{{musteri', rPr: red) +
            templateRun('.ad}}', rPr: red),
      ),
      _p(templateRun('Miktar: {{miktar}}')),
      '<w:tbl><w:tblPr><w:tblW w:w="9072" w:type="dxa"/></w:tblPr>'
          '<w:tblGrid><w:gridCol w:w="4536"/><w:gridCol w:w="4536"/>'
          '</w:tblGrid>'
          '<w:tr>${_tc(templateRun('{{firma.unvan}}'))}'
          '${_tc(templateRun('{{musteri.ad}}'))}</w:tr>'
          '<w:tr>${_tc(templateRun(_t1Date))}'
          '${_tc(templateRun(_t1Amount))}</w:tr>'
          '<w:tr>${_tc(templateRun('{{miktar}}'))}'
          '${_tc(templateRun('{{firma.adres}}'))}</w:tr></w:tbl>',
      _p(templateRun('Eksik: {{yok}}')),
      _p(templateRun('Saygılarımızla.')),
    ].join(),
    header: _p(
      templateRun('Teklif: ') +
          templateRun('{{firma') +
          templateRun('.unvan}}'),
    ),
    footer: _p(templateRun('Tarih: ') + templateRun(_t1Date)),
  );
}

/// The text of `t1_values`, written by hand from `fillDocxData()` in Turkish:
/// the date as `dd.mm.yyyy`, the amount with Turkish separators, `2,5` for
/// `miktar` in General, and `{{yok}}`, which the data lacks, as written.
const List<String> t1ValuesText = <String>[
  'Firma: Acme A.Ş.',
  'Adres: Atatürk Bulvarı No: 1, Çankaya / Ankara',
  'Tarih: 14.11.2026',
  'Tutar: 1.234,56 ₺',
  'Müşteri: Ayşe Yılmaz',
  'Miktar: 2,5',
  'Acme A.Ş.\tAyşe Yılmaz',
  '14.11.2026\t1.234,56 ₺',
  '2,5\tAtatürk Bulvarı No: 1, Çankaya / Ankara',
  'Eksik: {{yok}}',
  'Saygılarımızla.',
];

/// What the header and footer of `t1_values` show, filled.
const List<String> _t1ValuesStories = <String>[
  '1 header: Teklif: Acme A.Ş.',
  '1 footer: Tarih: 14.11.2026',
];

/// The text of `t1_template`: the tags as written.
const List<String> _t1TemplateText = <String>[
  'Firma: {{firma.unvan}}',
  'Adres: {{firma.adres}}',
  'Tarih: $_t1Date',
  'Tutar: $_t1Amount',
  'Müşteri: {{musteri.ad}}',
  'Miktar: {{miktar}}',
  '{{firma.unvan}}\t{{musteri.ad}}',
  '$_t1Date\t$_t1Amount',
  '{{miktar}}\t{{firma.adres}}',
  'Eksik: {{yok}}',
  'Saygılarımızla.',
];

/// What the header and footer of `t1_template` show: the tags as written.
const List<String> _t1TemplateStories = <String>[
  '1 header: Teklif: {{firma.unvan}}',
  '1 footer: Tarih: $_t1Date',
];

/// The template of `t1_merge_fields`, as Word writes merge fields: complex
/// `MERGEFIELD`s with a text before and after (`\b`, `\f`), a casing (`\*
/// Upper` beside `\* MERGEFORMAT`) and a date picture (`\@`), a `w:fldSimple`,
/// and a field inside a sentence. The body ends in a paragraph.
Uint8List t1MergeFieldsTemplate() => templateWithStories(
  body: <String>[
    _p(complexMergeField(' MERGEFIELD Ad \\b "Sayın " \\f "," ', '«Ad»')),
    _p(
      templateRun('Müşteri: ') +
          complexMergeField(
            ' MERGEFIELD "Müşteri Adı" \\* Upper \\* MERGEFORMAT ',
            '«Müşteri Adı»',
          ),
    ),
    _p(
      templateRun('Tarih: ') +
          complexMergeField(' MERGEFIELD Tarih \\@ "dd.MM.yyyy" ', '«Tarih»'),
    ),
    _p(
      templateRun('Eski alan: ') + simpleMergeField(' MERGEFIELD Ad ', '«Ad»'),
    ),
    _p(
      templateRun('Değerli ') +
          complexMergeField(' MERGEFIELD Ad ', '«Ad»') +
          templateRun(', teklifimiz ektedir.'),
    ),
    _p(templateRun('Saygılarımızla.')),
  ].join(),
  header: _p(templateRun('Teklif')),
  footer: _p(templateRun('Sayfa altı')),
);

/// The text of `t1_merge_fields`, written by hand from `fillDocxData()`.
const List<String> _t1MergeFieldsText = <String>[
  'Sayın Ayşe,',
  'Müşteri: AYŞE YILMAZ',
  'Tarih: 14.11.2026',
  'Eski alan: Ayşe',
  'Değerli Ayşe, teklifimiz ektedir.',
  'Saygılarımızla.',
];

/// The text of `t1_merge_fields_template`: each field's cached result, as
/// Word writes it (`«Ad»`).
const List<String> _t1MergeFieldsTemplateText = <String>[
  '«Ad»',
  'Müşteri: «Müşteri Adı»',
  'Tarih: «Tarih»',
  'Eski alan: «Ad»',
  'Değerli «Ad», teklifimiz ektedir.',
  'Saygılarımızla.',
];
