import 'package:jet_office/src/xlsx/format/date_renderer.dart';
import 'package:jet_office/src/xlsx/format/excel_number.dart';
import 'package:jet_office/src/xlsx/format/format_code.dart';
import 'package:jet_office/src/xlsx/format/format_locale.dart';
import 'package:jet_office/src/xlsx/format/formatted_value.dart';
import 'package:jet_office/src/xlsx/format/number_renderer.dart';
import 'package:jet_office/src/xlsx/format/section_choice.dart';
import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:test/test.dart';

/// A locale with `,` as the decimal point and `.` for grouping.
final XlsxFormatLocale commaLocale = XlsxFormatLocale(
  decimalSeparator: ',',
  groupSeparator: '.',
  monthNames: XlsxFormatLocale.enUS.monthNames,
  monthAbbreviations: XlsxFormatLocale.enUS.monthAbbreviations,
  dayNames: XlsxFormatLocale.enUS.dayNames,
  dayAbbreviations: XlsxFormatLocale.enUS.dayAbbreviations,
  am: 'AM',
  pm: 'PM',
  trueText: 'TRUE',
  falseText: 'FALSE',
  errorNames: XlsxFormatLocale.enUS.errorNames,
  lcid: 0x407,
  builtinCodes: XlsxFormatLocale.enUS.builtinCodes,
  longDateCode: XlsxFormatLocale.enUS.longDateCode,
  longTimeCode: XlsxFormatLocale.enUS.longTimeCode,
  messageLocale: XlsxLocale.de,
  verified: false,
);

/// The parts of [value] in [code], with the section chosen as Task 5 does.
List<XlsxFormatPart> parts(
  String code,
  num value, {
  XlsxFormatLocale locale = XlsxFormatLocale.enUS,
}) {
  final ({FormatSection section, bool showMinus, ExcelNumber value}) choice =
      chooseNumberSection(parseFormatCode(code), ExcelNumber.from(value)!)!;
  return renderNumber(
    choice.section,
    choice.value,
    showMinus: choice.showMinus,
    locale: locale,
    generalWidth: 11,
  );
}

/// The parts joined as `text` joins them: padding is one space, a fill
/// nothing.
String t(
  String code,
  num value, {
  XlsxFormatLocale locale = XlsxFormatLocale.enUS,
}) => parts(code, value, locale: locale)
    .map(
      (XlsxFormatPart p) => switch (p) {
        XlsxFormatText() => p.text,
        XlsxFormatPadding() => ' ',
        XlsxFormatFill() => '',
      },
    )
    .join();

void main() {
  group('digit placeholders', () {
    test('0 rounds half away from zero', () {
      expect(t('0', 1234.5), '1235');
      expect(t('0', -2.5), '-3');
    });

    test('0 pads with zeros', () {
      expect(t('00000', 123), '00123');
    });

    test('# drops the leading zero', () {
      expect(t('#.00', 0.5), '.50');
    });

    test('? gives a space for an insignificant digit', () {
      expect(t('0.0?', 1.5), '1.5 ');
      expect(t('???', 5), '  5');
    });

    test('more integer digits than placeholders are all shown', () {
      expect(t('0', 123456), '123456');
      expect(t('.00', 12.5), '12.50');
    });

    test('# drops trailing zeros of the fraction', () {
      expect(t('0.##', 1.5), '1.5');
      expect(t('0.##', 2), '2.');
    });
  });

  group('grouping and scaling', () {
    test('#,##0.00 groups thousands', () {
      expect(t('#,##0.00', 1234.5), '1,234.50');
      expect(t('#,##0.00', -1234.5), '-1,234.50');
    });

    test('a trailing comma divides by 1000', () {
      expect(t('0.0,,', 12200000), '12.2');
      expect(t('#,', 12000), '12');
    });

    test('grouping and scaling combine', () {
      expect(t('#,##0,', 1234567), '1,235');
    });

    test('1E+308 shows 309 integer digits with 102 commas', () {
      final String text = t('#,##0.00', 1E+308);
      expect(text, '100${',000' * 102}.00');
      final String whole = text.substring(0, text.indexOf('.'));
      expect(whole.replaceAll(',', '').length, 309);
      expect(','.allMatches(whole).length, 102);
      expect(text.endsWith('.00'), isTrue);
    });
  });

  group('percent', () {
    test('% multiplies by 100', () {
      expect(t('0%', 0.256), '26%');
      expect(t('0.00%', 1), '100.00%');
    });
  });

  group('literals', () {
    test('unquoted, quoted and escaped literals are shown', () {
      expect(t(r'$#,##0.00', 1234.5), r'$1,234.50');
      expect(t('0" kg"', 5), '5 kg');
      expect(t(r'\X0', 5), 'X5');
    });

    test('the minus goes before leading literals', () {
      expect(t(r'$#,##0.00', -1234.5), r'-$1,234.50');
    });

    test('a negative section writes its own sign', () {
      expect(t('#,##0 ;(#,##0)', -1234), '(1,234)');
    });
  });

  group('negative zero', () {
    test('a value that rounds to zero shows no minus', () {
      expect(t('0', -0.4), '0');
      expect(t('0.00', -0.001), '0.00');
    });
  });

  group('scientific', () {
    test('a mantissa and an exponent', () {
      expect(t('0.00E+00', 12345), '1.23E+04');
      expect(t('0.00E+00', 0), '0.00E+00');
      expect(t('0.00E+00', -12345), '-1.23E+04');
      expect(t('0.00E+00', 0.00012), '1.20E-04');
      expect(t('0.00E+00', 99999), '1.00E+05');
    });

    test('E- shows only a minus, and more digits than placeholders', () {
      expect(t('0E-0', 0.001), '1E-3');
      expect(t('0E-0', 1000), '1E3');
      expect(t('0.0E+0', 1.5e100), '1.5E+100');
    });

    test('engineering: the exponent is a multiple of the integer digits', () {
      expect(t('##0.0E+0', 12200000), '12.2E+6');
      expect(t('##0.0E+0', 0.000123), '123.0E-6');
      expect(t('##0.0E+0', 1234), '1.2E+3');
      expect(t('##0.0E+0', 0), '0.0E+0');
    });

    test('engineering: a carry moves to the next multiple', () {
      expect(t('##0.0E+0', 999.96), '1.0E+3');
    });

    test('engineering: a negative exponent', () {
      expect(t('##0.0E+0', 0.0012), '1.2E-3');
      expect(t('##0.0E+0', 0.012), '12.0E-3');
      expect(t('##0.0E+0', -0.0012), '-1.2E-3');
    });

    test('# in the mantissa drops trailing zeros', () {
      expect(t('0.0#E+0', 12345), '1.23E+4');
      expect(t('0.0#E+0', 12000), '1.2E+4');
      expect(t('0.0#E+0', 10000), '1.0E+4');
    });

    test('E-00 pads the exponent and shows only a minus', () {
      expect(t('0.00E-00', 12345), '1.23E04');
      expect(t('0.00E-00', 0.000123), '1.23E-04');
    });

    test('a literal after the exponent with a negative value', () {
      expect(t('0.0E+0" m"', -12345), '-1.2E+4 m');
    });

    test('the letter is printed as written', () {
      expect(t('0.0e+00', 12345), '1.2e+04');
    });

    test('literals, and the locale decimal separator', () {
      expect(t(r'0.00E+00" m"', 12345), '1.23E+04 m');
      expect(t('"x "0.00E+00', 12345), 'x 1.23E+04');
      expect(t('0.00E+00', 12345, locale: commaLocale), '1,23E+04');
    });

    test('a value that rounds to zero shows no minus', () {
      expect(t('0.00E+00', -0.0), '0.00E+00');
    });
  });

  group('fractions', () {
    test('a whole part and the best fraction', () {
      expect(t('# ?/?', 2.5), '2 1/2');
      expect(t('# ??/??', 3.14159), '3 14/99');
      expect(t('# ???/???', 3.14159265358979), '3  16/113');
      expect(t('# ?/?', -2.5), '-2 1/2');
    });

    test('without a whole part the fraction is improper', () {
      expect(t('?/?', 1.5), '3/2');
      expect(t('?/?', 2), '2/1');
      expect(t('?/?', -0.25), '-1/4');
    });

    test('a fixed denominator rounds the numerator half away from zero', () {
      expect(t('# ?/8', 0.5), ' 4/8');
      expect(t('# ?/8', 2.3), '2 2/8');
      expect(t('# ?/8', 0.0625), ' 1/8');
      expect(t('0/100', 0.25), '25/100');
      expect(t('?/15', 0.5), '8/15');
      expect(t('?/1"5"', 0.5), '1/15');
    });

    test('a zero fraction is blank under ? and left out under #', () {
      expect(t('# ?/?', 2), '2    ');
      expect(t('# #/#', 2), '2 ');
      expect(t('# ##/##', 2), '2 ');
      expect(t('# #/8', 2), '2 ');
      // A blank fixed denominator: unconfirmed in Excel (oracle list).
      expect(t('# ?/8', 2), '2    ');
      expect(t('# ?/?', 0), '0    ');
      expect(t('# ?/?', -0.01), '0    ');
    });

    test('a fraction that rounds to one carries into the whole part', () {
      expect(t('# ?/?', 0.9999), '1    ');
      expect(t('# ?/?', -1.9999), '-2    ');
      expect(t('# ?/8', 0.9375), '1    ');
    });

    test('the numerator pads on the left, the denominator on the right', () {
      expect(t('# ??/??', 0.75), '  3/4 ');
      expect(t('# 00/00', 1.5), '1 01/2 ');
      expect(t('# ?/##', 0.5), ' 1/2 ');
      expect(t('# ?/?', 0.5), ' 1/2');
      expect(t('0 ?/?', 0.5), '0 1/2');
    });

    test('a slash before a denominator too long to be one is kept', () {
      expect(t('?/9999999999', 2), '2/9999999999');
    });

    test('a numerator wider than its placeholders is shown in full', () {
      expect(t('?/?', 12.5), '25/2');
    });

    test('a whole part beyond double precision comes from the digits', () {
      expect(t('# ?/?', 1e300), '1${'0' * 300}    ');
      expect(t('?/?', 1e20), '1${'0' * 20}/1');
    });

    test('literals, grouping and the minus at the very start', () {
      expect(t('"x"# ?/?', -2.5), '-x2 1/2');
      expect(t('#,##0 ?/?', 1234.5), '1,234 1/2');
      expect(t(r'# ?/?" kg"', 2.5), '2 1/2 kg');
    });
  });

  group('parts', () {
    test('_x is padding', () {
      expect(parts('_(#,##0_)', 1234), <XlsxFormatPart>[
        const XlsxFormatPadding('('),
        const XlsxFormatText('1,234'),
        const XlsxFormatPadding(')'),
      ]);
    });

    test('*x is a fill, and adjacent text is merged', () {
      expect(parts('_-* #,##0_-', 1234), <XlsxFormatPart>[
        const XlsxFormatPadding('-'),
        const XlsxFormatFill(' '),
        const XlsxFormatText('1,234'),
        const XlsxFormatPadding('-'),
      ]);
      expect(parts(r'$#,##0" kg"', 1234), <XlsxFormatPart>[
        const XlsxFormatText(r'$1,234 kg'),
      ]);
    });
  });

  group('locale', () {
    test('separators come from the locale', () {
      expect(t('#,##0.00', 1234.5, locale: commaLocale), '1.234,50');
    });

    test('quoted text is untouched', () {
      expect(t('"1,5"0', 2, locale: commaLocale), '1,52');
    });
  });

  group('sectionWarning', () {
    XlsxWarningCode? warn(String code) => sectionWarning(
      parseFormatCode(code).sections.first,
      date: false,
      locale: XlsxFormatLocale.enUS,
    );

    test('an unsupported bracket warns', () {
      expect(warn('[DBNum1]0'), XlsxWarningCode.numberFormatUnsupported);
      expect(warn('[NatNum1]0'), XlsxWarningCode.numberFormatUnsupported);
    });

    test('a numeral system other than 0 or 1 warns', () {
      expect(warn('[\$-D000409]0'), XlsxWarningCode.numberFormatUnsupported);
    });

    test('the language is ignored in a number section', () {
      expect(warn('[\$€-40C]#,##0'), isNull);
    });

    test('the calendar is ignored in a number section', () {
      expect(warn('[\$-1060409]0'), isNull);
    });

    test('B2 warns', () {
      expect(warn('B2 0'), XlsxWarningCode.numberFormatUnsupported);
    });

    test('a plain number section does not warn', () {
      expect(warn('#,##0.00'), isNull);
    });
  });
}
