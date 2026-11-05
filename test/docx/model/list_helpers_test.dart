// Tests the list helpers: DocxNumbering.addBulletList and addNumberedList
// add Word's toolbar lists without their identifiers (plan Ruling 9), and
// DocxBody.addListItem puts a paragraph in one (Ruling 8's numberingNotFound
// reports a list the document lacks). The documents are built in memory, so
// these tests run on the web as well.
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/builtin_numbering.dart';
import 'package:test/test.dart';

import '../support/localized_document.dart';
import '../support/numbering_documents.dart';
import '../support/styles_documents.dart' show docxWithStyles, readDocxText;

DocxParagraph _paragraph(DocxDocument doc, int index) =>
    doc.body.blocks[index] as DocxParagraph;

void main() {
  group('addBulletList and addNumberedList', () {
    test('addBulletList in a new document adds abstract 0 and num 1 and '
        'creates numbering.xml at save', () {
      final DocxDocument doc = DocxDocument();
      expect(readDocxText(doc.save().bytes), isNot(contains(_part)));
      final DocxNumberingInstance list = doc.numbering.addBulletList();
      expect(list.id, 1);
      expect(list.abstractId, 0);
      expect(doc.numbering.abstractNumberings, hasLength(1));
      final String xml = readDocxText(doc.save().bytes)[_part]!;
      expect(xml, contains('<w:abstractNum w:abstractNumId="0">'));
      expect(xml, contains('<w:num w:numId="1">'));
      expect(xml, contains('<w:abstractNumId w:val="0"/>'));
    });

    test('a second addNumberedList takes abstract 1 and num 2', () {
      final DocxDocument doc = DocxDocument();
      doc.numbering.addBulletList();
      final DocxNumberingInstance list = doc.numbering.addNumberedList();
      expect(list.id, 2);
      expect(list.abstractId, 1);
      expect(
        list.abstractNumbering!.levels[0].format,
        DocxNumberFormat.decimal,
      );
      expect(list.abstractNumbering!.levels[0].text, '%1.');
    });

    test('two bullet lists have an abstract definition each', () {
      final DocxDocument doc = DocxDocument();
      final DocxNumberingInstance a = doc.numbering.addBulletList();
      final DocxNumberingInstance b = doc.numbering.addBulletList();
      expect(<int>[a.abstractId, b.abstractId], <int>[0, 1]);
      expect(<int>[a.id, b.id], <int>[1, 2]);
    });

    test('bullet level 0 is Symbol U+F0B7 at 720 hanging 360', () {
      final DocxDocument doc = DocxDocument();
      final DocxNumberingLevel level = doc.numbering
          .addBulletList()
          .abstractNumbering!
          .levels[0];
      expect(level.format, DocxNumberFormat.bullet);
      expect(level.text, '');
      expect(level.bulletFont!.ascii, 'Symbol');
      expect(level.bulletFont!.hAnsi, 'Symbol');
      expect(level.indentation!.leftPt, 36);
      expect(level.indentation!.hangingPt, 18);
      final DocxNumberingLevel one =
          doc.numbering.abstractNumberings.single.levels[1];
      expect(one.text, 'o');
      expect(one.bulletFont!.ascii, 'Courier New');
    });

    test('every level of both lists is there, indented 360 further', () {
      final DocxDocument doc = DocxDocument();
      doc.numbering.addBulletList();
      doc.numbering.addNumberedList();
      for (final DocxAbstractNumbering a in doc.numbering.abstractNumberings) {
        expect(a.levels, hasLength(9));
        for (int i = 0; i < 9; i++) {
          expect(a.levels[i].indentation!.leftPt, 36.0 * (i + 1));
        }
      }
    });

    test('no new definition has nsid, tmpl or tplc', () {
      final DocxDocument doc = DocxDocument();
      doc.numbering.addBulletList();
      doc.numbering.addNumberedList();
      final String xml = readDocxText(doc.save().bytes)[_part]!;
      expect(xml, isNot(contains('nsid')));
      expect(xml, isNot(contains('tmpl')));
      expect(xml, isNot(contains('tplc')));
      expect(xml, isNot(contains('restartNumberingAfterBreak')));
      expect(xml, isNot(contains('durableId')));
      expect(bulletAbstractXml, isNot(contains('nsid')));
      expect(numberedAbstractXml, isNot(contains('tplc')));
    });

    test('an opened document keeps its definitions and gains the lowest '
        'unused ids', () {
      final DocxDocument doc = DocxDocument();
      doc.numbering.addBulletList();
      final DocxDocument again = DocxDocument.open(doc.save().bytes);
      final DocxNumberingInstance list = again.numbering.addNumberedList();
      expect(list.abstractId, 1);
      expect(list.id, 2);
      expect(again.numbering.abstractNumberings, hasLength(2));
    });

    test('a failed addInstance after addBulletList changes nothing more', () {
      final DocxDocument doc = DocxDocument();
      expect(
        () => doc.numbering.addInstance(
          doc.numbering.addBulletList().abstractNumbering!,
          startOverrides: <int, int>{9: 1},
        ),
        throwsRangeError,
      );
      expect(doc.numbering.instances, hasLength(1));
    });
  });

  group('addListItem', () {
    test('addListItem sets ListParagraph and numPr', () {
      final DocxDocument doc = DocxDocument();
      final DocxNumberingInstance list = doc.numbering.addBulletList();
      final DocxParagraph p = doc.body.addListItem(list, 'One');
      final DocxParagraph q = doc.body.addListItem(list, 'Two', level: 1);
      expect(p.style, 'ListParagraph');
      expect(p.properties.numbering, DocxNumberingRef(1));
      expect(q.properties.numbering, DocxNumberingRef(1, level: 1));
      expect(doc.body.blocks.last, same(q));
      final DocxDocument again = DocxDocument.open(doc.save().bytes);
      expect(_paragraph(again, 1).properties.numbering, DocxNumberingRef(1));
      expect(_paragraph(again, 2).style, 'ListParagraph');
    });

    test('in localizedWordDocx() addListItem uses ListeParagraf', () {
      final DocxDocument doc = DocxDocument.open(localizedWordDocx());
      final DocxNumberingInstance list = doc.numbering.addNumberedList();
      final DocxParagraph p = doc.body.addListItem(list, 'Bir');
      expect(p.style, 'ListeParagraf');
      final String styles = readDocxText(doc.save().bytes)['word/styles.xml']!;
      expect(styles, isNot(contains('w:styleId="ListParagraph"')));
    });

    test('paragraph text of a list item has no label', () {
      final DocxDocument doc = DocxDocument();
      final DocxNumberingInstance list = doc.numbering.addNumberedList();
      final DocxParagraph p = doc.body.addListItem(list, 'Alpha');
      expect(p.text, 'Alpha');
      final DocxDocument again = DocxDocument.open(doc.save().bytes);
      expect(_paragraph(again, 1).text, 'Alpha');
    });

    test('an instance of another document throws ArgumentError and changes '
        'nothing', () {
      final DocxDocument doc = DocxDocument();
      final DocxNumberingInstance foreign = DocxDocument().numbering
          .addBulletList();
      final int blocks = doc.body.blocks.length;
      expect(() => doc.body.addListItem(foreign, 'x'), throwsArgumentError);
      expect(doc.body.blocks, hasLength(blocks));
      expect(doc.numbering.instances, isEmpty);
    });

    test('a level outside 0 to 8 throws RangeError and changes nothing', () {
      final DocxDocument doc = DocxDocument.open(localizedWordDocx());
      final DocxNumberingInstance list = doc.numbering.addBulletList();
      final int blocks = doc.body.blocks.length;
      expect(() => doc.body.addListItem(list, 'x', level: 9), throwsRangeError);
      expect(
        () => doc.body.addListItem(list, 'x', level: -1),
        throwsRangeError,
      );
      expect(doc.body.blocks, hasLength(blocks));
    });

    test('a document without ListParagraph gains it, and a refused item '
        'adds nothing', () {
      final DocxDocument doc = DocxDocument.open(
        docxWithStyles(
          styles: stylesXmlOf(<String>[
            styleXml(
              'paragraph',
              'Normal',
              'Normal',
              attributes: ' w:default="1"',
            ),
          ]),
        ),
      );
      final DocxNumberingInstance foreign = DocxDocument().numbering
          .addBulletList();
      expect(() => doc.body.addListItem(foreign, 'x'), throwsArgumentError);
      expect(doc.styles.idOf(DocxBuiltInStyle.listParagraph), isNull);
      final DocxNumberingInstance list = doc.numbering.addBulletList();
      final DocxParagraph p = doc.body.addListItem(list, 'x');
      expect(p.style, 'ListParagraph');
      expect(doc.styles.idOf(DocxBuiltInStyle.listParagraph), 'ListParagraph');
    });
  });

  group('list helpers in a numbering part with odd ids', () {
    /// The names of the children of `w:numbering` and the ids of the
    /// definitions and instances, as the saved part writes them.
    (List<String>, List<String>) outline(DocxDocument doc) {
      final String xml = readDocxText(doc.save().bytes)[_part]!;
      final List<String> names = <String>[];
      final List<String> ids = <String>[];
      int depth = 0;
      for (final RegExpMatch m in RegExp(
        r'<(/?)w:([A-Za-z]+)([^>]*?)(/?)>',
      ).allMatches(xml)) {
        final bool closing = m.group(1) == '/';
        final bool selfClosing = m.group(4) == '/';
        if (closing) {
          depth--;
          continue;
        }
        if (depth == 1) {
          names.add(m.group(2)!);
          final RegExpMatch? id = RegExp(
            r'w:(?:abstractNumId|numId)="([^"]*)"',
          ).firstMatch(m.group(3)!);
          if (id != null) ids.add('${m.group(2)}:${id.group(1)}');
        }
        if (!selfClosing) depth++;
      }
      return (names, ids);
    }

    test('duplicate ids, an opaque id and a trailing numIdMacAtCleanup: the '
        'new definition follows the last abstractNum, the new instance the '
        'last num, and both take the lowest unused ids', () {
      final DocxDocument doc = DocxDocument.open(
        docxWithNumbering(
          pictureTarget: null,
          numbering: numberingXml(
            '${abstractNumXml('0')}${abstractNumXml('0')}'
            '${abstractNumXml('x')}'
            '${numXml('1', '0')}${numXml('1', '0')}${numXml('y', '0')}'
            '<w:numIdMacAtCleanup w:val="1"/>',
          ),
        ),
      );
      final DocxNumberingInstance list = doc.numbering.addBulletList();
      // 0 is used twice and `x` is no id, so the lowest unused is 1; the
      // same for numId 1 and `y`: the new instance is 2.
      expect(list.abstractId, 1);
      expect(list.id, 2);
      final (List<String> names, List<String> ids) = outline(doc);
      expect(names, <String>[
        'abstractNum',
        'abstractNum',
        'abstractNum',
        'abstractNum',
        'num',
        'num',
        'num',
        'num',
        'numIdMacAtCleanup',
      ]);
      expect(ids, <String>[
        'abstractNum:0',
        'abstractNum:0',
        'abstractNum:x',
        'abstractNum:1',
        'num:1',
        'num:1',
        'num:y',
        'num:2',
      ]);
      // A paragraph put in it names the new instance.
      expect(
        doc.body.addListItem(list, 'x').properties.numbering,
        DocxNumberingRef(2),
      );
    });

    test('a numbering part with only a numIdMacAtCleanup gains the '
        'definition and the instance before it', () {
      final DocxDocument doc = DocxDocument.open(
        docxWithNumbering(
          pictureTarget: null,
          numbering: numberingXml('<w:numIdMacAtCleanup w:val="0"/>'),
        ),
      );
      final DocxNumberingInstance list = doc.numbering.addNumberedList();
      expect((list.abstractId, list.id), (0, 1));
      final (List<String> names, List<String> ids) = outline(doc);
      expect(names, <String>['abstractNum', 'num', 'numIdMacAtCleanup']);
      expect(ids, <String>['abstractNum:0', 'num:1']);
    });
  });

  group('numberingNotFound', () {
    test('a numId set to 7 that the document lacks warns numberingNotFound '
        'on save', () {
      final DocxDocument doc = DocxDocument();
      doc.numbering.addBulletList();
      doc.body.addParagraph('x').properties.numbering = DocxNumberingRef(7);
      final List<DocxWarning> found = doc
          .save()
          .warnings
          .where((DocxWarning w) => w.code == DocxWarningCode.numberingNotFound)
          .toList();
      expect(found, hasLength(1));
      expect(found.single.detail, '7');
      expect(
        found.single.message(),
        '1 paragraph in /word/document.xml${_where(found.single)} belongs to '
        'the list 7, which the document does not define; Word shows it '
        'without a number.',
      );
    });

    test('numId 0 does not warn', () {
      final DocxDocument doc = DocxDocument();
      doc.body.addParagraph('x').properties.numbering = DocxNumberingRef(0);
      expect(
        doc.save().warnings.map((DocxWarning w) => w.code),
        isNot(contains(DocxWarningCode.numberingNotFound)),
      );
    });
  });
}

const String _part = 'word/numbering.xml';

String _where(DocxWarning w) =>
    w.locations.isEmpty ? '' : ' (${w.locations.join(', ')})';
