// Tests the edit primitives of the DOCX body model: each body edit applies
// itself and records a change in the document's ChangeLog that reverts and
// reapplies it, the edits a paragraph reports through its sink are recorded
// the same way, and an edit that fails inside a transaction is rolled back.
// They build documents in memory, so they run on the web as well.
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart';
import 'package:jet_office/src/docx/model/blocks.dart';
import 'package:jet_office/src/docx/model/edit_sink.dart';
import 'package:jet_office/src/docx/model/inlines.dart';
import 'package:jet_office/src/docx/model/primitives.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:test/test.dart';

import '../support/read_xlsx.dart';
import 'support/docx_builder.dart';

/// A container the block primitives can put blocks in.
final Object _container = Object();

/// The texts of the paragraphs among [blocks].
List<String> _texts(List<DocxBlock> blocks) => <String>[
  for (final DocxBlock b in blocks)
    if (b is DocxParagraph) b.text,
];

/// A document of three paragraphs, `one`, `two` and `three`, the second
/// with two runs.
DocxDocument _open() => DocxDocument.open(
  buildDocx(
    document:
        '<w:document xmlns:w="${Ns.w}"><w:body>'
        '<w:p><w:r><w:t>one</w:t></w:r></w:p>'
        '<w:p><w:r><w:t>t</w:t></w:r><w:r><w:t>wo</w:t></w:r></w:p>'
        '<w:p><w:r><w:t>three</w:t></w:r></w:p>'
        '</w:body></w:document>',
  ),
);

void main() {
  group('block primitives', () {
    test('insert, remove and replace record changes that revert and '
        'reapply', () {
      final DocxEdits edits = DocxEdits();
      final List<DocxBlock> blocks = <DocxBlock>[];
      final DocxParagraph a = DocxParagraph.text('a');
      final DocxParagraph b = DocxParagraph.text('b');
      final DocxParagraph c = DocxParagraph.text('c');
      final ChangeSet set = edits.transaction(() {
        insertBlock(edits, _container, blocks, 0, a);
        insertBlock(edits, _container, blocks, 1, b);
        replaceBlock(edits, _container, blocks, 0, c);
        removeBlock(edits, _container, blocks, 1);
      });
      expect(_texts(blocks), <String>['c']);
      expect(set.changes, hasLength(4));
      expect(blockContainerOf(c), same(_container));
      expect(blockContainerOf(a), isNull);
      expect(blockContainerOf(b), isNull);
      expect(editSinkOf(c), same(edits));
      expect(editSinkOf(a), same(DocxEditSink.none));

      edits.log.revertSet(set);
      expect(blocks, isEmpty);
      expect(blockContainerOf(a), isNull);
      expect(blockContainerOf(c), isNull);
      expect(editSinkOf(c), same(DocxEditSink.none));

      edits.log.reapplySet(set);
      expect(_texts(blocks), <String>['c']);
      expect(blockContainerOf(c), same(_container));
      expect(editSinkOf(c), same(edits));
    });

    test('a block in a container throws StateError and changes nothing', () {
      final DocxEdits edits = DocxEdits();
      final List<DocxBlock> blocks = <DocxBlock>[];
      final DocxParagraph a = DocxParagraph.text('a');
      edits.transaction(() => insertBlock(edits, _container, blocks, 0, a));
      expect(
        () => edits.transaction(
          () => insertBlock(edits, Object(), <DocxBlock>[], 0, a),
        ),
        throwsStateError,
      );
      expect(
        () => edits.transaction(
          () => replaceBlock(edits, _container, blocks, 0, a),
        ),
        throwsStateError,
      );
      expect(blocks, <DocxBlock>[a]);
      expect(blockContainerOf(a), same(_container));
    });

    test('a removed block has no container and can be inserted again', () {
      final DocxEdits edits = DocxEdits();
      final List<DocxBlock> blocks = <DocxBlock>[];
      final DocxParagraph a = DocxParagraph.text('a');
      edits.transaction(() {
        insertBlock(edits, _container, blocks, 0, a);
        removeBlock(edits, _container, blocks, 0);
      });
      expect(blockContainerOf(a), isNull);
      edits.transaction(() => insertBlock(edits, _container, blocks, 0, a));
      expect(blocks, <DocxBlock>[a]);
    });

    test('a bad index throws RangeError and records nothing', () {
      final DocxEdits edits = DocxEdits();
      final List<DocxBlock> blocks = <DocxBlock>[];
      expect(
        () => edits.transaction(
          () => insertBlock(edits, _container, blocks, 1, DocxParagraph()),
        ),
        throwsRangeError,
      );
      expect(
        () =>
            edits.transaction(() => removeBlock(edits, _container, blocks, 0)),
        throwsRangeError,
      );
      expect(edits.log.hasChanges, isFalse);
    });

    test('outside a transaction it throws and leaves the list unchanged', () {
      final DocxEdits edits = DocxEdits();
      final List<DocxBlock> blocks = <DocxBlock>[];
      final DocxParagraph a = DocxParagraph();
      expect(
        () => insertBlock(edits, _container, blocks, 0, a),
        throwsStateError,
      );
      expect(blocks, isEmpty);
      expect(blockContainerOf(a), isNull);
    });
  });

  group('paragraph edits through the sink', () {
    test('inline, text and style edits are recorded and revert', () {
      final DocxEdits edits = DocxEdits();
      final DocxParagraph p = DocxParagraph.text('a');
      attachEditSink(p, edits);
      final DocxRun first = p.inlines.single as DocxRun;
      final DocxRun added = DocxRun('x');
      final ChangeSet set = edits.transaction(() {
        p.insertInline(0, added);
        first.text = 'b\u0001';
        first.style = 'Strong';
        p.style = 'Title';
        replaceInlineAt(p, 0, DocxRun('y'));
        p.removeInlineAt(1);
      });
      expect(set.changes, hasLength(6));
      expect(p.text, 'y');
      expect(p.style, 'Title');

      edits.log.revertSet(set);
      expect(p.inlines, <DocxInline>[first]);
      expect(first.text, 'a');
      expect(first.style, isNull);
      expect(p.style, isNull);
      expect(paragraphOf(added), isNull);

      edits.log.reapplySet(set);
      expect(p.text, 'y');
      expect(first.text, 'b');
      expect(first.style, 'Strong');
      expect(p.style, 'Title');
    });

    test('an edit made alone runs in a transaction of its own', () {
      final DocxEdits edits = DocxEdits();
      final DocxParagraph p = DocxParagraph();
      attachEditSink(p, edits);
      p.addRun('a').text = 'b';
      expect(edits.log.hasChanges, isTrue);
    });

    test('reverting does not record the replayed edits again', () {
      final DocxEdits edits = DocxEdits();
      final DocxParagraph p = DocxParagraph();
      attachEditSink(p, edits);
      int records = 0;
      edits.afterRecord = () => records++;
      final ChangeSet set = edits.transaction(() {
        p.addRun('a');
        p.style = 'Title';
      });
      expect(records, 2);
      edits.log.revertSet(set);
      edits.log.reapplySet(set);
      expect(records, 2);
    });
  });

  group('property sets', () {
    /// A document whose one paragraph has the style `Title`, written with a
    /// w14 attribute, and whose run has the style `Strong`.
    DocxDocument styled() => DocxDocument.open(
      buildDocx(
        document:
            '<w:document xmlns:w="${Ns.w}" xmlns:w14="${Ns.w14}"><w:body>'
            '<w:p><w:pPr><w:pStyle w:val="Title" w14:x="1"/></w:pPr>'
            '<w:r><w:rPr><w:rStyle w:val="Strong"/></w:rPr><w:t>a</w:t></w:r>'
            '</w:p></w:body></w:document>',
      ),
    );

    String documentXml(DocxDocument doc) =>
        readXlsx(doc.save().bytes)['word/document.xml']!;

    test('a property set is one change that reverts and reapplies', () {
      final DocxDocument doc = styled();
      final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
      final DocxRun run = p.inlines.single as DocxRun;
      expect(p.style, 'Title');
      final ChangeSet set = changeLogOf(doc).transaction(() {
        p.style = 'Heading1';
        run.style = null;
      });
      expect(set.changes, hasLength(2));
      expect(p.style, 'Heading1');
      expect(run.style, isNull);

      changeLogOf(doc).revertSet(set);
      expect(p.style, 'Title');
      expect(run.style, 'Strong');

      changeLogOf(doc).reapplySet(set);
      expect(p.style, 'Heading1');
      expect(run.style, isNull);
    });

    test('a failing property set rolls back', () {
      final DocxDocument doc = styled();
      final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
      final DocxRun run = p.inlines.single as DocxRun;
      int records = 0;
      editsOf(doc).afterRecord = () {
        records++;
        throw StateError('test hook');
      };
      expect(() => p.style = 'Heading1', throwsStateError);
      expect(() => run.style = 'Emphasis', throwsStateError);
      expect(records, 2);
      expect(p.style, 'Title');
      expect(run.style, 'Strong');
      expect(changeLogOf(doc).hasChanges, isFalse);
      editsOf(doc).afterRecord = null;
      expect(documentXml(doc), contains('<w:pStyle w:val="Title" w14:x="1"/>'));
    });

    test('reverting a set on a read child restores the child as read', () {
      final DocxDocument doc = styled();
      final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
      final ChangeSet set = changeLogOf(
        doc,
      ).transaction(() => p.style = 'Heading1');
      expect(documentXml(doc), contains('<w:pStyle w:val="Heading1"/>'));
      changeLogOf(doc).revertSet(set);
      expect(documentXml(doc), contains('<w:pStyle w:val="Title" w14:x="1"/>'));
    });

    test('an edit after save is in the next save', () {
      final DocxDocument doc = styled();
      final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
      final DocxRun run = p.inlines.single as DocxRun;
      doc.save();
      p.style = 'Heading1';
      run.style = null;
      final DocxDocument reopened = DocxDocument.open(doc.save().bytes);
      final DocxParagraph q = reopened.body.blocks.single as DocxParagraph;
      expect(q.style, 'Heading1');
      expect((q.inlines.single as DocxRun).style, isNull);
    });

    DocxDocument twoStyles() => DocxDocument.open(
      buildDocx(
        document:
            '<w:document xmlns:w="${Ns.w}"><w:body>'
            '<w:p><w:pPr><w:pStyle w:val="A"/><w:pStyle w:val="B"/></w:pPr>'
            '<w:r><w:t>a</w:t></w:r></w:p></w:body></w:document>',
      ),
    );

    test('setting the view back changes nothing and keeps the child', () {
      final DocxDocument doc = styled();
      final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
      p.style = 'Title';
      p.style = p.style;
      expect(changeLogOf(doc).hasChanges, isFalse);
      expect(documentXml(doc), contains('<w:pStyle w:val="Title" w14:x="1"/>'));
    });

    test('setting null on an untyped child records nothing', () {
      final DocxDocument doc = twoStyles();
      final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
      expect(p.style, isNull);
      p.style = null;
      p.style = p.style;
      expect(changeLogOf(doc).hasChanges, isFalse);
      expect(documentXml(doc), contains('<w:pStyle w:val="A"/>'));
      expect(documentXml(doc), contains('<w:pStyle w:val="B"/>'));
    });

    test('clear removes untyped children in one change that reverts', () {
      final DocxDocument doc = twoStyles();
      final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
      final ChangeSet set = changeLogOf(
        doc,
      ).transaction(() => paragraphPropertySetOf(p).clearChild('pStyle'));
      expect(set.changes, hasLength(1));
      expect(documentXml(doc), isNot(contains('pStyle')));
      paragraphPropertySetOf(p).clearChild('pStyle');
      expect(changeLogOf(doc).transaction(() {}).isEmpty, isTrue);
      changeLogOf(doc).revertSet(set);
      expect(documentXml(doc), contains('<w:pStyle w:val="A"/>'));
      expect(documentXml(doc), contains('<w:pStyle w:val="B"/>'));
      changeLogOf(doc).reapplySet(set);
      expect(documentXml(doc), isNot(contains('pStyle')));
    });

    test('setting null twice on a typed child is one change', () {
      final DocxDocument doc = styled();
      final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
      final ChangeSet set = changeLogOf(doc).transaction(() {
        p.style = null;
        p.style = null;
      });
      expect(set.changes, hasLength(1));
      expect(p.style, isNull);
      changeLogOf(doc).revertSet(set);
      expect(p.style, 'Title');
    });

    test('a run detached after the edit reverts and reapplies', () {
      final DocxDocument doc = styled();
      final DocxParagraph p = doc.body.blocks.single as DocxParagraph;
      final DocxRun run = p.inlines.single as DocxRun;
      final ChangeSet set = changeLogOf(
        doc,
      ).transaction(() => run.style = 'Emphasis');
      p.removeInlineAt(0);
      expect(paragraphOf(run), isNull);
      changeLogOf(doc).revertSet(set);
      expect(run.style, 'Strong');
      changeLogOf(doc).reapplySet(set);
      expect(run.style, 'Emphasis');
      // The detached run reports to no document.
      final ChangeSet after = changeLogOf(
        doc,
      ).transaction(() => run.style = 'Other');
      expect(after.isEmpty, isTrue);
    });
  });

  group('rollback', () {
    test('a failing edit inside a transaction rolls back', () {
      final DocxDocument doc = _open();
      final DocxBody body = doc.body;
      final DocxParagraph second = body.blocks[1] as DocxParagraph;
      final DocxRun run = second.inlines.first as DocxRun;
      final DocxEdits edits = editsOf(doc);
      final List<DocxBlock> before = body.blocks.toList();
      int records = 0;
      // Throws on every record: each edit applies, records, then fails.
      edits.afterRecord = () {
        records++;
        throw StateError('test hook');
      };

      final DocxParagraph fresh = DocxParagraph.text('new');
      expect(() => body.insertBlock(0, fresh), throwsStateError);
      expect(() => body.addParagraph('new'), throwsStateError);
      expect(() => body.removeBlockAt(0), throwsStateError);
      expect(
        () => body.replaceBlockAt(0, DocxParagraph.text('x')),
        throwsStateError,
      );
      expect(() => run.text = 'changed', throwsStateError);
      expect(() => run.style = 'Strong', throwsStateError);
      expect(() => second.style = 'Title', throwsStateError);
      expect(() => second.addRun('more'), throwsStateError);
      expect(() => second.removeInlineAt(1), throwsStateError);
      expect(records, 9);

      expect(body.blocks, before);
      expect(_texts(body.blocks), <String>['one', 'two', 'three']);
      expect(second.inlines, hasLength(2));
      expect(run.text, 't');
      expect(run.style, isNull);
      expect(second.style, isNull);
      expect(blockContainerOf(fresh), isNull);
      expect(changeLogOf(doc).hasChanges, isFalse);

      // The rolled-back paragraph can be inserted once the hook is gone.
      edits.afterRecord = null;
      body.insertBlock(0, fresh);
      expect(_texts(body.blocks), <String>['new', 'one', 'two', 'three']);
    });

    test('a transaction of several edits that throws undoes them all', () {
      final DocxDocument doc = _open();
      final DocxBody body = doc.body;
      final DocxRun run =
          (body.blocks.first as DocxParagraph).inlines.single as DocxRun;
      expect(
        () => changeLogOf(doc).transaction(() {
          body.addParagraph('four');
          run.text = 'uno';
          body.removeBlockAt(1);
          throw StateError('test');
        }),
        throwsStateError,
      );
      expect(_texts(body.blocks), <String>['one', 'two', 'three']);
      expect(run.text, 'one');
      expect(changeLogOf(doc).hasChanges, isFalse);
    });

    test('an edit of a paragraph outside the body is not recorded', () {
      final DocxDocument doc = _open();
      final DocxBody body = doc.body;
      final DocxParagraph p = body.blocks.first as DocxParagraph;
      body.removeBlockAt(0);
      final ChangeLog log = changeLogOf(doc);
      final ChangeSet set = log.transaction(() => p.addRun('x'));
      expect(set.isEmpty, isTrue);
    });
  });
}
