import 'package:jet_office/src/xlsx/date_serial.dart';
import 'package:test/test.dart';

void main() {
  test('date serial edges', () {
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

  test('date-time serials use wall-clock fields', () {
    expect(dateTimeSerial(DateTime(2026, 10, 24)), 46319.0);
    expect(dateTimeSerial(DateTime(2026, 10, 24, 12)), 46319.5);
    expect(dateTimeSerial(DateTime.utc(2026, 10, 24, 12)), 46319.5);
    expect(
      dateTimeSerial(DateTime(2026, 10, 24, 23, 59, 59, 999)),
      closeTo(46319.9999999884259259, 1e-9),
    );
    expect(
      dateTimeSerial(DateTime(2026, 10, 24, 23, 59, 59, 999))! < 46320,
      isTrue,
    );
    expect(dateTimeSerial(DateTime(1899, 12, 31, 23)), isNull);
  });
}
