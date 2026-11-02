/// XML a model does not type, kept as the exact source text.
///
/// Not ported from Quds; written for jet_office.
///
/// A reader walks a part with `XmlPullReader`, types the elements it knows and
/// calls [OpaqueXml.capture] on the rest, so they are written back at their
/// position. [keepAttributes] does the same for unknown attributes and
/// [XmlRoot] for the root element's namespace declarations and attributes
/// (`mc:Ignorable` among them).
///
/// A captured slice may use a prefix that an ancestor declared. [OpaqueXml]
/// records those bindings and [OpaqueXml.writeTo] declares the ones the new
/// parent does not, so the slice stays well-formed and means the same.
library;

import '../xml/xml_escape.dart';
import '../xml/xml_pull_reader.dart';
import '../xml/xml_writer.dart';

/// An attribute kept without being typed.
typedef KeptAttribute = ({
  String qualifiedName,
  String namespaceUri,
  String value,
});

/// The attributes of the current start element of [r], in source order.
///
/// [except] holds the local names of attributes without a namespace that a
/// typed reader owns; they are left out, and so is every `xmlns` declaration.
/// A prefixed attribute is never matched by [except].
List<KeptAttribute> keepAttributes(
  XmlPullReader r, {
  Set<String> except = const <String>{},
}) {
  final List<KeptAttribute> kept = <KeptAttribute>[];
  for (int i = 0; i < r.attributeCount; i++) {
    final String name = r.attributeQualifiedName(i);
    if (name == 'xmlns' || name.startsWith('xmlns:')) {
      continue;
    }
    if (r.attributePrefix(i).isEmpty && except.contains(name)) {
      continue;
    }
    kept.add((
      qualifiedName: name,
      namespaceUri: r.attributeNamespace(i),
      value: r.attributeValue(i),
    ));
  }
  return kept;
}

/// Writes [attributes] on the start tag open on [w], in order.
///
/// [declaredAbove] holds the bindings in scope where the element goes,
/// prefix to URI. A prefixed attribute whose prefix it lacks (or binds to
/// another URI) gets `xmlns:prefix="uri"` written before it, once per
/// prefix, since [keepAttributes] does not keep declarations. An attribute
/// without a prefix needs none, and the `xml` prefix is never declared. A
/// character XML forbids in a value, which only a character reference in
/// the source can have put there, is dropped.
void writeKeptAttributes(
  XmlWriter w,
  List<KeptAttribute> attributes, {
  Map<String, String> declaredAbove = const {},
}) {
  Set<String>? declared;
  for (final KeptAttribute a in attributes) {
    final int colon = a.qualifiedName.indexOf(':');
    if (colon > 0) {
      final String prefix = a.qualifiedName.substring(0, colon);
      if (prefix != 'xml' &&
          declaredAbove[prefix] != a.namespaceUri &&
          (declared ??= <String>{}).add(prefix)) {
        w.attribute('xmlns:$prefix', scrubXmlText(a.namespaceUri).text);
      }
    }
    w.attribute(a.qualifiedName, scrubXmlText(a.value).text);
  }
}

/// An element and everything inside it, kept as written.
final class OpaqueXml {
  const OpaqueXml._(
    this.xml,
    this.localName,
    this.namespaceUri,
    this.inheritedNamespaces,
  );

  /// Captures the element the current event of [r] starts, and consumes it:
  /// afterwards [r] is on the element's end event, so the next event is what
  /// follows it.
  ///
  /// [r] must be on a start element; anything else throws [StateError].
  factory OpaqueXml.capture(XmlPullReader r) {
    if (r.eventType != XmlEventType.startElement) {
      throw StateError('OpaqueXml.capture needs a start element.');
    }
    final int start = r.eventStart;
    final String localName = r.localName;
    final String namespaceUri = r.namespaceUri;
    final int startDepth = r.depth;
    final Map<String, String> inherited = <String, String>{};
    // The prefixes each open element of the slice declares, innermost last.
    final List<Set<String>> declared = <Set<String>>[];

    void visit() {
      declared.add(r.declaredNamespaces.keys.toSet());
      _inherit(r.prefix, r, declared, inherited);
      for (int i = 0; i < r.attributeCount; i++) {
        final String name = r.attributeQualifiedName(i);
        if (name == 'xmlns' || name.startsWith('xmlns:')) {
          continue;
        }
        final String prefix = r.attributePrefix(i);
        if (prefix.isNotEmpty) {
          _inherit(prefix, r, declared, inherited);
        }
      }
    }

    visit();
    int end;
    if (r.isEmptyElement) {
      end = r.eventEnd;
      r.next();
    } else {
      while (true) {
        if (!r.next()) {
          throw StateError('The document ended inside the element.');
        }
        if (r.eventType == XmlEventType.startElement) {
          visit();
        } else if (r.eventType == XmlEventType.endElement) {
          if (r.depth < startDepth) {
            end = r.eventEnd;
            break;
          }
          if (declared.isNotEmpty) {
            declared.removeLast();
          }
        }
      }
    }
    return OpaqueXml._(
      r.sourceText(start, end),
      localName,
      namespaceUri,
      Map<String, String>.unmodifiable(inherited),
    );
  }

  /// The element as written in the source, from `<` to the end of its closing
  /// tag.
  final String xml;

  /// The element's local name.
  final String localName;

  /// The element's namespace URI, or the empty string.
  final String namespaceUri;

  /// The bindings, prefix to URI (`''` for the default namespace), that the
  /// element's ancestors declared and that the slice uses in an element or
  /// attribute name without declaring them itself.
  final Map<String, String> inheritedNamespaces;

  /// Writes the element to [w].
  ///
  /// [declaredAbove] holds the bindings already in scope where the element
  /// goes. The ones in [inheritedNamespaces] that it lacks (or binds to
  /// another URI) are declared on the element's start tag; with none missing
  /// the slice is written unchanged.
  void writeTo(XmlWriter w, {Map<String, String> declaredAbove = const {}}) {
    final StringBuffer missing = StringBuffer();
    inheritedNamespaces.forEach((String prefix, String uri) {
      if (declaredAbove[prefix] == uri) {
        return;
      }
      missing
        ..write(prefix.isEmpty ? ' xmlns="' : ' xmlns:$prefix="')
        ..write(escapeXmlAttribute(uri))
        ..write('"');
    });
    if (missing.isEmpty) {
      w.raw(xml);
      return;
    }
    // The start tag's name ends at the first space, `/` or `>`.
    int at = 1;
    while (at < xml.length) {
      final int c = xml.codeUnitAt(at);
      if (c == 0x20 ||
          c == 0x09 ||
          c == 0x0A ||
          c == 0x0D ||
          c == 0x2F ||
          c == 0x3E) {
        break;
      }
      at++;
    }
    w.raw('${xml.substring(0, at)}$missing${xml.substring(at)}');
  }
}

/// Records the binding of [prefix] in [inherited] when no open element of the
/// slice declares it and the document does.
void _inherit(
  String prefix,
  XmlPullReader r,
  List<Set<String>> declared,
  Map<String, String> inherited,
) {
  if (prefix == 'xml' || prefix == 'xmlns' || inherited.containsKey(prefix)) {
    return;
  }
  for (final Set<String> own in declared) {
    if (own.contains(prefix)) {
      return;
    }
  }
  final String? uri = r.namespacesInScope[prefix];
  if (uri != null) {
    inherited[prefix] = uri;
  }
}

/// The start tag of a part's root element: its name, namespace declarations
/// and other attributes.
final class XmlRoot {
  const XmlRoot._(this.qualifiedName, this.namespaces, this.attributes);

  /// Captures the root element's start tag the current event of [r] is on.
  /// [r] stays on it; nothing is consumed.
  ///
  /// [r] must be on a start element; anything else throws [StateError].
  factory XmlRoot.capture(XmlPullReader r) {
    if (r.eventType != XmlEventType.startElement) {
      throw StateError('XmlRoot.capture needs a start element.');
    }
    return XmlRoot._(
      r.qualifiedName,
      Map<String, String>.unmodifiable(r.declaredNamespaces),
      List<KeptAttribute>.unmodifiable(keepAttributes(r)),
    );
  }

  /// The element name as written, with its prefix.
  final String qualifiedName;

  /// The namespaces the root declares, prefix to URI (`''` for the default).
  final Map<String, String> namespaces;

  /// The root's other attributes, such as `mc:Ignorable`.
  final List<KeptAttribute> attributes;

  /// Opens the root on [w]: the name, the declarations, then the attributes.
  /// The caller writes the content and ends the element.
  void writeStart(XmlWriter w) {
    w.start(qualifiedName);
    namespaces.forEach((String prefix, String uri) {
      w.attribute(prefix.isEmpty ? 'xmlns' : 'xmlns:$prefix', uri);
    });
    for (final KeptAttribute a in attributes) {
      w.attribute(a.qualifiedName, a.value);
    }
  }
}

/// Writes `xmlns` declarations for [namespaces], prefix to URI (`''` for the
/// default namespace), on the start tag open on [w].
void writeNamespaceDeclarations(XmlWriter w, Map<String, String> namespaces) {
  namespaces.forEach((String prefix, String uri) {
    w.attribute(prefix.isEmpty ? 'xmlns' : 'xmlns:$prefix', uri);
  });
}

/// The bindings of [a] with those of [b] on top, as in scope inside an
/// element that declares [b] under a parent where [a] is in scope.
Map<String, String> mergeNamespaces(
  Map<String, String> a,
  Map<String, String> b,
) => b.isEmpty ? a : <String, String>{...a, ...b};
