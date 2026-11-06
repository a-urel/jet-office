import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/read/serial_dates.dart';
import 'package:test/test.dart';

/// Shows the date and the time down to the millisecond.
const String _code = 'yyyy-mm-dd hh:mm:ss.000';

void main() {
  // The reader turns a serial into a UTC date and time (`serialToDateTime`),
  // and the formatter reads a serial itself: the two must agree, in both
  // date systems.
  group('a serial read as a date shows as the serial does', () {
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
          final NumberFormatter formatter = NumberFormatter(date1904: date1904);
          final DateTime value = serialToDateTime(
            digits,
            date1904: date1904,
          ).date!;
          expect(
            formatter.format(value, numberFormat: _code).text,
            formatter.format(XlsxDecimal(digits), numberFormat: _code).text,
          );
        });
      }
    }
  });
}
