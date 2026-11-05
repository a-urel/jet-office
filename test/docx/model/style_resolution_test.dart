// Tests how a style id set through the API finds its style: by the id the
// document defines, by the name of a built-in style under a localized id, or
// by adding Word's definition (plan Rulings 5, 6 and 8). The documents are
// built in memory, so these tests run on the web as well.
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart';
import 'package:jet_office/src/docx/model/primitives.dart' show DocxEdits;
import 'package:jet_office/src/opc/change_log.dart' show ChangeSet;
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:test/test.dart';

import '../support/docx_builder.dart';
import '../support/localized_document.dart';
import '../support/styles_documents.dart';

DocxDocument _localized() => DocxDocument.open(localizedWordDocx());

DocxDocument _german() => DocxDocument.open(germanStyleDocx());

/// A document without a styles part.
DocxDocument _withoutStyles() => DocxDocument.open(buildDocx());

/// Every style id of [doc], in document order.
List<String?> _ids(DocxDocument doc) => <String?>[
  for (final DocxStyle s in doc.styles.styles) s.id,
];

/// The `styles.xml` [doc] saves.
String _savedStyles(DocxDocument doc) =>
    readDocxText(doc.save().bytes)['word/styles.xml']!;

/// The warnings of [code] that saving [doc] gives.
List<DocxWarning> _warnings(DocxDocument doc, DocxWarningCode code) =>
    <DocxWarning>[
      for (final DocxWarning w in doc.save().warnings)
        if (w.code == code) w,
    ];

void _expectNamesUnique(DocxDocument doc) {
  final List<String> names = <String>[
    for (final DocxStyle s in doc.styles.styles) s.name!.toLowerCase(),
  ];
  expect(names.toSet(), hasLength(names.length));
  final List<String> ids = <String>[
    for (final DocxStyle s in doc.styles.styles) s.id!.toLowerCase(),
  ];
  expect(ids.toSet(), hasLength(ids.length));
}

void main() {
  group('a Turkish document', () {
    test('idOf finds Balk1 by its name heading 1', () {
      expect(_localized().styles.idOf(DocxBuiltInStyle.heading1), 'Balk1');
    });

    test('idOf gives null for a built-in the document lacks', () {
      final DocxDocument doc = _localized();
      final List<String?> before = _ids(doc);
      expect(doc.styles.idOf(DocxBuiltInStyle.header), isNull);
      expect(_ids(doc), before);
    });

    test('ensure(heading1) returns Balk1 and adds nothing', () {
      final DocxDocument doc = _localized();
      final List<String?> before = _ids(doc);
      expect(doc.styles.ensure(DocxBuiltInStyle.heading1), 'Balk1');
      expect(_ids(doc), before);
    });

    test('p.style = Heading1 on an attached paragraph stores and reads '
        'Balk1', () {
      final DocxDocument doc = _localized();
      final DocxParagraph p = doc.body.addParagraph('x');
      p.style = 'Heading1';
      expect(p.style, 'Balk1');
      expect(p.properties.style, 'Balk1');
      expect(doc.styles.byId('Heading1'), isNull);
      expect(
        readDocxText(doc.save().bytes)['word/document.xml'],
        contains('w:pStyle w:val="Balk1"'),
      );
    });

    test('a detached paragraph with style Title inserted gets KonuBal', () {
      final DocxDocument doc = _localized();
      final DocxParagraph p = DocxParagraph.text('x')..style = 'Title';
      expect(p.style, 'Title');
      doc.body.insertBlock(0, p);
      expect(p.style, 'KonuBal');
    });

    test('a paragraph put in with replaceBlockAt is resolved', () {
      final DocxDocument doc = _localized();
      final DocxParagraph p = DocxParagraph()..style = 'Title';
      doc.body.replaceBlockAt(0, p);
      expect(p.style, 'KonuBal');
    });

    test('a run with rStyle Hyperlink inserted adds Hyperlink basedOn '
        'VarsaylanParagrafYazTipi', () {
      final DocxDocument doc = _localized();
      final DocxRun run = DocxRun('x')..style = 'Hyperlink';
      doc.body.addParagraph().insertInline(0, run);
      expect(run.style, 'Hyperlink');
      expect(doc.styles.byId('Hyperlink')?.basedOn, 'VarsaylanParagrafYazTipi');
    });

    test('a run of a detached paragraph is resolved when it goes in', () {
      final DocxDocument doc = _localized();
      final DocxParagraph p = DocxParagraph();
      final DocxRun run = p.addRun('x')..style = 'Strong';
      doc.body.insertBlock(0, p);
      expect(run.style, 'Strong');
      expect(doc.styles.byId('Strong')?.name, 'Strong');
    });

    test('run.style on an attached run adds the built-in', () {
      final DocxDocument doc = _localized();
      final DocxRun run = doc.body.addParagraph().addRun('x');
      run.properties.style = 'Emphasis';
      expect(doc.styles.byId('Emphasis')?.type, DocxStyleType.character);
    });

    test('ensure(header) adds Header basedOn Normal and HeaderChar linked '
        'both ways, and no name twice', () {
      final DocxDocument doc = _localized();
      expect(doc.styles.ensure(DocxBuiltInStyle.header), 'Header');
      final DocxStyle header = doc.styles.byId('Header')!;
      final DocxStyle char = doc.styles.byId('HeaderChar')!;
      expect(header.basedOn, 'Normal');
      expect(header.link, 'HeaderChar');
      expect(char.link, 'Header');
      expect(char.basedOn, 'VarsaylanParagrafYazTipi');
      expect(header.isCustom, isFalse);
      expect(char.isCustom, isTrue);
      _expectNamesUnique(doc);
      final String saved = _savedStyles(doc);
      expect(saved, contains('w:styleId="Header"'));
      expect(saved, contains('<w:name w:val="header"/>'));
      expect(saved, contains('w:pos="9072"'));
      expect(saved, contains('<w:basedOn w:val="VarsaylanParagrafYazTipi"/>'));
      expect(saved, isNot(contains('DefaultParagraphFont')));
    });

    test('ensure(tableGrid) is basedOn NormalTablo', () {
      final DocxDocument doc = _localized();
      expect(doc.styles.ensure(DocxBuiltInStyle.tableGrid), 'TableGrid');
      expect(doc.styles.byId('TableGrid')?.basedOn, 'NormalTablo');
      expect(doc.styles.byId('TableNormal'), isNull);
    });

    test('ensure(heading2) adds Heading2_1 named heading 2 beside My '
        'heading', () {
      final DocxDocument doc = _localized();
      expect(doc.styles.ensure(DocxBuiltInStyle.heading2), 'Heading2_1');
      final DocxStyle added = doc.styles.byId('Heading2_1')!;
      expect(added.name, 'heading 2');
      expect(added.link, 'Heading2Char');
      expect(doc.styles.byId('Heading2Char')?.link, 'Heading2_1');
      expect(doc.styles.byId('Heading2')?.name, 'My heading');
      expect(doc.styles.idOf(DocxBuiltInStyle.heading2), 'Heading2_1');
      _expectNamesUnique(doc);
    });

    test('the suffix is the smallest one free', () {
      final DocxDocument doc = DocxDocument.open(
        docxWithStyles(
          styles: stylesXmlOf(<String>[
            styleXml('paragraph', 'Normal', 'Normal'),
            styleXml('paragraph', 'Title', 'Mine'),
            styleXml('paragraph', 'Title_1', 'Mine too'),
            styleXml('paragraph', 'TITLE_2', 'Mine as well'),
          ]),
        ),
      );
      expect(doc.styles.ensure(DocxBuiltInStyle.title), 'Title_3');
    });

    test('p.style = Heading2 keeps the defined custom Heading2', () {
      final DocxDocument doc = _localized();
      final List<String?> before = _ids(doc);
      final DocxParagraph p = doc.body.addParagraph('x')..style = 'Heading2';
      expect(p.style, 'Heading2');
      expect(_ids(doc), before);
    });

    test('a read pStyle Heading3 is not resolved', () {
      final DocxDocument doc = _localized();
      final DocxParagraph p = doc.body.blocks.first as DocxParagraph;
      expect(p.style, 'Heading3');
      final DocxParagraph moved = p;
      doc.body.removeBlockAt(0);
      doc.body.insertBlock(0, moved);
      expect(moved.style, 'Heading3');
      expect(doc.styles.byName('heading 3'), isNull);
    });

    test('a read document that sets nothing does not load styles', () {
      final DocxDocument doc = _localized();
      final DocxParagraph p = doc.body.blocks.first as DocxParagraph;
      doc.body.removeBlockAt(0);
      doc.body.insertBlock(0, p);
      doc.body.addParagraph('x');
      expect(isStylesLoaded(doc), isFalse);
    });

    test('setting the id a paragraph reads records nothing', () {
      final DocxDocument doc = _localized();
      final DocxParagraph p = doc.body.addParagraph('x')..style = 'Balk1';
      final int before = _changes(doc, () => p.style = 'Heading1');
      expect(before, 0);
      expect(p.style, 'Balk1');
    });

    test('setting back a read id the document lacks adds nothing', () {
      final DocxDocument doc = _localized();
      final DocxParagraph p = doc.body.blocks.first as DocxParagraph;
      p.style = p.style;
      p.style = 'Heading3';
      expect(p.style, 'Heading3');
      expect(isStylesLoaded(doc), isFalse);
      expect(doc.styles.byName('heading 3'), isNull);
    });

    test('setting null neither resolves nor loads the styles', () {
      final DocxDocument doc = _localized();
      final DocxParagraph p = doc.body.blocks.first as DocxParagraph;
      p.style = null;
      expect(p.style, isNull);
      expect(isStylesLoaded(doc), isFalse);
    });

    test('an id of the wrong type is not a built-in', () {
      final DocxDocument doc = _localized();
      final DocxParagraph p = doc.body.addParagraph('x')..style = 'Hyperlink';
      expect(p.style, 'Hyperlink');
      expect(doc.styles.byId('Hyperlink'), isNull);
    });

    test('a paragraph resolved and rolled back is as it was', () {
      final DocxDocument doc = _localized();
      final DocxParagraph p = DocxParagraph()..style = 'Header';
      final List<String?> before = _ids(doc);
      int calls = 0;
      editsOf(doc).afterRecord = () {
        if (++calls == 3) throw StateError('stop');
      };
      expect(() => doc.body.insertBlock(0, p), throwsStateError);
      editsOf(doc).afterRecord = null;
      expect(_ids(doc), before);
      expect(p.style, 'Header');
      expect(doc.body.blocks, isNot(contains(p)));
    });

    test('a run inserted and rolled back leaves no style', () {
      final DocxDocument doc = _localized();
      final DocxParagraph p = doc.body.addParagraph();
      final DocxRun run = DocxRun('x')..style = 'Hyperlink';
      final List<String?> before = _ids(doc);
      int calls = 0;
      editsOf(doc).afterRecord = () {
        if (++calls == 2) throw StateError('stop');
      };
      expect(() => p.insertInline(0, run), throwsStateError);
      editsOf(doc).afterRecord = null;
      expect(_ids(doc), before);
      expect(p.inlines, isEmpty);
    });

    test('a set that fails takes the style it added with it', () {
      final DocxDocument doc = _localized();
      final DocxParagraph p = doc.body.addParagraph('x');
      final List<String?> before = _ids(doc);
      int calls = 0;
      editsOf(doc).afterRecord = () {
        if (++calls == 2) throw StateError('stop');
      };
      expect(() => p.style = 'NoSpacing', throwsStateError);
      editsOf(doc).afterRecord = null;
      expect(_ids(doc), before);
      expect(p.style, isNull);
    });

    test('a failing ensure rolls back every style it added', () {
      final DocxDocument doc = _localized();
      final List<String?> before = _ids(doc);
      int calls = 0;
      editsOf(doc).afterRecord = () {
        if (++calls == 2) throw StateError('stop');
      };
      expect(
        () => doc.styles.ensure(DocxBuiltInStyle.header),
        throwsStateError,
      );
      editsOf(doc).afterRecord = null;
      expect(calls, 2);
      expect(_ids(doc), before);
      expect(doc.styles.byId('Header'), isNull);
      expect(doc.styles.byId('HeaderChar'), isNull);
      expect(doc.styles.ensure(DocxBuiltInStyle.header), 'Header');
    });

    test('ensure is one transaction: revert and reapply it whole', () {
      final DocxDocument doc = _localized();
      final List<String?> before = _ids(doc);
      final DocxEdits edits = editsOf(doc);
      final ChangeSet set = edits.transaction(
        () => doc.styles.ensure(DocxBuiltInStyle.header),
      );
      expect(set.changes, hasLength(2));
      final List<String?> after = _ids(doc);
      edits.log.revertSet(set);
      expect(_ids(doc), before);
      expect(doc.styles.byId('Header'), isNull);
      edits.log.reapplySet(set);
      expect(_ids(doc), after);
      expect(doc.styles.byId('Header')?.link, 'HeaderChar');
    });
  });

  group('undoing a set that added styles', () {
    test('a revert and a reapply resolve nothing', () {
      final DocxDocument doc = _localized();
      final DocxEdits edits = editsOf(doc);
      final DocxParagraph p = doc.body.addParagraph();
      final DocxRun run = DocxRun('x')..style = 'Hyperlink';
      final List<String?> before = _ids(doc);
      final ChangeSet set = edits.transaction(() => p.insertInline(0, run));
      final List<String?> after = _ids(doc);
      expect(after, hasLength(before.length + 1));
      int resolved = 0;
      edits.styleResolver = (String id, DocxStyleType type) {
        resolved++;
        return id;
      };

      edits.log.revertSet(set);
      expect(_ids(doc), before);
      expect(p.inlines, isEmpty);

      edits.log.reapplySet(set);
      expect(_ids(doc), after);
      expect(p.inlines, <DocxInline>[run]);
      expect(resolved, 0);
    });

    test('a set reverted and reapplied reads what it did', () {
      final DocxDocument doc = _localized();
      final DocxEdits edits = editsOf(doc);
      final DocxParagraph p = doc.body.addParagraph();
      final List<String?> before = _ids(doc);
      final ChangeSet set = edits.transaction(() => p.style = 'Header');
      final List<String?> after = _ids(doc);
      edits.log.revertSet(set);
      expect(p.style, isNull);
      expect(_ids(doc), before);
      edits.log.reapplySet(set);
      expect(p.style, 'Header');
      expect(_ids(doc), after);
    });
  });

  group('styleNotFound (Ruling 8)', () {
    test('an unknown id is kept and warns styleNotFound at its path on '
        'save', () {
      final DocxDocument doc = _localized();
      final DocxParagraph p = doc.body.addParagraph('x')..style = 'Bilinmez';
      final DocxRun run = doc.body.addParagraph().addRun('y')
        ..style = 'Bilinmez';
      expect(p.style, 'Bilinmez');
      expect(run.style, 'Bilinmez');
      final List<DocxWarning> found = _warnings(
        doc,
        DocxWarningCode.styleNotFound,
      );
      expect(found, hasLength(1));
      expect(found.single.detail, 'Bilinmez');
      expect(found.single.count, 2);
      expect(found.single.part, '/word/document.xml');
      expect(found.single.locations, <String>['body/p[3]', 'body/p[4]/r[0]']);
    });

    test('a character style set as a paragraph style warns styleNotFound', () {
      final DocxDocument doc = _localized();
      doc.body.addParagraph('x').style = 'VarsaylanParagrafYazTipi';
      expect(
        _warnings(doc, DocxWarningCode.styleNotFound).single.detail,
        'VarsaylanParagrafYazTipi',
      );
    });

    test('a paragraph style set as a character style warns styleNotFound', () {
      final DocxDocument doc = _localized();
      doc.body.addParagraph().addRun('x').style = 'Balk1';
      expect(
        _warnings(doc, DocxWarningCode.styleNotFound).single.locations,
        <String>['body/p[3]/r[0]'],
      );
    });

    test('a character style named heading 1 is the id of the built-in, and '
        'a paragraph given it warns styleNotFound', () {
      final DocxDocument doc = _withoutStyles();
      doc.styles.add(
        DocxStyle(
          type: DocxStyleType.character,
          id: 'CharH',
          name: 'heading 1',
        ),
      );
      expect(doc.styles.idOf(DocxBuiltInStyle.heading1), 'CharH');
      expect(doc.styles.ensure(DocxBuiltInStyle.heading1), 'CharH');
      final DocxParagraph p = doc.body.addParagraph('x')..style = 'CharH';
      expect(p.style, 'CharH');
      final List<DocxWarning> found = _warnings(
        doc,
        DocxWarningCode.styleNotFound,
      );
      expect(found.single.detail, 'CharH');
      expect(found.single.locations, <String>['body/p[1]']);
    });

    test('a read dangling pStyle does not warn', () {
      final DocxDocument doc = _localized();
      doc.body;
      doc.styles;
      expect(_warnings(doc, DocxWarningCode.styleNotFound), isEmpty);
    });

    test('a style that resolves does not warn', () {
      final DocxDocument doc = _localized();
      doc.body.addParagraph('x').style = 'Heading1';
      doc.body.addParagraph().addRun('y').style = 'Hyperlink';
      expect(_warnings(doc, DocxWarningCode.styleNotFound), isEmpty);
    });

    test('a block taken out is not reported', () {
      final DocxDocument doc = _localized();
      doc.body.addParagraph('x').style = 'Bilinmez';
      doc.body.removeBlockAt(doc.body.blocks.length - 1);
      expect(_warnings(doc, DocxWarningCode.styleNotFound), isEmpty);
    });
  });

  group('content read in one document and put in another', () {
    const String body =
        '<w:p><w:pPr><w:pStyle w:val="ListeParagraf"/></w:pPr>'
        '<w:r><w:t>Madde</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:pStyle w:val="Balk1"/></w:pPr>'
        '<w:r><w:rPr><w:rStyle w:val="Vurgu"/></w:rPr><w:t>Metin</w:t></w:r>'
        '</w:p>'
        '<w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="7"/>'
        '</w:numPr></w:pPr></w:p>'
        '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr></w:p>'
        '<w:p><w:pPr><w:pStyle w:foo="1" w:val="Eksik"/></w:pPr></w:p>'
        '<w:p><w:pPr><w:numPr><w:numId w:val="0"/></w:numPr></w:pPr></w:p>'
        '<w:p><w:pPr><w:numPr><w:numId w:val="1"/></w:numPr></w:pPr></w:p>';

    /// A document with [body] and the styles of a Turkish Word, which define
    /// neither `Vurgu` nor `Heading1`.
    DocxDocument source() => DocxDocument.open(
      rewriteDocxPart(
        localizedWordDocx(),
        'word/document.xml',
        (String xml) =>
            '<w:document xmlns:w="${Ns.w}"><w:body>$body</w:body>'
            '</w:document>',
      ),
    );

    /// Takes the block at [index] out of [doc].
    DocxParagraph take(DocxDocument doc, int index) {
      final DocxParagraph p = doc.body.blocks[index] as DocxParagraph;
      doc.body.removeBlockAt(index);
      return p;
    }

    test('a ListeParagraf paragraph in a new document warns styleNotFound', () {
      final DocxDocument target = DocxDocument();
      final DocxParagraph p = take(source(), 0);
      target.body.insertBlock(1, p);
      expect(p.style, 'ListeParagraf');
      final DocxWarning found = _warnings(
        target,
        DocxWarningCode.styleNotFound,
      ).single;
      expect(found.detail, 'ListeParagraf');
      expect(found.locations, <String>['body/p[1]']);
      expect(
        readDocxText(target.save().bytes)['word/document.xml'],
        contains('<w:pStyle w:val="ListeParagraf"/>'),
      );
    });

    test('a Balk1 heading put in by replaceBlockAt warns, and so does the '
        'rStyle of its run', () {
      final DocxDocument target = DocxDocument();
      target.body.replaceBlockAt(0, take(source(), 1));
      final List<DocxWarning> found = _warnings(
        target,
        DocxWarningCode.styleNotFound,
      );
      expect(<String?>[
        for (final DocxWarning w in found) w.detail,
      ], unorderedEquals(<String>['Balk1', 'Vurgu']));
    });

    test('a run put in a paragraph of a document warns', () {
      final DocxDocument target = DocxDocument();
      final DocxParagraph from = take(source(), 1);
      final DocxInline run = from.inlines.single;
      from.removeInlineAt(0);
      target.body.addParagraph().insertInline(0, run);
      final DocxWarning found = _warnings(
        target,
        DocxWarningCode.styleNotFound,
      ).single;
      expect(found.detail, 'Vurgu');
      expect(found.locations, <String>['body/p[1]/r[0]']);
    });

    test('a run put in a new paragraph warns when that goes in', () {
      final DocxDocument target = DocxDocument();
      final DocxParagraph from = take(source(), 1);
      final DocxInline run = from.inlines.single;
      from.removeInlineAt(0);
      final DocxParagraph fresh = DocxParagraph()..insertInline(0, run);
      expect(target.warnings, isEmpty);
      target.body.insertBlock(0, fresh);
      expect(
        _warnings(target, DocxWarningCode.styleNotFound).single.detail,
        'Vurgu',
      );
    });

    test('an id that resolves in the target does not warn', () {
      final DocxDocument target = _localized();
      target.body.insertBlock(0, take(source(), 3));
      expect(target.body.blocks.first, isA<DocxParagraph>());
      expect((target.body.blocks.first as DocxParagraph).style, 'Balk1');
      expect(_warnings(target, DocxWarningCode.styleNotFound), isEmpty);
    });

    test('a numId missing in the target warns numberingNotFound', () {
      final DocxDocument target = DocxDocument();
      target.body.insertBlock(0, take(source(), 2));
      final DocxWarning found = _warnings(
        target,
        DocxWarningCode.numberingNotFound,
      ).single;
      expect(found.detail, '7');
      expect(found.locations, <String>['body/p[0]']);
    });

    test('a numId the target has joins that list, unreported', () {
      final DocxDocument target = DocxDocument();
      expect(target.numbering.addBulletList().id, 1);
      target.body.insertBlock(0, take(source(), 6));
      expect(_warnings(target, DocxWarningCode.numberingNotFound), isEmpty);
    });

    test('numId 0 names no list and does not warn', () {
      final DocxDocument target = DocxDocument();
      target.body.insertBlock(0, take(source(), 5));
      expect(_warnings(target, DocxWarningCode.numberingNotFound), isEmpty);
    });

    test('a reference the model does not type stays as read, unreported', () {
      final DocxDocument target = DocxDocument();
      target.body.insertBlock(0, take(source(), 4));
      expect(_warnings(target, DocxWarningCode.styleNotFound), isEmpty);
      expect(
        readDocxText(target.save().bytes)['word/document.xml'],
        contains('w:foo="1"'),
      );
    });

    test('moved within one document it stays unresolved', () {
      final DocxDocument doc = _localized();
      final DocxParagraph p = take(doc, 0);
      final DocxParagraph q = doc.body.blocks.first as DocxParagraph;
      final DocxInline run = q.inlines.single;
      q.removeInlineAt(0);
      doc.body.insertBlock(1, p);
      (doc.body.blocks.last as DocxParagraph).insertInline(0, run);
      expect(p.style, 'Heading3');
      expect(isStylesLoaded(doc), isFalse);
      doc.styles;
      expect(_warnings(doc, DocxWarningCode.styleNotFound), isEmpty);
    });

    test('a target whose styles cannot be read changes nothing', () {
      final DocxDocument from = source();
      final DocxParagraph p = take(from, 0);
      final DocxDocument target = DocxDocument.open(
        docxWithStyles(styles: '<w:styles'),
      );
      final int blocks = target.body.blocks.length;
      expect(
        () => target.body.insertBlock(0, p),
        throwsA(isA<DocxReadException>()),
      );
      expect(target.body.blocks, hasLength(blocks));
      from.body.insertBlock(0, p);
      expect(_warnings(from, DocxWarningCode.styleNotFound), isEmpty);
    });

    test('a style set before the move is the one resolved', () {
      final DocxDocument target = DocxDocument();
      final DocxParagraph p = take(source(), 0)..style = 'Heading1';
      target.body.insertBlock(0, p);
      expect(p.style, 'Heading1');
      expect(_warnings(target, DocxWarningCode.styleNotFound), isEmpty);
    });
  });

  group('style links', () {
    test('basedOn, next and link take a built-in by its name', () {
      final DocxDocument doc = _localized();
      final DocxStyle s = doc.styles.add(
        DocxStyle(type: DocxStyleType.paragraph, id: 'Not', name: 'Not'),
      );
      s.basedOn = 'Heading1';
      s.next = 'Title';
      expect(s.basedOn, 'Balk1');
      expect(s.next, 'KonuBal');
      expect(doc.styles.byId('Heading1'), isNull);
    });

    test('add applies the same rules, and adds what is missing', () {
      final DocxDocument doc = _localized();
      final DocxStyle s = doc.styles.add(
        DocxStyle(
          type: DocxStyleType.paragraph,
          id: 'Not',
          name: 'Not',
          basedOn: 'Heading1',
          next: 'NoSpacing',
        ),
      );
      expect(s.basedOn, 'Balk1');
      expect(s.next, 'NoSpacing');
      expect(doc.styles.byId('NoSpacing')?.name, 'No Spacing');
    });

    test('a link takes a built-in of the other type', () {
      final DocxDocument doc = _localized();
      final DocxStyle s = doc.styles.add(
        DocxStyle(type: DocxStyleType.paragraph, id: 'Not', name: 'Not'),
      );
      s.link = 'Strong';
      expect(doc.styles.byId('Strong')?.type, DocxStyleType.character);
      expect(() => s.link = 'Title', throwsArgumentError);
      expect(s.link, 'Strong');
    });

    test('a link to a style of the same type throws', () {
      final DocxDocument doc = _localized();
      expect(
        () => doc.styles.add(
          DocxStyle(
            type: DocxStyleType.paragraph,
            id: 'Not',
            name: 'Not',
            link: 'Normal',
          ),
        ),
        throwsArgumentError,
      );
    });

    test('an unknown link throws, and add rolls back what it added', () {
      final DocxDocument doc = _localized();
      final List<String?> before = _ids(doc);
      expect(
        () => doc.styles.add(
          DocxStyle(
            type: DocxStyleType.paragraph,
            id: 'Not',
            name: 'Not',
            basedOn: 'NoSpacing',
            next: 'Bilinmez',
          ),
        ),
        throwsArgumentError,
      );
      expect(_ids(doc), before);
      final DocxStyle s = doc.styles.byId('Normal')!;
      expect(() => s.next = 'Bilinmez', throwsArgumentError);
    });

    test('a new style cannot take an id its links add', () {
      final DocxDocument doc = _localized();
      final List<String?> before = _ids(doc);
      expect(
        () => doc.styles.add(
          DocxStyle(
            type: DocxStyleType.character,
            id: 'HeaderChar',
            name: 'Mine',
            link: 'Header',
          ),
        ),
        throwsArgumentError,
      );
      expect(_ids(doc), before);
    });

    test('a built-in cannot be based on itself through a new style', () {
      final DocxDocument doc = _localized();
      expect(
        () => doc.styles.add(
          DocxStyle(
            type: DocxStyleType.paragraph,
            id: 'NoSpacing',
            name: 'Mine',
            basedOn: 'NoSpacing',
          ),
        ),
        throwsArgumentError,
      );
      expect(doc.styles.byId('NoSpacing'), isNull);
    });

    test('a link that fails takes what it added with it', () {
      final DocxDocument doc = _localized();
      final int before = doc.styles.styles.length;
      final DocxStyle normal = doc.styles.byId('Normal')!;
      // Header is added, and it is based on Normal: a cycle.
      expect(() => normal.basedOn = 'Header', throwsArgumentError);
      expect(doc.styles.styles, hasLength(before));
      expect(doc.styles.byId('Header'), isNull);
      expect(normal.basedOn, isNull);
      expect(changeLogOf(doc).hasChanges, isFalse);
    });

    test('setting the link a style reads is a no-op', () {
      final DocxDocument doc = DocxDocument.open(
        docxWithStyles(
          styles: stylesXmlOf(<String>[
            styleXml(
              'paragraph',
              'Normal',
              'Normal',
              children: '<w:basedOn w:val="Yok"/>',
            ),
          ]),
        ),
      );
      final DocxStyle s = doc.styles.byId('Normal')!;
      s.basedOn = s.basedOn;
      expect(s.basedOn, 'Yok');
    });
  });

  group('a new document', () {
    test('in a new document ensure(listParagraph) returns ListParagraph and '
        'leaves styles unchanged', () {
      final DocxDocument doc = DocxDocument();
      final List<String?> before = _ids(doc);
      expect(
        doc.styles.ensure(DocxBuiltInStyle.listParagraph),
        'ListParagraph',
      );
      expect(_ids(doc), before);
    });

    test('p.style = Heading1 stays Heading1', () {
      final DocxDocument doc = DocxDocument();
      expect(
        (doc.body.addParagraph('x')..style = 'Heading1').style,
        'Heading1',
      );
    });

    test('every built-in resolves to itself or is added by its English id', () {
      for (final DocxBuiltInStyle b in DocxBuiltInStyle.values) {
        final DocxDocument doc = DocxDocument();
        expect(doc.styles.ensure(b), b.id);
        expect(doc.styles.byId(b.id)?.type, b.type);
        expect(doc.styles.byId(b.id)?.name, b.name);
        _expectNamesUnique(doc);
      }
    });
  });

  group('a document without styles', () {
    test('ensure in a document without styles.xml adds Normal, '
        'DefaultParagraphFont and the style', () {
      final DocxDocument doc = _withoutStyles();
      expect(
        doc.styles.ensure(DocxBuiltInStyle.listParagraph),
        'ListParagraph',
      );
      expect(_ids(doc), <String>[
        'Normal',
        'DefaultParagraphFont',
        'ListParagraph',
      ]);
      expect(doc.styles.byId('Normal')?.isDefault, isTrue);
      expect(doc.styles.byId('DefaultParagraphFont')?.isDefault, isTrue);
      final Map<String, String> saved = readDocxText(doc.save().bytes);
      expect(saved['word/styles.xml'], contains('w:default="1"'));
      expect(saved['[Content_Types].xml'], contains('/word/styles.xml'));
    });

    test('ensure(normal) adds Normal once', () {
      final DocxDocument doc = _withoutStyles();
      expect(doc.styles.ensure(DocxBuiltInStyle.normal), 'Normal');
      expect(_ids(doc), <String>['Normal', 'DefaultParagraphFont']);
    });

    test('p.style = Heading1 adds the part at save, and a second save adds '
        'nothing', () {
      final DocxDocument doc = _withoutStyles();
      doc.body.addParagraph('x').style = 'Heading1';
      final Uint8List first = doc.save().bytes;
      final Map<String, String> saved = readDocxText(first);
      expect(saved['word/styles.xml'], contains('w:styleId="Heading1"'));
      expect(saved['word/styles.xml'], contains('w:styleId="Heading1Char"'));
      expect(doc.warnings, isEmpty);
      expect(readDocxText(doc.save().bytes), saved);
    });

    test('a style set and rolled back leaves no part', () {
      final DocxDocument doc = _withoutStyles();
      final DocxParagraph p = doc.body.addParagraph('x');
      editsOf(doc).afterRecord = () => throw StateError('stop');
      expect(() => p.style = 'Heading1', throwsStateError);
      editsOf(doc).afterRecord = null;
      expect(
        readDocxText(doc.save().bytes),
        isNot(contains('word/styles.xml')),
      );
    });
  });

  group('a styles part with no change keeps its bytes', () {
    const String kept =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
        '<w:styles xmlns:w="${Ns.w}"><!-- kept -->'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
        '<w:name w:val="Normal"/></w:style>'
        '<w:style w:type="paragraph" w:styleId="Balk1">'
        '<w:name w:val="heading 1"/><w:basedOn w:val="Normal"/></w:style>'
        '</w:styles>';

    DocxDocument open() => DocxDocument.open(docxWithStyles(styles: kept));

    String saved(DocxDocument doc) =>
        readDocxText(doc.save().bytes)['word/styles.xml']!;

    test('a set that adds nothing keeps a comment under w:styles', () {
      final DocxDocument doc = open();
      final DocxParagraph p = doc.body.blocks.whereType<DocxParagraph>().first
        ..style = 'Heading1';
      expect(p.style, 'Balk1');
      expect(saved(doc), kept);
    });

    test('reading the styles keeps them', () {
      final DocxDocument doc = open();
      expect(doc.styles.styles, hasLength(2));
      expect(saved(doc), kept);
    });

    test('an edit rolled back keeps them', () {
      final DocxDocument doc = open();
      editsOf(doc).afterRecord = () => throw StateError('stop');
      expect(
        () => doc.styles.ensure(DocxBuiltInStyle.noSpacing),
        throwsStateError,
      );
      editsOf(doc).afterRecord = null;
      expect(saved(doc), kept);
    });

    test('a change is written from the model, and its revert is as read', () {
      final DocxDocument doc = open();
      final DocxEdits edits = editsOf(doc);
      final ChangeSet set = edits.transaction(() {
        doc.styles.byId('Balk1')!.uiPriority = 9;
        doc.styles.ensure(DocxBuiltInStyle.noSpacing);
      });
      final String changed = saved(doc);
      expect(changed, contains('<w:uiPriority w:val="9"/>'));
      expect(changed, contains('w:styleId="NoSpacing"'));
      expect(changed, isNot(contains('<!-- kept -->')));

      edits.log.revertSet(set);
      expect(saved(doc), kept);

      edits.log.reapplySet(set);
      expect(saved(doc), changed);
    });

    test('a default set is a change', () {
      final DocxDocument doc = open();
      doc.styles.defaults.runProperties.italic = true;
      expect(saved(doc), contains('<w:docDefaults>'));
    });

    test('a set that changes nothing keeps them', () {
      final DocxDocument doc = open();
      doc.styles.byId('Balk1')!.quickFormat = false;
      expect(saved(doc), kept);
    });
  });

  group('a styles part that cannot be read', () {
    test('a set or an insertion throws, changes nothing, and the part is '
        'copied', () {
      const String broken = '<w:styles xmlns:w="${Ns.w}"><w:style>';
      final DocxDocument doc = DocxDocument.open(
        docxWithStyles(styles: broken),
      );
      final DocxParagraph p = doc.body.blocks.whereType<DocxParagraph>().first;
      final String? before = p.style;
      final int blocks = doc.body.blocks.length;
      final Matcher fails = throwsA(isA<DocxReadException>());
      expect(() => p.style = 'Heading1', fails);
      expect(p.style, before);
      final DocxParagraph q = DocxParagraph()..style = 'Heading1';
      expect(() => doc.body.insertBlock(0, q), fails);
      expect(doc.body.blocks, hasLength(blocks));
      expect(readDocxText(doc.save().bytes)['word/styles.xml'], broken);
    });
  });

  group('the default of a type', () {
    for (final (DocxBuiltInStyle builtIn, String type)
        in <(DocxBuiltInStyle, String)>[
          (DocxBuiltInStyle.normal, 'paragraph'),
          (DocxBuiltInStyle.defaultParagraphFont, 'character'),
          (DocxBuiltInStyle.tableNormal, 'table'),
          (DocxBuiltInStyle.noList, 'numbering'),
        ]) {
      test('a default $type style without an id is still the default', () {
        final DocxDocument doc = DocxDocument.open(
          docxWithStyles(
            styles: stylesXmlOf(<String>[
              '<w:style w:type="$type" w:default="1">'
                  '<w:name w:val="Without an id"/></w:style>',
            ]),
          ),
        );
        expect(doc.styles.ensure(builtIn), builtIn.id);
        expect(doc.styles.byId(builtIn.id)?.isDefault, isFalse);
        expect(
          RegExp('w:default=').allMatches(_savedStyles(doc)),
          hasLength(1),
        );
      });
    }

    test('adding a built-in keeps the default of the file', () {
      final DocxDocument doc = DocxDocument.open(
        docxWithStyles(
          styles: stylesXmlOf(<String>[
            styleXml(
              'paragraph',
              'Govde',
              'Body',
              attributes: ' w:default="1"',
            ),
            styleXml(
              'table',
              'Duz',
              'Plain table',
              attributes: ' w:default="1"',
            ),
            styleXml(
              'numbering',
              'Yok',
              'Nothing',
              attributes: ' w:default="1"',
            ),
          ]),
        ),
      );
      expect(doc.styles.ensure(DocxBuiltInStyle.normal), 'Normal');
      expect(doc.styles.ensure(DocxBuiltInStyle.tableNormal), 'TableNormal');
      expect(doc.styles.ensure(DocxBuiltInStyle.noList), 'NoList');
      for (final DocxStyleType type in <DocxStyleType>[
        DocxStyleType.paragraph,
        DocxStyleType.table,
        DocxStyleType.numbering,
      ]) {
        expect(
          doc.styles.styles.where(
            (DocxStyle s) => s.type == type && s.isDefault,
          ),
          hasLength(1),
          reason: type.name,
        );
      }
      expect(doc.styles.byId('Normal')?.isDefault, isFalse);
      final String saved = _savedStyles(doc);
      expect(RegExp('w:default=').allMatches(saved), hasLength(3));
      final DocxDocument again = DocxDocument.open(doc.save().bytes);
      expect(again.styles.byId('Normal')?.isDefault, isFalse);
      expect(again.styles.byId('Govde')?.isDefault, isTrue);
    });

    test('a dependency on Normal takes the default of the file', () {
      final DocxDocument doc = DocxDocument.open(
        docxWithStyles(
          styles: stylesXmlOf(<String>[
            styleXml(
              'paragraph',
              'Govde',
              'Body',
              attributes: ' w:default="1"',
            ),
          ]),
        ),
      );
      doc.styles.ensure(DocxBuiltInStyle.heading1);
      expect(doc.styles.byId('Heading1')?.basedOn, 'Govde');
      expect(doc.styles.byId('Heading1')?.next, 'Govde');
      expect(doc.styles.byId('Normal'), isNull);
    });

    test('without a default, a dependency finds Normal by its name', () {
      final DocxDocument doc = DocxDocument.open(
        docxWithStyles(
          styles: stylesXmlOf(<String>[
            styleXml('paragraph', 'Temel', 'normal'),
          ]),
        ),
      );
      doc.styles.ensure(DocxBuiltInStyle.quote);
      expect(doc.styles.byId('Quote')?.basedOn, 'Temel');
      expect(doc.styles.byId('Normal'), isNull);
    });
  });

  group('the prefix of the part', () {
    test('a style added to a part with another prefix is well formed', () {
      const String ns0 = 'ns0';
      final DocxDocument doc = DocxDocument.open(
        docxWithStyles(
          styles:
              '<$ns0:styles xmlns:$ns0="${Ns.w}">'
              '<$ns0:style $ns0:type="paragraph" $ns0:default="1" '
              '$ns0:styleId="Temel"><$ns0:name $ns0:val="Normal"/>'
              '</$ns0:style></$ns0:styles>',
        ),
      );
      doc.styles.ensure(DocxBuiltInStyle.listParagraph);
      final DocxDocument again = DocxDocument.open(doc.save().bytes);
      final DocxStyle added = again.styles.byId('ListParagraph')!;
      expect(added.name, 'List Paragraph');
      expect(added.basedOn, 'Temel');
      expect(added.uiPriority, 34);
      expect(added.type, DocxStyleType.paragraph);
    });

    test('the definition is written without a declaration of its own', () {
      final DocxDocument doc = _localized();
      doc.styles.ensure(DocxBuiltInStyle.noSpacing);
      expect(
        _savedStyles(doc),
        contains(
          '<w:style w:type="paragraph" w:styleId="NoSpacing">'
          '<w:name w:val="No Spacing"/>',
        ),
      );
    });
  });

  group('a German document', () {
    test('idOf heading1 and heading2 are berschrift1 and berschrift2', () {
      final DocxStyles styles = _german().styles;
      expect(styles.idOf(DocxBuiltInStyle.heading1), 'berschrift1');
      expect(styles.idOf(DocxBuiltInStyle.heading2), 'berschrift2');
    });

    test('p.style = Heading1 stores berschrift1 and adds no Heading1', () {
      final DocxDocument doc = _german();
      final List<String?> before = _ids(doc);
      final DocxParagraph p = doc.body.addParagraph('x')..style = 'Heading1';
      expect(p.style, 'berschrift1');
      expect(_ids(doc), before);
    });

    test('the style with outlineLvl 0 named Chapter is not heading 1', () {
      final DocxDocument doc = _german();
      expect(doc.styles.byId('Gliederung')?.name, 'Chapter');
      expect(doc.styles.idOf(DocxBuiltInStyle.heading1), isNot('Gliederung'));
    });

    test('ensure(header) is basedOn Standard and its char style basedOn '
        'Absatz-Standardschriftart', () {
      final DocxDocument doc = _german();
      doc.styles.ensure(DocxBuiltInStyle.header);
      expect(doc.styles.byId('Header')?.basedOn, 'Standard');
      expect(
        doc.styles.byId('HeaderChar')?.basedOn,
        'Absatz-Standardschriftart',
      );
      expect(doc.styles.byId('Normal'), isNull);
      expect(doc.styles.byId('DefaultParagraphFont'), isNull);
    });

    test('idOf takes the first style of the name in document order', () {
      DocxDocument named(List<String> ids) => DocxDocument.open(
        docxWithStyles(
          styles: stylesXmlOf(<String>[
            styleXml('paragraph', ids.first, 'Heading 1'),
            styleXml('paragraph', ids.last, 'heading 1'),
          ]),
        ),
      );
      const DocxBuiltInStyle h1 = DocxBuiltInStyle.heading1;
      expect(named(<String>['Bir', 'Iki']).styles.idOf(h1), 'Bir');
      expect(named(<String>['Iki', 'Bir']).styles.idOf(h1), 'Iki');
    });

    test('idOf never matches by id', () {
      final DocxDocument doc = DocxDocument.open(
        docxWithStyles(
          styles: stylesXmlOf(<String>[
            styleXml('paragraph', 'Heading1', 'Foo'),
            styleXml('paragraph', 'Balk1', 'heading 1'),
          ]),
        ),
      );
      expect(doc.styles.idOf(DocxBuiltInStyle.heading1), 'Balk1');
    });
  });
}

/// How many changes [body] records in [doc].
int _changes(DocxDocument doc, void Function() body) =>
    editsOf(doc).transaction(body).changes.length;
