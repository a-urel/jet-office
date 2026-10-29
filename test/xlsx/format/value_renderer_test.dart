import 'package:jet_office/src/xlsx/format/format_code.dart';
import 'package:jet_office/src/xlsx/format/format_locale.dart';
import 'package:jet_office/src/xlsx/format/formatted_value.dart';
import 'package:jet_office/src/xlsx/format/value_renderer.dart';
import 'package:jet_office/src/xlsx/read/read_cell.dart';
import 'package:jet_office/src/xlsx/values.dart';
import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:test/test.dart';

RenderedValue render(
  Object? value,
  String code, {
  XlsxFormatLocale locale = XlsxFormatLocale.enUS,
  bool date1904 = false,
}) => renderValue(
  value,
  parseFormatCode(code),
  locale: locale,
  generalWidth: 11,
  date1904: date1904,
);

String textOf(
  Object? value,
  String code, {
  XlsxFormatLocale locale = XlsxFormatLocale.enUS,
  bool date1904 = false,
}) => render(
  value,
  code,
  locale: locale,
  date1904: date1904,
).parts.map((XlsxFormatPart p) => p is XlsxFormatText ? p.text : '').join();

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

    test('no matching section overflows without a color or warning', () {
      final RenderedValue r = render(50, '[>100]0;[<-100]0');
      expect(r.overflow, isTrue);
      expect(r.parts, <XlsxFormatPart>[const XlsxFormatText('#')]);
      expect(r.section, isNull);
      expect(r.warning, isNull);
    });
  });

  group('dates', () {
    test('a date section renders the serial', () {
      expect(textOf(46323, 'yyyy-mm-dd'), '2026-10-28');
    });

    test('a negative serial in a date section overflows', () {
      final RenderedValue r = render(-1.5, 'yyyy-mm-dd');
      expect(r.overflow, isTrue);
      expect(r.parts, <XlsxFormatPart>[const XlsxFormatText('#')]);
    });

    test('a negative section without date tokens takes the number', () {
      expect(textOf(-1, 'yyyy-mm-dd;"neg"'), 'neg');
    });

    test('an explicit negative date section does not hide the sign', () {
      // Ruling 4: the date renderer gets the signed serial.
      final RenderedValue r = render(-0.5, '0;h:mm');
      expect(r.overflow, isTrue);
      expect(textOf(-0.5, '0;h:mm'), '#');
    }, skip: 'Owner Excel check C10b');

    test('a conditional date section', () {
      expect(textOf(2.5, '[<1]h:mm;d "days"'), '2 days');
    });
  });

  group('warnings', () {
    test('an unsupported calendar in a date section', () {
      expect(
        render(46323, 'B2yyyy').warning,
        XlsxWarningCode.numberFormatUnsupported,
      );
    });

    test('an unsupported bracket in a number section', () {
      final RenderedValue r = render(5, '[DBNum1]0');
      expect(textOf(5, '[DBNum1]0'), '5');
      expect(r.warning, XlsxWarningCode.numberFormatUnsupported);
    });

    test('an empty bracket shows the number and warns', () {
      final RenderedValue r = render(5, '[]0');
      expect(textOf(5, '[]0'), '5');
      expect(r.overflow, isFalse);
      expect(r.warning, XlsxWarningCode.numberFormatUnsupported);
    });

    test('a plain date code warns nothing', () {
      expect(render(46323, 'yyyy').warning, isNull);
    });

    test('an overflowing date section keeps its section and warning', () {
      final RenderedValue r = render(-1, '[Red]B2yyyy');
      expect(r.overflow, isTrue);
      expect(r.section, isNotNull);
      expect(r.section!.color, isNotNull);
      expect(r.warning, XlsxWarningCode.numberFormatUnsupported);
    });

    test('a text section never warns', () {
      expect(textOf('abc', '[DBNum1]@'), 'abc');
      expect(render('abc', '[DBNum1]@').warning, isNull);
    });
  });

  group('non-numbers with a date code', () {
    test('text is unchanged', () {
      expect(textOf('abc', 'yyyy-mm-dd'), 'abc');
    });

    test('a boolean in de-DE', () {
      expect(textOf(true, '0.00', locale: XlsxFormatLocale.deDE), 'WAHR');
    }, skip: 'Owner Excel check C16');

    test('errors in de-DE and tr-TR', () {
      expect(
        textOf(XlsxErrorValue.value, 'yyyy', locale: XlsxFormatLocale.deDE),
        '#WERT!',
      );
      expect(
        textOf(XlsxErrorValue.div0, 'yyyy', locale: XlsxFormatLocale.trTR),
        '#SAYI/0!',
      );
    });

    test('#SPILL! and #CALC! have Turkish names in tr-TR (c17)', () {
      expect(
        textOf(
          const XlsxErrorValue('#SPILL!'),
          'yyyy',
          locale: XlsxFormatLocale.trTR,
        ),
        '#TAŞMA!',
      );
      expect(
        textOf(
          const XlsxErrorValue('#CALC!'),
          'yyyy',
          locale: XlsxFormatLocale.trTR,
        ),
        '#HESAPLA!',
      );
    });
  });

  group('other types', () {
    test('a DateTime is its serial', () {
      final DateTime value = DateTime.utc(2026, 10, 28, 13, 30);
      expect(textOf(value, 'dd.mm.yyyy hh:mm'), '28.10.2026 13:30');
      expect(textOf(value, '0.00'), '46323.56');
      expect(textOf(value, 'General'), '46323.5625');
    });

    test('a DateTime before the first serial', () {
      expect(textOf(DateTime.utc(1899, 12, 30), 'yyyy'), '#');
      expect(textOf(DateTime.utc(1899, 12, 30), '0'), '-1');
    });

    test('a DateTime past the last serial', () {
      expect(render(DateTime.utc(275000), 'yyyy').overflow, isTrue);
      expect(textOf(DateTime.utc(275000), 'yyyy'), '#');
    });

    test('DateTime extremes before the first serial overflow', () {
      for (final DateTime value in <DateTime>[
        DateTime.utc(-271820, 1, 1),
        DateTime(1, 1, 1),
        DateTime(1899, 12, 30),
      ]) {
        final RenderedValue r = render(value, 'yyyy-mm-dd');
        expect(r.overflow, isTrue, reason: '$value');
        expect(r.parts, <XlsxFormatPart>[
          const XlsxFormatText('#'),
        ], reason: '$value');
        expect(r.warning, isNull, reason: '$value');
      }
    });

    test('the last millisecond of 9999 keeps its milliseconds', () {
      final RenderedValue r = render(
        DateTime(9999, 12, 31, 23, 59, 59, 999),
        'yyyy-mm-dd hh:mm:ss.000',
      );
      expect(r.overflow, isFalse);
      expect(
        textOf(
          DateTime(9999, 12, 31, 23, 59, 59, 999),
          'yyyy-mm-dd hh:mm:ss.000',
        ),
        '9999-12-31 23:59:59.999',
      );
    });

    test('1904: values before the epoch overflow in a date section', () {
      for (final Object value in <Object>[
        XlsxDecimal('-1'),
        DateTime(1903, 12, 31),
      ]) {
        final RenderedValue r = render(value, 'yyyy-mm-dd', date1904: true);
        expect(r.overflow, isTrue, reason: '$value');
        expect(r.parts, <XlsxFormatPart>[
          const XlsxFormatText('#'),
        ], reason: '$value');
      }
    });

    test('a negative Duration of 100,000 days or more overflows', () {
      final RenderedValue r = render(
        const Duration(days: -100001, hours: 3),
        '[h]:mm',
      );
      expect(r.overflow, isTrue);
      expect(r.parts, <XlsxFormatPart>[const XlsxFormatText('#')]);
    });

    test('a Duration is its serial', () {
      expect(textOf(const Duration(hours: 36), '[h]:mm'), '36:00');
      expect(textOf(const Duration(hours: 36), '0.0'), '1.5');
    });

    test('a negative Duration overflows in the 1900 system', () {
      expect(textOf(const Duration(hours: -1), '[h]:mm'), '#');
    });

    test('a negative Duration shows a minus in the 1904 system', () {
      expect(
        textOf(const Duration(hours: -1), '[h]:mm', date1904: true),
        '-1:00',
      );
    }, skip: 'Owner Excel check C10');

    test('anything else is a programmer error', () {
      expect(() => render(Object(), '0'), throwsArgumentError);
    });
  });
}
