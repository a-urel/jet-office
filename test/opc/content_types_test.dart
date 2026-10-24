import 'package:jet_office/src/opc/content_types.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

String _render(ContentTypes types) {
  final StringBuffer out = StringBuffer();
  types.write(XmlWriter(out));
  return out.toString();
}

void main() {
  test('writes defaults and overrides sorted, whatever the add order', () {
    final ContentTypes types = ContentTypes()
      ..addOverride('/xl/worksheets/sheet1.xml', ContentType.worksheet)
      ..addDefault('xml', ContentType.xml)
      ..addOverride('/xl/workbook.xml', ContentType.workbook)
      ..addDefault('rels', ContentType.relationships);
    expect(
      _render(types),
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '</Types>',
    );
  });

  test('sorts sheet10 after sheet2 by plain string order (deterministic)', () {
    final ContentTypes types = ContentTypes()
      ..addOverride('/xl/worksheets/sheet2.xml', ContentType.worksheet)
      ..addOverride('/xl/worksheets/sheet10.xml', ContentType.worksheet);
    final String xml = _render(types);
    expect(xml.indexOf('sheet10.xml'), lessThan(xml.indexOf('sheet2.xml')));
  });

  test('the same key with the same type is a no-op', () {
    final ContentTypes types = ContentTypes()
      ..addDefault('xml', ContentType.xml)
      ..addDefault('xml', ContentType.xml)
      ..addOverride('/xl/workbook.xml', ContentType.workbook)
      ..addOverride('/xl/workbook.xml', ContentType.workbook);
    final String xml = _render(types);
    expect('<Default '.allMatches(xml).length, 1);
    expect('<Override '.allMatches(xml).length, 1);
  });

  test('the same key with another type throws StateError', () {
    final ContentTypes types = ContentTypes()
      ..addDefault('xml', ContentType.xml)
      ..addOverride('/xl/workbook.xml', ContentType.workbook);
    expect(
      () => types.addDefault('xml', 'a/b'),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          allOf(contains('xml'), contains('a/b'), contains(ContentType.xml)),
        ),
      ),
    );
    expect(
      () => types.addOverride('/xl/workbook.xml', ContentType.worksheet),
      throwsStateError,
    );
  });

  test('keys are case-insensitive: a conflict is still a conflict', () {
    final ContentTypes types = ContentTypes()
      ..addDefault('xml', ContentType.xml)
      ..addOverride('/xl/workbook.xml', ContentType.workbook);
    expect(() => types.addDefault('XML', 'a/b'), throwsStateError);
    expect(
      () => types.addOverride('/xl/Workbook.xml', ContentType.worksheet),
      throwsStateError,
    );
  });

  test('case variants with the same type are a no-op, first spelling wins', () {
    final ContentTypes types = ContentTypes()
      ..addDefault('Xml', ContentType.xml)
      ..addDefault('XML', ContentType.xml.toUpperCase())
      ..addOverride('/xl/Workbook.xml', ContentType.workbook)
      ..addOverride('/xl/workbook.xml', ContentType.workbook);
    final String xml = _render(types);
    expect('<Default '.allMatches(xml).length, 1);
    expect('<Override '.allMatches(xml).length, 1);
    expect(xml, contains('Extension="Xml"'));
    expect(xml, contains('PartName="/xl/Workbook.xml"'));
  });

  test('bad extensions and part names throw ArgumentError', () {
    final ContentTypes types = ContentTypes();
    expect(() => types.addDefault('', ContentType.xml), throwsArgumentError);
    expect(
      () => types.addDefault('.xml', ContentType.xml),
      throwsArgumentError,
    );
    expect(() => types.addDefault('a.b', ContentType.xml), throwsArgumentError);
    expect(
      () => types.addOverride('xl/workbook.xml', ContentType.workbook),
      throwsArgumentError,
    );
  });

  test('constants hold the ECMA-376 values', () {
    expect(
      ContentType.workbook,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml',
    );
    expect(
      ContentType.worksheet,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml',
    );
    expect(
      ContentType.styles,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml',
    );
    expect(
      ContentType.sharedStrings,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml',
    );
    expect(
      ContentType.coreProperties,
      'application/vnd.openxmlformats-package.core-properties+xml',
    );
    expect(
      ContentType.extendedProperties,
      'application/vnd.openxmlformats-officedocument.extended-properties+xml',
    );
    expect(
      Ns.main,
      'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
    );
    expect(
      Ns.rel,
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
    );
  });
}
