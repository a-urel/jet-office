/// Bounded aggregation of warnings, shared by every format.
///
/// Moved from `lib/src/xlsx/warnings.dart`, where it was the aggregation
/// inside `WarningCollector`; not ported from Quds. Each format wraps the
/// entries in its own public warning type and writes its own messages.
library;

import 'dart:collection';

/// One aggregated warning: every occurrence of [code] with [detail] under
/// [scope], or one occurrence recorded by
/// [WarningAggregator.addUnaggregated].
final class AggregatedWarning<C extends Enum> {
  AggregatedWarning._(this.code, this.scope, this.detail);

  /// How many locations an entry keeps.
  static const int maxLocations = 10;

  /// The kind of problem.
  final C code;

  /// What the entry is aggregated and removed under: a sheet name or index,
  /// a part name, whatever the format chooses.
  final Object scope;

  /// The parameter of the warning, or null when it has none or when the
  /// scope and code already have ten other details.
  final String? detail;

  int _count = 0;
  int _locationsOffered = 0;
  final List<String> _locations = <String>[];
  late final List<String> _locationsView = UnmodifiableListView<String>(
    _locations,
  );

  /// How many occurrences the entry stands for.
  int get count => _count;

  /// How many locations were given, kept or not.
  ///
  /// More than [locations] holds when some were dropped past the first
  /// ten. It counts calls that named a location, not occurrences: one call
  /// may stand for several occurrences at one location.
  int get locationsOffered => _locationsOffered;

  /// The first ten locations given, in the order they were added.
  ///
  /// An unmodifiable view, the same object on every call, that shows
  /// locations added later.
  List<String> get locations => _locationsView;
}

/// Collects warnings so that memory stays bounded however often they recur.
///
/// [add] aggregates by `(scope, code, detail)`: one entry counts every
/// occurrence and keeps the first ten locations. A scope and code keep at
/// most ten distinct non-null details; an [add] with an eleventh or later
/// new detail joins the entry for `(scope, code, null)`, so a hostile file
/// cannot make an entry per detail. [addUnaggregated] records an entry per
/// call, for warnings that are each about something different (a renamed
/// sheet).
final class WarningAggregator<C extends Enum> {
  final List<AggregatedWarning<C>> _all = <AggregatedWarning<C>>[];
  late final List<AggregatedWarning<C>> _allView =
      UnmodifiableListView<AggregatedWarning<C>>(_all);
  final Map<(Object, C, String?), AggregatedWarning<C>> _aggregated =
      <(Object, C, String?), AggregatedWarning<C>>{};

  /// How many distinct non-null details each `(scope, code)` has an entry
  /// for.
  final Map<(Object, C), int> _details = <(Object, C), int>{};

  /// How many distinct non-null details a scope and code keep.
  static const int _maxDetails = 10;

  /// Records [count] occurrences of [code] under [scope] and returns the
  /// entry they joined.
  ///
  /// [location] (such as an A1 reference) is kept while the entry has fewer
  /// than ten. [detail] is the parameter of the code, if it has one;
  /// occurrences with different details are separate entries, up to ten
  /// details per scope and code, after which a new detail is recorded as
  /// null.
  AggregatedWarning<C> add(
    C code, {
    required Object scope,
    String? location,
    String? detail,
    int count = 1,
  }) {
    String? kept = detail;
    if (kept != null && !_aggregated.containsKey((scope, code, kept))) {
      final int named = _details[(scope, code)] ?? 0;
      if (named < _maxDetails) {
        _details[(scope, code)] = named + 1;
      } else {
        kept = null;
      }
    }
    final AggregatedWarning<C> entry = _aggregated.putIfAbsent(
      (scope, code, kept),
      () {
        final AggregatedWarning<C> created = AggregatedWarning<C>._(
          code,
          scope,
          kept,
        );
        _all.add(created);
        return created;
      },
    );
    _record(entry, location, count);
    return entry;
  }

  /// Records one occurrence of [code] under [scope] as an entry of its own,
  /// never joined by a later call, and returns it.
  ///
  /// [detail] is kept as given. [removeScope] drops the entry like any
  /// other.
  AggregatedWarning<C> addUnaggregated(
    C code, {
    required Object scope,
    String? location,
    String? detail,
  }) {
    final AggregatedWarning<C> entry = AggregatedWarning<C>._(
      code,
      scope,
      detail,
    );
    _all.add(entry);
    _record(entry, location, 1);
    return entry;
  }

  /// The entries so far, in first-occurrence order. An unmodifiable view,
  /// the same object on every call, that shows entries added later.
  List<AggregatedWarning<C>> get all => _allView;

  /// Drops every entry added under [scope], keeping the order of the rest.
  ///
  /// Entries whose code is in [keep] stay. The aggregation state of the
  /// dropped entries goes too, so a later [add] starts a fresh entry with
  /// fresh details.
  void removeScope(Object scope, {Set<C> keep = const {}}) {
    bool drop(AggregatedWarning<C> w) =>
        w.scope == scope && !keep.contains(w.code);
    _all.removeWhere(drop);
    _aggregated.removeWhere(
      ((Object, C, String?) k, AggregatedWarning<C> w) => drop(w),
    );
    _details.removeWhere(
      ((Object, C) k, int n) => k.$1 == scope && !keep.contains(k.$2),
    );
  }

  /// The state of every entry now, for [restore].
  WarningSnapshot mark() => WarningSnapshot._(
    List<Object>.of(_all),
    Map<Object, Object>.of(_aggregated),
    Map<Object, int>.of(_details),
    <Object, (int, int, int)>{
      for (final AggregatedWarning<C> w in _all)
        w: (w._count, w._locationsOffered, w._locations.length),
    },
  );

  /// Puts every entry back as it was at [snapshot], a [mark] of this
  /// aggregator: entries added since go, counts and locations return.
  void restore(WarningSnapshot snapshot) {
    _all
      ..clear()
      ..addAll(snapshot._all.cast<AggregatedWarning<C>>());
    _aggregated
      ..clear()
      ..addAll(
        snapshot._aggregated.cast<(Object, C, String?), AggregatedWarning<C>>(),
      );
    _details
      ..clear()
      ..addAll(snapshot._details.cast<(Object, C), int>());
    for (final AggregatedWarning<C> w in _all) {
      final (int count, int offered, int kept) = snapshot._entries[w]!;
      w._count = count;
      w._locationsOffered = offered;
      w._locations.removeRange(kept, w._locations.length);
    }
  }

  static void _record(AggregatedWarning<Enum> entry, String? location, int n) {
    entry._count += n;
    if (location == null) return;
    entry._locationsOffered++;
    if (entry._locations.length < AggregatedWarning.maxLocations) {
      entry._locations.add(location);
    }
  }
}

/// What [WarningAggregator.mark] saw, for [WarningAggregator.restore].
final class WarningSnapshot {
  WarningSnapshot._(this._all, this._aggregated, this._details, this._entries);

  final List<Object> _all;
  final Map<Object, Object> _aggregated;
  final Map<Object, int> _details;
  final Map<Object, (int, int, int)> _entries;
}
