/// Number formats for cells.
///
/// New in jet_office; Quds passes number format codes around as plain
/// strings. The idea of registering custom codes from id 164 is ported in
/// `style_registry.dart`.
library;

/// A number format: either one of Excel's built-in formats, identified by
/// id, or a custom format code.
///
/// Values are compared by id or by code. Whether a built-in id or a custom
/// code is acceptable is checked when the format is registered, so a
/// constant can be declared without running any validation.
final class XlsxNumFmt {
  /// A built-in format with the given [id] (valid ids are `0..163`).
  const XlsxNumFmt.builtin(int id) : builtinId = id, code = null;

  /// A custom format with the given format [code], such as `0.000` or
  /// `dd.mm.yyyy`. The code must be non-empty and free of characters XML
  /// cannot carry.
  const XlsxNumFmt.custom(String this.code) : builtinId = null;

  /// The `General` format (built-in id 0).
  static const XlsxNumFmt general = XlsxNumFmt.builtin(0);

  /// The locale's short date format (built-in id 14).
  static const XlsxNumFmt localeShortDate = XlsxNumFmt.builtin(14);

  /// The locale's date and time format (built-in id 22).
  static const XlsxNumFmt localeDateTime = XlsxNumFmt.builtin(22);

  /// The built-in id, or `null` for a custom format.
  final int? builtinId;

  /// The custom format code, or `null` for a built-in format.
  final String? code;

  @override
  bool operator ==(Object other) =>
      other is XlsxNumFmt && other.builtinId == builtinId && other.code == code;

  @override
  int get hashCode => Object.hash(builtinId, code);

  @override
  String toString() => code == null
      ? 'XlsxNumFmt.builtin($builtinId)'
      : 'XlsxNumFmt.custom($code)';
}

final RegExp _quoted = RegExp(r'"[^"]*"');
final RegExp _bracketed = RegExp(r'\[[^\]]*\]');
final RegExp _escaped = RegExp(r'\\.', dotAll: true);
final RegExp _general = RegExp('general', caseSensitive: false);
final RegExp _dateLetters = RegExp('[dmyhs]', caseSensitive: false);

/// Whether [format] shows dates or times.
///
/// Built-in ids 14 to 22 and 45 to 47 are date formats. A custom code is one
/// when, after removing quoted literals, `[...]` sections, backslash escapes
/// and the word `General`, it still contains any of `d m y h s`.
bool isDateFormat(XlsxNumFmt format) {
  final int? id = format.builtinId;
  if (id != null) {
    return (id >= 14 && id <= 22) || (id >= 45 && id <= 47);
  }
  final String stripped = format.code!
      .replaceAll(_quoted, '')
      .replaceAll(_bracketed, '')
      .replaceAll(_escaped, '')
      .replaceAll(_general, '');
  return _dateLetters.hasMatch(stripped);
}
