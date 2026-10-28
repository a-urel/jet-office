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
  test('escapeXmlText leaves tab, LF and valid pairs alone', () {
    expect(escapeXmlText('a\tb\nc😀'), 'a\tb\nc😀');
  });
  test('escapeXmlText writes CR as a character reference', () {
    // A reader turns a literal CR (and CRLF) into LF (XML 1.0, 2.11).
    expect(escapeXmlText('a\rb\r\nc'), 'a&#13;b&#13;\nc');
  });
  test('escaping unscrubbed text is a programmer error', () {
    expect(() => escapeXmlText('a\u0001'), throwsArgumentError);
    expect(() => escapeXmlAttribute('\uD800'), throwsArgumentError);
  });

  test('scrub removes U+FFFE and U+FFFF', () {
    final ScrubResult r = scrubXmlText('a\uFFFEb\uFFFFc');
    expect(r.text, 'abc');
    expect(r.removed, 2);
  });
  test('scrub counts high, high, low as two removed units', () {
    final ScrubResult r = scrubXmlText('\uD83D\uD83D\uDE00');
    expect(r.text, '\uD83D\uDE00');
    expect(r.removed, 1);
    final ScrubResult lone = scrubXmlText('\uD83D\uD83Dx');
    expect(lone.text, 'x');
    expect(lone.removed, 2);
  });
  test('scrub boundaries: U+001F goes, U+0020 and U+007F stay', () {
    expect(scrubXmlText('\u001F').text, '');
    expect(scrubXmlText(' ').text, ' ');
    expect(scrubXmlText('\u007F').text, '\u007F');
  });
  test('escapeXmlText returns the identical instance when nothing changes', () {
    final String s = 'Şube '.padRight(10, 'x');
    expect(identical(escapeXmlText(s), s), isTrue);
    expect(identical(escapeXmlAttribute(s), s), isTrue);
  });
  test('escapeXmlAttribute throws on U+FFFF and U+FFFE', () {
    expect(() => escapeXmlAttribute('a\uFFFF'), throwsArgumentError);
    expect(() => escapeXmlText('\uFFFE'), throwsArgumentError);
  });
  test('the error names the index and code unit, not the whole string', () {
    final String long = 'x' * 500;
    try {
      escapeXmlText('$long\u0001$long');
      fail('should throw');
    } on ArgumentError catch (e) {
      final String m = e.toString();
      expect(m, contains('500'));
      expect(m, contains('0x0001'));
      expect(m.length, lessThan(300));
    }
  });
  test('runs between replacements survive intact', () {
    expect(escapeXmlText('ab&cd<ef😀gh>ij'), 'ab&amp;cd&lt;ef😀gh&gt;ij');
    expect(
      escapeXmlAttribute('long text here "q" and more text'),
      'long text here &quot;q&quot; and more text',
    );
  });

  test('escapeFormulaText escapes _xHHHH_ like cell text, then XML', () {
    // Decision 0005: Excel decodes `_xHHHH_` inside `<f>` and defined names,
    // and writes `_x005F_x` there itself.
    expect(escapeFormulaText('"_x0041_"&A1<2'), '"_x005F_x0041_"&amp;A1&lt;2');
    expect(escapeFormulaText("'D_x0041_'!\$A\$1"), "'D_x005F_x0041_'!\$A\$1");
    expect(escapeFormulaText('"_x0041_x0042_"'), '"_x005F_x0041_x005F_x0042_"');
    expect(escapeFormulaText('A1_x'), 'A1_x');
    expect(() => escapeFormulaText('a\u0001'), throwsArgumentError);
  });

  group('decodeXstring', () {
    test('decodes escapes', () {
      expect(decodeXstring('a_x0009_b'), 'a\tb');
      expect(decodeXstring('_x0041__x0042_'), 'AB');
      expect(decodeXstring('_x004a_'), 'J');
    });
    test('reverses escapeXstring, overlaps included', () {
      for (final String s in <String>[
        '_x0041_',
        '_x0041_x0042_',
        '_x005F_',
        '_x005f_',
        'a_x00',
        '__x0041_',
        'plain',
        '',
        '_x_',
        '_x12345_',
      ]) {
        expect(decodeXstring(escapeXstring(s)), s, reason: s);
      }
      expect(decodeXstring('_x005F_x0041_'), '_x0041_');
    });
    test('joins an escaped surrogate pair, keeps a lone one', () {
      expect(decodeXstring('_xD83D__xDE00_'), '😀');
      expect(decodeXstring('_xD83D_'), '_xD83D_');
    });
  });
}
