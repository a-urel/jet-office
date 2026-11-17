/// The regions a section fill works on (a range of blocks, of table rows, or
/// of inlines) and the walk of a region into its paragraphs, their entries
/// and their section tag sites.
///
/// New in jet_office (decision 0024, spec sections 4.1 and 8, T2 plan Rulings
/// 8, 13, 14 and 15); quds_office_engine has no template fill, so this is not
/// ported from Quds. The walk reads the model and edits nothing. A region
/// carries the template paths of what it holds, so a warning in a copy names
/// the template paragraph the copy was made from.
library;

import 'package:jet_core/jet_core.dart' show FormatLocale;

import '../../opc/ooxml.dart' show Ns;
import '../model/blocks.dart';
import '../model/inlines.dart';
import '../model/table_formatting.dart' show DocxVerticalMerge;
import 'paragraph_text.dart';
import 'sections.dart';
import 'tag_scanner.dart';
import 'template_walk.dart';

/// A part of a story a section fill works on.
sealed class TemplateRegion {
  /// Creates a region.
  const TemplateRegion();
}

/// Blocks `[start, end)` of [container]'s [blocks]; [paths]`[k]` is the
/// template path of `blocks[start + k]` (Ruling 15).
final class BlockRegion extends TemplateRegion {
  /// Creates a block region.
  const BlockRegion(
    this.container,
    this.blocks,
    this.start,
    this.end,
    this.paths,
  );

  /// The owner of [blocks] (a story's block list owner or a cell), the
  /// container of the region's sites' first [BlockStep].
  final Object container;

  /// The block list.
  final List<DocxBlock> blocks;

  /// The first block of the region.
  final int start;

  /// The end of the region, exclusive.
  final int end;

  /// The template path of each block of the region.
  final List<String> paths;
}

/// Rows `[start, end)` of [table]; [templateRows]`[k]` is the template index
/// of `rows[start + k]`; [tablePath] the table's template path.
final class RowRegion extends TemplateRegion {
  /// Creates a row region.
  const RowRegion(
    this.table,
    this.start,
    this.end,
    this.templateRows,
    this.tablePath,
  );

  /// The table.
  final DocxTable table;

  /// The first row of the region.
  final int start;

  /// The end of the region, exclusive.
  final int end;

  /// The template index of each row of the region.
  final List<int> templateRows;

  /// The table's template path.
  final String tablePath;
}

/// Inlines `[start, end)` of [inlines], the list of [paragraph] or of a
/// hyperlink in it; [path] the paragraph's template path.
final class InlineRegion extends TemplateRegion {
  /// Creates an inline region.
  const InlineRegion(
    this.paragraph,
    this.inlines,
    this.start,
    this.end,
    this.path,
  );

  /// The paragraph.
  final DocxParagraph paragraph;

  /// The inline list: the paragraph's own or a hyperlink's in it.
  final List<DocxInline> inlines;

  /// The first inline of the region.
  final int start;

  /// The end of the region, exclusive.
  final int end;

  /// The paragraph's template path.
  final String path;
}

/// One paragraph of a region as the fill meets it: its template path, the
/// steps from the region to it (an opaque block's own [BlockStep] last), the
/// paragraph and its text (both `null` for an opaque block, whose entries
/// can none be filled), its entries in reading order and its section tag
/// sites.
///
/// A section tag that can be filled where it stands is an entry with no
/// problem, keeping its map and match, and a site whose payload is that
/// entry; any other section tag is an entry with its problem and no site.
typedef RegionParagraph = ({
  String location,
  List<SiteStep> steps,
  DocxParagraph? paragraph,
  ParagraphText? map,
  List<TemplateEntry> entries,
  List<SectionTagSite> sites,
});

/// The paragraphs of [region] in reading order, every one, with the opaque
/// blocks that hold a tag or a merge field (as T1's walk reports them),
/// their entries and their section tag sites, whose steps start at the
/// region: at its container for a [BlockRegion], at
/// its table's [CellStep] for a [RowRegion], and empty for an
/// [InlineRegion]. A merge field's `\#` picture is read with [locale]'s
/// separators.
///
/// Throws [RangeError] when the region's range is not inside its list, and
/// [ArgumentError] when its template paths or rows do not cover the range.
List<RegionParagraph> scanRegion(
  TemplateRegion region,
  int maxDepth, {
  FormatLocale locale = FormatLocale.enUS,
}) {
  // The fields a story keeps as runs, from the region's start: a region the
  // fill expands starts outside any (Ruling 22).
  final _RegionWalk walk = _RegionWalk(maxDepth, locale, LooseFields());
  switch (region) {
    case BlockRegion():
      RangeError.checkValidRange(
        region.start,
        region.end,
        region.blocks.length,
        'start',
        'end',
      );
      if (region.paths.length != region.end - region.start) {
        throw ArgumentError.value(
          region.paths.length,
          'paths',
          'A block region of ${region.end - region.start} blocks needs as '
              'many paths.',
        );
      }
      for (int i = region.start; i < region.end; i++) {
        walk.block(
          region.container,
          region.blocks[i],
          i,
          region.paths[i - region.start],
          const <SiteStep>[],
        );
      }
    case RowRegion():
      final DocxTable table = region.table;
      RangeError.checkValidRange(
        region.start,
        region.end,
        table.rows.length,
        'start',
        'end',
      );
      if (region.templateRows.length != region.end - region.start) {
        throw ArgumentError.value(
          region.templateRows.length,
          'templateRows',
          'A row region of ${region.end - region.start} rows needs as many '
              'template rows.',
        );
      }
      for (int r = region.start; r < region.end; r++) {
        final int template = region.templateRows[r - region.start];
        final int cells = table.rows[r].cells.length;
        for (int c = 0; c < cells; c++) {
          walk.cell(
            table,
            r,
            c,
            '${region.tablePath}/tr[$template]/tc[$c]',
            const <SiteStep>[],
          );
        }
      }
    case InlineRegion():
      RangeError.checkValidRange(
        region.start,
        region.end,
        region.inlines.length,
        'start',
        'end',
      );
      walk.inlineRange(region);
  }
  return walk.out;
}

final class _RegionWalk {
  _RegionWalk(this.maxDepth, this.locale, this.fields);

  final int maxDepth;
  final FormatLocale locale;
  final LooseFields fields;
  final List<RegionParagraph> out = <RegionParagraph>[];

  /// Walks [block], the [index]-th of [container], whose template path is
  /// [path]; [prefix] leads from the region to [container].
  void block(
    Object container,
    DocxBlock block,
    int index,
    String path,
    List<SiteStep> prefix,
  ) {
    switch (block) {
      case DocxParagraph():
        final List<SiteStep> steps = List<SiteStep>.unmodifiable(<SiteStep>[
          ...prefix,
          BlockStep(container, index),
        ]);
        _paragraph(
          block,
          block.inlines,
          0,
          block.inlines.length,
          path,
          steps,
          block,
        );
      case DocxTable():
        final List<SiteStep> at = <SiteStep>[
          ...prefix,
          BlockStep(container, index),
        ];
        final List<DocxTableRow> rows = block.rows;
        for (int r = 0; r < rows.length; r++) {
          for (int c = 0; c < rows[r].cells.length; c++) {
            cell(block, r, c, '$path/tr[$r]/tc[$c]', at);
          }
        }
      case DocxOpaqueBlock():
        final List<TemplateEntry> entries = opaqueBlockEntries(block, maxDepth);
        if (entries.isNotEmpty) {
          out.add((
            location: path,
            steps: List<SiteStep>.unmodifiable(<SiteStep>[
              ...prefix,
              BlockStep(container, index),
            ]),
            paragraph: null,
            map: null,
            entries: entries,
            sites: const <SectionTagSite>[],
          ));
        }
    }
  }

  /// Walks cell [c] of row [r] of [table], whose template path is [path];
  /// [prefix] leads from the region to the table.
  void cell(DocxTable table, int r, int c, String path, List<SiteStep> prefix) {
    final DocxTableCell cell = table.rows[r].cells[c];
    final List<SiteStep> inCell = <SiteStep>[...prefix, CellStep(table, r, c)];
    int paragraphs = 0;
    int tables = 0;
    final Map<String, int> opaque = <String, int>{};
    final List<DocxBlock> blocks = cell.blocks;
    for (int i = 0; i < blocks.length; i++) {
      final DocxBlock b = blocks[i];
      final String at = switch (b) {
        DocxParagraph() => '$path/p[${paragraphs++}]',
        DocxTable() => '$path/tbl[${tables++}]',
        DocxOpaqueBlock() => () {
          final int n = opaque[b.localName] ?? 0;
          opaque[b.localName] = n + 1;
          return '$path/${b.localName}[$n]';
        }(),
      };
      block(cell, b, i, at, inCell);
    }
  }

  void inlineRange(InlineRegion region) {
    final DocxParagraph paragraph = region.paragraph;
    _paragraph(
      paragraph,
      region.inlines,
      region.start,
      region.end,
      region.path,
      const <SiteStep>[],
      _ownerOf(paragraph, region.inlines),
    );
  }

  /// Adds the inlines `[start, end)` of [inlines] of [paragraph] at [path]:
  /// the whole paragraph, or an inline region's range; [steps] lead from the
  /// region to the paragraph, [owner] holds [inlines].
  void _paragraph(
    DocxParagraph paragraph,
    List<DocxInline> inlines,
    int start,
    int end,
    String path,
    List<SiteStep> steps,
    Object owner,
  ) {
    final bool whole = start == 0 && end == inlines.length;
    final ParagraphText map = whole && identical(inlines, paragraph.inlines)
        ? paragraphTextOf(paragraph, fields: fields)
        : inlineRangeTextOf(inlines, start, end, fields: fields);
    final List<TemplateEntry> entries = rangeEntries(
      map,
      inlines,
      start,
      end,
      maxDepth,
      locale: locale,
      sections: true,
    );
    final List<SectionTagSite> sites = <SectionTagSite>[];
    Map<DocxRun, Object>? levels;
    bool? field;
    for (final TemplateEntry e in entries) {
      final TagKind? kind = e.kind;
      final TagMatch? match = e.match;
      if (e.problem != null ||
          match == null ||
          (kind != TagKind.section &&
              kind != TagKind.invertedSection &&
              kind != TagKind.sectionEnd)) {
        continue;
      }
      levels ??= _levels(inlines.sublist(start, end), owner);
      field ??= _holdsField(inlines.sublist(start, end));
      final DocxRun? run = map.positions[match.start].run;
      sites.add(
        SectionTagSite(
          kind: kind!,
          path: e.path,
          text: e.text,
          steps: steps,
          level: (run == null ? null : levels[run]) ?? owner,
          offset: e.offset,
          alone: !field && _blankOutside(map, match.start, match.end),
          breaksSection: paragraphHasBreak(paragraph),
          crossesMerge: _crossesMerge(steps, kind),
          payload: e,
        ),
      );
    }
    out.add((
      location: path,
      steps: steps,
      paragraph: paragraph,
      map: map,
      entries: entries,
      sites: List<SectionTagSite>.unmodifiable(sites),
    ));
  }
}

/// The paragraph or the hyperlink in it whose own list is [inlines].
Object _ownerOf(DocxParagraph paragraph, List<DocxInline> inlines) {
  if (identical(inlines, paragraph.inlines)) return paragraph;
  DocxHyperlink? find(List<DocxInline> list) {
    for (final DocxInline inline in list) {
      if (inline is DocxHyperlink) {
        if (identical(inline.inlines, inlines)) return inline;
        final DocxHyperlink? inner = find(inline.inlines);
        if (inner != null) return inner;
      }
    }
    return null;
  }

  return find(paragraph.inlines) ?? paragraph;
}

/// Each run of [inlines] and of the hyperlinks in them, by the paragraph or
/// hyperlink whose own list holds it: [owner] for [inlines]' own.
Map<DocxRun, Object> _levels(List<DocxInline> inlines, Object owner) {
  final Map<DocxRun, Object> out = Map<DocxRun, Object>.identity();
  void walk(List<DocxInline> list, Object level) {
    for (final DocxInline inline in list) {
      switch (inline) {
        case DocxRun():
          out[inline] = level;
        case DocxHyperlink():
          walk(inline.inlines, inline);
        default:
          break;
      }
    }
  }

  walk(inlines, owner);
  return out;
}

/// Whether [inlines] or a hyperlink in them hold a field, typed or a
/// `w:fldSimple`: a tag beside one is not alone (Ruling 8).
bool _holdsField(List<DocxInline> inlines) {
  for (final DocxInline inline in inlines) {
    switch (inline) {
      case DocxField():
        return true;
      case DocxHyperlink():
        if (_holdsField(inline.inlines)) return true;
      case DocxOpaqueInline()
          when inline.namespaceUri == Ns.w && inline.localName == 'fldSimple':
        return true;
      default:
        break;
    }
  }
  return false;
}

/// Whether [map]'s text outside `[start, end)` is only U+0020, U+00A0 and
/// comment references (Ruling 8); a tab, a break, a picture, a note
/// reference or other opaque content is a [nonText] there, which is not.
bool _blankOutside(ParagraphText map, int start, int end) {
  final String text = map.text;
  bool blank(int from, int to) {
    for (int i = from; i < to; i++) {
      final int unit = text.codeUnitAt(i);
      if (unit != 0x20 && unit != 0xA0 && !map.isCommentReference(i)) {
        return false;
      }
    }
    return true;
  }

  return blank(0, start) && blank(end, text.length);
}

/// Whether a rows section from a tag of [kind] at [steps] would cut a
/// vertical merge (Ruling 13): the tag's paragraph is directly in a cell, and
/// for an opener its row, for a closer the row after it, holds a cell that
/// continues a merge from above.
bool _crossesMerge(List<SiteStep> steps, TagKind kind) {
  if (steps.length < 2) return false;
  final SiteStep step = steps[steps.length - 2];
  if (step is! CellStep) return false;
  final DocxTable table = step.table as DocxTable;
  final int row = kind == TagKind.sectionEnd ? step.row + 1 : step.row;
  if (row >= table.rows.length) return false;
  for (final DocxTableCell cell in table.rows[row].cells) {
    if (cell.properties.verticalMerge == DocxVerticalMerge.continuation) {
      return true;
    }
  }
  return false;
}
