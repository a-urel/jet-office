// The owner's Word files and the template fill (decision 0024, T1): data
// naming nothing gives each file back unchanged. VM only: it reads files.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';

void main() {
  final List<File> files =
      Directory('test/fixtures/owner/docx')
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.endsWith('.docx'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));

  test('the owner has Word files', () => expect(files, isNotEmpty));

  for (final File file in files) {
    test('data naming nothing gives ${file.uri.pathSegments.last} back', () {
      final Uint8List bytes = file.readAsBytesSync();
      final DocxResult result = DocxTemplate(bytes).fill(<String, Object?>{});
      expect(comparePackages(bytes, result.bytes), isEmpty);
    });
  }
}
