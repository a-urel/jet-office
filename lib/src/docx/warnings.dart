/// Structured warnings about data the DOCX reader or writer had to repair.
///
/// New in jet_office; not ported from Quds. A warning describes a data
/// problem that was repaired instead of failing (decision 0003): characters
/// XML does not allow were removed, or a package declared a part with a
/// content type that was not usable. Warnings aggregate per part and code, so
/// a document with 100,000 dirty runs yields one warning with a count and the
/// first ten locations, not 100,000 objects. A location is a path of steps
/// joined with `/`, each step `name[index]` with a zero-based index among the
/// siblings of that kind: `body/p[12]/r[3]`. A header or footer part starts
/// with its file name: `header1.xml/p[0]`.
library;

import 'dart:collection';

import '../common/locale.dart';
import '../common/warning_aggregator.dart';
import 'read_exception.dart' show displayPart, displayText;
import 'warning_messages.dart';

/// What kind of data problem a [DocxWarning] reports.
enum DocxWarningCode {
  /// Characters XML does not allow (control characters, lone surrogates) were
  /// removed from text.
  invalidCharactersRemoved,

  /// A part had no content type in the package. It was read as the type in
  /// [DocxWarning.detail].
  contentTypeMissing,

  /// The main document part has a content type that is not a Word document
  /// type, given in [DocxWarning.detail]. It was read as a Word document.
  mainPartContentTypeUnexpected,

  /// A paragraph was put in a list through the API (its numbering set) that
  /// the document does not define; [DocxWarning.detail] is the list's id
  /// (`w:numId`). The reference is written as set, and Word shows the
  /// paragraph without a number. A reference read from the file is kept
  /// and never reported.
  numberingNotFound,

  /// A paragraph or a run was given a style through the API (`w:pStyle`,
  /// `w:rStyle`) that the document does not define as a style of that type;
  /// [DocxWarning.detail] is the style's id. The reference is written as
  /// set, and Word shows the text in the default style. A reference read
  /// from the file is kept and never reported.
  styleNotFound,
}

/// One data problem found while reading or writing a DOCX file, possibly
/// aggregated over many occurrences in one part.
final class DocxWarning {
  DocxWarning._(this._entry);

  /// The aggregated entry that holds the code, part, detail, count and
  /// locations.
  final AggregatedWarning<DocxWarningCode> _entry;

  /// The kind of problem.
  DocxWarningCode get code => _entry.code;

  /// The absolute name of the part the problem is in, such as
  /// `/word/document.xml`.
  String get part => _entry.scope as String;

  /// The parameter of the warning, or null when the code has none.
  ///
  /// [DocxWarningCode.contentTypeMissing] carries the content type the part
  /// was read as; [DocxWarningCode.mainPartContentTypeUnexpected] carries the
  /// content type the package declared; [DocxWarningCode.numberingNotFound]
  /// carries the id of the list; [DocxWarningCode.styleNotFound] carries the
  /// id of the style.
  String? get detail => _entry.detail;

  /// How many times the problem occurred in [part].
  int get count => _entry.count;

  /// Paths of the first ten occurrences, in reading order, such as
  /// `body/p[12]/r[3]`.
  ///
  /// Empty for a warning that names no location. An unmodifiable view, the
  /// same object on every call, that shows locations added later.
  List<String> get locations => _entry.locations;

  /// A human-readable description in [locale].
  String message([OfficeLocale locale = OfficeLocale.en]) =>
      formatDocxWarning(this, locale);

  /// The English [message].
  @override
  String toString() => message();
}

/// Whether [w] was given more locations than it keeps, so that its message
/// ends its location list with `…`.
///
/// Not [DocxWarning.count]: one run can lose several characters at one
/// location.
bool locationsTruncated(DocxWarning w) =>
    w._entry.locationsOffered > w._entry.locations.length;

/// Collects warnings while a DOCX file is read or written.
///
/// Warnings aggregate by `(part, code, detail)`. Memory stays bounded: a
/// warning keeps at most ten locations however often it recurs, and a part
/// and code keep at most ten distinct non-null details; later new details
/// aggregate into the warning whose detail is null.
final class DocxWarningCollector {
  final WarningAggregator<DocxWarningCode> _aggregator =
      WarningAggregator<DocxWarningCode>();
  final List<DocxWarning> _warnings = <DocxWarning>[];
  late final List<DocxWarning> _warningsView =
      UnmodifiableListView<DocxWarning>(_warnings);

  /// Records [count] occurrences of [code] in [part], the absolute part name.
  ///
  /// [location] is the path of the occurrence, for codes that have one.
  /// [detail] is the parameter of the code, if it has one. Both [part] and
  /// [detail] may come from the file, so they are cut and cleaned for
  /// display as `DocxReadException.part` is.
  void add(
    DocxWarningCode code, {
    required String part,
    String? location,
    String? detail,
    int count = 1,
  }) {
    final int before = _aggregator.all.length;
    final AggregatedWarning<DocxWarningCode> entry = _aggregator.add(
      code,
      scope: displayPart(part),
      location: location,
      detail: detail == null ? null : displayText(detail),
      count: count,
    );
    // A new entry is appended; an aggregated one is already wrapped.
    if (_aggregator.all.length > before) {
      _warnings.add(DocxWarning._(entry));
    }
  }

  /// The warnings so far, in first-occurrence order. An unmodifiable view,
  /// the same object on every call, that shows warnings added later.
  List<DocxWarning> get warnings => _warningsView;
}
