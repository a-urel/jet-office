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
        DocxTable() => 'table',
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
    expect(after, hasLength(before.length + 4));
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
    // The appended table comes before the heading and the list.
    expect(after[after.length - 4], 'table');
  });

  group('sections', () {
    DocxDocument edited(String name) =>
        DocxDocument.open(File('${output.path}/$name').readAsBytesSync());

    /// The text of [story] with each field's instruction in place of its
    /// result, as the last paragraph holds them.
    List<String> lastParagraph(DocxHeaderFooter story) => <String>[
      for (final DocxInline i in (story.blocks.last as DocxParagraph).inlines)
        i is DocxField ? i.instruction : (i as DocxRun).text,
    ];

    const List<String> footer = <String>[
      footerPageText,
      ' PAGE ',
      footerOfText,
      ' NUMPAGES ',
    ];

    test(
      'a new footer goes in a new part, and the new section inherits it',
      () {
        writeOnly(input, <String>{'d1_paragraphs.docx'});
        final StringBuffer out = StringBuffer();
        expect(run(out: out), 0, reason: '$out');
        final DocxDocument doc = edited('d1_paragraphs.docx');
        expect(doc.sections, hasLength(2));
        expect(doc.sections.first.footer.isInherited, isFalse);
        expect(lastParagraph(doc.sections.first.footer), footer);
        expect(doc.sections.last.footer.isInherited, isTrue);
        expect(lastParagraph(doc.sections.last.footer), footer);
      },
    );

    test('the footer goes at the end of the story the last section has', () {
      writeOnly(input, <String>{'d4_headers.docx'});
      final StringBuffer out = StringBuffer();
      expect(run(out: out), 0, reason: '$out');
      final DocxDocument doc = edited('d4_headers.docx');
      expect(doc.sections, hasLength(4));
      final DocxHeaderFooter story = doc.sections[2].footer;
      expect((story.blocks.first as DocxParagraph).text, 'Footer three');
      expect(story.blocks, hasLength(2));
      expect(lastParagraph(story), footer);
      // Section one's is another story, which the edit left alone.
      expect(doc.sections.first.footer.blocks, hasLength(1));
    });

    test('an inherited footer is edited where it lives', () {
      final DocxDocument source = DocxDocument();
      source.body.addParagraph('One');
      source.sections.last.footer.addParagraph('Shared');
      source.body.addSection();
      source.body.addParagraph('Two');
      File('${input.path}/s.docx').writeAsBytesSync(source.save().bytes);
      final StringBuffer out = StringBuffer();
      expect(run(out: out), 0, reason: '$out');
      final DocxDocument doc = edited('s.docx');
      expect(doc.sections.first.footer.blocks, hasLength(2));
      expect(lastParagraph(doc.sections.first.footer), footer);
    });

    test('the new last section is landscape A4, and starts on a new page', () {
      writeOnly(input, <String>{'d4_sections.docx'});
      final StringBuffer out = StringBuffer();
      expect(run(out: out), 0, reason: '$out');
      final DocxDocument doc = edited('d4_sections.docx');
      expect(doc.sections, hasLength(5));
      expect(doc.sections.last.pageSize, DocxPageSize.a4(landscape: true));
      expect(doc.sections.last.start, DocxSectionStart.nextPage);
      expect(doc.sections[3].pageSize, DocxPageSize.letter());
    });

    test('the table, the heading and the list follow the break', () {
      writeOnly(input, <String>{'d1_paragraphs.docx'});
      expect(run(), 0);
      final DocxDocument doc = edited('d1_paragraphs.docx');
      final List<DocxBlock> blocks = doc.body.blocks;
      // The last paragraph took the break, so there are four blocks more.
      expect(blocks, hasLength(9));
      expect((blocks[4] as DocxParagraph).section, same(doc.sections.first));
      expect(blocks[5], isA<DocxTable>());
      for (final DocxParagraph b in blocks.skip(5).whereType<DocxParagraph>()) {
        expect(b.section, isNull);
      }
    });

    test('the added table shares the width of the landscape page', () {
      writeOnly(input, <String>{'d1_paragraphs.docx'});
      expect(run(), 0);
      final DocxDocument doc = edited('d1_paragraphs.docx');
      // 16838 twips, less 2 x 1417 of margin and 10, shared by two columns.
      expect(doc.sections.last.textWidthPt, 700.2);
      expect(
        doc.body.blocks.whereType<DocxTable>().last.gridColumnsPt,
        <double>[349.85, 349.85],
      );
    });

    test('a body that ends in a table gets a paragraph for the break', () {
      final DocxDocument source = DocxDocument();
      source.body.addTable(columns: 1).addRow(<String?>['Last']);
      File('${input.path}/t.docx').writeAsBytesSync(source.save().bytes);
      final StringBuffer out = StringBuffer();
      expect(run(out: out), 0, reason: '$out');
      final DocxDocument doc = edited('t.docx');
      final List<DocxBlock> blocks = doc.body.blocks;
      // The source's two blocks, the paragraph of the break and four more.
      expect(blocks, hasLength(7));
      expect((blocks[2] as DocxParagraph).section, same(doc.sections.first));
      expect((blocks[2] as DocxParagraph).text, '');
    });

    test('a body whose last block holds a break gets one too', () {
      final DocxDocument source = DocxDocument();
      source.body.addParagraph('Text');
      source.body.addSection();
      File('${input.path}/b.docx').writeAsBytesSync(source.save().bytes);
      final StringBuffer out = StringBuffer();
      expect(run(out: out), 0, reason: '$out');
      expect(edited('b.docx').sections, hasLength(3));
    });

    test('a new footer may add its part, content type and relationship', () {
      writeOnly(input, <String>{'d1_paragraphs.docx'});
      expect(run(), 0);
      final Archive before = ZipDecoder().decodeBytes(
        File('${input.path}/d1_paragraphs.docx').readAsBytesSync(),
      );
      final Archive after = ZipDecoder().decodeBytes(
        File('${output.path}/d1_paragraphs.docx').readAsBytesSync(),
      );
      expect(before.findFile('word/footer1.xml'), isNull);
      expect(after.findFile('word/footer1.xml'), isNotNull);
    });

    String corrupted(
      String fixture,
      String part,
      String Function(String) rewrite,
    ) {
      writeOnly(input, <String>{fixture});
      final StringBuffer out = StringBuffer();
      final int code = editDocx(
        <String>[input.path, output.path],
        out: out,
        err: StringBuffer(),
        corruptForTest: (Uint8List saved) =>
            rewriteDocxPart(saved, part, rewrite),
      );
      expect(code, 1, reason: '$out');
      return out.toString();
    }

    test('reports a footer that does not read back', () {
      expect(
        corrupted(
          'd1_paragraphs.docx',
          'word/footer1.xml',
          (String x) => x.replaceFirst(' NUMPAGES ', ' PAGE '),
        ),
        contains('the footer of the last section is missing'),
      );
    });

    test('reports a new section that is not landscape', () {
      expect(
        corrupted(
          'd1_paragraphs.docx',
          'word/document.xml',
          (String x) => x.replaceFirst(' w:orient="landscape"', ''),
        ),
        contains('the new section is not landscape A4'),
      );
    });

    test('reports a section break that does not read back', () {
      expect(
        corrupted(
          'd1_paragraphs.docx',
          'word/document.xml',
          (String x) => x.replaceFirst(RegExp(r'<w:sectPr.*?</w:sectPr>'), ''),
        ),
        contains('sections, not 2'),
      );
    });

    test('reports a table that does not take the width of the section', () {
      expect(
        corrupted(
          'd1_paragraphs.docx',
          'word/document.xml',
          (String x) => x.replaceAll('w:w="6997"', 'w:w="4531"'),
        ),
        contains('the added table is not as wide as the section'),
      );
    });

    test('reports a second footer part that changes', () {
      expect(
        corrupted(
          'd4_headers.docx',
          'word/footer1.xml',
          (String x) => x.replaceFirst('Footer one', 'Changed'),
        ),
        contains('more than one footer part changed'),
      );
    });
  });

  group('tables', () {
    List<DocxBlock> edited(String name) => DocxDocument.open(
      File('${output.path}/$name').readAsBytesSync(),
    ).body.blocks;

    test('every fixture is edited, and the appended table is as built', () {
      write_fixtures.main(<String>[input.path]);
      final StringBuffer out = StringBuffer();
      expect(run(out: out), 0, reason: '$out');
      for (final FileSystemEntity e in output.listSync()) {
        final String name = e.uri.pathSegments.last;
        final List<DocxBlock> blocks = edited(name);
        final DocxTable table = blocks[blocks.length - 4] as DocxTable;
        expect(table.rows, hasLength(3), reason: name);
        expect(table.rows[0].isHeader, isTrue, reason: name);
        expect(table.rows[0].cells.map((DocxTableCell c) => c.text), <String>[
          'Head one',
          'Head two',
        ]);
        expect(table.rows[2].cells, hasLength(1), reason: name);
        expect(table.rows[2].cells.single.properties.gridSpan, 2);
      }
    });

    test('a table of a document takes the cell text and a new row', () {
      writeOnly(input, <String>{'d3_basic.docx', 'd3_merges.docx'});
      final StringBuffer out = StringBuffer();
      expect(run(out: out), 0, reason: '$out');
      for (final String name in <String>['d3_basic.docx', 'd3_merges.docx']) {
        final DocxTable before = DocxDocument.open(
          File('${input.path}/$name').readAsBytesSync(),
        ).body.blocks.whereType<DocxTable>().first;
        final DocxTable table = edited(name).whereType<DocxTable>().first;
        expect(
          (table.rows[0].cells[0].blocks.first as DocxParagraph).text,
          editedCellText,
          reason: name,
        );
        expect(table.rows, hasLength(before.rows.length + 1), reason: name);
        expect(table.rows.last.cells.first.text, newRowText, reason: name);
      }
    });

    test('reports a cell edit that does not read back', () {
      writeOnly(input, <String>{'d3_basic.docx'});
      final StringBuffer out = StringBuffer();
      final int code = editDocx(
        <String>[input.path, output.path],
        out: out,
        err: StringBuffer(),
        corruptForTest: (Uint8List saved) => rewriteDocxPart(
          saved,
          'word/document.xml',
          (String x) => x.replaceFirst(editedCellText, 'Not edited'),
        ),
      );
      expect(code, 1);
      expect(out.toString(), contains('the edited cell text is missing'));
    });
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

  group('a document that has its styles, numbering and a footer', () {
    Uint8List both() {
      final DocxDocument doc = DocxDocument();
      doc.body.addParagraph('Start');
      doc.styles.ensure(DocxBuiltInStyle.heading1);
      doc.styles.ensure(DocxBuiltInStyle.listParagraph);
      doc.numbering.addBulletList();
      doc.sections.last.footer.addParagraph('Foot');
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
