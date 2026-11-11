import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';

/// A sheet `Sales` with the table `Sales` over A1:C5: a header row, three
/// body rows and a totals row whose B5 is `SUBTOTAL(109,B2:B4)` and C5
/// `SUBTOTAL(103,C2:C4)`, as the model and the writer write it.
XlsxWorkbook _book() {
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet sheet = book.addSheet('Sales');
  for (int r = 1; r <= 3; r++) {
    sheet
      ..setCell(r, 0, 'R$r')
      ..setCell(r, 1, r * 10)
      ..setCell(r, 2, 'n$r');
  }
  sheet.addTable(
    XlsxTable('Sales', XlsxRange.parse('A1:C5'), const <XlsxTableColumn>[
      XlsxTableColumn('Region', totalsLabel: 'Total'),
      XlsxTableColumn('Amount', totalsFunction: XlsxTotalsFunction.sum),
      XlsxTableColumn('Note', totalsFunction: XlsxTotalsFunction.count),
    ], totalsRow: true),
  );
  return book;
}

String? _formula(XlsxSheet sheet, String ref) {
  final XlsxRange cell = XlsxRange.parse(ref);
  return sheet.cellAt(cell.firstRow, cell.firstColumn)?.formula;
}

/// Every totals cell of every table of every sheet of [bytes] whose column
/// has a `totalsRowFunction` other than `custom`: the cell must hold that
/// function's `SUBTOTAL` over the column's body rows, in A1 or as a
/// structured reference, as Excel requires (it repairs the table otherwise).
List<String> _totalsProblems(Uint8List bytes) {
  final XlsxWorkbook book = XlsxWorkbook.open(bytes);
  final List<String> problems = <String>[];
  for (final XlsxSheet sheet in book.sheets) {
    for (final XlsxTable table in sheet.tables) {
      if (!table.totalsRow) continue;
      final XlsxRange r = table.range;
      final int firstBody = r.firstRow + (table.headerRow ? 1 : 0);
      for (int i = 0; i < table.columns.length; i++) {
        final XlsxTableColumn c = table.columns[i];
        final int? code = switch (c.totalsFunction) {
          XlsxTotalsFunction.sum => 109,
          XlsxTotalsFunction.count => 103,
          XlsxTotalsFunction.average => 101,
          XlsxTotalsFunction.countNums => 102,
          XlsxTotalsFunction.max => 104,
          XlsxTotalsFunction.min => 105,
          XlsxTotalsFunction.stdDev => 107,
          XlsxTotalsFunction.variance => 110,
          _ => null,
        };
        if (code == null) continue;
        final int column = r.firstColumn + i;
        final String body = XlsxRange(firstBody, column, r.lastRow - 1).ref;
        final String? f = sheet.cellAt(r.lastRow, column)?.formula;
        if (f != 'SUBTOTAL($code,$body)' &&
            f != 'SUBTOTAL($code,${table.name}[${c.name}])') {
          problems.add(
            '${sheet.name}!${XlsxRange(r.lastRow, column).ref} of '
            '${table.name}[${c.name}]: $f, not SUBTOTAL($code,$body)',
          );
        }
      }
    }
  }
  return problems;
}

void main() {
  test('rows inserted right above the totals row widen its SUBTOTALs', () {
    final XlsxWorkbook book = _book();
    final XlsxSheet sheet = book.sheet('Sales');
    expect(_formula(sheet, 'B5'), 'SUBTOTAL(109,B2:B4)');
    sheet.insertRows(4, 2);
    expect(sheet.tables.single.range, XlsxRange.parse('A1:C7'));
    expect(_formula(sheet, 'B7'), 'SUBTOTAL(109,B2:B6)');
    expect(_formula(sheet, 'C7'), 'SUBTOTAL(103,C2:C6)');
    expect(_totalsProblems(book.save().bytes), isEmpty);
  });

  test('deleting the last body row narrows the SUBTOTALs', () {
    final XlsxWorkbook book = _book();
    final XlsxSheet sheet = book.sheet('Sales');
    sheet.deleteRows(3);
    expect(_formula(sheet, 'B4'), 'SUBTOTAL(109,B2:B3)');
    expect(_totalsProblems(book.save().bytes), isEmpty);
  });

  test('a column inserted inside the table keeps every total on its body', () {
    final XlsxWorkbook book = _book();
    final XlsxSheet sheet = book.sheet('Sales');
    sheet
      ..insertColumns(1)
      ..insertRows(4, 2);
    expect(_formula(sheet, 'C7'), 'SUBTOTAL(109,C2:C6)');
    expect(_formula(sheet, 'D7'), 'SUBTOTAL(103,D2:D6)');
    expect(_totalsProblems(book.save().bytes), isEmpty);
  });

  test('a totals cell the user changed is left to the formula rules', () {
    final XlsxWorkbook book = _book();
    final XlsxSheet sheet = book.sheet('Sales');
    sheet
      ..setCell(4, 1, const XlsxFormula('SUBTOTAL(109,B2:B3)'))
      ..insertRows(4, 2);
    expect(_formula(sheet, 'B7'), 'SUBTOTAL(109,B2:B3)');
  });

  test('undo restores the totals cells', () {
    final XlsxWorkbook book = _book();
    final XlsxSheet sheet = book.sheet('Sales');
    final Map<String, String> before = readXlsx(book.save().bytes);
    final XlsxChangeSet set = book.transaction(() => sheet.insertRows(4, 2));
    book.undo(set);
    expect(_formula(sheet, 'B5'), 'SUBTOTAL(109,B2:B4)');
    expect(
      readXlsx(book.save().bytes)['xl/worksheets/sheet1.xml'],
      before['xl/worksheets/sheet1.xml'],
    );
  });

  test('every fixture with a totals row, edited as edit_model edits it, '
      'keeps its totals on the body', () {
    for (final Fixture fixture in allFixtures()) {
      final Uint8List source = fixture.build();
      final XlsxWorkbook book = XlsxWorkbook.open(source);
      if (!book.sheets.any(
        (XlsxSheet s) => s.tables.any((XlsxTable t) => t.totalsRow),
      )) {
        continue;
      }
      for (final XlsxSheet sheet in book.sheets) {
        for (final XlsxTable t in sheet.tables) {
          if (!t.totalsRow) continue;
          // Above the totals row, inside the body, and a column inside.
          sheet
            ..insertRows(t.range.lastRow, 2)
            ..insertRows(t.range.firstRow + 1)
            ..insertColumns(t.range.firstColumn + 1);
          break;
        }
      }
      expect(_totalsProblems(book.save().bytes), isEmpty, reason: fixture.name);
    }
  });
}
