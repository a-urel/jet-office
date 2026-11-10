import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/xlsx_sheet.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';
import '../read/support/workbook_builder.dart';
import 'support/workbook_support.dart';

/// A workbook of one sheet `S` with a value column, a formula, a name, a
/// merge, a validation, a conditional format, a link and a table, every
/// row-bound feature from row 2 on shifted down by
/// [shift] rows: the input of an insert with [shift] 0, and the result an
/// insert of [shift] rows before row 2 (index 1) must give.
Uint8List _featureBook(int shift) {
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet s = book.addSheet('S');
  int r(int row) => row < 1 ? row : row + shift; // 0-based rows from 1 on
  String a(int row) => '${row + 1}'; // a 0-based row as Excel writes it
  s
    ..setCell(0, 0, 1)
    ..setCell(r(1), 0, 2)
    ..setCell(r(2), 0, 3)
    ..setCell(r(3), 1, XlsxFormula('SUM(A1:A${a(r(2))})', cached: 6))
    ..merge(XlsxRange(r(4), 0, r(4), 1))
    ..setCell(r(5), 0, XlsxHyperlink.url('https://example.com', text: 'x'))
    ..addDataValidation(
      XlsxDataValidation(
        <XlsxRange>[XlsxRange(r(1), 0, r(2), 0)],
        XlsxValidationType.list,
        formula1: '"a,b"',
      ),
    )
    ..addConditionalFormat(
      XlsxConditionalFormat(
        <XlsxRange>[XlsxRange(r(1), 0, r(2), 0)],
        <XlsxConditionalRule>[
          const XlsxCellValueRule(
            XlsxComparison.greaterThan,
            '2',
            style: XlsxStyle(font: XlsxFont(bold: true)),
          ),
        ],
      ),
    )
    ..setCell(0, 3, 'H1')
    ..setCell(0, 4, 'H2')
    ..setCell(r(1), 3, 10)
    ..setCell(r(1), 4, 20)
    ..setCell(r(2), 3, 30)
    ..setCell(r(2), 4, 40)
    ..addTable(
      XlsxTable('T', XlsxRange(0, 3, r(2), 4), const <XlsxTableColumn>[
        XlsxTableColumn('H1'),
        XlsxTableColumn('H2'),
      ]),
    );
  book.defineName(XlsxDefinedName('Rng', 'S!\$A\$${a(r(1))}:\$A\$${a(r(2))}'));
  return book.save().bytes;
}

void main() {
  XlsxSheet sheetOf(String xml) => XlsxWorkbook.open(
    buildWorkbook(<String, String>{'S': xml}),
  ).sheets.single;

  test('arguments throw named', () {
    final XlsxSheet s = sheetOf(
      worksheet('<row r="1"><c r="A1"><v>1</v></c></row>'),
    );
    void named(void Function() f, String name) => expect(
      f,
      throwsA(isA<ArgumentError>().having((e) => e.name, 'name', name)),
    );
    named(() => s.insertRows(-1), 'row');
    named(() => s.deleteRows(-1), 'row');
    named(() => s.insertColumns(-1), 'column');
    named(() => s.deleteColumns(-1), 'column');
    named(() => s.insertRows(1, 0), 'count');
    named(() => s.deleteColumns(1, 0), 'count');
    named(() => s.insertRows(XlsxLimits.maxRows), 'row');
    named(() => s.deleteColumns(XlsxLimits.maxColumns), 'column');
    named(() => s.deleteRows(XlsxLimits.maxRows - 1, 2), 'count');
    named(() => s.insertColumns(1, XlsxLimits.maxColumns), 'count');
    expect(s.cellAt(0, 0)?.value, XlsxDecimal('1'));
  });

  test('cells pushed past the last row throw StateError, nothing changed', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet(
          '<row r="1"><c r="A1"><f>A2</f><v>0</v></c></row>'
          '<row r="1048575"><c r="A1048575"><v>1</v></c></row>',
        ),
      }),
    );
    final Uint8List before = book.save().bytes;
    expect(() => book.sheets.single.insertRows(0, 2), throwsStateError);
    expect(changeLogOf(book).hasChanges, isFalse);
    expect(
      comparePackages(before, book.save().bytes, ignoreBookkeeping: true),
      isEmpty,
    );
  });

  test('a refused edit leaves no warning behind', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet(
          '<row r="1"><c r="A1"><f>A2&amp;"x</f><v>0</v></c></row>'
          '<row r="1048575"><c r="A1048575"><v>1</v></c></row>',
        ),
      }),
    );
    final XlsxSheet s = book.sheets.single..rows.toList();
    final List<XlsxWarning> before = List<XlsxWarning>.of(book.warnings);
    expect(() => s.insertRows(0, 2), throwsStateError);
    expect(book.warnings, before);
    // The same formula warns on an edit that succeeds.
    s.insertRows(0);
    expect(
      book.warnings.map((XlsxWarning w) => w.code),
      contains(XlsxWarningCode.formulaUnlexable),
    );
  });

  test('an inserted table column takes a name no other column has', () {
    final XlsxWorkbook book = XlsxWorkbook();
    book.addSheet('S')
      ..setCell(0, 0, 'Column1')
      ..setCell(0, 1, 'column2')
      ..setCell(1, 0, 1)
      ..setCell(1, 1, 2)
      ..addTable(
        XlsxTable('T', XlsxRange.parse('A1:B2'), const <XlsxTableColumn>[
          XlsxTableColumn('Column1'),
          XlsxTableColumn('column2'),
        ]),
      );
    final XlsxWorkbook opened = XlsxWorkbook.open(book.save().bytes);
    final XlsxSheet t = opened.sheets.single..insertColumns(1);
    expect(t.cellAt(0, 1)?.value, 'Column3');
    expect(t.tables.single.columns.map((XlsxTableColumn c) => c.name), <String>[
      'Column1',
      'Column3',
      'column2',
    ]);
  });

  test('every holder moved together', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_featureBook(0));
    book.sheets.single.insertRows(1, 2);
    expect(
      comparePackages(
        _featureBook(2),
        book.save().bytes,
        ignoreBookkeeping: true,
      ),
      isEmpty,
    );
  });

  test('deleting the inserted rows gives the input back', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_featureBook(2));
    book.sheets.single.deleteRows(1, 2);
    expect(
      comparePackages(
        _featureBook(0),
        book.save().bytes,
        ignoreBookkeeping: true,
      ),
      isEmpty,
    );
  });

  test('a column inserted inside a table takes its header name', () {
    final XlsxWorkbook book = XlsxWorkbook.open(_featureBook(0));
    final XlsxSheet s = book.sheets.single..insertColumns(4);
    expect(s.cellAt(0, 4)?.value, 'Column1');
    expect(s.cellAt(0, 5)?.value, 'H2');
    expect(s.tables.single.range, XlsxRange.parse('D1:F3'));
    expect(s.tables.single.columns.map((XlsxTableColumn c) => c.name), <String>[
      'H1',
      'Column1',
      'H2',
    ]);
    final XlsxReader read = XlsxReader(book.save().bytes);
    expect(read.rowsAt(0).first.cells.map((c) => c.value), contains('Column1'));
    expect(read.warnings, isEmpty);
  });

  test('the calculation chain goes and full calculation is asked', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      packageWith(
        rows:
            '<row r="1"><c r="A1"><v>1</v></c><c r="B1"><f>A1</f><v>1</v></c>'
            '</row>',
        calcChain: true,
      ),
    );
    book.sheets.single.insertColumns(0);
    final Map<String, String> parts = readXlsx(book.save().bytes);
    expect(parts.keys, isNot(contains('xl/calcChain.xml')));
    expect(parts['xl/workbook.xml'], contains('fullCalcOnLoad="1"'));
  });

  test('undo restores bytes on every fixture', () {
    for (final Fixture f in allFixtures()) {
      final XlsxWorkbook book = XlsxWorkbook.open(f.build());
      final Uint8List before = book.save().bytes;
      final XlsxSheet s = book.sheets.first;
      if (!sheetIsWorksheet(s)) continue;
      for (final void Function() edit in <void Function()>[
        () => s.insertRows(1, 3),
        () => s.deleteRows(0, 2),
        () => s.insertColumns(0),
        () => s.deleteColumns(1),
      ]) {
        final ChangeSet set;
        try {
          set = changeLogOf(book).transaction(edit);
        } on StateError {
          continue; // An edit Excel refuses.
        }
        changeLogOf(book).revertSet(set);
        expect(
          comparePackages(before, book.save().bytes, ignoreBookkeeping: true),
          isEmpty,
          reason: f.name,
        );
      }
    }
  });

  test('the result reads back with XlsxReader', () {
    for (final Fixture f in allFixtures()) {
      final XlsxWorkbook book = XlsxWorkbook.open(f.build());
      final XlsxSheet s = book.sheets.first;
      if (!sheetIsWorksheet(s)) continue;
      try {
        s
          ..insertRows(1, 2)
          ..deleteColumns(0);
      } on StateError {
        continue;
      }
      final XlsxReader read = XlsxReader(book.save().bytes);
      for (int i = 0; i < read.sheets.length; i++) {
        read.rowsAt(i).toList();
      }
      expect(read.sheets, isNotEmpty, reason: f.name);
    }
  });
}
