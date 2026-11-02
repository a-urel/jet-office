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

  test('a revert that throws does not stop the rollback or hide the error', () {
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
      throwsA(same(error)),
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

  test('record outside a transaction is its own one-change set', () {
    final List<String> log = <String>[];
    final ChangeLog changes = ChangeLog();
    expect(changes.hasChanges, isFalse);
    changes.record(_Fake('1', log));
    expect(changes.hasChanges, isTrue);
    final _Fake c2 = _Fake('2', log);
    final ChangeSet set = changes.transaction(() => changes.record(c2));
    expect(set.changes, <Change>[c2]);
    expect(changes.hasChanges, isTrue);
  });

  test('hasChanges stays true after a rolled back transaction', () {
    final ChangeLog changes = ChangeLog();
    expect(
      () => changes.transaction(() {
        changes.record(_Fake('1', <String>[]));
        throw StateError('boom');
      }),
      throwsStateError,
    );
    expect(changes.hasChanges, isTrue);
  });

  test('a ChangeSet cannot be changed from outside', () {
    final ChangeSet set = ChangeLog().transaction(() {});
    expect(
      () => set.changes.add(_Fake('1', <String>[])),
      throwsUnsupportedError,
    );
  });
}
