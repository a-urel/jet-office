/// The set-cell and rename-table-column primitives of the workbook model and
/// the formula-group role of a stored cell.
///
/// Not ported from Quds; written for jet_office.
///
/// [setStoredCell] is the one way a model edit changes a [CellStore]: it
/// applies the change, then records a [SetCellChange] so the edit can be
/// reverted and reapplied. [groupRoleAt] says whether a cell belongs to a
/// shared, array or data-table formula group, which the editing methods use to
/// refuse an edit that would break a group. [renameTableColumn] gives a table
/// column a new name, recording a [TableColumnNameChange] the same way, and
/// [setStoredRowAttributes] sets a row's attributes, recording a
/// [SetRowAttributesChange]; [editLayout] edits a part's `cols`,
/// `sheetFormatPr`, `mergeCells`, `sheetPr` and `sheetViews`, recording a
/// [SetLayoutChange].
/// [appendStyle] and [appendNumberFormat] give a cell format index,
/// recording a [StylesAppendChange] when that appended to the styles part,
/// so a transaction that fails later, or an undo, removes what it appended.
library;

import '../../opc/change_log.dart';
import '../../opc/opaque_xml.dart';
import '../range.dart';
import '../raw_cell.dart';
import '../style.dart';
import 'cell_store.dart';
import 'styles_part.dart';
import 'table_part.dart';
import 'worksheet_part.dart';

/// The change of one cell: its content before and after.
///
/// A `null` cell is an absent cell. The change is applied by
/// [setStoredCell]; [revert] and [reapply] write the old and the new content
/// back to the same position.
final class SetCellChange implements Change {
  /// A change of the cell at [row], [column] of [store] from [oldCell] to
  /// [newCell].
  SetCellChange(this.store, this.row, this.column, this.oldCell, this.newCell);

  /// The store the cell lives in.
  final CellStore store;

  /// The zero-based row.
  final int row;

  /// The zero-based column.
  final int column;

  /// The content before the change, or `null` when there was no cell.
  final RawCell? oldCell;

  /// The content after the change, or `null` when the cell was removed.
  final RawCell? newCell;

  @override
  void revert() => _write(oldCell);

  @override
  void reapply() => _write(newCell);

  void _write(RawCell? cell) {
    if (cell == null) {
      store.remove(row, column);
    } else {
      store.put(row, column, cell);
    }
  }
}

/// Sets the cell at [row], [column] of [store] to [cell] (`null` removes it)
/// and records the change in [log].
///
/// Must run inside `log.transaction`, which [ChangeLog.record] requires. If
/// recording throws, the store is put back as it was before the error leaves.
void setStoredCell(
  ChangeLog log,
  CellStore store,
  int row,
  int column,
  RawCell? cell,
) {
  final SetCellChange change = SetCellChange(
    store,
    row,
    column,
    store.cellAt(row, column),
    cell,
  );
  change.reapply();
  try {
    log.record(change);
  } catch (_) {
    change.revert();
    rethrow;
  }
}

/// The change of one row's `<row>` attributes: before and after.
///
/// An empty list is a row without attributes, which the store drops when it
/// also has no cells and no children.
final class SetRowAttributesChange implements Change {
  /// A change of the attributes of [row] of [store] from [oldAttributes] to
  /// [newAttributes].
  SetRowAttributesChange(
    this.store,
    this.row,
    this.oldAttributes,
    this.newAttributes,
  );

  /// The store the row lives in.
  final CellStore store;

  /// The zero-based row.
  final int row;

  /// The attributes before the change.
  final List<KeptAttribute> oldAttributes;

  /// The attributes after the change.
  final List<KeptAttribute> newAttributes;

  @override
  void revert() => store.setRowAttributes(row, oldAttributes);

  @override
  void reapply() => store.setRowAttributes(row, newAttributes);
}

/// Sets the `<row>` attributes of [row] of [store] to [attributes] and
/// records the change in [log].
///
/// Must run inside `log.transaction`. If recording throws, the store is put
/// back as it was before the error leaves.
void setStoredRowAttributes(
  ChangeLog log,
  CellStore store,
  int row,
  List<KeptAttribute> attributes,
) {
  final SetRowAttributesChange change = SetRowAttributesChange(
    store,
    row,
    store.rowAttributes(row),
    attributes,
  );
  change.reapply();
  try {
    log.record(change);
  } catch (_) {
    change.revert();
    rethrow;
  }
}

/// The change of one layout element of a worksheet part (`cols`,
/// `sheetFormatPr`, `mergeCells`, `sheetPr` or `sheetViews`): the element
/// before and after.
///
/// Only that element's slot is swapped, so a change to the other element is
/// independent of this one.
final class SetLayoutChange implements Change {
  /// A change of the element of [slot] in [part] from [before] to [after]
  /// (either `null` for none), both from [WorksheetPart.layoutElement].
  SetLayoutChange(this.part, this.slot, this.before, this.after);

  /// The worksheet part.
  final WorksheetPart part;

  /// `cols`, `sheetFormatPr`, `mergeCells`, `sheetPr` or `sheetViews`.
  final String slot;

  /// The element before the change.
  final Object? before;

  /// The element after the change.
  final Object? after;

  @override
  void revert() => part.swapLayout(slot, after, before);

  @override
  void reapply() => part.swapLayout(slot, before, after);
}

/// Runs [edit], which changes the element of [slot] (`cols`,
/// `sheetFormatPr` or `mergeCells`) of [part] through
/// [WorksheetPart.setColumnRuns], [WorksheetPart.changeSheetFormat],
/// [WorksheetPart.addMerge] or [WorksheetPart.removeMerge], and records the change in [log]
/// unless it changed nothing.
///
/// Must run inside `log.transaction`. If [edit] or recording throws, the
/// element is put back as it was before the error leaves.
void editLayout(
  ChangeLog log,
  WorksheetPart part,
  String slot,
  void Function() edit,
) {
  final Object? before = part.layoutElement(slot);
  try {
    edit();
    final Object? after = part.layoutElement(slot);
    if (identical(before, after)) return;
    log.record(SetLayoutChange(part, slot, before, after));
  } catch (_) {
    part.swapLayout(slot, part.layoutElement(slot), before);
    rethrow;
  }
}

/// The change of one table column's name: before and after.
final class TableColumnNameChange implements Change {
  /// A change of column [index] of [table] from [oldName] to [newName].
  TableColumnNameChange(this.table, this.index, this.oldName, this.newName);

  /// The table part the column belongs to.
  final TablePart table;

  /// The column's index in the table, 0 for its first column.
  final int index;

  /// The name before the change.
  final String oldName;

  /// The name after the change.
  final String newName;

  @override
  void revert() => table.setColumnName(index, oldName);

  @override
  void reapply() => table.setColumnName(index, newName);
}

/// Gives column [index] of [table] the name [name] and records the change in
/// [log].
///
/// Must run inside `log.transaction`. If recording throws, the old name is
/// put back before the error leaves.
void renameTableColumn(ChangeLog log, TablePart table, int index, String name) {
  final TableColumnNameChange change = TableColumnNameChange(
    table,
    index,
    table.columnName(index),
    name,
  );
  change.reapply();
  try {
    log.record(change);
  } catch (_) {
    change.revert();
    rethrow;
  }
}

/// The entries one call appended to a styles part: [StylesPart.idFor] for
/// a style, or [StylesPart.withNumberFormat].
///
/// The styles part is append-only, so [revert] rolls it back to the mark
/// taken before, and [reapply] makes the same call again, which appends
/// the same entries at the same positions.
final class StylesAppendChange implements Change {
  /// A change that appended to [styles], from [before], by `append`.
  StylesAppendChange(this.styles, this.before, this._append);

  /// The styles part the entries were appended to.
  final StylesPart styles;

  /// The part's counts before the entries were appended.
  final StylesMark before;

  final void Function() _append;

  @override
  void revert() => styles.rollBack(before);

  @override
  void reapply() => _append();
}

/// The cell format index of [style] in [styles] ([StylesPart.idFor]), and a
/// [StylesAppendChange] recorded in [log] when that appended entries.
///
/// Must run inside `log.transaction`. Throws as [StylesPart.idFor] does,
/// with nothing changed; if recording throws, the appended entries are
/// removed before the error leaves.
int appendStyle(ChangeLog log, StylesPart styles, XlsxStyle? style) =>
    _appending(log, styles, () => styles.idFor(style));

/// The cell format index [StylesPart.withNumberFormat] gives for [style]
/// and [numFmtId], recorded in [log] as [appendStyle] records.
int appendNumberFormat(
  ChangeLog log,
  StylesPart styles,
  int? style,
  int numFmtId,
) => _appending(log, styles, () => styles.withNumberFormat(style, numFmtId));

int _appending(ChangeLog log, StylesPart styles, int Function() append) {
  final StylesMark before = styles.mark();
  final int id = append();
  if (styles.mark() == before) return id;
  try {
    log.record(StylesAppendChange(styles, before, append));
  } catch (_) {
    styles.rollBack(before);
    rethrow;
  }
  return id;
}

/// How a cell takes part in a formula group.
enum GroupRole {
  /// Not part of any group.
  none,

  /// The cell carrying a shared formula's text and `ref`.
  sharedMaster,

  /// A shared-formula cell with an `si` and no `ref`, whose master exists.
  sharedChild,

  /// A cell inside an array or data-table master's `ref`, the master
  /// included: setting it alone would break the array or table.
  arrayOrTableMember,
}

/// The [GroupRole] of the cell at [row], [column], computed from the formulas
/// stored in [store].
///
/// A cell with its own array or data-table formula, or one inside such a
/// formula's `ref`, is [GroupRole.arrayOrTableMember]; a shared formula with a
/// `ref` is [GroupRole.sharedMaster]; one with an `si`, no `ref` and a master
/// of the same `si` somewhere in the store is [GroupRole.sharedChild].
/// Anything else is [GroupRole.none].
///
/// Complexity: a store without formulas answers at once; otherwise this
/// looks at the store's group masters ([CellStore.groupMasters]), so it
/// costs time in proportion to the number of groups, not of cells, and a
/// loop that sets every cell of a large sheet stays linear.
GroupRole groupRoleAt(CellStore store, int row, int column) {
  if (!store.hasFormulas) return GroupRole.none;
  final RawFormula? own = store.cellAt(row, column)?.formula;
  if (own != null) {
    switch (own.type) {
      case FormulaType.array || FormulaType.dataTable:
        return GroupRole.arrayOrTableMember;
      case FormulaType.shared when own.ref != null:
        return GroupRole.sharedMaster;
      case FormulaType.shared || FormulaType.normal:
        break;
    }
  }
  final String? childSi = own != null && own.type == FormulaType.shared
      ? own.si
      : null;
  bool masterFound = false;
  for (final ({int row, int column, RawFormula formula}) m
      in store.groupMasters) {
    final RawFormula f = m.formula;
    switch (f.type) {
      case FormulaType.array || FormulaType.dataTable:
        final XlsxRange? range = _range(f.ref);
        if (range != null &&
            row >= range.firstRow &&
            row <= range.lastRow &&
            column >= range.firstColumn &&
            column <= range.lastColumn) {
          return GroupRole.arrayOrTableMember;
        }
      case FormulaType.shared:
        if (childSi != null && f.si == childSi) masterFound = true;
      case FormulaType.normal:
        break;
    }
  }
  return masterFound ? GroupRole.sharedChild : GroupRole.none;
}

XlsxRange? _range(String? ref) {
  if (ref == null) return null;
  try {
    return XlsxRange.parse(ref);
  } on ArgumentError {
    return null;
  }
}
