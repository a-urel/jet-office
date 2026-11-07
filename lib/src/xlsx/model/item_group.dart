/// A worksheet or workbook element that holds a list of entries, each kept
/// as written with a typed value read from it, and the two bridges between
/// the phase 1 element writers and that form.
///
/// Not ported from Quds; written for jet_office.
///
/// An [ItemGroup] is `<dataValidations>`, `<hyperlinks>`, `<definedNames>`
/// and the like: its name, declarations and attributes as written, and its
/// children as [GroupItem]s in file order. Every item keeps its element as an
/// [OpaqueXml], so writing a group is writing its sources, and an entry the
/// model cannot read stays where it is. A group is immutable: an edit makes a
/// new one with [ItemGroup.withItems], and the slot of its part swaps it, so
/// an undo restores it exactly.
///
/// [renderElements] turns what a phase 1 writer writes into [OpaqueXml]s, so
/// a new entry is the writer's own element and the model forks no writer.
/// [readerOf] is the way back: a reader over one kept element, for a typed
/// read of it.
///
/// Text and comments between the items are not kept; the elements this is
/// used for have none.
library;

import '../../opc/ooxml.dart';
import '../../opc/opaque_xml.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import '../../xml/xml_writer.dart';
import '../read/read_exception.dart';
import '../read/read_limits.dart';
import 'columns.dart';

/// One child of an [ItemGroup].
final class GroupItem<T> {
  /// An item reading as [value], kept as [source].
  const GroupItem(this.value, this.source, {this.counted = true});

  /// The typed entry, or `null` for an element that is kept but not typed:
  /// an entry that cannot be read, or a child of another kind.
  final T? value;

  /// The element, as read or as the writer rendered it.
  final OpaqueXml source;

  /// Whether the element is an entry of the group (readable or not), which
  /// the group's `count` counts.
  final bool counted;
}

/// A group element: see the library comment.
///
/// An untouched group is written as it was, a wrong `count` included; once
/// [withItems] edits it, [writeTo] recomputes the count.
final class ItemGroup<T> {
  /// A group named [qualifiedName] (local name [localName]) holding [items].
  const ItemGroup(
    this.qualifiedName,
    this.localName,
    this.namespaces,
    this.attributes,
    this.items, {
    this.edited = false,
  });

  /// The element's name with its prefix, as written.
  final String qualifiedName;

  /// The element's local name.
  final String localName;

  /// The namespace declarations of the start tag.
  final Map<String, String> namespaces;

  /// The attributes, `count` included, as written.
  final List<KeptAttribute> attributes;

  /// The children, in source order.
  final List<GroupItem<T>> items;

  /// Whether the count is recomputed on save.
  final bool edited;

  /// The typed entries, in file order.
  List<T> get values => <T>[
    for (final GroupItem<T> i in items)
      if (i.value != null) i.value as T,
  ];

  /// This group holding [next], with the count recomputed on save.
  ItemGroup<T> withItems(List<GroupItem<T>> next) => ItemGroup<T>(
    qualifiedName,
    localName,
    namespaces,
    attributes,
    next,
    edited: true,
  );

  /// Writes the element to [w]. [above] holds the bindings in scope where it
  /// goes.
  ///
  /// [countAttribute] names the attribute that counts the entries: an edited
  /// group sets it to the number of its [GroupItem.counted] items. A group
  /// that was not edited, or `null` here, writes its attributes as they are.
  void writeTo(
    XmlWriter w,
    Map<String, String> above, {
    String? countAttribute,
  }) {
    w.start(qualifiedName);
    writeNamespaceDeclarations(w, namespaces);
    final Map<String, String> inner = mergeNamespaces(above, namespaces);
    writeKeptAttributes(
      w,
      edited && countAttribute != null
          ? replaceAttributes(attributes, <String, String?>{
              countAttribute:
                  '${items.where((GroupItem<T> i) => i.counted).length}',
            })
          : attributes,
      declaredAbove: inner,
    );
    for (final GroupItem<T> item in items) {
      item.source.writeTo(w, declaredAbove: inner);
    }
    w.end();
  }
}

/// Checks that a list of [count] items may take one more under [limits].
///
/// A small part could otherwise list millions of entries, each a kept
/// element. Throws a `limitExceeded` [XlsxReadException] naming `maxMerges`
/// and [part] when it may not.
void checkListRoom(int count, XlsxReadLimits limits, String part) {
  if (count >= limits.maxMerges) {
    throw XlsxReadException(
      XlsxReadFailure.limitExceeded,
      'Limit maxMerges (${limits.maxMerges}) exceeded.',
      part: part,
    );
  }
}

/// Reads the group element the current event of [r] starts and consumes it:
/// afterwards [r] is on the element's end event.
///
/// A direct SpreadsheetML child named [childName] is an entry: [read] gives
/// its value, or a problem for [warn], and the element is kept either way
/// and counted. Any other child is kept, not counted and not read. Throws a
/// `limitExceeded` [XlsxReadException] naming `maxMerges` and [part] when
/// the group holds more children of any kind than [limits] allows.
ItemGroup<T> readItemGroup<T>(
  XmlPullReader r, {
  required String childName,
  required XlsxReadLimits limits,
  required String part,
  required ({T? value, String? problem}) Function(OpaqueXml child) read,
  required void Function(String problem) warn,
}) {
  final String qualifiedName = r.qualifiedName;
  final String localName = r.localName;
  final Map<String, String> namespaces = Map<String, String>.of(
    r.declaredNamespaces,
  );
  final List<KeptAttribute> attributes = keepAttributes(r);
  final List<GroupItem<T>> items = <GroupItem<T>>[];
  if (r.isEmptyElement) {
    r.skip();
  } else {
    final int depth = r.depth;
    while (r.next()) {
      if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
      if (r.eventType != XmlEventType.startElement) continue;
      checkListRoom(items.length, limits, part);
      final bool entry =
          r.depth == depth + 1 &&
          r.namespaceUri == Ns.main &&
          r.localName == childName;
      final OpaqueXml source = OpaqueXml.capture(r);
      if (!entry) {
        items.add(GroupItem<T>(null, source, counted: false));
        continue;
      }
      final ({T? value, String? problem}) result = read(source);
      final String? problem = result.problem;
      if (problem != null) warn(problem);
      items.add(GroupItem<T>(result.value, source));
    }
  }
  return ItemGroup<T>(qualifiedName, localName, namespaces, attributes, items);
}

/// The elements [write] writes, each captured as an [OpaqueXml].
///
/// [write] runs inside a wrapper that binds the default namespace to
/// SpreadsheetML and `r` to the relationships namespace, as the writer's
/// root does, or binds [namespaces] when given. Each element records the bindings it uses, so
/// [OpaqueXml.writeTo] declares the ones its new parent lacks, and writes
/// none under a parent that has them.
List<OpaqueXml> renderElements(
  void Function(XmlWriter w) write, {
  Map<String, String> namespaces = const <String, String>{
    '': Ns.main,
    'r': Ns.rel,
  },
}) {
  final StringBuffer out = StringBuffer();
  final XmlWriter w = XmlWriter(out)..start('wrapper');
  writeNamespaceDeclarations(w, namespaces);
  write(w);
  w.end();
  final XmlPullReader r = XmlPullReader(out.toString())..next();
  final List<OpaqueXml> elements = <OpaqueXml>[];
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement) {
      elements.add(OpaqueXml.capture(r));
    }
  }
  return elements;
}

/// A reader over [element], on its start, with the bindings the element
/// inherited in scope, so a prefix an ancestor declared resolves as it did.
///
/// The element was read under the file's depth limit, so none applies here.
XmlPullReader readerOf(OpaqueXml element) =>
    _readerOver(element.inheritedNamespaces, element.xml);

/// [xml], an edited copy of [element]'s text, as an element with the
/// bindings [element] inherited in scope.
OpaqueXml rewrittenElement(OpaqueXml element, String xml) =>
    OpaqueXml.capture(_readerOver(element.inheritedNamespaces, xml));

XmlPullReader _readerOver(Map<String, String> namespaces, String xml) {
  final StringBuffer out = StringBuffer('<wrapper');
  namespaces.forEach((String prefix, String uri) {
    out
      ..write(prefix.isEmpty ? ' xmlns="' : ' xmlns:$prefix="')
      ..write(escapeXmlAttribute(scrubXmlText(uri).text))
      ..write('"');
  });
  out
    ..write('>')
    ..write(xml)
    ..write('</wrapper>');
  return XmlPullReader(out.toString(), maxDepth: 0x7FFFFFFF)
    ..next()
    ..next();
}
