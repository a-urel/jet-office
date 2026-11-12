import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/src/xlsx/model/drawing_part.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

const String _head =
    '<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">';

DrawingPart? _read(String xml, [List<String>? warnings]) =>
    DrawingPart.read(XmlPullReader(xml), warn: (warnings ?? <String>[]).add);

String _encoded(DrawingPart part) =>
    utf8.decode(part.encode().expand((Uint8List c) => c).toList());

void main() {
  const String pic =
      '<xdr:pic><xdr:nvPicPr><xdr:cNvPr id="4" name="P"/></xdr:nvPicPr>'
      '<xdr:blipFill><a:blip r:embed="rId1"/></xdr:blipFill></xdr:pic>';
  const String anchor =
      '<xdr:oneCellAnchor><xdr:from><xdr:col>1</xdr:col><xdr:colOff>0'
      '</xdr:colOff><xdr:row>2</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>'
      '<xdr:ext cx="9525" cy="9525"/>$pic<xdr:clientData/></xdr:oneCellAnchor>';
  const String frame =
      '<xdr:twoCellAnchor><xdr:graphicFrame><xdr:nvGraphicFramePr>'
      '<xdr:cNvPr id="9" name="Chart"/></xdr:nvGraphicFramePr>'
      '</xdr:graphicFrame></xdr:twoCellAnchor>';

  test('keeps every child, types the picture, collects the ids', () {
    final DrawingPart part = _read('$_head$frame$anchor</xdr:wsDr>')!;
    expect(part.entries, hasLength(2));
    expect(part.entries[0].anchor, isNull);
    expect(part.entries[0].pic, isNull);
    expect(part.entries[1].pic!.id, 4);
    expect(part.entries[1].pic!.embedId, 'rId1');
    expect(part.entries[0].ids, <int>[9]);
    expect(part.entries[1].ids, <int>[4]);
    expect(part.nextId, 10);
  });

  test('encode writes the root and the entries back', () {
    final DrawingPart part = _read('$_head$frame$anchor</xdr:wsDr>')!;
    expect(
      _encoded(part),
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '$_head$frame$anchor</xdr:wsDr>',
    );
    part.entries.removeAt(0);
    expect(_encoded(part), contains(anchor));
    expect(_encoded(part), isNot(contains('Chart')));
  });

  test('types a chart frame: its anchor, cNvPr and chart r:id', () {
    String chart({String cNvPr = 'id="7" name="Chart 2" descr="D"'}) =>
        '<xdr:oneCellAnchor><xdr:from><xdr:col>1</xdr:col><xdr:row>2</xdr:row>'
        '</xdr:from><xdr:ext cx="95250" cy="19050"/><xdr:graphicFrame>'
        '<xdr:nvGraphicFramePr><xdr:cNvPr $cNvPr/></xdr:nvGraphicFramePr>'
        '<a:graphic><a:graphicData '
        'uri="http://schemas.openxmlformats.org/drawingml/2006/chart">'
        '<c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/'
        'chart" r:id="rId4"/></a:graphicData></a:graphic></xdr:graphicFrame>'
        '<xdr:clientData/></xdr:oneCellAnchor>';
    final List<String> warnings = <String>[];
    final DrawingPart part = _read(
      '$_head${chart()}${chart(cNvPr: 'name="X"')}</xdr:wsDr>',
      warnings,
    )!;
    final DrawingEntry typed = part.entries[0];
    expect(typed.chartFrame, (
      id: 7,
      name: 'Chart 2',
      description: 'D',
      chartId: 'rId4',
    ));
    expect(typed.pic, isNull);
    expect(typed.anchor, isNotNull);
    expect(part.entries[1].chartFrame, isNull);
    expect(part.entries[1].anchor, isNull);
    expect(warnings, <String>['chart']);
    // A frame of no chart is no chart, and no problem.
    expect(
      _read('$_head$frame</xdr:wsDr>', warnings)!.entries[0].chartFrame,
      isNull,
    );
    expect(warnings, <String>['chart']);
  });

  test('is null when the root is no spreadsheet drawing', () {
    expect(_read('<root/>'), isNull);
    expect(_read('<wsDr/>'), isNull);
  });

  test('warns pic for a pic with neither embed nor link', () {
    final List<String> warnings = <String>[];
    final DrawingPart part = _read(
      '$_head${anchor.replaceAll('<a:blip r:embed="rId1"/>', '<a:blip/>')}'
      '</xdr:wsDr>',
      warnings,
    )!;
    expect(warnings, <String>['pic']);
    expect(part.entries.single.pic, isNull);
  });

  test('DrawingPart.empty encodes a bare root', () {
    expect(
      _encoded(DrawingPart.empty()),
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '${_head.substring(0, _head.length - 1)}/>',
    );
  });
}
