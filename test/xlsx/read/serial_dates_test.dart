import 'dart:math';

import 'package:jet_office/src/xlsx/date_serial.dart';
import 'package:jet_office/src/xlsx/read/serial_dates.dart';
import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:test/test.dart';

DateTime? _d(String digits, {bool date1904 = false}) {
  final ({DateTime? date, XlsxWarningCode? warning}) r = serialToDateTime(
    digits,
    date1904: date1904,
  );
  expect((r.date == null), (r.warning != null), reason: digits);
  if (r.date != null) expect(r.date!.isUtc, isTrue, reason: digits);
  return r.date;
}

XlsxWarningCode? _w(String digits, {bool date1904 = false}) {
  final ({DateTime? date, XlsxWarningCode? warning}) r = serialToDateTime(
    digits,
    date1904: date1904,
  );
  expect(r.date, isNull, reason: digits);
  return r.warning;
}

void main() {
  group('serialToDateTime, 1900 system', () {
    test('day numbers', () {
      expect(_d('0'), DateTime.utc(1899, 12, 31));
      expect(_d('1'), DateTime.utc(1900, 1, 1));
      expect(_d('59'), DateTime.utc(1900, 2, 28));
      expect(_d('61'), DateTime.utc(1900, 3, 1));
    });

    test('serial 60 is the phantom leap day, also after rounding', () {
      expect(_w('60'), XlsxWarningCode.phantomLeapDay);
      expect(_w('60.5'), XlsxWarningCode.phantomLeapDay);
      expect(_w('59.9999999999'), XlsxWarningCode.phantomLeapDay);
    });

    test('fractions', () {
      expect(_d('0.5'), DateTime.utc(1899, 12, 31, 12));
      expect(_d('45000.25'), DateTime.utc(2023, 3, 15, 6));
      expect(_d('1.000000005787037'), DateTime.utc(1900, 1, 1));
    });

    test('upper bound', () {
      expect(_d('2958465.99999'), DateTime.utc(9999, 12, 31, 23, 59, 59, 136));
      expect(_w('2958465.99999999999'), XlsxWarningCode.serialOutOfRange);
      expect(_w('2958466'), XlsxWarningCode.serialOutOfRange);
      expect(_w('9999999999'), XlsxWarningCode.serialOutOfRange);
      expect(_w('1${'0' * 5000}'), XlsxWarningCode.serialOutOfRange);
    });

    test('negative serials are out of range', () {
      expect(_w('-1'), XlsxWarningCode.serialOutOfRange);
      expect(_w('-0.5'), XlsxWarningCode.serialOutOfRange);
    });

    test('a very long fraction finishes and rounds', () {
      final DateTime? v = _d('46000.${'3' * 2000}');
      expect(v, DateTime.utc(2025, 12, 9, 8));
      expect(_d('46000.5${'0' * 2000}1'), DateTime.utc(2025, 12, 9, 12));
    });

    test('results are UTC', () {
      expect(_d('45000.25')!.isUtc, isTrue);
    });

    test('a leading-zero integer part', () {
      expect(_d('000000000045000'), DateTime.utc(2023, 3, 15));
      expect(_d('0'), DateTime.utc(1899, 12, 31));
    });

    test('an exact half millisecond rounds up', () {
      // 0.00000015625 days is exactly 13.5 ms.
      expect(_d('0.00000015625'), DateTime.utc(1899, 12, 31, 0, 0, 0, 14));
      expect(_d('0.000000156249'), DateTime.utc(1899, 12, 31, 0, 0, 0, 13));
    });

    test('rounding reaches 24:00 and rolls into the next day', () {
      expect(_d('45000.99999999999'), DateTime.utc(2023, 3, 16));
    });
  });

  group('serialToDateTime, 1904 system', () {
    test('day numbers', () {
      expect(_d('0', date1904: true), DateTime.utc(1904, 1, 1));
      expect(_d('60', date1904: true), DateTime.utc(1904, 3, 1));
      expect(
        _d('2957003.999', date1904: true),
        DateTime.utc(9999, 12, 31, 23, 58, 33, 600),
      );
      expect(_w('2957004', date1904: true), XlsxWarningCode.serialOutOfRange);
    });
  });

  test('dateTimeSerial round trip with seeded random values', () {
    final Random random = Random(20261028);
    final int firstDay =
        DateTime.utc(1900, 3, 1).millisecondsSinceEpoch ~/ 86400000;
    final int days =
        DateTime.utc(9999, 12, 31).millisecondsSinceEpoch ~/ 86400000 -
        firstDay +
        1;
    final List<DateTime> values = <DateTime>[
      DateTime.utc(1900, 1, 1, 5, 6, 7),
      DateTime.utc(1900, 2, 28, 23, 59, 59),
      for (int i = 0; i < 1000; i++)
        DateTime.utc(1970).add(
          Duration(
            days: firstDay + random.nextInt(days),
            seconds: random.nextInt(86400),
          ),
        ),
    ];
    for (final DateTime v in values) {
      final String s = dateTimeSerial(v)!.toString();
      expect(s.contains('e') || s.contains('E'), isFalse, reason: s);
      expect(_d(s), v, reason: s);
    }
  });

  group('serialToDuration', () {
    Duration? dur(String digits) {
      final ({Duration? duration, XlsxWarningCode? warning}) r =
          serialToDuration(digits);
      expect((r.duration == null), (r.warning != null), reason: digits);
      return r.duration;
    }

    XlsxWarningCode? durWarning(String digits) =>
        serialToDuration(digits).warning;

    test('values', () {
      expect(dur('0.5'), const Duration(hours: 12));
      expect(dur('-0.25'), const Duration(hours: -6));
      expect(dur('1.5'), const Duration(hours: 36));
      expect(dur('45000.5'), const Duration(days: 45000, hours: 12));
      expect(dur('0.0000115740740'), const Duration(seconds: 1));
      expect(dur('99999.9'), isNotNull);
    });

    test('out of range', () {
      expect(durWarning('100000'), XlsxWarningCode.serialOutOfRange);
      expect(durWarning('-100000'), XlsxWarningCode.serialOutOfRange);
      expect(durWarning('1${'0' * 5000}'), XlsxWarningCode.serialOutOfRange);
    });
  });

  group('parseIsoDateTime', () {
    test('accepted forms', () {
      expect(parseIsoDateTime('2026-10-28'), DateTime.utc(2026, 10, 28));
      expect(
        parseIsoDateTime('2026-10-28T13:45'),
        DateTime.utc(2026, 10, 28, 13, 45),
      );
      expect(
        parseIsoDateTime('2026-10-28T13:45:30.1235'),
        DateTime.utc(2026, 10, 28, 13, 45, 30, 124),
      );
      expect(
        parseIsoDateTime('2026-10-28T23:30:00-02:00'),
        DateTime.utc(2026, 10, 29, 1, 30),
      );
      expect(
        parseIsoDateTime('2026-10-28T00:30:00+0100'),
        DateTime.utc(2026, 10, 27, 23, 30),
      );
      expect(
        parseIsoDateTime('2026-10-28T13:45:30Z'),
        DateTime.utc(2026, 10, 28, 13, 45, 30),
      );
      expect(parseIsoDateTime('2026-10-28T13:45:30')!.isUtc, isTrue);
      expect(parseIsoDateTime('0001-01-01'), DateTime.utc(1));
    });

    test('rejected forms', () {
      for (final String s in <String>[
        '2026-02-30',
        '2026-13-01',
        '13:45:00',
        '2026-10-28T24:00:00',
        '28.10.2026',
        '',
        '0000-01-01',
        '2026-10-28T13:60',
        '2026-10-28T13:45:60',
        '2026-10-28T13:45+24:00',
        '2026-10-28T13:45+01:60',
        '2026-10-28+01:00',
        '2026-10-28T13:45:30.',
        '2026-10-28Z',
      ]) {
        expect(parseIsoDateTime(s), isNull, reason: s);
      }
    });

    test('a result outside 0001 to 9999 is null', () {
      for (final String s in <String>[
        '0001-01-01T00:00+01:00',
        '9999-12-31T23:59:59.9995',
        '9999-12-31T23:30-01:00',
      ]) {
        expect(parseIsoDateTime(s), isNull, reason: s);
      }
      expect(
        parseIsoDateTime('9999-12-31T23:59:59.999'),
        DateTime.utc(9999, 12, 31, 23, 59, 59, 999),
      );
      expect(
        parseIsoDateTime('0001-01-01T00:00-01:00'),
        DateTime.utc(1, 1, 1, 1),
      );
    });
  });
}
