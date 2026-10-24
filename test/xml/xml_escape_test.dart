import 'package:jet_office/src/xml/xml_escape.dart';
import 'package:test/test.dart';

void main() {
  test('scrub removes control characters Quds passed through', () {
    final ScrubResult r = scrubXmlText('a\u0000b\u0001c\u001Fd');
    expect(r.text, 'abcd');
    expect(r.removed, 3);
  });
  test('scrub keeps tab, LF and CR', () {
    expect(scrubXmlText('a\tb\nc\rd').text, 'a\tb\nc\rd');
  });
  test('scrub removes lone surrogates and U+FFFE/U+FFFF, keeps pairs', () {
    final ScrubResult r = scrubXmlText('x\uD800y\uDC00z￾￿😀');
    expect(r.text, 'xyz😀');
    expect(r.removed, 4);
  });
  test('scrub removes a high surrogate at the end of the string', () {
    final ScrubResult r = scrubXmlText('ab\uD83D');
    expect(r.text, 'ab');
    expect(r.removed, 1);
  });
  test('scrub removes a reversed surrogate pair', () {
    final ScrubResult r = scrubXmlText('\uDE00\uD83D');
    expect(r.text, '');
    expect(r.removed, 2);
  });
  test('scrub returns the same instance when clean', () {
    const String s = 'Şube Müdürü & Co';
    expect(identical(scrubXmlText(s).text, s), isTrue);
    expect(scrubXmlText(s).removed, 0);
  });
  test('escapeXmlText', () {
    expect(escapeXmlText('a<b>&"c\''), 'a&lt;b&gt;&amp;"c\'');
  });
  test('escapeXmlAttribute encodes quote and whitespace controls', () {
    expect(escapeXmlAttribute('a"b\tc\nd\re'), 'a&quot;b&#9;c&#10;d&#13;e');
  });
  test('escapeXmlText leaves tab, LF, CR and valid pairs alone', () {
    expect(escapeXmlText('a\tb\nc\r😀'), 'a\tb\nc\r😀');
  });
  test('escaping unscrubbed text is a programmer error', () {
    expect(() => escapeXmlText('a\u0001'), throwsArgumentError);
    expect(() => escapeXmlAttribute('\uD800'), throwsArgumentError);
  });
}
