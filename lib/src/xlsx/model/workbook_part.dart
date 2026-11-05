/// The workbook part of an XLSX package: the sheet list and `<calcPr>`
/// typed, everything else kept as written.
///
/// Not ported from Quds; written for jet_office.
///
/// A loaded part is always written from this model (spec §4.3). What the
/// model types is the `<sheets>` group, each `<sheet>` as a [SheetEntry], and
/// the attributes of `<calcPr>`; the first `<bookViews>` is an [XmlNode] whose
/// first `<workbookView>` gives the active tab ([WorkbookPart.activeTab]) and
/// keeps its other attributes, and the first `<workbookProtection>` is an
/// [XmlNode] too, which [WorkbookPart.swapElement] swaps as it does an
/// [ItemGroup]. Every other child of `<workbook>` (`workbookPr` with its
/// `date1904`, `definedNames`, `extLst`, ...) is an [OpaqueXml] at its
/// original position, and the root keeps its namespace declarations and
/// `mc:Ignorable`.
///
/// Sheet names are `ST_Xstring`: `_xHHHH_` is decoded on read and escaped on
/// write, as the writer does. A `<sheet>`'s `r:id` is written with the prefix
/// it had, declared where the part does not bind it already.
///
/// Only the first `<sheets>`, `<calcPr>`, `<bookViews>` and
/// `<workbookProtection>` are typed; a repeated one is kept opaque. A part
/// with no root element, or whose root is not a SpreadsheetML `<workbook>`,
/// is *untyped*: it has no sheets and is written back unchanged.
library;

import 'dart:typed_data';

import '../../opc/ooxml.dart';
import '../../opc/opaque_xml.dart';
import '../../opc/package.dart';
import '../../xml/utf8_buffer.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import '../../xml/xml_writer.dart';
import '../read/package_reader.dart'
    show strictSpreadsheetNs, strictUnsupported;
import '../read/read_exception.dart';
import '../read/read_limits.dart';
import '../read/workbook_reader.dart' show isDate1904, sheetVisibilityOf;
import '../sheet_view.dart';
import 'element_node.dart';
import 'item_group.dart';

/// The children of `<workbook>` in the order of the schema's `CT_Workbook`
/// sequence.
const List<String> workbookChildOrder = <String>[
  'fileVersion',
  'fileSharing',
  'workbookPr',
  'workbookProtection',
  'bookViews',
  'sheets',
  'functionGroups',
  'externalReferences',
  'definedNames',
  'calcPr',
  'oleSize',
  'customWorkbookViews',
  'pivotCaches',
  'smartTagPr',
  'smartTagTypes',
  'webPublishing',
  'fileRecoveryPr',
  'webPublishObjects',
  'extLst',
];

/// The typed children of `<bookViews>`.
const NodeShape _bookViewsShape = <String, Set<String>>{
  'bookViews': <String>{'workbookView'},
};

/// The children of `<workbook>` that [WorkbookPart.element] and
/// [WorkbookPart.swapElement] take.
const Set<String> _elementSlots = <String>{
  'workbookProtection',
  'definedNames',
};

/// A `<sheet>` of the workbook's `<sheets>`.
final class SheetEntry {
  SheetEntry._(
    this.name,
    this.rawSheetId,
    this.visibility,
    this.relationshipId,
    this.attributes, {
    required this.qualifiedName,
    required this.namespaces,
    required this.relPrefix,
    this.explicitVisible = false,
  }) : sheetId = parseSheetId(rawSheetId);

  /// The sheet name, `_xHHHH_` decoded.
  String name;

  /// The sheet's id in the workbook: the value of `sheetId` when its text is
  /// an `xsd:unsignedInt` (`0` included), else `null` (the attribute is
  /// missing or not a number).
  ///
  /// The text read is written back exactly as it was, so a load and save
  /// never changes it; only [WorkbookPart.addSheet] makes an id.
  final int? sheetId;

  /// The `sheetId` text as written, or `null` when the attribute is absent.
  final String? rawSheetId;

  /// Whether the sheet is visible, hidden or very hidden.
  XlsxSheetVisibility visibility;

  /// The `r:id` of the relationship to the worksheet part, or the empty string
  /// when the element had none (none is then written).
  final String relationshipId;

  /// The attributes the model does not type, as written.
  final List<KeptAttribute> attributes;

  /// The element name as written, with its prefix.
  final String qualifiedName;

  /// The namespaces the element declares.
  final Map<String, String> namespaces;

  /// The prefix of the `r:id` attribute.
  final String relPrefix;

  /// Whether the source said `state="visible"`, which is written back until
  /// the sheet's visibility is set (a visible sheet then has no `state`).
  bool explicitVisible;

  void _writeTo(XmlWriter w, Map<String, String> above) {
    w.start(qualifiedName);
    writeNamespaceDeclarations(w, namespaces);
    final Map<String, String> inner = mergeNamespaces(above, namespaces);
    w.attribute('name', escapeXstring(name));
    if (rawSheetId != null) w.attribute('sheetId', rawSheetId!);
    if (visibility != XlsxSheetVisibility.visible || explicitVisible) {
      w.attribute('state', visibility.name);
    }
    final List<KeptAttribute> all = <KeptAttribute>[
      if (relationshipId.isNotEmpty)
        (
          qualifiedName: '$relPrefix:id',
          namespaceUri: Ns.rel,
          value: relationshipId,
        ),
      ...attributes,
    ];
    writeKeptAttributes(w, all, declaredAbove: inner);
    w.end();
  }
}

/// The typed `<sheets>` group.
final class _Sheets {
  _Sheets(this.qualifiedName, this.namespaces, this.attributes, this.items);

  final String qualifiedName;
  final Map<String, String> namespaces;
  final List<KeptAttribute> attributes;

  /// [SheetEntry] and [OpaqueXml] items in order.
  final List<Object> items;

  Iterable<SheetEntry> get entries => items.whereType<SheetEntry>();

  void writeTo(XmlWriter w, Map<String, String> above) {
    w.start(qualifiedName);
    writeNamespaceDeclarations(w, namespaces);
    final Map<String, String> inner = mergeNamespaces(above, namespaces);
    writeKeptAttributes(w, attributes, declaredAbove: inner);
    for (final Object item in items) {
      switch (item) {
        case SheetEntry():
          item._writeTo(w, inner);
        case OpaqueXml():
          item.writeTo(w, declaredAbove: inner);
      }
    }
    w.end();
  }
}

/// The typed `<calcPr>`: its attributes, in order.
final class _CalcPr {
  _CalcPr(this.qualifiedName, this.namespaces, this.attributes);

  final String qualifiedName;
  final Map<String, String> namespaces;
  final List<KeptAttribute> attributes;

  void setFullCalcOnLoad() {
    const KeptAttribute on = (
      qualifiedName: 'fullCalcOnLoad',
      namespaceUri: '',
      value: '1',
    );
    final int i = attributes.indexWhere(
      (KeptAttribute a) => a.qualifiedName == 'fullCalcOnLoad',
    );
    if (i < 0) {
      attributes.add(on);
    } else {
      attributes[i] = on;
    }
  }

  void writeTo(XmlWriter w, Map<String, String> above) {
    w.start(qualifiedName);
    writeNamespaceDeclarations(w, namespaces);
    writeKeptAttributes(
      w,
      attributes,
      declaredAbove: mergeNamespaces(above, namespaces),
    );
    w.end();
  }
}

/// The workbook part: its sheet list and calculation settings typed, the
/// rest kept as written.
final class WorkbookPart implements PartContent {
  WorkbookPart._typed(
    XmlRoot this._root,
    this._children,
    this._sheets,
    this._calcPr,
    this.date1904,
  ) : _untypedText = null;

  WorkbookPart._untyped(this._untypedText)
    : _root = null,
      _children = <Object>[],
      _sheets = null,
      _calcPr = null,
      date1904 = false;

  /// Reads a workbook part from [r], which must not have been advanced.
  ///
  /// A part with no root element, or whose root is not a SpreadsheetML
  /// `<workbook>`, is untyped: [sheets] is empty, [encode] writes the text
  /// unchanged and [addSheet] and [requestFullCalculation] throw a
  /// [StateError].
  ///
  /// Throws an [XlsxReadException] of reason `unsupportedFormat` for a Strict
  /// root and `limitExceeded` when `<sheets>` lists more than
  /// [XlsxReadLimits.maxSheets] sheets. An `XmlParseException` passes
  /// through.
  ///
  /// A `<sheet>`'s `sheetId` is written back exactly as read: absent stays
  /// absent and text that is not an unsigned int (`abc`, `-1`) is kept
  /// verbatim, with [SheetEntry.sheetId] `null`. The children of `<sheet>`
  /// and `<calcPr>` (the schema has none) are not kept.
  factory WorkbookPart.read(XmlPullReader r, XlsxReadLimits limits) {
    while (r.next()) {
      if (r.eventType == XmlEventType.startElement) break;
    }
    if (r.eventType != XmlEventType.startElement) {
      return WorkbookPart._untyped(r.sourceText(0, r.sourceLength));
    }
    if (r.namespaceUri == strictSpreadsheetNs) throw strictUnsupported();
    if (r.localName != 'workbook' || r.namespaceUri != Ns.main) {
      return WorkbookPart._untyped(r.sourceText(0, r.sourceLength));
    }
    final XmlRoot root = XmlRoot.capture(r);
    final List<Object> children = <Object>[];
    _Sheets? sheets;
    _CalcPr? calcPr;
    var date1904 = false;
    var hasBookViews = false;
    var hasProtection = false;
    while (r.next()) {
      if (r.eventType == XmlEventType.endElement && r.depth < 1) break;
      if (r.eventType != XmlEventType.startElement) continue;
      final bool main = r.namespaceUri == Ns.main;
      if (main && r.localName == 'sheets' && sheets == null) {
        sheets = _readSheets(r, limits);
        children.add(sheets);
      } else if (main && r.localName == 'calcPr' && calcPr == null) {
        calcPr = _CalcPr(
          r.qualifiedName,
          Map<String, String>.of(r.declaredNamespaces),
          keepAttributes(r),
        );
        r.skip();
        children.add(calcPr);
      } else if (main && r.localName == 'bookViews' && !hasBookViews) {
        hasBookViews = true;
        children.add(XmlNode.read(r, _bookViewsShape));
      } else if (main &&
          r.localName == 'workbookProtection' &&
          !hasProtection) {
        hasProtection = true;
        children.add(XmlNode.read(r, const <String, Set<String>>{}));
      } else {
        if (main && r.localName == 'workbookPr') {
          date1904 = isDate1904(r.getAttribute('date1904'));
        }
        children.add(OpaqueXml.capture(r));
      }
    }
    return WorkbookPart._typed(root, children, sheets, calcPr, date1904);
  }

  /// The text of an untyped part; `null` for a typed one.
  final String? _untypedText;
  final XmlRoot? _root;
  final List<Object> _children;
  _Sheets? _sheets;
  _CalcPr? _calcPr;

  /// Whether the workbook counts dates from 1904, from `<workbookPr>`
  /// (`date1904` is `1` or `true`, as the reader reads it). The element
  /// stays opaque; `false` for an untyped part.
  final bool date1904;

  /// Whether the part is a SpreadsheetML workbook; `false` for an untyped
  /// part, which has no sheets.
  bool get isTyped => _untypedText == null;

  /// The sheets in tab order.
  List<SheetEntry> get sheets =>
      List<SheetEntry>.unmodifiable(_sheets?.entries ?? const <SheetEntry>[]);

  /// Appends a visible sheet named [name] whose worksheet is the part that
  /// the relationship [relationshipId] targets, with the next free `sheetId`
  /// (one more than the largest parsable one in use, or 1).
  ///
  /// Creates `<sheets>` in its schema position when the part has none.
  /// Throws a [StateError] for an untyped part.
  SheetEntry addSheet(String name, String relationshipId) {
    final XmlRoot root = _requireTyped();
    final _Sheets group = _sheets ??= _createSheets(root);
    final SheetEntry entry = SheetEntry._(
      name,
      '${_nextSheetId(group)}',
      XlsxSheetVisibility.visible,
      relationshipId,
      <KeptAttribute>[],
      qualifiedName: '${_prefixOf(group.qualifiedName)}sheet',
      namespaces: const <String, String>{},
      relPrefix: _relPrefix(root, group),
    );
    group.items.add(entry);
    return entry;
  }

  /// Sets `fullCalcOnLoad="1"` on `<calcPr>` so Excel recalculates every
  /// formula on opening, creating the element in schema position when it is
  /// absent. Other attributes are kept. Throws a [StateError] for an untyped
  /// part.
  void requestFullCalculation() {
    final XmlRoot root = _requireTyped();
    final _CalcPr calc = _calcPr ??= _createCalcPr(root);
    calc.setFullCalcOnLoad();
  }

  /// The first `<bookViews>`, or `null` when the part has none (or is
  /// untyped). Immutable; [swapBookViews] replaces it.
  XmlNode? get bookViews {
    for (final Object c in _children) {
      if (c is XmlNode && c.localName == 'bookViews') return c;
    }
    return null;
  }

  /// The typed first element of [slot] (`workbookProtection` or
  /// `definedNames`): an [XmlNode] or an [ItemGroup], or `null` when the part
  /// has none typed (or is untyped). Immutable; [swapElement] replaces it.
  /// An element kept as an [OpaqueXml] is not a slot's element.
  ///
  /// Throws an [ArgumentError] named `slot` for any other name.
  Object? element(String slot) {
    _checkSlot(slot);
    for (final Object c in _children) {
      if (c is XmlNode && c.localName == slot ||
          c is ItemGroup<Object?> && c.localName == slot) {
        return c;
      }
    }
    return null;
  }

  /// Replaces the element [from] of [slot] by [to]: in place, or where the
  /// schema puts it when [from] is `null` (inserted) or no longer there;
  /// `null` for [to] removes [from]. Only that slot's element is touched.
  ///
  /// Throws an [ArgumentError] named `slot` for a name [element] does not
  /// take, and a [StateError] for an untyped part.
  void swapElement(String slot, Object? from, Object? to) {
    _checkSlot(slot);
    _requireTyped();
    final int at = from == null
        ? -1
        : _children.indexWhere((Object c) => identical(c, from));
    if (to == null) {
      if (at >= 0) _children.removeAt(at);
    } else if (at >= 0) {
      _children[at] = to;
    } else {
      _children.insert(_positionFor(slot), to);
    }
  }

  void _checkSlot(String slot) {
    if (!_elementSlots.contains(slot)) {
      throw ArgumentError.value(slot, 'slot', 'Not a workbook element slot.');
    }
  }

  /// The index of the tab Excel opens on: the `activeTab` of the first
  /// `<workbookView>`, or 0 when there is none or its text is not an
  /// unsigned int.
  int get activeTab =>
      parseSheetId(bookViews?.child('workbookView')?.attribute('activeTab')) ??
      0;

  /// Sets the `activeTab` of the first `<workbookView>` to [index],
  /// creating `<bookViews>` in its schema position and `<workbookView>` when
  /// absent; every other attribute and child is kept. A value that is
  /// already [index] (an absent attribute reads as 0) changes nothing.
  ///
  /// Not recorded in a change log: use `setActiveTab` of `primitives.dart`.
  /// Throws a [StateError] for an untyped part.
  void setActiveTabIndex(int index) {
    final XmlRoot root = _requireTyped();
    final XmlNode? views = bookViews;
    final String prefix = _prefixOf(root.qualifiedName);
    final XmlNode next;
    if (views == null) {
      next = XmlNode.made(
        prefix,
        'bookViews',
        children: <Object>[
          XmlNode.made(
            prefix,
            'workbookView',
            attributes: <String, String>{'activeTab': '$index'},
          ),
        ],
      );
    } else {
      final XmlNode? first = views.child('workbookView');
      if (first == null) {
        next = views.withChildren(<Object>[
          XmlNode.made(
            _prefixOf(views.qualifiedName),
            'workbookView',
            attributes: <String, String>{'activeTab': '$index'},
          ),
          ...views.children,
        ]);
      } else {
        final String? text = first.attribute('activeTab');
        if (text == '$index' || (text == null && index == 0)) return;
        next = views.replacingChild(
          first,
          first.withChanges(<String, String?>{'activeTab': '$index'}),
        );
      }
    }
    swapBookViews(views, next);
  }

  /// Replaces the `<bookViews>` [from] (as [bookViews] returned it; `null`
  /// for none) by [to] (`null` removes it), at the same place, or in schema
  /// position when [from] is `null`. The primitive behind the undo of
  /// [setActiveTabIndex].
  void swapBookViews(XmlNode? from, XmlNode? to) {
    _requireTyped();
    if (from == null) {
      if (to != null) _children.insert(_positionFor('bookViews'), to);
      return;
    }
    final int at = _children.indexWhere((Object c) => identical(c, from));
    if (at < 0) throw StateError('The workbook views are not in the part.');
    if (to == null) {
      _children.removeAt(at);
    } else {
      _children[at] = to;
    }
  }

  XmlRoot _requireTyped() {
    final XmlRoot? root = _root;
    if (root == null) {
      throw StateError('The workbook part is not a SpreadsheetML workbook.');
    }
    return root;
  }

  _Sheets _createSheets(XmlRoot root) {
    final _Sheets group = _Sheets(
      '${_prefixOf(root.qualifiedName)}sheets',
      const <String, String>{},
      <KeptAttribute>[],
      <Object>[],
    );
    _children.insert(_positionFor('sheets'), group);
    return group;
  }

  _CalcPr _createCalcPr(XmlRoot root) {
    final _CalcPr calc = _CalcPr(
      '${_prefixOf(root.qualifiedName)}calcPr',
      const <String, String>{},
      <KeptAttribute>[],
    );
    _children.insert(_positionFor('calcPr'), calc);
    return calc;
  }

  /// The index in [_children] before the first element that follows [name]
  /// in [workbookChildOrder], or the end.
  int _positionFor(String name) {
    final Set<String> after = workbookChildOrder
        .skip(workbookChildOrder.indexOf(name) + 1)
        .toSet();
    for (var i = 0; i < _children.length; i++) {
      final Object c = _children[i];
      final String? childName = switch (c) {
        OpaqueXml() when c.namespaceUri == Ns.main => c.localName,
        _Sheets() => 'sheets',
        _CalcPr() => 'calcPr',
        XmlNode() => c.localName,
        ItemGroup<Object?>() => c.localName,
        _ => null,
      };
      if (childName != null && after.contains(childName)) return i;
    }
    return _children.length;
  }

  @override
  List<Uint8List> encode() {
    final Utf8Buffer buffer = Utf8Buffer();
    final String? untyped = _untypedText;
    if (untyped != null) return (buffer..write(untyped)).takeChunks();
    final XmlWriter w = XmlWriter(buffer)..declaration();
    final XmlRoot root = _root!;
    root.writeStart(w);
    for (final Object c in _children) {
      switch (c) {
        case _Sheets():
          c.writeTo(w, root.namespaces);
        case _CalcPr():
          c.writeTo(w, root.namespaces);
        case XmlNode():
          c.writeTo(w, root.namespaces);
        case ItemGroup<Object?>():
          c.writeTo(w, root.namespaces);
        case OpaqueXml():
          c.writeTo(w, declaredAbove: root.namespaces);
      }
    }
    w.end();
    return buffer.takeChunks();
  }
}

/// The value of a `sheetId` text, or `null` unless it is an `xsd:unsignedInt`.
int? parseSheetId(String? text) {
  if (text == null || !RegExp(r'^[0-9]+$').hasMatch(text)) return null;
  final int? v = int.tryParse(text);
  return v != null && v <= 4294967295 ? v : null;
}

String _prefixOf(String qualifiedName) {
  final int colon = qualifiedName.indexOf(':');
  return colon < 0 ? '' : qualifiedName.substring(0, colon + 1);
}

/// The prefix bound to the relationships namespace where a new `<sheet>`
/// goes, or `r`.
String _relPrefix(XmlRoot root, _Sheets group) {
  for (final Map<String, String> ns in <Map<String, String>>[
    group.namespaces,
    root.namespaces,
  ]) {
    for (final MapEntry<String, String> e in ns.entries) {
      if (e.value == Ns.rel && e.key.isNotEmpty) return e.key;
    }
  }
  return 'r';
}

int _nextSheetId(_Sheets group) {
  var max = 0;
  for (final SheetEntry s in group.entries) {
    final int? id = s.sheetId;
    if (id != null && id > max) max = id;
  }
  return max + 1;
}

_Sheets _readSheets(XmlPullReader r, XlsxReadLimits limits) {
  final _Sheets group = _Sheets(
    r.qualifiedName,
    Map<String, String>.of(r.declaredNamespaces),
    keepAttributes(r),
    <Object>[],
  );
  if (r.isEmptyElement) return group;
  final int groupDepth = r.depth;
  var count = 0;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < groupDepth) break;
    if (r.eventType != XmlEventType.startElement) continue;
    if (r.depth == groupDepth + 1 &&
        r.localName == 'sheet' &&
        r.namespaceUri == Ns.main) {
      if (count >= limits.maxSheets) {
        throw XlsxReadException(
          XlsxReadFailure.limitExceeded,
          'Limit maxSheets (${limits.maxSheets}) exceeded.',
        );
      }
      count++;
      group.items.add(_readSheet(r));
    } else {
      group.items.add(OpaqueXml.capture(r));
    }
  }
  return group;
}

/// A `<sheet>`, leaving [r] on its end.
SheetEntry _readSheet(XmlPullReader r) {
  final String name = decodeXstring(r.getAttribute('name') ?? '');
  final String? rawId = r.getAttribute('sheetId');
  final XlsxSheetVisibility visibility = sheetVisibilityOf(
    r.getAttribute('state'),
  );
  var relationshipId = '';
  var relPrefix = 'r';
  final List<KeptAttribute> kept = <KeptAttribute>[];
  for (final KeptAttribute a in keepAttributes(
    r,
    except: const <String>{'name', 'sheetId', 'state'},
  )) {
    final int colon = a.qualifiedName.indexOf(':');
    if (colon > 0 &&
        a.namespaceUri == Ns.rel &&
        a.qualifiedName.substring(colon + 1) == 'id') {
      relationshipId = a.value;
      relPrefix = a.qualifiedName.substring(0, colon);
    } else {
      kept.add(a);
    }
  }
  final SheetEntry entry = SheetEntry._(
    name,
    rawId,
    visibility,
    relationshipId,
    kept,
    qualifiedName: r.qualifiedName,
    namespaces: Map<String, String>.of(r.declaredNamespaces),
    relPrefix: relPrefix,
    explicitVisible: r.getAttribute('state') == 'visible',
  );
  r.skip();
  return entry;
}
