/// Compares the text of a document with an expected text, line by line.
///
/// New in jet_office; the DOCX counterpart of `csv_compare.dart`. Web-safe
/// (no `dart:io`), so its tests run in a browser too.
///
/// The contract, shared by `tool/compare_text.dart` (LibreOffice's text
/// export), `tool/compare_resaved_docx.dart` (LibreOffice's re-save, read
/// back by the model) and the owner files' test:
///
/// * a document's text is [docxBodyText]: the [DocxParagraph.text] of each
///   paragraph of the body, joined by `\n`; tables and opaque blocks are
///   left out;
/// * a re-save is read by [docxResavedText], as LibreOffice ends a section and
///   a page otherwise than the fixture did;
/// * what the headers and footers show is [docxStoriesText];
/// * a text file, expected or exported, is read by [readExpectedText]: a
///   leading BOM and one trailing `\n` are dropped, because LibreOffice
///   starts its export with a BOM and ends every paragraph with `\n`;
/// * everything else must be equal: edge and double spaces, tabs, empty
///   lines and every character.
library;

import 'package:jet_office/jet_office.dart';

/// The text of [doc]'s body: each paragraph's [DocxParagraph.text], joined
/// by `\n`. Blocks other than paragraphs are left out.
String docxBodyText(DocxDocument doc) => <String>[
  for (final DocxBlock block in doc.body.blocks)
    if (block is DocxParagraph) block.text,
].join('\n');

/// The text of [doc]'s body with its tables, for the fixtures: the blocks in
/// order, joined by `\n`; a paragraph is its [DocxParagraph.text] and a table
/// is a line for each row, the text of its cells joined by a tab, as
/// LibreOffice's text export writes it. Other blocks are left out.
///
/// A cell's text is [DocxTableCell.text]. A cell that continues a vertical
/// merge is an empty cell, and a row of merged cells has one cell for each
/// `w:tc`.
String docxFullText(DocxDocument doc) =>
    _blocksText(doc.body.blocks).join('\n');

/// [docxFullText] of a document LibreOffice saved, which ends sections and
/// pages in its own way: an empty paragraph that carries a section break is
/// no line (LibreOffice adds one after a paragraph that ended a section with
/// columns or another page), and a page break at either edge of a paragraph
/// is not one of its lines either (LibreOffice turns `w:pageBreakBefore` into
/// a `w:br` of the page before).
String docxResavedText(DocxDocument doc) => _blocksText(<DocxBlock>[
  for (final DocxBlock block in doc.body.blocks)
    if (block is! DocxParagraph || block.section == null || block.text != '')
      block,
], paragraph: _withoutEdgePageBreaks).join('\n');

/// The text of [paragraph] less a page break that starts or ends it.
String _withoutEdgePageBreaks(DocxParagraph paragraph) {
  String text = paragraph.text;
  bool isPageBreak(DocxRunContent? c) =>
      c is DocxBreak && c.type == DocxBreakType.page;
  final DocxInline? first = paragraph.inlines.firstOrNull;
  final DocxInline? last = paragraph.inlines.lastOrNull;
  if (first is DocxRun && isPageBreak(first.content.firstOrNull)) {
    text = text.substring(1);
  }
  if (text.isNotEmpty &&
      last is DocxRun &&
      isPageBreak(last.content.lastOrNull)) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

/// What the headers and footers of [doc] show, for the fixtures: a line for
/// each paragraph (a row, for a table) of each story a section shows, as
/// `<section> <kind>: <text>`, the sections in order, each with its `header`,
/// `first header`, `even header`, `footer`, `first footer` and `even footer`.
///
/// That is the document as Word shows it, not as the file writes it, which is
/// what survives a re-save: a section's stories count, inherited or its own
/// (LibreOffice writes every section its own copies), a `first` one with
/// [DocxSection.titlePage], an `even` one with
/// [DocxDocument.evenAndOddHeaders]. A blank line is left out, as LibreOffice
/// writes a blank paragraph in a story nobody filled. A field reads as
/// `{NAME}`, the first word of its instruction: its result is not this
/// comparison's, as LibreOffice computes `DATE` and `TIME`, and rewrites the
/// switches.
String docxStoriesText(DocxDocument doc) {
  final bool even = doc.evenAndOddHeaders;
  final List<DocxSection> sections = doc.sections;
  return <String>[
    for (int i = 0; i < sections.length; i++)
      for (final (String kind, DocxHeaderFooter story, bool shown)
          in <(String, DocxHeaderFooter, bool)>[
            ('header', sections[i].header, true),
            ('first header', sections[i].firstHeader, sections[i].titlePage),
            ('even header', sections[i].evenHeader, even),
            ('footer', sections[i].footer, true),
            ('first footer', sections[i].firstFooter, sections[i].titlePage),
            ('even footer', sections[i].evenFooter, even),
          ])
        if (shown)
          for (final String line in _blocksText(
            story.blocks,
            paragraph: _withFieldNames,
          ))
            if (line.trim().isNotEmpty) '${i + 1} $kind: $line',
  ].join('\n');
}

/// The text of [paragraph] with each field as `{NAME}`.
String _withFieldNames(DocxParagraph paragraph) => <String>[
  for (final DocxInline inline in paragraph.inlines)
    inline is DocxField
        ? '{${inline.instruction.trim().split(RegExp(r'\s+')).first}}'
        : inline.text,
].join();

List<String> _blocksText(
  List<DocxBlock> blocks, {
  String Function(DocxParagraph) paragraph = _paragraphText,
}) => <String>[
  for (final DocxBlock block in blocks)
    if (block is DocxParagraph)
      paragraph(block)
    else if (block is DocxTable)
      for (final DocxTableRow row in block.rows)
        <String>[
          for (final DocxTableCell cell in row.cells) cell.text,
        ].join('\t'),
];

String _paragraphText(DocxParagraph paragraph) => paragraph.text;

/// The text a file holds, as compared: [file] without a leading BOM and
/// without one trailing `\n`.
String readExpectedText(String file) {
  String text = file.startsWith('﻿') ? file.substring(1) : file;
  if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
  return text;
}

/// The most differing lines [textDifferences] names one by one.
const int _maxLines = 10;

/// The differences between [expected] and [actual], one line each, empty
/// when they are equal.
///
/// Each differing line is named by its number (from 1) with both texts,
/// quoted with tabs and other control characters escaped, up to ten lines,
/// then a count of the rest; a different number of lines is reported last.
List<String> textDifferences(String expected, String actual) {
  if (expected == actual) return const <String>[];
  final List<String> e = expected.split('\n');
  final List<String> a = actual.split('\n');
  final List<String> out = <String>[];
  int differing = 0;
  final int lines = e.length > a.length ? e.length : a.length;
  for (int i = 0; i < lines; i++) {
    final String? x = i < e.length ? e[i] : null;
    final String? y = i < a.length ? a[i] : null;
    if (x == y) continue;
    differing++;
    if (differing <= _maxLines) {
      out.add(
        'line ${i + 1}: expected ${x == null ? 'nothing' : _quote(x)}, '
        'got ${y == null ? 'nothing' : _quote(y)}',
      );
    }
  }
  if (differing > _maxLines) {
    out.add('... and ${differing - _maxLines} more differing lines');
  }
  if (e.length != a.length) {
    out.add('expected ${e.length} lines, got ${a.length}');
  }
  return out;
}

/// [text] in double quotes, with a tab as `\t`, a carriage return as `\r`
/// and any other control character, zero-width space or mark (U+200B to
/// U+200F) and byte order mark (U+FEFF) as `\u{…}`.
String _quote(String text) {
  final StringBuffer out = StringBuffer('"');
  for (final int c in text.runes) {
    if (c == 0x09) {
      out.write(r'\t');
    } else if (c == 0x0D) {
      out.write(r'\r');
    } else if (c < 0x20 ||
        c == 0x7F ||
        (c >= 0x200B && c <= 0x200F) ||
        c == 0xFEFF) {
      out.write('\\u{${c.toRadixString(16)}}');
    } else {
      out.writeCharCode(c);
    }
  }
  out.write('"');
  return out.toString();
}
