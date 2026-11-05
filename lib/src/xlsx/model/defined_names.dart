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
import '../sheet_name.dart';
import '../workbook_parts.dart' show writeDefinedName;
import 'item_group.dart';
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

/// [entry] as the writer writes a `<definedName>`.
OpaqueXml renderNameEntry(NameEntry entry) => renderElements(
  (XmlWriter w) => writeDefinedName(
    w,
    entry.name,
    entry.localSheetId,
    entry.formula,
    hidden: entry.hidden,
    comment: entry.comment,
  ),
).single;

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
