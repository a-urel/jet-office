import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/formula/reference_shift.dart';
import 'package:jet_office/src/xlsx/model/xlsx_sheet.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';

import '../read/support/workbook_builder.dart';
import 'support/workbook_support.dart';

/// A worksheet of [views], [cols], [rows] and [merges], in schema order.
String _sheet({
  String views = '',
  String cols = '',
  String rows = '',
  String merges = '',
}) =>
    '<worksheet xmlns="$mainNs">$views$cols<sheetData>$rows</sheetData>'
    '$merges</worksheet>';

XlsxWorkbook _book(String xml) =>
    XlsxWorkbook.open(buildWorkbook(<String, String>{'S': xml}));

ChangeSet _edit(XlsxWorkbook book, ReferenceShift edit) =>
    changeLogOf(book).transaction(() {
      referenceRegistryOf(book).apply(edit, edit);
      moveSheetGeometry(book.sheets.single, edit);
    });

String _saved(XlsxWorkbook book) =>
    partText(book.save().bytes, 'xl/worksheets/sheet1.xml');

void main() {
  test('columns split and shift', () {
    final XlsxWorkbook book = _book(
      _sheet(
        cols:
            '<cols><col min="2" max="4" width="20" customWidth="1"/>'
            '<col min="6" max="6" width="30" customWidth="1" hidden="1"/>'
            '<col min="8" max="9" width="40" customWidth="1"/></cols>',
      ),
    );
    // Inserting 2 at C: B:D grows (the new columns take B's width); F and
    // H:I shift.
    _edit(book, ReferenceShift.insert('S', ShiftAxis.columns, 3, 2));
    expect(
      _saved(book),
      contains(
        '<cols><col min="2" max="6" width="20" customWidth="1"/>'
        '<col min="8" max="8" width="30" customWidth="1" hidden="1"/>'
        '<col min="10" max="11" width="40" customWidth="1"/></cols>',
      ),
    );
    // Inserting at H: the hidden column shifts to I; the new H takes G's
    // format, and G has none.
    _edit(book, ReferenceShift.insert('S', ShiftAxis.columns, 8, 1));
    expect(
      _saved(book),
      contains(
        '<col min="2" max="6" width="20" customWidth="1"/>'
        '<col min="9" max="9" width="30" customWidth="1" hidden="1"/>'
        '<col min="11" max="12" width="40" customWidth="1"/>',
      ),
    );
    // Deleting C:I: B:F shrinks to B, the hidden column goes, J:L shifts.
    _edit(book, ReferenceShift.delete('S', ShiftAxis.columns, 3, 7));
    expect(
      _saved(book),
      contains(
        '<cols><col min="2" max="2" width="20" customWidth="1"/>'
        '<col min="4" max="5" width="40" customWidth="1"/></cols>',
      ),
    );
  });

  test('the column left of an insert gives its width to the new ones', () {
    final XlsxWorkbook book = _book(
      _sheet(
        cols:
            '<cols><col min="1" max="1" width="9" customWidth="1" '
            'hidden="1"/><col min="2" max="2" width="20" customWidth="1"/>'
            '</cols>',
      ),
    );
    _edit(book, ReferenceShift.insert('S', ShiftAxis.columns, 2, 2));
    expect(
      _saved(book),
      contains(
        '<cols><col min="1" max="1" width="9" customWidth="1" hidden="1"/>'
        '<col min="2" max="3" width="9" customWidth="1"/>'
        '<col min="4" max="4" width="20" customWidth="1"/></cols>',
      ),
    );
  });

  test('frozen pane grows', () {
    final XlsxWorkbook book = _book(
      _sheet(
        views:
            '<sheetViews><sheetView workbookViewId="0">'
            '<pane xSplit="1" ySplit="2" topLeftCell="B3" '
            'activePane="bottomRight" state="frozen"/>'
            '<selection pane="bottomRight" activeCell="C5" sqref="C5"/>'
            '</sheetView></sheetViews>',
      ),
    );
    final XlsxSheet sheet = book.sheets.single;
    _edit(book, ReferenceShift.insert('S', ShiftAxis.rows, 2, 3));
    expect(sheet.view.pane, const XlsxPane.frozen(rows: 5, columns: 1));
    expect(
      _saved(book),
      contains(
        '<pane xSplit="1" ySplit="5" topLeftCell="B6" '
        'activePane="bottomRight" state="frozen"/>'
        '<selection pane="bottomRight" activeCell="C8" sqref="C8"/>',
      ),
    );
    // Rows inserted below the split leave it.
    _edit(book, ReferenceShift.insert('S', ShiftAxis.rows, 7, 1));
    expect(sheet.view.pane, const XlsxPane.frozen(rows: 5, columns: 1));
    // Deleting frozen rows shrinks it; columns follow the same rule.
    _edit(book, ReferenceShift.delete('S', ShiftAxis.rows, 1, 2));
    _edit(book, ReferenceShift.insert('S', ShiftAxis.columns, 1, 1));
    expect(sheet.view.pane, const XlsxPane.frozen(rows: 3, columns: 2));
    expect(_saved(book), contains('topLeftCell="C4"'));
  });

  test('selection follows', () {
    final XlsxWorkbook book = _book(
      _sheet(
        views:
            '<sheetViews><sheetView workbookViewId="0">'
            '<selection activeCell="B4" sqref="B4:C6 E10 A2"/>'
            '</sheetView></sheetViews>',
      ),
    );
    _edit(book, ReferenceShift.insert('S', ShiftAxis.rows, 5, 2));
    expect(
      _saved(book),
      contains('<selection activeCell="B4" sqref="B4:C8 E12 A2"/>'),
    );
    // A deleted active cell moves to the row after the deletion; ranges
    // wholly deleted go.
    _edit(book, ReferenceShift.delete('S', ShiftAxis.rows, 2, 3));
    expect(
      _saved(book),
      contains('<selection activeCell="B2" sqref="B2:C5 E9"/>'),
    );
    _edit(book, ReferenceShift.delete('S', ShiftAxis.columns, 1, 5));
    expect(_saved(book), contains('<selection activeCell="A2" sqref="A2"/>'));
  });

  test('merges shift, grow, shrink and vanish', () {
    final XlsxWorkbook book = _book(
      _sheet(
        merges:
            '<mergeCells count="4"><mergeCell ref="A1:B1"/>'
            '<mergeCell ref="A3:A6"/><mergeCell ref="C8:D9"/>'
            '<mergeCell ref="E2:E3"/></mergeCells>',
      ),
    );
    final XlsxSheet sheet = book.sheets.single;
    // Insert 2 rows at 4: A3:A6 grows, C8:D9 shifts, the others stay.
    _edit(book, ReferenceShift.insert('S', ShiftAxis.rows, 4, 2));
    expect(sheet.merges.map((XlsxRange r) => r.ref), <String>[
      'A1:B1',
      'A3:A8',
      'C10:D11',
      'E2:E3',
    ]);
    // Delete rows 3 to 7: A3:A8 shrinks to A3, so it is no merge any more;
    // E2:E3 shrinks to one cell too.
    _edit(book, ReferenceShift.delete('S', ShiftAxis.rows, 7, 2));
    expect(sheet.merges.map((XlsxRange r) => r.ref), <String>[
      'A1:B1',
      'A3:A6',
      'C8:D9',
      'E2:E3',
    ]);
    _edit(book, ReferenceShift.delete('S', ShiftAxis.rows, 8, 2));
    expect(sheet.merges.map((XlsxRange r) => r.ref), <String>[
      'A1:B1',
      'A3:A6',
      'E2:E3',
    ]);
    _edit(book, ReferenceShift.delete('S', ShiftAxis.columns, 2, 1));
    expect(sheet.merges.map((XlsxRange r) => r.ref), <String>[
      'A3:A6',
      'D2:D3',
    ]);
    expect(_saved(book), contains('<mergeCells count="2">'));
  });
}
