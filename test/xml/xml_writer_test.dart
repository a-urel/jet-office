import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

void main() {
  test('writer produces compact XML', () {
    final StringBuffer out = StringBuffer();
    XmlWriter(out)
      ..declaration()
      ..start('a')
      ..attribute('k', 'x"y')
      ..start('b')
      ..end()
      ..text('1 < 2')
      ..end();
    expect(
      out.toString(),
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<a k="x&quot;y"><b/>1 &lt; 2</a>',
    );
  });

  test('raw closes an open start tag first', () {
    final StringBuffer out = StringBuffer();
    XmlWriter(out)
      ..start('row')
      ..attribute('r', '1')
      ..raw('<x/>')
      ..end();
    expect(out.toString(), '<row r="1"><x/></row>');
  });

  test('empty writes a self-closing element with attributes', () {
    final StringBuffer out = StringBuffer();
    XmlWriter(out)
      ..start('a')
      ..empty('b', <String, String>{'k': 'v', 'n': '1'})
      ..empty('c')
      ..end();
    expect(out.toString(), '<a><b k="v" n="1"/><c/></a>');
  });

  test('attribute after content is a StateError', () {
    final XmlWriter w = XmlWriter(StringBuffer())
      ..start('a')
      ..text('t');
    expect(() => w.attribute('k', 'v'), throwsStateError);
  });

  test('attribute with no open element is a StateError', () {
    expect(
      () => XmlWriter(StringBuffer()).attribute('k', 'v'),
      throwsStateError,
    );
  });

  test('end without open element is a StateError', () {
    expect(() => XmlWriter(StringBuffer()).end(), throwsStateError);
  });

  test('text and attribute reject unscrubbed input', () {
    final XmlWriter w = XmlWriter(StringBuffer())..start('a');
    expect(() => w.attribute('k', 'a\u0000'), throwsArgumentError);
    expect(() => w.text('\uD800'), throwsArgumentError);
  });
}
