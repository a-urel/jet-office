// Reads the properties of the owner's `blank.docx` (Word for Mac): the
// values Word wrote, and that reading them changes no byte on a save. VM
// only: it reads a file from disk.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';

void main() {
  test('blank.docx reads the properties Word wrote', () {
    final Uint8List bytes = File(
      'test/fixtures/owner/docx/blank.docx',
    ).readAsBytesSync();
    final DocxDocument doc = DocxDocument.open(bytes);
    final OfficeProperties p = doc.properties;
    expect(p.title, '');
    expect(p.creator, 'Ahmet Urel');
    expect(p.lastModifiedBy, 'Ahmet Urel');
    expect(p.revision, 1);
    expect(p.created, DateTime.utc(2026, 11, 3, 13, 52));
    expect(p.modified, DateTime.utc(2026, 11, 3, 13, 52));
    expect(p.application, 'Microsoft Office Word');
    expect(p.company, '');
    final DocxResult saved = doc.save();
    expect(saved.warnings, isEmpty);
    expect(comparePackages(bytes, saved.bytes), isEmpty);
  });
}
