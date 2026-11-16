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
  SectionPair._(this.open, this.close, this.form, this.depth, this.children);

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
/// Rulings 7, 8, 13 and 14. Never throws.
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
/// other are both malformed.
SectionLayout pairSections(List<SectionTagSite> sites) {
  final Map<SectionTagSite, int> order = Map<SectionTagSite, int>.identity();
  final List<SectionTagSite> malformed = <SectionTagSite>[];
  final List<_Frame> frames = <_Frame>[_Frame(null)];
  for (final SectionTagSite s in sites) {
    order[s] = order.length;
    if (s._opens) {
      frames.add(_Frame(s));
      continue;
    }
    if (s.kind != TagKind.sectionEnd) {
      malformed.add(s);
      continue;
    }
    int k = frames.length - 1;
    while (k >= 1 && !_samePath(frames[k].open!.path, s.path)) {
      k--;
    }
    if (k == 0) {
      malformed.add(s);
      continue;
    }
    if (k == frames.length - 1) {
      final _Frame own = frames.removeLast();
      frames.last.children.add(_Node(own.open!, s, own.children));
      continue;
    }
    while (frames.length > k) {
      _dropFrame(frames, malformed);
    }
    malformed.add(s);
  }
  while (frames.length > 1) {
    _dropFrame(frames, malformed);
  }
  List<_Node> roots = frames.single.children;
  _formAll(roots);
  roots = _wellFormed(roots, malformed);
  roots = _absorb(roots, malformed);
  malformed.sort(
    (SectionTagSite a, SectionTagSite b) => order[a]!.compareTo(order[b]!),
  );
  return SectionLayout._(
    List<SectionPair>.unmodifiable(<SectionPair>[
      for (final _Node n in roots) _build(n, 0),
    ]),
    List<SectionTagSite>.unmodifiable(malformed),
  );
}

/// An opener on the stack and the pairs closed inside it so far.
final class _Frame {
  _Frame(this.open);

  final SectionTagSite? open;
  final List<_Node> children = <_Node>[];
}

/// A pair while the layout is built.
final class _Node {
  _Node(this.open, this.close, this.children);

  final SectionTagSite open;
  final SectionTagSite close;
  List<_Node> children;

  /// The form, or `null` when the pair is malformed.
  SectionForm? form;
}

/// Pops the top frame as malformed; the pairs inside go to the frame below.
void _dropFrame(List<_Frame> frames, List<SectionTagSite> malformed) {
  final _Frame top = frames.removeLast();
  malformed.add(top.open!);
  frames.last.children.addAll(top.children);
}

bool _samePath(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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

void _formAll(List<_Node> nodes) {
  for (final _Node n in nodes) {
    n.form = _formOf(n.open, n.close);
    _formAll(n.children);
  }
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

/// [nodes] with every malformed pair replaced by the pairs inside it, its
/// tags added to [malformed]; recursively.
List<_Node> _wellFormed(List<_Node> nodes, List<SectionTagSite> malformed) {
  final List<_Node> out = <_Node>[];
  for (final _Node n in nodes) {
    n.children = _wellFormed(n.children, malformed);
    if (n.form != null) {
      out.add(n);
    } else {
      malformed
        ..add(n.open)
        ..add(n.close);
      out.addAll(n.children);
    }
  }
  return out;
}

bool _inside(_Node inner, _Node outer) =>
    _contains(outer.form!, outer.open, outer.close, inner.open) &&
    _contains(outer.form!, outer.open, outer.close, inner.close);

/// Moves into each rows pair of [nodes], siblings in reading order, the
/// siblings that stand in its rows (Ruling 8); rows pairs that overlap
/// without nesting are made malformed. Recursively.
List<_Node> _absorb(List<_Node> nodes, List<SectionTagSite> malformed) {
  List<_Node> list = nodes;
  bool changed = true;
  while (changed) {
    changed = false;
    for (int i = 0; i < list.length && !changed; i++) {
      final _Node q = list[i];
      if (q.form != SectionForm.rows) continue;
      int first = i;
      int last = i;
      _Node? conflict;
      for (final int dir in const <int>[-1, 1]) {
        int j = i + dir;
        while (conflict == null && j >= 0 && j < list.length) {
          final _Node s = list[j];
          final bool o = _contains(q.form!, q.open, q.close, s.open);
          final bool c = _contains(q.form!, q.open, q.close, s.close);
          final bool around = s.form == SectionForm.rows && _inside(q, s);
          if (o && c && around) {
            // Side by side over the same rows: neither nests.
            conflict = s;
            break;
          }
          // Nothing of s in q's rows, or q in s's: s takes q in its turn.
          if ((!o && !c) || around) break;
          if (o != c) {
            conflict = s;
            break;
          }
          if (dir < 0) {
            first = j;
          } else {
            last = j;
          }
          j += dir;
        }
      }
      if (conflict != null) {
        final List<_Node> next = <_Node>[];
        for (final _Node n in list) {
          if (identical(n, q) || identical(n, conflict)) {
            malformed
              ..add(n.open)
              ..add(n.close);
            next.addAll(n.children);
          } else {
            next.add(n);
          }
        }
        list = next;
        changed = true;
      } else if (first < i || last > i) {
        q.children = <_Node>[
          ...list.sublist(first, i),
          ...q.children,
          ...list.sublist(i + 1, last + 1),
        ];
        list = <_Node>[...list.sublist(0, first), q, ...list.sublist(last + 1)];
        changed = true;
      }
    }
  }
  for (final _Node n in list) {
    n.children = _absorb(n.children, malformed);
  }
  return list;
}

SectionPair _build(_Node n, int depth) => SectionPair._(
  n.open,
  n.close,
  n.form!,
  depth,
  List<SectionPair>.unmodifiable(<SectionPair>[
    for (final _Node c in n.children) _build(c, depth + 1),
  ]),
);

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
