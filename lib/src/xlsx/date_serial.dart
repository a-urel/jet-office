/// Conversion of calendar dates to Excel's 1900 date-system serial numbers.
///
/// Excel counts days from 1899-12-31 (serial 0). It wrongly treats 1900 as a
/// leap year, so serial 60 is the phantom 1900-02-29. This library never
/// produces 60: dates up to 1900-02-28 map to 1 to 59 and dates from
/// 1900-03-01 on map to 61 and up.
///
/// Only the wall-clock fields of a [DateTime] are used; `isUtc` and the time
/// zone offset are ignored. This file is new in jet_office; Quds wrote
/// `DateTime` values as strings.
library;

final DateTime _epoch = DateTime.utc(1899, 12, 30);
const int _microsPerDay = 86400 * 1000000;

/// Returns the Excel serial number of the date [year]-[month]-[day].
///
/// Returns `null` for dates before 1900-01-01, which have no serial; the
/// caller writes those as text. Throws an [ArgumentError] if the date does not
/// exist, for example month 13 or 30 February.
int? dateSerial(int year, int month, int day) {
  final date = DateTime.utc(year, month, day);
  // Dart normalizes out-of-range fields (2026-02-30 becomes 2026-03-02), so a
  // date that does not round-trip its fields does not exist.
  if (date.year != year || date.month != month || date.day != day) {
    throw ArgumentError('Invalid date: $year-$month-$day.');
  }
  // Whole days between UTC midnights: no DST gaps, always exact.
  final days = date.difference(_epoch).inDays;
  if (days < 2) return null; // before 1900-01-01
  // Days before 1900-03-01 skip Excel's phantom 29 February 1900.
  return days < 61 ? days - 1 : days;
}

/// Returns the Excel serial number of [value], with the time of day as the
/// fraction.
///
/// Uses the wall-clock fields only. Returns `null` for values before
/// 1900-01-01. The fraction is
/// `(h*3600 + m*60 + s + ms/1000 + us/1e6) / 86400`.
double? dateTimeSerial(DateTime value) {
  final days = dateSerial(value.year, value.month, value.day);
  if (days == null) return null;
  final micros =
      ((value.hour * 60 + value.minute) * 60 + value.second) * 1000000 +
      value.millisecond * 1000 +
      value.microsecond;
  return days + micros / _microsPerDay;
}
