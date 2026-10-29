/// The renderer of date and time sections.
///
/// New in jet_office; Quds has no number format engine. [renderDate] lays
/// a serial out in a section that has date or time tokens (spec §5.4): it
/// reads the serial's calendar fields with [serialToFields] and shows each
/// token from them, with month and day names from the renderer's locale
/// or the one a locale tag selects. Literals, `,`, `%`, a locale tag's
/// currency, padding and fill show as the number renderer shows them.
/// [sectionWarning] tells which sections ask for a calendar, numeral
/// system or language the engine does not render.
library;

import '../warnings.dart';
import 'excel_date.dart';
import 'excel_number.dart';
import 'format_code.dart';
import 'format_kind.dart';
import 'format_locale.dart';
import 'formatted_value.dart';

/// Renders [serial] with the date or time [section]; null when Excel
/// shows `#` (out of range, or negative in the 1900 system). In the 1904
/// system a negative serial shows `-` and then the text of its absolute
/// value, in any date or time section and also when that text is all
/// zeros (`h:mm:ss` on -0.000001 shows `-0:00:00`). The result's `warning` is
/// [sectionWarning] of [section]: `numberFormatUnsupported` when the
/// section asks for a calendar, numeral system or language the engine does
/// not render, which it renders as Gregorian dates with the names of
/// [locale]; else null.
///
/// Names (`mmm`, `mmmm`, `ddd`, `dddd`) come from the section's name
/// locale: the section's first locale tag with a language other than 0
/// selects [locale] when the language equals its
/// [XlsxFormatLocale.lcid], else the shipped locale with that id, else
/// [locale]. Without such a tag they come from [locale]. The `AM/PM`
/// words come from the name locale only when the section has such a tag
/// or a system tag; else they are `AM` and `PM` in every locale (Excel
/// for Mac shows `h:mm AM/PM` as `1:30 PM` in tr-TR, and
/// `[$-41F]h:mm AM/PM` as `1:30 ÖS`). Separators always come from
/// [locale]: a bare `/` ([DateSeparatorToken]) shows its
/// [XlsxFormatLocale.dateSeparator], an escaped or quoted `/` shows `/`.
///
/// A system date or time tag (`[$-F800]`, `[$-F400]`) replaces the whole
/// section with the first section of [locale]'s
/// [XlsxFormatLocale.longDateCode] or [XlsxFormatLocale.longTimeCode]; the
/// first such tag wins, and the caller keeps the section's color and
/// condition. The replacement renders with the outer section's name
/// locale; a system tag, locale tag or bracket inside it does not change
/// the names and is not reported.
///
/// [date1904] selects the 1904 date system. An `m` is a month or minutes by
/// [isMinuteToken].
///
/// Token lengths: `y` and `yy` show two digits of the year, `yyy` and
/// longer four; `mmmmm` shows the first letter of the month name and six or
/// more `m` the full name; `dddd` and longer the full day name; `h`, `m`
/// and `s` longer than two show two digits; `e` the four-digit year; `b`
/// and `bb` two digits of the year, `bbb` and longer four; `g`
/// nothing. `b` shows the Gregorian year, not the Buddhist one: Excel for
/// Mac shows `bbbb` as `2026` on a date in 2026.
///
/// The time is rounded to the second, or to the most fractional-second
/// digits the section shows, and then truncated to the units shown
/// (`h:mm` on 10:29:40 shows `10:29`). An `AM/PM` or `A/P` marker switches
/// `h` to the 12-hour clock: `AM/PM` in any case shows the words above,
/// `A/P` its letters in the case written. Fractional seconds show
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
  final ({bool tagged, XlsxFormatLocale? locale}) tag = _nameLocale(
    section,
    locale,
  );
  final XlsxFormatLocale names = tag.locale ?? locale;
  final List<FormatToken> tokens = _systemTokens(section, locale);
  // The AM/PM words need a language tag or a system tag (ruling R13).
  final XlsxFormatLocale? amPm =
      tag.tagged || !identical(tokens, section.tokens) ? names : null;
  final List<DateToken> counted = <DateToken>[
    for (final FormatToken token in tokens)
      if (token is DateToken && countedDateLetters.contains(token.letter))
        token,
  ];

  // Ruling R15 (replaces the 1904 half of N2 ruling 4): in the 1904
  // system a negative value shows a minus and its absolute value in any
  // date or time section; in the 1900 system it is `#`.
  final bool negativeTime = date1904 && serial.negative;
  var fractionDigits = 0;
  var twelveHour = false;
  for (final FormatToken token in tokens) {
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
  // First, before a literal, fill or padding, and also on a value that
  // rounds to zero (`-0:00:00`).
  if (negativeTime) out.text('-');
  var k = 0;
  for (final FormatToken token in tokens) {
    switch (token) {
      case DateToken(:final String letter):
        if (countedDateLetters.contains(letter)) {
          final bool minutes = letter == 'm' && isMinuteToken(counted, k);
          out.text(
            _dateText(
              token,
              fields,
              names,
              minutes: minutes,
              twelveHour: twelveHour,
            ),
          );
          k++;
        } else {
          out.text(_eraText(token, fields));
        }
      case DateSeparatorToken():
        out.text(locale.dateSeparator);
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
        out.text(_amPmText(text, fields.hour < 12, amPm));
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
        // A system tag was replaced above (one inside the replacement is
        // not followed); calendar and unsupported tokens show nothing and
        // are reported by sectionWarning. `@` and a decimal point show
        // nothing in a date section, and the number tokens make the code
        // invalid, or are dropped with the section a system tag replaces.
        break;
    }
  }
  return (
    parts: out.result,
    warning: sectionWarning(section, date: true, locale: locale),
  );
}

/// What [section] asks for that the engine does not render, rendered
/// with [locale]: `numberFormatUnsupported`, or null.
///
/// It is `numberFormatUnsupported` for a bracket the parser does not
/// interpret (`[DBNum1]`, `[NatNum1]`, `[foo]`), the Hijri calendar
/// (`B2`, `[B2]`) and a locale tag whose numeral system (bits 24 to 31)
/// is other than 0 or 1. When [date] is true it is also
/// `numberFormatUnsupported` for a locale tag whose calendar (bits 16 to
/// 23) is other than 0 or 1, and when the section's first tag with a
/// language other than 0 names a language neither [locale] nor a shipped
/// locale serves. A number section has no names, so its tags' language
/// and calendar do not matter: `[$€-40C]#,##0` is supported.
XlsxWarningCode? sectionWarning(
  FormatSection section, {
  required bool date,
  required XlsxFormatLocale locale,
}) {
  var named = false;
  for (final FormatToken token in section.tokens) {
    switch (token) {
      case UnsupportedToken():
        return XlsxWarningCode.numberFormatUnsupported;
      case CalendarToken(:final int calendar) when calendar != 1:
        return XlsxWarningCode.numberFormatUnsupported;
      case LocaleTagToken():
        if (token.numerals > 1) {
          return XlsxWarningCode.numberFormatUnsupported;
        }
        if (!date) break;
        if (token.calendar > 1) {
          return XlsxWarningCode.numberFormatUnsupported;
        }
        if (!named && token.language != 0) {
          named = true;
          if (_tagLocale(token.language, locale) == null) {
            return XlsxWarningCode.numberFormatUnsupported;
          }
        }
      default:
        break;
    }
  }
  return null;
}

/// Whether [section] has a locale tag with a language other than 0
/// (`tagged`), and the locale the first such tag selects, or null when
/// there is no such tag or no locale serves its language.
({bool tagged, XlsxFormatLocale? locale}) _nameLocale(
  FormatSection section,
  XlsxFormatLocale locale,
) {
  for (final FormatToken token in section.tokens) {
    if (token is LocaleTagToken && token.language != 0) {
      return (tagged: true, locale: _tagLocale(token.language, locale));
    }
  }
  return (tagged: false, locale: null);
}

/// [locale] when [language] is its id, else the shipped locale of
/// [language], else null.
XlsxFormatLocale? _tagLocale(int language, XlsxFormatLocale locale) =>
    language == locale.lcid ? locale : shippedFormatLocale(language);

/// The tokens [section] renders: its own, or, when it holds a system tag,
/// the first section of [locale]'s long date or long time code.
List<FormatToken> _systemTokens(
  FormatSection section,
  XlsxFormatLocale locale,
) {
  for (final FormatToken token in section.tokens) {
    if (token is SystemFormatToken) {
      return _parsedSystemCode(
        token.longDate ? locale.longDateCode : locale.longTimeCode,
      ).tokens;
    }
  }
  return section.tokens;
}

/// The first section of [code], parsed once and kept in [_systemCodes].
FormatSection _parsedSystemCode(String code) {
  final FormatSection? cached = _systemCodes[code];
  if (cached != null) return cached;
  if (_systemCodes.length >= _systemCodeCacheSize) _systemCodes.clear();
  final FormatSection section = parseFormatCode(code).sections.first;
  _systemCodes[code] = section;
  return section;
}

/// The most long date and long time codes [_systemCodes] holds before it
/// is cleared.
const int _systemCodeCacheSize = 16;

/// The parsed long date and long time codes, by code.
final Map<String, FormatSection> _systemCodes = <String, FormatSection>{};

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

/// The text of an AM/PM marker written as [written]: for `AM/PM` in any
/// case the `am` or `pm` of [locale], or `AM` or `PM` when [locale] is
/// null; else the letter before or after the slash of `A/P` in the case
/// written.
String _amPmText(String written, bool am, XlsxFormatLocale? locale) {
  if (written.length == 5) {
    if (locale == null) return am ? 'AM' : 'PM';
    return am ? locale.am : locale.pm;
  }
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
      // Ruling R14: the Gregorian year, as Excel for Mac shows it.
      return token.length <= 2
          ? _pad(fields.year % 100, 2)
          : _pad(fields.year, 4);
    default: // 'g'
      return '';
  }
}

/// [value] with leading zeros to [width] digits.
String _pad(int value, int width) => '$value'.padLeft(width, '0');

/// The first character of [name], a surrogate pair kept whole.
String _firstLetter(String name) =>
    name.isEmpty ? '' : String.fromCharCode(name.runes.first);
