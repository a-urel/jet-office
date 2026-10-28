import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/cell_ref.dart';
import 'package:jet_office/src/xlsx/read/cell_decoder.dart';
import 'package:jet_office/src/xlsx/read/formula_groups.dart';
import 'package:test/test.dart';

import '../../support/timing.dart';

/// A result that is the valid master group of [kind] over [ref].
Matcher _master(XlsxFormulaGroupKind kind, String ref) =>
    isA<FormulaGroupResult>()
        .having((FormulaGroupResult r) => r.invalid, 'invalid', isFalse)
        .having(
          (FormulaGroupResult r) => r.group,
          'group',
          XlsxFormulaGroup(kind, XlsxRange.parse(ref), isMaster: true),
        );

/// A result that is invalid and has no group.
final Matcher _invalid = isA<FormulaGroupResult>()
    .having((FormulaGroupResult r) => r.invalid, 'invalid', isTrue)
    .having((FormulaGroupResult r) => r.group, 'group', isNull);

void main() {
  test('shared master and followers', () {
    final FormulaGroups groups = FormulaGroups()..startRow(1);
    final FormulaGroupResult master = groups.master(
      FormulaType.shared,
      row: 1,
      column: 1,
      ref: 'B2:B4',
      si: '0',
    );
    expect(master, _master(XlsxFormulaGroupKind.shared, 'B2:B4'));
    groups.startRow(2);
    final FormulaGroupResult a = groups.follower('0', row: 2, column: 1);
    groups.startRow(3);
    final FormulaGroupResult b = groups.follower('00', row: 3, column: 1);
    const XlsxFormulaGroup follower = XlsxFormulaGroup(
      XlsxFormulaGroupKind.shared,
      XlsxRange(1, 1, 3, 1),
      isMaster: false,
    );
    expect(a.group, follower);
    expect(b.group, follower);
    expect(a.invalid || b.invalid, isFalse);
    expect(identical(a.group, b.group), isTrue);
    expect(master.group!.range, a.group!.range);
    // A shared formula covers no cell without <f>.
    expect(groups.coveredBy(2, 1), isNull);
  });

  test('array covers its range', () {
    final FormulaGroups groups = FormulaGroups()..startRow(0);
    expect(
      groups.master(FormulaType.array, row: 0, column: 2, ref: 'C1:C3'),
      _master(XlsxFormulaGroupKind.array, 'C1:C3'),
    );
    const XlsxFormulaGroup follower = XlsxFormulaGroup(
      XlsxFormulaGroupKind.array,
      XlsxRange(0, 2, 2, 2),
      isMaster: false,
    );
    expect(groups.coveredBy(0, 2), isNull, reason: 'the master itself');
    expect(groups.coveredBy(0, 1), isNull);
    expect(groups.coveredBy(0, 3), isNull);
    groups.startRow(1);
    expect(groups.coveredBy(1, 2), follower);
    groups.startRow(2);
    expect(groups.coveredBy(2, 2), follower);
    groups.startRow(3);
    expect(groups.coveredBy(3, 2), isNull);
  });

  test('data table', () {
    final FormulaGroups groups = FormulaGroups()..startRow(1);
    expect(
      groups.master(FormulaType.dataTable, row: 1, column: 1, ref: 'B2:C3'),
      _master(XlsxFormulaGroupKind.dataTable, 'B2:C3'),
    );
    expect(
      groups.coveredBy(1, 2),
      const XlsxFormulaGroup(
        XlsxFormulaGroupKind.dataTable,
        XlsxRange(1, 1, 2, 2),
        isMaster: false,
      ),
    );
    groups.startRow(2);
    expect(groups.coveredBy(2, 1)!.kind, XlsxFormulaGroupKind.dataTable);
  });

  test('array without ref covers itself', () {
    final FormulaGroups groups = FormulaGroups()..startRow(4);
    expect(
      groups.master(FormulaType.array, row: 4, column: 0),
      _master(XlsxFormulaGroupKind.array, 'A5'),
    );
    expect(groups.coveredBy(4, 0), isNull);
    expect(groups.coveredBy(4, 1), isNull);
  });

  test('a data table without ref is invalid', () {
    final FormulaGroups groups = FormulaGroups()..startRow(0);
    expect(groups.master(FormulaType.dataTable, row: 0, column: 0), _invalid);
  });

  test('a master without ref, with a bad ref or outside it is invalid', () {
    for (final (FormulaType type, String? ref) in <(FormulaType, String?)>[
      (FormulaType.shared, null),
      (FormulaType.shared, 'x'),
      (FormulaType.shared, 'A1:A'),
      (FormulaType.shared, 'C1:C3'),
      (FormulaType.array, 'x'),
      (FormulaType.array, 'C1:C3'),
      (FormulaType.dataTable, ''),
      (FormulaType.dataTable, 'B1:B2:B3'),
    ]) {
      final FormulaGroups groups = FormulaGroups()..startRow(1);
      expect(
        groups.master(type, row: 1, column: 1, ref: ref, si: '0'),
        _invalid,
        reason: '$type $ref',
      );
      // Nothing was defined.
      expect(
        groups.follower('0', row: 2, column: 1),
        _invalid,
        reason: '$type $ref',
      );
      expect(groups.coveredBy(2, 2), isNull, reason: '$type $ref');
    }
  });

  test('a shared master whose si is not a non-negative integer', () {
    for (final String? si in <String?>[null, '-1', '', 'a', '1.0', ' 1']) {
      final FormulaGroups groups = FormulaGroups()..startRow(0);
      expect(
        groups.master(
          FormulaType.shared,
          row: 0,
          column: 0,
          ref: 'A1:A2',
          si: si,
        ),
        _invalid,
        reason: '$si',
      );
    }
  });

  test('a huge si is a key like any other', () {
    final FormulaGroups groups = FormulaGroups()..startRow(0);
    final String si = '9' * 40;
    expect(
      groups.master(
        FormulaType.shared,
        row: 0,
        column: 0,
        ref: 'A1:A2',
        si: si,
      ),
      _master(XlsxFormulaGroupKind.shared, 'A1:A2'),
    );
    groups.startRow(1);
    expect(
      groups.follower(si, row: 1, column: 0).group!.range,
      XlsxRange.parse('A1:A2'),
    );
    expect(groups.follower('${'9' * 39}8', row: 1, column: 0), _invalid);
  });

  test('unknown si and follower before master', () {
    final FormulaGroups groups = FormulaGroups()..startRow(0);
    expect(
      groups.follower('0', row: 0, column: 1),
      _invalid,
      reason: 'before its master',
    );
    expect(groups.follower(null, row: 0, column: 1), _invalid);
    expect(groups.follower('-1', row: 0, column: 1), _invalid);
    groups.master(FormulaType.shared, row: 0, column: 1, ref: 'B1:B3', si: '0');
    groups.startRow(1);
    expect(
      groups.follower('1', row: 1, column: 1),
      _invalid,
      reason: 'unknown',
    );
    expect(groups.follower('0', row: 1, column: 1).invalid, isFalse);
  });

  test("a follower outside its master's range is invalid", () {
    final FormulaGroups groups = FormulaGroups()..startRow(0);
    groups.master(FormulaType.shared, row: 0, column: 1, ref: 'B1:B2', si: '0');
    groups.startRow(1);
    expect(groups.follower('0', row: 1, column: 1).invalid, isFalse);
    expect(groups.follower('0', row: 1, column: 2), _invalid, reason: 'C2');
    expect(groups.follower('0', row: 1, column: 0), _invalid, reason: 'A2');
    groups.startRow(2);
    expect(groups.follower('0', row: 2, column: 1), _invalid, reason: 'B3');
  });

  test('a second shared master reusing an si takes over later followers', () {
    final FormulaGroups groups = FormulaGroups()..startRow(0);
    groups.master(FormulaType.shared, row: 0, column: 0, ref: 'A1:A2', si: '0');
    groups.startRow(1);
    final FormulaGroupResult first = groups.follower('0', row: 1, column: 0);
    expect(first.group!.range, XlsxRange.parse('A1:A2'));
    groups.startRow(2);
    groups.master(FormulaType.shared, row: 2, column: 0, ref: 'A3:A4', si: '0');
    groups.startRow(3);
    final FormulaGroupResult second = groups.follower('0', row: 3, column: 0);
    expect(second.group!.range, XlsxRange.parse('A3:A4'));
    expect(second.invalid, isFalse);
  });

  test('an array overlapping an active one is invalid', () {
    final FormulaGroups groups = FormulaGroups()..startRow(0);
    groups.master(FormulaType.array, row: 0, column: 0, ref: 'A1:C3');
    groups.startRow(1);
    expect(
      groups.master(FormulaType.dataTable, row: 1, column: 3, ref: 'B2:D2'),
      _invalid,
    );
    // The first range is unchanged and the second covers nothing.
    expect(groups.coveredBy(1, 2)!.range, XlsxRange.parse('A1:C3'));
    expect(groups.coveredBy(1, 3), isNull);
    // Next to it, it is fine.
    expect(
      groups.master(FormulaType.array, row: 1, column: 3, ref: 'D2:E3'),
      _master(XlsxFormulaGroupKind.array, 'D2:E3'),
    );
  });

  test('a range that has ended no longer conflicts', () {
    final FormulaGroups groups = FormulaGroups()..startRow(0);
    groups.master(FormulaType.array, row: 0, column: 0, ref: 'A1:C1');
    groups.startRow(1);
    expect(
      groups.master(FormulaType.array, row: 1, column: 0, ref: 'A2:D2'),
      _master(XlsxFormulaGroupKind.array, 'A2:D2'),
    );
    expect(groups.coveredBy(1, 3)!.range, XlsxRange.parse('A2:D2'));
  });

  test('master rejects a normal formula', () {
    expect(
      () => FormulaGroups().master(FormulaType.normal, row: 0, column: 0),
      throwsArgumentError,
    );
  });

  test('an array master not at the top-left of its ref is invalid', () {
    for (final FormulaType type in <FormulaType>[
      FormulaType.array,
      FormulaType.dataTable,
    ]) {
      final FormulaGroups groups = FormulaGroups()..startRow(1);
      expect(groups.master(type, row: 1, column: 1, ref: 'A1:C3'), _invalid);
      groups.startRow(2);
      expect(groups.coveredBy(2, 2), isNull);
    }
    final FormulaGroups groups = FormulaGroups()..startRow(1);
    expect(
      groups.master(
        FormulaType.shared,
        row: 1,
        column: 1,
        ref: 'A1:C3',
        si: '0',
      ),
      _master(XlsxFormulaGroupKind.shared, 'A1:C3'),
    );
  });

  group('scale', () {
    const int columns = XlsxLimits.maxColumns;
    const int rows = 10;

    /// Inserts one array per column on row 0, each over [rows] more rows, in
    /// the column order [columnsInOrder], then checks every covered lookup
    /// and that nothing is covered past the ranges. Returns the number of
    /// wrong answers.
    int manyRanges(Iterable<int> columnsInOrder) {
      final FormulaGroups groups = FormulaGroups()..startRow(0);
      for (final int c in columnsInOrder) {
        final FormulaGroupResult result = groups.master(
          FormulaType.array,
          row: 0,
          column: c,
          ref: '${cellRef(0, c)}:${cellRef(rows, c)}',
        );
        if (result.invalid) fail('master ${cellRef(0, c)} is invalid');
      }
      int wrong = 0;
      for (int r = 1; r <= rows; r++) {
        groups.startRow(r);
        for (int c = 0; c < columns; c++) {
          final XlsxFormulaGroup? group = groups.coveredBy(r, c);
          if (group == null ||
              group.isMaster ||
              group.kind != XlsxFormulaGroupKind.array ||
              group.range != XlsxRange(0, c, rows, c)) {
            wrong++;
          }
        }
      }
      groups.startRow(rows + 1);
      for (int c = 0; c < columns; c++) {
        if (groups.coveredBy(rows + 1, c) != null) wrong++;
      }
      return wrong;
    }

    /// The same inserts and lookups on a tree that holds a single range.
    void singleRange() {
      final FormulaGroups groups = FormulaGroups()..startRow(0);
      groups.master(
        FormulaType.array,
        row: 0,
        column: 0,
        ref: 'A1:A${rows + 1}',
      );
      for (int c = 1; c < columns; c++) {
        groups.coveredBy(0, c);
      }
      for (int r = 1; r <= rows + 1; r++) {
        groups.startRow(r);
        for (int c = 0; c < columns; c++) {
          groups.coveredBy(r, c);
        }
      }
    }

    test('binary search over many ranges', () {
      int wrong = -1;
      final Duration many = bestOfThree(() {
        wrong = manyRanges(Iterable<int>.generate(columns));
      });
      expect(wrong, 0);
      expectWithinRatio(many, bestOfThree(singleRange));
    });

    test('ranges inserted right to left stay a binary search', () {
      int wrong = -1;
      final Duration many = bestOfThree(() {
        wrong = manyRanges(
          Iterable<int>.generate(columns, (int i) => columns - 1 - i),
        );
      });
      expect(wrong, 0);
      expectWithinRatio(many, bestOfThree(singleRange));
    });

    test('one wide range after many ended ones', () {
      const int ended = 10000;
      FormulaGroupResult? wide;
      XlsxFormulaGroup? covered;
      final Duration many = bestOfThree(() {
        final FormulaGroups groups = FormulaGroups();
        for (int r = 0; r < ended; r++) {
          groups.startRow(r);
          final String ref = cellRef(r, r % columns);
          final FormulaGroupResult result = groups.master(
            FormulaType.array,
            row: r,
            column: r % columns,
            ref: '$ref:$ref',
          );
          if (result.invalid) fail('master $ref is invalid');
        }
        groups.startRow(ended);
        wide = groups.master(
          FormulaType.array,
          row: ended,
          column: 0,
          ref: 'A${ended + 1}:XFD${ended + 1}',
        );
        covered = groups.coveredBy(ended, columns - 1);
      });
      expect(
        wide,
        _master(XlsxFormulaGroupKind.array, 'A${ended + 1}:XFD${ended + 1}'),
      );
      expect(
        covered,
        XlsxFormulaGroup(
          XlsxFormulaGroupKind.array,
          XlsxRange.parse('A${ended + 1}:XFD${ended + 1}'),
          isMaster: false,
        ),
      );
      // A tree that holds one range, with as many lookups.
      final Duration one = bestOfThree(() {
        final FormulaGroups groups = FormulaGroups()..startRow(0);
        groups.master(FormulaType.array, row: 0, column: 0, ref: 'A1:XFD1');
        for (int r = 0; r < ended; r++) {
          groups.coveredBy(0, r % columns);
        }
      });
      expectWithinRatio(many, one);
    });
  });
}
