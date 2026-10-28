/// Test helper: builds small XLSX packages by hand, for the cases
/// `XlsxWriter` never writes (rows without `r`, duplicate cells, cells past
/// `XFD`, prefixed elements, missing parts).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'zip_builder.dart';

/// The SpreadsheetML main namespace.
const String mainNs =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

const String _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _pkgRel =
    'http://schemas.openxmlformats.org/package/2006/relationships';
const String _wbType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml';

/// A worksheet part whose `<sheetData>` holds [rows] (raw XML).
String worksheet(String rows) =>
    '<worksheet xmlns="$mainNs"><sheetData>$rows</sheetData></worksheet>';

/// The ZIP entry name of the part of sheet [index] (0-based).
String sheetEntry(int index) => 'xl/worksheets/sheet${index + 1}.xml';

/// An XLSX package with one sheet per entry of [sheets], in order: its name
/// and its part's XML, or `null` for a sheet whose part is missing.
///
/// [sharedStrings] is the raw XML of `xl/sharedStrings.xml`; it is related
/// from the workbook when given or when [sharedStringsRelation] is true (a
/// relationship to a missing part). [styles] is the raw XML of
/// `xl/styles.xml`, related from the workbook when given. [date1904] writes
/// `<workbookPr date1904="1"/>`. [store] stores entries uncompressed.
Uint8List buildWorkbook(
  Map<String, String?> sheets, {
  String? sharedStrings,
  bool sharedStringsRelation = false,
  String? styles,
  bool date1904 = false,
  bool store = false,
}) => buildWorkbookList(
  <(String, String?)>[
    for (final MapEntry<String, String?> sheet in sheets.entries)
      (sheet.key, sheet.value),
  ],
  sharedStrings: sharedStrings,
  sharedStringsRelation: sharedStringsRelation,
  styles: styles,
  date1904: date1904,
  store: store,
);

/// [buildWorkbook] with the sheets as a list of name and part XML, so two
/// sheets can share a name, as a hostile file may.
Uint8List buildWorkbookList(
  List<(String, String?)> sheets, {
  String? sharedStrings,
  bool sharedStringsRelation = false,
  String? styles,
  bool date1904 = false,
  bool store = false,
}) {
  final StringBuffer sheetList = StringBuffer();
  final StringBuffer rels = StringBuffer();
  final Map<String, List<int>> parts = <String, List<int>>{};
  for (int i = 0; i < sheets.length; i++) {
    final (String name, String? xml) = sheets[i];
    sheetList.write(
      '<sheet name="${_escape(name)}" sheetId="${i + 1}" '
      'r:id="rId${i + 1}"/>',
    );
    rels.write(
      '<Relationship Id="rId${i + 1}" Type="$_rel/worksheet" '
      'Target="worksheets/sheet${i + 1}.xml"/>',
    );
    if (xml != null) parts[sheetEntry(i)] = utf8.encode(xml);
  }
  if (sharedStrings != null || sharedStringsRelation) {
    rels.write(
      '<Relationship Id="rIdS" Type="$_rel/sharedStrings" '
      'Target="sharedStrings.xml"/>',
    );
  }
  if (styles != null) {
    rels.write(
      '<Relationship Id="rIdT" Type="$_rel/styles" Target="styles.xml"/>',
    );
  }
  return buildZip(<String, List<int>>{
    '[Content_Types].xml': utf8.encode(
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
      'content-types"><Override PartName="/xl/workbook.xml" '
      'ContentType="$_wbType"/></Types>',
    ),
    '_rels/.rels': utf8.encode(
      '<Relationships xmlns="$_pkgRel"><Relationship Id="rId1" '
      'Type="$_rel/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>',
    ),
    'xl/workbook.xml': utf8.encode(
      '<workbook xmlns="$mainNs" xmlns:r="$_rel">'
      '${date1904 ? '<workbookPr date1904="1"/>' : ''}'
      '<sheets>$sheetList</sheets></workbook>',
    ),
    'xl/_rels/workbook.xml.rels': utf8.encode(
      '<Relationships xmlns="$_pkgRel">$rels</Relationships>',
    ),
    ...parts,
    if (sharedStrings != null)
      'xl/sharedStrings.xml': utf8.encode(sharedStrings),
    if (styles != null) 'xl/styles.xml': utf8.encode(styles),
  }, store: store);
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;');
