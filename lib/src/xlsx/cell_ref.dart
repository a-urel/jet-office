/// A1-style cell references.
///
/// Ported from quds_office_engine `lib/src/builders/office_markup.dart` at commit 15c5d29.
/// Ported: `colName`. What changed: the function is top-level rather
/// than a static method, indexes outside the sheet throw [RangeError] instead
/// of producing names Excel cannot open, and [cellRef] is new.
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
