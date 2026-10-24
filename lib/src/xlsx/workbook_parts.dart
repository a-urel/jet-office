/// The workbook-level parts of an XLSX package, written at `close()`:
/// `xl/workbook.xml`, `xl/_rels/workbook.xml.rels`, `_rels/.rels` and
/// `[Content_Types].xml`.
///
/// Ported from quds_office_engine `lib/src/builders/xlsx_io.dart` at commit 15c5d29.
/// Ported: the package, workbook-relationship and `workbook.xml` steps of
/// `XlsxWorkbookBuilder.build`. What changed: sheets are listed in tab order,
/// which is independent of the creation order that names their parts and
/// gives their `sheetId`; `workbook.xml` gains `bookViews` with the active
/// tab and, when a formula was written, `calcPr` for full recalculation on
/// load; the root relationships point to the property parts; and every part
/// is written through `XmlWriter` with scrub-checked attribute values instead
/// of string concatenation; a sheet with an auto filter gets the hidden
/// `_xlnm._FilterDatabase` defined name Excel expects. Drawings, charts,
/// pictures and passwords are not ported in this phase.
library;

import '../opc/content_types.dart';
import '../opc/ooxml.dart';
import '../opc/relationships.dart';
import '../xml/xml_escape.dart';
import '../xml/xml_writer.dart';
import 'range.dart';
import 'sheet_view.dart';

/// A worksheet as the workbook lists it.
///
/// `name` is the final, valid sheet name, unescaped; [writeWorkbook] escapes
/// `_xHHHH_` sequences when it writes it. `number` is the sheet's 1-based
/// creation order: it names the part (`sheet{number}.xml`), is the
/// `sheetId`, and its relationship id is [worksheetRelationshipId].
/// `visibility` is written as the `state` of a hidden sheet. `autoFilter` is
/// the sheet's filter range, or `null`; it becomes the `_xlnm._FilterDatabase`
/// defined name.
typedef WorkbookSheet = ({
  String name,
  int number,
  XlsxSheetVisibility visibility,
  XlsxRange? autoFilter,
});

/// The relationship id of the worksheet created [number]th (1-based).
///
/// `workbook.xml` refers to the worksheet by this id and
/// `workbook.xml.rels` declares it. [writeWorkbookRelationships] passes this
/// id to [Relationships.add] for each worksheet, so both parts take it from
/// here. The styles and shared strings get automatic ids, which skip the ids
/// the worksheets use.
String worksheetRelationshipId(int number) => 'rId$number';

/// The ZIP entry name of the worksheet created [number]th (1-based).
String worksheetPartName(int number) => 'xl/worksheets/sheet$number.xml';

/// Writes `xl/workbook.xml`, XML declaration included, to [w].
///
/// [tabs] lists the sheets in tab order. [activeTab] is the index in [tabs]
/// of the tab Excel opens on, which must not be hidden. [fullCalcOnLoad]
/// asks Excel to recalculate every formula when the file is opened, which a
/// workbook with formulas needs because the writer does not compute their
/// results.
///
/// After `sheets`, one hidden `_xlnm._FilterDatabase` defined name is written
/// per filtered sheet, in tab order, scoped by `localSheetId` (the tab index)
/// and reading `'<name>'!<absoluteRef>`: the name is always quoted with `'`
/// doubled. The text is a formula (ST_Formula), so it goes through
/// [escapeFormulaText] like `<f>` text and keeps `_xHHHH_` as given, while
/// the `sheet` element's name attribute is escaped with [escapeXstring].
void writeWorkbook(
  XmlWriter w, {
  required List<WorkbookSheet> tabs,
  required int activeTab,
  required bool fullCalcOnLoad,
}) {
  w.declaration();
  w.start('workbook');
  w.attribute('xmlns', Ns.main);
  w.attribute('xmlns:r', Ns.rel);
  w.start('bookViews');
  w.empty('workbookView', <String, String>{'activeTab': '$activeTab'});
  w.end();
  w.start('sheets');
  for (final WorkbookSheet sheet in tabs) {
    w.empty('sheet', <String, String>{
      'name': escapeXstring(sheet.name),
      'sheetId': '${sheet.number}',
      if (sheet.visibility != XlsxSheetVisibility.visible)
        'state': sheet.visibility.name,
      'r:id': worksheetRelationshipId(sheet.number),
    });
  }
  w.end();
  _writeFilterNames(w, tabs);
  if (fullCalcOnLoad) {
    w.empty('calcPr', const <String, String>{'fullCalcOnLoad': '1'});
  }
  w.end();
}

/// Writes `definedNames` with a `_xlnm._FilterDatabase` for each sheet of
/// [tabs] that has an auto filter, or nothing when none has.
void _writeFilterNames(XmlWriter w, List<WorkbookSheet> tabs) {
  if (!tabs.any((WorkbookSheet s) => s.autoFilter != null)) return;
  w.start('definedNames');
  for (int index = 0; index < tabs.length; index++) {
    final XlsxRange? filter = tabs[index].autoFilter;
    if (filter == null) continue;
    final String quoted = "'${tabs[index].name.replaceAll("'", "''")}'";
    w.start('definedName');
    w.attribute('name', '_xlnm._FilterDatabase');
    w.attribute('localSheetId', '$index');
    w.attribute('hidden', '1');
    w.raw(escapeFormulaText('$quoted!${filter.absoluteRef}'));
    w.end();
  }
  w.end();
}

/// Writes `xl/_rels/workbook.xml.rels` for a workbook of [sheetCount]
/// sheets to [w].
///
/// The worksheets come first, in creation order, with the ids of
/// [worksheetRelationshipId] (matching [writeWorkbook]), followed by the
/// styles and the shared-string table.
void writeWorkbookRelationships(XmlWriter w, int sheetCount) {
  final Relationships rels = Relationships();
  for (int number = 1; number <= sheetCount; number++) {
    rels.add(
      RelType.worksheet,
      'worksheets/sheet$number.xml',
      id: worksheetRelationshipId(number),
    );
  }
  rels
    ..add(RelType.styles, 'styles.xml')
    ..add(RelType.sharedStrings, 'sharedStrings.xml');
  rels.write(w);
}

/// Writes the package relationships, `_rels/.rels`, to [w]: the workbook
/// and the core and extended property parts.
void writeRootRelationships(XmlWriter w) {
  (Relationships()
        ..add(RelType.officeDocument, 'xl/workbook.xml')
        ..add(RelType.coreProperties, 'docProps/core.xml')
        ..add(RelType.extendedProperties, 'docProps/app.xml'))
      .write(w);
}

/// Writes `[Content_Types].xml` for a workbook of [sheetCount] sheets to [w].
///
/// Relationship parts and other XML get default types; the workbook, every
/// worksheet, the styles, the shared strings and both property parts get an
/// override.
void writeContentTypes(XmlWriter w, int sheetCount) {
  final ContentTypes types = ContentTypes()
    ..addDefault('rels', ContentType.relationships)
    ..addDefault('xml', ContentType.xml)
    ..addOverride('/xl/workbook.xml', ContentType.workbook)
    ..addOverride('/xl/styles.xml', ContentType.styles)
    ..addOverride('/xl/sharedStrings.xml', ContentType.sharedStrings)
    ..addOverride('/docProps/core.xml', ContentType.coreProperties)
    ..addOverride('/docProps/app.xml', ContentType.extendedProperties);
  for (int number = 1; number <= sheetCount; number++) {
    types.addOverride('/${worksheetPartName(number)}', ContentType.worksheet);
  }
  types.write(w);
}
