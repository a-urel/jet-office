/// Writes the workbooks the owner opens in the W6 Excel check (proof and
/// release readiness), to a directory that is created.
///
/// ```bash
/// dart run tool/write_w6_check.dart build/w6
/// ```
///
/// - `w6_generated_100k.xlsx` and `w6_generated_1m.xlsx`: 100,000 and
///   1,000,000 data rows of the benchmark's workload (`benchmark/src/
///   workload.dart`: 12 mixed columns), generated with `XlsxWorkbook()` and
///   saved. The last row's `Id` is `C-100000` and `C-1000000`.
/// - `w6_shapes.xlsx`: sheets `Veri`, `S` and `Veri 2` where `S` holds two
///   rectangles whose text is linked to cells (`textlink="$A$1"` and
///   `textlink="'Veri 2'!$B$2"`); then the model inserts a row above row 1
///   and a column left of A on `S`, a row above row 1 of `Veri 2`, and
///   renames `Veri 2` to `Veri 3`. The links must read `$B$2` and
///   `'Veri 3'!$B$3`.
/// - `w6_wrapped.xlsx`: a text box `Kutu` in `mc:AlternateContent` (a Choice
///   and a Fallback) over B3:D6, then a row and a column inserted before it:
///   C4:E7.
/// - `final/`: what `tool/edit_model.dart` writes for every fixture of
///   `allFixtures()` and for the `.xlsx` files of `test/fixtures/owner`.
///
/// The steps are in `docs/superpowers/plans/2026-11-11-phase-3-w6-excel-check.md`
/// (Turkish); the results go in `docs/excel-checks.md`, "W6", from the owner
/// only. Exit code 2 on unusable arguments, 1 on any error.
///
/// Not ported from Quds; written for jet_office.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';

import '../benchmark/src/workload.dart';
import '../test/fixtures/fixtures.dart';
import '../test/support/read_xlsx.dart';
import '../test/xlsx/read/support/workbook_builder.dart';
import '../test/xlsx/read/support/zip_builder.dart';
import 'edit_model.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/write_w6_check.dart <outDir>');
    exitCode = 2;
    return;
  }
  try {
    writeW6Check(args.single).forEach(stdout.writeln);
  } on Object catch (e) {
    stderr.writeln('write_w6_check failed: $e');
    exitCode = 1;
  }
}

/// Writes the W6 check's files to [dir] and returns their paths: the four
/// workbooks, then the files of `final/`. The two generated workbooks have
/// [smallRows] and [largeRows] data rows (100,000 and 1,000,000 for the
/// owner; a test passes fewer).
List<String> writeW6Check(
  String dir, {
  int smallRows = 100000,
  int largeRows = 1000000,
}) {
  final List<String> paths = <String>[
    _write('$dir/w6_generated_100k.xlsx', _generated(smallRows)),
    _write('$dir/w6_generated_1m.xlsx', _generated(largeRows)),
    _write('$dir/w6_shapes.xlsx', _shapesBook().save().bytes),
    _write('$dir/w6_wrapped.xlsx', _wrappedBook().save().bytes),
  ];
  return <String>[...paths, ..._writeFinal('$dir/final')];
}

String _write(String path, Uint8List bytes) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  return path;
}

/// The benchmark's workload, [rows] data rows, set cell by cell as
/// `benchmark/xlsx_model_generate_benchmark_test.dart` does.
Uint8List _generated(int rows) {
  final XlsxWorkbook book = XlsxWorkbook();
  final XlsxSheet sheet = book.addSheet('Data');
  for (int c = 0; c < workloadColumns.length; c++) {
    sheet.setColumn(c, workloadColumns[c]);
  }
  for (int c = 0; c < workloadHeader.length; c++) {
    sheet
      ..setCell(0, c, workloadHeader[c])
      ..setStyle(0, c, workloadHeaderStyle);
  }
  for (int r = 1; r <= rows; r++) {
    final List<Object?> values = workloadRow(r);
    for (int c = 0; c < values.length; c++) {
      final Object? value = values[c];
      if (value != null) sheet.setCell(r, c, value);
    }
  }
  return book.save().bytes;
}

const String _xdrNs =
    'xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"';
const String _relNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _pkgRelNs =
    'http://schemas.openxmlformats.org/package/2006/relationships';
const String _mcNs =
    'http://schemas.openxmlformats.org/markup-compatibility/2006';
const String _a14Ns = 'http://schemas.microsoft.com/office/drawing/2010/main';
const String _drawingType =
    'application/vnd.openxmlformats-officedocument.drawing+xml';

String _marker(String name, int col, int row) =>
    '<xdr:$name><xdr:col>$col</xdr:col><xdr:colOff>0</xdr:colOff>'
    '<xdr:row>$row</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:$name>';

String _inline(String ref, String text) =>
    '<c r="$ref" t="inlineStr"><is><t>$text</t></is></c>';

String _sheetData(Map<String, String> cells) {
  final StringBuffer rows = StringBuffer();
  final Map<int, StringBuffer> byRow = <int, StringBuffer>{};
  cells.forEach((String ref, String text) {
    final int row = int.parse(ref.substring(1));
    (byRow[row] ??= StringBuffer()).write(_inline(ref, text));
  });
  for (final int row in (byRow.keys.toList()..sort())) {
    rows.write('<row r="$row">${byRow[row]}</row>');
  }
  return '<sheetData>$rows</sheetData>';
}

/// A workbook package of [sheets] (name to worksheet XML); the worksheet at
/// [drawn] gets a `<drawing>` of [drawingXml] (the part `xl/drawings/
/// drawing1.xml`, with its content type and relationship).
XlsxWorkbook _withDrawing(
  List<(String, String)> sheets, {
  required int drawn,
  required String drawingXml,
}) {
  final Map<String, Uint8List> parts = readXlsxBytes(
    buildWorkbookList(<(String, String?)>[
      for (final (String name, String xml) in sheets) (name, xml),
    ]),
  );
  final StringBuffer types = StringBuffer(
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-'
    'package.relationships+xml"/><Default Extension="xml" '
    'ContentType="application/xml"/>',
  );
  for (int i = 1; i <= sheets.length; i++) {
    types.write(
      '<Override PartName="/xl/worksheets/sheet$i.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.'
      'spreadsheetml.worksheet+xml"/>',
    );
  }
  types.write(
    '<Override PartName="/xl/drawings/drawing1.xml" '
    'ContentType="$_drawingType"/></Types>',
  );
  parts['[Content_Types].xml'] = Uint8List.fromList(
    utf8.encode(
      utf8
          .decode(parts['[Content_Types].xml']!)
          .replaceFirst('</Types>', types.toString()),
    ),
  );
  parts['xl/worksheets/_rels/sheet${drawn + 1}.xml.rels'] = Uint8List.fromList(
    utf8.encode(
      '<Relationships xmlns="$_pkgRelNs"><Relationship Id="rId1" '
      'Type="$_relNs/drawing" Target="../drawings/drawing1.xml"/>'
      '</Relationships>',
    ),
  );
  parts['xl/drawings/drawing1.xml'] = Uint8List.fromList(
    utf8.encode(drawingXml),
  );
  return XlsxWorkbook.open(buildZip(<String, List<int>>{...parts}));
}

/// A worksheet holding [cells] and a drawing.
String _drawnSheet(Map<String, String> cells) =>
    '<worksheet xmlns="$mainNs" xmlns:r="$_relNs">${_sheetData(cells)}'
    '<drawing r:id="rId1"/></worksheet>';

String _plainSheet(Map<String, String> cells) =>
    '<worksheet xmlns="$mainNs">${_sheetData(cells)}</worksheet>';

const String _spPr =
    '<xdr:spPr><a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
    '<a:solidFill><a:srgbClr val="FFF2CC"/></a:solidFill>'
    '<a:ln w="9525"><a:solidFill><a:srgbClr val="7F6000"/></a:solidFill>'
    '</a:ln></xdr:spPr>';

/// A rectangle whose text is the cell [link] shows, with the cached [text].
String _linked(int id, String link, String text, int fromRow) =>
    '<xdr:twoCellAnchor>${_marker('from', 3, fromRow)}'
    '${_marker('to', 6, fromRow + 2)}'
    '<xdr:sp macro="" textlink="$link"><xdr:nvSpPr>'
    '<xdr:cNvPr id="$id" name="Rectangle ${id - 1}"/><xdr:cNvSpPr/>'
    '</xdr:nvSpPr>$_spPr<xdr:txBody><a:bodyPr vertOverflow="clip" '
    'horzOverflow="clip" rtlCol="0" anchor="ctr"/><a:lstStyle/><a:p>'
    '<a:fld id="{B1E4A2C0-5D3F-4E7A-9C11-0A2B3C4D5E6$id}" type="TxLink">'
    '<a:rPr lang="tr-TR" sz="1100"><a:solidFill><a:srgbClr val="000000"/>'
    '</a:solidFill></a:rPr><a:pPr/><a:t>$text</a:t></a:fld>'
    '<a:endParaRPr lang="tr-TR" sz="1100"/></a:p></xdr:txBody></xdr:sp>'
    '<xdr:clientData/></xdr:twoCellAnchor>';

XlsxWorkbook _shapesBook() {
  final XlsxWorkbook book = _withDrawing(
    <(String, String)>[
      ('Veri', _plainSheet(<String, String>{'A1': 'Bir', 'A2': 'Iki'})),
      ('S', _drawnSheet(<String, String>{'A1': 'Bir'})),
      ('Veri 2', _plainSheet(<String, String>{'B2': 'İki'})),
    ],
    drawn: 1,
    drawingXml:
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<xdr:wsDr $_xdrNs>'
        '${_linked(2, r'$A$1', 'Bir', 1)}'
        "${_linked(3, r"'Veri 2'!$B$2", 'İki', 5)}"
        '</xdr:wsDr>',
  );
  book.sheet('S')
    ..insertRows(0)
    ..insertColumns(0);
  book.sheet('Veri 2').insertRows(0);
  book.renameSheet(book.sheet('Veri 2'), 'Veri 3');
  return book;
}

/// The text box `Kutu`, the same twice: in the Choice and in the Fallback.
String _box() =>
    '<xdr:twoCellAnchor>${_marker('from', 1, 2)}${_marker('to', 4, 6)}'
    '<xdr:sp macro="" textlink=""><xdr:nvSpPr><xdr:cNvPr id="2" '
    'name="TextBox 1"/><xdr:cNvSpPr txBox="1"/></xdr:nvSpPr>$_spPr'
    '<xdr:txBody><a:bodyPr vertOverflow="clip" horzOverflow="clip" '
    'wrap="square" rtlCol="0" anchor="t"/><a:lstStyle/><a:p><a:r>'
    '<a:rPr lang="tr-TR" sz="1100"/><a:t>Kutu</a:t></a:r></a:p></xdr:txBody>'
    '</xdr:sp><xdr:clientData/></xdr:twoCellAnchor>';

XlsxWorkbook _wrappedBook() {
  final XlsxWorkbook book = _withDrawing(
    <(String, String)>[
      ('S', _drawnSheet(<String, String>{'A1': 'Bir'})),
    ],
    drawn: 0,
    drawingXml:
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<xdr:wsDr $_xdrNs><mc:AlternateContent xmlns:mc="$_mcNs">'
        '<mc:Choice xmlns:a14="$_a14Ns" Requires="a14">${_box()}</mc:Choice>'
        '<mc:Fallback>${_box()}</mc:Fallback></mc:AlternateContent>'
        '</xdr:wsDr>',
  );
  book.sheet('S')
    ..insertRows(0)
    ..insertColumns(0);
  return book;
}

/// Writes the fixtures and the owner's workbooks to temporary folders, runs
/// `tool/edit_model.dart` on both into [out] and returns the files written.
List<String> _writeFinal(String out) {
  final Directory work = Directory.systemTemp.createTempSync('w6_final');
  try {
    final Directory fixtures = Directory('${work.path}/fixtures')..createSync();
    for (final Fixture f in allFixtures()) {
      File('${fixtures.path}/${f.name}.xlsx').writeAsBytesSync(f.build());
    }
    final Directory owner = Directory('${work.path}/owner')..createSync();
    for (final File file
        in Directory('test/fixtures/owner')
            .listSync(recursive: true)
            .whereType<File>()
            .where((File f) => f.path.endsWith('.xlsx'))) {
      file.copySync('${owner.path}/${file.uri.pathSegments.last}');
    }
    for (final Directory input in <Directory>[fixtures, owner]) {
      final StringBuffer out0 = StringBuffer();
      final StringBuffer err = StringBuffer();
      final int code = editModel(
        <String>[input.path, out],
        out: out0,
        err: err,
      );
      if (code != 0) {
        throw StateError('edit_model on ${input.path} exited $code: $out0$err');
      }
    }
  } finally {
    work.deleteSync(recursive: true);
  }
  return <String>[
    for (final File f in Directory(out).listSync().whereType<File>())
      if (f.path.endsWith('.xlsx')) f.path,
  ]..sort();
}
