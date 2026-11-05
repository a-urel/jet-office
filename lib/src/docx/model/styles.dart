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
/// A style id set through the API resolves against the document (Ruling 5):
/// an id it defines is kept, the English id of a built-in becomes the id of
/// the style of that name, and a built-in the document lacks is added from
/// the catalog (`builtin_styles.dart`), with the styles it depends on mapped
/// to the document's own (Ruling 6). [DocxStyles.idOf] and
/// [DocxStyles.ensure] do the same for a built-in by name.
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
import '../../xml/xml_pull_reader.dart';
import '../builtin_styles.dart';
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
/// [link]) must name a style of the document, or the English id of a
/// built-in style of the right type, which becomes the document's id for it
/// (and is added when the document lacks it), and a [name] must be free.
/// Each set is one transaction of the document's change log.
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
    required DocxStyleType? type,
    required String? id,
    required bool isDefault,
    required bool isCustom,
    required bool isNew,
  }) : this._attached(
         _Attachment(),
         source,
         type: type,
         id: id,
         isDefault: isDefault,
         isCustom: isCustom,
         isNew: isNew,
       );

  DocxStyle._attached(
    _Attachment attachment,
    PropertyContainer source, {
    required DocxStyleType? type,
    required String? id,
    required bool isDefault,
    required bool isCustom,
    required bool isNew,
  }) : this._built(
         attachment,
         source,
         newParagraphProperties(
           source.nestedOf('pPr') ?? const PropertyContainer.empty(),
           attachment.sink,
           schema: paragraphPropertiesGeneralSchema,
         ),
         newRunProperties(
           source.nestedOf('rPr') ?? const PropertyContainer.empty(),
           attachment.sink,
         ),
         type: type,
         id: id,
         isDefault: isDefault,
         isCustom: isCustom,
         isNew: isNew,
       );

  DocxStyle._built(
    this._attachment,
    PropertyContainer source,
    this.paragraphProperties,
    this.runProperties, {
    required this.type,
    required this.id,
    required this.isDefault,
    required this.isCustom,
    required bool isNew,
  }) : _isNew = isNew,
       _set = _NestingSet(
         source,
         styleSchema,
         _attachment.sink,
         <String, NestedProperties>{
           'pPr': propertySetOfParagraphProperties(paragraphProperties),
           'rPr': propertySetOfRunProperties(runProperties),
         },
       );

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

  /// Whether the style was not read from the file (made with
  /// [DocxStyle.new], or a built-in added), so its attributes are written
  /// from [type], [id] and the flags.
  final bool _isNew;

  /// The document the style is in, shared with the sink of its property
  /// sets.
  final _Attachment _attachment;

  /// The styles the style is in, or `null`.
  DocxStyles? get _owner => _attachment.owner;

  set _owner(DocxStyles? value) => _attachment.owner = value;

  /// The paragraph properties the style gives (`w:pPr`), created when one
  /// is first set.
  final DocxParagraphProperties paragraphProperties;

  /// The run properties the style gives (`w:rPr`), created when one is
  /// first set.
  final DocxRunProperties runProperties;

  final PropertySet _set;

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
  /// of its type (after the English id of a built-in is resolved, see
  /// [DocxStyle]), or one that would make the style inherit from itself,
  /// throws [ArgumentError]. `null` removes the link.
  String? get basedOn => _set.valueOf('basedOn') as String?;

  set basedOn(String? value) => _setLink('basedOn', value);

  /// The id of the style of the next paragraph (`w:next`), or `null`.
  ///
  /// While the style is in a document, setting an id that names none of its
  /// styles or this one (after the English id of a built-in is resolved, see
  /// [DocxStyle]) throws [ArgumentError]. `null` removes it.
  String? get next => _set.valueOf('next') as String?;

  set next(String? value) => _setLink('next', value);

  /// The id of the style linked to this one (`w:link`): the character
  /// style of a paragraph style, or the other way round; `null` when there
  /// is none.
  ///
  /// While the style is in a document, setting an id that names no style
  /// of the other type (a character style for a paragraph style, or the
  /// other way round), after the English id of a built-in is resolved (see
  /// [DocxStyle]), throws [ArgumentError]. `null` removes it.
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
    if (value == _set.valueOf(localName)) {
      return;
    }
    final DocxStyles? owner = _owner;
    if (owner == null || value == null) {
      _set.setValue(localName, value);
      return;
    }
    owner._edits.transaction(
      () =>
          _set.setValue(localName, owner._checkedLink(this, localName, value)),
    );
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
  factory DocxDocumentDefaults._read(
    PropertyContainer source,
    DocxEditSink Function() sink,
  ) {
    final PropertyContainer rPrDefault =
        source.nestedOf('rPrDefault') ?? const PropertyContainer.empty();
    final PropertyContainer pPrDefault =
        source.nestedOf('pPrDefault') ?? const PropertyContainer.empty();
    final DocxRunProperties runProperties = newRunProperties(
      rPrDefault.nestedOf('rPr') ?? const PropertyContainer.empty(),
      sink,
    );
    final DocxParagraphProperties paragraphProperties = newParagraphProperties(
      pPrDefault.nestedOf('pPr') ?? const PropertyContainer.empty(),
      sink,
      schema: paragraphPropertiesGeneralSchema,
    );
    return DocxDocumentDefaults._(
      runProperties,
      paragraphProperties,
      _NestingSet(source, docDefaultsSchema, sink, <String, NestedProperties>{
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
      }),
    );
  }

  DocxDocumentDefaults._(
    this.runProperties,
    this.paragraphProperties,
    this._set,
  );

  /// The default run properties (`w:rPrDefault/w:rPr`).
  final DocxRunProperties runProperties;

  /// The default paragraph properties (`w:pPrDefault/w:pPr`).
  final DocxParagraphProperties paragraphProperties;

  final PropertySet _set;
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
          final String? id = child.id;
          if (id != null) {
            _byId.putIfAbsent(id, () => child);
          }
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
    _defaults = DocxDocumentDefaults._read(
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

  /// The first style of each id.
  final Map<String, DocxStyle> _byId = <String, DocxStyle>{};

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
  DocxStyle? byId(String id) => _byId[id];

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

  /// The id of the built-in [style] in this document, or `null` when the
  /// document lacks it. Nothing is added.
  ///
  /// A built-in is the first style, in document order, that has its
  /// [DocxBuiltInStyle.name], compared without regard to ASCII case. The id
  /// and the outline level say nothing: `heading 1` is `Balk1` in a Turkish
  /// document and `berschrift1` in a German one, and a style with the id
  /// `Heading1` and another name is not it. A style of that name without an
  /// id cannot be referenced, and does not count. The type of the style is
  /// not looked at: a style of another type that carries the built-in's name
  /// is returned, since the document cannot hold a second style of that
  /// name, and a reference to it as the built-in's type is reported at save
  /// (`DocxWarningCode.styleNotFound`).
  String? idOf(DocxBuiltInStyle style) => _idNamed(style.name);

  /// The id of the built-in [style] in this document, added with Word's
  /// definition when the document lacks it ([idOf]).
  ///
  /// The added style takes the English id, or that id with the smallest
  /// suffix `_1`, `_2`, … that is free. What it is based on, followed by
  /// and linked to maps to the document: `Normal`, `DefaultParagraphFont` and
  /// `TableNormal` to the default style of that type, others by name, and a
  /// style still missing is added the same way. The default style of a type
  /// stays the one the document has. Styles that are empty gain `Normal`
  /// and `DefaultParagraphFont` as well. It is one transaction: nothing
  /// stays when it fails.
  String ensure(DocxBuiltInStyle style) {
    String? id = idOf(style);
    if (id != null) {
      return id;
    }
    _edits.transaction(() {
      final Map<String, String> planned = <String, String>{};
      if (_styles.isEmpty) {
        _dependencyId(DocxBuiltInStyle.normal.id, planned);
        _dependencyId(DocxBuiltInStyle.defaultParagraphFont.id, planned);
      }
      id = idOf(style) ?? _addBuiltIn(style.id, planned);
    });
    return id!;
  }

  /// Adds [style], a new one, after the last style and returns it.
  ///
  /// A [DocxStyle.basedOn], [DocxStyle.next] or [DocxStyle.link] that is the
  /// English id of a built-in style of the right type, and that the document
  /// does not define, becomes the document's id for it, and the built-in is
  /// added when the document lacks it ([ensure]).
  ///
  /// Its id and name must be free: an id or a name of a style of the
  /// document, compared without regard to ASCII case, throws
  /// [ArgumentError]. So does a link that names no style of the document
  /// (`next` may name the style itself), a `basedOn` of another type, a
  /// `link` to the style itself or to one that is not of the other type, and
  /// a `basedOn` that would make the style inherit from itself. A style
  /// already in a document, this one or another, throws [StateError].
  /// Nothing changes when it throws; otherwise the add is one transaction.
  DocxStyle add(DocxStyle style) {
    if (style._owner != null || !style._isNew) {
      throw StateError('The style is already in a document.');
    }
    _edits.transaction(() {
      final Map<String, String> links = <String, String>{};
      for (final String localName in _linkNames) {
        final String? value = style._set.valueOf(localName) as String?;
        if (value != null) {
          links[localName] = _checkedLink(style, localName, value);
        }
      }
      // After the links: a built-in they add may take the id or the name.
      _checkFree(style);
      _append(style);
      links.forEach(style._set.setValue);
    });
    return style;
  }

  /// Throws [ArgumentError] when the id or the name of [style] is in use.
  void _checkFree(DocxStyle style) {
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
  }

  /// Adds [style] after the last style. Must run inside a transaction.
  void _append(DocxStyle style) {
    int at = _children.length;
    for (int i = _children.length - 1; i >= 0; i--) {
      if (_children[i] is DocxStyle) {
        at = i + 1;
        break;
      }
    }
    applyChange(_edits, _StyleAdded(this, at, _styles.length, style));
  }

  /// The id of the first style named [name] that has an id, or `null`.
  String? _idNamed(String name) {
    final String key = _asciiLower(name);
    for (final DocxStyle s in _styles) {
      final String? n = s.name;
      if (s.id != null && n != null && _asciiLower(n) == key) {
        return s.id;
      }
    }
    return null;
  }

  /// Whether a style is the default of [type], with an id or without.
  bool _hasDefault(DocxStyleType? type) =>
      _styles.any((DocxStyle s) => s.isDefault && s.type == type);

  /// The id of the first default style of [type] that has one, or `null`.
  String? _defaultIdOf(DocxStyleType? type) {
    for (final DocxStyle s in _styles) {
      if (s.isDefault && s.type == type && s.id != null) {
        return s.id;
      }
    }
    return null;
  }

  /// The id in this document of the catalog style [englishId], which a
  /// built-in depends on, added if missing (plan Ruling 6). [planned] holds
  /// the ids of the styles being added, by English id, so a style and the
  /// one linked to it find each other. Must run inside a transaction.
  String _dependencyId(String englishId, Map<String, String> planned) {
    final String? inProgress = planned[englishId];
    if (inProgress != null) {
      return inProgress;
    }
    final String? found = _baseTypes.containsKey(englishId)
        ? _defaultIdOf(_baseTypes[englishId])
        : null;
    return found ??
        _idNamed(_catalogSource(englishId).viewOf('name')! as String) ??
        _addBuiltIn(englishId, planned);
  }

  /// Adds the catalog style [englishId] with what it depends on and returns
  /// its id. Must run inside a transaction.
  String _addBuiltIn(String englishId, Map<String, String> planned) {
    final String id = _freeId(englishId, planned);
    planned[englishId] = id;
    final PropertyContainer source = _catalogSource(englishId);
    final DocxStyle read = readStyle(source);
    final DocxStyle style = DocxStyle._(
      source,
      type: read.type,
      id: id,
      isDefault: read.isDefault && !_hasDefault(read.type),
      isCustom: read.isCustom,
      isNew: true,
    );
    for (final String localName in _linkNames) {
      final String? target = style._set.valueOf(localName) as String?;
      if (target != null) {
        style._set.setValue(localName, _dependencyId(target, planned));
      }
    }
    _append(style);
    return id;
  }

  /// [englishId] or, when a style has it, that id with the smallest suffix
  /// `_1`, `_2`, … that is free; ids compare as in [add].
  String _freeId(String englishId, Map<String, String> planned) {
    final Set<String> taken = <String>{
      for (final DocxStyle s in _styles)
        if (s.id != null) _asciiLower(s.id!),
      for (final String id in planned.values) _asciiLower(id),
    };
    String id = englishId;
    for (int i = 1; taken.contains(_asciiLower(id)); i++) {
      id = '${englishId}_$i';
    }
    return id;
  }

  /// The id to store for the link [localName] of [style] to [id], checked
  /// against the document; throws [ArgumentError] when it is not allowed.
  ///
  /// Must run inside a transaction: it may add a built-in style.
  String _checkedLink(DocxStyle style, String localName, String id) {
    if (id == style.id) {
      return switch (localName) {
        'next' => id,
        'link' => throw ArgumentError.value(
          id,
          localName,
          'A style cannot link itself',
        ),
        _ => throw ArgumentError.value(
          id,
          localName,
          'The style would inherit from itself',
        ),
      };
    }
    final DocxStyleType? type = localName == 'link'
        ? _linkedType(style.type)
        : style.type;
    final String? resolved = _resolve(id, type);
    final DocxStyle? target = resolved == null ? null : byId(resolved);
    if (resolved == null || target == null) {
      throw ArgumentError.value(
        id,
        localName,
        'The document has no style with this id',
      );
    }
    if (localName == 'link' && target.type != type) {
      throw ArgumentError.value(
        id,
        localName,
        'The style it names is not of the other type',
      );
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

  /// The id of the style of the document that a reference set through the
  /// API to [id], naming a style of [type], stores, or `null` when there is
  /// none (plan Ruling 5): [id] itself when a style has it, whatever its
  /// type (a), else, when [id] is the English id of a built-in of [type],
  /// that built-in's id, added if missing (b, c).
  String? _resolve(String id, DocxStyleType? type) {
    if (_byId.containsKey(id)) {
      return id;
    }
    final DocxBuiltInStyle? builtIn = builtInStyleOfId(id);
    return builtIn == null || builtIn.type != type ? null : ensure(builtIn);
  }

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

/// The links of a style, in the order they are resolved.
const List<String> _linkNames = <String>['basedOn', 'next', 'link'];

/// The catalog styles that every style of a type starts from, which map to
/// the document's default style of that type (plan Ruling 6).
const Map<String, DocxStyleType> _baseTypes = <String, DocxStyleType>{
  'Normal': DocxStyleType.paragraph,
  'DefaultParagraphFont': DocxStyleType.character,
  'TableNormal': DocxStyleType.table,
};

/// The type a style of [type] links to, or `null` when it links to none.
DocxStyleType? _linkedType(DocxStyleType? type) => switch (type) {
  DocxStyleType.paragraph => DocxStyleType.character,
  DocxStyleType.character => DocxStyleType.paragraph,
  _ => null,
};

/// Word's definition of the catalog style [englishId], read as a file's
/// style is.
PropertyContainer _catalogSource(String englishId) {
  final XmlPullReader r = XmlPullReader(builtInStyleXml(englishId));
  r.nextTag();
  return PropertyContainer.read(r, styleSchema).withoutDeclarations();
}

/// The document a style is in, which its property sets report to.
final class _Attachment {
  DocxStyles? owner;

  DocxEditSink sink() => owner?._edits ?? DocxEditSink.none;
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
    _styles._byId.remove(_style.id);
    _style._owner = null;
  }

  @override
  void reapply() {
    _styles._children.insert(_childIndex, _style);
    _styles._styles.insert(_styleIndex, _style);
    _styles._byId[_style.id!] = _style;
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

/// The id to store for a reference to the style [id] of [type] set through
/// the API: what [styles] resolves it to, or [id] as given when it names
/// nothing the document has or the catalog can add (plan Ruling 5d).
String resolveStyleId(DocxStyles styles, String id, DocxStyleType type) =>
    styles._resolve(id, type) ?? id;

/// Whether [styles] defines a style of [type] with the id [id].
bool definesStyle(DocxStyles styles, String id, DocxStyleType type) =>
    styles.byId(id)?.type == type;

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
/// to WordprocessingML: `w:type`, `w:default` and `w:customStyle` when they
/// hold, and `w:styleId` for a style not read from the file, a new one or a
/// built-in added; `null` for one read (its attributes are kept as read).
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
    if (style.isDefault)
      (qualifiedName: '$prefix:default', namespaceUri: Ns.w, value: '1'),
    if (style.isCustom)
      (qualifiedName: '$prefix:customStyle', namespaceUri: Ns.w, value: '1'),
    (qualifiedName: '$prefix:styleId', namespaceUri: Ns.w, value: style.id!),
  ];
}
