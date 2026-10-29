/// Serials, calendar fields and Excel's two date systems.
///
/// New in jet_office; Quds has no number format engine. A date section
/// shows a serial's calendar fields (spec §5.4): [serialToFields] rounds
/// the serial to the second, or to the fraction of a second the section
/// shows, and splits it into a date, a time and a weekday.
/// [dateTimeToSerial] and [durationToSerial] turn the caller's `DateTime`
/// and `Duration` values into serials first, so every value takes the same
/// path.
///
/// No `double` arithmetic touches a serial: the rounding is `BigInt` on the
/// serial's decimal digits, and every `int` stays below 2^53, so the result
/// is the same on the VM and in JavaScript.
library;

import '../values.dart';
import 'excel_number.dart';

/// The last serial of the 1900 system, 9999-12-31.
const int _maxSerial1900 = 2958465;

/// The last serial of the 1904 system, 9999-12-31.
const int _maxSerial1904 = 2957003;

/// Days from 1899-12-30 to 1904-01-01, day 0 of the 1904 system.
const int _days1904 = 1462;

/// Days from 1970-01-01 to 1899-12-30.
const int _epochDays = -25569;

const int _secondsPerDay = 86400;
const int _msPerDay = 86400000;
const int _microsPerDay = 86400000000;

/// The magnitude of a `Duration`, in days, from which only its whole days
/// count: from here its microseconds pass 2^53.
const int _maxDurationDays = 100000;

/// The decimals [dateTimeToSerial] and [durationToSerial] write before
/// Excel's 15 significant digits take over, and those [serialToFields]
/// reads.
const int _places = 20;

final BigInt _scale = BigInt.from(10).pow(_places);
final BigInt _halfScale = _scale ~/ BigInt.two;
final BigInt _microsPerDayBig = BigInt.from(_microsPerDay);

/// The calendar fields of a non-negative serial, rounded to a number of
/// decimals of a second.
///
/// The 1900 system keeps Excel's two quirks: serial 0 is 1900-01-00 (a
/// Saturday) and serial 60 is the phantom 1900-02-29 (a Wednesday).
final class ExcelDateFields {
  /// Creates the fields; [serialToFields] is the only caller.
  const ExcelDateFields({
    required this.year,
    required this.month,
    required this.day,
    required this.weekday,
    required this.hour,
    required this.minute,
    required this.second,
    required this.fraction,
    required this.totalSeconds,
  });

  /// The year, 1900 to 9999 (1904 to 9999 in the 1904 system).
  final int year;

  /// The month, 1 to 12.
  final int month;

  /// The day of the month, 1 to 31; 0 for serial 0 of the 1900 system.
  final int day;

  /// The day of the week, 0 for Sunday to 6 for Saturday.
  final int weekday;

  /// The hour, 0 to 23.
  final int hour;

  /// The minute, 0 to 59.
  final int minute;

  /// The second, 0 to 59.
  final int second;

  /// The fraction of the second in the rounding's units, 0 to
  /// 10^fractionDigits - 1 (always 0 with no fraction digits).
  final int fraction;

  /// The whole seconds from serial 0, after rounding, for the elapsed
  /// tokens `[h]`, `[m]` and `[s]`.
  final int totalSeconds;

  /// The fields as `yyyy-mm-dd hh:mm:ss.fraction (weekday)`, for
  /// diagnostics.
  @override
  String toString() {
    String two(int n) => n.toString().padLeft(2, '0');
    return '$year-${two(month)}-${two(day)} '
        '${two(hour)}:${two(minute)}:${two(second)}.$fraction '
        '(weekday $weekday)';
  }
}

/// The calendar fields of [serial] in the 1900 system, or in the 1904
/// system when [date1904] is true, with the time rounded half up to
/// [fractionDigits] decimals of a second.
///
/// The rounding comes first and carries through minutes and hours into the
/// day (`0.99999999` is 1900-01-01 00:00:00). Returns null when [serial]
/// is negative and not zero (`-1E-20` included), or when it rounds past
/// 9999-12-31 23:59:59 of the system (2958465 in the 1900 system, 2957003
/// in the 1904 system). A [fractionDigits] outside 0 to 3 throws an
/// [ArgumentError].
ExcelDateFields? serialToFields(
  ExcelNumber serial, {
  required bool date1904,
  required int fractionDigits,
}) {
  if (fractionDigits < 0 || fractionDigits > 3) {
    throw ArgumentError.value(
      fractionDigits,
      'fractionDigits',
      'Must be 0 to 3',
    );
  }
  if (serial.negative) return null;
  final int max = date1904 ? _maxSerial1904 : _maxSerial1900;
  // Bound the work before any arithmetic: a serial of 1E300 has 300 digits.
  if (serial.compareTo(ExcelNumber.parse('${max + 1}')) >= 0) return null;
  // At most 15 significant digits below 2958466, so 20 decimals hold them
  // all except the far end of a tiny serial, which cannot move a rounding
  // to a thousandth of a second.
  final ({String whole, String fraction}) fixed = serial.toFixed(_places);
  final BigInt digits = BigInt.parse(fixed.whole + fixed.fraction);
  final int perSecond = _pow10(fractionDigits);
  final BigInt perDay = BigInt.from(_secondsPerDay * perSecond);
  final BigInt units = (digits * perDay + _halfScale) ~/ _scale;
  final BigInt dayBig = units ~/ perDay;
  if (dayBig > BigInt.from(max)) return null;
  // Below (max + 1) * 86,400,000, far from 2^53.
  final int unitCount = units.toInt();
  final int day = dayBig.toInt();
  final int totalSeconds = unitCount ~/ perSecond;
  final int secondOfDay = totalSeconds % _secondsPerDay;
  final ({int year, int month, int day}) date = _calendar(day, date1904);
  return ExcelDateFields(
    year: date.year,
    month: date.month,
    day: date.day,
    // Serial 0 of the 1900 system is a Saturday; day 0 of the 1904 system
    // was a Friday.
    weekday: (day + (date1904 ? 5 : 6)) % 7,
    hour: secondOfDay ~/ 3600,
    minute: secondOfDay ~/ 60 % 60,
    second: secondOfDay % 60,
    fraction: unitCount % perSecond,
    totalSeconds: totalSeconds,
  );
}

/// The serial of [value]'s wall-clock fields in the 1900 system, or in the
/// 1904 system when [date1904] is true, to Excel's 15 significant digits.
///
/// `isUtc` is ignored; milliseconds and microseconds are kept. A date
/// before the system's day 0 (1899-12-31, or 1904-01-01) is a negative
/// serial; dates before 1900-03-01 skip the phantom 1900-02-29, as the
/// writer does. A year above 9999 gives the system's last serial plus one
/// and a year below 1 gives -1, without any day arithmetic: both are
/// outside the range and show `#` in a date section. Never null and never
/// throws.
ExcelNumber dateTimeToSerial(DateTime value, {required bool date1904}) {
  final int max = date1904 ? _maxSerial1904 : _maxSerial1900;
  if (value.year > 9999) return ExcelNumber.parse('${max + 1}');
  if (value.year < 1) return ExcelNumber.parse('-1');
  // Whole days between UTC midnights; the milliseconds of year 1 are about
  // 6.2E13, below 2^53.
  final int fromEpoch =
      DateTime.utc(value.year, value.month, value.day).millisecondsSinceEpoch ~/
      _msPerDay;
  // Days from 1899-12-30.
  final int days = fromEpoch - _epochDays;
  final int serialDays = date1904
      ? days - _days1904
      : (days < 61 ? days - 1 : days);
  final int micros =
      ((value.hour * 60 + value.minute) * 60 + value.second) * 1000000 +
      value.millisecond * 1000 +
      value.microsecond;
  return _serial(
    BigInt.from(serialDays) * _microsPerDayBig + BigInt.from(micros),
  );
}

/// [value] in days, sign kept, to Excel's 15 significant digits.
///
/// A [value] of 100,000 days or more either way is its whole days only
/// (`inDays`): its microseconds pass 2^53 and would differ in JavaScript.
ExcelNumber durationToSerial(Duration value) {
  final int days = value.inDays;
  if (days >= _maxDurationDays || days <= -_maxDurationDays) {
    return ExcelNumber.parse('$days');
  }
  // Below 8.64E15, within 2^53.
  return _serial(BigInt.from(value.inMicroseconds));
}

/// The serial of [micros] microseconds from day 0: the days written with
/// [_places] decimals, rounded half away from zero, then read as Excel
/// reads a number.
ExcelNumber _serial(BigInt micros) {
  final bool negative = micros.isNegative;
  final BigInt scaled =
      (micros.abs() * _scale + _microsPerDayBig ~/ BigInt.two) ~/
      _microsPerDayBig;
  final String text = scaled.toString().padLeft(_places + 1, '0');
  final int point = text.length - _places;
  final String digits =
      '${negative ? '-' : ''}${text.substring(0, point)}.'
      '${text.substring(point)}';
  // The digits are finite, so this is never null.
  return ExcelNumber.from(XlsxDecimal(digits))!;
}

/// The date of serial day [day], 0 to the system's last.
({int year, int month, int day}) _calendar(int day, bool date1904) {
  final DateTime date;
  if (date1904) {
    date = DateTime.utc(1904, 1, 1 + day);
  } else if (day == 0) {
    return (year: 1900, month: 1, day: 0);
  } else if (day < 60) {
    date = DateTime.utc(1900, 1, day);
  } else if (day == 60) {
    return (year: 1900, month: 2, day: 29);
  } else {
    date = DateTime.utc(1899, 12, 30 + day);
  }
  return (year: date.year, month: date.month, day: date.day);
}

int _pow10(int n) {
  var result = 1;
  for (var k = 0; k < n; k++) {
    result *= 10;
  }
  return result;
}
