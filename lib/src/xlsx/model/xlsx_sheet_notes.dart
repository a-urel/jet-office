/// The notes of an [XlsxSheet]: the members that read them.
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
part of 'xlsx_sheet.dart';

/// What the sheet read of its notes: the two parts, where they are, and the
/// listed notes in file order.
final class _NotesRead {
  _NotesRead(this.commentsName, this.comments, this.vmlName, this.vml);

  /// The comments part's name (no leading `/`), or `null` for none.
  final String? commentsName;

  /// The typed comments part, or `null` when there is none or it is not
  /// SpreadsheetML.
  final CommentsPart? comments;

  /// The VML part's name (no leading `/`), or `null` for none.
  final String? vmlName;

  /// The typed VML part, or `null` when there is none or it is not well
  /// formed.
  final VmlPart? vml;

  /// The listed notes in file order.
  final List<XlsxCellNote> notes = <XlsxCellNote>[];

  /// The index in [notes] of the note at `row * maxColumns + column`.
  final Map<int, int> index = <int, int>{};
}

/// The note half of [XlsxSheet].
mixin _SheetNotes {
  // What the sheet gives its note half.
  SheetHost get _host;
  String? get _partName;
  WorksheetPart? _load();
  Set<String> get _featureReported;
  void _warn(XlsxWarningCode code, String? cell, {String? detail});

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
  List<XlsxCellNote> get notes =>
      List<XlsxCellNote>.unmodifiable(_readNotes().notes);

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
    final int? at = read.index[row * XlsxLimits.maxColumns + column];
    return at == null ? null : read.notes[at].note;
  }

  /// The notes, read once.
  _NotesRead _readNotes() {
    final _NotesRead? cached = _notesRead;
    if (cached != null) return cached;
    final WorksheetPart? part = _load();
    final String? sheetName = _partName;
    if (part == null || sheetName == null) {
      return _notesRead = _NotesRead(null, null, null, null);
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
        return VmlPart.read(r.sourceText(0, r.sourceLength));
      });
      if (vml == null) problems.add('legacyDrawing');
    }
    final _NotesRead read = _NotesRead(commentsName, comments, vmlName, vml);
    if (comments != null) {
      final Set<int> shown = <int>{};
      for (final VmlShape shape in vml?.shapes ?? const <VmlShape>[]) {
        final int? row = shape.row;
        final int? column = shape.column;
        if (shape.isNote && shape.visible && row != null && column != null) {
          shown.add(row * XlsxLimits.maxColumns + column);
        }
      }
      for (final CommentEntry entry in comments.entries) {
        final int? row = entry.row;
        final int? column = entry.column;
        if (row == null || column == null) continue;
        final int key = row * XlsxLimits.maxColumns + column;
        read.index[key] = read.notes.length;
        read.notes.add((
          row: row,
          column: column,
          note: XlsxNote(
            entry.text,
            author: entry.author,
            visible: shown.contains(key),
          ),
        ));
      }
    }
    for (final String detail in problems) {
      if (_featureReported.add(detail)) {
        _warn(XlsxWarningCode.featureEntryInvalid, null, detail: detail);
      }
    }
    return _notesRead = read;
  }
}
