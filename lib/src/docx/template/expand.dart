/// The edits a section fill makes on the model: a section's content repeated,
/// removed or shown once, in place, with its tags taken out.
///
/// New in jet_office (decision 0024, spec section 4.2, T2 plan Rulings 9 to
/// 11, 13, 14 and 17); quds_office_engine has no template fill, so this is
/// not ported from Quds. Every edit is one of the model's recorded edits
/// (`splitRunAt`, the paragraph's and the hyperlink's inline edits, a
/// table's rows, a container's blocks), so a fill made in a transaction is
/// undone whole. Copies are made from the content before it is filled
/// (`copyInlines`, `copyRows`, `copyBlocks`), so a value is never scanned
/// again, and leave annotations out; a removal takes the other half of a
/// paired mark with it (Ruling 11).
library;

import '../../opc/ooxml.dart' show Ns;
import '../../opc/opaque_xml.dart' show OpaqueXml;
import '../docx_document.dart';
import '../model/blocks.dart';
import '../model/inlines.dart';
import '../model/run_content.dart' show DocxText;
import '../model/template_copies.dart' show isDroppedByCopy;
import '../story_reader.dart' show readerOfCaptured;
import 'paragraph_text.dart';
import 'region.dart';
import 'replace.dart';
import 'sections.dart';
import 'template_walk.dart';

/// Whether [blocks], or a table in them at any depth, hold a paragraph that
/// carries a section break (Ruling 14): such content is never copied or
/// removed.
bool holdsSectionBreak(Iterable<DocxBlock> blocks) {
  for (final DocxBlock block in blocks) {
    bool found = false;
    visitBlocks(block, (DocxBlock b) {
      if (b is DocxParagraph && paragraphHasBreak(b)) found = true;
    });
    if (found) return true;
  }
  return false;
}

/// Whether the content of [pair] holds a paragraph with a section break
/// ([holdsSectionBreak]); inline content never does.
bool sectionHoldsBreak(SectionPair pair) {
  switch (pair.form) {
    case SectionForm.inline:
      return false;
    case SectionForm.rows:
      final (DocxTable table, int a, int b) = _rowsOf(pair);
      return holdsSectionBreak(<DocxBlock>[
        for (int r = a; r <= b; r++)
          for (final DocxTableCell cell in table.rows[r].cells) ...cell.blocks,
      ]);
    case SectionForm.blocks:
      final (Object container, int a, int b) = _blocksOf(pair);
      return holdsSectionBreak(containerBlocks(container).sublist(a + 1, b));
  }
}

/// What [repeatSection] made: the regions of the original content and of
/// each copy, in order; the annotations the copies left out
/// (`copyDroppedNames`); and whether removing the tags took the other half
/// of a paired mark (Ruling 11).
typedef RepeatResult = ({
  List<TemplateRegion> regions,
  Set<String> dropped,
  bool halves,
});

/// What [showSection] left: the region of the content, and whether removing
/// the tags took the other half of a paired mark (Ruling 11).
typedef ShowResult = ({TemplateRegion region, bool halves});

/// Repeats [pair]'s content [count] times (at least 1) in [region], in place:
/// the copies are made from the unfilled original and go right after it,
/// and the tags are removed. [openLocation] is the template path of the
/// opening tag's paragraph; [story] is the story the region is in, searched
/// for the other half of a mark the tags held.
///
/// The result's regions carry the template paths of the original (Ruling
/// 15). Content with a paragraph that carries a section break throws
/// [ArgumentError] (check [sectionHoldsBreak] first).
RepeatResult repeatSection(
  SectionPair pair,
  TemplateRegion region,
  int count,
  int maxDepth, {
  required String openLocation,
  required DocxStory story,
}) {
  if (count < 1) throw ArgumentError.value(count, 'count', 'must be >= 1');
  final Set<String> dropped = <String>{};
  switch (pair.form) {
    case SectionForm.inline:
      final _Inline at = _isolateInline(pair);
      final List<DocxInline> content = at.content;
      final List<List<DocxInline>> copies = <List<DocxInline>>[];
      for (int k = 1; k < count; k++) {
        final ({List<DocxInline> items, Set<String> dropped}) copy =
            copyInlines(content, maxDepth: maxDepth);
        dropped.addAll(copy.dropped);
        copies.add(copy.items);
      }
      final bool halves = _removeTagRuns(at, story, maxDepth, <DocxInline>[
        for (final List<DocxInline> c in copies) ...c,
      ]);
      return (
        regions: _inlineRegions(pair, at.list, content, copies, openLocation),
        dropped: dropped,
        halves: halves,
      );
    case SectionForm.rows:
      final (DocxTable table, int a, int b) = _rowsOf(pair);
      final List<int> templateRows = _templateRows(region, table, a, b);
      final String tablePath = _tablePath(openLocation);
      _removeRowTags(pair);
      const bool halves = false;
      final List<DocxTableRow> original = table.rows.sublist(a, b + 1);
      final int length = original.length;
      final List<DocxTableRow> copies = <DocxTableRow>[];
      for (int k = 1; k < count; k++) {
        final ({List<DocxTableRow> items, Set<String> dropped}) copy = copyRows(
          original,
          maxDepth: maxDepth,
        );
        dropped.addAll(copy.dropped);
        copies.addAll(copy.items);
      }
      // One edit for all copies: their place is found and the rows after
      // them move once.
      insertRowsAt(table, b + 1, copies);
      return (
        regions: <TemplateRegion>[
          for (int k = 0; k < count; k++)
            RowRegion(
              table,
              a + k * length,
              a + (k + 1) * length,
              templateRows,
              tablePath,
            ),
        ],
        dropped: dropped,
        halves: halves,
      );
    case SectionForm.blocks:
      final (Object container, int a, int b) = _blocksOf(pair);
      final List<DocxBlock> blocks = containerBlocks(container);
      final List<String> paths = _blockPaths(
        region,
        container,
        openLocation,
        a + 1,
        b,
      );
      final List<DocxBlock> original = blocks.sublist(a + 1, b);
      final int length = original.length;
      // A copy leaves out a bookmark or other mark that stands between
      // blocks, so its blocks and their paths are the original's without
      // those.
      final List<String> copyPaths = <String>[
        for (int i = 0; i < length; i++)
          if (!_droppedBlock(original[i])) paths[i],
      ];
      final List<DocxBlock> copies = <DocxBlock>[];
      for (int k = 1; k < count; k++) {
        final ({List<DocxBlock> items, Set<String> dropped}) copy = copyBlocks(
          original,
          maxDepth: maxDepth,
        );
        dropped.addAll(copy.dropped);
        copies.addAll(copy.items);
      }
      for (int i = 0; i < copies.length; i++) {
        insertContainerBlock(container, b + 1 + i, copies[i]);
      }
      final bool halves = _removeBlocks(
        container,
        <int>[b, a],
        story,
        maxDepth,
      );
      final int copyLength = copyPaths.length;
      return (
        regions: <TemplateRegion>[
          BlockRegion(container, blocks, a, a + length, paths),
          for (int k = 1; k < count; k++)
            BlockRegion(
              container,
              blocks,
              a + length + (k - 1) * copyLength,
              a + length + k * copyLength,
              copyPaths,
            ),
        ],
        dropped: dropped,
        halves: halves,
      );
  }
}

/// Removes [pair]'s content and both tags (Ruling 11) from [story]: a table
/// whose rows all went is removed, and a container left with no paragraph
/// gets an empty one. Returns whether the other half of a paired mark
/// (a bookmark, a comment range, a permission range or a move range) whose
/// one half was removed went too, found anywhere in [story].
///
/// Content with a paragraph that carries a section break throws
/// [ArgumentError] (check [sectionHoldsBreak] first).
bool removeSection(
  SectionPair pair,
  TemplateRegion region,
  DocxStory story,
  int maxDepth,
) {
  if (sectionHoldsBreak(pair)) {
    throw ArgumentError.value(
      pair.open.text,
      'pair',
      'must not hold a paragraph with a section break',
    );
  }
  switch (pair.form) {
    case SectionForm.inline:
      final _Inline at = _isolateInline(pair);
      final List<DocxInline> gone = at.list.sublist(
        _indexIn(at.list, at.openFirst),
        _indexIn(at.list, at.closeLast) + 1,
      );
      final _Marks marks = _Marks(maxDepth)..addInlines(gone);
      for (final DocxInline inline in gone.reversed) {
        removeHeldInline(inline);
      }
      return marks.removeOrphans(story);
    case SectionForm.rows:
      final (DocxTable table, int a, int last) = _rowsOf(pair);
      int b = last;
      final _Marks marks = _Marks(maxDepth);
      for (int r = a; r <= b; r++) {
        marks.addRow(table.rows[r]);
      }
      if (b - a + 1 == table.rows.length) {
        final (Object, int)? place = _tablePlace(pair);
        if (place != null) {
          final (Object container, int index) = place;
          removeContainerBlockAt(container, index);
          _ensureParagraph(container);
          return marks.removeOrphans(story);
        }
        // A table that is the region itself always keeps a row (Ruling 21).
        b--;
      }
      for (int r = b; r >= a; r--) {
        table.removeRowAt(r);
      }
      return marks.removeOrphans(story);
    case SectionForm.blocks:
      final (Object container, int a, int b) = _blocksOf(pair);
      return _removeBlocks(
        container,
        <int>[for (int i = b; i >= a; i--) i],
        story,
        maxDepth,
      );
  }
}

/// Removes [pair]'s tags only, so its content shows once; the result's
/// region is the content's, with the template paths of [region] (Ruling 15).
/// [openLocation] and [story] are as for [repeatSection].
ShowResult showSection(
  SectionPair pair,
  TemplateRegion region,
  int maxDepth, {
  required String openLocation,
  required DocxStory story,
}) {
  final RepeatResult result = repeatSection(
    pair,
    region,
    1,
    maxDepth,
    openLocation: openLocation,
    story: story,
  );
  return (region: result.regions.single, halves: result.halves);
}

/// The first block, row or inline of [region], or `null` when it is empty.
Object? firstUnitOf(TemplateRegion region) => switch (region) {
  BlockRegion() =>
    region.start < region.end ? region.blocks[region.start] : null,
  RowRegion() =>
    region.start < region.end ? region.table.rows[region.start] : null,
  InlineRegion() =>
    region.start < region.end ? region.inlines[region.start] : null,
};

/// [region] moved to where [first], its first unit as [firstUnitOf] gave it,
/// is now, its length kept: the copies of a section are filled one by one,
/// and filling one changes the length of what is before the next. [first] is
/// looked for from [from] on (the start of the copy filled before it, so all
/// copies together are searched once). [region] itself when it is empty or
/// did not move.
TemplateRegion rebased(TemplateRegion region, Object? first, {int from = 0}) {
  if (first == null) return region;
  switch (region) {
    case BlockRegion():
      final int at = region.blocks.indexWhere(
        (Object b) => identical(b, first),
        from,
      );
      if (at < 0 || at == region.start) return region;
      return BlockRegion(
        region.container,
        region.blocks,
        at,
        at + region.end - region.start,
        region.paths,
      );
    case RowRegion():
      final int at = region.table.rows.indexWhere(
        (Object r) => identical(r, first),
        from,
      );
      if (at < 0 || at == region.start) return region;
      return RowRegion(
        region.table,
        at,
        at + region.end - region.start,
        region.templateRows,
        region.tablePath,
      );
    case InlineRegion():
      final int at = region.inlines.indexWhere(
        (Object i) => identical(i, first),
        from,
      );
      if (at < 0 || at == region.start) return region;
      return InlineRegion(
        region.paragraph,
        region.inlines,
        at,
        at + region.end - region.start,
        region.path,
      );
  }
}

/// The index of [region]'s first unit in its list.
int startOf(TemplateRegion region) => switch (region) {
  BlockRegion() => region.start,
  RowRegion() => region.start,
  InlineRegion() => region.start,
};

/// The blocks of [container], a story or a table cell.
List<DocxBlock> containerBlocks(Object container) => switch (container) {
  final DocxStory story => story.blocks,
  final DocxTableCell cell => cell.blocks,
  _ => throw ArgumentError.value(container, 'container', 'holds no blocks'),
};

/// Inserts [block] at [index] of [container], a story or a table cell.
void insertContainerBlock(Object container, int index, DocxBlock block) {
  switch (container) {
    case final DocxStory story:
      story.insertBlock(index, block);
    case final DocxTableCell cell:
      cell.insertBlock(index, block);
    default:
      throw ArgumentError.value(container, 'container', 'holds no blocks');
  }
}

/// Removes the block at [index] of [container], a story or a table cell.
void removeContainerBlockAt(Object container, int index) {
  switch (container) {
    case final DocxStory story:
      story.removeBlockAt(index);
    case final DocxTableCell cell:
      cell.removeBlockAt(index);
    default:
      throw ArgumentError.value(container, 'container', 'holds no blocks');
  }
}

/// Gives [container] an empty paragraph when it has none, and a cell one at
/// its end when its last block is not a paragraph, as Word requires.
void _ensureParagraph(Object container) {
  final List<DocxBlock> blocks = containerBlocks(container);
  final bool cell = container is DocxTableCell;
  final bool needs = cell
      ? blocks.isEmpty || blocks.last is! DocxParagraph
      : !blocks.any((DocxBlock b) => b is DocxParagraph);
  if (needs) {
    insertContainerBlock(container, blocks.length, DocxParagraph());
  }
}

/// Removes the blocks at [indexes] (from the last to the first) of
/// [container], then the other halves of the marks they held; gives the
/// container a paragraph when it is left with none.
bool _removeBlocks(
  Object container,
  List<int> indexes,
  DocxStory story,
  int maxDepth,
) {
  final List<DocxBlock> blocks = containerBlocks(container);
  final _Marks marks = _Marks(maxDepth);
  for (final int i in indexes) {
    marks.addBlock(blocks[i]);
  }
  for (final int i in indexes) {
    removeContainerBlockAt(container, i);
  }
  _ensureParagraph(container);
  return marks.removeOrphans(story);
}

/// Whether a copy of blocks leaves [block] out: a mark kept as an opaque
/// block (`copyDroppedNames`).
bool _droppedBlock(DocxBlock block) =>
    block is DocxOpaqueBlock &&
    isDroppedByCopy(block.namespaceUri, block.localName);

/// The table and the first and last row of a rows pair.
(DocxTable, int, int) _rowsOf(SectionPair pair) {
  final CellStep a = pair.open.steps[pair.open.steps.length - 2] as CellStep;
  final CellStep b = pair.close.steps[pair.close.steps.length - 2] as CellStep;
  return (a.table as DocxTable, a.row, b.row);
}

/// The container and the indexes of the two tag paragraphs of a blocks pair.
(Object, int, int) _blocksOf(SectionPair pair) {
  final BlockStep a = pair.open.steps.last as BlockStep;
  final BlockStep b = pair.close.steps.last as BlockStep;
  return (a.container, a.index, b.index);
}

/// The container of a rows pair's table and its index there, or `null`
/// when the table is the region's own (its steps start at the table).
(Object, int)? _tablePlace(SectionPair pair) {
  final List<SiteStep> steps = pair.open.steps;
  final int cell = steps.length - 2;
  if (cell < 1) return null;
  final SiteStep step = steps[cell - 1];
  return step is BlockStep ? (step.container, step.index) : null;
}

/// The template path of the table of a tag whose paragraph's template path
/// is [location] (`.../tbl[0]/tr[1]/tc[0]/p[0]`).
String _tablePath(String location) {
  final int at = location.lastIndexOf('/tr[');
  return at < 0 ? location : location.substring(0, at);
}

/// The template index of each row [a] to [b] of [table]: the region's own
/// for a row region of that table, else the row's index, as no row of a
/// table that was not repeated yet moved.
List<int> _templateRows(TemplateRegion region, DocxTable table, int a, int b) {
  if (region is RowRegion && identical(region.table, table)) {
    return <int>[
      for (int r = a; r <= b; r++) region.templateRows[r - region.start],
    ];
  }
  return <int>[for (int r = a; r <= b; r++) r];
}

/// The template paths of blocks `[from, to)` of [container]: the region's
/// own when it is the region's container, else counted in the cell as the
/// walk counts them, under the cell of [openLocation].
List<String> _blockPaths(
  TemplateRegion region,
  Object container,
  String openLocation,
  int from,
  int to,
) {
  if (region is BlockRegion && identical(region.container, container)) {
    return region.paths.sublist(from - region.start, to - region.start);
  }
  final String cell = openLocation.substring(0, openLocation.lastIndexOf('/'));
  final List<DocxBlock> blocks = containerBlocks(container);
  int paragraphs = 0;
  int tables = 0;
  final Map<String, int> opaque = <String, int>{};
  final List<String> out = <String>[];
  for (int i = 0; i < to; i++) {
    final DocxBlock b = blocks[i];
    final String at = switch (b) {
      DocxParagraph() => '$cell/p[${paragraphs++}]',
      DocxTable() => '$cell/tbl[${tables++}]',
      DocxOpaqueBlock() => () {
        final int n = opaque[b.localName] ?? 0;
        opaque[b.localName] = n + 1;
        return '$cell/${b.localName}[$n]';
      }(),
    };
    if (i >= from) out.add(at);
  }
  return out;
}

int _indexIn(List<DocxInline> list, DocxInline inline) {
  final int i = list.indexWhere((DocxInline x) => identical(x, inline));
  if (i < 0) throw StateError('The inline is not in its list.');
  return i;
}

/// An inline pair with its tags split out into whole runs.
final class _Inline {
  _Inline(
    this.list,
    this.openFirst,
    this.openLast,
    this.closeFirst,
    this.closeLast,
  );

  /// The inline list both tags are in.
  final List<DocxInline> list;
  final DocxRun openFirst;
  final DocxRun openLast;
  final DocxRun closeFirst;
  final DocxRun closeLast;

  /// The inlines between the tags.
  List<DocxInline> get content =>
      list.sublist(_indexIn(list, openLast) + 1, _indexIn(list, closeFirst));
}

/// Splits the runs of an inline pair at its tags' edges (Ruling 17), the
/// closing tag first, so the opening tag's positions stay valid.
_Inline _isolateInline(SectionPair pair) {
  final Object level = pair.open.level;
  final List<DocxInline> list = level is DocxHyperlink
      ? level.inlines
      : (level as DocxParagraph).inlines;
  final (DocxRun closeFirst, DocxRun closeLast) = _isolate(
    pair.close.payload! as TemplateEntry,
  );
  final (DocxRun openFirst, DocxRun openLast) = _isolate(
    pair.open.payload! as TemplateEntry,
  );
  return _Inline(list, openFirst, openLast, closeFirst, closeLast);
}

/// Splits runs so the tag [e] is made of whole runs; its first and last run.
/// Splits only to the right of earlier positions of [e]'s map, whose run
/// keeps what comes before, so they stay valid.
(DocxRun, DocxRun) _isolate(TemplateEntry e) {
  final ParagraphText map = e.map!;
  final TextPosition first = map.positions[e.match!.start];
  final TextPosition last = map.positions[e.match!.end - 1];
  DocxRun firstRun = first.run!;
  DocxRun lastRun = last.run!;
  final int length = _textLength(lastRun, last.contentIndex);
  if (last.offset + 1 < length ||
      last.contentIndex < lastRun.content.length - 1) {
    splitRunAt(lastRun, last.contentIndex, last.offset + 1);
  }
  if (first.offset > 0 || first.contentIndex > 0) {
    final DocxRun tail = splitRunAt(firstRun, first.contentIndex, first.offset);
    if (identical(firstRun, lastRun)) lastRun = tail;
    firstRun = tail;
  }
  return (firstRun, lastRun);
}

int _textLength(DocxRun run, int contentIndex) {
  final Object content = run.content[contentIndex];
  return content is DocxText ? content.text.length : 0;
}

/// Removes the runs of both tags of [at] (marks between a tag's runs stay)
/// and puts [after] where the closing tag was; whether a mark's other half
/// went with them.
bool _removeTagRuns(
  _Inline at,
  DocxStory story,
  int maxDepth,
  List<DocxInline> after,
) {
  final List<DocxInline> list = at.list;
  final List<DocxRun> runs = <DocxRun>[];
  void collect(DocxRun first, DocxRun last) {
    final int a = _indexIn(list, first);
    final int b = _indexIn(list, last);
    for (int i = a; i <= b; i++) {
      final DocxInline inline = list[i];
      if (inline is DocxRun) runs.add(inline);
    }
  }

  collect(at.openFirst, at.openLast);
  collect(at.closeFirst, at.closeLast);
  final _Marks marks = _Marks(maxDepth)..addInlines(runs);
  // The copies take the closing tag's last run's place, in one edit.
  final DocxRun last = runs.removeLast();
  spliceHeldInline(last, after);
  for (final DocxRun run in runs.reversed) {
    removeHeldInline(run);
  }
  return marks.removeOrphans(story);
}

/// Removes the text of both tags of a rows pair, which are in two
/// paragraphs; the marks between a tag's runs stay where they are.
void _removeRowTags(SectionPair pair) {
  for (final SectionTagSite site in <SectionTagSite>[pair.close, pair.open]) {
    final TemplateEntry e = site.payload! as TemplateEntry;
    replaceSpan(e.map!, e.match!.start, e.match!.end, '');
  }
}

/// The regions of the original [content] and of each of [copies], which
/// follow it in [list]: the original is looked for once, and each copy starts
/// where the one before it ends, so many copies cost no search each.
List<TemplateRegion> _inlineRegions(
  SectionPair pair,
  List<DocxInline> list,
  List<DocxInline> content,
  List<List<DocxInline>> copies,
  String path,
) {
  final Object level = pair.open.level;
  final DocxParagraph paragraph = level is DocxParagraph
      ? level
      : paragraphOf(level as DocxHyperlink)!;
  if (content.isEmpty) {
    return <TemplateRegion>[
      for (int k = 0; k <= copies.length; k++)
        InlineRegion(paragraph, list, 0, 0, path),
    ];
  }
  // A copy may be shorter than the original: it leaves bookmarks out.
  int start = _indexIn(list, content.first);
  final List<TemplateRegion> out = <TemplateRegion>[];
  for (int k = 0; k <= copies.length; k++) {
    final int length = k == 0 ? content.length : copies[k - 1].length;
    out.add(InlineRegion(paragraph, list, start, start + length, path));
    start += length;
  }
  return out;
}

/// The kinds of paired marks, by their `w:` local name: the kind and
/// whether it is the start.
const Map<String, (String, bool)> _markNames = <String, (String, bool)>{
  'bookmarkStart': ('bookmark', true),
  'bookmarkEnd': ('bookmark', false),
  'commentRangeStart': ('comment', true),
  'commentRangeEnd': ('comment', false),
  'permStart': ('perm', true),
  'permEnd': ('perm', false),
  'moveFromRangeStart': ('moveFrom', true),
  'moveFromRangeEnd': ('moveFrom', false),
  'moveToRangeStart': ('moveTo', true),
  'moveToRangeEnd': ('moveTo', false),
};

/// The paired marks of removed content, and the removal of their other
/// halves from a story (Ruling 11).
final class _Marks {
  _Marks(this.maxDepth);

  final int maxDepth;
  final Set<String> starts = <String>{};
  final Set<String> ends = <String>{};

  void _add((String, bool)? mark) {
    if (mark == null) return;
    (mark.$2 ? starts : ends).add(mark.$1);
  }

  void addInlines(Iterable<DocxInline> inlines) {
    for (final DocxInline inline in inlines) {
      _add(_inlineMark(inline));
      final List<DocxInline>? held = inline is DocxHyperlink
          ? inline.inlines
          : heldInlinesOf(inline);
      if (held != null) addInlines(held);
    }
  }

  void addBlock(DocxBlock block) {
    visitBlocks(block, (DocxBlock b) {
      switch (b) {
        case DocxParagraph():
          addInlines(b.inlines);
        case DocxOpaqueBlock():
          _add(_blockMark(b));
        case DocxTable():
          break;
      }
    });
  }

  void addRow(DocxTableRow row) {
    for (final DocxTableCell cell in row.cells) {
      cell.blocks.forEach(addBlock);
    }
  }

  (String, bool)? _inlineMark(DocxInline inline) {
    switch (inline) {
      case DocxBookmarkStart():
        final int? id = inline.id;
        return (
          id == null ? 'bookmark#${identityHashCode(inline)}' : 'bookmark:$id',
          true,
        );
      case DocxBookmarkEnd():
        final int? id = inline.id;
        final DocxBookmarkStart? start = inline.start;
        if (id != null) return ('bookmark:$id', false);
        if (start == null) return null;
        return ('bookmark#${identityHashCode(start)}', false);
      case DocxOpaqueInline() when inline.namespaceUri == Ns.w:
        return _opaqueMark(inline.localName, () => opaqueInlineXml(inline));
      default:
        return null;
    }
  }

  (String, bool)? _blockMark(DocxOpaqueBlock block) =>
      block.namespaceUri != Ns.w
      ? null
      : _opaqueMark(block.localName, () => opaqueBlockXml(block));

  (String, bool)? _opaqueMark(String localName, OpaqueXml Function() xml) {
    final (String, bool)? kind = _markNames[localName];
    if (kind == null) return null;
    String? id;
    try {
      id = readerOfCaptured(
        xml(),
        maxDepth,
      ).getAttribute('id', namespaceUri: Ns.w);
    } on Exception {
      return null;
    }
    if (id == null) return null;
    return ('${kind.$1}:$id', kind.$2);
  }

  /// Removes from [story] each mark whose other half was removed; whether
  /// any went.
  bool removeOrphans(DocxStory story) {
    final Set<String> startsOnly = starts.difference(ends);
    final Set<String> endsOnly = ends.difference(starts);
    if (startsOnly.isEmpty && endsOnly.isEmpty) return false;
    bool orphan((String, bool)? mark) =>
        mark != null &&
        (mark.$2 ? endsOnly.contains(mark.$1) : startsOnly.contains(mark.$1));

    final List<DocxInline> inlines = <DocxInline>[];
    void walkInlines(List<DocxInline> list) {
      for (final DocxInline inline in list) {
        if (orphan(_inlineMark(inline))) inlines.add(inline);
        // A field and a hyperlink hold marks too, as [addInlines] reads them.
        final List<DocxInline>? held = inline is DocxHyperlink
            ? inline.inlines
            : heldInlinesOf(inline);
        if (held != null) walkInlines(held);
      }
    }

    void walkBlocks(Object container) {
      for (final DocxBlock block in containerBlocks(container)) {
        switch (block) {
          case DocxParagraph():
            walkInlines(block.inlines);
          case DocxTable():
            for (final DocxTableRow row in block.rows) {
              row.cells.forEach(walkBlocks);
            }
          case DocxOpaqueBlock():
            // A mark between blocks stays: removing a block would move the
            // blocks the fill still has to reach by their index.
            break;
        }
      }
    }

    walkBlocks(story);
    for (final DocxInline inline in inlines.reversed) {
      if (isInField(inline)) {
        removeFieldMark(inline);
      } else {
        removeHeldInline(inline);
      }
    }
    return inlines.isNotEmpty;
  }
}
