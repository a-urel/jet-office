/// Test helper: a DOCX whose body holds a table written by hand with every
/// element and attribute the table values of D3 read (`w:tblPr`, `w:trPr`,
/// `w:tcPr`), as the fuzzer's corpus entry `tables_by_hand`.
///
/// Not ported from Quds. The elements stand in schema order, as Word writes
/// them; the mutations then take the file out of its schema.
library;

import 'dart:typed_data';

import 'word_document.dart';

/// A cell with its properties [pr] (the inside of `w:tcPr`) and its blocks.
String _cell(String pr, String blocks) =>
    '<w:tc>${pr.isEmpty ? '' : '<w:tcPr>$pr</w:tcPr>'}$blocks</w:tc>';

/// A paragraph holding [text].
String _p(String text) => '<w:p><w:r><w:t>$text</w:t></w:r></w:p>';

const String _border = 'w:val="single" w:sz="4" w:space="0" w:color="auto"';

/// The table inside a cell.
final String _nested =
    '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/>'
    '<w:tblLook w:val="0000"/></w:tblPr>'
    '<w:tblGrid><w:gridCol w:w="1500"/><w:gridCol w:w="1500"/></w:tblGrid>'
    '<w:tr>${_cell('<w:tcW w:w="1500" w:type="dxa"/>', _p('N1'))}'
    '${_cell('<w:tcW w:w="1500" w:type="dxa"/>', _p('N2'))}</w:tr></w:tbl>';

/// The body of [tablesByHandDocumentXml]: a paragraph, a table with every
/// property, a bookmark and a content control between its rows, merges in
/// both directions, a row that skips grid columns, a nested table and a
/// closing paragraph.
final String _tableBody =
    '${_p('Before')}'
    '<w:tbl>'
    '<w:tblPr><w:tblStyle w:val="TableGrid"/>'
    '<w:tblW w:w="5000" w:type="pct"/><w:jc w:val="center"/>'
    '<w:tblInd w:w="108" w:type="dxa"/>'
    '<w:tblBorders><w:top $_border/><w:left $_border/><w:bottom $_border/>'
    '<w:right $_border/><w:insideH $_border/><w:insideV $_border/>'
    '</w:tblBorders><w:tblLayout w:type="fixed"/>'
    '<w:tblCellMar><w:top w:w="10" w:type="dxa"/>'
    '<w:left w:w="108" w:type="dxa"/><w:bottom w:w="10" w:type="dxa"/>'
    '<w:right w:w="108" w:type="dxa"/></w:tblCellMar>'
    '<w:tblLook w:val="04A0" w:firstRow="1" w:lastRow="0" w:firstColumn="1" '
    'w:lastColumn="0" w:noHBand="0" w:noVBand="1"/></w:tblPr>'
    '<w:tblGrid><w:gridCol w:w="2000"/><w:gridCol w:w="2000"/>'
    '<w:gridCol w:w="2000"/><w:gridCol w:w="2000"/></w:tblGrid>'
    // A header row that cannot split and has a height.
    '<w:tr><w:trPr><w:cantSplit/><w:trHeight w:val="400" w:hRule="exact"/>'
    '<w:tblHeader/></w:trPr>'
    '${_cell('<w:tcW w:w="2000" w:type="dxa"/><w:shd w:val="clear" '
    'w:color="auto" w:fill="D9E2F3"/><w:vAlign w:val="center"/>', _p('A'))}'
    '${_cell('<w:tcW w:w="2000" w:type="dxa"/><w:vAlign w:val="bottom"/>', _p('B'))}'
    '${_cell('<w:tcW w:w="4000" w:type="dxa"/><w:gridSpan w:val="2"/>'
    '<w:textDirection w:val="btLr"/>', _p('C D'))}'
    '</w:tr>'
    '<w:bookmarkStart w:id="7" w:name="between"/><w:bookmarkEnd w:id="7"/>'
    // A vertical merge, a cell with every border, a tblPrEx.
    '<w:tr><w:tblPrEx><w:tblW w:w="0" w:type="auto"/></w:tblPrEx>'
    '<w:trPr><w:trHeight w:val="300"/></w:trPr>'
    '${_cell('<w:tcW w:w="2000" w:type="dxa"/><w:vMerge w:val="restart"/>', _p('E'))}'
    '${_cell('<w:tcW w:w="2000" w:type="dxa"/><w:tcBorders><w:top $_border/>'
    '<w:left $_border/><w:bottom $_border/><w:right $_border/>'
    '<w:insideH $_border/><w:insideV $_border/>'
    '<w:tl2br $_border/><w:tr2bl $_border/></w:tcBorders>'
    '<w:textDirection w:val="tbRl"/><w:vAlign w:val="top"/>', _p('F'))}'
    '${_cell('<w:tcW w:w="2000" w:type="dxa"/>', _p('G'))}'
    '${_cell('<w:tcW w:w="2000" w:type="dxa"/>', _p('H'))}'
    '</w:tr>'
    '<w:sdt><w:sdtPr><w:id w:val="5"/></w:sdtPr><w:sdtContent><w:tr>'
    '${_cell('<w:tcW w:w="8000" w:type="dxa"/><w:gridSpan w:val="4"/>', _p('Hidden'))}'
    '</w:tr></w:sdtContent></w:sdt>'
    // The vertical merge continues; the row skips the last two columns.
    '<w:tr><w:trPr><w:gridAfter w:val="2"/>'
    '</w:trPr>'
    '${_cell('<w:tcW w:w="2000" w:type="dxa"/><w:vMerge/>', '<w:p/>')}'
    '${_cell('<w:tcW w:w="2000" w:type="dxa"/>', _p('J'))}'
    '</w:tr>'
    // A nested table, and a cell that ends in it.
    '<w:tr>'
    '${_cell('<w:tcW w:w="4000" w:type="dxa"/><w:gridSpan w:val="2"/>', '${_p('Nested')}$_nested<w:p/>')}'
    '${_cell('<w:tcW w:w="2000" w:type="dxa"/><w:vMerge w:val="restart"/>', _p('K'))}'
    '${_cell('<w:tcW w:w="2000" w:type="dxa"/>', _p('L'))}'
    '</w:tr>'
    '</w:tbl>'
    '${_p('After')}';

/// A `document.xml` of Word's root and final section properties around
/// [_tableBody].
final String tablesByHandDocumentXml = wordDocumentXml.replaceFirst(
  '<w:sectPr w:rsidR=',
  '$_tableBody<w:sectPr w:rsidR=',
);

/// A DOCX holding [tablesByHandDocumentXml], every entry stored, so its
/// bytes are the same on every platform.
Uint8List tablesByHandDocx() => wordDocx(
  document: tablesByHandDocumentXml,
  documentRels: wordDocumentRels,
  store: true,
);
