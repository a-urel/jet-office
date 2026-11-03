/// Edits every document of a directory through `DocxDocument`, so that CI
/// can validate what the model saves after a change to a real file.
///
/// ```bash
/// dart run tool/edit_docx.dart build/fixtures build/edited-docx-fixtures
/// ```
///
/// For every `*.docx` in the first directory (a Word lock file, `~$name`,
/// is skipped) it opens the document with `DocxDocument.open` and makes
/// three edits to the body:
///
/// * it sets the text of the first run, in a body paragraph, that has text
///   to `Edited by the model`;
/// * it replaces the last paragraph whose inlines are all runs (no
///   bookmark, field, hyperlink or drawing, whose loss could unpair
///   markup), other than the one just edited, with a new paragraph holding
///   `Replaced by the model`;
/// * it appends a paragraph `Added by the model` with the style `Heading1`,
///   or `Normal` when the file defines no style of id `Heading1`. The rule
///   is a simple one: `word/styles.xml` holds `w:styleId="Heading1"`. A file
///   whose styles part is elsewhere, or whose heading style has a localized
///   id, gets `Normal`, which may be undefined too: a paragraph naming a
///   style the file lacks is still valid and shows as the default.
///
/// A document without such a run or such a paragraph skips that edit. It
/// saves and writes the bytes to `<outDir>/<name>.docx`, then reads the
/// saved file back with `DocxDocument`: the edits must be there and the
/// body must have one block more than the input's. Last, `comparePackages`
/// from `tool/src/part_compare.dart` must find differences in
/// `word/document.xml` only: an edit of the body touches no other part.
///
/// Each problem is printed as `<file>: <problem>`. The exit code is 1 on any
/// problem, 2 when the arguments are unusable or the input directory holds
/// no `.docx`, and 0 otherwise, as `tool/edit_model.dart` does for
/// workbooks. The model's warnings are not problems.
///
/// CI runs it on the DOCX fixtures, on LibreOffice's re-save of them and on
/// the owner's Word files, and validates each output directory with
/// `tool/ooxml_validate`; the owner opens the edited owner files in Word
/// (`docs/word-checks.md`).
///
/// Not ported from Quds; written for jet_office.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/jet_office.dart';

import 'src/part_compare.dart';

void main(List<String> args) {
  exitCode = editDocx(args, out: stdout, err: stderr);
}

/// The text the tool sets on the first run with text.
const String editedText = 'Edited by the model';

/// The text of the paragraph that replaces one.
const String replacedText = 'Replaced by the model';

/// The text of the paragraph the tool appends.
const String addedText = 'Added by the model';

/// The main part, the only one an edit of the body may change.
const String _mainPart = 'word/document.xml';

/// Runs the tool on [args] (`<inDir> <outDir>`), writing problems to [out]
/// and usage problems to [err], and returns the exit code.
int editDocx(
  List<String> args, {
  required StringSink out,
  required StringSink err,
}) {
  if (args.length != 2) {
    err.writeln('Usage: dart run tool/edit_docx.dart <inDir> <outDir>');
    return 2;
  }
  final Directory input = Directory(args[0]);
  if (!input.existsSync()) {
    err.writeln('No such directory: ${input.path}');
    return 2;
  }
  final List<File> files = input.listSync().whereType<File>().where((File f) {
    final String name = f.uri.pathSegments.last;
    return name.endsWith('.docx') && !name.startsWith(r'~$');
  }).toList()..sort((File a, File b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    err.writeln('Nothing to edit: no .docx in ${input.path}.');
    return 2;
  }
  final Directory output = Directory(args[1])..createSync(recursive: true);
  int failed = 0;
  for (final File file in files) {
    final String name = file.uri.pathSegments.last;
    final List<String> problems = _edit(file, output, name);
    for (final String line in problems) {
      out.writeln('$name: $line');
    }
    if (problems.isNotEmpty) failed++;
  }
  out.writeln(
    failed == 0
        ? 'All ${files.length} documents edited.'
        : '$failed of ${files.length} documents failed.',
  );
  return failed == 0 ? 0 : 1;
}

/// What [_edit] did to a document, for the read-back check.
typedef _Edits = ({
  int blocks,
  ({int block, int inline})? run,
  int? replaced,
  String style,
});

/// Edits [file], writes the result to [output], and returns the problems.
List<String> _edit(File file, Directory output, String name) {
  final Uint8List input = file.readAsBytesSync();
  final Uint8List saved;
  final _Edits edits;
  try {
    final DocxDocument doc = DocxDocument.open(input);
    final DocxBody body = doc.body;
    final ({int block, int inline})? run = _firstRunWithText(body);
    if (run != null) {
      final DocxParagraph p = body.blocks[run.block] as DocxParagraph;
      (p.inlines[run.inline] as DocxRun).text = editedText;
    }
    final int? replaced = _paragraphToReplace(body, run?.block);
    if (replaced != null) {
      body.replaceBlockAt(replaced, DocxParagraph.text(replacedText));
    }
    final String style = _hasHeading1(input) ? 'Heading1' : 'Normal';
    final int blocks = body.blocks.length;
    body.addParagraph(addedText).style = style;
    edits = (blocks: blocks, run: run, replaced: replaced, style: style);
    saved = doc.save().bytes;
  } on Object catch (e) {
    return <String>['the edit failed: $e'];
  }
  File('${output.path}/$name').writeAsBytesSync(saved);
  return <String>[
    ..._check(saved, edits),
    for (final String d in comparePackages(input, saved))
      if (!d.startsWith('$_mainPart: ')) 'a part other than $_mainPart: $d',
  ];
}

/// The block and inline index of the first run of a body paragraph whose
/// text is not empty, or null when there is none.
({int block, int inline})? _firstRunWithText(DocxBody body) {
  for (int b = 0; b < body.blocks.length; b++) {
    final DocxBlock block = body.blocks[b];
    if (block is! DocxParagraph) continue;
    for (int i = 0; i < block.inlines.length; i++) {
      final DocxInline inline = block.inlines[i];
      if (inline is DocxRun && inline.text.isNotEmpty) {
        return (block: b, inline: i);
      }
    }
  }
  return null;
}

/// The index of the last paragraph of [body] whose inlines are all runs,
/// other than the block [edited], or null when there is none.
int? _paragraphToReplace(DocxBody body, int? edited) {
  for (int b = body.blocks.length - 1; b >= 0; b--) {
    final DocxBlock block = body.blocks[b];
    if (b == edited || block is! DocxParagraph) continue;
    if (block.inlines.every((DocxInline i) => i is DocxRun)) return b;
  }
  return null;
}

/// Whether the package [docx] has a `word/styles.xml` that defines a style
/// of id `Heading1`.
bool _hasHeading1(Uint8List docx) {
  final ArchiveFile? styles = ZipDecoder()
      .decodeBytes(docx)
      .findFile('word/styles.xml');
  if (styles == null) return false;
  return utf8
      .decode(styles.content, allowMalformed: true)
      .contains('w:styleId="Heading1"');
}

/// The edits [saved] lacks when read back with `DocxDocument`.
List<String> _check(Uint8List saved, _Edits edits) {
  final List<String> problems = <String>[];
  try {
    final List<DocxBlock> blocks = DocxDocument.open(saved).body.blocks;
    if (blocks.length != edits.blocks + 1) {
      problems.add(
        'the body has ${blocks.length} blocks, not ${edits.blocks + 1}',
      );
      return problems;
    }
    final ({int block, int inline})? run = edits.run;
    if (run != null) {
      final DocxBlock b = blocks[run.block];
      final DocxInline? i = b is DocxParagraph && run.inline < b.inlines.length
          ? b.inlines[run.inline]
          : null;
      if (i is! DocxRun || i.text != editedText) {
        problems.add('the edited run text is missing');
      }
    }
    final int? replaced = edits.replaced;
    if (replaced != null) {
      final DocxBlock b = blocks[replaced];
      if (b is! DocxParagraph || b.text != replacedText) {
        problems.add('the replacing paragraph is missing');
      }
    }
    final DocxBlock last = blocks.last;
    if (last is! DocxParagraph ||
        last.text != addedText ||
        last.style != edits.style) {
      problems.add('the added ${edits.style} paragraph is missing');
    }
  } on Object catch (e) {
    problems.add('reading the saved document failed: $e');
  }
  return problems;
}
