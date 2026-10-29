import 'package:jet_office/src/xlsx/format/format_locale.dart';
import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:test/test.dart';

void main() {
  group('XlsxFormatLocale.enUS', () {
    const XlsxFormatLocale l = XlsxFormatLocale.enUS;

    test('separators, markers and words', () {
      expect(l.decimalSeparator, '.');
      expect(l.groupSeparator, ',');
      expect((l.am, l.pm), ('AM', 'PM'));
      expect((l.trueText, l.falseText), ('TRUE', 'FALSE'));
      expect(l.lcid, 0x409);
      expect(l.messageLocale, XlsxLocale.en);
      expect(l.verified, isFalse);
    });

    test('names: 12 months, 7 days from Sunday', () {
      expect(l.monthNames, hasLength(12));
      expect(l.monthNames.first, 'January');
      expect(l.monthAbbreviations, hasLength(12));
      expect(l.monthAbbreviations.last, 'Dec');
      expect(l.dayNames, hasLength(7));
      expect(l.dayNames.first, 'Sunday');
      expect(l.dayAbbreviations, hasLength(7));
      expect(l.dayAbbreviations.last, 'Sat');
    });

    test('the seven classic error names are shown as written', () {
      const List<String> codes = <String>[
        '#NULL!',
        '#DIV/0!',
        '#VALUE!',
        '#REF!',
        '#NAME?',
        '#NUM!',
        '#N/A',
      ];
      expect(l.errorNames.keys, unorderedEquals(codes));
      for (final String code in codes) {
        expect(l.errorNames[code], code);
      }
    });

    test('built-in codes for 5-8, 14-22 and 37-44', () {
      expect(l.builtinCodes.keys.toList()..sort(), <int>[
        5, 6, 7, 8, //
        for (int id = 14; id <= 22; id++) id,
        for (int id = 37; id <= 44; id++) id,
      ]);
      expect(l.builtinCodes[14], 'm/d/yyyy');
      expect(l.builtinCodes[22], 'm/d/yyyy h:mm');
      expect(l.builtinCodes[5], r'$#,##0_);($#,##0)');
    });

    test('long date and time', () {
      expect(l.longDateCode, 'dddd, mmmm d, yyyy');
      expect(l.longTimeCode, 'h:mm:ss AM/PM');
    });
  });
}
