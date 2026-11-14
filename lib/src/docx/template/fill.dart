/// The template fill of T1: `{{}}` value tags and Word's `MERGEFIELD`s in the
/// body, its tables, headers and footers, filled in place from one map of
/// data, and the listing of a template's tags.
///
/// New in jet_office (decision 0024, spec sections 3.2, 5, 6, 8 and 10);
/// quds_office_engine has no template fill, so this is not ported from Quds.
/// A fill is one transaction of the document's change log, so one undo takes
/// it back. What cannot be filled stays as written and is reported in the
/// fill's own warnings, never in [DocxDocument.warnings]: a tag that is
/// malformed, inside a tracked change, a content control, a field result or
/// opaque content (text boxes, the footnotes, endnotes and comments parts),
/// a section tag (sections are filled from T2), a value the data lacks or
/// that is not text, and a `MERGEFIELD` the model does not type.
///
/// The walk is `template_walk.dart`'s; the text scan of opaque content is
/// `opaque_scan.dart`'s.
library;

import 'package:jet_core/jet_core.dart';

import '../../opc/change_log.dart';
import '../docx_document.dart';
import '../docx_package.dart';
import '../model/inlines.dart';
import '../warnings.dart';
import 'merge_field.dart';
import 'opaque_scan.dart';
import 'replace.dart';
import 'tag_scanner.dart';
import 'template_walk.dart';
import 'values.dart';

/// How a template is filled.
final class FillSettings {
  /// Creates settings: [locale] for numbers, dates and casing, and whether a
  /// tag or merge field the data lacks is removed ([removeMissing]) rather
  /// than left as written.
  const FillSettings({
    this.locale = FormatLocale.enUS,
    this.removeMissing = false,
  });

  /// The locale values are shown in, as Excel for Mac shows them.
  final FormatLocale locale;

  /// Whether a tag or merge field whose value is missing is removed. It is
  /// warned about either way.
  final bool removeMissing;
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

  /// How many section tags are open around it in its story (Ruling 12).
  final int depth;
}

final Expando<ChangeSet> _lastFill = Expando<ChangeSet>('lastFill');

/// The change set of the last fill of [document], for tests; `null` before
/// one.
ChangeSet? lastFillChangeSet(DocxDocument document) => _lastFill[document];

/// Fills [document] with [data] in one transaction (`documentTransaction`)
/// and returns the fill's warnings.
///
/// [data] is checked first (`checkTemplateData`): an [ArgumentError] then
/// leaves the document unchanged and records nothing. Names are looked up in
/// [data] itself.
List<DocxWarning> fillTemplate(
  DocxDocument document,
  Map<String, Object?> data,
  FillSettings settings,
) {
  checkTemplateData(data);
  final _Fill fill = _Fill(document, data, settings);
  _lastFill[document] = documentTransaction(document, fill.run);
  return fill.warnings.warnings;
}

/// The tags and merge fields of [document] in reading order, as a fill would
/// meet them, without changing it.
List<FoundTag> listTemplateTags(DocxDocument document) {
  final int maxDepth = docxPackageOf(document).limits.maxDepth;
  final List<FoundTag> out = <FoundTag>[];
  for (final TemplateStory story in templateStories(document)) {
    final List<int> open = <int>[];
    walkTemplateStory(story, maxDepth, (
      String location,
      List<TemplateEntry> entries,
    ) {
      for (final TemplateEntry e in entries) {
        int depth = open.length;
        switch (e.kind) {
          case TagKind.section || TagKind.invertedSection:
            open.add(0);
          case TagKind.sectionEnd:
            if (open.isNotEmpty) open.removeLast();
            depth = open.length;
          default:
            break;
        }
        out.add(_found(e, story.part, location, depth));
      }
    });
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

FoundTag _found(TemplateEntry e, String part, String? location, int depth) =>
    FoundTag(
      kind: e.kind,
      mergeField: e.mergeField,
      path: List<String>.unmodifiable(e.path),
      format: e.format,
      text: e.text,
      part: part,
      location: location,
      problem: e.problem,
      depth: depth,
    );

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

  void run() {
    for (final TemplateStory story in templateStories(document)) {
      walkTemplateStory(
        story,
        maxDepth,
        (String location, List<TemplateEntry> entries) =>
            _paragraph(story.part, location, entries),
      );
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

  /// Warns and fills the [entries] of one paragraph: every warning in
  /// reading order, then the text tags from the last to the first, then the
  /// merge fields, so no value is read as a tag.
  void _paragraph(String part, String location, List<TemplateEntry> entries) {
    void warn(DocxWarningCode code, String detail) =>
        warnings.add(code, part: part, location: location, detail: detail);

    final List<(TemplateEntry, String)> tags = <(TemplateEntry, String)>[];
    final List<(DocxInline, String?)> fields = <(DocxInline, String?)>[];
    for (final TemplateEntry e in entries) {
      final DocxWarningCode? problem = e.problem;
      if (problem != null) {
        warn(problem, e.text);
      } else if (e.match != null) {
        final String? text = _tagText(e, warn);
        if (text != null) tags.add((e, text));
      } else if (e.field != null) {
        final MergeField merge = e.merge!;
        for (int i = 0; i < merge.unsupported.length; i++) {
          warn(DocxWarningCode.templateSwitchUnsupported, e.text);
        }
        final (bool fill, String? text) = _fieldText(e, merge, warn);
        if (fill) fields.add((e.field!, text));
      }
    }
    for (final (TemplateEntry e, String text) in tags.reversed) {
      replaceSpan(e.map!, e.match!.start, e.match!.end, text);
    }
    for (final (DocxInline field, String? text) in fields) {
      if (text == null || text.isEmpty) {
        removeHeldInline(field);
      } else {
        replaceHeldInline(field, _runFor(field, text));
      }
    }
  }

  /// The text that replaces the value tag [e], or `null` when it stays.
  String? _tagText(
    TemplateEntry e,
    void Function(DocxWarningCode, String) warn,
  ) {
    final Lookup found = e.kind == TagKind.current
        ? Found(data)
        : lookupPath(data, e.path);
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
    void Function(DocxWarningCode, String) warn,
  ) {
    switch (lookupKey(data, merge.name)) {
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
