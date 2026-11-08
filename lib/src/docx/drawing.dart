/// The reader of an inline picture: what a `w:drawing` that holds one
/// `wp:inline` showing one `pic:pic` states.
///
/// Not ported from Quds; written for jet_office. The writer of a built
/// picture joins it here (task 8).
///
/// [readInlineDrawing] tells a picture from every other drawing (an anchor, a
/// chart, a shape, a group, several objects) so that only a picture is typed
/// (plan D5, Ruling 5). It reads the size, the name and the description the
/// model shows, and the id of the relationship that names the media; the
/// `pic` itself is read by the DrawingML layer both formats share
/// ([readDrawingPic]).
library;

import '../drawingml/picture.dart';
import '../opc/ooxml.dart' show Ns;
import '../xml/xml_pull_reader.dart';

/// EMU per point: 914,400 per inch over 72.
const int _emuPerPoint = 12700;

final RegExp _wholeNumber = RegExp(r'^[0-9]{1,15}$');

/// What an inline picture states.
typedef InlineDrawing = ({
  double? widthPt,
  double? heightPt,
  String name,
  String? description,
  String? embedId,
});

/// Reads the `w:drawing` [r] is on, or `null` when it is not an inline
/// picture: it must have exactly one element child, a `wp:inline` whose
/// `a:graphic` holds an `a:graphicData` with exactly one element child, a
/// `pic:pic` whose `cNvPr` has a whole number `id`.
///
/// The size is `wp:extent`'s `cx` and `cy` in points, each `null` when it is
/// not a non-negative whole number of EMU or the element is missing; the
/// name is `wp:docPr`'s `name` (empty when absent) and the description its
/// `descr`. `embedId` is the `r:embed` of the picture's blip,
/// `null` for none (a linked picture has an `r:link` and none). Throws
/// nothing for what the file holds; [r] must be on a start element and is
/// consumed to the element's end, or past what it read.
InlineDrawing? readInlineDrawing(XmlPullReader r) {
  if (r.eventType != XmlEventType.startElement || r.isEmptyElement) {
    return null;
  }
  final int depth = r.depth;
  int children = 0;
  InlineDrawing? found;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType != XmlEventType.startElement) continue;
    if (r.depth != depth + 1) {
      r.skip();
      continue;
    }
    children++;
    if (children == 1 &&
        r.localName == 'inline' &&
        r.namespaceUri == Ns.wp &&
        !r.isEmptyElement) {
      found = _readInline(r);
    } else {
      r.skip();
    }
  }
  return children == 1 ? found : null;
}

InlineDrawing? _readInline(XmlPullReader r) {
  final int depth = r.depth;
  double? widthPt;
  double? heightPt;
  bool extent = false;
  String? name;
  String? description;
  DrawingPic? pic;
  bool graphic = false;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType != XmlEventType.startElement) continue;
    if (r.depth != depth + 1) {
      r.skip();
      continue;
    }
    if (r.localName == 'extent' && r.namespaceUri == Ns.wp && !extent) {
      extent = true;
      widthPt = _points(r.getAttribute('cx'));
      heightPt = _points(r.getAttribute('cy'));
    } else if (r.localName == 'docPr' && r.namespaceUri == Ns.wp) {
      name ??= r.getAttribute('name') ?? '';
      description ??= r.getAttribute('descr');
    } else if (r.localName == 'graphic' &&
        r.namespaceUri == Ns.drawingMain &&
        !graphic &&
        !r.isEmptyElement) {
      graphic = true;
      pic = _readGraphic(r);
    }
    r.skip();
  }
  if (pic == null) return null;
  return (
    widthPt: widthPt,
    heightPt: heightPt,
    name: name ?? '',
    description: description,
    embedId: pic.embedId,
  );
}

/// The `pic` of the `a:graphic` [r] is on, when its `a:graphicData` holds
/// that and nothing else; [r] is left on the graphic's end.
DrawingPic? _readGraphic(XmlPullReader r) {
  final int depth = r.depth;
  DrawingPic? pic;
  int data = 0;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType != XmlEventType.startElement) continue;
    if (r.depth == depth + 1 &&
        r.localName == 'graphicData' &&
        r.namespaceUri == Ns.drawingMain &&
        data == 0 &&
        !r.isEmptyElement) {
      data++;
      pic = _readGraphicData(r);
    }
    r.skip();
  }
  return pic;
}

DrawingPic? _readGraphicData(XmlPullReader r) {
  final int depth = r.depth;
  int children = 0;
  DrawingPic? pic;
  while (r.next()) {
    if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
    if (r.eventType != XmlEventType.startElement) continue;
    if (r.depth != depth + 1) {
      r.skip();
      continue;
    }
    children++;
    if (children == 1 &&
        r.localName == 'pic' &&
        r.namespaceUri == drawingPictureNamespace) {
      pic = readDrawingPic(r);
    } else {
      r.skip();
    }
  }
  return children == 1 ? pic : null;
}

double? _points(String? emu) {
  if (emu == null || !_wholeNumber.hasMatch(emu)) return null;
  return int.parse(emu) / _emuPerPoint;
}
