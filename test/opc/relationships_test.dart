import 'package:jet_office/src/opc/ooxml.dart';
import 'package:jet_office/src/opc/relationships.dart';
import 'package:jet_office/src/xml/xml_writer.dart';
import 'package:test/test.dart';

void main() {
  test('add returns rId1, rId2, ... in call order', () {
    final Relationships rels = Relationships();
    expect(rels.add(RelType.worksheet, 'worksheets/sheet1.xml'), 'rId1');
    expect(rels.add(RelType.styles, 'styles.xml'), 'rId2');
    expect(rels.add(RelType.sharedStrings, 'sharedStrings.xml'), 'rId3');
  });

  test('writes the part in id order with relative targets', () {
    final Relationships rels = Relationships()
      ..add(RelType.worksheet, 'worksheets/sheet1.xml')
      ..add(RelType.styles, 'styles.xml');
    final StringBuffer out = StringBuffer();
    rels.write(XmlWriter(out));
    expect(
      out.toString(),
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>',
    );
  });

  test('type constants hold the ECMA-376 values', () {
    expect(
      RelType.officeDocument,
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument',
    );
    expect(
      RelType.coreProperties,
      'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties',
    );
    expect(
      RelType.extendedProperties,
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties',
    );
  });

  test('an empty collection writes an empty Relationships element', () {
    final StringBuffer out = StringBuffer();
    Relationships().write(XmlWriter(out));
    expect(
      out.toString(),
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>',
    );
  });

  test('an empty type or target throws ArgumentError and adds nothing', () {
    final Relationships rels = Relationships();
    expect(() => rels.add('', 'styles.xml'), throwsArgumentError);
    expect(() => rels.add(RelType.styles, ''), throwsArgumentError);
    expect(rels.add(RelType.styles, 'styles.xml'), 'rId1');
  });
}
