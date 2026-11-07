/// Codecs that type one child of a property container, and the parsing
/// helpers they share.
///
/// Not ported from Quds; written for jet_office.
///
/// A container (`PropertyContainer`) keeps every child as read. For a child
/// whose local name has a [PropertyCodec] in the container's schema, the
/// reader also builds a [PropertyElement] (what the codec sees of it) and
/// asks the codec for a *view*: the child's typed value. The child is typed
/// only when it is in `w:`, occurs once, every `w:` attribute it has is one
/// of the codec's [PropertyCodec.attributes], and [PropertyCodec.parse]
/// gives a value; otherwise its view is `null` and it is still written as
/// read (plan Ruling 2). When a value is set, the codec writes the child
/// anew, and may keep attributes of the child as read
/// ([PropertyCodec.write]'s `asRead`, Ruling 3).
///
/// The helpers read the simple types of ECMA-376 Part 1 §17.18 and §22.9
/// strictly, so a value reads the same on the VM and in JavaScript: a number
/// is typed only with at most 9 digits after an optional `-`, `"024"` reads
/// 24, and `"+24"`, `"1in"` or ten digits read `null`.
library;

import '../opc/ooxml.dart' show Ns;
import '../opc/opaque_xml.dart';
import '../xml/xml_escape.dart';
import '../xml/xml_pull_reader.dart';
import '../xml/xml_writer.dart';

/// What a codec sees of one child of a container: its name, attributes,
/// child elements and whether it holds text.
final class PropertyElement {
  PropertyElement._(this.localName, this.namespaceUri, this.attributes);

  /// The element's local name.
  final String localName;

  /// The element's namespace URI, or the empty string.
  final String namespaceUri;

  /// The element's attributes in source order, without `xmlns`
  /// declarations.
  final List<KeptAttribute> attributes;

  final List<PropertyElement> _children = <PropertyElement>[];

  bool _hasText = false;

  /// The child elements, in order.
  List<PropertyElement> get children => _children;

  /// Whether the element holds character data other than XML whitespace
  /// directly, or a CDATA section.
  bool get hasText => _hasText;

  /// The value of the attribute [localName] in the WordprocessingML
  /// namespace (`w:val` for `'val'`), or `null` when there is none.
  String? w(String localName) {
    for (final KeptAttribute a in attributes) {
      if (a.namespaceUri == Ns.w && _localOf(a.qualifiedName) == localName) {
        return a.value;
      }
    }
    return null;
  }

  /// The local names of the element's attributes in the WordprocessingML
  /// namespace.
  Set<String> get wAttributeNames => <String>{
    for (final KeptAttribute a in attributes)
      if (a.namespaceUri == Ns.w) _localOf(a.qualifiedName),
  };

  static String _localOf(String qualifiedName) =>
      qualifiedName.substring(qualifiedName.indexOf(':') + 1);
}

/// Builds the [PropertyElement] of an element from the events of its
/// capture: pass [add] as `onEvent` to `OpaqueXml.capture`.
final class PropertyElementBuilder {
  final List<PropertyElement> _open = <PropertyElement>[];

  PropertyElement? _element;

  /// The element built, once its end event was added; `null` before.
  PropertyElement? get element => _open.isEmpty ? _element : null;

  /// Takes the event [r] is on.
  void add(XmlPullReader r) {
    switch (r.eventType) {
      case XmlEventType.startElement:
        final PropertyElement e = PropertyElement._(
          r.localName,
          r.namespaceUri,
          List<KeptAttribute>.unmodifiable(keepAttributes(r)),
        );
        if (_open.isEmpty) {
          _element = e;
        } else {
          _open.last._children.add(e);
        }
        _open.add(e);
      case XmlEventType.endElement:
        if (_open.isNotEmpty) _open.removeLast();
      case XmlEventType.characters:
        if (_open.isNotEmpty && !r.isWhitespace) _open.last._hasText = true;
      case XmlEventType.cdata:
        if (_open.isNotEmpty) _open.last._hasText = true;
      default:
        break;
    }
  }
}

/// Types one child of a property container: reads its view and writes it
/// when a value is set.
///
/// [T] is the type of the value, such as [String] for a style id. Codecs
/// are constant and stateless; a container's schema maps each typed local
/// name to its codec.
abstract base class PropertyCodec<T extends Object> {
  /// A codec of the child `w:<localName>`.
  const PropertyCodec(this.localName);

  /// The child's local name in WordprocessingML, such as `pStyle`.
  final String localName;

  /// The local names of the `w:` attributes the codec understands.
  ///
  /// A child with any other `w:` attribute has no view, since typing it
  /// would lose that attribute on a set. An attribute the codec keeps as
  /// read when it writes ([write]'s `asRead`, such as `w:cs` of `w:rFonts`)
  /// counts as understood. Attributes in other namespaces are never looked
  /// at for typing.
  Set<String> get attributes;

  /// The view of [e], or `null` when the codec cannot type it (a value out
  /// of range, a child element the schema does not allow).
  ///
  /// [e] is in `w:` with local name [localName], and has no `w:` attribute
  /// outside [attributes]; the container checked both.
  T? parse(PropertyElement e);

  /// Writes the child for [value], as `<prefix:localName …/>`.
  ///
  /// [prefix] is bound to WordprocessingML where the child goes. [asRead]
  /// is the first child of this name the container read, or `null` when
  /// there was none; a codec that keeps attributes of the element as read
  /// takes them from it.
  void write(XmlWriter w, String prefix, T value, PropertyElement? asRead);

  /// Writes [value] as an occurrence of a repeated child
  /// (`ContainerSchema.repeated`) set through the API, where the bindings
  /// [scope] are in scope: what a codec needs when it writes an attribute of
  /// another namespace. By default it is [write], with nothing read.
  void writeRepeated(
    XmlWriter w,
    String prefix,
    T value,
    Map<String, String> scope,
  ) => write(w, prefix, value, null);

  /// Whether removing the value of [e], a child with a view, leaves
  /// something: attributes the codec keeps as read beside the ones it
  /// types, as `w:cs` of `w:rFonts`. Such a child stays, written by
  /// [writeRest]; any other is removed. Most codecs keep nothing.
  bool keepsRest(PropertyElement e) => false;

  /// Writes the child without its value, what stays of [asRead] when
  /// [keepsRest] says something does.
  void writeRest(XmlWriter w, String prefix, PropertyElement asRead) {
    throw StateError('The codec of $localName keeps nothing of the child.');
  }

  /// Whether [value] is of the codec's type, so it can be set.
  bool accepts(Object value) => value is T;
}

/// The codec of a style reference, `w:pStyle`, `w:rStyle` or `w:basedOn`:
/// its `w:val` is the style id.
///
/// A child is typed when its `w:val` is not empty and it has no other `w:`
/// attribute, no child element and no text; anything else (no `w:val`, an
/// empty one, children the schema does not allow) has no view and is
/// written as read.
final class StyleIdCodec extends PropertyCodec<String> {
  /// The codec of the style reference `w:<localName>`.
  const StyleIdCodec(super.localName);

  @override
  Set<String> get attributes => const <String>{'val'};

  @override
  String? parse(PropertyElement e) {
    final String? value = e.w('val');
    if (value == null || value.isEmpty || e.children.isNotEmpty || e.hasText) {
      return null;
    }
    return value;
  }

  @override
  void write(
    XmlWriter w,
    String prefix,
    String value,
    PropertyElement? asRead,
  ) => writeValElement(w, '$prefix:$localName', value, prefix: prefix);
}

/// Throws [ArgumentError] when [value], a style id to set, is empty or holds
/// a character XML forbids; `null` (no style) passes.
void checkStyleId(String? value) {
  if (value == null) {
    return;
  }
  if (value.isEmpty) {
    throw ArgumentError.value(value, 'style', 'Must not be empty');
  }
  if (scrubXmlText(value).removed > 0) {
    throw ArgumentError.value(
      value,
      'style',
      'Must not hold a character XML forbids',
    );
  }
}

/// Writes `<qualifiedName w:val="value"/>`, the shape of `w:pStyle`,
/// `w:rStyle` and other single-value properties.
///
/// The attribute is written as `[prefix]:val`, so [prefix] (`w` by
/// default) must be bound to the WordprocessingML namespace where the
/// element goes. A character XML forbids is removed from [value].
void writeValElement(
  XmlWriter w,
  String qualifiedName,
  String value, {
  String prefix = 'w',
}) {
  w.start(qualifiedName);
  w.attribute('$prefix:val', scrubXmlText(value).text);
  w.end();
}

/// An `ST_OnOff` value: `true` when absent (the attribute is optional and
/// means on) or `true`, `1` or `on`; `false` for `false`, `0` or `off`;
/// `null` for anything else.
bool? parseOnOff(String? value) => switch (value) {
  null || 'true' || '1' || 'on' => true,
  'false' || '0' || 'off' => false,
  _ => null,
};

final RegExp _decimal = RegExp(r'^-?[0-9]{1,9}$');

/// An `ST_DecimalNumber` from [min] to [max], or `null`.
///
/// Only an optional `-` and one to nine digits are read, so the number is
/// exact on the VM and in JavaScript: `"024"` reads 24, while `"+24"`,
/// `"1in"`, `"12.5"` and ten digits or more read `null`, as does a number
/// outside [min] to [max] and a `null` [value].
int? parseDecimal(String? value, {required int min, required int max}) {
  if (value == null || !_decimal.hasMatch(value)) {
    return null;
  }
  final int n = int.parse(value);
  return n < min || n > max ? null : n;
}

final RegExp _hex6 = RegExp(r'^[0-9A-Fa-f]{6}$');

final RegExp _hexByte = RegExp(r'^[0-9A-Fa-f]{2}$');

/// An RGB color of six hex digits (`ST_HexColorRGB`), in upper case, or
/// `null` for anything else: `00ff7F` reads `00FF7F`, `FF00` and `red`
/// read `null`.
String? parseHex6(String? value) =>
    value != null && _hex6.hasMatch(value) ? value.toUpperCase() : null;

/// A byte of two hex digits (`ST_UcharHexNumber`, such as a theme tint), or
/// `null` for anything else.
int? parseHexByte(String? value) => value != null && _hexByte.hasMatch(value)
    ? int.parse(value, radix: 16)
    : null;

/// The value [byXml] maps [value] to, compared exactly, or `null` for a
/// value it lacks and for a `null` [value].
E? parseEnum<E extends Enum>(String? value, Map<String, E> byXml) =>
    value == null ? null : byXml[value];
