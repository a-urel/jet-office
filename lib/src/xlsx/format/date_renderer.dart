/// The renderer of date and time sections.
///
/// New in jet_office; Quds has no number format engine. [renderDate] lays
/// a serial out in a section that has date or time tokens (spec §5.4): it
/// reads the serial's calendar fields with [serialToFields] and shows each
/// token from them, with month and day names from the renderer's locale.
/// Literals, `,`, `%`, a locale tag's currency, padding and fill show as
/// the number renderer shows them.
library;

import '../warnings.dart';
import 'excel_date.dart';
import 'excel_number.dart';
import 'format_code.dart';
import 'format_kind.dart';
import 'format_locale.dart';
import 'formatted_value.dart';

/// Renders [serial] with the date or time [section]; null when Excel
/// shows `#` (negative, out of range). In the 1904 system a negative
/// serial in a section with no date token (`d`, `y`, month `m`, `e`, `b`)
/// shows its absolute value with a `-` first. The result's `warning` is
/// `numberFormatUnsupported` when the section asks for what the engine
/// does not render; null for now.
///
/// Names (`mmm`, `mmmm`, `ddd`, `dddd`) come from [locale]. [date1904]
/// selects the 1904 date system. An `m` is a month or minutes by
/// [isMinuteToken]. Token lengths: `y` and
/// `yy` show two digits of the year, `yyy` and longer four; `mmmmm` shows
/// the first letter of the month name and six or more `m` the full name;
/// `dddd` and longer the full day name; `h`, `m` and `s` longer than two
/// show two digits; `e` the four-digit year; `b` and `bb` two digits of the
/// Buddhist year, `bbb` and longer four; `g` nothing.
///
/// The time is rounded to the second, or to the most fractional-second
/// digits the section shows, and then truncated to the units shown
/// (`h:mm` on 10:29:40 shows `10:29`). An `AM/PM` or `A/P` marker switches
/// `h` to the 12-hour clock: `AM/PM` in any case shows the locale's `am`
/// or `pm`, `A/P` its letters in the case written. Fractional seconds show
/// the locale's decimal separator. Elapsed `[h]`, `[m]` and `[s]` count
/// from serial 0, padded to their length; plain minutes and seconds next
/// to them are taken modulo 60.
///
/// Adjacent text is merged into one [XlsxFormatText], and empty text is
/// left out.
({List<XlsxFormatPart> parts, XlsxWarningCode? warning})? renderDate(
  FormatSection section,
  ExcelNumber serial, {
  required XlsxFormatLocale locale,
  required bool date1904,
}) {
  final List<DateToken> counted = <DateToken>[
    for (final FormatToken token in section.tokens)
      if (token is DateToken && countedDateLetters.contains(token.letter))
        token,
  ];

  // Ruling 4: in the 1904 system a negative value in a section without a
  // date token shows its absolute value with a leading minus; anywhere
  // else a negative value is `#`.
  final bool negativeTime =
      date1904 && serial.negative && !_hasDateToken(section, counted);
  var fractionDigits = 0;
  var twelveHour = false;
  for (final FormatToken token in section.tokens) {
    if (token is FractionalSecondsToken && token.digits > fractionDigits) {
      fractionDigits = token.digits;
    } else if (token is AmPmToken) {
      twelveHour = true;
    }
  }
  final ExcelDateFields? fields = serialToFields(
    negativeTime ? serial.abs() : serial,
    date1904: date1904,
    fractionDigits: fractionDigits,
  );
  if (fields == null) return null;

  final FormatPartsBuilder out = FormatPartsBuilder();
  // Like the number renderer's minus: first, and not on a value that
  // rounds to zero.
  if (negativeTime && (fields.totalSeconds > 0 || fields.fraction > 0)) {
    out.text('-');
  }
  var k = 0;
  for (final FormatToken token in section.tokens) {
    switch (token) {
      case DateToken(:final String letter):
        if (countedDateLetters.contains(letter)) {
          final bool minutes = letter == 'm' && isMinuteToken(counted, k);
          out.text(
            _dateText(
              token,
              fields,
              locale,
              minutes: minutes,
              twelveHour: twelveHour,
            ),
          );
          k++;
        } else {
          out.text(_eraText(token, fields));
        }
      case LiteralToken(:final String text):
        out.text(text);
      case CommaToken():
        out.text(',');
      case PercentToken():
        out.text('%');
      case LocaleTagToken(:final String currency):
        out.text(currency);
      case PaddingToken(:final String char):
        out.add(XlsxFormatPadding(char));
      case FillToken(:final String char):
        out.add(XlsxFormatFill(char));
      case AmPmToken(:final String text):
        out.text(_amPmText(text, fields.hour < 12, locale));
      case FractionalSecondsToken(:final int digits):
        out.text(
          locale.decimalSeparator +
              _pad(fields.fraction, fractionDigits).substring(0, digits),
        );
      case CalendarToken() ||
          SystemFormatToken() ||
          UnsupportedToken() ||
          TextToken() ||
          DecimalPointToken() ||
          DigitToken() ||
          GeneralToken() ||
          ExponentToken() ||
          FractionSlashToken() ||
          FixedDenominatorToken():
        // System, calendar and unsupported tokens come with locale tags.
        // `@` and a decimal point show nothing in a date section, and the
        // number tokens make the code invalid, so they never reach a
        // rendered section.
        break;
    }
  }
  return (parts: out.result, warning: null);
}

/// The text of a `d`, `m`, `y`, `h` or `s` [token]; [minutes] tells an
/// `m` that is minutes from a month.
String _dateText(
  DateToken token,
  ExcelDateFields fields,
  XlsxFormatLocale locale, {
  required bool minutes,
  required bool twelveHour,
}) {
  final int length = token.length;
  switch (token.letter) {
    case 'y':
      return length <= 2 ? _pad(fields.year % 100, 2) : _pad(fields.year, 4);
    case 'd':
      return switch (length) {
        1 => '${fields.day}',
        2 => _pad(fields.day, 2),
        3 => locale.dayAbbreviations[fields.weekday],
        _ => locale.dayNames[fields.weekday],
      };
    case 'm' when !minutes:
      return switch (length) {
        1 => '${fields.month}',
        2 => _pad(fields.month, 2),
        3 => locale.monthAbbreviations[fields.month - 1],
        5 => _firstLetter(locale.monthNames[fields.month - 1]),
        _ => locale.monthNames[fields.month - 1],
      };
    case 'h':
      final int hour = twelveHour
          ? (fields.hour % 12 == 0 ? 12 : fields.hour % 12)
          : fields.hour;
      return _timeText(token, hour, fields.totalSeconds ~/ 3600);
    case 'm':
      return _timeText(token, fields.minute, fields.totalSeconds ~/ 60);
    default: // 's'
      return _timeText(token, fields.second, fields.totalSeconds);
  }
}

/// Whether [section] shows a date: a `d`, `y`, month `m`, `e` or `b`
/// token. [counted] is its counted [DateToken]s.
bool _hasDateToken(FormatSection section, List<DateToken> counted) {
  for (var k = 0; k < counted.length; k++) {
    switch (counted[k].letter) {
      case 'd' || 'y':
        return true;
      case 'm' when !isMinuteToken(counted, k):
        return true;
    }
  }
  return section.tokens.any(
    (FormatToken token) =>
        token is DateToken && (token.letter == 'e' || token.letter == 'b'),
  );
}

/// The text of an AM/PM marker written as [written]: the locale's `am` or
/// `pm` for `AM/PM` in any case, else the letter before or after the
/// slash of `A/P` in the case written.
String _amPmText(String written, bool am, XlsxFormatLocale locale) {
  if (written.length == 5) return am ? locale.am : locale.pm;
  return am ? written[0] : written[written.length - 1];
}

/// The text of an hour, minute or second [token]: [value] padded to two
/// digits when the token is longer than one, or [elapsed] padded to the
/// token's length when it is an elapsed `[h]`, `[m]` or `[s]`.
String _timeText(DateToken token, int value, int elapsed) {
  if (token.elapsed) return _pad(elapsed, token.length);
  return token.length == 1 ? '$value' : _pad(value, 2);
}

/// The text of an era or calendar [token]: `e`, `b` or `g`.
String _eraText(DateToken token, ExcelDateFields fields) {
  switch (token.letter) {
    case 'e':
      return _pad(fields.year, 4);
    case 'b':
      final int year = fields.year + 543;
      return token.length <= 2 ? _pad(year % 100, 2) : _pad(year, 4);
    default: // 'g'
      return '';
  }
}

/// [value] with leading zeros to [width] digits.
String _pad(int value, int width) => '$value'.padLeft(width, '0');

/// The first character of [name], a surrogate pair kept whole.
String _firstLetter(String name) =>
    name.isEmpty ? '' : String.fromCharCode(name.runes.first);
