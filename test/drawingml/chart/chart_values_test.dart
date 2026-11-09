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
}
