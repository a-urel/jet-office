/// The walk of a template the fill and the listing share: its stories, their
/// paragraphs with the path a warning names, and every tag and `MERGEFIELD`
/// of a paragraph in reading order, with the problem its form has.
///
/// New in jet_office (decision 0024, spec sections 3.2, 5 and 8, Rulings 8,
/// 12, 13 and 14); quds_office_engine has no template fill, so this is not
/// ported from Quds. Reading a template edits nothing: the fill applies the
/// entries this walk gives, and the listing reports them.
library;

import 'package:jet_core/jet_core.dart' show FormatLocale;

import '../../opc/ooxml.dart' show Ns, RelType;
import '../../opc/package.dart' show OpcRelationship;
import '../docx_document.dart';
import '../docx_package.dart';
import '../model/blocks.dart';
import '../model/inlines.dart';
import '../model/run_content.dart';
import '../model/sections.dart';
import '../story_reader.dart' show readerOfCaptured;
import '../warnings.dart';
import 'merge_field.dart';
import 'opaque_scan.dart';
import 'paragraph_text.dart';
import 'tag_scanner.dart';

/// A story the fill walks: its blocks, the absolute name of its part and the
/// first segment of its paragraphs' paths (`body`, `header1.xml`).
typedef TemplateStory = ({List<DocxBlock> blocks, String part, String prefix});

/// The stories of [document] in reading order: the body, then for each
/// section its header, first header, even header, footer, first footer and
/// even footer, each part once and only when it has a part. Reading them
/// creates nothing in the file.
List<TemplateStory> templateStories(DocxDocument document) {
  final List<TemplateStory> out = <TemplateStory>[
    (
      blocks: document.body.blocks,
      part: docxPackageOf(document).mainPart,
      prefix: 'body',
    ),
  ];
  final Set<DocxHeaderFooter> seen = Set<DocxHeaderFooter>.identity();
  final Set<String> parts = <String>{};
  for (final DocxSection section in document.sections) {
    for (final DocxHeaderFooter story in <DocxHeaderFooter>[
      section.header,
      section.firstHeader,
      section.evenHeader,
      section.footer,
      section.firstFooter,
      section.evenFooter,
    ]) {
      if (!seen.add(story)) continue;
      final String? part = storyPartNameOf(story);
      if (part == null || !parts.add(part)) continue;
      out.add((
        blocks: story.blocks,
        part: part,
        prefix: part.substring(part.lastIndexOf('/') + 1),
      ));
    }
  }
  return out;
}

/// The footnotes, endnotes and comments parts of [package]'s main part, in
/// the order of its relationships, each once.
List<String> templateNoteParts(DocxPackage package) {
  final List<String> out = <String>[];
  final List<OpcRelationship> rels;
  try {
    rels = package.package.peekRelationships(package.mainPart);
  } on Exception {
    return out;
  }
  for (final OpcRelationship rel in rels) {
    if (rel.external) continue;
    if (rel.type != RelType.footnotes &&
        rel.type != RelType.endnotes &&
        rel.type != RelType.comments) {
      continue;
    }
    final String target = package.package.resolve(package.mainPart, rel.target);
    final String part = package.package.canonicalPartName(target) ?? target;
    if (!out.contains(part)) out.add(part);
  }
  return out;
}

/// One tag or `MERGEFIELD` of a template, as the walk found it.
final class TemplateEntry {
  TemplateEntry._({
    required this.offset,
    required this.text,
    required this.kind,
    required this.mergeField,
    required this.path,
    required this.format,
    required this.problem,
    this.map,
    this.match,
    this.field,
    this.merge,
  });

  /// Where the entry starts in its paragraph's text, for reading order.
  final int offset;

  /// The tag or the field instruction as written: a warning's detail.
  final String text;

  /// The tag's kind; `null` for a malformed tag or a merge field.
  final TagKind? kind;

  /// Whether the entry is a `MERGEFIELD`.
  final bool mergeField;

  /// The tag's path, or the merge field's name as one segment; empty when
  /// malformed.
  final List<String> path;

  /// The tag's format code, or the merge field's number or date picture.
  final String? format;

  /// What stops the entry being filled for its form, or `null`.
  final DocxWarningCode? problem;

  /// The paragraph's text and the tag's match, for a text tag.
  final ParagraphText? map;

  /// The tag's match in [map], for a text tag.
  final TagMatch? match;

  /// The typed `DocxField` or the opaque `w:fldSimple` of a merge field that
  /// can be filled.
  final DocxInline? field;

  /// The parsed instruction of [field].
  final MergeField? merge;
}

/// Walks [story]: [onParagraph] gets each paragraph's entries in reading
/// order, with the paragraph's path, right before the next paragraph is
/// read, so it may edit the paragraph; an opaque block's entries come with
/// its path too. Paragraphs in table cells and nested tables are walked.
/// A merge field's `\#` picture is read with [locale]'s separators
/// (`parseMergeField`).
void walkTemplateStory(
  TemplateStory story,
  int maxDepth,
  void Function(String location, List<TemplateEntry> entries) onParagraph, {
  FormatLocale locale = FormatLocale.enUS,
}) {
  _walkBlocks(story.blocks, story.prefix, maxDepth, onParagraph, locale);
}

void _walkBlocks(
  List<DocxBlock> blocks,
  String path,
  int maxDepth,
  void Function(String location, List<TemplateEntry> entries) onParagraph,
  FormatLocale locale,
) {
  int paragraphs = 0;
  int tables = 0;
  final Map<String, int> opaque = <String, int>{};
  for (final DocxBlock block in List<DocxBlock>.of(blocks)) {
    switch (block) {
      case DocxParagraph():
        final String at = '$path/p[${paragraphs++}]';
        onParagraph(at, paragraphEntries(block, maxDepth, locale: locale));
      case DocxTable():
        final String at = '$path/tbl[${tables++}]';
        final List<DocxTableRow> rows = block.rows;
        for (int r = 0; r < rows.length; r++) {
          final List<DocxTableCell> cells = rows[r].cells;
          for (int c = 0; c < cells.length; c++) {
            _walkBlocks(
              cells[c].blocks,
              '$at/tr[$r]/tc[$c]',
              maxDepth,
              onParagraph,
              locale,
            );
          }
        }
      case DocxOpaqueBlock():
        final String name = block.localName;
        final int index = opaque[name] ?? 0;
        opaque[name] = index + 1;
        final DocxWarningCode code = block.namespaceUri == Ns.w && name == 'sdt'
            ? DocxWarningCode.templatePlaceholderInContentControl
            : DocxWarningCode.templatePlaceholderNotTyped;
        final List<TemplateEntry> entries = <TemplateEntry>[
          for (final String s in placeholdersIn(
            opaqueBlockXml(block),
            maxDepth: maxDepth,
          ))
            placeholderEntry(s, code),
        ];
        if (entries.isNotEmpty) onParagraph('$path/$name[$index]', entries);
    }
  }
}

/// The entry for [text], a tag or a `MERGEFIELD` instruction found in opaque
/// content, which cannot be filled: [problem].
TemplateEntry placeholderEntry(
  String text,
  DocxWarningCode problem, {
  int offset = 0,
}) {
  final MergeField? merge = parseMergeField(text);
  if (merge != null) {
    return TemplateEntry._(
      offset: offset,
      text: text,
      kind: null,
      mergeField: true,
      path: <String>[merge.name],
      format: merge.numberFormat ?? merge.dateFormat,
      problem: problem,
    );
  }
  final List<TagMatch> matches = scanTags(text);
  final ParsedTag? tag = matches.length == 1 ? matches.single.tag : null;
  return TemplateEntry._(
    offset: offset,
    text: text,
    kind: tag?.kind,
    mergeField: false,
    path: tag?.path ?? const <String>[],
    format: tag?.format,
    problem: problem,
  );
}

/// The entries of [paragraph] in reading order: its text tags, its merge
/// fields, and what its opaque content holds; a merge field's `\#` picture
/// read with [locale]'s separators.
List<TemplateEntry> paragraphEntries(
  DocxParagraph paragraph,
  int maxDepth, {
  FormatLocale locale = FormatLocale.enUS,
}) {
  final ParagraphText map = paragraphTextOf(paragraph);
  final List<TemplateEntry> entries = <TemplateEntry>[
    for (final TagMatch m in scanTags(map.text)) _tagEntry(map, m),
  ];
  _InlineWalk(
    entries,
    maxDepth,
    locale,
  ).walk(paragraph.inlines, direct: true, counting: true);
  // A stable sort by offset; at one offset a field comes before the tag
  // that starts in its result, which cannot be filled anyway.
  final List<int> order = List<int>.generate(entries.length, (int i) => i)
    ..sort((int a, int b) {
      final int byOffset = entries[a].offset.compareTo(entries[b].offset);
      return byOffset != 0 ? byOffset : a.compareTo(b);
    });
  return <TemplateEntry>[for (final int i in order) entries[i]];
}

TemplateEntry _tagEntry(ParagraphText map, TagMatch m) {
  final ParsedTag? tag = m.tag;
  DocxWarningCode? problem;
  if (tag == null) {
    problem = DocxWarningCode.templateTagMalformed;
  } else {
    final ({Region region, bool crossesBoundary}) span = map.spanOf(
      m.start,
      m.end,
    );
    if (span.crossesBoundary) {
      problem = DocxWarningCode.templateTagMalformed;
    } else {
      problem = switch (span.region) {
        Region.fillable => null,
        Region.fieldResult => DocxWarningCode.templateTagMalformed,
        Region.revision => DocxWarningCode.templatePlaceholderInRevision,
        Region.contentControl =>
          DocxWarningCode.templatePlaceholderInContentControl,
        Region.opaque => DocxWarningCode.templatePlaceholderNotTyped,
      };
    }
    if (problem == null &&
        (tag.kind == TagKind.section ||
            tag.kind == TagKind.invertedSection ||
            tag.kind == TagKind.sectionEnd)) {
      // Ruling 12: sections are filled from T2; until then they stay.
      problem = DocxWarningCode.templateSectionMalformed;
    }
  }
  return TemplateEntry._(
    offset: m.start,
    text: m.text,
    kind: tag?.kind,
    mergeField: false,
    path: tag?.path ?? const <String>[],
    format: tag?.format,
    problem: problem,
    map: problem == null ? map : null,
    match: problem == null ? m : null,
  );
}

/// The walk of a paragraph's inlines for its merge fields and opaque
/// content, counting the offset of each as `paragraphTextOf` counts text.
final class _InlineWalk {
  _InlineWalk(this.entries, this.maxDepth, this.locale);

  final List<TemplateEntry> entries;
  final int maxDepth;
  final FormatLocale locale;
  int offset = 0;

  /// Walks [inlines]: [direct] when they are the paragraph's or a
  /// hyperlink's own (not inside a field), [counting] when their text is
  /// the paragraph's visible text (not a field's instruction).
  void walk(
    List<DocxInline> inlines, {
    required bool direct,
    required bool counting,
  }) {
    for (final DocxInline inline in inlines) {
      switch (inline) {
        case DocxRun():
          _run(inline, direct: direct, counting: counting);
        case DocxHyperlink():
          walk(inline.inlines, direct: direct, counting: counting);
        case DocxField():
          _field(inline, direct: direct, counting: counting);
        case DocxBookmarkStart() || DocxBookmarkEnd():
          break;
        case DocxOpaqueInline():
          _opaque(inline, direct: direct, counting: counting);
      }
    }
  }

  void _notTyped(String instruction) {
    entries.add(
      placeholderEntry(
        instruction,
        DocxWarningCode.templateFieldNotTyped,
        offset: offset,
      ),
    );
  }

  void _run(DocxRun run, {required bool direct, required bool counting}) {
    for (final DocxRunContent c in run.content) {
      switch (c) {
        case DocxText():
          if (counting) offset += c.text.length;
        case DocxFieldInstruction():
          // Loose instruction runs: a field the model could not pair.
          if (direct && parseMergeField(c.text) != null) _notTyped(c.text);
        case DocxOpaqueRunContent():
          for (final String s in placeholdersIn(
            opaqueRunContentXml(c),
            maxDepth: maxDepth,
          )) {
            entries.add(
              placeholderEntry(
                s,
                DocxWarningCode.templatePlaceholderNotTyped,
                offset: offset,
              ),
            );
          }
          if (counting) offset++;
        default:
          if (counting) offset++;
      }
    }
  }

  void _field(DocxField field, {required bool direct, required bool counting}) {
    final List<DocxInline> result = field.result;
    if (field.name == 'MERGEFIELD') {
      final String instruction = field.instruction;
      if (!direct) {
        // Ruling 8: a MERGEFIELD inside another field is not filled.
        _notTyped(instruction);
      } else {
        final MergeField? merge = parseMergeField(instruction, locale: locale);
        entries.add(_mergeEntry(instruction, merge, field));
      }
      walk(result, direct: false, counting: counting);
      return;
    }
    final List<DocxInline> held = heldInlinesOf(field)!;
    walk(
      held.sublist(0, held.length - 1 - result.length),
      direct: false,
      counting: false,
    );
    walk(result, direct: false, counting: counting);
  }

  TemplateEntry _mergeEntry(
    String instruction,
    MergeField? merge,
    DocxInline field,
  ) => TemplateEntry._(
    offset: offset,
    text: instruction,
    kind: null,
    mergeField: true,
    path: merge == null ? const <String>[] : <String>[merge.name],
    format: merge?.numberFormat ?? merge?.dateFormat,
    // A MERGEFIELD without a name cannot be filled.
    problem: merge == null ? DocxWarningCode.templateTagMalformed : null,
    field: merge == null ? null : field,
    merge: merge,
  );

  void _opaque(
    DocxOpaqueInline inline, {
    required bool direct,
    required bool counting,
  }) {
    final bool w = inline.namespaceUri == Ns.w;
    final String name = inline.localName;
    if (w && (name == 'del' || name == 'moveFrom')) return;
    if (w && name == 'fldSimple') {
      final String? instruction = _simpleInstruction(inline);
      final MergeField? merge = instruction == null
          ? null
          : parseMergeField(instruction, locale: locale);
      if (merge != null) {
        if (direct) {
          entries.add(_mergeEntry(instruction!, merge, inline));
        } else {
          _notTyped(instruction!);
        }
        if (counting) offset += inline.text.length;
        return;
      }
    }
    final DocxWarningCode code = !w
        ? DocxWarningCode.templatePlaceholderNotTyped
        : switch (name) {
            'ins' || 'moveTo' => DocxWarningCode.templatePlaceholderInRevision,
            'sdt' => DocxWarningCode.templatePlaceholderInContentControl,
            _ => DocxWarningCode.templatePlaceholderNotTyped,
          };
    // The tags of visible text are the paragraph text's; the text outside
    // any w:p of an element with text is that visible text, so only its
    // paragraphs (a text box's) are scanned for tags. A tag found here is
    // out of the paragraph's text, so not typed whatever holds it; a merge
    // field takes the holder's code.
    final bool visible = inline.text.isNotEmpty;
    for (final String s in placeholdersIn(
      opaqueInlineXml(inline),
      maxDepth: maxDepth,
      outsideParagraphs: !visible,
    )) {
      final bool merge = parseMergeField(s) != null;
      entries.add(
        placeholderEntry(
          s,
          merge ? code : DocxWarningCode.templatePlaceholderNotTyped,
          offset: offset,
        ),
      );
    }
    if (counting) offset += inline.text.length;
  }

  String? _simpleInstruction(DocxOpaqueInline inline) {
    try {
      return readerOfCaptured(
        opaqueInlineXml(inline),
        maxDepth,
      ).getAttribute('instr', namespaceUri: Ns.w);
    } on Exception {
      return null;
    }
  }
}
