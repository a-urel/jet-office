/// A low-allocation XML pull parser, hardened for untrusted input.
///
/// Ported from quds_office_engine `lib/src/xml/xml_reader.dart` at commit
/// 15c5d29: `XmlPullReader`, `XmlEventType`, `XmlParseException` and
/// `decodeXmlEntities`. The writer-side `encodeXmlText` and
/// `encodeXmlAttribute` are not ported.
///
/// What changed, because the input is a user-uploaded file:
///
/// * A `<!DOCTYPE` throws [XmlParseKind.doctype], so no entity or external
///   subset is ever read. There is no `dtd` event.
/// * An element deeper than `maxDepth` throws [XmlParseKind.tooDeep].
/// * [XmlPullReader.fromBytes] refuses UTF-16 and any declared encoding other
///   than UTF-8 and reports invalid UTF-8, all as [XmlParseKind.encoding].
/// * Entity decoding is strict: an unknown entity, a malformed numeric
///   reference, `&#0;`, a surrogate or a code point above U+10FFFF throws
///   [XmlParseKind.malformed].
/// * Truncated documents (an unterminated tag or attribute, or an element
///   still open at the end) throw instead of being cut short silently.
/// * Every failure is an [XmlParseException]; no `RangeError` or
///   `FormatException` escapes on any input.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Event kinds emitted by [XmlPullReader].
enum XmlEventType {
  /// Before the first call to [XmlPullReader.next].
  none,

  /// The `<?xml ... ?>` declaration.
  xmlDeclaration,

  /// Any other processing instruction.
  processingInstruction,

  /// A `<!-- ... -->` comment.
  comment,

  /// An opening tag, or the opening half of an empty element.
  startElement,

  /// A closing tag, or the closing half of an empty element.
  endElement,

  /// Character data between tags.
  characters,

  /// A `<![CDATA[ ... ]]>` section.
  cdata,

  /// The end of the source; [XmlPullReader.next] returns `false` after it.
  endDocument,
}

/// Why an [XmlParseException] was thrown.
enum XmlParseKind {
  /// The XML is not well-formed, or a reference cannot be decoded.
  malformed,

  /// The document has a `<!DOCTYPE`, which is never accepted.
  doctype,

  /// Elements are nested deeper than the reader's `maxDepth`.
  tooDeep,

  /// The bytes are not UTF-8 (UTF-16, another declared encoding, or invalid
  /// UTF-8).
  encoding,
}

/// Thrown by [XmlPullReader] and [decodeXmlEntities] on any input problem.
///
/// It is the only exception those two throw on any input.
final class XmlParseException implements Exception {
  /// Creates an exception for [message] at [offset] in the source.
  const XmlParseException(
    this.message,
    this.offset, {
    this.kind = XmlParseKind.malformed,
  });

  /// What went wrong.
  final String message;

  /// The UTF-16 offset in the source where it went wrong.
  final int offset;

  /// The category of the failure.
  final XmlParseKind kind;

  @override
  String toString() => 'XmlParseException: $message (at $offset)';
}

/// Low-allocation XML 1.0 pull parser.
///
/// The reader walks the source with integer indexes and only allocates
/// [String] values when a property is read. Namespace prefixes are resolved
/// against a stack of `xmlns` declarations. Entities in attribute values are
/// checked when the tag is read; those in character data when [text] is read.
final class XmlPullReader {
  /// Reads [source]. A leading BOM is skipped.
  ///
  /// An element nested deeper than [maxDepth] (the root is depth 1) throws
  /// [XmlParseKind.tooDeep].
  XmlPullReader(String source, {int maxDepth = 256})
    : _source = _stripBom(source),
      _maxDepth = maxDepth;

  /// Decodes UTF-8 [bytes] and reads them.
  ///
  /// A UTF-8 BOM is skipped. A UTF-16 BOM, an XML declaration naming an
  /// encoding other than UTF-8 (in any case) and invalid UTF-8 all throw
  /// [XmlParseKind.encoding].
  factory XmlPullReader.fromBytes(Uint8List bytes, {int maxDepth = 256}) {
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xFE && bytes[1] == 0xFF) ||
            (bytes[0] == 0xFF && bytes[1] == 0xFE))) {
      throw const XmlParseException(
        'UTF-16 is not supported, only UTF-8',
        0,
        kind: XmlParseKind.encoding,
      );
    }
    final String source;
    try {
      source = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const XmlParseException(
        'Invalid UTF-8',
        0,
        kind: XmlParseKind.encoding,
      );
    }
    final String declared = _declaredEncoding(_stripBom(source));
    if (declared.isNotEmpty && declared.toUpperCase() != 'UTF-8') {
      throw XmlParseException(
        'Unsupported encoding "$declared", only UTF-8',
        0,
        kind: XmlParseKind.encoding,
      );
    }
    return XmlPullReader(source, maxDepth: maxDepth);
  }

  final String _source;
  final int _maxDepth;
  int _pos = 0;

  XmlEventType _type = XmlEventType.none;
  int _depth = 0;
  bool _emptyElement = false;
  bool _documentEnded = false;

  int _nameStart = 0;
  int _nameEnd = 0;
  int _localStart = 0;
  int _localEnd = 0;
  int _prefixStart = 0;
  int _prefixEnd = 0;
  int _textStart = 0;
  int _textEnd = 0;
  bool _textHasEntities = false;

  final List<_NsScope> _nsStack = <_NsScope>[_NsScope.root()];
  final List<_AttrSlice> _attrs = <_AttrSlice>[];
  final List<String> _elementStack = <String>[];

  /// The kind of the current event.
  XmlEventType get eventType => _type;

  /// The element nesting depth: 1 at the root element's start tag.
  ///
  /// On an end event it is the depth of the parent.
  int get depth => _depth;

  /// Whether the current start element is written `<x/>`.
  bool get isEmptyElement =>
      _emptyElement && _type == XmlEventType.startElement;

  /// Whether the current event is character data of XML whitespace only.
  bool get isWhitespace {
    if (_type != XmlEventType.characters) {
      return false;
    }
    for (int i = _textStart; i < _textEnd; i++) {
      if (!_isXmlSpace(_source.codeUnitAt(i))) {
        return false;
      }
    }
    return true;
  }

  /// The element name as written, with its prefix.
  String get qualifiedName => _slice(_nameStart, _nameEnd);

  /// The element name without its prefix.
  String get localName => _slice(_localStart, _localEnd);

  /// The element's namespace prefix, or the empty string.
  String get prefix =>
      _prefixEnd > _prefixStart ? _slice(_prefixStart, _prefixEnd) : '';

  /// The namespace URI of the current element, or the empty string when it
  /// has none or the event is not an element event.
  String get namespaceUri {
    if (_type != XmlEventType.startElement &&
        _type != XmlEventType.endElement) {
      return '';
    }
    return _resolvePrefix(prefix);
  }

  /// The text of the current event: character data (entities decoded),
  /// CDATA, a comment, a processing instruction or a declaration. Empty for
  /// other events.
  ///
  /// Throws [XmlParseException] when character data holds an entity that
  /// cannot be decoded.
  String get text {
    if (_type == XmlEventType.characters || _type == XmlEventType.cdata) {
      if (_textHasEntities && _type == XmlEventType.characters) {
        return decodeXmlEntities(
          _source.substring(_textStart, _textEnd),
          offset: _textStart,
        );
      }
      return _source.substring(_textStart, _textEnd);
    }
    if (_type == XmlEventType.comment ||
        _type == XmlEventType.processingInstruction ||
        _type == XmlEventType.xmlDeclaration) {
      return _source.substring(_textStart, _textEnd);
    }
    return '';
  }

  /// The number of attributes of the current start element.
  int get attributeCount => _attrs.length;

  /// Advances to the next event.
  ///
  /// Returns `false` once [XmlEventType.endDocument] has been returned. Throws
  /// [XmlParseException] on malformed input, including a document that ends
  /// inside a tag or with an element still open.
  bool next() {
    if (_documentEnded) {
      return false;
    }
    if (_emptyElement) {
      _emptyElement = false;
      _type = XmlEventType.endElement;
      if (_elementStack.isNotEmpty) {
        _elementStack.removeLast();
      }
      _depth = _elementStack.length;
      if (_nsStack.length > 1) {
        _nsStack.removeLast();
      }
      return true;
    }

    _attrs.clear();
    _emptyElement = false;
    _textHasEntities = false;
    _nameStart = _nameEnd = _localStart = _localEnd = 0;
    _prefixStart = _prefixEnd = 0;
    _textStart = _textEnd = 0;

    if (_pos >= _source.length) {
      if (_elementStack.isNotEmpty) {
        throw XmlParseException(
          'Unclosed element <${_elementStack.last}>',
          _pos,
        );
      }
      _type = XmlEventType.endDocument;
      _documentEnded = true;
      return true;
    }

    final int ch = _source.codeUnitAt(_pos);
    if (ch == _lt) {
      _pos++;
      if (_pos >= _source.length) {
        throw XmlParseException('Unterminated tag', _pos);
      }
      final int nextCh = _source.codeUnitAt(_pos);
      if (nextCh == _slash) {
        _readEndElement();
      } else if (nextCh == _bang) {
        _readBang();
      } else if (nextCh == _quest) {
        _readPiOrDeclaration();
      } else {
        _readStartElement();
      }
      return true;
    }

    _readText();
    return true;
  }

  /// Advances to the next event that is not whitespace-only character data
  /// or a comment.
  ///
  /// Returns `false` at the end of the document.
  bool nextTag() {
    while (next()) {
      if (_type == XmlEventType.characters && isWhitespace) {
        continue;
      }
      if (_type == XmlEventType.comment) {
        continue;
      }
      return _type != XmlEventType.endDocument;
    }
    return false;
  }

  /// Skips the current start element and all of its descendants, stopping at
  /// its end event. Does nothing when the current event is not a start
  /// element.
  void skip() {
    if (_type != XmlEventType.startElement) {
      return;
    }
    if (isEmptyElement) {
      next();
      return;
    }
    final int startDepth = _depth;
    while (next()) {
      if (_type == XmlEventType.endElement && _depth < startDepth) {
        return;
      }
      if (_type == XmlEventType.endDocument) {
        return;
      }
    }
  }

  /// The qualified name of attribute [index], which must be below
  /// [attributeCount].
  String attributeQualifiedName(int index) => _attrs[index].qualified(_source);

  /// The local name of attribute [index], which must be below
  /// [attributeCount].
  String attributeLocalName(int index) => _attrs[index].local(_source);

  /// The namespace prefix of attribute [index], or the empty string.
  String attributePrefix(int index) => _attrs[index].prefix(_source);

  /// The decoded value of attribute [index], which must be below
  /// [attributeCount].
  String attributeValue(int index) => _attrs[index].decodedValue(_source);

  /// The namespace URI of attribute [index]; empty for an unprefixed
  /// attribute and for `xmlns` declarations.
  String attributeNamespace(int index) {
    final _AttrSlice attr = _attrs[index];
    if (attr.isXmlns) {
      return '';
    }
    final String pfx = attr.prefix(_source);
    if (pfx.isEmpty) {
      return '';
    }
    return _resolvePrefix(pfx);
  }

  /// The decoded value of the first attribute of the current start element
  /// named [localName], or `null`.
  ///
  /// With [namespaceUri] only an attribute in that namespace matches (the
  /// empty string matches an unprefixed one). Without it the prefix is
  /// ignored.
  String? getAttribute(String localName, {String? namespaceUri}) {
    for (int i = 0; i < _attrs.length; i++) {
      final _AttrSlice attr = _attrs[i];
      if (attr.local(_source) != localName) {
        continue;
      }
      if (namespaceUri == null) {
        return attr.decodedValue(_source);
      }
      if (attributeNamespace(i) == namespaceUri) {
        return attr.decodedValue(_source);
      }
    }
    return null;
  }

  /// The attributes of the current start element, qualified name to decoded
  /// value.
  Map<String, String> attributesAsMap() {
    final Map<String, String> map = <String, String>{};
    for (int i = 0; i < _attrs.length; i++) {
      map[attributeQualifiedName(i)] = attributeValue(i);
    }
    return map;
  }

  void _readStartElement() {
    _type = XmlEventType.startElement;
    final int tagStart = _pos - 1;
    if (_elementStack.length + 1 > _maxDepth) {
      throw XmlParseException(
        'Elements nested deeper than $_maxDepth',
        tagStart,
        kind: XmlParseKind.tooDeep,
      );
    }
    _readQName();
    _skipSpaces();
    final _NsScope scope = _NsScope(_nsStack.last);
    bool closed = false;
    while (_pos < _source.length) {
      final int ch = _source.codeUnitAt(_pos);
      if (ch == _gt) {
        _pos++;
        closed = true;
        break;
      }
      if (ch == _slash) {
        _pos++;
        _expect(_gt, 'Expected > after / in empty element');
        _emptyElement = true;
        closed = true;
        break;
      }
      _readAttribute(scope);
      _skipSpaces();
    }
    if (!closed) {
      throw XmlParseException('Unterminated start tag', _pos);
    }
    _nsStack.add(scope);
    _elementStack.add(qualifiedName);
    _depth = _elementStack.length;
  }

  void _readEndElement() {
    _type = XmlEventType.endElement;
    _pos++; // skip /
    _readQName();
    _skipSpaces();
    _expect(_gt, 'Expected > at end of closing tag');
    if (_elementStack.isEmpty) {
      throw XmlParseException('Unexpected end tag </$qualifiedName>', _pos);
    }
    final String open = _elementStack.removeLast();
    if (open != qualifiedName) {
      throw XmlParseException(
        'Mismatched end tag: expected </$open> but found </$qualifiedName>',
        _pos,
      );
    }
    _depth = _elementStack.length;
    if (_nsStack.length > 1) {
      _nsStack.removeLast();
    }
  }

  void _readQName() {
    _nameStart = _pos;
    _prefixStart = _pos;
    _prefixEnd = _pos;
    while (_pos < _source.length && _isNameChar(_source.codeUnitAt(_pos))) {
      if (_source.codeUnitAt(_pos) == _colon && _prefixEnd == _prefixStart) {
        _prefixEnd = _pos;
      }
      _pos++;
    }
    _nameEnd = _pos;
    if (_nameEnd == _nameStart ||
        !_isNameStart(_source.codeUnitAt(_nameStart))) {
      throw XmlParseException('Expected qualified name', _nameStart);
    }
    if (_prefixEnd > _prefixStart) {
      _localStart = _prefixEnd + 1;
      _localEnd = _nameEnd;
    } else {
      _localStart = _nameStart;
      _localEnd = _nameEnd;
      _prefixStart = _prefixEnd = _nameStart;
    }
  }

  void _readAttribute(_NsScope scope) {
    final int qStart = _pos;
    int prefixEnd = qStart;
    while (_pos < _source.length && _isNameChar(_source.codeUnitAt(_pos))) {
      if (_source.codeUnitAt(_pos) == _colon && prefixEnd == qStart) {
        prefixEnd = _pos;
      }
      _pos++;
    }
    final int qEnd = _pos;
    if (qEnd == qStart || !_isNameStart(_source.codeUnitAt(qStart))) {
      throw XmlParseException('Expected attribute name', qStart);
    }
    _skipSpaces();
    _expect(_eq, 'Expected = after attribute name');
    _skipSpaces();
    if (_pos >= _source.length) {
      throw XmlParseException('Expected quoted attribute value', _pos);
    }
    final int quote = _source.codeUnitAt(_pos);
    if (quote != _quot && quote != _apos) {
      throw XmlParseException('Expected quoted attribute value', _pos);
    }
    _pos++;
    final int vStart = _pos;
    bool hasEntities = false;
    while (_pos < _source.length && _source.codeUnitAt(_pos) != quote) {
      if (_source.codeUnitAt(_pos) == _amp) {
        hasEntities = true;
      }
      _pos++;
    }
    final int vEnd = _pos;
    _expect(quote, 'Unterminated attribute value');

    final _AttrSlice attr = _AttrSlice(
      nameStart: qStart,
      nameEnd: qEnd,
      prefixEnd: prefixEnd,
      valueStart: vStart,
      valueEnd: vEnd,
      hasEntities: hasEntities,
    );
    _attrs.add(attr);

    // Decoding here makes a bad reference fail while reading the tag, not
    // later, whenever (or whether) the value is asked for.
    final String value = attr.decodedValue(_source);
    final String qname = _source.substring(qStart, qEnd);
    if (qname == 'xmlns') {
      scope.declare('', value);
      attr.isXmlns = true;
    } else if (qname.startsWith('xmlns:')) {
      scope.declare(qname.substring(6), value);
      attr.isXmlns = true;
    }
  }

  void _readText() {
    _type = XmlEventType.characters;
    _textStart = _pos;
    while (_pos < _source.length && _source.codeUnitAt(_pos) != _lt) {
      if (_source.codeUnitAt(_pos) == _amp) {
        _textHasEntities = true;
      }
      _pos++;
    }
    _textEnd = _pos;
  }

  void _readBang() {
    _pos++; // !
    if (_startsWith('--')) {
      _pos += 2;
      _type = XmlEventType.comment;
      _textStart = _pos;
      final int end = _source.indexOf('-->', _pos);
      if (end < 0) {
        throw XmlParseException('Unterminated comment', _pos);
      }
      _textEnd = end;
      _pos = end + 3;
      return;
    }
    if (_startsWith('[CDATA[')) {
      _pos += 7;
      _type = XmlEventType.cdata;
      _textStart = _pos;
      final int end = _source.indexOf(']]>', _pos);
      if (end < 0) {
        throw XmlParseException('Unterminated CDATA', _pos);
      }
      _textEnd = end;
      _pos = end + 3;
      return;
    }
    if (_startsWith('DOCTYPE')) {
      throw XmlParseException(
        'A DOCTYPE is not allowed',
        _pos - 2,
        kind: XmlParseKind.doctype,
      );
    }
    throw XmlParseException('Unsupported declaration after <!', _pos);
  }

  void _readPiOrDeclaration() {
    _pos++; // ?
    final int nameStart = _pos;
    while (_pos < _source.length && _isNameChar(_source.codeUnitAt(_pos))) {
      _pos++;
    }
    final String target = _source.substring(nameStart, _pos);
    _skipSpaces();
    _textStart = _pos;
    final int end = _source.indexOf('?>', _pos);
    if (end < 0) {
      throw XmlParseException('Unterminated processing instruction', _pos);
    }
    _textEnd = end;
    _pos = end + 2;
    _type = target == 'xml'
        ? XmlEventType.xmlDeclaration
        : XmlEventType.processingInstruction;
    _nameStart = nameStart;
    _nameEnd = nameStart + target.length;
    _localStart = _nameStart;
    _localEnd = _nameEnd;
  }

  String _resolvePrefix(String prefix) {
    if (prefix == 'xml') {
      return 'http://www.w3.org/XML/1998/namespace';
    }
    if (prefix == 'xmlns') {
      return 'http://www.w3.org/2000/xmlns/';
    }
    return _nsStack.last.resolve(prefix);
  }

  void _skipSpaces() {
    while (_pos < _source.length && _isXmlSpace(_source.codeUnitAt(_pos))) {
      _pos++;
    }
  }

  void _expect(int codeUnit, String message) {
    if (_pos >= _source.length || _source.codeUnitAt(_pos) != codeUnit) {
      throw XmlParseException(message, _pos);
    }
    _pos++;
  }

  bool _startsWith(String token) {
    if (_pos + token.length > _source.length) {
      return false;
    }
    return _source.startsWith(token, _pos);
  }

  String _slice(int start, int end) => _source.substring(start, end);

  static String _stripBom(String source) {
    if (source.isNotEmpty && source.codeUnitAt(0) == 0xFEFF) {
      return source.substring(1);
    }
    return source;
  }

  /// The `encoding` of a leading XML declaration, or the empty string.
  static String _declaredEncoding(String source) {
    if (!source.startsWith('<?xml')) {
      return '';
    }
    final int end = source.indexOf('?>');
    if (end < 0) {
      return '';
    }
    final Match? match = _encodingPattern.firstMatch(source.substring(0, end));
    return match == null ? '' : (match.group(1) ?? match.group(2) ?? '');
  }

  static final RegExp _encodingPattern = RegExp(
    r'''\sencoding\s*=\s*(?:"([^"]*)"|'([^']*)')''',
  );
}

/// Decodes XML predefined and numeric character entities, and normalizes
/// line endings to `\n`.
///
/// Throws [XmlParseException] ([XmlParseKind.malformed]) for an unterminated
/// reference, an unknown entity, a numeric reference that is not made of
/// digits, `&#0;`, a surrogate or a code point above U+10FFFF. [offset] is
/// where [raw] starts in its document, added to the reported offsets.
String decodeXmlEntities(String raw, {int offset = 0}) {
  final int amp = raw.indexOf('&');
  if (amp < 0) {
    return raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < raw.length) {
    final int nextAmp = raw.indexOf('&', i);
    if (nextAmp < 0) {
      out.write(raw.substring(i));
      break;
    }
    out.write(raw.substring(i, nextAmp));
    final int semi = raw.indexOf(';', nextAmp + 1);
    if (semi < 0) {
      throw XmlParseException('Unterminated entity', offset + nextAmp);
    }
    final String body = raw.substring(nextAmp + 1, semi);
    out.writeCharCode(_entityCodePoint(body, offset + nextAmp));
    i = semi + 1;
  }
  return out.toString().replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

int _entityCodePoint(String body, int at) {
  switch (body) {
    case 'lt':
      return _lt;
    case 'gt':
      return _gt;
    case 'amp':
      return _amp;
    case 'quot':
      return _quot;
    case 'apos':
      return _apos;
  }
  if (body.startsWith('#x') || body.startsWith('#X')) {
    return _numericReference(body, 2, 16, at);
  }
  if (body.startsWith('#')) {
    return _numericReference(body, 1, 10, at);
  }
  throw XmlParseException('Unknown entity &$body;', at);
}

/// Parses the digits of [body] from [from], accepting nothing but digits of
/// [radix], and checks the result is a legal XML code point.
int _numericReference(String body, int from, int radix, int at) {
  if (from >= body.length) {
    throw XmlParseException('Empty character reference &$body;', at);
  }
  int value = 0;
  for (int i = from; i < body.length; i++) {
    final int digit = _digitValue(body.codeUnitAt(i));
    if (digit < 0 || digit >= radix) {
      throw XmlParseException('Malformed character reference &$body;', at);
    }
    value = value * radix + digit;
    if (value > 0x10FFFF) {
      throw XmlParseException('Character reference out of range', at);
    }
  }
  if (value == 0 || (value >= 0xD800 && value <= 0xDFFF)) {
    throw XmlParseException('Illegal character reference &$body;', at);
  }
  return value;
}

int _digitValue(int ch) {
  if (ch >= 0x30 && ch <= 0x39) {
    return ch - 0x30;
  }
  if (ch >= 0x41 && ch <= 0x46) {
    return ch - 0x41 + 10;
  }
  if (ch >= 0x61 && ch <= 0x66) {
    return ch - 0x61 + 10;
  }
  return -1;
}

final class _AttrSlice {
  _AttrSlice({
    required this.nameStart,
    required this.nameEnd,
    required this.prefixEnd,
    required this.valueStart,
    required this.valueEnd,
    required this.hasEntities,
  });

  final int nameStart;
  final int nameEnd;
  final int prefixEnd;
  final int valueStart;
  final int valueEnd;
  final bool hasEntities;
  bool isXmlns = false;

  String qualified(String source) => source.substring(nameStart, nameEnd);

  String local(String source) {
    if (prefixEnd > nameStart) {
      return source.substring(prefixEnd + 1, nameEnd);
    }
    return source.substring(nameStart, nameEnd);
  }

  String prefix(String source) {
    if (prefixEnd > nameStart) {
      return source.substring(nameStart, prefixEnd);
    }
    return '';
  }

  String decodedValue(String source) {
    final String raw = source.substring(valueStart, valueEnd);
    if (!hasEntities) {
      return raw;
    }
    return decodeXmlEntities(raw, offset: valueStart);
  }
}

final class _NsScope {
  _NsScope(this.parent);

  _NsScope.root() : parent = null {
    _map[''] = '';
  }

  final _NsScope? parent;
  final Map<String, String> _map = <String, String>{};

  void declare(String prefix, String uri) {
    _map[prefix] = uri;
  }

  String resolve(String prefix) {
    _NsScope? scope = this;
    while (scope != null) {
      final String? found = scope._map[prefix];
      if (found != null) {
        return found;
      }
      scope = scope.parent;
    }
    return '';
  }
}

bool _isXmlSpace(int ch) =>
    ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D;

/// A name may not start with a digit, `-` or `.`.
bool _isNameStart(int ch) =>
    _isNameChar(ch) && !(ch >= 48 && ch <= 57) && ch != 45 && ch != 46;

bool _isNameChar(int ch) {
  return (ch >= 65 && ch <= 90) ||
      (ch >= 97 && ch <= 122) ||
      (ch >= 48 && ch <= 57) ||
      ch == 95 ||
      ch == 45 ||
      ch == 46 ||
      ch == 58 ||
      ch >= 0xC0;
}

const int _lt = 0x3C;
const int _gt = 0x3E;
const int _slash = 0x2F;
const int _bang = 0x21;
const int _quest = 0x3F;
const int _eq = 0x3D;
const int _quot = 0x22;
const int _apos = 0x27;
const int _amp = 0x26;
const int _colon = 0x3A;
