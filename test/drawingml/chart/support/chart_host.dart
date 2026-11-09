/// The minimal chart host of milestone C1, for tests and fixtures only.
///
/// New in jet_office. [withCharts] puts chart parts written by
/// `writeDrawingChartSpace` into a workbook, so the parts reach the Open XML
/// SDK, LibreOffice and Excel inside a real file. It knows just enough of a
/// workbook to do that; C2's host in `lib/src/xlsx/` replaces it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/src/drawingml/chart/chart_space.dart';
import 'package:jet_office/src/opc/package.dart';
import 'package:jet_office/src/zip/archive_adapter.dart';
import 'package:xml/xml.dart';

const String _relationships =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

const String _drawingType = '$_relationships/drawing';

const String _drawingContentType =
    'application/vnd.openxmlformats-officedocument.drawing+xml';

/// One chart's anchor: 8 columns by 15 rows.
const int _columns = 8;
const int _rows = 15;

/// Excel's default column width (64 pixels) and row height (20 pixels) in
/// EMU, for the frame's `a:ext`.
const int _columnEmu = 609600;
const int _rowEmu = 190500;

/// The worksheet children that come after `drawing` (CT_Worksheet).
const List<String> _afterDrawing = <String>[
  'legacyDrawing',
  'legacyDrawingHF',
  'drawingHF',
  'picture',
  'oleObjects',
  'controls',
  'webPublishItems',
  'tableParts',
  'extLst',
];

/// A part's content: fixed bytes.
final class _Bytes implements PartContent {
  _Bytes(this.bytes);

  final Uint8List bytes;

  @override
  List<Uint8List> encode() => <Uint8List>[bytes];
}

/// Returns [xlsx] with [charts] drawn on its sheet named [sheet].
///
/// Each chart part becomes `xl/charts/chartN.xml` (N from 1, in order) of
/// [drawingChartContentType], shown by one `xdr:twoCellAnchor` graphic frame
/// of 8 columns by 15 rows in a new `xl/drawings/drawing1.xml`. The frames
/// form a grid of three across, starting in column A with one empty row
/// below the sheet's `dimension`. The sheet gains `<drawing r:id="…"/>` at its schema
/// place. The sheet must have no drawing yet.
Uint8List withCharts(Uint8List xlsx, String sheet, List<Uint8List> charts) {
  final OpcPackage package = OpcPackage.read(
    ZipReader(
      xlsx,
      maxEntries: 10000,
      maxEntryBytes: 1 << 28,
      maxTotalBytes: 1 << 30,
      maxCompressionRatio: 1000,
    ),
    maxDepth: 256,
  );
  final String sheetPart = _sheetPart(package, sheet);
  final String sheetXml = utf8.decode(package.originalBytes(sheetPart));
  if (sheetXml.contains('<drawing ')) {
    throw ArgumentError.value(sheet, 'sheet', 'already has a drawing');
  }
  final int firstRow = _lastRow(sheetXml) + 1;

  final String drawing = package.addPart(
    'xl/drawings/drawing1.xml',
    _drawingContentType,
    _Bytes(Uint8List(0)),
  );
  final StringBuffer anchors = StringBuffer();
  for (int i = 0; i < charts.length; i++) {
    final String chart = package.addPart(
      'xl/charts/chart${i + 1}.xml',
      drawingChartContentType,
      _Bytes(charts[i]),
    );
    final String id = package.addRelationship(
      drawing,
      type: drawingChartRelationshipType,
      target: '../charts/${chart.substring(chart.lastIndexOf('/') + 1)}',
    );
    final int column = (i % 3) * _columns;
    final int row = firstRow + (i ~/ 3) * _rows;
    anchors.write(
      '<xdr:twoCellAnchor editAs="oneCell">'
      '<xdr:from><xdr:col>$column</xdr:col><xdr:colOff>0</xdr:colOff>'
      '<xdr:row>$row</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>'
      '<xdr:to><xdr:col>${column + _columns}</xdr:col><xdr:colOff>0'
      '</xdr:colOff><xdr:row>${row + _rows}</xdr:row><xdr:rowOff>0'
      '</xdr:rowOff></xdr:to>'
      '<xdr:graphicFrame macro=""><xdr:nvGraphicFramePr>'
      '<xdr:cNvPr id="${i + 2}" name="Chart ${i + 1}"/>'
      '<xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr>'
      '<xdr:xfrm><a:off x="0" y="0"/>'
      '<a:ext cx="${_columns * _columnEmu}" cy="${_rows * _rowEmu}"/>'
      '</xdr:xfrm><a:graphic>'
      '<a:graphicData uri="$drawingChartNamespace">'
      '<c:chart xmlns:c="$drawingChartNamespace" '
      'xmlns:r="$_relationships" r:id="$id"/>'
      '</a:graphicData></a:graphic></xdr:graphicFrame>'
      '<xdr:clientData/></xdr:twoCellAnchor>',
    );
  }
  package.setContent(
    drawing,
    _Bytes(
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
        '<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/'
        '2006/spreadsheetDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '$anchors</xdr:wsDr>',
      ),
    ),
  );

  final String drawingId = package.addRelationship(
    sheetPart,
    type: _drawingType,
    target: '../drawings/${drawing.substring(drawing.lastIndexOf('/') + 1)}',
  );
  int at = sheetXml.lastIndexOf('</worksheet>');
  for (final String name in _afterDrawing) {
    final int found = sheetXml.indexOf('<$name');
    if (found >= 0 && found < at) at = found;
  }
  package.setContent(
    sheetPart,
    _Bytes(
      utf8.encode(
        '${sheetXml.substring(0, at)}<drawing r:id="$drawingId"/>'
        '${sheetXml.substring(at)}',
      ),
    ),
  );

  final ZipWriter zip = ZipWriter();
  package.writeTo(zip);
  return zip.close()!;
}

/// The part of the sheet named [name], from the workbook's relationships.
String _sheetPart(OpcPackage package, String name) {
  const String workbook = 'xl/workbook.xml';
  final XmlDocument book = XmlDocument.parse(
    utf8.decode(package.originalBytes(workbook)),
  );
  final XmlElement entry = book
      .findAllElements('sheet')
      .firstWhere(
        (XmlElement s) => s.getAttribute('name') == name,
        orElse: () => throw ArgumentError.value(name, 'sheet', 'no such sheet'),
      );
  final String id = entry.getAttribute('id', namespaceUri: _relationships)!;
  final OpcRelationship rel = package
      .relationshipsOf(workbook)
      .firstWhere((OpcRelationship r) => r.id == id);
  return package.resolve(workbook, rel.target);
}

/// The last row (counted from 1) of the sheet's `dimension`, or 0.
int _lastRow(String sheetXml) {
  final RegExpMatch? match = RegExp(
    r'<dimension ref="[A-Z]+\d+(?::[A-Z]+(\d+))?"',
  ).firstMatch(sheetXml);
  if (match == null) return 0;
  final RegExpMatch row = RegExp(r'(\d+)"$').firstMatch(match[0]!)!;
  return int.parse(row[1]!);
}
