@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/write_large_docx.dart' as write_large_docx;
import '../docx/support/large_document.dart';

void main() {
  final Uint8List source = File(
    'test/fixtures/owner/docx/long.docx',
  ).readAsBytesSync();

  test('scales long.docx, with bookmark ids and _Toc names per copy', () {
    final ScaledDocument scaled = scaledLongDocx(source, paragraphs: 400);
    final DocxDocument doc = DocxDocument.open(scaled.bytes);
    final int count = doc.body.blocks.whereType<DocxParagraph>().length;
    expect(count, greaterThanOrEqualTo(400));
    expect(
      count,
      scaled.sourceParagraphs * (400 / scaled.sourceParagraphs).ceil(),
    );
    expect(doc.warnings, isEmpty);
    final List<int?> ids = <int?>[
      for (final DocxParagraph p in doc.body.blocks.whereType<DocxParagraph>())
        for (final DocxBookmarkStart b
            in p.inlines.whereType<DocxBookmarkStart>())
          b.id,
    ];
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('a paragraph count below 1 throws', () {
    expect(() => scaledLongDocx(source, paragraphs: 0), throwsArgumentError);
  });

  test('editedLargeDocx changes one paragraph and reopens', () {
    final Uint8List bytes = write_large_docx.editedLargeDocx(
      source,
      paragraphs: 400,
    );
    final DocxDocument doc = DocxDocument.open(bytes);
    final List<String> texts = <String>[
      for (final DocxBlock b in doc.body.blocks)
        if (b is DocxParagraph) b.text,
    ];
    expect(
      texts.where(
        (String t) => t.startsWith(write_large_docx.largeDocxEditedText),
      ),
      hasLength(1),
    );
    expect(doc.warnings, isEmpty);
  });

  test('bad arguments exit 2', () {
    write_large_docx.main(<String>[]);
    expect(exitCode, 2);
    exitCode = 0;
    write_large_docx.main(<String>['--x']);
    expect(exitCode, 2);
    exitCode = 0;
  });
}
