import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/xlsx/color.dart' as impl;
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

String attrs(XlsxColor color) {
  final StringBuffer out = StringBuffer();
  final XmlWriter w = XmlWriter(out)..start('c');
  impl.writeColorAttributes(w, color);
  w.end();
  return out.toString();
}

void main() {
  test('equality is by meaning', () {
    const XlsxColor a = XlsxColor.rgb(0x1F4E79);
    const XlsxColor b = XlsxColor.argb(0xFF1F4E79);
    final XlsxColor c = XlsxColor.hex('#1f4e79');
    expect(a, b);
    expect(b, c);
    expect(a.hashCode, b.hashCode);
    expect(b.hashCode, c.hashCode);
    expect(XlsxColor.hex('FF1F4E79'), a);
    expect(const XlsxColor.argb(0x801F4E79), isNot(a));
    expect(const XlsxColor.theme(4), isNot(const XlsxColor.indexed(4)));
    expect(
      const XlsxColor.theme(4, tint: 0.5),
      isNot(const XlsxColor.theme(4)),
    );
    expect(XlsxColor.auto, XlsxColor.auto);
  });

  test('hex rejects malformed text', () {
    expect(() => XlsxColor.hex('GG0000'), throwsArgumentError);
    expect(() => XlsxColor.hex('12345'), throwsArgumentError);
    expect(() => XlsxColor.hex(''), throwsArgumentError);
  });

  test('hex throws where Quds normalizeRgb returned an empty string', () {
    expect(() => XlsxColor.hex('red'), throwsArgumentError);
  });

  test('validateColor checks each kind', () {
    impl.validateColor(const XlsxColor.theme(11), 'color');
    impl.validateColor(const XlsxColor.theme(0, tint: -1), 'color');
    impl.validateColor(const XlsxColor.indexed(65), 'color');
    impl.validateColor(const XlsxColor.rgb(0xFFFFFF), 'color');
    impl.validateColor(const XlsxColor.argb(0xFFFFFFFF), 'color');
    impl.validateColor(XlsxColor.auto, 'color');
    void bad(XlsxColor c) => expect(
      () => impl.validateColor(c, 'color'),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.name,
          'name',
          'color',
        ),
      ),
    );
    bad(const XlsxColor.theme(12));
    bad(const XlsxColor.theme(-1));
    bad(const XlsxColor.theme(4, tint: 1.5));
    bad(const XlsxColor.theme(4, tint: double.nan));
    bad(const XlsxColor.indexed(66));
    bad(const XlsxColor.indexed(-1));
    bad(const XlsxColor.rgb(0x1000000));
    bad(const XlsxColor.rgb(-1));
    bad(const XlsxColor.argb(0x100000000));
    bad(const XlsxColor.argb(-1));
  });

  test('an out-of-range rgb does not alias an argb value', () {
    expect(
      const XlsxColor.rgb(0x1000000),
      isNot(const XlsxColor.argb(0xFF000000)),
    );
  });

  test('writes the attribute forms', () {
    expect(attrs(const XlsxColor.rgb(0x1F4E79)), '<c rgb="FF1F4E79"/>');
    expect(attrs(const XlsxColor.argb(0x0A0B0C0D)), '<c rgb="0A0B0C0D"/>');
    expect(attrs(const XlsxColor.rgb(0xAB)), '<c rgb="FF0000AB"/>');
    expect(attrs(const XlsxColor.theme(4)), '<c theme="4"/>');
    expect(
      attrs(const XlsxColor.theme(4, tint: -0.25)),
      '<c theme="4" tint="-0.25"/>',
    );
    expect(attrs(const XlsxColor.indexed(64)), '<c indexed="64"/>');
    expect(attrs(XlsxColor.auto), '<c auto="1"/>');
  });

  test('toString names the kind', () {
    expect(const XlsxColor.rgb(0x1F4E79).toString(), contains('FF1F4E79'));
  });
}
