/// Change records and atomic transactions for a model.
///
/// Not ported from Quds; written for jet_office.
///
/// A model primitive (set a cell, say) applies itself and then calls
/// [ChangeLog.record] with a [Change] that can undo and redo it. A higher-level
/// edit wraps its primitives in [ChangeLog.transaction]: if the body throws,
/// the records made so far are reverted in reverse order and the error is
/// rethrown, so the model is never left half-changed. The library keeps no
/// history of its own; a transaction returns a [ChangeSet] that an editor may
/// hand to [ChangeLog.undo] and [ChangeLog.redo], which enforce the order
/// (only the last kept set, and only while nothing came after it), or to
/// [ChangeLog.revertSet] and [ChangeLog.reapplySet], which do not. A set also
/// carries the records a format layer noted with [ChangeLog.note].
///
/// [ChangeLog.hasChanges] is how a save learns that the model was edited.
library;

/// One applied edit that knows how to undo and redo itself.
abstract interface class Change {
  /// Undoes the edit, restoring the state from before it was applied.
  void revert();

  /// Applies the edit again after a [revert].
  void reapply();
}

/// The changes one transaction made, in the order they were recorded.
final class ChangeSet {
  /// Wraps [changes] and [records]; both lists are copied and cannot be
  /// modified.
  ChangeSet(Iterable<Change> changes, [Iterable<Object?> records = const []])
    : changes = List<Change>.unmodifiable(changes),
      records = List<Object?>.unmodifiable(records);

  /// The changes, oldest first.
  final List<Change> changes;

  // Undo bookkeeping of a kept set (ChangeLog.transaction with keep): its
  // sequence id, the generation it was made in, the id of the set that was
  // the last applied when it was made, and, while it is undone, the id of
  // the set that was the last undone before it. The log keeps ids only, so
  // a set the editor drops can be collected.
  int? _id;
  int _generation = 0;
  int? _predecessor;
  int? _undonePredecessor;

  /// The records noted with [ChangeLog.note] while the transaction ran,
  /// oldest first: what the edits were, for a caller, beside [changes], which
  /// know how to undo them.
  final List<Object?> records;

  /// Whether the transaction recorded nothing.
  bool get isEmpty => changes.isEmpty;
}

// Unique across logs, so a set of another log never matches.
int _nextSetId = 0;

/// Collects [Change]s and runs edits atomically.
final class ChangeLog {
  final List<Change> _open = <Change>[];
  final List<Object?> _records = <Object?>[];
  // Ids, never sets: the log holds no history (decision 0009).
  int _generation = 0;
  int? _topApplied;
  int? _topUndone;
  int _depth = 0;
  bool _hasChanges = false;

  /// Whether anything was recorded since this log was created.
  ///
  /// It becomes true on the first [record] and stays true, also when the
  /// change is later undone with [revertSet] or [reapplySet]: an undone change
  /// still counts as a change for save bookkeeping. Only a transaction that
  /// fails restores the value it had when it started.
  bool get hasChanges => _hasChanges;

  /// Records [change], which its primitive has already applied.
  ///
  /// Every mutation must run inside [transaction], so that its change can be
  /// undone; recording outside one throws a [StateError].
  void record(Change change) {
    if (_depth == 0) {
      throw StateError('A change must be recorded inside a transaction.');
    }
    _hasChanges = true;
    _open.add(change);
  }

  /// Whether a [transaction] is running.
  bool get inTransaction => _depth > 0;

  /// Notes [record], a description of an edit for the caller of the running
  /// transaction; it is part of that transaction's [ChangeSet.records].
  ///
  /// Throws a [StateError] outside a transaction.
  void note(Object? record) {
    if (_depth == 0) {
      throw StateError('A record must be noted inside a transaction.');
    }
    _records.add(record);
  }

  /// Runs [body] and returns the changes it recorded.
  ///
  /// When the transaction is the outermost one and succeeds, a [keep] set
  /// becomes the last set [undo] takes, and a new edit can no longer be
  /// redone. An outermost set that is not kept and recorded anything ends
  /// both: no set before it can be undone or redone, as it would undo out of
  /// order. [keep] is ignored on an inner transaction.
  ///
  /// If [body] throws, those changes are reverted in reverse order,
  /// [hasChanges] returns to its value from before the transaction, and the
  /// error is rethrown unchanged. If a [Change.revert] throws during that
  /// rollback, the remaining changes are still reverted and then a
  /// [StateError] is thrown that names the original error and every revert
  /// failure; the model may be inconsistent. A transaction started inside
  /// another folds into it: its changes are part of both sets, and if it fails
  /// only its own changes are reverted.
  ChangeSet transaction(void Function() body, {bool keep = false}) {
    final int start = _open.length;
    final int recordStart = _records.length;
    final bool hadChanges = _hasChanges;
    _depth++;
    try {
      body();
      final ChangeSet set = ChangeSet(
        _open.sublist(start),
        _records.sublist(recordStart),
      );
      if (_depth == 1) {
        if (keep) {
          set
            .._id = _nextSetId++
            .._generation = _generation
            .._predecessor = _topApplied;
          _topApplied = set._id;
          _topUndone = null;
        } else if (!set.isEmpty) {
          _generation++;
          _topApplied = null;
          _topUndone = null;
        }
      }
      return set;
    } catch (error) {
      final List<Change> mine = _open.sublist(start);
      _open.length = start;
      _records.length = recordStart;
      final List<Object> failures = <Object>[];
      for (final Change change in mine.reversed) {
        try {
          change.revert();
        } catch (e) {
          failures.add(e);
        }
      }
      _hasChanges = hadChanges;
      if (failures.isEmpty) rethrow;
      throw StateError(
        'The model may be inconsistent: a transaction failed with '
        '$error and ${failures.length} revert(s) failed while rolling it '
        'back: ${failures.join('; ')}',
      );
    } finally {
      _depth--;
      if (_depth == 0) {
        _open.clear();
        _records.clear();
      }
    }
  }

  /// Reverts [set], which must be the last kept set applied and not undone;
  /// otherwise throws a [StateError] and changes nothing, as undoing out of
  /// order would corrupt the parts.
  void undo(ChangeSet set) {
    _checkIdle();
    if (set._id == null ||
        set._id != _topApplied ||
        set._generation != _generation) {
      throw StateError(
        'Only the last change set applied and not undone can be undone.',
      );
    }
    revertSet(set);
    set._undonePredecessor = _topUndone;
    _topUndone = set._id;
    _topApplied = set._predecessor;
  }

  /// Reapplies [set], which must be the last set [undo] reverted, with
  /// nothing recorded since; otherwise throws a [StateError] and changes
  /// nothing.
  void redo(ChangeSet set) {
    _checkIdle();
    if (set._id == null ||
        set._id != _topUndone ||
        set._generation != _generation) {
      throw StateError(
        'Only the last change set undone, with no edit since, can be redone.',
      );
    }
    reapplySet(set);
    _topUndone = set._undonePredecessor;
    set._undonePredecessor = null;
    _topApplied = set._id;
  }

  void _checkIdle() {
    if (_depth > 0) {
      throw StateError(
        'A change set cannot be undone or redone inside a '
        'transaction.',
      );
    }
  }

  /// Reverts every change of [set], newest first.
  void revertSet(ChangeSet set) {
    for (final Change change in set.changes.reversed) {
      change.revert();
    }
  }

  /// Reapplies every change of [set], oldest first.
  void reapplySet(ChangeSet set) {
    for (final Change change in set.changes) {
      change.reapply();
    }
  }
}
