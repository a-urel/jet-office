// The hand-made producer variants of d1_paragraphs
// (test/docx/support/producer_variants.dart): each opens with the blocks
// d1_paragraphs has, with only the warnings its layout causes, and saves
// to a package equal to its input (spec 9, "Producer variants").
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';
import '../fixtures/docx_fixtures.dart';
import 'support/producer_variants.dart';

/// The blocks of [doc] as `p:<style>:<text>`, the shape the variants are
/// compared by.
List<String> _outline(DocxDocument doc) => <String>[
  for (final DocxBlock b in doc.body.blocks)
    if (b is DocxParagraph) 'p:${b.style}:${b.text}' else 'other:$b',
];

void main() {
  final DocxFixture paragraphs = docxFixtures().singleWhere(
    (DocxFixture f) => f.name == 'd1_paragraphs',
  );
  final List<String> expected = _outline(
    DocxDocument.open(paragraphs.build().bytes),
  );
  final List<ProducerVariant> variants = producerVariants();

  test('the variants are the six the plan names', () {
    expect(
      <String>[for (final ProducerVariant v in variants) v.name],
      <String>[
        'ns0_prefix',
        'default_namespace',
        'no_override',
        'libreoffice',
        'google_docs',
        'docm',
      ],
    );
  });

  for (final ProducerVariant variant in variants) {
    test('${variant.name}: opens as d1_paragraphs and saves equal', () {
      final Uint8List input = variant.bytes;
      final DocxDocument doc = DocxDocument.open(input);
      expect(_outline(doc), expected);
      expect(<DocxWarningCode>[
        for (final DocxWarning w in doc.warnings) w.code,
      ], variant.warnings);
      final DocxResult saved = doc.save();
      final List<String> differences = comparePackages(input, saved.bytes);
      expect(differences, isEmpty, reason: differences.join('\n'));
    });
  }

  test('an edited .docm keeps every part but the body as it was', () {
    // comparePackages compares a binary part such as vbaProject.bin byte
    // for byte, so only the edited document part may differ.
    final ProducerVariant docm = variants.singleWhere(
      (ProducerVariant v) => v.name == 'docm',
    );
    final DocxDocument doc = DocxDocument.open(docm.bytes);
    doc.body.addParagraph('Added.');
    final Uint8List saved = doc.save().bytes;
    expect(
      comparePackages(
        docm.bytes,
        saved,
        ignoreParts: <String>{'word/document.xml'},
      ),
      isEmpty,
    );
    expect(comparePackages(docm.bytes, saved), isNotEmpty);
  });
}
