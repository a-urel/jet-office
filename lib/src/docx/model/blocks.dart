/// The blocks of a body, the children of `w:body`: paragraphs, and opaque
/// blocks for everything else.
///
/// Not ported from Quds; written for jet_office.
///
/// A [DocxParagraph] holds its inlines and its properties (`w:pPr`, a
/// [PropertySet]), of which D1 types only the style. A [DocxOpaqueBlock]
/// keeps an element the model does not type, such as a table until D3 or a
/// content control, as written.
///
/// The top-level functions are the model's internal surface for the reader,
/// the writer and the document; none of them is exported.
library;

import 'dart:collection';

import '../../opc/opaque_xml.dart';
import '../properties.dart';
import '../property_codec.dart' show checkStyleId;
import 'edit_sink.dart';
import 'inlines.dart';
import 'property_set.dart';

/// One child of a body.
///
/// A block is in at most one container at a time: inserting one that is
/// already in a body throws [StateError]; remove it there first.
sealed class DocxBlock {
  DocxBlock._();

  /// The container the block is in, such as a document's body, or `null`
  /// while it is in none.
  Object? _container;
}

/// A paragraph, `w:p`.
final class DocxParagraph extends DocxBlock {
  /// An empty paragraph: no inlines, no style and no other properties.
  ///
  /// It belongs to no document until it is inserted into one.
  DocxParagraph()
    : _source = const PropertyContainer.empty(),
      _attributes = const <KeptAttribute>[],
      super._();

  /// A paragraph with one run that holds [text], or none when [text] is
  /// empty. The text is split and scrubbed as [DocxRun.text] is when set.
  DocxParagraph.text(String text)
    : _source = const PropertyContainer.empty(),
      _attributes = const <KeptAttribute>[],
      super._() {
    if (text.isNotEmpty) {
      addRun(text);
    }
  }

  DocxParagraph._read(this._source, this._attributes) : super._();

  /// The paragraph's `w:pPr` as read.
  final PropertyContainer _source;

  /// The paragraph's properties: [_source] with the values set.
  late final _ParagraphProperties _properties = _ParagraphProperties(
    _source,
    () => _sink,
  );

  /// The attributes of `w:p` the reader kept, such as `w14:paraId`.
  final List<KeptAttribute> _attributes;

  final List<DocxInline> _inlines = <DocxInline>[];

  late final List<DocxInline> _inlinesView = UnmodifiableListView<DocxInline>(
    _inlines,
  );

  DocxEditSink _sink = DocxEditSink.none;

  /// The id of the paragraph's style (`w:pStyle`), or `null` for none.
  ///
  /// A `w:pStyle` read from a file that the model does not type (no
  /// `w:val`, an empty one, another `w:` attribute, child elements) reads
  /// `null` and is written back as read until a style is set.
  ///
  /// Setting the empty string, or an id holding a character XML forbids,
  /// throws [ArgumentError]; set `null` to remove the style.
  String? get style => _properties.valueOf('pStyle') as String?;

  set style(String? value) {
    checkStyleId(value);
    _properties.setValue('pStyle', value);
  }

  /// The paragraph's inlines, in order. The list cannot be modified; use
  /// [addRun], [insertInline] and [removeInlineAt].
  List<DocxInline> get inlines => _inlinesView;

  /// The paragraph's visible text: the [DocxInline.text] of each inline, in
  /// order. A run gives its text and an opaque inline the visible text
  /// inside it, so inserted text counts and deleted text does not.
  String get text {
    final StringBuffer out = StringBuffer();
    for (final DocxInline inline in _inlines) {
      out.write(inline.text);
    }
    return out.toString();
  }

  /// Appends a new run that holds [text] and returns it. The text is split
  /// and scrubbed as [DocxRun.text] is when set.
  DocxRun addRun([String text = '']) {
    final DocxRun run = DocxRun(text);
    insertInline(_inlines.length, run);
    return run;
  }

  /// Inserts [inline] at [index], from 0 to the number of inlines.
  ///
  /// An [index] out of that range throws [RangeError]. An [inline] that is
  /// already in a paragraph, this one or another, throws [StateError]:
  /// remove it there first.
  void insertInline(int index, DocxInline inline) {
    RangeError.checkValueInInterval(index, 0, _inlines.length, 'index');
    _checkDetached(inline);
    _inlines.insert(index, inline);
    setParagraphOf(inline, this);
    _sink.inlineInserted(this, index, inline);
  }

  /// Removes the inline at [index].
  ///
  /// An [index] that is not one of an inline throws [RangeError].
  void removeInlineAt(int index) {
    RangeError.checkValidIndex(index, _inlines, 'index');
    final DocxInline removed = _inlines.removeAt(index);
    setParagraphOf(removed, null);
    _sink.inlineRemoved(this, index, removed);
  }

  static void _checkDetached(DocxInline inline) {
    if (paragraphOf(inline) != null) {
      throw StateError('The inline is already in a paragraph.');
    }
  }
}

/// A block the model does not type, kept as written.
final class DocxOpaqueBlock extends DocxBlock {
  DocxOpaqueBlock._(this._xml) : super._();

  final OpaqueXml _xml;

  /// The element's local name, such as `tbl` or `sdt`.
  String get localName => _xml.localName;

  /// The element's namespace URI, or the empty string.
  String get namespaceUri => _xml.namespaceUri;

  @override
  String toString() => 'DocxOpaqueBlock($localName)';
}

/// A paragraph as the reader builds it: its `w:pPr` as read (by
/// [paragraphPropertiesSchema]), the kept attributes of `w:p`, and its
/// inlines as read. Each inline must be in no paragraph, or [StateError] is
/// thrown.
DocxParagraph readParagraph({
  required PropertyContainer properties,
  required List<KeptAttribute> attributes,
  required List<DocxInline> inlines,
}) {
  final DocxParagraph p = DocxParagraph._read(properties, attributes);
  for (final DocxInline inline in inlines) {
    DocxParagraph._checkDetached(inline);
    p._inlines.add(inline);
    setParagraphOf(inline, p);
  }
  return p;
}

/// The `w:pPr` of [paragraph] as read, without the values set since.
PropertyContainer paragraphPropertiesOf(DocxParagraph paragraph) =>
    paragraph._source;

/// The properties of [paragraph], for the writer.
PropertySet paragraphPropertySetOf(DocxParagraph paragraph) =>
    paragraph._properties;

/// The properties of a paragraph until `DocxParagraphProperties` (D2 Task
/// 5) types more than the style.
final class _ParagraphProperties extends PropertySet {
  _ParagraphProperties(PropertyContainer source, DocxEditSink Function() sink)
    : super(source, paragraphPropertiesSchema, sink);
}

/// The attributes of `w:p` the reader kept on [paragraph], in source order.
List<KeptAttribute> paragraphAttributesOf(DocxParagraph paragraph) =>
    paragraph._attributes;

/// The sink [paragraph] and its runs report their edits to.
DocxEditSink editSinkOf(DocxParagraph paragraph) => paragraph._sink;

/// Makes [sink] receive the edits of [paragraph] and its runs from now on;
/// [DocxEditSink.none] detaches it.
void attachEditSink(DocxParagraph paragraph, DocxEditSink sink) {
  paragraph._sink = sink;
}

/// Puts [inline] in place of the inline at [index] of [paragraph], and
/// reports it to the paragraph's sink.
///
/// An [index] that is not one of an inline throws [RangeError], and an
/// [inline] already in a paragraph throws [StateError].
void replaceInlineAt(DocxParagraph paragraph, int index, DocxInline inline) {
  final List<DocxInline> inlines = paragraph._inlines;
  RangeError.checkValidIndex(index, inlines, 'index');
  DocxParagraph._checkDetached(inline);
  final DocxInline previous = inlines[index];
  inlines[index] = inline;
  setParagraphOf(previous, null);
  setParagraphOf(inline, paragraph);
  paragraph._sink.inlineReplaced(paragraph, index, previous, inline);
}

/// The container [block] is in, such as a document's body, or `null`.
Object? blockContainerOf(DocxBlock block) => block._container;

/// Records that [block] is now in [container] (`null`: in none). Only the
/// block primitives call it.
void setBlockContainerOf(DocxBlock block, Object? container) {
  block._container = container;
}

/// An opaque block for the element [xml] captured.
DocxOpaqueBlock opaqueBlock(OpaqueXml xml) => DocxOpaqueBlock._(xml);

/// The element [block] keeps, for the writer.
OpaqueXml opaqueBlockXml(DocxOpaqueBlock block) => block._xml;
