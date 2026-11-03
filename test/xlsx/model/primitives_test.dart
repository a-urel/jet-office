import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/xlsx/model/cell_store.dart';
import 'package:jet_office/src/xlsx/model/primitives.dart';
import 'package:jet_office/src/xlsx/raw_cell.dart';
import 'package:test/test.dart';

RawCell _num(String v) => RawCell(kind: RawCellKind.number, value: v);

RawCell _f(RawFormula f, [String? v]) =>
    RawCell(kind: RawCellKind.number, value: v, formula: f);

void main() {
  group('setStoredCell', () {
    test('records old and new; revert restores', () {
      final CellStore store = CellStore()..put(0, 0, _num('1'));
      final ChangeLog log = ChangeLog();
      final ChangeSet set = log.transaction(() {
        setStoredCell(log, store, 0, 0, _num('2'));
        setStoredCell(log, store, 1, 1, _num('3'));
      });
      expect(store.cellAt(0, 0)!.value, '2');
      expect(store.cellAt(1, 1)!.value, '3');
      expect(log.hasChanges, isTrue);

      log.revertSet(set);
      expect(store.cellAt(0, 0)!.value, '1');
      expect(store.cellAt(1, 1), isNull);

      log.reapplySet(set);
      expect(store.cellAt(0, 0)!.value, '2');
      expect(store.cellAt(1, 1)!.value, '3');
    });

    test('null removes the cell and revert puts it back', () {
      final CellStore store = CellStore()..put(0, 0, _num('1'));
      final ChangeLog log = ChangeLog();
      final ChangeSet set = log.transaction(
        () => setStoredCell(log, store, 0, 0, null),
      );
      expect(store.cellAt(0, 0), isNull);
      log.revertSet(set);
      expect(store.cellAt(0, 0)!.value, '1');
    });

    test('outside a transaction it throws and leaves the store unchanged', () {
      final CellStore store = CellStore();
      final ChangeLog log = ChangeLog();
      expect(
        () => setStoredCell(log, store, 0, 0, _num('1')),
        throwsStateError,
      );
      expect(store.cellAt(0, 0), isNull);
    });
  });

  group('groupRoleAt', () {
    final CellStore store = CellStore()
      ..put(
        1,
        1,
        _f(
          const RawFormula(
            type: FormulaType.shared,
            text: 'A2*2',
            ref: 'B2:B4',
            si: '0',
          ),
        ),
      )
      ..put(2, 1, _f(const RawFormula(type: FormulaType.shared, si: '0')))
      ..put(3, 1, _f(const RawFormula(type: FormulaType.shared, si: '0')))
      ..put(
        1,
        3,
        _f(
          const RawFormula(
            type: FormulaType.array,
            text: 'A1:A2',
            ref: 'D2:D3',
          ),
        ),
      )
      ..put(2, 3, _num('5'))
      ..put(5, 5, _f(const RawFormula(type: FormulaType.normal, text: '1')))
      ..put(6, 6, _f(const RawFormula(type: FormulaType.shared, si: '9')));

    test('shared master and children', () {
      expect(groupRoleAt(store, 1, 1), GroupRole.sharedMaster);
      expect(groupRoleAt(store, 2, 1), GroupRole.sharedChild);
      expect(groupRoleAt(store, 3, 1), GroupRole.sharedChild);
    });

    test('array master and member, with or without a stored cell', () {
      expect(groupRoleAt(store, 1, 3), GroupRole.arrayOrTableMember);
      expect(groupRoleAt(store, 2, 3), GroupRole.arrayOrTableMember);
      expect(groupRoleAt(store, 4, 3), GroupRole.none);
    });

    test('none for plain, normal and orphan shared cells', () {
      expect(groupRoleAt(store, 0, 0), GroupRole.none);
      expect(groupRoleAt(store, 5, 5), GroupRole.none);
      expect(groupRoleAt(store, 6, 6), GroupRole.none);
    });

    test('a store without formulas is none everywhere', () {
      expect(groupRoleAt(CellStore(), 0, 0), GroupRole.none);
    });
  });
}
