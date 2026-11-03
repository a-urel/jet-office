/// A small typed element tree for the parts of a worksheet the model edits
/// attribute by attribute: `sheetPr` and `sheetViews`.
///
/// Not ported from Quds; written for jet_office.
///
/// An [XmlNode] keeps its name, namespace declarations and attributes as
/// written, and its children in order: an [XmlNode] for the child names a
/// [NodeShape] types, an [OpaqueXml] for everything else (a foreign element,
/// a second `<sheetView>`, an `extLst`). A node is immutable, so an edit
/// replaces it and `WorksheetPart.swapLayout` undoes the edit; the `with...`
/// methods return the node itself when nothing changes, which is how an
/// equal edit is recognised as no edit.
///
/// Text and comments between the elements are not kept; the elements this
/// is used for have none.
library;

import '../../opc/ooxml.dart';
import '../../opc/opaque_xml.dart';
import '../../xml/xml_pull_reader.dart';
import '../../xml/xml_writer.dart';
import 'columns.dart';

/// For each element local name, the local names of its SpreadsheetML
/// children that are read as [XmlNode]s. An element the shape does not list
/// has only opaque children.
typedef NodeShape = Map<String, Set<String>>;

/// One typed element: see the library comment.
final class XmlNode {
  /// An element named [qualifiedName] (local name [localName]).
  const XmlNode(
    this.qualifiedName,
    this.localName,
    this.namespaces,
    this.attributes,
    this.children,
  );

  /// Reads the element the reader [r] is on, a SpreadsheetML element, and
  /// consumes it: afterwards [r] is on the element's end event.
  factory XmlNode.read(XmlPullReader r, NodeShape shape) {
    final String qualifiedName = r.qualifiedName;
    final String localName = r.localName;
    final Map<String, String> namespaces = Map<String, String>.of(
      r.declaredNamespaces,
    );
    final List<KeptAttribute> attributes = keepAttributes(r);
    final List<Object> children = <Object>[];
    if (r.isEmptyElement) {
      r.skip();
    } else {
      final Set<String> typed = shape[localName] ?? const <String>{};
      final int depth = r.depth;
      while (r.next()) {
        if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
        if (r.eventType != XmlEventType.startElement) continue;
        if (r.depth == depth + 1 &&
            r.namespaceUri == Ns.main &&
            typed.contains(r.localName)) {
          children.add(XmlNode.read(r, shape));
        } else {
          children.add(OpaqueXml.capture(r));
        }
      }
    }
    return XmlNode(qualifiedName, localName, namespaces, attributes, children);
  }

  /// A new element [localName] with [prefix] (with its colon, or empty) in
  /// front of its name, holding [attributes] and [children].
  factory XmlNode.made(
    String prefix,
    String localName, {
    Map<String, String> attributes = const <String, String>{},
    List<Object> children = const <Object>[],
  }) => XmlNode(
    '$prefix$localName',
    localName,
    const <String, String>{},
    <KeptAttribute>[
      for (final MapEntry<String, String> a in attributes.entries)
        (qualifiedName: a.key, namespaceUri: '', value: a.value),
    ],
    children,
  );

  /// The element's name with its prefix, as written.
  final String qualifiedName;

  /// The element's local name.
  final String localName;

  /// The namespace declarations of the start tag.
  final Map<String, String> namespaces;

  /// The attributes, in source order.
  final List<KeptAttribute> attributes;

  /// The children in order: [XmlNode] or [OpaqueXml].
  final List<Object> children;

  /// The value of the first attribute without a namespace named [name], or
  /// `null`.
  String? attribute(String name) {
    for (final KeptAttribute a in attributes) {
      if (a.namespaceUri.isEmpty && a.qualifiedName == name) return a.value;
    }
    return null;
  }

  /// The first typed child named [name], or `null`.
  XmlNode? child(String name) {
    for (final Object c in children) {
      if (c is XmlNode && c.localName == name) return c;
    }
    return null;
  }

  /// Whether the element has no attributes and no children.
  bool get isBare => attributes.isEmpty && children.isEmpty;

  /// This element with [changes] applied to its attributes as
  /// [replaceAttributes] does; this element itself when nothing changes.
  ///
  /// An attribute the element lacks is added after the others, or before
  /// the attribute named [addBefore] when the element has it (the schema
  /// puts `workbookViewId` after the flags of a `sheetView`).
  XmlNode withChanges(Map<String, String?> changes, {String? addBefore}) {
    final Set<String> present = <String>{
      for (final KeptAttribute a in attributes)
        if (a.namespaceUri.isEmpty) a.qualifiedName,
    };
    List<KeptAttribute> next = replaceAttributes(attributes, <String, String?>{
      for (final MapEntry<String, String?> c in changes.entries)
        if (present.contains(c.key)) c.key: c.value,
    });
    final List<KeptAttribute> added = <KeptAttribute>[
      for (final MapEntry<String, String?> c in changes.entries)
        if (!present.contains(c.key) && c.value != null)
          (qualifiedName: c.key, namespaceUri: '', value: c.value!),
    ];
    if (added.isNotEmpty) {
      final int at = next.indexWhere(
        (KeptAttribute a) =>
            a.namespaceUri.isEmpty && a.qualifiedName == addBefore,
      );
      next = at < 0
          ? <KeptAttribute>[...next, ...added]
          : <KeptAttribute>[...next.take(at), ...added, ...next.skip(at)];
    }
    return sameAttributes(attributes, next)
        ? this
        : XmlNode(qualifiedName, localName, namespaces, next, children);
  }

  /// This element holding [next] as its children.
  XmlNode withChildren(List<Object> next) =>
      XmlNode(qualifiedName, localName, namespaces, attributes, next);

  /// This element with the child [old] replaced by [replacement], or
  /// removed when [replacement] is `null`.
  XmlNode replacingChild(XmlNode old, XmlNode? replacement) {
    final List<Object> next = <Object>[];
    for (final Object c in children) {
      if (identical(c, old)) {
        if (replacement != null) next.add(replacement);
      } else {
        next.add(c);
      }
    }
    return withChildren(next);
  }

  /// This element with [child] added before the first child that [order]
  /// (local names, schema order) puts after it, else last.
  XmlNode withChildInOrder(XmlNode child, List<String> order) {
    final int rank = order.indexOf(child.localName);
    int at = children.length;
    for (int i = 0; i < children.length; i++) {
      final Object c = children[i];
      final String name = c is XmlNode
          ? c.localName
          : (c as OpaqueXml).localName;
      if (order.indexOf(name) > rank) {
        at = i;
        break;
      }
    }
    return withChildren(<Object>[
      ...children.take(at),
      child,
      ...children.skip(at),
    ]);
  }

  /// Writes the element. [above] holds the bindings in scope where it goes.
  void writeTo(XmlWriter w, Map<String, String> above) {
    w.start(qualifiedName);
    writeNamespaceDeclarations(w, namespaces);
    final Map<String, String> inner = mergeNamespaces(above, namespaces);
    writeKeptAttributes(w, attributes, declaredAbove: inner);
    for (final Object c in children) {
      if (c is XmlNode) {
        c.writeTo(w, inner);
      } else {
        (c as OpaqueXml).writeTo(w, declaredAbove: inner);
      }
    }
    w.end();
  }

  /// The element alone, without its children, as a document of its own in
  /// the SpreadsheetML default namespace, so a reader of one element (such
  /// as `readColor`) can read it whatever prefix the worksheet uses.
  String leafXml() {
    final StringBuffer out = StringBuffer();
    final XmlWriter w = XmlWriter(out)
      ..start(localName)
      ..attribute('xmlns', Ns.main);
    writeKeptAttributes(w, attributes);
    w.end();
    return out.toString();
  }
}
