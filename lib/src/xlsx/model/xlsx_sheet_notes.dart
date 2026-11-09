/// The notes of an [XlsxSheet]: the members that read, set and remove them.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `xlsx_sheet.dart`, kept apart only to keep that file readable:
/// [XlsxSheet] mixes [_SheetNotes] in, so these are members of the sheet.
///
/// A note is a `<comment>` of the sheet's comments part, with the box Excel
/// draws for it in a VML drawing part. The model types both parts
/// ([CommentsPart], [VmlPart]) and keeps what it does not understand as
/// written. Reading adds nothing to the package's content: the parts are
/// saved from the original bytes until an edit gives them to the package.
/// An edit changes the parts' lists in place, one entry per recorded change,
/// so generating many notes copies no list; the changes keep [_NotesRead]
/// true, an undo included.
part of 'xlsx_sheet.dart';

/// The parts of a sheet's notes: `commentsName` and `vmlName` have no leading
/// `/` and are `null` for none; `comments` and `vml` are the typed parts,
/// `null` when there is none or when it cannot be typed (a comments part that
/// is not SpreadsheetML, VML that is not well formed).
typedef _NoteParts = ({
  String? commentsName,
  CommentsPart? comments,
  String? vmlName,
  VmlPart? vml,
});

/// What the sheet read of its notes: the two parts, where they are, and the
/// notes by cell. The changes of an edit keep it up to date.
final class _NotesRead {
  _NotesRead(this.parts);

  /// The sheet's two parts.
  _NoteParts parts;

  /// The names of the parts the package writes from the typed parts, for
  /// `attachStoredPart`.
  final Set<String> attached = <String>{};

  /// The listed entries by `row * maxColumns + column`.
  final Map<int, CommentEntry> index = <int, CommentEntry>{};

  /// The cells, by the same key, whose box is shown all the time.
  final Set<int> shown = <int>{};

  /// The note of [entry], which is on a cell.
  XlsxCellNote noteOf(CommentEntry entry) {
    final int row = entry.row!;
    final int column = entry.column!;
    return (
      row: row,
      column: column,
      note: XlsxNote(
        entry.text,
        author: entry.author,
        visible: shown.contains(row * XlsxLimits.maxColumns + column),
      ),
    );
  }

  /// Takes [entry] out of [index]; an entry on no cell is not there.
  void forget(CommentEntry entry) {
    final int? key = _keyOf(entry.row, entry.column);
    if (key != null) index.remove(key);
  }

  /// Puts [entry] in [index]; an entry on no cell stays out.
  void remember(CommentEntry entry) {
    final int? key = _keyOf(entry.row, entry.column);
    if (key != null) index[key] = entry;
  }

  /// Adds the cell of [shape] to [shown], or takes it out, when it is the box
  /// of a visible note.
  void markShown(VmlShape shape, {required bool shown}) {
    final int? key = _keyOf(shape.row, shape.column);
    if (key == null || !shape.isNote || !shape.visible) return;
    if (shown) {
      this.shown.add(key);
    } else {
      this.shown.remove(key);
    }
  }

  static int? _keyOf(int? row, int? column) => row == null || column == null
      ? null
      : row * XlsxLimits.maxColumns + column;
}

/// The change of which parts the sheet's notes live in.
final class _NotePartsChange implements Change {
  _NotePartsChange(this.read, this.before, this.after);

  final _NotesRead read;
  final _NoteParts before;
  final _NoteParts after;

  @override
  void revert() => read.parts = before;

  @override
  void reapply() => read.parts = after;
}

/// The change of one entry of a comments part at [index]: a `null` [before]
/// is an insertion and a `null` [after] a removal.
final class _CommentChange implements Change {
  _CommentChange(this.read, this.part, this.index, this.before, this.after);

  final _NotesRead read;
  final CommentsPart part;
  final int index;
  final CommentEntry? before;
  final CommentEntry? after;

  @override
  void revert() => _swap(after, before);

  @override
  void reapply() => _swap(before, after);

  void _swap(CommentEntry? from, CommentEntry? to) {
    if (from != null) read.forget(from);
    if (to == null) {
      part.entries.removeAt(index);
      return;
    }
    if (from == null) {
      part.entries.insert(index, to);
    } else {
      part.entries[index] = to;
    }
    read.remember(to);
  }
}

/// The change of one author appended to a comments part.
final class _AuthorChange implements Change {
  _AuthorChange(this.part, this.author);

  final CommentsPart part;
  final String author;

  @override
  void revert() => part.authors.removeLast();

  @override
  void reapply() => part.authors.add(author);
}

/// The change of one shape of a VML part at [index]: a `null` [before] is an
/// insertion and a `null` [after] a removal.
final class _ShapeChange implements Change {
  _ShapeChange(this.read, this.part, this.index, this.before, this.after);

  final _NotesRead read;
  final VmlPart part;
  final int index;
  final VmlShape? before;
  final VmlShape? after;

  @override
  void revert() => _swap(after, before);

  @override
  void reapply() => _swap(before, after);

  void _swap(VmlShape? from, VmlShape? to) {
    part.swapShape(index, from, to);
    if (from != null) read.markShown(from, shown: false);
    if (to != null) read.markShown(to, shown: true);
  }
}

/// The change of what surrounds the shapes of a VML part.
final class _VmlFrameChange implements Change {
  _VmlFrameChange(this.part, this.before, this.after);

  final VmlPart part;
  final VmlFrame before;
  final VmlFrame after;

  @override
  void revert() => part.frame = before;

  @override
  void reapply() => part.frame = after;
}

/// The note half of [XlsxSheet].
mixin _SheetNotes {
  // What the sheet gives its note half.
  SheetHost get _host;
  String get name;
  String? get _partName;
  WorksheetPart? _load();
  WorksheetPart _editablePart(String what);
  Set<String> get _featureReported;
  void _warn(XlsxWarningCode code, String? cell, {String? detail});
  List<OpcRelationship> _readRelationships();

  /// The notes read on first use; `null` until then.
  _NotesRead? _notesRead;

  /// The notes of the sheet in file order, each with its cell.
  ///
  /// A `<comment>` whose `ref` cannot be read, or that repeats a cell, is
  /// left out, kept as written and reported once as `featureEntryInvalid`
  /// with the detail `comment`; so is a bad `authorId`, which reads an empty
  /// author. A note is [XlsxNote.visible] when the VML shape on its row and
  /// column has `<x:Visible/>`; VML that is not well formed reads every note
  /// as hidden and is reported once, with the detail `legacyDrawing`. A
  /// comments part that is not SpreadsheetML reads no notes and is reported.
  /// Unmodifiable. Loads the sheet. Throws an [XlsxReadException] when the
  /// sheet, its relationships or the comments part cannot be read, and,
  /// when the part holds more comments than `XlsxReadLimits.maxMerges`
  /// allows, `limitExceeded`.
  List<XlsxCellNote> get notes {
    final _NotesRead read = _readNotes();
    return List<XlsxCellNote>.unmodifiable(<XlsxCellNote>[
      for (final CommentEntry e
          in read.parts.comments?.entries ?? const <CommentEntry>[])
        if (e.row != null) read.noteOf(e),
    ]);
  }

  /// The note of the cell at [row] and [column], or `null` for a cell
  /// without one, with the reading of [notes]. Throws a [RangeError] outside
  /// Excel's grid.
  XlsxNote? noteAt(int row, int column) {
    RangeError.checkValueInInterval(row, 0, XlsxLimits.maxRows - 1, 'row');
    RangeError.checkValueInInterval(
      column,
      0,
      XlsxLimits.maxColumns - 1,
      'column',
    );
    final _NotesRead read = _readNotes();
    final CommentEntry? entry =
        read.index[row * XlsxLimits.maxColumns + column];
    return entry == null ? null : read.noteOf(entry).note;
  }

  /// Puts [note] on the cell at [row] and [column], replacing the note it
  /// has; `null` removes the note. A note equal to the cell's [noteAt] is no
  /// edit, and throws nothing for a note the writer would refuse or repair
  /// or for the note of a threaded comment.
  ///
  /// The checks and repairs are the sheet writer's (`XlsxSheetWriter.note`):
  /// characters XML forbids are removed from the text and text past 32,767
  /// UTF-16 code units is cut, with the warnings `invalidCharactersRemoved`
  /// and `textTruncated` at the cell. A replaced note keeps its other
  /// attributes and its box; [XlsxNote.visible] shows or hides the box. A new
  /// note goes before the first on a later cell, and a new box after the last
  /// shape. The first note of a sheet creates the comments part and, unless
  /// the sheet has one, the VML drawing; a VML drawing that holds form
  /// controls takes the boxes beside them. When the comments have no VML
  /// drawing, one is made with a box for every note.
  ///
  /// Removing the last note removes the comments part; the VML drawing and
  /// the sheet's `<legacyDrawing>` go too unless the drawing still holds
  /// something.
  ///
  /// A note whose text and author equal the cell's, with another
  /// visibility, changes the box alone: the comments part stays as written.
  ///
  /// Throws an [ArgumentError] for a bad note, as `XlsxSheetWriter.note`
  /// does, and one named `author` for a new note on a cell without one whose
  /// author starts `tc=` (it would be a thread's placeholder with no thread),
  /// and a [RangeError] for a cell outside Excel's grid when [note] is
  /// `null`; a [StateError] for the note of a threaded comment (its author
  /// starts `tc=`: the thread would lose it), for a sheet that is not a
  /// worksheet or has no part, for a comments part that is not SpreadsheetML
  /// and for VML that is not well formed; and an [XlsxReadException] when
  /// the sheet, its relationships or the note parts cannot be read. Whatever
  /// it throws, nothing has changed.
  void setNote(int row, int column, XlsxNote? note) {
    if (note == null) {
      XlsxSheet._checkCell(row, column);
    } else {
      try {
        checkNote(name, row, column, note);
      } on ArgumentError catch (error) {
        // A file may hold a note the writer refuses: set back, it is no edit.
        if (error.name == 'row' ||
            error.name == 'column' ||
            noteAt(row, column) != note) {
          rethrow;
        }
        return;
      }
    }
    final WorksheetPart part = _editablePart('notes');
    final _NotesRead read = _readNotes();
    final CommentEntry? entry =
        read.index[row * XlsxLimits.maxColumns + column];
    final String ref = cellRef(row, column);
    final XlsxNote? current = entry == null ? null : read.noteOf(entry).note;
    if (note == current) return;
    if (entry != null && entry.author.startsWith('tc=')) {
      throw StateError(
        'The note on cell $ref on sheet "$name" belongs to a threaded '
        'comment; it cannot be set or removed.',
      );
    }
    if (note != null && entry == null && note.author.startsWith('tc=')) {
      throw ArgumentError.value(
        note.author,
        'author',
        'An author that starts with "tc=" belongs to a threaded comment, '
            'whose note this model does not create.',
      );
    }
    final List<XlsxWarningCode> repairs = <XlsxWarningCode>[];
    final WorksheetNote? wanted = note == null
        ? null
        : cleanNote(row, column, note, repairs.add);
    final XlsxNote? next = wanted == null
        ? null
        : XlsxNote(wanted.text, author: wanted.author, visible: wanted.visible);
    if (current != next) {
      final _NoteParts parts = read.parts;
      if (parts.commentsName != null && parts.comments == null) {
        throw StateError(
          'The comments part of sheet "$name" is not SpreadsheetML; its notes '
          'cannot be set.',
        );
      }
      if (parts.vmlName != null && parts.vml == null) {
        throw StateError(
          'The VML drawing of sheet "$name" is not well formed; its notes '
          'cannot be set.',
        );
      }
      final WorksheetNote? value = wanted;
      _host.log.transaction(() {
        if (value == null) {
          _removeNote(part, read, entry!);
        } else {
          _putNote(part, read, value, entry);
        }
      });
    }
    for (final XlsxWarningCode code in repairs) {
      _warn(code, ref);
    }
  }

  /// Gives the cell of [note] that note, in the comments and the VML drawing,
  /// creating them when the sheet has none. [entry] is the one replaced.
  /// Must run inside a transaction of the workbook's change log.
  void _putNote(
    WorksheetPart part,
    _NotesRead read,
    WorksheetNote note,
    CommentEntry? entry,
  ) {
    final ChangeLog log = _host.log;
    final VmlPart vml = read.parts.vml ?? _addVml(part, read);
    // Only the box changes when the text and the author are what the note
    // holds: the comment is left as written, with the runs' fonts the model
    // does not type (Excel's `<color indexed="81"/>`).
    final XlsxNote? held = entry == null ? null : read.noteOf(entry).note;
    final bool sameComment =
        held != null && held.text == note.text && held.author == note.author;
    final CommentsPart comments = read.parts.comments ?? _addComments(read);
    final OpcPackage package = _host.reader.package;
    if (!sameComment) {
      attachStoredPart(
        log,
        package,
        read.attached,
        read.parts.commentsName!,
        comments,
      );
    }
    attachStoredPart(log, package, read.attached, read.parts.vmlName!, vml);
    if (!sameComment) {
      int authorId = comments.authors.indexOf(note.author);
      if (authorId < 0) {
        authorId = comments.authors.length;
        applyChange(log, _AuthorChange(comments, note.author));
      }
      applyChange(
        log,
        entry == null
            ? _CommentChange(
                read,
                comments,
                comments.insertionIndex(note.row, note.column),
                null,
                CommentEntry.of(note, authorId),
              )
            : _CommentChange(
                read,
                comments,
                comments.entries.indexOf(entry),
                entry,
                entry.replacedBy(note, authorId),
              ),
      );
    }
    final List<int> boxes = vml.noteShapes(note.row, note.column);
    if (boxes.isEmpty) _addShape(read, vml, note);
    for (final int at in boxes) {
      final VmlShape shape = vml.shapes[at];
      if (shape.visible == note.visible) continue;
      applyChange(
        log,
        _ShapeChange(
          read,
          vml,
          at,
          shape,
          vml.withVisible(shape, note.visible),
        ),
      );
    }
  }

  /// Takes the note of [entry] out of the comments and the VML drawing,
  /// removing what that leaves empty. Must run inside a transaction of the
  /// workbook's change log.
  void _removeNote(WorksheetPart part, _NotesRead read, CommentEntry entry) {
    final OpcPackage package = _host.reader.package;
    final CommentsPart comments = read.parts.comments!;
    attachStoredPart(
      _host.log,
      package,
      read.attached,
      read.parts.commentsName!,
      comments,
    );
    applyChange(
      _host.log,
      _CommentChange(
        read,
        comments,
        comments.entries.indexOf(entry),
        entry,
        null,
      ),
    );
    VmlPart? vml = read.parts.vml;
    if (vml != null) {
      attachStoredPart(
        _host.log,
        package,
        read.attached,
        read.parts.vmlName!,
        vml,
      );
      final List<int> boxes = vml.noteShapes(entry.row!, entry.column!);
      for (final int at in boxes.reversed) {
        _removeShape(read, vml, at);
      }
    } else if (read.index.isNotEmpty) {
      vml = _addVml(part, read);
    }
    if (comments.entries.isNotEmpty) return;
    _dropComments(read);
    if (vml != null && vml.shapes.isEmpty && !vml.holdsOther) {
      _dropVml(part, read);
    }
  }

  /// Adds a box for [note] after the last shape of [vml].
  void _addShape(_NotesRead read, VmlPart vml, WorksheetNote note) {
    final ChangeLog log = _host.log;
    final VmlPlan plan = vml.plan(note, _host.takeVmlBlock);
    if (!identical(plan.frame, vml.frame)) {
      applyChange(log, _VmlFrameChange(vml, vml.frame, plan.frame));
    }
    applyChange(
      log,
      _ShapeChange(read, vml, vml.shapes.length, null, plan.shape),
    );
  }

  /// Removes the shape at [at] of [vml]. The text after it, which may hold
  /// other elements, goes to the shape before it, or to the head.
  void _removeShape(_NotesRead read, VmlPart vml, int at) {
    final ChangeLog log = _host.log;
    final VmlShape shape = vml.shapes[at];
    if (shape.after.isNotEmpty) {
      if (at == 0) {
        applyChange(
          log,
          _VmlFrameChange(
            vml,
            vml.frame,
            vml.frame.withHeadEnding(shape.after),
          ),
        );
      } else {
        final VmlShape previous = vml.shapes[at - 1];
        applyChange(
          log,
          _ShapeChange(
            read,
            vml,
            at - 1,
            previous,
            previous.withAfter('${previous.after}${shape.after}'),
          ),
        );
      }
    }
    applyChange(log, _ShapeChange(read, vml, at, shape, null));
  }

  /// The number of the sheet's own part (`sheetN.xml`), which its new parts
  /// take, else its tab position counted from 1.
  int get _partNumber {
    final Match? match = RegExp(r'(\d{1,9})\.xml$').firstMatch(_partName!);
    return match == null
        ? _host.sheetIndexOf(this as XlsxSheet) + 1
        : int.parse(match[1]!);
  }

  /// Adds a comments part and the sheet's relationship to it.
  CommentsPart _addComments(_NotesRead read) {
    final ChangeLog log = _host.log;
    final OpcPackage package = _host.reader.package;
    final CommentsPart comments = CommentsPart.empty();
    final String added = addStoredPart(
      log,
      package,
      '/${commentsPartName(_partNumber)}',
      ContentType.comments,
      comments,
    );
    markStoredPart(log, read.attached, added.substring(1));
    addStoredRelationship(
      log,
      package,
      _partName!,
      type: RelType.comments,
      target: relationshipTarget(_partName, added),
    );
    _setParts(read, (
      commentsName: added.substring(1),
      comments: comments,
      vmlName: read.parts.vmlName,
      vml: read.parts.vml,
    ));
    return comments;
  }

  /// Adds a VML part, the sheet's relationship to it and `<legacyDrawing>`,
  /// with a box for every note the sheet has. A `<legacyDrawing>` that names
  /// no VML part gives way.
  VmlPart _addVml(WorksheetPart part, _NotesRead read) {
    final ChangeLog log = _host.log;
    final OpcPackage package = _host.reader.package;
    final VmlPart vml = VmlPart.empty(_host.takeVmlBlock());
    final String added = addStoredPart(
      log,
      package,
      '/${vmlDrawingPartName(_partNumber)}',
      ContentType.vmlDrawing,
      vml,
      byExtension: true,
    );
    markStoredPart(log, read.attached, added.substring(1));
    final String id = addStoredRelationship(
      log,
      package,
      _partName!,
      type: RelType.vmlDrawing,
      target: relationshipTarget(_partName, added),
    );
    final OpaqueXml element = renderElements((XmlWriter w) {
      w.empty('legacyDrawing', <String, String>{'r:id': id});
    }).single;
    final Object? old = part.layoutElement('legacyDrawing');
    editLayout(
      log,
      part,
      'legacyDrawing',
      () => part.swapLayout('legacyDrawing', old, element),
    );
    _setParts(read, (
      commentsName: read.parts.commentsName,
      comments: read.parts.comments,
      vmlName: added.substring(1),
      vml: vml,
    ));
    for (final CommentEntry e
        in read.parts.comments?.entries ?? const <CommentEntry>[]) {
      final int? row = e.row;
      final int? column = e.column;
      if (row == null || column == null) continue;
      _addShape(read, vml, (
        row: row,
        column: column,
        text: e.text,
        author: e.author,
        visible: false,
      ));
    }
    return vml;
  }

  /// Removes the sheet's relationships to the comments part and the part,
  /// unless something else still points at it.
  void _dropComments(_NotesRead read) {
    final String commentsName = read.parts.commentsName!;
    final OpcPackage package = _host.reader.package;
    final String sheet = _partName!;
    for (final OpcRelationship r in _readRelationships()) {
      if (r.type == RelType.comments &&
          !r.external &&
          _samePart(package.resolve(sheet, r.target), commentsName)) {
        removeStoredRelationship(_host.log, package, sheet, r.id);
      }
    }
    _dropPart(commentsName);
    _setParts(read, (
      commentsName: null,
      comments: null,
      vmlName: read.parts.vmlName,
      vml: read.parts.vml,
    ));
  }

  /// Removes the sheet's `<legacyDrawing>`, its relationship and the VML
  /// part, unless something else still points at the part.
  void _dropVml(WorksheetPart part, _NotesRead read) {
    final ChangeLog log = _host.log;
    final String? id = part.legacyDrawingId;
    if (id != null) {
      removeStoredRelationship(log, _host.reader.package, _partName!, id);
    }
    removeLayout(log, part, 'legacyDrawing');
    _dropPart(read.parts.vmlName!);
    _setParts(read, (
      commentsName: read.parts.commentsName,
      comments: read.parts.comments,
      vmlName: null,
      vml: null,
    ));
  }

  /// Takes the part [partName] out of the package unless a relationship
  /// still points at it.
  void _dropPart(String partName) {
    final PackageReader reader = _host.reader;
    final bool used = reader.guardXml(
      partName,
      () => reader.package.isReferenced(partName),
    );
    if (!used) removeStoredPart(_host.log, reader.package, partName);
  }

  void _setParts(_NotesRead read, _NoteParts parts) =>
      applyChange(_host.log, _NotePartsChange(read, read.parts, parts));

  static bool _samePart(String a, String b) {
    String plain(String name) =>
        (name.startsWith('/') ? name.substring(1) : name).toLowerCase();
    return plain(a) == plain(b);
  }

  /// The notes, read once.
  _NotesRead _readNotes() {
    final _NotesRead? cached = _notesRead;
    if (cached != null) return cached;
    final WorksheetPart? part = _load();
    final String? sheetName = _partName;
    if (part == null || sheetName == null) {
      return _notesRead = _NotesRead((
        commentsName: null,
        comments: null,
        vmlName: null,
        vml: null,
      ));
    }
    final PackageReader reader = _host.reader;
    final List<PartRelationship> rels = reader.relationshipsOf(
      sheetName.substring(1),
    );
    String? commentsName;
    for (final PartRelationship rel in rels) {
      if (rel.type == RelType.comments && reader.hasPart(rel.target)) {
        commentsName = rel.target;
        break;
      }
    }
    String? vmlName;
    final String? vmlId = part.legacyDrawingId;
    if (vmlId != null) {
      for (final PartRelationship rel in rels) {
        if (rel.id == vmlId &&
            rel.type == RelType.vmlDrawing &&
            reader.hasPart(rel.target)) {
          vmlName = rel.target;
          break;
        }
      }
    }
    // Problems are kept only once both parts have read, so a read that
    // throws and is retried does not report them twice.
    final List<String> problems = <String>[];
    CommentsPart? comments;
    if (commentsName != null) {
      final String name = commentsName;
      comments = reader.guardXml(
        name,
        () => CommentsPart.read(
          reader.openXml(name),
          warn: problems.add,
          limits: reader.limits,
          part: name,
        ),
      );
      if (comments == null) problems.add('comment');
    }
    VmlPart? vml;
    if (vmlName != null) {
      final String name = vmlName;
      vml = reader.guardXml(name, () {
        final XmlPullReader r = reader.openXml(name);
        return VmlPart.read(
          r.sourceText(0, r.sourceLength),
          limits: reader.limits,
          partName: name,
        );
      });
      if (vml == null) problems.add('legacyDrawing');
    }
    final _NotesRead read = _NotesRead((
      commentsName: commentsName,
      comments: comments,
      vmlName: vmlName,
      vml: vml,
    ));
    for (final VmlShape shape in vml?.shapes ?? const <VmlShape>[]) {
      read.markShown(shape, shown: true);
    }
    for (final CommentEntry entry
        in comments?.entries ?? const <CommentEntry>[]) {
      read.remember(entry);
    }
    for (final String detail in problems) {
      if (_featureReported.add(detail)) {
        _warn(XlsxWarningCode.featureEntryInvalid, null, detail: detail);
      }
    }
    return _notesRead = read;
  }
}

/// The `notes` holder of a sheet: on a row or column edit of the sheet each
/// note moves with its cell (its `<comment>`'s `ref`, and its box's
/// `<x:Row>` or `<x:Column>` and `<x:Anchor>`), and the note of a deleted
/// cell goes, as Excel does, with its box ([_SheetNotes._removeNote]). An
/// insert that would push a note off the sheet throws a [StateError], as
/// Excel refuses it for a cell that is not empty, before any change.
/// Other shapes of the VML drawing (form controls) move their anchor too.
/// Parts the model cannot type are left as written.
final class _NoteHolder implements ReferenceHolder {
  _NoteHolder(this._sheet, this._part);

  final XlsxSheet _sheet;
  final WorksheetPart _part;

  @override
  String get holderName => 'notes';

  @override
  void shiftReferences(ReferenceMapper mapper, ReferenceShift? edit) {
    if (edit == null || !_editsSheet(edit, _sheet.name)) return;
    final _NotesRead read = _sheet._readNotes();
    if (read.parts.comments == null && read.parts.vml == null) return;
    if (edit.count > 0) {
      for (final CommentEntry e
          in read.parts.comments?.entries ?? const <CommentEntry>[]) {
        if (e.row == null || edit.shiftCell(e.row!, e.column!) != null) {
          continue;
        }
        throw StateError(
          'The insert would push the note on cell '
          '${cellRef(e.row!, e.column!)} of sheet "${_sheet.name}" off the '
          'sheet.',
        );
      }
    }
    final ChangeLog log = _sheet._host.log;
    log.transaction(() {
      final CommentsPart? comments = read.parts.comments;
      if (comments != null) _moveComments(read, comments, edit);
      final VmlPart? vml = read.parts.vml;
      if (vml != null) _moveShapes(read, vml, edit);
    });
  }

  void _moveComments(
    _NotesRead read,
    CommentsPart comments,
    ReferenceShift edit,
  ) {
    final ChangeLog log = _sheet._host.log;
    for (final CommentEntry entry in List<CommentEntry>.of(comments.entries)) {
      if (entry.row == null) continue;
      if (edit.shiftCell(entry.row!, entry.column!) != null) continue;
      _sheet._removeNote(_part, read, entry);
    }
    final CommentsPart? left = read.parts.comments;
    if (left == null) return;
    final bool rows = edit.axis == ShiftAxis.rows;
    int position(CommentEntry e) => rows ? e.row! : e.column!;
    // Moved in the order that never puts one on a cell another still holds,
    // which the index of notes by cell would lose.
    final List<CommentEntry> moving =
        <CommentEntry>[
          for (final CommentEntry e in left.entries)
            if (e.row != null) e,
        ]..sort((CommentEntry a, CommentEntry b) {
          final int order = position(a).compareTo(position(b));
          return edit.count > 0 ? -order : order;
        });
    bool attached = false;
    for (final CommentEntry entry in moving) {
      final ({int row, int column}) cell = edit.shiftCell(
        entry.row!,
        entry.column!,
      )!;
      if (cell.row == entry.row && cell.column == entry.column) continue;
      if (!attached) {
        attachStoredPart(
          log,
          _sheet._host.reader.package,
          read.attached,
          read.parts.commentsName!,
          left,
        );
        attached = true;
      }
      applyChange(
        log,
        _CommentChange(
          read,
          left,
          left.entries.indexOf(entry),
          entry,
          entry.movedTo(cell.row, cell.column),
        ),
      );
    }
  }

  void _moveShapes(_NotesRead read, VmlPart vml, ReferenceShift edit) {
    final ChangeLog log = _sheet._host.log;
    if (!identical(read.parts.vml, vml)) return;
    final bool rows = edit.axis == ShiftAxis.rows;
    int position(int at) =>
        (rows ? vml.shapes[at].row : vml.shapes[at].column) ?? -1;
    // As for comments: the cells of shown boxes are kept by cell.
    final List<int> order =
        <int>[for (int at = 0; at < vml.shapes.length; at++) at]
          ..sort((int a, int b) {
            final int by = position(a).compareTo(position(b));
            return edit.count > 0 ? -by : by;
          });
    bool attached = false;
    for (final int at in order) {
      final VmlShape shape = vml.shapes[at];
      final VmlShape? moved = vml.shifted(shape, edit);
      if (moved == null) continue;
      if (!attached) {
        attachStoredPart(
          log,
          _sheet._host.reader.package,
          read.attached,
          read.parts.vmlName!,
          vml,
        );
        attached = true;
      }
      applyChange(log, _ShapeChange(read, vml, at, shape, moved));
    }
  }
}
