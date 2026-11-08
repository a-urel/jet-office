/// The inline picture of WordprocessingML: the writer of a built one and the
/// reader of what a `w:drawing` that holds one `wp:inline` showing one
/// `pic:pic` states.
///
/// The writer, [writeInlineDrawing], is ported from Quds:
/// `packages/quds_office_engine/lib/src/word/serial/word_drawing_io.dart`
/// (`WordDrawingIo.writeInline` and the inline branch of
/// `_writeAnchorOrInline`), commit `15c5d29`. Changed in the port: it writes
/// the `wp:inline` alone, which the story writer puts in its `w:drawing` and
/// run, not a whole paragraph; the anchored (floating) branch, wrapping,
/// shadow, outline, cropping and the aspect lock switch are left out (plan
/// D5, Ruling 15: a built picture is inline, its aspect locked, its effect
/// extent zero); `descr` is written only when given, not repeated from the
/// name; `pic:cNvPr` repeats the `wp:docPr` id instead of `0`; the `pic:pic`
/// is written by the DrawingML layer both formats share ([writeDrawingPic]);
/// and the `wp`, `a`, `pic` and `r` prefixes are declared where the
/// bindings above do not have them, as Word declares `a` and `pic`.
///
/// The reader is not ported; written for jet_office. [readInlineDrawing]
/// tells a picture from every other drawing (an anchor, a chart, a shape, a
/// group, several objects) so that only a picture is typed (plan D5, Ruling
/// 5). It reads the size, the name and the description the model shows, and
/// the id of the relationship that names the media; the `pic` itself is read
/// by the shared DrawingML layer ([readDrawingPic]).
library;

import '../drawingml/picture.dart';
import '../opc/ooxml.dart' show Ns;
import '../xml/xml_pull_reader.dart';
import '../xml/xml_writer.dart';

/// EMU per point: 914,400 per inch over 72.
const int _emuPerPoint = 12700;

final RegExp _wholeNumber = RegExp(r'^[0-9]{1,15}$');

/// The namespace of `a:`, DrawingML's main one.
const String _drawingMain = Ns.drawingMain;

/// What a built inline picture writes: its `wp:docPr` `id` (which
/// `pic:cNvPr` repeats), `name` and `description`, the id of the
/// relationship of its part that names its media (`embedId`, none when
/// `null`), and its size in EMU, `cx` by `cy`.
typedef BuiltInlineDrawing = ({
  int id,
  String name,
  String? description,
  String? embedId,
  int cx,
  int cy,
});

/// Writes the `wp:inline` of [picture] to [w], as Word writes a picture it
/// inserts: no distance from the text, the size in `wp:extent` and in the
/// picture's `a:xfrm`, a zero effect extent, the aspect locked, and the
/// media's relationship in `a:blip/@r:embed`.
///
/// [declaredAbove] is the prefix to namespace bindings in scope where it is
/// written. `wp` is declared on `wp:inline`, `a` on `a:graphicFrameLocks` and
/// on `a:graphic`, and `pic` and `r` on `pic:pic`, each only when
/// [declaredAbove] does not bind it to its namespace; a prefix bound to
/// another namespace is bound again there. The name and the description take
/// plain XML escaping: the caller has refused characters XML forbids.
void writeInlineDrawing(
  XmlWriter w,
  BuiltInlineDrawing picture, {
  Map<String, String> declaredAbove = const <String, String>{},
}) {
  bool bound(String prefix, String uri) => declaredAbove[prefix] == uri;
  final bool declareA = !bound('a', _drawingMain);
  w.start('wp:inline');
  if (!bound('wp', Ns.wp)) w.attribute('xmlns:wp', Ns.wp);
  w
    ..attribute('distT', '0')
    ..attribute('distB', '0')
    ..attribute('distL', '0')
    ..attribute('distR', '0')
    ..empty('wp:extent', <String, String>{
      'cx': '${picture.cx}',
      'cy': '${picture.cy}',
    })
    ..empty('wp:effectExtent', const <String, String>{
      'l': '0',
      't': '0',
      'r': '0',
      'b': '0',
    })
    ..empty('wp:docPr', <String, String>{
      'id': '${picture.id}',
      'name': picture.name,
      if (picture.description != null) 'descr': picture.description!,
    })
    ..start('wp:cNvGraphicFramePr')
    ..empty('a:graphicFrameLocks', <String, String>{
      if (declareA) 'xmlns:a': _drawingMain,
      'noChangeAspect': '1',
    })
    ..end()
    ..start('a:graphic');
  if (declareA) w.attribute('xmlns:a', _drawingMain);
  w
    ..start('a:graphicData')
    ..attribute('uri', drawingPictureNamespace);
  writeDrawingPic(
    w,
    DrawingPic(
      id: picture.id,
      name: picture.name,
      description: picture.description,
      embedId: picture.embedId,
    ),
    prefix: 'pic',
    extent: (cx: picture.cx, cy: picture.cy),
    namespaces: <String, String>{
      if (!bound('pic', drawingPictureNamespace))
        'pic': drawingPictureNamespace,
      if (!bound('r', Ns.rel)) 'r': Ns.rel,
    },
  );
  w
    ..end()
    ..end()
    ..end();
}

/// What an inline picture states.
typedef InlineDrawing = ({
  double? widthPt,
  double? heightPt,
  String name,
  String? description,
  String? embedId,
});

/// Reads the `w:drawing` [r] is on, or `null` when it is not an inline
/// picture: it must have exactly one element child, a `wp:inline` with
/// exactly one `a:graphic`, which holds exactly one `a:graphicData`, with
/// exactly one element child, a `pic:pic` whose `cNvPr` has a whole number
/// `id`.
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
  int graphics = 0;
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
    } else if (r.localName == 'graphic' && r.namespaceUri == Ns.drawingMain) {
      // A second graphic is not one picture: the drawing stays opaque.
      if (++graphics == 1 && !r.isEmptyElement) pic = _readGraphic(r);
    }
    r.skip();
  }
  if (pic == null || graphics != 1) return null;
  return (
    widthPt: widthPt,
    heightPt: heightPt,
    name: name ?? '',
    description: description,
    embedId: pic.embedId,
  );
}

/// The `pic` of the `a:graphic` [r] is on, when it holds one
/// `a:graphicData` and that holds the `pic` and nothing else; [r] is left on
/// the graphic's end.
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
        ++data == 1 &&
        !r.isEmptyElement) {
      pic = _readGraphicData(r);
    }
    r.skip();
  }
  return data == 1 ? pic : null;
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
