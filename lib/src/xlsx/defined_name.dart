/// [XlsxDefinedName], a named formula, and the checks the writer applies when
/// one is registered.
///
/// New in jet_office. Quds could write no defined names except its print
/// titles; names are the one way to give a formula, constant or range a name
/// that survives in the file.
library;

import '../xml/xml_escape.dart';
import 'formula_text.dart';
import 'limits.dart';
import 'sheet_name.dart';

/// A defined name: [name] stands for [formula] wherever a formula can use
/// it.
///
/// Whether it is workbook-wide or belongs to one sheet depends on where it
/// is registered: `defineName` of the writer defines it for the workbook,
/// `defineName` of a sheet for that sheet only. The `const` constructor
/// checks nothing; the writer does when the name is registered and throws
/// [ArgumentError] naming the field.
final class XlsxDefinedName {
  /// A name [name] for [formula].
  ///
  /// [formula] is a formula without or with its leading `=`: `0.18`,
  /// `Data!$B$2` or `SUM(Data!$A:$A)`. A sheet in it is spelled as Excel
  /// does, quoted when its name needs it. [hidden] keeps the name out of
  /// Excel's Name Manager; [comment] is shown there.
  const XlsxDefinedName(
    this.name,
    this.formula, {
    this.hidden = false,
    this.comment,
  });

  /// The name: a letter, `_` or `\` followed by letters, digits, `_`, `.`
  /// or `\`; at most [XlsxLimits.maxDefinedNameLength] characters; not a
  /// cell reference such as `A1` or `R1C1`, and not `R` or `C`; not
  /// starting with `_xlnm.`, which Excel reserves; and not `Print_Area`,
  /// `Print_Titles` or `_FilterDatabase` in any case, the built-in names
  /// that a sheet's `printArea`, `printTitles` and `autoFilter` write.
  final String name;

  /// The formula the name stands for.
  final String formula;

  /// Whether Excel hides the name in its Name Manager.
  final bool hidden;

  /// A comment shown in the Name Manager, at most
  /// [XlsxLimits.maxDefinedNameCommentLength] characters.
  final String? comment;

  @override
  bool operator ==(Object other) =>
      other is XlsxDefinedName &&
      other.name == name &&
      other.formula == formula &&
      other.hidden == hidden &&
      other.comment == comment;

  @override
  int get hashCode => Object.hash(name, formula, hidden, comment);

  @override
  String toString() =>
      'XlsxDefinedName($name, $formula'
      '${hidden ? ', hidden: true' : ''}'
      '${comment == null ? '' : ', comment: $comment'})';
}

/// The spellings of Excel's built-in names without their `_xlnm.` prefix,
/// keyed by [sheetNameKey], each with the sheet setting that writes it.
/// Excel reads a user name with such a spelling as the built-in.
final Map<String, String> _builtInSettings = <String, String>{
  sheetNameKey('Print_Area'): 'printArea',
  sheetNameKey('Print_Titles'): 'printTitles',
  sheetNameKey('_FilterDatabase'): 'autoFilter',
};

final RegExp _nameShape = RegExp(
  r'^[\p{L}_\\][\p{L}\p{N}_.\\]*$',
  unicode: true,
);
final RegExp _a1Shape = RegExp(r'^([A-Za-z]{1,3})([0-9]+)$');
final RegExp _r1c1Shape = RegExp(r'^[Rr][0-9]*[Cc][0-9]*$');

/// Whether [name] reads as an A1 cell reference inside the sheet, `XFD1048576`
/// at most. `XFE1` and `A1048577` are outside it and so allowed.
bool _isCellReference(String name) {
  final RegExpMatch? m = _a1Shape.firstMatch(name);
  if (m == null) return false;
  int column = 0;
  for (final int unit in m.group(1)!.toUpperCase().codeUnits) {
    column = column * 26 + (unit - 64);
  }
  if (column > XlsxLimits.maxColumns) return false;
  final String digits = m.group(2)!.replaceFirst(RegExp('^0+'), '');
  if (digits.isEmpty || digits.length > 7) return false;
  final int row = int.parse(digits);
  return row >= 1 && row <= XlsxLimits.maxRows;
}

/// Checks the shape of [name], a defined name or, when [table] is `true`,
/// a table name, and throws [ArgumentError] named [field] when it is wrong.
///
/// A name is not empty, at most [XlsxLimits.maxDefinedNameLength] UTF-16
/// code units ([XlsxLimits.maxTableNameLength] for a table), starts with a
/// letter, `_` or `\` and continues with letters, digits, `_`, `.` or `\`;
/// it does not start with `_xlnm.`, is not one of Excel's built-in names
/// (`Print_Area`, `Print_Titles`, `_FilterDatabase`, in any case), is not
/// `R` or `C` and does not look like a cell reference (`A1`, `R1C1`). The
/// message for a built-in name points a defined name at the sheet setting
/// it stands for; a table only hears that the name is reserved. Whether
/// the name is taken is checked elsewhere.
void checkNameSyntax(String name, String field, {bool table = false}) {
  if (name.isEmpty) {
    throw ArgumentError.value(name, field, 'A name must not be empty.');
  }
  final int maxLength = table
      ? XlsxLimits.maxTableNameLength
      : XlsxLimits.maxDefinedNameLength;
  if (name.length > maxLength) {
    throw ArgumentError.value(
      '${name.length} characters',
      field,
      table
          ? 'A table name has at most $maxLength characters.'
          : 'A name has at most $maxLength characters.',
    );
  }
  if (!_nameShape.hasMatch(name)) {
    throw ArgumentError.value(
      name,
      field,
      'A name starts with a letter, "_" or "\\" and continues with letters, '
      'digits, "_", "." or "\\".',
    );
  }
  if (name.toLowerCase().startsWith('_xlnm.')) {
    throw ArgumentError.value(
      name,
      field,
      'Names starting with "_xlnm." are reserved for Excel.',
    );
  }
  final String? setting = _builtInSettings[sheetNameKey(name)];
  if (setting != null) {
    throw ArgumentError.value(
      name,
      field,
      table
          ? '"$name" is a built-in name Excel reserves; a table cannot take '
                'it.'
          : '"$name" is the name of an Excel built-in; use the sheet\'s '
                '$setting instead.',
    );
  }
  if (name.length == 1 && 'RrCc'.contains(name)) {
    throw ArgumentError.value(name, field, 'R and C are not valid names.');
  }
  if (_isCellReference(name) || _r1c1Shape.hasMatch(name)) {
    throw ArgumentError.value(
      name,
      field,
      'A name must not look like a cell reference.',
    );
  }
}

/// Checks [definedName] and returns it with its formula as it is written
/// (the leading `=` removed).
///
/// [earlier] are the names already registered in the same scope; a name
/// that [sheetNameKey] folds to the same key as one of them is a duplicate.
/// Throws [ArgumentError] naming `name`, `formula` or `comment`, and the
/// duplicate message names both spellings. The name's shape is checked by
/// [checkNameSyntax].
XlsxDefinedName checkDefinedName(
  XlsxDefinedName definedName,
  Iterable<XlsxDefinedName> earlier,
) {
  final String name = definedName.name;
  checkNameSyntax(name, 'name');
  final String formula = checkFormulaText(definedName.formula, 'formula');
  final String? comment = definedName.comment;
  if (comment != null) {
    if (comment.length > XlsxLimits.maxDefinedNameCommentLength) {
      throw ArgumentError.value(
        '${comment.length} characters',
        'comment',
        'A comment has at most '
            '${XlsxLimits.maxDefinedNameCommentLength} characters.',
      );
    }
    if (scrubXmlText(comment).removed > 0) {
      throw ArgumentError.value(
        comment,
        'comment',
        'A comment must not contain characters XML forbids.',
      );
    }
  }
  final String key = sheetNameKey(name);
  for (final XlsxDefinedName other in earlier) {
    if (sheetNameKey(other.name) == key) {
      throw ArgumentError.value(
        name,
        'name',
        'The name "$name" is already defined as "${other.name}" in this '
            'scope; names are compared ignoring case.',
      );
    }
  }
  return XlsxDefinedName(
    name,
    formula,
    hidden: definedName.hidden,
    comment: comment,
  );
}
