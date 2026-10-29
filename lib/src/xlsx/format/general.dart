/// Excel's `General` format: a number fitted into a width.
///
/// New in jet_office; Quds has no number format engine. [renderGeneral]
/// shows a number in at most `width` characters, the sign not counted
/// (ECMA-376 §18.8.30, spec §5.3): an integer that fits in full, else
/// fixed or scientific notation, whichever shows more significant digits
/// (a tie is fixed), as Excel for Mac does. Rounding works on the number's decimal digits
/// ([ExcelNumber.toFixed], [ExcelNumber.toSignificant]), never on a
/// `double`.
library;

import 'excel_number.dart';
import 'format_locale.dart';

/// The most significant digits Excel holds and `General` shows.
const int _maxDigits = 15;

/// [value] in `General` notation, in at most [width] characters where
/// that is possible, without a sign.
///
/// [value]'s sign is ignored; callers put a `-` in front. The decimal
/// separator is [locale]'s, and the separator and any leading `0.` and
/// zeros count toward [width]. Of fixed and scientific notation
/// (`1.23457E+11`, at least two exponent digits) the one that shows more
/// of the significant digits in [width] is used; a tie is fixed, so
/// `0.00001` stays fixed and `0.000012345678` is `1.23457E-05` at width
/// 11 (Excel for Mac, oracle cases u14). Fixed needs the first digit's
/// exponent below [width] and at least one significant digit to fit.
/// Digits are rounded half away from zero and trailing zeros are
/// dropped.
///
/// [width] is at least 1. When even one significant digit does not fit,
/// the result is the shortest scientific form, `5E-01`, longer than
/// [width] (Excel would fill the cell with `#`).
String renderGeneral(
  ExcelNumber value, {
  required int width,
  required XlsxFormatLocale locale,
}) {
  if (value.isZero) return '0';
  final ({String digits, int exponent}) significant = value.abs().toSignificant(
    _maxDigits,
  );
  final String digits = _withoutTrailingZeros(significant.digits);
  final int exponent = significant.exponent;
  final String separator = locale.decimalSeparator;

  // An integer that fits is shown in full.
  if (exponent >= digits.length - 1 && exponent < width) {
    return digits + '0' * (exponent + 1 - digits.length);
  }

  // The form that shows more significant digits wins; a tie is decimal.
  if (exponent < width &&
      _fixedDigits(digits.length, exponent, width) >=
          _scientificDigits(digits.length, exponent, width)) {
    final String? fixed = _fixed(value, digits, exponent, width, separator);
    if (fixed != null) return fixed;
  }
  return _scientific(value, digits.length, exponent, width, separator);
}

/// How many of [length] significant digits, the first with [exponent],
/// fixed notation shows in [width]: `0.` and `-exponent - 1` zeros come
/// first when [exponent] is negative.
int _fixedDigits(int length, int exponent, int width) => exponent < 0
    ? _min(length, width - 1 + exponent)
    : _max(exponent + 1, _min(length, width - 1));

/// How many of [length] significant digits, the first with [exponent],
/// scientific notation shows in [width]: the mantissa takes what `E+XX`
/// leaves, one digit at least.
int _scientificDigits(int length, int exponent, int width) {
  final int room = width - _exponentLength(exponent);
  return room >= 3 ? _min(length, room - 1) : 1;
}

/// `E+XX`: the letter, the sign and at least two digits.
int _exponentLength(int exponent) => 2 + _max(2, '${exponent.abs()}'.length);

/// [value] in fixed notation with the most of its [digits] that fit in
/// [width], or null when not one significant digit fits.
///
/// [exponent] is that of the first digit, below [width].
String? _fixed(
  ExcelNumber value,
  String digits,
  int exponent,
  int width,
  String separator,
) {
  // With k significant digits the text is `0.` and `-exponent - 1` zeros
  // and k digits when the exponent is negative (1 - exponent + k
  // characters), else the whole digits, the separator and the rest
  // (k + 1 characters, or exponent + 1 with no fraction).
  final int shown = _fixedDigits(digits.length, exponent, width);
  if (shown < 1) return null;
  final ({String whole, String fraction}) parts = value.abs().toFixed(
    shown - exponent - 1,
  );
  final String fraction = _withoutTrailingZeros(parts.fraction);
  final String text = fraction.isEmpty
      ? parts.whole
      : '${parts.whole}$separator$fraction';
  // A carry (`99999999999.5` to `100000000000`) can make it one too long.
  return text.length <= width ? text : null;
}

/// [value], which has [length] significant digits and whose first digit
/// has [exponent], in scientific notation fitted into [width].
String _scientific(
  ExcelNumber value,
  int length,
  int exponent,
  int width,
  String separator,
) {
  // The mantissa is one digit, or `d.ddd` with the separator.
  final int shown = _scientificDigits(length, exponent, width);
  final ({String digits, int exponent}) rounded = value.abs().toSignificant(
    shown,
  );
  final String mantissa = _withoutTrailingZeros(rounded.digits);
  final String rest = mantissa.length > 1
      ? '$separator${mantissa.substring(1)}'
      : '';
  final String sign = rounded.exponent < 0 ? '-' : '+';
  final String power = '${rounded.exponent.abs()}'.padLeft(2, '0');
  return '${mantissa[0]}${rest}E$sign$power';
}

/// [digits] without trailing zeros; may be empty.
String _withoutTrailingZeros(String digits) {
  var end = digits.length;
  while (end > 0 && digits.codeUnitAt(end - 1) == 0x30) {
    end--;
  }
  return digits.substring(0, end);
}

int _max(int a, int b) => a > b ? a : b;

int _min(int a, int b) => a < b ? a : b;
