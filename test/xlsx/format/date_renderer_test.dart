import 'package:jet_office/src/xlsx/format/date_renderer.dart';
import 'package:jet_office/src/xlsx/format/excel_number.dart';
import 'package:jet_office/src/xlsx/format/format_code.dart';
import 'package:jet_office/src/xlsx/format/format_locale.dart';
import 'package:jet_office/src/xlsx/format/formatted_value.dart';
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

  group('overflow', () {
    test('a negative serial is null', () {
      expect(t('yyyy', -1), isNull);
    });

    test('a serial past 9999-12-31 is null', () {
      expect(t('yyyy', 2958466), isNull);
    });
  });
}
