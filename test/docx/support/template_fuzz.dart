/// Test helper: seeded mutation fuzzing of `DocxTemplate` (decision 0024, T1).
///
/// New in jet_office. [templateFuzzCorpus] is the set of templates the fuzzer
/// starts from, [templateFuzzCases] derives mutated copies of them from a
/// seed, and [exerciseTemplate] drives `DocxTemplate` over one file.
/// `test/docx/template/template_fuzz_test.dart` runs seeds 1 to 4 in the
/// quality gate; `tool/fuzz_docx.dart --template` runs any range by hand.
///
/// The mutations are those of `test/docx/support/docx_fuzz.dart` (the archive
/// and byte mutations of `test/support/fuzz_mutations.dart` with the DOCX
/// tokens, and the attribute mutation), and two of the template's own, on the
/// main, header and footer parts: [_insertTagText] puts `{{`, `}}`, `{{a}}` or
/// a random tag body into the text of a `w:t`, and [_insertSwitch] puts a
/// field switch into the text of a `w:instrText`. Each is inserted at a
/// character boundary, so the part stays valid UTF-8.
///
/// A seed gives the same cases on the VM and in a browser: the corpus is
/// rebuilt stored, not deflated (decision 0006).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

import '../../../tool/src/fill_data.dart';
import '../../../tool/src/part_compare.dart';
import '../../fixtures/docx_fixtures.dart'
    show t1MergeFieldsTemplate, t1ValuesTemplate;
import '../../support/fuzz_mutations.dart';
import '../../support/read_xlsx.dart';
import '../../xlsx/read/support/zip_builder.dart';
import 'docx_fuzz.dart' show docxAttributeMutation, docxFuzzTokens;
import 'template_documents.dart';

export '../../support/fuzz_mutations.dart' show FuzzCase, mutatedPart;

/// The templates the fuzzer mutates, in a fixed order: `t1_template` (the
/// template of the `t1_values` fixture: split, formatted, coloured, header,
/// footer and table tags), `t1_merge_fields` (the template of the
/// `t1_merge_fields` fixture: complex `MERGEFIELD`s with switches and a
/// `w:fldSimple`), `word_split_header` (`templateWithHeader`, a tag split by
/// `wordSplitTag` in the header and one with its first brace bold in the
/// body) and `word_split_kinds` (a tag split by `wordSplitTag`, one over a
/// hyperlink's edge, around a tab, in a field result, in a tracked insertion,
/// in a content control, a section and a malformed tag), each rebuilt with
/// stored entries.
List<({String name, Uint8List bytes})> templateFuzzCorpus() =>
    <({String name, Uint8List bytes})>[
      (name: 't1_template', bytes: _rebuild(t1ValuesTemplate())),
      (name: 't1_merge_fields', bytes: _rebuild(t1MergeFieldsTemplate())),
      (
        name: 'word_split_header',
        bytes: _rebuild(
          templateWithHeader(
            bodyInline: wordSplitTag('{{musteri.ad}}', boldFirstBrace: true),
          ),
        ),
      ),
      (
        name: 'word_split_kinds',
        bytes: _rebuild(
          templateDocument(<String>[
            wordSplitTag('{{firma.unvan}}'),
            tagInHyperlink('{{tu', <String>['tar:0.00'], '}}'),
            tagAroundTab(),
            tagInFieldResult('{{tarih}}'),
            tagInInsertion('{{miktar}}'),
            tagInInlineSdt('{{Ad}}'),
            templateRun('{{#liste}}{{.}}{{/liste}} {{a b c'),
          ]),
        ),
      ),
    ];

/// [zip] with the same entries in the same order, written again stored.
Uint8List _rebuild(Uint8List zip) => buildZipOrdered(<(String, List<int>)>[
  for (final MapEntry<String, Uint8List> e in readXlsxBytes(zip).entries)
    (e.key, e.value),
], store: true);

/// Whether the part [name] holds a story whose tags the fill fills: the main
/// part, a header or a footer. The extra mutations go there.
bool _storyPart(String name) =>
    RegExp(r'^word/(document|header\d*|footer\d*)\.xml$').hasMatch(name);

/// The texts [_insertTagText] puts into a `w:t`, besides a random body.
const List<String> _tagTexts = <String>['{{', '}}', '{{a}}', '{{#a}}'];

/// The characters of a random tag body: path, format, section and brace
/// characters, a space, a digit, a quote and a Turkish letter; never U+FFFC,
/// which the fill uses for what is not text.
const String _bodyAlphabet = 'ab.:#/^ 0,"{}ş%';

/// The switches [_insertSwitch] puts into a `w:instrText`.
const List<String> _switches = <String>[
  r' \* Upper',
  r' \* MERGEFORMAT',
  r' \* Roman',
  r' \@ "dd.MM.yyyy"',
  r' \@ "',
  r' \# "#,##0.00"',
  r' \# "x##"',
  r' \b "Sayın "',
  r' \f ","',
  r' \v',
  r' \',
  ' "',
  ' MERGEFIELD',
  ' MERGEFIELD Ad',
];

/// [part] (as text, `latin1`) with [insert] put at a character boundary of
/// the text of one element [element] chosen by [random]; `null` when the part
/// has no such element with text.
(String, List<int>)? _insertInto(
  String element,
  Uint8List part,
  Xorshift32 random,
  String insert,
) {
  final String text = latin1.decode(part);
  final List<RegExpMatch> found = RegExp(
    '<$element(?: [^>]*)?>([^<]*)</$element>',
  ).allMatches(text).toList();
  if (found.isEmpty) return null;
  final RegExpMatch match = found[random.nextInt(found.length)];
  final int start = match.start + match.group(0)!.indexOf('>') + 1;
  final int length = match.group(1)!.length;
  int at = start + random.nextInt(length + 1);
  // Not inside a UTF-8 sequence: back up over continuation bytes.
  while (at > start && (part[at] & 0xC0) == 0x80) {
    at--;
  }
  return (
    'insert ${jsonEncode(insert)} in $element at $at',
    <int>[...part.sublist(0, at), ...utf8.encode(insert), ...part.sublist(at)],
  );
}

/// The token insert of a part with no element to insert into.
(String, List<int>) _insertAnywhere(
  Uint8List part,
  Xorshift32 random,
  String insert,
) {
  final int at = random.nextInt(part.length + 1);
  return (
    'insert ${jsonEncode(insert)} at $at',
    <int>[...part.sublist(0, at), ...utf8.encode(insert), ...part.sublist(at)],
  );
}

/// Puts one of [_tagTexts], or a random tag body of [_bodyAlphabet] between
/// `{{` and `}}`, into the text of a `w:t` of [part].
(String, List<int>) _insertTagText(
  String name,
  Uint8List part,
  Xorshift32 random,
) {
  final int pick = random.nextInt(_tagTexts.length + 1);
  final String insert;
  if (pick < _tagTexts.length) {
    insert = _tagTexts[pick];
  } else {
    final int length = 1 + random.nextInt(12);
    final StringBuffer body = StringBuffer('{{');
    for (int i = 0; i < length; i++) {
      body.write(_bodyAlphabet[random.nextInt(_bodyAlphabet.length)]);
    }
    insert = (body..write('}}')).toString();
  }
  // `"` and `{` are markup-safe in element text; `<` and `&` are not used.
  return _insertInto('w:t', part, random, insert) ??
      _insertAnywhere(part, random, insert);
}

/// Puts one of [_switches] into the text of a `w:instrText` of [part], or of
/// a `w:t` when it has none.
(String, List<int>) _insertSwitch(
  String name,
  Uint8List part,
  Xorshift32 random,
) {
  final String insert = _switches[random.nextInt(_switches.length)];
  return _insertInto('w:instrText', part, random, insert) ??
      _insertInto('w:t', part, random, insert) ??
      _insertAnywhere(part, random, insert);
}

/// The extra mutations of a case, after the eight of
/// `test/support/fuzz_mutations.dart`: the DOCX attribute mutation once, the
/// tag text insert three times and the switch insert twice, so about one case
/// in three changes a tag or a field.
const List<PartMutation> _extra = <PartMutation>[
  docxAttributeMutation,
  _insertTagText,
  _insertTagText,
  _insertTagText,
  _insertSwitch,
  _insertSwitch,
];

/// The first [count] cases of [seed], each one mutation of one corpus entry.
///
/// Lazy, and the same for the same arguments every time.
Iterable<FuzzCase> templateFuzzCases(int seed, int count) {
  final List<({String name, Uint8List bytes})> corpus = templateFuzzCorpus();
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
    tokens: docxFuzzTokens,
    extra: _extra,
    extraParts: _storyPart,
  );
}

/// The options of every fill: Turkish, as `tool/fill_docx.dart` fills.
const DocxTemplateOptions _options = DocxTemplateOptions(
  locale: FormatLocale.trTR,
);

/// Opens [bytes] as a template, reads every tag, fills it with
/// `fillDocxData()` and with data that names nothing, and checks both.
///
/// Throws [DocxReadException] only from `DocxTemplate(bytes)` (a file that
/// cannot be read) or from a fill (a part it loads that cannot be read);
/// anything else they throw is a defect and propagates. Once the template
/// opened:
///
/// * every tag's fields read, and every warning renders in every locale;
/// * the filled bytes open and their body and stories load, unless the
///   template's own refuse the same part: a failure there is a [StateError];
/// * `fill({})` changes nothing: `comparePackages` finds no difference
///   between it and the template opened, with its body and stories loaded as
///   the fill loads them, and saved unchanged (a [StateError] otherwise). That
///   is the template itself for a file the model saves as read; a mutated
///   package the model's own save rewrites (a `[Content_Types].xml` whose
///   namespace is not the package one is written with it; a relationship
///   without an `Id` is left out once the stories are loaded) is not the
///   fill's change. With [exact], the comparison is with [bytes] themselves,
///   as for the corpus. The check is skipped when the yardstick cannot
///   compare the input with itself (a part it cannot parse).
void exerciseTemplate(Uint8List bytes, {bool exact = false}) {
  final DocxTemplate template = DocxTemplate(bytes);
  for (final DocxTemplateTag tag in template.tags) {
    tag.kind.name;
    tag.name?.length;
    tag.format?.length;
    tag.text.length;
    tag.part.length;
    tag.location?.length;
    tag.problem?.name;
    tag.depth.isNegative;
  }
  final DocxResult filled = template.fill(fillDocxData(), options: _options);
  _render(filled.warnings);
  try {
    _loaded(filled.bytes);
  } on DocxReadException catch (e) {
    // A story part the template could not read either is copied as it was.
    if (!_storyRefused(bytes, e)) {
      throw StateError('the filled file does not read back: $e');
    }
  } on Object catch (e) {
    throw StateError('the filled file does not read back: $e');
  }
  final DocxResult empty = template.fill(
    <String, Object?>{},
    options: _options,
  );
  _render(empty.warnings);
  List<String>? same;
  try {
    same = comparePackages(bytes, bytes);
  } on Object {
    same = null;
  }
  if (same == null || same.isNotEmpty) return;
  final Uint8List expected;
  if (exact) {
    expected = bytes;
  } else {
    try {
      expected = _loaded(bytes).save().bytes;
    } on DocxReadException {
      return;
    }
  }
  final List<String> differences = comparePackages(expected, empty.bytes);
  if (differences.isNotEmpty) {
    throw StateError('fill({}) changed the template: ${differences.first}');
  }
}

/// [bytes] opened, with the body and the six stories of every section loaded.
DocxDocument _loaded(Uint8List bytes) {
  final DocxDocument doc = DocxDocument.open(bytes);
  doc.body.blocks.length;
  for (final DocxSection section in doc.sections) {
    for (final DocxHeaderFooter story in <DocxHeaderFooter>[
      section.header,
      section.firstHeader,
      section.evenHeader,
      section.footer,
      section.firstFooter,
      section.evenFooter,
    ]) {
      story.blocks.length;
    }
  }
  return doc;
}

/// Whether [e], from reading the filled file back, names a part that reading
/// the template [bytes] the same way refuses too.
bool _storyRefused(Uint8List bytes, DocxReadException e) {
  try {
    _loaded(bytes);
  } on DocxReadException catch (original) {
    return original.part == e.part;
  }
  return false;
}

/// Renders every warning of [warnings] in every locale.
void _render(List<DocxWarning> warnings) {
  for (final DocxWarning warning in warnings) {
    for (final OfficeLocale locale in OfficeLocale.values) {
      warning.message(locale);
    }
  }
}
