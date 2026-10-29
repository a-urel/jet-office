import 'package:jet_office/src/xlsx/format/format_code.dart';
import 'package:jet_office/src/xlsx/format/format_locale.dart';
import 'package:jet_office/src/xlsx/format/formatted_value.dart';
import 'package:jet_office/src/xlsx/format/value_renderer.dart';
import 'package:jet_office/src/xlsx/read/read_cell.dart';
import 'package:jet_office/src/xlsx/values.dart';
import 'package:test/test.dart';

({List<XlsxFormatPart> parts, FormatSection? section, bool overflow}) render(
  Object? value,
  String code,
) => renderValue(
  value,
  parseFormatCode(code),
  locale: XlsxFormatLocale.enUS,
  generalWidth: 11,
);

String textOf(Object? value, String code) =>
    render(value, code).parts.map((XlsxFormatPart p) {
      return p is XlsxFormatText ? p.text : '';
    }).join();

void main() {
  group('text', () {
    test('without a text section is unchanged', () {
      expect(render('abc', '0.00').parts, <XlsxFormatPart>[
        const XlsxFormatText('abc'),
      ]);
      expect(render('abc', '0.00').section, isNull);
    });

    test('numeric-looking text stays text', () {
      expect(textOf('123', '0.00'), '123');
    });

    test('the fourth section replaces it', () {
      expect(textOf('abc', '0;0;0;"x"'), 'x');
    });

    test('a literal and @', () {
      expect(textOf('abc', '"Name: "@'), 'Name: abc');
    });

    test('@ twice repeats it', () {
      expect(textOf('abc', '@@'), 'abcabc');
    });

    test('padding around the text', () {
      expect(render('abc', '0;0;0;_(@_)').parts, <XlsxFormatPart>[
        const XlsxFormatPadding('('),
        const XlsxFormatText('abc'),
        const XlsxFormatPadding(')'),
      ]);
    });

    test('fill is kept', () {
      expect(render('abc', '@*-').parts, <XlsxFormatPart>[
        const XlsxFormatText('abc'),
        const XlsxFormatFill('-'),
      ]);
    });
  });

  group('addedTextLength', () {
    int added(String code, int length) =>
        addedTextLength(parseFormatCode(code).sections.last, length);

    test('the first @ shows the value and adds nothing', () {
      expect(added('@', 1500), 0);
      expect(added('"Name: "@', 1500), 6);
    });

    test('each further @ adds the text again', () {
      expect(added('@' * 255, 1 << 20), 254 * (1 << 20));
    });

    test('padding counts one, fill none, and no @ adds only literals', () {
      expect(added('_(@_)*-', 3), 2);
      expect(added('0;0;0;"x"', 3), 1);
    });
  });

  group('booleans, errors and empty cells', () {
    test('a boolean ignores the code', () {
      final r = render(true, '0.00');
      expect(r.parts, <XlsxFormatPart>[const XlsxFormatText('TRUE')]);
      expect(r.section, isNull);
      expect(textOf(false, '0.00'), 'FALSE');
    });

    test('errors', () {
      expect(textOf(XlsxErrorValue.na, '0.00'), '#N/A');
      expect(textOf(XlsxErrorValue.div0, '@'), '#DIV/0!');
      expect(textOf(const XlsxErrorValue('#SPILL!'), '0'), '#SPILL!');
    });

    test('null is empty', () {
      final r = render(null, '0.00');
      expect(r.parts, isEmpty);
      expect(r.section, isNull);
      expect(r.overflow, isFalse);
    });

    test('NaN and infinity are #NUM!', () {
      expect(textOf(double.nan, '0.00'), '#NUM!');
      expect(textOf(double.infinity, '0.00'), '#NUM!');
      expect(textOf(double.negativeInfinity, '0.00'), '#NUM!');
    });
  });

  group('numbers', () {
    test('a number section', () {
      final r = render(12.5, '0.00');
      expect(textOf(12.5, '0.00'), '12.50');
      expect(r.section, isNotNull);
      expect(r.overflow, isFalse);
    });

    test('an XlsxDecimal', () {
      expect(textOf(XlsxDecimal('1.5'), '0.00'), '1.50');
    });

    test('@ alone formats a number as General', () {
      expect(textOf(12.5, '@'), '12.5');
      expect(textOf(-12.5, '@'), '-12.5');
    });

    test('0;@ keeps its last section for text', () {
      expect(textOf(-5, '0;@'), '-5');
      expect(textOf(5, '0;@'), '5');
      expect(textOf('a', '0;@'), 'a');
      expect(textOf(0, '0;-0;@'), '0');
      expect(textOf(-5, '0;"neg "0;"t "@'), 'neg 5');
      expect(textOf('a', '0;"neg "0;"t "@'), 't a');
    });

    test('text skips a section holding @ that is not the last', () {
      expect(textOf('a', '"x"@;0'), 'a');
    });

    test('a negative number takes the second section', () {
      expect(textOf(-3, '0;(0)'), '(3)');
    });

    test('no matching section overflows', () {
      final r = render(5, '[<1]0');
      expect(r.overflow, isTrue);
      expect(r.parts, <XlsxFormatPart>[const XlsxFormatText('#')]);
      expect(r.section, isNull);
    });

    test('a date section shows General (until N2)', () {
      expect(textOf(45000, 'yyyy-mm-dd'), '45000');
      expect(textOf(-1.5, 'yyyy-mm-dd'), '-1.5');
    });
  });

  group('other types', () {
    test('DateTime (until N2)', () {
      expect(
        textOf(DateTime.utc(2026, 10, 28), '0'),
        '2026-10-28T00:00:00.000Z',
      );
    });

    test('Duration (until N2)', () {
      expect(textOf(const Duration(hours: 1), '0'), '1:00:00.000000');
    });

    test('anything else is a programmer error', () {
      expect(() => render(Object(), '0'), throwsArgumentError);
    });
  });
}
