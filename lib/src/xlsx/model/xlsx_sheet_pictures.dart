/// The pictures of an [XlsxSheet]: the members that read, add, move and
/// remove them.
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
/// package. An edit changes the drawing's list in place, one entry per
/// recorded change, and creates and drops the drawing and media parts; the
/// changes keep [_PicturesRead] and the media index true, an undo included.
part of 'xlsx_sheet.dart';

/// What the sheet read of its pictures: the drawing part and where it is,
/// and the media parts its relationships name, by relationship id. The
/// changes of an edit keep it up to date.
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

  /// The names of the parts the package writes from the typed drawing, for
  /// `attachStoredPart`.
  final Set<String> attached = <String>{};
}

/// The change of which drawing part holds the sheet's pictures.
final class _DrawingPartChange implements Change {
  _DrawingPartChange(this.read, this.after, this.afterName)
    : before = read.part,
      beforeName = read.partName;

  final _PicturesRead read;
  final DrawingPart? before;
  final String? beforeName;
  final DrawingPart? after;
  final String? afterName;

  @override
  void revert() => read
    ..part = before
    ..partName = beforeName;

  @override
  void reapply() => read
    ..part = after
    ..partName = afterName;
}

/// The change of one entry of a drawing at [index]: a `null` [before] is an
/// insertion, a `null` [after] a removal.
final class _DrawingEntryChange implements Change {
  _DrawingEntryChange(this.part, this.index, this.before, this.after);

  final DrawingPart part;
  final int index;
  final DrawingEntry? before;
  final DrawingEntry? after;

  @override
  void revert() => _swap(after, before);

  @override
  void reapply() => _swap(before, after);

  void _swap(DrawingEntry? from, DrawingEntry? to) {
    if (to == null) {
      part.entries.removeAt(index);
    } else if (from == null) {
      part.entries.insert(index, to);
    } else {
      part.entries[index] = to;
    }
  }
}

/// The change of the media part the relationship [id] of the drawing names:
/// [before] gave way to [after], either `null` for none.
final class _DrawingMediaChange implements Change {
  _DrawingMediaChange(this.read, this.id, this.before, this.after);

  final _PicturesRead read;
  final String id;
  final String? before;
  final String? after;

  @override
  void revert() => _set(before);

  @override
  void reapply() => _set(after);

  void _set(String? name) {
    if (name == null) {
      read.media.remove(id);
    } else {
      read.media[id] = name;
    }
  }
}

/// The change of what the media index knows of the part [name]: [before]
/// gave way to [after], `null` for a part it does not hold.
final class _MediaIndexChange implements Change {
  _MediaIndexChange(this.index, this.name, this.before, this.after);

  final DrawingMediaIndex index;
  final String name;
  final OfficeImage? before;
  final OfficeImage? after;

  @override
  void revert() => _set(before);

  @override
  void reapply() => _set(after);

  void _set(OfficeImage? image) {
    if (image == null) {
      index.forget(name);
    } else {
      index.add(name, image);
    }
  }
}

/// The picture half of [XlsxSheet].
mixin _SheetPictures {
  // What the sheet gives its picture half.
  SheetHost get _host;
  String get name;
  String? get _partName;
  int get _partNumber;
  WorksheetPart? _load();
  WorksheetPart _editablePart(String what);
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
    for (final int at in _listed(read)) {
      final DrawingEntry e = drawing.entries[at];
      final DrawingPic pic = e.pic!;
      final String media = read.media[pic.embedId]!;
      final OfficeImage image = reader.guardXml(
        media,
        () => _host.mediaIndex.imageOf(media),
      );
      found.add(
        XlsxPicture(
          image,
          e.anchor!,
          name: pic.name,
          description: pic.description,
        ),
      );
    }
    return List<XlsxPicture>.unmodifiable(found);
  }

  /// Adds [picture] after everything the sheet's drawing holds, creating the
  /// drawing when the sheet has none.
  ///
  /// It is checked as `XlsxSheetWriter.picture` checks it, and a picture
  /// without a name takes `Picture {k}`, k being its position in [pictures]
  /// from 1. Its `cNvPr` id is one above the highest of the drawing, at least
  /// 2. The image shares a media part that holds the same bytes, and the
  /// drawing's relationship to it; otherwise it gets a part of its own,
  /// `xl/media/image{n}`, its extension declared as a default content type.
  ///
  /// Throws an [ArgumentError] for a bad picture, as the writer does; a
  /// [StateError] for a sheet that is not a worksheet or has no part, and for
  /// a `<drawing>` whose part is missing or is not a spreadsheet drawing; and
  /// an [XlsxReadException] when the sheet, its relationships, the drawing or
  /// a media part cannot be read. Whatever it throws, nothing has changed.
  void addPicture(XlsxPicture picture) =>
      _recordSheetEdit(this, XlsxChangeKind.featureChanged, () {
        final WorksheetPart part = _editablePart('pictures');
        final _PicturesRead read = _editablePictures(part);
        final WorksheetPicture checked = checkPicture(
          name,
          _listed(read).length + 1,
          picture,
        );
        final PackageReader reader = _host.reader;
        final String? shared = reader.guardXml(
          reader.workbookPart,
          () => _host.mediaIndex.partFor(checked.image),
        );
        _host.log.transaction(() {
          final DrawingPart drawing = read.part ?? _addDrawing(part, read);
          final String media = shared ?? _addMedia(checked);
          final String embedId = _mediaRelationship(read, media);
          _attach(read, drawing);
          applyChange(
            _host.log,
            _DrawingEntryChange(
              drawing,
              drawing.entries.length,
              null,
              DrawingEntry.rendered(
                checked,
                id: drawing.nextId,
                embedId: embedId,
              ),
            ),
          );
        });
      });

  /// Moves the picture at [index] of [pictures] to [anchor], which may be of
  /// the other kind.
  ///
  /// The anchor element takes the new markers, `ext` and `editAs`; its `pic`,
  /// its `clientData` and its other attributes stay as written. A one-cell
  /// size left `null` is the image's, as for the writer. An [anchor] equal to
  /// the picture's is no edit.
  ///
  /// Throws a [RangeError] for an [index] outside [pictures]; an
  /// [ArgumentError] for a bad anchor, as the writer does, or named `anchor`
  /// for a size left to an image the library cannot size (a GIF, an EMF); a
  /// [StateError] for a sheet that is not a worksheet or has no part, and for
  /// a `<drawing>` whose part is missing or is not a spreadsheet drawing; and
  /// an [XlsxReadException] when the sheet, its relationships, the drawing or
  /// the media part cannot be read. Whatever it throws, nothing has changed.
  void movePicture(int index, XlsxAnchor anchor) => _recordSheetEdit(
    this,
    XlsxChangeKind.featureChanged,
    () {
      final WorksheetPart part = _editablePart('pictures');
      final _PicturesRead read = _editablePictures(part);
      final List<int> listed = _listed(read);
      RangeError.checkValidIndex(index, listed, 'index');
      final DrawingPart drawing = read.part!;
      final int at = listed[index];
      final DrawingEntry entry = drawing.entries[at];
      if (entry.anchor == anchor) return;
      final String which = 'Picture ${index + 1} on sheet "$name"';
      final ({int cx, int cy})? extent = checkAnchor(
        anchor,
        _sizeFor(anchor, read.media[entry.pic!.embedId]!, which),
        which,
      );
      final XlsxAnchor placed = anchor is XlsxOneCellAnchor
          ? XlsxOneCellAnchor(
              anchor.from,
              width: extent!.cx / emuPerPixel,
              height: extent.cy / emuPerPixel,
            )
          : anchor;
      if (entry.anchor == placed) return;
      final PackageReader reader = _host.reader;
      final String drawingName = read.partName!;
      final DrawingEntry moved = reader.guardXml(
        drawingName,
        () => entry.movedTo(anchor, extent),
      );
      _host.log.transaction(() {
        _attach(read, drawing);
        applyChange(_host.log, _DrawingEntryChange(drawing, at, entry, moved));
      });
    },
  );

  /// Removes the picture at [index] of [pictures].
  ///
  /// The relationships the picture names go when no other entry of the
  /// drawing, whatever its kind, names them; a media part goes when no
  /// relationship of the package, an unloaded sheet's included, targets it,
  /// and so does any other part they targeted (the `hdphoto` of a picture). A
  /// drawing left with no entry goes with the sheet's relationship to it and
  /// `<drawing>`, unless something else still targets it. The default content
  /// type of an extension stays, so a later picture may use it.
  ///
  /// Throws a [RangeError] for an [index] outside [pictures]; a [StateError]
  /// for a sheet that is not a worksheet or has no part, and for a
  /// `<drawing>` whose part is missing or is not a spreadsheet drawing; and
  /// an [XlsxReadException] when the sheet, the drawing or any relationships
  /// of the package cannot be read. Whatever it throws, nothing has changed.
  void removePicture(int index) =>
      _recordSheetEdit(this, XlsxChangeKind.featureChanged, () {
        final WorksheetPart part = _editablePart('pictures');
        final _PicturesRead read = _editablePictures(part);
        final List<int> listed = _listed(read);
        RangeError.checkValidIndex(index, listed, 'index');
        final DrawingPart drawing = read.part!;
        final int at = listed[index];
        final DrawingEntry entry = drawing.entries[at];
        final PackageReader reader = _host.reader;
        final String drawingName = read.partName!;
        final Set<String> unused = reader.guardXml(drawingName, () {
          final Set<String> ids = <String>{...entry.relationshipIds};
          for (final DrawingEntry other in drawing.entries) {
            if (!identical(other, entry)) ids.removeAll(other.relationshipIds);
          }
          return ids;
        });
        final Map<String, String> targets = _relationshipTargets(drawingName);
        final ChangeLog log = _host.log;
        log.transaction(() {
          _attach(read, drawing);
          applyChange(log, _DrawingEntryChange(drawing, at, entry, null));
          for (final String id in unused) {
            removeStoredRelationship(log, reader.package, drawingName, id);
            final String? media = read.media[id];
            if (media != null) {
              applyChange(log, _DrawingMediaChange(read, id, media, null));
            }
            final String? target = targets[id];
            if (target != null) _dropTarget(target);
          }
          if (drawing.entries.isEmpty) _dropDrawing(part, read);
        });
      });

  /// The size in pixels of the image of the part [media] when [anchor] leaves
  /// a size to it, else `null`.
  ({int width, int height})? _sizeFor(
    XlsxAnchor anchor,
    String media,
    String which,
  ) {
    if (anchor is! XlsxOneCellAnchor ||
        (anchor.width != null && anchor.height != null)) {
      return null;
    }
    final PackageReader reader = _host.reader;
    final OfficeImage image = reader.guardXml(
      media,
      () => _host.mediaIndex.imageOf(media),
    );
    try {
      return checkImage(image);
    } on ArgumentError catch (error, stack) {
      Error.throwWithStackTrace(
        ArgumentError.value(
          anchor,
          'anchor',
          '$which: the library cannot read the size of its image; give both '
              'the width and the height. ${error.message}',
        ),
        stack,
      );
    }
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

  /// Where the pictures listed in [pictures] are among the drawing's entries.
  List<int> _listed(_PicturesRead read) {
    final List<DrawingEntry> entries =
        read.part?.entries ?? const <DrawingEntry>[];
    return <int>[
      for (int at = 0; at < entries.length; at++)
        if (entries[at].anchor != null &&
            read.media.containsKey(entries[at].pic?.embedId))
          at,
    ];
  }

  /// The pictures read, to edit them. Throws a [StateError] for a `<drawing>`
  /// the model has no typed part for.
  _PicturesRead _editablePictures(WorksheetPart part) {
    final _PicturesRead read = _readPictures();
    if (read.part == null && part.layoutElement('drawing') != null) {
      throw StateError(
        'The drawing of sheet "$name" is missing or is not a spreadsheet '
        'drawing; its pictures cannot be set.',
      );
    }
    return read;
  }

  /// Adds a drawing part, the sheet's relationship to it and `<drawing>`.
  DrawingPart _addDrawing(WorksheetPart part, _PicturesRead read) {
    final ChangeLog log = _host.log;
    final OpcPackage package = _host.reader.package;
    final DrawingPart drawing = DrawingPart.empty();
    final String added = addStoredPart(
      log,
      package,
      '/${drawingPartName(_partNumber)}',
      ContentType.drawing,
      drawing,
    );
    final String id = addStoredRelationship(
      log,
      package,
      _partName!,
      type: RelType.drawing,
      target: relationshipTarget(_partName, added),
    );
    final OpaqueXml element = renderElements((XmlWriter w) {
      w.empty('drawing', <String, String>{'r:id': id});
    }).single;
    editLayout(
      log,
      part,
      'drawing',
      () => part.swapLayout('drawing', null, element),
    );
    markStoredPart(log, read.attached, added.substring(1));
    applyChange(log, _DrawingPartChange(read, drawing, added.substring(1)));
    return drawing;
  }

  /// Adds a media part for the image of [picture] and returns its name, with
  /// no leading `/`.
  String _addMedia(WorksheetPicture picture) {
    final ChangeLog log = _host.log;
    final DrawingMediaIndex index = _host.mediaIndex;
    final OfficeImage image = picture.image;
    final OfficeImageFormat format = picture.format;
    final String media = addStoredPart(
      log,
      _host.reader.package,
      '/${mediaPartName(index.nextNumber(), format.extension)}',
      format.contentType,
      DrawingMediaContent(image.bytes),
      byExtension: true,
    ).substring(1);
    applyChange(log, _MediaIndexChange(index, media, null, image));
    return media;
  }

  /// Makes [drawing], the part [_PicturesRead.partName] of [read], what the
  /// package writes for that part.
  void _attach(_PicturesRead read, DrawingPart drawing) => attachStoredPart(
    _host.log,
    _host.reader.package,
    read.attached,
    read.partName!,
    drawing,
  );

  /// The parts the internal relationships of [source] target, by id.
  Map<String, String> _relationshipTargets(String source) {
    final PackageReader reader = _host.reader;
    return <String, String>{
      for (final PartRelationship rel in reader.relationshipsOf(source))
        if (reader.hasPart(rel.target)) rel.id: rel.target,
    };
  }

  /// Takes the part [target], the target of a relationship just removed, out
  /// of the package unless a relationship still points at it or it left
  /// already. The media index keeps its image, so an undo finds it again by
  /// its bytes.
  void _dropTarget(String target) {
    final PackageReader reader = _host.reader;
    if (!reader.hasPart(target)) return;
    final DrawingMediaIndex index = _host.mediaIndex;
    final OfficeImage? image = reader.guardXml(
      target,
      () => reader.package.isReferenced(target) ? null : index.imageOf(target),
    );
    if (image == null) return;
    removeStoredPart(_host.log, reader.package, target);
    applyChange(_host.log, _MediaIndexChange(index, target, image, null));
  }

  /// Removes the sheet's `<drawing>` and its relationship, and the drawing
  /// part, with the parts only it still relates to, unless something else
  /// points at the part.
  void _dropDrawing(WorksheetPart part, _PicturesRead read) {
    final ChangeLog log = _host.log;
    final PackageReader reader = _host.reader;
    final OpcPackage package = reader.package;
    final String drawingName = read.partName!;
    final String? id = part.drawingId;
    if (id != null) {
      removeStoredRelationship(log, package, _partName!, id);
    }
    removeLayout(log, part, 'drawing');
    final Iterable<String> left = _relationshipTargets(drawingName).values;
    <String, String>{...read.media}.forEach((String id, String media) {
      applyChange(log, _DrawingMediaChange(read, id, media, null));
    });
    final bool used = reader.guardXml(
      drawingName,
      () => package.isReferenced(drawingName),
    );
    if (!used) {
      removeStoredPart(log, package, drawingName);
      left.forEach(_dropTarget);
    }
    applyChange(log, _DrawingPartChange(read, null, null));
  }

  /// The id of the drawing's relationship to the part [media], added when it
  /// has none.
  ///
  /// A relationship whose id holds a character XML cannot write (a `&#xFFFE;`
  /// read from the file) is not shared: the new picture's `r:embed` could not
  /// name it, so a relationship of its own is added.
  String _mediaRelationship(_PicturesRead read, String media) {
    for (final MapEntry<String, String> e in read.media.entries) {
      if (_sameMedia(e.value, media) && scrubXmlText(e.key).removed == 0) {
        return e.key;
      }
    }
    final String source = '/${read.partName!}';
    final String id = addStoredRelationship(
      _host.log,
      _host.reader.package,
      source,
      type: RelType.image,
      target: relationshipTarget(source, '/$media'),
      id: _freeRelationshipId(read),
    );
    applyChange(_host.log, _DrawingMediaChange(read, id, null, media));
    return id;
  }

  /// The lowest `rId<n>` the drawing has no relationship of and no entry
  /// names, so a dangling name stays dangling.
  String _freeRelationshipId(_PicturesRead read) {
    final PackageReader reader = _host.reader;
    final String drawingName = read.partName!;
    return reader.guardXml(drawingName, () {
      final Set<String> taken = <String>{
        for (final OpcRelationship r in reader.package.relationshipsOf(
          drawingName,
        ))
          r.id,
        for (final DrawingEntry e in read.part!.entries) ...e.relationshipIds,
      };
      int n = 1;
      while (taken.contains('rId$n')) {
        n++;
      }
      return 'rId$n';
    });
  }

  static bool _sameMedia(String a, String b) =>
      a.toLowerCase() == b.toLowerCase();
}

/// The `drawings` holder of a sheet: on a row or column edit of the sheet
/// every anchor of its drawing part moves as Excel moves it
/// ([DrawingEntry.shiftedBy]): pictures, shapes, charts and groups alike, a
/// picture whose cells are all deleted kept at zero size; an insert that
/// would push an anchor off the sheet throws a [StateError] before any
/// change. An anchor inside `mc:AlternateContent` moves as a bare one; one
/// whose branches hold anything else stays and the drawing part is warned
/// about (`referenceNotShifted`). A sheet rename or move changes no anchor.
/// A drawing the model cannot type is left as written.
final class _DrawingHolder implements ReferenceHolder {
  _DrawingHolder(this._sheet);

  final XlsxSheet _sheet;

  @override
  String get holderName => 'drawings';

  @override
  void shiftReferences(ReferenceMapper mapper, ReferenceShift? edit) {
    if (edit == null || !_editsSheet(edit, _sheet.name)) return;
    final _PicturesRead read = _sheet._readPictures();
    final DrawingPart? drawing = read.part;
    if (drawing == null) return;
    final PackageReader reader = _sheet._host.reader;
    final ChangeLog log = _sheet._host.log;
    final String partName = read.partName!;
    bool notShifted = false;
    // Every move, and so every refusal, before any change.
    final List<DrawingEntry?> moves = <DrawingEntry?>[
      for (final DrawingEntry entry in drawing.entries)
        reader.guardXml(
          partName,
          () => entry.shiftedBy(
            edit,
            onNotShifted: (String _) => notShifted = true,
          ),
        ),
    ];
    if (notShifted) {
      final String name =
          reader.package.canonicalPartName(partName) ?? partName;
      _sheet._host.references.warnPart(
        name.startsWith('/') ? name.substring(1) : name,
      );
    }
    log.transaction(() {
      for (int at = 0; at < moves.length; at++) {
        final DrawingEntry entry = drawing.entries[at];
        final DrawingEntry? moved = moves[at];
        if (moved == null) continue;
        _sheet._attach(read, drawing);
        applyChange(log, _DrawingEntryChange(drawing, at, entry, moved));
      }
    });
  }
}
