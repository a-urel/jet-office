/// Reads the sheet list and date system of an XLSX workbook part.
///
/// Ported from quds_office_engine `lib/src/builders/xlsx_io.dart` at commit
/// 15c5d29: `XlsxGridReader._sheetList`.
///
/// What changed: the workbook part comes from `PackageReader.workbookPart`
/// instead of the hard-coded `/xl/workbook.xml`, and a workbook without
/// `<sheet>` has no sheets instead of an invented `Sheet1`. A sheet whose
/// relationship or part is missing is kept with a null part instead of being
/// dropped, so the caller can warn. Sheet names are XML-string decoded, the
/// `state` and `date1904` attributes are read, and elements match by local
/// name and SpreadsheetML namespace so prefixed producers work.
library;

import '../../opc/ooxml.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import '../sheet_view.dart';
import 'package_reader.dart';

/// One `<sheet>` entry of a workbook.
final class WorkbookSheet {
  /// Creates a sheet entry.
  const WorkbookSheet(this.name, this.visibility, this.part);

  /// The sheet name as written in the file, XML-string decoded.
  final String name;

  /// Whether the sheet is visible, hidden or very hidden.
  final XlsxSheetVisibility visibility;

  /// The worksheet part name, or null when the sheet's relationship is
  /// missing or its part is not in the package.
  final String? part;
}

/// The workbook-level facts the reader needs.
final class WorkbookInfo {
  /// Creates workbook facts.
  const WorkbookInfo(this.sheets, this.date1904);

  /// The sheets in file order. Empty when the workbook lists none.
  final List<WorkbookSheet> sheets;

  /// Whether dates count from 1904 (`workbookPr date1904` is `1` or
  /// `true`).
  final bool date1904;
}

/// Reads the sheet list and date system from the workbook part of
/// [package].
///
/// Throws an `XlsxReadException` when the workbook XML cannot be read.
WorkbookInfo readWorkbook(PackageReader package) {
  final String part = package.workbookPart;
  final Map<String, String> targets = <String, String>{
    for (final PartRelationship r in package.relationshipsOf(part))
      r.id: r.target,
  };
  return package.guardXml(part, () {
    final XmlPullReader reader = package.openXml(part);
    final List<WorkbookSheet> sheets = <WorkbookSheet>[];
    bool date1904 = false;
    while (reader.next()) {
      if (reader.eventType != XmlEventType.startElement ||
          reader.namespaceUri != Ns.main) {
        continue;
      }
      if (reader.depth == 2 && reader.localName == 'workbookPr') {
        final String? value = reader.getAttribute('date1904');
        date1904 = value == '1' || value == 'true';
      } else if (reader.depth == 2 && reader.localName == 'sheets') {
        _readSheets(reader, package, targets, sheets);
      }
    }
    return WorkbookInfo(List<WorkbookSheet>.unmodifiable(sheets), date1904);
  });
}

void _readSheets(
  XmlPullReader reader,
  PackageReader package,
  Map<String, String> targets,
  List<WorkbookSheet> sheets,
) {
  if (reader.isEmptyElement) return;
  while (reader.next()) {
    if (reader.eventType == XmlEventType.endElement && reader.depth < 2) {
      return;
    }
    if (reader.eventType != XmlEventType.startElement ||
        reader.depth != 3 ||
        reader.localName != 'sheet' ||
        reader.namespaceUri != Ns.main) {
      continue;
    }
    final String name = decodeXstring(reader.getAttribute('name') ?? '');
    final String? id = reader.getAttribute('id', namespaceUri: Ns.rel);
    final String? target = id == null ? null : targets[id];
    sheets.add(
      WorkbookSheet(name, switch (reader.getAttribute('state')) {
        'hidden' => XlsxSheetVisibility.hidden,
        'veryHidden' => XlsxSheetVisibility.veryHidden,
        _ => XlsxSheetVisibility.visible,
      }, target != null && package.hasPart(target) ? target : null),
    );
  }
}
