/// [DocxPicture]: an inline picture, `w:drawing` holding one `wp:inline`.
///
/// Not ported from Quds; written for jet_office. It is a part of the run
/// content's library because [DocxRunContent] is sealed.
///
/// A picture read from a file keeps its element and is written as read, so
/// nothing of it changes in the part (plan D5, Ruling 5); the model reads its
/// size, name, description and image and does not edit them. It is removed
/// with its run.
///
/// A picture the API builds (`DocxParagraph.addPicture`, Ruling 6) holds its
/// image, its size and what it was given; [checkedPicture] checks them before
/// anything changes. What a file needs beyond that (the media part, the image
/// relationship of the part the picture is in, the `wp:docPr` id and the
/// default name) is not in the model: each save gives it and takes it back
/// once the file is written (Rulings 7 and A), so a built picture works in
/// any part of any document.
part of 'run_content.dart';

/// An inline picture: a `w:drawing` that holds one `wp:inline` showing one
/// `pic:pic`. An anchored (floating) picture, a chart, a shape and a group
/// are [DocxOpaqueRunContent].
///
/// Its text is empty. A picture read from a file is written as read; one
/// built with `DocxParagraph.addPicture` is written by each save, with the
/// media part, relationship and id that save gives it.
final class DocxPicture extends DocxRunContent {
  DocxPicture._read(
    OpaqueXml this._xml,
    this.widthPt,
    this.heightPt,
    this.name,
    this.description,
    this._embedId,
    this._resolveImage,
  ) : _built = null,
      _givenName = null,
      super(const <KeptAttribute>[]);

  DocxPicture._built(
    OfficeImage this._built,
    double this.widthPt,
    double this.heightPt,
    String? name,
    this.description,
  ) : _xml = null,
      _embedId = null,
      _resolveImage = null,
      _givenName = name,
      name = name ?? '',
      super(const <KeptAttribute>[]);

  /// The element read; `null` for a built picture.
  final OpaqueXml? _xml;
  final String? _embedId;
  final OfficeImage? Function(String id)? _resolveImage;

  /// The image a built picture shows; `null` for one read.
  final OfficeImage? _built;

  /// The name the API gave a built picture, `null` for none.
  final String? _givenName;

  /// The width in points (`wp:extent`'s `cx`, 12,700 EMU to the point), or
  /// `null` when it is missing or not a non-negative whole number.
  final double? widthPt;

  /// The height in points (`wp:extent`'s `cy`), or `null` as [widthPt].
  final double? heightPt;

  /// The picture's name (`wp:docPr`'s `name`), empty when it has none. A
  /// picture built without a name reads empty, and each save names it
  /// `Picture <id>` after the `wp:docPr` id that save gives it.
  final String name;

  /// The picture's description, its alternative text (`wp:docPr`'s `descr`),
  /// or `null`.
  final String? description;

  /// The image the picture shows: the media part its `r:embed` names in the
  /// relationships of the part the picture was read from, found on the first
  /// read and kept; `null` when it has no `r:embed` (a linked picture has an
  /// `r:link`), when the relationship is missing, external or not of the
  /// image type, when its target is no part of the file or cannot be read,
  /// and when the part's relationships cannot be read.
  ///
  /// The format is the signature's ([OfficeImage.format]): `null` for a GIF
  /// or EMF, which are given all the same. Pictures that show one media part
  /// share one [OfficeImage]. A story's relationships are peeked, never
  /// marked for rewriting, so reading this changes no part's bytes at save.
  ///
  /// A built picture gives the image it was built with.
  late final OfficeImage? image = _findImage();

  OfficeImage? _findImage() {
    final OfficeImage? built = _built;
    if (built != null) return built;
    final String? id = _embedId;
    final OfficeImage? Function(String)? resolve = _resolveImage;
    if (id == null || resolve == null) return null;
    return resolve(id);
  }

  @override
  String toString() => 'DocxPicture($name)';
}

/// A picture read from the `w:drawing` [xml] captured: [widthPt], [heightPt],
/// [name] and [description] as `readInlineDrawing` found them, [embedId] the
/// `r:embed` of its blip and [resolveImage] the image a relationship id of
/// its part names, or `null` when the part has no relationships to ask.
DocxPicture readPicture(
  OpaqueXml xml, {
  required double? widthPt,
  required double? heightPt,
  required String name,
  required String? description,
  required String? embedId,
  required OfficeImage? Function(String id)? resolveImage,
}) => DocxPicture._read(
  xml,
  widthPt,
  heightPt,
  name,
  description,
  embedId,
  resolveImage,
);

/// The element [picture] keeps, for the writer; `null` for a built picture.
OpaqueXml? pictureXml(DocxPicture picture) => picture._xml;

/// The image a built [picture] shows, or `null` for one read.
OfficeImage? builtPictureImage(DocxPicture picture) => picture._built;

/// The name the API gave a built [picture], `null` for none (each save gives
/// it `Picture <id>`) and for one read.
String? builtPictureName(DocxPicture picture) => picture._givenName;

/// The largest side of a built picture, in points: 22 inches, Word's bound.
const double maxPictureSidePt = 1584;

/// A new picture of [image], as `DocxParagraph.addPicture` builds it, sized
/// and checked as that says: [checkImage] first ([ArgumentError] for an
/// image that is not PNG or JPEG), then the size, then [name] and
/// [description]. It throws before anything is built.
DocxPicture checkedPicture(
  OfficeImage image, {
  double? widthPt,
  double? heightPt,
  String? name,
  String? description,
}) {
  final ({int width, int height}) pixels = checkImage(image);
  final double width;
  final double height;
  if (widthPt != null && heightPt != null) {
    width = _checkSide(widthPt, 'widthPt');
    height = _checkSide(heightPt, 'heightPt');
  } else if (widthPt != null) {
    width = _checkSide(widthPt, 'widthPt');
    height = _checkSide(width * pixels.height / pixels.width, 'heightPt');
  } else if (heightPt != null) {
    height = _checkSide(heightPt, 'heightPt');
    width = _checkSide(height * pixels.width / pixels.height, 'widthPt');
  } else {
    // 96 pixels to the inch: 0.75 pt each.
    width = _checkSide(pixels.width * 0.75, 'widthPt');
    height = _checkSide(pixels.height * 0.75, 'heightPt');
  }
  _checkText(name, 'name');
  _checkText(description, 'description');
  return DocxPicture._built(image, width, height, name, description);
}

/// [side], when it is finite, above 0 and at most [maxPictureSidePt]; a
/// [RangeError] naming [which] otherwise.
double _checkSide(double side, String which) {
  if (!side.isFinite || side <= 0 || side > maxPictureSidePt) {
    throw RangeError.value(
      side,
      which,
      'must be finite, above 0 and at most $maxPictureSidePt points',
    );
  }
  return side;
}

/// Throws [ArgumentError] naming [which] when [text] holds a character XML
/// forbids.
void _checkText(String? text, String which) {
  if (text != null && scrubXmlText(text).removed > 0) {
    throw ArgumentError.value(
      text,
      which,
      'must not hold a character XML forbids',
    );
  }
}
