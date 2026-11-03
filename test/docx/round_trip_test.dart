// Every D1 fixture (test/fixtures/docx_fixtures.dart) opens with the
// paragraphs it was built with, reports the warnings it should, and saves
// to a package equal to its input by the comparer of tool/src/part_compare
// (spec 4.2). The owner's Word files are round-tripped in
// owner_files_test.dart, which reads them from disk and runs on the VM only.
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';
import '../../tool/src/text_compare.dart';
import '../fixtures/docx_fixtures.dart';

void main() {
  final List<DocxFixture> fixtures = docxFixtures();

  test('the D1 fixtures are the five the plan names, each named once', () {
    final List<String> names = <String>[
      for (final DocxFixture f in fixtures) f.name,
    ];
    expect(names.toSet(), hasLength(names.length));
    expect(
      names,
      containsAll(<String>[
        'd1_blank',
        'd1_paragraphs',
        'd1_text_rules',
        'd1_unicode',
        'd1_large',
      ]),
    );
    expect(names.every((String n) => n.startsWith('d1_')), isTrue);
  });

  test('every D1 fixture builds the same bytes every time', () {
    for (final DocxFixture f in fixtures) {
      expect(f.build().bytes, f.build().bytes, reason: f.name);
    }
  });

  test('every D1 fixture builds with exactly its expected warnings', () {
    for (final DocxFixture f in fixtures) {
      final Map<DocxWarningCode, int> counts = <DocxWarningCode, int>{};
      for (final DocxWarning w in f.build().warnings) {
        counts[w.code] = (counts[w.code] ?? 0) + w.count;
      }
      expect(counts, f.expectedWarnings, reason: f.name);
    }
  });

  test('d1_text_rules expects one removed character', () {
    final DocxFixture f = fixtures.singleWhere(
      (DocxFixture f) => f.name == 'd1_text_rules',
    );
    expect(f.expectedWarnings, <DocxWarningCode, int>{
      DocxWarningCode.invalidCharactersRemoved: 1,
    });
  });

  test('d1_large holds 2,000 paragraphs', () {
    final DocxFixture f = fixtures.singleWhere(
      (DocxFixture f) => f.name == 'd1_large',
    );
    final DocxDocument doc = DocxDocument.open(f.build().bytes);
    expect(doc.body.blocks, hasLength(2000));
  });

  test('every D1 fixture round-trips', () {
    for (final DocxFixture f in fixtures) {
      final Uint8List input = f.build().bytes;
      final DocxDocument doc = DocxDocument.open(input);
      expect(
        doc.body.blocks.every((DocxBlock b) => b is DocxParagraph),
        isTrue,
        reason: '${f.name}: a D1 fixture holds paragraphs only',
      );
      expect(docxBodyText(doc), f.expectedText, reason: f.name);
      final DocxResult saved = doc.save();
      expect(saved.warnings, isEmpty, reason: f.name);
      final List<String> differences = comparePackages(input, saved.bytes);
      expect(
        differences,
        isEmpty,
        reason: '${f.name}\n${differences.join('\n')}',
      );
    }
  });
}
