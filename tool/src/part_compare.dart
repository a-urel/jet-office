/// Compares two XLSX or DOCX packages part by part, by meaning and not by
/// bytes.
///
/// Not ported from Quds; written for jet_office. This is the yardstick the
/// phase 3 and phase 4 round-trip tests use to prove that opening and
/// saving a file keeps every part (spec 4.2 of each phase). It is test-side tooling: it uses
/// `package:archive` and `package:xml`, never `dart:io`, so it runs on the
/// VM and in a browser.
///
/// [comparePackages] returns one line per difference, `'<part>: <what>'`,
/// and nothing when the packages are equal. A part is XML or binary by its
/// content type (from `[Content_Types].xml`: a `Default` by extension, an
/// `Override` by part name); a type ending in `+xml` or `/xml` is XML, any
/// other is compared byte for byte.
///
/// XML compares as follows:
///
/// * elements by namespace URI and local name, so prefixes do not matter;
/// * attributes as a map keyed by namespace URI and local name, so their
///   order does not matter; `xmlns` declarations are left out;
/// * text exactly, leading and trailing spaces included; only a text node
///   of whitespace between elements (indentation) is ignored, and not
///   under `xml:space="preserve"`;
/// * relationship ids by what they resolve to: a `.rels` part compares as
///   the set of `(type, target, mode)`, and an attribute in the
///   relationships namespace (`r:id`, `r:embed`) in the part the rels
///   belong to compares by the relationship it names;
/// * a shared string cell (`t="s"`) by the `si` it names, not by its
///   index; `sharedStrings.xml` itself as the set of strings the cells
///   reference, plus its root's attributes (but `count` and `uniqueCount`)
///   and its children other than `<si>` (an `extLst`), which are not
///   items and do not shift their indexes;
/// * the children of `[Content_Types].xml` as a set;
/// * in SpreadsheetML, a `<t>` whose text neither starts nor ends with
///   whitespace as if it had no `xml:space="preserve"`, which only keeps
///   those spaces;
/// * in SpreadsheetML, a cell's `t="n"` as no `t` (both mean a number), and
///   a `<row>` or cell without `r` as if it had its position: a row follows
///   the previous row (the first is 1), a cell the previous cell of its row
///   (the first is in column A). A position that differs is reported.
///
/// With `ignoreBookkeeping`, a worksheet's `<dimension ref>` and each row's
/// `spans` are left out: they summarize the cells and a saving model
/// recomputes them (spec 4.4).
///
/// A package is a DOCX when the part its root `officeDocument` relationship
/// names has a WordprocessingML content type (by `[Content_Types].xml`, not
/// by the file's extension). A DOCX compares by the rules above with these
/// changes:
///
/// * no SpreadsheetML rule applies (shared strings, `t="n"`, the `xml:space`
///   of `<t>`, filled positions, `ignoreBookkeeping`), even to elements in
///   the SpreadsheetML namespace;
/// * the text of `w:t`, `w:instrText` and `w:delText` (by namespace URI)
///   compares exactly, whitespace included, and their `xml:space` compares
///   as written.
///
/// [compareXmlParts] compares one WordprocessingML part by the same DOCX
/// rules, with relationship ids compared literally.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// The relationships namespace, home of `r:id` and `r:embed`.
const String _relNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

/// The SpreadsheetML namespace.
const String _mainNs =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

/// The XML namespace, home of `xml:space`.
const String _xmlNs = 'http://www.w3.org/XML/1998/namespace';

/// The WordprocessingML namespace.
const String _wNs =
    'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

/// The WordprocessingML elements whose text is content to its last space:
/// `w:t`, `w:instrText` and `w:delText`, as `uri|local`.
const Set<String> _wordText = <String>{
  '$_wNs|t',
  '$_wNs|instrText',
  '$_wNs|delText',
};

/// The differences between the packages [expected] and [actual], one line
/// per difference, `'<part>: <what>'`; empty when they are equal.
///
/// A part named in [ignoreParts] is skipped on both sides. A part only in
/// [actual] is a difference unless it is named in [allowAdded].
/// [ignoreBookkeeping] leaves out `dimension/@ref` and `row/@spans`; it
/// has no effect on a DOCX. Whether the packages are DOCX is read from
/// [expected]; a package whose main part is WordprocessingML on one side
/// only is a difference.
List<String> comparePackages(
  Uint8List expected,
  Uint8List actual, {
  Set<String> ignoreParts = const <String>{},
  Set<String> allowAdded = const <String>{},
  bool ignoreBookkeeping = false,
}) {
  final _Package e = _Package(expected, 'expected');
  final _Package a = _Package(actual, 'actual');
  final List<String> out = <String>[
    if (e.error != null)
      'package: the expected package is unreadable: ${e.error}',
    if (a.error != null)
      'package: the actual package is unreadable: ${a.error}',
  ];
  if (out.isNotEmpty) return out;
  final bool docx = e.isWordprocessing;
  if (docx != a.isWordprocessing) {
    out.add(
      'package: the main part is WordprocessingML in the '
      '${docx ? 'expected' : 'actual'} package only',
    );
  }
  final Set<String> names = <String>{...e.parts.keys, ...a.parts.keys}
    ..removeAll(ignoreParts);
  for (final String name in names) {
    final Uint8List? eb = e.parts[name];
    final Uint8List? ab = a.parts[name];
    if (ab == null) {
      out.add('$name: missing from the actual package');
    } else if (eb == null) {
      if (!allowAdded.contains(name)) {
        out.add('$name: added to the actual package');
      }
    } else if (e.isXml(name) != a.isXml(name)) {
      out.add(
        '$name: content type differs '
        '(${e.typeOf(name)} vs ${a.typeOf(name)})',
      );
    } else if (!e.isXml(name)) {
      if (!_sameBytes(eb, ab)) out.add('$name: bytes differ');
    } else {
      _comparePart(name, e, a, out, ignoreBookkeeping, docx);
    }
  }
  return out;
}

/// The differences between the XML texts [expected] and [actual] of the
/// part [part], by the rules of [comparePackages] that need no other part:
/// no relationship ids or shared string indexes are resolved.
/// [ignoreBookkeeping] leaves out `dimension/@ref` and `row/@spans`.
List<String> compareXml(
  String part,
  String expected,
  String actual, {
  bool ignoreBookkeeping = false,
}) {
  final List<String> out = <String>[];
  final _Node? e = _canonicalText(
    part,
    expected,
    'expected',
    out,
    ignoreBookkeeping,
    false,
  );
  final _Node? a = _canonicalText(
    part,
    actual,
    'actual',
    out,
    ignoreBookkeeping,
    false,
  );
  if (e != null && a != null) _diff(part, e, a, '', out);
  return out;
}

/// The differences between the UTF-8 XML bytes [expected] and [actual] of
/// the WordprocessingML part [partName], one line per difference,
/// `'<part>: <what>'`; empty when they are equal.
///
/// The rules are those [comparePackages] applies to a part of a DOCX,
/// except that an attribute in the relationships namespace (`r:id`,
/// `r:embed`) compares literally: one part has no relationships to resolve
/// it through. Bytes that are not UTF-8 or not well-formed XML are a
/// difference, not an exception.
List<String> compareXmlParts(
  String partName,
  Uint8List expected,
  Uint8List actual,
) {
  final List<String> out = <String>[];
  _Node? canonical(Uint8List bytes, String side) {
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      out.add('$partName: the $side part is not UTF-8');
      return null;
    }
    return _canonicalText(partName, text, side, out, false, true);
  }

  final _Node? e = canonical(expected, 'expected');
  final _Node? a = canonical(actual, 'actual');
  if (e != null && a != null) _diff(partName, e, a, '', out);
  return out;
}

_Node? _canonicalText(
  String part,
  String text,
  String side,
  List<String> out,
  bool ignoreBookkeeping,
  bool wordprocessing,
) {
  try {
    return _Canon(
      null,
      null,
      ignoreBookkeeping: ignoreBookkeeping,
      wordprocessing: wordprocessing,
    ).node(XmlDocument.parse(text).rootElement, false);
  } on XmlException catch (error) {
    out.add('$part: the $side part is not well-formed XML (${error.message})');
    return null;
  }
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _comparePart(
  String name,
  _Package e,
  _Package a,
  List<String> out,
  bool ignoreBookkeeping,
  bool docx,
) {
  final XmlDocument? ed = e.document(name);
  final XmlDocument? ad = a.document(name);
  if (ed == null || ad == null) {
    if (ed == null) {
      out.add('$name: the expected part is not well-formed XML or not UTF-8');
    }
    if (ad == null) {
      out.add('$name: the actual part is not well-formed XML or not UTF-8');
    }
    return;
  }
  if (!docx && e.isSharedStrings(name) && a.isSharedStrings(name)) {
    final Set<String> es = e.referencedStrings();
    final Set<String> as = a.referencedStrings();
    for (final String s in (es.toList()..sort())) {
      if (!as.contains(s)) {
        out.add('$name: string only in expected: ${_show(s)}');
      }
    }
    for (final String s in (as.toList()..sort())) {
      if (!es.contains(s)) out.add('$name: string only in actual: ${_show(s)}');
    }
    _diff(
      name,
      _sstFrame(_Canon(e, name).node(ed.rootElement, false)),
      _sstFrame(_Canon(a, name).node(ad.rootElement, false)),
      '',
      out,
    );
    return;
  }
  _diff(
    name,
    _Canon(
      e,
      name,
      ignoreBookkeeping: ignoreBookkeeping,
      wordprocessing: docx,
    ).node(ed.rootElement, false),
    _Canon(
      a,
      name,
      ignoreBookkeeping: ignoreBookkeeping,
      wordprocessing: docx,
    ).node(ad.rootElement, false),
    '',
    out,
  );
}

/// The shared string table [root] without its items and counts: its other
/// attributes and its children other than `<si>`.
_Node _sstFrame(_Node root) => _Node(
  root.name,
  <String, String>{
    for (final MapEntry<String, String> a in root.attrs.entries)
      if (a.key != '|count' && a.key != '|uniqueCount') a.key: a.value,
  },
  <Object>[
    for (final Object c in root.children)
      if (c is! _Node || !_isSi(c.name)) c,
  ],
);

bool _isSi(String name) => name == '$_mainNs|si';

/// A canonical element: its `uri|local` name, attributes by `uri|local`,
/// and children that are [_Node]s or text [String]s.
class _Node {
  _Node(this.name, this.attrs, this.children);

  final String name;
  final Map<String, String> attrs;
  final List<Object> children;

  String get local => name.substring(name.indexOf('|') + 1);

  String get text => children.whereType<String>().join();

  /// A single string standing for the whole subtree, to sort and compare
  /// by.
  String serialize() {
    final StringBuffer b = StringBuffer('<$name');
    for (final String k in (attrs.keys.toList()..sort())) {
      b.write(' $k=${jsonEncode(attrs[k])}');
    }
    b.write('>');
    for (final Object c in children) {
      b.write(c is _Node ? c.serialize() : jsonEncode(c));
    }
    b.write('</>');
    return b.toString();
  }
}

/// Compares [e] and [a], at the location [loc], and adds a line per
/// difference to [out].
void _diff(String part, _Node e, _Node a, String loc, List<String> out) {
  final String here = '$loc/${e.local}';
  final String at = e.local == 'c' && e.attrs.containsKey('|r')
      ? e.attrs['|r']!
      : here;
  if (e.name != a.name) {
    out.add('$part: $at: element ${e.name} vs ${a.name}');
    return;
  }
  for (final String k in <String>{...e.attrs.keys, ...a.attrs.keys}) {
    final String? ev = e.attrs[k];
    final String? av = a.attrs[k];
    if (ev != av) {
      final String attr = k.substring(k.indexOf('|') + 1);
      out.add(
        '$part: $at: attribute $attr '
        '${ev == null ? 'missing' : jsonEncode(ev)} vs '
        '${av == null ? 'missing' : jsonEncode(av)}',
      );
    }
  }
  if (e.children.length != a.children.length) {
    out.add(
      '$part: $at: ${e.children.length} children vs ${a.children.length}',
    );
    return;
  }
  // Inside a cell, name the cell and not the cell's child.
  final String childLoc = e.local == 'c' && e.attrs.containsKey('|r')
      ? at
      : here;
  for (int i = 0; i < e.children.length; i++) {
    final Object ec = e.children[i];
    final Object ac = a.children[i];
    if (ec is _Node && ac is _Node) {
      _diff(part, ec, ac, childLoc, out);
    } else if (ec is String && ac is String) {
      if (ec != ac) {
        out.add(
          '$part: $at: text ${jsonEncode(_show(ec))} vs ${jsonEncode(_show(ac))}',
        );
      }
    } else {
      out.add(
        '$part: $at: child $i is an element in one and text in the other',
      );
    }
  }
}

/// Turns elements of one part into [_Node]s, resolving relationship ids and
/// shared string indexes through [_package] when there is one.
///
/// With [wordprocessing], the part belongs to a DOCX: no SpreadsheetML rule
/// applies, and the text of `w:t`, `w:instrText` and `w:delText` is exact.
class _Canon {
  _Canon(
    this._package,
    this._part, {
    bool ignoreBookkeeping = false,
    this.wordprocessing = false,
  }) : ignoreBookkeeping = ignoreBookkeeping && !wordprocessing;

  final _Package? _package;
  final String? _part;
  final bool ignoreBookkeeping;
  final bool wordprocessing;

  /// Whether the SpreadsheetML rules apply.
  bool get _spreadsheet => !wordprocessing;

  late final Map<String, String> _rels =
      _package?.relationshipsOf(_part!) ?? const <String, String>{};

  _Node node(XmlElement element, bool inheritedExact) {
    final String name = _key(element.name);
    if (_part == '[Content_Types].xml' && _isRoot(element)) {
      return _sorted(element, name);
    }
    if (_part != null && _part.endsWith('.rels') && _isRoot(element)) {
      return _relationships(element, name);
    }
    final Map<String, String> attrs = <String, String>{};
    for (final XmlAttribute attr in element.attributes) {
      if (_isXmlns(attr)) continue;
      String value = attr.value;
      if (attr.name.prefix != null && attr.name.namespaceUri == _relNs) {
        value = _rels[value] ?? value;
      }
      attrs[_attrKey(attr.name)] = value;
    }
    final bool preserve = element.attributes.any(
      (XmlAttribute a) =>
          _attrKey(a.name) == '$_xmlNs|space' && a.value == 'preserve',
    );
    final String local = element.name.local;
    final bool exact =
        inheritedExact ||
        preserve ||
        wordprocessing && _wordText.contains(name);
    final bool hasElements = element.childElements.isNotEmpty;
    final List<Object> children = <Object>[];
    final StringBuffer run = StringBuffer();
    void flush() {
      if (run.isEmpty) return;
      final String text = run.toString();
      // Whitespace between elements is layout; in a leaf it is content.
      final bool layout = hasElements && !exact && text.trim().isEmpty;
      if (text.isNotEmpty && !layout) children.add(text);
      run.clear();
    }

    for (final XmlNode child in element.children) {
      if (child is XmlText || child is XmlCDATA) {
        run.write(child.value);
      } else if (child is XmlElement) {
        flush();
        children.add(node(child, exact));
      }
    }
    flush();
    if (_spreadsheet && name == '$_mainNs|c' && attrs['|t'] == 'n') {
      attrs.remove('|t');
    }
    // A SpreadsheetML text's xml:space="preserve" only keeps the spaces
    // around it (the writer's rule, `writeTextElement`); without any it
    // changes nothing Excel shows.
    if (_spreadsheet && name == '$_mainNs|t' && !hasElements) {
      final String text = children.whereType<String>().join();
      if (text.isEmpty ||
          !_xmlSpace(text.codeUnitAt(0)) &&
              !_xmlSpace(text.codeUnitAt(text.length - 1))) {
        if (attrs['$_xmlNs|space'] == 'preserve') attrs.remove('$_xmlNs|space');
      }
    }
    if (ignoreBookkeeping) {
      if (name == '$_mainNs|dimension') attrs.remove('|ref');
      if (name == '$_mainNs|row') attrs.remove('|spans');
    }
    if (_spreadsheet && name == '$_mainNs|sheetData') {
      _fillPositions(children);
    }
    final _Node result = _Node(name, attrs, children);
    final _Package? package = _package;
    if (_spreadsheet &&
        package != null &&
        local == 'c' &&
        attrs['|t'] == 's' &&
        children.length == 1 &&
        children.single is _Node &&
        (children.single as _Node).local == 'v') {
      final _Node v = children.single as _Node;
      final int? index = int.tryParse(v.text.trim());
      final String? si = index == null ? null : package.sharedString(index);
      return _Node(name, attrs, <Object>[
        _Node(v.name, v.attrs, <Object>[si ?? 'unresolved:${v.text}']),
      ]);
    }
    return result;
  }

  bool _isRoot(XmlElement e) => e.parent is XmlDocument;

  /// Gives each `<row>` of a `<sheetData>`'s [children], and each cell of a
  /// row, that has no `r` the position a reader gives it: the row after the
  /// previous row, the column after the previous cell.
  static void _fillPositions(List<Object> children) {
    var previousRow = 0;
    for (final Object row in children) {
      if (row is! _Node || row.name != '$_mainNs|row') continue;
      final String? r = row.attrs['|r'];
      final int index = r == null
          ? previousRow + 1
          : int.tryParse(r) ?? previousRow + 1;
      row.attrs['|r'] ??= '$index';
      previousRow = index;
      var previousColumn = 0;
      for (final Object cell in row.children) {
        if (cell is! _Node || cell.name != '$_mainNs|c') continue;
        final String? ref = cell.attrs['|r'];
        final int column = ref == null
            ? previousColumn + 1
            : _columnOf(ref) ?? previousColumn + 1;
        cell.attrs['|r'] ??= '${_columnName(column)}$index';
        previousColumn = column;
      }
    }
  }

  /// The 1-based column of the reference [ref], or `null` without letters.
  static int? _columnOf(String ref) {
    var column = 0;
    var i = 0;
    for (; i < ref.length; i++) {
      final int c = ref.codeUnitAt(i);
      if (c < 0x41 || c > 0x5A) break;
      column = column * 26 + (c - 0x40);
    }
    return i == 0 ? null : column;
  }

  /// The letters of the 1-based [column].
  static String _columnName(int column) {
    var name = '';
    for (var c = column; c > 0; c = (c - 1) ~/ 26) {
      name = String.fromCharCode(0x41 + (c - 1) % 26) + name;
    }
    return name;
  }

  /// An element whose children compare as a set.
  _Node _sorted(XmlElement element, String name) {
    final List<_Node> kids = <_Node>[
      for (final XmlElement c in element.childElements)
        _Canon(null, null).node(c, false),
    ]..sort((_Node a, _Node b) => a.serialize().compareTo(b.serialize()));
    return _Node(name, <String, String>{}, kids);
  }

  /// A relationships part: the set of `(type, target, mode)`, without ids.
  _Node _relationships(XmlElement element, String name) {
    final List<_Node> kids = <_Node>[
      for (final XmlElement r in element.childElements)
        _Node(_key(r.name), <String, String>{
          'Type': r.getAttribute('Type') ?? '',
          'Target': r.getAttribute('Target') ?? '',
          'TargetMode': r.getAttribute('TargetMode') ?? 'Internal',
        }, const <Object>[]),
    ]..sort((_Node a, _Node b) => a.serialize().compareTo(b.serialize()));
    return _Node(name, <String, String>{}, kids);
  }
}

/// [text] without the namespace URIs of a serialized subtree, to read.
String _show(String text) => text.replaceAll(RegExp(r'<[^>|"]*\|'), '<');

String _key(XmlName name) => '${name.namespaceUri ?? ''}|${name.local}';

String _attrKey(XmlName name) {
  if (name.prefix == 'xml') return '$_xmlNs|${name.local}';
  // An unprefixed attribute has no namespace, whatever the default is.
  if (name.prefix == null) return '|${name.local}';
  return _key(name);
}

/// Whether [unit] is XML whitespace: space, tab, line feed or carriage
/// return.
bool _xmlSpace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;

bool _isXmlns(XmlAttribute a) =>
    a.name.prefix == 'xmlns' ||
    (a.name.prefix == null && a.name.local == 'xmlns');

/// The parts of one package, with the lookups the comparison needs.
class _Package {
  _Package(Uint8List bytes, this.side) {
    try {
      for (final ArchiveFile file in ZipDecoder().decodeBytes(bytes).files) {
        if (file.isFile) parts[file.name] = Uint8List.fromList(file.content);
      }
      if (parts.isEmpty) {
        error_ = 'not a readable ZIP (it holds no parts)';
        return;
      }
    } on ArchiveException catch (error) {
      error_ = 'not a readable ZIP (${error.message})';
      return;
    } on FormatException catch (error) {
      error_ = 'not a readable ZIP (${error.message})';
      return;
    }
    final Uint8List? types = parts['[Content_Types].xml'];
    if (types != null) {
      try {
        for (final XmlElement e in XmlDocument.parse(
          utf8.decode(types),
        ).rootElement.childElements) {
          final String? type = e.getAttribute('ContentType');
          if (type == null) continue;
          if (e.name.local == 'Default') {
            final String? ext = e.getAttribute('Extension');
            if (ext != null) _defaults[ext.toLowerCase()] = type;
          } else if (e.name.local == 'Override') {
            final String? partName = e.getAttribute('PartName');
            if (partName != null) {
              _overrides[partName.replaceFirst('/', '')] = type;
            }
          }
        }
      } on XmlException {
        // The part itself is reported as not well-formed.
      } on FormatException {
        // The part itself is reported as not valid UTF-8.
      }
    }
  }

  final String side;
  String? error_;

  /// Why the package could not be opened, or null.
  String? get error => error_;
  final Map<String, Uint8List> parts = <String, Uint8List>{};
  final Map<String, String> _defaults = <String, String>{};
  final Map<String, String> _overrides = <String, String>{};
  final Map<String, XmlDocument?> _documents = <String, XmlDocument?>{};

  String typeOf(String part) {
    final String? override = _overrides[part];
    if (override != null) return override;
    final int dot = part.lastIndexOf('.');
    final String ext = dot < 0 ? '' : part.substring(dot + 1).toLowerCase();
    final String? type = _defaults[ext];
    if (type != null) return type;
    // No declared type: an XML extension still reads as XML.
    return ext == 'xml' || ext == 'rels' ? 'application/xml' : '';
  }

  bool isXml(String part) {
    final String type = typeOf(part);
    return type.endsWith('+xml') || type.endsWith('/xml');
  }

  /// Whether the part the root `officeDocument` relationship names has a
  /// WordprocessingML content type: a document, a template, or either with
  /// macros.
  late final bool isWordprocessing = _isWordprocessing();

  bool _isWordprocessing() {
    if (!parts.containsKey('_rels/.rels')) return false;
    final XmlDocument? rels = document('_rels/.rels');
    if (rels == null) return false;
    for (final XmlElement r in rels.rootElement.childElements) {
      final String type = r.getAttribute('Type') ?? '';
      if (!type.endsWith('/officeDocument')) continue;
      final String target = (r.getAttribute('Target') ?? '').replaceFirst(
        RegExp('^/'),
        '',
      );
      final String contentType = typeOf(target);
      if (contentType.contains('.wordprocessingml.') ||
          contentType.startsWith('application/vnd.ms-word.')) {
        return true;
      }
    }
    return false;
  }

  bool isSharedStrings(String part) =>
      typeOf(part).endsWith('spreadsheetml.sharedStrings+xml');

  /// The parsed [part], or null when it is not well-formed.
  XmlDocument? document(String part) => _documents.putIfAbsent(part, () {
    try {
      return XmlDocument.parse(utf8.decode(parts[part]!));
    } on XmlException {
      return null;
    } on FormatException {
      return null;
    }
  });

  /// The relationships of [part]: id to `type|target|mode`.
  Map<String, String> relationshipsOf(String part) {
    final int slash = part.lastIndexOf('/');
    final String dir = slash < 0 ? '' : part.substring(0, slash + 1);
    final String file = part.substring(slash + 1);
    final String rels = '${dir}_rels/$file.rels';
    if (!parts.containsKey(rels)) return const <String, String>{};
    final XmlDocument? doc = document(rels);
    if (doc == null) return const <String, String>{};
    return <String, String>{
      for (final XmlElement r in doc.rootElement.childElements)
        r.getAttribute('Id') ?? '':
            '${r.getAttribute('Type')}|${r.getAttribute('Target')}|'
            '${r.getAttribute('TargetMode') ?? 'Internal'}',
    };
  }

  late final List<String> _strings = _loadStrings();

  List<String> _loadStrings() {
    final List<String> out = <String>[];
    for (final String part in parts.keys) {
      if (!isSharedStrings(part)) continue;
      final XmlDocument? doc = document(part);
      if (doc == null) continue;
      for (final XmlElement si in doc.rootElement.childElements) {
        if (si.name.local != 'si' || si.name.namespaceUri != _mainNs) continue;
        out.add(_Canon(null, null).node(si, false).serialize());
      }
      break;
    }
    return out;
  }

  /// The canonical form of the shared string [index], or null if none.
  String? sharedString(int index) =>
      index >= 0 && index < _strings.length ? _strings[index] : null;

  /// The shared strings that some cell of the package references.
  Set<String> referencedStrings() {
    final Set<String> out = <String>{};
    for (final String part in parts.keys) {
      if (!isXml(part) || isSharedStrings(part)) continue;
      final XmlDocument? doc = document(part);
      if (doc == null) continue;
      for (final XmlElement c in doc.descendantElements) {
        if (c.name.local != 'c' || c.getAttribute('t') != 's') continue;
        for (final XmlElement v in c.childElements) {
          if (v.name.local != 'v') continue;
          final int? index = int.tryParse(v.innerText.trim());
          final String? s = index == null ? null : sharedString(index);
          if (s != null) out.add(s);
        }
      }
    }
    return out;
  }
}
