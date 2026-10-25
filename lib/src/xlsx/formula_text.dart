/// The shared checks and builders for formula-typed text: defined names,
/// and the formulas of later features.
///
/// New in jet_office. Quds wrote formula text and sheet references by string
/// concatenation: print titles without `$` and without quoting the sheet
/// name, so a sheet named `My Sheet` produced a reference Excel refuses.
library;

import '../xml/xml_escape.dart';

/// The longest formula Excel accepts, in UTF-16 code units, counted after
/// the leading `=` is removed.
const int _maxFormulaLength = 8192;

/// Checks formula text and returns it as it is written: one leading `=`
/// removed.
///
/// [name] is the argument name the error reports. Throws [ArgumentError]
/// when the text is empty after the `=`, longer than 8,192 UTF-16 code
/// units, or holds a character XML forbids; silently dropping such a
/// character would change the formula's meaning. The result goes through
/// `escapeFormulaText` when it is written.
String checkFormulaText(String text, String name) {
  final String stripped = text.startsWith('=') ? text.substring(1) : text;
  if (stripped.isEmpty) {
    throw ArgumentError.value(text, name, 'A formula must not be empty.');
  }
  if (stripped.length > _maxFormulaLength) {
    throw ArgumentError.value(
      '${stripped.length} characters',
      name,
      'A formula has at most $_maxFormulaLength characters.',
    );
  }
  if (scrubXmlText(stripped).removed > 0) {
    throw ArgumentError.value(
      text,
      name,
      'A formula must not contain characters XML forbids.',
    );
  }
  return stripped;
}

/// Formula text that registration has checked, as it is written: one
/// leading `=` removed, nothing else.
///
/// Write paths use this instead of [checkFormulaText], so text that slipped
/// past registration cannot make writing throw and leave the writer dead.
/// An assertion confirms in debug builds that the text is valid.
String writtenFormulaText(String text) {
  assert(_isValidFormula(text), 'Unchecked formula text: "$text".');
  return text.startsWith('=') ? text.substring(1) : text;
}

bool _isValidFormula(String text) {
  try {
    checkFormulaText(text, 'text');
    return true;
  } on ArgumentError {
    return false;
  }
}

/// The reference [ref] on the sheet [sheetName], as `'<name>'!<ref>`.
///
/// The name is always quoted, with each `'` doubled, so it needs no test
/// for spaces, digits or look-alikes of a cell reference. The caller
/// escapes the whole formula once with `escapeFormulaText`; this function
/// does not escape `_xHHHH_`.
String quotedSheetRef(String sheetName, String ref) =>
    "'${sheetName.replaceAll("'", "''")}'!$ref";
