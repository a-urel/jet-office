import 'package:jet_office/src/xlsx/formula/formula_lexer.dart';
import 'package:jet_office/src/xlsx/formula/formula_reference.dart';
import 'package:jet_office/src/xlsx/formula/formula_rewrite.dart';
import 'package:jet_office/src/xlsx/formula/formula_token.dart';
import 'package:test/test.dart';

import 'formula_lexer_test.dart' as lexer_test;

/// The reference of [text], a prefix and one reference token.
FormulaReference? parsed(String text) {
  final List<XlsxFormulaToken> tokens = lexFormula(text);
  if (tokens.length == 1) return FormulaReference.parse('', tokens.single);
  if (tokens.length == 2 &&
      tokens.first.kind == XlsxFormulaTokenKind.sheetPrefix) {
    return FormulaReference.parse(tokens.first.text, tokens.last);
  }
  return null;
}

/// Changes nothing.
final class IdentityMapper implements ReferenceMapper {
  @override
  FormulaReferenceResult? mapReference(FormulaReference ref, String host) =>
      null;

  @override
  String? mapSheetName(String sheet) => null;

  @override
  String? mapStructured(String table, String spec, String host) => null;
}

/// Moves every cell of [sheet] (or of the host sheet when unqualified) one
/// row down; a reference to row [deleted] becomes `#REF!`; renames [from]
/// to [to].
final class TestMapper implements ReferenceMapper {
  TestMapper({this.sheet = 'Sheet1', this.deleted, this.from, this.to});

  final String sheet;
  final int? deleted;
  final String? from;
  final String? to;

  @override
  FormulaReferenceResult? mapReference(FormulaReference ref, String host) {
    if ((ref.sheet ?? host) != sheet || ref.externalIndex != null) return null;
    if (ref.firstRow == null) return null;
    if (deleted != null &&
        ref.firstRow! <= deleted! &&
        ref.lastRow! >= deleted!) {
      return const FormulaReferenceResult.refError();
    }
    return FormulaReferenceResult.to(
      FormulaReference(
        form: ref.form,
        sheet: ref.sheet,
        lastSheet: ref.lastSheet,
        externalIndex: ref.externalIndex,
        firstRow: ref.firstRow! + 1,
        lastRow: ref.lastRow! + 1,
        firstColumn: ref.firstColumn,
        lastColumn: ref.lastColumn,
        absFirstRow: ref.absFirstRow,
        absLastRow: ref.absLastRow,
        absFirstColumn: ref.absFirstColumn,
        absLastColumn: ref.absLastColumn,
      ),
    );
  }

  @override
  String? mapSheetName(String name) => name == from ? to : null;

  @override
  String? mapStructured(String table, String spec, String host) => null;
}

void main() {
  test('parse and render round-trip every reference form', () {
    for (final String text in <String>[
      'A1',
      r'$A$1',
      r'A$1',
      r'$A1',
      r'A1:$B$2',
      r'$C3:D$4',
      'XFD1048576',
      '3:5',
      r'$3:$5',
      'B:D',
      r'$B:$D',
      'Sheet1!A1',
      "'My Sheet'!A1:B2",
      "'O''Brien'!\$A\$1",
      'Sheet1:Sheet3!B5',
      "'Q 1:Q 3'!B5",
      '[1]Sheet1!\$A\$1',
      "'[2]My Sheet'!B2",
      'Data!3:5',
      "'1st'!A:A",
    ]) {
      final FormulaReference? ref = parsed(text);
      expect(ref, isNotNull, reason: text);
      expect(ref!.render(), text);
    }
    final FormulaReference ref = parsed(r"'[2]My Sheet'!$B2:C$9")!;
    expect(ref.externalIndex, 2);
    expect(ref.sheet, 'My Sheet');
    expect(ref.form, FormulaReferenceForm.area);
    expect(
      (ref.firstRow, ref.lastRow, ref.firstColumn, ref.lastColumn),
      (2, 9, 2, 3),
    );
    expect(
      (ref.absFirstRow, ref.absLastRow, ref.absFirstColumn, ref.absLastColumn),
      (false, true, true, false),
    );
    final FormulaReference rows = parsed('3:5')!;
    expect((rows.firstColumn, rows.lastColumn), (null, null));
    final FormulaReference cols = parsed('Sheet1:Sheet3!B:D')!;
    expect((cols.sheet, cols.lastSheet), ('Sheet1', 'Sheet3'));
    expect((cols.firstRow, cols.lastRow), (null, null));
    // Not references: a name half, a workbook-level name, a function.
    expect(parsed('Rate:B2'), isNull);
    expect(parsed('[1]!Rate'), isNull);
    expect(parsed('Rate'), isNull);
  });

  test('untouched text is identical', () {
    const List<String> formulas = lexer_test.fixedFormulas;
    expect(formulas.length, greaterThanOrEqualTo(60));
    for (final String f in formulas) {
      expect(rewriteFormula(f, IdentityMapper(), 'Sheet1'), isNull, reason: f);
    }
    // A mapper that touches only Sheet9 leaves them all as read too.
    for (final String f in formulas) {
      expect(
        rewriteFormula(f, TestMapper(sheet: 'Sheet9'), 'Sheet1'),
        isNull,
        reason: f,
      );
    }
  });

  test('only the token changes', () {
    final TestMapper m = TestMapper();
    expect(
      rewriteFormula('SUM( A1 ,\r\n  \$B\$2:C3 )+N("A1 note")', m, 'Sheet1'),
      'SUM( A2 ,\r\n  \$B\$3:C4 )+N("A1 note")',
    );
    expect(
      rewriteFormula("Sheet1!A1+'Other'!A1+Rate", m, 'Other'),
      "Sheet1!A2+'Other'!A1+Rate",
    );
    expect(rewriteFormula('SUM(3:5)', m, 'Sheet1'), 'SUM(4:6)');
    expect(rewriteFormula('SUM(B:B)', m, 'Sheet1'), isNull);
    expect(rewriteFormula('A1:Sheet1!B2', m, 'Sheet1'), 'A2:Sheet1!B3');
    // Renames reach every prefix, quoting as needed; the external one is
    // another workbook's sheet.
    final TestMapper r = TestMapper(sheet: 'none', from: 'Old', to: 'New Name');
    expect(
      rewriteFormula('Old!A1+Old!Rate+Old:Z!B2+[1]Old!A1', r, 'Sheet1'),
      "'New Name'!A1+'New Name'!Rate+'New Name:Z'!B2+[1]Old!A1",
    );
  });

  test('a ref mapped to #REF! keeps its sheet prefix', () {
    final TestMapper m = TestMapper(deleted: 2);
    expect(rewriteFormula('Sheet1!A2+1', m, 'Other'), 'Sheet1!#REF!+1');
    expect(
      rewriteFormula("SUM('Sheet1'!A1:A5)", m, 'x'),
      "SUM('Sheet1'!#REF!)",
    );
    expect(rewriteFormula('A2*B1', m, 'Sheet1'), '#REF!*B2');
  });

  test('sqref lists rewrite each range, a #REF! range is dropped', () {
    final TestMapper m = TestMapper(deleted: 2);
    expect(rewriteSqref('A1 B3:C4 D2', m, 'Sheet1'), 'A2 B4:C5');
    expect(rewriteSqref('A2 B3:B9', m, 'Sheet1'), 'B4:B10');
    expect(rewriteSqref('A2', m, 'Sheet1'), '');
    expect(rewriteSqref('A1 B1', m, 'Other'), isNull);
    expect(rewriteSqref('A3', m, 'Other'), isNull);
  });

  test('unlexable formulas come back null and are reported once', () {
    final List<String> reported = <String>[];
    final TestMapper m = TestMapper();
    expect(
      rewriteFormula('A1;B1;"open', m, 'Sheet1', onUnlexable: reported.add),
      isNull,
    );
    expect(reported, <String>['A1;B1;"open']);
    expect(
      rewriteSqref('A1 B1;', m, 'Sheet1', onUnlexable: reported.add),
      isNull,
    );
    expect(reported, <String>['A1;B1;"open', 'A1 B1;']);
  });
}
