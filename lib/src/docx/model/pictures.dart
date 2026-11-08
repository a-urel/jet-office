/// [DocxPicture]: an inline picture, `w:drawing` holding one `wp:inline`.
///
/// Not ported from Quds; written for jet_office. It is a part of the run
/// content's library because [DocxRunContent] is sealed.
///
/// A picture read from a file keeps its element and is written as read, so
/// nothing of it changes in the part (plan D5, Ruling 5); the model reads its
/// size, name, description and image and does not edit them. It is removed
/// with its run.
part of 'run_content.dart';

/// An inline picture: a `w:drawing` that holds one `wp:inline` showing one
/// `pic:pic`. An anchored (floating) picture, a chart, a shape and a group
/// are [DocxOpaqueRunContent].
///
/// Its text is empty. A picture read from a file is written as read.
final class DocxPicture extends DocxRunContent {
  DocxPicture._read(
    this._xml,
    this.widthPt,
    this.heightPt,
    this.name,
    this.description,
    this._embedId,
    this._resolveImage,
  ) : super(const <KeptAttribute>[]);

  final OpaqueXml _xml;
  final String? _embedId;
  final OfficeImage? Function(String id)? _resolveImage;

  /// The width in points (`wp:extent`'s `cx`, 12,700 EMU to the point), or
  /// `null` when it is missing or not a non-negative whole number.
  final double? widthPt;

  /// The height in points (`wp:extent`'s `cy`), or `null` as [widthPt].
  final double? heightPt;

  /// The picture's name (`wp:docPr`'s `name`), empty when it has none.
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
  late final OfficeImage? image = _findImage();

  OfficeImage? _findImage() {
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

/// The element [picture] keeps, for the writer.
OpaqueXml pictureXml(DocxPicture picture) => picture._xml;
