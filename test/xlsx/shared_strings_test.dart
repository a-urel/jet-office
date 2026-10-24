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
}
