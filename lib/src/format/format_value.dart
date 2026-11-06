/// The two value types the number format engine takes besides `num`,
/// `DateTime`, `Duration`, `String` and `bool`.
///
/// Moved from jet_office, where `FormatDecimal` and `FormatErrorValue` extend
/// these. The engine knows no file format, so it names its inputs plainly:
/// an exact decimal and an error value such as `#N/A`.
library;

final RegExp _decimalDigits = RegExp(r'^-?\d+(\.\d+)?$');

/// An exact decimal number, given digit for digit.
///
/// Use it where a `double` would show binary rounding, for example
/// `FormatDecimal('-1234.50')`: the formatter reads the digits as a `double`
/// and writes them back with 15 significant digits, as Excel does, so the
/// trailing zero of `1234.50` is the format code's business, not the
/// value's.
///
/// [digits] must be an optional minus sign, one or more digits, and
/// optionally a point followed by one or more digits. The constructor throws
/// an [ArgumentError] for anything else (a decimal comma, an exponent, a
/// leading plus sign, thousands separators, an empty string).
class FormatDecimal {
  /// Creates a decimal from [digits], for example `'12.30'`.
  FormatDecimal(this.digits) {
    if (!_decimalDigits.hasMatch(digits)) {
      throw ArgumentError.value(
        digits,
        'digits',
        'Expected an optional minus sign, digits and an optional ".digits" '
            'fraction, such as "-1234.50".',
      );
    }
  }

  /// The number as given.
  final String digits;

  /// The number as a `double`, rounded to the nearest representable value:
  /// `0.0` (or `-0.0`) when it is too small and `double.infinity` (or its
  /// negative) when it is too large.
  double toDouble() => double.parse(digits);

  @override
  bool operator ==(Object other) =>
      other is FormatDecimal && other.digits == digits;

  @override
  int get hashCode => digits.hashCode;

  @override
  String toString() => 'FormatDecimal($digits)';
}

/// An error value to format, such as `#N/A`.
///
/// The engine shows it as the locale's name for [code] (a code the locale
/// does not know shows as written) and ignores the format code.
class FormatErrorValue {
  /// The error value written as [code], such as `#N/A`.
  const FormatErrorValue(this.code);

  /// The code, such as `#N/A` or `#SPILL!`.
  final String code;

  @override
  bool operator ==(Object other) =>
      other is FormatErrorValue && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'FormatErrorValue($code)';
}
