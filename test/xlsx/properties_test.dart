import 'package:jet_office/src/xlsx/properties.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

String _core(XlsxProperties p) {
  final StringBuffer out = StringBuffer();
  writeCoreProperties(XmlWriter(out), p);
  return out.toString();
}

String _app(XlsxProperties p) {
  final StringBuffer out = StringBuffer();
  writeAppProperties(XmlWriter(out), p);
  return out.toString();
}

const String _coreRoot =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<cp:coreProperties'
    ' xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"'
    ' xmlns:dc="http://purl.org/dc/elements/1.1/"'
    ' xmlns:dcterms="http://purl.org/dc/terms/"'
    ' xmlns:dcmitype="http://purl.org/dc/dcmitype/"'
    ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">';

void main() {
  test('core writes only the given fields, dates as UTC W3CDTF seconds', () {
    final String xml = _core(
      XlsxProperties(
        title: 'Cari Hesaplar',
        created: DateTime.utc(2026, 10, 24, 9, 30, 15, 500),
      ),
    );
    expect(
      xml,
      '$_coreRoot<dc:title>Cari Hesaplar</dc:title>'
      '<dcterms:created xsi:type="dcterms:W3CDTF">2026-10-24T09:30:15Z</dcterms:created>'
      '</cp:coreProperties>',
    );
    expect(xml, isNot(contains('dcterms:modified')));
  });

  test('empty properties write no dcterms date elements', () {
    final String xml = _core(const XlsxProperties());
    expect(xml, '${_coreRoot.substring(0, _coreRoot.length - 1)}/>');
    expect(xml, isNot(contains('<dcterms:')));
  });

  test('core keeps the order Excel writes', () {
    final String xml = _core(
      XlsxProperties(
        modified: DateTime.utc(2026, 1, 2, 3, 4, 5),
        created: DateTime.utc(2026, 1, 1),
        category: 'cat',
        lastModifiedBy: 'lmb',
        description: 'desc',
        keywords: 'kw',
        creator: 'cr',
        subject: 'sub',
        title: 'ti',
      ),
    );
    final List<String> order = <String>[
      '<dc:title>',
      '<dc:subject>',
      '<dc:creator>',
      '<cp:keywords>',
      '<dc:description>',
      '<cp:lastModifiedBy>',
      '<cp:category>',
      '<dcterms:created ',
      '<dcterms:modified ',
    ];
    final List<int> at = order.map(xml.indexOf).toList();
    expect(at, everyElement(isNonNegative));
    expect(at, orderedEquals(<int>[...at]..sort()));
  });

  test('a local DateTime is converted to UTC', () {
    final DateTime local = DateTime.utc(2026, 6, 1, 12).toLocal();
    expect(
      _core(XlsxProperties(modified: local)),
      contains('>2026-06-01T12:00:00Z<'),
    );
  });

  test('text is escaped', () {
    expect(
      _core(const XlsxProperties(title: 'A & B <c>')),
      contains('<dc:title>A &amp; B &lt;c&gt;</dc:title>'),
    );
  });

  test('forbidden characters throw ArgumentError', () {
    expect(
      () => _core(const XlsxProperties(title: 'a\u0000b')),
      throwsArgumentError,
    );
    expect(
      () => _app(const XlsxProperties(company: 'a\uD800')),
      throwsArgumentError,
    );
  });

  test('app writes Application and Company when set', () {
    const String head =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
        '<Application>jet_office</Application>';
    expect(_app(const XlsxProperties()), '$head</Properties>');
    expect(
      _app(const XlsxProperties(company: 'Jetronik')),
      '$head<Company>Jetronik</Company></Properties>',
    );
  });
}
