/// The mutable properties of a paragraph, a run or a style, over a
/// container as read.
///
/// Not ported from Quds; written for jet_office.
///
/// A [PropertySet] holds the [PropertyContainer] it was read from and the
/// values set on it since. A value reads the one set, else the container's
/// view; writing merges the two ([PropertyContainer.writeTo]). Each set that
/// changes something is reported to the document's sink
/// ([DocxEditSink.propertySet]) with the state from before, and an undo puts
/// that state back with [PropertySet.restore], which reports nothing. A
/// child never set is written as read.
///
/// It is the internal base of the public property classes
/// (`DocxRunProperties`, `DocxParagraphProperties`), which give each
/// property a typed getter and setter that checks the value.
///
/// @docImport '../property_codec.dart';
library;

import '../../opc/opaque_xml.dart' show KeptAttribute;
import '../../xml/xml_writer.dart';
import '../properties.dart';
import '../property_codec.dart' show PropertyElement;
import 'edit_sink.dart';
import 'styles.dart' show DocxStyleType;

/// Whether a property was set on a [PropertySet], and to what: what
/// [PropertySet.stateOf] gives and [PropertySet.restore] takes.
typedef PropertyState = ({bool isSet, Object? value});

/// Properties over a container as read, with the values set on them.
abstract base class PropertySet implements NestedProperties {
  /// Properties over [source], read by [schema]; each edit is reported to
  /// the sink that `sink` gives at the time of the edit.
  PropertySet(this.source, this.schema, DocxEditSink Function() sink)
    : _sink = sink;

  /// The container the properties were read from (an empty one for new
  /// properties).
  final PropertyContainer source;

  /// The schema [source] was read by and the properties are written by.
  final ContainerSchema schema;

  final DocxEditSink Function() _sink;

  /// The values set, by local name; `null` removes the child.
  final Map<String, Object?> _overrides = <String, Object?>{};

  /// The entries set for each repeated child, by local name: a
  /// [RepeatedKept] for an occurrence as read, else a value. Lists are
  /// replaced, never changed, so a [PropertyState] may hold one.
  final Map<String, List<Object>> _repeated = <String, List<Object>>{};

  /// The nested properties written in place of [source]'s nested
  /// containers, by local name; none by default. A subclass with nested
  /// containers (a style's `w:pPr`) overrides it.
  Map<String, NestedProperties> get nested =>
      const <String, NestedProperties>{};

  /// The value of the typed child [localName]: the one set, else the view
  /// of [source] (`null` when it has no such child or does not type it).
  ///
  /// A name that is not a typed child of [schema] throws [ArgumentError].
  Object? valueOf(String localName) {
    _check(localName, null);
    if (!_overrides.containsKey(localName)) {
      return source.viewOf(localName);
    }
    final Object? value = _overrides[localName];
    return value is ValueRemoved ? null : value;
  }

  /// Whether a value (`null` included) was set for [localName], so the
  /// child is written anew rather than as read.
  bool isSet(String localName) => schema.repeated.containsKey(localName)
      ? _repeated.containsKey(localName)
      : _overrides.containsKey(localName);

  /// Whether [localName] is set, and to what: for a repeated child, the
  /// list of entries ([RepeatedKept] or value) written.
  PropertyState stateOf(String localName) => (
    isSet: isSet(localName),
    value: schema.repeated.containsKey(localName)
        ? _repeated[localName]
        : _overrides[localName],
  );

  /// The value of each occurrence of the repeated child [localName], in
  /// order: the value set, else the view of [source] (`null` for an
  /// occurrence the codec cannot type, which is still written as read).
  ///
  /// A name that is not a repeated child of [schema] throws [ArgumentError].
  List<Object?> repeatedOf(String localName) {
    _checkRepeated(localName);
    final List<Object?> views = source.repeatedViewsOf(localName);
    final List<Object>? entries = _repeated[localName];
    if (entries == null) {
      return views;
    }
    return List<Object?>.unmodifiable(<Object?>[
      for (final Object e in entries) e is RepeatedKept ? views[e.index] : e,
    ]);
  }

  /// The element read of each occurrence of the repeated child [localName],
  /// in the order of [repeatedOf]: `null` for a value set.
  ///
  /// A name that is not a repeated child of [schema] throws [ArgumentError].
  List<PropertyElement?> repeatedElementsOf(String localName) {
    _checkRepeated(localName);
    final List<PropertyElement?> read = source.repeatedElementsOf(localName);
    final List<Object>? entries = _repeated[localName];
    if (entries == null) {
      return read;
    }
    return <PropertyElement?>[
      for (final Object e in entries) e is RepeatedKept ? read[e.index] : null,
    ];
  }

  /// Adds [value] after the occurrences of the repeated child [localName];
  /// the others are written as read. A value its codec does not accept, or
  /// a name that is not repeated, throws [ArgumentError] before anything
  /// changes.
  void addRepeated(String localName, Object value) {
    _checkRepeated(localName, value);
    _recordRepeated(localName, <Object>[..._entries(localName), value]);
  }

  /// Replaces the occurrence [index] of the repeated child [localName] with
  /// [value]. Nothing changes when it already reads [value]. An [index]
  /// out of range throws [RangeError], a bad name or value [ArgumentError],
  /// before anything changes.
  void replaceRepeatedAt(String localName, int index, Object value) {
    _checkRepeated(localName, value);
    final List<Object> entries = _entries(localName);
    RangeError.checkValidIndex(index, entries, 'index');
    if (repeatedOf(localName)[index] == value) {
      return;
    }
    _recordRepeated(localName, <Object>[...entries]..[index] = value);
  }

  /// Removes the occurrence [index] of the repeated child [localName]; the
  /// others are written as read. An [index] out of range throws
  /// [RangeError], a bad name [ArgumentError], before anything changes.
  void removeRepeatedAt(String localName, int index) {
    _checkRepeated(localName);
    final List<Object> entries = _entries(localName);
    RangeError.checkValidIndex(index, entries, 'index');
    _recordRepeated(localName, <Object>[...entries]..removeAt(index));
  }

  /// The entries now written for [localName]: the ones set, else every
  /// occurrence as read.
  List<Object> _entries(String localName) =>
      _repeated[localName] ??
      <Object>[
        for (int i = 0; i < source.repeatedViewsOf(localName).length; i++)
          RepeatedKept(i),
      ];

  void _recordRepeated(String localName, List<Object> entries) {
    final PropertyState previous = stateOf(localName);
    _repeated[localName] = List<Object>.unmodifiable(entries);
    _sink().propertySet(this, localName, previous);
  }

  void _checkRepeated(String localName, [Object? value]) => checkRepeated(
    schema,
    localName,
    <Object>[?value],
    source.repeatedViewsOf(localName).length,
  );

  /// Sets the typed child [localName] to [value]; `null` removes it, but for
  /// what its codec keeps of the child read ([PropertyCodec.keepsRest]),
  /// such as `w:cs` of `w:rFonts`: that stays, and [clearChild] removes it.
  ///
  /// Nothing changes and nothing is reported when [value] equals the
  /// current value ([valueOf]), `null` included: setting a property to what
  /// it reads never touches the child, so `x.style = x.style` keeps a child
  /// the model does not type (two `w:pStyle`, a `w:sz` of `1in`) and a
  /// typed one with its extra attributes. To remove a child whatever it
  /// reads, use [clearChild]. Otherwise the value is set and the sink is told,
  /// with the state from before.
  ///
  /// A name that is not a typed child of [schema], or a value its codec
  /// does not accept, throws [ArgumentError] before anything changes. The
  /// subclass checks the value itself (range, form) before.
  void setValue(String localName, Object? value) {
    _check(localName, value);
    if (value == valueOf(localName)) {
      return;
    }
    _record(localName, value ?? source.valueRemovedOf(localName, schema));
  }

  /// Sets the style reference [localName] (`w:pStyle`, `w:rStyle`) to the
  /// style [id] of [type], as the document resolves it
  /// ([DocxEditSink.resolveStyleId]), in one edit with whatever that adds;
  /// `null` removes it.
  ///
  /// The no-op rule of [setValue] holds for [id] as given, which resolves
  /// nothing and loads nothing, so setting back a read reference the
  /// document lacks adds no style; and for the resolved id, so `Heading1`
  /// on what reads `Balk1` records nothing.
  void setStyleId(String localName, String? id, DocxStyleType type) {
    _check(localName, id);
    if (id == null || id == valueOf(localName)) {
      setValue(localName, id);
      return;
    }
    final DocxEditSink sink = _sink();
    sink.atomically(() => setValue(localName, sink.resolveStyleId(id, type)));
  }

  /// Resolves the style reference [localName] if one was set through the
  /// API, now that the properties belong to a document; a reference read
  /// from the file stays as it is (plan Ruling 5).
  void resolveStyleIdSet(String localName, DocxStyleType type) {
    final Object? id = _overrides[localName];
    if (id is String) {
      setValue(localName, _sink().resolveStyleId(id, type));
    }
  }

  /// Counts the child [localName] as read, when typed and not set since, as
  /// set to what it reads: how the properties of content read in one
  /// document join another, whose ids are not those it was read with. The
  /// child is written anew from then on, and the edit is reported.
  void countReadAsSet(String localName) {
    final Object? read = source.viewOf(localName);
    if (read != null && !isSet(localName)) {
      _record(localName, read);
    }
  }

  /// Removes every child [localName] from the written properties, whatever
  /// the model reads of it, so a child it does not type goes too.
  ///
  /// Nothing changes and nothing is reported when the child is already
  /// removed (set to `null`) or [source] has none and nothing was set.
  /// A name that is not a typed child of [schema] throws [ArgumentError].
  void clearChild(String localName) {
    _check(localName, null);
    final bool removed = isSet(localName) && _overrides[localName] == null;
    if (removed || (!isSet(localName) && !source.holds(localName))) {
      return;
    }
    _record(localName, null);
  }

  void _record(String localName, Object? value) {
    final PropertyState previous = stateOf(localName);
    _overrides[localName] = value;
    _sink().propertySet(this, localName, previous);
  }

  /// Puts [state] back for [localName] without reporting it: how a recorded
  /// set is undone or redone.
  void restore(String localName, PropertyState state) {
    if (schema.repeated.containsKey(localName)) {
      if (state.isSet) {
        _repeated[localName] = state.value! as List<Object>;
      } else {
        _repeated.remove(localName);
      }
    } else if (state.isSet) {
      _overrides[localName] = state.value;
    } else {
      _overrides.remove(localName);
    }
  }

  /// Takes the values set on [other] in place of those set here, without
  /// reporting anything: how a copy of properties starts as the original is
  /// now. [other] must be over the same [source] and [schema], since a value
  /// set may stand for one of [source]'s children (a [RepeatedKept], a
  /// [ValueRemoved]); otherwise it throws [ArgumentError].
  ///
  /// The values are immutable, and lists of repeated entries are replaced and
  /// never changed, so later sets on either side do not reach the other.
  void takeValuesSetOn(PropertySet other) {
    if (!identical(other.source, source) || !identical(other.schema, schema)) {
      throw ArgumentError.value(
        other,
        'other',
        'must be over the same source and schema',
      );
    }
    _overrides
      ..clear()
      ..addAll(other._overrides);
    _repeated
      ..clear()
      ..addAll(other._repeated);
  }

  /// Writes the properties as [qualifiedName]: [source]'s children merged
  /// with the values set, in [schema]'s order ([PropertyContainer.writeTo]
  /// has the rules). [attributes], when given, are written in place of
  /// [source]'s own.
  @override
  void writeTo(
    XmlWriter w,
    String qualifiedName, {
    String prefix = 'w',
    Map<String, String> declaredAbove = const <String, String>{},
    List<KeptAttribute>? attributes,
  }) => source.writeTo(
    w,
    qualifiedName,
    schema,
    overrides: _overrides,
    nested: nested,
    repeated: _repeated,
    prefix: prefix,
    declaredAbove: declaredAbove,
    attributes: attributes,
  );

  /// Whether [writeTo] would write an empty element the file need not
  /// have: [source] was built from scratch, no value other than `null` is
  /// set, and every nested set writes nothing. Properties read from a file
  /// always write, as they were.
  @override
  bool get writesNothing =>
      !source.isRead &&
      source.isEmpty &&
      _overrides.values.every((Object? v) => v == null) &&
      _repeated.values.every((List<Object> v) => v.isEmpty) &&
      nested.values.every((NestedProperties n) => n.writesNothing);

  void _check(String localName, Object? value) =>
      checkSettable(schema, localName, value, 'the properties');
}
