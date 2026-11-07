/// The sections of a document: what ends each one, and its page.
///
/// Not ported from Quds; written for jet_office.
///
/// A [DocxSection] is a view over a `w:sectPr` as read (a private
/// [PropertySet]), in the shape of `DocxParagraphProperties`: each member is
/// a nullable getter and setter, `null` meaning "not set here", a value the
/// model cannot type reads `null` and stays in the file, setting what a
/// member reads is a no-op, and a set writes one element in the place the
/// schema gives, among the children the model does not type. Every other
/// child stays as read, header and footer references among them: the six
/// getters read them, and reading one creates nothing (plan Ruling 5). An edit
/// of a story adds a reference, and so does [DocxSection.ownHeader]; the part
/// and the relationship it names come at save.
///
/// A section lives in one of two places, and may move from the second to the
/// first (`DocxBody.addSection`): in the `w:pPr` of the paragraph that ends
/// it, or at the end of the body, as the last section. The section reports
/// its edits to the sink of the place it is in ([bindSection]). A last
/// section the file does not have is written once something is set; a
/// section in a paragraph is always written, as it is the break.
///
/// The top-level functions are the model's internal surface for the reader,
/// the writer and the document; none of them is exported.
library;

import '../../xml/xml_writer.dart';
import '../docx_document.dart' show DocxHeaderFooter, DocxHeaderFooterType;
import '../properties.dart';
import '../property_codec.dart' show PropertyElement;
import '../section_property_codecs.dart';
import '../units.dart';
import 'edit_sink.dart';
import 'numbering_formats.dart';
import 'property_set.dart';
import 'section_formatting.dart';

/// What a new last section takes from the section before it (plan Ruling 8):
/// its page, numbering and alignment, and the kept `w:docGrid`. Not its
/// references, so it inherits them, nor its title page or its type.
const Set<String> _copiedChildren = <String>{
  'pgSz',
  'pgMar',
  'lnNumType',
  'pgNumType',
  'cols',
  'vAlign',
  'docGrid',
};

/// A section of a document: a run of the body with one page setup.
///
/// Get them from `DocxDocument.sections`, or from `DocxParagraph.section`
/// for the one a paragraph ends. A section is the same object for as long
/// as it is in the document, also when `DocxBody.addSection` ends it. Each
/// set is one change of the document's change log.
final class DocxSection {
  DocxSection._(PropertyContainer source, this._sink) {
    _set = _SectionSet(source, () => _sink());
  }

  late final PropertySet _set;

  /// What gives the sink of the place the section is in.
  DocxEditSink Function() _sink;

  /// The sink of the document the section belongs to; `null` until it is in
  /// one.
  DocxEditSink? _home;

  /// How big the pages are (`w:pgSz`), or `null`.
  DocxPageSize? get pageSize => _set.valueOf('pgSz') as DocxPageSize?;

  set pageSize(DocxPageSize? value) => _set.setValue('pgSz', value);

  /// The margins of the pages (`w:pgMar`), or `null`.
  DocxPageMargins? get margins => _set.valueOf('pgMar') as DocxPageMargins?;

  set margins(DocxPageMargins? value) => _set.setValue('pgMar', value);

  /// The text columns (`w:cols`), or `null`.
  DocxColumns? get columns => _set.valueOf('cols') as DocxColumns?;

  set columns(DocxColumns? value) => _set.setValue('cols', value);

  /// How the section breaks from the one before it (`w:type`), or `null`:
  /// Word then starts it on the next page.
  DocxSectionStart? get start => _set.valueOf('type') as DocxSectionStart?;

  set start(DocxSectionStart? value) => _set.setValue('type', value);

  /// Whether the section's first page has a header and a footer of its own
  /// (`w:titlePg`).
  ///
  /// Setting `true` sets the child, and setting `false` removes it, unless
  /// it already reads `false`: a `w:titlePg w:val="0"`, or one the model
  /// cannot type, then stays as read.
  bool get titlePage => _set.valueOf('titlePg') == true;

  set titlePage(bool value) {
    if (value != titlePage) _set.setValue('titlePg', value ? true : null);
  }

  /// How the text sits between the top and bottom margins (`w:vAlign`), or
  /// `null`.
  DocxSectionVerticalAlignment? get verticalAlignment =>
      _set.valueOf('vAlign') as DocxSectionVerticalAlignment?;

  set verticalAlignment(DocxSectionVerticalAlignment? value) =>
      _set.setValue('vAlign', value);

  /// How the pages are numbered (`w:pgNumType`), or `null`. Its chapter
  /// attributes, which the model does not type, stay as read.
  DocxPageNumbering? get pageNumbering =>
      _set.valueOf('pgNumType') as DocxPageNumbering?;

  set pageNumbering(DocxPageNumbering? value) =>
      _set.setValue('pgNumType', value);

  /// How the lines are numbered (`w:lnNumType`), or `null`.
  DocxLineNumbering? get lineNumbering =>
      _set.valueOf('lnNumType') as DocxLineNumbering?;

  set lineNumbering(DocxLineNumbering? value) =>
      _set.setValue('lnNumType', value);

  /// The header of the section's pages: the section's own, else the nearest
  /// previous section's ([DocxHeaderFooter.isInherited]), else an empty one.
  ///
  /// Reading it creates nothing, and its part loads only on the first access
  /// to [DocxHeaderFooter.blocks]. A block added to an empty one gives the
  /// section a reference to it, and one added to an inherited one reaches
  /// every section that uses it, as Word's "Link to Previous" does; use
  /// [ownHeader] for one of the section's own. Throws [StateError] for a
  /// section in no document.
  DocxHeaderFooter get header =>
      _headerFooter(DocxHeaderFooterType.primary, isHeader: true);

  /// The header of the section's first page, as [header] reads it. Word shows
  /// it only when this section has a [titlePage], also when it is inherited.
  ///
  /// The first content of a story sets [titlePage] on the sections that have
  /// it as their own, in the same transaction; not on one that inherits it,
  /// which sets its own.
  DocxHeaderFooter get firstHeader =>
      _headerFooter(DocxHeaderFooterType.first, isHeader: true);

  /// The header of the section's even pages, as [header] reads it. Word shows
  /// it only when the document has odd and even headers.
  DocxHeaderFooter get evenHeader =>
      _headerFooter(DocxHeaderFooterType.even, isHeader: true);

  /// The footer of the section's pages, as [header] reads it.
  DocxHeaderFooter get footer =>
      _headerFooter(DocxHeaderFooterType.primary, isHeader: false);

  /// The footer of the section's first page, as [firstHeader] reads it.
  DocxHeaderFooter get firstFooter =>
      _headerFooter(DocxHeaderFooterType.first, isHeader: false);

  /// The footer of the section's even pages, as [evenHeader] reads it.
  DocxHeaderFooter get evenFooter =>
      _headerFooter(DocxHeaderFooterType.even, isHeader: false);

  DocxHeaderFooter _headerFooter(
    DocxHeaderFooterType type, {
    required bool isHeader,
  }) {
    final DocxHeaderFooter? story = _home?.headerFooterOf(
      this,
      type,
      isHeader: isHeader,
    );
    if (story == null) throw StateError('The section is in no document.');
    return story;
  }

  /// Gives the section a header of [type] of its own and returns it: the one
  /// it has, or a new empty one in place of the one it inherits, which it no
  /// longer shows. A reference of [type] that names no header, such as one
  /// with no relationship, is replaced; any other stays.
  ///
  /// A section that gets no content in it still shows an empty header, as a
  /// part of one empty paragraph is written. [DocxHeaderFooterType.first]
  /// sets [titlePage], also when the section had that header.
  ///
  /// One transaction. Throws [StateError] for a section in no document.
  DocxHeaderFooter ownHeader(DocxHeaderFooterType type) =>
      _own(type, isHeader: true);

  /// Gives the section a footer of [type] of its own, as [ownHeader] does.
  DocxHeaderFooter ownFooter(DocxHeaderFooterType type) =>
      _own(type, isHeader: false);

  /// Drops the section's own header of [type], so that it inherits the
  /// previous section's again. Nothing happens when it has none, and a
  /// reference that names no header stays.
  ///
  /// The part and its relationship stay in the package, and [titlePage] stays
  /// as it is. One transaction. Throws [StateError] for a section in no
  /// document.
  void removeHeader(DocxHeaderFooterType type) => _remove(type, isHeader: true);

  /// Drops the section's own footer of [type], as [removeHeader] does.
  void removeFooter(DocxHeaderFooterType type) =>
      _remove(type, isHeader: false);

  DocxHeaderFooter _own(DocxHeaderFooterType type, {required bool isHeader}) {
    final DocxHeaderFooter? story = _home?.ownHeaderFooter(
      this,
      type,
      isHeader: isHeader,
    );
    if (story == null) throw StateError('The section is in no document.');
    return story;
  }

  void _remove(DocxHeaderFooterType type, {required bool isHeader}) {
    final DocxEditSink? home = _home;
    if (home == null) throw StateError('The section is in no document.');
    home.removeHeaderFooter(this, type, isHeader: isHeader);
  }

  /// The width of the text, in points: the width of the page less the left
  /// and right margins and the gutter; `null` while [pageSize] or [margins]
  /// reads `null`.
  ///
  /// It does not count columns, and it is negative for margins wider than
  /// the page, which a file may hold.
  double? get textWidthPt {
    final DocxPageSize? page = pageSize;
    final DocxPageMargins? margin = margins;
    if (page == null || margin == null) return null;
    return ptOfTwips(
      _twips(page.widthPt) -
          _twips(margin.leftPt) -
          _twips(margin.rightPt) -
          _twips(margin.gutterPt),
    );
  }

  /// [pt], a length a value of this library holds, in twips.
  static int _twips(double pt) => twipsOf(pt, 'pt', min: 0, max: maxTwips);
}

/// A section over [source] (a `w:sectPr` as read, or an empty container for
/// a section the file does not have), in no document: its edits go nowhere
/// until [bindSection].
DocxSection newSection(PropertyContainer source) =>
    DocxSection._(source, () => DocxEditSink.none);

/// The last section that follows [previous], in no document yet, as
/// `DocxBody.addSection` makes it (plan Ruling 8): [start] as its type, and
/// a copy of [_copiedChildren] with the values set on them, without the
/// first page number. A `w:pgNumType` the model cannot type may hold one, so
/// it is not copied.
DocxSection nextSection(DocxSection previous, DocxSectionStart start) {
  final PropertySet from = previous._set;
  final DocxSection next = newSection(from.source.keeping(_copiedChildren));
  final PropertySet to = next._set;
  for (final String name in _copiedChildren) {
    if (from.isSet(name)) to.restore(name, from.stateOf(name));
  }
  final DocxPageNumbering? numbering = next.pageNumbering;
  if (numbering == null) {
    if (!to.isSet('pgNumType')) to.clearChild('pgNumType');
  } else if (numbering.start != null) {
    final DocxNumberFormat? format = numbering.format;
    next.pageNumbering = format == null
        ? null
        : DocxPageNumbering(format: format);
  }
  next.start = start;
  return next;
}

/// Makes [section] report its edits to the sink [sink] gives from now on.
void bindSection(DocxSection section, DocxEditSink Function() sink) {
  section._sink = sink;
}

/// Records that [section] belongs to the document of [sink].
void setSectionHome(DocxSection section, DocxEditSink sink) {
  section._home = sink;
}

/// The sink of the document [section] belongs to, or `null`.
DocxEditSink? sectionHomeOf(DocxSection section) => section._home;

/// The references of [section] the model can type, in order: to headers when
/// [isHeader], else to footers.
Iterable<SectionReference> sectionReferencesOf(
  DocxSection section, {
  required bool isHeader,
}) => section._set
    .repeatedOf(_referenceName(isHeader))
    .whereType<SectionReference>();

/// Puts [reference] in [section], in place of the first reference of its type
/// there: when the section has a story of that type this is not called, so
/// that one names nothing. To a header when [isHeader], else to a footer.
void putSectionReference(
  DocxSection section,
  SectionReference reference, {
  required bool isHeader,
}) {
  final String name = _referenceName(isHeader);
  final PropertySet set = section._set;
  final List<Object?> views = set.repeatedOf(name);
  final List<PropertyElement?> elements = set.repeatedElementsOf(name);
  for (int i = 0; i < views.length; i++) {
    final Object? view = views[i];
    final bool sameType = view is SectionReference
        ? view.type == reference.type
        : elements[i]?.w('type') == reference.type.xml;
    if (sameType) {
      set.replaceRepeatedAt(name, i, reference);
      return;
    }
  }
  set.addRepeated(name, reference);
}

/// Removes the references of [section] that [drops] says so of, to headers
/// when [isHeader], else to footers.
void removeSectionReferences(
  DocxSection section,
  bool Function(SectionReference) drops, {
  required bool isHeader,
}) {
  final String name = _referenceName(isHeader);
  final PropertySet set = section._set;
  final List<Object?> views = set.repeatedOf(name);
  for (int i = views.length - 1; i >= 0; i--) {
    final Object? view = views[i];
    if (view is SectionReference && drops(view)) {
      set.removeRepeatedAt(name, i);
    }
  }
}

String _referenceName(bool isHeader) =>
    isHeader ? 'headerReference' : 'footerReference';

/// The properties of [section], for the writer.
PropertySet sectionPropertySetOf(DocxSection section) => section._set;

/// What the `w:pPr` of a paragraph writes for its break [section]: its
/// `w:sectPr`, even with nothing in it.
NestedProperties sectionBreakOf(DocxSection section) =>
    _SectionBreak(section._set);

/// A `w:sectPr` in a paragraph, which is the break whatever it holds.
final class _SectionBreak implements NestedProperties {
  const _SectionBreak(this._set);

  final PropertySet _set;

  @override
  bool get writesNothing => false;

  @override
  void writeTo(
    XmlWriter w,
    String qualifiedName, {
    String prefix = 'w',
    Map<String, String> declaredAbove = const <String, String>{},
  }) => _set.writeTo(
    w,
    qualifiedName,
    prefix: prefix,
    declaredAbove: declaredAbove,
  );
}

/// The property set of a `w:sectPr`.
final class _SectionSet extends PropertySet {
  _SectionSet(PropertyContainer source, DocxEditSink Function() sink)
    : super(source, sectionPropertiesSchema, sink);
}
