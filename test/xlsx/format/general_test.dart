import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/format/excel_number.dart';
import 'package:jet_office/src/xlsx/format/format_code.dart';
import 'package:jet_office/src/xlsx/format/format_locale.dart';
import 'package:jet_office/src/xlsx/format/formatted_value.dart';
import 'package:jet_office/src/xlsx/format/general.dart';
import 'package:jet_office/src/xlsx/format/number_renderer.dart';
import 'package:jet_office/src/xlsx/format/section_choice.dart';
import 'package:test/test.dart';

import 'number_renderer_test.dart' show commaLocale;

/// [value] in `General` at [width], with no sign.
String g(
  Object value, {
  int width = 11,
  XlsxFormatLocale locale = XlsxFormatLocale.enUS,
}) =>
    renderGeneral(ExcelNumber.from(value)!.abs(), width: width, locale: locale);

/// [value] in [code], with the section chosen as Task 5 does.
({String text, FormatColor? color}) section(String code, num value) {
  final ({FormatSection section, bool showMinus, ExcelNumber value}) choice =
      chooseNumberSection(parseFormatCode(code), ExcelNumber.from(value)!)!;
  final List<XlsxFormatPart> parts = renderNumber(
    choice.section,
    choice.value,
    showMinus: choice.showMinus,
    locale: XlsxFormatLocale.enUS,
    generalWidth: 11,
  );
  return (
    text: parts
        .map(
          (XlsxFormatPart p) => switch (p) {
            XlsxFormatText() => p.text,
            XlsxFormatPadding() => ' ',
            XlsxFormatFill() => '',
          },
        )
        .join(),
    color: choice.section.color,
  );
}

void main() {
  group('General at the default width of 11', () {
    test('an integer of up to 11 digits is shown in full', () {
      expect(g(12345678901), '12345678901');
      expect(g(100), '100');
      expect(g(0), '0');
    });

    test('a 12-digit integer is scientific', () {
      expect(g(123456789012), '1.23457E+11');
    });

    test('fixed notation keeps the digits that fit', () {
      expect(g(XlsxDecimal('0.333333333333333')), '0.333333333');
      expect(g(12345.6789012), '12345.6789');
    });

    test('the 15-digit limit removes binary noise', () {
      expect(g(XlsxDecimal('0.30000000000000004')), '0.3');
      expect(g(0.1 + 0.2), '0.3');
    });

    test('leading zeros count toward the width', () {
      expect(g(0.0001234567891), '0.000123457');
    });

    test('an exponent of -5 or below is scientific', () {
      expect(g(0.000012345678), '1.23457E-05');
      expect(g(1E-10), '1E-10');
    });

    test('rounding that carries is shown correctly', () {
      expect(g(XlsxDecimal('0.0999999999999')), '0.1');
      expect(g(99999999999.5), '1E+11');
      expect(g(XlsxDecimal('9999999999.99')), '10000000000');
    });

    test('a three-digit exponent shortens the mantissa', () {
      expect(g(1.23456789E+100), '1.2346E+100');
      expect(g(1.5E-300), '1.5E-300');
    });
  });

  group('General at other widths', () {
    test('width 5', () {
      expect(g(123456, width: 5), '1E+05');
      expect(g(1.25, width: 5), '1.25');
    });

    test('a wider column shows up to 15 significant digits', () {
      expect(
        g(XlsxDecimal('0.333333333333333'), width: 20),
        '0.333333333333333',
      );
    });

    test('a width too small still returns the shortest form', () {
      expect(g(5, width: 1), '5');
      expect(g(1.5, width: 1), '2');
      expect(g(0.5, width: 1), '5E-01');
      expect(g(123, width: 2), '1E+02');
    });
  });

  group('General in a section', () {
    test('literals are added around the number', () {
      expect(section('General" kg"', 5).text, '5 kg');
    });

    test('an explicit minus in the negative section', () {
      expect(section('General;-General', -3).text, '-3');
    });

    test('a single section with a color shows the minus and the color', () {
      final ({String text, FormatColor? color}) red = section(
        '[Red]General',
        -3,
      );
      expect(red.text, '-3');
      expect(red.color, const FormatColor(rgb: 0xFF0000));
    });

    test('the minus comes before literals', () {
      expect(section('"x"General', -1.5).text, '-x1.5');
    });
  });

  test('the decimal separator comes from the locale', () {
    expect(g(1.5, locale: commaLocale), '1,5');
  });
}
