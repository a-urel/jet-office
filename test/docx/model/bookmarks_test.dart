// Tests bookmarks: the marks of a file read as typed inlines (a block-level
// one stays opaque, a broken id reads null, every mark is written as read),
// the marks the API builds (an id per save shared by start and end, unique
// against the file's, a name repaired and reported by every save), and undo.
// They build documents in memory, so they run on the web as well.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart'
    show changeLogOf, editsOf;
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

import '../../support/read_xlsx.dart';
import '../support/docx_builder.dart';

const String _decls = 'xmlns:w="${Ns.w}"';

String _main(String body) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document $_decls><w:body>$body</w:body></w:document>';

DocxDocument _open(String body) =>
    DocxDocument.open(buildDocx(document: _main(body)));

String _savedMain(DocxDocument doc) => utf8.decode(
  readXlsxBytes(Uint8List.fromList(doc.save().bytes))['word/document.xml']!,
);

List<DocxWarning> _repairs(DocxDocument doc) => doc
    .save()
    .warnings
    .where((DocxWarning w) => w.code == DocxWarningCode.bookmarkNameRepaired)
    .toList();

/// The ids of every `w:bookmarkStart` and `w:bookmarkEnd` of [xml] with the
/// element name.
List<String> _marks(String xml) => RegExp(
  r'<w:(bookmarkStart|bookmarkEnd)[^>]*w:id="([^"]*)"',
).allMatches(xml).map((Match m) => '${m[1]}:${m[2]}').toList();

void main() {
  group('reading', () {
    const String sample =
        '<w:p><w:r><w:t>a</w:t></w:r>'
        '<w:bookmarkStart w:id="3" w:name="Total"/><w:r><w:t>b</w:t></w:r>'
        '<w:bookmarkEnd w:id="3"/></w:p>';

    test('a start and an end read typed, the text unchanged', () {
      final DocxParagraph p = _open(sample).body.blocks.single as DocxParagraph;
      expect(
        p.inlines.map((DocxInline i) => i.runtimeType.toString()),
        <String>['DocxRun', 'DocxBookmarkStart', 'DocxRun', 'DocxBookmarkEnd'],
      );
      final DocxBookmarkStart start = p.inlines[1] as DocxBookmarkStart;
      final DocxBookmarkEnd end = p.inlines[3] as DocxBookmarkEnd;
      expect(start.id, 3);
      expect(start.name, 'Total');
      expect(end.id, 3);
      expect(end.start, isNull);
      expect(p.text, 'ab');
    });

    test('a block-level bookmark stays an opaque block', () {
      final DocxDocument doc = _open(
        '<w:bookmarkStart w:id="1" w:name="B"/>$sample'
        '<w:bookmarkEnd w:id="1"/>',
      );
      expect(doc.body.blocks.first, isA<DocxOpaqueBlock>());
      expect(doc.body.blocks.last, isA<DocxOpaqueBlock>());
    });

    test('a bad id reads null, an absent name reads empty, both as read', () {
      const String body =
          '<w:p><w:bookmarkStart w:id="x" w:name="N" w:colFirst="1"/>'
          '<w:bookmarkStart w:id="-4"/><w:bookmarkEnd/></w:p>';
      final DocxDocument doc = _open(body);
      final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
      final DocxBookmarkStart a = p.inlines[0] as DocxBookmarkStart;
      final DocxBookmarkStart b = p.inlines[1] as DocxBookmarkStart;
      expect(a.id, isNull);
      expect(a.name, 'N');
      expect(b.id, isNull);
      expect(b.name, '');
      expect((p.inlines[2] as DocxBookmarkEnd).id, isNull);
      // An edit elsewhere re-encodes the part; the marks come out as read.
      doc.body.addParagraph();
      expect(_savedMain(doc), contains(body));
    });

    test('a bookmark inside a field is kept in place', () {
      const String body =
          '<w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r>'
          '<w:bookmarkStart w:id="1" w:name="B"/>'
          '<w:r><w:instrText> PAGE </w:instrText></w:r>'
          '<w:bookmarkEnd w:id="1"/>'
          '<w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>';
      final DocxDocument doc = _open(body);
      doc.body.addParagraph();
      expect(_savedMain(doc), contains(body));
    });
  });

  group('building', () {
    test('a start and an end in the next paragraph share one id', () {
      final DocxDocument doc = _open(
        '<w:p><w:bookmarkStart w:id="4" w:name="Old"/>'
        '<w:bookmarkEnd w:id="4"/></w:p>',
      );
      final DocxParagraph one = doc.body.addParagraph();
      final DocxBookmarkStart start = one.addBookmarkStart('Total');
      final DocxParagraph two = doc.body.addParagraph();
      final DocxBookmarkEnd end = two.addBookmarkEnd(start);
      expect(start.id, isNull);
      expect(end.id, isNull);
      expect(end.start, same(start));
      final String xml = _savedMain(doc);
      expect(xml, contains('<w:bookmarkStart w:id="5" w:name="Total"/>'));
      expect(_marks(xml), <String>[
        'bookmarkStart:4',
        'bookmarkEnd:4',
        'bookmarkStart:5',
        'bookmarkEnd:5',
      ]);
      // Nothing is stored back: the model still holds no id.
      expect(start.id, isNull);
      expect(doc.save().warnings, isEmpty);
    });

    test('an end written before its start in the document pairs with it', () {
      final DocxDocument doc = DocxDocument();
      final DocxParagraph first = doc.body.addParagraph();
      final DocxParagraph second = doc.body.addParagraph();
      final DocxBookmarkStart start = second.addBookmarkStart('Later');
      first.addBookmarkEnd(start);
      expect(_marks(_savedMain(doc)), <String>[
        'bookmarkEnd:0',
        'bookmarkStart:0',
      ]);
    });

    test('two bookmarks get two ids, an end of a read start its id', () {
      final DocxDocument doc = _open(
        '<w:p><w:bookmarkStart w:id="9" w:name="Read"/></w:p>',
      );
      final DocxParagraph p = doc.body.addParagraph();
      final DocxBookmarkStart a = p.addBookmarkStart('A');
      final DocxBookmarkStart b = p.addBookmarkStart('B');
      p
        ..addBookmarkEnd(b)
        ..addBookmarkEnd(a)
        ..addBookmarkEnd(doc.body.blocks.first.asParagraphStart);
      expect(_marks(_savedMain(doc)), <String>[
        'bookmarkStart:9',
        'bookmarkStart:10',
        'bookmarkStart:11',
        'bookmarkEnd:11',
        'bookmarkEnd:10',
        'bookmarkEnd:9',
      ]);
    });

    test('a name is repaired, cut, and reported by every save', () {
      final DocxDocument doc = DocxDocument();
      final DocxParagraph p = doc.body.addParagraph();
      final DocxBookmarkStart start = p.addBookmarkStart('2 Totals!');
      final DocxBookmarkStart long = p.addBookmarkStart('a' * 50);
      expect(start.name, 'B2_Totals_');
      expect(long.name, 'a' * 40);
      expect(_savedMain(doc), contains('w:name="B2_Totals_"'));
      for (int i = 0; i < 2; i++) {
        final List<DocxWarning> repairs = _repairs(doc);
        expect(repairs, hasLength(2));
        expect(repairs[0].detail, '2 Totals!');
        expect(repairs[0].part, '/word/document.xml');
        expect(repairs[0].locations, <String>['body/p[1]']);
        expect(repairs[1].detail, 'a' * 50);
      }
    });

    test('a name that follows the rules is not reported', () {
      final DocxDocument doc = DocxDocument();
      doc.body.addParagraph().addBookmarkStart('Total_2');
      expect(_repairs(doc), isEmpty);
    });

    test('repairBookmarkName', () {
      expect(repairBookmarkName('Total'), 'Total');
      expect(repairBookmarkName('2 Totals!'), 'B2_Totals_');
      expect(repairBookmarkName('_Hidden'), 'B_Hidden');
      expect(repairBookmarkName(''), 'B');
      expect(repairBookmarkName('Şube Özet'), 'Şube_Özet');
      expect(repairBookmarkName('x' * 41), 'x' * 40);
      expect(repairBookmarkName('1${'x' * 45}'), 'B1${'x' * 38}');
    });

    test('a built mark belongs to a document that holds its id elsewhere', () {
      final DocxDocument doc = DocxDocument();
      doc.body.addParagraph().addBookmarkStart('A');
      // A second save does not drift: ids come per save.
      expect(_marks(_savedMain(doc)), <String>['bookmarkStart:0']);
      expect(_marks(_savedMain(doc)), <String>['bookmarkStart:0']);
    });

    test('undo removes both marks, redo puts them back', () {
      final DocxDocument doc = DocxDocument();
      final String before = _savedMain(doc);
      final ChangeSet set = editsOf(doc).transaction(() {
        final DocxParagraph p = doc.body.addParagraph();
        p.addBookmarkEnd(p.addBookmarkStart('Total'));
      });
      expect(_marks(_savedMain(doc)), hasLength(2));
      changeLogOf(doc).revertSet(set);
      expect(_savedMain(doc), before);
      expect(_repairs(doc), isEmpty);
      changeLogOf(doc).reapplySet(set);
      expect(_marks(_savedMain(doc)), <String>[
        'bookmarkStart:0',
        'bookmarkEnd:0',
      ]);
    });

    test('a mark sits in one paragraph once, and goes with removeInlineAt', () {
      final DocxDocument doc = DocxDocument();
      final DocxParagraph p = doc.body.addParagraph();
      final DocxBookmarkStart start = p.addBookmarkStart('A');
      expect(
        () => doc.body.addParagraph().insertInline(0, start),
        throwsStateError,
      );
      p.removeInlineAt(0);
      expect(_marks(_savedMain(doc)), isEmpty);
    });
  });
}

extension on DocxBlock {
  DocxBookmarkStart get asParagraphStart =>
      (this as DocxParagraph).inlines.single as DocxBookmarkStart;
}
