// Tests tool/edit_docx.dart: the model edits every document of a directory
// (a run's text, a replaced paragraph, an added heading) for the Open XML
// SDK to validate. It reads and writes files, so it runs on the VM only.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

import '../../tool/edit_docx.dart';
import '../../tool/write_fixtures.dart' as write_fixtures;
import '../docx/support/docx_builder.dart' show rewriteDocxPart;
import '../docx/support/localized_document.dart';
import '../docx/support/styles_documents.dart';
import '../docx/support/word_document.dart';

void main() {
  late Directory temp;
  late Directory input;
  late Directory output;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('edit_docx_test');
    input = Directory('${temp.path}/in')..createSync();
    output = Directory('${temp.path}/out');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  /// Writes every fixture to [dir], then deletes all but the files named in
  /// [keep].
  void writeOnly(Directory dir, Set<String> keep) {
    write_fixtures.main(<String>[dir.path]);
    for (final FileSystemEntity e in dir.listSync()) {
      if (!keep.contains(e.uri.pathSegments.last)) e.deleteSync();
    }
  }

  int run({StringBuffer? out, StringBuffer? err}) => editDocx(
    <String>[input.path, output.path],
    out: out ?? StringBuffer(),
    err: err ?? StringBuffer(),
  );

  List<String> outline(Uint8List bytes) => <String>[
    for (final DocxBlock b in DocxDocument.open(bytes).body.blocks)
      switch (b) {
        DocxParagraph() => '${b.style ?? '-'}:${b.text}',
        DocxOpaqueBlock() => 'opaque:${b.localName}',
      },
  ];

  test('edits two fixtures and skips a lock file: exit 0', () {
    writeOnly(input, <String>{'d1_blank.docx', 'd1_paragraphs.docx'});
    File('${input.path}/~\$d1_blank.docx').writeAsBytesSync(<int>[1, 2]);
    final StringBuffer out = StringBuffer();
    final StringBuffer err = StringBuffer();
    expect(
      run(out: out, err: err),
      0,
      reason: '$out$err',
    );
    expect(err.toString(), isEmpty);
    expect(<String>[
      for (final FileSystemEntity e in output.listSync())
        e.uri.pathSegments.last,
    ], unorderedEquals(<String>['d1_blank.docx', 'd1_paragraphs.docx']));
    expect(out.toString(), contains('All 2 documents edited.'));
  });

  test('a Word-like document gets the edits, and only the allowed parts '
      'change', () {
    File('${input.path}/word.docx').writeAsBytesSync(richWordDocx());
    final StringBuffer out = StringBuffer();
    expect(run(out: out), 0, reason: '$out');
    final List<String> before = outline(richWordDocx());
    final List<String> after = outline(
      File('${output.path}/word.docx').readAsBytesSync(),
    );
    expect(after, hasLength(before.length + 3));
    // The first run with text is the title's.
    expect(before.first, 'Title:Fiyat listesiÜrün ');
    expect(after.first, 'Title:$editedTextÜrün ');
    // The last all-runs paragraph is the empty one after the table.
    expect(before[10], '-:');
    expect(after[10], '-:$replacedText');
    // No styles part, so Word's heading and list styles are added.
    expect(after[after.length - 3], 'Heading1:$addedText');
    expect(after[after.length - 2], 'ListParagraph:$firstItemText');
    expect(after.last, 'ListParagraph:$secondItemText');
    expect(after.sublist(1, 10), before.sublist(1, 10));
  });

  test('a document that defines Heading1 gets a Heading1 paragraph', () {
    writeOnly(input, <String>{'d1_paragraphs.docx'});
    final File file = File('${input.path}/d1_paragraphs.docx');
    final Uint8List bytes = file.readAsBytesSync();
    final Uint8List withHeading = rewriteDocxPart(
      bytes,
      'word/styles.xml',
      (String xml) => xml.replaceFirst(
        '</w:styles>',
        '<w:style w:type="paragraph" w:styleId="Heading1">'
            '<w:name w:val="heading 1"/></w:style></w:styles>',
      ),
    );
    file.writeAsBytesSync(withHeading);
    expect(run(), 0);
    final List<String> after = outline(
      File('${output.path}/d1_paragraphs.docx').readAsBytesSync(),
    );
    expect(after[after.length - 3], 'Heading1:$addedText');
  });

  test('edits a document with Turkish style ids using Balk1', () {
    File('${input.path}/tr.docx').writeAsBytesSync(localizedWordDocx());
    final StringBuffer out = StringBuffer();
    expect(run(out: out), 0, reason: '$out');
    final List<String> after = outline(
      File('${output.path}/tr.docx').readAsBytesSync(),
    );
    expect(after[after.length - 3], 'Balk1:$addedText');
    expect(after[after.length - 2], 'ListeParagraf:$firstItemText');
  });

  test('creates numbering.xml in a document without one', () {
    File('${input.path}/tr.docx').writeAsBytesSync(localizedWordDocx());
    final Uint8List before = localizedWordDocx();
    expect(
      ZipDecoder().decodeBytes(before).findFile('word/numbering.xml'),
      isNull,
    );
    final StringBuffer out = StringBuffer();
    expect(run(out: out), 0, reason: '$out');
    final Archive after = ZipDecoder().decodeBytes(
      File('${output.path}/tr.docx').readAsBytesSync(),
    );
    expect(after.findFile('word/numbering.xml'), isNotNull);
  });

  test('reports a part outside the allowed set', () {
    File('${input.path}/word.docx').writeAsBytesSync(richWordDocx());
    final StringBuffer out = StringBuffer();
    final int code = editDocx(
      <String>[input.path, output.path],
      out: out,
      err: StringBuffer(),
      corruptForTest: (Uint8List saved) => rewriteDocxPart(
        saved,
        'word/settings.xml',
        (String x) => x.replaceFirst('100', '200'),
      ),
    );
    expect(code, 1);
    expect(out.toString(), contains('a part outside the allowed set'));
    expect(out.toString(), contains('word/settings.xml'));
  });

  test('reports an edit that does not read back', () {
    File('${input.path}/word.docx').writeAsBytesSync(richWordDocx());
    final StringBuffer out = StringBuffer();
    final int code = editDocx(
      <String>[input.path, output.path],
      out: out,
      err: StringBuffer(),
      corruptForTest: (Uint8List saved) => rewriteDocxPart(
        saved,
        'word/document.xml',
        (String x) => x.replaceFirst(editedText, 'Not edited'),
      ),
    );
    expect(code, 1);
    expect(out.toString(), contains('the edited run text is missing'));
  });

  test('skips a paragraph with a field in a run as the one to replace', () {
    final Uint8List doc = docxWithStyles(
      document:
          '<w:document xmlns:w="${Ns.w}"><w:body>'
          '<w:p><w:r><w:t>First</w:t></w:r></w:p>'
          '<w:p><w:r><w:t>Plain</w:t></w:r></w:p>'
          '<w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r>'
          '<w:r><w:instrText>PAGE</w:instrText></w:r>'
          '<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>'
          '</w:body></w:document>',
      styles: stylesXmlOf(<String>[]),
    );
    File('${input.path}/field.docx').writeAsBytesSync(doc);
    final StringBuffer out = StringBuffer();
    expect(run(out: out), 0, reason: '$out');
    final List<String> after = outline(
      File('${output.path}/field.docx').readAsBytesSync(),
    );
    expect(after[1], '-:$replacedText');
    expect(after[2], '-:');
  });

  test('skips a paragraph whose pPr holds a sectPr as the one to replace', () {
    final Uint8List doc = docxWithStyles(
      document:
          '<w:document xmlns:w="${Ns.w}"><w:body>'
          '<w:p><w:r><w:t>First</w:t></w:r></w:p>'
          '<w:p><w:r><w:t>Plain</w:t></w:r></w:p>'
          '<w:p><w:pPr><w:sectPr/></w:pPr><w:r><w:t>Break</w:t></w:r></w:p>'
          '</w:body></w:document>',
      styles: stylesXmlOf(<String>[]),
    );
    File('${input.path}/sect.docx').writeAsBytesSync(doc);
    final StringBuffer out = StringBuffer();
    expect(run(out: out), 0, reason: '$out');
    final List<String> after = outline(
      File('${output.path}/sect.docx').readAsBytesSync(),
    );
    expect(after[1], '-:$replacedText');
    expect(after[2], '-:Break');
  });

  test('a paragraph with proof marks is replaced like a plain one', () {
    final Uint8List doc = docxWithStyles(
      document:
          '<w:document xmlns:w="${Ns.w}"><w:body>'
          '<w:p><w:r><w:t>First</w:t></w:r></w:p>'
          '<w:p><w:proofErr w:type="spellStart"/><w:r><w:t>Plian</w:t></w:r>'
          '<w:proofErr w:type="spellEnd"/></w:p>'
          '</w:body></w:document>',
      styles: stylesXmlOf(<String>[]),
    );
    File('${input.path}/proof.docx').writeAsBytesSync(doc);
    final StringBuffer out = StringBuffer();
    expect(run(out: out), 0, reason: '$out');
    final List<String> after = outline(
      File('${output.path}/proof.docx').readAsBytesSync(),
    );
    expect(after[1], '-:$replacedText');
  });

  group('a document that has its styles and numbering', () {
    Uint8List both() {
      final DocxDocument doc = DocxDocument();
      doc.body.addParagraph('Start');
      doc.styles.ensure(DocxBuiltInStyle.heading1);
      doc.styles.ensure(DocxBuiltInStyle.listParagraph);
      doc.numbering.addBulletList();
      return doc.save().bytes;
    }

    String editWith(Uint8List Function(Uint8List) corrupt) {
      File('${input.path}/both.docx').writeAsBytesSync(both());
      final StringBuffer out = StringBuffer();
      final int code = editDocx(
        <String>[input.path, output.path],
        out: out,
        err: StringBuffer(),
        corruptForTest: corrupt,
      );
      expect(code, 1, reason: '$out');
      return out.toString();
    }

    test('is reported when a relationship of the main part changes', () {
      final String out = editWith(
        (Uint8List saved) => rewriteDocxPart(
          saved,
          'word/_rels/document.xml.rels',
          (String x) => x.replaceFirst(
            '</Relationships>',
            '<Relationship Id="rId99" Type="http://example.com/x" '
                'Target="x.xml"/></Relationships>',
          ),
        ),
      );
      expect(out, contains('a part outside the allowed set'));
      expect(out, contains('word/_rels/document.xml.rels'));
    });

    for (final (String name, String from, String to, String message)
        in <(String, String, String, String)>[
          ('removes the bold', '<w:b/>', '', 'the edited run is not bold'),
          (
            'changes the paragraph style',
            '<w:pStyle w:val="Heading1"/>',
            '<w:pStyle w:val="Normal"/>',
            'the added Heading1 paragraph is missing',
          ),
          (
            'changes the list number',
            '<w:numId w:val="2"/>',
            '<w:numId w:val="3"/>',
            'the list item "$firstItemText" is missing',
          ),
        ]) {
      test('is reported when the hook $name', () {
        final String out = editWith(
          (Uint8List saved) =>
              rewriteDocxPart(saved, 'word/document.xml', (String x) {
                expect(x, contains(from), reason: 'the hook finds $from');
                return x.replaceFirst(from, to);
              }),
        );
        expect(out, contains(message));
      });
    }
  });

  test('a truncated document is reported: exit 1', () {
    writeOnly(input, <String>{'d1_paragraphs.docx'});
    final File file = File('${input.path}/d1_paragraphs.docx');
    final Uint8List bytes = file.readAsBytesSync();
    file.writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
    final StringBuffer out = StringBuffer();
    expect(run(out: out), 1);
    expect(out.toString(), contains('d1_paragraphs.docx: the edit failed: '));
    expect(out.toString(), contains('1 of 1 documents failed.'));
  });

  test('unusable arguments or no document: exit 2', () {
    final StringBuffer err = StringBuffer();
    expect(editDocx(<String>['one'], out: StringBuffer(), err: err), 2);
    expect(err.toString(), contains('Usage:'));
    expect(
      editDocx(
        <String>['${temp.path}/missing', output.path],
        out: StringBuffer(),
        err: StringBuffer(),
      ),
      2,
    );
    expect(run(), 2);
  });
}
