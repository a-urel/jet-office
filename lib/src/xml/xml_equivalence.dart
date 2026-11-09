/// XML equality as the chart layer defines it (C1, ruling R2).
///
/// Not ported from Quds; written for jet_office.
library;

import 'dart:typed_data';

import 'xml_pull_reader.dart';

/// Compares two XML documents and returns `null` when they are equal, or one
/// line naming the first difference with its element path, for example
/// `/chartSpace/chart/plotArea/barChart/gapWidth: attribute val 219 vs 150`.
///
/// Equal means: the same elements in the same order, each with the same
/// namespace URI and local name, the same attributes (as a set, keyed by
/// namespace URI and local name) with the same values, and the same text.
/// Ignored are the XML declaration, namespace declarations (`xmlns` and
/// `xmlns:*`) and prefixes, comments, processing instructions and
/// whitespace-only text. Other text is compared exactly; a CDATA section
/// counts as text.
///
/// Never throws. Input that cannot be read, or nests deeper than the reader's
/// limit, is a difference: `a: unreadable: <message>` for the first document
/// and `b: unreadable: <message>` for the second.
String? xmlDifference(Uint8List a, Uint8List b) {
  final _Tokens left;
  final _Tokens right;
  try {
    left = _Tokens(XmlPullReader.fromBytes(a));
  } on Object catch (e) {
    return 'a: unreadable: ${_message(e)}';
  }
  try {
    right = _Tokens(XmlPullReader.fromBytes(b));
  } on Object catch (e) {
    return 'b: unreadable: ${_message(e)}';
  }
  final List<String> path = <String>[];
  while (true) {
    final _Token x;
    final _Token y;
    try {
      x = left.next();
    } on Object catch (e) {
      return 'a: unreadable: ${_message(e)}';
    }
    try {
      y = right.next();
    } on Object catch (e) {
      return 'b: unreadable: ${_message(e)}';
    }
    final String where = '/${path.join('/')}';
    if (x.kind == _Kind.end && y.kind == _Kind.end && path.isEmpty) {
      return null;
    }
    if (x.kind != y.kind) {
      return '$where: ${_describe(x)} vs ${_describe(y)}';
    }
    switch (x.kind) {
      case _Kind.start:
        if (x.uri != y.uri || x.name != y.name) {
          return '$where: element ${_clark(x.uri, x.name)} vs '
              '${_clark(y.uri, y.name)}';
        }
        path.add(x.name);
        final String here = '/${path.join('/')}';
        for (final MapEntry<String, String> e in x.attributes.entries) {
          final String? other = y.attributes[e.key];
          if (other == null) {
            return '$here: attribute ${e.key} ${e.value} vs (missing)';
          }
          if (other != e.value) {
            return '$here: attribute ${e.key} ${e.value} vs $other';
          }
        }
        for (final String key in y.attributes.keys) {
          if (!x.attributes.containsKey(key)) {
            return '$here: attribute $key (missing) vs ${y.attributes[key]}';
          }
        }
      case _Kind.text:
        if (x.text != y.text) {
          return '$where: text "${_excerpt(x.text)}" vs '
              '"${_excerpt(y.text)}"';
        }
      case _Kind.end:
        if (path.isEmpty) {
          return null;
        }
        path.removeLast();
    }
  }
}

String _message(Object e) => switch (e) {
  XmlParseException() => e.message,
  FormatException() => e.message,
  _ => '$e',
};

String _clark(String uri, String name) => uri.isEmpty ? name : '{$uri}$name';

String _excerpt(String s) => s.length > 40 ? '${s.substring(0, 40)}…' : s;

String _describe(_Token t) => switch (t.kind) {
  _Kind.start => 'element ${_clark(t.uri, t.name)}',
  _Kind.end => 'end of element',
  _Kind.text => 'text "${_excerpt(t.text)}"',
};

enum _Kind { start, end, text }

final class _Token {
  const _Token.start(this.uri, this.name, this.attributes)
    : kind = _Kind.start,
      text = '';

  const _Token.end()
    : kind = _Kind.end,
      uri = '',
      name = '',
      attributes = const <String, String>{},
      text = '';

  const _Token.text(this.text)
    : kind = _Kind.text,
      uri = '',
      name = '',
      attributes = const <String, String>{};

  final _Kind kind;
  final String uri;
  final String name;

  /// Attribute values keyed by `{uri}local` (just `local` with no namespace).
  final Map<String, String> attributes;
  final String text;
}

/// The significant events of one document: elements, and text with adjacent
/// character data and CDATA merged and whitespace-only runs dropped. The end
/// of the document is an end token.
final class _Tokens {
  _Tokens(this._reader);

  final XmlPullReader _reader;
  _Token? _pending;
  bool _done = false;
  bool _sawElement = false;

  _Token next() {
    final _Token? p = _pending;
    if (p != null) {
      _pending = null;
      return p;
    }
    if (_done) {
      return const _Token.end();
    }
    StringBuffer? text;
    bool allSpace = true;
    while (_reader.next()) {
      switch (_reader.eventType) {
        case XmlEventType.characters:
        case XmlEventType.cdata:
          (text ??= StringBuffer()).write(_reader.text);
          if (_reader.eventType == XmlEventType.cdata ||
              !_reader.isWhitespace) {
            allSpace = false;
          }
        case XmlEventType.startElement:
          final _Token t = _start();
          return _flush(text, allSpace, t);
        case XmlEventType.endElement:
          return _flush(text, allSpace, const _Token.end());
        case XmlEventType.endDocument:
          if (!_sawElement) {
            throw const FormatException('no root element');
          }
          _done = true;
          return _flush(text, allSpace, const _Token.end());
        case XmlEventType.none:
        case XmlEventType.xmlDeclaration:
        case XmlEventType.processingInstruction:
        case XmlEventType.comment:
          break;
      }
    }
    if (!_sawElement) {
      throw const FormatException('no root element');
    }
    _done = true;
    return _flush(text, allSpace, const _Token.end());
  }

  _Token _flush(StringBuffer? text, bool allSpace, _Token then) {
    if (text == null || allSpace) {
      return then;
    }
    _pending = then;
    return _Token.text(text.toString());
  }

  _Token _start() {
    _sawElement = true;
    final Map<String, String> attributes = <String, String>{};
    for (int i = 0; i < _reader.attributeCount; i++) {
      final String qualified = _reader.attributeQualifiedName(i);
      if (qualified == 'xmlns' || _reader.attributePrefix(i) == 'xmlns') {
        continue;
      }
      final String uri = _reader.attributeNamespace(i);
      final String local = _reader.attributeLocalName(i);
      attributes[uri.isEmpty ? local : '{$uri}$local'] = _reader.attributeValue(
        i,
      );
    }
    return _Token.start(_reader.namespaceUri, _reader.localName, attributes);
  }
}
