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
/// shows `#` (negative, out of range). The result's `warning` is
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
/// Adjacent text is merged into one [XlsxFormatText], and empty text is
/// left out.
({List<XlsxFormatPart> parts, XlsxWarningCode? warning})? renderDate(
  FormatSection section,
  ExcelNumber serial, {
  required XlsxFormatLocale locale,
  required bool date1904,
}) {
  // Seam for the 12-hour clock, fractional seconds and negative 1904
  // times: the fields are read to the whole second, and a negative serial
  // is `#` in both systems.
  final ExcelDateFields? fields = serialToFields(
    serial,
    date1904: date1904,
    fractionDigits: 0,
  );
  if (fields == null) return null;

  final List<DateToken> counted = <DateToken>[
    for (final FormatToken token in section.tokens)
      if (token is DateToken && countedDateLetters.contains(token.letter))
        token,
  ];

  final FormatPartsBuilder out = FormatPartsBuilder();
  var k = 0;
  for (final FormatToken token in section.tokens) {
    switch (token) {
      case DateToken(:final String letter):
        if (countedDateLetters.contains(letter)) {
          final bool minutes = letter == 'm' && isMinuteToken(counted, k);
          out.text(_dateText(token, fields, locale, minutes: minutes));
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
      case AmPmToken() ||
          FractionalSecondsToken() ||
          CalendarToken() ||
          SystemFormatToken() ||
          UnsupportedToken() ||
          TextToken() ||
          DecimalPointToken() ||
          DigitToken() ||
          GeneralToken() ||
          ExponentToken() ||
          FractionSlashToken() ||
          FixedDenominatorToken():
        // AM/PM and fractional seconds come with the 12-hour clock and the
        // rounding to a fraction of a second; system, calendar and
        // unsupported tokens with locale tags. `@` and a decimal point
        // show nothing in a date section, and the number tokens make the
        // code invalid, so they never reach a rendered section.
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
      return _timeText(token, fields.hour, fields.totalSeconds ~/ 3600);
    case 'm':
      return _timeText(token, fields.minute, fields.totalSeconds ~/ 60);
    default: // 's'
      return _timeText(token, fields.second, fields.totalSeconds);
  }
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
