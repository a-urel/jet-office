import 'package:jet_office/src/docx/properties.dart';
import 'package:jet_office/src/docx/schema_order.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

/// The namespaces the test documents declare on their root.
const Map<String, String> _above = <String, String>{'w': Ns.w, 'w14': Ns.w14};

/// A reader on the first child of a root that declares [_above] and holds
/// [inner].
XmlPullReader _readerOn(String inner) {
  final XmlPullReader r = XmlPullReader(
    '<w:document xmlns:w="${Ns.w}" xmlns:w14="${Ns.w14}">$inner'
    '</w:document>',
  );
  r.nextTag();
  r.nextTag();
  return r;
}

/// Reads the container at the start of [inner] with no typed children.
PropertyContainer _read(
  String inner, {
  Set<String> typed = const <String>{},
  void Function(String localName, XmlPullReader r)? onTyped,
}) => PropertyContainer.read(
  _readerOn(inner),
  typed: typed,
  onTyped: onTyped ?? (String name, XmlPullReader r) => r.skip(),
);

/// [c] written as [name] in [order] with [typed], under [_above].
String _write(
  PropertyContainer c,
  String name,
  List<String> order, [
  Map<String, void Function(XmlWriter)> typed =
      const <String, void Function(XmlWriter)>{},
]) {
  final StringBuffer b = StringBuffer();
  c.writeTo(XmlWriter(b), name, order, typed, declaredAbove: _above);
  return b.toString();
}

void main() {
  test('typed pStyle is written first among kept children', () {
    final PropertyContainer c = _read('<w:pPr><w:jc/><w:spacing/></w:pPr>');
    expect(
      _write(c, 'w:pPr', pPrOrder, <String, void Function(XmlWriter)>{
        'pStyle': (XmlWriter w) => writeValElement(w, 'w:pStyle', 'Heading1'),
      }),
      '<w:pPr><w:pStyle w:val="Heading1"/><w:spacing/><w:jc/></w:pPr>',
    );
  });

  test('a kept w14 child stays after its predecessor', () {
    // w14:shadow shares its local name with w:shadow, which would sit
    // between b and sz; matched by namespace it is not in the schema.
    final PropertyContainer c = _read(
      '<w:rPr><w:sz w:val="20"/><w14:shadow/><w:b/></w:rPr>',
    );
    expect(
      _write(c, 'w:rPr', rPrOrder),
      '<w:rPr><w:b/><w:sz w:val="20"/><w14:shadow/></w:rPr>',
    );
  });

  test('kept schema children in the wrong input order are written in '
      'schema order', () {
    final PropertyContainer c = _read('<w:rPr><w:sz/><w:b/></w:rPr>');
    expect(_write(c, 'w:rPr', rPrOrder), '<w:rPr><w:b/><w:sz/></w:rPr>');
  });

  test('attributes of the container are kept', () {
    final PropertyContainer c = _read(
      '<w:pPr w:rsidR="00A1" w14:paraId="1F" plain="x"><w:jc/></w:pPr>',
    );
    expect(c.attributes.map((a) => a.qualifiedName), <String>[
      'w:rsidR',
      'w14:paraId',
      'plain',
    ]);
    expect(
      _write(c, 'w:pPr', pPrOrder),
      '<w:pPr w:rsidR="00A1" w14:paraId="1F" plain="x"><w:jc/></w:pPr>',
    );
  });

  test('replacing a kept rStyle drops the old one', () {
    final PropertyContainer c = _read(
      '<w:rPr><w:b/><w:rStyle w:val="Old"/></w:rPr>',
    );
    expect(
      _write(c, 'w:rPr', rPrOrder, <String, void Function(XmlWriter)>{
        'rStyle': (XmlWriter w) => writeValElement(w, 'w:rStyle', 'New'),
      }),
      '<w:rPr><w:rStyle w:val="New"/><w:b/></w:rPr>',
    );
  });

  test('a kept child is matched by namespace, not by prefix', () {
    final PropertyContainer c = _read(
      '<w:rPr><x:sz xmlns:x="${Ns.w}"/><w:b/></w:rPr>',
    );
    expect(
      _write(c, 'w:rPr', rPrOrder),
      '<w:rPr><w:b/><x:sz xmlns:x="${Ns.w}"/></w:rPr>',
    );
  });

  test('typed children go to onTyped and are not kept', () {
    final List<String> seen = <String>[];
    String? style;
    final PropertyContainer c = _read(
      '<w:pPr><w:jc/><w:pStyle w:val="Title"/><w14:x/></w:pPr>',
      typed: const <String>{'pStyle'},
      onTyped: (String name, XmlPullReader r) {
        seen.add(name);
        style = r.getAttribute('val', namespaceUri: Ns.w);
        r.skip();
      },
    );
    expect(seen, <String>['pStyle']);
    expect(style, 'Title');
    expect(c.kept.map((k) => k.localName), <String>['jc', 'x']);
    // w14:x followed the typed pStyle in the input, so it follows it here.
    expect(
      _write(c, 'w:pPr', pPrOrder, <String, void Function(XmlWriter)>{
        'pStyle': (XmlWriter w) => writeValElement(w, 'w:pStyle', 'Title'),
      }),
      '<w:pPr><w:pStyle w:val="Title"/><w14:x/><w:jc/></w:pPr>',
    );
  });

  test('a kept child whose typed predecessor is gone follows the one '
      'before it', () {
    final PropertyContainer c = _read(
      '<w:pPr><w:jc/><w:pStyle w:val="Title"/><w14:x/></w:pPr>',
      typed: const <String>{'pStyle'},
    );
    expect(_write(c, 'w:pPr', pPrOrder), '<w:pPr><w:jc/><w14:x/></w:pPr>');
  });

  test('a kept child with no predecessor is written first', () {
    final PropertyContainer c = _read(
      '<w:rPr><w14:ligatures/><w14:glow/><w:b/></w:rPr>',
    );
    expect(
      _write(c, 'w:rPr', rPrOrder, <String, void Function(XmlWriter)>{
        'rStyle': (XmlWriter w) => writeValElement(w, 'w:rStyle', 'S'),
      }),
      '<w:rPr><w14:ligatures/><w14:glow/><w:rStyle w:val="S"/><w:b/></w:rPr>',
    );
  });

  test('a kept child that followed a replaced one follows its '
      'replacement', () {
    final PropertyContainer c = _read(
      '<w:rPr><w:b/><w:rStyle w:val="Old"/><w14:glow/></w:rPr>',
    );
    expect(
      _write(c, 'w:rPr', rPrOrder, <String, void Function(XmlWriter)>{
        'rStyle': (XmlWriter w) => writeValElement(w, 'w:rStyle', 'New'),
      }),
      '<w:rPr><w:rStyle w:val="New"/><w14:glow/><w:b/></w:rPr>',
    );
  });

  test('read leaves the reader on the end of the container', () {
    final XmlPullReader r = _readerOn('<w:rPr><w:b/></w:rPr><w:after/>');
    PropertyContainer.read(
      r,
      typed: const <String>{},
      onTyped: (String name, XmlPullReader r) => r.skip(),
    );
    expect(r.eventType, XmlEventType.endElement);
    expect(r.localName, 'rPr');
    r.nextTag();
    expect(r.localName, 'after');
  });

  test('an empty container element reads and writes', () {
    final PropertyContainer c = _read('<w:rPr/>');
    expect(c.kept, isEmpty);
    expect(c.isEmpty, isTrue);
    expect(_write(c, 'w:rPr', rPrOrder), '<w:rPr/>');
  });

  test('a new container writes only its typed children', () {
    const PropertyContainer c = PropertyContainer.empty();
    expect(
      _write(c, 'w:pPr', pPrOrder, <String, void Function(XmlWriter)>{
        'pStyle': (XmlWriter w) => writeValElement(w, 'w:pStyle', 'A & B'),
      }),
      '<w:pPr><w:pStyle w:val="A &amp; B"/></w:pPr>',
    );
  });

  test('a typed child outside the order is a programmer error', () {
    const PropertyContainer c = PropertyContainer.empty();
    expect(
      () => _write(c, 'w:rPr', rPrOrder, <String, void Function(XmlWriter)>{
        'pStyle': (XmlWriter w) {},
      }),
      throwsArgumentError,
    );
  });

  test('a kept child declares a namespace the new parent lacks', () {
    final PropertyContainer c = _read('<w:rPr><w14:glow/></w:rPr>');
    final StringBuffer b = StringBuffer();
    c.writeTo(
      XmlWriter(b),
      'w:rPr',
      rPrOrder,
      const <String, void Function(XmlWriter)>{},
      declaredAbove: const <String, String>{'w': Ns.w},
    );
    expect(b.toString(), '<w:rPr><w14:glow xmlns:w14="${Ns.w14}"/></w:rPr>');
  });
}
