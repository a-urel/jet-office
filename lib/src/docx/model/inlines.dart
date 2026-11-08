/// The inlines of a paragraph, the children of `w:p`: runs, complex fields
/// (`fields.dart`), bookmark marks (`bookmarks.dart`), and opaque inlines for
/// everything else.
///
/// Not ported from Quds; written for jet_office.
///
/// A [DocxRun] holds its content ([DocxRunContent]) and its properties
/// (`w:rPr`, a [PropertySet]), of which D1 types only the style. Setting
/// its text splits the string into text, tabs and breaks and removes the
/// characters XML forbids; the run records how many it removed, and the
/// save reports them.
///
/// A [DocxOpaqueInline] keeps an element the model does not type, such as a
/// tracked change (`w:ins`, `w:del`), a content control or a hyperlink until
/// D5, and carries its visible text ([VisibleTextCollector]), computed once
/// when it is built.
///
/// The top-level functions are the model's internal surface for the reader,
/// the writer and the document; none of them is exported.
library;

import 'dart:collection';

import '../../opc/change_log.dart' show Change;
import '../../opc/ooxml.dart' show Ns;
import '../../opc/opaque_xml.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import '../properties.dart';
import 'blocks.dart';
import 'edit_sink.dart';
import 'property_set.dart';
import 'run_content.dart';
import 'run_properties.dart';

part 'bookmarks.dart';
part 'fields.dart';

/// One child of a paragraph, or an inline of a [DocxField].
sealed class DocxInline {
  DocxInline._();

  /// The paragraph the inline is in, or `null` while it is in none. An
  /// inline of a field is in the paragraph of the field.
  DocxParagraph? _paragraph;

  /// The field that holds the inline, or `null`.
  DocxField? _field;

  /// The text the inline shows: the run's text, the visible text inside an
  /// opaque inline, or a field's result.
  String get text;
}

/// A run's content and the number of characters removed from the text that
/// produced it, as `runTextOf` returns and `restoreRunText` takes.
typedef DocxRunText = ({List<DocxRunContent> content, int removed});

/// A run of text with one set of properties, `w:r`.
final class DocxRun extends DocxInline {
  /// A new run that holds [text], split and scrubbed as [text] is when set.
  ///
  /// It belongs to no paragraph until it is inserted into one.
  DocxRun([String text = ''])
    : _source = const PropertyContainer.empty(),
      _attributes = const <KeptAttribute>[],
      super._() {
    _setText(text);
  }

  DocxRun._read(this._source, this._attributes, List<DocxRunContent> content)
    : super._() {
    _content.addAll(content);
  }

  /// The run's `w:rPr` as read.
  final PropertyContainer _source;

  /// The run's properties: [_source] with the values set.
  late final DocxRunProperties _properties = newRunProperties(
    _source,
    () => _sink,
  );

  /// The attributes of `w:r` the reader kept, such as `w:rsidR`.
  final List<KeptAttribute> _attributes;

  final List<DocxRunContent> _content = <DocxRunContent>[];

  late final List<DocxRunContent> _contentView =
      UnmodifiableListView<DocxRunContent>(_content);

  /// How many characters XML forbids were removed when the text was set.
  int _removed = 0;

  /// The sink of the document the run was read in; `null` for a new run.
  DocxEditSink? _readIn;

  DocxEditSink get _sink {
    final DocxParagraph? paragraph = _paragraph;
    return paragraph == null ? DocxEditSink.none : editSinkOf(paragraph);
  }

  /// The run's formatting (`w:rPr`). It is the same object every time; a
  /// new run has none set.
  DocxRunProperties get properties => _properties;

  /// The id of the run's character style (`w:rStyle`), or `null` for none.
  /// A shortcut for [DocxRunProperties.style] of [properties], which has
  /// the rules: the id set may read back as the document's own, and a set
  /// on a run of a document throws a `DocxReadException` when its styles
  /// part cannot be read.
  String? get style => _properties.style;

  set style(String? value) => _properties.style = value;

  /// The run's content, in order. The list cannot be modified; set [text]
  /// to change it.
  List<DocxRunContent> get content => _contentView;

  /// The run's text: each [DocxText] as it is, `\t` for a [DocxTab], `\n`
  /// for a [DocxBreak] of any type and for a [DocxCarriageReturn], and
  /// nothing for opaque content.
  ///
  /// Setting it replaces the whole content: `\t` becomes a [DocxTab], and
  /// `\n`, `\r\n` and a lone `\r` each become one line [DocxBreak]. Whatever
  /// else the run held is removed with it: opaque content (drawings, note
  /// and comment references, `mc:AlternateContent`), the marks and instruction
  /// of a field ([DocxFieldMark], [DocxFieldInstruction]) and carriage returns
  /// ([DocxCarriageReturn]) are gone, so set the text of a run that holds
  /// only text. Characters XML forbids (control characters other than tab,
  /// LF and CR, U+FFFE, U+FFFF and lone surrogates) are removed; the save
  /// reports how many with `DocxWarningCode.invalidCharactersRemoved` at the
  /// run's location.
  ///
  /// Setting a text that gives the content the run already has, with the
  /// same number of removed characters, changes nothing: the content as
  /// read is kept, and no edit is recorded.
  @override
  String get text {
    final StringBuffer out = StringBuffer();
    for (final DocxRunContent c in _content) {
      out.write(_textOf(c));
    }
    return out.toString();
  }

  set text(String value) {
    final ScrubResult scrubbed = scrubXmlText(value);
    final List<DocxRunContent> next = _split(scrubbed.text);
    if (scrubbed.removed == _removed && _sameContent(next)) {
      return;
    }
    final DocxRunText previous = runTextOf(this);
    _apply(next, scrubbed.removed);
    _sink.runTextSet(this, previous);
  }

  void _setText(String value) {
    final ScrubResult scrubbed = scrubXmlText(value);
    _apply(_split(scrubbed.text), scrubbed.removed);
  }

  void _apply(List<DocxRunContent> content, int removed) {
    _removed = removed;
    _content
      ..clear()
      ..addAll(content);
  }

  /// Whether [other] equals the run's content, kind by kind. Opaque content
  /// is equal only to itself, so a run holding any is never the same as
  /// split text.
  bool _sameContent(List<DocxRunContent> other) {
    if (other.length != _content.length) {
      return false;
    }
    for (int i = 0; i < other.length; i++) {
      if (other[i] != _content[i]) {
        return false;
      }
    }
    return true;
  }
}

/// An inline the model does not type, kept as written.
final class DocxOpaqueInline extends DocxInline {
  DocxOpaqueInline._(this._xml, this.text, this._holdsRuns, this._breaksFields)
    : super._();

  final OpaqueXml _xml;

  /// Whether a run or a `w:fldSimple` is inside the element, which can then
  /// not sit in the instruction of a field.
  final bool _holdsRuns;

  /// Whether the field marks inside the element do not pair among themselves,
  /// so some of them belong to a field around it.
  final bool _breaksFields;

  /// The element's local name, such as `ins` or `proofErr`.
  String get localName => _xml.localName;

  /// The element's namespace URI, or the empty string.
  String get namespaceUri => _xml.namespaceUri;

  /// The visible text inside the element: inserted and moved-in text counts,
  /// deleted and moved-away text does not ([VisibleTextCollector] has the
  /// rule).
  @override
  final String text;

  @override
  String toString() => 'DocxOpaqueInline($localName)';
}

/// The text of one piece of run content.
String _textOf(DocxRunContent content) => switch (content) {
  DocxText(:final String text) => text,
  DocxTab() => '\t',
  DocxBreak() || DocxCarriageReturn() => '\n',
  DocxFieldMark() || DocxFieldInstruction() || DocxOpaqueRunContent() => '',
};

/// Splits [text] into text, tabs and line breaks; `\r\n` is one break.
List<DocxRunContent> _split(String text) {
  final List<DocxRunContent> out = <DocxRunContent>[];
  int start = 0;
  void flush(int end) {
    if (end > start) {
      out.add(DocxText(text.substring(start, end)));
    }
  }

  for (int i = 0; i < text.length; i++) {
    final int c = text.codeUnitAt(i);
    if (c == 0x09) {
      flush(i);
      out.add(const DocxTab());
      start = i + 1;
    } else if (c == 0x0A || c == 0x0D) {
      flush(i);
      out.add(const DocxBreak());
      if (c == 0x0D && i + 1 < text.length && text.codeUnitAt(i + 1) == 0x0A) {
        i++;
      }
      start = i + 1;
    }
  }
  flush(text.length);
  return out;
}

/// A run as the reader builds it: its `w:rPr` as read (by
/// `runPropertiesSchema`), the kept attributes of `w:r`, and its content as
/// read.
DocxRun readRun({
  required PropertyContainer properties,
  required List<KeptAttribute> attributes,
  required List<DocxRunContent> content,
}) => DocxRun._read(properties, attributes, content);

/// The `w:rPr` of [run] as read, without the values set since.
PropertyContainer runPropertiesOf(DocxRun run) => run._source;

/// The properties of [run], for the writer.
PropertySet runPropertySetOf(DocxRun run) =>
    propertySetOfRunProperties(run._properties);

/// The sink of the document [run] was read in, or `null` for a new run.
DocxEditSink? runReadInOf(DocxRun run) => run._readIn;

/// Records that [run] was read in the document of [sink].
void setRunReadIn(DocxRun run, DocxEditSink sink) {
  run._readIn = sink;
}

/// The attributes of `w:r` the reader kept on [run], in source order.
List<KeptAttribute> runAttributesOf(DocxRun run) => run._attributes;

/// How many characters XML forbids were removed when [run]'s text was last
/// set; 0 for a run whose text was never set.
int removedCharactersOf(DocxRun run) => run._removed;

/// A copy of [run]'s content with its removed count, for `restoreRunText`.
DocxRunText runTextOf(DocxRun run) => (
  content: List<DocxRunContent>.unmodifiable(run._content),
  removed: run._removed,
);

/// Puts [state] back as [run]'s content and removed count, without calling
/// any sink: how a recorded text edit is undone or redone.
void restoreRunText(DocxRun run, DocxRunText state) {
  run._content
    ..clear()
    ..addAll(state.content);
  run._removed = state.removed;
}

/// The paragraph [inline] is in, or `null`.
DocxParagraph? paragraphOf(DocxInline inline) => inline._paragraph;

/// Records that [inline], and every inline of it if it is a field, is now in
/// [paragraph] (`null`: in none). Only the paragraph's own edits call it.
void setParagraphOf(DocxInline inline, DocxParagraph? paragraph) {
  inline._paragraph = paragraph;
  if (inline is DocxField) {
    for (final DocxInline held in inline._inlines) {
      setParagraphOf(held, paragraph);
    }
  }
}

/// An opaque inline for the element [xml] captured.
///
/// [text] is its visible text, when the reader computed it while capturing;
/// without it, [visibleText] computes it from [xml]. [holdsRuns] says that a
/// run or a `w:fldSimple` is inside it, and [breaksFields] that the field
/// marks inside it do not pair among themselves.
DocxOpaqueInline opaqueInline(
  OpaqueXml xml, {
  String? text,
  bool holdsRuns = false,
  bool breaksFields = false,
}) =>
    DocxOpaqueInline._(xml, text ?? visibleText(xml), holdsRuns, breaksFields);

/// The element [inline] keeps, for the writer.
OpaqueXml opaqueInlineXml(DocxOpaqueInline inline) => inline._xml;

/// The local names, in WordprocessingML, of the containers whose runs are
/// visible text.
const Set<String> _visibleContainers = <String>{
  'ins',
  'moveTo',
  'hyperlink',
  'smartTag',
  'customXml',
  'fldSimple',
  'dir',
  'bdo',
  'sdtContent',
};

/// The text the inline element [node] shows, as a paragraph's text counts
/// it ([VisibleTextCollector] has the rule).
///
/// It parses [node]'s slice again, nested at most [maxDepth] deep; the
/// reader instead collects the text while it captures the element. Throws
/// an [XmlParseException] for an entity in a `w:t` that cannot be decoded.
String visibleText(OpaqueXml node, {int maxDepth = 256}) {
  // A root that declares the bindings the slice inherited, so its prefixes
  // resolve as they did in the document.
  final StringBuffer source = StringBuffer('<r');
  node.inheritedNamespaces.forEach((String prefix, String uri) {
    source
      ..write(prefix.isEmpty ? ' xmlns="' : ' xmlns:$prefix="')
      ..write(escapeXmlAttribute(scrubXmlText(uri).text))
      ..write('"');
  });
  source
    ..write('>')
    ..write(node.xml)
    ..write('</r>');
  final XmlPullReader r = XmlPullReader(
    source.toString(),
    maxDepth: maxDepth + 1,
  );
  r.nextTag();
  r.nextTag();
  final VisibleTextCollector collector = VisibleTextCollector();
  OpaqueXml.capture(r, onEvent: collector.add);
  return collector.text;
}

/// What an open element of a slice contributes to its visible text.
enum _Visible {
  /// A container whose runs are visible: `w:ins`, `w:hyperlink` and the
  /// others of [_visibleContainers], or the slice itself.
  container,

  /// A `w:sdt`: only its `w:sdtContent` is visible.
  sdt,

  /// A `w:r`.
  run,

  /// A `w:t` in a run: its character data is the text.
  text,

  /// Anything else: nothing inside it is visible.
  hidden,
}

/// Collects the visible text of an inline element from the events of its
/// capture: pass [add] as `onEvent` to `OpaqueXml.capture`.
///
/// Runs (`w:r`) give their `w:t` text, `\t` for `w:tab`, and `\n` for
/// `w:br` and `w:cr`; nothing else in a run is text (`w:delText`,
/// `w:delInstrText`, `w:instrText`, drawings and other content give `''`).
/// Inserted and moved-in text counts: `w:ins`, `w:moveTo`, `w:hyperlink`,
/// `w:smartTag`, `w:customXml`, `w:fldSimple`, `w:dir` and `w:bdo` give the
/// text of their children in order, recursively, and `w:sdt` gives that of
/// its `w:sdtContent` only, never the placeholders of `w:sdtPr`. Deleted and
/// moved-away text does not: `w:del` and `w:moveFrom` give `''` wherever
/// they are nested, so a `w:del` inside a `w:ins` is deleted. Any other
/// element, or one in another namespace, gives `''`. Elements are matched by
/// namespace and local name, never by prefix.
final class VisibleTextCollector {
  final StringBuffer _out = StringBuffer();

  /// What each open element contributes, innermost last.
  final List<_Visible> _open = <_Visible>[];

  /// The visible text collected so far.
  String get text => _out.toString();

  /// The length of [text], without building it.
  int get length => _out.length;

  /// Takes the event [r] is on. Throws an [XmlParseException] for character
  /// data in a `w:t` holding an entity that cannot be decoded.
  void add(XmlPullReader r) {
    switch (r.eventType) {
      case XmlEventType.startElement:
        _open.add(_kindOf(r, _open.isEmpty ? _Visible.container : _open.last));
      case XmlEventType.endElement:
        if (_open.isNotEmpty) _open.removeLast();
      case XmlEventType.characters || XmlEventType.cdata:
        if (_open.isNotEmpty && _open.last == _Visible.text) {
          _out.write(r.text);
        }
      default:
        break;
    }
  }

  /// What the element [r] starts contributes inside a [parent], writing
  /// the text of a tab or break at once.
  _Visible _kindOf(XmlPullReader r, _Visible parent) {
    if (parent == _Visible.hidden ||
        parent == _Visible.text ||
        r.namespaceUri != Ns.w) {
      return _Visible.hidden;
    }
    final String name = r.localName;
    switch (parent) {
      case _Visible.container:
        if (name == 'r') return _Visible.run;
        if (name == 'sdt') return _Visible.sdt;
        return _visibleContainers.contains(name)
            ? _Visible.container
            : _Visible.hidden;
      case _Visible.sdt:
        return name == 'sdtContent' ? _Visible.container : _Visible.hidden;
      case _Visible.run:
        switch (name) {
          case 't':
            return _Visible.text;
          case 'tab':
            _out.write('\t');
          case 'br' || 'cr':
            _out.write('\n');
        }
        return _Visible.hidden;
      case _Visible.text || _Visible.hidden:
        return _Visible.hidden;
    }
  }
}
