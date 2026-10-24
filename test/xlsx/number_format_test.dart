import 'package:jet_office/src/xlsx/number_format.dart';
import 'package:test/test.dart';

void main() {
  test('date format detection', () {
    expect(isDateFormat(XlsxNumFmt.localeShortDate), isTrue);
    expect(isDateFormat(const XlsxNumFmt.builtin(46)), isTrue);
    expect(isDateFormat(XlsxNumFmt.general), isFalse);
    expect(isDateFormat(const XlsxNumFmt.builtin(4)), isFalse);
    expect(isDateFormat(const XlsxNumFmt.custom('dd.mm.yyyy')), isTrue);
    expect(isDateFormat(const XlsxNumFmt.custom('[h]:mm')), isTrue);
    expect(isDateFormat(const XlsxNumFmt.custom('#,##0.00 "₺"')), isFalse);
    expect(isDateFormat(const XlsxNumFmt.custom('"days" 0')), isFalse);
    expect(isDateFormat(const XlsxNumFmt.custom('[Red]0.00')), isFalse);
    expect(isDateFormat(const XlsxNumFmt.custom('General')), isFalse);
    expect(isDateFormat(const XlsxNumFmt.custom(r'0\d')), isFalse);
  });
  test('built-in date id ranges', () {
    for (final int id in <int>[
      14,
      15,
      16,
      17,
      18,
      19,
      20,
      21,
      22,
      45,
      46,
      47,
    ]) {
      expect(isDateFormat(XlsxNumFmt.builtin(id)), isTrue, reason: '$id');
    }
    for (final int id in <int>[0, 13, 23, 44, 48]) {
      expect(isDateFormat(XlsxNumFmt.builtin(id)), isFalse, reason: '$id');
    }
  });
  test('value equality', () {
    expect(const XlsxNumFmt.custom('0.0'), const XlsxNumFmt.custom('0.0'));
    expect(
      const XlsxNumFmt.custom('0.0').hashCode,
      const XlsxNumFmt.custom('0.0').hashCode,
    );
    expect(const XlsxNumFmt.builtin(14), XlsxNumFmt.localeShortDate);
    expect(const XlsxNumFmt.custom('0.0'), isNot(const XlsxNumFmt.builtin(0)));
  });

  group('constants', () {
    test('built-in ids and codes', () {
      expect(XlsxNumFmt.integer, const XlsxNumFmt.builtin(1));
      expect(XlsxNumFmt.decimal2, const XlsxNumFmt.builtin(2));
      expect(XlsxNumFmt.thousands, const XlsxNumFmt.builtin(3));
      expect(XlsxNumFmt.thousands2, const XlsxNumFmt.builtin(4));
      expect(XlsxNumFmt.scientific, const XlsxNumFmt.builtin(11));
      expect(XlsxNumFmt.fraction, const XlsxNumFmt.builtin(12));
      expect(XlsxNumFmt.time, const XlsxNumFmt.builtin(21));
      expect(XlsxNumFmt.elapsedTime, const XlsxNumFmt.builtin(46));
      expect(XlsxNumFmt.text, const XlsxNumFmt.builtin(49));
    });
  });
  group('helpers', () {
    test('number', () {
      expect(XlsxNumFmt.number(), XlsxNumFmt.integer);
      expect(XlsxNumFmt.number(decimals: 2), XlsxNumFmt.decimal2);
      expect(XlsxNumFmt.number(grouping: true), XlsxNumFmt.thousands);
      expect(
        XlsxNumFmt.number(decimals: 2, grouping: true),
        XlsxNumFmt.thousands2,
      );
      expect(XlsxNumFmt.number(decimals: 3, grouping: true).code, '#,##0.000');
      expect(
        XlsxNumFmt.number(decimals: 2, negativeRed: true).code,
        '0.00;[Red]-0.00',
      );
      expect(XlsxNumFmt.number(decimals: 30).code, '0.${'0' * 30}');
    });
    test('percent', () {
      expect(XlsxNumFmt.percent(), const XlsxNumFmt.builtin(9));
      expect(XlsxNumFmt.percent(decimals: 2), const XlsxNumFmt.builtin(10));
      expect(XlsxNumFmt.percent(decimals: 1).code, '0.0%');
    });
    test('money', () {
      expect(XlsxNumFmt.money(), XlsxNumFmt.thousands2);
      expect(XlsxNumFmt.money(symbol: '₺').code, '#,##0.00" ₺"');
      expect(
        XlsxNumFmt.money(symbol: r'$', symbolFirst: true).code,
        r'"$"#,##0.00',
      );
      expect(
        XlsxNumFmt.money(symbol: '€', decimals: 0, negativeRed: true).code,
        '#,##0" €";[Red]-#,##0" €"',
      );
      expect(XlsxNumFmt.money(decimals: 0), XlsxNumFmt.thousands);
    });
    test('invalid arguments throw at once', () {
      expect(() => XlsxNumFmt.money(symbol: 'a"b'), throwsArgumentError);
      expect(() => XlsxNumFmt.money(symbol: 'a\u0001'), throwsArgumentError);
      expect(() => XlsxNumFmt.number(decimals: 31), throwsArgumentError);
      expect(() => XlsxNumFmt.number(decimals: -1), throwsArgumentError);
      expect(() => XlsxNumFmt.percent(decimals: 31), throwsArgumentError);
      expect(() => XlsxNumFmt.money(decimals: 31), throwsArgumentError);
    });
  });
  group('isDateFormat scanner', () {
    bool d(String code) => isDateFormat(XlsxNumFmt.custom(code));
    test('an escaped quote does not open a literal', () {
      expect(d(r'\"d"h"'), isTrue);
    });
    test('locale, colour and case', () {
      expect(d('[\$-41F]dd.mm.yyyy'), isTrue);
      expect(d('[Red]dd/mm'), isTrue);
      expect(d('DD/MM/YYYY'), isTrue);
      expect(d('h:mm AM/PM'), isTrue);
    });
    test('literals and General', () {
      expect(d('"d"d'), isTrue);
      expect(d('General dd'), isTrue);
      expect(d('General'), isFalse);
      expect(d('0.00E+00'), isFalse);
      expect(d('[h]'), isFalse);
    });
  });
}
