/// Excel's hard size limits and the error raised when one is exceeded.
///
/// The figures come from Microsoft's "Excel specifications and limits" page,
/// except where a constant names ECMA-376.
/// This file is new in jet_office; Quds has no equivalent.
library;

/// The size limits of an Excel workbook, as published by Microsoft.
///
/// Callers that write more data than fits split it across sheets themselves,
/// using these constants together with the sheet writer's row count.
abstract final class XlsxLimits {
  /// The maximum number of rows in a worksheet.
  static const int maxRows = 1048576;

  /// The maximum number of columns in a worksheet (column `XFD`).
  static const int maxColumns = 16384;

  /// The maximum length of the text in a single cell, in UTF-16 code units.
  static const int maxCellTextLength = 32767;

  /// The maximum length of a sheet name, in UTF-16 code units.
  static const int maxSheetNameLength = 31;

  /// The maximum number of unique cell formats in a workbook.
  static const int maxCellFormats = 65490;

  /// The maximum number of unique fonts in a workbook. The default font
  /// counts as one.
  static const int maxFonts = 512;

  /// The maximum number of custom number formats in a workbook.
  ///
  /// Microsoft's "Excel specifications and limits" page gives 200 to 250,
  /// depending on the language version of Excel. The lowest figure is used,
  /// so a workbook opens in every language version.
  static const int maxNumberFormats = 200;

  /// The widest a column can be, in characters of the default font.
  ///
  /// Microsoft's "Excel specifications and limits" page: column width 255
  /// characters. A wider column is a programmer error and throws
  /// [ArgumentError] when the columns are set.
  static const int maxColumnWidth = 255;

  /// The tallest a row can be, in points.
  ///
  /// Microsoft's "Excel specifications and limits" page: row height 409
  /// points. A taller row is a programmer error and throws [ArgumentError].
  static const int maxRowHeight = 409;

  /// The deepest outline (grouping) level of a row or column; 0 is not
  /// grouped.
  ///
  /// ECMA-376 Part 1 types `outlineLevel` of `row` (§18.3.1.73) and `col`
  /// (§18.3.1.13) as an unsigned byte; Excel accepts 0 to 7, eight levels
  /// counting the ungrouped one. A deeper level throws [ArgumentError].
  static const int maxOutlineLevel = 7;

  /// The maximum number of hyperlinks in a worksheet. No writer enforces it
  /// yet; the sheet writer will once it can write hyperlinks.
  static const int maxHyperlinksPerSheet = 65530;
}

/// Thrown when a write would exceed one of the [XlsxLimits].
///
/// Reaching a limit is a programmer error, not a data problem: callers are
/// expected to split their data before they get there, so this is an [Error].
final class XlsxLimitError extends Error {
  /// Creates an error for the limit named [limit] (for example `rows`) whose
  /// maximum is [max].
  XlsxLimitError(this.limit, this.max);

  /// A short name of the exceeded limit, such as `rows` or `columns`.
  final String limit;

  /// The maximum Excel allows for [limit].
  final int max;

  @override
  String toString() =>
      "XlsxLimitError: $limit exceeds Excel's maximum of $max.";
}
