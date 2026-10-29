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
}
