/// The numbering of a document: the list definitions of
/// `word/numbering.xml`, read, looked up, edited and added to.
///
/// Not ported from Quds; written for jet_office.
///
/// A list in WordprocessingML has two halves. An abstract definition
/// ([DocxAbstractNumbering], `w:abstractNum`) gives up to nine levels
/// ([DocxNumberingLevel], `w:lvl`): how each level shows its number and how
/// far it is indented. An instance ([DocxNumberingInstance], `w:num`) is
/// what a paragraph names in its `w:numPr`; it points at one abstract
/// definition and may override the start of some levels
/// ([DocxLevelOverride], `w:lvlOverride`). Two instances of one definition
/// number apart.
///
/// [DocxNumbering] holds the root's children in document order. An
/// abstract definition and an instance whose id parses (at most nine
/// digits, plan Ruling 4) are typed; one whose id does not parse, the
/// picture bullets (`w:numPicBullet`), `w:numIdMacAtCleanup` and every
/// other child are kept as read, in place. Inside a definition, a level
/// whose `w:ilvl` is 0 to 8 is typed by `levelSchema`, and every other
/// child (`w:nsid`, `w:multiLevelType`, `w:tmpl`, a level past the ninth)
/// is kept as read; inside an instance, `w:abstractNumId` is read and a
/// level override is typed by `levelOverrideSchema`. Every attribute
/// (`w:tplc`, `w:tentative`, `w15:restartNumberingAfterBreak`,
/// `w16cid:durableId`) is kept. An instance whose `w:abstractNumId` is
/// missing, repeated or does not parse is kept and not listed, but its id
/// stays taken.
///
/// New definitions take the lowest unused ids (plan Ruling 9): an abstract
/// definition from 0, an instance from 1, since `w:numId` 0 means "no list";
/// ids are taken over every definition whose id parses. Every edit is
/// recorded in the document's change log, so a transaction that fails puts
/// everything back.
///
/// The part reads and writes through the functions at the end of this
/// library (`numbering_part.dart`).
library;

import 'dart:collection';

import '../../opc/change_log.dart';
import '../../opc/ooxml.dart' show Ns;
import '../../opc/opaque_xml.dart';
import '../../xml/xml_pull_reader.dart';
import '../builtin_numbering.dart';
import '../numbering_schemas.dart';
import '../paragraph_property_codecs.dart'
    show IntValCodec, paragraphPropertiesGeneralSchema;
import '../properties.dart';
import '../property_codec.dart';
import '../units.dart' show maxNumId;
import 'edit_sink.dart';
import 'formatting.dart';
import 'numbering_formats.dart';
import 'primitives.dart';
import 'property_set.dart';

/// A property of a numbering level, to name it for
/// [DocxNumberingLevel.clear].
enum DocxNumberingLevelProperty {
  /// The number format, [DocxNumberingLevel.format] (`w:numFmt`).
  format('numFmt'),

  /// The level text, [DocxNumberingLevel.text] (`w:lvlText`).
  text('lvlText'),

  /// The start, [DocxNumberingLevel.start] (`w:start`).
  start('start'),

  /// The alignment, [DocxNumberingLevel.alignment] (`w:lvlJc`).
  alignment('lvlJc'),

  /// The indentation, [DocxNumberingLevel.indentation] (`w:pPr/w:ind`).
  indentation('ind', inParagraph: true),

  /// The bullet font, [DocxNumberingLevel.bulletFont]
  /// (`w:rPr/w:rFonts`).
  bulletFont('rFonts', inRun: true);

  const DocxNumberingLevelProperty(
    this._element, {
    bool inParagraph = false,
    bool inRun = false,
  }) : _inParagraph = inParagraph,
       _inRun = inRun;

  final String _element;
  final bool _inParagraph;
  final bool _inRun;
}

/// One level of a list definition (`w:lvl`): how the number of a paragraph
/// at that level looks and where it sits.
///
/// Every member is nullable, `null` meaning "not set here", and reads
/// `null` too when the file holds a value the model cannot type; such a
/// child is written back as read. Setting a member to
/// the value it reads is a no-op, so `null` does not remove a child the
/// model cannot type; [clear] does. Each set of a level in a document is
/// one change of its change log. `w:tplc`, `w:tentative` and every child
/// the model does not type stay as read.
final class DocxNumberingLevel {
  factory DocxNumberingLevel._read(
    PropertyContainer source,
    int level,
    _Attachment attachment,
  ) {
    final DocxEditSink Function() sink = attachment.sink;
    final _Set pPr = _Set(
      source.nestedOf('pPr') ?? const PropertyContainer.empty(),
      paragraphPropertiesGeneralSchema,
      sink,
    );
    final _Set rPr = _Set(
      source.nestedOf('rPr') ?? const PropertyContainer.empty(),
      levelRunPropertiesSchema,
      sink,
    );
    return DocxNumberingLevel._(
      level,
      _Set(source, levelSchema, sink, <String, NestedProperties>{
        'pPr': pPr,
        'rPr': rPr,
      }),
      pPr,
      rPr,
    );
  }

  DocxNumberingLevel._(this.level, this._set, this._pPr, this._rPr);

  /// The level, from 0 (the outermost) to 8 (`w:ilvl`).
  final int level;

  final PropertySet _set;
  final PropertySet _pPr;
  final PropertySet _rPr;

  /// How the number is shown (`w:numFmt`), or `null`.
  ///
  /// A format the model does not type (`chicago`, the other scripts'
  /// counting systems, a custom `w:format`) reads `null`.
  DocxNumberFormat? get format => _set.valueOf('numFmt') as DocxNumberFormat?;

  set format(DocxNumberFormat? value) => _set.setValue('numFmt', value);

  /// The text of the number (`w:lvlText`), or `null`: `%1` stands for the
  /// number of level 0, `%2` for that of level 1, and so on, so `%1.%2.`
  /// gives `1.3.`; a bullet's text is the bullet character.
  ///
  /// Setting a text with a `%` that no digit from 1 to 9 follows, or with
  /// a character XML forbids, throws [ArgumentError]; such a text read from
  /// a file reads `null`.
  String? get text => _set.valueOf('lvlText') as String?;

  set text(String? value) {
    if (value != null && !isLevelText(value)) {
      throw ArgumentError.value(
        value,
        'text',
        'Each % must be followed by a level from 1 to 9, and the text must '
            'not hold a character XML forbids',
      );
    }
    _set.setValue('lvlText', value);
  }

  /// The number the level starts at (`w:start`), from 0 to 32767, or
  /// `null` (Word starts at 0 then).
  ///
  /// Setting a value outside 0 to 32767 throws [RangeError].
  int? get start => _set.valueOf('start') as int?;

  set start(int? value) {
    if (value != null) {
      RangeError.checkValueInInterval(value, 0, maxLevelStart, 'start');
    }
    _set.setValue('start', value);
  }

  /// Where the number sits against the indentation (`w:lvlJc`), or `null`.
  DocxLevelAlignment? get alignment =>
      _set.valueOf('lvlJc') as DocxLevelAlignment?;

  set alignment(DocxLevelAlignment? value) => _set.setValue('lvlJc', value);

  /// The indentation of a paragraph at this level (`w:pPr/w:ind`), or
  /// `null`: the hanging indentation is where the text starts after the
  /// number.
  ///
  /// It reads `null` where `DocxParagraphProperties.indentation` would.
  DocxIndentation? get indentation => _pPr.valueOf('ind') as DocxIndentation?;

  set indentation(DocxIndentation? value) => _pPr.setValue('ind', value);

  /// The font of the number or bullet (`w:rPr/w:rFonts`), or `null`; a
  /// bullet such as U+F0B7 needs its symbol font (`Symbol`).
  ///
  /// A set writes the slots the value names, normally `w:ascii` and
  /// `w:hAnsi`, and keeps every other attribute of the element (`w:cs`,
  /// `w:hint`) as read; without a `w:hint` read, it writes
  /// `w:hint="default"`, as Word does. Setting `null` removes those slots
  /// only: while another attribute remains the element stays with it, and
  /// [clear] removes it.
  DocxFonts? get bulletFont => _rPr.valueOf('rFonts') as DocxFonts?;

  set bulletFont(DocxFonts? value) => _rPr.setValue('rFonts', value);

  /// Removes [property] from the level, whatever the model reads of it: a
  /// child it does not type (`w:start w:val="1in"`, `w:numFmt
  /// w:val="chicago"`, `w:lvlText w:val="%0"`) goes too. Clearing
  /// [DocxNumberingLevelProperty.bulletFont] removes the `w:rFonts` of the
  /// level's `w:rPr` and leaves the rest of it. Nothing is recorded when
  /// the level has no such child.
  void clear(DocxNumberingLevelProperty property) {
    final PropertySet set = property._inParagraph
        ? _pPr
        : property._inRun
        ? _rPr
        : _set;
    set.clearChild(property._element);
  }

  @override
  String toString() => 'DocxNumberingLevel($level, ${format?.name}, $text)';
}

/// An abstract list definition (`w:abstractNum`): the levels a list's
/// instances share.
///
/// Its header (`w:nsid`, `w:multiLevelType`, `w:tmpl`, `w:name`, the style
/// links) and every attribute are kept as read.
final class DocxAbstractNumbering {
  DocxAbstractNumbering._(
    this.id,
    this._start,
    this._children,
    this._attachment,
  ) : _levels = List<DocxNumberingLevel>.unmodifiable(
        _children.whereType<DocxNumberingLevel>(),
      );

  /// The id instances name it by (`w:abstractNumId`).
  final int id;

  final NumberingStart _start;

  /// The children in document order: [OpaqueXml] and [DocxNumberingLevel].
  final List<Object> _children;

  final List<DocxNumberingLevel> _levels;

  final _Attachment _attachment;

  /// The levels the model types (those whose `w:ilvl` is 0 to 8), in
  /// document order. Unmodifiable.
  List<DocxNumberingLevel> get levels => _levels;

  @override
  String toString() => 'DocxAbstractNumbering($id)';
}

/// A start override of one level of a list instance (`w:lvlOverride`).
///
/// A `w:lvl` inside it, which replaces the level outright, is kept as
/// read.
final class DocxLevelOverride {
  DocxLevelOverride._(this.level, this._set, {required bool isNew})
    : _isNew = isNew;

  /// The level overridden, from 0 to 8 (`w:ilvl`).
  final int level;

  final PropertySet _set;

  /// Whether the override was added through the API, so its `w:ilvl` is
  /// written from [level].
  final bool _isNew;

  /// The number the level starts at in this instance
  /// (`w:startOverride`), from 0 to 32767, or `null`.
  ///
  /// Setting a value outside 0 to 32767 throws [RangeError]; `null`
  /// removes the override of the start.
  int? get startOverride => _set.valueOf('startOverride') as int?;

  set startOverride(int? value) {
    if (value != null) {
      RangeError.checkValueInInterval(value, 0, maxLevelStart, 'startOverride');
    }
    _set.setValue('startOverride', value);
  }

  /// Removes the `w:startOverride`, whatever the model reads of it (a
  /// value out of range, say), which setting `null` does not when it reads
  /// `null`. Nothing is recorded when there is none.
  void clearStartOverride() => _set.clearChild('startOverride');

  @override
  String toString() => 'DocxLevelOverride($level, $startOverride)';
}

/// A list instance (`w:num`): what a paragraph's numbering names.
///
/// Get one from [DocxNumbering.instances], [DocxNumbering.instanceById] or
/// [DocxNumbering.addInstance], and put a paragraph in it with [ref].
final class DocxNumberingInstance {
  DocxNumberingInstance._(
    this.id,
    this._abstractId,
    this._start,
    this._children,
    this._attachment,
  ) : _overrides = List<DocxLevelOverride>.unmodifiable(
        _children.whereType<DocxLevelOverride>(),
      );

  /// The id paragraphs name it by (`w:numId`), from 1.
  final int id;

  /// The abstract definition's id, or `null` when the file gives none the
  /// model can read (the instance is then not listed).
  final int? _abstractId;

  final NumberingStart _start;

  /// The children in document order: [OpaqueXml], [DocxLevelOverride] and,
  /// in an instance added through the API, [newAbstractNumId].
  final List<Object> _children;

  final List<DocxLevelOverride> _overrides;

  final _Attachment _attachment;

  /// The id of the abstract definition the instance uses
  /// (`w:abstractNumId`).
  int get abstractId => _abstractId!;

  /// The abstract definition the instance uses: the first of the document
  /// with [abstractId], or `null` when there is none (a dangling id read
  /// from a file).
  DocxAbstractNumbering? get abstractNumbering =>
      _attachment.owner?._abstractById(abstractId);

  /// The start overrides, in document order. Unmodifiable.
  List<DocxLevelOverride> get overrides => _overrides;

  /// A reference to this instance at [level], for
  /// `DocxParagraphProperties.numbering`.
  ///
  /// A [level] outside 0 to 8 throws [RangeError].
  DocxNumberingRef ref({int level = 0}) => DocxNumberingRef(id, level: level);

  @override
  String toString() => 'DocxNumberingInstance($id, abstract $_abstractId)';
}

/// The numbering of a document (`word/numbering.xml`): the list
/// definitions and instances, in document order.
///
/// Get it from `DocxDocument.numbering`. A document without a numbering
/// part has an empty one, which is added to the file at save once it
/// holds a definition.
final class DocxNumbering {
  DocxNumbering._(this._edits, this._root, List<Object> children) {
    for (final Object child in children) {
      switch (child) {
        case DocxAbstractNumbering():
          child._attachment.owner = this;
          _abstracts.add(child);
        case DocxNumberingInstance():
          child._attachment.owner = this;
          if (child._abstractId != null) {
            _instances.add(child);
          }
        case OpaqueXml():
          break;
        default:
          throw ArgumentError.value(child, 'children', 'Not a numbering child');
      }
      _children.add(child);
    }
  }

  final DocxEdits _edits;

  /// The root's start tag, written as read.
  final XmlRoot _root;

  /// The root's children in document order: [OpaqueXml],
  /// [DocxAbstractNumbering] and [DocxNumberingInstance] (listed or not).
  final List<Object> _children = <Object>[];

  final List<DocxAbstractNumbering> _abstracts = <DocxAbstractNumbering>[];

  final List<DocxNumberingInstance> _instances = <DocxNumberingInstance>[];

  late final List<DocxAbstractNumbering> _abstractsView =
      UnmodifiableListView<DocxAbstractNumbering>(_abstracts);

  late final List<DocxNumberingInstance> _instancesView =
      UnmodifiableListView<DocxNumberingInstance>(_instances);

  /// The abstract definitions in document order. The list cannot be
  /// modified, and shows later edits.
  List<DocxAbstractNumbering> get abstractNumberings => _abstractsView;

  /// The instances in document order. The list cannot be modified, and
  /// shows later edits; use [addInstance].
  List<DocxNumberingInstance> get instances => _instancesView;

  /// The first instance whose id is [numId], or `null`.
  DocxNumberingInstance? instanceById(int numId) {
    for (final DocxNumberingInstance n in _instances) {
      if (n.id == numId) {
        return n;
      }
    }
    return null;
  }

  /// Adds a new instance of [abstract] with the lowest unused id (from 1)
  /// and returns it: a list of its own, numbered apart from the other
  /// instances of [abstract].
  ///
  /// [startOverrides] maps a level (0 to 8) to the number it starts at in
  /// this instance (0 to 32767); each is written as a `w:lvlOverride` with
  /// a `w:startOverride`. The instance goes after the last instance, before
  /// `w:numIdMacAtCleanup`.
  ///
  /// An [abstract] that is not one of this document's throws
  /// [ArgumentError], and a level or a start out of range throws
  /// [RangeError]; nothing changes then. The add is one transaction.
  DocxNumberingInstance addInstance(
    DocxAbstractNumbering abstract, {
    Map<int, int> startOverrides = const <int, int>{},
  }) {
    if (!identical(abstract._attachment.owner, this)) {
      throw ArgumentError.value(
        abstract,
        'abstract',
        'Not an abstract definition of this document',
      );
    }
    startOverrides.forEach((int level, int start) {
      RangeError.checkValueInInterval(level, 0, maxListLevel, 'level');
      RangeError.checkValueInInterval(start, 0, maxLevelStart, 'start');
    });
    final int id = _lowestUnused(<int>{
      for (final Object c in _children)
        if (c is DocxNumberingInstance) c.id,
    }, 1);
    final _Attachment attachment = _Attachment();
    final List<int> levels = startOverrides.keys.toList()..sort();
    final List<Object> children = <Object>[
      newAbstractNumId,
      for (final int level in levels)
        DocxLevelOverride._(
          level,
          _Set(
            const PropertyContainer.empty(),
            levelOverrideSchema,
            attachment.sink,
          )..setValue('startOverride', startOverrides[level]),
          isNew: true,
        ),
    ];
    final DocxNumberingInstance instance = DocxNumberingInstance._(
      id,
      abstract.id,
      const NumberingStart._added(<KeptAttribute>[]),
      children,
      attachment,
    );
    int at = _lastIndexOf('num') + 1;
    if (at == 0) {
      final int cleanup = _children.indexWhere(
        (Object c) => _isW(c, 'numIdMacAtCleanup'),
      );
      at = cleanup < 0 ? _children.length : cleanup;
    }
    _edits.transaction(
      () => applyChange(
        _edits,
        _DefinitionAdded(this, at, _instances, instance, attachment),
      ),
    );
    return instance;
  }

  /// Adds a bullet list as Word's Bullets button makes one, and returns its
  /// instance: Symbol's bullet at level 0, `o` at level 1, Wingdings' square
  /// at level 2, repeating, each level indented 36 points further.
  ///
  /// It adds one abstract definition and one instance, with the lowest
  /// unused ids ([addInstance] has the rules), as one transaction. The
  /// definition has none of the identifiers Word writes for a list it
  /// makes (`w:nsid`, `w:tmpl`), and the definitions already in the
  /// document are kept as they are. Put paragraphs in it with
  /// `DocxBody.addListItem`.
  DocxNumberingInstance addBulletList() => _addToolbarList(bulletAbstractXml);

  /// Adds a numbered list as Word's Numbering button makes one, and
  /// returns its instance: "1.", "a." and "i." at levels 0 to 2, repeating,
  /// each level indented 36 points further.
  ///
  /// It adds one abstract definition and one instance, as [addBulletList]
  /// does.
  DocxNumberingInstance addNumberedList() =>
      _addToolbarList(numberedAbstractXml);

  DocxNumberingInstance _addToolbarList(String xml) {
    late final DocxNumberingInstance instance;
    _edits.transaction(() {
      instance = addInstance(addAbstractNumbering(this, xml));
    });
    return instance;
  }

  /// The first abstract definition whose id is [id], or `null`.
  DocxAbstractNumbering? _abstractById(int id) {
    for (final DocxAbstractNumbering a in _abstracts) {
      if (a.id == id) {
        return a;
      }
    }
    return null;
  }

  /// The index of the last child `w:<localName>`, typed or kept, or -1.
  int _lastIndexOf(String localName) =>
      _children.lastIndexWhere((Object c) => _isW(c, localName));
}

/// Whether [child], a child of `w:numbering`, is `w:<localName>`.
bool _isW(Object child, String localName) => switch (child) {
  DocxAbstractNumbering() => localName == 'abstractNum',
  DocxNumberingInstance() => localName == 'num',
  OpaqueXml() => child.namespaceUri == Ns.w && child.localName == localName,
  _ => false,
};

/// The lowest id from [from] that [used] does not hold.
///
/// Throws [StateError] past the largest id the model writes, which a file
/// cannot make happen: it would need a billion definitions.
int _lowestUnused(Set<int> used, int from) {
  int id = from;
  while (used.contains(id)) {
    id++;
  }
  if (id > maxNumId) {
    throw StateError('No list id is free.');
  }
  return id;
}

/// The document a definition is in, which the property sets of its levels
/// and overrides report to.
final class _Attachment {
  DocxNumbering? owner;

  DocxEditSink sink() => owner?._edits ?? DocxEditSink.none;
}

/// A property set with the nested sets [nested] written in place of its
/// nested containers.
final class _Set extends PropertySet {
  _Set(
    super.source,
    super.schema,
    super.sink, [
    Map<String, NestedProperties> nested = const <String, NestedProperties>{},
  ]) : _nested = nested;

  final Map<String, NestedProperties> _nested;

  @override
  Map<String, NestedProperties> get nested => _nested;
}

/// An abstract definition or an instance added to a document's numbering.
final class _DefinitionAdded implements Change {
  _DefinitionAdded(
    this._numbering,
    this._childIndex,
    this._list,
    this._definition,
    this._attachment,
  ) : _listIndex = _list.length;

  final DocxNumbering _numbering;
  final int _childIndex;
  final List<Object> _list;
  final int _listIndex;
  final Object _definition;
  final _Attachment _attachment;

  @override
  void revert() {
    _numbering._children.removeAt(_childIndex);
    _list.removeAt(_listIndex);
    _attachment.owner = null;
  }

  @override
  void reapply() {
    _numbering._children.insert(_childIndex, _definition);
    _list.insert(_listIndex, _definition);
    _attachment.owner = _numbering;
  }
}

/// The start tag of an abstract definition or an instance: as read, or
/// that of one added through the API, whose name and id the writer gives.
final class NumberingStart {
  NumberingStart._read(XmlPullReader r)
    : qualifiedName = r.qualifiedName,
      namespaces = Map<String, String>.unmodifiable(r.declaredNamespaces),
      attributes = List<KeptAttribute>.unmodifiable(keepAttributes(r));

  const NumberingStart._added(this.attributes)
    : qualifiedName = null,
      namespaces = const <String, String>{};

  /// The element's name as read, or `null` for one added through the API.
  final String? qualifiedName;

  /// The namespaces the element declared, prefix to URI.
  final Map<String, String> namespaces;

  /// The element's attributes in source order; for one added, those it
  /// has besides its id.
  final List<KeptAttribute> attributes;
}

/// Marks where an instance added through the API writes its
/// `w:abstractNumId`.
const Object newAbstractNumId = _NewAbstractNumId();

final class _NewAbstractNumId {
  const _NewAbstractNumId();
}

/// The value of the attribute `w:<localName>` of the start element [r] is
/// on, or `null`.
String? _wAttribute(XmlPullReader r, String localName) {
  for (int i = 0; i < r.attributeCount; i++) {
    if (r.attributeNamespace(i) == Ns.w &&
        r.attributeLocalName(i) == localName) {
      return r.attributeValue(i);
    }
  }
  return null;
}

/// An id read from a file: at most nine digits (plan Ruling 4), or `null`.
int? _id(String? value) => parseDecimal(value, min: 0, max: maxNumId);

/// Reads the children of the element [r] is on with [child], called with
/// [r] on each child's start element, and consumes the element: afterwards
/// [r] is on its end event. Character data between children is dropped.
List<Object> _readChildren(
  XmlPullReader r,
  Object Function(XmlPullReader r) child,
) {
  final List<Object> children = <Object>[];
  if (r.isEmptyElement) {
    r.next();
    return children;
  }
  final int depth = r.depth;
  while (r.next()) {
    final XmlEventType type = r.eventType;
    if (type == XmlEventType.endElement && r.depth < depth) {
      break;
    }
    if (type == XmlEventType.startElement && r.depth == depth + 1) {
      children.add(child(r));
    }
  }
  return children;
}

/// The level of the `w:lvl` or `w:lvlOverride` [r] is on, from its
/// `w:ilvl`, or `null` when it is not 0 to 8.
int? _levelOf(XmlPullReader r) =>
    parseDecimal(_wAttribute(r, 'ilvl'), min: 0, max: maxListLevel);

/// Reads the `w:abstractNum` [r] is on and consumes it: a
/// [DocxAbstractNumbering], or an [OpaqueXml] when its id does not parse.
///
/// With [newId], the definition is one added through the API: it takes
/// that id, and its own `w:abstractNumId` and namespace declarations are
/// dropped.
Object readAbstractNumbering(XmlPullReader r, {int? newId}) {
  final int? id = newId ?? _id(_wAttribute(r, 'abstractNumId'));
  if (id == null) {
    return OpaqueXml.capture(r);
  }
  final NumberingStart start = newId == null
      ? NumberingStart._read(r)
      : NumberingStart._added(
          List<KeptAttribute>.unmodifiable(
            keepAttributes(r).where(
              (KeptAttribute a) =>
                  a.namespaceUri != Ns.w ||
                  a.qualifiedName.substring(a.qualifiedName.indexOf(':') + 1) !=
                      'abstractNumId',
            ),
          ),
        );
  final _Attachment attachment = _Attachment();
  final List<Object> children = _readChildren(r, (XmlPullReader r) {
    if (r.namespaceUri == Ns.w && r.localName == 'lvl') {
      final int? level = _levelOf(r);
      if (level != null) {
        return DocxNumberingLevel._read(
          PropertyContainer.read(r, levelSchema),
          level,
          attachment,
        );
      }
    }
    return OpaqueXml.capture(r);
  });
  return DocxAbstractNumbering._(id, start, children, attachment);
}

const IntValCodec _abstractNumIdCodec = IntValCodec(
  'abstractNumId',
  0,
  maxNumId,
);

/// Reads the `w:num` [r] is on and consumes it: a [DocxNumberingInstance],
/// or an [OpaqueXml] when its id does not parse. An instance without one
/// `w:abstractNumId` that parses is read but not listed.
Object readNumberingInstance(XmlPullReader r) {
  final int? id = _id(_wAttribute(r, 'numId'));
  if (id == null) {
    return OpaqueXml.capture(r);
  }
  final NumberingStart start = NumberingStart._read(r);
  final _Attachment attachment = _Attachment();
  int? abstractId;
  int abstractIds = 0;
  final List<Object> children = _readChildren(r, (XmlPullReader r) {
    if (r.namespaceUri == Ns.w && r.localName == 'abstractNumId') {
      final PropertyElementBuilder element = PropertyElementBuilder();
      final OpaqueXml xml = OpaqueXml.capture(r, onEvent: element.add);
      final PropertyElement e = element.element!;
      abstractIds++;
      abstractId = _abstractNumIdCodec.attributes.containsAll(e.wAttributeNames)
          ? _abstractNumIdCodec.parse(e)
          : null;
      return xml;
    }
    if (r.namespaceUri == Ns.w && r.localName == 'lvlOverride') {
      final int? level = _levelOf(r);
      if (level != null) {
        return DocxLevelOverride._(
          level,
          _Set(
            PropertyContainer.read(r, levelOverrideSchema),
            levelOverrideSchema,
            attachment.sink,
          ),
          isNew: false,
        );
      }
    }
    return OpaqueXml.capture(r);
  });
  return DocxNumberingInstance._(
    id,
    abstractIds == 1 ? abstractId : null,
    start,
    children,
    attachment,
  );
}

/// The numbering of a part whose root is [root] and whose children are
/// [children], in document order: an [OpaqueXml], or what
/// [readAbstractNumbering] and [readNumberingInstance] read. Its edits are
/// recorded in [edits].
DocxNumbering newNumbering(
  DocxEdits edits,
  XmlRoot root,
  List<Object> children,
) => DocxNumbering._(edits, root, children);

/// Adds to [numbering] the abstract definition [xml], one `w:abstractNum`
/// element whose prefixes are declared in it or are `w` for
/// WordprocessingML, with the lowest unused id (from 0), and returns it.
///
/// The definition's own `w:abstractNumId`, if any, is dropped. It goes
/// after the last abstract definition, or after the picture bullets when
/// there is none. How the list helpers add Word's toolbar lists (plan
/// Ruling 9). [xml] that is not one well-formed `w:abstractNum`, with
/// nothing after it and no entity XML does not define, throws
/// [ArgumentError]. The add is one transaction.
DocxAbstractNumbering addAbstractNumbering(
  DocxNumbering numbering,
  String xml,
) {
  final int id = _lowestUnused(<int>{
    for (final DocxAbstractNumbering a in numbering._abstracts) a.id,
  }, 0);
  final Object read;
  final String source = '<w:numbering xmlns:w="${Ns.w}">$xml</w:numbering>';
  try {
    _checkDecodes(source);
    final XmlPullReader r = XmlPullReader(source);
    Object? found;
    int roots = 0;
    while (r.next()) {
      if (r.eventType != XmlEventType.startElement) {
        continue;
      }
      // The input closed the wrapper and opened another root.
      if (r.depth == 1 && ++roots > 1) {
        throw ArgumentError.value(xml, 'xml', 'Not one w:abstractNum');
      }
      if (r.depth != 2) {
        continue;
      }
      if (found != null ||
          r.namespaceUri != Ns.w ||
          r.localName != 'abstractNum') {
        throw ArgumentError.value(xml, 'xml', 'Not one w:abstractNum');
      }
      found = readAbstractNumbering(r, newId: id);
    }
    if (found == null) {
      throw ArgumentError.value(xml, 'xml', 'Not one w:abstractNum');
    }
    read = found;
  } on XmlParseException catch (e) {
    throw ArgumentError.value(xml, 'xml', 'Not well-formed: ${e.message}');
  }
  final DocxAbstractNumbering abstract = read as DocxAbstractNumbering;
  int at = numbering._lastIndexOf('abstractNum') + 1;
  if (at == 0) {
    at = numbering._lastIndexOf('numPicBullet') + 1;
  }
  final DocxEdits edits = numbering._edits;
  edits.transaction(
    () => applyChange(
      edits,
      _DefinitionAdded(
        numbering,
        at,
        numbering._abstracts,
        abstract,
        abstract._attachment,
      ),
    ),
  );
  return abstract;
}

/// Decodes every attribute value and every text of the document [source],
/// so an entity XML does not define throws [XmlParseException] (the kept
/// slices are not decoded when read).
void _checkDecodes(String source) {
  final XmlPullReader r = XmlPullReader(source);
  while (r.next()) {
    switch (r.eventType) {
      case XmlEventType.startElement:
        for (int i = 0; i < r.attributeCount; i++) {
          r.attributeValue(i);
        }
      case XmlEventType.characters:
        r.text;
      default:
        break;
    }
  }
}

/// The root start tag of [numbering], as read.
XmlRoot numberingRootOf(DocxNumbering numbering) => numbering._root;

/// The children of the root of [numbering], in document order: [OpaqueXml],
/// [DocxAbstractNumbering] and [DocxNumberingInstance] (listed or not).
List<Object> numberingChildrenOf(DocxNumbering numbering) =>
    numbering._children;

/// Whether [numbering] holds anything a numbering part must keep: a child
/// read or a definition added (plan Ruling 7).
bool numberingHoldsSomething(DocxNumbering numbering) =>
    numbering._children.isNotEmpty;

/// The ids of every instance of [numbering], listed or not: the lists a
/// paragraph may name.
Set<int> numberingInstanceIds(DocxNumbering numbering) => <int>{
  for (final Object c in numbering._children)
    if (c is DocxNumberingInstance) c.id,
};

/// The start tag of [definition], a [DocxAbstractNumbering] or a
/// [DocxNumberingInstance].
NumberingStart numberingStartOf(Object definition) => switch (definition) {
  DocxAbstractNumbering() => definition._start,
  DocxNumberingInstance() => definition._start,
  _ => throw ArgumentError.value(definition, 'definition'),
};

/// The children of [definition], a [DocxAbstractNumbering] or a
/// [DocxNumberingInstance], in document order.
List<Object> numberingDefinitionChildrenOf(Object definition) =>
    switch (definition) {
      DocxAbstractNumbering() => definition._children,
      DocxNumberingInstance() => definition._children,
      _ => throw ArgumentError.value(definition, 'definition'),
    };

/// The abstract definition id [instance] writes for [newAbstractNumId].
int abstractIdOf(DocxNumberingInstance instance) => instance._abstractId!;

/// The property set of [level], which writes it as `w:lvl`.
PropertySet levelPropertySetOf(DocxNumberingLevel level) => level._set;

/// The property set of [override], which writes it as `w:lvlOverride`.
PropertySet levelOverridePropertySetOf(DocxLevelOverride override) =>
    override._set;

/// Whether [override] was added through the API, so its `w:ilvl` is
/// written from [DocxLevelOverride.level].
bool isNewLevelOverride(DocxLevelOverride override) => override._isNew;

/// Whether [instance] is an instance of [numbering], not of another
/// document's and not one a rollback took out.
bool ownsInstance(DocxNumbering numbering, DocxNumberingInstance instance) =>
    identical(instance._attachment.owner, numbering);
