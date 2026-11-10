import 'package:jet_office/src/opc/change_log.dart';
import 'package:test/test.dart';

final class _Fake implements Change {
  _Fake(this.name, this.log, {this.throwOnRevert = false});

  final String name;
  final List<String> log;
  final bool throwOnRevert;

  @override
  void revert() {
    log.add('r$name');
    if (throwOnRevert) throw StateError('revert $name failed');
  }

  @override
  void reapply() => log.add('a$name');
}

void main() {
  test('a transaction returns its changes in order', () {
    final List<String> log = <String>[];
    final ChangeLog changes = ChangeLog();
    final _Fake c1 = _Fake('1', log);
    final _Fake c2 = _Fake('2', log);
    final ChangeSet set = changes.transaction(() {
      changes.record(c1);
      changes.record(c2);
    });
    expect(set.changes, <Change>[c1, c2]);
    expect(set.isEmpty, isFalse);
    expect(changes.transaction(() {}).isEmpty, isTrue);
  });

  test('a throwing body reverts its changes in reverse order and rethrows', () {
    final List<String> log = <String>[];
    final ChangeLog changes = ChangeLog();
    final StateError error = StateError('boom');
    expect(
      () => changes.transaction(() {
        changes.record(_Fake('1', log));
        changes.record(_Fake('2', log));
        throw error;
      }),
      throwsA(same(error)),
    );
    expect(log, <String>['r2', 'r1']);
  });

  test('a revert that throws does not stop the rollback and is reported', () {
    final List<String> log = <String>[];
    final ChangeLog changes = ChangeLog();
    final StateError error = StateError('boom');
    expect(
      () => changes.transaction(() {
        changes.record(_Fake('1', log));
        changes.record(_Fake('2', log, throwOnRevert: true));
        changes.record(_Fake('3', log));
        throw error;
      }),
      throwsA(
        isA<StateError>()
            .having(
              (StateError e) => e,
              'is not the original',
              isNot(same(error)),
            )
            .having(
              (StateError e) => e.message,
              'message',
              allOf(
                contains('boom'),
                contains('revert 2 failed'),
                contains('inconsistent'),
              ),
            ),
      ),
    );
    expect(log, <String>['r3', 'r2', 'r1']);
  });

  test('nested transactions fold into the outer one', () {
    final List<String> log = <String>[];
    final ChangeLog changes = ChangeLog();
    final _Fake c1 = _Fake('1', log);
    final _Fake c2 = _Fake('2', log);
    final _Fake c3 = _Fake('3', log);
    late ChangeSet inner;
    final ChangeSet outer = changes.transaction(() {
      changes.record(c1);
      inner = changes.transaction(() => changes.record(c2));
      changes.record(c3);
    });
    expect(inner.changes, <Change>[c2]);
    expect(outer.changes, <Change>[c1, c2, c3]);
  });

  test('a failed inner transaction reverts only itself when the outer '
      'body handles the error', () {
    final List<String> log = <String>[];
    final ChangeLog changes = ChangeLog();
    final _Fake c1 = _Fake('1', log);
    final ChangeSet outer = changes.transaction(() {
      changes.record(c1);
      try {
        changes.transaction(() {
          changes.record(_Fake('2', log));
          throw StateError('inner');
        });
      } on StateError {
        // handled
      }
    });
    expect(log, <String>['r2']);
    expect(outer.changes, <Change>[c1]);
  });

  test('revertSet and reapplySet', () {
    final List<String> log = <String>[];
    final ChangeLog changes = ChangeLog();
    final ChangeSet set = changes.transaction(() {
      changes.record(_Fake('1', log));
      changes.record(_Fake('2', log));
    });
    changes.revertSet(set);
    changes.reapplySet(set);
    expect(log, <String>['r2', 'r1', 'a1', 'a2']);
  });

  test('record outside a transaction throws and leaves hasChanges false', () {
    final ChangeLog changes = ChangeLog();
    expect(() => changes.record(_Fake('1', <String>[])), throwsStateError);
    expect(changes.hasChanges, isFalse);
  });

  test('hasChanges is true after a transaction that recorded', () {
    final ChangeLog changes = ChangeLog();
    expect(changes.hasChanges, isFalse);
    changes.transaction(() => changes.record(_Fake('1', <String>[])));
    expect(changes.hasChanges, isTrue);
  });

  test('a rollback from a clean log leaves hasChanges false', () {
    final ChangeLog changes = ChangeLog();
    expect(
      () => changes.transaction(() {
        changes.record(_Fake('1', <String>[]));
        throw StateError('boom');
      }),
      throwsStateError,
    );
    expect(changes.hasChanges, isFalse);
  });

  test('a rollback keeps hasChanges true when it was already true', () {
    final ChangeLog changes = ChangeLog();
    changes.transaction(() => changes.record(_Fake('1', <String>[])));
    expect(
      () => changes.transaction(() {
        changes.record(_Fake('2', <String>[]));
        throw StateError('boom');
      }),
      throwsStateError,
    );
    expect(changes.hasChanges, isTrue);
  });

  test('a failed inner transaction restores hasChanges from its own start', () {
    final ChangeLog changes = ChangeLog();
    changes.transaction(() {
      changes.record(_Fake('1', <String>[]));
      try {
        changes.transaction(() {
          changes.record(_Fake('2', <String>[]));
          throw StateError('inner');
        });
      } on StateError {
        // handled
      }
      expect(changes.hasChanges, isTrue);
    });
    final ChangeLog clean = ChangeLog();
    clean.transaction(() {
      try {
        clean.transaction(() {
          clean.record(_Fake('1', <String>[]));
          throw StateError('inner');
        });
      } on StateError {
        // handled
      }
      expect(clean.hasChanges, isFalse);
    });
  });

  test('revertSet does not reset hasChanges', () {
    final ChangeLog changes = ChangeLog();
    final ChangeSet set = changes.transaction(
      () => changes.record(_Fake('1', <String>[])),
    );
    changes.revertSet(set);
    expect(changes.hasChanges, isTrue);
  });

  test('a ChangeSet cannot be changed from outside', () {
    final ChangeSet set = ChangeLog().transaction(() {});
    expect(
      () => set.changes.add(_Fake('1', <String>[])),
      throwsUnsupportedError,
    );
  });

  test('a transaction carries the records noted in it', () {
    final ChangeLog changes = ChangeLog();
    late ChangeSet inner;
    final ChangeSet set = changes.transaction(() {
      changes.note('a');
      inner = changes.transaction(() => changes.note('b'));
      expect(
        () => changes.transaction(() {
          changes.note('c');
          throw StateError('boom');
        }),
        throwsStateError,
      );
    });
    expect(set.records, <Object?>['a', 'b']);
    expect(inner.records, <Object?>['b']);
    expect(() => changes.note('x'), throwsStateError);
  });

  group('undo and redo of a kept set', () {
    late List<String> log;
    late ChangeLog changes;
    ChangeSet kept(String name) =>
        changes.transaction(() => changes.record(_Fake(name, log)), keep: true);
    setUp(() {
      log = <String>[];
      changes = ChangeLog();
    });

    test('undo takes the last set, then the one before', () {
      final ChangeSet one = kept('1');
      final ChangeSet two = kept('2');
      expect(() => changes.undo(one), throwsStateError);
      expect(log, isEmpty);
      changes.undo(two);
      changes.undo(one);
      expect(log, <String>['r2', 'r1']);
      expect(() => changes.redo(two), throwsStateError);
      changes.redo(one);
      changes.redo(two);
      expect(log, <String>['r2', 'r1', 'a1', 'a2']);
      expect(() => changes.redo(two), throwsStateError);
    });

    test('a new edit ends redo; an unkept edit ends undo', () {
      final ChangeSet one = kept('1');
      changes.undo(one);
      kept('2');
      expect(() => changes.redo(one), throwsStateError);
      final ChangeSet three = kept('3');
      changes.transaction(() => changes.record(_Fake('4', log)));
      expect(() => changes.undo(three), throwsStateError);
      changes.transaction(() {});
      expect(log, <String>['r1']);
    });

    test('a failed transaction leaves the sets as they were', () {
      final ChangeSet one = kept('1');
      expect(
        () => changes.transaction(() {
          changes.record(_Fake('2', log));
          throw StateError('boom');
        }),
        throwsStateError,
      );
      changes.undo(one);
      expect(log, <String>['r2', 'r1']);
    });

    test('a kept transaction inside another joins it', () {
      final ChangeSet outer = changes.transaction(() {
        changes.record(_Fake('1', log));
        changes.transaction(() => changes.record(_Fake('2', log)), keep: true);
      }, keep: true);
      changes.undo(outer);
      expect(log, <String>['r2', 'r1']);
    });
  });
}
