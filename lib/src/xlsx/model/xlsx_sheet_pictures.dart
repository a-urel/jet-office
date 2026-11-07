/// The pictures of an [XlsxSheet]: the member that reads them.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `xlsx_sheet.dart`, kept apart only to keep that file readable:
/// [XlsxSheet] mixes [_SheetPictures] in, so these are members of the sheet.
///
/// A picture is an anchor of the sheet's drawing part ([DrawingPart]) that
/// directly holds a `pic` showing a media part. The model types the anchors
/// and keeps the drawing as written, with whatever else it holds (charts,
/// shapes, groups). Reading adds nothing to the package's content: the
/// drawing is saved from the original bytes until an edit gives it to the
/// package.
part of 'xlsx_sheet.dart';

/// What the sheet read of its pictures: the drawing part and where it is,
/// and the media parts its relationships name, by relationship id.
final class _PicturesRead {
  _PicturesRead(this.partName, this.part, this.media);

  /// The drawing part's name without a leading `/`, or `null` for none.
  String? partName;

  /// The typed drawing, `null` when there is none or it cannot be typed (it
  /// is not a spreadsheet drawing).
  DrawingPart? part;

  /// The names (no leading `/`) of the existing media parts the drawing's
  /// image relationships point at, by relationship id.
  final Map<String, String> media;
}

/// The picture half of [XlsxSheet].
mixin _SheetPictures {
  // What the sheet gives its picture half.
  SheetHost get _host;
  String? get _partName;
  WorksheetPart? _load();
  Set<String> get _featureReported;
  void _warn(XlsxWarningCode code, String? cell, {String? detail});

  /// The pictures read on first use; `null` until then.
  _PicturesRead? _picturesRead;

  /// The pictures of the sheet in file order, each with the image its media
  /// part holds.
  ///
  /// A picture is a `oneCellAnchor` or `twoCellAnchor` that directly holds a
  /// `pic` whose `r:embed` names a relationship to a part of the file. Sizes
  /// and offsets are in pixels (9,525 EMU each). A picture in a format the
  /// library does not write (GIF, EMF) is listed; its `OfficeImage.format`
  /// reads `null`. Every other kind of object (a chart, a shape, a group, an
  /// absolute anchor, a picture inside `mc:AlternateContent`, a picture
  /// linked instead of embedded) is kept as written and not listed, without a
  /// warning. A picture the model cannot read (a dangling `r:embed`, a marker
  /// or size that is not a number, a `cNvPr` without an id) is kept, not
  /// listed and reported once as `featureEntryInvalid` with the detail
  /// `pic`; a drawing part that is not a spreadsheet drawing reads no
  /// pictures and is reported with the detail `drawing`. Pictures that show
  /// the same media part share one `Uint8List`, across sheets too.
  ///
  /// Unmodifiable. Loads the sheet. Throws an [XlsxReadException] when the
  /// sheet, its relationships, the drawing part or a media part cannot be
  /// read, and, when the drawing holds more objects than
  /// `XlsxReadLimits.maxMerges` allows, `limitExceeded`.
  List<XlsxPicture> get pictures {
    final _PicturesRead read = _readPictures();
    final DrawingPart? drawing = read.part;
    if (drawing == null) return const <XlsxPicture>[];
    final PackageReader reader = _host.reader;
    final List<XlsxPicture> found = <XlsxPicture>[];
    for (final DrawingEntry e in drawing.entries) {
      final XlsxAnchor? anchor = e.anchor;
      final DrawingPic? pic = e.pic;
      final String? media = pic == null ? null : read.media[pic.embedId];
      if (anchor == null || pic == null || media == null) continue;
      final OfficeImage image = reader.guardXml(
        media,
        () => _host.mediaIndex.imageOf(media),
      );
      found.add(
        XlsxPicture(
          image,
          anchor,
          name: pic.name,
          description: pic.description,
        ),
      );
    }
    return List<XlsxPicture>.unmodifiable(found);
  }

  /// The drawing and its media, read once.
  _PicturesRead _readPictures() {
    final _PicturesRead? cached = _picturesRead;
    if (cached != null) return cached;
    final WorksheetPart? part = _load();
    final String? sheetName = _partName;
    final String? drawingId = part?.drawingId;
    if (part == null || sheetName == null || drawingId == null) {
      return _picturesRead = _PicturesRead(null, null, <String, String>{});
    }
    final PackageReader reader = _host.reader;
    String? drawingName;
    for (final PartRelationship rel in reader.relationshipsOf(
      sheetName.substring(1),
    )) {
      if (rel.id == drawingId &&
          rel.type == RelType.drawing &&
          reader.hasPart(rel.target)) {
        drawingName = rel.target;
        break;
      }
    }
    if (drawingName == null) {
      return _picturesRead = _PicturesRead(null, null, <String, String>{});
    }
    // Problems are kept only once the part has read, so a read that throws
    // and is retried does not report them twice.
    final List<String> problems = <String>[];
    final String name = drawingName;
    final DrawingPart? drawing = reader.guardXml(
      name,
      () => DrawingPart.read(
        reader.openXml(name),
        warn: problems.add,
        limits: reader.limits,
        part: name,
      ),
    );
    if (drawing == null) problems.add('drawing');
    final Map<String, String> media = <String, String>{
      for (final PartRelationship rel in reader.relationshipsOf(name))
        if (rel.type == RelType.image && reader.hasPart(rel.target))
          rel.id: rel.target,
    };
    for (final DrawingEntry e in drawing?.entries ?? const <DrawingEntry>[]) {
      final String? embed = e.pic?.embedId;
      if (embed != null && !media.containsKey(embed)) problems.add('pic');
    }
    for (final String detail in problems) {
      if (_featureReported.add(detail)) {
        _warn(XlsxWarningCode.featureEntryInvalid, null, detail: detail);
      }
    }
    return _picturesRead = _PicturesRead(name, drawing, media);
  }
}
