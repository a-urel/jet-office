import 'package:jet_office/src/xlsx/format/excel_number.dart';
import 'package:jet_office/src/xlsx/format/format_code.dart';
import 'package:jet_office/src/xlsx/format/section_choice.dart';
import 'package:test/test.dart';

/// Chooses for [value] in [code] and returns (index, showMinus, abs text).
(int, bool, String)? choose(String code, String value) {
  final ParsedFormat format = parseFormatCode(code);
  final ({FormatSection section, bool showMinus, ExcelNumber value})? r =
      chooseNumberSection(format, ExcelNumber.parse(value));
  if (r == null) return null;
  return (format.sections.indexOf(r.section), r.showMinus, r.value.toString());
}

void main() {
  group('chooseNumberSection without conditions', () {
    test('one section takes every number and shows the minus', () {
      expect(choose('0', '-5'), (0, true, '5'));
      expect(choose('0', '5'), (0, false, '5'));
      expect(choose('0', '0'), (0, false, '0'));
    });

    test('two sections: the second takes negatives and writes its sign', () {
      expect(choose('0;(0)', '-5'), (1, false, '5'));
      expect(choose('0;(0)', '5'), (0, false, '5'));
      expect(choose('0;(0)', '0'), (0, false, '0'));
    });

    test('three sections: the third takes zero', () {
      expect(choose('0;-0;"z"', '0'), (2, false, '0'));
      expect(choose('0;-0;"z"', '-1'), (1, false, '1'));
      expect(choose('0;-0;"z"', '1'), (0, false, '1'));
    });

    test(
      'four sections: an empty third takes zero, text never takes numbers',
      () {
        expect(choose('0;-0;;@', '0'), (2, false, '0'));
        expect(choose('0;-0;;@', '3'), (0, false, '3'));
        expect(choose('0;-0;;@', '-3'), (1, false, '3'));
      },
    );

    test('an invalid code does not throw', () {
      expect(choose('0;0;0;0;0', '1'), isNotNull);
    });
  });

  group('chooseNumberSection with conditions', () {
    test('[>100]"big";"small"', () {
      expect(choose('[>100]"big";"small"', '150'), (0, false, '150'));
      expect(choose('[>100]"big";"small"', '50'), (1, false, '50'));
      expect(choose('[>100]"big";"small"', '-5'), (1, true, '5'));
    });

    test('a condition that matches only negatives drops the minus', () {
      expect(choose('[<0]"neg "0;"other "0', '-5'), (0, false, '5'));
      expect(choose('[<0]"neg "0;"other "0', '5'), (1, false, '5'));
      expect(choose('[<=-1]0;[>=1]0;"else "0', '-2'), (0, false, '2'));
      expect(choose('[=-3]0;0', '-3'), (0, false, '3'));
    });

    test('a condition that can match positives keeps the minus', () {
      expect(choose('[<5]0;0', '-2'), (0, true, '2'));
      expect(choose('[<=0]0;0', '-2'), (0, true, '2'));
      expect(choose('[<>3]0;0', '-2'), (0, true, '2'));
    });

    test('no match and no else section gives null', () {
      expect(choose('[>100]0;[<-100]0', '50'), isNull);
      expect(choose('[>100]0', '50'), isNull);
    });

    test('the third section is the else', () {
      expect(choose('[>100]0;[<-100]0;0', '50'), (2, false, '50'));
      expect(choose('[<=-1]0;[>=1]0;"else "0', '0.5'), (2, false, '0.5'));
      expect(choose('[<=-1]0;[>=1]0;"else "0', '-0.5'), (2, true, '0.5'));
    });

    test('the first match wins', () {
      expect(choose('[>1]0;[>2]0;0', '5'), (0, false, '5'));
      expect(choose('[>10]0;[>2]0;0', '5'), (1, false, '5'));
    });
  });

  group('chooseTextSection', () {
    FormatSection? text(String code) {
      final ParsedFormat format = parseFormatCode(code);
      final FormatSection? s = chooseTextSection(format);
      return s == null ? null : format.sections[format.sections.indexOf(s)];
    }

    int? index(String code) {
      final ParsedFormat format = parseFormatCode(code);
      final FormatSection? s = chooseTextSection(format);
      return s == null ? null : format.sections.indexOf(s);
    }

    test('the fourth section', () {
      expect(index('0;0;0;@'), 3);
      expect(index('0;0;0;"x"'), 3);
    });

    test('the section holding @ when there are fewer than four', () {
      expect(index('"Name: "@'), 0);
      expect(index('0;@'), 1);
    });

    test('null when no section holds @', () {
      expect(text('0.00'), isNull);
      expect(text('0;0;0'), isNull);
    });

    test('text never takes a conditional section', () {
      expect(text('[>1]@'), isNull);
    });
  });
}
