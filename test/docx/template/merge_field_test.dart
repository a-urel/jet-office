// Tests the MERGEFIELD instruction parser: names, switches, the translation
// of `\@` and `\#` and casing. Pure Dart, so it runs on the web too.
import 'package:jet_core/jet_core.dart';
import 'package:jet_office/src/docx/template/merge_field.dart';
import 'package:test/test.dart';

void main() {
  group('parseMergeField', () {
    test('names', () {
      expect(parseMergeField(' MERGEFIELD Ad ')!.name, 'Ad');
      final MergeField quoted = parseMergeField(
        ' MERGEFIELD  "Müşteri Adı" \\* MERGEFORMAT ',
      )!;
      expect(quoted.name, 'Müşteri Adı');
      expect(quoted.unsupported, isEmpty);
      expect(quoted.casing, isNull);
    });

    test('not a merge field, or no name', () {
      expect(parseMergeField(' PAGE '), isNull);
      expect(parseMergeField(' MERGEFIELD '), isNull);
      expect(parseMergeField(''), isNull);
    });

    test('date picture translation', () {
      String? date(String s) =>
          parseMergeField(' MERGEFIELD Tarih \\@ "$s" ')!.dateFormat;
      expect(
        parseMergeField(' mergefield Tarih \\@ "dd.MM.yyyy" ')!.dateFormat,
        'dd.mm.yyyy',
      );
      expect(date('d MMMM yyyy HH:mm'), 'd mmmm yyyy hh:mm');
      expect(date('h:mm am/pm'), 'h:mm AM/PM');
      expect(date('hh:mm AM/PM'), 'hh:mm AM/PM');
      expect(date('dddd, d MMM yy'), 'dddd, d mmm yy');
      expect(date("d 'of' MMMM"), 'd "of" mmmm');
      expect(date('y'), 'yy');
      expect(date('yyy'), 'yyyy');
      expect(date('m:ss'), 'm:ss');
      expect(date('d/M-yyyy'), 'd/m-yyyy');
    });

    test('an untranslatable date picture is unsupported', () {
      final MergeField f = parseMergeField(' MERGEFIELD T \\@ "dd w" ')!;
      expect(f.dateFormat, isNull);
      expect(f.unsupported, <String>['\\@ "dd w"']);
    });

    test('number picture translation', () {
      expect(
        parseMergeField(' MERGEFIELD T \\# "#.##0,00" ')!.numberFormat,
        '#.##0,00',
      );
      expect(
        parseMergeField(' MERGEFIELD T \\# "#,##0.00" ')!.numberFormat,
        '#,##0.00',
      );
      expect(
        parseMergeField(' MERGEFIELD T \\# "0.0%" ')!.numberFormat,
        '0.0"%"',
      );
      expect(
        parseMergeField(" MERGEFIELD T \\# \"0 'TL'\" ")!.numberFormat,
        '0 "TL"',
      );
      expect(
        parseMergeField(' MERGEFIELD T \\# "₺#,##0" ')!.numberFormat,
        '"₺"#,##0',
      );
      expect(
        parseMergeField(' MERGEFIELD T \\# "0;(0)" ')!.numberFormat,
        '0;"("0")"',
      );
    });

    test('a percent sign is a literal, not Excel percent', () {
      expect(parseMergeField(' MERGEFIELD T \\# "0%" ')!.numberFormat, '0"%"');
    });

    test('an untranslatable number picture is unsupported', () {
      final MergeField f = parseMergeField(' MERGEFIELD T \\# "x##" ')!;
      expect(f.numberFormat, isNull);
      expect(f.unsupported, <String>['\\# "x##"']);
    });

    test('before and after text', () {
      final MergeField f = parseMergeField(
        ' MERGEFIELD Ad \\b "Sayın " \\f "," ',
      )!;
      expect(f.before, 'Sayın ');
      expect(f.after, ',');
      final MergeField bare = parseMergeField(' MERGEFIELD Ad \\B x \\F y ')!;
      expect(bare.before, 'x');
      expect(bare.after, 'y');
    });

    test('casing and other general switches', () {
      expect(parseMergeField(' MERGEFIELD A \\* Upper ')!.casing, 'Upper');
      expect(parseMergeField(' MERGEFIELD A \\* lower ')!.casing, 'Lower');
      expect(
        parseMergeField(' MERGEFIELD A \\* FirstCap ')!.casing,
        'FirstCap',
      );
      expect(parseMergeField(' MERGEFIELD A \\* CAPS ')!.casing, 'Caps');
      final MergeField dropped = parseMergeField(
        ' MERGEFIELD A \\* CHARFORMAT \\* MERGEFORMAT ',
      )!;
      expect(dropped.unsupported, isEmpty);
      expect(dropped.casing, isNull);
      expect(parseMergeField(' MERGEFIELD A \\* Roman ')!.unsupported, <String>[
        '\\* Roman',
      ]);
    });

    test('switches without arguments are unsupported', () {
      expect(parseMergeField(' MERGEFIELD A \\v \\m ')!.unsupported, <String>[
        '\\v',
        '\\m',
      ]);
    });

    test('a quoted name keeps backslashes and switch look-alikes', () {
      expect(parseMergeField(' MERGEFIELD "a \\b c" ')!.name, 'a \\b c');
    });
  });

  group('applyCasing', () {
    test('Turkish letters', () {
      expect(
        applyCasing('istanbul ılık', 'Upper', FormatLocale.trTR),
        'İSTANBUL ILIK',
      );
      expect(
        applyCasing('İSTANBUL IŞIK', 'Lower', FormatLocale.trTR),
        'istanbul ışık',
      );
      expect(
        applyCasing('istanbul', 'FirstCap', FormatLocale.trTR),
        'İstanbul',
      );
      expect(applyCasing('ışık ili', 'Caps', FormatLocale.trTR), 'Işık İli');
    });

    test('other locales', () {
      expect(applyCasing('ali veli', 'Caps', FormatLocale.enUS), 'Ali Veli');
      expect(
        applyCasing('ali veli', 'FirstCap', FormatLocale.enUS),
        'Ali veli',
      );
      expect(applyCasing('istanbul', 'Upper', FormatLocale.enUS), 'ISTANBUL');
      expect(applyCasing('ISTANBUL', 'Lower', FormatLocale.deDE), 'istanbul');
      expect(applyCasing('', 'Caps', FormatLocale.enUS), '');
    });
  });
}
