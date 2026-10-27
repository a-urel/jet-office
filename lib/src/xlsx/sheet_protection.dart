/// [XlsxSheetProtection] and [XlsxWorkbookProtection], their password hash,
/// their registration checks and their `sheetProtection` and
/// `workbookProtection` XML.
///
/// Ported from quds_office_engine `lib/src/sheet/serial/sheet_serial.dart` at commit 15c5d29.
/// Ported: the sheet-protection writer, which wrote `<sheetProtection
/// sheet="1"/>` after `autoFilter` with no options and no password. What
/// changed: the element follows `sheetData` and precedes `autoFilter`, as
/// `CT_Worksheet` orders it; every permission of `CT_SheetProtection` is a
/// field named for what the user may do (the XML flags are inverted); a
/// password is hashed with the legacy ECMA-376 algorithm; and
/// `workbookProtection` is new. Attributes are written in `CT_SheetProtection`
/// order, only those that differ from the schema defaults, except `sheet`.
///
/// Protection is not security. The legacy hash is 16 bits wide and is broken
/// in seconds, and the workbook is not encrypted; the password only keeps an
/// honest user from changing what is locked by accident.
library;

import '../xml/xml_writer.dart';

/// The longest password the legacy hash covers, in characters.
const int _maxPasswordLength = 15;

/// The legacy password hash of ECMA-376 Part 4, 14.7.1 (MS-OFFCRYPTO
/// "Method 1"): four uppercase hexadecimal digits.
///
/// Every character at 1-based position `i` contributes its code unit shifted
/// left by `i`, rotated within 15 bits; the result is mixed with the length
/// and the constant `0xCE4B`. [password] is not checked here: see
/// [checkProtectionPassword].
String legacyPasswordHash(String password) {
  int hash = 0;
  for (int i = 1; i <= password.length; i++) {
    final int v = password.codeUnitAt(i - 1) << i;
    hash ^= (v & 0x7FFF) | (v >> 15);
  }
  hash ^= password.length;
  hash ^= 0xCE4B;
  return hash.toRadixString(16).toUpperCase().padLeft(4, '0');
}

/// Checks that [password] is 1 to 15 characters from U+0020 to U+007E, or
/// throws [ArgumentError] naming `password`.
///
/// The legacy hash covers 15 characters, and the code page of any other
/// character is undefined, so the text is not allowed rather than hashed
/// differently by different readers. The message never repeats the password.
void checkProtectionPassword(String? password) {
  if (password == null) return;
  final bool ok =
      password.isNotEmpty &&
      password.length <= _maxPasswordLength &&
      password.codeUnits.every((int c) => c >= 0x20 && c <= 0x7E);
  if (!ok) {
    throw ArgumentError.value(
      '***',
      'password',
      'A protection password is 1 to $_maxPasswordLength characters from '
          'U+0020 to U+007E.',
    );
  }
}

/// What a protected worksheet still allows, and the password that lifts the
/// protection.
///
/// Every `allow` field is named for what the user may do. The XML attribute
/// of each (`CT_SheetProtection`) has the opposite meaning: it is `1` when
/// the action is locked. A protection is written with `sheet="1"`, which
/// switches it on; only cells whose `XlsxProtection.locked` is not `false`
/// are then locked.
///
/// Protection is not security: the legacy password hash is 16 bits wide
/// and the workbook is not encrypted, so the password only keeps an honest
/// user from changing what is locked by accident. The password is compared
/// by `==` but never printed by [toString].
final class XlsxSheetProtection {
  /// Creates a protection; the defaults are Excel's: select cells, nothing
  /// else.
  const XlsxSheetProtection({
    this.password,
    this.allowSelectLockedCells = true,
    this.allowSelectUnlockedCells = true,
    this.allowFormatCells = false,
    this.allowFormatColumns = false,
    this.allowFormatRows = false,
    this.allowInsertColumns = false,
    this.allowInsertRows = false,
    this.allowInsertHyperlinks = false,
    this.allowDeleteColumns = false,
    this.allowDeleteRows = false,
    this.allowSort = false,
    this.allowAutoFilter = false,
    this.allowPivotTables = false,
    this.allowEditObjects = false,
    this.allowEditScenarios = false,
  });

  /// The password that unprotects the sheet, 1 to 15 characters from U+0020
  /// to U+007E, or `null` for none. XML `password`, the legacy hash.
  final String? password;

  /// Whether locked cells can be selected. XML `selectLockedCells`, `1` when
  /// not allowed.
  final bool allowSelectLockedCells;

  /// Whether unlocked cells can be selected. XML `selectUnlockedCells`, `1`
  /// when not allowed.
  final bool allowSelectUnlockedCells;

  /// Whether cells can be formatted. XML `formatCells`, `0` when allowed.
  final bool allowFormatCells;

  /// Whether columns can be formatted (width, hiding). XML `formatColumns`,
  /// `0` when allowed.
  final bool allowFormatColumns;

  /// Whether rows can be formatted (height, hiding). XML `formatRows`, `0`
  /// when allowed.
  final bool allowFormatRows;

  /// Whether columns can be inserted. XML `insertColumns`, `0` when allowed.
  final bool allowInsertColumns;

  /// Whether rows can be inserted. XML `insertRows`, `0` when allowed.
  final bool allowInsertRows;

  /// Whether hyperlinks can be inserted. XML `insertHyperlinks`, `0` when
  /// allowed.
  final bool allowInsertHyperlinks;

  /// Whether columns can be deleted. XML `deleteColumns`, `0` when allowed.
  final bool allowDeleteColumns;

  /// Whether rows can be deleted. XML `deleteRows`, `0` when allowed.
  final bool allowDeleteRows;

  /// Whether the unlocked cells of a range can be sorted. XML `sort`, `0`
  /// when allowed.
  final bool allowSort;

  /// Whether an auto filter can be used. XML `autoFilter`, `0` when allowed.
  final bool allowAutoFilter;

  /// Whether pivot tables can be used. XML `pivotTables`, `0` when allowed.
  final bool allowPivotTables;

  /// Whether objects can be edited. XML `objects`, `1` when not allowed.
  final bool allowEditObjects;

  /// Whether scenarios can be edited. XML `scenarios`, `1` when not allowed.
  final bool allowEditScenarios;

  List<Object?> get _fields => <Object?>[
    password,
    allowSelectLockedCells,
    allowSelectUnlockedCells,
    allowFormatCells,
    allowFormatColumns,
    allowFormatRows,
    allowInsertColumns,
    allowInsertRows,
    allowInsertHyperlinks,
    allowDeleteColumns,
    allowDeleteRows,
    allowSort,
    allowAutoFilter,
    allowPivotTables,
    allowEditObjects,
    allowEditScenarios,
  ];

  @override
  bool operator ==(Object other) {
    if (other is! XlsxSheetProtection) return false;
    final List<Object?> a = _fields;
    final List<Object?> b = other._fields;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_fields);

  @override
  String toString() =>
      'XlsxSheetProtection(password: ${password == null ? 'none' : '***'}, '
      'allowSelectLockedCells: $allowSelectLockedCells, '
      'allowSelectUnlockedCells: $allowSelectUnlockedCells, '
      'allowFormatCells: $allowFormatCells, '
      'allowFormatColumns: $allowFormatColumns, '
      'allowFormatRows: $allowFormatRows, '
      'allowInsertColumns: $allowInsertColumns, '
      'allowInsertRows: $allowInsertRows, '
      'allowInsertHyperlinks: $allowInsertHyperlinks, '
      'allowDeleteColumns: $allowDeleteColumns, '
      'allowDeleteRows: $allowDeleteRows, '
      'allowSort: $allowSort, '
      'allowAutoFilter: $allowAutoFilter, '
      'allowPivotTables: $allowPivotTables, '
      'allowEditObjects: $allowEditObjects, '
      'allowEditScenarios: $allowEditScenarios)';
}

/// What a protected workbook locks, and the password that lifts it.
///
/// XML `workbookProtection`. [lockStructure] stops users from adding,
/// deleting, hiding, unhiding and renaming sheets; [lockWindows] stops them
/// from moving and resizing the workbook window. Protection is not
/// security, as [XlsxSheetProtection] explains. The password is compared by
/// `==` but never printed by [toString].
final class XlsxWorkbookProtection {
  /// Creates a protection; by default it locks the structure only.
  const XlsxWorkbookProtection({
    this.password,
    this.lockStructure = true,
    this.lockWindows = false,
  });

  /// The password that unprotects the workbook, 1 to 15 characters from
  /// U+0020 to U+007E, or `null` for none. XML `workbookPassword`, the
  /// legacy hash.
  final String? password;

  /// Whether sheets cannot be added, deleted, hidden, unhidden or renamed.
  /// XML `lockStructure`.
  final bool lockStructure;

  /// Whether the workbook window cannot be moved or resized. XML
  /// `lockWindows`.
  final bool lockWindows;

  @override
  bool operator ==(Object other) =>
      other is XlsxWorkbookProtection &&
      other.password == password &&
      other.lockStructure == lockStructure &&
      other.lockWindows == lockWindows;

  @override
  int get hashCode => Object.hash(password, lockStructure, lockWindows);

  @override
  String toString() =>
      'XlsxWorkbookProtection(password: ${password == null ? 'none' : '***'}, '
      'lockStructure: $lockStructure, lockWindows: $lockWindows)';
}

/// Writes `sheetProtection` for [p]: its attributes in `CT_SheetProtection`
/// order, `sheet` always, the others only when they differ from the schema
/// default.
void writeSheetProtection(XmlWriter w, XlsxSheetProtection p) {
  final String? password = p.password;
  // The schema defaults are false for `sheet`, `objects`, `scenarios` and
  // the two select flags, and true for the other permissions.
  w.empty('sheetProtection', <String, String>{
    if (password != null) 'password': legacyPasswordHash(password),
    'sheet': '1',
    if (!p.allowEditObjects) 'objects': '1',
    if (!p.allowEditScenarios) 'scenarios': '1',
    if (p.allowFormatCells) 'formatCells': '0',
    if (p.allowFormatColumns) 'formatColumns': '0',
    if (p.allowFormatRows) 'formatRows': '0',
    if (p.allowInsertColumns) 'insertColumns': '0',
    if (p.allowInsertRows) 'insertRows': '0',
    if (p.allowInsertHyperlinks) 'insertHyperlinks': '0',
    if (p.allowDeleteColumns) 'deleteColumns': '0',
    if (p.allowDeleteRows) 'deleteRows': '0',
    if (p.allowSort) 'sort': '0',
    if (p.allowAutoFilter) 'autoFilter': '0',
    if (p.allowPivotTables) 'pivotTables': '0',
    if (!p.allowSelectLockedCells) 'selectLockedCells': '1',
    if (!p.allowSelectUnlockedCells) 'selectUnlockedCells': '1',
  });
}

/// Writes `workbookProtection` for [p], or nothing when it has no password
/// and locks nothing.
void writeWorkbookProtection(XmlWriter w, XlsxWorkbookProtection p) {
  final String? password = p.password;
  if (password == null && !p.lockStructure && !p.lockWindows) return;
  w.empty('workbookProtection', <String, String>{
    if (password != null) 'workbookPassword': legacyPasswordHash(password),
    if (p.lockStructure) 'lockStructure': '1',
    if (p.lockWindows) 'lockWindows': '1',
  });
}
