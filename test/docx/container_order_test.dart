// Tests that every container schema the library defines writes its children
// in its table's order (spec §4.7): children read in reverse order, and
// values set in reverse order, come out in the order of the table. The
// schemas are listed in support/container_schemas.dart. The tests build the
// XML in memory, so they run on the web as well.
import 'package:jet_office/src/docx/properties.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart' show XmlDocument, XmlElement;

import 'support/container_schemas.dart';

/// Reads `<w:name>` holding [children] (local names, each an empty `w:`
/// element) by [schema].
PropertyContainer _read(
  String name,
  List<String> children,
  ContainerSchema schema,
) {
  final XmlPullReader r = XmlPullReader(
    '<w:$name xmlns:w="${Ns.w}">'
    '${children.map((String c) => '<w:$c/>').join()}</w:$name>',
  );
  r.nextTag();
  return PropertyContainer.read(r, schema);
}

/// The local names of the children [c] writes as [name] with [overrides].
List<String> _written(
  PropertyContainer c,
  String name,
  ContainerSchema schema,
  Map<String, Object?> overrides,
) {
  final StringBuffer b = StringBuffer();
  c.writeTo(
    XmlWriter(b),
    'w:$name',
    schema,
    overrides: overrides,
    declaredAbove: const <String, String>{'w': Ns.w},
  );
  final XmlDocument doc = XmlDocument.parse(
    b.toString().replaceFirst('<w:$name', '<w:$name xmlns:w="${Ns.w}"'),
  );
  return <String>[
    for (final XmlElement e in doc.rootElement.childElements) e.localName,
  ];
}

void main() {
  for (final ContainerSchemaCase c in containerSchemaCases) {
    final ContainerSchema schema = c.schema;
    group(c.name, () {
      test('every codec and nested name is in the order, once, and every '
          'codec has a sample', () {
        expect(schema.order.toSet(), hasLength(schema.order.length));
        expect(schema.order, containsAll(schema.codecs.keys));
        expect(schema.order, containsAll(schema.nested.keys));
        expect(
          schema.codecs.keys.toSet().intersection(schema.nested.keys.toSet()),
          isEmpty,
        );
        expect(c.samples.keys.toSet(), schema.codecs.keys.toSet());
        schema.codecs.forEach((String name, codec) {
          expect(codec.localName, name);
          expect(codec.accepts(c.samples[name]!), isTrue, reason: name);
        });
      });

      test('children read in reverse order are written in table order', () {
        final PropertyContainer read = _read(
          c.name,
          schema.order.reversed.toList(),
          schema,
        );
        expect(
          _written(read, c.name, schema, const <String, Object?>{}),
          schema.order,
        );
      });

      test('values set in reverse order are written in table order', () {
        final Map<String, Object?> overrides = <String, Object?>{
          for (final String name in schema.order.reversed)
            if (c.samples.containsKey(name)) name: c.samples[name],
        };
        // Among the other children, read in reverse order.
        final PropertyContainer read = _read(c.name, <String>[
          for (final String name in schema.order.reversed)
            if (!overrides.containsKey(name)) name,
        ], schema);
        expect(_written(read, c.name, schema, overrides), schema.order);
        // And over children of the same names, read in reverse order.
        final PropertyContainer all = _read(
          c.name,
          schema.order.reversed.toList(),
          schema,
        );
        expect(_written(all, c.name, schema, overrides), schema.order);
      });
    });
  }
}
