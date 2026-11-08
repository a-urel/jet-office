/// Writes a list into the owner's Word for Mac files
/// (`test/fixtures/owner/docx/features.docx` and `long.docx`: Turkish
/// settings, styles of their own, and for `long.docx` odd and even headers):
/// the saved file reopens with no warning, reopening and saving it changes
/// nothing, and the last section's headers and footers hold the list's text.
/// VM only: it reads files from disk.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';
import '../../tool/write_list_into.dart';

const String _dir = 'test/fixtures/owner/docx';

/// The text of [story]'s paragraphs, one per block.
List<String> _texts(DocxHeaderFooter story) => <String>[
  for (final DocxBlock b in story.blocks)
    if (b is DocxParagraph) b.text,
];

void main() {
  for (final String name in <String>['features.docx', 'long.docx']) {
    group(name, () {
      final Uint8List source = File('$_dir/$name').readAsBytesSync();
      final DocxDocument doc = DocxDocument.open(source);
      final int blocksBefore = doc.body.blocks.length;
      final bool even = doc.evenAndOddHeaders;
      turkishList().writeTo(doc, turkishRows, totals: turkishTotals);
      final Uint8List saved = doc.save().bytes;

      test('reopens with no warning, the list after the file\'s own', () {
        final DocxDocument back = DocxDocument.open(saved);
        expect(back.warnings, isEmpty);
        expect(back.body.blocks.length, greaterThan(blocksBefore));
        final DocxTable table = back.body.blocks.whereType<DocxTable>().last;
        expect(table.rows, hasLength(5));
        expect(table.rows.first.cells.first.text, 'Kod');
        expect(table.rows.last.cells.first.text, 'Toplam');
      });

      test('opening and saving it again changes nothing', () {
        final DocxDocument back = DocxDocument.open(saved);
        expect(back.warnings, isEmpty);
        expect(comparePackages(saved, back.save().bytes), isEmpty);
      });

      test('the last section shows the list\'s header and footer', () {
        final DocxSection last = DocxDocument.open(saved).sections.last;
        expect(_texts(last.header), <String>['\tMüşteri listesi\t08.11.2026']);
        expect(_texts(last.footer), <String>['Sayfa 1 / 1']);
        expect(last.titlePage, isFalse);
        expect(last.columns?.count ?? 1, 1);
      });

      test('the even pages show them too when the file has odd and even', () {
        final DocxDocument back = DocxDocument.open(saved);
        expect(back.evenAndOddHeaders, even);
        if (!even) return;
        final DocxSection last = back.sections.last;
        expect(_texts(last.evenHeader), <String>[
          '\tMüşteri listesi\t08.11.2026',
        ]);
        expect(_texts(last.evenFooter), <String>['Sayfa 1 / 1']);
      });
    });
  }

  test('long.docx has odd and even headers, so the even case is covered', () {
    expect(
      DocxDocument.open(
        File('$_dir/long.docx').readAsBytesSync(),
      ).evenAndOddHeaders,
      isTrue,
    );
  });
}
