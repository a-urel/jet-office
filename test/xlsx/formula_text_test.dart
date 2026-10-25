import 'package:jet_office/src/xlsx/formula_text.dart';
import 'package:test/test.dart';

void main() {
  group('checkFormulaText', () {
    test('strips one leading =', () {
      expect(checkFormulaText('=SUM(A1)', 'f'), 'SUM(A1)');
      expect(checkFormulaText('SUM(A1)', 'f'), 'SUM(A1)');
      expect(checkFormulaText('==1', 'f'), '=1');
    });

    test('an empty formula throws, also after the =', () {
      expect(() => checkFormulaText('=', 'f'), throwsArgumentError);
      expect(() => checkFormulaText('', 'f'), throwsArgumentError);
    });

    test('at most 8,192 UTF-16 code units, counted after the =', () {
      expect(checkFormulaText('=${'1' * 8192}', 'f'), hasLength(8192));
      expect(
        () => checkFormulaText('1' * 8193, 'f'),
        throwsA(
          isA<ArgumentError>().having((ArgumentError e) => e.name, 'name', 'f'),
        ),
      );
    });

    test('a character XML forbids throws', () {
      expect(() => checkFormulaText('A\u0001', 'f'), throwsArgumentError);
      expect(() => checkFormulaText('A\uD800', 'f'), throwsArgumentError);
    });
  });

  group('quotedSheetRef', () {
    test('quotes the name and doubles every quote', () {
      expect(quotedSheetRef("O'Brien", r'$A$1'), r"'O''Brien'!$A$1");
      expect(quotedSheetRef('Data', r'$A:$B'), r"'Data'!$A:$B");
      expect(quotedSheetRef("''", r'$1:$1'), r"''''''!$1:$1");
    });
  });
}
