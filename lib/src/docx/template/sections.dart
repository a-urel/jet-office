/// The pairing of a region's section tags into sections, each with its form:
/// inline, table rows or blocks.
///
/// New in jet_office (decision 0024, spec sections 4 and 4.1, T2 plan Rulings
/// 7, 8, 13 and 14); quds_office_engine has no template fill, so this is not
/// ported from Quds. The pairing is pure: it reads sites the region walk
/// built, never the model, and never throws. A tag it cannot pair, or whose
/// pair has no form, is malformed: it stays as written and the content
/// around it is filled as if it were not there.
library;

import 'tag_scanner.dart';

/// One step of the way from a region's root down to a paragraph.
sealed class SiteStep {
  /// Creates a step.
  const SiteStep();
}

/// The [index]-th block of [container] (a story's block list owner or a
/// cell).
final class BlockStep extends SiteStep {
  /// Creates a block step.
  const BlockStep(this.container, this.index);

  /// The owner of the block list, compared by identity.
  final Object container;

  /// The block's index in the list.
  final int index;

  @override
  String toString() => 'BlockStep($index)';
}

/// Cell [cell] of row [row] of [table], the table the [BlockStep] before it
/// names.
final class CellStep extends SiteStep {
  /// Creates a cell step.
  const CellStep(this.table, this.row, this.cell);

  /// The table, compared by identity.
  final Object table;

  /// The row's index in the table.
  final int row;

  /// The cell's index in the row.
  final int cell;

  @override
  String toString() => 'CellStep($row, $cell)';
}

/// A section tag of a region, where it stands, as the region walk found it.
final class SectionTagSite {
  /// Creates a site.
  const SectionTagSite({
    required this.kind,
    required this.path,
    required this.text,
    required this.steps,
    required this.level,
    required this.offset,
    required this.alone,
    this.breaksSection = false,
    this.crossesMerge = false,
    this.payload,
  });

  /// [TagKind.section], [TagKind.invertedSection] or [TagKind.sectionEnd].
  final TagKind kind;

  /// The tag's path.
  final List<String> path;

  /// The tag as written.
  final String text;

  /// The way from the region's root to the tag's paragraph; the last step is
  /// the paragraph's [BlockStep].
  final List<SiteStep> steps;

  /// The inline list holding the tag: its paragraph or a hyperlink in it,
  /// compared by identity.
  final Object level;

  /// Where the tag starts in its paragraph's text.
  final int offset;

  /// Whether the tag is alone in its paragraph (Ruling 8): the paragraph's
  /// text outside it is empty after trimming U+0020 and U+00A0, and the
  /// paragraph holds no tab, break, picture, field or opaque inline with
  /// visible text.
  final bool alone;

  /// Whether the tag's paragraph carries a section break (Ruling 14).
  final bool breaksSection;

  /// Whether the tag stands in a row a rows section from it would cut a
  /// vertical merge at (Ruling 13): for an opener, its row holds a cell that
  /// continues a merge from above; for a closer, the next row holds one.
  final bool crossesMerge;

  /// What the walk keeps with the site (its entry), returned untouched.
  final Object? payload;

  bool get _opens => kind == TagKind.section || kind == TagKind.invertedSection;
}

/// Where a section's content is (spec section 4.1).
enum SectionForm {
  /// Both tags in one inline list of one paragraph: the content is the
  /// inlines between them.
  inline,

  /// The tags directly in cells of one table, in different rows or cells:
  /// the content is the whole rows from the opener's to the closer's.
  rows,

  /// Each tag alone in its paragraph, both paragraphs in one container: the
  /// content is the blocks between them.
  blocks,
}

/// A well-formed section: its two tags, its form and the sections inside.
final class SectionPair {
  SectionPair._(this.open, this.close, this.form, this.depth)
    : children = <SectionPair>[];

  /// The opening tag, `{{#name}}` or `{{^name}}`.
  final SectionTagSite open;

  /// The closing tag, `{{/name}}`.
  final SectionTagSite close;

  /// Where the content is.
  final SectionForm form;

  /// The number of well-formed sections around this one; 0 at the top.
  final int depth;

  /// The well-formed sections directly inside, in reading order.
  final List<SectionPair> children;

  /// Whether [site] is structurally inside this pair's content (Ruling 8):
  /// between the tags in their inline list, in the rows from the opener's to
  /// the closer's (before the opener in its row and after the closer in its
  /// row too, in nested tables too), or in the blocks between the tag
  /// paragraphs. The pair's own tags are not inside.
  bool contains(SectionTagSite site) => _contains(form, open, close, site);
}

/// The pairing of a region's section tags.
final class SectionLayout {
  SectionLayout._(this.roots, this.malformed);

  /// The top-level well-formed sections, in reading order.
  final List<SectionPair> roots;

  /// The tags that pair into no well-formed section, in reading order.
  final List<SectionTagSite> malformed;
}

/// Pairs [sites], a region's section tags in reading order, into sections by
/// Rulings 7, 8, 13, 14 and 21. Never throws, and needs no stack deeper than
/// a few frames however deep the sections nest.
///
/// A stack pairs a closer with the opener of its path on top. A closer whose
/// opener is deeper in the stack makes every opener above it, its own opener
/// and itself malformed; a closer whose path is not in the stack is
/// malformed alone; openers left at the end are malformed. A site of another
/// kind is malformed. A pair then takes its form (inline, rows, blocks, in
/// that order) or is malformed, and the sections inside a malformed pair
/// belong to its parent. A section that stands in the rows of a rows section
/// beside it, before its opener or after its closer, moves inside it; two
/// rows sections of one table whose rows overlap without one nesting in the
/// other are both malformed, and a rows section inside a rows section that
/// selects the same rows is malformed (Ruling 21).
///
/// The work is linear in the sites but for the moves of Ruling 8, which
/// look only at the neighbours of a rows section.
SectionLayout pairSections(List<SectionTagSite> sites) {
  final int n = sites.length;
  final List<bool> bad = List<bool>.filled(n, false);
  final List<int> partner = List<int>.filled(n, -1);

  // Ruling 7: the stack, with the open frames of each path by its key, so a
  // closer finds its opener without a scan.
  final List<int> frames = <int>[];
  final Map<String, List<int>> open = <String, List<int>>{};
  void pop() {
    final int i = frames.removeLast();
    open[_key(sites[i])]!.removeLast();
  }

  for (int i = 0; i < n; i++) {
    final SectionTagSite s = sites[i];
    if (s._opens) {
      (open[_key(s)] ??= <int>[]).add(frames.length);
      frames.add(i);
      continue;
    }
    final List<int>? same = s.kind == TagKind.sectionEnd ? open[_key(s)] : null;
    if (same == null || same.isEmpty) {
      bad[i] = true;
      continue;
    }
    final int k = same.last;
    if (k == frames.length - 1) {
      partner[frames[k]] = i;
      partner[i] = frames[k];
      pop();
      continue;
    }
    while (frames.length > k) {
      bad[frames.last] = true;
      pop();
    }
    bad[i] = true;
  }
  for (final int i in frames) {
    bad[i] = true;
  }

  // Forms (Rulings 8, 13, 14).
  final List<SectionForm?> forms = List<SectionForm?>.filled(n, null);
  for (int i = 0; i < n; i++) {
    final int j = partner[i];
    if (bad[i] || j <= i) continue;
    final SectionForm? form = _formOf(sites[i], sites[j]);
    if (form == null) {
      bad[i] = true;
      bad[j] = true;
    } else {
      forms[i] = form;
    }
  }

  // The tree of the well-formed pairs, which nest in reading order.
  final _Node root = _Node(null, null, null);
  final List<_Node> stack = <_Node>[root];
  for (int i = 0; i < n; i++) {
    if (bad[i]) continue;
    final int j = partner[i];
    if (j > i) {
      final _Node node = _Node(sites[i], sites[j], forms[i]);
      stack.last.children.add(node);
      stack.add(node);
    } else if (j >= 0) {
      stack.removeLast();
    }
  }

  // Ruling 8's moves and Ruling 21, each pair's children once, top down.
  final Map<SectionTagSite, int> index = Map<SectionTagSite, int>.identity();
  for (int i = 0; i < n; i++) {
    index[sites[i]] = i;
  }
  void drop(_Node node) {
    bad[index[node.open]!] = true;
    bad[index[node.close]!] = true;
  }

  final List<_Node> work = <_Node>[root];
  while (work.isNotEmpty) {
    final _Node parent = work.removeLast();
    parent.children = _arrange(parent, parent.allChildren(), drop);
    parent.before.clear();
    parent.after.clear();
    work.addAll(parent.children);
  }

  // The result, top down.
  final List<SectionPair> roots = <SectionPair>[];
  final List<(_Node, List<SectionPair>, int)> build =
      <(_Node, List<SectionPair>, int)>[
        for (final _Node c in root.children.reversed) (c, roots, 0),
      ];
  while (build.isNotEmpty) {
    final (_Node node, List<SectionPair> into, int depth) = build.removeLast();
    final SectionPair pair = SectionPair._(
      node.open!,
      node.close!,
      node.form!,
      depth,
    );
    into.add(pair);
    for (final _Node c in node.children.reversed) {
      build.add((c, pair.children, depth + 1));
    }
  }
  return SectionLayout._(
    List<SectionPair>.unmodifiable(roots),
    List<SectionTagSite>.unmodifiable(<SectionTagSite>[
      for (int i = 0; i < n; i++)
        if (bad[i]) sites[i],
    ]),
  );
}

String _key(SectionTagSite site) => site.path.join('.');

/// A pair while the layout is built; the root has no tags.
final class _Node {
  _Node(this.open, this.close, this.form);

  final SectionTagSite? open;
  final SectionTagSite? close;
  final SectionForm? form;
  List<_Node> children = <_Node>[];

  /// Siblings moved in before the opener, the nearest first.
  final List<_Node> before = <_Node>[];

  /// Siblings moved in after the closer, in reading order.
  final List<_Node> after = <_Node>[];

  /// [before], [children] and [after], in reading order.
  List<_Node> allChildren() => <_Node>[
    ...before.reversed,
    ...children,
    ...after,
  ];
}

bool _sameStep(SiteStep a, SiteStep b) => switch ((a, b)) {
  (final BlockStep x, final BlockStep y) =>
    identical(x.container, y.container) && x.index == y.index,
  (final CellStep x, final CellStep y) =>
    identical(x.table, y.table) && x.row == y.row && x.cell == y.cell,
  _ => false,
};

bool _sameSteps(List<SiteStep> a, List<SiteStep> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (!_sameStep(a[i], b[i])) return false;
  }
  return true;
}

/// The cell [site]'s paragraph is directly in, or `null`.
CellStep? _cellOf(SectionTagSite site) {
  final List<SiteStep> steps = site.steps;
  if (steps.length < 2 || steps.last is! BlockStep) return null;
  final SiteStep step = steps[steps.length - 2];
  return step is CellStep ? step : null;
}

/// The form of the pair [open], [close] (Ruling 8, then 13 and 14), or
/// `null` when it has none.
SectionForm? _formOf(SectionTagSite open, SectionTagSite close) {
  if (_sameSteps(open.steps, close.steps)) {
    return identical(open.level, close.level) ? SectionForm.inline : null;
  }
  final CellStep? a = _cellOf(open);
  final CellStep? b = _cellOf(close);
  if (a != null &&
      b != null &&
      identical(a.table, b.table) &&
      (a.row != b.row || a.cell != b.cell)) {
    if (a.row > b.row || (a.row == b.row && a.cell > b.cell)) return null;
    if (open.crossesMerge || close.crossesMerge) return null;
    return SectionForm.rows;
  }
  if (open.steps.isEmpty || close.steps.isEmpty) return null;
  final SiteStep x = open.steps.last;
  final SiteStep y = close.steps.last;
  if (x is BlockStep &&
      y is BlockStep &&
      identical(x.container, y.container) &&
      x.index < y.index &&
      open.alone &&
      close.alone &&
      !open.breaksSection &&
      !close.breaksSection) {
    return SectionForm.blocks;
  }
  return null;
}

/// How much of [inner] stands in the rows pair [outer]: none, part or all.
int _within(_Node inner, _Node outer) {
  int k = 0;
  if (_contains(outer.form!, outer.open!, outer.close!, inner.open!)) k++;
  if (_contains(outer.form!, outer.open!, outer.close!, inner.close!)) k++;
  return k;
}

/// Whether [a] and [b] are rows pairs of one table over the same rows.
bool _sameRows(_Node a, _Node b) {
  if (a.form != SectionForm.rows || b.form != SectionForm.rows) return false;
  final CellStep ao = _cellOf(a.open!)!;
  final CellStep ac = _cellOf(a.close!)!;
  final CellStep bo = _cellOf(b.open!)!;
  final CellStep bc = _cellOf(b.close!)!;
  return identical(ao.table, bo.table) && ao.row == bo.row && ac.row == bc.row;
}

/// The children of [parent], [nodes] in reading order, in one pass with a
/// cursor: a sibling that stands in a rows pair's rows moves into it (Ruling
/// 8); a pair that overlaps a rows sibling without nesting, and a rows pair
/// over [parent]'s own rows (Ruling 21), is malformed ([drop]) and the pairs
/// inside it come back to be arranged in its place.
List<_Node> _arrange(
  _Node parent,
  List<_Node> nodes,
  void Function(_Node node) drop,
) {
  final List<_Node> input = nodes.reversed.toList();
  final List<_Node> out = <_Node>[];
  void conflict(List<_Node> gone) {
    final List<_Node> back = <_Node>[];
    for (final _Node g in gone) {
      drop(g);
      back.addAll(g.allChildren());
    }
    input.addAll(back.reversed);
  }

  while (input.isNotEmpty) {
    final _Node f = input.removeLast();
    if (parent.form == SectionForm.rows && _sameRows(f, parent)) {
      conflict(<_Node>[f]);
      continue;
    }
    bool placed = false;
    while (!placed && out.isNotEmpty) {
      final _Node q = out.last;
      final int fInQ = q.form == SectionForm.rows ? _within(f, q) : 0;
      final int qInF = f.form == SectionForm.rows ? _within(q, f) : 0;
      if (fInQ == 2 && qInF == 2) {
        // Side by side over the same rows: neither nests.
        out.removeLast();
        conflict(<_Node>[q, f]);
        placed = true;
      } else if (fInQ == 2) {
        q.after.add(f);
        placed = true;
      } else if (qInF == 2) {
        out.removeLast();
        f.before.add(q);
      } else if (fInQ == 1 || qInF == 1) {
        // The rows overlap without one pair nesting in the other.
        out.removeLast();
        conflict(<_Node>[q, f]);
        placed = true;
      } else {
        break;
      }
    }
    if (!placed) out.add(f);
  }
  return out;
}

bool _contains(
  SectionForm form,
  SectionTagSite open,
  SectionTagSite close,
  SectionTagSite site,
) {
  if (identical(site, open) || identical(site, close)) return false;
  switch (form) {
    case SectionForm.inline:
      return _sameSteps(site.steps, open.steps) &&
          open.offset < site.offset &&
          site.offset < close.offset;
    case SectionForm.rows:
      final CellStep a = _cellOf(open)!;
      final CellStep b = _cellOf(close)!;
      for (final SiteStep step in site.steps) {
        if (step is CellStep &&
            identical(step.table, a.table) &&
            step.row >= a.row &&
            step.row <= b.row) {
          return true;
        }
      }
      return false;
    case SectionForm.blocks:
      final BlockStep a = open.steps.last as BlockStep;
      final BlockStep b = close.steps.last as BlockStep;
      for (final SiteStep step in site.steps) {
        if (step is BlockStep &&
            identical(step.container, a.container) &&
            step.index > a.index &&
            step.index < b.index) {
          return true;
        }
      }
      return false;
  }
}
