import 'package:jet_office/src/xlsx/font.dart';
import 'package:jet_office/src/xlsx/rich_text.dart';
import 'package:jet_office/src/xlsx/shared_strings.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

void main() {
  test('count counts references, uniqueCount counts strings', () {
    final SharedStrings s = SharedStrings();
    expect(s.indexOf('TRY'), 0);
    expect(s.indexOf('EUR'), 1);
    expect(s.indexOf('TRY'), 0);
    expect(s.count, 3);
    expect(s.uniqueCount, 2);
    expect(s.values, <String>['TRY', 'EUR']);
  });

  test('values is unmodifiable', () {
    final SharedStrings s = SharedStrings()..indexOf('a');
    expect(() => s.values.add('b'), throwsUnsupportedError);
  });

  test('xml marks only padded text as preserved', () {
    final SharedStrings s = SharedStrings()
      ..indexOf('a')
      ..indexOf(' b')
      ..indexOf('c\n');
    final StringBuffer out = StringBuffer();
    s.writeXml(XmlWriter(out));
    expect(
      out.toString(),
      endsWith(
        '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="3" uniqueCount="3">'
        '<si><t>a</t></si><si><t xml:space="preserve"> b</t></si><si><t xml:space="preserve">c\n</t></si></sst>',
      ),
    );
    expect(out.toString(), startsWith('<?xml '));
  });

  test('xml writes count and uniqueCount separately', () {
    final SharedStrings s = SharedStrings()
      ..indexOf('x')
      ..indexOf('x');
    final StringBuffer out = StringBuffer();
    s.writeXml(XmlWriter(out));
    expect(out.toString(), contains('count="2" uniqueCount="1"'));
  });

  test('an empty table writes an empty sst', () {
    final StringBuffer out = StringBuffer();
    SharedStrings().writeXml(XmlWriter(out));
    expect(out.toString(), endsWith('count="0" uniqueCount="0"/>'));
  });

  test('text that looks like an _xHHHH_ escape is written escaped', () {
    final SharedStrings s = SharedStrings()
      ..indexOf('_x0041_')
      ..indexOf('a_x00e9_b')
      ..indexOf('_x0041_x0042_')
      ..indexOf('_x00G1_ _x041_ x0041_');
    final StringBuffer out = StringBuffer();
    s.writeXml(XmlWriter(out));
    expect(
      out.toString(),
      contains(
        '<si><t>_x005F_x0041_</t></si>'
        '<si><t>a_x005F_x00e9_b</t></si>'
        '<si><t>_x005F_x0041_x005F_x0042_</t></si>'
        '<si><t>_x00G1_ _x041_ x0041_</t></si>',
      ),
    );
  });

  test('the table keeps and deduplicates the original text', () {
    final SharedStrings s = SharedStrings();
    expect(s.indexOf('_x0041_'), 0);
    expect(s.indexOf('_x005F_x0041_'), 1);
    expect(s.indexOf('_x0041_'), 0);
    expect(s.values, <String>['_x0041_', '_x005F_x0041_']);
    expect(s.uniqueCount, 2);
  });

  test('tab-only, CR-only and whitespace-only text is preserved', () {
    final SharedStrings s = SharedStrings()
      ..indexOf('\t')
      ..indexOf('\r')
      ..indexOf('  ');
    final StringBuffer out = StringBuffer();
    s.writeXml(XmlWriter(out));
    expect(
      out.toString(),
      contains(
        '<si><t xml:space="preserve">\t</t></si>'
        '<si><t xml:space="preserve">&#13;</t></si>'
        '<si><t xml:space="preserve">  </t></si>',
      ),
    );
  });

  test('values is a snapshot: later strings do not change it', () {
    final SharedStrings s = SharedStrings()..indexOf('a');
    final List<String> before = s.values;
    s.indexOf('b');
    expect(before, <String>['a']);
    expect(s.values, <String>['a', 'b']);
  });

  group('indexOfRich', () {
    const XlsxFont bold = XlsxFont(bold: true);
    XlsxRichText rich(List<XlsxTextRun> runs) => XlsxRichText(runs);

    String xml(SharedStrings s) {
      final StringBuffer out = StringBuffer();
      s.writeXml(XmlWriter(out));
      return out.toString();
    }

    test('deduplicates equal rich texts and counts every reference', () {
      final SharedStrings s = SharedStrings();
      expect(s.indexOf('a'), 0);
      expect(
        s.indexOfRich(
          rich(const <XlsxTextRun>[
            XlsxTextRun('a', font: bold),
            XlsxTextRun('b'),
          ]),
        ),
        1,
      );
      expect(
        s.indexOfRich(
          rich(const <XlsxTextRun>[
            XlsxTextRun('a', font: XlsxFont(bold: true)),
            XlsxTextRun('b'),
          ]),
        ),
        1,
      );
      expect(
        s.indexOfRich(
          rich(const <XlsxTextRun>[
            XlsxTextRun('a'),
            XlsxTextRun('b', font: bold),
          ]),
        ),
        2,
      );
      expect(s.count, 4);
      expect(s.uniqueCount, 3);
    });

    test('one run without a font is the plain string', () {
      final SharedStrings s = SharedStrings();
      expect(s.indexOfRich(rich(const <XlsxTextRun>[XlsxTextRun('abc')])), 0);
      expect(s.indexOf('abc'), 0);
      expect(s.count, 2);
      expect(s.uniqueCount, 1);
      expect(xml(s), endsWith('uniqueCount="1"><si><t>abc</t></si></sst>'));
    });

    test('one run with a font is a rich entry', () {
      final SharedStrings s = SharedStrings();
      expect(s.indexOf('abc'), 0);
      expect(
        s.indexOfRich(
          rich(const <XlsxTextRun>[XlsxTextRun('abc', font: bold)]),
        ),
        1,
      );
      expect(s.uniqueCount, 2);
    });

    test('rich entries are written as runs, in index order', () {
      final SharedStrings s = SharedStrings()
        ..indexOf(' x')
        ..indexOfRich(
          rich(const <XlsxTextRun>[
            XlsxTextRun('Total: ', font: bold),
            XlsxTextRun('_x0041_'),
          ]),
        )
        ..indexOf('y');
      expect(
        xml(s),
        endsWith(
          'count="3" uniqueCount="3">'
          '<si><t xml:space="preserve"> x</t></si>'
          '<si><r><rPr><b/></rPr><t xml:space="preserve">Total: </t></r>'
          '<r><t>_x005F_x0041_</t></r></si>'
          '<si><t>y</t></si></sst>',
        ),
      );
    });

    test('values gives a rich entry as its joined text', () {
      final SharedStrings s = SharedStrings()
        ..indexOf('a')
        ..indexOfRich(
          rich(const <XlsxTextRun>[
            XlsxTextRun('b', font: bold),
            XlsxTextRun('c'),
          ]),
        );
      expect(s.values, <String>['a', 'bc']);
    });
  });
}
