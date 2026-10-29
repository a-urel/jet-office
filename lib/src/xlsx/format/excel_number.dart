/// A cell's number as Excel holds it: at most 15 significant digits.
///
/// New in jet_office; Quds has no number format engine. [ExcelNumber.from]
/// turns a file's digits or a `num` into the number Excel shows (spec
/// §5.2, step 1); the renderers then scale and round it on its decimal
/// digits (step 2), never on a `double`, so the result is exact and the
/// same on the VM and in JavaScript.
library;

import '../values.dart';

/// The largest exponent magnitude [ExcelNumber.parse] keeps.
///
/// A double's exponent is within about ±330, so any larger one compares
/// and converts the same; the cap keeps every exponent a small `int`.
const int _maxExponent = 1000000000;

/// The smallest positive normal `double`; anything nearer zero is
/// subnormal, and Excel has no subnormal numbers.
const double _minNormal = 2.2250738585072014e-308;

/// A decimal number: a sign, significant digits and a decimal exponent.
///
/// The digits have no leading or trailing zeros, and the exponent is that
/// of the first digit, so `-120.01` is `-`, `12001` and `2`. Zero has no
/// digits and is never negative. Two equal numbers are `==`.
final class ExcelNumber implements Comparable<ExcelNumber> {
  const ExcelNumber._(this.negative, this._digits, this._exponent);

  /// The number Excel holds for [value], an [XlsxDecimal] or a `num`, or
  /// null for NaN or infinity.
  ///
  /// The value is parsed as a `double` and written back with 15
  /// significant digits, as Excel does when it loads a file: so
  /// `0.30000000000000004` is `0.3` and `9007199254740993` is
  /// `9007199254740990`. Digits too large for a `double` are infinity and
  /// give null; a subnormal `double` (below 2.2250738585072014E-308 in
  /// magnitude) is zero, as Excel has no denormals. Any other type of
  /// [value] throws an [ArgumentError].
  static ExcelNumber? from(Object value) {
    final double number = switch (value) {
      XlsxDecimal() => value.toDouble(),
      num() => value.toDouble(),
      _ => throw ArgumentError.value(
        value,
        'value',
        'Expected an XlsxDecimal or a num',
      ),
    };
    if (number.isNaN || number.isInfinite) return null;
    // Excel has no denormals: a subnormal double is zero.
    if (number.abs() < _minNormal) return parse('0');
    // Fixed (`2.67500000000000`) or exponential (`1.00000000000000e-7`),
    // depending on the magnitude; parse reads both.
    return parse(number.toStringAsPrecision(15));
  }

  /// The number [text] exactly, with no rounding to 15 digits.
  ///
  /// [text] is an optional sign, digits with at most one `.` (`.5` and
  /// `5.` are allowed) and an optional exponent `e` or `E` with an
  /// optional sign, the numbers a format condition holds. `-0` is zero.
  /// An exponent beyond ±10^9 is taken as ±10^9. Any other [text] throws
  /// an [ArgumentError].
  static ExcelNumber parse(String text) {
    final ExcelNumber? number = _parse(text);
    if (number == null) {
      throw ArgumentError.value(
        text,
        'text',
        'Expected an optional sign, digits with an optional "." and an '
            'optional exponent, such as "-1.5E3"',
      );
    }
    return number;
  }

  /// Whether the number is below zero. Zero is never negative.
  final bool negative;

  /// The significant digits, empty for zero.
  final String _digits;

  /// The decimal exponent of the first digit, 0 for zero.
  final int _exponent;

  /// Whether the number is zero.
  bool get isZero => _digits.isEmpty;

  /// The number without its sign.
  ExcelNumber abs() =>
      negative ? ExcelNumber._(false, _digits, _exponent) : this;

  /// The number times 10^[powerOfTen], exactly.
  ExcelNumber shift(int powerOfTen) =>
      isZero ? this : ExcelNumber._(negative, _digits, _exponent + powerOfTen);

  /// Compares the numbers by value, sign included.
  @override
  int compareTo(ExcelNumber other) {
    final int sign = _signum;
    final int otherSign = other._signum;
    if (sign != otherSign) return sign < otherSign ? -1 : 1;
    if (sign == 0) return 0;
    final int magnitude = _exponent != other._exponent
        ? (_exponent < other._exponent ? -1 : 1)
        : _digits.compareTo(other._digits).sign;
    return sign * magnitude;
  }

  /// The magnitude rounded half away from zero to [places] decimals.
  ///
  /// `whole` holds the whole digits with no sign, `'0'` when
  /// there are none; `fraction` holds exactly [places] digits. A carry may
  /// add a whole digit (`9.995` to two places is `10` and `00`). The sign
  /// is [negative]; a number that rounds to zero keeps it, and the caller
  /// decides. A negative [places] throws an [ArgumentError].
  ({String whole, String fraction}) toFixed(int places) {
    if (places < 0) {
      throw ArgumentError.value(places, 'places', 'Must not be negative');
    }
    // How many digits stand at or above 10^-places.
    final int keep = _exponent + places + 1;
    final String scaled;
    if (isZero || keep < 0) {
      scaled = '0';
    } else if (keep >= _digits.length) {
      scaled = _digits + '0' * (keep - _digits.length);
    } else {
      scaled = _roundAt(keep);
    }
    final String padded = scaled.padLeft(places + 1, '0');
    final int point = padded.length - places;
    return (
      whole: padded.substring(0, point),
      fraction: padded.substring(point),
    );
  }

  /// The first [n] significant digits rounded half away from zero, padded
  /// with zeros, and the decimal exponent of the first one.
  ///
  /// A carry moves the exponent (`99.96` to three digits is `100` and 2).
  /// Zero is [n] zeros and exponent 0. An [n] below 1 throws an
  /// [ArgumentError].
  ({String digits, int exponent}) toSignificant(int n) {
    if (n < 1) {
      throw ArgumentError.value(n, 'n', 'Must be at least 1');
    }
    if (isZero) return (digits: '0' * n, exponent: 0);
    if (n >= _digits.length) {
      return (digits: _digits.padRight(n, '0'), exponent: _exponent);
    }
    final String rounded = _roundAt(n);
    if (rounded.length > n) {
      // A carry: `999` became `1000`.
      return (digits: rounded.substring(0, n), exponent: _exponent + 1);
    }
    return (digits: rounded, exponent: _exponent);
  }

  /// The number as the nearest `double`.
  double toDouble() {
    if (isZero) return 0.0;
    return double.parse('${negative ? '-' : ''}0.${_digits}e${_exponent + 1}');
  }

  /// The first [keep] digits, `0 <= keep < length`, rounded half away from
  /// zero on the next digit; the result may be one digit longer.
  String _roundAt(int keep) {
    final String kept = _digits.substring(0, keep);
    if (_digits.codeUnitAt(keep) < 0x35) return kept.isEmpty ? '0' : kept;
    return _increment(kept);
  }

  int get _signum => isZero ? 0 : (negative ? -1 : 1);

  @override
  bool operator ==(Object other) =>
      other is ExcelNumber &&
      other.negative == negative &&
      other._digits == _digits &&
      other._exponent == _exponent;

  @override
  int get hashCode => Object.hash(negative, _digits, _exponent);

  /// The number in plain decimals when its exponent is within ±20, else
  /// as `1.5e300`; for diagnostics.
  @override
  String toString() {
    if (isZero) return '0';
    final String sign = negative ? '-' : '';
    if (_exponent.abs() > 20) {
      final String rest = _digits.length > 1 ? '.${_digits.substring(1)}' : '';
      return '$sign${_digits[0]}${rest}e$_exponent';
    }
    final ({String whole, String fraction}) parts = toFixed(
      _digits.length - _exponent - 1 < 0 ? 0 : _digits.length - _exponent - 1,
    );
    return parts.fraction.isEmpty
        ? '$sign${parts.whole}'
        : '$sign${parts.whole}.${parts.fraction}';
  }
}

/// [digits] plus one in the last place, as a digit string; empty is `0`.
String _increment(String digits) {
  final List<int> units = digits.codeUnits.toList();
  var k = units.length - 1;
  while (k >= 0 && units[k] == 0x39) {
    units[k] = 0x30;
    k--;
  }
  if (k < 0) return '1${String.fromCharCodes(units)}';
  units[k]++;
  return String.fromCharCodes(units);
}

bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

/// [text] as a number, or null when it is not one.
ExcelNumber? _parse(String text) {
  var k = 0;
  var negative = false;
  if (k < text.length && (text[k] == '+' || text[k] == '-')) {
    negative = text[k] == '-';
    k++;
  }
  final int intStart = k;
  while (k < text.length && _isDigit(text.codeUnitAt(k))) {
    k++;
  }
  final String whole = text.substring(intStart, k);
  var fraction = '';
  if (k < text.length && text[k] == '.') {
    k++;
    final int fractionStart = k;
    while (k < text.length && _isDigit(text.codeUnitAt(k))) {
      k++;
    }
    fraction = text.substring(fractionStart, k);
  }
  if (whole.isEmpty && fraction.isEmpty) return null;
  var exponent = 0;
  if (k < text.length && (text[k] == 'e' || text[k] == 'E')) {
    k++;
    var exponentNegative = false;
    if (k < text.length && (text[k] == '+' || text[k] == '-')) {
      exponentNegative = text[k] == '-';
      k++;
    }
    if (k >= text.length || !_isDigit(text.codeUnitAt(k))) return null;
    while (k < text.length && _isDigit(text.codeUnitAt(k))) {
      if (exponent < _maxExponent) {
        exponent = exponent * 10 + text.codeUnitAt(k) - 0x30;
      }
      k++;
    }
    if (exponent > _maxExponent) exponent = _maxExponent;
    if (exponentNegative) exponent = -exponent;
  }
  if (k != text.length) return null;
  final String all = whole + fraction;
  var first = 0;
  while (first < all.length && all.codeUnitAt(first) == 0x30) {
    first++;
  }
  if (first == all.length) return const ExcelNumber._(false, '', 0);
  var last = all.length;
  while (all.codeUnitAt(last - 1) == 0x30) {
    last--;
  }
  return ExcelNumber._(
    negative,
    all.substring(first, last),
    whole.length - 1 - first + exponent,
  );
}
