/// A worksheet part of an XLSX package: its cells in a [CellStore], its
/// `<dimension>` recomputed, everything else kept as written.
///
/// Not ported from Quds; written for jet_office.
///
/// A loaded part is always written from this model (spec §4.3). The rows of
/// the first `<sheetData>` are read by [RawRowReader] with extras kept, so
/// the store holds what the file stores: values, styles, formulas, inline
/// strings, styled empty cells, the attributes of rows and cells, and the
/// children of a row other than its cells (an `extLst`, written after the
/// cells). Children of `<sheetData>` other than rows, which the schema does
/// not allow, are kept too but written after the last row, so their position
/// among the rows is not kept. Every
/// other child of `<worksheet>` (`dataValidations`, `drawing`, ...) is an
/// [OpaqueXml] at its original position, except the first
/// `<sheetFormatPr>` and the first `<cols>`, which are typed when plain
/// (`columns.dart`), the first `<mergeCells>` ([MergeGroup]) and the first
/// `<hyperlinks>` (an [ItemGroup] of [LinkEntry]), the first `<tableParts>`
/// (an [ItemGroup] of relationship ids) and the first
/// `<dataValidations>` (an [ItemGroup] of [XlsxDataValidation]) and the first
/// run of adjacent `<conditionalFormatting>`s ([CfBlock]); all of these are
/// edited as immutable values, so `swapLayout` undoes an edit of one
/// without touching the others. The first element of each of [_nodeSlots]
/// (`sheetPr`, `sheetViews`, `pageSetup`, `extLst`, ...) is typed too, as an
/// [XmlNode] (`element_node.dart`), and swaps the same way; so does an
/// [ItemGroup] (`item_group.dart`), the form of a list of feature entries.
/// The root keeps its namespace declarations and `mc:Ignorable`.
///
/// Saving recomputes the bookkeeping (spec §4.4): `<dimension ref>` from the
/// store's bounds (`A1` without cells), and each row's `spans` as the first
/// and last 1-based column of its cells (none on a row without cells).
/// Each row gets its `r`; cells are written by [CellEncoder.writeRaw], the
/// one writer of cell elements (decision 0002).
///
/// Only the first `<dimension>` and the first `<sheetData>` are typed; a
/// repeated one is kept opaque, as the reader reads only the first sheet
/// data. A part without `<sheetData>` gets one in schema position; a part
/// without `<dimension>` gets none, since the element is optional. A part
/// with no root element, or whose root is not a SpreadsheetML `<worksheet>`
/// (a chartsheet, say), is *untyped*, as the reader reads such a part as no
/// rows: it is written back unchanged.
library;

import 'dart:typed_data';

import '../../opc/ooxml.dart';
import '../../opc/opaque_xml.dart';
import '../../opc/package.dart';
import '../../xml/utf8_buffer.dart';
import '../../xml/xml_escape.dart' show decodeXstring;
import '../../xml/xml_pull_reader.dart';
import '../../xml/xml_writer.dart';
import '../cell_encoder.dart';
import '../cell_ref.dart';
import '../data_validation.dart' show XlsxDataValidation;
import '../range.dart';
import '../raw_cell.dart';
import '../read/merge_reader.dart' show parseMergeRange;
import '../read/package_reader.dart'
    show strictSpreadsheetNs, strictUnsupported;
import '../read/read_exception.dart';
import '../read/read_limits.dart';
import '../read/sheet_reader.dart' show RawRow, RawRowReader;
import '../warnings.dart';
import 'cell_store.dart';
import 'columns.dart';
import 'conditional_elements.dart';
import 'conditional_x14.dart';
import 'element_node.dart';
import 'item_group.dart';
import 'validation_elements.dart' show readDataValidation;

/// The children of `<worksheet>` in the order of the schema's
/// `CT_Worksheet` sequence.
const List<String> worksheetChildOrder = <String>[
  'sheetPr',
  'dimension',
  'sheetViews',
  'sheetFormatPr',
  'cols',
  'sheetData',
  'sheetCalcPr',
  'sheetProtection',
  'protectedRanges',
  'scenarios',
  'autoFilter',
  'sortState',
  'dataConsolidate',
  'customSheetViews',
  'mergeCells',
  'phoneticPr',
  'conditionalFormatting',
  'dataValidations',
  'hyperlinks',
  'printOptions',
  'pageMargins',
  'pageSetup',
  'headerFooter',
  'rowBreaks',
  'colBreaks',
  'customProperties',
  'cellWatches',
  'ignoredErrors',
  'smartTags',
  'drawing',
  'legacyDrawing',
  'legacyDrawingHF',
  'drawingHF',
  'picture',
  'oleObjects',
  'controls',
  'webPublishItems',
  'tableParts',
  'extLst',
];

/// What is typed inside the elements of [_nodeSlots]. A `<headerFooter>`
/// has opaque children, which keep their text.
const NodeShape worksheetNodeShape = <String, Set<String>>{
  'sheetPr': <String>{'tabColor', 'outlinePr', 'pageSetUpPr'},
  'sheetViews': <String>{'sheetView'},
  'sheetView': <String>{'pane', 'selection'},
  'headerFooter': <String>{},
  'rowBreaks': <String>{'brk'},
  'colBreaks': <String>{'brk'},
  'extLst': <String>{'ext'},
};

/// The children of `<worksheet>` whose first element is an [XmlNode].
const Set<String> _nodeSlots = <String>{
  'sheetPr',
  'sheetViews',
  'sheetProtection',
  'autoFilter',
  'sortState',
  'printOptions',
  'pageMargins',
  'pageSetup',
  'headerFooter',
  'rowBreaks',
  'colBreaks',
  'extLst',
};

/// A `<hyperlink>`, as the model reads it: the cells it covers and the
/// attributes that say where it goes, as written (the `location`, `tooltip`
/// and `display` with `_xHHHH_` decoded).
///
/// The relationship id names a relationship of the sheet part, whose target
/// is the external address; `null` for a link inside the workbook.
typedef LinkEntry = ({
  XlsxRange range,
  String? relationshipId,
  String? location,
  String? tooltip,
  String? display,
});

/// The [LinkEntry] of the `<hyperlink>` [element], or the problem that keeps
/// it from being read: no `ref`, or one that is not a range of cells.
({LinkEntry? value, String? problem}) readLinkEntry(OpaqueXml element) {
  final XmlPullReader r = readerOf(element);
  final String? ref = r.getAttribute('ref', namespaceUri: '');
  final XlsxRange? range = ref == null ? null : parseMergeRange(ref);
  if (range == null) return (value: null, problem: 'hyperlink');
  String? text(String name) {
    final String? value = r.getAttribute(name, namespaceUri: '');
    return value == null ? null : decodeXstring(value);
  }

  return (
    value: (
      range: range,
      relationshipId: r.getAttribute('id', namespaceUri: Ns.rel),
      location: text('location'),
      tooltip: text('tooltip'),
      display: text('display'),
    ),
    problem: null,
  );
}

/// The typed `<dimension>`: its `ref` is recomputed on save.
final class _Dimension {
  _Dimension(this.qualifiedName, this.namespaces, this.attributes);

  final String qualifiedName;
  final Map<String, String> namespaces;

  /// The attributes but `ref`, as written.
  final List<KeptAttribute> attributes;

  void writeTo(XmlWriter w, Map<String, String> above, String ref) {
    w.start(qualifiedName);
    writeNamespaceDeclarations(w, namespaces);
    w.attribute('ref', ref);
    writeKeptAttributes(
      w,
      attributes,
      declaredAbove: mergeNamespaces(above, namespaces),
    );
    w.end();
  }
}

/// The typed `<sheetFormatPr>`: its attributes as written, with
/// `outlineLevelRow` and `outlineLevelCol` raised on save when an edit went
/// deeper than the element and the file's rows or columns did.
///
/// Only an element without element children is typed (an end tag with
/// nothing between is the same as an empty element). One with children stays
/// an [OpaqueXml], is written as it was, and its outline levels are not
/// bookkept; no second element is made beside it, and it is read through an
/// untyped view of the same class.
final class _SheetFormat {
  _SheetFormat(this.qualifiedName, this.namespaces, this.attributes);

  final String qualifiedName;
  final Map<String, String> namespaces;
  final List<KeptAttribute> attributes;

  /// The value of the first attribute without a namespace named [name].
  String? attribute(String name) {
    for (final KeptAttribute a in attributes) {
      if (a.namespaceUri.isEmpty && a.qualifiedName == name) return a.value;
    }
    return null;
  }

  /// The kept `outlineLevelRow`, or 0 when it is absent or not a level.
  int get outlineLevelRow =>
      parseOutlineLevel(attribute('outlineLevelRow')) ?? 0;

  /// The kept `outlineLevelCol`, or 0 when it is absent or not a level.
  int get outlineLevelCol =>
      parseOutlineLevel(attribute('outlineLevelCol')) ?? 0;

  /// This element with [next] as its attributes.
  _SheetFormat withAttributes(List<KeptAttribute> next) =>
      _SheetFormat(qualifiedName, namespaces, next);

  /// Writes the element with `outlineLevelRow` of [rowLevel] and
  /// `outlineLevelCol` of [colLevel] when those are deeper than the kept
  /// values, else as it was. A level no edit raised is passed as 0.
  void writeTo(
    XmlWriter w,
    Map<String, String> above, {
    required int rowLevel,
    required int colLevel,
  }) {
    w.start(qualifiedName);
    writeNamespaceDeclarations(w, namespaces);
    final List<KeptAttribute> out =
        replaceAttributes(attributes, <String, String?>{
          if (rowLevel > outlineLevelRow) 'outlineLevelRow': '$rowLevel',
          if (colLevel > outlineLevelCol) 'outlineLevelCol': '$colLevel',
        });
    writeKeptAttributes(
      w,
      out,
      declaredAbove: mergeNamespaces(above, namespaces),
    );
    w.end();
  }
}

/// One child of a `<mergeCells>`: a merged range, or an element kept as
/// written (an unreadable `<mergeCell>`, or a foreign element).
final class MergeItem {
  const MergeItem._(this.range, this.source, this.counted);

  /// A merge made by the model, written as `<mergeCell ref="..."/>`.
  const MergeItem.made(XlsxRange this.range) : source = null, counted = true;

  /// The merged range, or `null` for an element that is not a readable
  /// `<mergeCell>`.
  final XlsxRange? range;

  /// The element as read; `null` for a merge made by the model.
  final OpaqueXml? source;

  /// Whether the element is a `<mergeCell>` (readable or not), which
  /// `count` counts.
  final bool counted;
}

/// The typed first `<mergeCells>`: its name, declarations and attributes as
/// written, and its [items] in file order.
///
/// An untouched group is written as it was (a wrong `count` included); once
/// [withItems] edits it, `count` is the number of its `<mergeCell>` items.
final class MergeGroup {
  /// A `<mergeCells>` named [qualifiedName] holding [items].
  MergeGroup(
    this.qualifiedName,
    this.namespaces,
    this.attributes,
    this.items, {
    this.edited = false,
  });

  /// The element's name with its prefix.
  final String qualifiedName;

  /// The namespace declarations of the start tag.
  final Map<String, String> namespaces;

  /// The attributes, `count` included, as written.
  final List<KeptAttribute> attributes;

  /// The children, in source order.
  final List<MergeItem> items;

  /// Whether `count` is recomputed on save.
  final bool edited;

  /// The readable merged ranges, in file order.
  List<XlsxRange> get ranges => <XlsxRange>[
    for (final MergeItem i in items)
      if (i.range != null) i.range!,
  ];

  /// This group holding [next], with `count` recomputed on save.
  MergeGroup withItems(List<MergeItem> next) =>
      MergeGroup(qualifiedName, namespaces, attributes, next, edited: true);

  /// Writes the element. [above] holds the bindings in scope at the
  /// worksheet's root.
  void writeTo(XmlWriter w, Map<String, String> above) {
    w.start(qualifiedName);
    writeNamespaceDeclarations(w, namespaces);
    final Map<String, String> inner = mergeNamespaces(above, namespaces);
    writeKeptAttributes(
      w,
      edited
          ? replaceAttributes(attributes, <String, String?>{
              'count': '${items.where((MergeItem i) => i.counted).length}',
            })
          : attributes,
      declaredAbove: inner,
    );
    final int colon = qualifiedName.indexOf(':');
    final String prefix = colon < 0
        ? ''
        : qualifiedName.substring(0, colon + 1);
    for (final MergeItem item in items) {
      final OpaqueXml? source = item.source;
      if (source != null) {
        source.writeTo(w, declaredAbove: inner);
      } else {
        w
          ..start('${prefix}mergeCell')
          ..attribute('ref', item.range!.ref)
          ..end();
      }
    }
    w.end();
  }
}

/// The typed `<sheetData>`: its element name, declarations and attributes;
/// the rows live in the part's [CellStore].
final class _SheetData {
  _SheetData(this.qualifiedName, this.namespaces, this.attributes);

  final String qualifiedName;
  final Map<String, String> namespaces;
  final List<KeptAttribute> attributes;

  /// The children other than rows, in source order. The schema allows
  /// none; they are kept so nothing is lost, and written after the rows.
  List<OpaqueXml> extraChildren = const <OpaqueXml>[];
}

/// A worksheet part: its cells in a [CellStore], the rest kept as written.
final class WorksheetPart implements PartContent {
  WorksheetPart._typed(XmlRoot this._root, this._children)
    : _untypedText = null;

  WorksheetPart._untyped(this._untypedText)
    : _root = null,
      _children = <Object>[];

  /// Reads a worksheet part from [r], which must not have been advanced.
  ///
  /// [part] names the part in warnings and errors. Problems with rows and
  /// cells go to [warn] as `readSheetRows` documents them: a misplaced or
  /// duplicate cell, a row out of order, a cell outside the sheet (dropped).
  /// Rows are stored in row order whatever their order in the file.
  ///
  /// A part with no root element, or whose root is not a SpreadsheetML
  /// `<worksheet>`, is untyped: [cells] starts empty and [encode] writes the
  /// text unchanged.
  ///
  /// Throws an [XlsxReadException] of reason `unsupportedFormat` for a Strict
  /// root and `limitExceeded` for a `<v>`, `<f>` or inline text longer than
  /// [XlsxReadLimits.maxTextLength]. An `XmlParseException` passes through.
  factory WorksheetPart.read(
    XmlPullReader r, {
    required String part,
    required XlsxReadLimits limits,
    required void Function(XlsxWarningCode code, String? cell, {String? detail})
    warn,
  }) {
    while (r.next()) {
      if (r.eventType == XmlEventType.startElement) break;
    }
    if (r.eventType != XmlEventType.startElement) {
      return WorksheetPart._untyped(r.sourceText(0, r.sourceLength));
    }
    if (r.namespaceUri == strictSpreadsheetNs) {
      throw strictUnsupported(part: part);
    }
    if (r.localName != 'worksheet' || r.namespaceUri != Ns.main) {
      return WorksheetPart._untyped(r.sourceText(0, r.sourceLength));
    }
    final WorksheetPart sheet = WorksheetPart._typed(
      XmlRoot.capture(r),
      <Object>[],
    );
    final List<Object> children = sheet._children;
    // The block's list grows while its run of elements lasts, and not after.
    final List<GroupItem<CfEntry>> conditionalItems = <GroupItem<CfEntry>>[];
    int conditionalRules = 0;
    CfBlock? conditional;
    final int rootDepth = r.depth;
    while (r.next()) {
      if (r.eventType == XmlEventType.endElement && r.depth < rootDepth) {
        break;
      }
      if (r.eventType != XmlEventType.startElement) continue;
      final bool main = r.namespaceUri == Ns.main;
      if (main && r.localName == 'dimension' && sheet._dimension == null) {
        final _Dimension d = _Dimension(
          r.qualifiedName,
          Map<String, String>.of(r.declaredNamespaces),
          keepAttributes(r, except: const <String>{'ref'}),
        );
        r.skip();
        sheet._dimension = d;
        children.add(d);
      } else if (main &&
          r.localName == 'sheetFormatPr' &&
          !sheet._hasSheetFormat) {
        sheet._hasSheetFormat = true;
        final _SheetFormat f = _SheetFormat(
          r.qualifiedName,
          Map<String, String>.of(r.declaredNamespaces),
          keepAttributes(r),
        );
        final int depth = r.depth;
        bool hasChildren = false;
        final OpaqueXml whole = OpaqueXml.capture(
          r,
          onEvent: (XmlPullReader e) {
            if (e.eventType == XmlEventType.startElement && e.depth > depth) {
              hasChildren = true;
            }
          },
        );
        if (hasChildren) {
          sheet._formatOpaque = f;
          children.add(whole);
        } else {
          children.add(f);
        }
      } else if (main && r.localName == 'cols' && !sheet._hasCols) {
        sheet._hasCols = true;
        final CapturedCols cols = captureCols(r);
        final ColsGroup? typed = cols.typed;
        if (typed == null) {
          sheet._colsOpaque = true;
          children.add(cols.whole);
        } else {
          children.add(typed);
        }
      } else if (main &&
          _nodeSlots.contains(r.localName) &&
          sheet._nodesRead.add(r.localName)) {
        children.add(XmlNode.read(r, worksheetNodeShape));
      } else if (main && r.localName == 'mergeCells' && !sheet._hasMergeCells) {
        sheet._hasMergeCells = true;
        children.add(_readMergeCells(r, part, limits, warn));
      } else if (main && r.localName == 'hyperlinks' && !sheet._hasHyperlinks) {
        sheet._hasHyperlinks = true;
        children.add(
          readItemGroup<LinkEntry>(
            r,
            childName: 'hyperlink',
            limits: limits,
            part: part,
            read: readLinkEntry,
            warn: (String problem) => warn(
              XlsxWarningCode.featureEntryInvalid,
              null,
              detail: problem,
            ),
          ),
        );
      } else if (main &&
          r.localName == 'dataValidations' &&
          !sheet._hasDataValidations) {
        sheet._hasDataValidations = true;
        children.add(
          readItemGroup<XlsxDataValidation>(
            r,
            childName: 'dataValidation',
            limits: limits,
            part: part,
            read: readDataValidation,
            warn: (String problem) => warn(
              XlsxWarningCode.featureEntryInvalid,
              null,
              detail: problem,
            ),
          ),
        );
      } else if (main && r.localName == 'tableParts' && !sheet._hasTableParts) {
        sheet._hasTableParts = true;
        children.add(
          readItemGroup<String>(
            r,
            childName: 'tablePart',
            limits: limits,
            part: part,
            read: (OpaqueXml child) => (
              value: readerOf(child).getAttribute('id', namespaceUri: Ns.rel),
              problem: null,
            ),
            warn: (String problem) {},
          ),
        );
      } else if (main &&
          r.localName == 'conditionalFormatting' &&
          (conditional == null || identical(children.last, conditional))) {
        if (conditional == null) {
          children.add(conditional = CfBlock(conditionalItems));
        }
        checkListRoom(conditionalItems.length, limits, part);
        final OpaqueXml source = OpaqueXml.capture(r);
        final ({CfEntry? value, String? problem}) read =
            readConditionalFormatting(
              source,
              onRule: () => checkListRoom(conditionalRules++, limits, part),
            );
        final String? problem = read.problem;
        if (problem != null) {
          warn(XlsxWarningCode.featureEntryInvalid, null, detail: problem);
        }
        conditionalItems.add(GroupItem<CfEntry>(read.value, source));
      } else if (main &&
          r.localName == 'sheetData' &&
          sheet._sheetData == null) {
        final _SheetData data = _SheetData(
          r.qualifiedName,
          Map<String, String>.of(r.declaredNamespaces),
          keepAttributes(r),
        );
        sheet._sheetData = data;
        children.add(data);
        sheet._readRows(r, part, limits, warn);
      } else {
        children.add(OpaqueXml.capture(r));
      }
    }
    if (sheet._sheetData == null) sheet._insertSheetData();
    final XmlNode? extLst = sheet._topNode('extLst');
    if (extLst != null) {
      sheet._x14Node = extLst;
      sheet._x14Block = readX14Block(
        extLst,
        warn: (String problem) =>
            warn(XlsxWarningCode.featureEntryInvalid, null, detail: problem),
        checkRoom: (int count) => checkListRoom(count, limits, part),
      );
    }
    sheet._fileRowLevel = sheet._deepestRowLevel();
    sheet._fileColumnLevel = sheet._deepestColumnLevel();
    return sheet;
  }

  /// A new worksheet: a root declaring the SpreadsheetML and relationships
  /// namespaces, as the writer's, with `<dimension ref="A1"/>` and an empty
  /// `<sheetData>`.
  factory WorksheetPart.empty() {
    final XmlPullReader r = XmlPullReader(
      '<worksheet xmlns="${Ns.main}" xmlns:r="${Ns.rel}"/>',
    )..next();
    final _Dimension d = _Dimension(
      'dimension',
      const <String, String>{},
      const <KeptAttribute>[],
    );
    final WorksheetPart sheet = WorksheetPart._typed(
      XmlRoot.capture(r),
      <Object>[d],
    ).._dimension = d;
    sheet._insertSheetData();
    return sheet;
  }

  /// The text of an untyped part; `null` for a typed one.
  final String? _untypedText;
  final XmlRoot? _root;

  /// [_Dimension], [_SheetFormat], [ColsGroup], [MergeGroup], [XmlNode],
  /// [ItemGroup], [CfBlock], [_SheetData] and [OpaqueXml] children, in order.
  final List<Object> _children;
  _Dimension? _dimension;

  /// Whether the part read a `<sheetFormatPr>`, typed or kept opaque (one
  /// with element children): a second one is not typed.
  bool _hasSheetFormat = false;

  /// The attributes of a `<sheetFormatPr>` kept opaque, for reading only.
  _SheetFormat? _formatOpaque;

  /// The deepest row outline level the file has: `<sheetFormatPr>` is made
  /// or raised on save only for a level deeper than this, which only an
  /// edit gives, so an unchanged file keeps what it says, even when that is
  /// less than its rows need.
  int _fileRowLevel = 0;

  /// As [_fileRowLevel], for the columns.
  int _fileColumnLevel = 0;

  /// Whether the part read a `<cols>`, typed or kept opaque; a second one
  /// is not typed.
  bool _hasCols = false;

  /// Whether the first `<cols>` is kept opaque (it is not plain, see
  /// `columns.dart`): columns are not edited then.
  bool _colsOpaque = false;

  /// Whether the part read a SpreadsheetML `<mergeCells>`; a second one is
  /// kept opaque and its merges are not read.
  bool _hasMergeCells = false;

  /// Whether the part read a SpreadsheetML `<hyperlinks>`; a second one is
  /// kept opaque.
  bool _hasHyperlinks = false;

  /// Whether the first `<tableParts>` was read as a group; a later one stays
  /// as written.
  bool _hasTableParts = false;

  /// Whether the part read a SpreadsheetML `<dataValidations>`; a second one
  /// is kept opaque.
  bool _hasDataValidations = false;

  /// The `<extLst>` [_x14Block] is a reading of.
  XmlNode? _x14Node;

  /// The reading of [_x14Node]; see [x14Block].
  X14Block? _x14Block;

  /// The elements of [_nodeSlots] the part read; a second one of a name is
  /// kept opaque.
  final Set<String> _nodesRead = <String>{};
  _SheetData? _sheetData;
  CellEncoder? _encoder;

  /// The cells and row attributes of the sheet.
  ///
  /// For an untyped part the store stays empty; [encode] throws a
  /// [StateError] when anything was put in it, as there is no sheet data to
  /// write it to.
  final CellStore cells = CellStore();

  /// Whether the part is a SpreadsheetML worksheet; `false` for an untyped
  /// part (a chartsheet, say), whose [cells] must stay empty.
  bool get isTyped => _untypedText == null;

  /// Sets the encoder that writes the cells; [encode] needs one.
  void bindEncoder(CellEncoder encoder) {
    _encoder = encoder;
  }

  /// Reads the `<mergeCells>` the current event of [r] starts and consumes
  /// it. A `<mergeCell>` is read as `readMerges` reads it (same namespace,
  /// same `ref` parse); one it would skip is kept as written and reported
  /// to [warn] as `mergeRangeInvalid`. Throws a `limitExceeded`
  /// [XlsxReadException] naming `maxMerges` and [part] when the group holds
  /// more readable merges than [limits] allows.
  static MergeGroup _readMergeCells(
    XmlPullReader r,
    String part,
    XlsxReadLimits limits,
    void Function(XlsxWarningCode code, String? cell, {String? detail}) warn,
  ) {
    final String qualifiedName = r.qualifiedName;
    final Map<String, String> namespaces = Map<String, String>.of(
      r.declaredNamespaces,
    );
    final List<KeptAttribute> attributes = keepAttributes(r);
    final int depth = r.depth;
    final List<MergeItem> items = <MergeItem>[];
    int readable = 0;
    if (r.isEmptyElement) {
      r.skip();
    } else {
      while (r.next()) {
        if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
        if (r.eventType != XmlEventType.startElement) continue;
        final bool mergeCell =
            r.depth == depth + 1 &&
            r.namespaceUri == Ns.main &&
            r.localName == 'mergeCell';
        final String? ref = mergeCell
            ? r.getAttribute('ref', namespaceUri: '')
            : null;
        final XlsxRange? range = ref == null ? null : parseMergeRange(ref);
        final OpaqueXml source = OpaqueXml.capture(r);
        if (mergeCell && range == null) {
          warn(XlsxWarningCode.mergeRangeInvalid, null);
        }
        if (range != null) {
          if (readable >= limits.maxMerges) {
            throw XlsxReadException(
              XlsxReadFailure.limitExceeded,
              'Limit maxMerges (${limits.maxMerges}) exceeded.',
              part: part,
            );
          }
          readable++;
        }
        items.add(MergeItem._(range, source, mergeCell));
      }
    }
    return MergeGroup(qualifiedName, namespaces, attributes, items);
  }

  void _readRows(
    XmlPullReader r,
    String part,
    XlsxReadLimits limits,
    void Function(XlsxWarningCode code, String? cell, {String? detail}) warn,
  ) {
    final RawRowReader rows = RawRowReader(
      r,
      part: part,
      keepExtras: true,
      limits: limits,
      warn: warn,
    );
    for (RawRow? row = rows.next(); row != null; row = rows.next()) {
      for (int i = 0; i < row.cells.length; i++) {
        cells.put(row.index, row.columns[i], row.cells[i]);
      }
      if (row.attributes.isNotEmpty) {
        cells.setRowAttributes(row.index, row.attributes);
      }
      if (row.extraChildren.isNotEmpty) {
        cells.setRowChildren(row.index, row.extraChildren);
      }
    }
    cells.trim();
    _sheetData!.extraChildren = rows.extraChildren;
  }

  void _insertSheetData() {
    final _SheetData data = _SheetData(
      '${_prefixOf(_root!.qualifiedName)}sheetData',
      const <String, String>{},
      const <KeptAttribute>[],
    );
    _sheetData = data;
    _children.insert(_positionFor('sheetData'), data);
  }

  /// The index in [_children] before the first element that follows [name]
  /// in [worksheetChildOrder], or the end.
  int _positionFor(String name) {
    final Set<String> after = worksheetChildOrder
        .skip(worksheetChildOrder.indexOf(name) + 1)
        .toSet();
    for (var i = 0; i < _children.length; i++) {
      final Object c = _children[i];
      if (c is _Dimension && after.contains('dimension') ||
          c is _SheetFormat && after.contains('sheetFormatPr') ||
          c is ColsGroup && after.contains('cols') ||
          c is MergeGroup && after.contains('mergeCells') ||
          c is XmlNode && after.contains(c.localName) ||
          c is ItemGroup<Object?> && after.contains(c.localName) ||
          c is CfBlock && after.contains('conditionalFormatting') ||
          c is _SheetData && after.contains('sheetData') ||
          c is OpaqueXml &&
              c.namespaceUri == Ns.main &&
              after.contains(c.localName)) {
        return i;
      }
    }
    return _children.length;
  }

  /// Writes the part.
  ///
  /// Throws a [StateError] when no encoder is bound, or when cells were put
  /// in an untyped part.
  @override
  List<Uint8List> encode() {
    final Utf8Buffer buffer = Utf8Buffer();
    final String? untyped = _untypedText;
    if (untyped != null) {
      if (cells.rowIndexes.isNotEmpty) {
        throw StateError(
          'The worksheet part is not a SpreadsheetML worksheet; its cells '
          'cannot be written.',
        );
      }
      return (buffer..write(untyped)).takeChunks();
    }
    final CellEncoder? encoder = _encoder;
    if (encoder == null) {
      throw StateError('bindEncoder must be called before encode.');
    }
    final XmlWriter w = XmlWriter(buffer)..declaration();
    final XmlRoot root = _root!;
    writeRootStart(w, root);
    final int rowLevel = _deepestRowLevel();
    final int colLevel = _deepestColumnLevel();
    final int raisedRow = rowLevel > _fileRowLevel ? rowLevel : 0;
    final int raisedCol = colLevel > _fileColumnLevel ? colLevel : 0;
    final bool deeper = raisedRow > 0 || raisedCol > 0;
    final int madeAt = !_formatPresent && deeper
        ? _positionFor('sheetFormatPr')
        : -1;
    for (int i = 0; i <= _children.length; i++) {
      if (i == madeAt) _writeMadeSheetFormat(w, rowLevel, colLevel);
      if (i == _children.length) break;
      final Object c = _children[i];
      switch (c) {
        case _Dimension():
          c.writeTo(w, root.namespaces, _dimensionRef());
        case _SheetFormat():
          c.writeTo(
            w,
            root.namespaces,
            rowLevel: raisedRow,
            colLevel: raisedCol,
          );
        case ColsGroup():
          c.writeTo(w, root.namespaces);
        case MergeGroup():
          c.writeTo(w, root.namespaces);
        case XmlNode():
          c.writeTo(w, root.namespaces);
        case ItemGroup<Object?>():
          // `<hyperlinks>` is the group without a `count`.
          c.writeTo(
            w,
            root.namespaces,
            countAttribute: c.localName == 'hyperlinks' ? null : 'count',
          );
        case CfBlock():
          c.writeTo(w, root.namespaces);
        case _SheetData():
          _writeSheetData(w, c, root.namespaces, encoder);
        case OpaqueXml():
          c.writeTo(w, declaredAbove: root.namespaces);
      }
    }
    w.end();
    return buffer.takeChunks();
  }

  /// The deepest `outlineLevel` of the rows' attributes, 0 when none.
  int _deepestRowLevel() {
    int deepest = 0;
    for (final int row in cells.rowIndexes) {
      for (final KeptAttribute a in cells.rowAttributes(row)) {
        if (a.namespaceUri.isNotEmpty || a.qualifiedName != 'outlineLevel') {
          continue;
        }
        final int level = parseOutlineLevel(a.value) ?? 0;
        if (level > deepest) deepest = level;
      }
    }
    return deepest;
  }

  /// The deepest outline level of the typed `<cols>`, 0 when none.
  int _deepestColumnLevel() => _cols?.deepestOutline ?? 0;

  /// Writes the `<sheetFormatPr>` of a part that had none, as the writer
  /// does for an outline: `defaultRowHeight` (required), then
  /// `outlineLevelRow` and `outlineLevelCol` when they are deeper than 0.
  void _writeMadeSheetFormat(XmlWriter w, int rowLevel, int colLevel) {
    w
      ..start('${_prefixOf(_root!.qualifiedName)}sheetFormatPr')
      ..attribute('defaultRowHeight', '15');
    if (rowLevel > 0) w.attribute('outlineLevelRow', '$rowLevel');
    if (colLevel > 0) w.attribute('outlineLevelCol', '$colLevel');
    w.end();
  }

  // -- Columns and default sizes ---------------------------------------------

  /// The typed first `<cols>`, or `null` when there is none (or it is kept
  /// opaque).
  ColsGroup? get _cols {
    for (final Object c in _children) {
      if (c is ColsGroup) return c;
    }
    return null;
  }

  /// The typed first `<sheetFormatPr>`, or `null`.
  _SheetFormat? get _format {
    for (final Object c in _children) {
      if (c is _SheetFormat) return c;
    }
    return null;
  }

  /// Whether the part has a `<sheetFormatPr>`, typed or kept opaque.
  bool get _formatPresent => _formatOpaque != null || _format != null;

  /// Whether the columns can be edited: the part is a worksheet and its
  /// first `<cols>`, if any, is typed.
  bool get columnsEditable => isTyped && !_colsOpaque;

  /// The run of the first `<cols>` holding [column] (1-based), or `null`.
  ColRun? columnRunAt(int column) => _cols?.runAt(column);

  /// The runs of the first `<cols>`: none when the part has none or it is
  /// kept opaque (see [columnsEditable]).
  List<ColRun> get columnRuns => _cols?.runs ?? const <ColRun>[];

  /// Makes [runs] the `<col>` elements of the first `<cols>`: an empty list
  /// removes it, and a part without one gets it in schema position. Must
  /// run inside `editLayout`; throws a [StateError] when [columnsEditable]
  /// is false.
  void setColumnRuns(List<ColRun> runs) {
    if (!columnsEditable) {
      throw StateError('The sheet\'s <cols> cannot be edited.');
    }
    final ColsGroup? group = _cols;
    if (group == null) {
      if (runs.isEmpty) return;
      _children.insert(
        _positionFor('cols'),
        ColsGroup(
          '${_prefixOf(_root!.qualifiedName)}cols',
          const <String, String>{},
          const <KeptAttribute>[],
          runs,
        ),
      );
      return;
    }
    final int at = _children.indexOf(group);
    if (runs.isEmpty) {
      _children.removeAt(at);
    } else {
      _children[at] = group.withRuns(runs);
    }
  }

  /// The element name prefix (with the colon, or empty) the part's own
  /// elements take.
  String get elementPrefix => _prefixOf(_root!.qualifiedName);

  /// Whether the `<sheetFormatPr>` can be edited: the part is a worksheet
  /// and its first one, if any, has no element children.
  bool get sheetFormatEditable => isTyped && _formatOpaque == null;

  /// The value of the attribute without a namespace named [name] on the
  /// first `<sheetFormatPr>`, whether typed or opaque, or `null`.
  String? sheetFormatAttribute(String name) =>
      (_format ?? _formatOpaque)?.attribute(name);

  /// Whether the part has a `<sheetFormatPr>`.
  bool get hasSheetFormat => _formatPresent;

  /// Applies [changes] to the attributes of the `<sheetFormatPr>`, as
  /// [replaceAttributes] does, making the element in schema position when
  /// the part has none. Must run inside `editLayout`; throws a [StateError]
  /// when [sheetFormatEditable] is false.
  void changeSheetFormat(Map<String, String?> changes) {
    if (!sheetFormatEditable) {
      throw StateError('The sheet\'s <sheetFormatPr> cannot be edited.');
    }
    final _SheetFormat? format = _format;
    if (format == null) {
      _children.insert(
        _positionFor('sheetFormatPr'),
        _SheetFormat(
          '${_prefixOf(_root!.qualifiedName)}sheetFormatPr',
          const <String, String>{},
          replaceAttributes(const <KeptAttribute>[], changes),
        ),
      );
      return;
    }
    final List<KeptAttribute> next = replaceAttributes(
      format.attributes,
      changes,
    );
    if (sameAttributes(format.attributes, next)) return;
    _children[_children.indexOf(format)] = format.withAttributes(next);
  }

  // -- Merged ranges ---------------------------------------------------------

  MergeGroup? get _mergeGroup {
    for (final Object c in _children) {
      if (c is MergeGroup) return c;
    }
    return null;
  }

  /// The readable merged ranges of the first `<mergeCells>`, in file order;
  /// none for an untyped part.
  List<XlsxRange> get merges => _mergeGroup?.ranges ?? const <XlsxRange>[];

  /// Adds the merge [range] after the others, making the `<mergeCells>` in
  /// schema position when the part has none. Must run inside `editLayout`
  /// of slot `mergeCells`; the caller has checked [range].
  void addMerge(XlsxRange range) {
    final MergeGroup? group = _mergeGroup;
    if (group == null) {
      _children.insert(
        _positionFor('mergeCells'),
        MergeGroup(
          '${_prefixOf(_root!.qualifiedName)}mergeCells',
          const <String, String>{},
          const <KeptAttribute>[],
          <MergeItem>[MergeItem.made(range)],
          edited: true,
        ),
      );
      return;
    }
    _children[_children.indexOf(group)] = group.withItems(<MergeItem>[
      ...group.items,
      MergeItem.made(range),
    ]);
  }

  /// Removes the first merge equal to [range]; the `<mergeCells>` goes with
  /// its last child. Must run inside `editLayout` of slot `mergeCells`.
  /// Throws a [StateError] when [range] is not merged.
  void removeMerge(XlsxRange range) {
    final MergeGroup? group = _mergeGroup;
    final int at = group == null
        ? -1
        : group.items.indexWhere((MergeItem i) => i.range == range);
    if (group == null || at < 0) {
      throw StateError('The range ${range.ref} is not merged.');
    }
    final List<MergeItem> next = <MergeItem>[...group.items]..removeAt(at);
    final int index = _children.indexOf(group);
    if (next.isEmpty) {
      _children.removeAt(index);
    } else {
      _children[index] = group.withItems(next);
    }
  }

  /// Maps every readable merge of the first `<mergeCells>` through [map]:
  /// a merge it gives back unchanged stays as read, a moved one is written
  /// anew, and one it maps to `null` or to a single cell goes; the
  /// `<mergeCells>` goes with its last child. Changes nothing when no merge
  /// moves. Must run inside `editLayout` of slot `mergeCells`.
  void mapMerges(XlsxRange? Function(XlsxRange range) map) {
    final MergeGroup? group = _mergeGroup;
    if (group == null) return;
    bool changed = false;
    final List<MergeItem> next = <MergeItem>[];
    for (final MergeItem item in group.items) {
      final XlsxRange? range = item.range;
      final XlsxRange? moved = range == null ? null : map(range);
      if (range == null || moved == range) {
        next.add(item);
        continue;
      }
      changed = true;
      if (moved != null && !moved.isSingleCell) {
        next.add(MergeItem.made(moved));
      }
    }
    if (!changed) return;
    final int index = _children.indexOf(group);
    if (next.isEmpty) {
      _children.removeAt(index);
    } else {
      _children[index] = group.withItems(next);
    }
  }

  // -- Sheet properties and views --------------------------------------------

  /// The typed first element of [slot], one of [_nodeSlots], or `null`.
  XmlNode? _topNode(String slot) {
    for (final Object c in _children) {
      if (c is XmlNode && c.localName == slot) return c;
    }
    return null;
  }

  /// The typed first `<sheetPr>`, or `null`.
  XmlNode? get sheetPr => _topNode('sheetPr');

  /// The typed first `<sheetViews>`, or `null`.
  XmlNode? get sheetViews => _topNode('sheetViews');

  /// Makes [node] the first element of [slot], one of [_nodeSlots]: in
  /// place, or in schema position when the part has none; `null` removes it.
  /// Must run inside `editLayout` of that slot.
  void setNode(String slot, XmlNode? node) {
    final XmlNode? old = _topNode(slot);
    if (old == null) {
      if (node != null) _children.insert(_positionFor(slot), node);
    } else if (node == null) {
      _children.remove(old);
    } else {
      _children[_children.indexOf(old)] = node;
    }
  }

  /// The first `<hyperlinks>` as a group of [LinkEntry]s, or `null` when the
  /// part has none. Edited as a layout element of slot `hyperlinks`.
  ItemGroup<LinkEntry>? get hyperlinkGroup {
    final ItemGroup<Object?>? group = _topGroup('hyperlinks');
    return group is ItemGroup<LinkEntry> ? group : null;
  }

  /// The first `<dataValidations>` as a group of [XlsxDataValidation]s, or
  /// `null` when the part has none. Edited as a layout element of slot
  /// `dataValidations`.
  ItemGroup<XlsxDataValidation>? get dataValidationGroup {
    final ItemGroup<Object?>? group = _topGroup('dataValidations');
    return group is ItemGroup<XlsxDataValidation> ? group : null;
  }

  /// The first run of adjacent `<conditionalFormatting>`s, or `null` when
  /// the part has none. Edited as a layout element of slot
  /// `conditionalFormatting`.
  CfBlock? get conditionalBlock {
    for (final Object c in _children) {
      if (c is CfBlock) return c;
    }
    return null;
  }

  /// A reading of the first `<extLst>`, or `null` when it holds no Excel 2010
  /// conditional formats. The element is edited as a layout element of slot
  /// `extLst`; the reading follows it, an undo included.
  X14Block? get x14Block {
    final XmlNode? node = _topNode('extLst');
    if (!identical(node, _x14Node)) {
      _x14Node = node;
      _x14Block = node == null ? null : readX14Block(node);
    }
    return _x14Block;
  }

  /// The `r:id` of the part's first SpreadsheetML `<legacyDrawing>`, the
  /// relationship of the VML drawing that holds its notes' boxes, or `null`
  /// when there is none or it names no relationship.
  String? get legacyDrawingId {
    final OpaqueXml? element = _legacyDrawing;
    return element == null
        ? null
        : readerOf(element).getAttribute('id', namespaceUri: Ns.rel);
  }

  /// Adds a `<tablePart>` of the relationship [id] after the others, making
  /// the `<tableParts>` in schema position when the part has none. Must run
  /// inside `editLayout` of slot `tableParts`.
  void addTablePart(String id) {
    final GroupItem<String> item = GroupItem<String>(
      id,
      renderElements((XmlWriter w) {
        w.empty('tablePart', <String, String>{'r:id': id});
      }).single,
    );
    final ItemGroup<String>? group = _tableParts;
    if (group == null) {
      _children.insert(
        _positionFor('tableParts'),
        ItemGroup<String>(
          '${elementPrefix}tableParts',
          'tableParts',
          const <String, String>{},
          const <KeptAttribute>[],
          <GroupItem<String>>[item],
          edited: true,
        ),
      );
      return;
    }
    _children[_children.indexOf(group)] = group.withItems(<GroupItem<String>>[
      ...group.items,
      item,
    ]);
  }

  /// Removes the `<tablePart>`s of the relationship [id]; the `<tableParts>`
  /// goes when nothing is left in it. Must run inside `editLayout` of slot
  /// `tableParts`. A part without such an entry changes nothing.
  void removeTablePart(String id) {
    final ItemGroup<String>? group = _tableParts;
    if (group == null || !group.values.contains(id)) return;
    final List<GroupItem<String>> next = <GroupItem<String>>[
      for (final GroupItem<String> i in group.items)
        if (i.value != id) i,
    ];
    final int index = _children.indexOf(group);
    if (next.isEmpty) {
      _children.removeAt(index);
    } else {
      _children[index] = group.withItems(next);
    }
  }

  /// The first `<tableParts>`, or `null`.
  ItemGroup<String>? get _tableParts =>
      _topGroup('tableParts') as ItemGroup<String>?;

  /// The first SpreadsheetML `<legacyDrawing>`, or `null`.
  OpaqueXml? get _legacyDrawing => _firstMainChild('legacyDrawing');

  /// The `r:id` of the part's first SpreadsheetML `<drawing>`, the
  /// relationship of the drawing part that holds its pictures, or `null`
  /// when there is none or it names no relationship.
  String? get drawingId {
    final OpaqueXml? element = _firstMainChild('drawing');
    return element == null
        ? null
        : readerOf(element).getAttribute('id', namespaceUri: Ns.rel);
  }

  OpaqueXml? _firstMainChild(String localName) {
    for (final Object c in _children) {
      if (c is OpaqueXml &&
          c.namespaceUri == Ns.main &&
          c.localName == localName) {
        return c;
      }
    }
    return null;
  }

  /// The elements that hold conditional format rules, as written: those of
  /// the [CfBlock], those after it, and what an `<extLst>` keeps.
  Iterable<OpaqueXml> get _ruleElements sync* {
    for (final Object c in _children) {
      if (c is CfBlock) {
        yield* c.items.map((GroupItem<CfEntry> i) => i.source);
      } else if (c is OpaqueXml &&
          c.namespaceUri == Ns.main &&
          (c.localName == 'conditionalFormatting' || c.localName == 'extLst')) {
        yield c;
      } else if (c is XmlNode && c.localName == 'extLst') {
        for (final Object ext in c.children) {
          if (ext is OpaqueXml) yield ext;
          if (ext is XmlNode) yield* ext.children.whereType<OpaqueXml>();
        }
      }
    }
  }

  /// The highest priority of the sheet's conditional format rules, those of
  /// an element that is not listed and of the `<extLst>` included, or 0 for
  /// none.
  int get highestConditionalPriority {
    int highest = 0;
    for (final OpaqueXml element in _ruleElements) {
      final int found = highestRulePriority(element);
      if (found > highest) highest = found;
    }
    return highest;
  }

  /// Every id of an Excel 2010 rule the part uses, in uppercase: an
  /// `x14:cfRule`'s and an `x14:id`'s, listed or not.
  Set<String> get usedX14Ids {
    final Set<String> ids = <String>{};
    for (final OpaqueXml element in _ruleElements) {
      collectX14Ids(element, ids, ids);
    }
    return <String>{for (final String id in ids) id.toUpperCase()};
  }

  /// The ids the Excel 2007 elements that are not listed name.
  Set<String> get unlistedX14Links {
    final Set<String> links = <String>{};
    for (final Object c in _children) {
      if (c is CfBlock) {
        for (final GroupItem<CfEntry> item in c.items) {
          if (item.value == null) {
            collectX14Ids(item.source, <String>{}, links);
          }
        }
      } else if (c is OpaqueXml &&
          c.namespaceUri == Ns.main &&
          c.localName == 'conditionalFormatting') {
        collectX14Ids(c, <String>{}, links);
      }
    }
    return links;
  }

  /// The [ItemGroup] of [slot], or `null`.
  ItemGroup<Object?>? _topGroup(String slot) {
    for (final Object c in _children) {
      if (c is ItemGroup<Object?> && c.localName == slot) return c;
    }
    return null;
  }

  /// The typed first element of [slot] (`cols`, `sheetFormatPr`,
  /// `mergeCells`, one of [_nodeSlots], `dataValidations`, `hyperlinks`,
  /// `tableParts`, `conditionalFormatting`, whose element is the [CfBlock],
  /// or `drawing` and `legacyDrawing`, whose element is its [OpaqueXml]), or
  /// `null` when the part has none typed. Any other element kept as an
  /// [OpaqueXml] is not a slot's element: it is never swapped, and a repeated
  /// one stays where it is. Elements are immutable, so an edit replaces the
  /// element, and [swapLayout] undoes it.
  Object? layoutElement(String slot) => switch (slot) {
    'cols' => _cols,
    'sheetFormatPr' => _format,
    'mergeCells' => _mergeGroup,
    'dataValidations' || 'hyperlinks' || 'tableParts' => _topGroup(slot),
    'conditionalFormatting' => conditionalBlock,
    'drawing' => _firstMainChild('drawing'),
    'legacyDrawing' => _legacyDrawing,
    _ when _nodeSlots.contains(slot) => _topNode(slot),
    _ => throw ArgumentError.value(slot, 'slot', 'Not a layout slot.'),
  };

  /// Replaces the layout element [from] of [slot] by [to]: in place, or
  /// where the schema puts it when [from] is `null` (inserted) or no longer
  /// there; `null` for [to] removes [from]. Only that slot's element is
  /// touched, so edits of different elements swap independently.
  ///
  /// [position], from [layoutPosition], puts an inserted element back where
  /// it was, which a file out of schema order needs; -1 asks for the schema's
  /// place.
  void swapLayout(String slot, Object? from, Object? to, {int position = -1}) {
    final int at = from == null
        ? -1
        : _children.indexWhere((Object c) => identical(c, from));
    if (to == null) {
      if (at >= 0) _children.removeAt(at);
    } else if (at >= 0) {
      _children[at] = to;
    } else if (position >= 0 && position <= _children.length) {
      _children.insert(position, to);
    } else {
      _children.insert(_positionFor(slot), to);
    }
  }

  /// Where [element] is among the part's children, or -1 when it is not
  /// there, for [swapLayout].
  int layoutPosition(Object? element) =>
      _children.indexWhere((Object c) => identical(c, element));

  String _dimensionRef() {
    final ({int firstRow, int lastRow, int firstColumn, int lastColumn})? b =
        cells.bounds;
    if (b == null) return 'A1';
    final String first = cellRef(b.firstRow, b.firstColumn);
    if (b.firstRow == b.lastRow && b.firstColumn == b.lastColumn) {
      return first;
    }
    return '$first:${cellRef(b.lastRow, b.lastColumn)}';
  }

  /// Writes `<sheetData>` and its rows. Rows and cells are written without a
  /// prefix, so the SpreadsheetML namespace is declared as the default on
  /// `<sheetData>` when it is not the default there already.
  void _writeSheetData(
    XmlWriter w,
    _SheetData data,
    Map<String, String> above,
    CellEncoder encoder,
  ) {
    final Map<String, String> declared = <String, String>{...data.namespaces};
    if (mergeNamespaces(above, declared)[''] != Ns.main) {
      declared[''] = Ns.main;
    }
    final Map<String, String> inner = mergeNamespaces(above, declared);
    w.start(data.qualifiedName);
    writeNamespaceDeclarations(w, declared);
    writeKeptAttributes(w, data.attributes, declaredAbove: inner);
    final List<int> columns = <int>[];
    final List<RawCell> rowCells = <RawCell>[];
    for (final int row in cells.rowIndexes) {
      columns.clear();
      rowCells.clear();
      cells.forEachInRow(row, (int column, RawCell cell) {
        columns.add(column);
        rowCells.add(cell);
      });
      w
        ..start('row')
        ..attribute('r', '${row + 1}');
      if (columns.isNotEmpty) {
        w.attribute('spans', '${columns.first + 1}:${columns.last + 1}');
      }
      writeKeptAttributes(w, cells.rowAttributes(row), declaredAbove: inner);
      for (int i = 0; i < columns.length; i++) {
        encoder.writeRaw(
          w,
          row: row,
          column: columns[i],
          cell: rowCells[i],
          declaredAbove: inner,
        );
      }
      for (final OpaqueXml child in cells.rowChildren(row)) {
        child.writeTo(w, declaredAbove: inner);
      }
      w.end();
    }
    for (final OpaqueXml child in data.extraChildren) {
      child.writeTo(w, declaredAbove: inner);
    }
    w.end();
  }
}

String _prefixOf(String qualifiedName) {
  final int colon = qualifiedName.indexOf(':');
  return colon < 0 ? '' : qualifiedName.substring(0, colon + 1);
}
