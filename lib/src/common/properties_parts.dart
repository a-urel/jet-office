/// The document properties parts of a workbook or a document as model
/// content: core (`docProps/core.xml`), extended (`docProps/app.xml`) and
/// custom (`docProps/custom.xml`).
///
/// Not ported from Quds; written for jet_office.
///
/// Each part is immutable and keeps its root's start tag and every child as
/// an [OpaqueXml], so a loaded part is written back from the model with
/// everything it held (`dc:language`, `cp:lastPrinted`, `TitlesOfParts`, a
/// property of a type the model does not list). A part is found by the
/// package relationship of its kind, never by name. The values a part shows
/// are read from the first child of each kind; a value that cannot be read
/// (a date that is not W3CDTF, a number that is not one) leaves the child
/// where it is, reads as no value and is reported once, with the element's
/// name, through the host's [PropertyWarn] (a workbook reports
/// `XlsxWarningCode.featureEntryInvalid`). A part
/// whose root is not the expected element is untyped: it reads as nothing
/// and is never written from the model.
///
/// A set is a pure function from the old value and the new value to new
/// parts: only the fields that differ change, each as the writer's own
/// element rendered with the new value and captured, replaced in place, or
/// appended, or removed for a `null`. [PropertiesState] holds the current
/// parts of a workbook or a document and what they need at save: a part
/// that is not in the package joins it, and a custom part that holds
/// nothing leaves.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../opc/change_log.dart';
import '../opc/ooxml.dart';
import '../opc/opaque_xml.dart';
import '../opc/package.dart';
import '../xml/utf8_buffer.dart';
import '../xml/xml_pull_reader.dart';
import '../xml/xml_writer.dart';
import 'name_key.dart';
import 'properties.dart';

/// Reports a value that cannot be read: the element's name.
typedef PropertyWarn = void Function(String element);

/// What the properties parts are read from: the package of an open workbook
/// or document, its read limits and its way of reporting a part that cannot
/// be read.
abstract interface class PropertiesSource {
  /// The package the parts are found in, read from and written to.
  OpcPackage get package;

  /// The most children a properties part may have.
  int get maxChildren;

  /// The most UTF-16 code units one property's text may have.
  int get maxTextLength;

  /// Runs [body], which reads [part], mapping what the package or the XML
  /// parser throws to the format's read exception.
  T guard<T>(String part, T Function() body);

  /// A pull reader over the XML part [part], which the package holds.
  XmlPullReader openXml(String part);

  /// Throws the format's read exception for a limit that [part] exceeds,
  /// described by [message].
  Never limitExceeded(String part, String message);
}

/// One child of a properties part: the element as written and what a typed
/// read takes from it.
final class PropertyChild {
  const PropertyChild._(
    this.xml, {
    required this.text,
    this.name,
    this.pid,
    this.fmtid,
    this.variant,
    this.variantNamespace,
  });

  /// The element as written.
  final OpaqueXml xml;

  /// The character data of the element (for a custom property, of its
  /// value element).
  final String text;

  /// A custom property's `name`.
  final String? name;

  /// A custom property's `pid`, when it is a number.
  final int? pid;

  /// A custom property's `fmtid`.
  final String? fmtid;

  /// The local name of a custom property's value element.
  final String? variant;

  /// The namespace of a custom property's value element.
  final String? variantNamespace;

  /// Whether the element is [local] in [ns].
  bool isElement(String ns, String local) =>
      xml.namespaceUri == ns && xml.localName == local;
}

/// The start tag and the children of a typed part, as [PartContent].
abstract base class _PropertiesPart implements PartContent {
  _PropertiesPart(this._root, this.children);

  final XmlRoot? _root;

  /// The children, in order; empty for an untyped part.
  final List<PropertyChild> children;

  /// Whether the part's root is the expected element; an untyped part is
  /// never changed or written from the model.
  bool get isTyped => _root != null;

  /// Whether the part has no children.
  bool get isEmpty => children.isEmpty;

  @override
  List<Uint8List> encode() {
    final XmlRoot? root = _root;
    if (root == null) {
      throw StateError('An untyped properties part is written from bytes.');
    }
    final Utf8Buffer out = Utf8Buffer();
    final XmlWriter w = XmlWriter(out);
    w.declaration();
    writeRootStart(w, root);
    for (final PropertyChild child in children) {
      child.xml.writeTo(w, declaredAbove: root.namespaces);
    }
    w.end();
    return out.takeChunks();
  }
}

/// A field of the core or extended properties: its element and how to read
/// it from an [OfficeProperties].
final class _Field {
  const _Field(
    this.qualified,
    this.namespace,
    this.local,
    this.get, {
    this.parse,
  });

  /// The element name as the writer writes it.
  final String qualified;
  final String namespace;
  final String local;

  /// The field of [OfficeProperties].
  final Object? Function(OfficeProperties) get;

  /// Reads the value from the element's text, `null` when it cannot; a
  /// field without one takes the text as it is.
  final Object? Function(String text)? parse;
}

final List<_Field> _coreFields = <_Field>[
  _Field('dc:title', Ns.dc, 'title', (OfficeProperties p) => p.title),
  _Field('dc:subject', Ns.dc, 'subject', (OfficeProperties p) => p.subject),
  _Field('dc:creator', Ns.dc, 'creator', (OfficeProperties p) => p.creator),
  _Field(
    'cp:keywords',
    Ns.core,
    'keywords',
    (OfficeProperties p) => p.keywords,
  ),
  _Field(
    'dc:description',
    Ns.dc,
    'description',
    (OfficeProperties p) => p.description,
  ),
  _Field(
    'cp:lastModifiedBy',
    Ns.core,
    'lastModifiedBy',
    (OfficeProperties p) => p.lastModifiedBy,
  ),
  _Field(
    'cp:revision',
    Ns.core,
    'revision',
    (OfficeProperties p) => p.revision,
    parse: _parseRevision,
  ),
  _Field(
    'cp:category',
    Ns.core,
    'category',
    (OfficeProperties p) => p.category,
  ),
  _Field(
    'cp:contentStatus',
    Ns.core,
    'contentStatus',
    (OfficeProperties p) => p.contentStatus,
  ),
  _Field(
    'dcterms:created',
    Ns.dcterms,
    'created',
    (OfficeProperties p) => p.created,
    parse: parseW3cdtf,
  ),
  _Field(
    'dcterms:modified',
    Ns.dcterms,
    'modified',
    (OfficeProperties p) => p.modified,
    parse: parseW3cdtf,
  ),
];

final List<_Field> _appFields = <_Field>[
  _Field(
    'Application',
    Ns.extendedProperties,
    'Application',
    (OfficeProperties p) => p.application,
  ),
  _Field(
    'Company',
    Ns.extendedProperties,
    'Company',
    (OfficeProperties p) => p.company,
  ),
  _Field(
    'Manager',
    Ns.extendedProperties,
    'Manager',
    (OfficeProperties p) => p.manager,
  ),
];

/// Reads a `cp:revision` text: digits only, at most the largest integer
/// the web represents exactly, so the VM and the web agree; `null` for
/// anything else.
int? _parseRevision(String text) {
  final String t = text.trim();
  if (!_digits.hasMatch(t)) return null;
  final int? n = int.tryParse(t);
  return n == null || n > 9007199254740991 ? null : n;
}

final RegExp _digits = RegExp(r'^[0-9]+$');

/// Reads the part [r] walks: its root when it is [local] in [ns] (`null`
/// otherwise, for an untyped part) and its children, each captured whole.
///
/// [source], when given, bounds the number of children (by
/// [PropertiesSource.maxChildren]) and each text value (by
/// [PropertiesSource.maxTextLength]) of the part [part]; a breach throws
/// what [PropertiesSource.limitExceeded] throws.
(XmlRoot?, List<PropertyChild>) _readPart(
  XmlPullReader r,
  String ns,
  String local,
  PropertiesSource? source,
  String part,
) {
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement) break;
  }
  if (r.eventType != XmlEventType.startElement ||
      r.localName != local ||
      r.namespaceUri != ns) {
    return (null, const <PropertyChild>[]);
  }
  final XmlRoot root = XmlRoot.capture(r);
  final int rootDepth = r.depth;
  final List<PropertyChild> children = <PropertyChild>[];
  if (r.isEmptyElement) return (root, children);
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < rootDepth) break;
    if (r.eventType != XmlEventType.startElement) continue;
    if (source != null && children.length >= source.maxChildren) {
      source.limitExceeded(
        part,
        'Limit (${source.maxChildren} entries) exceeded by the entries of a '
        'document properties part.',
      );
    }
    children.add(_readChild(r, source, part));
  }
  return (root, children);
}

PropertyChild _readChild(
  XmlPullReader r,
  PropertiesSource? source,
  String part,
) {
  final bool custom =
      r.localName == 'property' && r.namespaceUri == Ns.customProperties;
  final int startDepth = r.depth;
  final StringBuffer text = StringBuffer();
  int length = 0;
  String? name;
  String? fmtid;
  int? pid;
  String? variant;
  String? variantNamespace;
  var inVariant = false;
  if (custom) {
    name = r.getAttribute('name');
    fmtid = r.getAttribute('fmtid');
    pid = int.tryParse(r.getAttribute('pid') ?? '');
  }
  final OpaqueXml xml = OpaqueXml.capture(
    r,
    onEvent: (XmlPullReader e) {
      switch (e.eventType) {
        case XmlEventType.startElement:
          if (custom && variant == null && e.depth == startDepth + 1) {
            variant = e.localName;
            variantNamespace = e.namespaceUri;
            inVariant = true;
          }
        case XmlEventType.endElement:
          if (custom && inVariant && e.depth < startDepth + 1) {
            inVariant = false;
          }
        case XmlEventType.characters || XmlEventType.cdata:
          if (!custom || inVariant) {
            final String t = e.text;
            length += t.length;
            if (source != null && length > source.maxTextLength) {
              source.limitExceeded(
                part,
                'Limit maxTextLength (${source.maxTextLength}) exceeded by '
                'a document property.',
              );
            }
            text.write(t);
          }
        default:
      }
    },
  );
  return PropertyChild._(
    xml,
    text: text.toString(),
    name: name,
    pid: pid,
    fmtid: fmtid,
    variant: variant,
    variantNamespace: variantNamespace,
  );
}

/// The children of the part rendered by [write], captured.
List<PropertyChild> _rendered(void Function(XmlWriter w) write) {
  final Utf8Buffer out = Utf8Buffer();
  write(XmlWriter(out));
  final XmlPullReader r = XmlPullReader.fromBytes(out.takeBytes());
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement) break;
  }
  final int rootDepth = r.depth;
  final List<PropertyChild> children = <PropertyChild>[];
  if (r.isEmptyElement) return children;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < rootDepth) break;
    if (r.eventType == XmlEventType.startElement) {
      children.add(_readChild(r, null, ''));
    }
  }
  return children;
}

/// The core properties part.
final class CoreProperties extends _PropertiesPart {
  CoreProperties._(super.root, super.children, [PropertyWarn? warn]) {
    _values = _readValues(_coreFields, children, warn);
  }

  /// A part with no children and the writer's root, for a package without
  /// one.
  factory CoreProperties.empty() => CoreProperties._(
    const XmlRoot.of('cp:coreProperties', <String, String>{
      'cp': Ns.core,
      'dc': Ns.dc,
      'dcterms': Ns.dcterms,
      'dcmitype': Ns.dcmitype,
      'xsi': Ns.xsi,
    }),
    const <PropertyChild>[],
  );

  /// A part whose root is not `cp:coreProperties`.
  factory CoreProperties.untyped() =>
      CoreProperties._(null, const <PropertyChild>[]);

  /// Reads the part [part], which [r] walks, within the limits of
  /// [source]; [warn] hears of each value that cannot be read.
  factory CoreProperties.read(
    XmlPullReader r,
    PropertiesSource source,
    String part,
    PropertyWarn warn,
  ) {
    final (XmlRoot? root, List<PropertyChild> children) = _readPart(
      r,
      Ns.core,
      'coreProperties',
      source,
      part,
    );
    return CoreProperties._(root, children, warn);
  }

  late final Map<String, Object?> _values;

  /// These parts with the fields of [next] that differ from [old] changed.
  ///
  /// Returns this part when nothing in it changes. Throws a [StateError]
  /// when a field changes and the part is untyped.
  CoreProperties apply(OfficeProperties old, OfficeProperties next) {
    final List<PropertyChild>? changed = _changedChildren(
      this,
      _coreFields,
      old,
      next,
      (XmlWriter w) => writeCoreProperties(w, next),
    );
    return changed == null ? this : CoreProperties._(_root, changed);
  }
}

/// The extended properties part.
final class AppProperties extends _PropertiesPart {
  AppProperties._(super.root, super.children, [PropertyWarn? warn]) {
    _values = _readValues(_appFields, children, warn);
  }

  /// A part with no children and the writer's root.
  factory AppProperties.empty() => AppProperties._(
    const XmlRoot.of('Properties', <String, String>{'': Ns.extendedProperties}),
    const <PropertyChild>[],
  );

  /// A part whose root is not `Properties` of the extended namespace.
  factory AppProperties.untyped() =>
      AppProperties._(null, const <PropertyChild>[]);

  /// Reads the part [part], which [r] walks, within the limits of
  /// [source]; [warn] hears of each value that cannot be read.
  factory AppProperties.read(
    XmlPullReader r,
    PropertiesSource source,
    String part,
    PropertyWarn warn,
  ) {
    final (XmlRoot? root, List<PropertyChild> children) = _readPart(
      r,
      Ns.extendedProperties,
      'Properties',
      source,
      part,
    );
    return AppProperties._(root, children, warn);
  }

  late final Map<String, Object?> _values;

  /// These parts with the fields of [next] that differ from [old] changed;
  /// see [CoreProperties.apply].
  AppProperties apply(OfficeProperties old, OfficeProperties next) {
    final List<PropertyChild>? changed = _changedChildren(
      this,
      _appFields,
      old,
      next,
      (XmlWriter w) => writeAppProperties(w, next, fallbackApplication: null),
    );
    return changed == null ? this : AppProperties._(_root, changed);
  }

  /// This part with the sheet titles of `TitlesOfParts` edited: the
  /// worksheets slice, which lists [before] (the sheets' names in tab
  /// order), lists [after] instead, and its count in `HeadingPairs` and the
  /// vector `size` follow. When [renamedFrom] is given, every other title
  /// that starts with [renamedFrom]'s prefix (a named range, such as
  /// `Data!Print_Area`; [prefix] gives a sheet's prefix with its `!`, quoted
  /// as Excel quotes it) starts with [renamedTo]'s.
  ///
  /// The worksheets slice is the heading pair `Worksheets` whose titles are
  /// [before], or else the one pair whose titles are. When the two elements
  /// cannot be read together (an unknown shape, counts that disagree with
  /// the titles, no such slice), both are removed: Excel rebuilds them.
  /// This part itself when it has neither element, or is untyped.
  AppProperties withSheetTitles({
    required List<String> before,
    required List<String> after,
    required String Function(String sheet) prefix,
    String? renamedFrom,
    String? renamedTo,
  }) {
    if (!isTyped) return this;
    int find(String local) => children.indexWhere(
      (PropertyChild c) => c.isElement(Ns.extendedProperties, local),
    );
    final int pairsAt = find('HeadingPairs');
    final int titlesAt = find('TitlesOfParts');
    if (pairsAt < 0 && titlesAt < 0) return this;
    List<PropertyChild> without() => <PropertyChild>[
      for (int i = 0; i < children.length; i++)
        if (i != pairsAt && i != titlesAt) children[i],
    ];
    if (pairsAt < 0 || titlesAt < 0) return AppProperties._(_root, without());
    final List<(String, int)>? pairs = _readPairs(children[pairsAt].xml);
    final List<String>? titles = _readTitles(children[titlesAt].xml);
    if (pairs == null || titles == null) {
      return AppProperties._(_root, without());
    }
    int total = 0;
    for (final (String, int) p in pairs) {
      total += p.$2;
    }
    if (total != titles.length) return AppProperties._(_root, without());
    bool isSlice(int pair) {
      int start = 0;
      for (int i = 0; i < pair; i++) {
        start += pairs[i].$2;
      }
      if (pairs[pair].$2 != before.length) return false;
      for (int i = 0; i < before.length; i++) {
        if (titles[start + i] != before[i]) return false;
      }
      return true;
    }

    int slice = -1;
    for (int i = 0; i < pairs.length && slice < 0; i++) {
      if (pairs[i].$1 == 'Worksheets' && isSlice(i)) slice = i;
    }
    for (int i = 0; i < pairs.length && slice < 0; i++) {
      if (isSlice(i)) slice = i;
    }
    if (slice < 0) return AppProperties._(_root, without());
    final List<String> nextTitles = <String>[];
    final List<(String, int)> nextPairs = <(String, int)>[];
    final String? oldPrefix = renamedFrom == null ? null : prefix(renamedFrom);
    int at = 0;
    for (int i = 0; i < pairs.length; i++) {
      final (String name, int count) = pairs[i];
      if (i == slice) {
        nextTitles.addAll(after);
        nextPairs.add((name, after.length));
      } else {
        for (int t = at; t < at + count; t++) {
          final String title = titles[t];
          nextTitles.add(
            oldPrefix != null && title.startsWith(oldPrefix)
                ? '${prefix(renamedTo!)}${title.substring(oldPrefix.length)}'
                : title,
          );
        }
        nextPairs.add((name, count));
      }
      at += count;
    }
    if (_sameTitles(titles, nextTitles) && after.length == before.length) {
      return this;
    }
    final List<PropertyChild> fresh = _rendered((XmlWriter w) {
      w.start('Properties');
      w.attribute('xmlns', Ns.extendedProperties);
      w.attribute('xmlns:vt', Ns.docPropsVTypes);
      w.start('HeadingPairs');
      w.start('vt:vector');
      w.attribute('size', '${nextPairs.length * 2}');
      w.attribute('baseType', 'variant');
      for (final (String name, int count) in nextPairs) {
        w
          ..start('vt:variant')
          ..start('vt:lpstr')
          ..text(name)
          ..end()
          ..end()
          ..start('vt:variant')
          ..start('vt:i4')
          ..text('$count')
          ..end()
          ..end();
      }
      w
        ..end()
        ..end()
        ..start('TitlesOfParts')
        ..start('vt:vector');
      w.attribute('size', '${nextTitles.length}');
      w.attribute('baseType', 'lpstr');
      for (final String title in nextTitles) {
        w
          ..start('vt:lpstr')
          ..text(title)
          ..end();
      }
      w
        ..end()
        ..end()
        ..end();
    });
    return AppProperties._(
      _root,
      List<PropertyChild>.of(children)
        ..[pairsAt] = fresh[0]
        ..[titlesAt] = fresh[1],
    );
  }
}

bool _sameTitles(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A reader over [xml], with the bindings it inherits declared, on the
/// element's start.
XmlPullReader _readerOf(OpaqueXml xml) {
  final Utf8Buffer out = Utf8Buffer();
  final XmlWriter w = XmlWriter(out)..start('wrapper');
  writeNamespaceDeclarations(w, xml.inheritedNamespaces);
  w
    ..raw(xml.xml)
    ..end();
  final XmlPullReader r = XmlPullReader.fromBytes(out.takeBytes());
  int starts = 0;
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement && ++starts == 2) break;
  }
  return r;
}

/// The leaf values of the `vt:` elements under [xml] in order, as (local
/// name, text), or `null` for any other element, or one at another depth
/// than [depth] below [xml].
List<(String, String)>? _leaves(OpaqueXml xml, int depth) {
  final XmlPullReader r;
  try {
    r = _readerOf(xml);
  } on Object {
    return null;
  }
  final int top = r.depth;
  final List<(String, String)> out = <(String, String)>[];
  String? leaf;
  final StringBuffer text = StringBuffer();
  try {
    while (r.next()) {
      if (r.eventType == XmlEventType.endElement && r.depth < top) break;
      switch (r.eventType) {
        case XmlEventType.startElement:
          if (r.namespaceUri != Ns.docPropsVTypes) return null;
          final int d = r.depth - top;
          if (d == depth) {
            leaf = r.localName;
            text.clear();
          } else if (d > depth) {
            return null;
          }
        case XmlEventType.characters || XmlEventType.cdata:
          if (leaf != null) text.write(r.text);
        case XmlEventType.endElement:
          // An end event is at its parent's depth.
          if (leaf != null && r.depth - top == depth - 1) {
            out.add((leaf, text.toString()));
            leaf = null;
          }
        default:
      }
    }
  } on Object {
    return null;
  }
  return out;
}

/// The heading pairs of `HeadingPairs` [xml] (a name, then a count), or
/// `null` for another shape.
List<(String, int)>? _readPairs(OpaqueXml xml) {
  final List<(String, String)>? leaves = _leaves(xml, 3);
  if (leaves == null || leaves.length.isOdd) return null;
  final List<(String, int)> pairs = <(String, int)>[];
  for (int i = 0; i < leaves.length; i += 2) {
    final (String nameKind, String name) = leaves[i];
    final (String countKind, String countText) = leaves[i + 1];
    final int? count = int.tryParse(countText.trim());
    if (nameKind != 'lpstr' && nameKind != 'bstr') return null;
    if (!countKind.startsWith('i') && !countKind.startsWith('ui')) return null;
    if (count == null || count < 0) return null;
    pairs.add((name, count));
  }
  return pairs;
}

/// The titles of `TitlesOfParts` [xml], or `null` for another shape.
List<String>? _readTitles(OpaqueXml xml) {
  final List<(String, String)>? leaves = _leaves(xml, 2);
  if (leaves == null) return null;
  final List<String> titles = <String>[];
  for (final (String kind, String text) in leaves) {
    if (kind != 'lpstr' && kind != 'bstr') return null;
    titles.add(text);
  }
  return titles;
}

/// The value of each field of [fields], read from the first child of its
/// kind; a text that cannot be read is reported to [warn] and reads as
/// `null`.
Map<String, Object?> _readValues(
  List<_Field> fields,
  List<PropertyChild> children,
  PropertyWarn? warn,
) {
  final Map<String, Object?> values = <String, Object?>{};
  for (final _Field field in fields) {
    final int at = children.indexWhere(
      (PropertyChild c) => c.isElement(field.namespace, field.local),
    );
    if (at < 0) continue;
    final String text = children[at].text;
    final Object? Function(String text)? parse = field.parse;
    if (parse == null) {
      values[field.qualified] = text;
      continue;
    }
    final Object? value = parse(text);
    if (value == null) {
      warn?.call(field.qualified);
    } else {
      values[field.qualified] = value;
    }
  }
  return values;
}

/// The children of [part] after the fields of [fields] that differ between
/// [old] and [next] are changed, or `null` when none does.
List<PropertyChild>? _changedChildren(
  _PropertiesPart part,
  List<_Field> fields,
  OfficeProperties old,
  OfficeProperties next,
  void Function(XmlWriter w) render,
) {
  final List<_Field> changed = <_Field>[
    for (final _Field f in fields)
      if (f.get(old) != f.get(next)) f,
  ];
  if (changed.isEmpty) return null;
  if (!part.isTyped) {
    throw StateError(
      'The document properties part is not a properties part, so it cannot '
      'be changed.',
    );
  }
  final List<PropertyChild> fresh = _rendered(render);
  final List<PropertyChild> children = List<PropertyChild>.of(part.children);
  for (final _Field field in changed) {
    final int at = children.indexWhere(
      (PropertyChild c) => c.isElement(field.namespace, field.local),
    );
    final int made = fresh.indexWhere(
      (PropertyChild c) => c.isElement(field.namespace, field.local),
    );
    if (made < 0) {
      if (at >= 0) children.removeAt(at);
    } else if (at >= 0) {
      children[at] = fresh[made];
    } else {
      children.add(fresh[made]);
    }
  }
  return children;
}

/// The custom properties part.
final class CustomProperties extends _PropertiesPart {
  CustomProperties._(super.root, super.children, [PropertyWarn? warn]) {
    final List<_Listed> listed = <_Listed>[];
    final Set<String> seen = <String>{};
    for (int i = 0; i < children.length; i++) {
      final PropertyChild c = children[i];
      if (!c.isElement(Ns.customProperties, 'property')) continue;
      final String? name = c.name;
      if (name == null || c.variantNamespace != Ns.docPropsVTypes) continue;
      final Object? value = _customValue(c, warn);
      if (value == null) continue;
      try {
        checkProperties(
          OfficeProperties(custom: <String, Object>{name: value}),
        );
      } on ArgumentError {
        warn?.call('property');
        continue;
      }
      if (!seen.add(officeNameKey(name))) continue;
      listed.add(_Listed(i, name, value));
    }
    _listed = List<_Listed>.unmodifiable(listed);
  }

  /// A part with no properties and the writer's root.
  factory CustomProperties.empty() => CustomProperties._(
    const XmlRoot.of('Properties', <String, String>{
      '': Ns.customProperties,
      'vt': Ns.docPropsVTypes,
    }),
    const <PropertyChild>[],
  );

  /// A part whose root is not `Properties` of the custom namespace.
  factory CustomProperties.untyped() =>
      CustomProperties._(null, const <PropertyChild>[]);

  /// Reads the part [part], which [r] walks, within the limits of
  /// [source]; [warn] hears of each value that cannot be read.
  factory CustomProperties.read(
    XmlPullReader r,
    PropertiesSource source,
    String part,
    PropertyWarn warn,
  ) {
    final (XmlRoot? root, List<PropertyChild> children) = _readPart(
      r,
      Ns.customProperties,
      'Properties',
      source,
      part,
    );
    return CustomProperties._(root, children, warn);
  }

  /// The listed properties: the first of each name (ignoring case) whose
  /// variant is one of the five the model lists and whose value is valid.
  late final List<_Listed> _listed;

  /// The listed properties, in file order.
  Map<String, Object> get values => <String, Object>{
    for (final _Listed l in _listed) l.name: l.value,
  };

  /// These properties with the custom map [next], which replaces [old].
  ///
  /// A listed property of an equal name and value stays as written (its
  /// `fmtid` and `pid` with it); any other listed property is rendered by
  /// the writer and takes the lowest free `pid` from 2. The properties the
  /// model does not list stay where they were, relative to the listed ones.
  /// Returns this part when the maps are equal; throws a [StateError] when
  /// the part is untyped.
  CustomProperties apply(Map<String, Object> old, Map<String, Object> next) {
    if (_sameMap(old, next)) return this;
    if (!isTyped) {
      throw StateError(
        'The document properties part is not a properties part, so it '
        'cannot be changed.',
      );
    }
    final Map<String, _Listed> byName = <String, _Listed>{
      for (final _Listed l in _listed) l.name: l,
    };
    final Set<int> listedAt = <int>{for (final _Listed l in _listed) l.index};
    // Every child that stays keeps its pid: the unlisted ones and the
    // listed ones reused as they are.
    final Set<int> used = <int>{
      for (int i = 0; i < children.length; i++)
        if (!listedAt.contains(i) && children[i].pid != null) children[i].pid!,
    };
    final List<PropertyChild?> slots = <PropertyChild?>[];
    final List<MapEntry<String, Object>> fresh = <MapEntry<String, Object>>[];
    for (final MapEntry<String, Object> e in next.entries) {
      final _Listed? existing = byName[e.key];
      if (existing != null && existing.value == e.value) {
        final PropertyChild kept = children[existing.index];
        slots.add(kept);
        if (kept.pid != null) used.add(kept.pid!);
      } else {
        slots.add(null);
        fresh.add(e);
      }
    }
    int pid = 2;
    final Iterator<MapEntry<String, Object>> toRender = fresh.iterator;
    for (int i = 0; i < slots.length; i++) {
      if (slots[i] != null) continue;
      toRender.moveNext();
      while (used.contains(pid)) {
        pid++;
      }
      used.add(pid);
      slots[i] = _renderCustom(toRender.current, pid);
    }
    // Merge: an unlisted child follows as many listed ones as it did.
    final List<PropertyChild> result = <PropertyChild>[];
    int listedSoFar = 0;
    int nextSlot = 0;
    for (int i = 0; i < children.length; i++) {
      if (listedAt.contains(i)) {
        listedSoFar++;
        continue;
      }
      while (nextSlot < listedSoFar && nextSlot < slots.length) {
        result.add(slots[nextSlot++]!);
      }
      result.add(children[i]);
    }
    while (nextSlot < slots.length) {
      result.add(slots[nextSlot++]!);
    }
    return CustomProperties._(_root, result);
  }
}

/// A listed custom property: the index of its child, its name and value.
final class _Listed {
  const _Listed(this.index, this.name, this.value);
  final int index;
  final String name;
  final Object value;
}

bool _sameMap(Map<String, Object> a, Map<String, Object> b) {
  if (a.length != b.length) return false;
  final Iterator<MapEntry<String, Object>> i = a.entries.iterator;
  final Iterator<MapEntry<String, Object>> j = b.entries.iterator;
  while (i.moveNext() && j.moveNext()) {
    if (i.current.key != j.current.key || i.current.value != j.current.value) {
      return false;
    }
  }
  return true;
}

/// The writer's `property` element for [entry] with the `pid` [pid].
PropertyChild _renderCustom(MapEntry<String, Object> entry, int pid) {
  final Utf8Buffer out = Utf8Buffer();
  writeCustomProperties(
    XmlWriter(out),
    OfficeProperties(custom: <String, Object>{entry.key: entry.value}),
  );
  // The pid is the writer's 2 and comes before the name, whose quotes are
  // escaped, so the first match is the attribute.
  final String text = utf8
      .decode(out.takeBytes())
      .replaceFirst(' pid="2" ', ' pid="$pid" ');
  final XmlPullReader r = XmlPullReader(text);
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement) break;
  }
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement) break;
  }
  return _readChild(r, null, '');
}

/// The value of a custom property of a variant the model lists, or `null`
/// (reporting a value that cannot be read to [warn]) when it is not one.
Object? _customValue(PropertyChild c, PropertyWarn? warn) {
  final String text = c.text;
  Object? invalid(String variant) {
    warn?.call('vt:$variant');
    return null;
  }

  switch (c.variant) {
    case 'lpwstr':
      return text;
    case 'i4':
      final int? n = int.tryParse(text.trim());
      return n == null || n < -2147483648 || n > 2147483647 ? invalid('i4') : n;
    case 'r8':
      final double? d = double.tryParse(text.trim());
      return d == null || !d.isFinite ? invalid('r8') : d;
    case 'bool':
      return switch (text.trim()) {
        'true' || '1' => true,
        'false' || '0' => false,
        _ => invalid('bool'),
      };
    case 'filetime':
      return parseW3cdtf(text) ?? invalid('filetime');
    default:
      return null;
  }
}

/// The three properties parts of a workbook or a document, held together.
final class PropertyParts {
  /// The parts [core], [app] and [custom].
  PropertyParts(this.core, this.app, this.custom);

  /// The core properties.
  final CoreProperties core;

  /// The extended properties.
  final AppProperties app;

  /// The custom properties.
  final CustomProperties custom;

  /// The properties the parts show, merged into one value.
  late final OfficeProperties merged = OfficeProperties(
    title: core._values['dc:title'] as String?,
    subject: core._values['dc:subject'] as String?,
    creator: core._values['dc:creator'] as String?,
    keywords: core._values['cp:keywords'] as String?,
    description: core._values['dc:description'] as String?,
    lastModifiedBy: core._values['cp:lastModifiedBy'] as String?,
    revision: core._values['cp:revision'] as int?,
    application: app._values['Application'] as String?,
    category: core._values['cp:category'] as String?,
    company: app._values['Company'] as String?,
    manager: app._values['Manager'] as String?,
    contentStatus: core._values['cp:contentStatus'] as String?,
    created: core._values['dcterms:created'] as DateTime?,
    modified: core._values['dcterms:modified'] as DateTime?,
    custom: Map<String, Object>.unmodifiable(custom.values),
  );

  /// The kind of the first part, in the order core, app, custom, that is
  /// untyped (its root is not the properties element of its namespace) and
  /// would have to change for [next]: the part [withProperties] throws for.
  /// `null` when there is none.
  PropertyKind? untypedChange(OfficeProperties next) {
    final OfficeProperties old = merged;
    bool differs(List<_Field> fields) =>
        fields.any((_Field f) => f.get(old) != f.get(next));
    if (!core.isTyped && differs(_coreFields)) return PropertyKind.core;
    if (!app.isTyped && differs(_appFields)) return PropertyKind.app;
    if (!custom.isTyped && !_sameMap(old.custom, next.custom)) {
      return PropertyKind.custom;
    }
    return null;
  }

  /// These parts with [next] set over what they show now; see
  /// [CoreProperties.apply] and [CustomProperties.apply].
  ///
  /// Throws a [StateError] when a part that must change is untyped
  /// ([untypedChange]).
  PropertyParts withProperties(OfficeProperties next) {
    final OfficeProperties old = merged;
    return PropertyParts(
      core.apply(old, next),
      app.apply(old, next),
      custom.apply(old.custom, next.custom),
    );
  }
}

/// The kinds of properties part.
enum PropertyKind {
  /// `docProps/core.xml`.
  core('docProps/core.xml', RelType.coreProperties, ContentType.coreProperties),

  /// `docProps/app.xml`.
  app(
    'docProps/app.xml',
    RelType.extendedProperties,
    ContentType.extendedProperties,
  ),

  /// `docProps/custom.xml`.
  custom(
    'docProps/custom.xml',
    RelType.customProperties,
    ContentType.customProperties,
  );

  const PropertyKind(this.partName, this.relationshipType, this.contentType);

  /// The name the writer gives the part.
  final String partName;

  /// The package relationship that finds the part.
  final String relationshipType;

  /// The part's content type.
  final String contentType;
}

/// The properties of an open workbook or document: the current parts,
/// where they are in the package and what saving must add or remove.
///
/// Loaded once, on first use. The parts of the package are replaced
/// ([swap]) with each edit; the package gains a part that has content and
/// lacks one, and loses a custom part that holds nothing, only at save
/// ([sync]), so an edit, an undo and a save in any order leave the package
/// right.
final class PropertiesState {
  PropertiesState._(
    this._package,
    this._parts,
    this._names,
    this._initial,
    this._asRead,
  );

  /// Reads the three parts of the package of [source], each found by its
  /// relationship in the package root.
  ///
  /// Throws what [source] throws when a part cannot be read; then nothing
  /// is kept and [warn] has heard of nothing. [warn] hears of each value
  /// that cannot be read once; a host that needs the part too gives
  /// [warnInPart] (the part's name and the element), which is then called
  /// instead of [warn].
  ///
  /// With [encodeOnLoad], each typed part loaded is written from the model
  /// from now on (meaning-equal to the file); without it, a loaded part
  /// keeps its bytes until [swap] gives it other parts, and gets them back
  /// when a swap returns to the parts as loaded.
  factory PropertiesState.load(
    PropertiesSource source,
    PropertyWarn warn, {
    bool encodeOnLoad = true,
    void Function(String part, String element)? warnInPart,
  }) {
    final OpcPackage package = source.package;
    final List<OpcRelationship> rels = source.guard(
      '_rels/.rels',
      () => package.relationshipsOf(''),
    );
    final Map<PropertyKind, String?> names = <PropertyKind, String?>{};
    for (final PropertyKind kind in PropertyKind.values) {
      for (final OpcRelationship r in rels) {
        if (r.external || r.type != kind.relationshipType) continue;
        final String? name = package.canonicalPartName(
          package.resolve('', r.target),
        );
        if (name != null) {
          names[kind] = name;
          break;
        }
      }
    }
    final List<(String, String)> problems = <(String, String)>[];
    String? reading;
    void hear(String element) => problems.add((reading!, element));
    T read<T>(
      PropertyKind kind,
      T Function(XmlPullReader r, String name) parse,
      T Function() absent,
    ) {
      final String? name = names[kind];
      if (name == null) return absent();
      reading = name;
      return source.guard(name, () => parse(source.openXml(name), name));
    }

    final CoreProperties core = read<CoreProperties>(
      PropertyKind.core,
      (XmlPullReader r, String name) =>
          CoreProperties.read(r, source, name, hear),
      CoreProperties.empty,
    );
    final AppProperties app = read<AppProperties>(
      PropertyKind.app,
      (XmlPullReader r, String name) =>
          AppProperties.read(r, source, name, hear),
      AppProperties.empty,
    );
    final CustomProperties custom = read<CustomProperties>(
      PropertyKind.custom,
      (XmlPullReader r, String name) =>
          CustomProperties.read(r, source, name, hear),
      CustomProperties.empty,
    );
    final Map<PropertyKind, Uint8List> asRead = <PropertyKind, Uint8List>{
      if (!encodeOnLoad)
        for (final PropertyKind kind in PropertyKind.values)
          if (names[kind] case final String name)
            kind: source.guard(name, () => package.originalBytes(name)),
    };
    for (final (String part, String element) in problems) {
      if (warnInPart != null) {
        warnInPart(part, element);
      } else {
        warn(element);
      }
    }
    final PropertyParts parts = PropertyParts(core, app, custom);
    final PropertiesState state = PropertiesState._(
      package,
      parts,
      names,
      parts,
      asRead,
    );
    if (encodeOnLoad) {
      for (final PropertyKind kind in PropertyKind.values) {
        final String? name = names[kind];
        final PartContent content = state._content(parts, kind);
        if (name != null && (content as _PropertiesPart).isTyped) {
          package.setContent(name, content);
        }
      }
    }
    return state;
  }

  final OpcPackage _package;
  PropertyParts _parts;
  final Map<PropertyKind, String?> _names;

  /// The parts as loaded: a part that is still the one loaded is never
  /// removed, though it holds nothing.
  final PropertyParts _initial;

  /// The bytes of each part loaded, kept when it is not encoded on load;
  /// empty otherwise.
  final Map<PropertyKind, Uint8List> _asRead;

  /// The kinds whose part this state added to the package.
  final Set<PropertyKind> _created = <PropertyKind>{};

  /// The parts now.
  PropertyParts get parts => _parts;

  /// The name of the part of [kind] in the package, or the name the writer
  /// gives it when the package has none.
  String partName(PropertyKind kind) => _names[kind] ?? '/${kind.partName}';

  PartContent _content(PropertyParts parts, PropertyKind kind) =>
      switch (kind) {
        PropertyKind.core => parts.core,
        PropertyKind.app => parts.app,
        PropertyKind.custom => parts.custom,
      };

  /// Makes [next] the current parts, giving each part that is in the
  /// package, typed and different from the current one, its new content.
  ///
  /// A part [next] leaves as it is keeps what the package holds, so a part
  /// kept as stored (without `encodeOnLoad`) stays a copy of its entry.
  void swap(PropertyParts next) {
    final PropertyParts previous = _parts;
    _parts = next;
    for (final PropertyKind kind in PropertyKind.values) {
      final String? name = _names[kind];
      final PartContent content = _content(next, kind);
      if (identical(content, _content(previous, kind))) continue;
      if (name != null && (content as _PropertiesPart).isTyped) {
        final Uint8List? bytes = _asRead[kind];
        _package.setContent(
          name,
          bytes != null && identical(content, _content(_initial, kind))
              ? _Bytes(bytes)
              : content,
        );
      }
    }
  }

  /// Adds to the package each part that has content and is not there, and
  /// removes a custom part that holds nothing (and any part this state added
  /// that holds nothing again), with the relationship and content type of
  /// each; changes nothing else.
  void sync() {
    for (final PropertyKind kind in PropertyKind.values) {
      final _PropertiesPart content = _content(_parts, kind) as _PropertiesPart;
      final String? name = _names[kind];
      if (!content.isTyped) continue;
      if (name == null) {
        if (content.isEmpty) continue;
        final String added = _package.addPart(
          kind.partName,
          kind.contentType,
          content,
        );
        _package.addRelationship(
          '',
          type: kind.relationshipType,
          target: added.substring(1),
        );
        _names[kind] = added;
        _created.add(kind);
      } else if (content.isEmpty &&
          (_created.contains(kind) ||
              (kind == PropertyKind.custom &&
                  !identical(content, _content(_initial, kind))))) {
        _package.removePart(name, sources: const <String>['']);
        _names[kind] = null;
        _created.remove(kind);
      }
    }
  }
}

/// A part's bytes as read.
final class _Bytes implements PartContent {
  _Bytes(this._bytes);

  final Uint8List _bytes;

  @override
  List<Uint8List> encode() => <Uint8List>[_bytes];
}

/// The change of the document properties: the three parts before and after.
final class SetPropertiesChange implements Change {
  /// A change of [state]'s parts from [before] to [after].
  SetPropertiesChange(this.state, this.before, this.after);

  /// The properties of the document.
  final PropertiesState state;

  /// The parts before the change.
  final PropertyParts before;

  /// The parts after the change.
  final PropertyParts after;

  @override
  void revert() => state.swap(before);

  @override
  void reapply() => state.swap(after);
}

/// Sets the document properties of [state] to [value] and records the
/// change in [log]; a [value] equal to what [state] shows changes nothing.
///
/// Must run inside `log.transaction`. Throws an [ArgumentError] for a bad
/// [value] (see `checkProperties`) and a [StateError] when a part that must
/// change is not a properties part; nothing has changed then. If recording
/// throws, the parts are put back as they were before the error leaves.
void setProperties(
  ChangeLog log,
  PropertiesState state,
  OfficeProperties value,
) {
  if (value == state.parts.merged) return;
  checkProperties(value);
  final PropertyParts before = state.parts;
  final PropertyParts after = before.withProperties(value);
  final SetPropertiesChange change = SetPropertiesChange(state, before, after);
  change.reapply();
  try {
    log.record(change);
  } catch (_) {
    change.revert();
    rethrow;
  }
}
