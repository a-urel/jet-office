/// Excel's hard size limits and the error raised when one is exceeded.
///
/// The figures come from Microsoft's "Excel specifications and limits" page,
/// except where a constant names another source: ECMA-376, another
/// Microsoft page or an Excel dialog.
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

  /// The maximum number of hyperlinks in a worksheet.
  ///
  /// Microsoft's "Excel specifications and limits" page: hyperlinks in a
  /// worksheet, 65,530. A sheet's 65,531st link throws [XlsxLimitError]
  /// (`hyperlinks`) from the sheet writer's `row`, before its cell is
  /// written.
  static const int maxHyperlinksPerSheet = 65530;

  /// The longest hyperlink address, in UTF-16 code units, counted as
  /// written (after percent-encoding).
  ///
  /// The M3 plan sets 2,079, the length Excel's own Insert Hyperlink
  /// dialog accepts. A longer address throws [ArgumentError] when its cell
  /// is written. The value is not on Microsoft's "Excel specifications and
  /// limits" page, which counts hyperlinks but gives no address length.
  static const int maxHyperlinkAddressLength = 2079;

  /// The longest ScreenTip (hyperlink tooltip), in UTF-16 code units.
  ///
  /// The M3 plan sets 255, the length Excel's Set Hyperlink ScreenTip
  /// dialog accepts. A longer tooltip throws [ArgumentError] when its cell
  /// is written.
  static const int maxScreenTipLength = 255;

  /// The longest defined name, in UTF-16 code units. A longer name throws
  /// [ArgumentError] when it is registered.
  ///
  /// Microsoft's "Names in formulas" support page: "A name can contain up
  /// to 255 characters." Its "Excel specifications and limits" page counts
  /// names (limited by memory) but gives no length.
  static const int maxDefinedNameLength = 255;

  /// The longest comment of a defined name, in UTF-16 code units.
  ///
  /// Microsoft's "Names in formulas" support page gives 255 for the
  /// comment (the "additional information about the name").
  static const int maxDefinedNameCommentLength = 255;

  /// The longest name of a custom document property, in UTF-16 code units.
  ///
  /// The M3 plan sets 255, the length of Excel's Custom Properties name box.
  /// The value is not on Microsoft's "Excel specifications and limits"
  /// page.
  static const int maxCustomPropertyNameLength = 255;

  /// The longest title of a validation's input or error message, in UTF-16
  /// code units.
  ///
  /// The M3 plan sets 32, the length Excel's Data Validation dialog accepts
  /// for its Title fields. A longer title throws [ArgumentError] when the
  /// validation is registered. The value is not on Microsoft's "Excel
  /// specifications and limits" page.
  static const int maxValidationTitleLength = 32;

  /// The longest input or error message of a validation, in UTF-16 code
  /// units.
  ///
  /// The M3 plan sets 255, the length Excel's Data Validation dialog accepts
  /// for its message fields. A longer message throws [ArgumentError] when
  /// the validation is registered.
  static const int maxValidationMessageLength = 255;

  /// The longest inline validation list, in UTF-16 code units, counted
  /// between the outer quotes as written (a quote inside an item counts
  /// twice, a comma between items once).
  ///
  /// 255 is the limit Excel's Data Validation dialog enforces on a typed
  /// Source; the value is not on Microsoft's "Excel specifications and
  /// limits" page. A longer list throws [ArgumentError] when the validation
  /// is registered; `XlsxDataValidation.listFrom` takes a range or a name
  /// instead.
  static const int maxValidationListLength = 255;

  /// The highest rank of a top or bottom conditional-format rule: the top
  /// 1,000 items. A percent rank goes from 1 to 100 instead.
  ///
  /// 1,000 is the most Excel's Top 10 Items dialog accepts (and 100 its Top
  /// 10 % dialog); the value is not on Microsoft's "Excel specifications
  /// and limits" page. A rank outside 1 to this, or 1 to 100 for a percent,
  /// throws [ArgumentError] when the format is registered.
  static const int maxTopBottomRank = 1000;

  /// The lowest print scale of a page setup, in percent. ECMA-376 and
  /// Excel's Page Setup dialog both allow 10.
  static const int minPageScale = 10;

  /// The highest print scale of a page setup, in percent. Excel's Page Setup
  /// dialog allows 400. A scale outside 10 to this throws [ArgumentError]
  /// when the page setup is registered.
  static const int maxPageScale = 400;

  /// The most pages a page setup can fit the sheet to, wide or tall: the
  /// `unsignedShort` maximum of ECMA-376's `fitToWidth` and `fitToHeight`.
  static const int maxFitToPages = 32767;

  /// The highest first page number of a page setup: Excel's Page Setup
  /// dialog accepts up to 32,767.
  static const int maxFirstPageNumber = 32767;

  /// The highest paper size id of a page setup: ECMA-376's `paperSize`
  /// list, the one Excel uses, runs from 1 to 118.
  static const int maxPaperSize = 118;

  /// The most UTF-16 code units one header or footer text holds, field
  /// codes included: Excel's Header & Footer dialog and Microsoft's "Excel
  /// specifications and limits" page ("Characters in a header or footer")
  /// allow 255. A longer text throws [ArgumentError] when the header or
  /// footer is registered.
  static const int maxHeaderFooterLength = 255;

  /// The longest author of a note, in UTF-16 code units.
  ///
  /// The M4 plan sets 255. Microsoft's "Excel specifications and limits"
  /// page gives no figure for it, and ECMA-376 types `author` as
  /// `ST_Xstring`, without a length. A longer author throws
  /// [ArgumentError] when the note is added.
  static const int maxNoteAuthorLength = 255;
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
