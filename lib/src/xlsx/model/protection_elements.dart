/// Reading and editing the `sheetProtection` and `workbookProtection`
/// elements as [XlsxSheetProtection] and [XlsxWorkbookProtection] values.
///
/// Not ported from Quds; written for jet_office.
///
/// A protection read from a file never shows its password: the file stores
/// a hash, and a hash is not a password, so `password` reads `null`
/// whatever the file holds (ruling R2). Writing a value with `password:
/// null` keeps the stored hash; writing a password replaces every hash
/// attribute of the element (`password`, `algorithmName`, `hashValue`,
/// `saltValue` and `spinCount`; for a workbook the same with the
/// `workbook` prefix, and not the `revisions...` ones, which protect the
/// shared-workbook revisions). Attributes the value types do not have
/// (`lockRevision`, `revisionsPassword`, ...) stay.
///
/// An attribute changes only when its meaning changes: the flag read from
/// the element is compared with the flag wanted, and an attribute whose
/// flag is equal keeps the spelling it has (`objects="0"`, `sheet="true"`).
/// A changed flag is written as the writer writes it, and dropped when it
/// is the schema default. A boolean may be `1`, `true`, `0` or `false`; any
/// other text reads as the attribute's default.
library;

import '../sheet_protection.dart';
import 'element_node.dart';

/// One permission of `sheetProtection`: its attribute, whether the schema
/// default is "locked", and the lock a value wants.
typedef _Lock = ({
  String attribute,
  bool defaultLocked,
  bool Function(XlsxSheetProtection) locked,
});

/// The permissions, in `CT_SheetProtection` order (the order the writer
/// writes them in). An XML flag is `1` when the action is locked.
final List<_Lock> _locks = <_Lock>[
  (
    attribute: 'objects',
    defaultLocked: false,
    locked: (XlsxSheetProtection p) => !p.allowEditObjects,
  ),
  (
    attribute: 'scenarios',
    defaultLocked: false,
    locked: (XlsxSheetProtection p) => !p.allowEditScenarios,
  ),
  (
    attribute: 'formatCells',
    defaultLocked: true,
    locked: (XlsxSheetProtection p) => !p.allowFormatCells,
  ),
  (
    attribute: 'formatColumns',
    defaultLocked: true,
    locked: (XlsxSheetProtection p) => !p.allowFormatColumns,
  ),
  (
    attribute: 'formatRows',
    defaultLocked: true,
    locked: (XlsxSheetProtection p) => !p.allowFormatRows,
  ),
  (
    attribute: 'insertColumns',
    defaultLocked: true,
    locked: (XlsxSheetProtection p) => !p.allowInsertColumns,
  ),
  (
    attribute: 'insertRows',
    defaultLocked: true,
    locked: (XlsxSheetProtection p) => !p.allowInsertRows,
  ),
  (
    attribute: 'insertHyperlinks',
    defaultLocked: true,
    locked: (XlsxSheetProtection p) => !p.allowInsertHyperlinks,
  ),
  (
    attribute: 'deleteColumns',
    defaultLocked: true,
    locked: (XlsxSheetProtection p) => !p.allowDeleteColumns,
  ),
  (
    attribute: 'deleteRows',
    defaultLocked: true,
    locked: (XlsxSheetProtection p) => !p.allowDeleteRows,
  ),
  (
    attribute: 'sort',
    defaultLocked: true,
    locked: (XlsxSheetProtection p) => !p.allowSort,
  ),
  (
    attribute: 'autoFilter',
    defaultLocked: true,
    locked: (XlsxSheetProtection p) => !p.allowAutoFilter,
  ),
  (
    attribute: 'pivotTables',
    defaultLocked: true,
    locked: (XlsxSheetProtection p) => !p.allowPivotTables,
  ),
  (
    attribute: 'selectLockedCells',
    defaultLocked: false,
    locked: (XlsxSheetProtection p) => !p.allowSelectLockedCells,
  ),
  (
    attribute: 'selectUnlockedCells',
    defaultLocked: false,
    locked: (XlsxSheetProtection p) => !p.allowSelectUnlockedCells,
  ),
];

/// The attributes that hold a sheet's password hash.
const List<String> _sheetHashAttributes = <String>[
  'password',
  'algorithmName',
  'hashValue',
  'saltValue',
  'spinCount',
];

/// The attributes that hold a workbook's password hash.
const List<String> _workbookHashAttributes = <String>[
  'workbookPassword',
  'workbookAlgorithmName',
  'workbookHashValue',
  'workbookSaltValue',
  'workbookSpinCount',
];

/// The boolean of [node]'s attribute [name], or [fallback] when it is
/// absent or not `1`, `true`, `0` or `false`.
bool _flag(XmlNode node, String name, bool fallback) =>
    switch (node.attribute(name)) {
      '1' || 'true' => true,
      '0' || 'false' => false,
      _ => fallback,
    };

/// Whether [node] has the attribute [name] with some text.
bool _has(XmlNode node, String name) => node.attribute(name) != null;

/// The protection [node], a `sheetProtection`, states, or `null` when its
/// `sheet` is absent or `0`: Excel does not protect the sheet then, and the
/// other attributes only wait.
///
/// The password reads `null`; see the library comment.
XlsxSheetProtection? readSheetProtection(XmlNode node) {
  if (!_flag(node, 'sheet', false)) return null;
  bool allow(String name, bool defaultLocked) =>
      !_flag(node, name, defaultLocked);
  return XlsxSheetProtection(
    allowSelectLockedCells: allow('selectLockedCells', false),
    allowSelectUnlockedCells: allow('selectUnlockedCells', false),
    allowFormatCells: allow('formatCells', true),
    allowFormatColumns: allow('formatColumns', true),
    allowFormatRows: allow('formatRows', true),
    allowInsertColumns: allow('insertColumns', true),
    allowInsertRows: allow('insertRows', true),
    allowInsertHyperlinks: allow('insertHyperlinks', true),
    allowDeleteColumns: allow('deleteColumns', true),
    allowDeleteRows: allow('deleteRows', true),
    allowSort: allow('sort', true),
    allowAutoFilter: allow('autoFilter', true),
    allowPivotTables: allow('pivotTables', true),
    allowEditObjects: allow('objects', false),
    allowEditScenarios: allow('scenarios', false),
  );
}

/// Whether [node], a `sheetProtection`, stores a password (`password` or
/// `hashValue`).
bool sheetHasStoredPassword(XmlNode node) =>
    _has(node, 'password') || _has(node, 'hashValue');

/// [node] (a `sheetProtection`, or `null` for none) made to state [value]:
/// a new element in the writer's form when [node] is `null`, else [node]
/// with the attributes whose meaning changes. [prefix] is the element's
/// prefix with its colon, or empty, for a new element.
///
/// Returns [node] itself when it already states [value] and [value] has no
/// password. The caller has checked the password.
XmlNode applySheetProtection(
  XmlNode? node,
  XlsxSheetProtection value,
  String prefix,
) {
  final String? password = value.password;
  if (node == null) {
    return XmlNode.made(
      prefix,
      'sheetProtection',
      attributes: <String, String>{
        if (password != null) 'password': legacyPasswordHash(password),
        'sheet': '1',
        for (final _Lock l in _locks)
          if (l.locked(value) != l.defaultLocked)
            l.attribute: l.locked(value) ? '1' : '0',
      },
    );
  }
  final Map<String, String?> changes = <String, String?>{
    if (password != null) ...<String, String?>{
      for (final String a in _sheetHashAttributes.skip(1)) a: null,
      'password': legacyPasswordHash(password),
    },
    if (!_flag(node, 'sheet', false)) 'sheet': '1',
    for (final _Lock l in _locks)
      if (_flag(node, l.attribute, l.defaultLocked) != l.locked(value))
        l.attribute: l.locked(value) == l.defaultLocked
            ? null
            : (l.locked(value) ? '1' : '0'),
  };
  return node.withChanges(changes);
}

/// The protection [node], a `workbookProtection`, states: its two locks,
/// with the password read as `null`.
XlsxWorkbookProtection readWorkbookProtection(XmlNode node) =>
    XlsxWorkbookProtection(
      lockStructure: _flag(node, 'lockStructure', false),
      lockWindows: _flag(node, 'lockWindows', false),
    );

/// Whether [node], a `workbookProtection`, stores a password
/// (`workbookPassword` or `workbookHashValue`).
bool workbookHasStoredPassword(XmlNode node) =>
    _has(node, 'workbookPassword') || _has(node, 'workbookHashValue');

/// [node] (a `workbookProtection`, or `null` for none) made to state
/// [value], or `null` when no element is left: [value] locks nothing, has
/// no password and [node] stores no hash, as the writer writes nothing for
/// such a protection.
///
/// A new element is the writer's; an existing one keeps the spelling of a
/// lock whose meaning does not change. The caller has checked the password.
XmlNode? applyWorkbookProtection(
  XmlNode? node,
  XlsxWorkbookProtection value,
  String prefix,
) {
  final String? password = value.password;
  if (node == null) {
    if (password == null && !value.lockStructure && !value.lockWindows) {
      return null;
    }
    return XmlNode.made(
      prefix,
      'workbookProtection',
      attributes: <String, String>{
        if (password != null) 'workbookPassword': legacyPasswordHash(password),
        if (value.lockStructure) 'lockStructure': '1',
        if (value.lockWindows) 'lockWindows': '1',
      },
    );
  }
  XmlNode lock(XmlNode n, String name, bool wanted) {
    if (_flag(n, name, false) == wanted) return n;
    return n.withChanges(<String, String?>{name: wanted ? '1' : null});
  }

  XmlNode next = lock(node, 'lockStructure', value.lockStructure);
  next = lock(next, 'lockWindows', value.lockWindows);
  if (password != null) {
    next = next.withChanges(<String, String?>{
      for (final String a in _workbookHashAttributes.skip(1)) a: null,
      'workbookPassword': legacyPasswordHash(password),
    });
  }
  if (!_flag(next, 'lockStructure', false) &&
      !_flag(next, 'lockWindows', false) &&
      !workbookHasStoredPassword(next)) {
    return null;
  }
  return next;
}
