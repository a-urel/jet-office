/// The content of a run, the children of `w:r`: text, tab, break, carriage
/// return, the marks and instruction of a field, and opaque content for
/// everything else.
///
/// Not ported from Quds; written for jet_office.
///
/// The typed kinds are values: two of the same kind with the same text or
/// break type are equal. What a reader keeps of them that the model does not
/// type (the attributes of `w:t`, `w:tab`, `w:br` and `w:cr`, `xml:space`
/// among them) is held beside the value and does not take part in equality.
/// Opaque content keeps its element as written, for the writer, and so do a
/// field's marks and instruction, whose value is what the model reads of it.
///
/// @docImport 'inlines.dart';
library;

import '../../opc/opaque_xml.dart';

/// One child of a run.
sealed class DocxRunContent {
  const DocxRunContent(this._attributes);

  /// The attributes the reader kept, in source order; empty for content
  /// built by the API.
  final List<KeptAttribute> _attributes;
}

/// Text, `w:t`.
final class DocxText extends DocxRunContent {
  /// Text that holds [text] as it is.
  ///
  /// A run builds its own content when its text is set; this constructor is
  /// for comparing a run's content.
  const DocxText(this.text) : _wasRead = false, super(const <KeptAttribute>[]);

  const DocxText._read(this.text, super._attributes) : _wasRead = true;

  /// Whether the text was read from a `w:t`, whose `xml:space` is then
  /// kept as read; text built by the API gets the writer's rule.
  final bool _wasRead;

  /// The text, without the tabs and breaks that are content of their own.
  final String text;

  @override
  bool operator ==(Object other) => other is DocxText && other.text == text;

  @override
  int get hashCode => Object.hash(DocxText, text);

  @override
  String toString() => 'DocxText($text)';
}

/// A tab character, `w:tab`; its text is `\t`.
final class DocxTab extends DocxRunContent {
  /// A tab.
  const DocxTab() : super(const <KeptAttribute>[]);

  const DocxTab._read(super._attributes);

  @override
  bool operator ==(Object other) => other is DocxTab;

  @override
  int get hashCode => (DocxTab).hashCode;

  @override
  String toString() => 'DocxTab()';
}

/// What a [DocxBreak] breaks: the value of `w:br/@w:type`.
enum DocxBreakType {
  /// A line break: `w:type` absent or `textWrapping`. A `w:clear` value of
  /// a `textWrapping` break is kept as read, not typed.
  line,

  /// A page break, `w:type="page"`.
  page,

  /// A column break, `w:type="column"`.
  column,
}

/// A break, `w:br`; its text is `\n` whatever its [type].
final class DocxBreak extends DocxRunContent {
  /// A break of [type], a line break by default.
  const DocxBreak([this.type = DocxBreakType.line])
    : super(const <KeptAttribute>[]);

  const DocxBreak._read(this.type, super._attributes);

  /// What the break breaks.
  final DocxBreakType type;

  @override
  bool operator ==(Object other) => other is DocxBreak && other.type == type;

  @override
  int get hashCode => Object.hash(DocxBreak, type);

  @override
  String toString() => 'DocxBreak(${type.name})';
}

/// A carriage return, `w:cr`; its text is `\n`.
///
/// Setting a run's text never produces one (a `\r` becomes a [DocxBreak]);
/// it comes from a file.
final class DocxCarriageReturn extends DocxRunContent {
  /// A carriage return.
  const DocxCarriageReturn() : super(const <KeptAttribute>[]);

  const DocxCarriageReturn._read(super._attributes);

  @override
  bool operator ==(Object other) => other is DocxCarriageReturn;

  @override
  int get hashCode => (DocxCarriageReturn).hashCode;

  @override
  String toString() => 'DocxCarriageReturn()';
}

/// What a [DocxFieldMark] marks: the value of `w:fldChar/@w:fldCharType`.
enum DocxFieldMarkType {
  /// The start of a field and of its instruction.
  begin,

  /// The end of a field's instruction and the start of its result.
  separate,

  /// The end of a field.
  end,
}

/// A mark of a complex field, `w:fldChar`; it has no text.
///
/// A field that is plain is a [DocxField] and its runs are behind it, so a run
/// that shows a mark in its [DocxRun.content] is one of a field the model
/// left as runs, such as a field across paragraphs. The element is kept as
/// read, `w:fldLock`, `w:dirty` and `w:fldData` among what it holds. A
/// `w:fldChar` of no known type is no mark but [DocxOpaqueRunContent].
final class DocxFieldMark extends DocxRunContent {
  DocxFieldMark._read(this.type, this._xml) : super(const <KeptAttribute>[]);

  final OpaqueXml _xml;

  /// What the mark marks.
  final DocxFieldMarkType type;

  @override
  bool operator ==(Object other) =>
      other is DocxFieldMark && other.type == type;

  @override
  int get hashCode => Object.hash(DocxFieldMark, type);

  @override
  String toString() => 'DocxFieldMark(${type.name})';
}

/// A piece of a field's instruction, `w:instrText`; it has no text of the run.
/// The element is kept as read.
final class DocxFieldInstruction extends DocxRunContent {
  DocxFieldInstruction._read(this.text, this._xml)
    : super(const <KeptAttribute>[]);

  final OpaqueXml _xml;

  /// The instruction text, as decoded from the element.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is DocxFieldInstruction && other.text == text;

  @override
  int get hashCode => Object.hash(DocxFieldInstruction, text);

  @override
  String toString() => 'DocxFieldInstruction($text)';
}

/// Run content the model does not type, such as `w:drawing`,
/// `w:delInstrText`, `w:sym` or `mc:AlternateContent`. It is kept as written
/// and has no text.
final class DocxOpaqueRunContent extends DocxRunContent {
  DocxOpaqueRunContent._(this._xml) : super(const <KeptAttribute>[]);

  final OpaqueXml _xml;

  /// The element's local name, such as `drawing`.
  String get localName => _xml.localName;

  /// The element's namespace URI, or the empty string.
  String get namespaceUri => _xml.namespaceUri;

  @override
  String toString() => 'DocxOpaqueRunContent($localName)';
}

/// Text read from a `w:t` with the attributes the reader kept.
DocxText readText(String text, List<KeptAttribute> attributes) =>
    DocxText._read(text, attributes);

/// A tab read from a `w:tab` with the attributes the reader kept.
DocxTab readTab(List<KeptAttribute> attributes) => DocxTab._read(attributes);

/// A break of [type] read from a `w:br` with the attributes the reader kept
/// (`w:clear` among them; `w:type` is typed and the reader leaves it out).
DocxBreak readBreak(DocxBreakType type, List<KeptAttribute> attributes) =>
    DocxBreak._read(type, attributes);

/// A carriage return read from a `w:cr` with the attributes the reader kept.
DocxCarriageReturn readCarriageReturn(List<KeptAttribute> attributes) =>
    DocxCarriageReturn._read(attributes);

/// A mark of [type] read from the `w:fldChar` [xml] captured.
DocxFieldMark readFieldMark(DocxFieldMarkType type, OpaqueXml xml) =>
    DocxFieldMark._read(type, xml);

/// Instruction [text] read from the `w:instrText` [xml] captured.
DocxFieldInstruction readFieldInstruction(String text, OpaqueXml xml) =>
    DocxFieldInstruction._read(text, xml);

/// The attributes the reader kept on [content], in source order; empty for
/// content built by the API, and for opaque content and a field's marks and
/// instruction, whose elements keep their own.
List<KeptAttribute> contentAttributesOf(DocxRunContent content) =>
    content._attributes;

/// Whether [text] was read from a file (its kept attributes, `xml:space`
/// among them, are then written as read) rather than built when a run's
/// text was set.
bool textWasRead(DocxText text) => text._wasRead;

/// Opaque run content for the element [xml] captured.
DocxOpaqueRunContent opaqueRunContent(OpaqueXml xml) =>
    DocxOpaqueRunContent._(xml);

/// The element [content] keeps, for the writer.
OpaqueXml opaqueRunContentXml(DocxOpaqueRunContent content) => content._xml;

/// The `w:fldChar` [mark] keeps, for the writer.
OpaqueXml fieldMarkXml(DocxFieldMark mark) => mark._xml;

/// The `w:instrText` [instruction] keeps, for the writer.
OpaqueXml fieldInstructionXml(DocxFieldInstruction instruction) =>
    instruction._xml;
