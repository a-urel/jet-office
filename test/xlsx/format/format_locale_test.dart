import 'package:jet_office/src/xlsx/format/format_code.dart';
import 'package:jet_office/src/xlsx/format/format_kind.dart';
import 'package:jet_office/src/xlsx/format/format_locale.dart';
import 'package:jet_office/src/xlsx/warnings.dart';
import 'package:test/test.dart';

void main() {
  group('XlsxFormatLocale.enUS', () {
    const XlsxFormatLocale l = XlsxFormatLocale.enUS;

    test('separators, markers and words', () {
      expect(l.decimalSeparator, '.');
      expect(l.groupSeparator, ',');
      expect(l.dateSeparator, '/');
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

    test('builtinCodes, the whole map', () {
      expect(l.builtinCodes, <int, String>{
        5: r'$#,##0_);($#,##0)',
        6: r'$#,##0_);[Red]($#,##0)',
        7: r'$#,##0.00_);($#,##0.00)',
        8: r'$#,##0.00_);[Red]($#,##0.00)',
        14: 'm/d/yyyy',
        15: 'd-mmm-yy',
        16: 'd-mmm',
        17: 'mmm-yy',
        18: 'h:mm AM/PM',
        19: 'h:mm:ss AM/PM',
        20: 'h:mm',
        21: 'h:mm:ss',
        22: 'm/d/yyyy h:mm',
        37: '#,##0_);(#,##0)',
        38: '#,##0_);[Red](#,##0)',
        39: '#,##0.00_);(#,##0.00)',
        40: '#,##0.00_);[Red](#,##0.00)',
        41: '_(* #,##0_);_(* (#,##0);_(* "-"_);_(@_)',
        42: r'_($* #,##0_);_($* (#,##0);_($* "-"_);_(@_)',
        43: '_(* #,##0.00_);_(* (#,##0.00);_(* "-"??_);_(@_)',
        44: r'_($* #,##0.00_);_($* (#,##0.00);_($* "-"??_);_(@_)',
      });
    });

    test('long date and time', () {
      expect(l.longDateCode, 'dddd, mmmm d, yyyy');
      expect(l.longTimeCode, 'h:mm:ss AM/PM');
    });
  });

  group('XlsxFormatLocale.deDE', () {
    const XlsxFormatLocale l = XlsxFormatLocale.deDE;

    test('separators, markers and words', () {
      expect(l.decimalSeparator, ',');
      expect(l.groupSeparator, '.');
      expect(l.dateSeparator, '.');
      expect((l.am, l.pm), ('AM', 'PM'));
      expect((l.trueText, l.falseText), ('WAHR', 'FALSCH'));
      expect(l.lcid, 0x407);
      expect(l.messageLocale, XlsxLocale.de);
      expect(l.verified, isFalse);
    });

    test('names', () {
      expect(l.monthNames, hasLength(12));
      expect(l.monthAbbreviations, hasLength(12));
      expect(l.dayNames, hasLength(7));
      expect(l.dayAbbreviations, hasLength(7));
      expect(l.monthNames[2], 'März');
      expect(l.dayNames[3], 'Mittwoch');
    });

    test('error names', () {
      expect(l.errorNames, <String, String>{
        '#NULL!': '#NULL!',
        '#DIV/0!': '#DIV/0!',
        '#VALUE!': '#WERT!',
        '#REF!': '#BEZUG!',
        '#NAME?': '#NAME?',
        '#NUM!': '#ZAHL!',
        '#N/A': '#NV',
      });
    });

    test('builtinCodes, the whole map', () {
      expect(l.builtinCodes, <int, String>{
        5: '#,##0 "€";-#,##0 "€"',
        6: '#,##0 "€";[Red]-#,##0 "€"',
        7: '#,##0.00 "€";-#,##0.00 "€"',
        8: '#,##0.00 "€";[Red]-#,##0.00 "€"',
        14: 'dd.mm.yyyy',
        15: 'dd. mmm yy',
        16: 'dd. mmm',
        17: 'mmm yy',
        18: 'h:mm AM/PM',
        19: 'h:mm:ss AM/PM',
        20: 'hh:mm',
        21: 'hh:mm:ss',
        22: 'dd.mm.yyyy hh:mm',
        37: '#,##0 ;-#,##0 ',
        38: '#,##0 ;[Red]-#,##0 ',
        39: '#,##0.00 ;-#,##0.00 ',
        40: '#,##0.00 ;[Red]-#,##0.00 ',
        41: '_-* #,##0 _€_-;-* #,##0 _€_-;_-* "-" _€_-;_-@_-',
        42: '_-* #,##0 "€"_-;-* #,##0 "€"_-;_-* "-" "€"_-;_-@_-',
        43: '_-* #,##0.00 _€_-;-* #,##0.00 _€_-;_-* "-"?? _€_-;_-@_-',
        44: '_-* #,##0.00 "€"_-;-* #,##0.00 "€"_-;_-* "-"?? "€"_-;_-@_-',
      });
    });

    test('built-in codes', () {
      expect(l.builtinCodes[14], 'dd.mm.yyyy');
      expect(l.builtinCodes[5], '#,##0 "€";-#,##0 "€"');
      expect(l.longDateCode, 'dddd, d. mmmm yyyy');
      expect(l.longTimeCode, 'hh:mm:ss');
    });
  });

  group('XlsxFormatLocale.trTR', () {
    const XlsxFormatLocale l = XlsxFormatLocale.trTR;

    test('separators, markers and words', () {
      expect(l.decimalSeparator, ',');
      expect(l.groupSeparator, '.');
      expect(l.dateSeparator, '.');
      expect((l.am, l.pm), ('ÖÖ', 'ÖS'));
      expect((l.trueText, l.falseText), ('DOĞRU', 'YANLIŞ'));
      expect(l.lcid, 0x41F);
      expect(l.messageLocale, XlsxLocale.tr);
      expect(l.verified, isFalse);
    });

    test('names', () {
      expect(l.monthNames, hasLength(12));
      expect(l.monthAbbreviations, hasLength(12));
      expect(l.dayNames, hasLength(7));
      expect(l.dayAbbreviations, hasLength(7));
      expect(l.monthNames[1], 'Şubat');
      expect(l.dayNames[3], 'Çarşamba');
    });

    test('error names', () {
      expect(l.errorNames, <String, String>{
        '#NULL!': '#BOŞ!',
        '#DIV/0!': '#SAYI/0!',
        '#VALUE!': '#DEĞER!',
        '#REF!': '#BAŞV!',
        '#NAME?': '#AD?',
        '#NUM!': '#SAYI!',
        '#N/A': '#YOK',
        '#SPILL!': '#TAŞMA!',
        '#CALC!': '#HESAPLA!',
      });
    });

    test('builtinCodes, the whole map', () {
      expect(l.builtinCodes, <int, String>{
        5: '"₺"#,##0;-"₺"#,##0',
        6: '"₺"#,##0;[Red]-"₺"#,##0',
        7: '"₺"#,##0.00;-"₺"#,##0.00',
        8: '"₺"#,##0.00;[Red]-"₺"#,##0.00',
        14: 'dd.mm.yyyy',
        15: 'dd.mmm.yy',
        16: 'dd.mmm',
        17: 'mmm.yy',
        18: r'[$-41F]h:mm AM/PM',
        19: r'[$-41F]h:mm:ss AM/PM',
        20: 'hh:mm',
        21: 'hh:mm:ss',
        22: 'dd.mm.yyyy hh:mm',
        37: '#,##0;-#,##0',
        38: '#,##0;[Red]-#,##0',
        39: '#,##0.00;-#,##0.00',
        40: '#,##0.00;[Red]-#,##0.00',
        41: '_-* #,##0_-;-* #,##0_-;_-* "-"_-;_-@_-',
        42: '_-"₺"* #,##0_-;-"₺"* #,##0_-;_-"₺"* "-"_-;_-@_-',
        43: '_-* #,##0.00_-;-* #,##0.00_-;_-* "-"??_-;_-@_-',
        44: '_-"₺"* #,##0.00_-;-"₺"* #,##0.00_-;_-"₺"* "-"??_-;_-@_-',
      });
    });

    test('built-in codes', () {
      expect(l.builtinCodes[15], 'dd.mmm.yy');
      expect(l.builtinCodes[7], '"₺"#,##0.00;-"₺"#,##0.00');
      expect(l.longDateCode, 'd mmmm yyyy dddd');
      expect(l.longTimeCode, 'hh:mm:ss');
    });
  });

  group('every shipped locale', () {
    const List<XlsxFormatLocale> all = <XlsxFormatLocale>[
      XlsxFormatLocale.enUS,
      XlsxFormatLocale.deDE,
      XlsxFormatLocale.trTR,
    ];
    final List<int> ids = <int>[
      5, 6, 7, 8, //
      for (int id = 14; id <= 22; id++) id,
      for (int id = 37; id <= 44; id++) id,
    ];

    for (final XlsxFormatLocale l in all) {
      test('lcid ${l.lcid.toRadixString(16)}: codes parse', () {
        expect(l.builtinCodes.keys.toList()..sort(), ids);
        for (final MapEntry<int, String> e in l.builtinCodes.entries) {
          final ParsedFormat p = parseFormatCode(e.value);
          expect(p.invalidReason, isNull, reason: '${e.key} ${e.value}');
          expect(p.truncated, isFalse, reason: '${e.key} ${e.value}');
        }
        expect(parseFormatCode(l.longDateCode).invalidReason, isNull);
        expect(parseFormatCode(l.longTimeCode).invalidReason, isNull);
        expect(classifyFormatCode(l.longDateCode), FormatKind.date);
        expect(classifyFormatCode(l.longTimeCode), FormatKind.time);
      });
    }

    test('shippedFormatLocale finds a locale by lcid', () {
      expect(shippedFormatLocale(0x407), same(XlsxFormatLocale.deDE));
      expect(shippedFormatLocale(0x41F), same(XlsxFormatLocale.trTR));
      expect(shippedFormatLocale(0x409), same(XlsxFormatLocale.enUS));
      expect(shippedFormatLocale(0x40C), isNull);
    });
  });
}
