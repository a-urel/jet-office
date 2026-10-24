import 'package:jet_office/src/xlsx/date_serial.dart';
import 'package:test/test.dart';

void main() {
  test('dateSerial at the edges of Excel\'s range and of the calendar', () {
    expect(dateSerial(1900, 1, 1), 1);
    expect(dateSerial(1900, 2, 28), 59);
    expect(dateSerial(1900, 3, 1), 61);
    expect(dateSerial(1970, 1, 1), 25569);
    expect(dateSerial(2026, 10, 24), 46319);
    expect(dateSerial(9999, 12, 31), 2958465);
    expect(dateSerial(1899, 12, 31), isNull);
    expect(() => dateSerial(2026, 13, 1), throwsArgumentError);
    expect(() => dateSerial(2026, 2, 30), throwsArgumentError);
  });

  test('dateTimeSerial uses the wall-clock fields and the day fraction', () {
    expect(dateTimeSerial(DateTime(2026, 10, 24)), 46319.0);
    expect(dateTimeSerial(DateTime(2026, 10, 24, 12)), 46319.5);
    expect(dateTimeSerial(DateTime.utc(2026, 10, 24, 12)), 46319.5);
    expect(
      dateTimeSerial(DateTime(2026, 10, 24, 23, 59, 59, 999)),
      allOf(closeTo(46319.9999999884259259, 1e-9), lessThan(46320)),
    );
    expect(dateTimeSerial(DateTime(1899, 12, 31, 23)), isNull);
  });

  test('dateSerial and dateTimeSerial return null after 9999-12-31', () {
    expect(dateSerial(10000, 1, 1), isNull);
    final last = dateTimeSerial(DateTime(9999, 12, 31, 23, 59, 59));
    expect(last, isNotNull);
    expect(last! < 2958466, isTrue);
    expect(dateTimeSerial(DateTime(10000)), isNull);
  });

  test(
    'dateTimeSerial returns null when 9999-12-31 rounds to the next day',
    () {
      // The fraction is just below 1, but the double sum rounds to 2958466.
      expect(
        dateTimeSerial(DateTime(9999, 12, 31, 23, 59, 59, 999, 999)),
        isNull,
      );
    },
  );

  test('invalid days are rejected and 1900 has no 29 February', () {
    expect(() => dateSerial(1900, 2, 29), throwsArgumentError);
    expect(dateSerial(2024, 2, 29), 45351);
    expect(() => dateSerial(2026, 1, 0), throwsArgumentError);
    expect(dateTimeSerial(DateTime(1900)), 1.0);
    expect(dateTimeSerial(DateTime(1900, 3, 1, 12)), 61.5);
  });

  test('dateSerial beyond DateTime checks the calendar by hand', () {
    expect(dateSerial(300000, 2, 29), isNull); // 300000 is a leap year
    expect(dateSerial(-300000, 1, 1), isNull);
    expect(() => dateSerial(300001, 2, 29), throwsArgumentError);
    expect(() => dateSerial(300000, 13, 1), throwsArgumentError);
    expect(() => dateSerial(300000, 1, 0), throwsArgumentError);
    expect(() => dateSerial(300000, 4, 31), throwsArgumentError);
  });
}
