/// Generates, reads and modifies XLSX and DOCX files in pure Dart.
///
/// Bytes in, bytes out: the library imports no Flutter, `dart:io` or
/// `dart:ui`, so it runs on the web, desktop, mobile and a Dart server alike.
/// It has no editors, no rendering and no PDF.
///
/// Two writers produce XLSX files with the same calls and the same bytes:
/// [XlsxWriter] keeps the file in memory and returns it from
/// [XlsxWriter.close] as an [XlsxResult], and [XlsxStreamWriter] sends it
/// to a `Sink<List<int>>` as each part finishes. Both hand out one
/// [XlsxSheetWriter] at a time from [XlsxWriterBase.addSheet]; its rows take
/// plain Dart values and the wrappers [XlsxCell], [XlsxDate],
/// [XlsxDecimal], [XlsxFormula], [XlsxHyperlink] and [XlsxRichText], styled
/// with [XlsxStyle]. [XlsxListExport] writes a whole filtered list, with an
/// optional caption and totals row, in one call.
///
/// Data the writer has to change to store, such as text with characters XML
/// forbids or a sheet name Excel refuses, is repaired and reported as an
/// [XlsxWarning], aggregated per sheet and [XlsxWarningCode].
/// [XlsxWarning.message] gives its text in English, German or Turkish
/// ([XlsxLocale]). A programmer error is thrown instead: [ArgumentError]
/// naming the field, [StateError] for a call out of order, and
/// [XlsxLimitError] past one of the [XlsxLimits]; their messages are in
/// English only.
///
/// Every call is synchronous: cells are encoded in
/// [XlsxSheetWriter.row], and `close()` writes the workbook-level parts and
/// finishes the ZIP. An `async` API would not move that work off the
/// calling thread, so the library does not offer one. To keep a user
/// interface responsive, run the writer in an isolate (`Isolate.run`) or a
/// web worker and send the bytes of the [XlsxResult], or the chunks an
/// [XlsxStreamWriter] sends to its sink, back to the caller.
///
/// [XlsxReader] reads an XLSX file from bytes, such as a user's upload for
/// a data import. It treats the file as untrusted: opening it reads only the
/// ZIP directory and the workbook, [XlsxReader.sheets] lists the sheets, and
/// [XlsxReader.rows] parses a sheet lazily as its [XlsxReadRow]s are taken,
/// each holding [XlsxReadCell]s whose values are `String`, `bool`,
/// [XlsxDecimal], `DateTime`, `Duration`, [XlsxErrorValue] or `null`;
/// [XlsxReader.merges] lists a sheet's merged ranges.
/// Reading is synchronous, like writing. A file that cannot be read at all
/// (not a ZIP, encrypted, a legacy `.xls`, malformed XML, or past one of
/// the [XlsxReadLimits]) throws an [XlsxReadException] whose
/// [XlsxReadFailure] says why; a cell or sheet that cannot be read exactly
/// is kept as far as possible and reported in [XlsxReader.warnings], with
/// the same [XlsxWarning] type the writers use.
///
/// This file is the whole public API. Everything under `lib/src/` is private,
/// and a type is public only once it is exported here.
///
/// @docImport 'src/xlsx/hyperlink.dart';
/// @docImport 'src/xlsx/limits.dart';
/// @docImport 'src/xlsx/list_export.dart';
/// @docImport 'src/xlsx/read/read_cell.dart';
/// @docImport 'src/xlsx/read/read_exception.dart';
/// @docImport 'src/xlsx/read/read_limits.dart';
/// @docImport 'src/xlsx/read/xlsx_reader.dart';
/// @docImport 'src/xlsx/rich_text.dart';
/// @docImport 'src/xlsx/sheet_writer.dart';
/// @docImport 'src/xlsx/style.dart';
/// @docImport 'src/xlsx/values.dart';
/// @docImport 'src/xlsx/warnings.dart';
/// @docImport 'src/xlsx/xlsx_writer.dart';
library;

export 'src/xlsx/alignment.dart'
    show
        XlsxAlignment,
        XlsxHorizontalAlignment,
        XlsxProtection,
        XlsxReadingOrder,
        XlsxVerticalAlignment;
export 'src/xlsx/border.dart' show XlsxBorder, XlsxBorderSide, XlsxBorderStyle;
export 'src/xlsx/color.dart' show XlsxColor;
export 'src/xlsx/column.dart' show XlsxColumn;
export 'src/xlsx/comparison.dart' show XlsxComparison;
export 'src/xlsx/conditional_format.dart'
    show
        XlsxAverageRule,
        XlsxCellValueRule,
        XlsxCfValue,
        XlsxCfValueType,
        XlsxColorScale,
        XlsxConditionalFormat,
        XlsxConditionalRule,
        XlsxDataBar,
        XlsxDataBarAxis,
        XlsxDuplicateRule,
        XlsxExpressionRule,
        XlsxIconSet,
        XlsxIconSetType,
        XlsxTextOperator,
        XlsxTextRule,
        XlsxTopBottomRule;
export 'src/xlsx/data_validation.dart'
    show XlsxDataValidation, XlsxValidationErrorStyle, XlsxValidationType;
export 'src/xlsx/defined_name.dart' show XlsxDefinedName;
export 'src/xlsx/drawing.dart'
    show
        XlsxAnchor,
        XlsxAnchorPoint,
        XlsxOneCellAnchor,
        XlsxPicture,
        XlsxPictureResize,
        XlsxTwoCellAnchor;
export 'src/xlsx/fill.dart'
    show
        XlsxFill,
        XlsxGradientFill,
        XlsxGradientStop,
        XlsxPatternFill,
        XlsxPatternType;
export 'src/xlsx/font.dart'
    show XlsxFont, XlsxFontScheme, XlsxFontScript, XlsxUnderline;
export 'src/xlsx/header_footer.dart' show XlsxHeaderFooter;
export 'src/xlsx/hyperlink.dart' show XlsxHyperlink;
export 'src/xlsx/image.dart' show XlsxImage, XlsxImageFormat;
export 'src/xlsx/limits.dart' show XlsxLimitError, XlsxLimits;
export 'src/xlsx/list_export.dart' show XlsxListColumn, XlsxListExport;
export 'src/xlsx/note.dart' show XlsxNote;
export 'src/xlsx/number_format.dart' show XlsxNumFmt;
export 'src/xlsx/page_setup.dart'
    show
        XlsxOrientation,
        XlsxPageMargins,
        XlsxPageOrder,
        XlsxPageSetup,
        XlsxPaperSize;
export 'src/xlsx/properties.dart' show XlsxProperties;
export 'src/xlsx/range.dart' show XlsxRange;
export 'src/xlsx/read/read_cell.dart'
    show
        XlsxErrorValue,
        XlsxFormulaGroup,
        XlsxFormulaGroupKind,
        XlsxReadCell,
        XlsxReadRow;
export 'src/xlsx/read/read_exception.dart'
    show XlsxReadException, XlsxReadFailure;
export 'src/xlsx/read/read_limits.dart' show XlsxReadLimits;
export 'src/xlsx/read/xlsx_reader.dart' show XlsxReadSheet, XlsxReader;
export 'src/xlsx/rich_text.dart' show XlsxRichText, XlsxTextRun;
export 'src/xlsx/sheet_protection.dart'
    show XlsxSheetProtection, XlsxWorkbookProtection;
export 'src/xlsx/sheet_view.dart'
    show XlsxPane, XlsxSheetView, XlsxSheetVisibility;
export 'src/xlsx/sheet_writer.dart' show XlsxSheetWriter;
export 'src/xlsx/style.dart' show XlsxStyle;
export 'src/xlsx/table.dart'
    show XlsxTable, XlsxTableColumn, XlsxTableStyle, XlsxTotalsFunction;
export 'src/xlsx/values.dart' show XlsxCell, XlsxDate, XlsxDecimal, XlsxFormula;
export 'src/xlsx/warnings.dart' show XlsxLocale, XlsxWarning, XlsxWarningCode;
export 'src/xlsx/xlsx_writer.dart'
    show XlsxResult, XlsxStreamWriter, XlsxWriter, XlsxWriterBase;
