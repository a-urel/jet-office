/// The cell value types the XLSX writer accepts beyond plain Dart values.
///
/// A cell value is one of: `null` (no cell), `String`, `int`, `double`,
/// `bool`, [DateTime], and the wrappers in this library: [XlsxCell] (a value
/// with its own style), [XlsxDate] (a calendar date without a time),
/// [XlsxDecimal] (an exact decimal number) and [XlsxFormula].
///
/// This file is new in jet_office; it has no counterpart in
/// quds_office_engine. Quds stored a `DateTime` as its `toString()` text and
/// had no decimal, date-only or formula value type.
library;

import 'style.dart';

/// A cell value together with the style of that one cell.
///
/// The style applies to this cell only and is merged over the row's style,
/// which is merged over the column's (see `XlsxStyle.merge`): a field the
/// cell style sets wins, one it leaves `null` is inherited. Wrap a value only
/// when the cell needs a style other than the row's; a bare value uses the
/// row style.
///
/// [value] may be anything a cell accepts except another [XlsxCell]; nesting
/// is a programmer error and throws an [ArgumentError] when the cell is
/// written.
final class XlsxCell {
  /// Creates a cell holding [value], styled with [style] when given.
  const XlsxCell(this.value, {this.style});

  /// The value to write: a `String`, `int`, `double`, `bool`, [DateTime],
  /// [XlsxDate], [XlsxDecimal], [XlsxFormula] or `null` (writes no cell).
  final Object? value;

  /// The style of this cell, or `null` to use the row's style.
  final XlsxStyle? style;

  @override
  bool operator ==(Object other) =>
      other is XlsxCell && other.value == value && other.style == style;

  @override
  int get hashCode => Object.hash(value, style);

  @override
  String toString() => 'XlsxCell($value, style: $style)';
}

/// A calendar date without a time of day.
///
/// Written as an Excel date serial in the 1900 date system. Unlike
/// [DateTime], it carries no time zone or daylight-saving ambiguity. A date
/// that does not exist (such as 30 February) throws an [ArgumentError] when
/// the cell is written. A date outside the range Excel can store as a date
/// (1900-01-01 to 9999-12-31) is written as ISO 8601 text (`yyyy-mm-dd`)
/// with a warning.
final class XlsxDate {
  /// Creates the date [year]-[month]-[day]; [month] is 1 to 12.
  const XlsxDate(this.year, this.month, this.day);

  /// The calendar year, for example 2026.
  final int year;

  /// The month, 1 (January) to 12 (December).
  final int month;

  /// The day of the month, starting at 1.
  final int day;

  @override
  bool operator ==(Object other) =>
      other is XlsxDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => 'XlsxDate($year, $month, $day)';
}

final RegExp _decimalDigits = RegExp(r'^-?\d+(\.\d+)?$');

/// An exact decimal number, written to the file digit for digit.
///
/// Use it for money and other values where a `double` would show binary
/// rounding, for example `XlsxDecimal('-1234.50')`. The digits are written
/// verbatim, so `1234.50` keeps its trailing zero in the file, but Excel
/// itself stores numbers as 64-bit floating point and reads only about 15
/// significant digits.
///
/// [digits] must be an optional minus sign, one or more digits, and
/// optionally a point followed by one or more digits. The constructor throws
/// an [ArgumentError] for anything else (a decimal comma, an exponent, a
/// leading plus sign, thousands separators, an empty string).
final class XlsxDecimal {
  /// Creates a decimal from [digits], for example `'12.30'`.
  XlsxDecimal(this.digits) {
    if (!_decimalDigits.hasMatch(digits)) {
      throw ArgumentError.value(
        digits,
        'digits',
        'Expected an optional minus sign, digits and an optional ".digits" '
            'fraction, such as "-1234.50".',
      );
    }
  }

  /// The number as written to the file.
  final String digits;

  @override
  bool operator ==(Object other) =>
      other is XlsxDecimal && other.digits == digits;

  @override
  int get hashCode => digits.hashCode;

  @override
  String toString() => 'XlsxDecimal($digits)';
}

/// A spreadsheet formula, with an optional cached result.
///
/// [text] is the formula as Excel shows it, without a leading `=` (one
/// leading `=` is accepted and removed), for example `SUM(A2:A9)`. Excel
/// recalculates formulas when it opens the file; [cached] is the result to
/// store meanwhile, for readers that do not calculate. It must be `null` (no
/// result stored), a `num`, a `String` or a `bool`; any other type, a `NaN`
/// or infinite number, or text containing characters XML forbids throws an
/// [ArgumentError] when the cell is written.
final class XlsxFormula {
  /// Creates a formula from [text] with an optional [cached] result.
  const XlsxFormula(this.text, {this.cached});

  /// The formula text, with or without one leading `=`.
  final String text;

  /// The result stored beside the formula: `null`, `num`, `String` or `bool`.
  final Object? cached;

  @override
  bool operator ==(Object other) =>
      other is XlsxFormula && other.text == text && other.cached == cached;

  @override
  int get hashCode => Object.hash(text, cached);

  @override
  String toString() => 'XlsxFormula($text, cached: $cached)';
}
