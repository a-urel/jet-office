/// The renderer of number sections.
///
/// New in jet_office; Quds has no number format engine. [renderNumber]
/// lays a number out in the section [chooseNumberSection] picked: digit
/// placeholders, grouping and scaling commas, percent signs, literals,
/// padding and fill (spec §5.2). Scaling and rounding work on the
/// number's decimal digits ([ExcelNumber.shift], [ExcelNumber.toFixed]),
/// never on a `double`, so the result is exact and the same on the VM and
/// in JavaScript. The one exception is a fraction's best approximation,
/// which runs on the fractional part as a `double`; IEEE arithmetic gives
/// the same result on both.
library;

import 'excel_number.dart';
import 'format_code.dart';
import 'format_locale.dart';
import 'formatted_value.dart';
import 'general.dart';
import 'section_choice.dart';

/// Renders [value] (already chosen and signed by [chooseNumberSection])
/// with [section].
///
/// [value] is shown without its sign; [showMinus] puts a `-` at the very
/// start of the output, before any literal, unless the digits shown are
/// all zero (a value that rounds to zero shows no minus). Separators come
/// from [locale]; quoted literals are shown as written. [generalWidth] is
/// the width a `General` section fits its number into.
///
/// Adjacent text is merged into one [XlsxFormatText], and empty text is
/// left out.
List<XlsxFormatPart> renderNumber(
  FormatSection section,
  ExcelNumber value, {
  required bool showMinus,
  required XlsxFormatLocale locale,
  required int generalWidth,
}) => switch (_layoutOf(section)) {
  _Layout.scientific => _renderScientific(section, value, showMinus, locale),
  _Layout.fraction => _renderFraction(section, value, showMinus, locale),
  _Layout.general => _renderGeneral(
    section,
    value,
    showMinus,
    locale,
    generalWidth,
  ),
  _Layout.fixed => _renderFixed(section, value, showMinus, locale),
};

/// How a number section lays its number out.
enum _Layout {
  /// Integer and fraction digits: `#,##0.00`.
  fixed,

  /// A mantissa and an exponent: `0.00E+00`.
  scientific,

  /// A whole part and a fraction: `# ?/?`.
  fraction,

  /// The `General` layout, which fits the number into a width.
  general,
}

/// The layout of [section], decided by its tokens.
_Layout _layoutOf(FormatSection section) {
  for (final FormatToken token in section.tokens) {
    if (token is GeneralToken) return _Layout.general;
    if (token is ExponentToken) return _Layout.scientific;
    if (token is FractionSlashToken) return _Layout.fraction;
  }
  return _Layout.fixed;
}

/// What a [CommaToken] does where it stands.
enum _Comma {
  /// Between two integer digit placeholders: turns grouping on.
  group,

  /// After the last placeholder of the integer or the fraction part:
  /// divides the value by 1000.
  scale,

  /// Between two fraction placeholders: nothing.
  ignored,

  /// Before every digit placeholder: shown as a `,`.
  literal,
}

/// Lays [value] out with the digit placeholders of [section].
List<XlsxFormatPart> _renderFixed(
  FormatSection section,
  ExcelNumber value,
  bool showMinus,
  XlsxFormatLocale locale,
) {
  final List<FormatToken> tokens = section.tokens;
  final int point = _pointIndex(tokens);

  // Each placeholder in order: the integer ones before the point, the
  // fraction ones after it.
  final List<String> integerPlaceholders = <String>[];
  final List<String> fractionPlaceholders = <String>[];
  for (var k = 0; k < tokens.length; k++) {
    final FormatToken token = tokens[k];
    if (token is DigitToken) {
      (k < point ? integerPlaceholders : fractionPlaceholders).add(token.char);
    }
  }

  final List<_Comma?> commas = _classifyCommas(tokens, point);
  final bool grouping = commas.contains(_Comma.group);
  var powerOfTen = 0;
  for (var k = 0; k < tokens.length; k++) {
    if (tokens[k] is PercentToken) powerOfTen += 2;
    if (commas[k] == _Comma.scale) powerOfTen -= 3;
  }

  final ({String whole, String fraction}) fixed = value
      .abs()
      .shift(powerOfTen)
      .toFixed(fractionPlaceholders.length);
  final String integerDigits = _withoutLeadingZeros(fixed.whole);
  final String fractionDigits = fixed.fraction;
  final bool allZero =
      integerDigits.isEmpty && _lastNonZero(fractionDigits) < 0;

  // Integer columns are counted from the right, from 0. Fraction digits
  // are shown through the last significant one or the last `0`
  // placeholder, whichever is later; the placeholders after it are blank.
  final int integerColumns = integerPlaceholders.length;
  final int lastShownFraction = _max(
    _lastNonZero(fractionDigits),
    fractionPlaceholders.lastIndexOf('0'),
  );

  final _Parts out = _Parts();
  if (showMinus && !allZero) out.text('-');

  void writeColumn(int c, String placeholder) => _writeColumn(
    out,
    integerDigits,
    c,
    placeholder,
    grouping ? locale.groupSeparator : null,
  );

  var integerSeen = 0;
  var fractionSeen = 0;
  for (var k = 0; k < tokens.length; k++) {
    final FormatToken token = tokens[k];
    switch (token) {
      case DigitToken(:final String char) when k < point:
        final int column = integerColumns - 1 - integerSeen;
        if (integerSeen == 0) {
          // Digits beyond the placeholders go before the first one.
          for (var c = integerDigits.length - 1; c >= integerColumns; c--) {
            writeColumn(c, '0');
          }
        }
        writeColumn(column, char);
        integerSeen++;
      case DigitToken(:final String char):
        final int index = fractionSeen;
        out.text(
          index <= lastShownFraction ? fractionDigits[index] : _blank(char),
        );
        fractionSeen++;
      case DecimalPointToken():
        if (integerColumns == 0) {
          // No integer placeholder: the integer digits stand before the
          // point.
          for (var c = integerDigits.length - 1; c >= 0; c--) {
            writeColumn(c, '#');
          }
        }
        out.text(locale.decimalSeparator);
      case CommaToken():
        if (commas[k] == _Comma.literal) out.text(',');
      case PercentToken():
        out.text('%');
      case LiteralToken(:final String text):
        out.text(text);
      case LocaleTagToken(:final String currency):
        out.text(currency);
      case PaddingToken(:final String char):
        out.add(XlsxFormatPadding(char));
      case FillToken(:final String char):
        out.add(XlsxFormatFill(char));
      case FractionSlashToken():
        // Only a slash with no denominator after it reaches fixed point
        // (`?/9999999999`); it is printed as written.
        out.text('/');
      case TextToken() ||
          GeneralToken() ||
          ExponentToken() ||
          FixedDenominatorToken() ||
          DateToken() ||
          AmPmToken() ||
          FractionalSecondsToken() ||
          CalendarToken() ||
          SystemFormatToken() ||
          UnsupportedToken():
        // Not part of a fixed-point layout.
        break;
    }
  }
  return out.result;
}

/// Lays [value] out in `General` notation fitted into [width], with the
/// literals, padding and fill of [section] around it: `General" kg"`.
///
/// [showMinus] puts a `-` at the very start, before any literal, unless
/// [value] is zero.
List<XlsxFormatPart> _renderGeneral(
  FormatSection section,
  ExcelNumber value,
  bool showMinus,
  XlsxFormatLocale locale,
  int width,
) {
  final _Parts out = _Parts();
  if (showMinus && !value.isZero) out.text('-');
  for (final FormatToken token in section.tokens) {
    switch (token) {
      case GeneralToken():
        out.text(renderGeneral(value, width: width, locale: locale));
      case LiteralToken(:final String text):
        out.text(text);
      case LocaleTagToken(:final String currency):
        out.text(currency);
      case PaddingToken(:final String char):
        out.add(XlsxFormatPadding(char));
      case FillToken(:final String char):
        out.add(XlsxFormatFill(char));
      case DigitToken() ||
          DecimalPointToken() ||
          CommaToken() ||
          PercentToken() ||
          TextToken() ||
          ExponentToken() ||
          FractionSlashToken() ||
          FixedDenominatorToken() ||
          DateToken() ||
          AmPmToken() ||
          FractionalSecondsToken() ||
          CalendarToken() ||
          SystemFormatToken() ||
          UnsupportedToken():
        // Not part of a General layout.
        break;
    }
  }
  return out.result;
}

/// Lays [value] out as a mantissa and an exponent: `0.00E+00`.
///
/// The mantissa has as many significant digits as the placeholders before
/// the exponent marker; the digit placeholders after it set the least
/// number of exponent digits. When the integer part has more than one
/// placeholder and starts with `#`, the exponent is a multiple of the
/// number of integer placeholders (`##0.0E+0`). Zero has exponent 0.
List<XlsxFormatPart> _renderScientific(
  FormatSection section,
  ExcelNumber value,
  bool showMinus,
  XlsxFormatLocale locale,
) {
  final List<FormatToken> tokens = section.tokens;
  final int marker = tokens.indexWhere((FormatToken t) => t is ExponentToken);
  final ExponentToken exponentToken = tokens[marker] as ExponentToken;
  final int point = _min(_pointIndex(tokens), marker);

  final List<String> integerPlaceholders = <String>[];
  final List<String> fractionPlaceholders = <String>[];
  for (var k = 0; k < marker; k++) {
    final FormatToken token = tokens[k];
    if (token is DigitToken) {
      (k < point ? integerPlaceholders : fractionPlaceholders).add(token.char);
    }
  }
  var exponentPlaceholders = 0;
  for (var k = marker + 1; k < tokens.length; k++) {
    if (tokens[k] is DigitToken) exponentPlaceholders++;
  }

  final int integerColumns = integerPlaceholders.length;
  final int fractionColumns = fractionPlaceholders.length;
  final bool engineering = integerColumns > 1 && integerPlaceholders[0] == '#';
  final ExcelNumber magnitude = value.abs();

  // The digits and the exponent. The integer part has [integerDigits]
  // digits; a carry in the rounding can move the exponent, so the layout
  // is settled again until it holds.
  var integerDigits = integerColumns;
  var digits = '';
  var exponent = 0;
  for (var attempt = 0; attempt < 4; attempt++) {
    final int count = _max(integerDigits + fractionColumns, 1);
    final ({String digits, int exponent}) significant = magnitude.toSignificant(
      count,
    );
    final int first = significant.exponent;
    final int newExponent;
    final int newIntegerDigits;
    if (magnitude.isZero) {
      newExponent = 0;
      newIntegerDigits = integerColumns;
    } else if (engineering) {
      newExponent = _floorDiv(first, integerColumns) * integerColumns;
      newIntegerDigits = first - newExponent + 1;
    } else {
      newExponent = first - integerColumns + 1;
      newIntegerDigits = integerColumns;
    }
    digits = significant.digits;
    exponent = newExponent;
    if (newIntegerDigits == integerDigits) break;
    integerDigits = newIntegerDigits;
    digits = '';
  }
  if (digits.isEmpty) {
    digits = magnitude
        .toSignificant(_max(integerDigits + fractionColumns, 1))
        .digits;
  }

  final String integerPart = magnitude.isZero
      ? ''
      : digits.substring(0, _min(integerDigits, digits.length));
  final String fractionPart = digits.length > integerPart.length
      ? digits.substring(integerPart.length)
      : '';
  final int lastShownFraction = _max(
    _lastNonZero(fractionPart),
    fractionPlaceholders.lastIndexOf('0'),
  );

  String exponentText = exponent.abs().toString();
  if (exponentText.length < exponentPlaceholders) {
    exponentText = exponentText.padLeft(exponentPlaceholders, '0');
  }
  final String exponentSign = exponent < 0
      ? '-'
      : (exponentToken.plus ? '+' : '');

  final _Parts out = _Parts();
  if (showMinus && !magnitude.isZero) out.text('-');

  var integerSeen = 0;
  var fractionSeen = 0;
  for (var k = 0; k < tokens.length; k++) {
    final FormatToken token = tokens[k];
    switch (token) {
      case DigitToken(:final String char) when k < marker && k < point:
        final int column = integerColumns - 1 - integerSeen;
        out.text(
          column < integerPart.length
              ? integerPart[integerPart.length - 1 - column]
              : _blank(char),
        );
        integerSeen++;
      case DigitToken(:final String char) when k < marker:
        final int index = fractionSeen;
        out.text(
          index <= lastShownFraction && index < fractionPart.length
              ? fractionPart[index]
              : _blank(char),
        );
        fractionSeen++;
      case DigitToken():
        // An exponent placeholder: the exponent is written at the marker.
        break;
      case DecimalPointToken():
        out.text(locale.decimalSeparator);
      case ExponentToken():
        out.text('${exponentToken.letter}$exponentSign$exponentText');
      case PercentToken():
        out.text('%');
      case LiteralToken(:final String text):
        out.text(text);
      case LocaleTagToken(:final String currency):
        out.text(currency);
      case PaddingToken(:final String char):
        out.add(XlsxFormatPadding(char));
      case FillToken(:final String char):
        out.add(XlsxFormatFill(char));
      case CommaToken() ||
          TextToken() ||
          GeneralToken() ||
          FractionSlashToken() ||
          FixedDenominatorToken() ||
          DateToken() ||
          AmPmToken() ||
          FractionalSecondsToken() ||
          CalendarToken() ||
          SystemFormatToken() ||
          UnsupportedToken():
        break;
    }
  }
  return out.result;
}

/// The decimal places a fraction's value is taken to: exact for any
/// number of 15 significant digits down to 10^-25, and far below what a
/// denominator under 10^9 can tell apart.
const int _fractionPlaces = 40;

/// The most denominator digits the approximation uses; more placeholders
/// only pad.
const int _maxDenominatorDigits = maxFixedDenominatorDigits;

/// Lays [value] out as a whole part and a fraction: `# ?/?`, `?/8`.
///
/// The numerator is the run of placeholders right before the slash; the
/// denominator is the run right after it, or a fixed denominator. Any
/// placeholder before the numerator makes the section mixed (`# ?/?`, a
/// whole part and a proper fraction); without one the whole value is an
/// improper fraction (`?/?` shows 1.5 as `3/2`).
///
/// A fixed denominator rounds the numerator half away from zero, exactly.
/// Otherwise the fraction is the best rational approximation with a
/// denominator below 10^d, d the denominator placeholders (at most 9
/// counted). A fraction that rounds to one carries into the whole part.
/// The numerator pads on the left, each placeholder as in fixed point;
/// the denominator pads on the right with spaces under every placeholder,
/// as a `0` there would change the value shown (`# 00/00` shows 1.5 as
/// `1 01/2 `). A mixed section whose fraction is zero
/// shows it blank: spaces under `?`, nothing under `#`, the slash and a
/// fixed denominator too; a `0` placeholder in the fraction shows it in
/// full instead.
List<XlsxFormatPart> _renderFraction(
  FormatSection section,
  ExcelNumber value,
  bool showMinus,
  XlsxFormatLocale locale,
) {
  final List<FormatToken> tokens = section.tokens;
  final int slash = tokens.indexWhere(
    (FormatToken t) => t is FractionSlashToken,
  );
  var numeratorStart = slash;
  while (numeratorStart > 0 && tokens[numeratorStart - 1] is DigitToken) {
    numeratorStart--;
  }
  var denominatorEnd = slash + 1;
  int? fixedDenominator;
  if (denominatorEnd < tokens.length &&
      tokens[denominatorEnd] is FixedDenominatorToken) {
    fixedDenominator = (tokens[denominatorEnd] as FixedDenominatorToken).value;
    denominatorEnd++;
  } else {
    while (denominatorEnd < tokens.length &&
        tokens[denominatorEnd] is DigitToken) {
      denominatorEnd++;
    }
  }
  if (fixedDenominator == null && denominatorEnd == slash + 1) {
    // A slash before a denominator too long to be one: no fraction.
    return _renderFixed(section, value, showMinus, locale);
  }

  final List<String> integerPlaceholders = <String>[
    for (var k = 0; k < numeratorStart; k++)
      if (tokens[k] case DigitToken(:final String char)) char,
  ];
  final List<String> numeratorPlaceholders = <String>[
    for (var k = numeratorStart; k < slash; k++) (tokens[k] as DigitToken).char,
  ];
  final List<String> denominatorPlaceholders = <String>[
    if (fixedDenominator == null)
      for (var k = slash + 1; k < denominatorEnd; k++)
        (tokens[k] as DigitToken).char,
  ];
  final bool mixed = integerPlaceholders.isNotEmpty;

  // Commas count in the whole part only, as in fixed point.
  final List<_Comma?> commas = _classifyCommas(
    tokens.sublist(0, numeratorStart),
    numeratorStart,
  );
  final bool grouping = commas.contains(_Comma.group);
  var powerOfTen = 0;
  for (var k = 0; k < tokens.length; k++) {
    if (tokens[k] is PercentToken) powerOfTen += 2;
    if (k < numeratorStart && commas[k] == _Comma.scale) powerOfTen -= 3;
  }

  final ({String whole, String fraction}) fixed = value
      .abs()
      .shift(powerOfTen)
      .toFixed(_fractionPlaces);
  BigInt whole = BigInt.parse(fixed.whole);
  int numerator;
  final int denominator;
  if (fixedDenominator != null) {
    // round(f * D) = floor((2 * digits * D + scale) / (2 * scale)).
    final BigInt scale = BigInt.from(10).pow(_fractionPlaces);
    final BigInt twice =
        BigInt.parse(fixed.fraction) *
        BigInt.from(fixedDenominator) *
        BigInt.two;
    numerator = ((twice + scale) ~/ (scale * BigInt.two)).toInt();
    denominator = fixedDenominator;
  } else {
    final int digits = _min(
      denominatorPlaceholders.length,
      _maxDenominatorDigits,
    );
    final ({int numerator, int denominator}) best = _bestFraction(
      double.parse('0.${fixed.fraction}'),
      _pow10(digits) - 1,
    );
    numerator = best.numerator;
    denominator = best.denominator;
  }
  if (mixed && numerator == denominator) {
    whole += BigInt.one;
    numerator = 0;
  }
  final BigInt shownNumerator = mixed
      ? BigInt.from(numerator)
      : whole * BigInt.from(denominator) + BigInt.from(numerator);
  final bool fractionZero = shownNumerator == BigInt.zero;
  final bool allZero = fractionZero && (!mixed || whole == BigInt.zero);
  final bool blankFraction =
      mixed &&
      fractionZero &&
      !numeratorPlaceholders.contains('0') &&
      !denominatorPlaceholders.contains('0');
  // Spaces stand for a blank fraction only under `?`.
  final bool blankAsSpace =
      numeratorPlaceholders.contains('?') ||
      denominatorPlaceholders.contains('?');

  // A mixed zero shows its whole part as `0`.
  final String integerDigits = !mixed
      ? ''
      : (whole == BigInt.zero ? (allZero ? '0' : '') : whole.toString());
  final String numeratorDigits = shownNumerator.toString();
  final String denominatorDigits = denominator.toString();
  final int integerColumns = integerPlaceholders.length;
  final int numeratorColumns = numeratorPlaceholders.length;

  final _Parts out = _Parts();
  if (showMinus && !allZero) out.text('-');

  void writeColumn(int c, String placeholder) => _writeColumn(
    out,
    integerDigits,
    c,
    placeholder,
    grouping ? locale.groupSeparator : null,
  );

  var integerSeen = 0;
  for (var k = 0; k < tokens.length; k++) {
    final FormatToken token = tokens[k];
    switch (token) {
      case DigitToken(:final String char) when k < numeratorStart:
        final int column = integerColumns - 1 - integerSeen;
        if (integerSeen == 0) {
          // Digits beyond the placeholders go before the first one.
          for (var c = integerDigits.length - 1; c >= integerColumns; c--) {
            writeColumn(c, '0');
          }
        }
        writeColumn(column, char);
        integerSeen++;
      case DigitToken(:final String char) when k < slash:
        final int index = k - numeratorStart;
        if (blankFraction) {
          out.text(_blank(char));
          break;
        }
        if (index == 0 && numeratorDigits.length > numeratorColumns) {
          // Digits beyond the placeholders go before the first one.
          out.text(
            numeratorDigits.substring(
              0,
              numeratorDigits.length - numeratorColumns,
            ),
          );
        }
        // Columns counted from the right.
        final int column = numeratorColumns - 1 - index;
        out.text(
          column < numeratorDigits.length
              ? numeratorDigits[numeratorDigits.length - 1 - column]
              : _blank(char),
        );
      case DigitToken(:final String char) when k < denominatorEnd:
        final int index = k - slash - 1;
        // The denominator pads on the right with spaces under every
        // placeholder: a `0` there would change the value shown.
        out.text(
          blankFraction
              ? _blank(char)
              : (index < denominatorDigits.length
                    ? denominatorDigits[index]
                    : ' '),
        );
      case DigitToken():
        // A placeholder after the fraction: not part of the layout.
        break;
      case FractionSlashToken():
        out.text(blankFraction ? (blankAsSpace ? ' ' : '') : '/');
      case FixedDenominatorToken():
        out.text(
          blankFraction
              ? (blankAsSpace ? ' ' * denominatorDigits.length : '')
              : denominatorDigits,
        );
      case DecimalPointToken():
        out.text(locale.decimalSeparator);
      case CommaToken():
        if (k < numeratorStart && commas[k] == _Comma.literal) out.text(',');
      case PercentToken():
        out.text('%');
      case LiteralToken(:final String text):
        out.text(text);
      case LocaleTagToken(:final String currency):
        out.text(currency);
      case PaddingToken(:final String char):
        out.add(XlsxFormatPadding(char));
      case FillToken(:final String char):
        out.add(XlsxFormatFill(char));
      case TextToken() ||
          GeneralToken() ||
          ExponentToken() ||
          DateToken() ||
          AmPmToken() ||
          FractionalSecondsToken() ||
          CalendarToken() ||
          SystemFormatToken() ||
          UnsupportedToken():
        break;
    }
  }
  return out.result;
}

/// 10^[n] for `0 <= n <= 9`.
int _pow10(int n) {
  var result = 1;
  for (var k = 0; k < n; k++) {
    result *= 10;
  }
  return result;
}

/// The fraction closest to [x], `0 <= x < 1`, with a denominator from 1
/// to [maxDenominator]; of two equally close, the one with the smaller
/// denominator.
///
/// It walks the continued fraction of [x] to the last convergent whose
/// denominator fits, then checks the largest semiconvergent that fits
/// too (`0.14159` with denominators to 99 is `14/99`, not the convergent
/// `1/7`). Every numerator and denominator stays below [maxDenominator],
/// so they are exact `int`s on the VM and in JavaScript.
({int numerator, int denominator}) _bestFraction(double x, int maxDenominator) {
  // The convergents before the last and the last: p/q.
  var previousP = 0;
  var previousQ = 1;
  var p = 1;
  var q = 0;
  var rest = x;
  for (var step = 0; step < 64; step++) {
    final double term = rest.floorToDouble();
    final double nextQ = term * q + previousQ;
    if (nextQ > maxDenominator) {
      final int k = (maxDenominator - previousQ) ~/ q;
      final int semiP = previousP + k * p;
      final int semiQ = previousQ + k * q;
      final double convergentError = (x - p / q).abs();
      final double semiError = (x - semiP / semiQ).abs();
      return semiError < convergentError
          ? (numerator: semiP, denominator: semiQ)
          : (numerator: p, denominator: q);
    }
    final int a = term.toInt();
    final int nextP = a * p + previousP;
    previousP = p;
    previousQ = q;
    p = nextP;
    q = nextQ.toInt();
    final double remainder = rest - term;
    if (remainder == 0) break;
    rest = 1 / remainder;
  }
  return (numerator: p, denominator: q);
}

/// The index of the decimal point in [tokens], or their length.
int _pointIndex(List<FormatToken> tokens) {
  final int point = tokens.indexWhere(
    (FormatToken t) => t is DecimalPointToken,
  );
  return point < 0 ? tokens.length : point;
}

/// The role of each token of [tokens] that is a [CommaToken], null for any
/// other token; [point] is the decimal point's index.
List<_Comma?> _classifyCommas(List<FormatToken> tokens, int point) {
  final List<_Comma?> roles = List<_Comma?>.filled(tokens.length, null);
  bool digitIn(int from, int to) {
    for (var k = from; k < to; k++) {
      if (tokens[k] is DigitToken) return true;
    }
    return false;
  }

  for (var k = 0; k < tokens.length; k++) {
    if (tokens[k] is! CommaToken) continue;
    // The part the comma stands in: the integer part before the point,
    // the fraction part after it.
    final int partStart = k < point ? 0 : point + 1;
    final int partEnd = k < point ? point : tokens.length;
    final bool before = digitIn(0, k);
    final bool beforeInPart = digitIn(partStart, k);
    final bool afterInPart = digitIn(k + 1, partEnd);
    if (!before) {
      roles[k] = _Comma.literal;
    } else if (afterInPart) {
      roles[k] = beforeInPart && k < point ? _Comma.group : _Comma.ignored;
    } else {
      roles[k] = _Comma.scale;
    }
  }
  return roles;
}

/// Writes integer column [c] of [digits] (columns counted from the right,
/// from 0), shown as [placeholder] where [digits] has none, and the
/// [groupSeparator] after it when grouping is on (non-null) and the
/// column starts a group of three.
void _writeColumn(
  _Parts out,
  String digits,
  int c,
  String placeholder,
  String? groupSeparator,
) {
  final String shown = c < digits.length
      ? digits[digits.length - 1 - c]
      : _blank(placeholder);
  out.text(shown);
  if (groupSeparator != null && c > 0 && c % 3 == 0 && shown.isNotEmpty) {
    // A `?` column's separator is a space too.
    out.text(shown == ' ' ? ' ' : groupSeparator);
  }
}

/// What [placeholder] shows where there is no significant digit.
String _blank(String placeholder) => switch (placeholder) {
  '0' => '0',
  '?' => ' ',
  _ => '',
};

/// [digits] without leading zeros; `0` is empty.
String _withoutLeadingZeros(String digits) {
  var first = 0;
  while (first < digits.length && digits.codeUnitAt(first) == 0x30) {
    first++;
  }
  return digits.substring(first);
}

/// The index of the last digit of [digits] that is not `0`, or -1.
int _lastNonZero(String digits) {
  for (var k = digits.length - 1; k >= 0; k--) {
    if (digits.codeUnitAt(k) != 0x30) return k;
  }
  return -1;
}

int _max(int a, int b) => a > b ? a : b;

int _min(int a, int b) => a < b ? a : b;

/// [a] divided by the positive [b], rounded toward minus infinity.
int _floorDiv(int a, int b) => a >= 0 ? a ~/ b : -((-a + b - 1) ~/ b);

/// The parts of a result, with adjacent text merged.
final class _Parts {
  final List<XlsxFormatPart> _parts = <XlsxFormatPart>[];
  final StringBuffer _text = StringBuffer();

  /// Appends [text] to the current text part.
  void text(String text) => _text.write(text);

  /// Appends [part] after the current text.
  void add(XlsxFormatPart part) {
    _flush();
    _parts.add(part);
  }

  void _flush() {
    if (_text.isEmpty) return;
    _parts.add(XlsxFormatText(_text.toString()));
    _text.clear();
  }

  /// The parts, the last text included.
  List<XlsxFormatPart> get result {
    _flush();
    return _parts;
  }
}
