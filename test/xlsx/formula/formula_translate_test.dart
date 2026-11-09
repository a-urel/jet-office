import 'package:jet_office/src/xlsx/formula/formula_translate.dart';
import 'package:test/test.dart';

void main() {
  test(r'relative parts move, $ parts stay', () {
    expect(translateFormula(r'B1*$C$1+D$2+$E3', 2, 1, 'S'), r'C3*$C$1+E$2+$E5');
    expect(
      translateFormula('SUM(A1:B2)+Other!A1', 1, 0, 'S'),
      'SUM(A2:B3)+Other!A2',
    );
    expect(
      translateFormula('SUM(3:4)+SUM(B:C)', 1, 1, 'S'),
      'SUM(4:5)+SUM(C:D)',
    );
  });

  test('a reference moved off the sheet is #REF!', () {
    expect(translateFormula('A1+B2', -1, 0, 'S'), '#REF!+B1');
  });

  test('no offset or nothing to move keeps the text', () {
    expect(translateFormula('a1 + 1', 0, 0, 'S'), 'a1 + 1');
    expect(translateFormula(r'"A1"&$A$1', 3, 3, 'S'), r'"A1"&$A$1');
  });

  test('an unlexable formula gives null', () {
    expect(translateFormula('A1+"x', 1, 0, 'S'), isNull);
  });
}
