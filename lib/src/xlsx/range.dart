/// Rectangular cell ranges.
///
/// New in jet_office; Quds keeps merged and filtered ranges as bare strings.
library;

import 'cell_ref.dart';
import 'limits.dart';

/// A rectangle of cells: 0-based, inclusive row and column indexes.
///
/// The `const` constructor cannot check its arguments. A range that lies
/// outside the sheet, or whose first corner is after its last, is reported
/// when it is registered with the writer (a merge or an auto filter), which
/// throws [ArgumentError]. [XlsxRange.parse] checks at once.
final class XlsxRange {
  /// The range from ([firstRow], [firstColumn]) to ([lastRow], [lastColumn]),
  /// both inclusive and 0-based. A last row or column left out is the first,
  /// so `XlsxRange(1, 1)` is the single cell `B2`.
  const XlsxRange(
    this.firstRow,
    this.firstColumn, [
    int? lastRow,
    int? lastColumn,
  ]) : lastRow = lastRow ?? firstRow,
       lastColumn = lastColumn ?? firstColumn;

  /// The range written as [ref]: `B2`, `B2:D10` or `$B$2:$D$10`, in either
  /// case. Corners given in reverse order are swapped (`D10:B2` is `B2:D10`).
  ///
  /// Throws [ArgumentError] for whole-row or whole-column references (`A:A`,
  /// `1:3`), references outside the sheet and malformed text.
  factory XlsxRange.parse(String ref) {
    final List<String> parts = ref.split(':');
    if (parts.length > 2) {
      throw ArgumentError.value(ref, 'ref', 'Not a cell range.');
    }
    final ({int row, int column}) a = _parseCorner(parts.first, ref);
    final ({int row, int column}) b = parts.length == 2
        ? _parseCorner(parts.last, ref)
        : a;
    return XlsxRange(
      a.row < b.row ? a.row : b.row,
      a.column < b.column ? a.column : b.column,
      a.row < b.row ? b.row : a.row,
      a.column < b.column ? b.column : a.column,
    );
  }

  static ({int row, int column}) _parseCorner(String corner, String ref) {
    try {
      return parseCellRef(corner);
    } on ArgumentError {
      throw ArgumentError.value(
        ref,
        'ref',
        'Not a cell range: only cell references are accepted.',
      );
    }
  }

  /// The first (top) row, 0-based.
  final int firstRow;

  /// The first (left) column, 0-based.
  final int firstColumn;

  /// The last (bottom) row, 0-based and inclusive.
  final int lastRow;

  /// The last (right) column, 0-based and inclusive.
  final int lastColumn;

  /// The number of rows the range spans.
  int get rowCount => lastRow - firstRow + 1;

  /// The number of columns the range spans.
  int get columnCount => lastColumn - firstColumn + 1;

  /// Whether the range is exactly one cell.
  bool get isSingleCell => rowCount == 1 && columnCount == 1;

  /// The A1-style reference: `B2:D10`, or `B2` for a single cell.
  ///
  /// Throws [RangeError] when a corner is outside the sheet.
  String get ref => _format(absolute: false);

  /// The reference with `$` before every column and row: `$B$2:$D$10`, or
  /// `$B$2` for a single cell.
  ///
  /// Throws [RangeError] when a corner is outside the sheet.
  String get absoluteRef => _format(absolute: true);

  String _format({required bool absolute}) {
    final String d = absolute ? r'$' : '';
    String corner(int row, int column) => '$d${columnName(column)}$d${row + 1}';
    final String first = corner(firstRow, firstColumn);
    return isSingleCell ? first : '$first:${corner(lastRow, lastColumn)}';
  }

  /// Whether this range and [other] share at least one cell.
  bool overlaps(XlsxRange other) =>
      firstRow <= other.lastRow &&
      other.firstRow <= lastRow &&
      firstColumn <= other.lastColumn &&
      other.firstColumn <= lastColumn;

  @override
  bool operator ==(Object other) =>
      other is XlsxRange &&
      other.firstRow == firstRow &&
      other.firstColumn == firstColumn &&
      other.lastRow == lastRow &&
      other.lastColumn == lastColumn;

  @override
  int get hashCode => Object.hash(firstRow, firstColumn, lastRow, lastColumn);

  @override
  String toString() {
    final bool inSheet =
        firstRow >= 0 &&
        firstColumn >= 0 &&
        lastRow < XlsxLimits.maxRows &&
        lastColumn < XlsxLimits.maxColumns;
    return inSheet
        ? 'XlsxRange($ref)'
        : 'XlsxRange($firstRow, $firstColumn, $lastRow, $lastColumn)';
  }
}

/// Checks that both corners of [range] are inside the sheet and that the
/// first is not after the last.
///
/// Throws [ArgumentError] naming [field] when they are not.
void validateRange(XlsxRange range, String field) {
  final bool inSheet =
      range.firstRow >= 0 &&
      range.firstColumn >= 0 &&
      range.lastRow < XlsxLimits.maxRows &&
      range.lastColumn < XlsxLimits.maxColumns;
  if (!inSheet) {
    throw ArgumentError.value(range, field, 'The range is outside the sheet.');
  }
  if (range.firstRow > range.lastRow || range.firstColumn > range.lastColumn) {
    throw ArgumentError.value(
      range,
      field,
      'The first row and column must not be after the last.',
    );
  }
}
