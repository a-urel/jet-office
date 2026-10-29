import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/format/excel_date.dart';
import 'package:jet_office/src/xlsx/format/excel_number.dart';
import 'package:jet_office/src/xlsx/read/serial_dates.dart';
import 'package:test/test.dart';

/// The fields of [digits] read as Excel reads it.
ExcelDateFields? f(String digits, {bool d1904 = false, int k = 0}) =>
    serialToFields(
      ExcelNumber.from(XlsxDecimal(digits))!,
      date1904: d1904,
      fractionDigits: k,
    );

String _two(int n) => n.toString().padLeft(2, '0');

/// [fields] as `yyyy-mm-dd`.
String date(ExcelDateFields? fields) =>
    '${fields!.year}-${_two(fields.month)}-${_two(fields.day)}';

/// [fields] as `hh:mm:ss`.
String time(ExcelDateFields? fields) =>
    '${_two(fields!.hour)}:${_two(fields.minute)}:${_two(fields.second)}';

/// [digits] read as Excel reads it.
ExcelNumber excel(String digits) => ExcelNumber.from(XlsxDecimal(digits))!;

void main() {
  group('serialToFields, 1900 system', () {
    test('46323.5625 is Wednesday 2026-10-28 13:30:00', () {
      final ExcelDateFields? fields = f('46323.5625');
      expect(date(fields), '2026-10-28');
      expect(fields!.weekday, 3);
      expect(time(fields), '13:30:00');
      expect(fields.fraction, 0);
    });

    test('0 is Saturday 1900-01-00', () {
      final ExcelDateFields? fields = f('0');
      expect(date(fields), '1900-01-00');
      expect(fields!.weekday, 6);
      expect(time(fields), '00:00:00');
    });

    test('1 is Sunday 1900-01-01', () {
      final ExcelDateFields? fields = f('1');
      expect(date(fields), '1900-01-01');
      expect(fields!.weekday, 0);
    });

    test('59 is 1900-02-28', () {
      expect(date(f('59')), '1900-02-28');
    });

    test('60 is the phantom Wednesday 1900-02-29', () {
      final ExcelDateFields? fields = f('60');
      expect(date(fields), '1900-02-29');
      expect(fields!.weekday, 3);
    });

    test('61 is Thursday 1900-03-01', () {
      final ExcelDateFields? fields = f('61');
      expect(date(fields), '1900-03-01');
      expect(fields!.weekday, 4);
    });

    test('2958465 is 9999-12-31, 2958466 is out of range', () {
      expect(date(f('2958465')), '9999-12-31');
      expect(f('2958466'), isNull);
    });

    test('a negative serial is null, even one that rounds to zero', () {
      expect(f('-1'), isNull);
      expect(f('-0.00000000000000000001'), isNull);
      expect(
        serialToFields(
          ExcelNumber.parse('-1E-20'),
          date1904: false,
          fractionDigits: 0,
        ),
        isNull,
      );
    });

    test('2958465.999999999 rounds past the end and is null', () {
      expect(f('2958465.999999999'), isNull);
      // 15 digits, 86399.999136 s: the rounding carries past the end.
      expect(f('2958465.99999999'), isNull);
      expect(time(f('2958465.99998843')), '23:59:59');
    });

    test('a huge serial is null', () {
      expect(f('1${'0' * 300}'), isNull);
    });
  });

  group('serialToFields, 1904 system', () {
    test('0 is Friday 1904-01-01', () {
      final ExcelDateFields? fields = f('0', d1904: true);
      expect(date(fields), '1904-01-01');
      expect(fields!.weekday, 5);
    });

    test('60 is an ordinary 1904-03-01', () {
      expect(date(f('60', d1904: true)), '1904-03-01');
    });

    test('44861 is Wednesday 2026-10-28', () {
      final ExcelDateFields? fields = f('44861', d1904: true);
      expect(date(fields), '2026-10-28');
      expect(fields!.weekday, 3);
    });

    test('2957003 is 9999-12-31, 2957004 is out of range', () {
      expect(date(f('2957003', d1904: true)), '9999-12-31');
      expect(f('2957004', d1904: true), isNull);
    });
  });

  group('rounding (ruling 1)', () {
    test('0.437268518518519 is 10:29:40', () {
      expect(time(f('0.437268518518519')), '10:29:40');
    });

    test('0.437495370370370 (10:29:59.6) rounds up to 10:30:00', () {
      expect(time(f('0.437495370370370')), '10:30:00');
    });

    test('0.437495370370370 to tenths is 10:29:59.6', () {
      final ExcelDateFields? fields = f('0.437495370370370', k: 1);
      expect(time(fields), '10:29:59');
      expect(fields!.fraction, 6);
    });

    test('0.99999999 carries into the next day', () {
      final ExcelDateFields? fields = f('0.99999999');
      expect(date(fields), '1900-01-01');
      expect(time(fields), '00:00:00');
    });

    test('totalSeconds of 1.5 is 129600', () {
      expect(f('1.5')!.totalSeconds, 129600);
    });

    test('totalSeconds counts whole seconds after rounding', () {
      final ExcelDateFields? fields = f('0.437495370370370', k: 3);
      expect(fields!.totalSeconds, 37799);
      expect(fields.fraction, 600);
    });

    test('a fractionDigits outside 0 to 3 throws', () {
      expect(() => f('1', k: 4), throwsArgumentError);
      expect(() => f('1', k: -1), throwsArgumentError);
    });
  });

  group('dateTimeToSerial', () {
    test('2026-10-28 13:30 UTC is 46323.5625', () {
      expect(
        dateTimeToSerial(DateTime.utc(2026, 10, 28, 13, 30), date1904: false),
        ExcelNumber.parse('46323.5625'),
      );
    });

    test('the days around the phantom leap day', () {
      ExcelNumber s(int y, int m, int d) =>
          dateTimeToSerial(DateTime(y, m, d), date1904: false);
      expect(s(1899, 12, 31), ExcelNumber.parse('0'));
      expect(s(1900, 2, 28), ExcelNumber.parse('59'));
      expect(s(1900, 3, 1), ExcelNumber.parse('61'));
      expect(s(1899, 12, 30), ExcelNumber.parse('-1'));
    });

    test('1904-01-01 is 0 in the 1904 system', () {
      expect(
        dateTimeToSerial(DateTime(1904, 1, 1), date1904: true),
        ExcelNumber.parse('0'),
      );
    });

    test('a local DateTime uses its wall-clock fields', () {
      expect(
        dateTimeToSerial(DateTime(2026, 10, 28, 13, 30), date1904: false),
        dateTimeToSerial(DateTime.utc(2026, 10, 28, 13, 30), date1904: false),
      );
    });

    test('a millisecond keeps 15 significant digits', () {
      final ExcelNumber serial = dateTimeToSerial(
        DateTime.utc(2026, 10, 28, 0, 0, 0, 1),
        date1904: false,
      );
      expect(serial.toFixed(12), (whole: '46323', fraction: '000000011600'));
    });

    test('a time before day 0 is a negative serial', () {
      expect(
        dateTimeToSerial(DateTime.utc(1899, 12, 30, 12), date1904: false),
        ExcelNumber.parse('-0.5'),
      );
    });

    test('years far outside the range return without throwing', () {
      expect(
        dateTimeToSerial(DateTime.utc(1), date1904: false).negative,
        isTrue,
      );
      expect(
        dateTimeToSerial(DateTime.utc(275000), date1904: false),
        ExcelNumber.parse('2958466'),
      );
      expect(
        dateTimeToSerial(DateTime.utc(275000), date1904: true),
        ExcelNumber.parse('2957004'),
      );
      expect(
        dateTimeToSerial(DateTime.utc(-5), date1904: false),
        ExcelNumber.parse('-1'),
      );
    });
  });

  group('durationToSerial', () {
    test('36 hours is 1.5', () {
      expect(
        durationToSerial(const Duration(hours: 36)),
        ExcelNumber.parse('1.5'),
      );
    });

    test('-6 hours is -0.25', () {
      expect(
        durationToSerial(const Duration(hours: -6)),
        ExcelNumber.parse('-0.25'),
      );
    });

    test('100,000,000 days and 12 hours is its whole days only', () {
      expect(
        durationToSerial(const Duration(days: 100000000, hours: 12)),
        ExcelNumber.parse('100000000'),
      );
    });
  });

  group('round trip through the reader', () {
    for (final String digits in <String>[
      '1',
      '59',
      '61',
      '46323.5625',
      '2958465.99998843',
    ]) {
      for (final bool date1904 in <bool>[false, true]) {
        // 2958465.99998843 is past 9999-12-31 in the 1904 system.
        if (date1904 && digits.startsWith('2958465')) continue;
        test('$digits, date1904: $date1904', () {
          final DateTime value = serialToDateTime(
            digits,
            date1904: date1904,
          ).date!;
          expect(dateTimeToSerial(value, date1904: date1904), excel(digits));
        });
      }
    }
  });
}
