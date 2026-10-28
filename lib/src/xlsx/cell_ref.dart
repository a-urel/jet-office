/// A1-style cell references.
///
/// Ported from quds_office_engine `lib/src/builders/office_markup.dart` at commit 15c5d29.
/// Ported: `colName`. What changed: the function is top-level rather
/// than a static method, indexes outside the sheet throw [RangeError] instead
/// of producing names Excel cannot open, and [cellRef], [matchCellRef] and
/// [parseCellRef] are new.
library;

import 'limits.dart';

/// The column letters for the 0-based [column]: 0 is `A`, 26 is `AA`,
/// 16383 is `XFD`.
///
/// Throws [RangeError] when [column] is outside `0..16383`.
String columnName(int column) {
  RangeError.checkValueInInterval(
    column,
    0,
    XlsxLimits.maxColumns - 1,
    'column',
  );
  var n = column;
  final List<int> chars = <int>[];
  while (n >= 0) {
    chars.add(65 + (n % 26));
    n = (n ~/ 26) - 1;
  }
  return String.fromCharCodes(chars.reversed);
}

/// The A1-style reference of the cell at the 0-based [row] and [column]:
/// `cellRef(0, 0)` is `A1`.
///
/// Throws [RangeError] when either index is outside the sheet.
String cellRef(int row, int column) {
  RangeError.checkValueInInterval(row, 0, XlsxLimits.maxRows - 1, 'row');
  return '${columnName(column)}${row + 1}';
}

final RegExp _cellRefPattern = RegExp(
  r'^\$?([A-Za-z]{1,3})\$?([1-9][0-9]{0,6})$',
);

/// Splits the A1-style cell reference [ref] into 0-based indexes, without
/// checking them against the sheet, or returns `null` when [ref] does not
/// match the pattern [parseCellRef] accepts.
///
/// The pattern takes an optional `$` before the column and before the row,
/// 1 to 3 letters of either case and a row of 1 to 7 digits without leading
/// zeros, so the column is at most 18,277 (`ZZZ`) and the row at most
/// 9,999,998. Both fit an `int` on every platform.
({int row, int column})? matchCellRef(String ref) {
  final RegExpMatch? match = _cellRefPattern.firstMatch(ref);
  if (match == null) return null;
  var column = 0;
  for (final int unit in match.group(1)!.toUpperCase().codeUnits) {
    column = column * 26 + (unit - 64);
  }
  return (row: int.parse(match.group(2)!) - 1, column: column - 1);
}

/// Parses the A1-style cell reference [ref] into 0-based indexes.
///
/// Accepts an optional `$` before the column and before the row, and letters
/// of either case: `B2`, `$B$2` and `b2` are all row 1, column 1.
///
/// Throws [ArgumentError] when [ref] is not a cell reference, writes its row
/// with leading zeros (`A01`), or names a cell outside the sheet (`XFE1`,
/// `A0`, `A1048577`).
({int row, int column}) parseCellRef(String ref) {
  final ({int row, int column})? cell = matchCellRef(ref);
  if (cell == null) {
    throw ArgumentError.value(ref, 'ref', 'Not a cell reference.');
  }
  if (cell.column >= XlsxLimits.maxColumns || cell.row >= XlsxLimits.maxRows) {
    throw ArgumentError.value(ref, 'ref', 'Outside the sheet.');
  }
  return cell;
}
