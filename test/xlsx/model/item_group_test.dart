import 'package:jet_office/src/opc/ooxml.dart';
import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xlsx/model/item_group.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

const String _x14 =
    'http://schemas.microsoft.com/office/spreadsheetml/2009/9/main';

/// A reader on the first child of the root of [xml].
XmlPullReader _onChild(String xml) {
  final XmlPullReader r = XmlPullReader(xml)..next();
  while (r.next()) {
    if (r.eventType == XmlEventType.startElement) break;
  }
  return r;
}

/// Reads the group that is the first child of the root of [xml], each
/// `<item>` as its `v`; an item without one is a problem.
ItemGroup<String> _read(String xml, {List<String>? problems}) =>
    readItemGroup<String>(
      _onChild(xml),
      childName: 'item',
      read: (OpaqueXml child) {
        final XmlPullReader r = readerOf(child);
        final String? v = r.getAttribute('v');
        return (value: v, problem: v == null ? 'item: no v.' : null);
      },
      warn: (String problem) => problems?.add(problem),
    );

String _written(ItemGroup<String> group, {String? count = 'count'}) {
  final StringBuffer out = StringBuffer();
  group.writeTo(XmlWriter(out), const <String, String>{
    '': Ns.main,
  }, countAttribute: count);
  return out.toString();
}

/// A new `<item>` as the writer would render it.
GroupItem<String> _made(String value) => GroupItem<String>(
  value,
  renderElements((XmlWriter w) {
    w
      ..start('item')
      ..attribute('v', value)
      ..end();
  }).single,
);

void main() {
  group('readItemGroup', () {
    test('reads the children in order and consumes the element', () {
      final XmlPullReader r = _onChild(
        '<root xmlns="${Ns.main}">'
        '<group count="2" a="1"><item v="x"/><item v="y"></item></group>'
        '<after/></root>',
      );
      final ItemGroup<String> group = readItemGroup<String>(
        r,
        childName: 'item',
        read: (OpaqueXml child) =>
            (value: readerOf(child).getAttribute('v'), problem: null),
        warn: (String problem) => fail(problem),
      );
      expect(r.eventType, XmlEventType.endElement);
      expect(group.qualifiedName, 'group');
      expect(group.localName, 'group');
      expect(group.values, <String>['x', 'y']);
      expect(group.edited, isFalse);
      expect(group.items.every((GroupItem<String> i) => i.counted), isTrue);
      r.next();
      expect(r.localName, 'after');
    });

    test('an empty element is a group without items', () {
      final XmlPullReader r = _onChild(
        '<root xmlns="${Ns.main}"><group/><after/></root>',
      );
      final ItemGroup<String> group = readItemGroup<String>(
        r,
        childName: 'item',
        read: (OpaqueXml child) => fail('no child'),
        warn: (String problem) => fail(problem),
      );
      expect(group.items, isEmpty);
      r.next();
      expect(r.localName, 'after');
    });

    test('an entry with a problem is kept, counted and reported', () {
      final List<String> problems = <String>[];
      final ItemGroup<String> group = _read(
        '<root xmlns="${Ns.main}"><group count="2">'
        '<item v="x"/><item w="1"/></group></root>',
        problems: problems,
      );
      expect(problems, <String>['item: no v.']);
      expect(group.values, <String>['x']);
      expect(group.items.length, 2);
      expect(group.items.last.value, isNull);
      expect(group.items.last.counted, isTrue);
      expect(group.items.last.source.xml, '<item w="1"/>');
    });

    test('another child is kept uncounted and not read', () {
      final List<String> problems = <String>[];
      final ItemGroup<String> group = _read(
        '<root xmlns="${Ns.main}" xmlns:o="urn:o"><group>'
        '<o:item v="foreign"/><other v="x"/><item v="y"/></group></root>',
        problems: problems,
      );
      expect(problems, isEmpty);
      expect(group.values, <String>['y']);
      expect(group.items.map((GroupItem<String> i) => i.counted), <bool>[
        false,
        false,
        true,
      ]);
    });
  });

  group('ItemGroup.writeTo', () {
    const String wrong =
        '<group count="9" a="1"><item v="x"/><o:other xmlns:o="urn:o"/></group>';

    test('an untouched group is written as it was', () {
      final ItemGroup<String> group = _read(
        '<root xmlns="${Ns.main}">$wrong</root>',
      );
      expect(_written(group), wrong);
    });

    test('an edited group recomputes count', () {
      final ItemGroup<String> group = _read(
        '<root xmlns="${Ns.main}">$wrong</root>',
      );
      final ItemGroup<String> next = group.withItems(<GroupItem<String>>[
        ...group.items,
        _made('y'),
      ]);
      expect(next.edited, isTrue);
      expect(next.values, <String>['x', 'y']);
      expect(
        _written(next),
        '<group count="2" a="1"><item v="x"/><o:other xmlns:o="urn:o"/>'
        '<item v="y"/></group>',
      );
      // The group it came from did not change.
      expect(_written(group), wrong);
    });

    test('count is added to a group that has none', () {
      final ItemGroup<String> group = _read(
        '<root xmlns="${Ns.main}"><group><item v="x"/></group></root>',
      );
      expect(
        _written(group.withItems(group.items)),
        '<group count="1"><item v="x"/></group>',
      );
    });

    test('without a countAttribute nothing is recomputed', () {
      final ItemGroup<String> group = _read(
        '<root xmlns="${Ns.main}">$wrong</root>',
      );
      expect(
        _written(group.withItems(group.items.take(1).toList()), count: null),
        '<group count="9" a="1"><item v="x"/></group>',
      );
    });

    test('a declaration with a forbidden character is written scrubbed', () {
      final ItemGroup<String> group = _read(
        '<root xmlns="${Ns.main}"><group xmlns:o="urn:&#1;o" o:a="1">'
        '<item v="x" o:b="2"/><o:c/></group></root>',
      );
      // Kept as read, so a child's inherited binding still matches it.
      expect(group.namespaces['o'], 'urn:\u0001o');
      expect(
        _written(group),
        '<group xmlns:o="urn:o" o:a="1"><item v="x" o:b="2"/><o:c/></group>',
      );
    });

    test('a group keeps its declarations for its children', () {
      final ItemGroup<String> group = _read(
        '<root xmlns="${Ns.main}"><group xmlns:o="urn:o" o:a="1">'
        '<item v="x" o:b="2"/></group></root>',
      );
      expect(
        _written(group),
        '<group xmlns:o="urn:o" o:a="1"><item v="x" o:b="2"/></group>',
      );
    });
  });

  group('renderElements', () {
    test('captures each element, in the main namespace', () {
      final List<OpaqueXml> out = renderElements((XmlWriter w) {
        w
          ..start('a')
          ..attribute('r:id', 'rId1')
          ..end()
          ..start('b')
          ..start('c')
          ..end()
          ..end();
      });
      expect(out.map((OpaqueXml e) => e.localName), <String>['a', 'b']);
      expect(out.first.namespaceUri, Ns.main);
      expect(out.first.xml, '<a r:id="rId1"/>');
      expect(out.last.xml, '<b><c/></b>');
      expect(out.first.inheritedNamespaces, <String, String>{
        '': Ns.main,
        'r': Ns.rel,
      });
    });

    test('a writer that writes nothing gives nothing', () {
      expect(renderElements((XmlWriter w) {}), isEmpty);
    });
  });

  group('readerOf', () {
    test('is on the element and reads to its end', () {
      final OpaqueXml e = renderElements((XmlWriter w) {
        w
          ..start('a')
          ..attribute('v', '1')
          ..start('b')
          ..end()
          ..end();
      }).single;
      final XmlPullReader r = readerOf(e);
      expect(r.eventType, XmlEventType.startElement);
      expect(r.localName, 'a');
      expect(r.namespaceUri, Ns.main);
      expect(r.getAttribute('v'), '1');
      expect(OpaqueXml.capture(r).xml, e.xml);
    });

    test('readerOf reads a prefix bound outside the slice', () {
      final XmlPullReader source = _onChild(
        '<root xmlns:x14="$_x14" xmlns:o="urn:o">'
        '<x14:rule o:a="1"><x14:child/></x14:rule></root>',
      );
      final OpaqueXml e = OpaqueXml.capture(source);
      final XmlPullReader r = readerOf(e);
      expect(r.localName, 'rule');
      expect(r.namespaceUri, _x14);
      expect(r.attributeNamespace(0), 'urn:o');
      r.next();
      expect(r.localName, 'child');
      expect(r.namespaceUri, _x14);
    });

    test('an element in no namespace stays in none', () {
      final OpaqueXml e = OpaqueXml.capture(_onChild('<root><a/></root>'));
      final XmlPullReader r = readerOf(e);
      expect(r.localName, 'a');
      expect(r.namespaceUri, '');
    });

    test('a forbidden character in a binding does not throw', () {
      final OpaqueXml e = OpaqueXml.capture(
        _onChild('<root xmlns:o="urn:&#1;o"><o:a/></root>'),
      );
      expect(readerOf(e).localName, 'a');
    });
  });
}
