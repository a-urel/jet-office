import 'package:jet_core/src/format/format_code.dart';
import 'package:jet_core/src/format/format_locale.dart';
import 'package:jet_core/src/format/format_value.dart';
import 'package:jet_core/src/format/formatted_value.dart';
import 'package:jet_core/src/format/value_renderer.dart';
import 'package:test/test.dart';

RenderedValue render(
  Object? value,
  String code, {
  FormatLocale locale = FormatLocale.enUS,
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
  FormatLocale locale = FormatLocale.enUS,
  bool date1904 = false,
}) => render(
  value,
  code,
  locale: locale,
  date1904: date1904,
).parts.map((FormatPart p) => p is FormatText ? p.text : '').join();

void main() {
  group('text', () {
    test('without a text section is unchanged', () {
      expect(render('abc', '0.00').parts, <FormatPart>[
        const FormatText('abc'),
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
      expect(render('abc', '0;0;0;_(@_)').parts, <FormatPart>[
        const FormatPadding('('),
        const FormatText('abc'),
        const FormatPadding(')'),
      ]);
    });

    test('fill is kept', () {
      expect(render('abc', '@*-').parts, <FormatPart>[
        const FormatText('abc'),
        const FormatFill('-'),
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
      expect(r.parts, <FormatPart>[const FormatText('TRUE')]);
      expect(r.section, isNull);
      expect(textOf(false, '0.00'), 'FALSE');
    });

    test('errors', () {
      expect(textOf(const FormatErrorValue('#N/A'), '0.00'), '#N/A');
      expect(textOf(const FormatErrorValue('#DIV/0!'), '@'), '#DIV/0!');
      expect(textOf(const FormatErrorValue('#SPILL!'), '0'), '#SPILL!');
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

    test('a FormatDecimal', () {
      expect(textOf(FormatDecimal('1.5'), '0.00'), '1.50');
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

    test('a lone conditional section falls back to General', () {
      // Excel repairs `[<1]0` to `[<1]0;General`.
      final r = render(5, '[<1]0');
      expect(r.overflow, isFalse);
      expect(r.parts, <FormatPart>[const FormatText('5')]);
    });

    test('no matching section overflows without a color or warning', () {
      final RenderedValue r = render(50, '[>100]0;[<-100]0');
      expect(r.overflow, isTrue);
      expect(r.parts, <FormatPart>[const FormatText('#')]);
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
      expect(r.parts, <FormatPart>[const FormatText('#')]);
    });

    test('a negative section without date tokens takes the number', () {
      expect(textOf(-1, 'yyyy-mm-dd;"neg"'), 'neg');
    });

    test('an explicit negative date section does not hide the sign', () {
      // Ruling 4, Owner Excel check C10b: the date renderer gets the
      // signed serial, so 1900 shows `#`.
      final RenderedValue r = render(-0.5, '0;h:mm');
      expect(r.overflow, isTrue);
      expect(textOf(-0.5, '0;h:mm'), '#');
    });

    test('1904: an explicit negative date section shows a minus', () {
      expect(textOf(-0.5, '0;h:mm', date1904: true), '-12:00');
    });

    test('a conditional date section', () {
      expect(textOf(2.5, '[<1]h:mm;d "days"'), '2 days');
    });
  });

  group('warnings', () {
    test('an unsupported calendar in a date section', () {
      expect(render(46323, 'B2yyyy').warning, FormatWarning.unsupported);
    });

    test('an unsupported bracket in a number section', () {
      final RenderedValue r = render(5, '[DBNum1]0');
      expect(textOf(5, '[DBNum1]0'), '5');
      expect(r.warning, FormatWarning.unsupported);
    });

    test('an empty bracket shows the number and warns', () {
      final RenderedValue r = render(5, '[]0');
      expect(textOf(5, '[]0'), '5');
      expect(r.overflow, isFalse);
      expect(r.warning, FormatWarning.unsupported);
    });

    test('a plain date code warns nothing', () {
      expect(render(46323, 'yyyy').warning, isNull);
    });

    test('an overflowing date section keeps its section and warning', () {
      final RenderedValue r = render(-1, '[Red]B2yyyy');
      expect(r.overflow, isTrue);
      expect(r.section, isNotNull);
      expect(r.section!.color, isNotNull);
      expect(r.warning, FormatWarning.unsupported);
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

    test('a boolean shows the region\'s word in any code (c16)', () {
      const String text = '"yes";"no";"zero";@';
      for (final (FormatLocale locale, String yes, String no)
          in <(FormatLocale, String, String)>[
            (FormatLocale.enUS, 'TRUE', 'FALSE'),
            (FormatLocale.deDE, 'WAHR', 'FALSCH'),
            (FormatLocale.trTR, 'DOĞRU', 'YANLIŞ'),
          ]) {
        for (final String code in <String>['0.00', 'General', text]) {
          expect(textOf(true, code, locale: locale), yes, reason: code);
          expect(textOf(false, code, locale: locale), no, reason: code);
        }
      }
    }); // Owner Excel check C16

    test('errors in de-DE and tr-TR', () {
      expect(
        textOf(
          const FormatErrorValue('#VALUE!'),
          'yyyy',
          locale: FormatLocale.deDE,
        ),
        '#WERT!',
      );
      expect(
        textOf(
          const FormatErrorValue('#DIV/0!'),
          'yyyy',
          locale: FormatLocale.trTR,
        ),
        '#SAYI/0!',
      );
    });

    test('#SPILL! and #CALC! have Turkish names in tr-TR (c17)', () {
      expect(
        textOf(
          const FormatErrorValue('#SPILL!'),
          'yyyy',
          locale: FormatLocale.trTR,
        ),
        '#TAŞMA!',
      );
      expect(
        textOf(
          const FormatErrorValue('#CALC!'),
          'yyyy',
          locale: FormatLocale.trTR,
        ),
        '#HESAPLA!',
      );
    });

    test('#SPILL! is #ÜBERLAUF! in de-DE, #CALC! stays as written (c17)', () {
      expect(
        textOf(
          const FormatErrorValue('#SPILL!'),
          'yyyy',
          locale: FormatLocale.deDE,
        ),
        '#ÜBERLAUF!',
      );
      expect(
        textOf(
          const FormatErrorValue('#CALC!'),
          'yyyy',
          locale: FormatLocale.deDE,
        ),
        '#CALC!',
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
        expect(r.parts, <FormatPart>[const FormatText('#')], reason: '$value');
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

    test('1904: values before the epoch show a minus in a date section', () {
      // Owner Excel check C10: c10-03.
      for (final Object value in <Object>[
        FormatDecimal('-1'),
        DateTime(1903, 12, 31),
      ]) {
        final RenderedValue r = render(value, 'yyyy-mm-dd', date1904: true);
        expect(r.overflow, isFalse, reason: '$value');
        expect(r.parts, <FormatPart>[
          const FormatText('-1904-01-02'),
        ], reason: '$value');
      }
    });

    test('a negative Duration of 100,000 days or more overflows', () {
      final RenderedValue r = render(
        const Duration(days: -100001, hours: 3),
        '[h]:mm',
      );
      expect(r.overflow, isTrue);
      expect(r.parts, <FormatPart>[const FormatText('#')]);
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
    });

    test('anything else is a programmer error', () {
      expect(() => render(Object(), '0'), throwsArgumentError);
    });
  });
}
