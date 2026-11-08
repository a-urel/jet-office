/// XML namespaces, relationship types and content types of XLSX and DOCX
/// packages.
///
/// Ported from quds_office_engine `lib/src/xml/namespaces.dart` at commit 15c5d29.
/// Ported from quds_office_engine `lib/src/opc/content_types.dart` at commit 15c5d29.
/// Ported: the namespace URIs, relationship types and content types that a
/// spreadsheet package uses (`OfficeNamespaces`, `OfficeContentTypes`),
/// regrouped as [Ns], [RelType] and [ContentType]. The drawing namespaces
/// (Quds' `xdr` and `a`) and the VML namespaces (Quds' `v` and `o`) are
/// [Ns.xdr], [Ns.drawingMain], [Ns.vml] and [Ns.vmlOffice]; the `drawing`,
/// `image` and `comments` relationship types and the drawing, PNG and JPEG
/// content types come from Quds too. What changed: the Word, PowerPoint and
/// other constants nothing in the XLSX writer needs are not ported. The
/// values are the ECMA-376 transitional ones, and no ported value differs
/// from Quds. New: [Ns.x14] and [Ns.xm], Microsoft's extension namespaces
/// for the Excel 2010 conditional formats; [Ns.vmlExcel], the Excel VML
/// namespace of notes, which Quds lacks; the `vmlDrawing` and `table`
/// relationship types; and the comments, VML drawing and table content
/// types. The WordprocessingML names ([Ns.w], [Ns.w14], [Ns.wp], [Ns.mc],
/// [Ns.wStrict], the settings, web settings, font table, theme, numbering,
/// header and footer relationship types, and the `wml…` and theme content
/// types) are new too, with the ECMA-376 transitional values. So are the
/// other main part types of SpreadsheetML (`sml…`: macro-enabled, template
/// and binary) and PresentationML (`pml…`), by which the DOCX reader
/// recognises and refuses a workbook or a presentation.
library;

/// XML namespace URIs.
abstract final class Ns {
  /// SpreadsheetML main: the default namespace of workbook, worksheet,
  /// styles and shared-string parts.
  static const String main =
      'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

  /// Office document relationships (`r:`), used for `r:id` attributes.
  static const String rel =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  /// Open Packaging Conventions relationships part.
  static const String packageRel =
      'http://schemas.openxmlformats.org/package/2006/relationships';

  /// Open Packaging Conventions `[Content_Types].xml`.
  static const String contentTypes =
      'http://schemas.openxmlformats.org/package/2006/content-types';

  /// Core properties (`cp:`).
  static const String core =
      'http://schemas.openxmlformats.org/package/2006/metadata/core-properties';

  /// Dublin Core elements (`dc:`).
  static const String dc = 'http://purl.org/dc/elements/1.1/';

  /// Dublin Core terms (`dcterms:`).
  static const String dcterms = 'http://purl.org/dc/terms/';

  /// Dublin Core types (`dcmitype:`).
  static const String dcmitype = 'http://purl.org/dc/dcmitype/';

  /// XML Schema instance (`xsi:`).
  static const String xsi = 'http://www.w3.org/2001/XMLSchema-instance';

  /// Extended (application) properties, `docProps/app.xml`.
  static const String extendedProperties =
      'http://schemas.openxmlformats.org/officeDocument/2006/'
      'extended-properties';

  /// Custom properties, `docProps/custom.xml`.
  static const String customProperties =
      'http://schemas.openxmlformats.org/officeDocument/2006/custom-properties';

  /// Document property value types (`vt:`), used by `docProps/custom.xml`.
  static const String docPropsVTypes =
      'http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes';

  /// SpreadsheetML 2009 (`x14:`), Excel 2010's extensions (MS-XLSX):
  /// the data bars and icon sets of its conditional formats.
  static const String x14 =
      'http://schemas.microsoft.com/office/spreadsheetml/2009/9/main';

  /// Excel 2006 main (`xm:`, MS-XLSX): the formulas (`xm:f`) and ranges
  /// (`xm:sqref`) inside Excel 2010 extensions.
  static const String xm =
      'http://schemas.microsoft.com/office/excel/2006/main';

  /// Spreadsheet DrawingML (`xdr:`), the root namespace of a drawing part.
  static const String xdr =
      'http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing';

  /// DrawingML main (`a:`), the shapes and pictures inside a drawing.
  static const String drawingMain =
      'http://schemas.openxmlformats.org/drawingml/2006/main';

  /// VML (`v:`), the shapes of a VML drawing part.
  static const String vml = 'urn:schemas-microsoft-com:vml';

  /// Office VML (`o:`), the shape layout and ids of a VML drawing part.
  static const String vmlOffice = 'urn:schemas-microsoft-com:office:office';

  /// Excel VML (`x:`), the `x:ClientData` that ties a VML shape to a note's
  /// cell.
  static const String vmlExcel = 'urn:schemas-microsoft-com:office:excel';

  /// WordprocessingML main (`w:`), the namespace of document, styles,
  /// settings and numbering parts.
  static const String w =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

  /// Word 2010 extensions (`w14:`, MS-DOCX).
  static const String w14 =
      'http://schemas.microsoft.com/office/word/2010/wordml';

  /// WordprocessingML drawing (`wp:`), the inline and anchored pictures of a
  /// document.
  static const String wp =
      'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing';

  /// Markup compatibility (`mc:`), `mc:Ignorable` and `mc:AlternateContent`.
  static const String mc =
      'http://schemas.openxmlformats.org/markup-compatibility/2006';

  /// WordprocessingML main in Strict OOXML, which is not read.
  static const String wStrict =
      'http://purl.oclc.org/ooxml/wordprocessingml/main';
}

/// Relationship type URIs.
abstract final class RelType {
  /// The main part of the package: the workbook of an XLSX, the document of
  /// a DOCX.
  static const String officeDocument =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument';

  /// A worksheet.
  static const String worksheet =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet';

  /// The styles part.
  static const String styles =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles';

  /// The shared-string table.
  static const String sharedStrings =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings';

  /// A hyperlink to an external target; used with `TargetMode="External"`.
  static const String hyperlink =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink';

  /// Core properties, `docProps/core.xml`. Note the `package` namespace.
  static const String coreProperties =
      'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties';

  /// Extended properties, `docProps/app.xml`.
  static const String extendedProperties =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties';

  /// Custom properties, `docProps/custom.xml`.
  static const String customProperties =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/custom-properties';

  /// A worksheet's drawing part, which holds its pictures.
  static const String drawing =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing';

  /// An image part, such as `xl/media/image1.png`, from a drawing.
  static const String image =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/image';

  /// A worksheet's comments part, the text of its notes.
  static const String comments =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments';

  /// A worksheet's VML drawing part, the boxes of its notes.
  static const String vmlDrawing =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/vmlDrawing';

  /// A table part of a worksheet.
  static const String table =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/table';

  /// The calculation chain, the order in which Excel last calculated the
  /// formula cells.
  static const String calcChain =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/calcChain';

  /// The document settings part (`word/settings.xml`).
  static const String settings =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings';

  /// The web settings part (`word/webSettings.xml`).
  static const String webSettings =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/webSettings';

  /// The font table part (`word/fontTable.xml`).
  static const String fontTable =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/fontTable';

  /// A theme part (`word/theme/theme1.xml`).
  static const String theme =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme';

  /// The numbering definitions part (`word/numbering.xml`).
  static const String numbering =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering';

  /// A header part of a document.
  static const String header =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/header';

  /// A footer part of a document.
  static const String footer =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer';

  /// The main document part in a Strict OOXML package. A Strict file is
  /// recognised by this type and refused; it is not read.
  static const String officeDocumentStrict =
      'http://purl.oclc.org/ooxml/officeDocument/relationships/officeDocument';
}

/// Content types (MIME types) of package parts.
abstract final class ContentType {
  /// The workbook part.
  static const String workbook =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml';

  /// A worksheet part.
  static const String worksheet =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml';

  /// The styles part.
  static const String styles =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml';

  /// The shared-string table part.
  static const String sharedStrings =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml';

  /// The core properties part.
  static const String coreProperties =
      'application/vnd.openxmlformats-package.core-properties+xml';

  /// The extended properties part.
  static const String extendedProperties =
      'application/vnd.openxmlformats-officedocument.extended-properties+xml';

  /// The custom properties part.
  static const String customProperties =
      'application/vnd.openxmlformats-officedocument.custom-properties+xml';

  /// A relationships part (`.rels`).
  static const String relationships =
      'application/vnd.openxmlformats-package.relationships+xml';

  /// Generic XML.
  static const String xml = 'application/xml';

  /// A drawing part.
  static const String drawing =
      'application/vnd.openxmlformats-officedocument.drawing+xml';

  /// A worksheet's comments part.
  static const String comments =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.comments+xml';

  /// A VML drawing part (`.vml`).
  static const String vmlDrawing =
      'application/vnd.openxmlformats-officedocument.vmlDrawing';

  /// A table part.
  static const String table =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.table+xml';

  /// A PNG image.
  static const String png = 'image/png';

  /// A JPEG image.
  static const String jpeg = 'image/jpeg';

  /// The main part of a Word document.
  static const String wmlDocument =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml';

  /// The main part of a Word template.
  static const String wmlTemplate =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.template.main+xml';

  /// The main part of a macro-enabled Word document.
  static const String wmlMacroDocument =
      'application/vnd.ms-word.document.macroEnabled.main+xml';

  /// The main part of a macro-enabled Word template.
  static const String wmlMacroTemplate =
      'application/vnd.ms-word.template.macroEnabledTemplate.main+xml';

  /// The styles part of a Word document.
  static const String wmlStyles =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml';

  /// A header part of a Word document (`word/header1.xml`).
  static const String wmlHeader =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml';

  /// A footer part of a Word document (`word/footer1.xml`).
  static const String wmlFooter =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml';

  /// The footnotes part of a Word document (`word/footnotes.xml`).
  static const String wmlFootnotes =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml';

  /// The endnotes part of a Word document (`word/endnotes.xml`).
  static const String wmlEndnotes =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.endnotes+xml';

  /// The comments part of a Word document (`word/comments.xml`).
  static const String wmlComments =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml';

  /// The numbering part of a Word document (`word/numbering.xml`).
  static const String wmlNumbering =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml';

  /// The settings part of a Word document.
  static const String wmlSettings =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml';

  /// The font table part of a Word document.
  static const String wmlFontTable =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.fontTable+xml';

  /// The web settings part of a Word document.
  static const String wmlWebSettings =
      'application/vnd.openxmlformats-officedocument.wordprocessingml.webSettings+xml';

  /// A theme part.
  static const String theme =
      'application/vnd.openxmlformats-officedocument.theme+xml';

  /// The main part of a macro-enabled workbook (`.xlsm`).
  static const String smlMacroWorkbook =
      'application/vnd.ms-excel.sheet.macroEnabled.main+xml';

  /// The main part of a workbook template (`.xltx`).
  static const String smlTemplate =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.template.main+xml';

  /// The main part of a macro-enabled workbook template (`.xltm`).
  static const String smlMacroTemplate =
      'application/vnd.ms-excel.template.macroEnabled.main+xml';

  /// The main part of a binary workbook (`.xlsb`), which is not XML.
  static const String smlBinaryWorkbook =
      'application/vnd.ms-excel.sheet.binary.macroEnabled.main';

  /// The main part of a presentation (`.pptx`).
  static const String pmlPresentation =
      'application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml';

  /// The main part of a presentation template (`.potx`).
  static const String pmlTemplate =
      'application/vnd.openxmlformats-officedocument.presentationml.template.main+xml';

  /// The main part of a slide show (`.ppsx`).
  static const String pmlSlideshow =
      'application/vnd.openxmlformats-officedocument.presentationml.slideshow.main+xml';

  /// The main part of a macro-enabled presentation (`.pptm`).
  static const String pmlMacroPresentation =
      'application/vnd.ms-powerpoint.presentation.macroEnabled.main+xml';

  /// The main part of a macro-enabled presentation template (`.potm`).
  static const String pmlMacroTemplate =
      'application/vnd.ms-powerpoint.template.macroEnabled.main+xml';

  /// The main part of a macro-enabled slide show (`.ppsm`).
  static const String pmlMacroSlideshow =
      'application/vnd.ms-powerpoint.slideshow.macroEnabled.main+xml';
}
