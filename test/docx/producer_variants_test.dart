// The hand-made producer variants of d1_paragraphs
// (test/docx/support/producer_variants.dart): each opens with the blocks
// d1_paragraphs has, with only the warnings its layout causes, and saves
// to a package equal to its input (spec 9, "Producer variants").
library;

import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/src/docx_serialize.dart';
import '../../tool/src/part_compare.dart';
import '../fixtures/docx_fixtures.dart';
import 'support/producer_variants.dart';
import 'support/styles_documents.dart' show readDocxText;

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

  test('the variants are the seven the plan names', () {
    expect(
      <String>[for (final ProducerVariant v in variants) v.name],
      <String>[
        'ns0_prefix',
        'default_namespace',
        'no_override',
        'libreoffice',
        'google_docs',
        'docm',
        'google_docs_no_numbering',
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

  test('the google_docs_no_numbering variant gains numbering.xml once', () {
    final ProducerVariant variant = variants.singleWhere(
      (ProducerVariant v) => v.name == 'google_docs_no_numbering',
    );
    final Map<String, String> before = readDocxText(variant.bytes);
    expect(before.keys, isNot(contains('word/numbering.xml')));
    expect(
      before['word/_rels/document.xml.rels'],
      isNot(contains('numbering')),
    );
    final DocxDocument doc = DocxDocument.open(variant.bytes);
    final DocxNumberingInstance list = doc.numbering.addBulletList();
    doc.body.addListItem(list, 'A bullet');
    doc.body.addListItem(list, 'A nested bullet', level: 1);
    // A second save of the same document must not add the part again.
    doc.save();
    final Uint8List saved = doc.save().bytes;
    final Map<String, String> after = readDocxText(saved);
    expect(after.keys.where((String k) => k.contains('numbering')), <String>[
      'word/numbering.xml',
    ]);
    expect(
      RegExp(
        'Type="[^"]*/numbering"',
      ).allMatches(after['word/_rels/document.xml.rels']!).length,
      1,
    );
    expect(
      RegExp(
        'PartName="/word/numbering.xml"',
      ).allMatches(after['[Content_Types].xml']!).length,
      1,
    );
    // Reopened, the file holds the list, the paragraphs it had and the
    // built-in style the helper added; nothing else about the layout moved.
    final DocxDocument back = DocxDocument.open(saved);
    expect(back.numbering.instances, hasLength(1));
    expect(back.warnings, isEmpty);
    expect(_outline(back).take(expected.length), expected);
    expect(
      comparePackages(
        variant.bytes,
        saved,
        ignoreParts: <String>{
          'word/document.xml',
          'word/numbering.xml',
          'word/styles.xml',
          'word/_rels/document.xml.rels',
          '[Content_Types].xml',
        },
      ),
      isEmpty,
    );
    expect(encodedPartDifferences(saved), isEmpty);
  });

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
