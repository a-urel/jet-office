/// Test helper: seeded mutation fuzzing of `DocxDocument`.
///
/// New in jet_office (phase 4, D1). [docxFuzzCorpus] is the set of valid
/// packages the fuzzer starts from, [docxFuzzCases] derives mutated copies
/// of them from a seed with the mutations of `test/support/fuzz_mutations.dart`
/// (the ones that fuzz the XLSX reader), and [exerciseDocx] drives the
/// public surface of `DocxDocument` over one file.
/// `test/docx/fuzz_test.dart` runs a fixed range of seeds in the quality
/// gate; `tool/fuzz_docx.dart` runs any range by hand.
///
/// A seed gives the same cases on the VM and in a browser: the corpus is
/// rebuilt stored, not deflated, so its bytes do not depend on the
/// platform's deflater (decision 0006).
///
/// The 5 s hang bound is checked after a case returns, so a real infinite
/// loop is not reported as a hang: the test's timeout stops it and names no
/// case. `tool/fuzz_docx.dart --verbose` writes each case to stderr before
/// it runs, so the last line names it.
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

import '../../fixtures/docx_fixtures.dart';
import '../../support/fuzz_mutations.dart';
import '../../support/read_xlsx.dart';
import '../../xlsx/read/support/zip_builder.dart';
import 'producer_variants.dart';

export '../../support/fuzz_mutations.dart'
    show FuzzCase, Xorshift32, mutatedPart;

/// The valid packages the fuzzer mutates, in a fixed order: every fixture of
/// `docxFixtures()` and every `producerVariants()` entry, each rebuilt with
/// stored entries and a fixed timestamp, so the bytes are equal on every
/// platform.
///
/// Nothing is deflated, so inflation is fuzzed only by the archive
/// mutations, which damage the stored headers and sizes.
List<({String name, Uint8List bytes})> docxFuzzCorpus() =>
    <({String name, Uint8List bytes})>[
      for (final DocxFixture f in docxFixtures())
        (name: f.name, bytes: _rebuild(f.build().bytes)),
      for (final ProducerVariant v in producerVariants())
        (name: v.name, bytes: _rebuild(v.bytes)),
    ];

/// [zip] with the same entries in the same order, written again stored.
Uint8List _rebuild(Uint8List zip) => buildZipOrdered(<(String, List<int>)>[
  for (final MapEntry<String, Uint8List> e in readXlsxBytes(zip).entries)
    (e.key, e.value),
], store: true);

/// The entry names of the corpus package [zip], in archive order.
List<String> docxCorpusPartNames(Uint8List zip) =>
    readXlsxBytes(zip).keys.toList();

/// The tokens the insert mutation puts into a part: markup, entities,
/// relationship ids and numbers that the DOCX parsers treat specially.
final List<String> _tokens = <String>[
  '<',
  '>',
  '&',
  '"',
  '</w:p>',
  '<w:p>',
  '<w:r>',
  '<w:t>',
  '</w:t>',
  '<w:t xml:space="preserve">',
  '<w:pStyle w:val="Heading1"/>',
  '<w:rStyle w:val=""/>',
  '<w:tab/>',
  '<w:br w:type="page"/>',
  '<w:sectPr/>',
  '<w:body>',
  '<w:tbl>',
  '<w:sdt>',
  ' r:id="rId999"',
  ' Target="../../x.xml"',
  ' TargetMode="External"',
  '<!DOCTYPE a>',
  '<![CDATA[',
  '&#0;',
  '&#xD800;',
  '_x0000_',
  '99999999999999999999',
  '<w:r>' * 300,
];

/// The first [count] cases of [seed], each one mutation of one corpus
/// entry, chosen and mutated as `mutationCases` describes.
///
/// Lazy, and the same for the same arguments every time.
Iterable<FuzzCase> docxFuzzCases(int seed, int count) {
  final List<({String name, Uint8List bytes})> corpus = docxFuzzCorpus();
  final List<List<(String, Uint8List)>> parts = <List<(String, Uint8List)>>[
    for (final ({String name, Uint8List bytes}) entry in corpus)
      <(String, Uint8List)>[
        for (final MapEntry<String, Uint8List> e in readXlsxBytes(
          entry.bytes,
        ).entries)
          (e.key, e.value),
      ],
  ];
  return mutationCases(
    seed: seed,
    count: count,
    corpus: corpus,
    parts: parts,
    tokens: _tokens,
  );
}

/// Opens [bytes], renders every warning in English, German and Turkish,
/// walks the body, appends a paragraph, saves, and opens the saved bytes
/// again.
///
/// Returns normally or throws [DocxReadException], and only from `open` or
/// from the first access to `body`: a file that opens but whose main part
/// cannot be read is saved anyway (the part is copied as it was), and the
/// exception is rethrown after the save and the reopen. Anything else
/// thrown by `open` or `body` is a defect and propagates at once.
///
/// The model makes nothing worse: `save()` may throw nothing, the saved
/// bytes must open, and their body must load unless the input's did not.
/// A failure there is a [StateError] naming the step, so a
/// [DocxReadException] from a later step cannot pass for a refused file.
void exerciseDocx(Uint8List bytes) {
  final DocxDocument doc = DocxDocument.open(bytes);
  DocxReadException? first;
  try {
    _walk(doc.body);
    doc.body.addParagraph('x').addRun('y');
  } on DocxReadException catch (e) {
    e.toString();
    first = e;
  }
  for (final DocxWarning warning in doc.warnings) {
    for (final OfficeLocale locale in OfficeLocale.values) {
      warning.message(locale);
    }
  }
  final Uint8List saved;
  try {
    saved = doc.save().bytes;
  } on Object catch (e) {
    throw StateError('save() threw: $e');
  }
  _reopen(saved, bodyReadable: first == null);
  if (first != null) throw first;
}

/// Reads every block, inline and run content of [body].
void _walk(DocxBody body) {
  for (final DocxBlock block in body.blocks) {
    block.toString();
    if (block is! DocxParagraph) continue;
    block.text;
    block.style;
    for (final DocxInline inline in block.inlines) {
      inline.text;
      inline.toString();
      if (inline is! DocxRun) continue;
      inline.style;
      for (final DocxRunContent content in inline.content) {
        content.toString();
      }
    }
  }
}

/// Opens [saved] and loads its body; only when the input's body could not
/// be read ([bodyReadable] false) may that throw a [DocxReadException].
/// Anything else is a [StateError].
void _reopen(Uint8List saved, {required bool bodyReadable}) {
  final DocxDocument again;
  try {
    again = DocxDocument.open(saved);
  } on Object catch (e) {
    throw StateError('opening the saved document threw: $e');
  }
  try {
    _walk(again.body);
  } on DocxReadException catch (e) {
    if (bodyReadable) {
      throw StateError('the body of the saved document threw: $e');
    }
  } on Object catch (e) {
    throw StateError('the body of the saved document threw: $e');
  }
}
