/// A drawing part (`xl/drawings/drawingN.xml`): the anchors of a sheet's
/// pictures and of whatever else sits on it, each kept as written.
///
/// Not ported from Quds; written for jet_office.
///
/// The part is read, not rewritten: every anchor keeps its source
/// ([OpaqueXml]), so a chart, a shape, a group or a picture nobody edits is
/// written back character for character. A `oneCellAnchor` or `twoCellAnchor`
/// that directly holds a picture showing embedded media also keeps its typed
/// [XlsxAnchor] and [DrawingPic], and one that directly holds a chart's
/// graphic frame its [XlsxAnchor] and [DrawingChartFrame]; every other child
/// of the root is an entry without a value. An edit changes
/// [DrawingPart.entries], a mutable list, and [DrawingPart.encode] writes the
/// part from it; each entry knows the `cNvPr` ids it uses, so a new picture
/// takes a free one ([DrawingPart.nextId]). A new entry is the writer's
/// anchor ([DrawingEntry.rendered]); a moved one keeps all but its place
/// ([DrawingEntry.movedTo]).
library;

import 'dart:typed_data';

import '../../drawingml/chart/chart_space.dart' show drawingChartNamespace;
import '../../drawingml/picture.dart';
import '../../opc/ooxml.dart';
import '../../opc/opaque_xml.dart';
import '../../opc/package.dart';
import '../../xml/utf8_buffer.dart';
import '../../xml/xml_pull_reader.dart';
import '../../xml/xml_writer.dart';
import '../drawing.dart';
import '../formula/formula_rewrite.dart';
import '../formula/reference_shift.dart';
import '../read/read_limits.dart';
import 'comments_part.dart' show WarnFn;
import 'item_group.dart'
    show checkListRoom, readerOf, renderElements, rewrittenElement;
import 'reference_holders.dart' show SpliceEdit, spliceElement;

/// The identity of a chart's graphic frame: its `cNvPr` `id`, `name` and
/// `description` (`descr`), and the relationship id `chartId` its `c:chart`
/// names.
typedef DrawingChartFrame = ({
  int id,
  String name,
  String? description,
  String chartId,
});

/// One child of a drawing's root: the element as written and, for a picture
/// or a chart the model lists, where it sits and what it is.
///
/// Immutable: an edit replaces the entry.
final class DrawingEntry {
  /// An entry kept as [source], which holds the `cNvPr` ids [ids]; [anchor]
  /// is `null` for an element that is no picture or chart the model reads,
  /// [pic] for one that is no picture and [chartFrame] for one that is no
  /// chart.
  DrawingEntry({
    required this.source,
    this.ids = const <int>[],
    this.anchor,
    this.pic,
    this.chartFrame,
  });

  /// The entry of [picture] as the writer renders it, with the `cNvPr` id
  /// [id], showing the media of the relationship [embedId]. It records the
  /// prefixes it uses, so `OpaqueXml.writeTo` declares them on the anchor
  /// under a root that binds others.
  factory DrawingEntry.rendered(
    WorksheetPicture picture, {
    required int id,
    required String embedId,
  }) => _entry(
    renderElements(
      (XmlWriter w) => writeAnchor(w, picture, id: id, embedId: embedId),
      namespaces: const <String, String>{
        'xdr': Ns.xdr,
        'a': Ns.drawingMain,
        'r': Ns.rel,
      },
    ).single,
    <int>[id],
    _noWarning,
  );

  /// The entry of a chart frame as [writeChartFrame] renders it: at
  /// [anchor] (one-cell sizes [extent]), with the `cNvPr` [id], [name] and
  /// [description], showing the chart part of the relationship [chartId].
  factory DrawingEntry.renderedChart(
    XlsxAnchor anchor, {
    required ({int cx, int cy})? extent,
    required int id,
    required String name,
    required String? description,
    required String chartId,
  }) => _entry(
    renderElements(
      (XmlWriter w) => writeChartFrame(
        w,
        anchor,
        extent: extent,
        id: id,
        name: name,
        description: description,
        chartId: chartId,
      ),
      namespaces: const <String, String>{'xdr': Ns.xdr, 'a': Ns.drawingMain},
    ).single,
    <int>[id],
    _noWarning,
  );

  /// The element as written.
  final OpaqueXml source;

  /// The `id` of every `cNvPr` the element holds.
  final List<int> ids;

  /// The relationship ids the element names ([relationshipIdsIn]), read on
  /// first use. Throws XML errors as a reader does.
  late final Set<String> relationshipIds = relationshipIdsIn(source);

  /// Where the picture sits, or `null`.
  final XlsxAnchor? anchor;

  /// The picture's identity and the relationship of its media, or `null`.
  final DrawingPic? pic;

  /// The chart frame's identity and the relationship of its chart part, or
  /// `null`.
  final DrawingChartFrame? chartFrame;

  /// This picture at [place], whose size in EMU is [extent] for a one-cell
  /// anchor: the element takes the kind of [place] and its markers, `ext` and
  /// `editAs`, in the anchor's own prefix. Its other attributes, its
  /// namespace declarations and every other child (the `pic`, `clientData`)
  /// stay as written.
  ///
  /// Must be an entry with an [anchor]. The first of the old `from`, `to` and
  /// `ext` gives way to the new ones.
  DrawingEntry movedTo(XlsxAnchor place, ({int cx, int cy})? extent) {
    final XmlPullReader r = readerOf(source);
    final String prefix = r.prefix;
    final String kind = anchorElementName(place);
    final StringBuffer out = StringBuffer();
    final XmlWriter w = XmlWriter(out)
      ..start(prefix.isEmpty ? kind : '$prefix:$kind');
    writeNamespaceDeclarations(w, r.declaredNamespaces);
    writeKeptAttributes(
      w,
      keepAttributes(r, except: const <String>{'editAs'}),
      declaredAbove: r.namespacesInScope,
    );
    final String? editAs = anchorEditAs(place);
    if (editAs != null) w.attribute('editAs', editAs);
    int at = r.eventEnd;
    bool placed = false;
    final int depth = r.depth;
    while (r.next()) {
      if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
      if (r.eventType != XmlEventType.startElement) continue;
      final int start = r.eventStart;
      final bool marker =
          r.depth == depth + 1 &&
          r.namespaceUri == Ns.xdr &&
          const <String>{'from', 'to', 'ext'}.contains(r.localName);
      r.skip();
      if (!marker) continue;
      w.raw(r.sourceText(at, start));
      at = r.eventEnd;
      if (!placed) writeAnchorPlace(w, place, extent: extent, prefix: prefix);
      placed = true;
    }
    w
      ..raw(r.sourceText(at, r.eventStart))
      ..end();
    return _entry(rewrittenElement(source, out.toString()), ids, _noWarning);
  }

  /// This entry after [edit], a row or column edit of its sheet, or `null`
  /// when it does not move. Excel's three cases: a `twoCellAnchor` (its
  /// `editAs` left out or `twoCell`) moves and resizes with its cells, both
  /// markers shifting ([ReferenceShift.shiftAnchor]); a `oneCellAnchor`, or
  /// a `twoCellAnchor` with `editAs="oneCell"`, moves, its `to` keeping its
  /// distance from `from`; an `absoluteAnchor`, a `twoCellAnchor` with
  /// `editAs="absolute"` and anything else stay. Only the text of the
  /// markers' `row` or `col` and `rowOff` or `colOff` changes, whatever the
  /// anchor holds (a picture, a shape, a chart, a group).
  ///
  /// An `mc:AlternateContent` entry (an equation's text box, say) moves each
  /// `oneCellAnchor` and `twoCellAnchor` that is a direct child of one of its
  /// `mc:Choice` elements or its `mc:Fallback` by the same rules as a
  /// bare anchor, each on its own (an `editAs="absolute"` anchor stays while
  /// the other branch's anchor moves). When a branch holds anything else, or no branch
  /// holds an anchor, the entry stays as written and [onNotShifted] gets a
  /// detail.
  ///
  /// Throws a [StateError] when an insert would push a corner off the sheet
  /// (Excel refuses), and XML errors as a reader does on what a file holds.
  DrawingEntry? shiftedBy(
    ReferenceShift edit, {
    void Function(String detail)? onNotShifted,
  }) {
    if (source.namespaceUri == Ns.mc &&
        source.localName == 'AlternateContent') {
      return _wrappedShiftedBy(edit, onNotShifted);
    }
    if (!_isAnchor(source.namespaceUri, source.localName)) return null;
    final _AnchorMove? move = _anchorMove(
      readerOf(source),
      edit,
      onPushedOff: () => throw _pushedOff(),
    );
    if (move == null) return null;
    final OpaqueXml moved = spliceElement(source, move.markerSplice());
    return _entry(moved, ids, _noWarning);
  }

  /// This entry with every non-empty `textlink` attribute (the cell a
  /// shape's text shows, `textlink="$A$1"`) rewritten by [mapper] as a
  /// formula of the sheet [hostSheet], at any depth: on a bare or a wrapped
  /// anchor's shape, inside a group. `null` when none changes. Only the
  /// attributes' values change; every other character stays as written.
  ///
  /// A `textlink` the formula lexer cannot read is kept and given to
  /// [onUnlexable]. Throws XML errors as a reader does on what a file holds.
  DrawingEntry? withTextLinks(
    ReferenceMapper mapper,
    String hostSheet, {
    required void Function(String text) onUnlexable,
  }) {
    final OpaqueXml next = spliceElement(source, (XmlPullReader r, int _) {
      for (int i = 0; i < r.attributeCount; i++) {
        if (r.attributeQualifiedName(i) != 'textlink') continue;
        final String link = r.attributeValue(i);
        if (link.isEmpty) return null;
        final String? rewritten = rewriteFormula(
          link,
          mapper,
          hostSheet,
          onUnlexable: onUnlexable,
        );
        if (rewritten == null) return null;
        return SpliceEdit(attributes: <String, String>{'textlink': rewritten});
      }
      return null;
    });
    if (identical(next, source)) return null;
    return _entry(next, ids, _noWarning);
  }

  /// [shiftedBy] for an `mc:AlternateContent` entry.
  DrawingEntry? _wrappedShiftedBy(
    ReferenceShift edit,
    void Function(String detail)? onNotShifted,
  ) {
    final List<_AnchorMove?> moves = <_AnchorMove?>[];
    bool pushedOff = false;
    final bool anchorsOnly = walkWrappedAnchors(
      readerOf(source),
      (XmlPullReader r) =>
          moves.add(_anchorMove(r, edit, onPushedOff: () => pushedOff = true)),
    );
    if (!anchorsOnly) {
      onNotShifted?.call(
        'An mc:AlternateContent holds something other than a cell anchor.',
      );
      return null;
    }
    if (pushedOff) throw _pushedOff();
    if (moves.every((_AnchorMove? m) => m == null)) return null;
    final OpaqueXml moved = spliceElement(
      source,
      wrappedAnchorSplice((int anchor) => moves[anchor]?.markerSplice()),
    );
    return _entry(moved, ids, _noWarning);
  }
}

/// Whether an element of [namespace] named [localName] is a cell anchor, a
/// `oneCellAnchor` or a `twoCellAnchor`.
bool _isAnchor(String namespace, String localName) =>
    namespace == Ns.xdr &&
    (localName == 'oneCellAnchor' || localName == 'twoCellAnchor');

/// Whether the element [r] is on is an `mc:Choice` or an `mc:Fallback`.
bool _isBranch(XmlPullReader r) =>
    r.namespaceUri == Ns.mc &&
    (r.localName == 'Choice' || r.localName == 'Fallback');

/// Walks the `mc:AlternateContent` [r] is on: calls [onAnchor] on each cell
/// anchor that is a direct child of an `mc:Choice` or the `mc:Fallback`, in
/// file order, with the reader on its start tag ([onAnchor] must leave it on
/// that anchor's end, or not move it from an empty one). Other children of
/// the root are passed over. Returns `false` when a branch holds an element
/// that is no cell anchor, or no branch holds an anchor. Throws XML errors as
/// a reader does.
bool walkWrappedAnchors(
  XmlPullReader r,
  void Function(XmlPullReader r) onAnchor,
) {
  if (r.isEmptyElement) return false;
  final int depth = r.depth;
  int anchors = 0;
  bool other = false;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType != XmlEventType.startElement) continue;
    if (r.depth == depth + 1) {
      if (!_isBranch(r)) r.skip();
      continue;
    }
    if (r.depth == depth + 2 && _isAnchor(r.namespaceUri, r.localName)) {
      anchors++;
      final bool empty = r.isEmptyElement;
      onAnchor(r);
      if (empty && r.eventType == XmlEventType.startElement) r.skip();
      continue;
    }
    other = true;
    r.skip();
  }
  return anchors > 0 && !other;
}

/// A [spliceElement] edit over an `mc:AlternateContent`: the `n`th cell
/// anchor that [walkWrappedAnchors] visits gets the edit `inAnchor(n)` (none
/// when `null`), called on the anchor's descendants with their level below
/// the anchor.
SpliceEdit? Function(XmlPullReader r, int level) wrappedAnchorSplice(
  SpliceEdit? Function(XmlPullReader r, int level)? Function(int anchor)
  inAnchor,
) {
  bool inBranch = false;
  int anchor = -1;
  SpliceEdit? Function(XmlPullReader r, int level)? current;
  return (XmlPullReader r, int level) {
    if (level == 1) {
      inBranch = _isBranch(r);
      current = null;
    } else if (level == 2) {
      current = null;
      if (inBranch && _isAnchor(r.namespaceUri, r.localName)) {
        current = inAnchor(++anchor);
      }
    } else if (level > 2) {
      return current?.call(r, level - 2);
    }
    return null;
  };
}

/// Where one cell anchor's markers go on an edit: their [read] values and
/// the [next] ones, by marker (`from`, `to`), in the edit's axis.
final class _AnchorMove {
  _AnchorMove(this.cellName, this.offsetName, this.read, this.next);

  /// `row` or `col`.
  final String cellName;

  /// `rowOff` or `colOff`.
  final String offsetName;

  final Map<String, ({int at, int offset})> read;
  final Map<String, ({int at, int offset})> next;

  /// A [spliceElement] edit of the anchor (its markers at level 1, their
  /// values at level 2) that gives the markers their [next] values.
  SpliceEdit? Function(XmlPullReader r, int level) markerSplice() {
    String? marker;
    return (XmlPullReader r, int level) {
      if (level == 1) {
        marker = r.namespaceUri == Ns.xdr ? r.localName : null;
        return null;
      }
      if (level != 2 || r.namespaceUri != Ns.xdr) return null;
      final ({int at, int offset})? value = next[marker];
      final ({int at, int offset})? was = read[marker];
      if (value == null || was == null) return null;
      if (r.localName == cellName && value.at != was.at) {
        return SpliceEdit(text: (String _) => '${value.at}');
      }
      if (r.localName == offsetName && value.offset != was.offset) {
        return SpliceEdit(text: (String _) => '${value.offset}');
      }
      return null;
    };
  }
}

/// How the cell anchor [r] is on moves on [edit] ([DrawingEntry.shiftedBy]'s
/// rules), or `null` when it does not move: it is absolute, a marker cannot
/// be read, it has no `from`, or the edit leaves it where it is. Calls
/// [onPushedOff] and returns `null` when the edit would push a corner off
/// the sheet. Leaves the reader on the anchor's end, or on the start tag of
/// an empty anchor.
_AnchorMove? _anchorMove(
  XmlPullReader r,
  ReferenceShift edit, {
  required void Function() onPushedOff,
}) {
  final String kind = r.localName;
  final String? editAs = kind == 'twoCellAnchor'
      ? r.getAttribute('editAs')
      : null;
  if (r.isEmptyElement) return null;
  if (editAs == 'absolute') {
    r.skip();
    return null;
  }
  final bool sizes = kind == 'twoCellAnchor' && editAs != 'oneCell';
  final bool rows = edit.axis == ShiftAxis.rows;
  final String cellName = rows ? 'row' : 'col';
  final String offsetName = rows ? 'rowOff' : 'colOff';
  final Map<String, ({int at, int offset})> read =
      <String, ({int at, int offset})>{};
  bool unreadable = false;
  final int depth = r.depth;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType != XmlEventType.startElement) continue;
    final String name = r.localName;
    if (unreadable ||
        r.depth != depth + 1 ||
        r.namespaceUri != Ns.xdr ||
        (name != 'from' && name != 'to') ||
        read.containsKey(name)) {
      r.skip();
      continue;
    }
    final ({int at, int offset})? value = _rawMarker(r, cellName, offsetName);
    if (value == null) {
      unreadable = true;
    } else {
      read[name] = value;
    }
  }
  if (unreadable) return null;
  final ({int at, int offset})? from = read['from'];
  if (from == null) return null;
  final ({int at, int offset})? movedFrom = edit.shiftAnchor(
    from.at,
    from.offset,
    end: false,
  );
  if (movedFrom == null) {
    onPushedOff();
    return null;
  }
  final Map<String, ({int at, int offset})> next =
      <String, ({int at, int offset})>{'from': movedFrom};
  final ({int at, int offset})? to = read['to'];
  if (to != null) {
    final ({int at, int offset})? movedTo = sizes
        ? edit.shiftAnchor(to.at, to.offset, end: true)
        : (at: to.at + movedFrom.at - from.at, offset: to.offset);
    if (movedTo == null || movedTo.at > edit.lastIndex) {
      onPushedOff();
      return null;
    }
    next['to'] = movedTo;
  }
  if (next['from'] == from && next['to'] == to) return null;
  return _AnchorMove(cellName, offsetName, read, next);
}

void _noWarning(String detail) {}

StateError _pushedOff() =>
    StateError('The insert would push a drawing object off the sheet.');

/// The relationship ids [element] names: the value of every attribute in the
/// relationships namespace, at any depth. Throws XML errors as a reader does
/// on what a file holds.
Set<String> relationshipIdsIn(OpaqueXml element) {
  final Set<String> ids = <String>{};
  final XmlPullReader r = readerOf(element);
  do {
    if (r.eventType != XmlEventType.startElement) continue;
    for (int i = 0; i < r.attributeCount; i++) {
      if (r.attributeNamespace(i) == Ns.rel) ids.add(r.attributeValue(i));
    }
  } while (r.next());
  return ids;
}

/// A drawing part with its anchors kept as written and its pictures typed.
final class DrawingPart implements PartContent {
  DrawingPart._(this.root, this.entries);

  /// A new part without anchors, as the writer starts one.
  factory DrawingPart.empty() => DrawingPart._(
    const XmlRoot.of('xdr:wsDr', <String, String>{
      'xdr': Ns.xdr,
      'a': Ns.drawingMain,
      'r': Ns.rel,
    }),
    <DrawingEntry>[],
  );

  /// Reads the drawing part [r] is positioned before, or returns `null` when
  /// the root is not a spreadsheet drawing's `wsDr`.
  ///
  /// Each child of the root is an entry. A `oneCellAnchor` or `twoCellAnchor`
  /// whose `pic` shows embedded media (`r:embed`) is typed; one whose `pic`
  /// is linked (`r:link` only) is kept without a value and without a
  /// warning, as is every other element. A `pic` that cannot be read (no
  /// numeric `cNvPr` id, neither `r:embed` nor `r:link`, a marker or an
  /// `ext` that is not a number, a missing marker) is kept without a value
  /// and reported to [warn] as `pic`. One holding, with no `pic`, a
  /// `graphicFrame` whose `a:graphicData` shows a chart is typed with its
  /// [DrawingChartFrame]; a chart frame without a numeric `cNvPr` id or a
  /// `c:chart` `r:id`, or with a marker or `ext` as a broken picture's, is
  /// kept without a value and reported as `chart`. Each entry keeps the `id`
  /// of every `cNvPr` it holds.
  ///
  /// Throws an `XlsxReadException` (`limitExceeded`, naming `maxMerges` and
  /// [part]) when the part holds more children than [limits] allows, and XML
  /// errors as [r] reads.
  static DrawingPart? read(
    XmlPullReader r, {
    required WarnFn warn,
    XlsxReadLimits limits = const XlsxReadLimits(),
    String part = '',
  }) {
    XmlRoot? root;
    final List<DrawingEntry> entries = <DrawingEntry>[];
    while (r.next()) {
      if (r.eventType != XmlEventType.startElement) continue;
      if (r.depth == 1) {
        if (r.localName != 'wsDr' || r.namespaceUri != Ns.xdr) return null;
        root = XmlRoot.capture(r);
        continue;
      }
      if (r.depth != 2) continue;
      checkListRoom(entries.length, limits, part);
      final List<int> ids = <int>[];
      final OpaqueXml source = OpaqueXml.capture(
        r,
        onEvent: (XmlPullReader e) {
          if (e.eventType != XmlEventType.startElement ||
              e.localName != 'cNvPr') {
            return;
          }
          final int? id = int.tryParse(e.getAttribute('id') ?? '');
          if (id != null) ids.add(id);
        },
      );
      entries.add(_entry(source, ids, warn));
    }
    if (root == null) return null;
    return DrawingPart._(root, entries);
  }

  /// The start tag of the root, kept as written.
  final XmlRoot root;

  /// Every child of the root, in file order, listed or not.
  final List<DrawingEntry> entries;

  /// The `cNvPr` id of a new picture: one above the highest the part holds,
  /// at least 2, as the writer's first picture.
  int get nextId {
    int highest = 1;
    for (final DrawingEntry e in entries) {
      for (final int id in e.ids) {
        if (id > highest) highest = id;
      }
    }
    return highest + 1;
  }

  @override
  List<Uint8List> encode() {
    final Utf8Buffer buffer = Utf8Buffer();
    final XmlWriter w = XmlWriter(buffer)..declaration();
    root.writeStart(w);
    for (final DrawingEntry e in entries) {
      e.source.writeTo(w, declaredAbove: root.namespaces);
    }
    w.end();
    return buffer.takeChunks();
  }
}

DrawingEntry _entry(OpaqueXml source, List<int> ids, WarnFn warn) {
  if (source.namespaceUri != Ns.xdr ||
      (source.localName != 'oneCellAnchor' &&
          source.localName != 'twoCellAnchor')) {
    return DrawingEntry(source: source, ids: ids);
  }
  final _Typed? typed = _typed(source, warn);
  return DrawingEntry(
    source: source,
    ids: ids,
    anchor: typed?.anchor,
    pic: typed?.pic,
    chartFrame: typed?.chartFrame,
  );
}

/// What [_typed] reads of an anchor: where it sits and either its picture or
/// its chart frame.
typedef _Typed = ({
  XlsxAnchor anchor,
  DrawingPic? pic,
  DrawingChartFrame? chartFrame,
});

/// The anchor and the picture or chart frame of [source], an anchor element,
/// or `null` when it holds neither one the model reads; a broken picture is
/// reported as `pic`, a broken chart frame as `chart`.
///
/// The first `pic` child is the anchor's object, else its first
/// `graphicFrame`, which is a chart frame when its `a:graphicData` has the
/// chart namespace as its `uri` (any other graphic is no chart, and no
/// problem).
_Typed? _typed(OpaqueXml source, WarnFn warn) {
  final XmlPullReader r = readerOf(source);
  final bool two = source.localName == 'twoCellAnchor';
  final String? editAs = r.getAttribute('editAs');
  XlsxAnchorPoint? from;
  XlsxAnchorPoint? to;
  ({int cx, int cy})? ext;
  DrawingPic? pic;
  _FrameRead? frame;
  bool hasPic = false;
  bool sawFrame = false;
  bool broken = false;
  final int depth = r.depth;
  if (r.isEmptyElement) return null;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType != XmlEventType.startElement) continue;
    if (r.depth != depth + 1 || r.namespaceUri != Ns.xdr) {
      r.skip();
      continue;
    }
    switch (r.localName) {
      case 'from':
        from = _marker(r);
        if (from == null) broken = true;
      case 'to':
        to = _marker(r);
        if (to == null) broken = true;
      case 'ext':
        final int? cx = int.tryParse(r.getAttribute('cx') ?? '');
        final int? cy = int.tryParse(r.getAttribute('cy') ?? '');
        if (cx == null || cy == null || cx < 0 || cy < 0) {
          broken = true;
        } else {
          ext = (cx: cx, cy: cy);
        }
        r.skip();
      case 'pic':
        if (hasPic) {
          r.skip();
          continue;
        }
        hasPic = true;
        pic = readDrawingPic(r);
        if (pic == null) broken = true;
      case 'graphicFrame':
        if (hasPic || sawFrame) {
          r.skip();
          continue;
        }
        sawFrame = true;
        frame = _readFrame(r);
      default:
        r.skip();
    }
  }
  final bool placed =
      !broken && from != null && (two ? to != null : ext != null);
  XlsxAnchor anchor() => two
      ? XlsxTwoCellAnchor(
          from!,
          to!,
          resize: switch (editAs) {
            'oneCell' => XlsxPictureResize.move,
            'absolute' => XlsxPictureResize.none,
            _ => XlsxPictureResize.moveAndSize,
          },
        )
      : XlsxOneCellAnchor(
          from!,
          width: ext!.cx / emuPerPixel,
          height: ext.cy / emuPerPixel,
        );
  final _FrameRead? chart = frame;
  if (!hasPic && chart != null) {
    final int? id = chart.id;
    final String? chartId = chart.chartId;
    if (!placed || id == null || chartId == null) {
      warn('chart');
      return null;
    }
    return (
      anchor: anchor(),
      pic: null,
      chartFrame: (
        id: id,
        name: chart.name,
        description: chart.description,
        chartId: chartId,
      ),
    );
  }
  if (!hasPic) return null;
  final DrawingPic? found = pic;
  if (found != null && found.embedId == null) {
    // A linked picture is not an error; a picture of nothing is.
    if (found.linkId != null) return null;
    broken = true;
  }
  if (found == null || broken || !placed) {
    warn('pic');
    return null;
  }
  return (anchor: anchor(), pic: found, chartFrame: null);
}

/// What [_readFrame] reads of a chart's graphic frame: the `cNvPr` id (`null`
/// when it is missing or not a whole number), name and description, and the
/// `r:id` of the `c:chart` (`null` when it has none).
typedef _FrameRead = ({
  int? id,
  String name,
  String? description,
  String? chartId,
});

/// Reads the `graphicFrame` [r] is on and consumes it; `null` when it shows
/// no chart (its `a:graphicData` `uri` is not the chart namespace). The first
/// `cNvPr` of the first `nvGraphicFramePr` and the first `c:chart` of the
/// first `a:graphic` are read.
_FrameRead? _readFrame(XmlPullReader r) {
  if (r.isEmptyElement) {
    r.skip();
    return null;
  }
  int? id;
  String name = '';
  String? description;
  bool named = false;
  bool chart = false;
  bool graphic = false;
  String? chartId;
  final int depth = r.depth;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType != XmlEventType.startElement) continue;
    final int level = r.depth - depth;
    final String ns = r.namespaceUri;
    final String local = r.localName;
    if (level == 1) {
      if (ns == Ns.xdr && local == 'nvGraphicFramePr' && !named) continue;
      if (ns == Ns.drawingMain && local == 'graphic' && !graphic) {
        graphic = true;
        continue;
      }
      r.skip();
    } else if (level == 2 && ns == Ns.xdr && local == 'cNvPr' && !named) {
      named = true;
      id = int.tryParse(r.getAttribute('id') ?? '');
      name = r.getAttribute('name') ?? '';
      description = r.getAttribute('descr');
      r.skip();
    } else if (level == 2 &&
        ns == Ns.drawingMain &&
        local == 'graphicData' &&
        !chart) {
      chart = r.getAttribute('uri') == drawingChartNamespace;
      if (!chart) r.skip();
    } else if (level == 3 &&
        ns == drawingChartNamespace &&
        local == 'chart' &&
        chartId == null) {
      for (int i = 0; i < r.attributeCount; i++) {
        if (r.attributeNamespace(i) == Ns.rel &&
            r.attributeLocalName(i) == 'id') {
          chartId = r.attributeValue(i);
        }
      }
      r.skip();
    } else {
      r.skip();
    }
  }
  if (!chart) return null;
  return (id: id, name: name, description: description, chartId: chartId);
}

/// Reads the marker [r] is on (`from` or `to`) and consumes it; `null` when
/// `col` or `row` is missing or is not a whole number, or an offset given
/// is not.
XlsxAnchorPoint? _marker(XmlPullReader r) {
  int? column;
  int? row;
  int? offsetX = 0;
  int? offsetY = 0;
  if (!r.isEmptyElement) {
    final int depth = r.depth;
    while (r.next()) {
      if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
      if (r.eventType != XmlEventType.startElement) continue;
      if (r.depth != depth + 1 || r.namespaceUri != Ns.xdr) {
        r.skip();
        continue;
      }
      final String name = r.localName;
      if (name != 'col' &&
          name != 'colOff' &&
          name != 'row' &&
          name != 'rowOff') {
        r.skip();
        continue;
      }
      final int? value = int.tryParse(_text(r).trim());
      switch (name) {
        case 'col':
          column = value;
        case 'row':
          row = value;
        case 'colOff':
          offsetX = value;
        default:
          offsetY = value;
      }
    }
  } else {
    r.skip();
  }
  if (column == null ||
      row == null ||
      offsetX == null ||
      offsetY == null ||
      column < 0 ||
      row < 0) {
    return null;
  }
  return XlsxAnchorPoint(
    row,
    column,
    offsetX: offsetX / emuPerPixel,
    offsetY: offsetY / emuPerPixel,
  );
}

/// The [cellName] (`row` or `col`) and [offsetName] (EMU, as written) of
/// the marker [r] is on, which it consumes; `null` when the cell is missing
/// or either is not a whole number (an offset left out is 0).
({int at, int offset})? _rawMarker(
  XmlPullReader r,
  String cellName,
  String offsetName,
) {
  int? at;
  int? offset = 0;
  if (r.isEmptyElement) {
    r.skip();
    return null;
  }
  final int depth = r.depth;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType != XmlEventType.startElement) continue;
    if (r.depth != depth + 1 || r.namespaceUri != Ns.xdr) {
      r.skip();
      continue;
    }
    final String name = r.localName;
    if (name == cellName) {
      at = int.tryParse(_text(r).trim());
    } else if (name == offsetName) {
      offset = int.tryParse(_text(r).trim());
    } else {
      r.skip();
    }
  }
  if (at == null || at < 0 || offset == null) return null;
  return (at: at, offset: offset);
}

/// The text of the element [r] is on, which it consumes.
String _text(XmlPullReader r) {
  if (r.isEmptyElement) {
    r.skip();
    return '';
  }
  final StringBuffer out = StringBuffer();
  final int depth = r.depth;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType == XmlEventType.characters ||
        r.eventType == XmlEventType.cdata) {
      out.write(r.text);
    } else if (r.eventType == XmlEventType.startElement) {
      r.skip();
    }
  }
  return out.toString();
}
