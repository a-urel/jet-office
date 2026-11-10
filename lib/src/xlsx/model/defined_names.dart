/// The defined names of a workbook: [NameEntry], its reading from a
/// `<definedName>` and writing as the writer writes it, and the edits that
/// the public `defineName` and `removeName` of the workbook and of a sheet
/// share.
///
/// Not ported from Quds; written for jet_office.
///
/// A name is kept in the workbook part's `<definedNames>` group as an
/// [ItemGroup] of [NameEntry] items. The item's source is the element as
/// read, so every attribute the model does not type (`function`,
/// `vbProcedure`, `xlm`, `shortcutKey`, ...) stays in it; an entry that
/// cannot be read stays too, left out of the typed list.
library;

import '../../opc/change_log.dart';
import '../../opc/opaque_xml.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import '../../xml/xml_writer.dart';
import '../defined_name.dart';
import '../formula/formula_rewrite.dart';
import '../formula/reference_shift.dart';
import '../sheet_name.dart';
import '../workbook_parts.dart' show writeDefinedName;
import 'columns.dart' show replaceAttributes;
import 'item_group.dart';
import 'reference_holders.dart';
import 'workbook_part.dart';

/// A `<definedName>`, as the model reads it.
///
/// The name and the comment have `_xHHHH_` decoded and the formula is the
/// text as written, decoded the same way (decision 0005).
final class NameEntry {
  /// A name [name] for [formula] in the scope of the sheet at tab index
  /// [localSheetId], or in the workbook's when that is `null`.
  NameEntry({
    required this.name,
    required this.formula,
    this.localSheetId,
    this.hidden = false,
    this.comment,
  });

  /// The name, `_xHHHH_` decoded.
  final String name;

  /// The tab index of the sheet the name belongs to, or `null` for the
  /// workbook. An index that names no sheet is read as written.
  final int? localSheetId;

  /// The formula the name stands for, without a leading `=` as the file
  /// has it.
  final String formula;

  /// Whether Excel hides the name in its Name Manager.
  final bool hidden;

  /// The comment shown in the Name Manager, if any.
  final String? comment;

  /// Whether this is one of Excel's built-in names: `_xlnm.` followed by
  /// anything, in any case.
  bool get builtIn => name.toLowerCase().startsWith('_xlnm.');

  /// This name as the public value type.
  XlsxDefinedName get definedName =>
      XlsxDefinedName(name, formula, hidden: hidden, comment: comment);
}

/// The `<definedName>` that [element] is, read, or the problem that keeps
/// it from being read: no `name` or an empty one, or a `localSheetId` that is
/// not an unsigned integer.
({NameEntry? value, String? problem}) readNameEntry(OpaqueXml element) {
  final XmlPullReader r = readerOf(element);
  final String? name = r.getAttribute('name');
  if (name == null || name.isEmpty) {
    return (value: null, problem: 'definedName');
  }
  final String? scope = r.getAttribute('localSheetId');
  final int? localSheetId = scope == null ? null : parseSheetId(scope);
  if (scope != null && localSheetId == null) {
    return (value: null, problem: 'definedName');
  }
  final String? comment = r.getAttribute('comment');
  final String? hidden = r.getAttribute('hidden');
  final StringBuffer text = StringBuffer();
  try {
    if (!r.isEmptyElement) {
      final int depth = r.depth;
      while (r.next()) {
        if (r.eventType == XmlEventType.endElement && r.depth < depth) break;
        switch (r.eventType) {
          case XmlEventType.characters || XmlEventType.cdata:
            text.write(r.text);
          case XmlEventType.startElement:
            r.skip();
          default:
        }
      }
    }
  } on XmlParseException {
    return (value: null, problem: 'definedName');
  }
  return (
    value: NameEntry(
      name: decodeXstring(name),
      formula: decodeXstring(text.toString()),
      localSheetId: localSheetId,
      hidden: hidden == '1' || hidden == 'true',
      comment: comment == null ? null : decodeXstring(comment),
    ),
    problem: null,
  );
}

/// [entry] as the writer writes a `<definedName>`. A forbidden character in
/// the formula, which only the name of a sheet read from a file can have put
/// there, is dropped, as it is from that name when the sheet is written.
OpaqueXml renderNameEntry(NameEntry entry) => renderElements(
  (XmlWriter w) => writeDefinedName(
    w,
    entry.name,
    entry.localSheetId,
    scrubXmlText(entry.formula).text,
    hidden: entry.hidden,
    comment: entry.comment,
  ),
).single;

/// [source], the element of the name [old], holding the formula of [entry]
/// as the writer writes one, with `hidden` set as [entry] says when it
/// differs from [old]. Its name, prefix, declarations and every other
/// attribute (`publishToServer`, `description`, `xr:uid`, ...) stay as
/// written.
OpaqueXml rewriteNameEntry(OpaqueXml source, NameEntry old, NameEntry entry) {
  final XmlPullReader r = readerOf(source);
  final Map<String, String> namespaces = Map<String, String>.of(
    r.declaredNamespaces,
  );
  final List<KeptAttribute> kept = keepAttributes(r);
  final Map<String, String> inner = mergeNamespaces(
    source.inheritedNamespaces,
    namespaces,
  );
  final StringBuffer out = StringBuffer();
  final XmlWriter w = XmlWriter(out)..start('wrapper');
  writeNamespaceDeclarations(w, source.inheritedNamespaces);
  w.start(r.qualifiedName);
  writeNamespaceDeclarations(w, namespaces);
  final Map<String, String?> changes = <String, String?>{
    if (old.hidden != entry.hidden) 'hidden': entry.hidden ? '1' : null,
    if (old.localSheetId != entry.localSheetId)
      'localSheetId': entry.localSheetId?.toString(),
  };
  writeKeptAttributes(
    w,
    changes.isEmpty ? kept : replaceAttributes(kept, changes),
    declaredAbove: inner,
  );
  w
    ..raw(escapeFormulaText(scrubXmlText(entry.formula).text))
    ..end()
    ..end();
  // The element was read under the file's depth limit, as in `readerOf`.
  return OpaqueXml.capture(
    XmlPullReader(out.toString(), maxDepth: 0x7FFFFFFF)
      ..next()
      ..next(),
  );
}

/// The change of the `<definedNames>` group made by `defineName` or
/// `removeName`: the group before and after, and, as that moves the
/// workbook's [WorkbookPart.nameEdits], the way back and forth.
final class SetNamesChange implements Change {
  /// A change of the group of [part] from [before] to [after], both from
  /// [WorkbookPart.element] (`null` for none).
  SetNamesChange(this.part, this.before, this.after, {this.position = -1});

  /// The workbook part.
  final WorkbookPart part;

  /// The group before the change.
  final Object? before;

  /// The group after the change.
  final Object? after;

  /// Where [before] was among the part's children, or -1 for none.
  final int position;

  @override
  void revert() {
    part.swapElement('definedNames', after, before, position: position);
    part.nameEdits--;
  }

  @override
  void reapply() {
    part.swapElement('definedNames', before, after);
    part.nameEdits++;
  }
}

/// The mark a table resize leaves on the workbook: [WorkbookPart.tableEdits]
/// one higher while the resize is in force.
final class TableResizeChange implements Change {
  /// A change that raised the count of [part], already applied.
  TableResizeChange(this.part);

  /// The workbook part.
  final WorkbookPart part;

  @override
  void revert() => part.tableEdits--;

  @override
  void reapply() => part.tableEdits++;
}

/// The mark a row or column insert or delete leaves on the workbook:
/// [WorkbookPart.structureEdits] one higher while the edit is in force.
final class StructureEditChange implements Change {
  /// A change that raised the count of [part], already applied.
  StructureEditChange(this.part);

  /// The workbook part.
  final WorkbookPart part;

  @override
  void revert() => part.structureEdits--;

  @override
  void reapply() => part.structureEdits++;
}

/// Runs [edit], which changes the names of [part] through
/// [WorkbookPart.addName] or [WorkbookPart.removeName], and records the
/// change in [log] as a name edit, which makes the save ask Excel to
/// recalculate (`WorkbookPart.nameEdits`).
///
/// Must run inside `log.transaction`. If [edit] or recording throws, the
/// names are put back as they were before the error leaves.
void editNames(ChangeLog log, WorkbookPart part, void Function() edit) {
  final Object? before = part.element('definedNames');
  final int position = part.elementPosition(before);
  try {
    edit();
    final Object? after = part.element('definedNames');
    if (identical(before, after)) return;
    log.record(SetNamesChange(part, before, after, position: position));
    part.nameEdits++;
  } catch (_) {
    part.swapElement(
      'definedNames',
      part.element('definedNames'),
      before,
      position: position,
    );
    rethrow;
  }
}

/// The names of [part] in the scope of the sheet at tab index [scope] (the
/// workbook's when `null`) that are not built in, as public values.
List<XlsxDefinedName> definedNamesIn(WorkbookPart part, int? scope) =>
    List<XlsxDefinedName>.unmodifiable(<XlsxDefinedName>[
      for (final NameEntry e in part.names)
        if (!e.builtIn && e.localSheetId == scope) e.definedName,
    ]);

/// Defines [name] in the scope [scope] of [part], as `defineName` of the
/// workbook (`null`) and of a sheet (its tab index) do.
///
/// [checkNotTable] throws an [ArgumentError] when a table has the name.
/// Throws an [ArgumentError] as `checkDefinedName` does, naming the field;
/// nothing has changed then.
void defineNameIn(
  ChangeLog log,
  WorkbookPart part,
  int? scope,
  XlsxDefinedName name,
  void Function(String name) checkNotTable,
) {
  final XlsxDefinedName checked = checkDefinedName(
    name,
    definedNamesIn(part, scope),
  );
  checkNotTable(checked.name);
  final NameEntry entry = NameEntry(
    name: checked.name,
    formula: checked.formula,
    localSheetId: scope,
    hidden: checked.hidden,
    comment: checked.comment,
  );
  log.transaction(() {
    editNames(log, part, () => part.addName(entry));
  });
}

/// Removes the name [name] from the scope [scope] of [part], comparing
/// names ignoring case as Excel does.
///
/// Throws an [ArgumentError] named `name` when the scope has no such name
/// (a built-in name is none); nothing has changed then.
void removeNameIn(
  ChangeLog log,
  WorkbookPart part,
  int? scope,
  String name,
  String scopeName,
) {
  final String key = sheetNameKey(name);
  NameEntry? found;
  for (final NameEntry e in part.names) {
    if (!e.builtIn && e.localSheetId == scope && sheetNameKey(e.name) == key) {
      found = e;
      break;
    }
  }
  if (found == null) {
    throw ArgumentError.value(
      name,
      'name',
      'The name "$name" is not defined in $scopeName.',
    );
  }
  final NameEntry entry = found;
  log.transaction(() {
    editNames(log, part, () => part.removeName(entry));
  });
}

/// The `definedNames` holder of a workbook: each readable name's formula
/// goes through the rewriter, unqualified references read on the sheet of
/// the name's scope (on none for a workbook name). Excel's built-in names
/// are names too, so a print area shrinks with its rows and becomes
/// `S!#REF!`, as Excel writes it, when they are all deleted. A changed
/// name keeps its element but its text ([rewriteNameEntry]); a name that
/// cannot be read, or whose formula cannot be lexed, stays as read.
final class DefinedNameHolder implements ReferenceHolder {
  /// The holder of the names of the part [_part] gives, recording to [_log].
  DefinedNameHolder(this._log, this._part);

  final ChangeLog _log;
  final WorkbookPart Function() _part;

  @override
  String get holderName => 'definedNames';

  @override
  void shiftReferences(ReferenceMapper mapper, ReferenceShift? edit) {
    final WorkbookPart part = _part();
    if (!part.isTyped) return;
    final Object? group = part.element('definedNames');
    if (group is! ItemGroup<NameEntry>) return;
    final List<SheetEntry> sheets = part.sheets;
    bool changed = false;
    final List<GroupItem<NameEntry>> items = <GroupItem<NameEntry>>[
      for (final GroupItem<NameEntry> item in group.items)
        _shifted(item, mapper, sheets) ?? item,
    ];
    for (int i = 0; i < items.length; i++) {
      changed |= !identical(items[i], group.items[i]);
    }
    if (!changed) return;
    final ItemGroup<NameEntry> next = ItemGroup<NameEntry>(
      group.qualifiedName,
      group.localName,
      group.namespaces,
      group.attributes,
      items,
      edited: group.edited,
    );
    editNames(_log, part, () => part.swapElement('definedNames', group, next));
  }

  static GroupItem<NameEntry>? _shifted(
    GroupItem<NameEntry> item,
    ReferenceMapper mapper,
    List<SheetEntry> sheets,
  ) {
    final NameEntry? entry = item.value;
    if (entry == null) return null;
    final int? scope = entry.localSheetId;
    final String host = scope != null && scope < sheets.length
        ? sheets[scope].name
        : '';
    final String? formula = rewriteFormula(entry.formula, mapper, host);
    if (formula == null) return null;
    final NameEntry next = NameEntry(
      name: entry.name,
      formula: formula,
      localSheetId: entry.localSheetId,
      hidden: entry.hidden,
      comment: entry.comment,
    );
    return GroupItem<NameEntry>(
      next,
      rewriteNameEntry(item.source, entry, next),
      counted: item.counted,
    );
  }
}

/// Gives each name of [part] scoped to a sheet the tab index [map] gives
/// its sheet's index, after the sheets moved, recording the change in
/// [log]; a name whose index [map] leaves alone (`null`, or the same index),
/// or a name that cannot be read, stays as read.
///
/// A name stays on its sheet, so the change is not counted in
/// [WorkbookPart.nameEdits]. Must run inside `log.transaction`.
void remapNameScopes(ChangeLog log, WorkbookPart part, int? Function(int) map) {
  if (!part.isTyped) return;
  final Object? group = part.element('definedNames');
  if (group is! ItemGroup<NameEntry>) return;
  bool changed = false;
  final List<GroupItem<NameEntry>> items = <GroupItem<NameEntry>>[
    for (final GroupItem<NameEntry> item in group.items)
      if (item.value case final NameEntry entry?
          when entry.localSheetId != null &&
              map(entry.localSheetId!) != null &&
              map(entry.localSheetId!) != entry.localSheetId)
        () {
          changed = true;
          final NameEntry next = NameEntry(
            name: entry.name,
            formula: entry.formula,
            localSheetId: map(entry.localSheetId!),
            hidden: entry.hidden,
            comment: entry.comment,
          );
          return GroupItem<NameEntry>(
            next,
            rewriteNameEntry(item.source, entry, next),
            counted: item.counted,
          );
        }()
      else
        item,
  ];
  if (!changed) return;
  final ItemGroup<NameEntry> next = ItemGroup<NameEntry>(
    group.qualifiedName,
    group.localName,
    group.namespaces,
    group.attributes,
    items,
    edited: group.edited,
  );
  final int position = part.elementPosition(group);
  part.swapElement('definedNames', group, next);
  log.record(_ScopeChange(part, group, next, position));
}

/// The change of [remapNameScopes]: the `<definedNames>` before and after.
final class _ScopeChange implements Change {
  _ScopeChange(this.part, this.before, this.after, this.position);

  final WorkbookPart part;
  final Object before;
  final Object after;
  final int position;

  @override
  void revert() =>
      part.swapElement('definedNames', after, before, position: position);

  @override
  void reapply() => part.swapElement('definedNames', before, after);
}
