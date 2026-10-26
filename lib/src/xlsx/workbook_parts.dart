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
/// `_xlnm._FilterDatabase` defined name Excel expects, and the defined
/// names, print areas and print titles are written by one `definedNames`
/// writer (Quds' print titles were relative and unquoted). Pictures and
/// tables are written by their sheets (see `drawing.dart` and `table.dart`),
/// not here; charts are not ported in this phase. `workbookProtection`
/// (see `sheet_protection.dart`) comes before `bookViews`;
/// `[Content_Types].xml` also lists the content types the sheets registered
/// for their other parts (see `PackageContentTypes`), such as drawings,
/// media, notes and tables.
library;

import '../opc/content_types.dart';
import '../opc/ooxml.dart';
import '../opc/relationships.dart';
import '../xml/xml_escape.dart';
import '../xml/xml_writer.dart';
import 'cell_ref.dart';
import 'defined_name.dart';
import 'formula_text.dart';
import 'range.dart';
import 'sheet_protection.dart';
import 'sheet_view.dart';

/// A worksheet as the workbook lists it.
///
/// `name` is the final, valid sheet name, unescaped; [writeWorkbook] escapes
/// `_xHHHH_` sequences when it writes it. `number` is the sheet's 1-based
/// creation order: it names the part (`sheet{number}.xml`), is the
/// `sheetId`, and its relationship id is [worksheetRelationshipId].
/// `visibility` is written as the `state` of a hidden sheet. `autoFilter` is
/// the sheet's filter range, or `null`; it becomes the `_xlnm._FilterDatabase`
/// defined name. `names` holds the sheet's other defined names.
typedef WorkbookSheet = ({
  String name,
  int number,
  XlsxSheetVisibility visibility,
  XlsxRange? autoFilter,
  SheetNames names,
});

/// The defined names of one sheet besides its filter: its print area and
/// titles, and the names registered on it.
final class SheetNames {
  /// Names of a sheet; each part defaults to none.
  const SheetNames({
    this.printArea = const <XlsxRange>[],
    this.printTitleRows,
    this.printTitleColumns,
    this.defined = const <XlsxDefinedName>[],
  });

  /// A sheet with no print setting and no names.
  static const SheetNames none = SheetNames();

  /// The print area's ranges; empty for none.
  final List<XlsxRange> printArea;

  /// The first and last row (0-based, inclusive) repeated on every printed
  /// page, or `null`.
  final (int, int)? printTitleRows;

  /// The first and last column (0-based, inclusive) repeated on every
  /// printed page, or `null`.
  final (int, int)? printTitleColumns;

  /// The sheet-scoped names, in definition order; their formulas are
  /// already checked (see [checkDefinedName]).
  final List<XlsxDefinedName> defined;
}

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
/// [protection], when given, writes `workbookProtection` before `bookViews`.
///
/// After `sheets`, `definedNames` lists [workbookNames] in definition
/// order, then for each tab in tab order its hidden `_xlnm._FilterDatabase`
/// (when it has an auto filter), `_xlnm.Print_Area`, `_xlnm.Print_Titles` and
/// the names registered on it. A name of a tab is scoped by `localSheetId`,
/// the tab index. Every sheet reference is `'<name>'!<ref>`, always quoted
/// with `'` doubled and absolute (Quds wrote relative, unquoted print
/// titles). The text is a formula (ST_Formula), so it goes through
/// [escapeFormulaText] once, like `<f>` text, which escapes `_xHHHH_`
/// exactly as [escapeXstring] escapes the `sheet` element's name attribute;
/// the two spellings therefore agree. Print titles list the columns before
/// the rows, as Excel writes them.
void writeWorkbook(
  XmlWriter w, {
  required List<WorkbookSheet> tabs,
  required int activeTab,
  required bool fullCalcOnLoad,
  List<XlsxDefinedName> workbookNames = const <XlsxDefinedName>[],
  XlsxWorkbookProtection? protection,
}) {
  w.declaration();
  w.start('workbook');
  w.attribute('xmlns', Ns.main);
  w.attribute('xmlns:r', Ns.rel);
  if (protection != null) writeWorkbookProtection(w, protection);
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
  _writeDefinedNames(w, workbookNames, tabs);
  if (fullCalcOnLoad) {
    w.empty('calcPr', const <String, String>{'fullCalcOnLoad': '1'});
  }
  w.end();
}

/// Writes `definedNames` for [workbookNames] and [tabs], or nothing when
/// there is no name.
void _writeDefinedNames(
  XmlWriter w,
  List<XlsxDefinedName> workbookNames,
  List<WorkbookSheet> tabs,
) {
  final bool any =
      workbookNames.isNotEmpty ||
      tabs.any(
        (WorkbookSheet s) =>
            s.autoFilter != null ||
            s.names.printArea.isNotEmpty ||
            s.names.printTitleRows != null ||
            s.names.printTitleColumns != null ||
            s.names.defined.isNotEmpty,
      );
  if (!any) return;
  w.start('definedNames');
  for (final XlsxDefinedName name in workbookNames) {
    _writeName(
      w,
      name.name,
      null,
      name.formula,
      hidden: name.hidden,
      comment: name.comment,
    );
  }
  for (int index = 0; index < tabs.length; index++) {
    final WorkbookSheet tab = tabs[index];
    final String sheet = tab.name;
    final XlsxRange? filter = tab.autoFilter;
    if (filter != null) {
      _writeName(
        w,
        '_xlnm._FilterDatabase',
        index,
        quotedSheetRef(sheet, filter.absoluteRef),
        hidden: true,
      );
    }
    final SheetNames names = tab.names;
    if (names.printArea.isNotEmpty) {
      _writeName(
        w,
        '_xlnm.Print_Area',
        index,
        <String>[
          for (final XlsxRange r in names.printArea)
            quotedSheetRef(sheet, r.absoluteRef),
        ].join(','),
      );
    }
    final (int, int)? rows = names.printTitleRows;
    final (int, int)? columns = names.printTitleColumns;
    if (rows != null || columns != null) {
      _writeName(
        w,
        '_xlnm.Print_Titles',
        index,
        <String>[
          if (columns != null)
            quotedSheetRef(
              sheet,
              '\$${columnName(columns.$1)}:\$${columnName(columns.$2)}',
            ),
          if (rows != null)
            quotedSheetRef(sheet, '\$${rows.$1 + 1}:\$${rows.$2 + 1}'),
        ].join(','),
      );
    }
    for (final XlsxDefinedName name in names.defined) {
      _writeName(
        w,
        name.name,
        index,
        name.formula,
        hidden: name.hidden,
        comment: name.comment,
      );
    }
  }
  w.end();
}

/// Writes one `definedName`: its [name], the scope [localSheetId] (the tab
/// index, or `null` for the workbook), the [text] as a formula, and its
/// optional [comment] and [hidden] flag. The name and comment are
/// ST_Xstring, the text ST_Formula.
void _writeName(
  XmlWriter w,
  String name,
  int? localSheetId,
  String text, {
  bool hidden = false,
  String? comment,
}) {
  w.start('definedName');
  w.attribute('name', escapeXstring(name));
  if (localSheetId != null) w.attribute('localSheetId', '$localSheetId');
  if (comment != null) w.attribute('comment', escapeXstring(comment));
  if (hidden) w.attribute('hidden', '1');
  w.raw(escapeFormulaText(text));
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
/// and the core and extended property parts, and with [custom] the custom
/// property part.
void writeRootRelationships(XmlWriter w, {bool custom = false}) {
  final Relationships rels = Relationships()
    ..add(RelType.officeDocument, 'xl/workbook.xml')
    ..add(RelType.coreProperties, 'docProps/core.xml')
    ..add(RelType.extendedProperties, 'docProps/app.xml');
  if (custom) rels.add(RelType.customProperties, 'docProps/custom.xml');
  rels.write(w);
}

/// Writes `[Content_Types].xml` for a workbook of [sheetCount] sheets to [w].
///
/// Relationship parts and other XML get default types; the workbook, every
/// worksheet, the styles, the shared strings and both property parts get an
/// override, and with [custom] so does the custom property part.
///
/// [defaults] and [overrides] are the extra types the sheets registered
/// (see `PackageContentTypes`): the defaults are added after `rels` and
/// `xml`, the overrides after the worksheets. [ContentTypes] writes each
/// list sorted, so the output does not depend on the order they were added
/// in, and empty extras leave the part as it was.
void writeContentTypes(
  XmlWriter w,
  int sheetCount, {
  bool custom = false,
  Map<String, String> defaults = const <String, String>{},
  Map<String, String> overrides = const <String, String>{},
}) {
  final ContentTypes types = ContentTypes()
    ..addDefault('rels', ContentType.relationships)
    ..addDefault('xml', ContentType.xml);
  defaults.forEach(types.addDefault);
  types
    ..addOverride('/xl/workbook.xml', ContentType.workbook)
    ..addOverride('/xl/styles.xml', ContentType.styles)
    ..addOverride('/xl/sharedStrings.xml', ContentType.sharedStrings)
    ..addOverride('/docProps/core.xml', ContentType.coreProperties)
    ..addOverride('/docProps/app.xml', ContentType.extendedProperties);
  if (custom) {
    types.addOverride('/docProps/custom.xml', ContentType.customProperties);
  }
  for (int number = 1; number <= sheetCount; number++) {
    types.addOverride('/${worksheetPartName(number)}', ContentType.worksheet);
  }
  overrides.forEach(types.addOverride);
  types.write(w);
}
