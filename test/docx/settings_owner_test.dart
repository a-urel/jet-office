/// `evenAndOddHeaders` on the owner's Word files: set true and undone, a file
/// saves as it was, and set true, the settings part differs from the file's
/// only by the one child, in schema order. VM only: it reads files from disk.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart' show changeLogOf;
import 'package:jet_office/src/opc/change_log.dart' show ChangeSet;
import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';

const String _dir = 'test/fixtures/owner/docx';

void main() {
  for (final String name in <String>['blank', 'features', 'long', 'builtins']) {
    test('$name: true then undone saves what the file holds', () {
      final Uint8List input = File('$_dir/$name.docx').readAsBytesSync();
      final DocxDocument doc = DocxDocument.open(input);
      final bool before = doc.evenAndOddHeaders;
      final ChangeSet set = changeLogOf(
        doc,
      ).transaction(() => doc.evenAndOddHeaders = !before);
      expect(doc.evenAndOddHeaders, !before);
      changeLogOf(doc).revertSet(set);
      expect(doc.evenAndOddHeaders, before);
      expect(comparePackages(input, doc.save().bytes), isEmpty);
    });

    test('$name: true changes only the settings part', () {
      final Uint8List input = File('$_dir/$name.docx').readAsBytesSync();
      final DocxDocument doc = DocxDocument.open(input)
        ..evenAndOddHeaders = true;
      final Uint8List out = doc.save().bytes;
      final Set<String> differing = <String>{
        for (final String line in comparePackages(input, out))
          line.split(':').first,
      };
      expect(
        differing.difference(<String>{
          'word/settings.xml',
          '[Content_Types].xml',
          'word/_rels/document.xml.rels',
        }),
        isEmpty,
      );
      expect(DocxDocument.open(out).evenAndOddHeaders, isTrue);
    });
  }
}
