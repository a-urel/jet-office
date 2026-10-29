/// Excel's `General` format: a number fitted into a width.
///
/// New in jet_office; Quds has no number format engine. [renderGeneral]
/// shows a number in at most `width` characters, the sign not counted
/// (ECMA-376 §18.8.30, spec §5.3): an integer that fits in full, else
/// fixed notation with the most significant digits that fit, else
/// scientific notation. At Excel's default width of 11 it agrees with
/// SheetJS SSF and numfmt. Rounding works on the number's decimal digits
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
/// zeros count toward [width]. Fixed notation is used when the first
/// significant digit has an exponent from -4 to `width - 1` and at least
/// one significant digit fits; otherwise the result is scientific,
/// `1.23457E+11`, with at least two exponent digits. Digits are rounded
/// half away from zero and trailing zeros are dropped.
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

  if (exponent > -5 && exponent < width) {
    final String? fixed = _fixed(value, digits, exponent, width, separator);
    if (fixed != null) return fixed;
  }
  return _scientific(value, digits.length, exponent, width, separator);
}

/// [value] in fixed notation with the most of its [digits] that fit in
/// [width], or null when not one significant digit fits.
///
/// [exponent] is that of the first digit, `-5 < exponent < width`.
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
  final int shown = exponent < 0
      ? _min(digits.length, width - 1 + exponent)
      : _max(exponent + 1, _min(digits.length, width - 1));
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
  // `E+XX`: the letter, the sign and at least two digits.
  final int exponentLength = 2 + _max(2, '${exponent.abs()}'.length);
  // The mantissa is one digit, or `d.ddd` with the separator.
  final int room = width - exponentLength;
  final int shown = room >= 3 ? _min(length, room - 1) : 1;
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
