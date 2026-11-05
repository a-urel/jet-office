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

import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/ooxml.dart';

import '../../fixtures/docx_fixtures.dart';
import '../../support/fuzz_mutations.dart';
import '../../support/read_xlsx.dart';
import '../../xlsx/read/support/zip_builder.dart';
import 'localized_document.dart';
import 'numbering_documents.dart';
import 'producer_variants.dart';
import 'styles_documents.dart';
import 'word_document.dart';

export '../../support/fuzz_mutations.dart'
    show FuzzCase, PartMutation, Xorshift32, mutatedPart;

/// The valid packages the fuzzer mutates, in a fixed order: `word_like`,
/// the Word-like document of `richWordDocx()` (tracked changes, a
/// hyperlink, content controls, a table, markup compatibility content,
/// fields and a bookmark), `localized_word`, the document of
/// `localizedWordDocx()` with Word's styles part (Turkish ids, `w14` and
/// `w15` content) and numbering part, then every fixture of `docxFixtures()` and every
/// `producerVariants()` entry, each rebuilt with stored entries and a fixed
/// timestamp, so the bytes are equal on every platform.
///
/// Nothing is deflated, so inflation is fuzzed only by the archive
/// mutations, which damage the stored headers and sizes.
List<({String name, Uint8List bytes})> docxFuzzCorpus() =>
    <({String name, Uint8List bytes})>[
      (name: 'word_like', bytes: _rebuild(richWordDocx())),
      (name: 'localized_word', bytes: _rebuild(_localizedWithNumbering())),
      for (final DocxFixture f in docxFixtures())
        (name: f.name, bytes: _rebuild(f.build().bytes)),
      for (final ProducerVariant v in producerVariants())
        (name: v.name, bytes: _rebuild(v.bytes)),
    ];

/// `localizedWordDocx()` with `wordStylesXml` as its styles part (Turkish
/// ids; `w14` and `w15` declared and used) and `wordNumberingXml` as a
/// numbering part, related from the main part.
Uint8List _localizedWithNumbering() {
  final Map<String, Uint8List> entries = readXlsxBytes(localizedWordDocx());
  String text(String name) => utf8.decode(entries[name]!);
  return buildZipOrdered(<(String, List<int>)>[
    for (final MapEntry<String, Uint8List> e in entries.entries)
      switch (e.key) {
        'word/styles.xml' => (e.key, utf8.encode(wordStylesXml)),
        '[Content_Types].xml' => (
          e.key,
          utf8.encode(
            text(e.key).replaceFirst(
              '</Types>',
              '<Override PartName="/word/numbering.xml" '
                  'ContentType="${ContentType.wmlNumbering}"/></Types>',
            ),
          ),
        ),
        'word/_rels/document.xml.rels' => (
          e.key,
          utf8.encode(
            text(e.key).replaceFirst(
              '</Relationships>',
              '${numberingRelationship('numbering.xml')}</Relationships>',
            ),
          ),
        ),
        _ => (e.key, e.value),
      },
    ('word/numbering.xml', utf8.encode(wordNumberingXml)),
  ], store: true);
}

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

/// The values the attribute mutation writes: text where a number is read,
/// a number past every range, a bare sign and a unit the readers do not
/// take.
const List<String> _attributeValues = <String>[
  'abc',
  '99999999999999999999',
  '-',
  '1in',
];

/// Replaces the value of one attribute of [part], chosen uniformly among
/// the `="..."` it holds, by one of [_attributeValues]; a part without an
/// attribute gets a token inserted instead, as the digit mutation does.
(String, List<int>) _replaceAttributeValue(Uint8List part, Xorshift32 random) {
  final String text = latin1.decode(part);
  final List<RegExpMatch> found = RegExp(
    r'="([^"]*)"',
  ).allMatches(text).toList();
  if (found.isEmpty) {
    final int at = random.nextInt(part.length + 1);
    return (
      'insert "abc" at $at',
      <int>[
        ...part.sublist(0, at),
        ...latin1.encode('abc'),
        ...part.sublist(at),
      ],
    );
  }
  final RegExpMatch match = found[random.nextInt(found.length)];
  final String value =
      _attributeValues[random.nextInt(_attributeValues.length)];
  return (
    'replace attribute value at ${match.start + 2} with "$value"',
    <int>[
      ...part.sublist(0, match.start + 2),
      ...latin1.encode(value),
      ...part.sublist(match.end - 1),
    ],
  );
}

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
    extra: <PartMutation>[_replaceAttributeValue],
  );
}

/// Opens [bytes], renders every warning in English, German and Turkish,
/// reads the body, the styles and the numbering with every typed property,
/// edits what loaded, saves, and opens the saved bytes again.
///
/// Returns normally or throws [DocxReadException], and only from `open`, from
/// the first access to `body`, `styles` or `numbering`, or from an edit of a
/// part that could not be used (`DocxStyles.ensure` on a styles part whose
/// content is not what it says): a file that opens but has such a part is
/// saved anyway (the part is copied as it was), and the first exception is
/// rethrown after the save and the reopen. Anything else thrown by `open`
/// or those steps is a defect and propagates at once.
///
/// Reading a typed property throws nothing, whatever the file holds. When
/// styles and numbering both opened, `styles.ensure(DocxBuiltInStyle.heading1)`
/// and `numbering.addBulletList()` run before the save.
///
/// The model makes nothing worse: `save()` may throw nothing, the saved
/// bytes must open, and their body, styles and numbering must load unless
/// the input's did not. A failure there is a [StateError] naming the step,
/// so a [DocxReadException] from a later step cannot pass for a refused
/// file.
void exerciseDocx(Uint8List bytes) {
  final DocxDocument doc = DocxDocument.open(bytes);
  DocxReadException? first;
  final bool bodyReadable = _guard(() {
    _walk(doc.body);
    doc.body.addParagraph('x').addRun('y');
  }, (DocxReadException e) => first ??= e);
  final bool stylesReadable = _guard(
    () => _readStyles(doc.styles),
    (DocxReadException e) => first ??= e,
  );
  final bool numberingReadable = _guard(
    () => _readNumbering(doc.numbering),
    (DocxReadException e) => first ??= e,
  );
  if (stylesReadable && numberingReadable) {
    _guard(() {
      doc.styles.ensure(DocxBuiltInStyle.heading1);
      doc.numbering.addBulletList();
    }, (DocxReadException e) => first ??= e);
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
  _reopen(
    saved,
    bodyReadable: bodyReadable,
    stylesReadable: stylesReadable,
    numberingReadable: numberingReadable,
  );
  if (first != null) throw first!;
}

/// Runs [action]; a [DocxReadException] goes to [onRefusal] and the result
/// is false, anything else propagates.
bool _guard(
  void Function() action,
  void Function(DocxReadException) onRefusal,
) {
  try {
    action();
    return true;
  } on DocxReadException catch (e) {
    e.toString();
    onRefusal(e);
    return false;
  }
}

/// Reads every block, inline and run content of [body], and every typed
/// property of its paragraphs and runs.
void _walk(DocxBody body) {
  for (final DocxBlock block in body.blocks) {
    block.toString();
    if (block is! DocxParagraph) continue;
    block.text;
    block.style;
    _paragraph(block.properties);
    for (final DocxInline inline in block.inlines) {
      inline.text;
      inline.toString();
      if (inline is! DocxRun) continue;
      inline.style;
      _run(inline.properties);
      for (final DocxRunContent content in inline.content) {
        content.toString();
      }
    }
  }
}

/// Reads the defaults, every style and every typed property of [styles].
void _readStyles(DocxStyles styles) {
  _paragraph(styles.defaults.paragraphProperties);
  _run(styles.defaults.runProperties);
  for (final DocxStyle style in styles.styles) {
    <Object?>[
      style.id,
      style.type,
      style.name,
      style.basedOn,
      style.next,
      style.link,
      style.uiPriority,
      style.quickFormat,
    ].toString();
    _paragraph(style.paragraphProperties);
    _run(style.runProperties);
    if (style.id case final String id) styles.byId(id);
    styles.byName(style.name ?? '');
  }
}

/// Reads every level, instance and override of [numbering].
void _readNumbering(DocxNumbering numbering) {
  for (final DocxAbstractNumbering abstract in numbering.abstractNumberings) {
    abstract.toString();
    for (final DocxNumberingLevel level in abstract.levels) {
      <Object?>[
        level.format,
        level.text,
        level.start,
        level.alignment,
        level.indentation,
        level.bulletFont,
      ].toString();
    }
  }
  for (final DocxNumberingInstance instance in numbering.instances) {
    instance.ref().toString();
    for (final DocxLevelOverride o in instance.overrides) {
      o.startOverride.toString();
    }
  }
}

void _paragraph(DocxParagraphProperties p) => <Object?>[
  p.style,
  p.alignment,
  p.indentation,
  p.spacing,
  p.keepWithNext,
  p.keepLines,
  p.pageBreakBefore,
  p.widowControl,
  p.outlineLevel,
  p.borders,
  p.shading,
  p.tabs,
  p.numbering,
].toString();

void _run(DocxRunProperties r) => <Object?>[
  r.style,
  r.fonts,
  r.bold,
  r.italic,
  r.caps,
  r.smallCaps,
  r.strike,
  r.doubleStrike,
  r.color,
  r.characterSpacingPt,
  r.sizePt,
  r.highlight,
  r.underline,
  r.shading,
  r.verticalAlign,
  r.language,
].toString();

/// Opens [saved] and loads its body, styles and numbering; only a part
/// that the input could not read ([bodyReadable], [stylesReadable],
/// [numberingReadable] false) may throw a [DocxReadException]. Anything
/// else is a [StateError].
void _reopen(
  Uint8List saved, {
  required bool bodyReadable,
  required bool stylesReadable,
  required bool numberingReadable,
}) {
  final DocxDocument again;
  try {
    again = DocxDocument.open(saved);
  } on Object catch (e) {
    throw StateError('opening the saved document threw: $e');
  }
  void load(String what, bool readable, void Function() read) {
    try {
      read();
    } on DocxReadException catch (e) {
      if (readable) throw StateError('the saved $what threw: $e');
    } on Object catch (e) {
      throw StateError('the saved $what threw: $e');
    }
  }

  load('body', bodyReadable, () => _walk(again.body));
  load('styles', stylesReadable, () => _readStyles(again.styles));
  load('numbering', numberingReadable, () => _readNumbering(again.numbering));
}
