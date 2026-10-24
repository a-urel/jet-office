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
}
