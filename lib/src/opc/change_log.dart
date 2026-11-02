/// Change records and atomic transactions for a model.
///
/// Not ported from Quds; written for jet_office.
///
/// A model primitive (set a cell, say) applies itself and then calls
/// [ChangeLog.record] with a [Change] that can undo and redo it. A higher-level
/// edit wraps its primitives in [ChangeLog.transaction]: if the body throws,
/// the records made so far are reverted in reverse order and the error is
/// rethrown, so the model is never left half-changed. The library keeps no
/// history; a transaction returns a [ChangeSet] that an editor may hand to
/// [ChangeLog.revertSet] and [ChangeLog.reapplySet].
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
  /// Wraps [changes]; the list is copied and cannot be modified.
  ChangeSet(Iterable<Change> changes)
    : changes = List<Change>.unmodifiable(changes);

  /// The changes, oldest first.
  final List<Change> changes;

  /// Whether the transaction recorded nothing.
  bool get isEmpty => changes.isEmpty;
}

/// Collects [Change]s and runs edits atomically.
final class ChangeLog {
  final List<Change> _open = <Change>[];
  int _depth = 0;
  bool _hasChanges = false;

  /// Whether anything was ever recorded since this log was created.
  ///
  /// It becomes true on the first [record] and stays true, even when the
  /// change is later reverted or its transaction rolls back.
  bool get hasChanges => _hasChanges;

  /// Records [change], which its primitive has already applied.
  ///
  /// Inside a [transaction] the change joins that transaction's set. Outside
  /// one it stands alone: it only marks [hasChanges], and nothing is kept.
  void record(Change change) {
    _hasChanges = true;
    if (_depth > 0) _open.add(change);
  }

  /// Runs [body] and returns the changes it recorded.
  ///
  /// If [body] throws, those changes are reverted in reverse order and the
  /// error is rethrown. A [Change.revert] that itself throws does not stop the
  /// rollback: the remaining changes are still reverted and the original error
  /// is the one rethrown. A transaction started inside another folds into it:
  /// its changes are part of both sets, and if it fails only its own changes
  /// are reverted.
  ChangeSet transaction(void Function() body) {
    final int start = _open.length;
    _depth++;
    try {
      body();
    } catch (_) {
      _depth--;
      final List<Change> mine = _open.sublist(start);
      _open.length = start;
      for (final Change change in mine.reversed) {
        try {
          change.revert();
        } catch (_) {
          // Keep reverting the rest; the body's error is the one reported.
        }
      }
      rethrow;
    }
    _depth--;
    final ChangeSet set = ChangeSet(_open.sublist(start));
    if (_depth == 0) _open.clear();
    return set;
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
