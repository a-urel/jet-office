/// Excel's hard size limits and the error raised when one is exceeded.
///
/// The figures come from Microsoft's "Excel specifications and limits" page.
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

  /// The maximum number of characters in a single cell.
  static const int maxCellTextLength = 32767;

  /// The maximum number of characters in a sheet name.
  static const int maxSheetNameLength = 31;

  /// The maximum number of unique cell formats in a workbook.
  static const int maxCellFormats = 65490;

  /// The maximum number of hyperlinks in a worksheet.
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
