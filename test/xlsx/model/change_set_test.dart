import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/model/change_set.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';

/// A saved workbook of one sheet `S` with values in A1:A3 and a formula.
Uint8List _book() {
  final XlsxWorkbook book = XlsxWorkbook();
  book.addSheet('S')
    ..setCell(0, 0, 1)
    ..setCell(1, 0, 2)
    ..setCell(2, 0, 3)
    ..setCell(3, 0, const XlsxFormula('SUM(A1:A3)', cached: 6));
  book.addSheet('T');
  return book.save().bytes;
}

void main() {
  late XlsxWorkbook book;
  late XlsxSheet s;
  late Uint8List before;
  setUp(() {
    book = XlsxWorkbook.open(_book());
    s = book.sheet('S');
    before = book.save().bytes;
  });

  void expectSame(Uint8List bytes) =>
      expect(comparePackages(before, bytes, ignoreBookkeeping: true), isEmpty);

  test('a transaction collects every edit\'s record', () {
    final XlsxChangeSet set = book.transaction(() {
      s.setCell(4, 1, 'x');
      s.setStyle(4, 1, const XlsxStyle(font: XlsxFont(bold: true)));
      s.merge(const XlsxRange(6, 0, 6, 1));
      book.defineName(const XlsxDefinedName('Rate', 'S!\$A\$1'));
      book.renameSheet(book.sheet('T'), 'U');
      book.moveSheet(book.sheet('U'), 0);
      book.addSheet('V');
    });
    expect(set.isEmpty, isFalse);
    expect(set.changes, <XlsxChange>[
      const XlsxChange(
        XlsxChangeKind.cellsSet,
        sheet: 'S',
        range: XlsxRange(4, 1),
      ),
      const XlsxChange(
        XlsxChangeKind.cellsSet,
        sheet: 'S',
        range: XlsxRange(4, 1),
      ),
      const XlsxChange(
        XlsxChangeKind.featureChanged,
        sheet: 'S',
        range: XlsxRange(6, 0, 6, 1),
      ),
      const XlsxChange(XlsxChangeKind.nameChanged),
      const XlsxChange(XlsxChangeKind.sheetRenamed, sheet: 'U', oldSheet: 'T'),
      const XlsxChange(XlsxChangeKind.sheetMoved, sheet: 'U', index: 0),
      const XlsxChange(XlsxChangeKind.sheetAdded, sheet: 'V', index: 2),
    ]);
    expect(() => set.changes.clear(), throwsUnsupportedError);
  });

  test('a throw reverts and rethrows', () {
    final StateError error = StateError('boom');
    expect(
      () => book.transaction(() {
        s.setCell(5, 0, 'x');
        s.insertRows(0, 2);
        throw error;
      }),
      throwsA(same(error)),
    );
    expectSame(book.save().bytes);
  });

  test('undo of the last set restores bytes', () {
    final XlsxChangeSet set = book.transaction(() {
      s.setCell(0, 0, 10);
      s.insertRows(1);
      book.renameSheet(s, 'R');
    });
    book.undo(set);
    expect(s.name, 'S');
    expectSame(book.save().bytes);
  });

  test('undo out of order throws StateError, nothing changed', () {
    final XlsxChangeSet one = book.transaction(() => s.setCell(0, 0, 10));
    book.transaction(() => s.setCell(0, 0, 20));
    final Uint8List edited = book.save().bytes;
    expect(() => book.undo(one), throwsStateError);
    expect(
      comparePackages(edited, book.save().bytes, ignoreBookkeeping: true),
      isEmpty,
    );
  });

  test('an edit outside a transaction ends undo of the sets before it', () {
    final XlsxChangeSet one = book.transaction(() => s.setCell(0, 0, 10));
    s.setCell(0, 0, 20);
    expect(() => book.undo(one), throwsStateError);
    expect(s.cellAt(0, 0)?.value, XlsxDecimal('20'));
  });

  test('redo after undo restores the edit; after another edit throws', () {
    final XlsxChangeSet set = book.transaction(() => s.deleteRows(0));
    final Uint8List edited = book.save().bytes;
    book.undo(set);
    book.redo(set);
    expect(
      comparePackages(edited, book.save().bytes, ignoreBookkeeping: true),
      isEmpty,
    );
    expect(() => book.redo(set), throwsStateError);
    book.undo(set);
    book.transaction(() => s.setCell(9, 0, 'y'));
    expect(() => book.redo(set), throwsStateError);
  });

  test('nested transaction joins the outer', () {
    late XlsxChangeSet inner;
    final XlsxChangeSet outer = book.transaction(() {
      s.setCell(0, 0, 10);
      inner = book.transaction(() => s.setCell(1, 0, 20));
    });
    expect(inner.isEmpty, isTrue);
    expect(inner.changes, isEmpty);
    expect(outer.changes, hasLength(2));
    expect(() => book.undo(inner), throwsStateError);
    book.undo(outer);
    expectSame(book.save().bytes);
  });

  test('a throw in a nested transaction reverts the outer one', () {
    expect(
      () => book.transaction(() {
        s.setCell(0, 0, 10);
        book.transaction(() => throw StateError('boom'));
      }),
      throwsStateError,
    );
    expectSame(book.save().bytes);
  });

  test('records of a row insert carry index and count', () {
    final XlsxChangeSet set = book.transaction(() {
      s.insertRows(2, 3);
      s.deleteRows(1);
      s.insertColumns(0, 2);
      s.deleteColumns(4, 1);
    });
    expect(set.changes, <XlsxChange>[
      const XlsxChange(
        XlsxChangeKind.rowsInserted,
        sheet: 'S',
        index: 2,
        count: 3,
      ),
      const XlsxChange(
        XlsxChangeKind.rowsDeleted,
        sheet: 'S',
        index: 1,
        count: 1,
      ),
      const XlsxChange(
        XlsxChangeKind.columnsInserted,
        sheet: 'S',
        index: 0,
        count: 2,
      ),
      const XlsxChange(
        XlsxChangeKind.columnsDeleted,
        sheet: 'S',
        index: 4,
        count: 1,
      ),
    ]);
  });

  test('undo across save', () {
    final XlsxChangeSet set = book.transaction(() => s.insertRows(0));
    book.save();
    book.undo(set);
    expectSame(book.save().bytes);
    book.redo(set);
    expect(s.cellAt(1, 0)?.value, XlsxDecimal('1'));
  });

  test('an empty transaction is empty', () {
    final XlsxChangeSet set = book.transaction(() {});
    expect(set.isEmpty, isTrue);
    expect(set.changes, isEmpty);
  });
}
