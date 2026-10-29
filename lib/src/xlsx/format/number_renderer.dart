/// The renderer of number sections.
///
/// New in jet_office; Quds has no number format engine. [renderNumber]
/// lays a number out in the section [chooseNumberSection] picked: digit
/// placeholders, grouping and scaling commas, percent signs, literals,
/// padding and fill (spec §5.2). Scaling and rounding work on the
/// number's decimal digits ([ExcelNumber.shift], [ExcelNumber.toFixed]),
/// never on a `double`, so the result is exact and the same on the VM and
/// in JavaScript.
library;

import 'excel_number.dart';
import 'format_code.dart';
import 'format_locale.dart';
import 'formatted_value.dart';
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
  // Fraction and General sections are laid out as fixed point, their own
  // tokens left out, until their renderers exist.
  _Layout.fixed ||
  _Layout.fraction ||
  _Layout.general => _renderFixed(section, value, showMinus, locale),
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

  /// Writes integer column [c] (shown as [placeholder]) and the group
  /// separator after it.
  void writeColumn(int c, String placeholder) {
    final String shown = c < integerDigits.length
        ? integerDigits[integerDigits.length - 1 - c]
        : _blank(placeholder);
    out.text(shown);
    if (grouping && c > 0 && c % 3 == 0 && shown.isNotEmpty) {
      // A `?` column's separator is a space too.
      out.text(shown == ' ' ? ' ' : locale.groupSeparator);
    }
  }

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
      case TextToken() ||
          GeneralToken() ||
          ExponentToken() ||
          FractionSlashToken() ||
          DateToken() ||
          AmPmToken():
        // Not part of a fixed-point layout.
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
          DateToken() ||
          AmPmToken():
        break;
    }
  }
  return out.result;
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
