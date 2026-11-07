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
import 'table_document.dart';
import 'word_document.dart';

export '../../support/fuzz_mutations.dart'
    show FuzzCase, PartMutation, Xorshift32, mutatedPart;

/// The valid packages the fuzzer mutates, in a fixed order: `word_like`,
/// the Word-like document of `richWordDocx()` (tracked changes, a
/// hyperlink, content controls, a table, markup compatibility content,
/// fields and a bookmark), `localized_word`, the document of
/// `localizedWordDocx()` with Word's styles part (Turkish ids, `w14` and
/// `w15` content) and numbering part, then every fixture of
/// `docxFixtures()` (the `d3_*` and `d4_*` fixtures among them), `tables_by_hand`,
/// the document of `tablesByHandDocx()` with every element the table values
/// read, and every `producerVariants()` entry, each rebuilt with stored
/// entries and a fixed timestamp, so the bytes are equal on every platform.
///
/// Nothing is deflated, so inflation is fuzzed only by the archive
/// mutations, which damage the stored headers and sizes.
List<({String name, Uint8List bytes})> docxFuzzCorpus() =>
    <({String name, Uint8List bytes})>[
      (name: 'word_like', bytes: _rebuild(richWordDocx())),
      (name: 'localized_word', bytes: _rebuild(_localizedWithNumbering())),
      for (final DocxFixture f in docxFixtures())
        (name: f.name, bytes: _rebuild(f.build().bytes)),
      (name: 'tables_by_hand', bytes: _rebuild(tablesByHandDocx())),
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

/// How many of the operations of a case, out of eight plus this many, are
/// the attribute mutation: a share of about one in three, so that every
/// seed of the gate reaches the styles and numbering parts.
const int _attributeShare = 5;

/// The values the attribute mutation writes: text where a number is read,
/// a number past every range, a bare sign and a unit the readers do not
/// take.
const List<String> _attributeValues = <String>[
  'abc',
  '99999999999999999999',
  '-',
  '1in',
];

/// The attributes of the `w` prefix whose values the typed codecs read as
/// numbers, enumerations or flags: the ones the attribute mutation prefers.
const Set<String> typedAttributes = <String>{
  'val',
  'w',
  'left',
  'right',
  'start',
  'end',
  'hanging',
  'firstLine',
  'before',
  'after',
  'line',
  'lineRule',
  'sz',
  'szCs',
  'pos',
  'space',
  'color',
  'fill',
  'themeColor',
  'themeShade',
  'themeTint',
  'ilvl',
  'numId',
  'type',
  'leader',
  'ascii',
  'hAnsi',
  'eastAsia',
  'cs',
  'hRule',
  'firstRow',
  'lastRow',
  'firstColumn',
  'lastColumn',
  'noHBand',
  'noVBand',
};

/// Whether the part [name] holds typed properties: the main part, the
/// styles part and the numbering part.
bool _typedPart(String name) =>
    name == 'word/document.xml' ||
    name == 'word/styles.xml' ||
    name == 'word/numbering.xml';

/// Replaces the value of one `w:` attribute of [part], by one of
/// [_attributeValues].
///
/// It runs only on a part that holds typed properties ([_typedPart]) when
/// the document has one, and chooses uniformly among the `w:` attributes
/// named in [typedAttributes], among all `w:` attributes when it holds none,
/// and among all attributes when it holds no `w:` attribute. A part without
/// an attribute gets a token inserted instead, as the digit mutation does.
/// The description reads `replace <attribute> at <offset> with "<value>"`.
(String, List<int>) _replaceAttributeValue(
  String name,
  Uint8List part,
  Xorshift32 random,
) {
  final String text = latin1.decode(part);
  final List<RegExpMatch> all = RegExp(
    r'([\w:.-]+)="([^"]*)"',
  ).allMatches(text).toList();
  final List<RegExpMatch> w = <RegExpMatch>[
    for (final RegExpMatch m in all)
      if (m.group(1)!.startsWith('w:')) m,
  ];
  final List<RegExpMatch> typed = <RegExpMatch>[
    for (final RegExpMatch m in w)
      if (typedAttributes.contains(m.group(1)!.substring(2))) m,
  ];
  final List<RegExpMatch> found = typed.isNotEmpty
      ? typed
      : w.isNotEmpty
      ? w
      : all;
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
  final int from = match.start + match.group(1)!.length + 2;
  return (
    'replace ${match.group(1)} at $from with "$value"',
    <int>[
      ...part.sublist(0, from),
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
    extra: List<PartMutation>.filled(_attributeShare, _replaceAttributeValue),
    extraParts: _typedPart,
  );
}

/// Opens [bytes], renders every warning in English, German and Turkish,
/// reads the body, the styles and the numbering with every typed property,
/// edits what loaded, saves, and opens the saved bytes again.
///
/// Returns normally or throws [DocxReadException], and only from `open`,
/// from loading the body, the styles or the numbering (the first access to
/// `body`, `blocks`, `styles` or `numbering`), or from an edit of a part
/// that could not be used (`DocxStyles.ensure` on a styles part whose
/// content is not what it says): a file that opens but has such a part is
/// saved anyway (the part is copied as it was), and the first exception is
/// rethrown after the save and the reopen. Anything else thrown by `open`
/// or those steps is a defect and propagates at once.
///
/// Every table of what loaded is read (its properties, its rows' and its
/// cells', the grid, nested tables), then gets a row added and merges over
/// a range of its cells; only [ArgumentError] may come out of those edits.
/// A table the file left without rows is a read one: the save writes it as
/// read and throws no [StateError].
///
/// Reading a property or an accessor of what loaded throws nothing,
/// whatever the file holds: a [DocxReadException] from there is a defect
/// too, for the loading is guarded apart from the reading. When styles and
/// numbering both opened, `styles.ensure(DocxBuiltInStyle.heading1)` and
/// `numbering.addBulletList()` run before the save.
///
/// The model makes nothing worse: `save()` may throw nothing, the saved
/// bytes must open, and their body, styles and numbering must load unless
/// the input's did not; the styles then hold the id `ensure` returned and
/// the numbering has one instance more. A failure there is a [StateError]
/// naming the step, so a [DocxReadException] from a later step cannot pass
/// for a refused file.
void exerciseDocx(Uint8List bytes) {
  final DocxDocument doc = DocxDocument.open(bytes);
  DocxReadException? first;
  void refused(DocxReadException e) => first ??= e;
  DocxBody? body;
  List<DocxBlock>? blocks;
  DocxStyles? styles;
  DocxNumbering? numbering;
  _guard(() {
    body = doc.body;
    blocks = body!.blocks.toList();
  }, refused);
  _guard(() => styles = doc.styles, refused);
  _guard(() => numbering = doc.numbering, refused);
  if (blocks != null) {
    _walk(blocks!);
    docxEditTables(blocks!);
    body!.addParagraph('x').addRun('y');
  }
  if (styles != null) _readStyles(styles!);
  final int instancesBefore = numbering == null
      ? 0
      : _readNumbering(numbering!);
  String? ensured;
  bool listAdded = false;
  if (styles != null && numbering != null) {
    _guard(() {
      ensured = styles!.ensure(DocxBuiltInStyle.heading1);
      numbering!.addBulletList();
      listAdded = true;
    }, refused);
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
    bodyReadable: blocks != null,
    stylesReadable: styles != null,
    numberingReadable: numbering != null,
    ensuredId: ensured,
    instancesAfter: listAdded ? instancesBefore + 1 : null,
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

/// Reads every block, inline and run content of [blocks], and every typed
/// property of its paragraphs and runs.
void _walk(List<DocxBlock> blocks) {
  for (final DocxBlock block in blocks) {
    block.toString();
    if (block is DocxTable) {
      _table(block);
      continue;
    }
    if (block is! DocxParagraph) continue;
    block.text;
    block.style;
    _paragraph(block.properties);
    block.inlines.forEach(_inline);
  }
}

/// Reads [inline] and, for a field, its instruction and what is in its result.
void _inline(DocxInline inline) {
  inline.text;
  inline.toString();
  if (inline is DocxField) {
    inline.instruction;
    inline.name;
    inline.result.forEach(_inline);
  }
  if (inline is! DocxRun) return;
  inline.style;
  _run(inline.properties);
  for (final DocxRunContent content in inline.content) {
    content.toString();
  }
}

/// Reads every typed property of [table], its rows and its cells, and walks
/// the blocks of each cell, nested tables included.
void _table(DocxTable table) {
  final DocxTableProperties p = table.properties;
  <Object?>[
    p.style,
    p.width,
    p.layout,
    p.alignment,
    p.indentationPt,
    p.borders,
    p.cellMargins,
    p.look,
    table.gridColumnsPt,
  ].toString();
  for (final DocxTableRow row in table.rows) {
    final DocxTableRowProperties r = row.properties;
    <Object?>[r.height, r.cantSplit, r.repeatAsHeader, row.isHeader].toString();
    for (final DocxTableCell cell in row.cells) {
      final DocxTableCellProperties c = cell.properties;
      <Object?>[
        c.width,
        c.gridSpan,
        c.verticalMerge,
        c.verticalAlignment,
        c.shading,
        c.borders,
        c.textDirection,
        cell.toString(),
      ].toString();
      _walk(cell.blocks.toList());
    }
  }
}

/// Edits every table of [blocks] and of the cells below them: a row added,
/// then merges over a range of what loaded (the whole table, its first
/// rows and columns, its last cell, its first row, its first column).
///
/// Only [ArgumentError] may come out of the calls, for a table whose grid
/// or rows do not allow the edit; anything else, a [RangeError] too, is a
/// defect and propagates. Returns how many rows and merges took.
({int rows, int merges}) docxEditTables(List<DocxBlock> blocks) {
  int rows = 0;
  int merges = 0;
  for (final DocxBlock block in blocks) {
    if (block is! DocxTable) continue;
    final int columns = block.gridColumnsPt?.length ?? 0;

    /// Whether [edit] took. A [RangeError] is a bug inside the model: every
    /// argument here is in range or refused with a plain [ArgumentError].
    bool attempt(void Function() edit) {
      try {
        edit();
        return true;
      } on RangeError {
        rethrow;
      } on ArgumentError {
        // The table's shape does not allow it, as the API documents.
        return false;
      }
    }

    if (attempt(() => block.addRow(<String?>['x', null]))) rows++;
    final int last = block.rows.length - 1;
    for (final (int, int, int, int) range in <(int, int, int, int)>[
      (0, 0, last, columns - 1),
      (0, 0, 1, 1),
      (last, columns - 1, last, columns - 1),
      (0, 0, 0, columns - 1),
      (0, 0, last, 0),
    ]) {
      final bool merged = attempt(
        () => block.mergeCells(
          firstRow: range.$1,
          firstColumn: range.$2,
          lastRow: range.$3,
          lastColumn: range.$4,
        ),
      );
      if (merged) merges++;
    }
    for (final DocxTableRow row in block.rows) {
      for (final DocxTableCell cell in row.cells) {
        final ({int rows, int merges}) nested = docxEditTables(
          cell.blocks.toList(),
        );
        rows += nested.rows;
        merges += nested.merges;
      }
    }
  }
  return (rows: rows, merges: merges);
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
      style.isDefault,
      style.isCustom,
    ].toString();
    _paragraph(style.paragraphProperties);
    _run(style.runProperties);
    if (style.id case final String id) styles.byId(id);
    styles.byName(style.name ?? '');
  }
}

/// Reads every level, instance and override of [numbering]; returns how
/// many instances it lists.
int _readNumbering(DocxNumbering numbering) {
  for (final DocxAbstractNumbering abstract in numbering.abstractNumberings) {
    abstract.id.toString();
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
    <Object?>[
      instance.id,
      instance.abstractId,
      instance.abstractNumbering,
      numbering.instanceById(instance.id),
      instance.ref(),
    ].toString();
    for (final DocxLevelOverride o in instance.overrides) {
      o.startOverride.toString();
    }
  }
  return numbering.instances.length;
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
///
/// When [ensuredId] is not null the styles must hold that id; when
/// [instancesAfter] is not null the numbering must list that many
/// instances.
void _reopen(
  Uint8List saved, {
  required bool bodyReadable,
  required bool stylesReadable,
  required bool numberingReadable,
  required String? ensuredId,
  required int? instancesAfter,
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

  load('body', bodyReadable, () => _walk(again.body.blocks.toList()));
  load('styles', stylesReadable, () {
    final DocxStyles styles = again.styles;
    _readStyles(styles);
    if (ensuredId != null && styles.byId(ensuredId) == null) {
      throw StateError('the style "$ensuredId" ensure returned is missing');
    }
  });
  load('numbering', numberingReadable, () {
    final int count = _readNumbering(again.numbering);
    if (instancesAfter != null && count != instancesAfter) {
      throw StateError('$count instances, not $instancesAfter');
    }
  });
}
