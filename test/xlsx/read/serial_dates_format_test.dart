import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import 'support/workbook_builder.dart';

/// Shows the date and the time down to the millisecond.
const String _code = 'yyyy-mm-dd hh:mm:ss.000';

/// Styles with one cell format, `xf` 1, that shows [_code].
const String _styles =
    '<styleSheet xmlns="$mainNs">'
    '<numFmts count="1"><numFmt numFmtId="164" formatCode="$_code"/></numFmts>'
    '<cellXfs count="2"><xf numFmtId="0"/>'
    '<xf numFmtId="164" applyNumberFormat="1"/></cellXfs>'
    '</styleSheet>';

/// The cell A1 of a workbook that holds the serial [digits] in a date format.
XlsxReadCell _readCell(String digits, {required bool date1904}) {
  final XlsxReader reader = XlsxReader(
    buildWorkbook(
      <String, String?>{
        'S': worksheet('<row r="1"><c r="A1" s="1"><v>$digits</v></c></row>'),
      },
      styles: _styles,
      date1904: date1904,
    ),
  );
  return reader.rows('S').single.cells.single;
}

void main() {
  // The reader turns a serial into a UTC date and time, and the formatter
  // reads a serial itself: the two must agree, in both date systems.
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
          final XlsxReadCell cell = _readCell(digits, date1904: date1904);
          expect(cell.value, isA<DateTime>());
          expect(
            formatter.formatCell(cell).text,
            formatter.format(XlsxDecimal(digits), numberFormat: _code).text,
          );
          // The date is the exact serial: it shows as the same number.
          expect(
            formatter.format(cell.value, numberFormat: '0.00000000').text,
            formatter
                .format(XlsxDecimal(digits), numberFormat: '0.00000000')
                .text,
          );
        });
      }
    }
  });
}
