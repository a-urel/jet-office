// Tests the writer of a built inline picture, `writeInlineDrawing`: its
// output for one fixed picture is pinned, it declares `wp`, `a`, `pic` and `r`
// only where the bindings above do not, and what it writes reads back through
// `readInlineDrawing`. They write strings, so they run on the web as well.
import 'package:jet_office/src/docx/drawing.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

const String _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const String _pic = 'http://schemas.openxmlformats.org/drawingml/2006/picture';

const BuiltInlineDrawing _picture = (
  id: 5,
  name: 'Logo & "mark"',
  description: 'Alt <text>',
  embedId: 'rId7',
  cx: 38100,
  cy: 19050,
);

String _write(BuiltInlineDrawing picture, Map<String, String> above) {
  final StringBuffer out = StringBuffer();
  writeInlineDrawing(XmlWriter(out), picture, declaredAbove: above);
  return out.toString();
}

void main() {
  test('the output for one fixed picture', () {
    expect(
      _write(_picture, const <String, String>{
        'wp': Ns.wp,
        'a': _a,
        'pic': _pic,
        'r': Ns.rel,
      }),
      '<wp:inline distT="0" distB="0" distL="0" distR="0">'
      '<wp:extent cx="38100" cy="19050"/>'
      '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
      '<wp:docPr id="5" name="Logo &amp; &quot;mark&quot;" '
      'descr="Alt &lt;text&gt;"/>'
      '<wp:cNvGraphicFramePr>'
      '<a:graphicFrameLocks noChangeAspect="1"/>'
      '</wp:cNvGraphicFramePr>'
      '<a:graphic>'
      '<a:graphicData uri="$_pic">'
      '<pic:pic>'
      '<pic:nvPicPr>'
      '<pic:cNvPr id="5" name="Logo &amp; &quot;mark&quot;" '
      'descr="Alt &lt;text&gt;"/>'
      '<pic:cNvPicPr><a:picLocks noChangeAspect="1"/></pic:cNvPicPr>'
      '</pic:nvPicPr>'
      '<pic:blipFill><a:blip r:embed="rId7"/>'
      '<a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
      '<pic:spPr><a:xfrm><a:off x="0" y="0"/>'
      '<a:ext cx="38100" cy="19050"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
      '</pic:pic>'
      '</a:graphicData>'
      '</a:graphic>'
      '</wp:inline>',
    );
  });

  test('declares what is not bound above, as Word does', () {
    final String xml = _write(_picture, const <String, String>{});
    expect(xml, startsWith('<wp:inline xmlns:wp="${Ns.wp}" distT="0" '));
    expect(xml, contains('<a:graphicFrameLocks xmlns:a="$_a" '));
    expect(xml, contains('<a:graphic xmlns:a="$_a">'));
    expect(xml, contains('<pic:pic xmlns:pic="$_pic" xmlns:r="${Ns.rel}">'));
  });

  test('a prefix bound to another namespace above is bound again', () {
    final String xml = _write(_picture, const <String, String>{
      'wp': 'urn:other',
      'a': 'urn:other',
      'pic': _pic,
      'r': Ns.rel,
    });
    expect(xml, startsWith('<wp:inline xmlns:wp="${Ns.wp}" '));
    expect(xml, contains('<a:graphic xmlns:a="$_a">'));
    expect(xml, contains('<pic:pic>'));
  });

  test('no description writes no descr, no embed id no r:embed', () {
    final String xml = _write((
      id: 1,
      name: 'Picture 1',
      description: null,
      embedId: null,
      cx: 1,
      cy: 2,
    ), const <String, String>{});
    expect(xml, isNot(contains('descr=')));
    expect(xml, contains('<a:blip/>'));
  });

  test('what it writes reads back as an inline picture', () {
    final String xml = _write(_picture, const <String, String>{});
    final XmlPullReader r = XmlPullReader(
      '<w:drawing xmlns:w="${Ns.w}">$xml</w:drawing>',
    );
    while (r.next() && r.eventType != XmlEventType.startElement) {}
    final InlineDrawing? read = readInlineDrawing(r);
    expect(read, isNotNull);
    expect(read!.widthPt, 3);
    expect(read.heightPt, 1.5);
    expect(read.name, 'Logo & "mark"');
    expect(read.description, 'Alt <text>');
    expect(read.embedId, 'rId7');
  });
}
