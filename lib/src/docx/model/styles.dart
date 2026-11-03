/// The styles of a document: the document defaults and the styles of
/// `word/styles.xml`, read, looked up, edited and added to.
///
/// Not ported from Quds; written for jet_office.
///
/// [DocxStyles] holds the root's children in document order. The document
/// defaults (`w:docDefaults`) and each `w:style` are typed; the latent
/// styles and every other child are kept as read, in place
/// (`styles_part.dart` reads and writes the part). A style ([DocxStyle]) is
/// a view over its `w:style` as read, like the run and paragraph
/// properties: its name, links, priority and quick-format flag are typed
/// children (a private `PropertySet` by `styleSchema`), its `w:pPr` and
/// `w:rPr` are [DocxParagraphProperties] and [DocxRunProperties], and every
/// other child and attribute (`w:rsid`, `w:tblPr`, `w14:` attributes) is
/// written back as read. A style is identified by its `w:styleId`, the key
/// that paragraphs and runs reference; a built-in style is recognized by its
/// `w:name`, which is English in every locale (plan Ruling 5).
///
/// Every edit is recorded in the document's change log: a style added is
/// one change, and each property set of a style in the document is one
/// change, so a transaction that fails puts everything back. A style that
/// is in no document records nothing.
///
/// @docImport '../style_schemas.dart';
library;

import 'dart:collection';

import '../../opc/change_log.dart';
import '../../opc/ooxml.dart' show Ns;
import '../../opc/opaque_xml.dart';
import '../../xml/xml_escape.dart';
import '../paragraph_property_codecs.dart'
    show paragraphPropertiesGeneralSchema;
import '../properties.dart';
import '../property_codec.dart' show parseOnOff;
import '../style_schemas.dart';
import 'edit_sink.dart';
import 'paragraph_properties.dart';
import 'primitives.dart';
import 'property_set.dart';
import 'run_properties.dart';

/// The kind of a style: what it formats (`w:type`).
enum DocxStyleType {
  /// A paragraph style, for `w:pStyle`.
  paragraph,

  /// A character style, for `w:rStyle`.
  character,

  /// A table style.
  table,

  /// A numbering style, for lists.
  numbering,
}

/// One style of a document (`w:style`).
///
/// A style read from a file keeps every child and attribute; the members
/// read and set the typed ones. A new style ([DocxStyle.new]) is a custom
/// style (`w:customStyle="1"`) that belongs to no document until
/// [DocxStyles.add] adds it. Setting a member to the value it reads is a
/// no-op. While the style is in a document, a link set ([basedOn], [next],
/// [link]) must name a style of the document and a [name] must be free, and
/// each set is one change of the document's change log.
final class DocxStyle {
  /// A new custom style of [type] with the id [id] and the name [name]
  /// shown to the user.
  ///
  /// [basedOn] is the style this one inherits from, [next] the paragraph
  /// style of the paragraph that follows (paragraph styles), and [link] the
  /// style of the other type linked to this one (a paragraph style and its
  /// character style); they are checked when the style is added. [uiPriority]
  /// orders the style in Word's lists, and [quickFormat] shows it in the
  /// style gallery.
  ///
  /// An empty [id], [name] or link, or one holding a character XML forbids,
  /// throws [ArgumentError]; a [uiPriority] outside 0 to 99 throws
  /// [RangeError].
  factory DocxStyle({
    required DocxStyleType type,
    required String id,
    required String name,
    String? basedOn,
    String? next,
    String? link,
    int? uiPriority,
    bool quickFormat = false,
  }) {
    _checkText(id, 'id');
    _checkText(name, 'name');
    _checkLink(basedOn, 'basedOn');
    _checkLink(next, 'next');
    _checkLink(link, 'link');
    _checkPriority(uiPriority);
    final DocxStyle style = DocxStyle._(
      const PropertyContainer.empty(),
      type: type,
      id: id,
      isDefault: false,
      isCustom: true,
      isNew: true,
    );
    final PropertySet set = style._set;
    set.setValue('name', name);
    set.setValue('basedOn', basedOn);
    set.setValue('next', next);
    set.setValue('link', link);
    set.setValue('uiPriority', uiPriority);
    if (quickFormat) {
      set.setValue('qFormat', true);
    }
    return style;
  }

  DocxStyle._(
    PropertyContainer source, {
    required this.type,
    required this.id,
    required this.isDefault,
    required this.isCustom,
    required bool isNew,
  }) : _isNew = isNew {
    paragraphProperties = newParagraphProperties(
      source.nestedOf('pPr') ?? const PropertyContainer.empty(),
      _sink,
      schema: paragraphPropertiesGeneralSchema,
    );
    runProperties = newRunProperties(
      source.nestedOf('rPr') ?? const PropertyContainer.empty(),
      _sink,
    );
    _set = _NestingSet(source, styleSchema, _sink, <String, NestedProperties>{
      'pPr': propertySetOfParagraphProperties(paragraphProperties),
      'rPr': propertySetOfRunProperties(runProperties),
    });
  }

  /// The kind of style (`w:type`): [DocxStyleType.paragraph] when the file
  /// has no `w:type`, and `null` when it has one the model does not know.
  final DocxStyleType? type;

  /// The style's id (`w:styleId`), which paragraphs and runs reference, or
  /// `null` when the file gives none.
  final String? id;

  /// Whether this is the default style of its type (`w:default`), the one
  /// content without a style of that type uses.
  final bool isDefault;

  /// Whether this is a custom style (`w:customStyle`) rather than one of
  /// Word's built-in styles.
  final bool isCustom;

  /// Whether the style was made with [DocxStyle.new], so its attributes are
  /// written from [type] and [id].
  final bool _isNew;

  /// The styles the style is in, or `null`.
  DocxStyles? _owner;

  /// The paragraph properties the style gives (`w:pPr`), created when one
  /// is first set.
  late final DocxParagraphProperties paragraphProperties;

  /// The run properties the style gives (`w:rPr`), created when one is
  /// first set.
  late final DocxRunProperties runProperties;

  late final PropertySet _set;

  DocxEditSink _sink() => _owner?._edits ?? DocxEditSink.none;

  /// The name shown to the user (`w:name`), or `null` when the file gives
  /// none the model can read. A built-in style's name is English, such as
  /// `heading 1`, whatever the language of the document.
  ///
  /// Setting `null`, the empty string or a name holding a character XML
  /// forbids throws [ArgumentError], and so does, while the style is in a
  /// document, the name of another of its styles (compared without regard
  /// to ASCII case).
  String? get name => _set.valueOf('name') as String?;

  set name(String? value) {
    if (value == null) {
      throw ArgumentError.notNull('name');
    }
    _checkText(value, 'name');
    final DocxStyles? owner = _owner;
    if (owner != null) {
      final DocxStyle? other = owner.byName(value);
      if (other != null && !identical(other, this)) {
        throw ArgumentError.value(
          value,
          'name',
          'Another style of the document has this name',
        );
      }
    }
    _set.setValue('name', value);
  }

  /// The id of the style this one inherits from (`w:basedOn`), or `null`.
  ///
  /// While the style is in a document, setting an id that names no style
  /// of its type, or one that would make the style inherit from itself,
  /// throws [ArgumentError]. `null` removes the link.
  String? get basedOn => _set.valueOf('basedOn') as String?;

  set basedOn(String? value) => _setLink('basedOn', value);

  /// The id of the style of the next paragraph (`w:next`), or `null`.
  ///
  /// While the style is in a document, setting an id that names none of its
  /// styles (or this one) throws [ArgumentError]. `null` removes it.
  String? get next => _set.valueOf('next') as String?;

  set next(String? value) => _setLink('next', value);

  /// The id of the style linked to this one (`w:link`): the character
  /// style of a paragraph style, or the other way round; `null` when there
  /// is none.
  ///
  /// While the style is in a document, setting an id that names none of
  /// its other styles throws [ArgumentError]. `null` removes it.
  String? get link => _set.valueOf('link') as String?;

  set link(String? value) => _setLink('link', value);

  /// Where Word lists the style (`w:uiPriority`), from 0 (first) to 99, or
  /// `null`.
  ///
  /// Setting a value outside 0 to 99 throws [RangeError].
  int? get uiPriority => _set.valueOf('uiPriority') as int?;

  set uiPriority(int? value) {
    _checkPriority(value);
    _set.setValue('uiPriority', value);
  }

  /// Whether Word shows the style in its style gallery (`w:qFormat`).
  ///
  /// Setting `false` removes `w:qFormat`.
  bool get quickFormat => _set.valueOf('qFormat') == true;

  set quickFormat(bool value) {
    if (value == quickFormat) {
      return;
    }
    _set.setValue('qFormat', value ? true : null);
  }

  void _setLink(String localName, String? value) {
    _checkLink(value, localName);
    final DocxStyles? owner = _owner;
    String? stored = value;
    if (owner != null && value != null) {
      stored = owner._checkedLink(this, localName, value);
    }
    _set.setValue(localName, stored);
  }

  @override
  String toString() => 'DocxStyle(${type?.name}, $id, $name)';
}

/// The document defaults (`w:docDefaults`): the run and paragraph
/// properties every style and paragraph starts from.
///
/// Both are created in the file when a property of them is first set; a
/// set is one change of the document's change log.
final class DocxDocumentDefaults {
  DocxDocumentDefaults._(
    PropertyContainer source,
    DocxEditSink Function() sink,
  ) {
    final PropertyContainer rPrDefault =
        source.nestedOf('rPrDefault') ?? const PropertyContainer.empty();
    final PropertyContainer pPrDefault =
        source.nestedOf('pPrDefault') ?? const PropertyContainer.empty();
    runProperties = newRunProperties(
      rPrDefault.nestedOf('rPr') ?? const PropertyContainer.empty(),
      sink,
    );
    paragraphProperties = newParagraphProperties(
      pPrDefault.nestedOf('pPr') ?? const PropertyContainer.empty(),
      sink,
      schema: paragraphPropertiesGeneralSchema,
    );
    _set = _NestingSet(
      source,
      docDefaultsSchema,
      sink,
      <String, NestedProperties>{
        'rPrDefault': _NestingSet(
          rPrDefault,
          rPrDefaultSchema,
          sink,
          <String, NestedProperties>{
            'rPr': propertySetOfRunProperties(runProperties),
          },
        ),
        'pPrDefault': _NestingSet(
          pPrDefault,
          pPrDefaultSchema,
          sink,
          <String, NestedProperties>{
            'pPr': propertySetOfParagraphProperties(paragraphProperties),
          },
        ),
      },
    );
  }

  /// The default run properties (`w:rPrDefault/w:rPr`).
  late final DocxRunProperties runProperties;

  /// The default paragraph properties (`w:pPrDefault/w:pPr`).
  late final DocxParagraphProperties paragraphProperties;

  late final PropertySet _set;
}

/// The styles of a document (`word/styles.xml`): the document defaults and
/// the styles, in document order.
///
/// Get it from `DocxDocument.styles`. A document without a styles part has
/// an empty one, which is added to the file at save once it holds a style
/// or a default.
final class DocxStyles {
  DocxStyles._(this._edits, this._root, List<Object> children) {
    PropertyContainer? defaults;
    for (final Object child in children) {
      switch (child) {
        case DocxStyle():
          child._owner = this;
          _styles.add(child);
          _children.add(child);
        case PropertyContainer() when defaults == null:
          defaults = child;
          _children.add(_defaultsSlot);
        case OpaqueXml():
          _children.add(child);
        default:
          throw ArgumentError.value(child, 'children', 'Not a styles child');
      }
    }
    _defaultsRead = defaults != null;
    _defaults = DocxDocumentDefaults._(
      defaults ?? const PropertyContainer.empty(),
      () => _edits,
    );
  }

  final DocxEdits _edits;

  /// The root's start tag, written as read.
  final XmlRoot _root;

  /// The root's children in document order: [OpaqueXml], [DocxStyle], and
  /// [_defaultsSlot] where the document defaults were read.
  final List<Object> _children = <Object>[];

  final List<DocxStyle> _styles = <DocxStyle>[];

  late final List<DocxStyle> _stylesView = UnmodifiableListView<DocxStyle>(
    _styles,
  );

  late final DocxDocumentDefaults _defaults;

  /// Whether the document defaults were read from the file, so they have a
  /// place among [_children].
  late final bool _defaultsRead;

  /// The document defaults. They are the same object every time.
  DocxDocumentDefaults get defaults => _defaults;

  /// The styles in document order. The list cannot be modified, and shows
  /// later edits; use [add].
  List<DocxStyle> get styles => _stylesView;

  /// The first style whose id is [id], compared exactly, or `null`.
  DocxStyle? byId(String id) {
    for (final DocxStyle s in _styles) {
      if (s.id == id) {
        return s;
      }
    }
    return null;
  }

  /// The first style whose name is [name], compared without regard to
  /// ASCII case as Word compares style names, or `null`: `byName('HEADING
  /// 1')` finds `heading 1`.
  DocxStyle? byName(String name) {
    final String key = _asciiLower(name);
    for (final DocxStyle s in _styles) {
      final String? n = s.name;
      if (n != null && _asciiLower(n) == key) {
        return s;
      }
    }
    return null;
  }

  /// Adds [style], a new one, after the last style and returns it.
  ///
  /// Its id and name must be free: an id or a name of a style of the
  /// document, compared without regard to ASCII case, throws
  /// [ArgumentError]. So does a [DocxStyle.basedOn], [DocxStyle.next] or
  /// [DocxStyle.link] that names no style of the document (`next` may name
  /// the style itself), a `basedOn` of another type, a `link` to the style
  /// itself, and a `basedOn` that would make the style inherit from itself.
  /// A style already in a document, this one or another, throws
  /// [StateError]. Nothing changes when it throws; otherwise the add is one
  /// transaction.
  DocxStyle add(DocxStyle style) {
    if (style._owner != null || !style._isNew) {
      throw StateError('The style is already in a document.');
    }
    final String id = style.id!;
    final String key = _asciiLower(id);
    for (final DocxStyle s in _styles) {
      final String? other = s.id;
      if (other != null && _asciiLower(other) == key) {
        throw ArgumentError.value(
          id,
          'style',
          'The document already has a style with this id',
        );
      }
    }
    final String name = style.name!;
    if (byName(name) != null) {
      throw ArgumentError.value(
        name,
        'style',
        'The document already has a style with this name',
      );
    }
    final Map<String, String> links = <String, String>{};
    for (final String localName in const <String>['basedOn', 'next', 'link']) {
      final String? value = style._set.valueOf(localName) as String?;
      if (value != null) {
        links[localName] = _checkedLink(style, localName, value);
      }
    }
    int at = _children.length;
    for (int i = _children.length - 1; i >= 0; i--) {
      if (_children[i] is DocxStyle) {
        at = i + 1;
        break;
      }
    }
    _edits.transaction(() {
      applyChange(_edits, _StyleAdded(this, at, _styles.length, style));
      links.forEach(style._set.setValue);
    });
    return style;
  }

  /// The id to store for the link [localName] of [style] to [id], checked
  /// against the document; throws [ArgumentError] when it is not allowed.
  String _checkedLink(DocxStyle style, String localName, String id) {
    if (localName == 'next' && id == style.id) {
      return id;
    }
    final String? resolved = _resolveLink(id);
    final DocxStyle? target = resolved == null ? null : byId(resolved);
    if (resolved == null || target == null) {
      throw ArgumentError.value(
        id,
        localName,
        'The document has no style with this id',
      );
    }
    if (identical(target, style) && localName == 'link') {
      throw ArgumentError.value(id, localName, 'A style cannot link itself');
    }
    if (localName == 'basedOn') {
      if (target.type != style.type) {
        throw ArgumentError.value(
          id,
          localName,
          'The style it names is of another type',
        );
      }
      if (_inherits(resolved, style)) {
        throw ArgumentError.value(
          id,
          localName,
          'The style would inherit from itself',
        );
      }
    }
    return resolved;
  }

  /// The id of the style of the document that a link set through the API
  /// to [id] stores, or `null` when there is none: [id] itself when a style
  /// has it (plan Ruling 5a).
  ///
  /// Recognizing the English id of a built-in style by its name and adding
  /// a missing built-in (Rulings 5b and 5c) come with the built-in catalog,
  /// here.
  String? _resolveLink(String id) => byId(id) == null ? null : id;

  /// Whether the style [id], or one it inherits from, is [style] or has its
  /// id: so basing [style] on [id] would make a cycle. A cycle already in
  /// the file ends the walk.
  bool _inherits(String id, DocxStyle style) {
    final Set<String> seen = <String>{};
    String? at = id;
    while (at != null && seen.add(at)) {
      if (at == style.id) {
        return true;
      }
      final DocxStyle? s = byId(at);
      if (identical(s, style)) {
        return true;
      }
      at = s?.basedOn;
    }
    return false;
  }
}

/// Marks where the document defaults were read among the root's children.
const Object _defaultsSlot = _DefaultsSlot();

final class _DefaultsSlot {
  const _DefaultsSlot();
}

/// A style added to a document's styles.
final class _StyleAdded implements Change {
  _StyleAdded(this._styles, this._childIndex, this._styleIndex, this._style);

  final DocxStyles _styles;
  final int _childIndex;
  final int _styleIndex;
  final DocxStyle _style;

  @override
  void revert() {
    _styles._children.removeAt(_childIndex);
    _styles._styles.removeAt(_styleIndex);
    _style._owner = null;
  }

  @override
  void reapply() {
    _styles._children.insert(_childIndex, _style);
    _styles._styles.insert(_styleIndex, _style);
    _style._owner = _styles;
  }
}

/// A property set whose nested containers are written from [_nested].
final class _NestingSet extends PropertySet {
  _NestingSet(
    super.source,
    super.schema,
    super.sink,
    Map<String, NestedProperties> nested,
  ) : _nested = Map<String, NestedProperties>.unmodifiable(nested);

  final Map<String, NestedProperties> _nested;

  @override
  Map<String, NestedProperties> get nested => _nested;
}

/// [text] in ASCII lower case; other characters stay.
String _asciiLower(String text) {
  final List<int> units = text.codeUnits.toList();
  bool changed = false;
  for (int i = 0; i < units.length; i++) {
    final int u = units[i];
    if (u >= 0x41 && u <= 0x5A) {
      units[i] = u + 0x20;
      changed = true;
    }
  }
  return changed ? String.fromCharCodes(units) : text;
}

/// Throws [ArgumentError] when [value], the [name] of a style, is empty or
/// holds a character XML forbids.
void _checkText(String value, String name) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty');
  }
  if (scrubXmlText(value).removed > 0) {
    throw ArgumentError.value(
      value,
      name,
      'Must not hold a character XML forbids',
    );
  }
}

void _checkLink(String? value, String name) {
  if (value != null) {
    _checkText(value, name);
  }
}

void _checkPriority(int? value) {
  if (value != null) {
    RangeError.checkValueInInterval(value, 0, maxUiPriority, 'uiPriority');
  }
}

/// The value of the attribute `w:<localName>` of [source], or `null`.
String? _wAttribute(PropertyContainer source, String localName) {
  for (final KeptAttribute a in source.attributes) {
    if (a.namespaceUri == Ns.w &&
        a.qualifiedName.substring(a.qualifiedName.indexOf(':') + 1) ==
            localName) {
      return a.value;
    }
  }
  return null;
}

/// The style read from the `w:style` container [source] (by
/// `styleSchema`), in no document yet.
DocxStyle readStyle(PropertyContainer source) {
  final String? type = _wAttribute(source, 'type');
  return DocxStyle._(
    source,
    type: type == null
        ? DocxStyleType.paragraph
        : DocxStyleType.values.asNameMap()[type],
    id: _wAttribute(source, 'styleId'),
    isDefault: parseOnOff(_wAttribute(source, 'default') ?? 'false') == true,
    isCustom: parseOnOff(_wAttribute(source, 'customStyle') ?? 'false') == true,
    isNew: false,
  );
}

/// The styles of a part whose root is [root] and whose children are
/// [children], in document order: an [OpaqueXml], a [DocxStyle] from
/// [readStyle], or the `w:docDefaults` container read by
/// `docDefaultsSchema` (the first only). Their edits are recorded in
/// [edits].
DocxStyles newStyles(DocxEdits edits, XmlRoot root, List<Object> children) =>
    DocxStyles._(edits, root, children);

/// The root start tag of [styles], as read.
XmlRoot stylesRootOf(DocxStyles styles) => styles._root;

/// What the styles part of [styles] writes inside its root, in order: each
/// [OpaqueXml] and [DocxStyle], and the document defaults as the
/// [NestedProperties] to write as `w:docDefaults`, in their place, or
/// before the latent styles and the first style when they were not read
/// (and only when they write something).
List<Object> stylesChildrenOf(DocxStyles styles) {
  final NestedProperties defaults = styles._defaults._set;
  final List<Object> out = <Object>[
    for (final Object c in styles._children)
      identical(c, _defaultsSlot) ? defaults : c,
  ];
  if (!styles._defaultsRead && !defaults.writesNothing) {
    int at = out.length;
    for (int i = 0; i < out.length; i++) {
      final Object c = out[i];
      if (c is DocxStyle ||
          (c is OpaqueXml &&
              c.namespaceUri == Ns.w &&
              c.localName == 'latentStyles')) {
        at = i;
        break;
      }
    }
    out.insert(at, defaults);
  }
  return out;
}

/// Whether [styles] holds anything a styles part must keep: a child read,
/// a style, or a document default set (plan Ruling 7).
bool stylesHoldSomething(DocxStyles styles) =>
    styles._children.isNotEmpty || !styles._defaults._set.writesNothing;

/// The property set of [style], which writes it as `w:style`.
PropertySet stylePropertySetOf(DocxStyle style) => style._set;

/// The attributes to write on the `w:style` of [style] with [prefix] bound
/// to WordprocessingML: `w:type`, `w:customStyle` and `w:styleId` for a new
/// style, `null` for one read (its attributes are kept as read).
List<KeptAttribute>? newStyleAttributesOf(DocxStyle style, String prefix) {
  if (!style._isNew) {
    return null;
  }
  return <KeptAttribute>[
    (
      qualifiedName: '$prefix:type',
      namespaceUri: Ns.w,
      value: style.type!.name,
    ),
    (qualifiedName: '$prefix:customStyle', namespaceUri: Ns.w, value: '1'),
    (qualifiedName: '$prefix:styleId', namespaceUri: Ns.w, value: style.id!),
  ];
}
