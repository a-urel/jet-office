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
library;

import '../../xml/xml_writer.dart';
import '../properties.dart';
import 'edit_sink.dart';

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
    return _overrides.containsKey(localName)
        ? _overrides[localName]
        : source.viewOf(localName);
  }

  /// Whether a value (`null` included) was set for [localName], so the
  /// child is written anew rather than as read.
  bool isSet(String localName) => _overrides.containsKey(localName);

  /// Whether [localName] is set, and to what.
  PropertyState stateOf(String localName) =>
      (isSet: isSet(localName), value: _overrides[localName]);

  /// Sets the typed child [localName] to [value]; `null` removes it.
  ///
  /// Nothing changes and nothing is reported when [value] equals the
  /// current value ([valueOf]), unless it is `null` and [source] holds a
  /// child of that name the model does not type, which a `null` removes.
  /// Otherwise the value is set and the sink is told, with the state from
  /// before.
  ///
  /// A name that is not a typed child of [schema], or a value its codec
  /// does not accept, throws [ArgumentError] before anything changes. The
  /// subclass checks the value itself (range, form) before.
  void setValue(String localName, Object? value) {
    _check(localName, value);
    if (value == valueOf(localName) &&
        (value != null || isSet(localName) || !source.holds(localName))) {
      return;
    }
    final PropertyState previous = stateOf(localName);
    _overrides[localName] = value;
    _sink().propertySet(this, localName, previous);
  }

  /// Puts [state] back for [localName] without reporting it: how a recorded
  /// set is undone or redone.
  void restore(String localName, PropertyState state) {
    if (state.isSet) {
      _overrides[localName] = state.value;
    } else {
      _overrides.remove(localName);
    }
  }

  /// Writes the properties as [qualifiedName]: [source]'s children merged
  /// with the values set, in [schema]'s order ([PropertyContainer.writeTo]
  /// has the rules).
  @override
  void writeTo(
    XmlWriter w,
    String qualifiedName, {
    String prefix = 'w',
    Map<String, String> declaredAbove = const <String, String>{},
  }) => source.writeTo(
    w,
    qualifiedName,
    schema,
    overrides: _overrides,
    nested: nested,
    prefix: prefix,
    declaredAbove: declaredAbove,
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
      nested.values.every((NestedProperties n) => n.writesNothing);

  void _check(String localName, Object? value) =>
      checkSettable(schema, localName, value, 'the properties');
}
