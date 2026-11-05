/// Style resolution on the owner's Word for Mac files, saved under a Turkish
/// system: a built-in style is found by its name whatever its id, and no
/// parallel English style is added (plan Rulings 5 and 6). VM only: it reads
/// files from disk.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/src/part_compare.dart';
import 'support/styles_documents.dart';

const String _dir = 'test/fixtures/owner/docx';

Uint8List _bytes(String name) => File('$_dir/$name').readAsBytesSync();

DocxDocument _open(String name) => DocxDocument.open(_bytes(name));

/// The parts [comparePackages] names between [before] and [after].
Set<String> _changedParts(Uint8List before, Uint8List after) => <String>{
  for (final String line in comparePackages(before, after))
    line.substring(0, line.indexOf(': ')),
};

void main() {
  test('features.docx: idOf heading1, listParagraph, tableGrid, header, '
      'footer are Balk1, ListeParagraf, TabloKlavuzu, stBilgi, AltBilgi', () {
    final DocxStyles styles = _open('features.docx').styles;
    expect(styles.idOf(DocxBuiltInStyle.heading1), 'Balk1');
    expect(styles.idOf(DocxBuiltInStyle.listParagraph), 'ListeParagraf');
    expect(styles.idOf(DocxBuiltInStyle.tableGrid), 'TabloKlavuzu');
    expect(styles.idOf(DocxBuiltInStyle.header), 'stBilgi');
    expect(styles.idOf(DocxBuiltInStyle.footer), 'AltBilgi');
  });

  test('long.docx: idOf title and hyperlink are KonuBal and Kpr', () {
    final DocxStyles styles = _open('long.docx').styles;
    expect(styles.idOf(DocxBuiltInStyle.title), 'KonuBal');
    expect(styles.idOf(DocxBuiltInStyle.hyperlink), 'Kpr');
  });

  test('long.docx: ensure(tableGrid) adds TableGrid basedOn NormalTablo', () {
    final Uint8List input = _bytes('long.docx');
    final DocxDocument doc = DocxDocument.open(input);
    expect(doc.styles.ensure(DocxBuiltInStyle.tableGrid), 'TableGrid');
    expect(doc.styles.byId('TableGrid')?.basedOn, 'NormalTablo');
    expect(_changedParts(input, doc.save().bytes), <String>{'word/styles.xml'});
  });

  for (final String name in <String>['features.docx', 'long.docx']) {
    group(name, () {
      late Uint8List input;
      late DocxDocument doc;
      late DocxParagraph first;
      late Uint8List saved;
      late String styles;

      setUp(() {
        input = _bytes(name);
        doc = DocxDocument.open(input);
        first = doc.body.blocks.whereType<DocxParagraph>().first;
        first.style = 'Heading1';
        saved = doc.save().bytes;
        styles = readDocxText(saved)['word/styles.xml']!;
      });

      test('setting Heading1 on the first paragraph and saving adds no style '
          'named heading 1', () {
        expect(
          RegExp('w:name w:val="heading 1"').allMatches(styles),
          hasLength(1),
        );
        final DocxDocument again = DocxDocument.open(saved);
        expect(
          again.body.blocks.whereType<DocxParagraph>().first.style,
          'Balk1',
        );
      });

      test('no saved styles.xml has w:styleId Heading1', () {
        expect(styles, isNot(contains('w:styleId="Heading1"')));
      });

      test('the saved file differs only in document.xml when nothing was '
          'added', () {
        expect(
          _changedParts(input, saved).difference(<String>{'word/document.xml'}),
          isEmpty,
        );
      });

      test('the saved file differs only in document.xml and styles.xml when '
          'something was added', () {
        final DocxDocument added = DocxDocument.open(input);
        added.body.addParagraph('x').style = 'NoSpacing';
        expect(_changedParts(input, added.save().bytes), <String>{
          'word/document.xml',
          'word/styles.xml',
        });
      });
    });
  }
}
