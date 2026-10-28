/// The shared, array and data-table formula groups of one pass over a
/// worksheet.
///
/// Not ported from Quds, whose reader kept only the text of each `<f>` and
/// knew no groups; written for jet_office.
library;

import 'dart:collection';

import '../range.dart';
import 'cell_decoder.dart';
import 'read_cell.dart';

final RegExp _digits = RegExp(r'^[0-9]+$');

final RegExp _leadingZeros = RegExp('^0+');

/// The result of defining or following a group: the cell's `group`, or
/// `null`, and whether the file defines it wrongly (`invalid`).
typedef FormulaGroupResult = ({XlsxFormulaGroup? group, bool invalid});

const FormulaGroupResult _invalid = (group: null, invalid: true);

/// An array or data-table range that may still cover cells of the walk.
final class _Active {
  _Active(this.master, this.follower, this.masterRow, this.masterColumn);

  /// The group of the master's cell.
  final XlsxFormulaGroup master;

  /// The group of every other cell of the range.
  final XlsxFormulaGroup follower;

  final int masterRow;
  final int masterColumn;

  XlsxRange get range => master.range;
}

/// The formula groups of one sheet pass: the shared formulas its masters
/// defined and the array and data-table ranges that still cover cells.
///
/// The walker calls [startRow] at every row, [master] for the `<f>` of a
/// shared master (one with `ref`), an array or a data table, [follower] for
/// a shared `<f>` without `ref`, and [coveredBy] for a cell without `<f>`.
///
/// Each group has two instances: one with `isMaster` for its master, and
/// one shared by all its followers. A master is invalid when its `ref` is
/// missing (except an array's, which then covers the master alone), not a
/// cell range or does not contain the master, when a shared master's `si`
/// is not a non-negative integer, and when an array or data-table range
/// overlaps an active one. A follower is invalid when no master defined its
/// `si` earlier in the sheet, or when its cell is not inside the range of
/// the master that did. An invalid `<f>` defines nothing.
///
/// Active ranges are kept with disjoint columns, in a tree ordered by first
/// column, so finding the range of a cell is a search in O(log n): a file
/// with many ranges cannot make the walk quadratic. Rows come in order, so
/// every active range holds the current row and two whose columns meet
/// overlap. A range is dropped when the walk passes its last row (lazily,
/// when a lookup or a new range meets it, so a row costs nothing for the
/// ranges it does not touch). With rows out of order, a range whose columns
/// meet an active one is refused even when their rows do not meet.
final class FormulaGroups {
  /// The shared followers' groups by `si`, without leading zeros.
  final Map<String, XlsxFormulaGroup> _shared = <String, XlsxFormulaGroup>{};

  /// The active array and data-table ranges by first column.
  final SplayTreeMap<int, _Active> _active = SplayTreeMap<int, _Active>();

  /// The 0-based index of the latest row started.
  int _row = 0;

  /// Starts the row at the 0-based [row]: ranges whose last row is before
  /// it no longer cover cells. A row before the latest one (rows out of
  /// order) brings no dropped range back.
  void startRow(int row) {
    if (row > _row) _row = row;
  }

  /// Defines the group of the master cell at the 0-based [row] and
  /// [column] whose `<f>` is of [type] with the `ref` and `si` attributes
  /// [ref] and [si] (`si` is used for a shared formula only).
  ///
  /// Throws [ArgumentError] for [FormulaType.normal], which has no group.
  FormulaGroupResult master(
    FormulaType type, {
    required int row,
    required int column,
    String? ref,
    String? si,
  }) {
    final XlsxFormulaGroupKind kind = switch (type) {
      FormulaType.shared => XlsxFormulaGroupKind.shared,
      FormulaType.array => XlsxFormulaGroupKind.array,
      FormulaType.dataTable => XlsxFormulaGroupKind.dataTable,
      FormulaType.normal => throw ArgumentError.value(
        type,
        'type',
        'A normal formula has no group.',
      ),
    };
    final XlsxRange? range = ref == null
        ? (type == FormulaType.array ? XlsxRange(row, column) : null)
        : _parse(ref);
    if (range == null ||
        row < range.firstRow ||
        row > range.lastRow ||
        column < range.firstColumn ||
        column > range.lastColumn) {
      return _invalid;
    }
    final XlsxFormulaGroup master = XlsxFormulaGroup(
      kind,
      range,
      isMaster: true,
    );
    final XlsxFormulaGroup follower = XlsxFormulaGroup(
      kind,
      range,
      isMaster: false,
    );
    if (type == FormulaType.shared) {
      final String? key = _key(si);
      if (key == null) return _invalid;
      _shared[key] = follower;
    } else {
      if (_meetsActive(range)) return _invalid;
      _active[range.firstColumn] = _Active(master, follower, row, column);
    }
    return (group: master, invalid: false);
  }

  /// The group of a shared follower at the 0-based [row] and [column]
  /// whose `si` is [si]: the one the latest master of that `si` defined
  /// earlier in the sheet, if the cell is inside its range.
  FormulaGroupResult follower(
    String? si, {
    required int row,
    required int column,
  }) {
    final String? key = _key(si);
    final XlsxFormulaGroup? group = key == null ? null : _shared[key];
    if (group == null) return _invalid;
    final XlsxRange range = group.range;
    if (row < range.firstRow ||
        row > range.lastRow ||
        column < range.firstColumn ||
        column > range.lastColumn) {
      return _invalid;
    }
    return (group: group, invalid: false);
  }

  /// The follower group of the active array or data-table range holding
  /// the cell at the 0-based [row] and [column], or `null` when there is
  /// none or the cell is the range's master.
  XlsxFormulaGroup? coveredBy(int row, int column) {
    final int? key = _active.containsKey(column)
        ? column
        : _active.lastKeyBefore(column);
    if (key == null) return null;
    final _Active active = _active[key]!;
    if (_ended(active)) {
      _active.remove(key);
      return null;
    }
    final XlsxRange range = active.range;
    if (column > range.lastColumn ||
        row < range.firstRow ||
        row > range.lastRow ||
        (row == active.masterRow && column == active.masterColumn)) {
      return null;
    }
    return active.follower;
  }

  /// Whether [range]'s columns meet an active range's, dropping the ended
  /// ranges it passes.
  bool _meetsActive(XlsxRange range) {
    int? key = _active.containsKey(range.firstColumn)
        ? range.firstColumn
        : _active.lastKeyBefore(range.firstColumn);
    if (key != null && _active[key]!.range.lastColumn < range.firstColumn) {
      key = _active.firstKeyAfter(key);
    }
    while (key != null && key <= range.lastColumn) {
      final int? next = _active.firstKeyAfter(key);
      if (!_ended(_active[key]!)) return true;
      _active.remove(key);
      key = next;
    }
    return false;
  }

  bool _ended(_Active active) => active.range.lastRow < _row;

  /// The range [ref], or `null` when it is not a cell range.
  static XlsxRange? _parse(String ref) {
    try {
      return XlsxRange.parse(ref);
    } on ArgumentError {
      return null;
    }
  }

  /// [si] without leading zeros, or `null` when it is not a non-negative
  /// integer. Kept as text, so a huge `si` cannot overflow.
  static String? _key(String? si) {
    if (si == null || !_digits.hasMatch(si)) return null;
    final String key = si.replaceFirst(_leadingZeros, '');
    return key.isEmpty ? '0' : key;
  }
}
