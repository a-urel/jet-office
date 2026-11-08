/// Writes `large.docx`, a Word document of about 40,000 paragraphs, for the
/// owner's Word check of the benchmark's document (`docs/word-checks.md`,
/// section D6).
///
/// ```bash
/// dart run tool/write_large_docx.dart build/d6/benchmark
/// ```
///
/// It reads the owner's `test/fixtures/owner/docx/long.docx`, repeats its body
/// by `scaledLongDocx` (`test/docx/support/large_document.dart`, the
/// benchmark's own scaling), opens the result with `DocxDocument`, sets the
/// text of the first paragraph with text at or after the middle of the body to
/// `Edited by the model`, and saves `<out-dir>/large.docx`. It is not part of
/// the CI chain. The exit code is 2 on unusable arguments and 1 on any error.
/// Not ported from Quds.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

import '../test/docx/support/large_document.dart';

/// The text the tool gives the changed paragraph.
const String largeDocxEditedText = 'Edited by the model';

/// [longDocx] scaled to at least [paragraphs] paragraphs, with the first
/// paragraph with text at or after the middle of its body set to
/// [largeDocxEditedText], saved.
///
/// Throws what `scaledLongDocx` throws, and [StateError] when no paragraph
/// after the middle has text.
Uint8List editedLargeDocx(Uint8List longDocx, {int paragraphs = 40000}) {
  final DocxDocument doc = DocxDocument.open(
    scaledLongDocx(longDocx, paragraphs: paragraphs).bytes,
  );
  final List<DocxBlock> blocks = doc.body.blocks;
  for (int i = blocks.length ~/ 2; i < blocks.length; i++) {
    final DocxBlock block = blocks[i];
    if (block is! DocxParagraph) continue;
    for (final DocxInline inline in block.inlines) {
      if (inline is DocxRun && inline.text.isNotEmpty) {
        inline.text = largeDocxEditedText;
        return doc.save().bytes;
      }
    }
  }
  throw StateError('No paragraph with text after the middle of the body.');
}

void main(List<String> args) {
  if (args.length != 1 || args.single.startsWith('-')) {
    stderr.writeln('Usage: dart run tool/write_large_docx.dart <out-dir>');
    exitCode = 2;
    return;
  }
  try {
    final Uint8List source = File(
      'test/fixtures/owner/docx/long.docx',
    ).readAsBytesSync();
    final Uint8List bytes = editedLargeDocx(source);
    final Directory dir = Directory(args.single)..createSync(recursive: true);
    File('${dir.path}/large.docx').writeAsBytesSync(bytes);
    stdout.writeln('Wrote large.docx (${bytes.length} bytes) to ${dir.path}.');
  } on Object catch (e) {
    stderr.writeln('write_large_docx: $e');
    exitCode = 1;
  }
}
