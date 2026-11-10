/// Writes the workbooks the owner opens in the W5 Excel check (structural
/// editing), to a directory that is created.
///
/// ```bash
/// dart run tool/write_w5_check.dart build/w5
/// ```
///
/// - `w5_generated.xlsx`: the workbook of `tool/write_model_sample.dart`,
///   made and then edited structurally.
/// - `w5_rows.xlsx`: two rows inserted at row 3 of `Data` (under values, a
///   formula, a rule, a validation and a 30-point bold row 2), row 4 of `Del`
///   deleted, two rows inserted directly below the table of `Table`, and the
///   table of `Convert` removed, which turns its `[@Qty]` uses into ranges.
///   The sheet `Checks` holds each case as a formula, the value Excel should
///   compute, the formula expected and an empty column `Excel?` for the
///   owner.
/// - `w5_charts.xlsx`: the fixture `c1_kinds` with a row inserted inside the
///   chart data.
/// - `w5_rename.xlsx`: sheets renamed to names that need quotes (`Q1 Sales`,
///   `2026`), one moved first, and an insert and a rename undone; `Checks` as
///   above.
/// - `w5_chart_reference.xlsx`: the owner's `chart_reference.xlsx` with a row
///   inserted in the data of `Veri`, renamed `Veri Yeni`.
/// - `w5_objects.xlsx`: the producer file `excel_objects` (a table, notes, a
///   threaded comment, a picture, a chart and a control as Excel writes them;
///   no owner file has tables and notes) with a row inserted at row 2 and its
///   sheet renamed `Nesneler`.
///
/// The steps are in `docs/superpowers/plans/2026-11-10-phase-3-w5-excel-check.md`
/// (Turkish); the results go in `docs/excel-checks.md`, "W5", from the owner
/// only. Exit code 2 on unusable arguments.
///
/// Not ported from Quds; written for jet_office.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

import '../test/fixtures/c1_fixtures.dart';
import '../test/fixtures/fixture.dart';
import '../test/xlsx/read/support/producers.dart';
import 'write_model_sample.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/write_w5_check.dart <outDir>');
    exitCode = 2;
    return;
  }
  writeW5Check(args.single).forEach(stdout.writeln);
}

/// Writes the W5 check's workbooks to [dir] and returns their paths.
List<String> writeW5Check(String dir) => <String>[
  _write('$dir/w5_generated.xlsx', structureBook()),
  _write('$dir/w5_rows.xlsx', _rowsBook()),
  _write('$dir/w5_charts.xlsx', _chartsBook()),
  _write('$dir/w5_rename.xlsx', _renameBook()),
  _write('$dir/w5_chart_reference.xlsx', _chartReferenceBook()),
  _write('$dir/w5_objects.xlsx', _objectsBook()),
];

String _write(String path, XlsxWorkbook book) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(book.save().bytes);
  return path;
}

/// One row of a `Checks` sheet: the case, its formula as written before the
/// edit, the value and the formula expected after it.
typedef _Check = (String, String, Object, String);

/// Writes [checks] to [sheet] under a header, with an empty `Excel?` column.
void _writeChecks(XlsxSheet sheet, List<_Check> checks) {
  const List<String> header = <String>[
    'Case',
    'Formula',
    'Expected value',
    'Expected formula',
    'Excel?',
  ];
  for (int c = 0; c < header.length; c++) {
    sheet.setCell(0, c, header[c]);
  }
  for (int i = 0; i < checks.length; i++) {
    final (String name, String formula, Object value, String expected) =
        checks[i];
    sheet
      ..setCell(i + 1, 0, name)
      ..setCell(i + 1, 1, XlsxFormula(formula))
      ..setCell(i + 1, 2, value)
      ..setCell(i + 1, 3, '=$expected');
  }
}

XlsxWorkbook _rowsBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet data = book.addSheet('Data');
  final XlsxSheet other = book.addSheet('Other');
  final XlsxSheet del = book.addSheet('Del');
  final XlsxSheet table = book.addSheet('Table');
  final XlsxSheet convert = book.addSheet('Convert');
  final XlsxSheet checks = book.addSheet('Checks');
  for (int r = 0; r < 10; r++) {
    data.setCell(r, 0, r + 1);
    del.setCell(r, 0, r + 1);
  }
  data
    ..setCell(0, 2, const XlsxFormula('A5*2'))
    ..setRowFormat(
      1,
      const XlsxRowFormat(
        height: 30,
        style: XlsxStyle(font: XlsxFont(bold: true)),
      ),
    )
    ..addDataValidation(
      XlsxDataValidation(
        <XlsxRange>[XlsxRange.parse('A1:A10')],
        XlsxValidationType.whole,
        comparison: XlsxComparison.greaterThanOrEqual,
        formula1: '0',
      ),
    )
    ..addConditionalFormat(
      XlsxConditionalFormat(
        <XlsxRange>[XlsxRange.parse('A1:A10')],
        <XlsxConditionalRule>[
          const XlsxCellValueRule(
            XlsxComparison.greaterThan,
            r'$C$1',
            style: XlsxStyle(fill: XlsxFill.solid(XlsxColor.rgb(0xFFC7CE))),
          ),
        ],
      ),
    );
  other.setCell(4, 0, 1000);
  table
    ..setCell(0, 0, 'Item')
    ..setCell(0, 1, 'Qty')
    ..setCell(1, 0, 'Bolt')
    ..setCell(1, 1, 10)
    ..setCell(2, 0, 'Nut')
    ..setCell(2, 1, 25)
    ..addTable(
      XlsxTable('Tbl', const XlsxRange(0, 0, 2, 1), <XlsxTableColumn>[
        const XlsxTableColumn('Item'),
        const XlsxTableColumn('Qty'),
      ]),
    )
    ..setCell(5, 0, 'Below');
  convert
    ..setCell(0, 0, 'Item')
    ..setCell(0, 1, 'Qty')
    ..setCell(0, 2, 'Double')
    ..setCell(0, 4, 'Formula')
    ..setCell(0, 5, 'Expected value')
    ..setCell(0, 6, 'Expected formula')
    ..setCell(0, 7, 'Excel?');
  const List<(String, int)> items = <(String, int)>[('Bolt', 10), ('Nut', 25)];
  for (int i = 0; i < items.length; i++) {
    convert
      ..setCell(i + 1, 0, items[i].$1)
      ..setCell(i + 1, 1, items[i].$2)
      ..setCell(i + 1, 2, const XlsxFormula('Conv[[#This Row],[Qty]]*2'));
  }
  convert.addTable(
    XlsxTable('Conv', const XlsxRange(0, 0, 2, 2), <XlsxTableColumn>[
      const XlsxTableColumn('Item'),
      const XlsxTableColumn('Qty'),
      const XlsxTableColumn('Double'),
    ]),
  );
  // Column E: [@Qty] from beside the table, on a data row and outside them.
  convert
    ..setCell(1, 4, const XlsxFormula('Conv[[#This Row],[Qty]]'))
    ..setCell(1, 5, 10)
    ..setCell(1, 6, r'=$B2')
    ..setCell(4, 0, 'Outside')
    ..setCell(4, 4, const XlsxFormula('Conv[[#This Row],[Qty]]'))
    ..setCell(4, 5, '#VALUE!')
    ..setCell(4, 6, r'=$A2:$C3')
    ..setCell(5, 0, 'Sum')
    ..setCell(5, 4, const XlsxFormula('SUM(Conv[Double])'))
    ..setCell(5, 5, 70)
    ..setCell(5, 6, r'=SUM($C$2:$C$3)');
  _writeChecks(checks, const <_Check>[
    ('Cell below the insert', 'Data!A5', 5, 'Data!A7'),
    ('Range across the insert', 'SUM(Data!A1:A10)', 55, 'SUM(Data!A1:A12)'),
    (
      'Range to the last row',
      r'SUM(Data!A5:A1048576)',
      45,
      r'SUM(Data!A7:A1048576)',
    ),
    ('Whole column', 'SUM(Data!A:A)', 55, 'SUM(Data!A:A)'),
    ('3D reference', 'SUM(Data:Other!A5)', 1003, 'SUM(Data:Other!A5)'),
    ('Formula on the edited sheet', 'Data!C1', 10, 'Data!C1'),
    ('Deleted cell', 'Del!A4', '#REF!', 'Del!#REF!'),
    ('Range over the deleted row', 'SUM(Del!A1:A10)', 51, 'SUM(Del!A1:A9)'),
    ('Table below the insert', 'SUM(Tbl[Qty])', 35, 'SUM(Tbl[Qty])'),
    ('Cell below the table', 'Table!A6', 'Below', 'Table!A8'),
  ]);
  data.insertRows(2, 2);
  del.deleteRows(3);
  table.insertRows(3, 2);
  convert.removeTable('Conv');
  return book;
}

XlsxWorkbook _chartsBook() {
  final Fixture kinds = c1Fixtures().firstWhere(
    (Fixture f) => f.name == 'c1_kinds',
  );
  final XlsxWorkbook book = XlsxWorkbook.open(kinds.build());
  book.sheet('Data').insertRows(2);
  return book;
}

XlsxWorkbook _renameBook() {
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet data = book.addSheet('Data');
  final XlsxSheet other = book.addSheet('Other');
  final XlsxSheet keep = book.addSheet('Keep');
  final XlsxSheet checks = book.addSheet('Checks');
  data.setCell(0, 0, 5);
  other.setCell(0, 0, 7);
  keep
    ..setCell(0, 0, 1)
    ..setCell(1, 0, 2);
  _writeChecks(checks, const <_Check>[
    ('Renamed with a space', 'Data!A1', 5, "'Q1 Sales'!A1"),
    ('Renamed to digits', 'Other!A1', 7, "'2026'!A1"),
    ('Both', 'Data!A1+Other!A1', 12, "'Q1 Sales'!A1+'2026'!A1"),
    ('Undone insert and rename', 'Keep!A2', 2, 'Keep!A2'),
  ]);
  book
    ..renameSheet(data, 'Q1 Sales')
    ..renameSheet(other, '2026')
    ..moveSheet(other, 0);
  final XlsxChangeSet undone = book.transaction(() {
    keep.insertRows(0, 3);
    book.renameSheet(keep, 'Undone');
  });
  book.undo(undone);
  return book;
}

XlsxWorkbook _chartReferenceBook() {
  final XlsxWorkbook book = XlsxWorkbook.open(
    Uint8List.fromList(
      File('test/fixtures/owner/charts/chart_reference.xlsx').readAsBytesSync(),
    ),
  );
  final XlsxSheet sheet = book.sheets.first;
  sheet.insertRows(2);
  book.renameSheet(sheet, 'Veri Yeni');
  return book;
}

XlsxWorkbook _objectsBook() {
  final XlsxWorkbook book = XlsxWorkbook.open(excelObjectsFile().bytes);
  final XlsxSheet sheet = book.sheets.first;
  sheet.insertRows(1);
  book.renameSheet(sheet, 'Nesneler');
  return book;
}
