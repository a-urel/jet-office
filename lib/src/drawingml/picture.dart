/// The DrawingML picture (`pic`) that spreadsheet and word processing
/// drawings share: its identity read from any prefix, and the element written
/// as phase 1 writes it.
///
/// Not ported from Quds; written for jet_office. The `pic` markup is the one
/// the XLSX writer's `_writePic` ported from quds_office_engine
/// `lib/src/sheet/serial/sheet_drawing_io.dart` at commit 15c5d29 wrote
/// (see `../xlsx/drawing.dart`), now prefix-generic.
///
/// This layer imports `opc`, `xml` and `common` only, never `xlsx` or `docx`,
/// so DOCX can use it (decision 0014).
library;

import '../opc/ooxml.dart';
import '../xml/xml_pull_reader.dart';
import '../xml/xml_writer.dart';

/// EMU (English Metric Units) per pixel at 96 dpi, as Excel inserts a
/// picture at 100 % zoom: 914,400 EMU per inch ÷ 96 (Decision 4 of the M4
/// plan). The image's own resolution (`pHYs`, the JFIF density) is
/// ignored.
const int emuPerPixel = 9525;

/// [pixels] in EMU, rounded to a whole EMU (half away from zero).
int pixelsToEmu(double pixels) => (pixels * emuPerPixel).round();

/// The picture namespace (`pic:`), the one a word processing drawing's `pic`
/// is in; a spreadsheet drawing's is [Ns.xdr].
const String drawingPictureNamespace =
    'http://schemas.openxmlformats.org/drawingml/2006/picture';

/// The identity of a `pic` element (`CT_Picture`): its `cNvPr` and the
/// relationships its `blip` names.
final class DrawingPic {
  /// A picture [id] called [name], described by [description], showing the
  /// media of relationship [embedId] or, linked, the one of [linkId].
  const DrawingPic({
    required this.id,
    required this.name,
    this.description,
    this.embedId,
    this.linkId,
  });

  /// The `id` of `cNvPr`.
  final int id;

  /// The `name` of `cNvPr`, empty when it has none.
  final String name;

  /// The `descr` of `cNvPr`, or `null`.
  final String? description;

  /// The `r:embed` of the `blip`, or `null`.
  final String? embedId;

  /// The `r:link` of the `blip`, or `null`.
  final String? linkId;
}

bool _isPictureNamespace(String uri) =>
    uri == Ns.xdr || uri == drawingPictureNamespace;

/// Reads the `pic` the current event of [r] starts, in the spreadsheet or the
/// picture namespace and any prefix, and consumes it: afterwards [r] is on
/// the element's end event.
///
/// The first `cNvPr` of the first `nvPicPr` and the first `blip` of the
/// `blipFill` are read. Returns `null` when `cNvPr` is missing or has no
/// `id` that is a whole number; [r] is past the element either way. Throws
/// [StateError] when [r] is not on a start element.
DrawingPic? readDrawingPic(XmlPullReader r) {
  if (r.eventType != XmlEventType.startElement) {
    throw StateError('readDrawingPic needs a start element.');
  }
  int? id;
  String name = '';
  String? description;
  String? embedId;
  String? linkId;
  bool named = false;
  bool blipped = false;
  if (!r.isEmptyElement) {
    final int depth = r.depth;
    while (r.next()) {
      if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
      if (r.eventType != XmlEventType.startElement) continue;
      final bool child = r.depth == depth + 1;
      if (child &&
          r.localName == 'nvPicPr' &&
          _isPictureNamespace(r.namespaceUri) &&
          !named) {
        named = true;
        final int own = r.depth;
        while (r.next()) {
          if (r.eventType == XmlEventType.endElement && r.depth < own) break;
          if (r.eventType != XmlEventType.startElement) continue;
          if (r.depth == own + 1 &&
              r.localName == 'cNvPr' &&
              _isPictureNamespace(r.namespaceUri) &&
              id == null) {
            id = int.tryParse(r.getAttribute('id') ?? '');
            name = r.getAttribute('name') ?? '';
            description = r.getAttribute('descr');
          }
          r.skip();
        }
      } else if (child &&
          r.localName == 'blipFill' &&
          _isPictureNamespace(r.namespaceUri) &&
          !blipped) {
        blipped = true;
        final int own = r.depth;
        while (r.next()) {
          if (r.eventType == XmlEventType.endElement && r.depth < own) break;
          if (r.eventType != XmlEventType.startElement) continue;
          if (r.depth == own + 1 &&
              r.localName == 'blip' &&
              r.namespaceUri == Ns.drawingMain) {
            embedId = r.getAttribute('embed', namespaceUri: Ns.rel);
            linkId = r.getAttribute('link', namespaceUri: Ns.rel);
          }
          r.skip();
        }
      } else {
        r.skip();
      }
    }
  } else {
    r.skip();
  }
  if (id == null) return null;
  return DrawingPic(
    id: id,
    name: name,
    description: description,
    embedId: embedId,
    linkId: linkId,
  );
}

/// Writes the `pic` of [pic] to [w], its elements named with [prefix]
/// (`xdr` for a spreadsheet drawing, `pic` for a word processing one); the
/// `a:` and `r:` prefixes must be declared above.
///
/// It shows the media [DrawingPic.embedId] names, and the one of
/// [DrawingPic.linkId] as `r:link` when given. [extent], given for a picture
/// that is not sized by its anchor, goes into `a:xfrm`. The name and the
/// description take plain XML escaping only.
void writeDrawingPic(
  XmlWriter w,
  DrawingPic pic, {
  required String prefix,
  ({int cx, int cy})? extent,
}) {
  w.start('$prefix:pic');
  w.start('$prefix:nvPicPr');
  w.start('$prefix:cNvPr');
  w.attribute('id', '${pic.id}');
  w.attribute('name', pic.name);
  final String? description = pic.description;
  if (description != null) w.attribute('descr', description);
  w.end();
  w.start('$prefix:cNvPicPr');
  w.empty('a:picLocks', const <String, String>{'noChangeAspect': '1'});
  w.end();
  w.end();
  w.start('$prefix:blipFill');
  w.empty('a:blip', <String, String>{
    if (pic.embedId != null) 'r:embed': pic.embedId!,
    if (pic.linkId != null) 'r:link': pic.linkId!,
  });
  w.start('a:stretch');
  w.empty('a:fillRect');
  w.end();
  w.end();
  w.start('$prefix:spPr');
  if (extent != null) {
    w.start('a:xfrm');
    w.empty('a:off', const <String, String>{'x': '0', 'y': '0'});
    w.empty('a:ext', <String, String>{
      'cx': '${extent.cx}',
      'cy': '${extent.cy}',
    });
    w.end();
  }
  w.start('a:prstGeom');
  w.attribute('prst', 'rect');
  w.empty('a:avLst');
  w.end();
  w.end();
  w.end();
}
