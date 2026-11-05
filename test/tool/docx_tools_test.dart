// Tests the DOCX validation tools: tool/write_fixtures.dart's DOCX output,
// tool/compare_text.dart, tool/round_trip_docx.dart and
// tool/compare_resaved_docx.dart, their exit codes and their messages.
// LibreOffice is not run: its text export and re-save are stood in for by
// files the tests write. They read and write files, so they run on the VM
// only.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/compare_resaved_docx.dart';
import '../../tool/compare_text.dart';
import '../../tool/draft_expected_docx.dart';
import '../../tool/round_trip_docx.dart';
import '../../tool/src/text_compare.dart';
import '../../tool/write_fixtures.dart' as write_fixtures;
import '../docx/support/docx_builder.dart' show buildDocx, rewriteDocxPart;
import '../fixtures/docx_fixtures.dart';

void main() {
  late Directory temp;
  late Directory dir;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('docx_tools_test');
    dir = Directory('${temp.path}/fixtures')..createSync();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  List<String> names(Directory d) => <String>[
    for (final FileSystemEntity e in d.listSync()) e.uri.pathSegments.last,
  ]..sort();

  /// Writes every fixture (and the corrupt ones) to [d], then deletes all
  /// files but those named in [keep].
  void writeOnly(Directory d, Set<String> keep, {bool corrupt = false}) {
    write_fixtures.main(<String>[d.path, if (corrupt) '--corrupt']);
    for (final FileSystemEntity e in d.listSync()) {
      if (!keep.contains(e.uri.pathSegments.last)) e.deleteSync();
    }
  }

  /// What LibreOffice's text export of [docx] would hold if it read the
  /// text as the model does: a BOM, then every paragraph ending in `\n`.
  void exportText(File docx) {
    final String text = docxBodyText(DocxDocument.open(docx.readAsBytesSync()));
    File(
      docx.path.replaceFirst(RegExp(r'\.docx$'), '.txt'),
    ).writeAsStringSync('﻿$text\n');
  }

  group('write_fixtures', () {
    test('writes every D1 fixture as .docx with its .expected.txt', () {
      write_fixtures.main(<String>[dir.path]);
      final List<String> written = names(dir);
      for (final DocxFixture f in docxFixtures()) {
        expect(written, contains('${f.name}.docx'));
        expect(written, contains('${f.name}.expected.txt'));
        expect(
          File('${dir.path}/${f.name}.expected.txt').readAsStringSync(),
          '${f.expectedText}\n',
        );
        expect(
          File('${dir.path}/${f.name}.docx').readAsBytesSync(),
          f.build().bytes,
        );
      }
      expect(written, isNot(contains('d1_corrupt.docx')));
      expect(written, contains('m1_values.xlsx'));
    });

    test('writes what LibreOffice exports, only where it differs', () {
      write_fixtures.main(<String>[dir.path]);
      final List<String> written = names(dir);
      for (final DocxFixture f in docxFixtures()) {
        final String file = '${f.name}.libreoffice.txt';
        if (f.libreOfficeText == f.expectedText) {
          expect(written, isNot(contains(file)), reason: f.name);
        } else {
          expect(written, contains(file), reason: f.name);
          expect(
            File('${dir.path}/$file').readAsStringSync(),
            '${f.libreOfficeText}\n',
          );
        }
      }
      expect(written, contains('d2_lists.libreoffice.txt'));
    });

    test(
      '--corrupt adds d1_corrupt.docx: a stray run and a changed letter',
      () {
        write_fixtures.main(<String>[dir.path, '--corrupt']);
        expect(names(dir), contains('d1_corrupt.docx'));
        expect(names(dir), contains('m1_corrupt.xlsx'));
        final DocxFixture paragraphs = docxFixtures().singleWhere(
          (DocxFixture f) => f.name == 'd1_paragraphs',
        );
        expect(
          File('${dir.path}/d1_corrupt.expected.txt').readAsStringSync(),
          '${paragraphs.expectedText}\n',
        );
        final DocxDocument doc = DocxDocument.open(
          File('${dir.path}/d1_corrupt.docx').readAsBytesSync(),
        );
        expect(
          doc.body.blocks.whereType<DocxOpaqueBlock>().single.localName,
          'r',
        );
        expect(docxBodyText(doc), isNot(paragraphs.expectedText));
      },
    );
  });

  group('compare_text', () {
    test('equal exports: exit 0', () {
      writeOnly(dir, <String>{
        'd1_paragraphs.docx',
        'd1_paragraphs.expected.txt',
        'd1_text_rules.docx',
        'd1_text_rules.expected.txt',
      });
      exportText(File('${dir.path}/d1_paragraphs.docx'));
      exportText(File('${dir.path}/d1_text_rules.docx'));
      final StringBuffer out = StringBuffer();
      final StringBuffer err = StringBuffer();
      final int code = compareText(<String>[dir.path], out: out, err: err);
      expect(code, 0, reason: '$out$err');
      expect(out.toString(), contains('2 documents'));
    });

    test(
      'a fixture with list labels is compared with its LibreOffice text',
      () {
        writeOnly(dir, <String>{
          'd2_lists.docx',
          'd2_lists.expected.txt',
          'd2_lists.libreoffice.txt',
        });
        final DocxFixture lists = docxFixtures().singleWhere(
          (DocxFixture f) => f.name == 'd2_lists',
        );
        final File exported = File('${dir.path}/d2_lists.txt');
        exported.writeAsStringSync('\u{FEFF}${lists.libreOfficeText}\n');
        final StringBuffer out = StringBuffer();
        expect(
          compareText(<String>[dir.path], out: out, err: StringBuffer()),
          0,
          reason: '$out',
        );
        // The model's own text, without the labels, is not what LibreOffice
        // writes for it.
        exported.writeAsStringSync('\u{FEFF}${lists.expectedText}\n');
        final StringBuffer again = StringBuffer();
        expect(
          compareText(<String>[dir.path], out: again, err: StringBuffer()),
          1,
        );
        expect(again.toString(), contains('d2_lists: line 2: expected'));
      },
    );

    test('the corrupt document: exit 1 naming its changed line', () {
      writeOnly(dir, <String>{
        'd1_corrupt.docx',
        'd1_corrupt.expected.txt',
      }, corrupt: true);
      exportText(File('${dir.path}/d1_corrupt.docx'));
      final StringBuffer out = StringBuffer();
      final int code = compareText(
        <String>[dir.path],
        out: out,
        err: StringBuffer(),
      );
      expect(code, 1);
      expect(out.toString(), contains('d1_corrupt: line 1: expected'));
    });

    test('a missing export is a difference: exit 1', () {
      writeOnly(dir, <String>{'d1_blank.docx', 'd1_blank.expected.txt'});
      final StringBuffer out = StringBuffer();
      final int code = compareText(
        <String>[dir.path],
        out: out,
        err: StringBuffer(),
      );
      expect(code, 1);
      expect(out.toString(), contains('d1_blank: missing'));
    });

    test('unusable input: exit 2', () {
      expect(
        compareText(<String>[], out: StringBuffer(), err: StringBuffer()),
        2,
      );
      expect(
        compareText(
          <String>['${temp.path}/none'],
          out: StringBuffer(),
          err: StringBuffer(),
        ),
        2,
      );
      expect(
        compareText(
          <String>[dir.path],
          out: StringBuffer(),
          err: StringBuffer(),
        ),
        2,
        reason: 'no .expected.txt',
      );
    });
  });

  group('round_trip_docx', () {
    test('round-trips the D1 fixtures: exit 0 and their outputs', () {
      writeOnly(dir, <String>{'d1_paragraphs.docx', 'd1_unicode.docx'});
      final Directory output = Directory('${temp.path}/out');
      final StringBuffer out = StringBuffer();
      final StringBuffer err = StringBuffer();
      final int code = roundTripDocx(
        <String>[dir.path, output.path],
        out: out,
        err: err,
      );
      expect(code, 0, reason: '$out$err');
      expect(names(output), <String>['d1_paragraphs.docx', 'd1_unicode.docx']);
    });

    test('round-trips the D2 fixtures: exit 0 and their outputs', () {
      final Set<String> keep = <String>{
        for (final DocxFixture f in docxFixtures())
          if (f.name.startsWith('d2_')) '${f.name}.docx',
      };
      writeOnly(dir, keep);
      final Directory output = Directory('${temp.path}/out');
      final StringBuffer out = StringBuffer();
      final int code = roundTripDocx(
        <String>[dir.path, output.path],
        out: out,
        err: StringBuffer(),
      );
      expect(code, 0, reason: '$out');
      expect(names(output), keep.toList()..sort());
    });

    test('a styles part the model cannot read is refused with its name', () {
      writeOnly(dir, <String>{'d2_styles.docx'});
      final File file = File('${dir.path}/d2_styles.docx');
      file.writeAsBytesSync(
        rewriteDocxPart(
          file.readAsBytesSync(),
          'word/styles.xml',
          (String xml) => xml.replaceFirst('</w:styles>', '<w:style'),
        ),
      );
      final StringBuffer out = StringBuffer();
      final int code = roundTripDocx(
        <String>[dir.path, '${temp.path}/out'],
        out: out,
        err: StringBuffer(),
      );
      expect(code, 1);
      expect(out.toString(), contains('d2_styles.docx: '));
      expect(out.toString(), contains('word/styles.xml'));
    });

    test('skips Word lock files', () {
      writeOnly(dir, <String>{'d1_blank.docx'});
      File(
        '${dir.path}/~\$d1_blank.docx',
      ).writeAsBytesSync(utf8.encode('owner lock'));
      final Directory output = Directory('${temp.path}/out');
      final int code = roundTripDocx(
        <String>[dir.path, output.path],
        out: StringBuffer(),
        err: StringBuffer(),
      );
      expect(code, 0);
      expect(names(output), <String>['d1_blank.docx']);
    });

    test('the corrupt document keeps its fault, so validation rejects it', () {
      // The model keeps what it does not type: the stray run under w:body
      // comes back as written, so the round trip finds no difference and
      // the Open XML SDK step is what rejects the output.
      writeOnly(dir, <String>{'d1_corrupt.docx'}, corrupt: true);
      final Directory output = Directory('${temp.path}/out');
      final int code = roundTripDocx(
        <String>[dir.path, output.path],
        out: StringBuffer(),
        err: StringBuffer(),
      );
      expect(code, 0);
      expect(File('${output.path}/d1_corrupt.docx').existsSync(), isTrue);
    });

    test('a truncated document is refused: exit 1 and a message', () {
      writeOnly(dir, <String>{'d1_paragraphs.docx'});
      final File file = File('${dir.path}/d1_paragraphs.docx');
      final Uint8List bytes = file.readAsBytesSync();
      file.writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
      final StringBuffer out = StringBuffer();
      final int code = roundTripDocx(
        <String>[dir.path, '${temp.path}/out'],
        out: out,
        err: StringBuffer(),
      );
      expect(code, 1);
      expect(out.toString(), contains('d1_paragraphs.docx: '));
    });

    test('unusable arguments or no .docx: exit 2', () {
      expect(
        roundTripDocx(
          <String>[dir.path],
          out: StringBuffer(),
          err: StringBuffer(),
        ),
        2,
      );
      expect(
        roundTripDocx(
          <String>[dir.path, '${temp.path}/out'],
          out: StringBuffer(),
          err: StringBuffer(),
        ),
        2,
      );
    });
  });

  group('compare_resaved_docx', () {
    late Directory resaved;
    setUp(() => resaved = Directory('${temp.path}/resaved')..createSync());

    test('a re-save with the expected text: exit 0', () {
      writeOnly(dir, <String>{
        'd1_paragraphs.expected.txt',
        'd1_paragraphs.docx',
      });
      File(
        '${dir.path}/d1_paragraphs.docx',
      ).copySync('${resaved.path}/d1_paragraphs.docx');
      final StringBuffer out = StringBuffer();
      final StringBuffer err = StringBuffer();
      final int code = compareResavedDocx(
        <String>[dir.path, resaved.path],
        out: out,
        err: err,
      );
      expect(code, 0, reason: '$out$err');
    });

    test('a changed letter: exit 1 naming the line', () {
      writeOnly(dir, <String>{
        'd1_corrupt.expected.txt',
        'd1_corrupt.docx',
      }, corrupt: true);
      File(
        '${dir.path}/d1_corrupt.docx',
      ).copySync('${resaved.path}/d1_corrupt.docx');
      final StringBuffer out = StringBuffer();
      final int code = compareResavedDocx(
        <String>[dir.path, resaved.path],
        out: out,
        err: StringBuffer(),
      );
      expect(code, 1);
      expect(out.toString(), contains('d1_corrupt: line 1: expected'));
    });

    test('a warning on the re-save is a mismatch', () {
      writeOnly(dir, <String>{'d1_blank.expected.txt'});
      final Uint8List bytes = _withoutMainOverride(DocxDocument().save().bytes);
      File('${resaved.path}/d1_blank.docx').writeAsBytesSync(bytes);
      final StringBuffer out = StringBuffer();
      final int code = compareResavedDocx(
        <String>[dir.path, resaved.path],
        out: out,
        err: StringBuffer(),
      );
      expect(code, 1);
      expect(
        out.toString(),
        contains('d1_blank: warning mainPartContentTypeUnexpected'),
      );
    });

    test('a missing re-save is a mismatch; no expectations: exit 2', () {
      writeOnly(dir, <String>{'d1_blank.expected.txt'});
      final StringBuffer out = StringBuffer();
      expect(
        compareResavedDocx(
          <String>[dir.path, resaved.path],
          out: out,
          err: StringBuffer(),
        ),
        1,
      );
      expect(out.toString(), contains('d1_blank: missing'));
      expect(
        compareResavedDocx(
          <String>[resaved.path, resaved.path],
          out: StringBuffer(),
          err: StringBuffer(),
        ),
        2,
      );
      expect(
        compareResavedDocx(
          <String>[dir.path],
          out: StringBuffer(),
          err: StringBuffer(),
        ),
        2,
      );
    });
  });

  group('draft_expected_docx', () {
    test('drafts the body text, lists every block, refuses to overwrite', () {
      final File docx = File('${dir.path}/doc.docx')
        ..writeAsBytesSync(
          buildDocx(
            document:
                '<w:document xmlns:w="http://schemas.openxmlformats.org/'
                'wordprocessingml/2006/main"><w:body>'
                '<w:p><w:r><w:t>Title</w:t></w:r></w:p>'
                '<w:tbl/>'
                '<w:p><w:r><w:t>a</w:t><w:tab/><w:t>\u200Bb</w:t></w:r></w:p>'
                '</w:body></w:document>',
          ),
        );
      final StringBuffer out = StringBuffer();
      final StringBuffer err = StringBuffer();
      expect(
        draftExpectedDocx(<String>[docx.path], out: out, err: err),
        0,
        reason: '$err',
      );
      expect(
        File('${dir.path}/doc.expected.txt').readAsStringSync(),
        'Title\na\t\u200Bb\n',
      );
      expect(out.toString(), contains('   1  Title\n'));
      expect(out.toString(), contains('   2  [tbl: not in the text]\n'));
      expect(out.toString(), contains(r'   3  a\t\u{200b}b'));
      expect(
        draftExpectedDocx(
          <String>[docx.path],
          out: StringBuffer(),
          err: StringBuffer(),
        ),
        1,
      );
    });

    test('a usage error exits 64, a missing file 66', () {
      expect(
        draftExpectedDocx(<String>[], out: StringBuffer(), err: StringBuffer()),
        64,
      );
      expect(
        draftExpectedDocx(
          <String>['${dir.path}/none.docx'],
          out: StringBuffer(),
          err: StringBuffer(),
        ),
        66,
      );
    });
  });
}

/// [docx] with the content type override of its main part removed. A new
/// document declares `xml` as `application/xml`, so the model reports
/// `mainPartContentTypeUnexpected` when it opens the result.
Uint8List _withoutMainOverride(Uint8List docx) =>
    rewriteDocxPart(docx, '[Content_Types].xml', (String xml) {
      return xml.replaceFirst(
        RegExp(r'<Override PartName="/word/document.xml"[^>]*/>'),
        '',
      );
    });
