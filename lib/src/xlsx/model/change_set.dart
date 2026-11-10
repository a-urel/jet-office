/// Public change records, change sets and the recording of a model edit.
///
/// Not ported from Quds; written for jet_office (decision 0009).
library;

import '../../opc/change_log.dart';
import '../range.dart';

/// What kind of edit an [XlsxChange] records.
enum XlsxChangeKind {
  /// Cell values, formulas, styles or links were set ([XlsxChange.range]).
  cellsSet,

  /// Rows were inserted at [XlsxChange.index] (0-based), [XlsxChange.count]
  /// of them.
  rowsInserted,

  /// Rows were deleted from [XlsxChange.index] on, [XlsxChange.count] of
  /// them.
  rowsDeleted,

  /// Columns were inserted, as [rowsInserted].
  columnsInserted,

  /// Columns were deleted, as [rowsDeleted].
  columnsDeleted,

  /// A sheet was renamed from [XlsxChange.oldSheet] to [XlsxChange.sheet].
  sheetRenamed,

  /// A sheet was moved to the tab index [XlsxChange.index].
  sheetMoved,

  /// A sheet was added at the tab index [XlsxChange.index].
  sheetAdded,

  /// A defined name was defined or removed: of the sheet [XlsxChange.sheet],
  /// or of the workbook when it is `null`.
  nameChanged,

  /// A sheet feature changed (a merge, a rule, a note, a picture, the page
  /// setup, a view, the layout, the protection and the like).
  featureChanged,

  /// A table was added, resized, renamed, restyled or removed.
  tableChanged,

  /// A workbook-wide part changed (properties, protection, active sheet).
  partChanged,
}

/// One edit of an `XlsxWorkbook`, as a calculation engine needs it to know
/// what to invalidate.
final class XlsxChange {
  /// A record of [kind] on [sheet].
  const XlsxChange(
    this.kind, {
    this.sheet,
    this.oldSheet,
    this.range,
    this.index,
    this.count,
  });

  /// What kind of edit this is.
  final XlsxChangeKind kind;

  /// The sheet's name after the edit, or `null` for a workbook-wide edit.
  final String? sheet;

  /// The sheet's name before a rename; `null` otherwise.
  final String? oldSheet;

  /// The cells affected, or `null` when the edit is not bound to cells (a
  /// row or column edit, which [index] and [count] describe, or a
  /// whole-sheet or workbook-wide edit).
  final XlsxRange? range;

  /// The first row or column (0-based) of a row or column edit, or the tab
  /// index of a moved or added sheet.
  final int? index;

  /// The number of rows or columns of a row or column edit.
  final int? count;

  @override
  bool operator ==(Object other) =>
      other is XlsxChange &&
      other.kind == kind &&
      other.sheet == sheet &&
      other.oldSheet == oldSheet &&
      other.range == range &&
      other.index == index &&
      other.count == count;

  @override
  int get hashCode => Object.hash(kind, sheet, oldSheet, range, index, count);

  @override
  String toString() =>
      'XlsxChange(${kind.name}'
      '${sheet == null ? '' : ', sheet: $sheet'}'
      '${oldSheet == null ? '' : ', oldSheet: $oldSheet'}'
      '${range == null ? '' : ', range: $range'}'
      '${index == null ? '' : ', index: $index'}'
      '${count == null ? '' : ', count: $count'}'
      ')';
}

/// The edits one `XlsxWorkbook.transaction` made, to hand to
/// `XlsxWorkbook.undo` and `XlsxWorkbook.redo`.
final class XlsxChangeSet {
  XlsxChangeSet._(this._set)
    : changes = List<XlsxChange>.unmodifiable(
        _set.records.whereType<XlsxChange>(),
      );

  final ChangeSet _set;

  /// The edits, one per call of a public edit, oldest first. Unmodifiable.
  final List<XlsxChange> changes;

  /// Whether the transaction changed nothing.
  bool get isEmpty => _set.isEmpty;
}

/// [set] as the public change set.
XlsxChangeSet publicChangeSet(ChangeSet set) => XlsxChangeSet._(set);

/// The internal set [set] wraps.
ChangeSet internalChangeSet(XlsxChangeSet set) => set._set;

final Expando<bool> _recording = Expando<bool>('recording');

/// Runs [edit], a public edit, in a transaction of [log] and, when it
/// changed anything, notes the record [change] gives (computed after the
/// edit) for the transaction's caller. A public edit called inside another
/// notes nothing, so each public call notes one record.
T recordEdit<T>(
  ChangeLog log,
  XlsxChange Function() change,
  T Function() edit,
) {
  if (_recording[log] ?? false) return edit();
  late T result;
  log.transaction(() {
    _recording[log] = true;
    final ChangeSet set;
    try {
      set = log.transaction(() => result = edit());
    } finally {
      _recording[log] = null;
    }
    if (!set.isEmpty) log.note(change());
  });
  return result;
}
