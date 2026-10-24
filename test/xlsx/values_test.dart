import 'package:jet_office/src/xlsx/number_format.dart';
import 'package:jet_office/src/xlsx/style.dart';
import 'package:jet_office/src/xlsx/values.dart';
import 'package:test/test.dart';

void main() {
  group('XlsxDecimal', () {
    test('accepts plain decimal digits', () {
      expect(XlsxDecimal('-1234.50').digits, '-1234.50');
      expect(XlsxDecimal('0').digits, '0');
      expect(XlsxDecimal('007').digits, '007');
    });

    test('rejects everything else', () {
      for (final String bad in <String>[
        '1.234,56',
        '1e3',
        '',
        '+1',
        '.5',
        '5.',
        '1 ',
        '-',
        '1.2.3',
      ]) {
        expect(() => XlsxDecimal(bad), throwsArgumentError, reason: bad);
      }
    });
  });

  group('value equality', () {
    test('XlsxDate', () {
      expect(const XlsxDate(2026, 10, 24), const XlsxDate(2026, 10, 24));
      expect(
        const XlsxDate(2026, 10, 24).hashCode,
        const XlsxDate(2026, 10, 24).hashCode,
      );
      expect(const XlsxDate(2026, 10, 24), isNot(const XlsxDate(2026, 10, 25)));
    });

    test('XlsxDecimal', () {
      expect(XlsxDecimal('1.5'), XlsxDecimal('1.5'));
      expect(XlsxDecimal('1.5').hashCode, XlsxDecimal('1.5').hashCode);
      expect(XlsxDecimal('1.5'), isNot(XlsxDecimal('1.50')));
    });

    test('XlsxFormula', () {
      expect(
        const XlsxFormula('A1', cached: 1),
        const XlsxFormula('A1', cached: 1),
      );
      expect(
        const XlsxFormula('A1', cached: 1).hashCode,
        const XlsxFormula('A1', cached: 1).hashCode,
      );
      expect(
        const XlsxFormula('A1'),
        isNot(const XlsxFormula('A1', cached: 1)),
      );
      expect(const XlsxFormula('A1'), isNot(const XlsxFormula('A2')));
    });

    test('XlsxCell', () {
      const XlsxStyle style = XlsxStyle(numFmt: XlsxNumFmt.localeShortDate);
      expect(const XlsxCell(1, style: style), const XlsxCell(1, style: style));
      expect(
        const XlsxCell(1, style: style).hashCode,
        const XlsxCell(1, style: style).hashCode,
      );
      expect(const XlsxCell(1, style: style), isNot(const XlsxCell(1)));
      expect(const XlsxCell(1), isNot(const XlsxCell(2)));
    });
  });
}
