import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xlsx/formula/reference_shift.dart';
import 'package:jet_office/src/xlsx/model/cell_store.dart';
import 'package:jet_office/src/xlsx/model/xlsx_sheet.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:jet_office/src/xlsx/raw_cell.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../../fixtures/fixtures.dart';
import '../read/support/workbook_builder.dart';

CellStore _store(XlsxSheet sheet) {
  sheet.rows.toList();
  return cellStoreOf(sheet)!;
}

/// Runs [edit] as a structural edit does: the holders on the positions
/// before it, then the cells and the sheet's geometry, in one transaction.
ChangeSet _edit(XlsxWorkbook book, ReferenceShift edit) =>
    changeLogOf(book).transaction(() {
      referenceRegistryOf(book).apply(edit, edit);
      moveSheetGeometry(
        book.sheets.firstWhere((XlsxSheet s) => s.name == edit.sheet),
        edit,
      );
    });

String? _attr(List<KeptAttribute> attributes, String name) {
  for (final KeptAttribute a in attributes) {
    if (a.qualifiedName == name) return a.value;
  }
  return null;
}

List<int> _rows(CellStore store) => store.rowIndexes.toList();

void main() {
  test('inserting 3 rows at 2 moves every cell and row format', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet(
          '<row r="1"><c r="A1"><v>1</v></c></row>'
          '<row r="2" ht="30" customHeight="1"><c r="A2"><v>2</v></c>'
          '<c r="C2" t="str"><f>A2*2</f><v>4</v></c></row>'
          '<row r="3" hidden="1"><c r="B3"><v>3</v></c></row>',
        ),
      }),
    );
    final XlsxSheet sheet = book.sheets.single;
    final CellStore store = _store(sheet);
    _edit(book, ReferenceShift.insert('S', ShiftAxis.rows, 2, 3));
    expect(_rows(store), <int>[0, 4, 5]);
    expect(store.cellAt(0, 0)?.value, '1');
    expect(store.cellAt(4, 0)?.value, '2');
    expect(store.cellAt(4, 2)?.formula?.text, 'A5*2');
    expect(store.cellAt(5, 1)?.value, '3');
    expect(store.cellAt(1, 0), isNull);
    expect(_attr(store.rowAttributes(4), 'ht'), '30');
    expect(_attr(store.rowAttributes(5), 'hidden'), '1');
    expect(store.rowAttributes(1), isEmpty);
    expect(store.cellCount, 4);
  });

  test('deleting drops the rows\' cells and strings stay in the table '
      'unused', () {
    final Uint8List input = buildWorkbook(
      <String, String>{
        'S': worksheet(
          '<row r="1"><c r="A1" t="s"><v>0</v></c></row>'
          '<row r="2" ht="20" customHeight="1"><c r="A2" t="s"><v>1</v></c>'
          '</row>'
          '<row r="3"><c r="A3"><v>3</v></c></row>'
          '<row r="4"><c r="A4" t="s"><v>2</v></c></row>',
        ),
      },
      sharedStrings:
          '<sst xmlns="$mainNs" count="3" uniqueCount="3"><si><t>one</t></si>'
          '<si><t>two</t></si><si><t>four</t></si></sst>',
    );
    final XlsxWorkbook book = XlsxWorkbook.open(input);
    final XlsxSheet sheet = book.sheets.single;
    final CellStore store = _store(sheet);
    _edit(book, ReferenceShift.delete('S', ShiftAxis.rows, 2, 2));
    expect(_rows(store), <int>[0, 1]);
    expect(store.cellAt(1, 0)?.value, '2');
    expect(store.rowAttributes(1), isEmpty);
    expect(store.cellCount, 2);
    final Uint8List output = book.save().bytes;
    expect(comparePackages(input, output, ignoreBookkeeping: true), <String>[
      'xl/worksheets/sheet1.xml: /worksheet/sheetData: 4 children vs 2',
      // The table keeps every string; only its count of uses changes.
      'xl/sharedStrings.xml: /sst: attribute count "3" vs "2"',
    ]);
    final XlsxWorkbook reopened = XlsxWorkbook.open(output);
    expect(reopened.sheets.single.rows.map((XlsxReadRow r) => r.index), <int>[
      0,
      1,
    ]);
    expect(reopened.sheets.single.cellAt(1, 0)?.value, 'four');
  });

  test('inserted rows copy the format above', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet(
          '<row r="1" s="3" customFormat="1" ht="25" customHeight="1" '
          'hidden="1"><c r="A1"><v>1</v></c></row>'
          '<row r="2"><c r="A2"><v>2</v></c></row>',
        ),
      }),
    );
    final CellStore store = _store(book.sheets.single);
    _edit(book, ReferenceShift.insert('S', ShiftAxis.rows, 2, 2));
    for (final int row in <int>[1, 2]) {
      final List<KeptAttribute> a = store.rowAttributes(row);
      expect(_attr(a, 's'), '3', reason: '$row');
      expect(_attr(a, 'customFormat'), '1');
      expect(_attr(a, 'ht'), '25');
      expect(_attr(a, 'hidden'), isNull);
      expect(store.cellAt(row, 0), isNull);
    }
    expect(store.cellAt(3, 0)?.value, '2');
    expect(store.rowAttributes(3), isEmpty);
  });

  test('columns move inside every row; deleted ones drop', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet(
          '<row r="1"><c r="A1"><v>1</v></c><c r="B1"><v>2</v></c>'
          '<c r="D1"><v>4</v></c></row>'
          '<row r="2"><c r="B2"><v>5</v></c></row>'
          '<row r="3"><c r="C3"><v>6</v></c></row>',
        ),
      }),
    );
    final CellStore store = _store(book.sheets.single);
    _edit(book, ReferenceShift.delete('S', ShiftAxis.columns, 2, 1));
    expect(store.cellAt(0, 0)?.value, '1');
    expect(store.cellAt(0, 2)?.value, '4');
    expect(store.cellAt(0, 1), isNull);
    expect(store.cellAt(2, 1)?.value, '6');
    expect(_rows(store), <int>[0, 2]);
    _edit(book, ReferenceShift.insert('S', ShiftAxis.columns, 1, 2));
    expect(store.cellAt(0, 2)?.value, '1');
    expect(store.cellAt(0, 4)?.value, '4');
    expect(store.cellAt(2, 3)?.value, '6');
    expect(store.cellCount, 3);
  });

  test('an insert that pushes a cell off the sheet throws, nothing '
      'changed', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet(
          '<row r="1"><c r="A1"><v>1</v></c></row>'
          '<row r="1048575"><c r="A1048575"><v>2</v></c></row>',
        ),
      }),
    );
    final CellStore store = _store(book.sheets.single);
    expect(
      () => _edit(book, ReferenceShift.insert('S', ShiftAxis.rows, 1, 2)),
      throwsStateError,
    );
    expect(_rows(store), <int>[0, XlsxLimits.maxRows - 2]);
    expect(changeLogOf(book).hasChanges, isFalse);
  });

  test('undoing a move restores every byte', () {
    for (final Fixture f in allFixtures()) {
      final Uint8List input = f.build();
      final XlsxWorkbook book = XlsxWorkbook.open(input);
      final Uint8List before = book.save().bytes;
      for (final ReferenceShift edit in <ReferenceShift>[
        ReferenceShift.insert(book.sheets.first.name, ShiftAxis.rows, 2, 3),
        ReferenceShift.delete(book.sheets.first.name, ShiftAxis.rows, 1, 2),
        ReferenceShift.insert(book.sheets.first.name, ShiftAxis.columns, 1, 1),
        ReferenceShift.delete(book.sheets.first.name, ShiftAxis.columns, 2, 1),
      ]) {
        final ChangeSet set;
        try {
          set = _edit(book, edit);
        } on StateError {
          continue; // An array or table Excel refuses to cut.
        }
        changeLogOf(book).revertSet(set);
        expect(
          comparePackages(before, book.save().bytes, ignoreBookkeeping: true),
          isEmpty,
          reason: '${f.name} ${edit.axis} ${edit.count}',
        );
        changeLogOf(book).reapplySet(set);
        changeLogOf(book).revertSet(set);
      }
    }
  });

  test('100,000 rows: insert at 1 is linear', () {
    final StringBuffer rows = StringBuffer();
    for (int r = 1; r <= 100000; r++) {
      rows.write(
        '<row r="$r"><c r="A$r"><v>$r</v></c><c r="B$r"><v>1</v></c>'
        '</row>',
      );
    }
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{'S': worksheet(rows.toString())}),
    );
    final CellStore store = _store(book.sheets.single);
    final Stopwatch watch = Stopwatch()..start();
    final ChangeSet set = changeLogOf(book).transaction(
      () => moveSheetGeometry(
        book.sheets.single,
        ReferenceShift.insert('S', ShiftAxis.rows, 1, 1),
      ),
    );
    watch.stop();
    // ignore: avoid_print
    print('insert at row 1 of 100,000 rows: ${watch.elapsedMilliseconds} ms');
    expect(set.changes, hasLength(1));
    expect(store.cellAt(0, 0), isNull);
    expect(store.cellAt(100000, 0)?.value, '100000');
    expect(store.cellCount, 200000);
  });

  test('a shift that misses keeps every byte', () {
    for (final Fixture f in allFixtures()) {
      final XlsxWorkbook book = XlsxWorkbook.open(f.build());
      final Uint8List before = book.save().bytes;
      for (final XlsxSheet sheet in book.sheets) {
        if (!sheetIsWorksheet(sheet)) continue;
        // A note on the last row or column (m4_notes) refuses the insert,
        // as Excel does; the refusal changes nothing either.
        for (final ReferenceShift edit in <ReferenceShift>[
          ReferenceShift.insert(sheet.name, ShiftAxis.rows, 1048000, 3),
          ReferenceShift.insert(sheet.name, ShiftAxis.columns, 16000, 2),
        ]) {
          try {
            _edit(book, edit);
          } on StateError {
            expect(f.name, 'm4_notes');
          }
        }
      }
      expect(
        comparePackages(before, book.save().bytes, ignoreBookkeeping: true),
        isEmpty,
        reason: f.name,
      );
    }
  });

  test('a store move is one change whatever it moves', () {
    final XlsxWorkbook book = XlsxWorkbook.open(
      buildWorkbook(<String, String>{
        'S': worksheet('<row r="2"><c r="A2"><v>1</v></c></row>'),
      }),
    );
    final CellStore store = _store(book.sheets.single);
    final ChangeSet set = changeLogOf(book).transaction(
      () => moveSheetGeometry(
        book.sheets.single,
        ReferenceShift.delete('S', ShiftAxis.rows, 1, 1),
      ),
    );
    expect(set.changes, hasLength(1));
    expect(store.cellAt(0, 0), isA<RawCell>());
  });
}
