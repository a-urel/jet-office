/// The fixtures of DOCX milestones D1, D2 and D3: new documents with
/// paragraphs of text (D1), with run and paragraph formatting, styles and
/// lists (D2) and with tables (D3).
///
/// New in jet_office. Every fixture starts from `DocxDocument()`, the blank
/// document, so what LibreOffice and the Open XML SDK see is what the model
/// writes. `tool/write_fixtures.dart` writes each as `<name>.docx` with its
/// `<name>.expected.txt`; `test/docx/round_trip_test.dart` checks them.
library;

import 'package:jet_office/jet_office.dart';

import '../../tool/src/text_compare.dart' show docxFullText;
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

/// The fixtures of D1, D2 and D3, in a fixed order.
///
/// No fixture may end in a table: LibreOffice's text export of a document
/// whose body ends in a table never ends, it writes the file without bound
/// (the model adds no paragraph after a last table), and the CI job converts
/// every fixture. End the body in a paragraph.
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
  _tableFixture('d3_basic', _fillBasic),
  _tableFixture('d3_header_row', _fillHeaderRow),
  _tableFixture('d3_merges', _fillMerges),
  _tableFixture('d3_formatting', _fillFormatting),
  _tableFixture(
    'd3_nested',
    _fillNested,
    libreOfficeTextSkip:
        'LibreOffice repeats a paragraph in the text of nested tables; '
        'differs by version',
  ),
];

/// A D3 fixture: built by [fill], whose expected text is what `docxFullText`
/// reads from the saved file (tables as lines of cells joined by tabs).
DocxFixture _tableFixture(
  String name,
  void Function(DocxDocument doc) fill, {
  String? libreOfficeTextSkip,
}) => DocxFixture(
  name,
  docxFullText(DocxDocument.open(_build(fill).bytes)),
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
  final DocxTableRow first = table.rows[0];
  first.cells[0].properties.verticalAlignment = DocxCellAlignment.top;
  first.cells[1].properties.verticalAlignment = DocxCellAlignment.center;
  first.cells[2].properties.verticalAlignment = DocxCellAlignment.bottom;
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
    cell.properties.verticalAlignment = DocxCellAlignment.center;
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
