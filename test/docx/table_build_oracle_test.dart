// The table `addTable` and `addRow` build against the one Word's Insert Table
// wrote in the owner's `builtins.docx` (a table of two columns on a blank A4
// page): the properties, the grid and the cell widths are the same XML.
// VM only: it reads the file from disk.
@TestOn('vm')
library;

import 'dart:io';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/styles_documents.dart';

const String _fixture = 'test/fixtures/owner/docx/builtins.docx';

/// The children `w:<name>` of [table] and of its descendants, as written.
List<String> _xmlOf(XmlElement table, String name) => <String>[
  for (final XmlElement e in table.findAllElements(name, namespaceUri: Ns.w))
    e.toXmlString(),
];

void main() {
  test("addTable writes what Word's Insert Table writes", () {
    final DocxDocument doc = DocxDocument.open(
      File(_fixture).readAsBytesSync(),
    );
    final DocxTable table = doc.body.addTable(columns: 2);
    table.addRow(<String?>['A', 'B']);
    table.addRow(<String?>['C', 'D']);

    final List<XmlElement> tables = XmlDocument.parse(
      readDocxText(doc.save().bytes)['word/document.xml']!,
    ).findAllElements('tbl', namespaceUri: Ns.w).toList();
    expect(tables, hasLength(2));
    final XmlElement word = tables.first;
    final XmlElement built = tables.last;
    for (final String name in <String>['tblPr', 'tblGrid', 'tcPr']) {
      expect(_xmlOf(built, name), _xmlOf(word, name), reason: name);
    }
  });
}
