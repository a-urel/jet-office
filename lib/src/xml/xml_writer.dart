/// A compact, streaming XML serializer.
///
/// Ported from quds_office_engine `lib/src/xml/xml_writer.dart` at commit 15c5d29.
/// What changed: the writer takes a required [StringSink] (so a worksheet can
/// stream into a `Utf8Buffer`), the API is shortened to `start`, `attribute`,
/// `text`, `raw`, `end` and `empty`, and text and attribute values go through
/// the scrub-checked escapers. CDATA, comments, processing instructions,
/// namespace helpers, `toXml` and `writeEndDocument` are not ported because
/// nothing uses them.
library;

import 'xml_escape.dart';

/// Writes compact XML (no indentation) to a [StringSink].
///
/// Start tags stay open until content arrives, so an element closed without
/// content is written as `<name/>`.
final class XmlWriter {
  /// Creates a writer that appends to [_sink].
  XmlWriter(this._sink);

  final StringSink _sink;
  final List<String> _open = <String>[];
  bool _inStartTag = false;

  /// Writes `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>`.
  void declaration() {
    _sink.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
  }

  /// Opens the element [name]. Attributes may follow until content is written.
  ///
  /// Names are written as given and must be valid XML names; they are not
  /// validated.
  void start(String name) {
    _closeStartTag();
    _sink
      ..write('<')
      ..write(name);
    _open.add(name);
    _inStartTag = true;
  }

  /// Writes the attribute [name]="[value]" on the open start tag.
  ///
  /// [name] must be a valid XML name (it is not validated). The value is
  /// escaped before anything is written, so a throw leaves no partial output.
  /// [value] must already be scrubbed with `scrubXmlText`; otherwise this
  /// throws [ArgumentError]. Throws [StateError] when no start tag is open,
  /// that is, when nothing was started or content was already written.
  void attribute(String name, String value) {
    if (!_inStartTag) {
      throw StateError('Attributes can only be written on an open start tag.');
    }
    _writeAttribute(name, escapeXmlAttribute(value));
  }

  void _writeAttribute(String name, String escaped) {
    _sink
      ..write(' ')
      ..write(name)
      ..write('="')
      ..write(escaped)
      ..write('"');
  }

  /// Writes [text] as escaped character data inside the open element.
  ///
  /// [text] must already be scrubbed with `scrubXmlText`; otherwise this
  /// throws [ArgumentError].
  void text(String text) {
    final String escaped = escapeXmlText(text);
    _closeStartTag();
    _sink.write(escaped);
  }

  /// Writes [xml] as it is, after closing an open start tag. The caller is
  /// responsible for [xml] being well-formed and escaped.
  void raw(String xml) {
    _closeStartTag();
    _sink.write(xml);
  }

  /// Closes the innermost open element, as `<name/>` when it has no content.
  ///
  /// Throws [StateError] when no element is open.
  void end() {
    if (_open.isEmpty) {
      throw StateError('No open element to close.');
    }
    final String name = _open.removeLast();
    if (_inStartTag) {
      _sink.write('/>');
      _inStartTag = false;
    } else {
      _sink
        ..write('</')
        ..write(name)
        ..write('>');
    }
  }

  /// Writes the element [name] with [attributes] and no content.
  ///
  /// Every attribute value is escaped before anything is written, so a throw
  /// leaves no partial output. Names must be valid XML names (not validated).
  void empty(String name, [Map<String, String> attributes = const {}]) {
    final List<String> escaped = <String>[
      for (final String value in attributes.values) escapeXmlAttribute(value),
    ];
    start(name);
    int i = 0;
    for (final String key in attributes.keys) {
      _writeAttribute(key, escaped[i++]);
    }
    end();
  }

  void _closeStartTag() {
    if (_inStartTag) {
      _sink.write('>');
      _inStartTag = false;
    }
  }
}
