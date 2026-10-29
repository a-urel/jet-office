/// The one tokenizer of number format codes.
///
/// New in jet_office; Quds has no number format engine. [parseFormatCode]
/// splits a code such as `#,##0.00;[Red]-#,##0.00` into sections and each
/// section into tokens, in one left-to-right scan with no regular
/// expression. The classifier and the renderers read its output; nothing
/// else in the library interprets a format code.
library;

import 'excel_number.dart';

/// Parses the number format [code] into its sections and tokens.
///
/// Sections are separated by `;` outside quoted literals (`"..."`), the
/// character after `\`, `_` or `*`, and `[...]` brackets. The scan skips
/// exactly what the reader's classifier skips, so the classifier can be
/// rebuilt on the result for any code.
///
/// The result always holds every section and token the scan saw, even when
/// [ParsedFormat.invalidReason] is set (more than four sections, a third
/// condition, an unknown `[ColorN]`, a code longer than 255 characters, or
/// one of the codes Excel for Mac repairs to `General` on opening: a
/// lowercase `e+` or `e-` exponent, a fixed denominator of ten or more
/// digits, `@` in more than one section, or two `[$…-…]` locale tags in one
/// section).
/// Only an unterminated quote or bracket ends the scan early, which sets
/// [ParsedFormat.truncated]. This never throws, and its time is linear in
/// the length of [code].
ParsedFormat parseFormatCode(String code) => _Parser(code).parse();

/// The longest code Excel accepts.
const int _maxCodeLength = 255;

/// A number format code split into sections and tokens.
final class ParsedFormat {
  /// Creates a parsed code; [parseFormatCode] is the way to get one.
  ParsedFormat(
    List<FormatSection> sections, {
    this.invalidReason,
    this.truncated = false,
  }) : sections = List<FormatSection>.unmodifiable(sections);

  /// The sections in the order written: one to four when the code is
  /// valid, and at least one always.
  final List<FormatSection> sections;

  /// Why the code is invalid, in English for diagnostics, or null. An
  /// invalid code renders as `General`.
  final String? invalidReason;

  /// Whether an unterminated quote or bracket ended the code early.
  ///
  /// The tokens before it are kept; the rest of the code is not scanned.
  final bool truncated;

  @override
  String toString() =>
      'ParsedFormat($sections, invalidReason: $invalidReason, '
      'truncated: $truncated)';
}

/// One `;`-separated section of a number format code.
final class FormatSection {
  /// Creates a section of [tokens] with an optional [condition] and
  /// [color].
  FormatSection(List<FormatToken> tokens, {this.condition, this.color})
    : tokens = List<FormatToken>.unmodifiable(tokens);

  /// The tokens in the order written, without the condition and the color.
  final List<FormatToken> tokens;

  /// The section's condition, such as `[>100]`, or null.
  final FormatCondition? condition;

  /// The section's color, such as `[Red]` or `[Color12]`, or null.
  final FormatColor? color;

  /// Whether the section holds an `@` text placeholder.
  bool get hasText => tokens.any((FormatToken t) => t is TextToken);

  /// Whether the section holds the word `General`.
  bool get hasGeneral => tokens.any((FormatToken t) => t is GeneralToken);

  /// Whether the section holds a digit placeholder `0`, `#` or `?`.
  bool get hasDigits => tokens.any((FormatToken t) => t is DigitToken);

  /// Whether the section holds a date or time token, elapsed or not, an
  /// AM/PM marker, fractional seconds or a system date or time tag.
  bool get hasDateTime => tokens.any(
    (FormatToken t) =>
        t is DateToken ||
        t is AmPmToken ||
        t is FractionalSecondsToken ||
        t is SystemFormatToken,
  );

  @override
  String toString() =>
      'FormatSection($tokens, condition: $condition, color: $color)';
}

/// A section condition such as `[>100]` or `[<=-1.5]`.
final class FormatCondition {
  /// Creates a condition comparing with [op] against [value].
  const FormatCondition(this.op, this.value);

  /// The operator: `=`, `<`, `>`, `<=`, `>=` or `<>`.
  final String op;

  /// The number compared with, exactly as written (`[<=-1.5]` holds
  /// `-1.5`, `[>=1E3]` holds 1000), with no rounding to 15 digits.
  final ExcelNumber value;

  @override
  bool operator ==(Object other) =>
      other is FormatCondition && other.op == op && other.value == value;

  @override
  int get hashCode => Object.hash(op, value);

  @override
  String toString() => 'FormatCondition($op$value)';
}

/// A section color: a named color or an index into the legacy palette.
///
/// Exactly one of [rgb] and [index] is set.
final class FormatColor {
  /// Creates a color from an [rgb] value or a palette [index].
  const FormatColor({this.rgb, this.index});

  /// The color as `0xRRGGBB`, for the eight named colors.
  final int? rgb;

  /// The `indexed` palette entry, `8` to `63`, for `[Color1]` to
  /// `[Color56]`.
  final int? index;

  @override
  bool operator ==(Object other) =>
      other is FormatColor && other.rgb == rgb && other.index == index;

  @override
  int get hashCode => Object.hash(rgb, index);

  @override
  String toString() => rgb != null
      ? 'FormatColor(rgb: 0x${rgb!.toRadixString(16).padLeft(6, '0')})'
      : 'FormatColor(index: $index)';
}

/// One token of a format section.
sealed class FormatToken {
  const FormatToken();
}

/// Text shown as written: a quoted literal, the character after `\`, or a
/// character with no meaning in a format code.
///
/// A bracket the parser does not interpret, such as `[DBNum1]`, is an
/// [UnsupportedToken] instead.
final class LiteralToken extends FormatToken {
  /// Creates a literal of [text].
  const LiteralToken(this.text);

  /// The text, without quotes or `\`.
  final String text;

  @override
  bool operator ==(Object other) => other is LiteralToken && other.text == text;

  @override
  int get hashCode => Object.hash(LiteralToken, text);

  @override
  String toString() => 'LiteralToken("$text")';
}

/// A digit placeholder: `0`, `#` or `?`.
final class DigitToken extends FormatToken {
  /// Creates a placeholder for [char].
  const DigitToken(this.char);

  /// The placeholder character: `0`, `#` or `?`.
  final String char;

  @override
  bool operator ==(Object other) => other is DigitToken && other.char == char;

  @override
  int get hashCode => Object.hash(DigitToken, char);

  @override
  String toString() => 'DigitToken($char)';
}

/// The decimal point: the first `.` of a section that has no date or time
/// token. Every other `.` is a [LiteralToken].
final class DecimalPointToken extends FormatToken {
  /// Creates the decimal point.
  const DecimalPointToken();

  @override
  bool operator ==(Object other) => other is DecimalPointToken;

  @override
  int get hashCode => (DecimalPointToken).hashCode;

  @override
  String toString() => 'DecimalPointToken';
}

/// A `,`: grouping, scaling by 1000, or a literal, as its place decides.
///
/// The renderer decides the role from the tokens around it.
final class CommaToken extends FormatToken {
  /// Creates a comma.
  const CommaToken();

  @override
  bool operator ==(Object other) => other is CommaToken;

  @override
  int get hashCode => (CommaToken).hashCode;

  @override
  String toString() => 'CommaToken';
}

/// A `%`: the value is multiplied by 100 and the sign shown.
final class PercentToken extends FormatToken {
  /// Creates a percent sign.
  const PercentToken();

  @override
  bool operator ==(Object other) => other is PercentToken;

  @override
  int get hashCode => (PercentToken).hashCode;

  @override
  String toString() => 'PercentToken';
}

/// A scientific exponent marker: `E+`, `E-`, `e+` or `e-`.
///
/// The lowercase `e+` and `e-` make the code invalid, as Excel repairs
/// them to `General`; the token is kept for the classifier.
final class ExponentToken extends FormatToken {
  /// Creates an exponent marker.
  const ExponentToken({required this.plus, required this.letter});

  /// Whether the sign was `+`, which always shows the exponent's sign;
  /// `-` shows only a minus.
  final bool plus;

  /// The letter as written, `E` or `e`.
  final String letter;

  @override
  bool operator ==(Object other) =>
      other is ExponentToken && other.plus == plus && other.letter == letter;

  @override
  int get hashCode => Object.hash(ExponentToken, plus, letter);

  @override
  String toString() => 'ExponentToken($letter${plus ? '+' : '-'})';
}

/// A `/` right after a digit placeholder and right before a placeholder or
/// a digit, which makes the section a fraction. Any other `/` is a
/// [LiteralToken].
final class FractionSlashToken extends FormatToken {
  /// Creates a fraction slash.
  const FractionSlashToken();

  @override
  bool operator ==(Object other) => other is FractionSlashToken;

  @override
  int get hashCode => (FractionSlashToken).hashCode;

  @override
  String toString() => 'FractionSlashToken';
}

/// The fixed denominator of a fraction, such as the `16` of `# ?/16`.
///
/// It is the run of unquoted digits right after a [FractionSlashToken]
/// when that run starts with `1` to `9` and has at most
/// [maxFixedDenominatorDigits] digits; a longer run is one [LiteralToken]
/// per digit and makes the code invalid (Excel repairs it to `General`).
/// A run that starts with `0` is a placeholder instead (`?/0`). A quote
/// or `\` ends the run, so `?/1"5"` has the denominator 1 and the literal
/// `5`.
final class FixedDenominatorToken extends FormatToken {
  /// Creates a fixed denominator of [value].
  const FixedDenominatorToken(this.value);

  /// The denominator, 1 to 999,999,999.
  final int value;

  @override
  bool operator ==(Object other) =>
      other is FixedDenominatorToken && other.value == value;

  @override
  int get hashCode => Object.hash(FixedDenominatorToken, value);

  @override
  String toString() => 'FixedDenominatorToken($value)';
}

/// The most digits a [FixedDenominatorToken] holds, which keeps every
/// numerator and denominator well below 2^53.
const int maxFixedDenominatorDigits = 9;

/// The text placeholder `@`.
final class TextToken extends FormatToken {
  /// Creates a text placeholder.
  const TextToken();

  @override
  bool operator ==(Object other) => other is TextToken;

  @override
  int get hashCode => (TextToken).hashCode;

  @override
  String toString() => 'TextToken';
}

/// The word `General`, in any case.
final class GeneralToken extends FormatToken {
  /// Creates a `General` token.
  const GeneralToken();

  @override
  bool operator ==(Object other) => other is GeneralToken;

  @override
  int get hashCode => (GeneralToken).hashCode;

  @override
  String toString() => 'GeneralToken';
}

/// `_x`: a space as wide as the character x.
final class PaddingToken extends FormatToken {
  /// Creates padding as wide as [char].
  const PaddingToken(this.char);

  /// The character whose width the space takes.
  final String char;

  @override
  bool operator ==(Object other) => other is PaddingToken && other.char == char;

  @override
  int get hashCode => Object.hash(PaddingToken, char);

  @override
  String toString() => 'PaddingToken($char)';
}

/// `*x`: the character x repeated to fill the cell.
///
/// Only the last `*` of a section counts, so a section holds at most one,
/// where the last was written.
final class FillToken extends FormatToken {
  /// Creates a fill of [char].
  const FillToken(this.char);

  /// The character repeated.
  final String char;

  @override
  bool operator ==(Object other) => other is FillToken && other.char == char;

  @override
  int get hashCode => Object.hash(FillToken, char);

  @override
  String toString() => 'FillToken($char)';
}

/// A locale and currency tag such as `[$€-407]`, `[$-41F]` or `[$€]`.
///
/// Two tags with a `-` in one section, system tags ([SystemFormatToken])
/// included, make the code invalid, as Excel repairs `[$-407][$-F800]` to
/// `General`; a currency-only tag such as `[$€]` does not count.
final class LocaleTagToken extends FormatToken {
  /// Creates a tag of [currency] and [lcid].
  const LocaleTagToken(this.currency, this.lcid);

  /// The currency text before the `-`, possibly empty.
  final String currency;

  /// The hexadecimal locale id after the `-`, or null when there is none or
  /// it is not one to eight hexadecimal digits. A system date or time tag
  /// (`[$-F800]`, `[$-x-sysdate]`) is a [SystemFormatToken] instead.
  final int? lcid;

  @override
  bool operator ==(Object other) =>
      other is LocaleTagToken &&
      other.currency == currency &&
      other.lcid == lcid;

  @override
  int get hashCode => Object.hash(LocaleTagToken, currency, lcid);

  /// The language of [lcid]: its bits 0 to 15, such as `0x407` for
  /// German (Germany), or 0 when [lcid] is null.
  int get language => (lcid ?? 0) & 0xFFFF;

  /// The calendar of [lcid]: its bits 16 to 23, or 0 when [lcid] is null.
  /// 0 and 1 are Gregorian.
  int get calendar => ((lcid ?? 0) >> 16) & 0xFF;

  /// The numeral system of [lcid]: its bits 24 to 31, or 0 when [lcid] is
  /// null. 0 and 1 are Western digits.
  int get numerals => ((lcid ?? 0) >> 24) & 0xFF;

  @override
  String toString() {
    final String id = lcid == null ? 'null' : '0x${lcid!.toRadixString(16)}';
    return 'LocaleTagToken("$currency", $id)';
  }
}

/// A run of one date or time letter, such as `yyyy` or the elapsed `[h]`.
final class DateToken extends FormatToken {
  /// Creates a run of [length] times [letter].
  const DateToken(this.letter, this.length, {this.elapsed = false});

  /// The letter in lowercase: `d`, `m`, `y`, `h`, `s`, or the era and
  /// calendar letters `e`, `g` and `b`.
  final String letter;

  /// How many times the letter was written.
  final int length;

  /// Whether the run was an elapsed time in brackets, such as `[h]`.
  final bool elapsed;

  @override
  bool operator ==(Object other) =>
      other is DateToken &&
      other.letter == letter &&
      other.length == length &&
      other.elapsed == elapsed;

  @override
  int get hashCode => Object.hash(DateToken, letter, length, elapsed);

  @override
  String toString() {
    final String run = letter * length;
    return elapsed ? 'DateToken([$run])' : 'DateToken($run)';
  }
}

/// A 12-hour clock marker, `AM/PM` or `A/P` in any case.
final class AmPmToken extends FormatToken {
  /// Creates a marker written as [text].
  const AmPmToken(this.text);

  /// The marker as written, such as `AM/PM` or `a/p`; the case of `A/P`
  /// is shown.
  final String text;

  @override
  bool operator ==(Object other) => other is AmPmToken && other.text == text;

  @override
  int get hashCode => Object.hash(AmPmToken, text);

  @override
  String toString() => 'AmPmToken($text)';
}

/// `.0` to `.000` after a time token: [digits] decimals of a second.
///
/// It is a `.` followed directly by one to three `0` in a date or time
/// section that has an `h`, `m` or `s` token (elapsed or not) before it.
/// Four or more `0` make the code invalid.
final class FractionalSecondsToken extends FormatToken {
  /// Creates fractional seconds of [digits] decimals.
  const FractionalSecondsToken(this.digits);

  /// How many decimals of a second are shown: 1 to 3.
  final int digits;

  @override
  bool operator ==(Object other) =>
      other is FractionalSecondsToken && other.digits == digits;

  @override
  int get hashCode => Object.hash(FractionalSecondsToken, digits);

  @override
  String toString() => 'FractionalSecondsToken($digits)';
}

/// `B1` or `B2`, bracketed or not and in any case: the calendar of the
/// section's dates.
final class CalendarToken extends FormatToken {
  /// Creates a calendar token for [calendar].
  const CalendarToken(this.calendar);

  /// The calendar: 1 Gregorian, 2 Hijri.
  final int calendar;

  @override
  bool operator ==(Object other) =>
      other is CalendarToken && other.calendar == calendar;

  @override
  int get hashCode => Object.hash(CalendarToken, calendar);

  @override
  String toString() => 'CalendarToken($calendar)';
}

/// A system date or time tag: `[$-F800]` or `[$-x-sysdate]` for the long
/// date, `[$-F400]` or `[$-x-systime]` for the long time.
///
/// The upper bits of the locale id do not matter: `[$-10F800]` is the long
/// date too.
final class SystemFormatToken extends FormatToken {
  /// Creates a system tag for the long date or the long time.
  const SystemFormatToken({required this.longDate});

  /// Whether the tag stands for the long date; false for the long time.
  final bool longDate;

  @override
  bool operator ==(Object other) =>
      other is SystemFormatToken && other.longDate == longDate;

  @override
  int get hashCode => Object.hash(SystemFormatToken, longDate);

  @override
  String toString() => 'SystemFormatToken(longDate: $longDate)';
}

/// A bracket the engine does not render, such as `[DBNum1]`, `[NatNum1]`
/// or `[foo]`: it holds its place and shows nothing.
final class UnsupportedToken extends FormatToken {
  /// Creates an unsupported bracket of [content].
  const UnsupportedToken(this.content);

  /// The text between the brackets, without them; empty for `[]`.
  final String content;

  @override
  bool operator ==(Object other) =>
      other is UnsupportedToken && other.content == content;

  @override
  int get hashCode => Object.hash(UnsupportedToken, content);

  @override
  String toString() => 'UnsupportedToken("$content")';
}

/// The most decimals of a second a section may show.
const int _maxSecondDecimals = 3;

const String _generalWord = 'general';
const String _amPm = 'am/pm';
const String _aP = 'a/p';
const String _dateLetters = 'dmyhsegb';
const String _digitPlaceholders = '0#?';

/// What may follow a fraction slash: a placeholder or a fixed denominator.
const String _afterSlash = '0#?123456789';

const Map<String, int> _namedColors = <String, int>{
  'black': 0x000000,
  'blue': 0x0000FF,
  'cyan': 0x00FFFF,
  'green': 0x00FF00,
  'magenta': 0xFF00FF,
  'red': 0xFF0000,
  'white': 0xFFFFFF,
  'yellow': 0xFFFF00,
};

/// The most conditions a code may hold.
const int _maxConditions = 2;

/// The most sections a code may hold.
const int _maxSections = 4;

/// One scan of one code.
final class _Parser {
  _Parser(this.code);

  final String code;
  final List<FormatSection> _sections = <FormatSection>[];
  List<FormatToken> _tokens = <FormatToken>[];
  FormatCondition? _condition;
  FormatColor? _color;
  int _conditions = 0;
  int _textSections = 0;
  int _localeTags = 0;
  String? _invalid;

  ParsedFormat parse() {
    if (code.length > _maxCodeLength) {
      _invalid = 'longer than $_maxCodeLength characters';
    }
    var i = 0;
    var truncated = false;
    while (i < code.length && !truncated) {
      final String c = code[i];
      if (c == ';') {
        _endSection();
        i++;
      } else if (c == '"') {
        final int close = code.indexOf('"', i + 1);
        if (close < 0) {
          truncated = true;
        } else {
          if (close > i + 1) {
            _tokens.add(LiteralToken(code.substring(i + 1, close)));
          }
          i = close + 1;
        }
      } else if (c == r'\' || c == '_' || c == '*') {
        // A lone one at the end adds nothing.
        if (i + 1 < code.length) {
          final String next = _charAt(i + 1);
          _tokens.add(switch (c) {
            '_' => PaddingToken(next),
            '*' => FillToken(next),
            _ => LiteralToken(next),
          });
          i += 1 + next.length;
        } else {
          i++;
        }
      } else if (c == '[') {
        final int close = code.indexOf(']', i + 1);
        if (close < 0) {
          truncated = true;
        } else {
          _bracket(code.substring(i + 1, close));
          i = close + 1;
        }
      } else if (_isWordAt(i, _generalWord)) {
        _tokens.add(const GeneralToken());
        i += _generalWord.length;
      } else if (_isWordAt(i, _amPm)) {
        _tokens.add(AmPmToken(code.substring(i, i + _amPm.length)));
        i += _amPm.length;
      } else if (_isWordAt(i, _aP)) {
        _tokens.add(AmPmToken(code.substring(i, i + _aP.length)));
        i += _aP.length;
      } else if (c == '@') {
        _tokens.add(const TextToken());
        i++;
      } else if ((c == 'E' || c == 'e') &&
          i + 1 < code.length &&
          (code[i + 1] == '+' || code[i + 1] == '-')) {
        if (c == 'e') _invalid ??= 'a lowercase exponent e${code[i + 1]}';
        _tokens.add(ExponentToken(plus: code[i + 1] == '+', letter: c));
        i += 2;
      } else if ((c == 'b' || c == 'B') &&
          i + 1 < code.length &&
          (code[i + 1] == '1' || code[i + 1] == '2')) {
        _tokens.add(CalendarToken(code.codeUnitAt(i + 1) - 0x30));
        i += 2;
      } else if (_dateLetters.contains(c.toLowerCase())) {
        final String letter = c.toLowerCase();
        var end = i + 1;
        // A run of `g` stops where the word `General` starts.
        while (end < code.length &&
            code[end].toLowerCase() == letter &&
            !_isWordAt(end, _generalWord)) {
          end++;
        }
        _tokens.add(DateToken(letter, end - i));
        i = end;
      } else if (_digitPlaceholders.contains(c)) {
        _tokens.add(DigitToken(c));
        i++;
      } else if (c == '.') {
        // Which `.` is the decimal point is settled when the section ends.
        _tokens.add(const DecimalPointToken());
        i++;
      } else if (c == ',') {
        _tokens.add(const CommaToken());
        i++;
      } else if (c == '%') {
        _tokens.add(const PercentToken());
        i++;
      } else if (c == '/' && _isFractionSlashAt(i)) {
        _tokens.add(const FractionSlashToken());
        i = _fixedDenominator(i + 1);
      } else {
        final String char = _charAt(i);
        _tokens.add(LiteralToken(char));
        i += char.length;
      }
    }
    _endSection();
    if (_sections.length > _maxSections) {
      _invalid ??= 'more than $_maxSections sections';
    }
    return ParsedFormat(
      _sections,
      invalidReason: _invalid,
      truncated: truncated,
    );
  }

  /// The character at [i], two code units for a surrogate pair.
  String _charAt(int i) {
    final int unit = code.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < code.length) {
      final int low = code.codeUnitAt(i + 1);
      if (low >= 0xDC00 && low <= 0xDFFF) return code.substring(i, i + 2);
    }
    return code[i];
  }

  /// Whether [code] holds the lowercase [word] at [i], in any case.
  bool _isWordAt(int i, String word) =>
      i + word.length <= code.length &&
      code.substring(i, i + word.length).toLowerCase() == word;

  /// Whether the `/` at [i] follows a digit placeholder and precedes a
  /// placeholder or a digit.
  bool _isFractionSlashAt(int i) =>
      _tokens.isNotEmpty &&
      _tokens.last is DigitToken &&
      i + 1 < code.length &&
      _afterSlash.contains(code[i + 1]);

  /// Reads the fixed denominator that may start at [i], right after a
  /// fraction slash, and returns the index after it.
  int _fixedDenominator(int i) {
    if (i >= code.length) return i;
    final int first = code.codeUnitAt(i);
    // `0` is a placeholder; a denominator starts with `1` to `9`.
    if (first < 0x31 || first > 0x39) return i;
    var end = i;
    while (end < code.length &&
        code.codeUnitAt(end) >= 0x30 &&
        code.codeUnitAt(end) <= 0x39) {
      end++;
    }
    if (end - i > maxFixedDenominatorDigits) {
      _invalid ??=
          'a fixed denominator of more than $maxFixedDenominatorDigits digits';
      for (var k = i; k < end; k++) {
        _tokens.add(LiteralToken(code[k]));
      }
    } else {
      _tokens.add(FixedDenominatorToken(int.parse(code.substring(i, end))));
    }
    return end;
  }

  /// Reads the bracket [content] by its first character.
  void _bracket(String content) {
    if (content.isEmpty) {
      _tokens.add(const UnsupportedToken(''));
      return;
    }
    final String first = content[0];
    final String lower = content.toLowerCase();
    if (first == r'$') {
      if (content.contains('-') && ++_localeTags > 1) {
        _invalid ??= 'two locale tags in one section';
      }
      _tokens.add(_dollarTag(content.substring(1)));
    } else if (lower == 'b1' || lower == 'b2') {
      _tokens.add(CalendarToken(lower == 'b1' ? 1 : 2));
    } else if (first == '<' || first == '>' || first == '=') {
      _addCondition(content);
    } else if ('hms'.contains(lower[0]) && _isRunOf(lower, lower[0])) {
      _tokens.add(DateToken(lower[0], lower.length, elapsed: true));
    } else if (_namedColors.containsKey(lower)) {
      _color ??= FormatColor(rgb: _namedColors[lower]);
    } else if (lower.startsWith('color')) {
      final int? n = _decimal(lower.substring('color'.length));
      if (n == null || n < 1 || n > 56) {
        _invalid ??= 'no palette color [$content]';
      } else {
        _color ??= FormatColor(index: n + 7);
      }
    } else {
      // [DBNum1], [NatNum1] and the like: kept in place for the renderers.
      _tokens.add(UnsupportedToken(content));
    }
  }

  void _addCondition(String content) {
    final String op =
        content.length > 1 &&
            (content.startsWith('<=') ||
                content.startsWith('>=') ||
                content.startsWith('<>'))
        ? content.substring(0, 2)
        : content[0];
    final String value = content.substring(op.length).trim();
    if (!_isNumber(value)) {
      _invalid ??= 'a condition without a number [$content]';
      return;
    }
    _conditions++;
    if (_conditions > _maxConditions) {
      _invalid ??= 'more than $_maxConditions conditions';
    }
    if (_condition != null) {
      _invalid ??= 'two conditions in one section';
    } else {
      _condition = FormatCondition(op, ExcelNumber.parse(value));
    }
  }

  void _endSection() {
    final bool isDate = _tokens.any(
      (FormatToken t) => t is DateToken || t is AmPmToken,
    );
    var pointSeen = isDate;
    final int lastFill = _tokens.lastIndexWhere(
      (FormatToken t) => t is FillToken,
    );
    final List<FormatToken> tokens = <FormatToken>[];
    var timeSeen = false;
    for (var k = 0; k < _tokens.length; k++) {
      final FormatToken token = _tokens[k];
      if (token is DateToken && 'hms'.contains(token.letter)) timeSeen = true;
      if (token is DecimalPointToken) {
        final int run = isDate && timeSeen ? _zeroRunAt(k + 1) : 0;
        if (run > _maxSecondDecimals) {
          _invalid ??= 'more than $_maxSecondDecimals decimals of a second';
        } else if (run > 0) {
          tokens.add(FractionalSecondsToken(run));
          k += run;
          continue;
        }
        tokens.add(pointSeen ? const LiteralToken('.') : token);
        pointSeen = true;
      } else if (token is FillToken && k != lastFill) {
        continue;
      } else {
        tokens.add(token);
      }
    }
    if (isDate) {
      for (final FormatToken token in tokens) {
        if (token is DigitToken ||
            token is GeneralToken ||
            token is ExponentToken ||
            token is FractionSlashToken ||
            token is FixedDenominatorToken) {
          _invalid ??= 'a date or time section mixed with $token';
          break;
        }
      }
    }
    final FormatSection section = FormatSection(
      tokens,
      condition: _condition,
      color: _color,
    );
    if (section.hasText && ++_textSections > 1) {
      _invalid ??= '@ in more than one section';
    }
    _sections.add(section);
    _tokens = <FormatToken>[];
    _condition = null;
    _color = null;
    _localeTags = 0;
  }

  /// How many `0` placeholders of the current section follow each other
  /// from [k].
  int _zeroRunAt(int k) {
    var end = k;
    while (end < _tokens.length && _tokens[end] == const DigitToken('0')) {
      end++;
    }
    return end - k;
  }
}

/// Whether [text] is one character repeated.
bool _isRunOf(String text, String char) {
  for (var k = 0; k < text.length; k++) {
    if (text[k] != char) return false;
  }
  return true;
}

/// [text] as a decimal of one to three digits, or null.
int? _decimal(String text) {
  if (text.isEmpty || text.length > 3) return null;
  var n = 0;
  for (var k = 0; k < text.length; k++) {
    final int digit = text.codeUnitAt(k) - 0x30;
    if (digit < 0 || digit > 9) return null;
    n = n * 10 + digit;
  }
  return n;
}

/// The tag after `[$`: the currency, then `-` and a hexadecimal LCID, or a
/// system date or time tag.
FormatToken _dollarTag(String text) {
  final int dash = text.indexOf('-');
  if (dash < 0) return LocaleTagToken(text, null);
  final String after = text.substring(dash + 1);
  final String lower = after.toLowerCase();
  if (lower == 'x-sysdate') return const SystemFormatToken(longDate: true);
  if (lower == 'x-systime') return const SystemFormatToken(longDate: false);
  final int? lcid = _hex(after);
  if (lcid != null && lcid & 0xFFFF == 0xF800) {
    return const SystemFormatToken(longDate: true);
  }
  if (lcid != null && lcid & 0xFFFF == 0xF400) {
    return const SystemFormatToken(longDate: false);
  }
  return LocaleTagToken(text.substring(0, dash), lcid);
}

/// [text] as one to eight hexadecimal digits, or null.
int? _hex(String text) {
  if (text.isEmpty || text.length > 8) return null;
  var n = 0;
  for (var k = 0; k < text.length; k++) {
    final int unit = text.codeUnitAt(k);
    final int digit;
    if (unit >= 0x30 && unit <= 0x39) {
      digit = unit - 0x30;
    } else if (unit >= 0x41 && unit <= 0x46) {
      digit = unit - 0x41 + 10;
    } else if (unit >= 0x61 && unit <= 0x66) {
      digit = unit - 0x61 + 10;
    } else {
      return null;
    }
    n = n * 16 + digit;
  }
  return n;
}

/// Whether [text] is a decimal number: an optional sign, digits with at
/// most one `.`, and an optional exponent.
bool _isNumber(String text) {
  var k = 0;
  bool isDigitAt(int at) =>
      at < text.length &&
      text.codeUnitAt(at) >= 0x30 &&
      text.codeUnitAt(at) <= 0x39;
  if (k < text.length && (text[k] == '+' || text[k] == '-')) k++;
  var digits = 0;
  while (isDigitAt(k)) {
    k++;
    digits++;
  }
  if (k < text.length && text[k] == '.') {
    k++;
    while (isDigitAt(k)) {
      k++;
      digits++;
    }
  }
  if (digits == 0) return false;
  if (k < text.length && (text[k] == 'e' || text[k] == 'E')) {
    k++;
    if (k < text.length && (text[k] == '+' || text[k] == '-')) k++;
    if (!isDigitAt(k)) return false;
    while (isDigitAt(k)) {
      k++;
    }
  }
  return k == text.length;
}
