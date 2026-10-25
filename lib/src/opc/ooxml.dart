/// XML namespaces, relationship types and content types of an XLSX package.
///
/// Ported from quds_office_engine `lib/src/xml/namespaces.dart` at commit 15c5d29.
/// Ported from quds_office_engine `lib/src/opc/content_types.dart` at commit 15c5d29.
/// Ported: the namespace URIs, relationship types and content types that a
/// spreadsheet package uses (`OfficeNamespaces`, `OfficeContentTypes`),
/// regrouped as [Ns], [RelType] and [ContentType]. What changed: the Word,
/// PowerPoint, VML and other constants nothing in the XLSX writer needs are
/// not ported. The values are the ECMA-376 transitional ones and none differs
/// from Quds; [Ns.x14] and [Ns.xm], Microsoft's extension namespaces for the
/// Excel 2010 conditional formats, are new.
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
      'http://schemas.openxmlformats.org/officeDocument/2006/extended-properties';

  /// SpreadsheetML 2009 (`x14:`), Excel 2010's extensions (MS-XLSX):
  /// the data bars and icon sets of its conditional formats.
  static const String x14 =
      'http://schemas.microsoft.com/office/spreadsheetml/2009/9/main';

  /// Excel 2006 main (`xm:`, MS-XLSX): the formulas (`xm:f`) and ranges
  /// (`xm:sqref`) inside Excel 2010 extensions.
  static const String xm =
      'http://schemas.microsoft.com/office/excel/2006/main';
}

/// Relationship type URIs.
abstract final class RelType {
  /// The main document part of the package, the workbook.
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

  /// A relationships part (`.rels`).
  static const String relationships =
      'application/vnd.openxmlformats-package.relationships+xml';

  /// Generic XML.
  static const String xml = 'application/xml';
}
