/// Reads the owner's Word for Mac files (`test/fixtures/owner/docx/`):
/// every one round-trips through `DocxDocument` with nothing lost, and every
/// one the owner confirmed reads the text the owner confirmed. A draft
/// (`"confirmedBy": null`) prints `pending` instead. The manifest format is
/// in `test/support/owner_docx.dart` and `test/fixtures/owner/README.md`.
/// VM only: it reads files from disk.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';
import '../../tool/src/text_compare.dart';
import '../support/owner_docx.dart';

const String _dir = 'test/fixtures/owner/docx';

void main() {
  final List<String> names = <String>[
    for (final FileSystemEntity e in Directory(_dir).listSync())
      if (e is File) e.uri.pathSegments.last,
  ];
  final List<OwnerDocx> manifest = parseOwnerDocxManifest(
    File('$_dir/manifest.json').readAsStringSync(),
  );

  test('every .docx and .expected.txt is listed and has its partner', () {
    expect(ownerDocxDirectoryProblems(names, manifest), isEmpty);
  });

  test('the manifest lists the three Word for Mac files', () {
    expect(<String>[
      for (final OwnerDocx e in manifest) e.file,
    ], containsAll(<String>['blank.docx', 'features.docx', 'long.docx']));
  });

  test('every owner file round-trips', () {
    for (final OwnerDocx entry in manifest) {
      final Uint8List input = File('$_dir/${entry.file}').readAsBytesSync();
      final DocxDocument doc = DocxDocument.open(input);
      expect(doc.body.blocks, isNotEmpty, reason: entry.file);
      final DocxResult saved = doc.save();
      expect(saved.warnings, isEmpty, reason: entry.file);
      final List<String> differences = comparePackages(input, saved.bytes);
      expect(
        differences,
        isEmpty,
        reason: '${entry.file}\n${differences.join('\n')}',
      );
    }
  });

  test('every owner file round-trips with its styles loaded', () {
    for (final OwnerDocx entry in manifest) {
      final Uint8List input = File('$_dir/${entry.file}').readAsBytesSync();
      final DocxDocument doc = DocxDocument.open(input);
      expect(doc.styles.styles, isNotEmpty, reason: entry.file);
      expect(doc.styles.byName('Normal'), isNotNull, reason: entry.file);
      final List<String> differences = comparePackages(input, doc.save().bytes);
      expect(
        differences,
        isEmpty,
        reason: '${entry.file}\n${differences.join('\n')}',
      );
    }
  });

  test('every owner file round-trips with its numbering loaded', () {
    for (final OwnerDocx entry in manifest) {
      final Uint8List input = File('$_dir/${entry.file}').readAsBytesSync();
      final DocxDocument doc = DocxDocument.open(input);
      final DocxNumbering numbering = doc.numbering;
      for (final DocxNumberingInstance n in numbering.instances) {
        expect(n.abstractNumbering, isNotNull, reason: '${entry.file} $n');
      }
      final List<String> differences = comparePackages(input, doc.save().bytes);
      expect(
        differences,
        isEmpty,
        reason: '${entry.file}\n${differences.join('\n')}',
      );
    }
  });

  test('every owner file reads its confirmed text', () {
    for (final OwnerDocx entry in manifest) {
      final String stem = entry.file.substring(0, entry.file.length - 5);
      final String expected = readExpectedText(
        File('$_dir/$stem.expected.txt').readAsStringSync(),
      );
      final DocxDocument doc = DocxDocument.open(
        File('$_dir/${entry.file}').readAsBytesSync(),
      );
      final String actual = docxBodyText(doc);
      if (!entry.confirmed) {
        // ignore: avoid_print
        print('${entry.file}: pending (drafted, not confirmed by the owner)');
        continue;
      }
      final List<String> differences = textDifferences(expected, actual);
      expect(
        differences,
        isEmpty,
        reason: '${entry.file}\n${differences.join('\n')}',
      );
    }
  });

  test('a draft still matches what the model reads', () {
    // A draft is the model's own answer, which the owner then checks
    // against Word; one that no longer matches the model would make that
    // check meaningless. A confirmed text is the owner's and is checked
    // above instead.
    for (final OwnerDocx entry in manifest) {
      if (entry.confirmed) continue;
      final String stem = entry.file.substring(0, entry.file.length - 5);
      final String expected = readExpectedText(
        File('$_dir/$stem.expected.txt').readAsStringSync(),
      );
      final DocxDocument doc = DocxDocument.open(
        File('$_dir/${entry.file}').readAsBytesSync(),
      );
      expect(
        textDifferences(expected, docxBodyText(doc)),
        isEmpty,
        reason: entry.file,
      );
    }
  });
}
