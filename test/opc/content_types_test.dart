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

  test('a later add for the same key replaces the earlier one', () {
    final ContentTypes types = ContentTypes()
      ..addDefault('xml', 'a/b')
      ..addDefault('xml', ContentType.xml);
    expect(_render(types), contains('ContentType="application/xml"'));
    expect(_render(types), isNot(contains('a/b')));
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
