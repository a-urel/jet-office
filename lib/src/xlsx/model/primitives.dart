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
/// [SetRowAttributesChange]; [editLayout] edits an element of a worksheet
/// part (a slot of [WorksheetPart.layoutElement]), recording a
/// [SetLayoutChange], and [editWorkbook] one of a workbook part, recording a
/// [SetWorkbookElementChange].
/// [setEntryVisibility] and [setActiveTab] change the workbook part's sheet
/// state and active tab, recording a [SetVisibilityChange] and a
/// [SetBookViewsChange].
/// [setProperties] replaces the document properties parts, recording a
/// [SetPropertiesChange].
/// [addStoredRelationship] and [removeStoredRelationship] change a part's
/// relationships, recording a [SetRelationshipChange].
/// [addStoredPart] and [removeStoredPart] add a part to the package and take
/// one out, recording an [AddPartChange] and a [RemovePartChange] whose undo
/// gives back, or takes away, the part with its relationships and content
/// type.
/// [appendStyle] and [appendNumberFormat] give a cell format index,
/// recording a [StylesAppendChange] when that appended to the styles part,
/// so a transaction that fails later, or an undo, removes what it appended.
library;

import '../../opc/change_log.dart';
import '../../opc/opaque_xml.dart';
import '../../opc/package.dart';
import '../properties.dart';
import '../range.dart';
import '../raw_cell.dart';
import '../sheet_view.dart';
import '../style.dart';
import 'cell_store.dart';
import 'element_node.dart';
import 'properties_parts.dart';
import 'styles_part.dart';
import 'table_part.dart';
import 'workbook_part.dart';
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
  void revert() {
    _write(oldCell);
    if (_changesContent) store.valueEdits--;
  }

  @override
  void reapply() {
    _write(newCell);
    if (_changesContent) store.valueEdits++;
  }

  late final bool _changesContent = _contentDiffers(oldCell, newCell);

  void _write(RawCell? cell) {
    if (cell == null) {
      store.remove(row, column);
    } else {
      store.put(row, column, cell);
    }
  }
}

bool _sameFormula(RawFormula? a, RawFormula? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.type != b.type ||
      a.text != b.text ||
      a.ref != b.ref ||
      a.si != b.si ||
      a.attributes.length != b.attributes.length) {
    return false;
  }
  for (int i = 0; i < a.attributes.length; i++) {
    if (a.attributes[i] != b.attributes[i]) return false;
  }
  return true;
}

/// Whether the value or the formula of a cell differs between [a] and [b]
/// (`null` is an absent cell); the style, attributes and other children do
/// not count.
bool _contentDiffers(RawCell? a, RawCell? b) {
  bool empty(RawCell? c) =>
      c == null || (c.value == null && c.formula == null && c.inline == null);
  if (empty(a) && empty(b)) return false;
  if (a == null || b == null) return true;
  return a.kind != b.kind ||
      a.value != b.value ||
      a.typeText != b.typeText ||
      !_sameFormula(a.formula, b.formula) ||
      a.inline?.xml != b.inline?.xml;
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

/// The change of one element of a worksheet part (a slot of
/// [WorksheetPart.layoutElement]): the element before and after.
///
/// Only that element's slot is swapped, so a change to the other element is
/// independent of this one.
final class SetLayoutChange implements Change {
  /// A change of the element of [slot] in [part] from [before] to [after]
  /// (either `null` for none), both from [WorksheetPart.layoutElement].
  SetLayoutChange(
    this.part,
    this.slot,
    this.before,
    this.after, {
    this.position = -1,
  });

  /// The worksheet part.
  final WorksheetPart part;

  /// The slot, as [WorksheetPart.layoutElement] names it.
  final String slot;

  /// The element before the change.
  final Object? before;

  /// The element after the change.
  final Object? after;

  /// Where [before] was among the part's children, or -1 for none.
  final int position;

  @override
  void revert() => part.swapLayout(slot, after, before, position: position);

  @override
  void reapply() => part.swapLayout(slot, before, after);
}

/// Runs [edit], which changes the element of [slot] of [part] (a slot of
/// [WorksheetPart.layoutElement]) through [WorksheetPart.setColumnRuns],
/// [WorksheetPart.changeSheetFormat], [WorksheetPart.addMerge],
/// [WorksheetPart.removeMerge], [WorksheetPart.setNode] or
/// [WorksheetPart.swapLayout], and records the change in [log] unless it
/// changed nothing.
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
  final int position = part.layoutPosition(before);
  try {
    edit();
    final Object? after = part.layoutElement(slot);
    if (identical(before, after)) return;
    log.record(SetLayoutChange(part, slot, before, after, position: position));
  } catch (_) {
    part.swapLayout(slot, part.layoutElement(slot), before, position: position);
    rethrow;
  }
}

/// The change of one element of a workbook part (a slot of
/// [WorkbookPart.element]): the element before and after.
final class SetWorkbookElementChange implements Change {
  /// A change of the element of [slot] in [part] from [before] to [after]
  /// (either `null` for none), both from [WorkbookPart.element].
  SetWorkbookElementChange(
    this.part,
    this.slot,
    this.before,
    this.after, {
    this.position = -1,
  });

  /// The workbook part.
  final WorkbookPart part;

  /// The slot, as [WorkbookPart.element] names it.
  final String slot;

  /// The element before the change.
  final Object? before;

  /// The element after the change.
  final Object? after;

  /// Where [before] was among the part's children, or -1 for none.
  final int position;

  @override
  void revert() => part.swapElement(slot, after, before, position: position);

  @override
  void reapply() => part.swapElement(slot, before, after);
}

/// Runs [edit], which changes the element of [slot] of [part] through
/// [WorkbookPart.swapElement], and records the change in [log] unless it
/// changed nothing.
///
/// Must run inside `log.transaction`. If [edit] or recording throws, the
/// element is put back as it was before the error leaves.
void editWorkbook(
  ChangeLog log,
  WorkbookPart part,
  String slot,
  void Function() edit,
) {
  final Object? before = part.element(slot);
  final int position = part.elementPosition(before);
  try {
    edit();
    final Object? after = part.element(slot);
    if (identical(before, after)) return;
    log.record(
      SetWorkbookElementChange(part, slot, before, after, position: position),
    );
  } catch (_) {
    part.swapElement(slot, part.element(slot), before, position: position);
    rethrow;
  }
}

/// The change of one relationship of a part: it was added, or removed.
///
/// A relationship put back goes after the others; their order means nothing
/// in a package, and its id is the one it had.
final class SetRelationshipChange implements Change {
  /// A change of the relationships of [source] in [package]: [before] gave
  /// way to [after], either `null` for none.
  SetRelationshipChange(this.package, this.source, this.before, this.after);

  /// The package.
  final OpcPackage package;

  /// The source part, or `''` for the package root.
  final String source;

  /// The relationship before the change; `null` when it was added.
  final OpcRelationship? before;

  /// The relationship after the change; `null` when it was removed.
  final OpcRelationship? after;

  @override
  void revert() => _swap(after, before);

  @override
  void reapply() => _swap(before, after);

  void _swap(OpcRelationship? from, OpcRelationship? to) {
    if (from != null) package.removeRelationship(source, from.id);
    if (to != null) {
      package.addRelationship(
        source,
        type: to.type,
        target: to.target,
        external: to.external,
        id: to.id,
      );
    }
  }
}

/// Adds a relationship to [source] as [OpcPackage.addRelationship] does,
/// records the change in [log] and returns its id.
///
/// Must run inside `log.transaction`. Throws as
/// [OpcPackage.addRelationship] does, with nothing changed; if recording
/// throws, the relationship is removed before the error leaves.
String addStoredRelationship(
  ChangeLog log,
  OpcPackage package,
  String source, {
  required String type,
  required String target,
  bool external = false,
}) {
  final String id = package.addRelationship(
    source,
    type: type,
    target: target,
    external: external,
  );
  final SetRelationshipChange change = SetRelationshipChange(
    package,
    source,
    null,
    (id: id, type: type, target: target, external: external),
  );
  try {
    log.record(change);
  } catch (_) {
    change.revert();
    rethrow;
  }
  return id;
}

/// Removes the relationship [id] of [source] and records the change in
/// [log]. An id [source] does not have changes nothing. Neither does an id
/// a file repeats, nor a relationship with an empty id, type or target: they
/// stay as written, since [OpcPackage.addRelationship] refuses a used id and
/// those empty values, so the change could not be undone.
///
/// Must run inside `log.transaction`. Throws an [OpcFormatException] when
/// the relationships cannot be read; if recording throws, the relationship
/// is put back before the error leaves.
void removeStoredRelationship(
  ChangeLog log,
  OpcPackage package,
  String source,
  String id,
) {
  final List<OpcRelationship> found = <OpcRelationship>[
    for (final OpcRelationship r in package.relationshipsOf(source))
      if (r.id == id) r,
  ];
  if (found.length != 1) return;
  final OpcRelationship relationship = found.single;
  if (relationship.id.isEmpty ||
      relationship.type.isEmpty ||
      relationship.target.isEmpty) {
    return;
  }
  final SetRelationshipChange change = SetRelationshipChange(
    package,
    source,
    relationship,
    null,
  );
  change.reapply();
  try {
    log.record(change);
  } catch (_) {
    change.revert();
    rethrow;
  }
}

/// The change of adding a part: undone, the part leaves the package with its
/// override and relationships, and the content type default this change
/// added goes too.
final class AddPartChange implements Change {
  /// A change that added the part [name] to [package]; [addedDefault] is the
  /// extension of the default content type the addition declared, `null`
  /// when it declared none, and [defaultType] its type.
  AddPartChange(this.package, this.name, this.addedDefault, this.defaultType);

  /// The package.
  final OpcPackage package;

  /// The absolute name of the added part.
  final String name;

  /// The extension of the default this change declared, or `null`.
  final String? addedDefault;

  /// The type of that default.
  final String? defaultType;

  DetachedPart? _detached;

  @override
  void revert() {
    _detached = package.detachPart(name);
    final String? extension = addedDefault;
    if (extension != null) package.removeDefault(extension);
  }

  @override
  void reapply() {
    final String? extension = addedDefault;
    if (extension != null) package.ensureDefault(extension, defaultType!);
    package.restorePart(_detached!);
    _detached = null;
  }
}

/// The change of removing a part: undone, the part comes back with its
/// override and relationships.
final class RemovePartChange implements Change {
  /// A change that removed [detached] from [package].
  RemovePartChange(this.package, this.detached);

  /// The package.
  final OpcPackage package;

  /// What [OpcPackage.detachPart] took out.
  final DetachedPart detached;

  @override
  void revert() => package.restorePart(detached);

  @override
  void reapply() => package.detachPart(detached.name);
}

/// Adds a part as [OpcPackage.addPart] does, records the change in [log] and
/// returns the part's name.
///
/// Must run inside `log.transaction`. Throws as [OpcPackage.addPart] does,
/// with nothing changed; if recording throws, the part is taken out again
/// before the error leaves. Undoing the change removes the part and the
/// default content type it declared; redoing it gives the same name.
String addStoredPart(
  ChangeLog log,
  OpcPackage package,
  String preferredName,
  String contentType,
  PartContent content, {
  bool byExtension = false,
}) {
  final String last = preferredName.substring(
    preferredName.lastIndexOf(RegExp(r'[/\\]')) + 1,
  );
  final int dot = last.lastIndexOf('.');
  final String extension = dot < 0 ? '' : last.substring(dot + 1);
  final bool declare = byExtension && extension.isNotEmpty;
  final bool addedDefault =
      declare && package.ensureDefault(extension, contentType);
  final String name;
  try {
    name = package.addPart(
      preferredName,
      contentType,
      content,
      byExtension: byExtension,
    );
  } catch (_) {
    if (addedDefault) package.removeDefault(extension);
    rethrow;
  }
  final AddPartChange change = AddPartChange(
    package,
    name,
    addedDefault ? extension : null,
    addedDefault ? contentType : null,
  );
  try {
    log.record(change);
  } catch (_) {
    change.revert();
    rethrow;
  }
  return name;
}

/// Takes the part [name] out of the package ([OpcPackage.detachPart]) and
/// records the change in [log].
///
/// Relationships that point at the part stay; the caller removes them, as
/// separate changes. Must run inside `log.transaction`. Throws
/// [ArgumentError] when there is no such part; if recording throws, the part
/// is put back before the error leaves.
void removeStoredPart(ChangeLog log, OpcPackage package, String name) {
  final RemovePartChange change = RemovePartChange(
    package,
    package.detachPart(name),
  );
  try {
    log.record(change);
  } catch (_) {
    change.revert();
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
/// a style, [StylesPart.withNumberFormat], or
/// [StylesPart.differentialIdFor].
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

/// The differential style index of [style] in [styles]
/// ([StylesPart.differentialIdFor]), and a [StylesAppendChange] recorded in
/// [log] when that appended a `<dxf>`.
///
/// An equal exact `<dxf>` of the part is reused and records nothing. Must
/// run inside `log.transaction`. Validates nothing itself: the caller has
/// run `validateDifferentialStyle` (a conditional format's check does), and
/// what the registry still refuses, such as a number format code, throws as
/// [StylesPart.differentialIdFor] does, with nothing changed. If recording
/// throws, the appended entry is removed before the error leaves.
int appendDifferentialStyle(
  ChangeLog log,
  StylesPart styles,
  XlsxStyle style,
) => _appending(log, styles, () => styles.differentialIdFor(style));

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

/// The change of one sheet's visibility: before and after.
final class SetVisibilityChange implements Change {
  /// A change of [entry] from [oldVisibility] (written with `state="visible"`
  /// when [oldExplicit]) to [newVisibility].
  SetVisibilityChange(
    this.entry,
    this.oldVisibility,
    this.oldExplicit,
    this.newVisibility,
  );

  /// The sheet entry that changed.
  final SheetEntry entry;

  /// The visibility before the change.
  final XlsxSheetVisibility oldVisibility;

  /// Whether the source said `state="visible"` before the change.
  final bool oldExplicit;

  /// The visibility after the change.
  final XlsxSheetVisibility newVisibility;

  @override
  void revert() {
    entry.visibility = oldVisibility;
    entry.explicitVisible = oldExplicit;
  }

  @override
  void reapply() {
    entry.visibility = newVisibility;
    entry.explicitVisible = false;
  }
}

/// Sets the visibility of [entry] to [visibility] and records the change in
/// [log]; an equal visibility changes nothing. A visible sheet has no
/// `state` attribute afterwards.
///
/// Must run inside `log.transaction`. If recording throws, the entry is put
/// back as it was before the error leaves.
void setEntryVisibility(
  ChangeLog log,
  SheetEntry entry,
  XlsxSheetVisibility visibility,
) {
  if (entry.visibility == visibility) return;
  final SetVisibilityChange change = SetVisibilityChange(
    entry,
    entry.visibility,
    entry.explicitVisible,
    visibility,
  );
  change.reapply();
  try {
    log.record(change);
  } catch (_) {
    change.revert();
    rethrow;
  }
}

/// The change of the workbook's `<bookViews>` element: before and after.
final class SetBookViewsChange implements Change {
  /// A change of [part]'s `<bookViews>` from [before] to [after]; `null` is
  /// an absent element.
  SetBookViewsChange(this.part, this.before, this.after);

  /// The workbook part.
  final WorkbookPart part;

  /// The element before the change.
  final XmlNode? before;

  /// The element after the change.
  final XmlNode? after;

  @override
  void revert() => part.swapBookViews(after, before);

  @override
  void reapply() => part.swapBookViews(before, after);
}

/// Sets the active tab of [part] to [index] and records the change in [log];
/// an equal index changes nothing.
///
/// Must run inside `log.transaction`. If recording throws, the element is
/// put back as it was before the error leaves.
void setActiveTab(ChangeLog log, WorkbookPart part, int index) {
  final XmlNode? before = part.bookViews;
  part.setActiveTabIndex(index);
  final XmlNode? after = part.bookViews;
  if (identical(before, after)) return;
  try {
    log.record(SetBookViewsChange(part, before, after));
  } catch (_) {
    part.swapBookViews(after, before);
    rethrow;
  }
}

/// The change of the document properties: the three parts before and after.
final class SetPropertiesChange implements Change {
  /// A change of [state]'s parts from [before] to [after].
  SetPropertiesChange(this.state, this.before, this.after);

  /// The properties of the workbook.
  final PropertiesState state;

  /// The parts before the change.
  final PropertyParts before;

  /// The parts after the change.
  final PropertyParts after;

  @override
  void revert() => state.swap(before);

  @override
  void reapply() => state.swap(after);
}

/// Sets the document properties of [state] to [value] and records the
/// change in [log]; a [value] equal to what [state] shows changes nothing.
///
/// Must run inside `log.transaction`. Throws an [ArgumentError] for a bad
/// [value] (see `checkProperties`) and a [StateError] when a part that must
/// change is not a properties part; nothing has changed then. If recording
/// throws, the parts are put back as they were before the error leaves.
void setProperties(ChangeLog log, PropertiesState state, XlsxProperties value) {
  if (value == state.parts.merged) return;
  checkProperties(value);
  final PropertyParts before = state.parts;
  final PropertyParts after = before.withProperties(value);
  final SetPropertiesChange change = SetPropertiesChange(state, before, after);
  change.reapply();
  try {
    log.record(change);
  } catch (_) {
    change.revert();
    rethrow;
  }
}
