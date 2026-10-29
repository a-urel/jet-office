import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/format/excel_number.dart';
import 'package:test/test.dart';

/// [digits] read as Excel reads it.
ExcelNumber excel(String digits) => ExcelNumber.from(XlsxDecimal(digits))!;

/// [n] rounded to [places] decimals, as a record for `expect`.
({String whole, String fraction}) fixed(ExcelNumber n, int places) =>
    n.toFixed(places);

void main() {
  group('from', () {
    test('0.30000000000000004 is 0.3 to 15 places', () {
      expect(fixed(excel('0.30000000000000004'), 15), (
        whole: '0',
        fraction: '300000000000000',
      ));
    });

    test('2.675 rounds to 2.68, not the double 2.67', () {
      expect(fixed(excel('2.675'), 2), (whole: '2', fraction: '68'));
    });

    test('1.005 rounds to 1.01', () {
      expect(fixed(excel('1.005'), 2), (whole: '1', fraction: '01'));
    });

    test('-2.5 rounds half away from zero to 3, negative', () {
      final ExcelNumber n = excel('-2.5');
      expect(fixed(n, 0), (whole: '3', fraction: ''));
      expect(n.negative, isTrue);
    });

    test('9007199254740993 keeps 15 significant digits', () {
      expect(fixed(excel('9007199254740993'), 0).whole, '9007199254740990');
    });

    test('1e308 has 309 whole digits', () {
      final String whole = ExcelNumber.from(1e308)!.toFixed(0).whole;
      expect(whole.length, 309);
      expect(whole, '1${'0' * 308}');
    });

    test('a small number in exponential form', () {
      expect(ExcelNumber.from(1e-7)!.toSignificant(3), (
        digits: '100',
        exponent: -7,
      ));
      expect(fixed(ExcelNumber.from(1.5e-7)!, 8), (
        whole: '0',
        fraction: '00000015',
      ));
    });

    test('NaN and infinity are null', () {
      expect(ExcelNumber.from(double.nan), isNull);
      expect(ExcelNumber.from(double.infinity), isNull);
      expect(ExcelNumber.from(double.negativeInfinity), isNull);
      expect(ExcelNumber.from(XlsxDecimal('1${'0' * 400}')), isNull);
    });

    test('an int and a double', () {
      expect(fixed(ExcelNumber.from(42)!, 1), (whole: '42', fraction: '0'));
      expect(fixed(ExcelNumber.from(-0.125)!, 2), (whole: '0', fraction: '13'));
    });

    test('negative zero is zero and not negative', () {
      final ExcelNumber n = ExcelNumber.from(-0.0)!;
      expect(n.isZero, isTrue);
      expect(n.negative, isFalse);
      expect(fixed(n, 2), (whole: '0', fraction: '00'));
    });

    test('a subnormal double is zero, as Excel has no denormals', () {
      for (final num v in <num>[1e-320, -1e-320, 5e-324, -5e-324]) {
        final ExcelNumber n = ExcelNumber.from(v)!;
        expect(n.isZero, isTrue, reason: '$v');
        expect(n.negative, isFalse, reason: '$v');
      }
      expect(excel('0.${'0' * 309}2').isZero, isTrue);
      expect(ExcelNumber.from(2.2250738585072014e-308)!.isZero, isFalse);
      expect(ExcelNumber.from(-2.2250738585072014e-308)!.isZero, isFalse);
    });

    test('another type is a programmer error', () {
      expect(() => ExcelNumber.from('1'), throwsArgumentError);
      expect(() => ExcelNumber.from(Object()), throwsArgumentError);
    });
  });

  group('toFixed', () {
    test('-0.0001 to two places is 0.00 but not zero', () {
      final ExcelNumber n = excel('-0.0001');
      expect(fixed(n, 2), (whole: '0', fraction: '00'));
      expect(n.isZero, isFalse);
      expect(n.negative, isTrue);
    });

    test('a carry adds a digit', () {
      expect(fixed(ExcelNumber.parse('9.995'), 2), (
        whole: '10',
        fraction: '00',
      ));
      expect(fixed(ExcelNumber.parse('0.5'), 0), (whole: '1', fraction: ''));
      expect(fixed(ExcelNumber.parse('0.05'), 1), (whole: '0', fraction: '1'));
      expect(fixed(ExcelNumber.parse('0.04'), 1), (whole: '0', fraction: '0'));
    });

    test('pads the fraction with zeros', () {
      expect(fixed(ExcelNumber.parse('1200'), 3), (
        whole: '1200',
        fraction: '000',
      ));
    });

    test('a negative place count is a programmer error', () {
      expect(() => ExcelNumber.parse('1').toFixed(-1), throwsArgumentError);
    });
  });

  group('shift', () {
    test('12200000 shifted by -6 is 12.2', () {
      expect(fixed(ExcelNumber.parse('12200000').shift(-6), 1), (
        whole: '12',
        fraction: '2',
      ));
    });

    test('0.25 shifted by 2 is 25', () {
      expect(fixed(ExcelNumber.parse('0.25').shift(2), 0), (
        whole: '25',
        fraction: '',
      ));
    });

    test('zero stays zero', () {
      expect(ExcelNumber.parse('0').shift(5).isZero, isTrue);
    });
  });

  group('toSignificant', () {
    test('0.000012345678 to six digits', () {
      expect(ExcelNumber.parse('0.000012345678').toSignificant(6), (
        digits: '123457',
        exponent: -5,
      ));
    });

    test('a carry moves the exponent', () {
      expect(ExcelNumber.parse('99.96').toSignificant(3), (
        digits: '100',
        exponent: 2,
      ));
    });

    test('pads with zeros', () {
      expect(ExcelNumber.parse('-1.5').toSignificant(4), (
        digits: '1500',
        exponent: 0,
      ));
    });

    test('zero', () {
      expect(ExcelNumber.parse('0').toSignificant(2), (
        digits: '00',
        exponent: 0,
      ));
    });

    test('fewer than one digit is a programmer error', () {
      expect(
        () => ExcelNumber.parse('1').toSignificant(0),
        throwsArgumentError,
      );
    });
  });

  group('parse', () {
    test('is exact, with no rounding to 15 digits', () {
      expect(
        ExcelNumber.parse('9007199254740993').toFixed(0).whole,
        '9007199254740993',
      );
    });

    test('accepts a sign, a fraction and an exponent', () {
      expect(ExcelNumber.parse('+1.5'), ExcelNumber.parse('1.5'));
      expect(ExcelNumber.parse('.5'), ExcelNumber.parse('0.5'));
      expect(ExcelNumber.parse('5.'), ExcelNumber.parse('5'));
      expect(ExcelNumber.parse('1E3'), ExcelNumber.parse('1000'));
      expect(ExcelNumber.parse('1.5e-2'), ExcelNumber.parse('0.015'));
      expect(ExcelNumber.parse('-00120.0100'), ExcelNumber.parse('-120.01'));
    });

    test('-0 is zero and not negative', () {
      final ExcelNumber n = ExcelNumber.parse('-0.000');
      expect(n.isZero, isTrue);
      expect(n.negative, isFalse);
      expect(n, ExcelNumber.parse('0'));
    });

    test('an exponent of any length', () {
      expect(
        ExcelNumber.parse('1e99999999999999999999').toDouble(),
        double.infinity,
      );
      expect(ExcelNumber.parse('1e-99999999999999999999').toDouble(), 0.0);
      expect(
        ExcelNumber.parse(
          '1e99999999999999999999',
        ).compareTo(ExcelNumber.parse('1e400')),
        1,
      );
    });

    test('anything else is a programmer error', () {
      for (final String text in <String>[
        '',
        '-',
        '.',
        'e5',
        '1e',
        '1e+',
        '1.2.3',
        'abc',
        ' 1',
        '1 ',
        '--1',
      ]) {
        expect(
          () => ExcelNumber.parse(text),
          throwsArgumentError,
          reason: text,
        );
      }
    });
  });

  group('compareTo', () {
    int cmp(String a, String b) =>
        ExcelNumber.parse(a).compareTo(ExcelNumber.parse(b));

    test('across signs', () {
      expect(cmp('-1', '1'), -1);
      expect(cmp('1', '-1'), 1);
      expect(cmp('-1', '0'), -1);
      expect(cmp('0', '-0.001'), 1);
      expect(cmp('0', '-0'), 0);
    });

    test('across exponents', () {
      expect(cmp('100', '99.9'), 1);
      expect(cmp('0.01', '0.1'), -1);
      expect(cmp('-100', '-99.9'), -1);
      expect(cmp('-0.01', '-0.1'), 1);
    });

    test('same exponent, by digits', () {
      expect(cmp('1.5', '1.25'), 1);
      expect(cmp('1.2', '1.25'), -1);
      expect(cmp('-1.2', '-1.25'), 1);
      expect(cmp('1.50', '1.5'), 0);
    });
  });

  group('the rest', () {
    test('abs drops the sign', () {
      expect(ExcelNumber.parse('-2.5').abs(), ExcelNumber.parse('2.5'));
      expect(ExcelNumber.parse('2.5').abs(), ExcelNumber.parse('2.5'));
    });

    test('toDouble', () {
      expect(ExcelNumber.parse('-2.5').toDouble(), -2.5);
      expect(ExcelNumber.parse('0').toDouble(), 0.0);
      expect(ExcelNumber.parse('1.5e300').toDouble(), 1.5e300);
      expect(excel('0.30000000000000004').toDouble(), 0.3);
    });

    test('equal numbers have equal hash codes', () {
      expect(
        ExcelNumber.parse('1.50').hashCode,
        ExcelNumber.parse('1.5').hashCode,
      );
    });

    test('toString', () {
      expect(ExcelNumber.parse('-120.01').toString(), '-120.01');
      expect(ExcelNumber.parse('0.0015').toString(), '0.0015');
      expect(ExcelNumber.parse('1200').toString(), '1200');
      expect(ExcelNumber.parse('0').toString(), '0');
      expect(ExcelNumber.parse('1.5e300').toString(), '1.5e300');
      expect(ExcelNumber.parse('-1e-300').toString(), '-1e-300');
    });
  });
}
