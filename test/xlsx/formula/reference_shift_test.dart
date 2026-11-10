import 'package:jet_office/src/xlsx/formula/formula_rewrite.dart';
import 'package:jet_office/src/xlsx/formula/reference_shift.dart';
import 'package:jet_office/src/xlsx/range.dart';
import 'package:test/test.dart';

const List<String> order = <String>['Data', 'Mid', 'Other', 'Last'];

/// Rows 5 and 6 inserted on `Data` (count 2).
final ReferenceShift insRows = ReferenceShift.insert(
  'Data',
  ShiftAxis.rows,
  5,
  2,
);

/// Rows 5 and 6 deleted on `Data`.
final ReferenceShift delRows = ReferenceShift.delete(
  'Data',
  ShiftAxis.rows,
  5,
  2,
);

/// One column inserted at C on `Data`.
final ReferenceShift insCols = ReferenceShift.insert(
  'Data',
  ShiftAxis.columns,
  3,
  1,
);

/// Columns C and D deleted on `Data`.
final ReferenceShift delCols = ReferenceShift.delete(
  'Data',
  ShiftAxis.columns,
  3,
  2,
);

/// Rows 5 and 6 inserted on `Mid` (inside the span `Data:Other`).
final ReferenceShift insMid = ReferenceShift.insert(
  'Mid',
  ShiftAxis.rows,
  5,
  2,
);

/// (edit, host sheet, formula, expected formula).
final List<(ReferenceShift, String, String, String)> table =
    <(ReferenceShift, String, String, String)>[
      // Insert rows: before, at, after the index.
      (insRows, 'Data', 'A4', 'A4'),
      (insRows, 'Data', 'A5', 'A7'),
      (insRows, 'Data', 'A6', 'A8'),
      (insRows, 'Data', 'B100', 'B102'),
      (insRows, 'Data', r'$A$5', r'$A$7'),
      (insRows, 'Data', r'A$5', r'A$7'),
      (insRows, 'Data', r'$A5', r'$A7'),
      // Ranges.
      (insRows, 'Data', 'A1:B4', 'A1:B4'),
      (insRows, 'Data', 'A1:B5', 'A1:B7'),
      (insRows, 'Data', 'A4:B6', 'A4:B8'),
      (insRows, 'Data', 'A5:B6', 'A7:B8'),
      (insRows, 'Data', 'A6:B9', 'A8:B11'),
      (insRows, 'Data', r'$A$1:$B$10', r'$A$1:$B$12'),
      (insRows, 'Data', 'A5:A5', 'A7:A7'),
      // Whole rows and columns.
      (insRows, 'Data', '3:4', '3:4'),
      (insRows, 'Data', '3:5', '3:7'),
      (insRows, 'Data', '5:8', '7:10'),
      (insRows, 'Data', r'$3:$9', r'$3:$11'),
      (insRows, 'Data', 'B:D', 'B:D'),
      // Other sheets and hosts.
      (insRows, 'Data', 'Other!A5', 'Other!A5'),
      (insRows, 'Other', 'A5', 'A5'),
      (insRows, 'Other', 'Data!A5', 'Data!A7'),
      (insRows, 'Other', 'data!A5', 'data!A7'),
      (insRows, 'Other', "'Data'!A5:A9", "'Data'!A7:A11"),
      (insRows, 'Data', '[1]Data!A5', '[1]Data!A5'),
      (insRows, 'Data', 'SUM(A1:A10)+A5*Other!A5', 'SUM(A1:A12)+A7*Other!A5'),
      // 3D spans never shift, even on an end sheet.
      (insRows, 'Other', 'Data:Data!A5', 'Data:Data!A7'),
      (delRows, 'Other', 'Other:Data!A9', 'Other:Data!A9'),
      (insRows, 'Mid', 'Data:Other!A5', 'Data:Other!A5'),
      (insRows, 'Mid', 'Mid:Last!A5', 'Mid:Last!A5'),
      (insMid, 'Data', 'Data:Other!A5', 'Data:Other!A5'),
      (insMid, 'Data', 'Other:Last!A5', 'Other:Last!A5'),
      (insMid, 'Data', 'Data:Mid!B1:B9', 'Data:Mid!B1:B9'),
      // Insert at first row, at the last row, past the last row.
      (ReferenceShift.insert('Data', ShiftAxis.rows, 1, 1), 'Data', 'A1', 'A2'),
      (
        ReferenceShift.insert('Data', ShiftAxis.rows, 1, 1),
        'Data',
        'A1:A3',
        'A2:A4',
      ),
      (
        ReferenceShift.insert('Data', ShiftAxis.rows, 3, 1),
        'Data',
        'A1:A3',
        'A1:A4',
      ),
      (
        ReferenceShift.insert('Data', ShiftAxis.rows, 4, 1),
        'Data',
        'A1:A3',
        'A1:A3',
      ),
      // The row limit.
      (insRows, 'Data', 'A1048575', '#REF!'),
      (insRows, 'Data', 'A1048574', 'A1048576'),
      (insRows, 'Other', 'Data!A1048576', 'Data!#REF!'),
      (insRows, 'Data', 'A1048575:A1048576', '#REF!'),
      (insRows, 'Data', 'A1:A1048576', 'A1:A1048576'),
      (insRows, 'Data', 'A6:A1048576', 'A8:A1048576'),
      (insRows, 'Data', '1:1048576', '1:1048576'),
      // Delete rows 5 and 6.
      (delRows, 'Data', 'A4', 'A4'),
      (delRows, 'Data', 'A5', '#REF!'),
      (delRows, 'Data', 'A6', '#REF!'),
      (delRows, 'Data', 'A7', 'A5'),
      (delRows, 'Data', r'$A$7', r'$A$5'),
      (delRows, 'Other', 'Data!A5', 'Data!#REF!'),
      (delRows, 'Other', 'SUM(Data!A6)', 'SUM(Data!#REF!)'),
      (delRows, 'Data', 'A1:A4', 'A1:A4'),
      (delRows, 'Data', 'A5:A6', '#REF!'),
      (delRows, 'Data', 'A1:A10', 'A1:A8'),
      (delRows, 'Data', 'A5:A10', 'A5:A8'),
      (delRows, 'Data', 'A6:A10', 'A5:A8'),
      (delRows, 'Data', 'A1:A5', 'A1:A4'),
      (delRows, 'Data', 'A1:A6', 'A1:A4'),
      (delRows, 'Data', 'A7:A10', 'A5:A8'),
      (delRows, 'Data', '5:6', '#REF!'),
      (delRows, 'Data', '3:8', '3:6'),
      (delRows, 'Data', '6:9', '5:7'),
      (delRows, 'Data', 'C:C', 'C:C'),
      (delRows, 'Other', 'A5', 'A5'),
      (delRows, 'Mid', 'Data:Other!A5', 'Data:Other!A5'),
      (delRows, 'Data', 'A1048576', 'A1048574'),
      // Insert one column at C.
      (insCols, 'Data', 'B1', 'B1'),
      (insCols, 'Data', 'C1', 'D1'),
      (insCols, 'Data', r'$C$1', r'$D$1'),
      (insCols, 'Data', 'A1:B9', 'A1:B9'),
      (insCols, 'Data', 'A1:C9', 'A1:D9'),
      (insCols, 'Data', 'C1:E9', 'D1:F9'),
      (insCols, 'Data', 'B:C', 'B:D'),
      (insCols, 'Data', 'D:F', 'E:G'),
      (insCols, 'Data', '1:3', '1:3'),
      (insCols, 'Data', 'XFD1', '#REF!'),
      (insCols, 'Data', 'XFC1', 'XFD1'),
      (insCols, 'Data', 'A:XFD', 'A:XFD'),
      (insCols, 'Other', 'C1', 'C1'),
      // Delete columns C and D.
      (delCols, 'Data', 'B1', 'B1'),
      (delCols, 'Data', 'C1', '#REF!'),
      (delCols, 'Data', 'D1', '#REF!'),
      (delCols, 'Data', 'E1', 'C1'),
      (delCols, 'Data', 'C1:D9', '#REF!'),
      (delCols, 'Data', 'A1:F9', 'A1:D9'),
      (delCols, 'Data', 'D1:F9', 'C1:D9'),
      (delCols, 'Data', 'A1:C9', 'A1:B9'),
      (delCols, 'Data', 'C:D', '#REF!'),
      (delCols, 'Data', r'$B:$E', r'$B:$C'),
      (delCols, 'Other', 'Data!E1', 'Data!C1'),
      (delCols, 'Data', '4:4', '4:4'),
    ];

void main() {
  test('the shift table', () {
    expect(table.length, greaterThanOrEqualTo(80));
    for (final (ReferenceShift edit, String host, String f, String want)
        in table) {
      final String got = rewriteFormula(f, edit, host) ?? f;
      expect(got, want, reason: '$f on $host');
    }
  });

  test('shiftRange and shiftCell use 0-based indexes', () {
    // Rows 5 and 6 (0-based 4 and 5).
    expect(delRows.shiftRange(const XlsxRange(4, 0, 5, 3)), isNull);
    expect(
      delRows.shiftRange(const XlsxRange(0, 0, 9, 3)),
      const XlsxRange(0, 0, 7, 3),
    );
    expect(
      insRows.shiftRange(const XlsxRange(4, 0, 4, 0)),
      const XlsxRange(6, 0, 6, 0),
    );
    expect(
      insCols.shiftRange(const XlsxRange(0, 1, 0, 2)),
      const XlsxRange(0, 1, 0, 3),
    );
    expect(delRows.shiftCell(5, 2), isNull);
    expect(delRows.shiftCell(6, 2), (row: 4, column: 2));
    expect(insCols.shiftCell(0, 2), (row: 0, column: 3));
    expect(insRows.shiftCell(1048574, 0), isNull);
  });

  test('an area with a name half is left as read', () {
    // `Rate:B2` is a range between a defined name and a cell, not a cell
    // range: a row insert above it must not shift B2 (nor the name).
    final ReferenceShift above = ReferenceShift.insert(
      'Data',
      ShiftAxis.rows,
      1,
      1,
    );
    expect(rewriteFormula('SUM(Rate:B2)', above, 'Data'), isNull);
    expect(rewriteFormula('SUM(Rate:B2)+B2', above, 'Data'), 'SUM(Rate:B2)+B3');
  });

  test('a reversed range neither throws nor inverts', () {
    expect(rewriteFormula('SUM(A5:A1)', delRows, 'Data'), isNull);
  });

  test('a count of zero or a bad index throws', () {
    expect(
      () => ReferenceShift.insert('Data', ShiftAxis.rows, 0, 1),
      throwsArgumentError,
    );
    expect(
      () => ReferenceShift.delete('Data', ShiftAxis.rows, 1, 0),
      throwsArgumentError,
    );
  });

  test('rename quoting', () {
    for (final (String name, String want) in <(String, String)>[
      ('Q1 2026', "'Q1 2026'!A1"),
      ('2026', "'2026'!A1"),
      ('A1', "'A1'!A1"),
      ('R1C1', "'R1C1'!A1"),
      ("It's", "'It''s'!A1"),
      ('Çiğdem', 'Çiğdem!A1'),
      ('Sheet-1', "'Sheet-1'!A1"),
      ('Plain', 'Plain!A1'),
    ]) {
      expect(
        rewriteFormula('Data!A1', SheetRename('Data', name), 'Other'),
        want,
        reason: name,
      );
    }
    expect(
      rewriteFormula('Data:Other!A1', SheetRename('Other', 'Q 4'), 'Data'),
      "'Data:Q 4'!A1",
    );
  });

  test('rename ignores case and external prefixes', () {
    final SheetRename rename = SheetRename('Data', 'Facts');
    expect(rewriteFormula('DATA!A1+data!B2', rename, 'X'), 'Facts!A1+Facts!B2');
    expect(rewriteFormula('[1]Data!A1', rename, 'X'), isNull);
    expect(rewriteFormula('A1', rename, 'Data'), isNull);
    expect(rewriteFormula('"Data!A1"', rename, 'X'), isNull);
    expect(rename.mapSheetName('Other'), isNull);
  });

  test('move swaps 3D ends', () {
    // Data moves to the end: Data:Other now runs Other..Data.
    final SheetMove move = SheetMove(order, 0, 3);
    expect(
      rewriteFormula('SUM(Data:Other!A1)', move, 'Mid'),
      'SUM(Other:Data!A1)',
    );
    expect(rewriteFormula('Mid:Other!A1', move, 'Mid'), isNull);
    expect(rewriteFormula('Data!A1', move, 'Mid'), isNull);
    expect(rewriteFormula('[1]Data:Other!A1', move, 'Mid'), isNull);
    expect(
      rewriteFormula(
        "'data:Q 1'!A1",
        SheetMove(<String>['Data', 'Q 1'], 1, 0),
        'Data',
      ),
      "'Q 1:data'!A1",
    );
  });
}
