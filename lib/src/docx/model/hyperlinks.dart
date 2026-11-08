/// Hyperlinks: [DocxHyperlink], a `w:hyperlink` child of a paragraph.
///
/// Not ported from Quds; written for jet_office. It is a part of the inlines'
/// library because [DocxInline] is sealed.
///
/// A hyperlink read from a file keeps the attributes of its start tag and
/// holds its children as inlines, read by the rules of a paragraph's (plan
/// D5, Ruling 8): runs, bookmark marks, opaque inlines, and the plain fields
/// among them grouped inside the hyperlink alone, so a field that crosses its
/// edge stays runs. The writer writes the start tag as read and then the
/// inlines, which is why typing a hyperlink read changes nothing in the part.
/// A `w:hyperlink` inside another inline (a `w:ins`, another hyperlink) stays
/// inside that opaque inline.
///
/// To a field around it, a hyperlink is what the opaque inline it was before
/// D5 was: the reader records whether a run is inside it and whether the
/// field marks inside it pair among themselves, so the fields of a paragraph
/// are grouped as they were.
part of 'inlines.dart';

/// A hyperlink, `w:hyperlink`: inlines that link to an address or to a
/// bookmark of the document.
///
/// [DocxParagraph.inlines] shows a hyperlink as one inline; [inlines] shows
/// what it holds. Its runs are ordinary [DocxRun]s whose text and properties
/// can be set: each such edit is one change of the document's log, as for a
/// run of the paragraph, and a run of a hyperlink counts in the run locations
/// of its paragraph's warnings (`p[i]/r[j]`), in file order. A run stays in
/// its hyperlink: it cannot be inserted elsewhere, even after the hyperlink
/// left its paragraph.
///
/// A hyperlink read in one document and inserted in another keeps its `r:id`
/// as read (plan D5, Ruling 13), which that document may lack or mean
/// otherwise; [url] still gives the target the part it was read from names.
final class DocxHyperlink extends DocxInline {
  DocxHyperlink._read(
    this._attributes,
    List<DocxInline> inlines,
    this._resolveUrl,
    this._holdsRuns,
    this._breaksFields,
  ) : _inlines = inlines,
      super._() {
    for (final DocxInline inline in _inlines) {
      inline._hyperlink = this;
    }
  }

  /// The attributes of `w:hyperlink` as read, written back as they are.
  final List<KeptAttribute> _attributes;

  final List<DocxInline> _inlines;

  late final List<DocxInline> _inlinesView = UnmodifiableListView<DocxInline>(
    _inlines,
  );

  /// The target of a relationship of the part the hyperlink was read from,
  /// by its id, when that relationship is an external hyperlink; `null` for
  /// none, or when nothing can say.
  final String? Function(String id)? _resolveUrl;

  /// Whether a run or a `w:fldSimple` is inside the element, which can then
  /// not sit in the instruction of a field.
  final bool _holdsRuns;

  /// Whether the field marks inside the element do not pair among themselves,
  /// so some of them belong to a field around it.
  final bool _breaksFields;

  /// The value of the attribute [localName] in [namespaceUri], by default
  /// WordprocessingML, or `null`.
  String? _attribute(String localName, [String namespaceUri = Ns.w]) {
    for (final KeptAttribute a in _attributes) {
      if (a.namespaceUri == namespaceUri &&
          a.qualifiedName.endsWith(':$localName')) {
        return a.value;
      }
    }
    return null;
  }

  /// The address the hyperlink links to: the target of the relationship its
  /// `r:id` names, in the part it was read from, when that relationship is of
  /// the hyperlink type and external (`TargetMode="External"`); `null`
  /// otherwise, and for a hyperlink without `r:id`.
  ///
  /// It is found on the first read and kept. A header's or footer's
  /// relationships are read for it without being marked for rewriting, so
  /// the save still copies them as they were (Ruling 12). A relationships part
  /// that cannot be read gives `null`, and throws nothing: the part's own
  /// content read, and the link still writes as read.
  late final String? url = _findUrl();

  String? _findUrl() {
    final String? id = _attribute('id', Ns.rel);
    final String? Function(String)? resolve = _resolveUrl;
    if (id == null || resolve == null) return null;
    return resolve(id);
  }

  /// The bookmark the hyperlink links to (`w:anchor`), or `null`.
  String? get anchor => _attribute('anchor');

  /// The text shown when the pointer rests on the hyperlink (`w:tooltip`), or
  /// `null`.
  String? get tooltip => _attribute('tooltip');

  /// The inlines the hyperlink holds, in order: runs, fields, bookmark marks
  /// and opaque inlines. The list cannot be modified.
  List<DocxInline> get inlines => _inlinesView;

  /// The text of [inlines], as a paragraph's text is made of its inlines'.
  @override
  String get text {
    final StringBuffer out = StringBuffer();
    for (final DocxInline inline in _inlines) {
      out.write(inline.text);
    }
    return out.toString();
  }

  @override
  String toString() => 'DocxHyperlink(${url ?? anchor ?? ''})';
}

/// A hyperlink the reader found: [attributes] of its start tag as read,
/// [inlines] its children read as a paragraph's and grouped by [groupFields],
/// and [resolveUrl] the target of an external hyperlink relationship of its
/// part by id, or `null` when the part has no relationships to ask.
/// [holdsRuns] and [breaksFields] are what an opaque inline of the same
/// element would hold ([opaqueInline]).
DocxHyperlink readHyperlink({
  required List<KeptAttribute> attributes,
  required List<DocxInline> inlines,
  required String? Function(String id)? resolveUrl,
  required bool holdsRuns,
  required bool breaksFields,
}) => DocxHyperlink._read(
  attributes,
  inlines,
  resolveUrl,
  holdsRuns,
  breaksFields,
);

/// The attributes of `w:hyperlink` the reader kept on [link], in source
/// order.
List<KeptAttribute> hyperlinkAttributesOf(DocxHyperlink link) =>
    link._attributes;
