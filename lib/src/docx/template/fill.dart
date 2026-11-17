/// The template fill: `{{}}` value tags, sections and Word's `MERGEFIELD`s
/// in the body, its tables, headers and footers, filled in place from one
/// map of data (T1 and T2), and the listing of a template's tags.
///
/// New in jet_office (decision 0024, spec sections 3.2, 4, 5, 6, 8 and 10,
/// T2 plan Rulings 1 to 22); quds_office_engine has no template fill, so this
/// is not ported from Quds. A fill is one transaction of the document's
/// change log, so one undo takes it back. Each story is filled as a region
/// (`region.dart`): its section tags are paired (`sections.dart`), each
/// well-formed section repeated, removed or shown once on the model
/// (`expand.dart`) and its content filled as a region of its own with the
/// section's value as the innermost scope. What cannot be filled stays as
/// written and is reported in the fill's own warnings, never in
/// [DocxDocument.warnings]: a tag that is malformed, inside a tracked
/// change, a content control, a field result or opaque content (text boxes,
/// the footnotes, endnotes and comments parts), a section tag that does not
/// pair or stand where a section can, a value the data lacks or that is not
/// text, a `MERGEFIELD` the model does not type, and a section or tag past a
/// limit of the fill.
///
/// The walk is `template_walk.dart`'s; the text scan of opaque content is
/// `opaque_scan.dart`'s.
///
/// @docImport '../read_exception.dart';
library;

import 'package:jet_core/jet_core.dart';

import '../../opc/change_log.dart';
import '../docx_document.dart';
import '../docx_package.dart';
import '../model/blocks.dart';
import '../model/inlines.dart';
import '../story_reader.dart' show marksInSimpleField;
import '../warnings.dart';
import 'expand.dart';
import 'merge_field.dart';
import 'opaque_scan.dart';
import 'region.dart';
import 'replace.dart';
import 'sections.dart';
import 'tag_scanner.dart';
import 'template_walk.dart';
import 'values.dart';

/// How a template is filled.
final class FillSettings {
  /// Creates settings: [locale] for numbers, dates and casing, whether a
  /// tag or merge field the data lacks is removed ([removeMissing]) rather
  /// than left as written, and the limits of one fill (Ruling 1 of T2).
  const FillSettings({
    this.locale = FormatLocale.enUS,
    this.removeMissing = false,
    this.maxCopies = 100000,
    this.maxSectionDepth = 32,
    this.maxTags = 1000000,
  });

  /// The locale values are shown in, as Excel for Mac shows them.
  final FormatLocale locale;

  /// Whether a tag or merge field whose value is missing is removed. It is
  /// warned about either way.
  final bool removeMissing;

  /// The units (blocks, rows or inlines) the copies of one fill may add, all
  /// sections and levels together.
  final int maxCopies;

  /// How deep sections may nest.
  final int maxSectionDepth;

  /// The tags and merge fields one fill may fill, copies counted.
  final int maxTags;

  /// Throws [ArgumentError] when a limit is below 1.
  void check() {
    for (final (String name, int value) in <(String, int)>[
      ('maxCopies', maxCopies),
      ('maxSectionDepth', maxSectionDepth),
      ('maxTags', maxTags),
    ]) {
      if (value < 1) {
        throw ArgumentError.value(value, name, 'must be at least 1');
      }
    }
  }
}

/// A tag or `MERGEFIELD` of a template, as [listTemplateTags] finds it.
final class FoundTag {
  /// Creates a found tag.
  const FoundTag({
    required this.kind,
    required this.mergeField,
    required this.path,
    required this.format,
    required this.text,
    required this.part,
    required this.location,
    required this.problem,
    required this.depth,
  });

  /// The tag's kind; `null` for a malformed tag and for a merge field.
  final TagKind? kind;

  /// Whether it is a `MERGEFIELD`.
  final bool mergeField;

  /// The tag's path, or the merge field's name as one segment; empty for a
  /// malformed tag.
  final List<String> path;

  /// The tag's format code, or the merge field's number or date picture as
  /// a format code.
  final String? format;

  /// The tag or the field instruction as written.
  final String text;

  /// The absolute name of the part it is in, such as `/word/document.xml`.
  final String part;

  /// The path of its paragraph, such as `body/tbl[0]/tr[1]/tc[0]/p[0]` or
  /// `header1.xml/p[0]`; `null` in a footnotes, endnotes or comments part.
  final String? location;

  /// The warning a fill raises for its form, or `null` for one a fill can
  /// fill (it may still warn for the data it gets).
  final DocxWarningCode? problem;

  /// How many well-formed sections are around it in its story (Ruling 19 of
  /// T2); a section's own tags count the sections outside it.
  final int depth;
}

/// Fills [document] with [data] in one transaction (`documentTransaction`)
/// and returns the fill's warnings; [fillTemplateWithChanges] has the rules.
List<DocxWarning> fillTemplate(
  DocxDocument document,
  Map<String, Object?> data,
  FillSettings settings,
) => fillTemplateWithChanges(document, data, settings).warnings;

/// Fills [document] with [data] in one transaction (`documentTransaction`)
/// and returns the fill's warnings and the transaction's change set, which
/// the caller may hand to the change log's undo; the library keeps no
/// change set (decision 0009).
///
/// [settings]' limits and [data] are checked first (`checkTemplateData`): an
/// [ArgumentError] then leaves the document unchanged and records nothing.
/// Names are looked up in [data], and inside a section in its value first
/// (`lookupInScopes`). A part that cannot be read (a header or footer) throws a
/// [DocxReadException] from the walk, before anything changes.
({List<DocxWarning> warnings, ChangeSet changes}) fillTemplateWithChanges(
  DocxDocument document,
  Map<String, Object?> data,
  FillSettings settings,
) {
  settings.check();
  checkTemplateData(data);
  final _Fill fill = _Fill(document, data, settings);
  final ChangeSet changes = documentTransaction(document, fill.run);
  return (warnings: fill.warnings.warnings, changes: changes);
}

/// The tags and merge fields of [document] in reading order, as a fill would
/// meet them, without changing it. Each story is paired as one region
/// without data (Ruling 19 of T2): a section tag that pairs into a
/// well-formed section has no problem, one that does not has
/// `templateSectionMalformed`, and a tag's depth is the number of
/// well-formed sections around it.
List<FoundTag> listTemplateTags(DocxDocument document) {
  final int maxDepth = docxPackageOf(document).limits.maxDepth;
  final List<FoundTag> out = <FoundTag>[];
  for (final TemplateStory story in templateStories(document)) {
    final List<RegionParagraph> paragraphs = scanRegion(
      storyRegion(story),
      maxDepth,
    );
    final SectionLayout layout = pairSections(<SectionTagSite>[
      for (final RegionParagraph p in paragraphs) ...p.sites,
    ]);
    final Set<Object?> malformed = Set<Object?>.identity()
      ..addAll(layout.malformed.map((SectionTagSite s) => s.payload));
    final List<SectionPair> pairs = <SectionPair>[];
    final List<SectionPair> work = List<SectionPair>.of(layout.roots);
    while (work.isNotEmpty) {
      final SectionPair pair = work.removeLast();
      pairs.add(pair);
      work.addAll(pair.children);
    }
    final _Cover cover = _Cover(paragraphs, pairs);
    for (int i = 0; i < paragraphs.length; i++) {
      final RegionParagraph p = paragraphs[i];
      for (final TemplateEntry e in p.entries) {
        out.add(
          _found(
            e,
            story.part,
            p.location,
            cover.count(i, e),
            problem: malformed.contains(e)
                ? DocxWarningCode.templateSectionMalformed
                : e.problem,
          ),
        );
      }
    }
  }
  final DocxPackage package = docxPackageOf(document);
  for (final String part in templateNoteParts(package)) {
    for (final String s in placeholdersInPart(package, part)) {
      final TemplateEntry e = placeholderEntry(
        s,
        DocxWarningCode.templatePlaceholderNotTyped,
      );
      out.add(_found(e, part, null, 0));
    }
  }
  return out;
}

/// The region of [story]'s whole block list, with the template path of each
/// block as the walk names it.
BlockRegion storyRegion(TemplateStory story) {
  final List<DocxBlock> blocks = story.blocks;
  int paragraphs = 0;
  int tables = 0;
  final Map<String, int> opaque = <String, int>{};
  return BlockRegion(story.story, blocks, 0, blocks.length, <String>[
    for (final DocxBlock b in blocks)
      switch (b) {
        DocxParagraph() => '${story.prefix}/p[${paragraphs++}]',
        DocxTable() => '${story.prefix}/tbl[${tables++}]',
        DocxOpaqueBlock() => () {
          final int n = opaque[b.localName] ?? 0;
          opaque[b.localName] = n + 1;
          return '${story.prefix}/${b.localName}[$n]';
        }(),
      },
  ]);
}

/// Which sections of a region hold which entries, found in time linear in
/// the region's paragraphs, entries and sections (a review of P3: asking
/// every section about every entry made listing a template quadratic).
///
/// A section's content is a run of the region's paragraphs in reading order:
/// one paragraph for an inline section, the paragraphs between its two tag
/// paragraphs for a blocks section, and every paragraph of its rows for a
/// rows section ([rangeOf]). [count] adds up, per paragraph, the blocks and
/// rows sections over it, and the inline sections of the paragraph around
/// the entry's offset; a rows section's own tags, which stand in its rows,
/// are not in it.
final class _Cover {
  _Cover(this.paragraphs, Iterable<SectionPair> pairs)
    : _over = List<int>.filled(paragraphs.length + 1, 0) {
    for (int i = 0; i < paragraphs.length; i++) {
      for (final TemplateEntry e in paragraphs[i].entries) {
        _paragraphOf[e] = i;
      }
    }
    for (final SectionPair pair in pairs) {
      switch (pair.form) {
        case SectionForm.inline:
          final int i = _paragraphOf[pair.open.payload]!;
          (_opens[i] ??= <int>[]).add(pair.open.offset);
          (_closes[i] ??= <int>[]).add(pair.close.offset);
        case SectionForm.blocks || SectionForm.rows:
          final (int lo, int hi) = rangeOf(pair);
          if (lo > hi) continue;
          _over[lo]++;
          _over[hi + 1]--;
          if (pair.form == SectionForm.rows) {
            _ownTags
              ..add(pair.open.payload)
              ..add(pair.close.payload);
          }
      }
    }
    for (final List<int> offsets in <List<int>>[
      ..._opens.values,
      ..._closes.values,
    ]) {
      offsets.sort();
    }
    for (int i = 1; i < _over.length; i++) {
      _over[i] += _over[i - 1];
    }
  }

  final List<RegionParagraph> paragraphs;
  final Map<Object?, int> _paragraphOf = Map<Object?, int>.identity();

  /// Per paragraph, how many blocks and rows sections are over it (a
  /// running sum once built).
  final List<int> _over;
  final Map<int, List<int>> _opens = <int, List<int>>{};
  final Map<int, List<int>> _closes = <int, List<int>>{};
  final Set<Object?> _ownTags = Set<Object?>.identity();

  /// The paragraphs `[lo, hi]` whose entries [pair] may hold (none when `lo`
  /// is above `hi`): its own for an inline section, those between its tag
  /// paragraphs for a blocks section, and those of its rows for a rows
  /// section, found from its tag paragraphs outward.
  (int, int) rangeOf(SectionPair pair) {
    final int open = _paragraphOf[pair.open.payload]!;
    final int close = _paragraphOf[pair.close.payload]!;
    switch (pair.form) {
      case SectionForm.inline:
        return (open, open);
      case SectionForm.blocks:
        return (open + 1, close - 1);
      case SectionForm.rows:
        bool holds(int i) =>
            pair.contains(_probeAt(paragraphs[i], paragraphs[i].steps, 0));
        int lo = open;
        while (lo > 0 && holds(lo - 1)) {
          lo--;
        }
        int hi = close;
        while (hi + 1 < paragraphs.length && holds(hi + 1)) {
          hi++;
        }
        return (lo, hi);
    }
  }

  /// How many of the sections hold the entry [e] of paragraph [i].
  int count(int i, TemplateEntry e) {
    int n = _over[i] - (_ownTags.contains(e) ? 1 : 0);
    final List<int>? opens = _opens[i];
    if (opens != null) {
      // Inline sections nest or follow each other: those opened before the
      // offset, less those closed at or before it.
      n += _below(opens, e.offset) - _below(_closes[i]!, e.offset + 1);
    }
    return n;
  }

  /// How many of the sorted [offsets] are below [x].
  static int _below(List<int> offsets, int x) {
    int lo = 0;
    int hi = offsets.length;
    while (lo < hi) {
      final int mid = (lo + hi) >> 1;
      if (offsets[mid] < x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

/// Whether the fill fills [e] and counts it against `maxTags`: a value tag
/// or a merge field that can be filled where it stands; never a section tag.
bool _fillable(TemplateEntry e) =>
    e.problem == null &&
    (e.field != null ||
        (e.match != null &&
            e.kind != TagKind.section &&
            e.kind != TagKind.invertedSection &&
            e.kind != TagKind.sectionEnd));

/// A site standing where the entry [e] of [p] is, to ask a pair whether it
/// holds the entry ([SectionPair.contains]).
SectionTagSite _probe(RegionParagraph p, TemplateEntry e) =>
    _probeAt(p, p.steps, e.offset);

SectionTagSite _probeAt(Object level, List<SiteStep> steps, int offset) =>
    SectionTagSite(
      kind: TagKind.value,
      path: const <String>[],
      text: '',
      steps: steps,
      level: level,
      offset: offset,
      alone: false,
    );

FoundTag _found(
  TemplateEntry e,
  String part,
  String? location,
  int depth, {
  DocxWarningCode? problem,
}) => FoundTag(
  kind: e.kind,
  mergeField: e.mergeField,
  path: List<String>.unmodifiable(e.path),
  format: e.format,
  text: e.text,
  part: part,
  location: location,
  problem: problem ?? e.problem,
  depth: depth,
);

/// A well-formed section of a region and what the fill does with it.
final class _Decided {
  _Decided(
    this.pair,
    this.depth,
    this.effect,
    this.items, {
    this.prepaid = false,
  });

  final SectionPair pair;

  /// How many sections it is inside, itself counted (1 at the top).
  final int depth;

  /// What its value does; `null` for a missing name with `removeMissing`,
  /// which shows the content once in the same scope.
  final SectionEffect? effect;

  /// The items of [effect].
  final List<Object?> items;

  /// Whether the tags of its content, in every copy, were counted against
  /// `maxTags` when it was decided, so filling them counts nothing more.
  final bool prepaid;
}

/// One edit of a paragraph, applied from the last offset to the first.
typedef _Edit = ({int offset, void Function() apply});

/// One fill: the walk with the data, and its warnings.
final class _Fill {
  _Fill(this.document, this.data, this.settings)
    : formatter = NumberFormatter(locale: settings.locale),
      maxDepth = docxPackageOf(document).limits.maxDepth;

  final DocxDocument document;
  final Map<String, Object?> data;
  final FillSettings settings;
  final NumberFormatter formatter;
  final int maxDepth;
  final DocxWarningCollector warnings = DocxWarningCollector();

  /// The units (blocks, rows or inlines) the copies made so far added, all
  /// sections and levels together (Ruling 1, as the owner set it on
  /// 2026-11-17).
  int _copies = 0;

  /// The tags and merge fields filled so far (Ruling 1).
  int _tags = 0;

  void run() {
    for (final TemplateStory story in templateStories(document)) {
      _region(story, storyRegion(story), <Object?>[data], 0);
    }
    final DocxPackage package = docxPackageOf(document);
    for (final String part in templateNoteParts(package)) {
      for (final String s in placeholdersInPart(package, part)) {
        warnings.add(
          DocxWarningCode.templatePlaceholderNotTyped,
          part: part,
          detail: s,
        );
      }
    }
  }

  /// Fills [region] of [story] with [scopes] (the data first, the innermost
  /// last), inside [depth] sections (Ruling 16): pairs its section tags,
  /// decides each well-formed section, fills every tag and merge field
  /// outside the sections it expands (a paragraph's inline sections in the
  /// same pass, from the last to the first), then expands its other
  /// sections from the last to the first, each copy a region of its own.
  ///
  /// [prepaid] says the region's tags were counted against `maxTags` when
  /// its section was decided. Otherwise the tags outside its sections are
  /// counted first, when all of them fit, before any section is decided,
  /// so a section cannot take what they need (a review of P3).
  void _region(
    TemplateStory story,
    TemplateRegion region,
    List<Object?> scopes,
    int depth, {
    bool prepaid = false,
  }) {
    final List<RegionParagraph> paragraphs = scanRegion(
      region,
      maxDepth,
      locale: settings.locale,
    );
    final SectionLayout layout = pairSections(<SectionTagSite>[
      for (final RegionParagraph p in paragraphs) ...p.sites,
    ]);
    final Map<SectionTagSite, String> at =
        Map<SectionTagSite, String>.identity();
    final Map<Object?, SectionTagSite> siteOf =
        Map<Object?, SectionTagSite>.identity();
    for (final RegionParagraph p in paragraphs) {
      for (final SectionTagSite site in p.sites) {
        at[site] = p.location;
        siteOf[site.payload] = site;
      }
    }
    final Set<SectionTagSite> malformed = Set<SectionTagSite>.identity()
      ..addAll(layout.malformed);
    final Set<SectionTagSite> kept = Set<SectionTagSite>.identity();
    // The tags outside every section, counted at once when they all fit.
    bool outsidePaid = prepaid;
    if (!prepaid) {
      final _Cover roots = _Cover(paragraphs, layout.roots);
      int outside = 0;
      for (int i = 0; i < paragraphs.length; i++) {
        for (final TemplateEntry e in paragraphs[i].entries) {
          if (_fillable(e) && roots.count(i, e) == 0) outside++;
        }
      }
      if (_tags + outside <= settings.maxTags) {
        _tags += outside;
        outsidePaid = true;
      }
    }
    final _Cover rootCover = outsidePaid && !prepaid
        ? _Cover(paragraphs, layout.roots)
        : _Cover(paragraphs, const <SectionPair>[]);
    final List<_Decided> expanded = _decide(
      story,
      region,
      layout.roots,
      paragraphs,
      scopes,
      depth,
      at,
      malformed,
      kept,
      prepaid: prepaid,
    );
    final Set<SectionTagSite> expandedTags = Set<SectionTagSite>.identity();
    final Map<Object, List<_Decided>> inline =
        Map<Object, List<_Decided>>.identity();
    for (final _Decided d in expanded) {
      expandedTags
        ..add(d.pair.open)
        ..add(d.pair.close);
      if (d.pair.form == SectionForm.inline) {
        (inline[d.pair.open.payload!] ??= <_Decided>[]).add(d);
      }
    }
    final _Cover cover = _Cover(paragraphs, <SectionPair>[
      for (final _Decided d in expanded) d.pair,
    ]);
    for (int i = 0; i < paragraphs.length; i++) {
      final RegionParagraph p = paragraphs[i];
      bool inside(TemplateEntry e) => cover.count(i, e) > 0;
      void warn(DocxWarningCode code, String detail) => warnings.add(
        code,
        part: story.part,
        location: p.location,
        detail: detail,
      );
      final List<_Edit> edits = <_Edit>[];
      final List<_Edit> fields = <_Edit>[];
      for (final TemplateEntry e in p.entries) {
        final SectionTagSite? site = siteOf[e];
        if (site != null) {
          if (expandedTags.contains(site)) {
            final List<_Decided>? here = inline[e];
            if (here != null) {
              for (final _Decided d in here) {
                edits.add((
                  offset: d.pair.open.offset,
                  apply: () => _expand(story, region, d, scopes, at),
                ));
              }
            }
            continue;
          }
          if (kept.contains(site) || inside(e)) continue;
          if (malformed.contains(site)) {
            warn(DocxWarningCode.templateSectionMalformed, e.text);
          }
          continue;
        }
        if (inside(e)) continue;
        // A tag in a section left as written was not counted with the
        // tags outside every section.
        _entry(
          e,
          scopes,
          warn,
          edits,
          fields,
          counted: prepaid || (outsidePaid && rootCover.count(i, e) == 0),
        );
      }
      edits.sort((_Edit a, _Edit b) => b.offset.compareTo(a.offset));
      for (final _Edit edit in edits) {
        edit.apply();
      }
      for (final _Edit edit in fields) {
        edit.apply();
      }
    }
    for (final _Decided d in expanded.reversed) {
      if (d.pair.form != SectionForm.inline) {
        _expand(story, region, d, scopes, at);
      }
    }
  }

  /// Decides each well-formed section of [roots] (Rulings 1, 5, 12 to 14 and
  /// 21) and returns those the fill expands, in reading order. A section left
  /// as written goes in [kept] (with its tags) and its sections are decided
  /// in its place, one level deeper, with the same [scopes]; one that is
  /// malformed after all goes in [malformed] instead.
  List<_Decided> _decide(
    TemplateStory story,
    TemplateRegion region,
    List<SectionPair> roots,
    List<RegionParagraph> paragraphs,
    List<Object?> scopes,
    int depth,
    Map<SectionTagSite, String> at,
    Set<SectionTagSite> malformed,
    Set<SectionTagSite> kept, {
    required bool prepaid,
  }) {
    final List<_Decided> out = <_Decided>[];
    // The paragraphs each section may hold, to count its tags.
    final _Cover ranges = _Cover(paragraphs, const <SectionPair>[]);
    // A stack of the sections to decide, each with its depth, so they are
    // decided in reading order; a section kept as written puts its own in
    // its place.
    final List<(SectionPair, int)> work = <(SectionPair, int)>[
      for (final SectionPair pair in roots.reversed) (pair, depth + 1),
    ];
    void inPlace(SectionPair pair, int level) {
      for (final SectionPair child in pair.children.reversed) {
        work.add((child, level + 1));
      }
    }

    while (work.isNotEmpty) {
      final (SectionPair pair, int level) = work.removeLast();
      void warn(DocxWarningCode code) => warnings.add(
        code,
        part: story.part,
        location: at[pair.open],
        detail: pair.open.text,
      );
      void keep() {
        kept
          ..add(pair.open)
          ..add(pair.close);
        inPlace(pair, level);
      }

      if (region is RowRegion &&
          pair.form == SectionForm.rows &&
          _selectsRegion(pair, region)) {
        // Ruling 21: the rows of the copy it is in; malformed.
        malformed
          ..add(pair.open)
          ..add(pair.close);
        inPlace(pair, level - 1);
        continue;
      }
      if (level > settings.maxSectionDepth) {
        warn(DocxWarningCode.templateLimitExceeded);
        keep();
        continue;
      }
      // What the content's tags cost, once: nothing more when this region's
      // tags were counted, as its copy is one of them.
      int once() => prepaid ? 0 : _fillableIn(pair, ranges);
      // A section shown once is counted when its tags fit; otherwise each
      // tag is counted as it fills.
      bool payOnce() {
        final int tags = once();
        if (_tags + tags > settings.maxTags) return false;
        _tags += tags;
        return true;
      }

      final Lookup found = lookupInScopes(scopes, pair.open.path);
      if (found is! Found) {
        warn(DocxWarningCode.templateValueMissing);
        if (settings.removeMissing) {
          out.add(
            _Decided(pair, level, null, const <Object?>[], prepaid: payOnce()),
          );
        } else {
          keep();
        }
        continue;
      }
      final ({SectionEffect effect, List<Object?> items}) effect =
          sectionEffect(
            found.value,
            inverted: pair.open.kind == TagKind.invertedSection,
          );
      if ((effect.effect == SectionEffect.repeat ||
              effect.effect == SectionEffect.remove) &&
          sectionHoldsBreak(pair)) {
        // Ruling 14: such content is never copied or removed.
        warn(DocxWarningCode.templateSectionMalformed);
        keep();
        continue;
      }
      switch (effect.effect) {
        case SectionEffect.repeat:
          final int count = effect.items.length;
          // A prepaid region counted one copy of the content already.
          final int extra =
              _fillableIn(pair, ranges) * (prepaid ? count - 1 : count);
          // The units its copies add (the owner's ruling, 2026-11-17).
          final int units = contentUnits(pair) * (count - 1);
          if (_copies + units > settings.maxCopies ||
              _tags + extra > settings.maxTags) {
            warn(DocxWarningCode.templateLimitExceeded);
            keep();
            continue;
          }
          // Counted now, so the sections decided after it count them.
          _copies += units;
          _tags += extra;
          out.add(
            _Decided(pair, level, effect.effect, effect.items, prepaid: true),
          );
        case SectionEffect.remove:
          out.add(_Decided(pair, level, effect.effect, effect.items));
        case SectionEffect.once || SectionEffect.scope:
          out.add(
            _Decided(
              pair,
              level,
              effect.effect,
              effect.items,
              prepaid: prepaid || payOnce(),
            ),
          );
      }
    }
    return out;
  }

  /// Whether the rows pair [pair] selects every row of [region], the copy of
  /// rows it is in (Ruling 21).
  bool _selectsRegion(SectionPair pair, RowRegion region) {
    final CellStep a = pair.open.steps[pair.open.steps.length - 2] as CellStep;
    final CellStep b =
        pair.close.steps[pair.close.steps.length - 2] as CellStep;
    return identical(a.table, region.table) &&
        a.row == region.start &&
        b.row == region.end - 1;
  }

  /// The fillable entries (tags, section tags and merge fields with no
  /// problem of form) in the content of [pair], for the tag limit.
  int _fillableIn(SectionPair pair, _Cover cover) {
    int n = 0;
    final (int lo, int hi) = cover.rangeOf(pair);
    for (int i = lo; i <= hi; i++) {
      final RegionParagraph p = cover.paragraphs[i];
      for (final TemplateEntry e in p.entries) {
        if (_fillable(e) && pair.contains(_probe(p, e))) n++;
      }
    }
    return n;
  }

  /// Expands the decided section [d] of [region] in place, then fills its
  /// content, or each copy, as a region of its own.
  void _expand(
    TemplateStory story,
    TemplateRegion region,
    _Decided d,
    List<Object?> scopes,
    Map<SectionTagSite, String> at,
  ) {
    final SectionPair pair = d.pair;
    final String location = at[pair.open]!;
    void warn(DocxWarningCode code) => warnings.add(
      code,
      part: story.part,
      location: location,
      detail: pair.open.text,
    );
    switch (d.effect) {
      case SectionEffect.remove:
        if (removeSection(pair, region, story.story, maxDepth)) {
          warn(DocxWarningCode.templateRemovalDroppedAnnotation);
        }
      case SectionEffect.repeat:
        final RepeatResult result = repeatSection(
          pair,
          region,
          d.items.length,
          maxDepth,
          openLocation: location,
          story: story.story,
        );
        if (result.dropped.isNotEmpty) {
          warn(DocxWarningCode.templateRepeatDroppedAnnotation);
        }
        if (result.halves) {
          warn(DocxWarningCode.templateRemovalDroppedAnnotation);
        }
        // Filling a copy changes how many blocks, rows or inlines it has, so
        // each later copy is found again by its first unit before it fills.
        final List<Object?> firsts = <Object?>[
          for (final TemplateRegion r in result.regions) firstUnitOf(r),
        ];
        int from = 0;
        for (int k = 0; k < result.regions.length; k++) {
          final TemplateRegion region = rebased(
            result.regions[k],
            firsts[k],
            from: from,
          );
          from = startOf(region);
          _region(
            story,
            region,
            <Object?>[...scopes, d.items[k]],
            d.depth,
            prepaid: d.prepaid,
          );
        }
      case SectionEffect.once || SectionEffect.scope || null:
        final ShowResult shown = showSection(
          pair,
          region,
          maxDepth,
          openLocation: location,
          story: story.story,
        );
        if (shown.halves) {
          warn(DocxWarningCode.templateRemovalDroppedAnnotation);
        }
        _region(
          story,
          shown.region,
          <Object?>[...scopes, ...d.items],
          d.depth,
          prepaid: d.prepaid,
        );
    }
  }

  /// Warns for the entry [e] in reading order and adds its edit: a tag's
  /// replacement to [edits], a merge field's to [fields].
  void _entry(
    TemplateEntry e,
    List<Object?> scopes,
    void Function(DocxWarningCode, String) warn,
    List<_Edit> edits,
    List<_Edit> fields, {
    required bool counted,
  }) {
    final DocxWarningCode? problem = e.problem;
    if (problem != null) {
      warn(problem, e.text);
      return;
    }
    if (e.match == null && e.field == null) return;
    if (!counted) {
      if (_tags >= settings.maxTags) {
        warn(DocxWarningCode.templateLimitExceeded, e.text);
        return;
      }
      _tags++;
    }
    if (e.match != null) {
      final String? text = _tagText(e, scopes, warn);
      if (text != null) {
        edits.add((
          offset: e.offset,
          apply: () => replaceSpan(e.map!, e.match!.start, e.match!.end, text),
        ));
      }
      return;
    }
    final MergeField merge = e.merge!;
    for (int i = 0; i < merge.unsupported.length; i++) {
      warn(DocxWarningCode.templateSwitchUnsupported, e.text);
    }
    final (bool fill, String? text) = _fieldText(e, merge, scopes, warn);
    if (!fill) return;
    final DocxInline field = e.field!;
    fields.add((
      offset: e.offset,
      apply: () {
        // The marks the field holds go after its value, so a bookmark or a
        // comment range that starts or ends in its result keeps both halves.
        final List<DocxInline> marks = field is DocxField
            ? fieldMarkCopies(field)
            : marksInSimpleField(field as DocxOpaqueInline, maxDepth);
        spliceHeldInline(field, <DocxInline>[
          if (text != null && text.isNotEmpty) _runFor(field, text),
          ...marks,
        ]);
      },
    ));
  }

  /// The text that replaces the value tag [e], or `null` when it stays.
  String? _tagText(
    TemplateEntry e,
    List<Object?> scopes,
    void Function(DocxWarningCode, String) warn,
  ) {
    final Lookup found = lookupInScopes(
      scopes,
      e.kind == TagKind.current ? const <String>[] : e.path,
    );
    switch (found) {
      case Missing():
        warn(DocxWarningCode.templateValueMissing, e.text);
        return settings.removeMissing ? '' : null;
      case Found(:final Object? value):
        final ValueText text = valueText(value, e.format, formatter);
        if (text.problem != null) {
          warn(text.problem!, e.text);
          return null;
        }
        if (text.formatWarning != null) {
          warn(DocxWarningCode.templateFormatWarning, e.text);
        }
        return text.text;
    }
  }

  /// Whether the merge field [e] changes, and its text: `null` or empty to
  /// remove it.
  (bool, String?) _fieldText(
    TemplateEntry e,
    MergeField merge,
    List<Object?> scopes,
    void Function(DocxWarningCode, String) warn,
  ) {
    switch (lookupKeyInScopes(scopes, merge.name)) {
      case Missing():
        warn(DocxWarningCode.templateValueMissing, e.text);
        return (settings.removeMissing, null);
      case Found(:final Object? value):
        final String? format = value is DateTime
            ? merge.dateFormat
            : value is num || value is FormatDecimal
            ? merge.numberFormat
            : null;
        final ValueText text = valueText(value, format, formatter);
        if (text.problem != null) {
          warn(text.problem!, e.text);
          return (false, null);
        }
        if (text.formatWarning != null) {
          warn(DocxWarningCode.templateFormatWarning, e.text);
        }
        final String shown = text.text!;
        if (shown.isEmpty) return (true, '');
        final String? casing = merge.casing;
        final String cased = casing == null
            ? shown
            : applyCasing(shown, casing, settings.locale);
        return (true, '${merge.before ?? ''}$cased${merge.after ?? ''}');
    }
  }

  /// The run that replaces the merge field [field]: of its first result
  /// run's properties, else its first run's (the begin mark's); for a
  /// `w:fldSimple`, of its first inner run's.
  DocxRun _runFor(DocxInline field, String text) {
    if (field is DocxOpaqueInline) {
      return runOfSimpleField(field, text, maxDepth: maxDepth);
    }
    final DocxField typed = field as DocxField;
    DocxRun? source;
    for (final DocxInline inline in typed.result) {
      if (inline is DocxRun) {
        source = inline;
        break;
      }
    }
    if (source == null) {
      for (final DocxInline inline in heldInlinesOf(typed)!) {
        if (inline is DocxRun) {
          source = inline;
          break;
        }
      }
    }
    return source == null ? DocxRun(text) : copyRunWithText(source, text);
  }
}
