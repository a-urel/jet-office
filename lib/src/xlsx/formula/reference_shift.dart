/// The reference mappers of structural edits: rows or columns inserted or
/// deleted, a sheet renamed, a sheet moved.
///
/// This file is new in jet_office; Quds has no equivalent.
library;

import '../limits.dart';
import '../range.dart';
import 'formula_reference.dart';
import 'formula_rewrite.dart';

/// The axis a [ReferenceShift] inserts or deletes on.
enum ShiftAxis {
  /// Whole rows.
  rows,

  /// Whole columns.
  columns,
}

/// One structural edit: insert (count > 0) or delete (count < 0) at [index]
/// (1-based) of [axis] on [sheet], as Excel shifts references.
///
/// Inserting `n` at `r`: a coordinate `>= r` moves by `n`; a range with
/// `first < r <= last` grows. Deleting `r..r+n-1`: a coordinate after the
/// deleted ones moves back by `n`; a range losing some of them shrinks; a
/// reference losing all of them becomes `#REF!`. `$` marks do not stop a
/// shift. A reference pushed wholly past the sheet's last row (or column)
/// becomes `#REF!`; a range whose first edge stays on the sheet keeps its
/// last edge at the sheet's end (so `A:A` written as `A1:A1048576` stays).
///
/// Sheet names compare ignoring case, as Excel's. A 3D reference
/// (`Sheet1:Sheet3!A5`) never shifts, as in Excel: the edit is on one sheet,
/// not on every sheet of the span, even when [sheet] is one of its ends. An
/// external reference never shifts, and neither does a reversed range
/// (`A5:A1`), which is left as read.
final class ReferenceShift implements ReferenceMapper {
  /// Inserts [count] rows or columns before [index] (1-based).
  ReferenceShift.insert(this.sheet, this.axis, this.index, int count)
    : count = count {
    _check(index, count, 'count');
  }

  /// Deletes [count] rows or columns from [index] (1-based) on.
  ReferenceShift.delete(this.sheet, this.axis, this.index, int count)
    : count = -count {
    _check(index, count, 'count');
  }

  static void _check(int index, int count, String name) {
    if (index < 1) throw ArgumentError.value(index, 'index', 'Must be >= 1.');
    if (count < 1) throw ArgumentError.value(count, name, 'Must be >= 1.');
  }

  /// The edited sheet.
  final String sheet;

  /// The axis edited.
  final ShiftAxis axis;

  /// The first row or column inserted or deleted, 1-based.
  final int index;

  /// Rows or columns inserted (positive) or deleted (negative).
  final int count;

  int get _limit =>
      axis == ShiftAxis.rows ? XlsxLimits.maxRows : XlsxLimits.maxColumns;

  /// The span [first]..[last] (1-based) after the edit; `null` when it is
  /// deleted or pushed off the sheet.
  (int, int)? _span(int first, int last) {
    final int limit = _limit;
    if (count > 0) {
      if (last < index) return (first, last);
      if (first >= index) {
        final int f = first + count;
        if (f > limit) return null;
        return (f, _atMost(last + count, limit));
      }
      return (first, _atMost(last + count, limit));
    }
    final int n = -count;
    final int end = index + n - 1;
    if (last < index) return (first, last);
    if (first > end) return (first - n, last - n);
    if (first >= index && last <= end) return null;
    return (first < index ? first : index, last > end ? last - n : index - 1);
  }

  static int _atMost(int value, int limit) => value > limit ? limit : value;

  /// [range] (0-based, on [sheet]) after the edit, or `null` when deleted
  /// entirely or pushed off the sheet.
  XlsxRange? shiftRange(XlsxRange range) {
    if (axis == ShiftAxis.rows) {
      final (int, int)? s = _span(range.firstRow + 1, range.lastRow + 1);
      if (s == null) return null;
      return XlsxRange(s.$1 - 1, range.firstColumn, s.$2 - 1, range.lastColumn);
    }
    final (int, int)? s = _span(range.firstColumn + 1, range.lastColumn + 1);
    if (s == null) return null;
    return XlsxRange(range.firstRow, s.$1 - 1, range.lastRow, s.$2 - 1);
  }

  /// A drawing corner on the edited axis after the edit: [at] is its 0-based
  /// row or column and [offset] its offset into it. A start corner on the
  /// first inserted row or column moves; an [end] corner there moves only
  /// when it reaches into that row or column (an offset above 0), so a
  /// picture ending at its top keeps its size. A corner in deleted rows or
  /// columns goes to the start of the first one after them, at offset 0, so a
  /// picture whose cells are all deleted keeps zero height or width. `null`
  /// when an insert pushes the corner past the sheet's last row or column.
  ({int at, int offset})? shiftAnchor(int at, int offset, {required bool end}) {
    final int first = index - 1;
    if (count > 0) {
      if (at > first || (at == first && (!end || offset > 0))) {
        if (at + count > _limit - 1) return null;
        return (at: at + count, offset: offset);
      }
      return (at: at, offset: offset);
    }
    final int n = -count;
    if (at < first) return (at: at, offset: offset);
    if (at >= first + n) return (at: at - n, offset: offset);
    return (at: first, offset: 0);
  }

  /// The last 0-based row or column of the edited axis.
  int get lastIndex => _limit - 1;

  /// The cell at 0-based ([row], [column]) on [sheet] after the edit, or
  /// `null` when it is deleted or pushed off the sheet.
  ({int row, int column})? shiftCell(int row, int column) {
    final XlsxRange? r = shiftRange(XlsxRange(row, column));
    return r == null ? null : (row: r.firstRow, column: r.firstColumn);
  }

  bool _applies(FormulaReference ref, String hostSheet) {
    if (ref.externalIndex != null) return false;
    final String target = _key(sheet);
    if (ref.sheet == null) return _key(hostSheet) == target;
    if (ref.lastSheet != null && _key(ref.lastSheet!) != _key(ref.sheet!)) {
      return false;
    }
    return _key(ref.sheet!) == target;
  }

  @override
  FormulaReferenceResult? mapReference(FormulaReference ref, String hostSheet) {
    if (!_applies(ref, hostSheet)) return null;
    final bool rows = axis == ShiftAxis.rows;
    final int? first = rows ? ref.firstRow : ref.firstColumn;
    final int? last = rows ? ref.lastRow : ref.lastColumn;
    if (first == null || last == null || first > last) return null;
    final (int, int)? s = _span(first, last);
    if (s == null) return const FormulaReferenceResult.refError();
    if (s.$1 == first && s.$2 == last) return null;
    return FormulaReferenceResult.to(
      FormulaReference(
        form: ref.form,
        sheet: ref.sheet,
        lastSheet: ref.lastSheet,
        externalIndex: ref.externalIndex,
        firstRow: rows ? s.$1 : ref.firstRow,
        lastRow: rows ? s.$2 : ref.lastRow,
        firstColumn: rows ? ref.firstColumn : s.$1,
        lastColumn: rows ? ref.lastColumn : s.$2,
        absFirstRow: ref.absFirstRow,
        absLastRow: ref.absLastRow,
        absFirstColumn: ref.absFirstColumn,
        absLastColumn: ref.absLastColumn,
      ),
    );
  }

  @override
  String? mapSheetName(String sheet) => null;

  @override
  String? mapStructured(String table, String spec, String hostSheet) => null;
}

/// A sheet renamed from [from] to [to]: every sheet prefix naming [from]
/// (ignoring case, 3D ends included) names [to], quoted when it needs it.
/// External prefixes are never renamed (the rewriter does not ask).
final class SheetRename implements ReferenceMapper {
  /// The rename of [from] to [to].
  SheetRename(this.from, this.to);

  /// The old name.
  final String from;

  /// The new name.
  final String to;

  @override
  FormulaReferenceResult? mapReference(
    FormulaReference ref,
    String hostSheet,
  ) => null;

  @override
  String? mapSheetName(String sheet) => _key(sheet) == _key(from) ? to : null;

  @override
  String? mapStructured(String table, String spec, String hostSheet) => null;
}

/// The sheet at position `from` of `order` moved to position `to`
/// (0-based, the position in the new order). Only 3D references change: one
/// whose first sheet now lies after its last has its ends swapped.
final class SheetMove implements ReferenceMapper {
  /// The move of `order[from]` to position [to].
  SheetMove(List<String> order, int from, int to)
    : _keys = _moved(order, from, to);

  static List<String> _moved(List<String> order, int from, int to) {
    RangeError.checkValidIndex(from, order, 'from');
    RangeError.checkValidIndex(to, order, 'to');
    final List<String> keys = order.map(_key).toList();
    return keys..insert(to, keys.removeAt(from));
  }

  /// The sheet keys in their new order.
  final List<String> _keys;

  @override
  FormulaReferenceResult? mapReference(FormulaReference ref, String hostSheet) {
    if (ref.externalIndex != null || ref.lastSheet == null) return null;
    final int a = _keys.indexOf(_key(ref.sheet!));
    final int b = _keys.indexOf(_key(ref.lastSheet!));
    if (a < 0 || b < 0 || a <= b) return null;
    return FormulaReferenceResult.to(
      FormulaReference(
        form: ref.form,
        sheet: ref.lastSheet,
        lastSheet: ref.sheet,
        firstRow: ref.firstRow,
        lastRow: ref.lastRow,
        firstColumn: ref.firstColumn,
        lastColumn: ref.lastColumn,
        absFirstRow: ref.absFirstRow,
        absLastRow: ref.absLastRow,
        absFirstColumn: ref.absFirstColumn,
        absLastColumn: ref.absLastColumn,
      ),
    );
  }

  @override
  String? mapSheetName(String sheet) => null;

  @override
  String? mapStructured(String table, String spec, String hostSheet) => null;
}

/// [name] as Excel compares sheet names: ignoring case.
String _key(String name) => name.toLowerCase();
