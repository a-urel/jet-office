import 'package:jet_office/src/drawingml/chart/chart_values.dart';
import 'package:test/test.dart';

void main() {
  group('drawingNumberText', () {
    test('writes whole numbers without a fraction', () {
      expect(drawingNumberText(1), '1');
      expect(drawingNumberText(-3), '-3');
      expect(drawingNumberText(0), '0');
      expect(drawingNumberText(-0.0), '0');
      expect(drawingNumberText(46023), '46023');
    });

    test('writes the shortest text that reads back', () {
      expect(drawingNumberText(0.5), '0.5');
      expect(drawingNumberText(0.1 + 0.2), '0.30000000000000004');
      expect(double.parse(drawingNumberText(0.1 + 0.2)), 0.1 + 0.2);
    });

    test('writes exponents with an upper-case E', () {
      expect(drawingNumberText(1e21), '1E+21');
      expect(drawingNumberText(1.5e-7), '1.5E-7');
      expect(double.parse(drawingNumberText(1.5e-7)), 1.5e-7);
    });

    test('throws for a value that is not finite', () {
      expect(() => drawingNumberText(double.nan), throwsArgumentError);
      expect(() => drawingNumberText(double.infinity), throwsArgumentError);
    });
  });

  group('drawingSerialOf and drawingDateOf', () {
    test('the 1904 system counts from 1904-01-01 with no phantom day', () {
      expect(drawingSerialOf(DateTime.utc(1904, 1, 1), date1904: true), 0);
      expect(drawingSerialOf(DateTime.utc(1904, 1, 2), date1904: true), 1);
      expect(
        drawingSerialOf(DateTime(2026, 1, 1), date1904: true),
        46023 - 1462,
      );
      expect(drawingSerialOf(DateTime(1904, 3, 1, 12), date1904: true), 60.5);
      expect(drawingDateOf(0, date1904: true), DateTime(1904, 1, 1));
      expect(drawingDateOf(1, date1904: true), DateTime(1904, 1, 2));
      expect(drawingDateOf(60, date1904: true), DateTime(1904, 3, 1));
      expect(drawingDateOf(60.5, date1904: true), DateTime(1904, 3, 1, 12));
      expect(drawingDateOf(46023 - 1462, date1904: true), DateTime(2026, 1, 1));
    });

    test("skip Excel's 29 February 1900", () {
      expect(drawingSerialOf(DateTime(1900, 1, 1)), 1);
      expect(drawingSerialOf(DateTime(1900, 2, 28)), 59);
      expect(drawingSerialOf(DateTime(1900, 3, 1)), 61);
      expect(drawingDateOf(59), DateTime(1900, 2, 28));
      expect(drawingDateOf(61), DateTime(1900, 3, 1));
      expect(drawingDateOf(1), DateTime(1900, 1, 1));
    });

    test('count days from 1899-12-31', () {
      expect(drawingSerialOf(DateTime(2026, 1, 1)), 46023);
      expect(drawingDateOf(46023), DateTime(2026, 1, 1));
    });

    test('carry the time of day as the fraction', () {
      expect(drawingSerialOf(DateTime(2026, 1, 1, 12)), 46023.5);
      expect(drawingDateOf(46023.5), DateTime(2026, 1, 1, 12));
      expect(drawingDateOf(46023.25), DateTime(2026, 1, 1, 6));
    });

    test('use the wall-clock fields only', () {
      expect(drawingSerialOf(DateTime.utc(2026, 1, 1)), 46023);
    });

    test('read the phantom day as 1 March 1900', () {
      expect(drawingDateOf(60), DateTime(1900, 3, 1));
    });

    test('round-trip every day of a year to the millisecond', () {
      for (int d = 0; d < 366; d++) {
        final DateTime date = DateTime(2024, 1, 1 + d, 13, 14, 15, 16);
        expect(drawingDateOf(drawingSerialOf(date)), date);
      }
    });

    test('drawingDateOf throws for a value that is not finite', () {
      expect(() => drawingDateOf(double.nan), throwsArgumentError);
      expect(() => drawingDateOf(double.infinity), throwsArgumentError);
    });
  });

  group('drawingEscapeXstring and drawingUnescapeXstring', () {
    test('escape every _xHHHH_ look-alike', () {
      expect(drawingEscapeXstring('_x0041_'), '_x005F_x0041_');
      expect(
        drawingEscapeXstring('_x0041_x0042_'),
        '_x005F_x0041_x005F_x0042_',
      );
      expect(drawingEscapeXstring('a_b _x12_ _xZZZZ_'), 'a_b _x12_ _xZZZZ_');
      expect(drawingEscapeXstring('_X0041_'), '_X0041_');
    });

    test('unescape reads _xHHHH_ as the character', () {
      expect(drawingUnescapeXstring('_x0041_'), 'A');
      expect(drawingUnescapeXstring('_x005F_x0041_'), '_x0041_');
      expect(drawingUnescapeXstring('_xD83D__xDE00_'), '😀');
      expect(drawingUnescapeXstring('plain'), 'plain');
    });

    test('round-trip', () {
      for (final String s in <String>[
        '_x0041_',
        '_x0041_x0042_',
        'a_x005F_b',
        "'O''Brien'!\$A\$1",
        '',
      ]) {
        expect(drawingUnescapeXstring(drawingEscapeXstring(s)), s);
      }
    });
  });

  group('drawingDateOf field by field', () {
    test('a whole day and a fractional serial round-trip', () {
      // 2026-03-29 and 2026-10-25 are DST change days in much of Europe.
      for (final DateTime d in <DateTime>[
        DateTime(2026, 3, 29),
        DateTime(2026, 3, 29, 2, 30),
        DateTime(2026, 3, 29, 23, 59, 59, 999),
        DateTime(2026, 10, 25, 2, 30, 15, 250),
        DateTime(2026, 10, 25, 12),
      ]) {
        final DateTime back = drawingDateOf(drawingSerialOf(d));
        expect(
          <int>[
            back.year,
            back.month,
            back.day,
            back.hour,
            back.minute,
            back.second,
            back.millisecond,
          ],
          <int>[
            d.year,
            d.month,
            d.day,
            d.hour,
            d.minute,
            d.second,
            d.millisecond,
          ],
          reason: '$d',
        );
      }
    });

    test('a time that rounds up to midnight carries to the next day', () {
      expect(drawingDateOf(46023 + 0.9999999999), DateTime(2026, 1, 2));
      expect(drawingDateOf(59.9999999999), DateTime(1900, 3, 1));
    });
  });
}
