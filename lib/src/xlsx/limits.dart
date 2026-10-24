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

  /// The largest font size, in points.
  ///
  /// Microsoft's "Excel specifications and limits" page: font size 409
  /// points. A larger size, or one below 1, is a programmer error and
  /// throws [ArgumentError] when the style is first used.
  static const int maxFontSize = 409;

  /// The deepest indent of a cell's text, in character widths.
  ///
  /// ECMA-376 Part 1 §18.8.1 types the `indent` of `alignment` as an
  /// unsigned integer; Excel's Format Cells dialog accepts 0 to 250. A
  /// deeper indent is a programmer error and throws [ArgumentError] when
  /// the style is first used.
  static const int maxIndent = 250;

  /// The largest text rotation in degrees, apart from
  /// [verticalTextRotation]: `0..90` turn the text counterclockwise and
  /// `91..180` clockwise by the value less 90.
  ///
  /// ECMA-376 Part 1, the `ST_TextRotation` type of the `textRotation` of
  /// `alignment` (§18.8.1). Any other value throws [ArgumentError] when the
  /// style is first used.
  static const int maxTextRotation = 180;

  /// The text rotation that stacks the letters vertically, the one value
  /// outside `0..`[maxTextRotation] that `ST_TextRotation` allows
  /// (ECMA-376 Part 1). Also `XlsxAlignment.verticalText`.
  static const int verticalTextRotation = 255;

  /// The smallest zoom of a sheet view, in percent.
  ///
  /// Microsoft's "Excel specifications and limits" page: zoom 10 to 400
  /// percent. A zoom outside that range is a programmer error and throws
  /// [ArgumentError] when the view is set.
  static const int minZoom = 10;

  /// The largest zoom of a sheet view, in percent. See [minZoom].
  static const int maxZoom = 400;

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
