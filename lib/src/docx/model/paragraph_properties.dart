/// The formatting of a paragraph: alignment, indentation, spacing, borders,
/// tab stops, list membership and the rest of a paragraph's `w:pPr`.
///
/// Not ported from Quds; written for jet_office.
///
/// [DocxParagraphProperties] is a view over the `w:pPr` of a paragraph as
/// read (a private [PropertySet]). Each member is a nullable getter and
/// setter, `null` meaning "not set here" (the style or the document default
/// decides). Reading gives what the file holds when the model can type it,
/// else `null`: a `w:ind w:left="1in"` or a `w:jc w:val="lowKashida"` reads
/// `null` and stays in the file (plan Ruling 2). Setting writes one element,
/// replacing the old one, in the place the schema gives; the paragraph
/// mark's `w:rPr`, `w:sectPr`, `w:pPrChange` and every child the model does
/// not type stay as read. Setting a property to the value it reads is a
/// no-op, so such a set neither records a change nor rewrites a child the
/// model reads in another spelling. To remove formatting the getter cannot
/// read, use [DocxParagraphProperties.clear].
///
/// Lengths are points; a value is rounded to the file's unit and reads back
/// rounded (Ruling 4).
library;

import '../paragraph_property_codecs.dart';
import '../properties.dart';
import '../property_codec.dart';
import 'edit_sink.dart';
import 'formatting.dart';
import 'property_set.dart';
import 'styles.dart' show DocxStyleType;

/// A property of a paragraph, to name it for
/// [DocxParagraphProperties.clear].
enum DocxParagraphProperty {
  /// The paragraph style, [DocxParagraphProperties.style] (`w:pStyle`).
  style('pStyle'),

  /// The alignment, [DocxParagraphProperties.alignment] (`w:jc`).
  alignment('jc'),

  /// The indentation, [DocxParagraphProperties.indentation] (`w:ind`).
  indentation('ind'),

  /// The spacing, [DocxParagraphProperties.spacing] (`w:spacing`).
  spacing('spacing'),

  /// Keep with the next paragraph, [DocxParagraphProperties.keepWithNext]
  /// (`w:keepNext`).
  keepWithNext('keepNext'),

  /// Keep the lines together, [DocxParagraphProperties.keepLines]
  /// (`w:keepLines`).
  keepLines('keepLines'),

  /// A page break before, [DocxParagraphProperties.pageBreakBefore]
  /// (`w:pageBreakBefore`).
  pageBreakBefore('pageBreakBefore'),

  /// Widow and orphan control, [DocxParagraphProperties.widowControl]
  /// (`w:widowControl`).
  widowControl('widowControl'),

  /// The outline level, [DocxParagraphProperties.outlineLevel]
  /// (`w:outlineLvl`).
  outlineLevel('outlineLvl'),

  /// The borders, [DocxParagraphProperties.borders] (`w:pBdr`).
  borders('pBdr'),

  /// The shading, [DocxParagraphProperties.shading] (`w:shd`).
  shading('shd'),

  /// The tab stops, [DocxParagraphProperties.tabs] (`w:tabs`).
  tabs('tabs'),

  /// The list membership, [DocxParagraphProperties.numbering]
  /// (`w:numPr`).
  numbering('numPr');

  const DocxParagraphProperty(this._element);

  final String _element;
}

/// The properties of a paragraph (`w:pPr`), also as a style or the
/// document defaults give them.
///
/// Get one from `DocxParagraph.properties`, `DocxStyle.paragraphProperties`
/// or `DocxDocumentDefaults.paragraphProperties`; it is the same object
/// every time. Each set is one change of the document's change log.
final class DocxParagraphProperties {
  DocxParagraphProperties._(
    PropertyContainer source,
    ContainerSchema schema,
    DocxEditSink Function() sink,
  ) : _set = _ParagraphSet(source, schema, sink);

  /// The set behind the members; private so a caller cannot reach its
  /// untyped surface.
  final PropertySet _set;

  /// The id of the paragraph's style (`w:pStyle`), or `null`.
  ///
  /// A `w:pStyle` the model does not type (no `w:val`, an empty one, other
  /// attributes, child elements) reads `null` and is written back as read.
  /// Setting the empty string, or an id holding a character XML forbids,
  /// throws [ArgumentError]; `null` removes the style.
  ///
  /// On a paragraph in a document, the id set is resolved against the
  /// document's styles, which loads them: an id the document defines is
  /// kept; the English id of a built-in paragraph style (`Heading1`) becomes
  /// the id the document has for it, whatever its language, so `Heading1`
  /// reads back as `Balk1` in a Turkish document, and the built-in is added
  /// when the document lacks it. Any other id is kept and reported at save
  /// (`DocxWarningCode.styleNotFound`). A paragraph in no document is
  /// resolved when it is inserted into one.
  ///
  /// A styles part that cannot be read makes the set throw a
  /// `DocxReadException` naming it, on a document that opened; nothing
  /// changes then.
  String? get style => _set.valueOf('pStyle') as String?;

  set style(String? value) {
    checkStyleId(value);
    _set.setStyleId('pStyle', value, DocxStyleType.paragraph);
  }

  /// The alignment (`w:jc`), or `null`.
  ///
  /// A `w:jc` of a kashida value, `numTab` or `thaiDistribute` reads `null`
  /// and is written back as read.
  DocxAlignment? get alignment => _set.valueOf('jc') as DocxAlignment?;

  set alignment(DocxAlignment? value) => _set.setValue('jc', value);

  /// The indentation (`w:ind`), or `null`.
  ///
  /// A `w:ind` with `w:start`, `w:end`, a `…Chars` attribute, both
  /// `w:firstLine` and `w:hanging`, or a value the model cannot read
  /// (`1in`) reads `null` and is written back as read.
  DocxIndentation? get indentation => _set.valueOf('ind') as DocxIndentation?;

  set indentation(DocxIndentation? value) => _set.setValue('ind', value);

  /// The spacing before, after and between lines (`w:spacing`), or `null`.
  ///
  /// A `w:spacing` with a `…Lines` attribute, a line rule the model does
  /// not know, a `w:lineRule` without `w:line`, or a `w:line` of 0 under
  /// the `auto` rule (or no rule) reads `null` and is written back as
  /// read.
  DocxSpacing? get spacing => _set.valueOf('spacing') as DocxSpacing?;

  set spacing(DocxSpacing? value) => _set.setValue('spacing', value);

  /// Whether the paragraph stays on the page of the next one
  /// (`w:keepNext`), or `null`. `false` is written as `w:val="0"`.
  bool? get keepWithNext => _set.valueOf('keepNext') as bool?;

  set keepWithNext(bool? value) => _set.setValue('keepNext', value);

  /// Whether the lines of the paragraph stay on one page (`w:keepLines`),
  /// or `null`.
  bool? get keepLines => _set.valueOf('keepLines') as bool?;

  set keepLines(bool? value) => _set.setValue('keepLines', value);

  /// Whether the paragraph starts a page (`w:pageBreakBefore`), or `null`.
  bool? get pageBreakBefore => _set.valueOf('pageBreakBefore') as bool?;

  set pageBreakBefore(bool? value) => _set.setValue('pageBreakBefore', value);

  /// Whether a single line is kept from a page of its own (`w:widowControl`),
  /// or `null`. `false` is written as `w:val="0"`, which turns off what a
  /// style turned on.
  bool? get widowControl => _set.valueOf('widowControl') as bool?;

  set widowControl(bool? value) => _set.setValue('widowControl', value);

  /// The outline level (`w:outlineLvl`), from 0 (level 1) to 8; 9 is body
  /// text. `null` when not set.
  ///
  /// Setting a level outside 0 to 9 throws [RangeError].
  int? get outlineLevel => _set.valueOf('outlineLvl') as int?;

  set outlineLevel(int? value) {
    if (value != null) {
      RangeError.checkValueInInterval(value, 0, 9, 'outlineLevel');
    }
    _set.setValue('outlineLvl', value);
  }

  /// The borders (`w:pBdr`), or `null`.
  ///
  /// A `w:pBdr` with an art border, a side twice, or a child the model does
  /// not know reads `null` and is written back as read.
  DocxParagraphBorders? get borders =>
      _set.valueOf('pBdr') as DocxParagraphBorders?;

  set borders(DocxParagraphBorders? value) => _set.setValue('pBdr', value);

  /// The shading behind the paragraph (`w:shd`), or `null`.
  DocxShading? get shading => _set.valueOf('shd') as DocxShading?;

  set shading(DocxShading? value) => _set.setValue('shd', value);

  /// The tab stops (`w:tabs`), or `null`. The list cannot be modified.
  ///
  /// Setting replaces all the stops; `null` or an empty list removes
  /// `w:tabs`. A `w:tabs` with a child the model does not know, or with no
  /// stop, reads `null` and is written back as read.
  List<DocxTabStop>? get tabs => _set.valueOf('tabs') as List<DocxTabStop>?;

  set tabs(List<DocxTabStop>? value) {
    final List<DocxTabStop>? stops = value == null || value.isEmpty
        ? null
        : List<DocxTabStop>.unmodifiable(value);
    final List<DocxTabStop>? current = tabs;
    if (stops == null || current == null) {
      _set.setValue('tabs', stops);
      return;
    }
    if (_sameStops(stops, current)) {
      return;
    }
    _set.setValue('tabs', stops);
  }

  /// The list the paragraph belongs to and its level (`w:numPr`), or
  /// `null`.
  ///
  /// A `w:numPr` without `w:numId`, or with `w:numberingChange` or
  /// `w:ins`, reads `null` and is written back as read. Setting always
  /// writes the level, and `numId` 0 removes the paragraph from the list
  /// its style gives.
  DocxNumberingRef? get numbering => _set.valueOf('numPr') as DocxNumberingRef?;

  set numbering(DocxNumberingRef? value) => _set.setValue('numPr', value);

  /// Removes [property] from the paragraph, whatever the getter reads of
  /// it.
  ///
  /// Setting a property to `null` does nothing when it already reads
  /// `null`, so a child the model cannot type (a `w:ind w:left="1in"`, a
  /// `w:jc w:val="lowKashida"`) stays; clear removes every such child.
  /// Nothing is recorded when the paragraph has no such child. The
  /// paragraph mark's `w:rPr` is not a property and is never removed.
  void clear(DocxParagraphProperty property) =>
      _set.clearChild(property._element);
}

bool _sameStops(List<DocxTabStop> a, List<DocxTabStop> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// The paragraph properties over [source], read by [schema]: a paragraph's
/// `w:pPr` (`paragraphPropertiesSchema`, as `DocxParagraph` holds them) or
/// the `w:pPr` of a style or a default (`paragraphPropertiesGeneralSchema`).
/// Edits go to the sink [sink] gives.
DocxParagraphProperties newParagraphProperties(
  PropertyContainer source,
  DocxEditSink Function() sink, {
  ContainerSchema schema = paragraphPropertiesSchema,
}) => DocxParagraphProperties._(source, schema, sink);

/// The property set behind [properties], for the writer and the edit
/// primitives. Not exported.
PropertySet propertySetOfParagraphProperties(
  DocxParagraphProperties properties,
) => properties._set;

/// The property set of a `w:pPr`.
final class _ParagraphSet extends PropertySet {
  _ParagraphSet(super.source, super.schema, super.sink);
}
