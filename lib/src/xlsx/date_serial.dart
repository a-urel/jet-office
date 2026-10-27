/// Conversion of calendar dates to Excel's 1900 date-system serial numbers.
///
/// Excel counts days from 1899-12-31 (serial 0). It wrongly treats 1900 as a
/// leap year, so serial 60 is the phantom 1900-02-29. This library never
/// produces 60: dates up to 1900-02-28 map to 1 to 59 and dates from
/// 1900-03-01 on map to 61 and up.
///
/// Excel stores dates from 1900-01-01 to 9999-12-31 only. Both functions
/// return `null` outside that range; the caller writes such values as text.
///
/// Only the wall-clock fields of a [DateTime] are used; `isUtc` and the time
/// zone offset are ignored. This file is new in jet_office; Quds wrote
/// `DateTime` values as strings.
library;

final DateTime _epoch = DateTime.utc(1899, 12, 30);
const int _maxSerial = 2958465; // 9999-12-31
/// Years beyond this are outside `DateTime`'s range (about 275,760).
const int _maxDartYear = 270000;
const int _secondsPerDay = 86400;

/// Returns the Excel serial number of the date [year]-[month]-[day].
///
/// Returns `null` for dates outside Excel's range (before 1900-01-01 or after
/// 9999-12-31), which have no serial; the caller writes those as text.
/// Throws an [ArgumentError] if the date does not exist, for example month
/// 13 or 30 February.
int? dateSerial(int year, int month, int day) {
  if (year > _maxDartYear || year < -_maxDartYear) {
    // Beyond what DateTime holds, so DateTime.utc cannot check the date.
    if (month < 1 || month > 12 || day < 1 || day > _daysIn(year, month)) {
      throw ArgumentError('Invalid date: $year-$month-$day.');
    }
    return null;
  }
  final date = DateTime.utc(year, month, day);
  // Dart normalizes out-of-range fields (2026-02-30 becomes 2026-03-02), so a
  // date that does not round-trip its fields does not exist.
  if (date.year != year || date.month != month || date.day != day) {
    throw ArgumentError('Invalid date: $year-$month-$day.');
  }
  // Whole days between UTC midnights: no DST gaps, always exact.
  final days = date.difference(_epoch).inDays;
  if (days < 2) return null; // before 1900-01-01
  if (days > _maxSerial) return null; // after 9999-12-31
  // Days before 1900-03-01 skip Excel's phantom 29 February 1900.
  return days < 61 ? days - 1 : days;
}

/// Returns the Excel serial number of [value], with the time of day as the
/// fraction.
///
/// Uses the wall-clock fields only. The sub-second part (milliseconds and
/// microseconds) is dropped: Excel shows a serial rounded to the second, so
/// 23:59:59.999 would show as 00:00 on the next day. A caller who needs
/// milliseconds writes the serial as a `double` with a `ss.000` format.
/// Returns `null` for values outside Excel's range (before 1900-01-01 or
/// after 9999-12-31). The fraction is `(h*3600 + m*60 + s) / 86400`.
double? dateTimeSerial(DateTime value) {
  final days = dateSerial(value.year, value.month, value.day);
  if (days == null) return null;
  final seconds = (value.hour * 60 + value.minute) * 60 + value.second;
  return days + seconds / _secondsPerDay;
}

int _daysIn(int year, int month) {
  if (month == 2) {
    final bool leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    return leap ? 29 : 28;
  }
  return const <int>[4, 6, 9, 11].contains(month) ? 30 : 31;
}
