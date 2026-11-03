/// Property containers, `w:pPr` and `w:rPr`, that keep what they do not
/// type and write their children in schema order.
///
/// Not ported from Quds; written for jet_office.
///
/// A reader types a few children of a container (in D1, `w:pStyle` of a
/// paragraph and `w:rStyle` of a run, each with its `w:val`) and keeps the
/// rest as [OpaqueXml], with the container's own attributes. A writer then
/// merges its typed children with the kept ones in the order the schema
/// gives (`pPrOrder` and `rPrOrder`), because Word repairs a document whose
/// property children are out of that order.
///
/// Children are matched by namespace URI and local name, never by prefix:
/// a `w14:shadow` is not the schema's `w:shadow`.
library;

import '../opc/ooxml.dart' show Ns;
import '../opc/opaque_xml.dart';
import '../xml/xml_escape.dart';
import '../xml/xml_pull_reader.dart';
import '../xml/xml_writer.dart';

/// Writes `<qualifiedName w:val="value"/>`, the shape of `w:pStyle`,
/// `w:rStyle` and other single-value properties.
///
/// The attribute is written as `w:val`, so `w` must be bound to the
/// WordprocessingML namespace where the element goes. A character XML
/// forbids is removed from [value].
void writeValElement(XmlWriter w, String qualifiedName, String value) {
  w.start(qualifiedName);
  w.attribute('w:val', scrubXmlText(value).text);
  w.end();
}

/// One child of a container as it was read: typed (only its local name is
/// recorded, for the position of the kept children after it) or kept.
final class _Slot {
  const _Slot.typed(String this.typedName) : kept = null;

  const _Slot.kept(OpaqueXml this.kept) : typedName = null;

  /// The local name of a typed child, in `w:`; `null` for a kept one.
  final String? typedName;

  /// The kept child; `null` for a typed one.
  final OpaqueXml? kept;
}

/// The children and attributes of a `w:pPr` or `w:rPr` that a model does not
/// type, ready to be written back with the typed ones in schema order.
final class PropertyContainer {
  /// A container that keeps nothing, for properties written from scratch.
  const PropertyContainer.empty()
    : namespaces = const <String, String>{},
      attributes = const <KeptAttribute>[],
      kept = const <OpaqueXml>[],
      _slots = const <_Slot>[];

  PropertyContainer._(this.namespaces, this.attributes, this._slots)
    : kept = List<OpaqueXml>.unmodifiable(<OpaqueXml>[
        for (final _Slot s in _slots)
          if (s.kept != null) s.kept!,
      ]);

  /// Reads the container whose start element the current event of [r] is,
  /// and consumes it: afterwards [r] is on the container's end event.
  ///
  /// A child in the WordprocessingML namespace whose local name is in
  /// [typed] is handed to [onTyped] with [r] on its start element;
  /// [onTyped] must leave [r] on that child's end event (`r.skip()` does).
  /// Every other child is kept as [OpaqueXml], and the container's
  /// attributes are kept as well. Character data and comments between the
  /// children are dropped.
  ///
  /// [r] must be on a start element; anything else throws [StateError].
  factory PropertyContainer.read(
    XmlPullReader r, {
    required Set<String> typed,
    required void Function(String localName, XmlPullReader r) onTyped,
  }) {
    if (r.eventType != XmlEventType.startElement) {
      throw StateError('PropertyContainer.read needs a start element.');
    }
    final Map<String, String> namespaces = Map<String, String>.unmodifiable(
      r.declaredNamespaces,
    );
    final List<KeptAttribute> attributes = List<KeptAttribute>.unmodifiable(
      keepAttributes(r),
    );
    final List<_Slot> slots = <_Slot>[];
    if (r.isEmptyElement) {
      r.next();
      return PropertyContainer._(namespaces, attributes, slots);
    }
    final int depth = r.depth;
    while (r.next()) {
      final XmlEventType type = r.eventType;
      if (type == XmlEventType.endElement && r.depth < depth) {
        break;
      }
      if (type != XmlEventType.startElement || r.depth != depth + 1) {
        continue;
      }
      final String localName = r.localName;
      if (r.namespaceUri == Ns.w && typed.contains(localName)) {
        slots.add(_Slot.typed(localName));
        onTyped(localName, r);
      } else {
        slots.add(_Slot.kept(OpaqueXml.capture(r)));
      }
    }
    return PropertyContainer._(namespaces, attributes, slots);
  }

  /// The namespaces the container element declared, prefix to URI.
  final Map<String, String> namespaces;

  /// The container element's attributes, in source order.
  final List<KeptAttribute> attributes;

  /// The children kept untyped, in input order.
  final List<OpaqueXml> kept;

  /// Every child in input order, typed ones by name.
  final List<_Slot> _slots;

  /// Whether the container keeps no attribute and no child.
  bool get isEmpty => attributes.isEmpty && kept.isEmpty;

  /// Writes the container as [qualifiedName], with [typed] and the kept
  /// children merged in [order] (`pPrOrder` or `rPrOrder`).
  ///
  /// [typed] maps a local name in [order] to the function that writes that
  /// child; a name outside [order] throws [ArgumentError]. The merge:
  ///
  /// * A kept child in the WordprocessingML namespace whose local name is in
  ///   [order] is written at its slot in [order]; several of one name keep
  ///   their input order. One whose name is in [typed] is dropped: the typed
  ///   child replaces it.
  /// * Any other kept child (another namespace, such as `w14:`, or a name
  ///   the schema lacks) follows the child that preceded it in the input:
  ///   kept, typed, or the typed child that replaced it. When that child is
  ///   a typed one no longer written, the one before it counts; with none,
  ///   the kept child is written first.
  ///
  /// [declaredAbove] holds the bindings in scope where the container goes;
  /// a kept child or attribute declares the ones it needs and lacks.
  void writeTo(
    XmlWriter w,
    String qualifiedName,
    List<String> order,
    Map<String, void Function(XmlWriter)> typed, {
    Map<String, String> declaredAbove = const <String, String>{},
  }) {
    for (final String name in typed.keys) {
      if (!order.contains(name)) {
        throw ArgumentError.value(
          name,
          'typed',
          'Not a child of $qualifiedName in schema order',
        );
      }
    }
    final Set<String> inOrder = order.toSet();
    bool inSchema(OpaqueXml k) =>
        k.namespaceUri == Ns.w && inOrder.contains(k.localName);

    // Kept schema children by local name, and the kept children that follow
    // each anchor: null for the start, a slot index or a typed name.
    final Map<String, List<int>> byName = <String, List<int>>{};
    final Map<Object?, List<int>> followers = <Object?, List<int>>{};
    for (int i = 0; i < _slots.length; i++) {
      final OpaqueXml? k = _slots[i].kept;
      if (k == null) {
        continue;
      }
      if (inSchema(k)) {
        byName.putIfAbsent(k.localName, () => <int>[]).add(i);
      } else {
        followers
            .putIfAbsent(_anchorOf(i, typed, inSchema), () => <int>[])
            .add(i);
      }
    }

    final Map<String, String> inner = mergeNamespaces(
      declaredAbove,
      namespaces,
    );
    void writeFollowers(Object? anchor) {
      final List<int>? after = followers[anchor];
      if (after == null) {
        return;
      }
      for (final int i in after) {
        _slots[i].kept!.writeTo(w, declaredAbove: inner);
        writeFollowers(i);
      }
    }

    w.start(qualifiedName);
    writeNamespaceDeclarations(w, namespaces);
    writeKeptAttributes(w, attributes, declaredAbove: inner);
    writeFollowers(null);
    for (final String name in order) {
      final void Function(XmlWriter)? writeTyped = typed[name];
      if (writeTyped != null) {
        writeTyped(w);
        writeFollowers(name);
        continue;
      }
      final List<int>? slots = byName[name];
      if (slots == null) {
        continue;
      }
      for (final int i in slots) {
        _slots[i].kept!.writeTo(w, declaredAbove: inner);
        writeFollowers(i);
      }
    }
    w.end();
  }

  /// The anchor of the kept child at [index] that is not in the schema: the
  /// nearest child before it that is written, as a slot index (a kept child)
  /// or a typed name (a typed child, or the one replacing a kept child), or
  /// `null` when none is.
  Object? _anchorOf(
    int index,
    Map<String, void Function(XmlWriter)> typed,
    bool Function(OpaqueXml) inSchema,
  ) {
    for (int j = index - 1; j >= 0; j--) {
      final _Slot s = _slots[j];
      final OpaqueXml? k = s.kept;
      if (k == null) {
        if (typed.containsKey(s.typedName)) {
          return s.typedName;
        }
        continue;
      }
      if (inSchema(k) && typed.containsKey(k.localName)) {
        return k.localName;
      }
      return j;
    }
    return null;
  }
}
