// Tests the parsing helpers the property codecs share and the style id
// codec. They need no file, so they run on the web as well: the decimal
// cases pin that a number reads the same on the VM and in JavaScript.
import 'package:jet_office/src/docx/property_codec.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

/// The element [xml] (inside a root that declares `w` and `w14`) as a codec
/// sees it.
PropertyElement _element(String xml) {
  final XmlPullReader r = XmlPullReader(
    '<w:document xmlns:w="${Ns.w}" xmlns:w14="${Ns.w14}">$xml</w:document>',
  );
  r.nextTag();
  r.nextTag();
  final PropertyElementBuilder builder = PropertyElementBuilder();
  OpaqueXml.capture(r, onEvent: builder.add);
  return builder.element!;
}

enum _Shape { round, square }

void main() {
  test('parseOnOff reads absent, true, 1, on, false, 0, off and refuses '
      'maybe', () {
    expect(parseOnOff(null), isTrue);
    expect(parseOnOff('true'), isTrue);
    expect(parseOnOff('1'), isTrue);
    expect(parseOnOff('on'), isTrue);
    expect(parseOnOff('false'), isFalse);
    expect(parseOnOff('0'), isFalse);
    expect(parseOnOff('off'), isFalse);
    expect(parseOnOff('maybe'), isNull);
    expect(parseOnOff('TRUE'), isNull);
    expect(parseOnOff(''), isNull);
  });

  test('parseDecimal refuses ten digits, a sign alone, a plus sign, 1in and '
      '12.5', () {
    const int min = -2147483648;
    const int max = 2147483647;
    expect(parseDecimal('1234567890', min: min, max: max), isNull);
    expect(parseDecimal('-1234567890', min: min, max: max), isNull);
    expect(parseDecimal('-', min: min, max: max), isNull);
    expect(parseDecimal('+24', min: min, max: max), isNull);
    expect(parseDecimal('1in', min: min, max: max), isNull);
    expect(parseDecimal('12.5', min: min, max: max), isNull);
    expect(parseDecimal('', min: min, max: max), isNull);
    expect(parseDecimal(' 1', min: min, max: max), isNull);
    expect(parseDecimal(null, min: min, max: max), isNull);
    // Leading zeros are a valid ST_DecimalNumber.
    expect(parseDecimal('024', min: min, max: max), 24);
    expect(parseDecimal('-0', min: min, max: max), 0);
    // Out of the codec's range.
    expect(parseDecimal('1639', min: 1, max: 1638), isNull);
    expect(parseDecimal('0', min: 1, max: 1638), isNull);
    expect(parseDecimal('1638', min: 1, max: 1638), 1638);
  });

  test('parseDecimal of -999999999 and 999999999 is exact', () {
    const int min = -999999999;
    const int max = 999999999;
    expect(parseDecimal('-999999999', min: min, max: max), -999999999);
    expect(parseDecimal('999999999', min: min, max: max), 999999999);
    expect(parseDecimal('000000001', min: min, max: max), 1);
  });

  test('parseHex6 accepts 00ff7F and refuses FF00 and red', () {
    expect(parseHex6('00ff7F'), '00FF7F');
    expect(parseHex6('FF0000'), 'FF0000');
    expect(parseHex6('FF00'), isNull);
    expect(parseHex6('red'), isNull);
    expect(parseHex6('FF00000'), isNull);
    expect(parseHex6('GG0000'), isNull);
    expect(parseHex6(null), isNull);
  });

  test('parseHexByte accepts two hex digits only', () {
    expect(parseHexByte('00'), 0);
    expect(parseHexByte('bF'), 0xBF);
    expect(parseHexByte('FF'), 255);
    expect(parseHexByte('F'), isNull);
    expect(parseHexByte('100'), isNull);
    expect(parseHexByte('-1'), isNull);
    expect(parseHexByte(null), isNull);
  });

  test('parseEnum reads a value of the map and nothing else', () {
    const Map<String, _Shape> byXml = <String, _Shape>{
      'round': _Shape.round,
      'square': _Shape.square,
    };
    expect(parseEnum('round', byXml), _Shape.round);
    expect(parseEnum('Round', byXml), isNull);
    expect(parseEnum(null, byXml), isNull);
  });

  group('PropertyElement', () {
    test('holds the attributes, children and text of the element', () {
      final PropertyElement e = _element(
        '<w:rFonts w:ascii="Arial" w14:x="1" plain="p">'
        '<w:a w:val="1"/><w:b>t</w:b></w:rFonts>',
      );
      expect(e.localName, 'rFonts');
      expect(e.namespaceUri, Ns.w);
      expect(e.w('ascii'), 'Arial');
      expect(e.w('x'), isNull);
      expect(e.wAttributeNames, <String>{'ascii'});
      expect(e.attributes.map((KeptAttribute a) => a.qualifiedName), <String>[
        'w:ascii',
        'w14:x',
        'plain',
      ]);
      expect(e.hasText, isFalse);
      expect(e.children.map((PropertyElement c) => c.localName), <String>[
        'a',
        'b',
      ]);
      expect(e.children.first.w('val'), '1');
      expect(e.children.last.hasText, isTrue);
    });

    test('whitespace is not text', () {
      expect(_element('<w:b> </w:b>').hasText, isFalse);
      expect(_element('<w:b> x </w:b>').hasText, isTrue);
    });
  });

  group('the style id codec', () {
    const StyleIdCodec codec = StyleIdCodec('pStyle');

    test('reads a non-empty w:val of an element without children', () {
      expect(codec.attributes, <String>{'val'});
      expect(codec.parse(_element('<w:pStyle w:val="Title"/>')), 'Title');
      expect(codec.parse(_element('<w:pStyle w:val=""/>')), isNull);
      expect(codec.parse(_element('<w:pStyle/>')), isNull);
      expect(
        codec.parse(_element('<w:pStyle w:val="Title"><w:x/></w:pStyle>')),
        isNull,
      );
      expect(
        codec.parse(_element('<w:pStyle w:val="Title">t</w:pStyle>')),
        isNull,
      );
    });

    test('writes w:val with the prefix given', () {
      final StringBuffer b = StringBuffer();
      codec.write(XmlWriter(b), 'ns0', 'A & B', null);
      expect(b.toString(), '<ns0:pStyle ns0:val="A &amp; B"/>');
    });
  });
}
