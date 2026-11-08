/// The document model benchmark: open a large Word-authored document, load its
/// body, change one paragraph, save, and reopen the saved bytes.
///
/// Not ported from Quds; written for jet_office. It records figures, it does
/// not judge them (docs/benchmark.md). The owner supplied no large Word file,
/// so the document is made from the owner's `long.docx` (15 pages, written by
/// Word for Mac; `test/fixtures/owner/docx/`): the children of its body, but
/// for the final `w:sectPr`, are repeated until the body has about 40,000
/// paragraphs, by string surgery on `word/document.xml`, and the package is
/// repackaged with the same parts (`scaledLongDocx`,
/// `test/docx/support/large_document.dart`, which `tool/write_large_docx.dart`
/// uses too). Word's markup is kept as it is, with two
/// changes so that no copy repeats what Word makes unique: the `w:id` of every
/// bookmark and the numbers in the `_Toc` names (and so in the `PAGEREF` and
/// hyperlink anchors that point to them) differ per copy, and the
/// `w14:paraId` and `w14:textId` attributes are dropped (they are optional).
/// Only bookmark ids and `_Toc` names are made unique per copy: other ids,
/// such as `wp:docPr` ids and `_Ref` names, may repeat across copies, which
/// the model does not check.
/// The bytes are read from disk on the VM and by `spawnHybridUri` in Chrome
/// (`src/owner_file_hybrid.dart`), then built once; each platform deflates and
/// opens its own bytes (decision 0006). Phases: open, load the body, set the
/// text of one paragraph near the middle, save, open the saved bytes and read
/// that paragraph back. Run it with `dart test benchmark` and
/// `dart test -p chrome benchmark`; the quality gate does not.
@Tags(<String>['benchmark'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../test/docx/support/large_document.dart';
import 'src/memory_probe.dart';

/// The owner's file, relative to the package root.
const String _ownerFile = 'test/fixtures/owner/docx/long.docx';

/// About how many paragraphs the large body has.
const int _targetParagraphs = 40000;

/// The text the benchmark gives the changed paragraph's first run.
const String _changedText = 'Changed by the benchmark';

// A double 0.0 is the integer 0 on JavaScript only.
const bool _isWeb = identical(0, 0.0);

/// The bytes of the owner's file.
Future<Uint8List> _readOwnerFile() async {
  final Stream<Object?> stream = spawnHybridUri(
    'src/owner_file_hybrid.dart',
    message: _ownerFile,
  ).stream;
  final Object? bytes = await stream.first;
  return Uint8List.fromList((bytes! as List<Object?>).cast<int>());
}

/// The first run with text of [paragraph], or `null`.
DocxRun? _firstTextRun(DocxParagraph paragraph) {
  for (final DocxInline inline in paragraph.inlines) {
    if (inline is DocxRun && inline.text.isNotEmpty) return inline;
  }
  return null;
}

void main() {
  final MemoryProbe memory = currentProbe();
  final MemoryProbe peakProbe = probe();
  const String platform = _isWeb ? 'chrome' : 'vm';

  void line(String text) {
    // ignore: avoid_print
    print('$platform | $text');
  }

  /// Runs [body] once, timed, and prints its time and memory: the process
  /// memory ([MemoryProbe.unit]) before and after, and the peak where the
  /// platform has one.
  T phase<T>(String name, T Function() body) {
    final int? before = memory.sample();
    final int? peakBefore = peakProbe.sample();
    final Stopwatch watch = Stopwatch()..start();
    final T result = body();
    watch.stop();
    final int? after = memory.sample();
    final int? peak = peakProbe.sample();
    line(
      'phase | $name | ${(watch.elapsedMicroseconds / 1000).toStringAsFixed(1)}'
      ' ms | ${memory.unit} before ${before ?? 'n/a'} | after '
      '${after ?? 'n/a'} | ${peakProbe.unit} ${peak ?? 'n/a'} (was '
      '${peakBefore ?? 'n/a'})',
    );
    return result;
  }

  test('open, load, change one paragraph, save and reopen', () async {
    final Uint8List original = await _readOwnerFile();
    final ScaledDocument scaled = scaledLongDocx(
      original,
      paragraphs: _targetParagraphs,
    );
    final Uint8List file = scaled.bytes;
    line(
      'input | long.docx ${original.length} bytes, ${scaled.sourceParagraphs} '
      'paragraphs | scaled file ${file.length} bytes | '
      '$largeDocumentMainPart ${scaled.mainXmlBytes} bytes XML',
    );

    final DocxDocument doc = phase('open', () => DocxDocument.open(file));
    final List<DocxBlock> blocks = phase(
      'load the body',
      () => doc.body.blocks,
    );
    final int paragraphs = blocks.whereType<DocxParagraph>().length;
    line('body | ${blocks.length} blocks | $paragraphs paragraphs');
    expect(paragraphs, greaterThanOrEqualTo(_targetParagraphs));
    expect(doc.warnings, isEmpty);

    // The first paragraph at or after the middle that has a run with text.
    int index = blocks.length ~/ 2;
    DocxRun? run;
    while (index < blocks.length) {
      final DocxBlock block = blocks[index];
      if (block is DocxParagraph) {
        run = _firstTextRun(block);
        if (run != null) break;
      }
      index++;
    }
    expect(run, isNotNull, reason: 'a paragraph with text after the middle');
    final String before = (blocks[index] as DocxParagraph).text;
    phase('set the text of block $index', () => run!.text = _changedText);

    final Uint8List saved = phase('save', () => doc.save().bytes);
    line('output | saved file ${saved.length} bytes');

    final DocxDocument reopened = phase(
      'reopen (and load the body)',
      () => DocxDocument.open(saved)..body,
    );
    final List<DocxBlock> back = reopened.body.blocks;
    expect(back, hasLength(blocks.length));
    final String after = (back[index] as DocxParagraph).text;
    expect(after, startsWith(_changedText));
    expect(after, isNot(before));
    line('read back | block $index | "$after"');
  });
}
