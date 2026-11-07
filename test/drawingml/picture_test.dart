import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/drawingml/picture.dart';
import 'package:jet_office/src/xlsx/drawing.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

import '../fixtures/m4_fixtures.dart';

const String _xdrNs =
    'http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing';
const String _aNs = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const String _picNs =
    'http://schemas.openxmlformats.org/drawingml/2006/picture';
const String _rNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

/// A reader on the first `pic` element of [xml].
XmlPullReader _onPic(String xml) {
  final XmlPullReader r = XmlPullReader(xml);
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement && r.localName == 'pic') {
      return r;
    }
  }
  throw StateError('No pic in $xml');
}

void main() {
  test('writer bytes are unchanged', () {
    final StringBuffer out = StringBuffer();
    writeDrawing(
      XmlWriter(out),
      <WorksheetPicture>[
        checkPicture(
          'S',
          1,
          XlsxPicture(
            OfficeImage(png4x2),
            const XlsxOneCellAnchor(
              XlsxAnchorPoint(1, 1, offsetX: 2, offsetY: 3),
              width: 8,
            ),
            description: 'a "b"',
          ),
        ),
        checkPicture(
          'S',
          2,
          XlsxPicture(
            OfficeImage(png4x2),
            const XlsxTwoCellAnchor(
              XlsxAnchorPoint(0, 0),
              XlsxAnchorPoint(2, 3),
              resize: XlsxPictureResize.move,
            ),
            name: 'N',
          ),
        ),
      ],
      <String>['rId1', 'rId2'],
    );
    expect(
      out.toString(),
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<xdr:wsDr xmlns:xdr="$_xdrNs" xmlns:a="$_aNs" xmlns:r="$_rNs">'
      '<xdr:oneCellAnchor><xdr:from><xdr:col>1</xdr:col>'
      '<xdr:colOff>19050</xdr:colOff><xdr:row>1</xdr:row>'
      '<xdr:rowOff>28575</xdr:rowOff></xdr:from>'
      '<xdr:ext cx="76200" cy="38100"/><xdr:pic><xdr:nvPicPr>'
      '<xdr:cNvPr id="2" name="Picture 1" descr="a &quot;b&quot;"/>'
      '<xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr>'
      '</xdr:nvPicPr><xdr:blipFill><a:blip r:embed="rId1"/><a:stretch>'
      '<a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:xfrm>'
      '<a:off x="0" y="0"/><a:ext cx="76200" cy="38100"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic>'
      '<xdr:clientData/></xdr:oneCellAnchor>'
      '<xdr:twoCellAnchor editAs="oneCell"><xdr:from><xdr:col>0</xdr:col>'
      '<xdr:colOff>0</xdr:colOff><xdr:row>0</xdr:row><xdr:rowOff>0</xdr:rowOff>'
      '</xdr:from><xdr:to><xdr:col>3</xdr:col><xdr:colOff>0</xdr:colOff>'
      '<xdr:row>2</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to><xdr:pic>'
      '<xdr:nvPicPr><xdr:cNvPr id="3" name="N"/><xdr:cNvPicPr>'
      '<a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr>'
      '<xdr:blipFill><a:blip r:embed="rId2"/><a:stretch><a:fillRect/>'
      '</a:stretch></xdr:blipFill><xdr:spPr><a:prstGeom prst="rect">'
      '<a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/>'
      '</xdr:twoCellAnchor></xdr:wsDr>',
    );
  });

  test('pixelsToEmu is 9,525 EMU per pixel', () {
    expect(emuPerPixel, 9525);
    expect(pixelsToEmu(2.5), 23813);
  });

  group('readDrawingPic', () {
    test('reads xdr: and pic: prefixes', () {
      final XmlPullReader xdr = _onPic(
        '<w xmlns:xdr="$_xdrNs" xmlns:a="$_aNs" xmlns:r="$_rNs"><xdr:pic>'
        '<xdr:nvPicPr><xdr:cNvPr id="7" name="Logo" descr="Alt"/>'
        '</xdr:nvPicPr><xdr:blipFill><a:blip r:embed="rId4"/></xdr:blipFill>'
        '</xdr:pic></w>',
      );
      final DrawingPic? a = readDrawingPic(xdr);
      expect(a!.id, 7);
      expect(a.name, 'Logo');
      expect(a.description, 'Alt');
      expect(a.embedId, 'rId4');
      expect(a.linkId, isNull);
      // Consumed: the reader is on the pic's end event.
      expect(xdr.eventType, XmlEventType.endElement);
      expect(xdr.localName, 'pic');

      final DrawingPic? b = readDrawingPic(
        _onPic(
          '<w xmlns:p="$_picNs" xmlns:x="$_aNs" xmlns:q="$_rNs"><p:pic>'
          '<p:nvPicPr><p:cNvPr id="0" name="image.png"/><p:cNvPicPr/>'
          '</p:nvPicPr><p:blipFill><x:blip q:link="rId9"/></p:blipFill>'
          '</p:pic></w>',
        ),
      );
      expect(b!.id, 0);
      expect(b.name, 'image.png');
      expect(b.description, isNull);
      expect(b.embedId, isNull);
      expect(b.linkId, 'rId9');
    });

    test('is null when cNvPr has no numeric id', () {
      expect(
        readDrawingPic(
          _onPic(
            '<w xmlns:xdr="$_xdrNs"><xdr:pic><xdr:nvPicPr>'
            '<xdr:cNvPr name="x"/></xdr:nvPicPr></xdr:pic></w>',
          ),
        ),
        isNull,
      );
      expect(
        readDrawingPic(
          _onPic(
            '<w xmlns:xdr="$_xdrNs"><xdr:pic><xdr:nvPicPr>'
            '<xdr:cNvPr id="abc" name="x"/></xdr:nvPicPr></xdr:pic></w>',
          ),
        ),
        isNull,
      );
    });
  });

  group('writeDrawingPic', () {
    test('with pic: writes the namespace\'s elements', () {
      final StringBuffer out = StringBuffer();
      writeDrawingPic(
        XmlWriter(out),
        const DrawingPic(id: 1, name: 'n', description: 'd', embedId: 'rId2'),
        prefix: 'pic',
        extent: (cx: 10, cy: 20),
      );
      expect(
        out.toString(),
        '<pic:pic><pic:nvPicPr><pic:cNvPr id="1" name="n" descr="d"/>'
        '<pic:cNvPicPr><a:picLocks noChangeAspect="1"/></pic:cNvPicPr>'
        '</pic:nvPicPr><pic:blipFill><a:blip r:embed="rId2"/><a:stretch>'
        '<a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm>'
        '<a:off x="0" y="0"/><a:ext cx="10" cy="20"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>',
      );
    });
  });
}
