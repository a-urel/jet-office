import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/format/formatter.dart'
    show formatterCacheSize;
import 'package:test/test.dart';

final XlsxNumberFormatter formatter = XlsxNumberFormatter();

String text(Object? value, String code) =>
    formatter.format(value, numberFormat: code).text;

void main() {
  group('end to end', () {
    test('section choice', () {
      expect(text(-1234, '#,##0 ;(#,##0)'), '(1,234)');
    });

    test('fixed point', () {
      expect(text(XlsxDecimal('1234.5'), '#,##0.00'), '1,234.50');
    });

    test('scientific', () {
      expect(text(12345, '0.00E+00'), '1.23E+04');
    });

    test('fraction', () {
      expect(text(2.5, '# ?/?'), '2 1/2');
    });

    test('General', () {
      expect(text(123456789012, 'General'), '1.23457E+11');
    });

    test('a subnormal double shows as zero', () {
      expect(text(1e-320, 'General'), '0');
      expect(text(-1e-320, '0.00E+00'), '0.00E+00');
      expect(text(5e-324, 'General'), '0');
    });

    test('text', () {
      expect(text('abc', '"Name: "@'), 'Name: abc');
    });

    test('a last text section leaves numbers to the others', () {
      expect(text(-5, '0;@'), '-5');
      expect(text(5, '0;@'), '5');
      expect(text('a', '0;@'), 'a');
    });

    test('a boolean, an error and null', () {
      expect(text(true, '0.00'), 'TRUE');
      expect(text(const XlsxErrorValue('#DIV/0!'), '0.00'), '#DIV/0!');
      expect(text(null, '0.00'), '');
    });

    test('a date code shows the number as General (until N2)', () {
      expect(text(46000, 'dd.mm.yyyy'), '46000');
    });
  });

  group('the result', () {
    test('text joins padding as one space and leaves fill out', () {
      final XlsxFormattedValue result = formatter.format(
        'abc',
        numberFormat: '_(@_)*-',
      );
      expect(result.parts, <XlsxFormatPart>[
        const XlsxFormatPadding('('),
        const XlsxFormatText('abc'),
        const XlsxFormatPadding(')'),
        const XlsxFormatFill('-'),
      ]);
      expect(result.text, ' abc ');
      expect(result.color, isNull);
      expect(result.overflow, isFalse);
      expect(result.warning, isNull);
    });

    test('no section matching is overflow, shown as #', () {
      final XlsxFormattedValue result = formatter.format(
        50,
        numberFormat: '[>100]0;[<-100]0',
      );
      expect(result.overflow, isTrue);
      expect(result.text, '#');
      expect(result.warning, isNull);
    });

    test('a named color is rgb', () {
      final XlsxFormattedValue result = formatter.format(
        5,
        numberFormat: '[Blue]0',
      );
      expect(result.text, '5');
      expect(result.color, const XlsxColor.rgb(0x0000FF));
    });

    test('[ColorN] is the indexed entry N + 7', () {
      expect(
        formatter.format(5, numberFormat: '[Color12]0').color,
        const XlsxColor.indexed(19),
      );
    });

    test('has value equality and a toString', () {
      final XlsxFormattedValue a = formatter.format(5, numberFormat: '0.0');
      final XlsxFormattedValue b = formatter.format(5, numberFormat: '0.0');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(formatter.format(6, numberFormat: '0.0')));
      expect(a.toString(), contains('5.0'));
    });
  });

  group('code resolution', () {
    test('a built-in id without a code uses the built-in table', () {
      expect(formatter.format(1234.5, numberFormatId: 4).text, '1,234.50');
    });

    test('id 0 without a code is General', () {
      final XlsxFormattedValue result = formatter.format(1234.5);
      expect(result.text, '1234.5');
      expect(result.warning, isNull);
    });

    test('an unknown id without a code is General with a warning', () {
      final XlsxFormattedValue result = formatter.format(
        1234.5,
        numberFormatId: 200,
      );
      expect(result.text, '1234.5');
      expect(result.warning, XlsxWarningCode.unresolvedNumberFormat);
    });

    test('a code given wins over the id', () {
      expect(
        formatter.format(1234.5, numberFormatId: 4, numberFormat: '0').text,
        '1235',
      );
    });
  });

  group('invalid codes show General with numberFormatInvalid', () {
    for (final String code in <String>['0"abc', '0' * 256, '0;0;0;0;0']) {
      test(code.length > 20 ? 'a ${code.length}-character code' : code, () {
        final XlsxFormattedValue result = formatter.format(
          1234.5,
          numberFormat: code,
        );
        expect(result.text, '1234.5');
        expect(result.warning, XlsxWarningCode.numberFormatInvalid);
      });
    }

    test('an output longer than 1,000 characters', () {
      final XlsxFormattedValue result = formatter.format(
        1e308,
        numberFormat: '0${'%' * 254}',
      );
      expect(result.text, '1E+308');
      expect(result.warning, XlsxWarningCode.numberFormatInvalid);
    });

    test('a 1 MiB code is General and is not cached', () {
      final XlsxNumberFormatter own = XlsxNumberFormatter();
      final XlsxFormattedValue result = own.format(
        1234.5,
        numberFormat: '0' * (1 << 20),
      );
      expect(result.text, '1234.5');
      expect(result.warning, XlsxWarningCode.numberFormatInvalid);
      expect(formatterCacheSize(own), 0);
    });

    test('@ repeated on long text is refused before it is built', () {
      final String long = 'x' * 100000;
      final Stopwatch watch = Stopwatch()..start();
      final XlsxFormattedValue result = formatter.format(
        long,
        numberFormat: '@' * 255,
      );
      expect(watch.elapsedMilliseconds, lessThan(1000));
      expect(result.text, long);
      expect(result.warning, XlsxWarningCode.numberFormatInvalid);
    });

    test('literals and a second @ count toward the bound', () {
      final String text = 'x' * 600;
      expect(formatter.format(text, numberFormat: '@@').warning, isNull);
      expect(
        formatter.format(text, numberFormat: '@"${'y' * 401}"@').warning,
        XlsxWarningCode.numberFormatInvalid,
      );
    });
  });

  group('a value shown unchanged is never over the bound', () {
    final String long = 'x' * 1500;
    for (final String code in <String>['General', '@', '0.00']) {
      test('1,500 characters of text with $code', () {
        final XlsxFormattedValue result = formatter.format(
          long,
          numberFormat: code,
        );
        expect(result.text, long);
        expect(result.warning, isNull);
      });
    }

    test('1,500 characters of text with a literal', () {
      final XlsxFormattedValue result = formatter.format(
        long,
        numberFormat: '"Name: "@',
      );
      expect(result.text, 'Name: $long');
      expect(result.warning, isNull);
    });
  });

  test('formatCell formats the cell\'s value with its format', () {
    final XlsxReadCell cell = XlsxReadCell(
      2,
      XlsxDecimal('1234.5'),
      numberFormatId: 4,
      numberFormat: '#,##0.00',
    );
    expect(
      formatter.formatCell(cell, generalWidth: 8),
      formatter.format(
        cell.value,
        numberFormatId: 4,
        numberFormat: '#,##0.00',
        generalWidth: 8,
      ),
    );
    expect(formatter.formatCell(cell).text, '1,234.50');
  });

  group('programmer errors throw', () {
    test('generalWidth below 1', () {
      expect(() => formatter.format(5, generalWidth: 0), throwsArgumentError);
    });

    test('an unsupported value type', () {
      expect(() => formatter.format(Object()), throwsArgumentError);
    });
  });

  test('the cache stays bounded over 300,000 distinct codes', () {
    final XlsxNumberFormatter own = XlsxNumberFormatter();
    int largest = 0;
    for (int i = 0; i < 300000; i++) {
      final String shown = own.format(1, numberFormat: '0"$i"').text;
      if (shown != '1$i') fail('code $i shows $shown');
      final int size = formatterCacheSize(own);
      if (size > largest) largest = size;
    }
    expect(largest, 1024);
  });

  test('the formatter keeps its locale and date system', () {
    final XlsxNumberFormatter own = XlsxNumberFormatter(date1904: true);
    expect(own.locale, XlsxFormatLocale.enUS);
    expect(own.date1904, isTrue);
    expect(formatter.date1904, isFalse);
  });
}
