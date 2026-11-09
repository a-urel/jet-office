/// The merged ranges of an [XlsxSheet]: the members that read, add and
/// remove them.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `xlsx_sheet.dart`, kept apart only to keep that file readable:
/// [XlsxSheet] mixes [_SheetMerges] in, so these are members of the sheet.
part of 'xlsx_sheet.dart';

/// The merge half of [XlsxSheet].
mixin _SheetMerges {
  // What the sheet gives its merge half.
  SheetHost get _host;
  String get name;
  WorksheetPart? _load();
  WorksheetPart _editablePart(String what);
  List<({String partName, TablePart table})> _sheetTables();

  /// The merged ranges, in file order, as the reader's `mergesAt` reads
  /// them.
  ///
  /// A `<mergeCell>` whose `ref` cannot be read is left out, kept as
  /// written and reported once as `mergeRangeInvalid`. Only the first
  /// `<mergeCells>` is read. Unmodifiable. Loads the sheet. Throws an
  /// [XlsxReadException] when the sheet cannot be read, and, on load, when
  /// it holds more merges than `XlsxReadLimits.maxMerges` allows
  /// (`limitExceeded`).
  List<XlsxRange> get merges =>
      List<XlsxRange>.unmodifiable(_load()?.merges ?? const <XlsxRange>[]);

  /// Merges the cells of [range] into one that shows the top-left cell.
  ///
  /// The merge is added after the others as the writer writes it
  /// (`<mergeCell ref=...>`), the `<mergeCells>` is made in schema position
  /// when the sheet has none, and its `count` is recomputed. The cells keep
  /// their values.
  ///
  /// Throws an [ArgumentError] named `range`, as the writer's `merge` does,
  /// for a range outside the sheet, with its first corner after its last,
  /// that is a single cell, or that overlaps a merged range or a table of
  /// the sheet (the message names both ranges); a [StateError] for a sheet
  /// that is not a worksheet or has no part; and an [XlsxReadException]
  /// when the sheet cannot be read. Whatever it throws, nothing has
  /// changed, except that reading warnings are reported on first read.
  void merge(XlsxRange range) {
    validateRange(range, 'range');
    final WorksheetPart part = _editablePart('merged ranges');
    checkMerge(range, part.merges, <({String name, XlsxRange range})>[
      for (final ({String partName, TablePart table}) t in _sheetTables())
        (name: t.table.displayName, range: t.table.range),
    ]);
    final ChangeLog log = _host.log;
    log.transaction(() {
      editLayout(log, part, 'mergeCells', () => part.addMerge(range));
    });
  }

  /// Splits the merged range [range], which must be one of [merges]
  /// exactly. The cells keep their values, as Excel's own unmerge keeps
  /// them; the `<mergeCells>` goes with its last child, and `count` is
  /// recomputed.
  ///
  /// Throws an [ArgumentError] named `range` when [range] is not merged, a
  /// [StateError] for a sheet that is not a worksheet or has no part and an
  /// [XlsxReadException] when the sheet cannot be read. Whatever it throws,
  /// nothing has changed.
  void unmerge(XlsxRange range) {
    final WorksheetPart part = _editablePart('merged ranges');
    if (!part.merges.contains(range)) {
      throw ArgumentError.value(
        range,
        'range',
        'The range ${range.ref} is not a merged range of the sheet "$name".',
      );
    }
    final ChangeLog log = _host.log;
    log.transaction(() {
      editLayout(log, part, 'mergeCells', () => part.removeMerge(range));
    });
  }
}

/// The `merges` holder of a sheet: on a row or column edit of the sheet,
/// each merge shifts, grows when an insert crosses it, shrinks when a
/// delete cuts it, and goes when the edit deletes it wholly or leaves one
/// cell of it ([ReferenceShift.shiftRange]).
final class _MergeHolder implements ReferenceHolder {
  _MergeHolder(this._log, this._part, this._sheetName);

  final ChangeLog _log;
  final WorksheetPart _part;
  final String Function() _sheetName;

  @override
  String get holderName => 'merges';

  @override
  void shiftReferences(ReferenceMapper mapper, ReferenceShift? edit) {
    if (edit == null || !_editsSheet(edit, _sheetName())) return;
    if (_part.merges.isEmpty) return;
    editLayout(
      _log,
      _part,
      'mergeCells',
      () => _part.mapMerges(edit.shiftRange),
    );
  }
}

/// Whether [edit] edits the sheet named [name] (ignoring case, as Excel).
bool _editsSheet(ReferenceShift edit, String name) =>
    edit.sheet.toLowerCase() == name.toLowerCase();
