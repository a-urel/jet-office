/// Pictures: [XlsxPicture] and its anchors ([XlsxOneCellAnchor],
/// [XlsxTwoCellAnchor]), the checks a picture passes when it is added to a
/// sheet, and the drawing part (`xl/drawings/drawing{n}.xml`) that holds a
/// sheet's pictures, with its relationships to the media parts.
///
/// Ported from quds_office_engine `lib/src/sheet/serial/sheet_drawing_io.dart` at commit 15c5d29.
/// Ported from quds_office_engine `lib/src/builders/xlsx_io.dart` at commit 15c5d29.
/// Ported: the anchor and `pic` markup of `SheetDrawingIo._writeAnchor`
/// and `_writePic`, and the picture branch of `XlsxWorkbookBuilder.build`
/// behind `XlsxSheetBuilder.addPicture`. What changed: pictures are value
/// types checked when added (the cell inside the sheet, offsets and sizes
/// finite and positive, the bytes a PNG or a JPEG whose size can be read,
/// see `../common/image.dart`); a picture is anchored to one cell or, new,
/// to two (`twoCellAnchor` with `editAs`); the markup goes through `XmlWriter`
/// (the builder concatenated strings), with the name and description as
/// given; `cNvPr` ids count 2, 3, … per drawing; and a media part is shared
/// by every picture of the workbook that uses the same bytes. Quds defects
/// fixed: the size was in points (12,700 EMU per point), not in pixels at
/// 96 dpi (9,525 EMU per pixel) as Excel inserts a picture; any image not
/// starting `FF D8` was taken for a PNG; media names collided, the
/// builder's `image{drawing}{index}` naming image 11 of drawing 1 and
/// image 1 of drawing 11 both `image111`, and `SheetDrawingIo.syncSheet`
/// numbering media from 1 on every sheet; and `addPicture` took no title
/// or description, so its pictures carried no `descr`.
library;

import '../common/image.dart';
import '../drawingml/picture.dart';
import '../opc/ooxml.dart';
import '../opc/relationships.dart';
import '../xml/xml_escape.dart';
import '../xml/xml_number.dart';
import '../xml/xml_writer.dart';
import 'limits.dart';
import 'range.dart';

export '../drawingml/picture.dart' show emuPerPixel, pixelsToEmu;

/// A corner of a picture: a zero-based cell and an offset into it, in
/// pixels.
///
/// Pixels are at 96 dpi, as Excel inserts a picture at 100 % zoom: one
/// pixel is 9,525 EMU, the unit the file stores. The `const` constructor
/// cannot check anything; the sheet writer does when the picture is added
/// (see `XlsxSheetWriter.picture`).
final class XlsxAnchorPoint {
  /// The cell ([row], [column]), both zero-based, and the offset of the
  /// corner from the cell's top-left corner: [offsetX] pixels right and
  /// [offsetY] pixels down.
  const XlsxAnchorPoint(
    this.row,
    this.column, {
    this.offsetX = 0,
    this.offsetY = 0,
  });

  /// The zero-based row of the cell.
  final int row;

  /// The zero-based column of the cell, A being 0.
  final int column;

  /// How many pixels right of the cell's left edge the corner lies.
  final double offsetX;

  /// How many pixels below the cell's top edge the corner lies.
  final double offsetY;

  @override
  bool operator ==(Object other) =>
      other is XlsxAnchorPoint &&
      other.row == row &&
      other.column == column &&
      other.offsetX == offsetX &&
      other.offsetY == offsetY;

  @override
  int get hashCode => Object.hash(row, column, offsetX, offsetY);

  @override
  String toString() =>
      'XlsxAnchorPoint(row: $row, column: $column, '
      'offsetX: ${describeDouble(offsetX)}, '
      'offsetY: ${describeDouble(offsetY)})';
}

/// Where a picture sits on its sheet: [XlsxOneCellAnchor] or
/// [XlsxTwoCellAnchor].
sealed class XlsxAnchor {
  const XlsxAnchor();

  /// The picture's top-left corner.
  XlsxAnchorPoint get from;
}

/// A picture whose top-left corner sits at [from] and whose size is its
/// own: it moves with the cell but keeps its size when columns or rows
/// change.
///
/// [width] and [height] are in pixels. A size left out comes from the
/// image; with only one given, the other keeps the image's aspect ratio.
final class XlsxOneCellAnchor extends XlsxAnchor {
  /// A picture at [from], [width] by [height] pixels, each `null` for the
  /// size the image's aspect ratio gives (the image's own size when both
  /// are `null`).
  const XlsxOneCellAnchor(this.from, {this.width, this.height});

  @override
  final XlsxAnchorPoint from;

  /// The width in pixels, or `null` for the one the image gives.
  final double? width;

  /// The height in pixels, or `null` for the one the image gives.
  final double? height;

  @override
  bool operator ==(Object other) =>
      other is XlsxOneCellAnchor &&
      other.from == from &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(from, width, height);

  @override
  String toString() =>
      'XlsxOneCellAnchor($from, width: ${_describe(width)}, '
      'height: ${_describe(height)})';
}

/// A picture stretched from the corner [from] to the corner [to], which
/// [resize] lets follow the cells.
final class XlsxTwoCellAnchor extends XlsxAnchor {
  /// A picture from [from] (top-left) to [to] (bottom-right), whose
  /// behaviour when cells move or change size is [resize].
  const XlsxTwoCellAnchor(
    this.from,
    this.to, {
    this.resize = XlsxPictureResize.moveAndSize,
  });

  /// A picture that fills [range]: from the top-left corner of its first
  /// cell to the top-left corner of the cell diagonally after its last,
  /// (`lastRow + 1`, `lastColumn + 1`), both without offset.
  ///
  /// Like the constructor, it checks nothing: a range on the sheet's last
  /// row or column gives a [to] outside the sheet, which the sheet writer
  /// refuses.
  factory XlsxTwoCellAnchor.range(
    XlsxRange range, {
    XlsxPictureResize resize = XlsxPictureResize.moveAndSize,
  }) => XlsxTwoCellAnchor(
    XlsxAnchorPoint(range.firstRow, range.firstColumn),
    XlsxAnchorPoint(range.lastRow + 1, range.lastColumn + 1),
    resize: resize,
  );

  @override
  final XlsxAnchorPoint from;

  /// The picture's bottom-right corner.
  final XlsxAnchorPoint to;

  /// Whether the picture follows the cells it covers.
  final XlsxPictureResize resize;

  @override
  bool operator ==(Object other) =>
      other is XlsxTwoCellAnchor &&
      other.from == from &&
      other.to == to &&
      other.resize == resize;

  @override
  int get hashCode => Object.hash(from, to, resize);

  @override
  String toString() => 'XlsxTwoCellAnchor($from, $to, resize: ${resize.name})';
}

/// How a two-cell picture follows the cells it covers when they move or
/// change size: Excel's "Move and size with cells", "Move but don't size
/// with cells" and "Don't move or size with cells".
enum XlsxPictureResize {
  /// Moves with the cells and stretches with them; Excel's default for a
  /// two-cell anchor (`editAs="twoCell"`, not written).
  moveAndSize,

  /// Moves with the cells but keeps its size (`editAs="oneCell"`).
  move,

  /// Stays where it is, whatever the cells do (`editAs="absolute"`).
  none,
}

/// A picture on a sheet: an [image] placed by its [anchor].
///
/// [name] is what Excel's selection pane shows, `Picture {k}` when `null`,
/// k being the picture's 1-based position among the pictures of its sheet.
/// [description] is its alternative text. Both are a programmer's choice: a
/// character XML forbids is refused. The `const` constructor cannot check
/// anything; the sheet writer does when the picture is added (see
/// `XlsxSheetWriter.picture`).
///
/// ```dart
/// sheet.picture(XlsxPicture(
///   OfficeImage(logoPngBytes),
///   const XlsxOneCellAnchor(XlsxAnchorPoint(0, 3), width: 120),
///   description: 'Company logo',
/// ));
/// ```
final class XlsxPicture {
  /// A picture of [image] at [anchor], named [name] and described by
  /// [description].
  const XlsxPicture(this.image, this.anchor, {this.name, this.description});

  /// The PNG or JPEG the picture shows.
  final OfficeImage image;

  /// Where the picture sits and how large it is.
  final XlsxAnchor anchor;

  /// The picture's name, or `null` for `Picture {k}`.
  final String? name;

  /// The picture's alternative text, or `null` for none.
  final String? description;

  @override
  bool operator ==(Object other) =>
      other is XlsxPicture &&
      other.image == image &&
      other.anchor == anchor &&
      other.name == name &&
      other.description == description;

  @override
  int get hashCode => Object.hash(image, anchor, name, description);

  @override
  String toString() =>
      'XlsxPicture($image, $anchor, name: $name, description: $description)';
}

String _describe(double? value) =>
    value == null ? 'null' : describeDouble(value);

/// A picture as a sheet holds it until the sheet finishes: its image and
/// the format of its bytes, its anchor, the image's own size in pixels,
/// its name (the default filled in) and its description.
typedef WorksheetPicture = ({
  OfficeImage image,
  OfficeImageFormat format,
  XlsxAnchor anchor,
  ({int width, int height}) size,
  String name,
  String? description,
});

/// The largest offset of a picture's corner into its cell, in EMU: the
/// bound of DrawingML's `ST_Coordinate` (ECMA-376 Part 1, an `xsd:long`
/// in `dml-main.xsd`), which `xdr:colOff` and `xdr:rowOff` take. It is
/// about 2,863,311,529 pixels.
const int maxCoordinateEmu = 27273042316900;

/// The largest width or height of a picture, in EMU: 2^31 − 1, the bound
/// the Open XML SDK's Microsoft 365 schemas put on `cx` and `cy` of
/// `xdr:ext` and `a:ext`, well below the `ST_PositiveCoordinate` bound of
/// ECMA-376 ([maxCoordinateEmu]). It is about 225,457 pixels.
const int maxExtentEmu = 2147483647;

/// Checks [picture], the [index]th (1-based) picture of the sheet named
/// [sheet], and returns it as the sheet holds it, its name filled in with
/// `Picture {index}` when it has none.
///
/// Throws [ArgumentError], each message naming the picture and the sheet:
/// - named `image` when its bytes fail [checkImage];
/// - named `from` or `to` for an anchor point whose cell lies outside the
///   sheet;
/// - named `from.offsetX`, `from.offsetY`, `to.offsetX` or `to.offsetY`
///   for an offset that is negative, NaN or infinite, or past
///   [maxCoordinateEmu] in EMU;
/// - named `width` or `height` for a one-cell size that is given but not a
///   finite number above 0, or that, given or kept by the image's aspect,
///   rounds to 0 EMU or past [maxExtentEmu];
/// - named `to` for a two-cell `to` that is not after its `from` on both
///   axes, by cell and then by offset (a picture of no width or height);
/// - named `name` or `description` for text holding a character XML
///   forbids.
WorksheetPicture checkPicture(String sheet, int index, XlsxPicture picture) {
  final String which = 'Picture $index on sheet "$sheet"';
  final OfficeImage image = picture.image;
  final ({int width, int height}) size;
  try {
    size = checkImage(image);
  } on ArgumentError catch (error, stack) {
    Error.throwWithStackTrace(
      ArgumentError.value(
        error.invalidValue,
        'image',
        '$which: ${error.message}',
      ),
      stack,
    );
  }
  final XlsxAnchor anchor = picture.anchor;
  checkAnchor(anchor, size, which);
  final String? name = picture.name;
  final String? description = picture.description;
  _checkText(name, 'name', which);
  _checkText(description, 'description', which);
  return (
    image: image,
    format: image.format!,
    anchor: anchor,
    size: size,
    name: name ?? 'Picture $index',
    description: description,
  );
}

/// Checks [anchor], the place of the picture [which] whose image is [size]
/// pixels, as [checkPicture] does, and returns the size in EMU of a one-cell
/// anchor ([oneCellExtent]), `null` for a two-cell one.
///
/// [size] may be `null` only for an anchor that needs none: a two-cell one,
/// or a one-cell one that gives both its width and its height. Throws
/// [ArgumentError] named as [checkPicture] says.
({int cx, int cy})? checkAnchor(
  XlsxAnchor anchor,
  ({int width, int height})? size,
  String which,
) {
  _checkPoint(anchor.from, 'from', which);
  switch (anchor) {
    case XlsxOneCellAnchor(:final width, :final height):
      _checkSize(width, 'width', which);
      _checkSize(height, 'height', which);
      final ({int cx, int cy}) extent = oneCellExtent(
        anchor,
        size ?? (width: 1, height: 1),
      );
      _checkExtent(extent.cx, 'width', which);
      _checkExtent(extent.cy, 'height', which);
      return extent;
    case XlsxTwoCellAnchor(:final from, :final to):
      _checkPoint(to, 'to', which);
      final bool after =
          _after(to.column, to.offsetX, from.column, from.offsetX) &&
          _after(to.row, to.offsetY, from.row, from.offsetY);
      if (!after) {
        throw ArgumentError.value(
          to,
          'to',
          '$which: the bottom-right corner must lie right of and below the '
              'top-left corner $from, by cell and then by offset.',
        );
      }
      return null;
  }
}

/// Throws unless [point], the anchor point [field] of [which], lies on a
/// cell inside the sheet with offsets [_checkOffset] accepts.
void _checkPoint(XlsxAnchorPoint point, String field, String which) {
  if (point.row < 0 ||
      point.row >= XlsxLimits.maxRows ||
      point.column < 0 ||
      point.column >= XlsxLimits.maxColumns) {
    throw ArgumentError.value(
      point,
      field,
      '$which: the cell of the corner must lie inside the sheet, on a row '
      'within 0..${XlsxLimits.maxRows - 1} and a column within '
      '0..${XlsxLimits.maxColumns - 1}.',
    );
  }
  _checkOffset(point.offsetX, '$field.offsetX', which);
  _checkOffset(point.offsetY, '$field.offsetY', which);
}

/// Throws unless [offset] is finite, not negative and at most
/// [maxCoordinateEmu] once in EMU.
void _checkOffset(double offset, String field, String which) {
  // Pixels are compared before converting: a huge finite offset times
  // [emuPerPixel] overflows to infinity, which cannot be rounded.
  if (!offset.isFinite ||
      offset < 0 ||
      offset > maxCoordinateEmu ||
      pixelsToEmu(offset) > maxCoordinateEmu) {
    throw ArgumentError.value(
      offset,
      field,
      '$which: an offset is a finite number of pixels from 0 to '
      '$maxCoordinateEmu EMU (about 2,863,311,529 pixels).',
    );
  }
}

/// Throws unless [size], when given, is finite and above 0.
void _checkSize(double? size, String field, String which) {
  // Compared in pixels, before [oneCellExtent] converts to EMU: a huge
  // finite size would overflow to infinity there.
  if (size == null || (size.isFinite && size > 0 && size <= maxExtentEmu)) {
    return;
  }
  throw ArgumentError.value(
    size,
    field,
    '$which: a size is a finite number of pixels above 0.',
  );
}

/// Throws unless [emu], a size of the picture rounded to EMU, is within 1
/// and [maxExtentEmu].
void _checkExtent(int emu, String field, String which) {
  if (emu >= 1 && emu <= maxExtentEmu) return;
  throw ArgumentError.value(
    emu,
    field,
    '$which: its $field is $emu EMU once rounded (9,525 EMU per pixel, '
    'the other size following the image\'s aspect); it must be within '
    '1..$maxExtentEmu (about 225,457 pixels).',
  );
}

/// Whether the position at [cell] and [offset] lies after the one at
/// [fromCell] and [fromOffset]: a later cell, or the same cell and a
/// larger offset in EMU.
bool _after(int cell, double offset, int fromCell, double fromOffset) =>
    cell > fromCell ||
    (cell == fromCell && pixelsToEmu(offset) > pixelsToEmu(fromOffset));

/// Throws unless [text], when given, is free of characters XML forbids.
void _checkText(String? text, String field, String which) {
  if (text == null || scrubXmlText(text).removed == 0) return;
  throw ArgumentError.value(
    text,
    field,
    '$which: the $field must not contain characters XML forbids.',
  );
}

/// The size in EMU of a picture of the image [size] (in pixels) at the
/// one-cell [anchor]: each size the anchor gives, and for a size it leaves
/// out the image's own, or, when the other is given, the given one scaled
/// by the image's aspect ratio. Each is rounded to a whole EMU once:
/// `width: 8` on a 4 × 2 image is 76,200 × 38,100 EMU.
({int cx, int cy}) oneCellExtent(
  XlsxOneCellAnchor anchor,
  ({int width, int height}) size,
) {
  final double? width = anchor.width;
  final double? height = anchor.height;
  final double cx = width != null
      ? width * emuPerPixel
      : height != null
      ? height * emuPerPixel * size.width / size.height
      : (size.width * emuPerPixel).toDouble();
  final double cy = height != null
      ? height * emuPerPixel
      : width != null
      ? width * emuPerPixel * size.height / size.width
      : (size.height * emuPerPixel).toDouble();
  return (cx: cx.round(), cy: cy.round());
}

/// Writes the drawing part of a sheet's [pictures], XML declaration
/// included, to [w].
///
/// Picture `i` (from 0) is one anchor ([writeAnchor]), in the order given,
/// with the `cNvPr` id `i + 2`, showing the media whose relationship id is
/// `embedIds[i]`.
void writeDrawing(
  XmlWriter w,
  List<WorksheetPicture> pictures,
  List<String> embedIds,
) {
  w.declaration();
  w.start('xdr:wsDr');
  w.attribute('xmlns:xdr', Ns.xdr);
  w.attribute('xmlns:a', Ns.drawingMain);
  w.attribute('xmlns:r', Ns.rel);
  for (int i = 0; i < pictures.length; i++) {
    writeAnchor(w, pictures[i], id: i + 2, embedId: embedIds[i]);
  }
  w.end();
}

/// Writes the anchor of [picture] to [w]: a `oneCellAnchor` with its `from`
/// and `ext` ([oneCellExtent]), or a `twoCellAnchor` with its `from` and
/// `to` and an `editAs` unless it moves and sizes with its cells. Its `pic`
/// has the `cNvPr` id [id], its name and its description (`descr`), and
/// shows the media of the relationship [embedId]; a one-cell picture's
/// `spPr` repeats its size in `a:xfrm`. Offsets are in EMU ([pixelsToEmu]).
/// The name and description are `xsd:string`, so they take plain XML
/// escaping only, no `escapeXstring`; everything else written is a number or
/// a constant. The prefixes `xdr`, `a` and `r` must be declared above.
void writeAnchor(
  XmlWriter w,
  WorksheetPicture picture, {
  required int id,
  required String embedId,
}) {
  final XlsxAnchor anchor = picture.anchor;
  final ({int cx, int cy})? extent = anchor is XlsxOneCellAnchor
      ? oneCellExtent(anchor, picture.size)
      : null;
  w.start('xdr:${anchorElementName(anchor)}');
  final String? editAs = anchorEditAs(anchor);
  if (editAs != null) w.attribute('editAs', editAs);
  writeAnchorPlace(w, anchor, extent: extent);
  writeDrawingPic(
    w,
    DrawingPic(
      id: id,
      name: picture.name,
      description: picture.description,
      embedId: embedId,
    ),
    prefix: 'xdr',
    extent: extent,
  );
  w.empty('xdr:clientData');
  w.end();
}

/// The local name of the element of [anchor].
String anchorElementName(XlsxAnchor anchor) => switch (anchor) {
  XlsxOneCellAnchor() => 'oneCellAnchor',
  XlsxTwoCellAnchor() => 'twoCellAnchor',
};

/// The `editAs` of [anchor], `null` when none is written: a one-cell anchor
/// has none, and moving and sizing with the cells is a two-cell one's
/// default.
String? anchorEditAs(XlsxAnchor anchor) => switch (anchor) {
  XlsxOneCellAnchor() => null,
  XlsxTwoCellAnchor(:final resize) => switch (resize) {
    XlsxPictureResize.moveAndSize => null,
    XlsxPictureResize.move => 'oneCell',
    XlsxPictureResize.none => 'absolute',
  },
};

/// Writes where [anchor] sits, its elements named with [prefix] (empty for
/// none): its `from`, then its `to` or, for a one-cell anchor, its `ext` of
/// [extent], which such an anchor must be given.
void writeAnchorPlace(
  XmlWriter w,
  XlsxAnchor anchor, {
  ({int cx, int cy})? extent,
  String prefix = 'xdr',
}) {
  final String p = prefix.isEmpty ? '' : '$prefix:';
  _writeMarker(w, p, 'from', anchor.from);
  switch (anchor) {
    case XlsxOneCellAnchor():
      w.empty('${p}ext', <String, String>{
        'cx': '${extent!.cx}',
        'cy': '${extent.cy}',
      });
    case XlsxTwoCellAnchor(:final to):
      _writeMarker(w, p, 'to', to);
  }
}

/// Writes the marker [name] (`from` or `to`) of [point], its elements
/// starting with [p]: its column and column offset, then its row and row
/// offset, in `CT_Marker` order.
void _writeMarker(XmlWriter w, String p, String name, XlsxAnchorPoint point) {
  w.start('$p$name');
  _writeNumber(w, '${p}col', point.column);
  _writeNumber(w, '${p}colOff', pixelsToEmu(point.offsetX));
  _writeNumber(w, '${p}row', point.row);
  _writeNumber(w, '${p}rowOff', pixelsToEmu(point.offsetY));
  w.end();
}

void _writeNumber(XmlWriter w, String name, int value) {
  w.start(name);
  w.text('$value');
  w.end();
}

/// Writes the relationships part of a drawing to [w]: one `image`
/// relationship per media part of [mediaIds] (a part name such as
/// `xl/media/image1.png`, and its relationship id), in its order, with the
/// target relative to `xl/drawings/` (`../media/image1.png`).
void writeDrawingRelationships(XmlWriter w, Map<String, String> mediaIds) {
  final Relationships rels = Relationships();
  mediaIds.forEach((String part, String id) {
    rels.add(RelType.image, '../${part.substring('xl/'.length)}', id: id);
  });
  rels.write(w);
}
