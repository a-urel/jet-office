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
/// ([OfficeLocale]). A programmer error is thrown instead: [ArgumentError]
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
/// ZIP directory, the content types, the package and workbook
/// relationships, the workbook and its styles. [XlsxReader.sheets] lists
/// each [XlsxReadSheet], and [XlsxReader.date1904] gives the date system.
/// [XlsxReader.rows] (by name) and [XlsxReader.rowsAt] (by index) parse a
/// sheet lazily as its [XlsxReadRow]s are taken, each holding
/// [XlsxReadCell]s whose values are `String`, `bool`, [XlsxDecimal],
/// `DateTime`, `Duration`, [XlsxErrorValue] or `null`. A cell also carries
/// its formula text, its [XlsxFormulaGroup] and its number format
/// ([XlsxReadCell.numberFormatId], [XlsxReadCell.numberFormat],
/// [XlsxReadCell.isDate]). [XlsxReader.merges] and [XlsxReader.mergesAt]
/// list a sheet's merged ranges.
///
/// A file that cannot be read at all (not a ZIP, encrypted, a legacy
/// `.xls`, malformed XML, or past one of the [XlsxReadLimits]) throws an
/// [XlsxReadException] whose [XlsxReadFailure] says why; a cell or sheet
/// that cannot be read exactly is kept as far as possible and reported in
/// [XlsxReader.warnings], with the same [XlsxWarning] type the writers use.
/// A sheet's warnings are complete once its rows have been iterated to the
/// end, except [XlsxWarningCode.mergeRangeInvalid], which appears only once
/// its merges are read ([XlsxReader.merges] or [XlsxReader.mergesAt]).
/// Reading is synchronous, like writing: for a responsive user
/// interface, run the reader in an isolate or a web worker too, and send
/// the values it reads back to the caller.
///
/// [NumberFormatter], from the jet_core package that holds the number format
/// engine (decision 0012), shows a cell value as Excel for Mac does: it
/// applies the cell's number format code with the separators and words of
/// a [FormatLocale] and returns a [FormattedValue], whose text is what the
/// cell shows and whose parts mark the padding and fill a viewer lays out.
/// jet_office re-exports the engine's types, so a caller needs no import of
/// jet_core. [XlsxCellFormatting.formatCell] takes an [XlsxReadCell]
/// directly. A code the engine cannot read shows as `General`, and the
/// result's [FormattedValue.warning] says so; [XlsxFormatWarning.xlsxCode]
/// gives the [XlsxWarningCode] of that [FormatWarning], and
/// [XlsxFormatColor.xlsxColor] the [XlsxColor] of a [FormattedValue.color].
/// [XlsxDecimal] and [XlsxErrorValue] are the engine's [FormatDecimal] and
/// [FormatErrorValue], so a cell's value goes to it unconverted.
///
/// [XlsxWorkbook] is the workbook model: [XlsxWorkbook.open] reads a file,
/// within the same [XlsxReadLimits] and with the same [XlsxReadException]s
/// as the reader, and [XlsxWorkbook.new] starts an empty one. Its
/// [XlsxSheet]s load on first use; [XlsxSheet.cellAt] and [XlsxSheet.rows]
/// return the reader's [XlsxReadCell]s and [XlsxReadRow]s, and
/// [XlsxSheet.setCell] takes the writer's values (strings, numbers, `bool`,
/// `DateTime`, [XlsxDate], [XlsxDecimal], [XlsxFormula], an [XlsxCell] of
/// them and `null`), checked and repaired as the writer does.
/// [XlsxSheet.styleAt] and [XlsxSheet.setStyle] read and set a cell's
/// [XlsxStyle], [XlsxSheet.rowFormat] and [XlsxSheet.setRowFormat] a row's
/// [XlsxRowFormat], [XlsxSheet.column] and [XlsxSheet.setColumn] an
/// [XlsxColumn]; [XlsxSheet.merges], [XlsxSheet.merge] and
/// [XlsxSheet.unmerge] the merged ranges; [XlsxSheet.view],
/// [XlsxSheet.tabColor] and [XlsxSheet.visibility] how a sheet shows.
/// [XlsxWorkbook.activeSheet] is the sheet Excel opens on, and
/// [XlsxWorkbook.resolveColor] gives the colour an [XlsxColor] shows, from
/// the theme or [XlsxWorkbook.indexedColors]. A style is appended to the
/// styles, so no existing index moves. [XlsxWorkbook.save] returns an
/// [XlsxResult] and [XlsxWorkbook.saveTo] streams to a sink. Saving keeps
/// every part the model did not change: what it never loaded is copied from
/// the file, and what it does not understand inside a part it loaded is kept
/// as written, so an opened file comes back with only the cells that were
/// set changed.
///
/// [DocxDocument] is the Word document model, in progress (milestones D1 to
/// D3; the API may change before D6). [DocxDocument.new] starts a document
/// like Word for Mac's blank one: A4 portrait, Aptos 12, no document
/// properties.
/// [DocxDocument.open] reads a DOCX file within [DocxReadLimits]; a file it
/// cannot read throws a [DocxReadException] whose [DocxReadFailure] says why,
/// and so does a part that turns out broken when it first loads. Its
/// [DocxBody] loads on first access and holds the [DocxBlock]s of the
/// document: each [DocxParagraph] holds [DocxInline]s, and each [DocxRun]
/// holds [DocxRunContent] (text, tabs, breaks), with the paragraph and run
/// style typed, and [DocxRunProperties] and [DocxParagraphProperties] that
/// give the formatting (bold, size, colour, alignment, indentation,
/// borders, tab stops and the rest of the typed members) as values such as
/// [DocxColor] and [DocxIndentation], where `null` means "not set here"; a
/// property or value the model does not understand is kept as written and
/// reads `null`. A [DocxTable] gives its rows and cells, and a cell its
/// blocks; the table, the row and the cell give their formatting as
/// [DocxTableProperties], [DocxTableRowProperties] and
/// [DocxTableCellProperties]. [DocxBody.addTable] adds a table as Word's Insert
/// Table writes it, with the document's `Table Grid` style, and
/// [DocxTable.addRow] fills it row by row with text; [DocxTableCell.addTable]
/// nests one. Rows, cells and blocks of a cell are added, removed and replaced
/// like the blocks of the body, [DocxTable.mergeCells] merges a range, and a
/// table built in no document, or read in another, has its styles resolved when
/// it goes in. A table lists only its typed rows and cells (one inside a
/// content control is kept in place, not listed), the API nests tables at most
/// 80 deep, [DocxBody.addTable] takes at most [maxTableColumns] columns, and
/// a table with no row is not saved. What the model does not type yet, such as content controls,
/// tracked changes, hyperlinks, drawings and fields, is kept as written in a
/// [DocxOpaqueBlock], a [DocxOpaqueInline] or a [DocxOpaqueRunContent], which
/// can be removed but not changed; the final section and the parts other than
/// the body are kept as written too. Blocks and inlines are added, removed and
/// replaced, and a run's text and the styles are set; each edit is atomic.
/// [DocxDocument.save] returns a [DocxResult] and [DocxDocument.saveTo] streams
/// to a sink. As for a workbook, saving keeps every part the model did not
/// change: a body never accessed is copied from the file, and what a loaded
/// body does not type is written back as it was. Characters XML forbids are
/// removed from text when it is set and reported at save as a [DocxWarning].
/// The visible text of an opaque inline holding `mc:AlternateContent` or a text
/// box is empty.
///
/// [DocxDocument.styles] gives the document's [DocxStyles] (milestone D2):
/// the [DocxDocumentDefaults] and each [DocxStyle] of the styles part, by
/// id or by name, whose name, links and [DocxParagraphProperties] and
/// [DocxRunProperties] are set like a paragraph's; [DocxStyles.add] adds a
/// custom style, and [DocxBuiltInStyle] names Word's built-in styles, which
/// are found by their English name and added with Word's definition on
/// demand, so that `style = 'Heading1'` lands on `Balk1` in a Turkish
/// document. The styles part loads on first access, a part nothing changed
/// is saved as it was read, and a document without one gains it at save once
/// it holds something. A style set through the API that the document does
/// not define is reported at save ([DocxWarningCode.styleNotFound]).
///
/// [DocxDocument.numbering] gives the document's lists, a [DocxNumbering]:
/// each [DocxAbstractNumbering] holds the [DocxNumberingLevel]s that say
/// how a level is numbered ([DocxNumberFormat], [DocxLevelAlignment]),
/// and each [DocxNumberingInstance], which a paragraph names through
/// [DocxNumberingInstance.ref], uses one of them, with a
/// [DocxLevelOverride] per level whose start it changes.
/// [DocxNumbering.addBulletList] and [DocxNumbering.addNumberedList] add the
/// lists Word's Bullets and Numbering buttons write, [DocxBody.addListItem]
/// puts a paragraph in one, and [DocxNumbering.addInstance] starts a new
/// list of a definition. A paragraph put in a list the document does not
/// define is reported at save ([DocxWarningCode.numberingNotFound]).
///
/// This file is the whole public API. Everything under `lib/src/` is private,
/// and a type is public only once it is exported here.
///
/// @docImport 'package:jet_core/jet_core.dart';
/// @docImport 'src/common/locale.dart';
/// @docImport 'src/docx/builtin_styles.dart';
/// @docImport 'src/docx/docx_document.dart';
/// @docImport 'src/docx/model/blocks.dart';
/// @docImport 'src/docx/model/formatting.dart';
/// @docImport 'src/docx/model/inlines.dart';
/// @docImport 'src/docx/model/numbering.dart';
/// @docImport 'src/docx/model/numbering_formats.dart';
/// @docImport 'src/docx/model/paragraph_properties.dart';
/// @docImport 'src/docx/model/run_content.dart';
/// @docImport 'src/docx/model/run_properties.dart';
/// @docImport 'src/docx/model/styles.dart';
/// @docImport 'src/docx/model/table_formatting.dart';
/// @docImport 'src/docx/model/table_properties.dart';
/// @docImport 'src/docx/read_exception.dart';
/// @docImport 'src/docx/read_limits.dart';
/// @docImport 'src/docx/warnings.dart';
/// @docImport 'src/xlsx/cell_formatting.dart';
/// @docImport 'src/xlsx/color.dart';
/// @docImport 'src/xlsx/column.dart';
/// @docImport 'src/xlsx/hyperlink.dart';
/// @docImport 'src/xlsx/limits.dart';
/// @docImport 'src/xlsx/list_export.dart';
/// @docImport 'src/xlsx/model/xlsx_sheet.dart';
/// @docImport 'src/xlsx/model/xlsx_workbook.dart';
/// @docImport 'src/xlsx/read/read_cell.dart';
/// @docImport 'src/xlsx/read/read_exception.dart';
/// @docImport 'src/xlsx/read/read_limits.dart';
/// @docImport 'src/xlsx/read/xlsx_reader.dart';
/// @docImport 'src/xlsx/rich_text.dart';
/// @docImport 'src/xlsx/row_format.dart';
/// @docImport 'src/xlsx/sheet_writer.dart';
/// @docImport 'src/xlsx/style.dart';
/// @docImport 'src/xlsx/values.dart';
/// @docImport 'src/xlsx/warnings.dart';
/// @docImport 'src/xlsx/xlsx_writer.dart';
library;

export 'package:jet_core/jet_core.dart'
    show
        FormatDecimal,
        FormatErrorValue,
        FormatColor,
        FormatFill,
        FormatLocale,
        FormatPadding,
        FormatPart,
        FormatText,
        FormatWarning,
        FormattedValue,
        NumberFormatter;
export 'src/common/image.dart' show OfficeImage, OfficeImageFormat;
export 'src/common/locale.dart' show OfficeLocale;
export 'src/docx/builtin_styles.dart' show DocxBuiltInStyle;
export 'src/docx/docx_document.dart' show DocxBody, DocxDocument, DocxResult;
export 'src/docx/model/blocks.dart'
    show
        DocxBlock,
        DocxOpaqueBlock,
        DocxParagraph,
        DocxTable,
        DocxTableCell,
        DocxTableRow;
export 'src/docx/model/formatting.dart'
    show
        DocxAlignment,
        DocxBorder,
        DocxBorderStyle,
        DocxColor,
        DocxFonts,
        DocxHighlight,
        DocxIndentation,
        DocxLineRule,
        DocxLineSpacing,
        DocxNumberingRef,
        DocxParagraphBorders,
        DocxShading,
        DocxShadingPattern,
        DocxSpacing,
        DocxTabAlignment,
        DocxTabLeader,
        DocxTabStop,
        DocxThemeColor,
        DocxUnderline,
        DocxUnderlineStyle,
        DocxVerticalAlign;
export 'src/docx/model/inlines.dart' show DocxInline, DocxOpaqueInline, DocxRun;
export 'src/docx/model/numbering.dart'
    show
        DocxAbstractNumbering,
        DocxLevelOverride,
        DocxNumbering,
        DocxNumberingInstance,
        DocxNumberingLevel,
        DocxNumberingLevelProperty;
export 'src/docx/model/numbering_formats.dart'
    show DocxLevelAlignment, DocxNumberFormat;
export 'src/docx/model/paragraph_properties.dart'
    show DocxParagraphProperties, DocxParagraphProperty;
export 'src/docx/model/run_content.dart'
    show
        DocxBreak,
        DocxBreakType,
        DocxCarriageReturn,
        DocxOpaqueRunContent,
        DocxRunContent,
        DocxTab,
        DocxText;
export 'src/docx/model/run_properties.dart'
    show DocxRunProperties, DocxRunProperty;
export 'src/docx/model/styles.dart'
    show DocxDocumentDefaults, DocxStyle, DocxStyleType, DocxStyles;
export 'src/docx/model/table_formatting.dart'
    show
        DocxCellAlignment,
        DocxCellBorders,
        DocxRowHeight,
        DocxRowHeightRule,
        DocxTableAlignment,
        DocxTableBorders,
        DocxTableLayout,
        DocxTableLook,
        DocxTableMargins,
        DocxTableWidth,
        DocxTableWidthKind,
        DocxTextDirection,
        DocxVerticalMerge;
export 'src/docx/model/table_properties.dart'
    show
        DocxTableCellProperties,
        DocxTableCellProperty,
        DocxTableProperties,
        DocxTableProperty,
        DocxTableRowProperties,
        DocxTableRowProperty,
        maxTableColumns;
export 'src/docx/read_exception.dart' show DocxReadException, DocxReadFailure;
export 'src/docx/read_limits.dart' show DocxReadLimits;
export 'src/docx/warnings.dart' show DocxWarning, DocxWarningCode;
export 'src/xlsx/alignment.dart'
    show
        XlsxAlignment,
        XlsxHorizontalAlignment,
        XlsxProtection,
        XlsxReadingOrder,
        XlsxVerticalAlignment;
export 'src/xlsx/border.dart' show XlsxBorder, XlsxBorderSide, XlsxBorderStyle;
export 'src/xlsx/cell_formatting.dart'
    show XlsxCellFormatting, XlsxFormatColor, XlsxFormatWarning;
export 'src/xlsx/color.dart' show XlsxColor, XlsxColorKind;
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
export 'src/xlsx/limits.dart' show XlsxLimitError, XlsxLimits;
export 'src/xlsx/list_export.dart' show XlsxListColumn, XlsxListExport;
export 'src/xlsx/model/xlsx_sheet.dart' show XlsxSheet;
export 'src/xlsx/model/xlsx_workbook.dart' show XlsxWorkbook;
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
export 'src/xlsx/row_format.dart' show XlsxRowFormat;
export 'src/xlsx/sheet_protection.dart'
    show XlsxSheetProtection, XlsxWorkbookProtection;
export 'src/xlsx/sheet_view.dart'
    show XlsxPane, XlsxSheetView, XlsxSheetVisibility;
export 'src/xlsx/sheet_writer.dart' show XlsxSheetWriter;
export 'src/xlsx/style.dart' show XlsxStyle;
export 'src/xlsx/table.dart'
    show XlsxTable, XlsxTableColumn, XlsxTableStyle, XlsxTotalsFunction;
export 'src/xlsx/values.dart' show XlsxCell, XlsxDate, XlsxDecimal, XlsxFormula;
export 'src/xlsx/warnings.dart' show XlsxWarning, XlsxWarningCode;
export 'src/xlsx/xlsx_writer.dart'
    show XlsxResult, XlsxStreamWriter, XlsxWriter, XlsxWriterBase;
