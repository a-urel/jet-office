/// The public face of the DOCX template fill (decision 0024, T1): open a
/// template once, list its tags, and fill it with data as often as needed.
///
/// New in jet_office; quds_office_engine has no template fill, so this is not
/// ported from Quds. It wraps `fill.dart`, which does the work in one
/// transaction of the document's change log.
///
/// @docImport '../read_exception.dart';
library;

import 'dart:typed_data';

import 'package:jet_core/jet_core.dart';

import '../docx_document.dart';
import '../read_limits.dart';
import '../warnings.dart';
import 'fill.dart';
import 'tag_scanner.dart';

/// A DOCX template: a document with `{{}}` tags and Word merge fields that is
/// filled with data into new documents.
///
/// The template keeps a copy of its bytes and never changes: each [fill]
/// opens that copy, fills it and saves a new file. A tag is `{{path}}`,
/// `{{path:format}}` or a section; a `MERGEFIELD` is filled from the same
/// data. What cannot be filled stays as written and is reported in the
/// result's warnings.
///
/// ```dart
/// final DocxTemplate template = DocxTemplate(bytes);
/// final DocxResult result = template.fill(
///   <String, Object?>{
///     'musteri': <String, Object?>{'unvan': 'Acme A.Ş.'},
///     'tutar': FormatDecimal('1234.56'),
///   },
///   options: const DocxTemplateOptions(locale: FormatLocale.trTR),
/// );
/// ```
final class DocxTemplate {
  /// Opens [bytes] once to check them, lists their tags and keeps a copy.
  ///
  /// Throws a [DocxReadException] as [DocxDocument.open] does, or when the
  /// body, a header or a footer part cannot be read, and an [ArgumentError]
  /// when a limit is below 1.
  DocxTemplate(
    Uint8List bytes, {
    DocxReadLimits limits = const DocxReadLimits(),
  }) : _bytes = Uint8List.fromList(bytes),
       _limits = limits {
    _tags = List<DocxTemplateTag>.unmodifiable(
      listTemplateTags(DocxDocument.open(_bytes, limits: limits)).map(_tagOf),
    );
  }

  final Uint8List _bytes;
  final DocxReadLimits _limits;
  late final List<DocxTemplateTag> _tags;

  /// The template's tags in reading order: the body, then each header and
  /// footer. The list is the same for every call and cannot be modified.
  List<DocxTemplateTag> get tags => _tags;

  /// A new document: the template filled with [data], saved.
  ///
  /// The result's warnings are the fill's, then the save's. Throws an
  /// [ArgumentError] when [data] holds a value that is not a supported kind;
  /// nothing is filled then. Throws a [DocxReadException] when a part of the
  /// copy cannot be read, as [DocxDocument.open] and [DocxDocument.save] do;
  /// the template read its body, headers and footers when it was made.
  DocxResult fill(
    Map<String, Object?> data, {
    DocxTemplateOptions options = const DocxTemplateOptions(),
  }) {
    final DocxDocument document = DocxDocument.open(_bytes, limits: _limits);
    final List<DocxWarning> fillWarnings = fillDocument(
      document,
      data,
      options: options,
    );
    final DocxResult saved = document.save();
    return newDocxResult(saved.bytes, <DocxWarning>[
      ...fillWarnings,
      ...saved.warnings,
    ]);
  }

  /// Fills [document] in place with [data] as one edit and returns the fill's
  /// warnings.
  ///
  /// Throws an [ArgumentError] for a value that is not a supported kind, and
  /// a [DocxReadException] when the body, a header or a footer part of
  /// [document] cannot be read; either way [document] is left unchanged.
  static List<DocxWarning> fillDocument(
    DocxDocument document,
    Map<String, Object?> data, {
    DocxTemplateOptions options = const DocxTemplateOptions(),
  }) => fillTemplate(
    document,
    data,
    FillSettings(locale: options.locale, removeMissing: options.removeMissing),
  );

  /// The tags of [document] in reading order, without changing it. The list
  /// cannot be modified.
  ///
  /// Throws a [DocxReadException] when a header or footer part of
  /// [document] cannot be read.
  static List<DocxTemplateTag> tagsOf(DocxDocument document) =>
      List<DocxTemplateTag>.unmodifiable(
        listTemplateTags(document).map(_tagOf),
      );

  static DocxTemplateTag _tagOf(FoundTag t) {
    final DocxTemplateTagKind kind;
    if (t.mergeField) {
      kind = DocxTemplateTagKind.mergeField;
    } else if (t.kind == null) {
      kind = DocxTemplateTagKind.malformed;
    } else {
      kind = switch (t.kind!) {
        TagKind.value => DocxTemplateTagKind.value,
        TagKind.section => DocxTemplateTagKind.section,
        TagKind.invertedSection => DocxTemplateTagKind.invertedSection,
        TagKind.sectionEnd => DocxTemplateTagKind.sectionEnd,
        TagKind.current => DocxTemplateTagKind.current,
      };
    }
    final bool named =
        kind != DocxTemplateTagKind.malformed &&
        kind != DocxTemplateTagKind.current &&
        t.path.isNotEmpty;
    return DocxTemplateTag._(
      kind: kind,
      name: named ? t.path.join('.') : null,
      format: t.format,
      text: t.text,
      part: t.part,
      location: t.location,
      problem: t.problem,
      depth: t.depth,
    );
  }
}

/// How a template is filled.
final class DocxTemplateOptions {
  /// Creates options: [locale] for numbers, dates and casing, and whether a
  /// tag or merge field the data lacks is removed ([removeMissing]) rather
  /// than left as written.
  const DocxTemplateOptions({
    this.locale = FormatLocale.enUS,
    this.removeMissing = false,
  });

  /// The locale values are shown in, as Excel for Mac shows them.
  final FormatLocale locale;

  /// Whether a tag or merge field whose value is missing is removed. It is
  /// warned about either way.
  final bool removeMissing;
}

/// What a tag of a template is.
enum DocxTemplateTagKind {
  /// `{{path}}` or `{{path:format}}`: a value.
  value,

  /// `{{#path}}`: the start of a section.
  section,

  /// `{{^path}}`: the start of an inverted section.
  invertedSection,

  /// `{{/path}}`: the end of a section.
  sectionEnd,

  /// `{{.}}`: the current item of a section.
  current,

  /// A Word `MERGEFIELD`.
  mergeField,

  /// Braces that do not form a tag.
  malformed,
}

/// A tag or merge field of a template, as [DocxTemplate.tags] lists it.
final class DocxTemplateTag {
  const DocxTemplateTag._({
    required this.kind,
    required this.name,
    required this.format,
    required this.text,
    required this.part,
    required this.location,
    required this.problem,
    required this.depth,
  });

  /// What the tag is.
  final DocxTemplateTagKind kind;

  /// The tag's path joined by `.`, or the merge field's name as written;
  /// `null` for a malformed tag and for the current item.
  final String? name;

  /// The tag's format code, or the merge field's number or date picture as a
  /// format code; `null` when it has none.
  final String? format;

  /// The tag or the field instruction as written.
  final String text;

  /// The absolute name of the part it is in, such as `/word/document.xml`.
  final String part;

  /// The path of its paragraph, such as `body/tbl[0]/tr[1]/tc[0]/p[0]`;
  /// `null` in a footnotes, endnotes or comments part.
  final String? location;

  /// The warning a fill raises for the tag's form, or `null` for a tag a
  /// fill can fill (it may still warn for the data it gets).
  final DocxWarningCode? problem;

  /// How many section tags are open around it in its story.
  final int depth;
}
