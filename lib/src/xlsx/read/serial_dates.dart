/// Exact mapping of Excel serial numbers and ISO 8601 text to dates and
/// durations, the reverse of `lib/src/xlsx/date_serial.dart`.
///
/// A serial arrives as the digit string of an `XlsxDecimal` (`-?\d+(\.\d+)?`),
/// never as a `double`, so the milliseconds are exact: the integer part times
/// 86,400,000 plus the fraction times 86,400,000 computed with `BigInt` on the
/// fraction's first 30 digits, rounded half up; later digits cannot change the
/// result except on an exact half, which already rounds up. The integer part is
/// checked against the range before any arithmetic, so a hostile file cannot
/// make it large; every `int` here stays below 2^53, which keeps the result
/// identical on the VM and on the web.
///
/// Dates are `DateTime.utc` values built from the wall-clock fields. Durations
/// are `Duration`s. A value no date or duration can have yields a warning code
/// instead of a value; exactly one of the two is non-null.
///
/// This file is new in jet_office; Quds has no counterpart.
library;

import '../warnings.dart';

const int _msPerDay = 86400000;
const int _maxDigits = 9;
const int _maxSerial1900 = 2958465; // 9999-12-31
const int _maxSerial1904 = 2957003; // 9999-12-31
const int _maxDurationDays = 100000;
const int _fractionDigits = 30;

final BigInt _msPerDayBig = BigInt.from(_msPerDay);
final BigInt _scale = BigInt.from(10).pow(_fractionDigits);

/// The split of a serial's digits: sign, integer part and the milliseconds of
/// its fraction.
typedef _Parts = ({bool negative, int whole, int fractionMs});

/// Converts [digits], an `XlsxDecimal.digits` string, to a UTC date and time.
///
/// [date1904] selects the 1904 date system. The result is `(date: ..)` or, for
/// a serial no date can have, `(warning: ..)`:
/// [XlsxWarningCode.serialOutOfRange] for a negative serial or one beyond
/// 9999-12-31, and [XlsxWarningCode.phantomLeapDay] for serial 60 of the 1900
/// system (29 February 1900, which never existed), judged after rounding to
/// the millisecond.
({DateTime? date, XlsxWarningCode? warning}) serialToDateTime(
  String digits, {
  required bool date1904,
}) {
  const ({DateTime? date, XlsxWarningCode? warning}) outOfRange = (
    date: null,
    warning: XlsxWarningCode.serialOutOfRange,
  );
  if (digits.startsWith('-')) return outOfRange;
  final int max = date1904 ? _maxSerial1904 : _maxSerial1900;
  final _Parts? parts = _split(digits, max);
  if (parts == null) return outOfRange;
  // whole <= max, so this is below 2^53.
  final int total = parts.whole * _msPerDay + parts.fractionMs;
  final int day = total ~/ _msPerDay;
  final int timeMs = total % _msPerDay;
  if (day > max) return outOfRange;
  final DateTime base;
  if (date1904) {
    base = DateTime.utc(1904, 1, 1).add(Duration(days: day));
  } else if (day == 0) {
    base = DateTime.utc(1899, 12, 31);
  } else if (day < 60) {
    base = DateTime.utc(1900, 1, 1).add(Duration(days: day - 1));
  } else if (day == 60) {
    return (date: null, warning: XlsxWarningCode.phantomLeapDay);
  } else {
    base = DateTime.utc(1899, 12, 30).add(Duration(days: day));
  }
  return (date: base.add(Duration(milliseconds: timeMs)), warning: null);
}

/// Converts [digits], an `XlsxDecimal.digits` string, to a [Duration] of that
/// many days, rounded to the millisecond. The sign is kept.
///
/// A magnitude of 100,000 days or more yields
/// [XlsxWarningCode.serialOutOfRange].
({Duration? duration, XlsxWarningCode? warning}) serialToDuration(
  String digits,
) {
  final _Parts? parts = _split(digits, _maxDurationDays - 1);
  if (parts == null) {
    return (duration: null, warning: XlsxWarningCode.serialOutOfRange);
  }
  final int ms = parts.whole * _msPerDay + parts.fractionMs;
  return (
    duration: Duration(milliseconds: parts.negative ? -ms : ms),
    warning: null,
  );
}

/// Splits [digits] into sign, integer part and rounded fraction milliseconds.
///
/// Returns `null` when the integer part exceeds [maxWhole] (checked by length
/// first, before parsing). The fraction may be thousands of digits long; only
/// only its first 30 are used.
_Parts? _split(String digits, int maxWhole) {
  final bool negative = digits.startsWith('-');
  final int start = negative ? 1 : 0;
  final int dot = digits.indexOf('.');
  final int wholeEnd = dot < 0 ? digits.length : dot;
  // Skip leading zeros so a long run of them is not "too long".
  int first = start;
  while (first < wholeEnd - 1 && digits.codeUnitAt(first) == 0x30) {
    first++;
  }
  if (wholeEnd - first > _maxDigits) return null;
  final int whole = int.parse(digits.substring(first, wholeEnd));
  if (whole > maxWhole) return null;
  int fractionMs = 0;
  if (dot >= 0) {
    final String fraction = digits.substring(dot + 1);
    final String head = fraction.length > _fractionDigits
        ? fraction.substring(0, _fractionDigits)
        : fraction.padRight(_fractionDigits, '0');
    final BigInt product = BigInt.parse(head) * _msPerDayBig;
    final BigInt quotient = product ~/ _scale;
    final BigInt remainder = product - quotient * _scale;
    // Half up. A non-zero tail past the 30th digit makes an exact half
    // "above half", which rounds up like the half itself, so it needs no
    // separate bit.
    final bool up = remainder * BigInt.two >= _scale;
    fractionMs = quotient.toInt() + (up ? 1 : 0);
  }
  return (negative: negative, whole: whole, fractionMs: fractionMs);
}

final RegExp _iso = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})'
  r'(?:T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?'
  r'(?:(Z)|([+-])(\d{2}):?(\d{2}))?)?$',
);

/// Parses ISO 8601 [text] to a UTC date and time, or returns `null`.
///
/// The grammar is `YYYY-MM-DD`, optionally followed by `Thh:mm[:ss[.f+]]` and
/// then `Z` or `±hh:mm` / `±hhmm`; years 0001 to 9999. An offset is
/// subtracted, so the result is the UTC wall clock, and an offset needs a
/// time. The fraction of a second rounds to the millisecond. Anything else,
/// time-only text and impossible dates included, returns `null`.
DateTime? parseIsoDateTime(String text) {
  final RegExpMatch? m = _iso.firstMatch(text);
  if (m == null) return null;
  final int year = int.parse(m[1]!);
  final int month = int.parse(m[2]!);
  final int day = int.parse(m[3]!);
  if (year < 1) return null;
  final DateTime date = DateTime.utc(year, month, day);
  // Dart normalizes out-of-range fields, so a date that does not keep its
  // fields does not exist.
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  if (m[4] == null) return date;
  final int hour = int.parse(m[4]!);
  final int minute = int.parse(m[5]!);
  final int second = m[6] == null ? 0 : int.parse(m[6]!);
  if (hour > 23 || minute > 59 || second > 59) return null;
  int ms = 0;
  final String? fraction = m[7];
  if (fraction != null) {
    final String f = fraction.padRight(4, '0');
    ms = int.parse(f.substring(0, 3));
    if (f.codeUnitAt(3) >= 0x35) ms++;
  }
  Duration offset = Duration.zero;
  if (m[9] != null) {
    final int offHours = int.parse(m[10]!);
    final int offMinutes = int.parse(m[11]!);
    if (offHours > 23 || offMinutes > 59) return null;
    offset = Duration(hours: offHours, minutes: offMinutes);
    if (m[9] == '-') offset = -offset;
  }
  return date
      .add(Duration(hours: hour, minutes: minute, seconds: second))
      .add(Duration(milliseconds: ms))
      .subtract(offset);
}
