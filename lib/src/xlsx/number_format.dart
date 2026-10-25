/// Number formats for cells.
///
/// New in jet_office; Quds passes number format codes around as plain
/// strings. The idea of registering custom codes from id 164 is ported in
/// `style_registry.dart`.
library;

import '../xml/xml_escape.dart';

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

  /// Whole numbers, `0` (built-in id 1).
  static const XlsxNumFmt integer = XlsxNumFmt.builtin(1);

  /// Two decimals, `0.00` (built-in id 2).
  static const XlsxNumFmt decimal2 = XlsxNumFmt.builtin(2);

  /// Whole numbers with thousands grouping, `#,##0` (built-in id 3).
  static const XlsxNumFmt thousands = XlsxNumFmt.builtin(3);

  /// Two decimals with thousands grouping, `#,##0.00` (built-in id 4).
  static const XlsxNumFmt thousands2 = XlsxNumFmt.builtin(4);

  /// Scientific notation, `0.00E+00` (built-in id 11).
  static const XlsxNumFmt scientific = XlsxNumFmt.builtin(11);

  /// A fraction, `# ?/?` (built-in id 12).
  static const XlsxNumFmt fraction = XlsxNumFmt.builtin(12);

  /// A time of day, `h:mm:ss` (built-in id 21).
  static const XlsxNumFmt time = XlsxNumFmt.builtin(21);

  /// Elapsed time, `[h]:mm:ss` (built-in id 46).
  static const XlsxNumFmt elapsedTime = XlsxNumFmt.builtin(46);

  /// Text, `@` (built-in id 49).
  static const XlsxNumFmt text = XlsxNumFmt.builtin(49);

  /// The `General` format (built-in id 0).
  static const XlsxNumFmt general = XlsxNumFmt.builtin(0);

  /// The locale's short date format (built-in id 14).
  static const XlsxNumFmt localeShortDate = XlsxNumFmt.builtin(14);

  /// The locale's date and time format (built-in id 22).
  static const XlsxNumFmt localeDateTime = XlsxNumFmt.builtin(22);

  /// A number with [decimals] decimal places (`0..30`), optionally with
  /// thousands [grouping] and with negative numbers in red.
  ///
  /// Returns the matching built-in format when there is one. Throws
  /// [ArgumentError] when [decimals] is outside `0..30`.
  factory XlsxNumFmt.number({
    int decimals = 0,
    bool grouping = false,
    bool negativeRed = false,
  }) {
    final String body = _body(decimals, grouping);
    if (!negativeRed) {
      final XlsxNumFmt? builtin = _builtinFor(body);
      if (builtin != null) return builtin;
    }
    return XlsxNumFmt.custom(_withNegative(body, negativeRed));
  }

  /// A percentage with [decimals] decimal places (`0..30`).
  ///
  /// `0%` and `0.00%` are the built-in ids 9 and 10. Throws [ArgumentError]
  /// when [decimals] is outside `0..30`.
  factory XlsxNumFmt.percent({int decimals = 0}) {
    final String code = '${_body(decimals, false)}%';
    return _builtinFor(code) ?? XlsxNumFmt.custom(code);
  }

  /// A money amount with thousands grouping and [decimals] decimal places
  /// (`0..30`, default 2), with an optional currency [symbol].
  ///
  /// The symbol is quoted and follows the number after a space, or precedes
  /// it when [symbolFirst] is set. Throws [ArgumentError] when [decimals]
  /// is outside `0..30`, or when [symbol] contains `"` or a character XML
  /// cannot carry.
  factory XlsxNumFmt.money({
    String symbol = '',
    bool symbolFirst = false,
    int decimals = 2,
    bool negativeRed = false,
  }) {
    if (symbol.contains('"')) {
      throw ArgumentError.value(symbol, 'symbol', 'must not contain "');
    }
    if (scrubXmlText(symbol).removed > 0) {
      throw ArgumentError.value(
        symbol,
        'symbol',
        'contains characters XML cannot carry',
      );
    }
    final String body = _body(decimals, true);
    final String shown = symbol.isEmpty
        ? body
        : symbolFirst
        ? '"$symbol"$body'
        : '$body" $symbol"';
    if (symbol.isEmpty && !negativeRed) {
      final XlsxNumFmt? builtin = _builtinFor(body);
      if (builtin != null) return builtin;
    }
    return XlsxNumFmt.custom(_withNegative(shown, negativeRed));
  }

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

String _body(int decimals, bool grouping) {
  if (decimals < 0 || decimals > 30) {
    throw ArgumentError.value(decimals, 'decimals', 'must be in 0..30');
  }
  final String integerPart = grouping ? '#,##0' : '0';
  return decimals == 0 ? integerPart : '$integerPart.${'0' * decimals}';
}

String _withNegative(String positive, bool negativeRed) =>
    negativeRed ? '$positive;[Red]-$positive' : positive;

XlsxNumFmt? _builtinFor(String code) => switch (code) {
  '0' => XlsxNumFmt.integer,
  '0.00' => XlsxNumFmt.decimal2,
  '#,##0' => XlsxNumFmt.thousands,
  '#,##0.00' => XlsxNumFmt.thousands2,
  '0%' => const XlsxNumFmt.builtin(9),
  '0.00%' => const XlsxNumFmt.builtin(10),
  _ => null,
};

/// Whether [format] shows dates or times.
///
/// Built-in ids 14 to 22 and 45 to 47 are date formats. A custom code is one
/// when a single left-to-right scan finds any of `d m y h s` outside quoted
/// literals (`"..."`), backslash escapes, the character after `_` (a space
/// as wide as it) or `*` (it repeated to fill the cell), `[...]` sections,
/// the word `General` and the markers `AM/PM` and `A/P` (each in any case).
/// An unterminated quote or bracket ends the scan. So `AM/PM` alone, `0_d`
/// and `0*d` are not dates, while `h AM/PM` is.
bool isDateFormat(XlsxNumFmt format) {
  final int? id = format.builtinId;
  if (id != null) {
    return (id >= 14 && id <= 22) || (id >= 45 && id <= 47);
  }
  final String code = format.code!;
  var i = 0;
  while (i < code.length) {
    final String c = code[i];
    if (c == '"') {
      final int close = code.indexOf('"', i + 1);
      if (close < 0) return false;
      i = close + 1;
    } else if (c == r'\' || c == '_' || c == '*') {
      // The next character is a literal, a width or a fill; a lone one at
      // the end is skipped harmlessly.
      i += 2;
    } else if (c == '[') {
      final int close = code.indexOf(']', i + 1);
      if (close < 0) return false;
      i = close + 1;
    } else if (_isWordAt(code, i, _generalWord)) {
      i += _generalWord.length;
    } else if (_isWordAt(code, i, _amPm)) {
      i += _amPm.length;
    } else if (_isWordAt(code, i, _aP)) {
      i += _aP.length;
    } else if ('dmyhsDMYHS'.contains(c)) {
      return true;
    } else {
      i++;
    }
  }
  return false;
}

const String _generalWord = 'general';
const String _amPm = 'am/pm';
const String _aP = 'a/p';

/// Whether [code] holds the lowercase [word] at [i], in any case.
bool _isWordAt(String code, int i, String word) =>
    i + word.length <= code.length &&
    code.substring(i, i + word.length).toLowerCase() == word;
