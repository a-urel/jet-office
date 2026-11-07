/// A drawing part (`xl/drawings/drawingN.xml`): the anchors of a sheet's
/// pictures and of whatever else sits on it, each kept as written.
///
/// Not ported from Quds; written for jet_office.
///
/// The part is read, not rewritten: every anchor keeps its source
/// ([OpaqueXml]), so a chart, a shape, a group or a picture nobody edits is
/// written back character for character. A `oneCellAnchor` or `twoCellAnchor`
/// that directly holds a picture showing embedded media also keeps its typed
/// [XlsxAnchor] and [DrawingPic]; every other child of the root is an entry
/// without a value. An edit changes [DrawingPart.entries], a mutable list, and
/// [DrawingPart.encode] writes the part from it; the `cNvPr` ids the part
/// uses are in [DrawingPart.ids], so a new picture takes a free one.
library;

import 'dart:typed_data';

import '../../drawingml/picture.dart';
import '../../opc/ooxml.dart';
import '../../opc/opaque_xml.dart';
import '../../opc/package.dart';
import '../../xml/utf8_buffer.dart';
import '../../xml/xml_pull_reader.dart';
import '../../xml/xml_writer.dart';
import '../drawing.dart';
import '../read/read_limits.dart';
import 'comments_part.dart' show WarnFn;
import 'item_group.dart' show checkListRoom, readerOf;

/// One child of a drawing's root: the element as written and, for a picture
/// the model lists, where it sits and what it is.
final class DrawingEntry {
  /// An entry kept as [source]; [anchor] and [pic] are `null` for an element
  /// that is no picture the model reads.
  DrawingEntry({required this.source, this.anchor, this.pic});

  /// The element as written.
  OpaqueXml source;

  /// Where the picture sits, or `null`.
  XlsxAnchor? anchor;

  /// The picture's identity and the relationship of its media, or `null`.
  DrawingPic? pic;
}

/// A drawing part with its anchors kept as written and its pictures typed.
final class DrawingPart implements PartContent {
  DrawingPart._(this.root, this.entries, this.ids);

  /// A new part without anchors, as the writer starts one.
  factory DrawingPart.empty() => DrawingPart._(
    const XmlRoot.of('xdr:wsDr', <String, String>{
      'xdr': Ns.xdr,
      'a': Ns.drawingMain,
      'r': Ns.rel,
    }),
    <DrawingEntry>[],
    <int>{},
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
  /// and reported to [warn] as `pic`. The `id` of every `cNvPr` of the part
  /// goes into [ids].
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
    final Set<int> ids = <int>{};
    while (r.next()) {
      if (r.eventType != XmlEventType.startElement) continue;
      if (r.depth == 1) {
        if (r.localName != 'wsDr' || r.namespaceUri != Ns.xdr) return null;
        root = XmlRoot.capture(r);
        continue;
      }
      if (r.depth != 2) continue;
      checkListRoom(entries.length, limits, part);
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
      entries.add(_entry(source, warn));
    }
    if (root == null) return null;
    return DrawingPart._(root, entries, ids);
  }

  /// The start tag of the root, kept as written.
  final XmlRoot root;

  /// Every child of the root, in file order, listed or not.
  final List<DrawingEntry> entries;

  /// The `id` of every `cNvPr` the part holds, of any kind of object.
  final Set<int> ids;

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

DrawingEntry _entry(OpaqueXml source, WarnFn warn) {
  if (source.namespaceUri != Ns.xdr ||
      (source.localName != 'oneCellAnchor' &&
          source.localName != 'twoCellAnchor')) {
    return DrawingEntry(source: source);
  }
  final ({XlsxAnchor anchor, DrawingPic pic})? typed = _typed(source, warn);
  return typed == null
      ? DrawingEntry(source: source)
      : DrawingEntry(source: source, anchor: typed.anchor, pic: typed.pic);
}

/// The anchor and picture of [source], an anchor element, or `null` when it
/// holds no picture the model reads; a picture that is broken is reported.
({XlsxAnchor anchor, DrawingPic pic})? _typed(OpaqueXml source, WarnFn warn) {
  final XmlPullReader r = readerOf(source);
  final bool two = source.localName == 'twoCellAnchor';
  final String? editAs = r.getAttribute('editAs');
  XlsxAnchorPoint? from;
  XlsxAnchorPoint? to;
  ({int cx, int cy})? ext;
  DrawingPic? pic;
  bool hasPic = false;
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
      default:
        r.skip();
    }
  }
  if (!hasPic) return null;
  final DrawingPic? found = pic;
  if (found != null && found.embedId == null) {
    // A linked picture is not an error; a picture of nothing is.
    if (found.linkId != null) return null;
    broken = true;
  }
  if (found == null ||
      broken ||
      from == null ||
      (two ? to == null : ext == null)) {
    warn('pic');
    return null;
  }
  final XlsxAnchor anchor = two
      ? XlsxTwoCellAnchor(
          from,
          to!,
          resize: switch (editAs) {
            'oneCell' => XlsxPictureResize.move,
            'absolute' => XlsxPictureResize.none,
            _ => XlsxPictureResize.moveAndSize,
          },
        )
      : XlsxOneCellAnchor(
          from,
          width: ext!.cx / emuPerPixel,
          height: ext.cy / emuPerPixel,
        );
  return (anchor: anchor, pic: found);
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
