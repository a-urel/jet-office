// Tests tool/edit_docx.dart: the model edits every document of a directory
// (a run's text, a replaced paragraph, an added heading) for the Open XML
// SDK to validate. It reads and writes files, so it runs on the VM only.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/edit_docx.dart';
import '../../tool/write_fixtures.dart' as write_fixtures;
import '../docx/support/docx_builder.dart' show rewriteDocxPart;
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

  test('a Word-like document gets the three edits, and only document.xml '
      'changes', () {
    File('${input.path}/word.docx').writeAsBytesSync(richWordDocx());
    final StringBuffer out = StringBuffer();
    expect(run(out: out), 0, reason: '$out');
    final List<String> before = outline(richWordDocx());
    final List<String> after = outline(
      File('${output.path}/word.docx').readAsBytesSync(),
    );
    expect(after, hasLength(before.length + 1));
    // The first run with text is the title's.
    expect(before.first, 'Title:Fiyat listesiÜrün ');
    expect(after.first, 'Title:$editedTextÜrün ');
    // The last all-runs paragraph is the empty one after the table.
    expect(before[10], '-:');
    expect(after[10], '-:$replacedText');
    // No styles part, so the added paragraph is Normal.
    expect(after.last, 'Normal:$addedText');
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
    expect(
      outline(File('${output.path}/d1_paragraphs.docx').readAsBytesSync()).last,
      'Heading1:$addedText',
    );
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
