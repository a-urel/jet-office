import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

XmlPullReader _at(String xml, String localName) {
  final XmlPullReader r = XmlPullReader(xml);
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement && r.localName == localName) {
      return r;
    }
  }
  throw StateError('no <$localName>');
}

String _write(OpaqueXml o, [Map<String, String> above = const {}]) {
  final StringBuffer sb = StringBuffer();
  o.writeTo(XmlWriter(sb), declaredAbove: above);
  return sb.toString();
}

void main() {
  _siblingScopes();
  group('OpaqueXml', () {
    test('capture keeps the exact source', () {
      const String slice =
          '<e  a = "1" >t&amp;x<!-- c --><![CDATA[<>]]>'
          '<f/> </e>';
      final OpaqueXml o = OpaqueXml.capture(_at('<r>$slice</r>', 'e'));
      expect(o.xml, slice);
      expect(o.localName, 'e');
      expect(o.namespaceUri, '');
    });

    test('capture shows onEvent every event of the element in order', () {
      String events(String xml) {
        final List<String> seen = <String>[];
        OpaqueXml.capture(
          _at(xml, 'e'),
          onEvent: (XmlPullReader r) => seen.add(switch (r.eventType) {
            XmlEventType.startElement => '<${r.localName}',
            XmlEventType.endElement => '>',
            XmlEventType.characters || XmlEventType.cdata => '"${r.text}"',
            _ => r.eventType.name,
          }),
        );
        return seen.join(' ');
      }

      expect(
        events('<r><e>a&amp;<f/><!--c--><![CDATA[b]]></e><s/></r>'),
        '<e "a&" <f > comment "b" >',
      );
      expect(events('<r><e/><s/></r>'), '<e >');
    });

    test('capture leaves the reader after the element', () {
      final XmlPullReader r = _at('<r><e><g/></e><s/></r>', 'e');
      OpaqueXml.capture(r);
      expect(r.eventType, XmlEventType.endElement);
      expect(r.next(), isTrue);
      expect(r.localName, 's');
    });

    test('capture of an empty element', () {
      final XmlPullReader r = _at('<r><e a="1"/><s/></r>', 'e');
      final OpaqueXml o = OpaqueXml.capture(r);
      expect(o.xml, '<e a="1"/>');
      r.next();
      expect(r.localName, 's');
    });

    test('namespaceUri is the element namespace', () {
      final OpaqueXml o = OpaqueXml.capture(
        _at('<r xmlns:x="ux"><x:e/></r>', 'e'),
      );
      expect(o.namespaceUri, 'ux');
      expect(o.inheritedNamespaces, <String, String>{'x': 'ux'});
    });

    test('inherited namespace is re-declared', () {
      const String doc =
          '<r xmlns="m" xmlns:x14="u14"><e><x14:id v="1"/></e></r>';
      final OpaqueXml o = OpaqueXml.capture(_at(doc, 'e'));
      expect(o.inheritedNamespaces, <String, String>{'': 'm', 'x14': 'u14'});
      expect(_write(o, {'': 'm'}), '<e xmlns:x14="u14"><x14:id v="1"/></e>');
      expect(_write(o, {'': 'm', 'x14': 'u14'}), o.xml);
      expect(_write(o), '<e xmlns="m" xmlns:x14="u14"><x14:id v="1"/></e>');
    });

    test('a different binding above is overridden', () {
      final OpaqueXml o = OpaqueXml.capture(
        _at('<r xmlns:x="1"><e><x:a/></e></r>', 'e'),
      );
      expect(_write(o, {'x': '2'}), '<e xmlns:x="1"><x:a/></e>');
    });

    test('a prefix declared inside the slice is not inherited', () {
      final OpaqueXml o = OpaqueXml.capture(
        _at('<r xmlns:x="1"><e xmlns:x="2"><x:a/></e></r>', 'e'),
      );
      expect(o.inheritedNamespaces, <String, String>{'': ''});
      final OpaqueXml p = OpaqueXml.capture(
        _at('<r xmlns:x="1"><e><i xmlns:x="2"><x:a/></i><x:b/></e></r>', 'e'),
      );
      expect(p.inheritedNamespaces, <String, String>{'': '', 'x': '1'});
    });

    test('an attribute prefix is inherited, an xml: attribute is not', () {
      final OpaqueXml o = OpaqueXml.capture(
        _at('<r xmlns:m="um"><e m:a="1" xml:space="preserve"/></r>', 'e'),
      );
      expect(o.inheritedNamespaces, <String, String>{'': '', 'm': 'um'});
    });

    test('a slice without namespaces writes unchanged', () {
      final OpaqueXml o = OpaqueXml.capture(_at('<r><e a="1"/></r>', 'e'));
      expect(o.inheritedNamespaces, <String, String>{'': ''});
      expect(_write(o), '<e a="1"/>');
      expect(_write(o, {'': ''}), '<e a="1"/>');
    });

    test('an unqualified slice undeclares a default namespace above', () {
      final OpaqueXml o = OpaqueXml.capture(
        _at('<x:r xmlns:x="m"><e><f/></e></x:r>', 'e'),
      );
      expect(o.inheritedNamespaces, <String, String>{'': ''});
      expect(_write(o, {'': 'm'}), '<e xmlns=""><f/></e>');
      final OpaqueXml undeclared = OpaqueXml.capture(
        _at('<r xmlns="m"><e xmlns=""><f/></e></r>', 'e'),
      );
      expect(undeclared.inheritedNamespaces, isEmpty);
      expect(_write(undeclared, {'': 'm'}), undeclared.xml);
    });

    test('an empty element gets the declarations after its name', () {
      final OpaqueXml o = OpaqueXml.capture(
        _at('<r xmlns:x="u"><x:e/></r>', 'e'),
      );
      expect(_write(o), '<x:e xmlns:x="u"/>');
    });
  });

  group('keepAttributes', () {
    test('keepAttributes skips owned names and xmlns', () {
      final XmlPullReader r = _at(
        '<r xmlns:x="ux" xmlns="d" id="1" x:keep="2" other="3" '
            'xml:space="preserve"/>',
        'r',
      );
      final List<KeptAttribute> kept = keepAttributes(r, except: {'id'});
      expect(kept.map((KeptAttribute a) => a.qualifiedName), <String>[
        'x:keep',
        'other',
        'xml:space',
      ]);
      expect(kept[0].namespaceUri, 'ux');
      expect(kept[0].value, '2');
      expect(kept[1].namespaceUri, '');
      expect(kept[2].namespaceUri, 'http://www.w3.org/XML/1998/namespace');
    });

    test('a prefixed attribute is not owned by its local name', () {
      final XmlPullReader r = _at('<r xmlns:x="u" x:id="1"/>', 'r');
      expect(keepAttributes(r, except: {'id'}), hasLength(1));
    });
  });

  group('XmlRoot', () {
    test('XmlRoot round-trips declarations and mc:Ignorable', () {
      const String root =
          '<worksheet xmlns="m" xmlns:mc="umc" xmlns:x14ac="u14" '
          'mc:Ignorable="x14ac" count="2">';
      final XmlRoot x = XmlRoot.capture(
        _at('$root<a/></worksheet>', 'worksheet'),
      );
      expect(x.qualifiedName, 'worksheet');
      expect(x.namespaces, <String, String>{
        '': 'm',
        'mc': 'umc',
        'x14ac': 'u14',
      });
      expect(x.attributes.map((KeptAttribute a) => a.qualifiedName), <String>[
        'mc:Ignorable',
        'count',
      ]);
      final StringBuffer sb = StringBuffer();
      final XmlWriter w = XmlWriter(sb);
      x.writeStart(w);
      w.end();
      expect(sb.toString(), '${root.substring(0, root.length - 1)}/>');
    });

    test('capture leaves the reader on the start element', () {
      final XmlPullReader r = _at('<r xmlns="m"><a/></r>', 'r');
      XmlRoot.capture(r);
      expect(r.eventType, XmlEventType.startElement);
      expect(r.localName, 'r');
    });
  });

  group('writeKeptAttributes', () {
    String write(
      List<KeptAttribute> attributes, [
      Map<String, String> above = const {},
    ]) {
      final StringBuffer sb = StringBuffer();
      final XmlWriter w = XmlWriter(sb)..start('e');
      writeKeptAttributes(w, attributes, declaredAbove: above);
      w.end();
      return sb.toString();
    }

    test('declares a prefix the parent does not bind, once', () {
      expect(
        write(<KeptAttribute>[
          (qualifiedName: 'a', namespaceUri: '', value: '1'),
          (qualifiedName: 'x:b', namespaceUri: 'u', value: '2'),
          (qualifiedName: 'x:c', namespaceUri: 'u', value: '3'),
        ]),
        '<e a="1" xmlns:x="u" x:b="2" x:c="3"/>',
      );
    });

    test('does not redeclare a prefix bound to the same URI', () {
      expect(
        write(
          <KeptAttribute>[
            (qualifiedName: 'x:b', namespaceUri: 'u', value: '2'),
          ],
          <String, String>{'x': 'u'},
        ),
        '<e x:b="2"/>',
      );
    });

    test('redeclares a prefix bound to another URI', () {
      expect(
        write(
          <KeptAttribute>[
            (qualifiedName: 'x:b', namespaceUri: 'u', value: '2'),
          ],
          <String, String>{'x': 'other'},
        ),
        '<e xmlns:x="u" x:b="2"/>',
      );
    });

    test('never declares the xml prefix', () {
      expect(
        write(<KeptAttribute>[
          (
            qualifiedName: 'xml:space',
            namespaceUri: 'http://www.w3.org/XML/1998/namespace',
            value: 'preserve',
          ),
        ]),
        '<e xml:space="preserve"/>',
      );
    });

    test('escapes values and drops characters XML forbids', () {
      expect(
        write(<KeptAttribute>[
          (qualifiedName: 'a', namespaceUri: '', value: 'x"<\u0001'),
        ]),
        '<e a="x&quot;&lt;"/>',
      );
    });
  });
}

void _siblingScopes() {
  test('a declaration on an empty child does not leak to its sibling', () {
    final OpaqueXml o = OpaqueXml.capture(
      _at('<r xmlns:x="1"><e><i xmlns:x="2"/><x:b/></e></r>', 'e'),
    );
    expect(o.inheritedNamespaces, <String, String>{'': '', 'x': '1'});
  });
}
