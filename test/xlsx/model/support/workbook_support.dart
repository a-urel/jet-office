/// Shared helpers of the `XlsxWorkbook` tests: the package builder and the
/// small readers they use.
///
/// Not ported from Quds; written for jet_office.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:jet_office/src/xlsx/model/cell_store.dart';
import 'package:jet_office/src/xlsx/raw_cell.dart';
import '../../../support/read_xlsx.dart';
import '../../read/support/workbook_builder.dart';
import '../../read/support/zip_builder.dart';

const String relNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String pkgRelNs =
    'http://schemas.openxmlformats.org/package/2006/relationships';
const String ctNs =
    'http://schemas.openxmlformats.org/package/2006/content-types';
const String wbType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml';
const String wsType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml';

/// A styles part with the `<xf>`s [xfs] (raw XML) and the `<numFmt>`s
/// [numFmts].
String stylesPart(String xfs, {String numFmts = ''}) =>
    '<styleSheet xmlns="$mainNs">'
    '${numFmts.isEmpty ? '' : '<numFmts>$numFmts</numFmts>'}'
    '<cellXfs>$xfs</cellXfs></styleSheet>';

/// The text of the part [name] of [bytes].
String partText(Uint8List bytes, String name) => readXlsx(bytes)[name]!;

/// A one-sheet package with [rows] (raw XML) in its sheet, a calcChain
/// part when [calcChain] is true, and [extra] entries.
Uint8List packageWith({
  required String rows,
  bool calcChain = false,
  String contentType = wbType,
  Map<String, String> extra = const <String, String>{},
  String extraRels = '',
  String extraTypes = '',
}) {
  return buildZip(<String, List<int>>{
    '[Content_Types].xml': utf8.encode(
      '<Types xmlns="$ctNs">'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="rels" ContentType="application/'
      'vnd.openxmlformats-package.relationships+xml"/>'
      '$extraTypes'
      '<Override PartName="/xl/workbook.xml" ContentType="$contentType"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" '
      'ContentType="$wsType"/>'
      '${calcChain ? '<Override PartName="/xl/calcChain.xml" ContentType="'
                'application/vnd.openxmlformats-officedocument.spreadsheetml.'
                'calcChain+xml"/>' : ''}'
      '</Types>',
    ),
    '_rels/.rels': utf8.encode(
      '<Relationships xmlns="$pkgRelNs"><Relationship Id="rId1" '
      'Type="$relNs/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>',
    ),
    'xl/workbook.xml': utf8.encode(
      '<workbook xmlns="$mainNs" xmlns:r="$relNs"><sheets>'
      '<sheet name="S" sheetId="1" r:id="rId1"/></sheets>'
      '<calcPr calcId="191029"/></workbook>',
    ),
    'xl/_rels/workbook.xml.rels': utf8.encode(
      '<Relationships xmlns="$pkgRelNs"><Relationship Id="rId1" '
      'Type="$relNs/worksheet" Target="worksheets/sheet1.xml"/>'
      '${calcChain ? '<Relationship Id="rId2" Type="$relNs/calcChain" '
                'Target="calcChain.xml"/>' : ''}'
      '$extraRels</Relationships>',
    ),
    'xl/worksheets/sheet1.xml': utf8.encode(worksheet(rows)),
    if (calcChain)
      'xl/calcChain.xml': utf8.encode(
        '<calcChain xmlns="$mainNs"><c r="A1" i="1"/></calcChain>',
      ),
    for (final MapEntry<String, String> e in extra.entries)
      e.key: utf8.encode(e.value),
  });
}

/// Every cell of [store], as `(row, column, kind, style, value, formula)`.
List<Object?> cellsOf(CellStore store) => <Object?>[
  for (final int r in store.rowIndexes)
    ...() {
      final List<Object?> out = <Object?>[];
      store.forEachInRow(r, (int c, RawCell cell) {
        out.add((r, c, cell.kind, cell.style, cell.value, cell.formula?.text));
      });
      return out;
    }(),
];
