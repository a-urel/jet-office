// Tests the internal edit primitives the template fill edits through
// (`setRunContent`, `copyRunWithText`, `runOfSimpleField`, `removeHeldInline`,
// `replaceHeldInline`) and the document hooks it uses (`documentTransaction`,
// `newDocxResult`, `storyPartNameOf`, `docxPackageOf`): each edit is one
// recorded change, undone with the transaction's set, an inline of a
// hyperlink is edited in place, and a transaction that throws leaves the
// document as it was. They build documents in memory, so they run on the web
// as well.
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart'
    show
        changeLogOf,
        docxPackageOf,
        documentTransaction,
        newDocxResult,
        storyPartNameOf;
import 'package:jet_office/src/docx/model/inlines.dart'
    show
        copyRunWithText,
        removeHeldInline,
        removedCharactersOf,
        replaceHeldInline,
        runOfSimpleField,
        setRunContent;
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

import '../../fixtures/docx_fixtures.dart';
import '../support/docx_builder.dart';
import '../support/styles_documents.dart' show readDocxText;

const String _decls = 'xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}"';

/// A paragraph of runs `a`, `b` (bold) and a hyperlink of `c` and `d`, then a
/// paragraph holding a `MERGEFIELD` as a `w:fldSimple` with an italic run.
const String _body =
    '<w:p>'
    '<w:r w:rsidR="00AB12CD"><w:t>a</w:t></w:r>'
    '<w:r w:rsidR="00EF3456"><w:rPr><w:b/></w:rPr><w:t>b</w:t></w:r>'
    '<w:hyperlink w:anchor="target">'
    '<w:r><w:t>c</w:t></w:r><w:r><w:t>d</w:t></w:r>'
    '</w:hyperlink>'
    '</w:p>'
    '<w:p><w:fldSimple w:instr=" MERGEFIELD Ad ">'
    '<w:r><w:rPr><w:i/></w:rPr><w:t>«Ad»</w:t></w:r>'
    '</w:fldSimple></w:p>'
    '<w:p><w:fldSimple w:instr=" PAGE "/></w:p>';

Uint8List _bytes() => buildDocx(
  document:
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document $_decls><w:body>$_body</w:body></w:document>',
);

/// The paragraph at [index] of [document]'s body.
DocxParagraph _p(DocxDocument document, int index) =>
    document.body.blocks[index] as DocxParagraph;

void main() {
  late DocxDocument doc;
  late DocxParagraph paragraph;
  late DocxRun r0;
  late DocxRun r1;
  late DocxHyperlink link;
  late DocxRun r2;
  late DocxRun r3;

  setUp(() {
    doc = DocxDocument.open(_bytes());
    paragraph = _p(doc, 0);
    r0 = paragraph.inlines[0] as DocxRun;
    r1 = paragraph.inlines[1] as DocxRun;
    link = paragraph.inlines[2] as DocxHyperlink;
    r2 = link.inlines[0] as DocxRun;
    r3 = link.inlines[1] as DocxRun;
  });

  String mainXml(Uint8List bytes) => readDocxText(bytes)['word/document.xml']!;

  group('setRunContent', () {
    test('splits the text, and the set undoes it', () {
      final ChangeSet set = documentTransaction(
        doc,
        () => setRunContent(r1, const <DocxRunContent>[], 'x\ty\nz', const []),
      );
      expect(r1.content, <DocxRunContent>[
        const DocxText('x'),
        const DocxTab(),
        const DocxText('y'),
        const DocxBreak(),
        const DocxText('z'),
      ]);
      expect(set.changes, hasLength(1));
      changeLogOf(doc).undo(set);
      expect(r1.content, <DocxRunContent>[const DocxText('b')]);
    });

    test('puts the content before and after around the text', () {
      setRunContent(
        r2,
        <DocxRunContent>[const DocxTab()],
        'v',
        <DocxRunContent>[const DocxText('w')],
      );
      expect(r2.content, <DocxRunContent>[
        const DocxTab(),
        const DocxText('v'),
        const DocxText('w'),
      ]);
      expect(link.text, '\tvwd');
    });

    test('scrubs the text and counts what it removed', () {
      setRunContent(r0, const <DocxRunContent>[], 'p\u0001q', const []);
      expect(r0.text, 'pq');
      expect(removedCharactersOf(r0), 1);
      final DocxResult result = doc.save();
      expect(
        result.warnings.map((DocxWarning w) => w.code),
        contains(DocxWarningCode.invalidCharactersRemoved),
      );
    });

    test('records nothing when the content stays the same', () {
      final ChangeSet set = documentTransaction(
        doc,
        () => setRunContent(r1, const <DocxRunContent>[], 'b', const []),
      );
      expect(set.changes, isEmpty);
    });
  });

  group('copyRunWithText', () {
    test('copies the run properties, without the run attributes', () {
      final DocxRun copy = copyRunWithText(r1, 'v');
      expect(copy.properties.bold, isTrue);
      expect(copy.text, 'v');
      replaceHeldInline(r0, copy);
      final String xml = mainXml(doc.save().bytes);
      expect(xml, contains('<w:r><w:rPr><w:b/></w:rPr><w:t>v</w:t></w:r>'));
      expect(xml, isNot(contains('00AB12CD')));
    });

    test('takes values set through the API', () {
      r1.properties.italic = true;
      final DocxRun copy = copyRunWithText(r1, 'v');
      expect(copy.properties.bold, isTrue);
      expect(copy.properties.italic, isTrue);
      r1.properties.italic = false;
      expect(copy.properties.italic, isTrue);
    });

    test('belongs to no paragraph', () {
      final DocxRun copy = copyRunWithText(r2, 'v');
      paragraph.insertInline(0, copy);
      expect(paragraph.text, 'vabcd');
    });
  });

  group('removeHeldInline', () {
    test('removes a run of a hyperlink, and the set undoes it', () {
      final ChangeSet set = documentTransaction(
        doc,
        () => removeHeldInline(r3),
      );
      expect(link.inlines, <DocxInline>[r2]);
      expect(set.changes, hasLength(1));
      final String saved = mainXml(doc.save().bytes);
      final String hyperlink = RegExp(
        '<w:hyperlink[^>]*>(.*)</w:hyperlink>',
      ).firstMatch(saved)![1]!;
      expect(RegExp('<w:r>').allMatches(hyperlink), hasLength(1));
      changeLogOf(doc).undo(set);
      expect(link.inlines, <DocxInline>[r2, r3]);
      expect(paragraph.text, 'abcd');
      // The run is back in its paragraph: it reports there again.
      r3.text = 'e';
      expect(paragraph.text, 'abce');
    });

    test('removes a run of the paragraph', () {
      removeHeldInline(r0);
      expect(paragraph.inlines, hasLength(2));
      expect(paragraph.text, 'bcd');
    });

    test('throws for an inline in no paragraph or in a field', () {
      expect(() => removeHeldInline(DocxRun('x')), throwsStateError);
      final DocxField field = DocxField(' PAGE ', result: '1');
      paragraph.insertInline(0, field);
      expect(() => removeHeldInline(field.result.first), throwsStateError);
      removeHeldInline(r3);
      expect(() => removeHeldInline(r3), throwsStateError);
    });
  });

  group('replaceHeldInline', () {
    test('replaces a run of the paragraph', () {
      replaceHeldInline(r0, DocxRun('n'));
      final DocxDocument reopened = DocxDocument.open(doc.save().bytes);
      expect(_p(reopened, 0).text, 'nbcd');
    });

    test('replaces a run of a hyperlink, and the set undoes it', () {
      final DocxRun n = DocxRun('n');
      final ChangeSet set = documentTransaction(
        doc,
        () => replaceHeldInline(r2, n),
      );
      expect(set.changes, hasLength(1));
      expect(link.inlines, <DocxInline>[n, r3]);
      expect(paragraph.text, 'abnd');
      changeLogOf(doc).undo(set);
      expect(link.inlines, <DocxInline>[r2, r3]);
      expect(paragraph.text, 'abcd');
      // The run taken out stays the hyperlink's: it can go nowhere else.
      expect(() => paragraph.insertInline(0, n), throwsStateError);
    });

    test('a run put in a hyperlink reports there and saves there', () {
      final DocxRun n = DocxRun('n');
      replaceHeldInline(r2, n);
      final ChangeSet set = documentTransaction(doc, () => n.text = 'm');
      expect(set.changes, hasLength(1));
      expect(paragraph.text, 'abmd');
      final DocxDocument reopened = DocxDocument.open(doc.save().bytes);
      final DocxHyperlink saved = _p(reopened, 0).inlines[2] as DocxHyperlink;
      expect(saved.anchor, 'target');
      expect(saved.text, 'md');
    });

    test('throws for a replacement that is held, before anything changes', () {
      expect(() => replaceHeldInline(r0, r2), throwsStateError);
      expect(
        () => replaceHeldInline(DocxRun('x'), DocxRun('y')),
        throwsStateError,
      );
      expect(paragraph.text, 'abcd');
    });
  });

  group('runOfSimpleField', () {
    test('takes the properties of the first run inside', () {
      final DocxOpaqueInline field =
          _p(doc, 1).inlines.single as DocxOpaqueInline;
      expect(field.localName, 'fldSimple');
      final DocxRun run = runOfSimpleField(field, 'Ayşe');
      expect(run.properties.italic, isTrue);
      expect(run.text, 'Ayşe');
    });

    test('gives a run of no properties for a field of no run', () {
      final DocxOpaqueInline field =
          _p(doc, 2).inlines.single as DocxOpaqueInline;
      final DocxRun run = runOfSimpleField(field, '7');
      expect(run.properties.italic, isNull);
      replaceHeldInline(field, run);
      expect(mainXml(doc.save().bytes), contains('<w:p><w:r><w:t>7</w:t>'));
    });
  });

  group('documentTransaction', () {
    test('a body that throws leaves the document as it was', () {
      expect(
        () => documentTransaction(doc, () {
          setRunContent(r0, const <DocxRunContent>[], 'x', const []);
          removeHeldInline(r3);
          throw StateError('stop');
        }),
        throwsStateError,
      );
      expect(paragraph.text, 'abcd');
      expect(link.inlines, <DocxInline>[r2, r3]);
    });
  });

  group('the document hooks', () {
    test('storyPartNameOf names the part of a story, or none', () {
      final DocxDocument headers = DocxDocument.open(
        docxFixtures()
            .singleWhere((DocxFixture f) => f.name == 'd4_headers')
            .build()
            .bytes,
      );
      expect(
        storyPartNameOf(headers.sections.first.header),
        '/word/header1.xml',
      );
      expect(storyPartNameOf(DocxDocument().sections.first.header), isNull);
    });

    test('newDocxResult and docxPackageOf', () {
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2]);
      final DocxResult result = newDocxResult(bytes, const <DocxWarning>[]);
      expect(result.bytes, same(bytes));
      expect(result.warnings, isEmpty);
      expect(docxPackageOf(doc).mainPart, '/word/document.xml');
    });
  });
}
