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
