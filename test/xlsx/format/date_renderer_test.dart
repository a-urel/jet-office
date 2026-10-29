import 'package:jet_office/src/xlsx/format/date_renderer.dart';
import 'package:jet_office/src/xlsx/format/excel_number.dart';
import 'package:jet_office/src/xlsx/format/format_code.dart';
import 'package:jet_office/src/xlsx/format/format_locale.dart';
import 'package:jet_office/src/xlsx/format/formatted_value.dart';
import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:test/test.dart';

/// The parts of [serial] in the first section of [code], or null for `#`.
List<XlsxFormatPart>? parts(
  String code,
  num serial, {
  XlsxFormatLocale locale = XlsxFormatLocale.enUS,
  bool date1904 = false,
}) {
  final FormatSection section = parseFormatCode(code).sections.first;
  return renderDate(
    section,
    ExcelNumber.from(serial)!,
    locale: locale,
    date1904: date1904,
  )?.parts;
}

/// The parts joined as `text` joins them, or null for `#`.
String? t(
  String code,
  num serial, {
  XlsxFormatLocale locale = XlsxFormatLocale.enUS,
  bool date1904 = false,
}) {
  final List<XlsxFormatPart>? result = parts(
    code,
    serial,
    locale: locale,
    date1904: date1904,
  );
  return result == null ? null : XlsxFormattedValue(result).text;
}

/// The warning of rendering [serial] with the first section of [code].
XlsxWarningCode? w(
  String code,
  num serial, {
  XlsxFormatLocale locale = XlsxFormatLocale.enUS,
}) {
  final FormatSection section = parseFormatCode(code).sections.first;
  return renderDate(
    section,
    ExcelNumber.from(serial)!,
    locale: locale,
    date1904: false,
  )!.warning;
}

/// en-US with [lcid], [monthNames] and [longDateCode] replaced.
XlsxFormatLocale custom({
  int lcid = 0x409,
  List<String>? monthNames,
  String? longDateCode,
}) {
  const XlsxFormatLocale en = XlsxFormatLocale.enUS;
  return XlsxFormatLocale(
    decimalSeparator: en.decimalSeparator,
    groupSeparator: en.groupSeparator,
    monthNames: monthNames ?? en.monthNames,
    monthAbbreviations: en.monthAbbreviations,
    dayNames: en.dayNames,
    dayAbbreviations: en.dayAbbreviations,
    am: en.am,
    pm: en.pm,
    trueText: en.trueText,
    falseText: en.falseText,
    errorNames: en.errorNames,
    lcid: lcid,
    builtinCodes: en.builtinCodes,
    longDateCode: longDateCode ?? en.longDateCode,
    longTimeCode: en.longTimeCode,
    messageLocale: en.messageLocale,
    verified: false,
  );
}

/// Wed 28 Oct 2026.
const int oct28 = 46323;

/// Mon 2 Mar 2026.
const int mar2 = 46083;

void main() {
  group('dates', () {
    test('day, month and year in digits', () {
      expect(t('dd.mm.yyyy', oct28), '28.10.2026');
      expect(t('d/m/yy', oct28), '28/10/26');
      expect(t('m/d/yyyy', oct28), '10/28/2026');
      expect(t('d', mar2), '2');
      expect(t('mm', mar2), '03');
    });

    test('month and day names', () {
      expect(t('dddd, mmmm d, yyyy', oct28), 'Wednesday, October 28, 2026');
      expect(t('ddd mmm', oct28), 'Wed Oct');
      expect(t('mmmmm', oct28), 'O');
    });

    test('the warning is null', () {
      final FormatSection section = parseFormatCode('yyyy').sections.first;
      expect(
        renderDate(
          section,
          ExcelNumber.from(oct28)!,
          locale: XlsxFormatLocale.enUS,
          date1904: false,
        )!.warning,
        isNull,
      );
    });
  });

  group('month or minute', () {
    test('m after h is minutes', () {
      expect(t('h:mm', 46323.5625), '13:30');
    });

    test('m before s is minutes', () {
      expect(t('mm:ss', 46323.5625), '30:00');
    });

    test('a lone m is the month', () {
      expect(t('m', 46323.5625), '10');
    });

    test('date and time in one section', () {
      expect(t('yyyy-mm-dd hh:mm', 46323.5625), '2026-10-28 13:30');
    });
  });

  group('locales', () {
    test('de-DE names', () {
      expect(
        t('dddd, d. mmmm yyyy', oct28, locale: XlsxFormatLocale.deDE),
        'Mittwoch, 28. Oktober 2026',
      );
    });

    test('tr-TR names', () {
      expect(
        t('d mmmm yyyy dddd', oct28, locale: XlsxFormatLocale.trTR),
        '28 Ekim 2026 Çarşamba',
      );
    });

    test('de-DE abbreviations', () {
      expect(t('mmm ddd', mar2, locale: XlsxFormatLocale.deDE), 'Mär Mo');
    }, skip: 'Owner Excel check C4a');

    test('tr-TR abbreviations', () {
      expect(t('mmm ddd', mar2, locale: XlsxFormatLocale.trTR), 'Mar Pzt');
    }, skip: 'Owner Excel check C4b');
  });

  group('literals and layout', () {
    test('a quoted literal', () {
      expect(t('"Day "d', oct28), 'Day 28');
    });

    test('a comma is a literal comma', () {
      expect(t('mmmm d, yyyy', oct28), 'October 28, 2026');
    });

    test('padding', () {
      expect(parts('_(dd_)', oct28), const <XlsxFormatPart>[
        XlsxFormatPadding('('),
        XlsxFormatText('28'),
        XlsxFormatPadding(')'),
      ]);
    });

    test('fill', () {
      expect(parts('* dd', oct28), const <XlsxFormatPart>[
        XlsxFormatFill(' '),
        XlsxFormatText('28'),
      ]);
    });

    test('a locale tag prints its currency', () {
      expect(parts('[\$€-407]dd', oct28), const <XlsxFormatPart>[
        XlsxFormatText('€28'),
      ]);
    });
  });

  group('serial 0 and the phantom leap day', () {
    test('weekdays and days', () {
      expect(t('dddd yyyy-mm-dd', 0), 'Saturday 1900-01-00');
      expect(t('dddd yyyy-mm-dd', 60), 'Wednesday 1900-02-29');
      expect(t('dddd yyyy-mm-dd', 61), 'Thursday 1900-03-01');
    }, skip: 'Owner Excel check C11');

    test('60 is 1900-02-29', () {
      expect(t('yyyy-mm-dd', 60), '1900-02-29');
    });
  });

  group('1904', () {
    test('0 is 1904-01-01', () {
      expect(t('yyyy-mm-dd', 0, date1904: true), '1904-01-01');
    });

    test('44861 is 2026-10-28', () {
      expect(t('yyyy-mm-dd', 44861, date1904: true), '2026-10-28');
    });
  });

  group('years', () {
    test('lengths Excel shows', () {
      expect(t('y', oct28), '26');
      expect(t('yyy', oct28), '2026');
      expect(t('yyyyy', oct28), '2026');
      expect(t('e', oct28), '2026');
      expect(t('bb', oct28), '69');
      expect(t('bbbb', oct28), '2569');
      expect(t('mmmmmm', oct28), 'October');
      expect(t('g', oct28), '');
    }, skip: 'Owner Excel check C15a');

    test('yy and yyyy', () {
      expect(t('yy', oct28), '26');
      expect(t('yyyy', oct28), '2026');
    });
  });

  group('time', () {
    test('hours, minutes and seconds', () {
      expect(t('h:mm:ss', 0.4375), '10:30:00');
      expect(t('hh:mm', 0.0625), '01:30');
    });

    test('without AM/PM the clock has 24 hours', () {
      expect(t('h:mm', 0.5625), '13:30');
    });

    test('AM/PM uses the 12-hour clock', () {
      expect(t('h:mm AM/PM', 0.5625), '1:30 PM');
      expect(t('h:mm AM/PM', 0), '12:00 AM');
      expect(t('h:mm AM/PM', 0.5), '12:00 PM');
      expect(t('hh:mm am/pm', 0.0625), '01:30 AM');
    });

    test('A/P shows the letters in the case written', () {
      expect(t('h:mm A/P', 0.5625), '1:30 P');
      expect(t('h:mm a/p', 0.5625), '1:30 p');
      expect(t('h:mm a/p', 0.0625), '1:30 a');
    });

    test('minutes are truncated', () {
      expect(t('h:mm', 0.437268518518519), '10:29');
    }, skip: 'Owner Excel check C9');

    test('seconds round and carry into minutes', () {
      expect(t('h:mm', 0.437495370370370), '10:30');
      expect(t('h:mm:ss', 0.437495370370370), '10:30:00');
    });

    test('fractional seconds round to the digits shown', () {
      expect(t('h:mm:ss.0', 0.437495370370370), '10:29:59.6');
      expect(t('h:mm:ss.00', 0.437495370370370), '10:29:59.60');
      expect(t('h:mm:ss.000', 0.5), '12:00:00.000');
    });

    test('built-in 47', () {
      expect(t('mmss.0', 0.000712962962963), '0101.6');
    });

    test('the carry runs through the hours', () {
      expect(t('h:mm:ss', 0.99999999), '0:00:00');
    }, skip: 'Owner Excel check C9');

    test('the carry runs into the date', () {
      expect(t('yyyy-mm-dd h:mm:ss', 46323.99999999), '2026-10-29 0:00:00');
    }, skip: 'Owner Excel check C9b');

    test('h and s longer than two show two digits', () {
      expect(t('hhh', 0.0625), '01');
      expect(t('sss', 0.0006944444444444), '00');
      expect(t('sss', 0.0000694444444444), '06');
    });

    test('mmm after h is the month abbreviation, not minutes', () {
      // isMinuteToken treats a run of three or more as a month, after h
      // too, so the shared rule shows the month.
      expect(t('h:mmm', 46323.5625), '13:Oct');
    });
  });

  group('elapsed', () {
    test('hours, minutes and seconds from serial 0', () {
      expect(t('[h]:mm:ss', 1.5), '36:00:00');
      expect(t('[mm]:ss', 0.0625), '90:00');
      expect(t('[ss]', 0.000694444444444444), '60');
      expect(t('[hh]', 0.0416666666666667), '01');
    });

    test('[hhh] pads to three digits', () {
      expect(t('[hhh]', 0.0416666666666667), '001');
      expect(t('[hhh]', 1.5), '036');
    });

    test('minutes and seconds after an elapsed token are modulo 60', () {
      expect(t('[h]:mm:ss', 1.0423611111111111), '25:01:00');
      expect(t('[m]:ss', 0.000706018518518519), '1:01');
    });

    test('the largest serial', () {
      expect(t('[h]:mm', 2958465), '71003160:00');
    });

    test('past the largest serial is null', () {
      expect(t('[h]', 2958466), isNull);
    });
  });

  group('AM/PM by locale', () {
    test('tr-TR', () {
      expect(t('h:mm AM/PM', 0.5625, locale: XlsxFormatLocale.trTR), '1:30 ÖS');
      expect(t('h:mm A/P', 0.5625, locale: XlsxFormatLocale.trTR), '1:30 P');
    }, skip: 'Owner Excel check C5');

    test('de-DE', () {
      expect(t('h:mm AM/PM', 0.5625, locale: XlsxFormatLocale.deDE), '1:30 PM');
    }, skip: 'Owner Excel check C5');
  });

  group('decimal separator', () {
    test('de-DE fractional seconds', () {
      expect(
        t('hh:mm:ss.00', 0.437505787037037, locale: XlsxFormatLocale.deDE),
        '10:30:00,50',
      );
    }, skip: 'Owner Excel check C15b');

    test('the separator comes from the locale', () {
      expect(t('ss.0', 0.5, locale: XlsxFormatLocale.deDE), '00,0');
    });
  });

  group('1904 negative', () {
    test('1900: a negative time is null', () {
      expect(t('h:mm', -0.25), isNull);
      expect(t('[h]:mm', -1.5), isNull);
    });

    test('1904: a negative time shows a minus', () {
      expect(t('h:mm', -0.25, date1904: true), '-6:00');
      expect(t('[h]:mm', -1.5, date1904: true), '-36:00');
    }, skip: 'Owner Excel check C10');

    test('1904: a negative date is null', () {
      // Ruling 4: a section with a date token shows `#` on a negative
      // value in either system.
      expect(t('yyyy-mm-dd', -1, date1904: true), isNull);
    });

    test('1904: the minus goes before a leading literal', () {
      expect(t('"t "h:mm', -0.25, date1904: true), '-t 6:00');
    });

    test('1904: a date token makes it null', () {
      expect(t('d h:mm', -0.25, date1904: true), isNull);
      expect(t('m h', -0.25, date1904: true), isNull);
      expect(t('yy h', -0.25, date1904: true), isNull);
      expect(t('e h', -0.25, date1904: true), isNull);
    });

    test('1904: minutes and seconds only are a time', () {
      expect(t('mm:ss', -0.0006944444444444, date1904: true), '-01:00');
    });

    test('1904: a negative that rounds to zero shows no minus', () {
      expect(t('h:mm:ss', -1e-9, date1904: true), '0:00:00');
    });
  });

  group('overflow', () {
    test('a negative serial is null', () {
      expect(t('yyyy', -1), isNull);
    });

    test('a serial past 9999-12-31 is null', () {
      expect(t('yyyy', 2958466), isNull);
    });
  });

  group('tags', () {
    test('a language tag picks a shipped locale for names', () {
      expect(t('[\$-407]mmmm dddd', oct28), 'Oktober Mittwoch');
    }, skip: 'Owner Excel check C18');

    test('a shipped locale gives the names and no warning', () {
      expect(t('[\$-41F]dddd', oct28), 'Çarşamba');
      expect(w('[\$-41F]dddd', oct28), isNull);
    });

    test('a language no locale serves keeps the names and warns', () {
      expect(t('[\$-40C]mmmm', oct28), 'October');
      expect(w('[\$-40C]mmmm', oct28), XlsxWarningCode.numberFormatUnsupported);
    });

    test('language 0 selects nothing and warns nothing', () {
      expect(t('[\$-0]mmmm', oct28), 'October');
      expect(w('[\$-0]mmmm', oct28), isNull);
    });

    test('AM/PM comes from the tag locale', () {
      expect(t('[\$-41F]h:mm AM/PM', 0.5625), '1:30 ÖS');
    });

    test('the first non-zero language decides', () {
      expect(t('[\$-0][\$-41F]dddd[\$-407]', oct28), 'Çarşamba');
    });

    test('the renderer locale wins over a shipped one with its lcid', () {
      final XlsxFormatLocale mine = custom(
        lcid: 0x407,
        monthNames: List<String>.filled(12, 'X'),
      );
      expect(t('[\$-407]mmmm', oct28, locale: mine), 'X');
      expect(w('[\$-407]mmmm', oct28, locale: mine), isNull);
    });

    test('separators come from the renderer locale', () {
      expect(t('[\$-407]ss.0', 0.5), '00.0');
    });
  });

  group('system formats', () {
    test('en-US long date and long time', () {
      expect(
        t('[\$-F800]dddd, mmmm dd, yyyy', 46323.5625),
        'Wednesday, October 28, 2026',
      );
      expect(t('[\$-F400]h:mm:ss AM/PM', 46323.5625), '1:30:00 PM');
      expect(t('[\$-x-sysdate]', 46323.5625), 'Wednesday, October 28, 2026');
      expect(t('[\$-x-systime]', 46323.5625), '1:30:00 PM');
      expect(w('[\$-F800]dddd, mmmm dd, yyyy', 46323.5625), isNull);
    });

    test('de-DE long date and long time', () {
      expect(
        t(
          '[\$-F800]dddd, mmmm dd, yyyy',
          46323.5625,
          locale: XlsxFormatLocale.deDE,
        ),
        'Mittwoch, 28. Oktober 2026',
      );
      expect(
        t('[\$-F400]h:mm:ss AM/PM', 46323.5625, locale: XlsxFormatLocale.deDE),
        '13:30:00',
      );
    }, skip: 'Owner Excel check C8');

    test('tr-TR long date and long time', () {
      expect(
        t(
          '[\$-F800]dddd, mmmm dd, yyyy',
          46323.5625,
          locale: XlsxFormatLocale.trTR,
        ),
        '28 Ekim 2026 Çarşamba',
      );
      expect(
        t('[\$-F400]h:mm:ss AM/PM', 46323.5625, locale: XlsxFormatLocale.trTR),
        '13:30:00',
      );
    }, skip: 'Owner Excel check C8');

    test('upper bits of the tag do not matter', () {
      expect(t('[\$-10F800]', oct28), 'Wednesday, October 28, 2026');
    });

    test('the system format replaces the whole section', () {
      expect(t('[\$-F800]0', oct28), 'Wednesday, October 28, 2026');
      expect(t('"x"[\$-F800]"y"', oct28), 'Wednesday, October 28, 2026');
    });

    test('a currency on a system tag is dropped', () {
      expect(t('[\$USD-F800]', oct28), 'Wednesday, October 28, 2026');
    });

    test('the first system token wins', () {
      expect(
        t('[\$-F800][\$-F400]', 46323.5625),
        'Wednesday, October 28, 2026',
      );
      expect(t('[\$-F400][\$-F800]', 46323.5625), '1:30:00 PM');
    });

    test('a color stays on the section', () {
      final FormatSection section = parseFormatCode(
        '[Red][\$-F800]dddd',
      ).sections.first;
      expect(section.color, isNotNull);
      expect(t('[Red][\$-F800]dddd', oct28), 'Wednesday, October 28, 2026');
    });

    test('a long caller code renders in full', () {
      final XlsxFormatLocale long = custom(longDateCode: '"${'x' * 1000}"');
      final String? text = t('[\$-F800]', oct28, locale: long);
      expect(text, 'x' * 1000);
    });

    test('a system tag in the caller code is not followed', () {
      final XlsxFormatLocale loop = custom(longDateCode: '[\$-F800]yyyy');
      expect(t('[\$-F800]', oct28, locale: loop), '2026');
    });

    test('a 1904 negative in a long time shows a minus', () {
      expect(t('[\$-F400]', -0.25, date1904: true), '-6:00:00 AM');
    });
  });

  group('calendars', () {
    test('B1 is Gregorian and shows nothing', () {
      expect(t('B1yyyy', oct28), '2026');
      expect(t('[B1]yyyy', oct28), '2026');
      expect(w('B1yyyy', oct28), isNull);
    });

    test('B2 shows the Gregorian year and warns', () {
      expect(t('B2yyyy', oct28), '2026');
      expect(w('B2yyyy', oct28), XlsxWarningCode.numberFormatUnsupported);
      expect(w('[B2]yyyy', oct28), XlsxWarningCode.numberFormatUnsupported);
    });

    test('a tag calendar other than 0 or 1 warns', () {
      expect(t('[\$-1060409]yyyy', oct28), '2026');
      expect(
        w('[\$-1060409]yyyy', oct28),
        XlsxWarningCode.numberFormatUnsupported,
      );
      expect(w('[\$-1010409]yyyy', oct28), isNull);
    });

    test('an unsupported bracket shows nothing and warns', () {
      expect(t('[DBNum1]yyyy', oct28), '2026');
      expect(w('[DBNum1]yyyy', oct28), XlsxWarningCode.numberFormatUnsupported);
    });
  });
}
