// Tests the property containers: every child is kept as read, a typed one
// also gives a view, and the writer merges the children with the values set
// in the schema's order. They build the XML in memory, so they run on the
// web as well.
import 'package:jet_office/src/docx/model/edit_sink.dart';
import 'package:jet_office/src/docx/model/property_set.dart';
import 'package:jet_office/src/docx/properties.dart';
import 'package:jet_office/src/docx/property_codec.dart';
import 'package:jet_office/src/docx/schema_order.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';

/// The namespaces the test documents declare on their root.
const Map<String, String> _above = <String, String>{'w': Ns.w, 'w14': Ns.w14};

/// An on/off property for the tests, such as `w:b`.
final class _OnOffCodec extends PropertyCodec<bool> {
  const _OnOffCodec(super.localName);

  @override
  Set<String> get attributes => const <String>{'val'};

  @override
  bool? parse(PropertyElement e) => parseOnOff(e.w('val'));

  @override
  void write(XmlWriter w, String prefix, bool value, PropertyElement? asRead) {
    w.start('$prefix:$localName');
    if (!value) w.attribute('$prefix:val', '0');
    w.end();
  }
}

/// `w:rPr` with the style and bold typed.
const ContainerSchema _rPr = ContainerSchema(
  rPrOrder,
  codecs: <String, PropertyCodec<Object>>{
    'rStyle': StyleIdCodec('rStyle'),
    'b': _OnOffCodec('b'),
  },
);

/// `w:pPr` with the style typed.
const ContainerSchema _pPr = ContainerSchema(
  pPrOrder,
  codecs: <String, PropertyCodec<Object>>{'pStyle': StyleIdCodec('pStyle')},
);

/// `w:style` with its `w:pPr` and `w:rPr` read as containers of their own.
const ContainerSchema _style = ContainerSchema(
  styleOrder,
  codecs: <String, PropertyCodec<Object>>{'basedOn': StyleIdCodec('basedOn')},
  nested: <String, ContainerSchema>{'pPr': _pPr, 'rPr': _rPr},
);

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

/// Reads the container at the start of [inner] by [schema].
PropertyContainer _read(String inner, [ContainerSchema schema = _rPr]) =>
    PropertyContainer.read(_readerOn(inner), schema);

/// [c] written as [name] by [schema] with [overrides], under [_above].
String _write(
  PropertyContainer c,
  String name,
  ContainerSchema schema, [
  Map<String, Object?> overrides = const <String, Object?>{},
  Map<String, NestedProperties> nested = const <String, NestedProperties>{},
]) {
  final StringBuffer b = StringBuffer();
  c.writeTo(
    XmlWriter(b),
    name,
    schema,
    overrides: overrides,
    nested: nested,
    declaredAbove: _above,
  );
  return b.toString();
}

/// The differences between [expected] and [actual], each a container
/// written under a root that declares [_above].
List<String> _compare(String expected, String actual) {
  String rooted(String inner) =>
      '<w:document xmlns:w="${Ns.w}" xmlns:w14="${Ns.w14}">$inner'
      '</w:document>';
  return compareXml('pPr', rooted(expected), rooted(actual));
}

/// A property set over a container, reporting to no document.
final class _Set extends PropertySet {
  _Set(PropertyContainer source, ContainerSchema schema)
    : super(source, schema, () => DocxEditSink.none);
}

void main() {
  test('typed pStyle is written first among kept children', () {
    final PropertyContainer c = _read(
      '<w:pPr><w:jc/><w:spacing/></w:pPr>',
      _pPr,
    );
    expect(
      _write(c, 'w:pPr', _pPr, <String, Object?>{'pStyle': 'Heading1'}),
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
      _write(c, 'w:rPr', _rPr),
      '<w:rPr><w:b/><w:sz w:val="20"/><w14:shadow/></w:rPr>',
    );
  });

  test('kept schema children in the wrong input order are written in '
      'schema order', () {
    final PropertyContainer c = _read('<w:rPr><w:sz/><w:b/></w:rPr>');
    expect(_write(c, 'w:rPr', _rPr), '<w:rPr><w:b/><w:sz/></w:rPr>');
  });

  test('attributes of the container are kept', () {
    final PropertyContainer c = _read(
      '<w:pPr w:rsidR="00A1" w14:paraId="1F" plain="x"><w:jc/></w:pPr>',
      _pPr,
    );
    expect(c.attributes.map((a) => a.qualifiedName), <String>[
      'w:rsidR',
      'w14:paraId',
      'plain',
    ]);
    expect(
      _write(c, 'w:pPr', _pPr),
      '<w:pPr w:rsidR="00A1" w14:paraId="1F" plain="x"><w:jc/></w:pPr>',
    );
  });

  test('replacing a kept rStyle drops the old one', () {
    final PropertyContainer c = _read(
      '<w:rPr><w:b/><w:rStyle w:val="Old"/></w:rPr>',
    );
    expect(
      _write(c, 'w:rPr', _rPr, <String, Object?>{'rStyle': 'New'}),
      '<w:rPr><w:rStyle w:val="New"/><w:b/></w:rPr>',
    );
  });

  test('a kept child is matched by namespace, not by prefix', () {
    final PropertyContainer c = _read(
      '<w:rPr><x:sz xmlns:x="${Ns.w}"/><w:b/></w:rPr>',
    );
    expect(
      _write(c, 'w:rPr', _rPr),
      '<w:rPr><w:b/><x:sz xmlns:x="${Ns.w}"/></w:rPr>',
    );
  });

  test('typed children go to onTyped and are not kept', () {
    // On the new API a typed child is a view of the kept child: it reads
    // as its value and is not among the untyped children.
    final PropertyContainer c = _read(
      '<w:pPr><w:jc/><w:pStyle w:val="Title"/><w14:x/></w:pPr>',
      _pPr,
    );
    expect(c.viewOf('pStyle'), 'Title');
    expect(c.kept.map((k) => k.localName), <String>['jc', 'x']);
    // w14:x followed the typed pStyle in the input, so it follows it here.
    expect(
      _write(c, 'w:pPr', _pPr, <String, Object?>{'pStyle': 'Title'}),
      '<w:pPr><w:pStyle w:val="Title"/><w14:x/><w:jc/></w:pPr>',
    );
  });

  test('a kept child whose typed predecessor is gone follows the one '
      'before it', () {
    final PropertyContainer c = _read(
      '<w:pPr><w:jc/><w:pStyle w:val="Title"/><w14:x/></w:pPr>',
      _pPr,
    );
    expect(
      _write(c, 'w:pPr', _pPr, <String, Object?>{'pStyle': null}),
      '<w:pPr><w:jc/><w14:x/></w:pPr>',
    );
  });

  test('a kept child with no predecessor is written first', () {
    final PropertyContainer c = _read(
      '<w:rPr><w14:ligatures/><w14:glow/><w:b/></w:rPr>',
    );
    expect(
      _write(c, 'w:rPr', _rPr, <String, Object?>{'rStyle': 'S'}),
      '<w:rPr><w14:ligatures/><w14:glow/><w:rStyle w:val="S"/><w:b/></w:rPr>',
    );
  });

  test('a kept child that followed a replaced one follows its '
      'replacement', () {
    final PropertyContainer c = _read(
      '<w:rPr><w:b/><w:rStyle w:val="Old"/><w14:glow/></w:rPr>',
    );
    expect(
      _write(c, 'w:rPr', _rPr, <String, Object?>{'rStyle': 'New'}),
      '<w:rPr><w:rStyle w:val="New"/><w14:glow/><w:b/></w:rPr>',
    );
  });

  test('read leaves the reader on the end of the container', () {
    final XmlPullReader r = _readerOn('<w:rPr><w:b/></w:rPr><w:after/>');
    PropertyContainer.read(r, _rPr);
    expect(r.eventType, XmlEventType.endElement);
    expect(r.localName, 'rPr');
    r.nextTag();
    expect(r.localName, 'after');
  });

  test('an empty container element reads and writes', () {
    final PropertyContainer c = _read('<w:rPr/>');
    expect(c.kept, isEmpty);
    expect(c.isEmpty, isTrue);
    expect(_write(c, 'w:rPr', _rPr), '<w:rPr/>');
  });

  test('a new container writes only its typed children', () {
    const PropertyContainer c = PropertyContainer.empty();
    expect(
      _write(c, 'w:pPr', _pPr, <String, Object?>{'pStyle': 'A & B'}),
      '<w:pPr><w:pStyle w:val="A &amp; B"/></w:pPr>',
    );
  });

  test('a typed child outside the order is a programmer error', () {
    const PropertyContainer c = PropertyContainer.empty();
    expect(
      () => _write(c, 'w:rPr', _rPr, <String, Object?>{'pStyle': 'S'}),
      throwsArgumentError,
    );
    // A name of the order without a codec cannot be set either.
    expect(
      () => _write(c, 'w:rPr', _rPr, <String, Object?>{'sz': 24}),
      throwsArgumentError,
    );
    // Nor can a value of the wrong type.
    expect(
      () => _write(c, 'w:rPr', _rPr, <String, Object?>{'b': 'yes'}),
      throwsArgumentError,
    );
  });

  test('a kept child declares a namespace the new parent lacks', () {
    final PropertyContainer c = _read('<w:rPr><w14:glow/></w:rPr>');
    final StringBuffer b = StringBuffer();
    c.writeTo(
      XmlWriter(b),
      'w:rPr',
      _rPr,
      declaredAbove: const <String, String>{'w': Ns.w},
    );
    expect(b.toString(), '<w:rPr><w14:glow xmlns:w14="${Ns.w14}"/></w:rPr>');
  });

  test('an unset typed child is written as read', () {
    final PropertyContainer c = _read(
      '<w:rPr><w:b w:val="on"/><w:rStyle w:val="S"/></w:rPr>',
    );
    expect(c.viewOf('b'), isTrue);
    expect(c.viewOf('rStyle'), 'S');
    expect(
      _write(c, 'w:rPr', _rPr),
      '<w:rPr><w:rStyle w:val="S"/><w:b w:val="on"/></w:rPr>',
    );
  });

  test('a child occurring twice has no view and both are written', () {
    final PropertyContainer c = _read(
      '<w:rPr><w:b/><w:i/><w:b w:val="0"/></w:rPr>',
    );
    expect(c.viewOf('b'), isNull);
    expect(c.kept.map((OpaqueXml k) => k.localName), <String>['b', 'i', 'b']);
    expect(
      _write(c, 'w:rPr', _rPr),
      '<w:rPr><w:b/><w:b w:val="0"/><w:i/></w:rPr>',
    );
  });

  test('a typed child with an unknown w attribute has no view', () {
    final PropertyContainer c = _read('<w:rPr><w:b w:x="1"/></w:rPr>');
    expect(c.viewOf('b'), isNull);
    expect(_write(c, 'w:rPr', _rPr), '<w:rPr><w:b w:x="1"/></w:rPr>');
    // A value the codec cannot parse gives no view either.
    expect(_read('<w:rPr><w:b w:val="maybe"/></w:rPr>').viewOf('b'), isNull);
  });

  test('a typed child with a w14 attribute has its view', () {
    final PropertyContainer c = _read(
      '<w:rPr><w:b w:val="0" w14:x="1" plain="p"/></w:rPr>',
    );
    expect(c.viewOf('b'), isFalse);
    expect(c.kept, isEmpty);
    expect(
      _write(c, 'w:rPr', _rPr),
      '<w:rPr><w:b w:val="0" w14:x="1" plain="p"/></w:rPr>',
    );
  });

  test('a child of another namespace is never typed', () {
    final PropertyContainer c = _read('<w:rPr><w14:b/></w:rPr>');
    expect(c.viewOf('b'), isNull);
    expect(c.holds('b'), isFalse);
  });

  test('setting replaces every child of that name at its slot', () {
    final PropertyContainer c = _read(
      '<w:rPr><w:sz/><w:b w:val="on"/><w14:glow/><w:i/><w:b w:x="1"/>'
      '</w:rPr>',
    );
    expect(c.holds('b'), isTrue);
    expect(
      _write(c, 'w:rPr', _rPr, <String, Object?>{'b': false}),
      '<w:rPr><w:b w:val="0"/><w14:glow/><w:i/><w:sz/></w:rPr>',
    );
  });

  test('setting null removes them', () {
    final PropertyContainer c = _read(
      '<w:rPr><w:b/><w:b w:val="0"/><w:i/></w:rPr>',
    );
    expect(
      _write(c, 'w:rPr', _rPr, <String, Object?>{'b': null}),
      '<w:rPr><w:i/></w:rPr>',
    );
  });

  test('a nested container reads and writes as its own', () {
    const String xml =
        '<w:style w:type="paragraph" w:styleId="H"><w:name w:val="h"/>'
        '<w:rPr><w:b/><w:rStyle w:val="S"/></w:rPr>'
        '<w:basedOn w:val="Normal"/><w:pPr w:rsidR="1"><w:jc/>'
        '<w:pStyle w:val="P"/></w:pPr></w:style>';
    final PropertyContainer c = _read(xml, _style);
    expect(c.viewOf('basedOn'), 'Normal');
    final PropertyContainer pPr = c.nestedOf('pPr')!;
    final PropertyContainer rPr = c.nestedOf('rPr')!;
    expect(pPr.viewOf('pStyle'), 'P');
    expect(pPr.attributes.single.qualifiedName, 'w:rsidR');
    expect(rPr.viewOf('rStyle'), 'S');
    expect(c.nestedOf('name'), isNull);
    // Nested containers are not among the kept children.
    expect(c.kept.map((OpaqueXml k) => k.localName), <String>['name']);
    // Written in styleOrder, each nested container in its own order.
    expect(
      _write(c, 'w:style', _style),
      '<w:style w:type="paragraph" w:styleId="H"><w:name w:val="h"/>'
      '<w:basedOn w:val="Normal"/><w:pPr w:rsidR="1">'
      '<w:pStyle w:val="P"/><w:jc/></w:pPr>'
      '<w:rPr><w:rStyle w:val="S"/><w:b/></w:rPr></w:style>',
    );
    // A nested replacement is written at the slot with its own edits.
    expect(
      _write(
        c,
        'w:style',
        _style,
        const <String, Object?>{},
        <String, NestedProperties>{
          'rPr': _Set(rPr, _rPr)..setValue('b', null),
          'pPr': _Set(const PropertyContainer.empty(), _pPr),
        },
      ),
      '<w:style w:type="paragraph" w:styleId="H"><w:name w:val="h"/>'
      '<w:basedOn w:val="Normal"/>'
      '<w:rPr><w:rStyle w:val="S"/></w:rPr></w:style>',
    );
  });

  test('a second nested child of one name is kept as read', () {
    final PropertyContainer c = _read(
      '<w:style><w:rPr><w:b/></w:rPr><w:rPr><w:i/></w:rPr></w:style>',
      _style,
    );
    expect(c.nestedOf('rPr')!.viewOf('b'), isTrue);
    expect(c.kept.single.xml, '<w:rPr><w:i/></w:rPr>');
    expect(
      _write(c, 'w:style', _style),
      '<w:style><w:rPr><w:b/></w:rPr><w:rPr><w:i/></w:rPr></w:style>',
    );
  });

  test('whitespace and a comment between children round-trip equal', () {
    for (final String xml in <String>[
      '<w:pPr> <w:spacing/> <!-- c --> <w:jc/> </w:pPr>',
      '<w:pPr> <!-- c --> </w:pPr>',
      '<w:pPr>\n  </w:pPr>',
    ]) {
      final PropertyContainer c = _read(xml, _pPr);
      expect(_compare(xml, _write(c, 'w:pPr', _pPr)), isEmpty, reason: xml);
    }
    // Once a child is written, the whitespace is indentation again.
    final PropertyContainer c = _read('<w:pPr> <!-- c --> </w:pPr>', _pPr);
    expect(
      _write(c, 'w:pPr', _pPr, <String, Object?>{'pStyle': 'T'}),
      '<w:pPr><w:pStyle w:val="T"/></w:pPr>',
    );
  });

  test('a pPr that redeclares the w prefix writes typed children with a '
      'bound prefix', () {
    // The container is in WordprocessingML through x, and rebinds w to
    // another namespace: a typed child written with w would leave it.
    final PropertyContainer c = _read(
      '<x:pPr xmlns:x="${Ns.w}" xmlns:w="urn:other"><x:jc/><w:o/></x:pPr>',
      _pPr,
    );
    expect(
      _write(c, 'w:pPr', _pPr, <String, Object?>{'pStyle': 'T'}),
      '<x:pPr xmlns:x="${Ns.w}" xmlns:w="urn:other">'
      '<x:pStyle x:val="T"/><x:jc/><w:o/></x:pPr>',
    );
    final PropertyContainer e = _read(
      '<x:pPr xmlns:x="${Ns.w}" xmlns:w="urn:other"/>',
      _pPr,
    );
    expect(
      _write(e, 'w:pPr', _pPr, <String, Object?>{'pStyle': 'T'}),
      '<x:pPr xmlns:x="${Ns.w}" xmlns:w="urn:other">'
      '<x:pStyle x:val="T"/></x:pPr>',
    );
    // With no other binding to WordprocessingML in scope, one is declared.
    final PropertyContainer f = PropertyContainer.read(
      _readerOn('<w:pPr xmlns:w="urn:other"/>'),
      _pPr,
    );
    expect(
      _write(f, 'w:pPr', _pPr, <String, Object?>{'pStyle': 'T'}),
      '<w1:pPr xmlns:w="urn:other" xmlns:w1="${Ns.w}">'
      '<w1:pStyle w1:val="T"/></w1:pPr>',
    );
  });

  test('writesNothing is false for a read empty container', () {
    final _Set read = _Set(_read('<w:rPr/>'), _rPr);
    expect(read.writesNothing, isFalse);
    final _Set fresh = _Set(const PropertyContainer.empty(), _rPr);
    expect(fresh.writesNothing, isTrue);
    fresh.setValue('b', null);
    expect(fresh.writesNothing, isTrue);
    fresh.setValue('b', true);
    expect(fresh.writesNothing, isFalse);
  });

  group('property set', () {
    test('a value reads the override, else the view', () {
      final _Set s = _Set(
        _read('<w:rPr><w:rStyle w:val="S"/><w:b w:val="on"/></w:rPr>'),
        _rPr,
      );
      expect(s.valueOf('b'), isTrue);
      expect(s.isSet('b'), isFalse);
      s.setValue('b', true);
      // Equal to the view: nothing set, the child stays as read.
      expect(s.isSet('b'), isFalse);
      s.setValue('b', false);
      expect(s.isSet('b'), isTrue);
      expect(s.valueOf('b'), isFalse);
      expect(s.stateOf('b'), (isSet: true, value: false));
      s.setValue('rStyle', null);
      expect(s.valueOf('rStyle'), isNull);
      final StringBuffer b = StringBuffer();
      s.writeTo(XmlWriter(b), 'w:rPr', declaredAbove: _above);
      expect(b.toString(), '<w:rPr><w:b w:val="0"/></w:rPr>');
      s.restore('b', (isSet: false, value: null));
      s.restore('rStyle', (isSet: false, value: null));
      expect(s.valueOf('b'), isTrue);
      expect(s.valueOf('rStyle'), 'S');
    });

    test('setting null where an untyped child is removes it', () {
      final _Set s = _Set(_read('<w:rPr><w:b/><w:b/></w:rPr>'), _rPr);
      expect(s.valueOf('b'), isNull);
      s.setValue('b', null);
      expect(s.isSet('b'), isTrue);
      final StringBuffer b = StringBuffer();
      s.writeTo(XmlWriter(b), 'w:rPr', declaredAbove: _above);
      expect(b.toString(), '<w:rPr/>');
      // Where no child is, null is the current value: nothing to set.
      final _Set t = _Set(_read('<w:rPr/>'), _rPr);
      t.setValue('b', null);
      expect(t.isSet('b'), isFalse);
    });

    test('a name without a codec or a value of the wrong type throws', () {
      final _Set s = _Set(const PropertyContainer.empty(), _rPr);
      expect(() => s.setValue('sz', 24), throwsArgumentError);
      expect(() => s.setValue('b', 'yes'), throwsArgumentError);
      expect(() => s.valueOf('sz'), throwsArgumentError);
      expect(s.isSet('b'), isFalse);
    });
  });
}
