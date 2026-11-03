/// Drafts the expected text of a real Word document.
///
/// ```bash
/// dart run tool/draft_expected_docx.dart test/fixtures/owner/docx/features.docx
/// ```
///
/// Opens the file with `DocxDocument` and writes `<stem>.expected.txt`
/// beside it: `docxBodyText` (each paragraph's text of the body, joined by
/// `\n`; tables and other blocks the model keeps opaque are left out) and a
/// final newline. It prints a review list, one line per block of the body:
/// `<n>  <text>` for a paragraph, with tabs and control characters shown
/// escaped, and `<n>  [<element>: not in the text]` for any other block. The
/// draft is the model's own answer: the owner checks every line against
/// Word and then sets `"confirmedBy": "owner"` on the file's entry in
/// `test/fixtures/owner/docx/manifest.json`, which
/// `test/docx/owner_files_test.dart` then holds the model to. The tool
/// never overwrites an existing `.expected.txt` (exit 1), so a confirmed
/// text cannot be lost; it exits 64 on a usage error and 66 when the file
/// does not exist. See `test/fixtures/owner/README.md`.
library;

import 'dart:io';

import 'package:jet_office/jet_office.dart';

import 'src/text_compare.dart';

void main(List<String> args) {
  exitCode = draftExpectedDocx(args, out: stdout, err: stderr);
}

/// Runs the tool on [args] (`<file.docx>`), writing the review list to
/// [out] and problems to [err], and returns the exit code.
int draftExpectedDocx(
  List<String> args, {
  required StringSink out,
  required StringSink err,
}) {
  if (args.length != 1 || !args.single.endsWith('.docx')) {
    err.writeln('Usage: dart run tool/draft_expected_docx.dart <file.docx>');
    return 64;
  }
  final File input = File(args.single);
  if (!input.existsSync()) {
    err.writeln('No such file: ${input.path}');
    return 66;
  }
  final File output = File(
    '${input.path.substring(0, input.path.length - 5)}.expected.txt',
  );
  if (output.existsSync()) {
    err.writeln(
      '${output.path} exists; delete it first if you mean to draft again.',
    );
    return 1;
  }
  final DocxDocument doc;
  final String text;
  try {
    doc = DocxDocument.open(input.readAsBytesSync());
    text = docxBodyText(doc);
  } on DocxReadException catch (e) {
    err.writeln('The model refused ${input.path}: $e');
    return 1;
  }
  output.writeAsStringSync('$text\n');
  final List<DocxBlock> blocks = doc.body.blocks;
  for (int i = 0; i < blocks.length; i++) {
    final String shown = switch (blocks[i]) {
      final DocxParagraph p => _show(p.text),
      final DocxOpaqueBlock b => '[${b.localName}: not in the text]',
    };
    out.writeln('${'${i + 1}'.padLeft(4)}  $shown');
  }
  for (final DocxWarning w in doc.warnings) {
    out.writeln('warning: ${w.message()}');
  }
  out
    ..writeln('Wrote ${output.path}: check every line above in Word, then')
    ..writeln('set "confirmedBy": "owner" on its entry in manifest.json.');
  return 0;
}

/// [text] with tabs, line breaks, other control characters and invisible
/// format characters (zero-width spaces and joiners, marks, the BOM)
/// escaped, so that each paragraph takes one line and nothing is hidden.
String _show(String text) => text.replaceAllMapped(
  RegExp('[\u0000-\u001F\u007F\u200B-\u200F\u2028\u2029\uFEFF]'),
  (Match m) => switch (m[0]!) {
    '\t' => r'\t',
    '\n' => r'\n',
    final String c => '\\u{${c.codeUnitAt(0).toRadixString(16)}}',
  },
);
