/// Property containers, such as `w:pPr` and `w:rPr`, that keep every child
/// as read, type a view of some, and write their children in schema order.
///
/// Not ported from Quds; written for jet_office.
///
/// A [ContainerSchema] gives a container's children in schema order, the
/// [PropertyCodec] of each child the model types, and the children that are
/// containers of their own (`w:pPr` in a `w:style`). [PropertyContainer.read]
/// keeps every child as [OpaqueXml], with the container's own attributes;
/// a typed child also gets a *view*, its value, when it is in `w:`, occurs
/// once, has no `w:` attribute its codec does not understand, and parses
/// (plan Ruling 2). A child with no view is still written exactly as read,
/// so `<w:b w:val="on"/>` stays `w:val="on"` until bold is set.
///
/// [PropertyContainer.writeTo] merges the kept children with the values set
/// (`overrides`) in the schema's order, because Word repairs a document
/// whose property children are out of that order. A value set replaces
/// every child of its name at its slot; `null` removes them, and
/// [valueRemoved] removes the value but keeps what its codec keeps of the
/// child.
///
/// Children are matched by namespace URI and local name, never by prefix:
/// a `w14:shadow` is not the schema's `w:shadow`.
///
/// A child that repeats (`w:headerReference` of a `w:sectPr`) is a
/// *repeated* child of its schema: each occurrence gets a view of its own
/// ([PropertyContainer.repeatedViewsOf], `null` for one the codec cannot
/// type), and a set writes the occurrences it lists, each as read
/// ([RepeatedKept]) or as a value the codec writes, in place of all of them.
///
/// The schema of a paragraph's `w:pPr`, `paragraphPropertiesSchema`, is in
/// `paragraph_property_codecs.dart`; the run's, `runPropertiesSchema`, is in
/// `run_property_codecs.dart`.
library;

import '../opc/ooxml.dart' show Ns;
import '../opc/opaque_xml.dart';
import '../xml/xml_pull_reader.dart';
import '../xml/xml_writer.dart';
import 'property_codec.dart';

/// The children of a container in schema order, the codecs of the typed
/// ones and the schemas of the nested containers.
final class ContainerSchema {
  /// A schema of the children [order] (a list of `schema_order.dart`),
  /// typing the children [codecs] names and reading those [nested] names
  /// as containers of their own.
  ///
  /// Every name in [codecs], [nested] and [repeated] must be in [order],
  /// and none in two of them; `test/docx/container_order_test.dart` checks every schema the
  /// library defines.
  const ContainerSchema(
    this.order, {
    this.codecs = const <String, PropertyCodec<Object>>{},
    this.nested = const <String, ContainerSchema>{},
    this.repeated = const <String, PropertyCodec<Object>>{},
  });

  /// The local names of the children, in `w:`, in schema order.
  final List<String> order;

  /// The codec of each typed child, by local name.
  final Map<String, PropertyCodec<Object>> codecs;

  /// The schema of each child read as a container of its own, by local
  /// name, such as `pPr` and `rPr` in a `w:style`.
  final Map<String, ContainerSchema> nested;

  /// The codec of each child that may occur several times, by local name,
  /// such as `headerReference` in a `w:sectPr`. Each occurrence is typed on
  /// its own; none is a [codecs] child. The schema lets them mix (Word writes
  /// headers and footers in turn), so those read keep their order among
  /// themselves, at the place of the first name of [order] that is repeated.
  final Map<String, PropertyCodec<Object>> repeated;
}

/// An entry of a repeated child's list that stays as read: the occurrence
/// at [index] among the container's children of that name, written byte
/// for byte as it was read.
final class RepeatedKept {
  /// The occurrence at [index], counting from 0.
  const RepeatedKept(this.index);

  /// The position among the children of that name read.
  final int index;

  @override
  bool operator ==(Object other) =>
      other is RepeatedKept && other.index == index;

  @override
  int get hashCode => index.hashCode;
}

/// What a value is set to in `overrides` when the child loses its value and
/// keeps the rest ([PropertyCodec.keepsRest]), which is not `null`: `null`
/// removes the child. A property with this value reads `null`.
final class ValueRemoved {
  const ValueRemoved._();
}

/// The one [ValueRemoved].
const ValueRemoved valueRemoved = ValueRemoved._();

/// A container written in place of a nested child of another, such as the
/// `w:pPr` of a style with the values set on it. The property sets
/// (`PropertySet`) implement it.
abstract interface class NestedProperties {
  /// Whether writing would write nothing: a container built from scratch
  /// with no value set. A container read from a file is always written.
  bool get writesNothing;

  /// Writes the container as [qualifiedName], where [prefix] is bound to
  /// WordprocessingML and [declaredAbove] holds the bindings in scope.
  void writeTo(
    XmlWriter w,
    String qualifiedName, {
    String prefix = 'w',
    Map<String, String> declaredAbove = const <String, String>{},
  });
}

/// One child of a container as read.
final class _Slot {
  _Slot.kept(OpaqueXml this.kept, this.element)
    : container = null,
      localName = null;

  _Slot.nested(String this.localName, PropertyContainer this.container)
    : kept = null,
      element = null;

  /// The child kept as read; `null` for a nested container.
  final OpaqueXml? kept;

  /// What the codec of the child sees, when its name has a codec.
  final PropertyElement? element;

  /// The child read as a container of its own; `null` for a kept one.
  final PropertyContainer? container;

  /// The local name of a nested container; `null` for a kept one.
  final String? localName;

  /// The child's local name.
  String get name => kept?.localName ?? localName!;

  /// Whether the child is in WordprocessingML.
  bool get isW => kept == null || kept!.namespaceUri == Ns.w;
}

/// The children and attributes of a property container as read, with the
/// view of each typed child.
///
/// A container is immutable: values set through the model are kept apart
/// (a `PropertySet`) and passed to [writeTo] as `overrides`.
final class PropertyContainer {
  /// A container that keeps nothing, for properties written from scratch.
  const PropertyContainer.empty()
    : isRead = false,
      namespaces = const <String, String>{},
      attributes = const <KeptAttribute>[],
      _slots = const <_Slot>[],
      _views = const <String, Object>{},
      _repeated = const <String, List<Object?>>{},
      _innerText = null;

  PropertyContainer._(
    this.namespaces,
    this.attributes,
    this._slots,
    this._views,
    this._repeated,
    this._innerText,
  ) : isRead = true;

  /// Reads the container whose start element the current event of [r] is,
  /// by [schema], and consumes it: afterwards [r] is on the container's end
  /// event.
  ///
  /// Every child is kept as [OpaqueXml], except the first child in `w:` of
  /// each name in [ContainerSchema.nested], which is read as a container of
  /// its own ([nestedOf]); a second one of that name is kept. A child in
  /// `w:` whose name has a codec gets a view ([viewOf]) when it is the only
  /// child of that name, has no `w:` attribute outside the codec's
  /// [PropertyCodec.attributes], and the codec parses it. The container's
  /// attributes are kept. Character data, comments and processing
  /// instructions between children are dropped, but a container without
  /// child elements keeps them, so `<w:pPr> </w:pPr>` is written back as
  /// it was.
  ///
  /// [r] must be on a start element; anything else throws [StateError].
  factory PropertyContainer.read(XmlPullReader r, ContainerSchema schema) {
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
      return PropertyContainer._(
        namespaces,
        attributes,
        slots,
        const <String, Object>{},
        const <String, List<Object?>>{},
        null,
      );
    }
    final int depth = r.depth;
    final int innerStart = r.eventEnd;
    int innerEnd = innerStart;
    final Set<String> nestedRead = <String>{};
    while (r.next()) {
      final XmlEventType type = r.eventType;
      if (type == XmlEventType.endElement && r.depth < depth) {
        innerEnd = r.eventStart;
        break;
      }
      if (type != XmlEventType.startElement || r.depth != depth + 1) {
        continue;
      }
      final String localName = r.localName;
      if (r.namespaceUri != Ns.w) {
        slots.add(_Slot.kept(OpaqueXml.capture(r), null));
        continue;
      }
      final ContainerSchema? nested = schema.nested[localName];
      if (nested != null && nestedRead.add(localName)) {
        slots.add(_Slot.nested(localName, PropertyContainer.read(r, nested)));
        continue;
      }
      if (schema.codecs.containsKey(localName) ||
          schema.repeated.containsKey(localName)) {
        final PropertyElementBuilder element = PropertyElementBuilder();
        final OpaqueXml xml = OpaqueXml.capture(r, onEvent: element.add);
        slots.add(_Slot.kept(xml, element.element));
      } else {
        slots.add(_Slot.kept(OpaqueXml.capture(r), null));
      }
    }
    final String? innerText = slots.isEmpty && innerEnd > innerStart
        ? r.sourceText(innerStart, innerEnd)
        : null;
    return PropertyContainer._(
      namespaces,
      attributes,
      slots,
      _viewsOf(slots, schema),
      _repeatedViewsOf(slots, schema),
      innerText,
    );
  }

  /// The view of each typed child, by local name.
  static Map<String, Object> _viewsOf(
    List<_Slot> slots,
    ContainerSchema schema,
  ) {
    final Map<String, Object> views = <String, Object>{};
    schema.codecs.forEach((String name, PropertyCodec<Object> codec) {
      PropertyElement? only;
      int count = 0;
      for (final _Slot s in slots) {
        if (s.isW && s.name == name) {
          count++;
          only = s.element;
        }
      }
      if (count != 1 || only == null) return;
      if (!codec.attributes.containsAll(only.wAttributeNames)) return;
      final Object? view = codec.parse(only);
      if (view != null) views[name] = view;
    });
    return Map<String, Object>.unmodifiable(views);
  }

  /// The view of each occurrence of each repeated child, in input order.
  static Map<String, List<Object?>> _repeatedViewsOf(
    List<_Slot> slots,
    ContainerSchema schema,
  ) {
    final Map<String, List<Object?>> views = <String, List<Object?>>{};
    schema.repeated.forEach((String name, PropertyCodec<Object> codec) {
      final List<Object?> list = <Object?>[];
      for (final _Slot s in slots) {
        if (!s.isW || s.name != name) continue;
        final PropertyElement? e = s.element;
        list.add(
          e == null || !codec.attributes.containsAll(e.wAttributeNames)
              ? null
              : codec.parse(e),
        );
      }
      views[name] = List<Object?>.unmodifiable(list);
    });
    return Map<String, List<Object?>>.unmodifiable(views);
  }

  /// Whether the container was read from a file. A read container is
  /// written back even when it holds nothing, as it was; an empty one built
  /// from scratch need not be.
  final bool isRead;

  /// The namespaces the container element declared, prefix to URI.
  final Map<String, String> namespaces;

  /// The container element's attributes, in source order.
  final List<KeptAttribute> attributes;

  /// Every child in input order.
  final List<_Slot> _slots;

  final Map<String, Object> _views;

  final Map<String, List<Object?>> _repeated;

  /// What a container without child elements held between its tags
  /// (whitespace, comments), as written; `null` when it held nothing or
  /// had children.
  final String? _innerText;

  /// This container with only its children in `w:` named in [names], and
  /// their views, without its attributes and the namespaces it declared: a
  /// copy for a new element. A kept child declares what it needs and lacks.
  PropertyContainer keeping(Set<String> names) {
    if (!isRead) return this;
    return PropertyContainer._(
      const <String, String>{},
      const <KeptAttribute>[],
      <_Slot>[
        for (final _Slot s in _slots)
          if (s.isW && names.contains(s.name)) s,
      ],
      <String, Object>{
        for (final MapEntry<String, Object> e in _views.entries)
          if (names.contains(e.key)) e.key: e.value,
      },
      const <String, List<Object?>>{},
      null,
    );
  }

  /// This container without the namespaces its element declared: a
  /// definition parsed on its own, once it goes in a part whose root binds
  /// them. A kept child declares what it needs and lacks.
  PropertyContainer withoutDeclarations() => PropertyContainer._(
    const <String, String>{},
    attributes,
    _slots,
    _views,
    _repeated,
    _innerText,
  );

  /// The children kept untyped, in input order: every child but the typed
  /// ones (those with a view) and the nested containers.
  List<OpaqueXml> get kept => <OpaqueXml>[
    for (final _Slot s in _slots)
      if (s.kept != null && !(s.isW && _views.containsKey(s.name))) s.kept!,
  ];

  /// Whether the container keeps no attribute and no child.
  bool get isEmpty => attributes.isEmpty && _slots.isEmpty;

  /// The view of the typed child [localName]: its value, or `null` when
  /// there is no such child or it is not typed (plan Ruling 2).
  Object? viewOf(String localName) => _views[localName];

  /// The view of each occurrence of the repeated child [localName], in
  /// input order: the value, or `null` for one the codec cannot type (a
  /// `w:` attribute it does not understand, a value out of range). Empty
  /// when the container has none or [localName] is not repeated.
  List<Object?> repeatedViewsOf(String localName) =>
      _repeated[localName] ?? const <Object?>[];

  /// The element of each occurrence of the repeated child [localName], in
  /// input order, for what a [repeatedViewsOf] that is `null` still tells.
  List<PropertyElement?> repeatedElementsOf(String localName) =>
      <PropertyElement?>[
        for (final _Slot s in _slots)
          if (s.isW && s.name == localName) s.element,
      ];

  /// The nested container [localName] read, or `null` when the container
  /// has none.
  PropertyContainer? nestedOf(String localName) {
    for (final _Slot s in _slots) {
      if (s.container != null && s.localName == localName) return s.container;
    }
    return null;
  }

  /// Whether the container holds a child `w:<localName>`, typed or not.
  bool holds(String localName) {
    for (final _Slot s in _slots) {
      if (s.isW && s.name == localName) return true;
    }
    return false;
  }

  /// What to set for the typed child [localName] of [schema] to lose its
  /// value: [valueRemoved] when its codec keeps something of the child read,
  /// `null` when the child goes.
  ValueRemoved? valueRemovedOf(String localName, ContainerSchema schema) {
    final PropertyElement? element = _elementOf(localName);
    return element != null && schema.codecs[localName]!.keepsRest(element)
        ? valueRemoved
        : null;
  }

  /// The first child `w:<localName>` as its codec saw it, or `null`.
  PropertyElement? _elementOf(String localName) {
    for (final _Slot s in _slots) {
      if (s.isW && s.name == localName && s.element != null) return s.element;
    }
    return null;
  }

  /// Writes the container as [qualifiedName] by [schema], the one it was
  /// read by, with the values [overrides] gives.
  ///
  /// [overrides] maps the local name of a typed child to its value: a value
  /// replaces every kept child `w:` of that name with the one its codec
  /// writes, at its slot in the schema order; `null` removes them;
  /// [valueRemoved] writes what its codec keeps of the child. A name
  /// without a codec in [schema], or a value the codec does not accept,
  /// throws [ArgumentError] before anything is written. [nested] maps the
  /// name of a nested container to the one written in its place (the first
  /// read of that name; nothing when it [NestedProperties.writesNothing]).
  /// The merge of the rest:
  ///
  /// * A kept child in `w:` whose name is in the schema order is written at
  ///   its slot; several of one name keep their input order, and so do
  ///   repeated children of several names ([ContainerSchema.repeated]).
  /// * Any other kept child (another namespace, such as `w14:`, or a name
  ///   the schema lacks) follows the child that preceded it in the input,
  ///   or the one written in its place. When that child is removed, the one
  ///   before it counts; with none, the kept child is written first.
  ///
  /// [prefix] must be bound to WordprocessingML in [declaredAbove], the
  /// bindings in scope where the container goes; the container and the
  /// children set are written with it. When the container rebinds
  /// [prefix] to another namespace, another prefix bound to
  /// WordprocessingML is used, or `w1` (`w2`, …) is declared on the
  /// container. A kept child or attribute declares the bindings it needs
  /// and lacks.
  ///
  /// [attributes], when given, are written in place of the container's own
  /// [PropertyContainer.attributes]: how a new `w:style` gets its
  /// `w:type` and `w:styleId` with the prefix in use.
  void writeTo(
    XmlWriter w,
    String qualifiedName,
    ContainerSchema schema, {
    Map<String, Object?> overrides = const <String, Object?>{},
    Map<String, NestedProperties> nested = const <String, NestedProperties>{},
    Map<String, List<Object>> repeated = const <String, List<Object>>{},
    String prefix = 'w',
    Map<String, String> declaredAbove = const <String, String>{},
    List<KeptAttribute>? attributes,
  }) {
    overrides.forEach((String name, Object? value) {
      checkSettable(
        schema,
        name,
        value is ValueRemoved ? null : value,
        qualifiedName,
      );
    });
    for (final String name in nested.keys) {
      if (!schema.nested.containsKey(name)) {
        throw ArgumentError.value(
          name,
          'nested',
          'Not a nested container of $qualifiedName',
        );
      }
    }
    repeated.forEach((String name, List<Object> entries) {
      checkRepeated(schema, name, entries, _repeated[name]?.length ?? 0);
    });
    final Set<String> inOrder = schema.order.toSet();
    bool inSchema(_Slot s) => s.isW && inOrder.contains(s.name);
    // Whether the slot is not written because a value or a nested
    // container takes its place (or removes it).
    bool replaced(_Slot s) =>
        s.isW &&
        (overrides.containsKey(s.name) ||
            repeated.containsKey(s.name) ||
            (s.container != null && nested.containsKey(s.name)));
    // Whether what takes the place of the name is written.
    bool replacementWritten(String name) => overrides.containsKey(name)
        ? overrides[name] != null
        : repeated.containsKey(name)
        ? repeated[name]!.isNotEmpty
        : !nested[name]!.writesNothing;

    // Kept schema children by local name, and the kept children that follow
    // each anchor: null for the start, a slot index or a replaced name.
    final Map<String, List<int>> byName = <String, List<int>>{};
    // The slots of each repeated child that a set replaces, by occurrence.
    final Map<String, List<int>> occurrences = <String, List<int>>{};
    final Map<Object?, List<int>> followers = <Object?, List<int>>{};
    for (int i = 0; i < _slots.length; i++) {
      final _Slot s = _slots[i];
      if (!inSchema(s)) {
        followers
            .putIfAbsent(
              _anchorOf(i, inSchema, replaced, replacementWritten),
              () => <int>[],
            )
            .add(i);
      } else if (!replaced(s)) {
        byName.putIfAbsent(_placeOf(s.name, schema), () => <int>[]).add(i);
      } else if (repeated.containsKey(s.name)) {
        occurrences.putIfAbsent(s.name, () => <int>[]).add(i);
      }
    }

    final (String p, String name, String? declare) = _boundPrefix(
      qualifiedName,
      prefix,
      declaredAbove,
    );
    final Map<String, String> inner = mergeNamespaces(
      declaredAbove,
      declare == null
          ? namespaces
          : <String, String>{...namespaces, declare: Ns.w},
    );
    void writeSlot(int i) {
      final _Slot s = _slots[i];
      final PropertyContainer? container = s.container;
      if (container != null) {
        container.writeTo(
          w,
          '$p:${s.name}',
          schema.nested[s.name]!,
          prefix: p,
          declaredAbove: inner,
        );
      } else {
        s.kept!.writeTo(w, declaredAbove: inner);
      }
    }

    // Each kept child follows the one before it, so a chain is as long as
    // the file makes it: this walks it with a stack of its own, not by
    // recursion, which a small file could overflow.
    void writeFollowers(Object? anchor) {
      final List<int> pending = <int>[...?followers[anchor]?.reversed];
      while (pending.isNotEmpty) {
        final int i = pending.removeLast();
        writeSlot(i);
        pending.addAll(followers[i]?.reversed ?? const <int>[]);
      }
    }

    w.start(name);
    writeNamespaceDeclarations(w, namespaces);
    if (declare != null) w.attribute('xmlns:$declare', Ns.w);
    writeKeptAttributes(w, attributes ?? this.attributes, declaredAbove: inner);
    bool wrote = false;
    writeFollowers(null);
    for (final String child in schema.order) {
      final Object? value = overrides[child];
      if (value is ValueRemoved) {
        schema.codecs[child]!.writeRest(w, p, _elementOf(child)!);
        wrote = true;
        writeFollowers(child);
      } else if (value != null) {
        schema.codecs[child]!.write(w, p, value, _elementOf(child));
        wrote = true;
        writeFollowers(child);
      } else if (nested[child] case final NestedProperties n
          when !n.writesNothing) {
        n.writeTo(w, '$p:$child', prefix: p, declaredAbove: inner);
        wrote = true;
        writeFollowers(child);
      }
      if (repeated[child] case final List<Object> entries
          when entries.isNotEmpty) {
        for (final Object entry in entries) {
          if (entry is RepeatedKept) {
            writeSlot(occurrences[child]![entry.index]);
          } else {
            schema.repeated[child]!.writeRepeated(w, p, entry, inner);
          }
        }
        wrote = true;
        writeFollowers(child);
      }
      final List<int>? slots = byName[child];
      if (slots == null) {
        continue;
      }
      for (final int i in slots) {
        writeSlot(i);
        writeFollowers(i);
      }
    }
    final String? innerText = _innerText;
    if (innerText != null && !wrote) {
      w.raw(innerText);
    }
    w.end();
  }

  /// The child of [schema] whose place in its order the kept child [name]
  /// is written at: its own, or for a repeated child the first repeated one.
  static String _placeOf(String name, ContainerSchema schema) =>
      schema.repeated.containsKey(name)
      ? schema.order.firstWhere(schema.repeated.containsKey)
      : name;

  /// The prefix to write WordprocessingML with inside the container, the
  /// container's qualified name with it, and a prefix to declare on the
  /// container for it (or `null`).
  ///
  /// It is [prefix] unless the container rebinds [prefix]: then a prefix
  /// bound to WordprocessingML inside the container, or a new `w1`, `w2`, …
  (String, String, String?) _boundPrefix(
    String qualifiedName,
    String prefix,
    Map<String, String> declaredAbove,
  ) {
    final String? rebound = namespaces[prefix];
    if (rebound == null || rebound == Ns.w) {
      return (prefix, qualifiedName, null);
    }
    final String local = qualifiedName.startsWith('$prefix:')
        ? qualifiedName.substring(prefix.length + 1)
        : qualifiedName;
    final Map<String, String> inner = mergeNamespaces(
      declaredAbove,
      namespaces,
    );
    for (final MapEntry<String, String> e in inner.entries) {
      if (e.key.isNotEmpty && e.value == Ns.w) {
        return (e.key, '${e.key}:$local', null);
      }
    }
    String fresh = 'w1';
    for (int i = 2; inner.containsKey(fresh); i++) {
      fresh = 'w$i';
    }
    return (fresh, '$fresh:$local', fresh);
  }

  /// The anchor of the slot at [index], which is not in the schema: the
  /// nearest child before it that is written, as a slot index, or the name
  /// of a replaced child whose replacement is written, or `null` when none
  /// is.
  Object? _anchorOf(
    int index,
    bool Function(_Slot) inSchema,
    bool Function(_Slot) replaced,
    bool Function(String) replacementWritten,
  ) {
    for (int j = index - 1; j >= 0; j--) {
      final _Slot s = _slots[j];
      if (inSchema(s) && replaced(s)) {
        if (replacementWritten(s.name)) {
          return s.name;
        }
        continue;
      }
      return j;
    }
    return null;
  }
}

/// Throws [ArgumentError] unless [name] is a typed child of [schema] (in its
/// order, with a codec) and [value] is `null` or accepted by its codec.
/// [container] names the container in the message.
void checkSettable(
  ContainerSchema schema,
  String name,
  Object? value,
  String container,
) {
  final PropertyCodec<Object>? codec = schema.codecs[name];
  if (codec == null || !schema.order.contains(name)) {
    throw ArgumentError.value(
      name,
      'name',
      'Not a typed child of $container in schema order',
    );
  }
  if (value != null && !codec.accepts(value)) {
    throw ArgumentError.value(
      value,
      name,
      'Not a value of the ${codec.localName} property',
    );
  }
}

/// Throws [ArgumentError] unless [name] is a repeated child of [schema] (in
/// its order, with a codec) and every entry of [entries] is a [RepeatedKept]
/// of one of the [count] occurrences read or a value its codec accepts.
void checkRepeated(
  ContainerSchema schema,
  String name,
  List<Object> entries,
  int count,
) {
  final PropertyCodec<Object>? codec = schema.repeated[name];
  if (codec == null || !schema.order.contains(name)) {
    throw ArgumentError.value(
      name,
      'name',
      'Not a repeated child in schema order',
    );
  }
  for (final Object entry in entries) {
    if (entry is RepeatedKept) {
      if (entry.index < 0 || entry.index >= count) {
        throw ArgumentError.value(
          entry.index,
          name,
          'Not an occurrence read ($count)',
        );
      }
    } else if (!codec.accepts(entry)) {
      throw ArgumentError.value(
        entry,
        name,
        'Not a value of the ${codec.localName} property',
      );
    }
  }
}
