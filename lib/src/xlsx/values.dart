/// The cell value types the XLSX writer accepts beyond plain Dart values.
///
/// A cell value is one of: `null` (no cell), `String`, `int`, `double`,
/// `bool`, [DateTime], the wrappers in this library: [XlsxCell] (a value
/// with its own style), [XlsxDate] (a calendar date without a time),
/// [XlsxDecimal] (an exact decimal number) and [XlsxFormula], and
/// [XlsxHyperlink] and [XlsxRichText] (text in runs with their own fonts)
/// from their own libraries.
///
/// This file is new in jet_office; it has no counterpart in
/// quds_office_engine. Quds stored a `DateTime` as its `toString()` text and
/// had no decimal, date-only or formula value type.
library;

import 'hyperlink.dart';
import 'rich_text.dart';
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
/// written. A `null` [value] with a [style] is an empty styled cell: it is
/// written with the merged style and no value, so a border or fill reaches
/// a cell that holds nothing. When the merged style is the default, or
/// [style] is `null`, nothing is written.
final class XlsxCell {
  /// Creates a cell holding [value], styled with [style] when given.
  const XlsxCell(this.value, {this.style});

  /// The value to write: a `String`, `int`, `double`, `bool`, [DateTime],
  /// [XlsxDate], [XlsxDecimal], [XlsxFormula], [XlsxHyperlink],
  /// [XlsxRichText] or `null` (an empty cell, written only when it has a
  /// [style] that does not merge to the default).
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

/// The largest integer a web `double` holds exactly, 2^53 - 1, as digits.
const String _maxSafeInt = '9007199254740991';

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

  /// The number as written to the file. For a cell the reader returns,
  /// the file's number normalized to this form: a leading `+` and a
  /// trailing `.` are dropped, `.5` becomes `0.5`, a zero loses its sign
  /// (`-0` is `0`) and an exponent is applied (`1.5E3` is `1500`, with no
  /// leading zeros); without one the digits are kept as written (`1234.50`
  /// and `007` stay).
  final String digits;

  /// The number as a `double`, rounded to the nearest representable value:
  /// `0.0` (or `-0.0`) when it is too small and `double.infinity` (or its
  /// negative) when it is too large, which any long number read from a
  /// file can be, not only one written with an exponent (up to 400).
  double toDouble() => double.parse(digits);

  /// The number as an `int`, or `null` when it is not a whole number or its
  /// magnitude exceeds 2^53 - 1 (9007199254740991).
  ///
  /// A fraction of zeros only (`12.000`) counts as whole. The limit is the
  /// largest integer a web `double` holds exactly, so the result is the same
  /// on the VM and the web. The magnitude is compared as text before parsing,
  /// so digits of any length are safe.
  int? toIntOrNull() {
    final int point = digits.indexOf('.');
    final String fraction = point < 0 ? '' : digits.substring(point + 1);
    if (fraction.replaceAll('0', '').isNotEmpty) {
      return null;
    }
    final bool negative = digits.startsWith('-');
    final String whole = digits.substring(
      negative ? 1 : 0,
      point < 0 ? digits.length : point,
    );
    int start = 0;
    while (start < whole.length - 1 && whole.codeUnitAt(start) == 0x30) {
      start++;
    }
    final String magnitude = whole.substring(start);
    if (magnitude.length > _maxSafeInt.length ||
        (magnitude.length == _maxSafeInt.length &&
            magnitude.compareTo(_maxSafeInt) > 0)) {
      return null;
    }
    final int value = int.parse(magnitude);
    return negative ? -value : value;
  }

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
/// [ArgumentError] when the cell is written. So does a [text] that is empty
/// after its leading `=`, longer than 8,192 UTF-16 code units or holding a
/// character XML forbids (named `text`, the cell in the message). Its
/// syntax is not checked.
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
