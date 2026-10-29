import 'package:jet_office/src/xlsx/format/excel_number.dart';
import 'package:jet_office/src/xlsx/format/format_code.dart';
import 'package:test/test.dart';

/// The tokens of the only section of [code].
List<FormatToken> tokensOf(String code) {
  final ParsedFormat parsed = parseFormatCode(code);
  expect(parsed.sections, hasLength(1), reason: code);
  return parsed.sections.single.tokens;
}

void main() {
  group('sections', () {
    test('0;-0;;@ has four sections, the third empty', () {
      final ParsedFormat parsed = parseFormatCode('0;-0;;@');
      expect(parsed.sections, hasLength(4));
      expect(parsed.sections[0].tokens, <FormatToken>[const DigitToken('0')]);
      expect(parsed.sections[1].tokens, <FormatToken>[
        const LiteralToken('-'),
        const DigitToken('0'),
      ]);
      expect(parsed.sections[2].tokens, isEmpty);
      expect(parsed.sections[3].tokens, <FormatToken>[const TextToken()]);
      expect(parsed.invalidReason, isNull);
      expect(parsed.truncated, isFalse);
    });

    test('0 has one section', () {
      expect(parseFormatCode('0').sections, hasLength(1));
    });

    test('an empty code has one empty section', () {
      final ParsedFormat parsed = parseFormatCode('');
      expect(parsed.sections, hasLength(1));
      expect(parsed.sections.single.tokens, isEmpty);
      expect(parsed.invalidReason, isNull);
    });

    test('; has two empty sections', () {
      final ParsedFormat parsed = parseFormatCode(';');
      expect(parsed.sections, hasLength(2));
      expect(parsed.sections[0].tokens, isEmpty);
      expect(parsed.sections[1].tokens, isEmpty);
    });

    test('five sections are invalid, and all five are kept', () {
      final ParsedFormat parsed = parseFormatCode('0;0;0;0;0');
      expect(parsed.invalidReason, isNotNull);
      expect(parsed.sections, hasLength(5));
      expect(parsed.truncated, isFalse);
    });

    test('a ; inside literals does not split', () {
      final ParsedFormat parsed = parseFormatCode(r'"a;b"\;_;*;[;]0');
      expect(parsed.sections, hasLength(1));
    });
  });

  group('literals', () {
    test('a quoted literal', () {
      expect(tokensOf('"kg"0'), <FormatToken>[
        const LiteralToken('kg'),
        const DigitToken('0'),
      ]);
    });

    test('an escaped character', () {
      expect(tokensOf(r'\X0'), <FormatToken>[
        const LiteralToken('X'),
        const DigitToken('0'),
      ]);
    });

    test('the characters Excel shows unquoted are each a literal', () {
      const String chars = r"$-+/():!^&'~{}<>= ";
      expect(tokensOf(chars), <FormatToken>[
        for (var i = 0; i < chars.length; i++) LiteralToken(chars[i]),
      ]);
    });

    test('any other character is a literal', () {
      expect(tokensOf('€0'), <FormatToken>[
        const LiteralToken('€'),
        const DigitToken('0'),
      ]);
      expect(tokensOf('x1'), <FormatToken>[
        const LiteralToken('x'),
        const LiteralToken('1'),
      ]);
    });

    test('a character outside the BMP is one literal', () {
      expect(tokensOf('😀0'), <FormatToken>[
        const LiteralToken('😀'),
        const DigitToken('0'),
      ]);
      expect(tokensOf(r'\😀'), <FormatToken>[const LiteralToken('😀')]);
    });

    test('an empty quoted literal adds nothing', () {
      expect(tokensOf('""0'), <FormatToken>[const DigitToken('0')]);
    });

    test(r'a lone \, _ or * at the end adds nothing', () {
      expect(tokensOf(r'0\'), <FormatToken>[const DigitToken('0')]);
      expect(tokensOf('0_'), <FormatToken>[const DigitToken('0')]);
      expect(tokensOf('0*'), <FormatToken>[const DigitToken('0')]);
    });
  });

  group('brackets', () {
    test('a color and a condition', () {
      final ParsedFormat parsed = parseFormatCode('[Red][>100]0');
      final FormatSection section = parsed.sections.single;
      expect(section.color, const FormatColor(rgb: 0xFF0000));
      expect(section.condition, FormatCondition('>', ExcelNumber.parse('100')));
      expect(section.tokens, <FormatToken>[const DigitToken('0')]);
      expect(parsed.invalidReason, isNull);
    });

    test('every operator', () {
      const Map<String, String> ops = <String, String>{
        '[=1]0': '=',
        '[<1]0': '<',
        '[>1]0': '>',
        '[<=1]0': '<=',
        '[>=1]0': '>=',
        '[<>1]0': '<>',
      };
      ops.forEach((String code, String op) {
        expect(
          parseFormatCode(code).sections.single.condition,
          FormatCondition(op, ExcelNumber.parse('1')),
          reason: code,
        );
      });
    });

    test('a negative decimal condition', () {
      final ParsedFormat parsed = parseFormatCode('[<=-1.5]0');
      expect(
        parsed.sections.single.condition,
        FormatCondition('<=', ExcelNumber.parse('-1.5')),
      );
      expect(parsed.invalidReason, isNull);
    });

    test('a condition value is trimmed and read as a number', () {
      expect(
        parseFormatCode('[>= 1E3 ]0').sections.single.condition,
        FormatCondition('>=', ExcelNumber.parse('1000')),
      );
    });

    test('every number the condition accepts is read as one', () {
      const Map<String, String> values = <String, String>{
        '[>.5]0': '0.5',
        '[>5.]0': '5',
        '[>+1e+2]0': '100',
        '[<-0]0': '0',
        '[>1.5e-3]0': '0.0015',
      };
      values.forEach((String code, String value) {
        final ParsedFormat parsed = parseFormatCode(code);
        expect(parsed.invalidReason, isNull, reason: code);
        expect(
          parsed.sections.single.condition!.value,
          ExcelNumber.parse(value),
          reason: code,
        );
      });
      expect(
        parseFormatCode(
          '[>1e99999999999999999999]0',
        ).sections.single.condition!.value.toDouble(),
        double.infinity,
      );
    });

    test('a condition without a number is invalid', () {
      for (final String code in <String>['[>]0', '[>abc]0', '[<>1.2.3]0']) {
        expect(parseFormatCode(code).invalidReason, isNotNull, reason: code);
      }
    });

    test('a third condition is invalid, and every section is kept', () {
      final ParsedFormat parsed = parseFormatCode('[>1]0;[>2]0;[>3]0');
      expect(parsed.invalidReason, isNotNull);
      expect(parsed.sections, hasLength(3));
      expect(
        parsed.sections[2].condition,
        FormatCondition('>', ExcelNumber.parse('3')),
      );
    });

    test('two conditions are valid', () {
      expect(parseFormatCode('[>1]0;[<-1]0;0').invalidReason, isNull);
    });

    test('every color name, in any case', () {
      const Map<String, int> names = <String, int>{
        'Black': 0x000000,
        'Blue': 0x0000FF,
        'Cyan': 0x00FFFF,
        'Green': 0x00FF00,
        'Magenta': 0xFF00FF,
        'Red': 0xFF0000,
        'White': 0xFFFFFF,
        'Yellow': 0xFFFF00,
      };
      names.forEach((String name, int rgb) {
        for (final String written in <String>[
          name,
          name.toUpperCase(),
          name.toLowerCase(),
        ]) {
          expect(
            parseFormatCode('[$written]0').sections.single.color,
            FormatColor(rgb: rgb),
            reason: written,
          );
        }
      });
    });

    test('[ColorN] indexes the palette', () {
      expect(
        parseFormatCode('[COLOR12]0').sections.single.color,
        const FormatColor(index: 19),
      );
      expect(
        parseFormatCode('[Color1]0').sections.single.color,
        const FormatColor(index: 8),
      );
      expect(
        parseFormatCode('[color56]0').sections.single.color,
        const FormatColor(index: 63),
      );
    });

    test('[ColorN] outside 1..56 is invalid', () {
      for (final String code in <String>[
        '[Color57]0',
        '[Color0]0',
        '[Color]0',
      ]) {
        expect(parseFormatCode(code).invalidReason, isNotNull, reason: code);
      }
    });

    test('a locale tag with a currency and an LCID', () {
      expect(
        tokensOf(r'[$€-407]#,##0').first,
        const LocaleTagToken('€', 0x407),
      );
    });

    test('a locale tag with only an LCID', () {
      expect(tokensOf(r'[$-41F]0').first, const LocaleTagToken('', 0x41F));
    });

    test('a locale tag with only a currency', () {
      expect(tokensOf(r'[$€]0').first, const LocaleTagToken('€', null));
    });

    test('a locale tag whose LCID is not hexadecimal keeps no LCID', () {
      final ParsedFormat parsed = parseFormatCode(r'[$-x-sysdate]dddd');
      expect(
        parsed.sections.single.tokens.first,
        const LocaleTagToken('', null),
      );
      expect(parsed.invalidReason, isNull);
    });

    test('an elapsed time', () {
      expect(tokensOf('[h]:mm'), <FormatToken>[
        const DateToken('h', 1, elapsed: true),
        const LiteralToken(':'),
        const DateToken('m', 2),
      ]);
      expect(tokensOf('[MM]').single, const DateToken('m', 2, elapsed: true));
      expect(tokensOf('[sss]').single, const DateToken('s', 3, elapsed: true));
    });

    test('any other bracket is an empty literal placeholder', () {
      expect(tokensOf('[DBNum1]0'), <FormatToken>[
        const LiteralToken(''),
        const DigitToken('0'),
      ]);
      expect(tokensOf('[B2]').single, const LiteralToken(''));
      expect(tokensOf('[h:mm]').single, const LiteralToken(''));
      expect(tokensOf('[]').single, const LiteralToken(''));
    });
  });

  group('number tokens', () {
    test('#,##0.00', () {
      expect(tokensOf('#,##0.00'), <FormatToken>[
        const DigitToken('#'),
        const CommaToken(),
        const DigitToken('#'),
        const DigitToken('#'),
        const DigitToken('0'),
        const DecimalPointToken(),
        const DigitToken('0'),
        const DigitToken('0'),
      ]);
    });

    test('only the first . is the decimal point', () {
      expect(tokensOf('0.0.0'), <FormatToken>[
        const DigitToken('0'),
        const DecimalPointToken(),
        const DigitToken('0'),
        const LiteralToken('.'),
        const DigitToken('0'),
      ]);
    });

    test('each section has its own decimal point', () {
      final ParsedFormat parsed = parseFormatCode('0.0;0.0');
      for (final FormatSection section in parsed.sections) {
        expect(section.tokens[1], const DecimalPointToken());
      }
    });

    test('%', () {
      expect(tokensOf('0%'), <FormatToken>[
        const DigitToken('0'),
        const PercentToken(),
      ]);
    });

    test('scientific notation', () {
      expect(tokensOf('0.00E+00'), <FormatToken>[
        const DigitToken('0'),
        const DecimalPointToken(),
        const DigitToken('0'),
        const DigitToken('0'),
        const ExponentToken(plus: true, letter: 'E'),
        const DigitToken('0'),
        const DigitToken('0'),
      ]);
      expect(
        tokensOf('0e-0')[1],
        const ExponentToken(plus: false, letter: 'e'),
      );
    });

    test('a / between placeholders is a fraction slash', () {
      expect(tokensOf('# ?/?'), <FormatToken>[
        const DigitToken('#'),
        const LiteralToken(' '),
        const DigitToken('?'),
        const FractionSlashToken(),
        const DigitToken('?'),
      ]);
    });

    test('a / before a fixed denominator is a fraction slash', () {
      expect(tokensOf('?/8'), <FormatToken>[
        const DigitToken('?'),
        const FractionSlashToken(),
        const FixedDenominatorToken(8),
      ]);
    });

    test('the digits after a fraction slash are one fixed denominator', () {
      expect(tokensOf('# ?/16'), <FormatToken>[
        const DigitToken('#'),
        const LiteralToken(' '),
        const DigitToken('?'),
        const FractionSlashToken(),
        const FixedDenominatorToken(16),
      ]);
      expect(tokensOf('0/100'), <FormatToken>[
        const DigitToken('0'),
        const FractionSlashToken(),
        const FixedDenominatorToken(100),
      ]);
    });

    test('a quoted digit ends a fixed denominator', () {
      expect(tokensOf('?/1"5"'), <FormatToken>[
        const DigitToken('?'),
        const FractionSlashToken(),
        const FixedDenominatorToken(1),
        const LiteralToken('5'),
      ]);
      expect(tokensOf(r'?/1\5'), <FormatToken>[
        const DigitToken('?'),
        const FractionSlashToken(),
        const FixedDenominatorToken(1),
        const LiteralToken('5'),
      ]);
    });

    test('a 0 after the slash is a placeholder, not a denominator', () {
      expect(tokensOf('?/05'), <FormatToken>[
        const DigitToken('?'),
        const FractionSlashToken(),
        const DigitToken('0'),
        const LiteralToken('5'),
      ]);
    });

    test('a fixed denominator has at most nine digits', () {
      expect(
        tokensOf('?/999999999').last,
        const FixedDenominatorToken(999999999),
      );
      expect(tokensOf('?/1234567890'), <FormatToken>[
        const DigitToken('?'),
        const FractionSlashToken(),
        for (final String digit in '1234567890'.split('')) LiteralToken(digit),
      ]);
    });

    test('a / not between placeholders is a literal', () {
      expect(tokensOf('0/'), <FormatToken>[
        const DigitToken('0'),
        const LiteralToken('/'),
      ]);
      expect(tokensOf('/0'), <FormatToken>[
        const LiteralToken('/'),
        const DigitToken('0'),
      ]);
    });

    test('padding', () {
      expect(tokensOf('_)'), <FormatToken>[const PaddingToken(')')]);
    });

    test('only the last fill is kept, where it stands', () {
      expect(tokensOf('* 0*-'), <FormatToken>[
        const DigitToken('0'),
        const FillToken('-'),
      ]);
    });
  });

  group('words', () {
    test('General in any case', () {
      expect(tokensOf('General'), <FormatToken>[const GeneralToken()]);
      expect(tokensOf('GENERAL" kg"'), <FormatToken>[
        const GeneralToken(),
        const LiteralToken(' kg'),
      ]);
    });

    test('AM/PM and A/P as written', () {
      expect(tokensOf('AM/PM'), <FormatToken>[const AmPmToken('AM/PM')]);
      expect(tokensOf('a/p'), <FormatToken>[const AmPmToken('a/p')]);
      expect(tokensOf('am/PM'), <FormatToken>[const AmPmToken('am/PM')]);
    });

    test('@', () {
      expect(tokensOf('@'), <FormatToken>[const TextToken()]);
    });
  });

  group('dates', () {
    test('dd.mm.yyyy', () {
      expect(tokensOf('dd.mm.yyyy'), <FormatToken>[
        const DateToken('d', 2),
        const LiteralToken('.'),
        const DateToken('m', 2),
        const LiteralToken('.'),
        const DateToken('y', 4),
      ]);
    });

    test('letters are folded to lowercase', () {
      expect(tokensOf('DD'), <FormatToken>[const DateToken('d', 2)]);
      expect(tokensOf('Hh'), <FormatToken>[const DateToken('h', 2)]);
    });

    test('a . in a date section is a literal, even before the date', () {
      expect(tokensOf('ss.00'), <FormatToken>[
        const DateToken('s', 2),
        const LiteralToken('.'),
        const DigitToken('0'),
        const DigitToken('0'),
      ]);
      expect(tokensOf('0.d'), <FormatToken>[
        const DigitToken('0'),
        const LiteralToken('.'),
        const DateToken('d', 1),
      ]);
    });

    test('era and Buddhist letters', () {
      expect(tokensOf('ee'), <FormatToken>[const DateToken('e', 2)]);
      expect(tokensOf('E'), <FormatToken>[const DateToken('e', 1)]);
      expect(tokensOf('ggg'), <FormatToken>[const DateToken('g', 3)]);
      expect(tokensOf('bbbb'), <FormatToken>[const DateToken('b', 4)]);
    });

    test('a run of g stops before the word General', () {
      expect(tokensOf('gGeneral'), <FormatToken>[
        const DateToken('g', 1),
        const GeneralToken(),
      ]);
    });

    test('the section getters', () {
      final List<FormatSection> sections = parseFormatCode(
        'h AM/PM;[m];0;@;General',
      ).sections;
      expect(sections[0].hasDateTime, isTrue);
      expect(sections[1].hasDateTime, isTrue);
      expect(sections[2].hasDateTime, isFalse);
      expect(sections[2].hasDigits, isTrue);
      expect(sections[0].hasDigits, isFalse);
      expect(sections[3].hasText, isTrue);
      expect(sections[2].hasText, isFalse);
      expect(sections[4].hasGeneral, isTrue);
      expect(sections[3].hasGeneral, isFalse);
      expect(parseFormatCode('AM/PM').sections.single.hasDateTime, isTrue);
    });
  });

  group('truncation', () {
    test('an unterminated quote ends the code', () {
      final ParsedFormat parsed = parseFormatCode('0"abc;0');
      expect(parsed.truncated, isTrue);
      expect(parsed.sections, hasLength(1));
      expect(parsed.sections.single.tokens, <FormatToken>[
        const DigitToken('0'),
      ]);
    });

    test('0"abc keeps the digit', () {
      final ParsedFormat parsed = parseFormatCode('0"abc');
      expect(parsed.truncated, isTrue);
      expect(parsed.sections.single.tokens, <FormatToken>[
        const DigitToken('0'),
      ]);
    });

    test('an unterminated bracket ends the code', () {
      final ParsedFormat parsed = parseFormatCode('[Red');
      expect(parsed.truncated, isTrue);
      expect(parsed.sections.single.tokens, isEmpty);
      expect(parsed.sections.single.color, isNull);
    });

    test('earlier sections are kept', () {
      final ParsedFormat parsed = parseFormatCode('0;[Red');
      expect(parsed.truncated, isTrue);
      expect(parsed.sections, hasLength(2));
    });
  });

  group('limits', () {
    test('a code longer than 255 characters is invalid, and fully scanned', () {
      final ParsedFormat parsed = parseFormatCode('0' * 256);
      expect(parsed.invalidReason, isNotNull);
      expect(parsed.sections.single.tokens, hasLength(256));
    });

    test('a code of 255 characters is valid', () {
      expect(parseFormatCode('0' * 255).invalidReason, isNull);
    });

    test('255 [ parse in linear time', () {
      final Stopwatch watch = Stopwatch()..start();
      final ParsedFormat parsed = parseFormatCode('[' * 255);
      watch.stop();
      expect(parsed.truncated, isTrue);
      expect(watch.elapsedMilliseconds, lessThan(50));
    }, testOn: 'vm');

    test('long hostile codes parse quickly', () {
      final Stopwatch watch = Stopwatch()..start();
      for (final String code in <String>[
        '[' * 100000,
        '[]' * 50000,
        '""' * 50000,
        'general' * 20000,
        ';' * 100000,
      ]) {
        parseFormatCode(code);
      }
      watch.stop();
      expect(watch.elapsedMilliseconds, lessThan(2000));
    }, testOn: 'vm');
  });

  group('values', () {
    test('tokens have value equality and a readable toString', () {
      expect(const DateToken('d', 2), const DateToken('d', 2));
      expect(const DateToken('d', 2), isNot(const DateToken('d', 3)));
      expect(
        const DateToken('h', 1, elapsed: true),
        isNot(const DateToken('h', 1)),
      );
      expect(
        const LiteralToken('a').hashCode,
        const LiteralToken('a').hashCode,
      );
      expect(const LiteralToken('a'), isNot(const DigitToken('a')));
      expect(const DecimalPointToken(), const DecimalPointToken());
      expect(const DecimalPointToken(), isNot(const CommaToken()));
      expect(const LiteralToken('kg').toString(), contains('kg'));
      expect(const DateToken('m', 2).toString(), contains('m'));
    });
  });
}
