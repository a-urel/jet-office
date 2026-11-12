/// The values of a chart part as text: numbers as Excel writes them in a
/// `c:v`, and dates as serial numbers of the 1900 date system.
///
/// Not ported from Quds; written for jet_office.
///
/// A chart part stores every number of its caches as text and every date as
/// the serial number Excel would store in the cell. This file holds the one
/// spelling of a number the chart writer uses, and the conversion between a
/// [DateTime] and a serial in the chart's date system (`c:date1904 0`, the
/// only one the writer writes).
///
/// This layer imports `opc`, `xml`, `common`, `jet_charts_core` and `jet_core`
/// only, never `xlsx` or `docx` (decisions 0014 and 0015).
library;

import '../../xml/xml_escape.dart';
import '../../xml/xml_number.dart';

/// The text of [v] in a chart part: the shortest text that reads back as
/// [v], with no `.0` on a whole number and an upper-case `E` in an exponent.
///
/// `1` is `1`, `0.5` is `0.5`, `0.1 + 0.2` is `0.30000000000000004`, `1e21`
/// is `1E+21` and `1.5e-7` is `1.5E-7`; negative zero is `0`. The text is the
/// same on the VM and on the web (it is `formatXmlDouble`'s, with the
/// exponent's letter in upper case, as Excel writes it).
///
/// Throws an [ArgumentError] when [v] is `NaN` or infinite; the writer leaves
/// such a value out instead.
String drawingNumberText(double v) => formatXmlDouble(v).replaceFirst('e', 'E');

/// Midnight of 1899-12-30, the day the serials from 1 March 1900 on count
/// from.
final DateTime _epoch = DateTime.utc(1899, 12, 30);

/// Midnight of 1904-01-01, serial 0 of the 1904 date system.
final DateTime _epoch1904 = DateTime.utc(1904, 1, 1);

/// The serial of the first real day after Excel's phantom 29 February 1900.
const int _firstMarch1900 = 61;

/// The serial of Excel's phantom 29 February 1900.
const int _phantomDay = 60;

const int _msPerDay = 86400000;

/// The largest serial, either way, that [drawingDateOf] converts: well inside
/// what a [DateTime] holds.
const double _maxSerial = 9e7;

/// The serial number of [d] in Excel's 1900 date system, with the time of day
/// as the fraction.
///
/// Serial 1 is 1900-01-01. Excel counts a 29 February 1900 that never was, so
/// 1900-02-28 is 59 and 1900-03-01 is 61; no date gives 60. `DateTime(2026,
/// 1, 1)` is 46023. Only the wall-clock fields are used (`isUtc` and the time
/// zone are ignored), down to the microsecond. A date before 1900-01-01
/// counts on down through 0 and the negative numbers, which Excel does not
/// show as dates.
///
/// With [date1904] the serial counts in the 1904 date system instead: 0 is
/// 1904-01-01, there is no phantom day, and the serial is 1,462 lower than
/// the 1900 one.
double drawingSerialOf(DateTime d, {bool date1904 = false}) {
  final DateTime day = DateTime.utc(d.year, d.month, d.day);
  final int whole;
  if (date1904) {
    whole = day.difference(_epoch1904).inDays;
  } else {
    final int days = day.difference(_epoch).inDays;
    whole = days < _firstMarch1900 ? days - 1 : days;
  }
  final int micros =
      ((d.hour * 60 + d.minute) * 60 + d.second) * 1000000 +
      d.millisecond * 1000 +
      d.microsecond;
  return whole + micros / (_msPerDay * 1000);
}

/// The date of [serial] in Excel's 1900 date system, the inverse of
/// [drawingSerialOf], as a local [DateTime] of those wall-clock fields.
///
/// The fraction is the time of day, rounded to the millisecond (a time that
/// rounds to midnight is the next day), and the result is built from its
/// fields. Serial 59 is
/// 1900-02-28 and 61 is 1900-03-01; Excel's phantom 29 February 1900 (60, and
/// any time on it) reads as 1900-03-01, the day a [DateTime] makes of that
/// date. With [date1904] the serial is in the 1904 date system (0 is
/// 1904-01-01, no phantom day). Throws an [ArgumentError] when [serial] is not
/// finite or beyond 90,000,000 either way.
DateTime drawingDateOf(double serial, {bool date1904 = false}) {
  if (!serial.isFinite || serial.abs() > _maxSerial) {
    throw ArgumentError.value(serial, 'serial', 'is not a date serial');
  }
  int whole = serial.floor();
  int ms = ((serial - whole) * _msPerDay).round();
  if (ms >= _msPerDay) {
    // A time that rounds up to midnight is the next day.
    whole += 1;
    ms -= _msPerDay;
  }
  final DateTime day;
  if (date1904) {
    day = _epoch1904.add(Duration(days: whole));
  } else {
    if (whole == _phantomDay) {
      whole = _firstMarch1900;
    }
    day = _epoch.add(Duration(days: whole < _phantomDay ? whole + 1 : whole));
  }
  // Every field given, so a day of a daylight saving change cannot move the
  // hour as adding milliseconds to midnight could.
  return DateTime(
    day.year,
    day.month,
    day.day,
    ms ~/ 3600000,
    ms ~/ 60000 % 60,
    ms ~/ 1000 % 60,
    ms % 1000,
  );
}

/// [text] protected from ST_Xstring decoding, for the text of a chart part
/// that Excel decodes: a `c:v` of a series name or a text category, a `c:f`
/// and a `c:formatCode`.
///
/// Excel reads `_xHHHH_` (four hexadecimal digits) in such text as the
/// character U+HHHH, so every `_` that starts one is written `_x005F_`, the
/// escape of `_`: `_x0041_` is written `_x005F_x0041_`, as the cell writer
/// writes cell text. The text of a typed title (`a:t`) is not ST_Xstring and
/// is not escaped. Returns [text] itself when it holds no `_x`.
String drawingEscapeXstring(String text) => escapeXstring(text);

/// The inverse of [drawingEscapeXstring], for a reader: every `_xHHHH_` in
/// [text] read as U+HHHH, left to right once, so `_x005F_x0041_` gives
/// `_x0041_`; two escapes that spell a surrogate pair join into one
/// character, and a lone surrogate escape is kept as written.
String drawingUnescapeXstring(String text) => decodeXstring(text);
