import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xlsx/formula/reference_shift.dart';
import 'package:jet_office/src/xlsx/model/cell_store.dart';
import 'package:jet_office/src/xlsx/model/xlsx_sheet.dart';
import 'package:jet_office/src/xlsx/model/xlsx_workbook.dart';
import 'package:jet_office/src/xlsx/raw_cell.dart';
import 'package:test/test.dart';

import '../read/support/workbook_builder.dart';

XlsxWorkbook _book(Map<String, String> sheets) => XlsxWorkbook.open(
  buildWorkbook(<String, String>{
    for (final MapEntry<String, String> e in sheets.entries)
      e.key: worksheet(e.value),
  }),
);

CellStore _store(XlsxSheet sheet) {
  sheet.rows.toList();
  return cellStoreOf(sheet)!;
}

RawFormula? _f(XlsxSheet sheet, int row, int column) =>
    _store(sheet).cellAt(row, column)?.formula;

String? _attr(RawFormula f, String name) {
  for (final KeptAttribute a in f.attributes) {
    if (a.qualifiedName == name) return a.value;
  }
  return null;
}

void _apply(XlsxWorkbook book, ReferenceShift edit) =>
    referenceRegistryOf(book).apply(edit, edit);

ReferenceShift _insertRows(String sheet, int at, int n) =>
    ReferenceShift.insert(sheet, ShiftAxis.rows, at, n);

ReferenceShift _deleteRows(String sheet, int at, int n) =>
    ReferenceShift.delete(sheet, ShiftAxis.rows, at, n);

const String _shared =
    '<row r="1"><c r="A1"><f t="shared" ref="A1:A3" si="0">B1*2</f>'
    '<v>2</v></c><c r="D1"><f>SUM(B1:B3)</f><v>6</v></c></row>'
    '<row r="2"><c r="A2"><f t="shared" si="0"/><v>4</v></c></row>'
    '<row r="3"><c r="A3"><f t="shared" si="0"/><v>6</v></c></row>';

void main() {
  test('a formula on another sheet pointing here shifts', () {
    final XlsxWorkbook book = _book(<String, String>{
      'Data':
          '<row r="1"><c r="B1"><f>A5</f><v>1</v></c>'
          '<c r="C1"><f>SUM( A1 , A2 )</f><v>1</v></c></row>',
      'Calc':
          '<row r="1"><c r="A1"><f>SUM(Data!A1:A5)+B3</f><v>1</v></c></row>',
    });
    final XlsxSheet data = book.sheets[0];
    final XlsxSheet calc = book.sheets[1];
    _apply(book, _insertRows('Data', 3, 2));
    expect(_f(data, 0, 1)?.text, 'A7');
    expect(_f(data, 0, 2)?.text, 'SUM( A1 , A2 )');
    expect(_f(calc, 0, 0)?.text, 'SUM(Data!A1:A7)+B3');
    expect(_store(data).cellAt(0, 1)?.value, '1');
  });

  test('an untouched formula records no change', () {
    final XlsxWorkbook book = _book(<String, String>{
      'S': '<row r="1"><c r="A1"><f>B1+1</f><v>1</v></c></row>',
    });
    _apply(book, _insertRows('S', 5, 1));
    expect(changeLogOf(book).hasChanges, isFalse);
  });

  test("a shared group's ref and master shift", () {
    final XlsxWorkbook book = _book(<String, String>{'S': _shared});
    final XlsxSheet sheet = book.sheets.single;
    _apply(book, _insertRows('S', 1, 1));
    final RawFormula master = _f(sheet, 0, 0)!;
    expect(master.type, FormulaType.shared);
    expect(master.text, 'B2*2');
    expect(master.ref, 'A2:A4');
    expect(master.si, '0');
    expect(_f(sheet, 1, 0)?.text, isNull);
    expect(_f(sheet, 0, 3)?.text, 'SUM(B2:B4)');
  });

  test('an insert through a shared group grows its ref', () {
    final XlsxWorkbook book = _book(<String, String>{'S': _shared});
    final XlsxSheet sheet = book.sheets.single;
    _apply(book, _insertRows('S', 2, 1));
    expect(_f(sheet, 0, 0)?.text, 'B1*2');
    expect(_f(sheet, 0, 0)?.ref, 'A1:A4');
    expect(_f(sheet, 1, 0)?.ref, isNull);
  });

  test('deleting the master promotes the next follower with translated '
      'text', () {
    final XlsxWorkbook book = _book(<String, String>{'S': _shared});
    final XlsxSheet sheet = book.sheets.single;
    _apply(book, _deleteRows('S', 1, 1));
    // The follower at A2 (A1 once the rows move) becomes the master.
    final RawFormula promoted = _f(sheet, 1, 0)!;
    expect(promoted.type, FormulaType.shared);
    expect(promoted.text, 'B1*2');
    expect(promoted.ref, 'A1:A2');
    expect(promoted.si, '0');
    expect(_store(sheet).cellAt(1, 0)?.value, '4');
    expect(_f(sheet, 2, 0)?.text, isNull);
    expect(_f(sheet, 2, 0)?.si, '0');
  });

  test('a group whose followers would translate wrongly is unshared', () {
    // A5 is above the insert, A6 below it: the follower at B6 reads A2,
    // which moves; the master's A1 does not.
    final XlsxWorkbook book = _book(<String, String>{
      'S':
          '<row r="5"><c r="B5"><f t="shared" ref="B5:B6" si="3">A1</f>'
          '<v>1</v></c></row>'
          '<row r="6"><c r="B6"><f t="shared" si="3"/><v>2</v></c></row>',
    });
    final XlsxSheet sheet = book.sheets.single;
    _apply(book, _insertRows('S', 2, 1));
    expect(_f(sheet, 4, 1)?.type, FormulaType.normal);
    expect(_f(sheet, 4, 1)?.text, 'A1');
    expect(_f(sheet, 4, 1)?.ref, isNull);
    expect(_f(sheet, 5, 1)?.type, FormulaType.normal);
    expect(_f(sheet, 5, 1)?.text, 'A3');
    expect(_store(sheet).cellAt(5, 1)?.value, '2');
  });

  test('array formula ref shifts; partial delete refuses, nothing '
      'changed', () {
    final XlsxWorkbook book = _book(<String, String>{
      'S':
          '<row r="1"><c r="C1"><f t="array" ref="C1:C2">B1:B2*2</f>'
          '<v>1</v></c><c r="E1"><f>B1</f><v>1</v></c></row>'
          '<row r="2"><c r="C2"><v>2</v></c></row>',
    });
    final XlsxSheet sheet = book.sheets.single;
    for (final ReferenceShift edit in <ReferenceShift>[
      _deleteRows('S', 2, 1),
      _deleteRows('S', 1, 1),
      _insertRows('S', 2, 1),
    ]) {
      expect(
        () => _apply(book, edit),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('C1:C2'),
          ),
        ),
      );
      expect(changeLogOf(book).hasChanges, isFalse);
      expect(_f(sheet, 0, 2)?.ref, 'C1:C2');
      expect(_f(sheet, 0, 4)?.text, 'B1');
    }
    // Below the array, and the whole array: no refusal.
    _apply(book, _insertRows('S', 3, 1));
    expect(_f(sheet, 0, 2)?.ref, 'C1:C2');
    _apply(book, _insertRows('S', 1, 1));
    expect(_f(sheet, 0, 2)?.ref, 'C2:C3');
    expect(_f(sheet, 0, 2)?.text, 'B2:B3*2');
    _apply(book, ReferenceShift.insert('S', ShiftAxis.columns, 1, 1));
    expect(_f(sheet, 0, 2)?.ref, 'D2:D3');
    expect(_f(sheet, 0, 2)?.text, 'C2:C3*2');
  });

  test('data table r1 r2 shift', () {
    final XlsxWorkbook book = _book(<String, String>{
      'S':
          '<row r="2"><c r="B2"><f t="dataTable" ref="B2:C3" dt2D="1" '
          'dtr="1" r1="A1" r2="A2"/><v>1</v></c></row>',
    });
    final XlsxSheet sheet = book.sheets.single;
    _apply(book, _insertRows('S', 1, 1));
    final RawFormula f = _f(sheet, 1, 1)!;
    expect(f.type, FormulaType.dataTable);
    expect(f.ref, 'B3:C4');
    expect(_attr(f, 'r1'), 'A2');
    expect(_attr(f, 'r2'), 'A3');
    expect(_attr(f, 'dt2D'), '1');
  });

  test('an unlexable formula stays and warns formulaUnlexable once', () {
    final XlsxWorkbook book = _book(<String, String>{
      'S':
          '<row r="1"><c r="A1"><f t="shared" ref="A1:A3" si="0">B5+"x</f>'
          '<v>1</v></c><c r="B1"><f>A5+"abc</f><v>1</v></c></row>'
          '<row r="2"><c r="A2"><f t="shared" si="0"/><v>1</v></c></row>'
          '<row r="3"><c r="A3"><f t="shared" si="0"/><v>1</v></c></row>',
    });
    final XlsxSheet sheet = book.sheets.single;
    _apply(book, _insertRows('S', 1, 1));
    expect(_f(sheet, 0, 1)?.text, 'A5+"abc');
    expect(_f(sheet, 0, 0)?.text, 'B5+"x');
    final List<XlsxWarning> warnings = book.warnings
        .where((XlsxWarning w) => w.code == XlsxWarningCode.formulaUnlexable)
        .toList();
    expect(warnings, hasLength(1));
    expect(warnings.single.count, 2);
    expect(warnings.single.cells, <String>['A1', 'B1']);
  });

  test('deleting an unlexable shared master refuses, nothing changed', () {
    final XlsxWorkbook book = _book(<String, String>{
      'S':
          '<row r="1"><c r="A1"><f t="shared" ref="A1:A2" si="0">B5+"x</f>'
          '<v>1</v></c><c r="C1"><f>A9</f><v>1</v></c></row>'
          '<row r="2"><c r="A2"><f t="shared" si="0"/><v>1</v></c></row>',
    });
    final XlsxSheet sheet = book.sheets.single;
    expect(
      () => _apply(book, _deleteRows('S', 1, 1)),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('A1'),
        ),
      ),
    );
    expect(changeLogOf(book).hasChanges, isFalse);
    expect(_f(sheet, 0, 2)?.text, 'A9');
  });

  test('a shared master with an unreadable ref refuses when followed', () {
    final XlsxWorkbook followed = _book(<String, String>{
      'S':
          '<row r="1"><c r="A1"><f t="shared" ref="bad" si="0">B1</f>'
          '<v>1</v></c></row>'
          '<row r="2"><c r="A2"><f t="shared" si="0"/><v>1</v></c></row>',
    });
    expect(
      () => _apply(followed, _insertRows('S', 1, 1)),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('A1'),
        ),
      ),
    );
    expect(changeLogOf(followed).hasChanges, isFalse);
    final XlsxWorkbook alone = _book(<String, String>{
      'S':
          '<row r="1"><c r="A1"><f t="shared" ref="bad" si="0">B1</f>'
          '<v>1</v></c><c r="C1"><f>B1</f><v>1</v></c></row>',
    });
    _apply(alone, _insertRows('S', 1, 1));
    expect(_f(alone.sheets.single, 0, 2)?.text, 'B2');
  });
}
