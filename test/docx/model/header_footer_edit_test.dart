// Tests writing headers and footers: a story gets a part, a relationship and
// a reference at save, and only once a live section refers to it; `ownHeader`,
// `removeHeader` and their footer kin; a first story turning `titlePage` on;
// the closing paragraph of a story; undo and failure leaving nothing behind.
// They build documents in memory, so they run on the web as well.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart'
    show changeLogOf, editsOf;
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../support/docx_builder.dart';
import '../support/styles_documents.dart';

const String _decls = 'xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}"';

/// A relationship of the main part.
String _rel(String id, String target, {String type = RelType.header}) =>
    '<Relationship Id="$id" Type="$type" Target="$target"/>';

/// A `w:headerReference` of [type] through [id].
String _h(String type, String id) =>
    '<w:headerReference w:type="$type" r:id="$id"/>';

/// A `w:footerReference` of [type] through [id].
String _f(String type, String id) =>
    '<w:footerReference w:type="$type" r:id="$id"/>';

/// A paragraph that holds [text].
String _p(String text) => '<w:p><w:r><w:t>$text</w:t></w:r></w:p>';

/// A paragraph that holds [text] and ends a section of [references].
String _break(String text, [String references = '']) =>
    '<w:p><w:pPr><w:sectPr>$references</w:sectPr></w:pPr>'
    '<w:r><w:t>$text</w:t></w:r></w:p>';

/// A `w:hdr` that holds [content].
String _hdr(String content) => '<w:hdr $_decls>$content</w:hdr>';

/// A `w:ftr` that holds [content].
String _ftr(String content) => '<w:ftr $_decls>$content</w:ftr>';

/// A table of one empty cell, as a file holds it.
const String _table =
    '<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w="100"/></w:tblGrid>'
    '<w:tr><w:tc><w:p/></w:tc></w:tr></w:tbl>';

/// A package whose body holds [body], whose main part has the relationships
/// [rels], and which has [parts] (a ZIP entry name and its text). [root] is
/// what `w:document` declares.
Uint8List _docx(
  String body, {
  String rels = '',
  Map<String, String> parts = const <String, String>{},
  String root = _decls,
  String bodyAttributes = '',
}) {
  final StringBuffer overrides = StringBuffer();
  for (final String name in parts.keys) {
    final String type = name.contains('header')
        ? ContentType.wmlHeader
        : ContentType.wmlFooter;
    overrides.write('<Override PartName="/$name" ContentType="$type"/>');
  }
  return buildDocx(
    document:
        '<w:document $root><w:body$bodyAttributes>$body</w:body></w:document>',
    extra: <String, List<int>>{
      '[Content_Types].xml': utf8.encode(
        '<Types xmlns="$contentTypesNs">'
        '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
        '<Override PartName="/word/document.xml" '
        'ContentType="${ContentType.wmlDocument}"/>$overrides</Types>',
      ),
      'word/_rels/document.xml.rels': utf8.encode(
        '<Relationships xmlns="$packageRelsNs">$rels</Relationships>',
      ),
      for (final MapEntry<String, String> e in parts.entries)
        e.key: utf8.encode(e.value),
    },
  );
}

/// A document of [count] sections with no references.
Uint8List _sections(int count) => _docx(
  '${<String>[for (int i = 1; i < count; i++) _break('S$i')].join()}'
  '${_p('Last')}<w:sectPr/>',
);

/// A document whose first section has the default footer `Old`, with a
/// second section that inherits it.
Uint8List _inheriting() => _docx(
  '${_break('One', _f('default', 'rId1'))}${_p('Two')}<w:sectPr/>',
  rels: _rel('rId1', 'footer1.xml', type: RelType.footer),
  parts: <String, String>{'word/footer1.xml': _ftr(_p('Old'))},
);

/// The text of the paragraph [index] of [story].
String _text(DocxStory story, [int index = 0]) =>
    (story.blocks[index] as DocxParagraph).text;

/// The relationships of the main part of [text], the parts of a package.
String _rels(Map<String, String> text) => text['word/_rels/document.xml.rels']!;

/// How many times [pattern] occurs in [text].
int _count(String text, String pattern) => pattern.allMatches(text).length;

/// Expects that a save of [doc] holds the main part of [input] byte for byte,
/// and nothing else that means something else.
void _expectUnchanged(Uint8List input, DocxDocument doc) {
  final Uint8List saved = doc.save().bytes;
  expect(comparePackages(input, saved), isEmpty);
  expect(
    readDocxText(saved)['word/document.xml'],
    readDocxText(input)['word/document.xml'],
  );
}

void main() {
  group('a new story', () {
    test('a footer of a new document is a part, once saved', () {
      final DocxDocument doc = DocxDocument();
      doc.sections.single.footer.addParagraph('x');
      final Uint8List bytes = doc.save().bytes;
      final Map<String, String> text = readDocxText(bytes);

      expect(text.keys, contains('word/footer1.xml'));
      expect(
        _count(
          text['[Content_Types].xml']!,
          'PartName="/word/footer1.xml" ContentType="${ContentType.wmlFooter}"',
        ),
        1,
      );
      expect(
        _count(_rels(text), 'Type="${RelType.footer}"'),
        1,
        reason: _rels(text),
      );
      expect(_rels(text), contains('Target="footer1.xml"'));
      final String main = text['word/document.xml']!;
      expect(_count(main, '<w:footerReference '), 1);
      expect(main, contains('w:type="default"'));
      expect(
        main.indexOf('<w:footerReference '),
        lessThan(main.indexOf('<w:pgSz ')),
      );
      expect(text['word/footer1.xml'], contains('<w:ftr '));
      expect(text['word/footer1.xml'], contains('xmlns:r="${Ns.rel}"'));

      final DocxDocument again = DocxDocument.open(bytes);
      final DocxHeaderFooter footer = again.sections.single.footer;
      expect(footer.isInherited, isFalse);
      expect(_text(footer), 'x');
    });

    test('a header goes to header1.xml, with a w:hdr root', () {
      final DocxDocument doc = DocxDocument();
      doc.sections.single.header.addParagraph('h');
      final Uint8List bytes = doc.save().bytes;
      final Map<String, String> text = readDocxText(bytes);
      expect(text['word/header1.xml'], contains('<w:hdr '));
      expect(_text(DocxDocument.open(bytes).sections.single.header), 'h');
    });

    test('a read of the getters creates nothing', () {
      final Uint8List input = _sections(2);
      final DocxDocument doc = DocxDocument.open(input);
      for (final DocxSection s in doc.sections) {
        expect(s.footer.blocks, isEmpty);
        expect(s.firstHeader.blocks, isEmpty);
      }
      _expectUnchanged(input, doc);
    });

    test('takes the first free number, past parts and targets', () {
      final Uint8List input = _docx(
        '${_p('Body')}<w:sectPr>${_h('default', 'rId1')}</w:sectPr>',
        rels:
            '${_rel('rId1', 'header1.xml')}'
            '${_rel('rId2', 'footer1.xml', type: RelType.footer)}',
        parts: <String, String>{'word/header1.xml': _hdr(_p('Old'))},
      );
      final DocxDocument doc = DocxDocument.open(input);
      final DocxSection section = doc.sections.single;
      section.ownHeader(DocxHeaderFooterType.first).addParagraph('First');
      section.footer.addParagraph('Foot');
      final Map<String, String> text = readDocxText(doc.save().bytes);
      expect(text.keys, contains('word/header2.xml'));
      // A relationship read names footer1.xml, which is not there: a part
      // created at that name would give it a target it never had.
      expect(text.keys, isNot(contains('word/footer1.xml')));
      expect(text.keys, contains('word/footer2.xml'));
    });

    test('goes to the root when a part is named word', () {
      final Uint8List input = buildDocx(
        mainPath: 'main.xml',
        document:
            '<w:document $_decls><w:body>${_p('A')}<w:sectPr/></w:body>'
            '</w:document>',
        extra: <String, List<int>>{'word': utf8.encode('x')},
      );
      final DocxDocument doc = DocxDocument.open(input);
      doc.sections.single.footer.addParagraph('x');
      final Uint8List bytes = doc.save().bytes;
      expect(readDocxText(bytes).keys, contains('footer1.xml'));
      expect(_text(DocxDocument.open(bytes).sections.single.footer), 'x');
    });

    test('takes no id a reference names without a relationship', () {
      final Uint8List input = _docx(
        '${_break('One', _h('default', 'rId1'))}${_p('Two')}<w:sectPr/>',
      );
      final DocxDocument doc = DocxDocument.open(input);
      doc.sections.last.footer.addParagraph('x');
      final Uint8List bytes = doc.save().bytes;
      expect(_rels(readDocxText(bytes)), isNot(contains('Id="rId1"')));
      final DocxDocument again = DocxDocument.open(bytes);
      expect(again.sections.first.header.blocks, isEmpty);
      expect(_text(again.sections.last.footer), 'x');
    });

    test('takes no id of a reference of an unknown type', () {
      final DocxDocument doc = DocxDocument.open(
        _docx('${_p('A')}<w:sectPr>${_h('odd', 'rId1')}</w:sectPr>'),
      );
      doc.sections.single.footer.addParagraph('x');
      final String rels = _rels(readDocxText(doc.save().bytes));
      expect(rels, isNot(contains('Id="rId1"')));
      expect(rels, contains('Id="rId2"'));
    });

    test('takes no id of a reference of a w:sectPr in a cell', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w="100"/></w:tblGrid><w:tr>'
          '<w:tc><w:p><w:pPr><w:sectPr>${_h('default', 'rId1')}</w:sectPr>'
          '</w:pPr></w:p></w:tc></w:tr></w:tbl>${_p('A')}<w:sectPr/>',
        ),
      );
      doc.sections.single.footer.addParagraph('x');
      expect(
        _rels(readDocxText(doc.save().bytes)),
        isNot(contains('Id="rId1"')),
      );
    });

    test('names the parts in the order of the sections', () {
      final DocxDocument doc = DocxDocument.open(_sections(2));
      final List<DocxSection> sections = doc.sections;
      sections[1].footer.addParagraph('Second');
      sections[0].footer.addParagraph('First');
      sections[0].evenFooter.addParagraph('Even');
      final Map<String, String> text = readDocxText(doc.save().bytes);
      expect(text['word/footer1.xml'], contains('First'));
      expect(text['word/footer2.xml'], contains('Even'));
      expect(text['word/footer3.xml'], contains('Second'));
    });

    test('two saves give the same names and ids', () {
      final DocxDocument doc = DocxDocument();
      final DocxSection section = doc.sections.single;
      section.footer.addParagraph('x');
      section.header.addParagraph('h');
      final Uint8List first = doc.save().bytes;
      final Uint8List second = doc.save().bytes;
      expect(second, first);
      section.footer.addParagraph('y');
      final Map<String, String> text = readDocxText(doc.save().bytes);
      expect(_count(_rels(text), 'Type="${RelType.footer}"'), 1);
      expect(text['word/footer1.xml'], contains('y'));
      expect(text.keys, isNot(contains('word/footer2.xml')));
    });

    test('saveTo writes the references as save does', () {
      final DocxDocument doc = DocxDocument();
      doc.sections.single.footer.addParagraph('x');
      final BytesBuilder out = BytesBuilder();
      doc.saveTo(_BytesSink(out));
      expect(
        _text(DocxDocument.open(out.takeBytes()).sections.single.footer),
        'x',
      );
    });

    test('a list, a style and a warning in a new story are seen', () {
      final DocxDocument doc = DocxDocument();
      final DocxHeaderFooter footer = doc.sections.single.footer;
      final DocxParagraph paragraph = footer.addParagraph('x');
      paragraph.properties.numbering = DocxNumberingRef(42);
      paragraph.style = 'NoSuchStyle';
      (paragraph.inlines.single as DocxRun).text = 'a\u0001b';
      final List<DocxWarning> warnings = doc.save().warnings;
      expect(
        warnings.map((DocxWarning w) => (w.code, w.part, w.locations.single)),
        unorderedEquals(<Object>[
          (
            DocxWarningCode.numberingNotFound,
            '/word/footer1.xml',
            'word/footer1.xml/p[0]',
          ),
          (
            DocxWarningCode.styleNotFound,
            '/word/footer1.xml',
            'word/footer1.xml/p[0]',
          ),
          (
            DocxWarningCode.invalidCharactersRemoved,
            '/word/footer1.xml',
            'word/footer1.xml/p[0]/r[0]',
          ),
        ]),
      );
    });

    test('a table left without rows stops the save, and creates nothing', () {
      final DocxDocument doc = DocxDocument();
      final DocxHeaderFooter footer = doc.sections.single.footer;
      final DocxTable table = footer.addTable(columns: 1);
      expect(
        doc.save,
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('word/footer1.xml/tbl[0]'),
          ),
        ),
      );
      table.addRow(<String?>['x']);
      final Map<String, String> text = readDocxText(doc.save().bytes);
      expect(_count(_rels(text), 'Type="${RelType.footer}"'), 1);
      expect(text.keys, contains('word/footer1.xml'));
    });

    test('a section that left the body creates no part', () {
      final DocxDocument doc = DocxDocument.open(_sections(2));
      doc.sections.first.footer.addTable(columns: 1);
      doc.body.removeBlockAt(0);
      final Map<String, String> text = readDocxText(doc.save().bytes);
      expect(text.keys, isNot(contains('word/footer1.xml')));
      expect(_rels(text), isNot(contains(RelType.footer)));
    });

    test('a break moved to a cell writes no reference without a part', () {
      final DocxDocument doc = DocxDocument.open(_sections(2));
      doc.sections.first.footer.addParagraph('x');
      final DocxBlock block = doc.body.blocks.first;
      doc.body.removeBlockAt(0);
      final DocxTable table = doc.body.addTable(columns: 1);
      table.addRow(<String?>[null]);
      table.rows.single.cells.single.insertBlock(0, block);
      final Map<String, String> text = readDocxText(doc.save().bytes);
      expect(text['word/document.xml'], isNot(contains('footerReference')));
      expect(text.keys, isNot(contains('word/footer1.xml')));
    });
  });

  group('the prefix of a new reference', () {
    /// The `w:footerReference` of [input] once a footer is added.
    String reference(Uint8List input) {
      final DocxDocument doc = DocxDocument.open(input);
      doc.sections.single.footer.addParagraph('x');
      final Uint8List bytes = doc.save().bytes;
      expect(_text(DocxDocument.open(bytes).sections.single.footer), 'x');
      return RegExp(
        '<w:footerReference [^>]*>',
      ).stringMatch(readDocxText(bytes)['word/document.xml']!)!;
    }

    test('is r where r is bound to relationships', () {
      expect(
        reference(_docx('${_p('A')}<w:sectPr/>')),
        '<w:footerReference w:type="default" r:id="rId1"/>',
      );
    });

    test('is the one the part binds to relationships', () {
      expect(
        reference(
          _docx(
            '${_p('A')}<w:sectPr/>',
            root: 'xmlns:w="${Ns.w}" xmlns:rel="${Ns.rel}" xmlns:r="urn:other"',
          ),
        ),
        '<w:footerReference w:type="default" rel:id="rId1"/>',
      );
    });

    test('is declared when nothing binds it', () {
      expect(
        reference(_docx('${_p('A')}<w:sectPr/>', root: 'xmlns:w="${Ns.w}"')),
        '<w:footerReference w:type="default" xmlns:r="${Ns.rel}" r:id="rId1"/>',
      );
    });

    test('is another when r is bound to something else', () {
      expect(
        reference(
          _docx(
            '${_p('A')}<w:sectPr/>',
            root: 'xmlns:w="${Ns.w}" xmlns:r="urn:other"',
          ),
        ),
        '<w:footerReference w:type="default" xmlns:r1="${Ns.rel}" '
        'r1:id="rId1"/>',
      );
    });

    test('takes what the w:sectPr itself binds', () {
      expect(
        reference(
          _docx(
            '${_p('A')}<w:sectPr xmlns:r="urn:other"/>',
            root: 'xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}"',
          ),
        ),
        '<w:footerReference w:type="default" xmlns:r1="${Ns.rel}" '
        'r1:id="rId1"/>',
      );
    });

    test('takes what a paragraph\'s kept attribute binds', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '<w:p xmlns:r="urn:x" r:foo="1"><w:pPr><w:sectPr/></w:pPr></w:p>'
          '${_p('B')}<w:sectPr/>',
        ),
      );
      doc.sections.first.footer.addParagraph('x');
      final Uint8List bytes = doc.save().bytes;
      expect(readDocxText(bytes)['word/document.xml'], contains(' r:foo="1"'));
      expect(_text(DocxDocument.open(bytes).sections.first.footer), 'x');
    });

    test('takes what the body\'s kept attribute binds', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '${_p('A')}<w:sectPr/>',
          bodyAttributes: ' xmlns:r="urn:x" r:foo="1"',
        ),
      );
      doc.sections.single.footer.addParagraph('x');
      final Uint8List bytes = doc.save().bytes;
      expect(_text(DocxDocument.open(bytes).sections.single.footer), 'x');
    });

    test('takes what a kept attribute around a moved break binds', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '${_break('A')}${_p('B')}'
          '<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w="100"/></w:tblGrid><w:tr>'
          '<w:tc xmlns:r="urn:x" r:foo="1"><w:p/></w:tc></w:tr></w:tbl>'
          '${_p('C')}<w:sectPr/>',
        ),
      );
      doc.sections.first.footer.addParagraph('x');
      doc.save();
      final DocxBlock block = doc.body.blocks.first;
      doc.body.removeBlockAt(0);
      final DocxTable table = doc.body.blocks[1] as DocxTable;
      table.rows.single.cells.single.insertBlock(0, block);
      final String main = readDocxText(doc.save().bytes)['word/document.xml']!;
      expect(main, contains('xmlns:r1="${Ns.rel}" r1:id="rId1"'));
    });

    test('works in a paragraph break too', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '${_break('A')}${_p('B')}<w:sectPr/>',
          root: 'xmlns:w="${Ns.w}" xmlns:rel="${Ns.rel}"',
        ),
      );
      doc.sections.first.header.addParagraph('x');
      final Uint8List bytes = doc.save().bytes;
      expect(readDocxText(bytes)['word/document.xml'], contains(' rel:id='));
      expect(_text(DocxDocument.open(bytes).sections.first.header), 'x');
    });
  });

  group('a section with no w:sectPr of its own', () {
    test('gets one when a reference goes in, and only then', () {
      final Uint8List input = _docx(_p('A'));
      final DocxDocument doc = DocxDocument.open(input);
      doc.sections.single.footer.addParagraph('x');
      final Uint8List bytes = doc.save().bytes;
      expect(readDocxText(bytes)['word/document.xml'], contains('<w:sectPr>'));
      expect(_text(DocxDocument.open(bytes).sections.single.footer), 'x');
    });

    test('has none again after an undo', () {
      final Uint8List input = _docx(_p('A'));
      final DocxDocument doc = DocxDocument.open(input);
      final DocxSection section = doc.sections.single;
      final ChangeSet set = editsOf(
        doc,
      ).transaction(() => section.footer.addParagraph('x'));
      changeLogOf(doc).revertSet(set);
      expect(comparePackages(input, doc.save().bytes), isEmpty);
    });
  });

  group('sections around a footer (Review Focus 1)', () {
    test('a footer of section 2 of 3 is section 3\'s, not section 1\'s', () {
      final DocxDocument doc = DocxDocument.open(_sections(3));
      final List<DocxSection> sections = doc.sections;
      sections[1].footer.addParagraph('Two');

      expect(sections[0].footer.blocks, isEmpty);
      expect(sections[1].footer.isInherited, isFalse);
      expect(sections[2].footer.isInherited, isTrue);
      expect(_text(sections[2].footer), 'Two');

      final Uint8List bytes = doc.save().bytes;
      final String main = readDocxText(bytes)['word/document.xml']!;
      expect(_count(main, '<w:footerReference '), 1);
      expect(
        main.indexOf('<w:footerReference '),
        greaterThan(main.indexOf('S1')),
      );
      expect(main.indexOf('<w:footerReference '), lessThan(main.indexOf('S2')));
      final List<DocxSection> again = DocxDocument.open(bytes).sections;
      expect(again[0].footer.blocks, isEmpty);
      expect(_text(again[1].footer), 'Two');
      expect(again[2].footer.isInherited, isTrue);
      expect(_text(again[2].footer), 'Two');
    });

    test('an edit of an inherited story reaches every section', () {
      final DocxDocument doc = DocxDocument.open(_inheriting());
      final List<DocxSection> sections = doc.sections;
      sections[1].footer.addParagraph('New');
      expect(sections[0].footer.blocks, hasLength(2));
      expect(sections[1].footer.isInherited, isTrue);
      final Uint8List bytes = doc.save().bytes;
      final Map<String, String> text = readDocxText(bytes);
      expect(text['word/footer1.xml'], contains('New'));
      expect(_count(text['word/document.xml']!, '<w:footerReference '), 1);
      final List<DocxSection> again = DocxDocument.open(bytes).sections;
      expect(_text(again[0].footer, 1), 'New');
      expect(_text(again[1].footer, 1), 'New');
    });

    test('a section added later inherits a new story', () {
      final DocxDocument doc = DocxDocument();
      final DocxSection first = doc.sections.single;
      first.footer.addParagraph('x');
      final DocxSection second = doc.body.addSection();
      expect(second.footer.isInherited, isTrue);
      expect(_text(second.footer), 'x');
      final List<DocxSection> again = DocxDocument.open(
        doc.save().bytes,
      ).sections;
      expect(_text(again[1].footer), 'x');
      expect(again[1].footer.isInherited, isTrue);
    });
  });

  group('ownHeader and ownFooter', () {
    test('give a new empty story in place of an inherited one', () {
      final DocxDocument doc = DocxDocument.open(_inheriting());
      final List<DocxSection> sections = doc.sections;
      final DocxHeaderFooter own = sections[1].ownFooter(
        DocxHeaderFooterType.primary,
      );
      expect(own.isInherited, isFalse);
      expect(own.blocks, isEmpty);
      expect(identical(sections[1].footer, own), isTrue);
      expect(_text(sections[0].footer), 'Old');
      own.addParagraph('New');
      final Uint8List bytes = doc.save().bytes;
      final List<DocxSection> again = DocxDocument.open(bytes).sections;
      expect(_text(again[0].footer), 'Old');
      expect(_text(again[1].footer), 'New');
      expect(readDocxText(bytes).keys, contains('word/footer2.xml'));
    });

    test('an own story left empty is written as one empty paragraph', () {
      final DocxDocument doc = DocxDocument.open(_inheriting());
      doc.sections[1].ownFooter(DocxHeaderFooterType.primary);
      final Uint8List bytes = doc.save().bytes;
      expect(readDocxText(bytes)['word/footer2.xml'], contains('<w:p/>'));
      final DocxHeaderFooter again = DocxDocument.open(
        bytes,
      ).sections[1].footer;
      expect(again.isInherited, isFalse);
      expect(_text(again), '');
    });

    test('give the section\'s own story when it has one', () {
      final DocxDocument doc = DocxDocument.open(_inheriting());
      final DocxSection section = doc.sections[0];
      final DocxHeaderFooter own = section.ownFooter(
        DocxHeaderFooterType.primary,
      );
      expect(identical(own, section.footer), isTrue);
      expect(_text(own), 'Old');
      expect(changeLogOf(doc).hasChanges, isFalse);
    });

    test('give the handle a section read as empty', () {
      final DocxDocument doc = DocxDocument();
      final DocxSection section = doc.sections.single;
      final DocxHeaderFooter empty = section.header;
      expect(
        identical(section.ownHeader(DocxHeaderFooterType.primary), empty),
        isTrue,
      );
    });

    for (final (String name, String reference) in <(String, String)>[
      ('a dangling id', _h('default', 'rId9')),
      ('no id', '<w:headerReference w:type="default"/>'),
      ('an id of another type', _h('default', 'rId2')),
    ]) {
      test('replace a reference of $name', () {
        final DocxDocument doc = DocxDocument.open(
          _docx(
            '${_p('A')}<w:sectPr>'
            '$reference${_h('first', 'rId9')}<w:pgSz w:w="100" w:h="100"/>'
            '</w:sectPr>',
            rels: _rel('rId2', 'footer1.xml', type: RelType.footer),
            parts: <String, String>{'word/footer1.xml': _ftr(_p('F'))},
          ),
        );
        final DocxSection section = doc.sections.single;
        section
            .ownHeader(DocxHeaderFooterType.primary)
            .addParagraph('Replaced');
        final Uint8List bytes = doc.save().bytes;
        final String main = readDocxText(bytes)['word/document.xml']!;
        expect(_count(main, '<w:headerReference '), 2);
        expect(_count(main, 'w:type="default"'), 1);
        expect(main, contains(_h('first', 'rId9')));
        expect(
          _text(DocxDocument.open(bytes).sections.single.header),
          'Replaced',
        );
      });
    }

    test('an edit replaces a broken reference as own does', () {
      final DocxDocument doc = DocxDocument.open(
        _docx('${_p('A')}<w:sectPr>${_h('default', 'rId9')}</w:sectPr>'),
      );
      doc.sections.single.header.addParagraph('x');
      final Uint8List bytes = doc.save().bytes;
      expect(
        _count(
          readDocxText(bytes)['word/document.xml']!,
          '<w:headerReference ',
        ),
        1,
      );
      expect(_text(DocxDocument.open(bytes).sections.single.header), 'x');
    });

    test('keep a reference of an unknown type', () {
      final DocxDocument doc = DocxDocument.open(
        _docx('${_p('A')}<w:sectPr>${_h('odd', 'rId9')}</w:sectPr>'),
      );
      doc.sections.single.ownHeader(DocxHeaderFooterType.primary);
      final String main = readDocxText(doc.save().bytes)['word/document.xml']!;
      expect(main, contains(_h('odd', 'rId9')));
      expect(_count(main, '<w:headerReference '), 2);
    });
  });

  group('removeHeader and removeFooter', () {
    test('leave the part, and read the previous section\'s', () {
      final Uint8List input = _docx(
        '${_break('One', _f('default', 'rId1'))}${_p('Two')}'
        '<w:sectPr>${_f('default', 'rId2')}</w:sectPr>',
        rels:
            '${_rel('rId1', 'footer1.xml', type: RelType.footer)}'
            '${_rel('rId2', 'footer2.xml', type: RelType.footer)}',
        parts: <String, String>{
          'word/footer1.xml': _ftr(_p('First')),
          'word/footer2.xml': _ftr(_p('Second')),
        },
      );
      final DocxDocument doc = DocxDocument.open(input);
      final DocxSection last = doc.sections.last;
      last.removeFooter(DocxHeaderFooterType.primary);
      expect(last.footer.isInherited, isTrue);
      expect(_text(last.footer), 'First');
      final Uint8List bytes = doc.save().bytes;
      final Map<String, String> text = readDocxText(bytes);
      expect(text['word/footer2.xml'], contains('Second'));
      expect(_rels(text), contains('footer2.xml'));
      expect(_count(text['word/document.xml']!, '<w:footerReference '), 1);
      expect(_text(DocxDocument.open(bytes).sections.last.footer), 'First');
    });

    test('with no own reference do nothing and record nothing', () {
      final Uint8List input = _inheriting();
      final DocxDocument doc = DocxDocument.open(input);
      doc.sections[1].removeFooter(DocxHeaderFooterType.primary);
      doc.sections[0].removeHeader(DocxHeaderFooterType.primary);
      doc.sections[0].removeFooter(DocxHeaderFooterType.first);
      expect(changeLogOf(doc).hasChanges, isFalse);
      _expectUnchanged(input, doc);
    });

    test('a broken reference stays', () {
      final Uint8List input = _docx(
        '${_p('A')}<w:sectPr>${_h('default', 'rId9')}</w:sectPr>',
      );
      final DocxDocument doc = DocxDocument.open(input);
      doc.sections.single.removeHeader(DocxHeaderFooterType.primary);
      expect(changeLogOf(doc).hasChanges, isFalse);
      _expectUnchanged(input, doc);
    });

    test('every reference of the type that counts goes', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '${_p('A')}<w:sectPr>${_h('default', 'rId1')}'
          '${_h('default', 'rId1')}${_h('first', 'rId1')}</w:sectPr>',
          rels: _rel('rId1', 'header1.xml'),
          parts: <String, String>{'word/header1.xml': _hdr(_p('H'))},
        ),
      );
      final DocxSection section = doc.sections.single;
      section.removeHeader(DocxHeaderFooterType.primary);
      expect(section.header.blocks, isEmpty);
      expect(section.header.isInherited, isFalse);
      expect(_text(section.firstHeader), 'H');
    });

    test('a removed new story is not created, and an undo brings it back', () {
      final DocxDocument doc = DocxDocument();
      final DocxSection section = doc.sections.single;
      final DocxHeaderFooter footer = section.footer;
      footer.addParagraph('x');
      final ChangeSet set = editsOf(
        doc,
      ).transaction(() => section.removeFooter(DocxHeaderFooterType.primary));
      expect(section.footer.blocks, isEmpty);
      expect(identical(section.footer, footer), isFalse);
      expect(
        readDocxText(doc.save().bytes).keys,
        isNot(contains('word/footer1.xml')),
      );
      changeLogOf(doc).revertSet(set);
      expect(identical(section.footer, footer), isTrue);
      expect(readDocxText(doc.save().bytes).keys, contains('word/footer1.xml'));
    });

    test('turn nothing off', () {
      final DocxDocument doc = DocxDocument();
      final DocxSection section = doc.sections.single;
      section.firstHeader.addParagraph('x');
      section.removeHeader(DocxHeaderFooterType.first);
      expect(section.titlePage, isTrue);
    });
  });

  group('a first story turns itself on (Ruling 6)', () {
    test('the first content sets titlePage on the section', () {
      final DocxDocument doc = DocxDocument();
      final DocxSection section = doc.sections.single;
      expect(section.titlePage, isFalse);
      section.firstFooter.addParagraph('x');
      expect(section.titlePage, isTrue);
      final Uint8List bytes = doc.save().bytes;
      final String main = readDocxText(bytes)['word/document.xml']!;
      expect(main, contains('<w:titlePg/>'));
      expect(main, contains('w:type="first"'));
      expect(DocxDocument.open(bytes).sections.single.titlePage, isTrue);
    });

    test('own sets it', () {
      final DocxDocument doc = DocxDocument();
      final DocxSection section = doc.sections.single;
      section.ownHeader(DocxHeaderFooterType.first);
      expect(section.titlePage, isTrue);
    });

    test('own sets it on the section asked, not on others of the part', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '${_break('One', _h('first', 'rId1'))}${_p('Two')}'
          '<w:sectPr>${_h('first', 'rId1')}</w:sectPr>',
          rels: _rel('rId1', 'header1.xml'),
          parts: <String, String>{'word/header1.xml': _hdr(_p('F'))},
        ),
      );
      final List<DocxSection> sections = doc.sections;
      sections[1].ownHeader(DocxHeaderFooterType.first);
      expect(sections[0].titlePage, isFalse);
      expect(sections[1].titlePage, isTrue);
    });

    test('own of a first story the section has sets it too', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '${_p('A')}<w:sectPr>${_h('first', 'rId1')}</w:sectPr>',
          rels: _rel('rId1', 'header1.xml'),
          parts: <String, String>{'word/header1.xml': _hdr(_p('F'))},
        ),
      );
      final DocxSection section = doc.sections.single;
      expect(section.titlePage, isFalse);
      section.ownHeader(DocxHeaderFooterType.first);
      expect(section.titlePage, isTrue);
    });

    test('the first content of a story read empty sets it', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '${_p('A')}<w:sectPr>${_h('first', 'rId1')}</w:sectPr>',
          rels: _rel('rId1', 'header1.xml'),
          parts: <String, String>{'word/header1.xml': _hdr('')},
        ),
      );
      final DocxSection section = doc.sections.single;
      section.firstHeader.addParagraph('x');
      expect(section.titlePage, isTrue);
    });

    test('a story of empty paragraphs has no content yet', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '${_p('A')}<w:sectPr>${_h('first', 'rId1')}</w:sectPr>',
          rels: _rel('rId1', 'header1.xml'),
          parts: <String, String>{
            'word/header1.xml': _hdr(
              '<w:p><w:pPr><w:pStyle w:val="Header"/></w:pPr></w:p>',
            ),
          },
        ),
      );
      final DocxSection section = doc.sections.single;
      expect(section.titlePage, isFalse);
      section.firstHeader.addParagraph('x');
      expect(section.titlePage, isTrue);
    });

    test('more content of a story that has some sets nothing', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '${_p('A')}<w:sectPr>${_h('first', 'rId1')}</w:sectPr>',
          rels: _rel('rId1', 'header1.xml'),
          parts: <String, String>{'word/header1.xml': _hdr(_p('F'))},
        ),
      );
      final DocxSection section = doc.sections.single;
      section.firstHeader.addParagraph('x');
      expect(section.titlePage, isFalse);
    });

    test('a section that inherits the story keeps its own titlePage', () {
      final DocxDocument doc = DocxDocument.open(_sections(2));
      final List<DocxSection> sections = doc.sections;
      sections[0].firstHeader.addParagraph('x');
      expect(sections[1].firstHeader.isInherited, isTrue);
      sections[1].firstHeader.addParagraph('y');
      expect(sections[0].titlePage, isTrue);
      expect(sections[1].titlePage, isFalse);
    });

    test('a primary or an even story leaves titlePage alone', () {
      final DocxDocument doc = DocxDocument();
      final DocxSection section = doc.sections.single;
      section.header.addParagraph('x');
      section.evenHeader.addParagraph('x');
      expect(section.titlePage, isFalse);
    });
  });

  group('a story ends in a paragraph (Ruling 11)', () {
    /// A document with the default header [content].
    Uint8List withHeader(String content) => _docx(
      '${_p('Body')}<w:sectPr>${_h('default', 'rId1')}</w:sectPr>',
      rels: _rel('rId1', 'header1.xml'),
      parts: <String, String>{'word/header1.xml': content},
    );

    /// The header part once [edit] ran on the header of [input].
    String after(Uint8List input, void Function(DocxHeaderFooter) edit) {
      final DocxDocument doc = DocxDocument.open(input);
      edit(doc.sections.single.header);
      return readDocxText(doc.save().bytes)['word/header1.xml']!;
    }

    test('a new table gets a closing paragraph', () {
      final DocxDocument doc = DocxDocument();
      doc.sections.single.footer.addTable(columns: 1).addRow(<String?>['x']);
      final String part = readDocxText(doc.save().bytes)['word/footer1.xml']!;
      expect(part, endsWith('</w:tbl><w:p/></w:ftr>'));
    });

    test('a story that ends in a paragraph gets none', () {
      final DocxDocument doc = DocxDocument();
      doc.sections.single.footer.addParagraph('x');
      final String part = readDocxText(doc.save().bytes)['word/footer1.xml']!;
      expect(part, isNot(contains('<w:p/>')));
    });

    test('a table added after what was read gets one', () {
      final String part = after(
        withHeader(_hdr(_p('H'))),
        (DocxHeaderFooter h) => h.addTable(columns: 1).addRow(<String?>['x']),
      );
      expect(part, endsWith('</w:tbl><w:p/></w:hdr>'));
    });

    test('a story emptied gets one', () {
      final String part = after(
        withHeader(_hdr(_p('H'))),
        (DocxHeaderFooter h) => h.removeBlockAt(0),
      );
      expect(part, endsWith('<w:p/></w:hdr>'));
    });

    test('a story read without a paragraph last is kept', () {
      final Uint8List input = withHeader(_hdr(_table));
      final DocxDocument doc = DocxDocument.open(input);
      expect(doc.sections.single.header.blocks, hasLength(1));
      doc.body.addParagraph('Edit');
      expect(
        readDocxText(doc.save().bytes)['word/header1.xml'],
        readDocxText(input)['word/header1.xml'],
      );
    });

    test('a story read empty is kept', () {
      final Uint8List input = withHeader(_hdr(''));
      final DocxDocument doc = DocxDocument.open(input);
      expect(doc.sections.single.header.blocks, isEmpty);
      doc.body.addParagraph('Edit');
      expect(
        readDocxText(doc.save().bytes)['word/header1.xml'],
        readDocxText(input)['word/header1.xml'],
      );
    });

    test('such a story changed gets one, and an undo keeps it as read', () {
      final Uint8List input = withHeader(_hdr('$_table$_table'));
      final DocxDocument doc = DocxDocument.open(input);
      final DocxHeaderFooter header = doc.sections.single.header;
      final ChangeSet set = editsOf(
        doc,
      ).transaction(() => header.removeBlockAt(1));
      expect(
        readDocxText(doc.save().bytes)['word/header1.xml'],
        endsWith('</w:tbl><w:p/></w:hdr>'),
      );
      changeLogOf(doc).revertSet(set);
      expect(
        readDocxText(doc.save().bytes)['word/header1.xml'],
        readDocxText(input)['word/header1.xml'],
      );
    });

    test('trailing range markers count as a cell\'s do', () {
      final String part = after(
        withHeader(_hdr('${_p('H')}<w:bookmarkEnd w:id="0"/>')),
        (DocxHeaderFooter h) => h.addParagraph('x'),
      );
      expect(part, isNot(contains('<w:p/>')));
      final String marked = after(
        withHeader(_hdr('$_table${_p('H')}<w:bookmarkEnd w:id="0"/>')),
        (DocxHeaderFooter h) => h.removeBlockAt(1),
      );
      expect(marked, endsWith('<w:bookmarkEnd w:id="0"/><w:p/></w:hdr>'));
    });
  });

  group('undo and failure (Review Focus 4)', () {
    /// Everything a failing transaction might leave: run [edit], make it
    /// fail on its last record, and expect the file as it was.
    void expectLeavesNothing(
      Uint8List input,
      void Function(DocxDocument) edit,
    ) {
      final DocxDocument doc = DocxDocument.open(input);
      expect(doc.sections, isNotEmpty);
      expect(
        () => editsOf(doc).transaction(() {
          edit(doc);
          throw StateError('failed');
        }),
        throwsStateError,
      );
      expect(changeLogOf(doc).hasChanges, isFalse);
      _expectUnchanged(input, doc);
    }

    test('a failed first header and addSection leave nothing', () {
      final Uint8List input = _sections(2);
      expectLeavesNothing(input, (DocxDocument doc) {
        doc.sections.first.firstHeader.addParagraph('x');
        doc.sections.last.ownFooter(DocxHeaderFooterType.even);
        doc.body.addSection().footer.addParagraph('y');
      });
      final DocxDocument doc = DocxDocument.open(input);
      expect(
        () => editsOf(doc).transaction(() {
          doc.sections.first.firstHeader.addParagraph('x');
          throw StateError('failed');
        }),
        throwsStateError,
      );
      expect(doc.sections.first.titlePage, isFalse);
      expect(doc.sections.first.firstHeader.blocks, isEmpty);
    });

    test('an edit that fails on its last record leaves nothing', () {
      final Uint8List input = _sections(1);
      final DocxDocument doc = DocxDocument.open(input);
      final DocxSection section = doc.sections.single;
      final DocxHeaderFooter first = section.firstHeader;
      int records = 0;
      editsOf(doc).afterRecord = () {
        if (++records == 3) throw StateError('failed');
      };
      expect(() => first.addParagraph('x'), throwsStateError);
      editsOf(doc).afterRecord = null;
      expect(section.titlePage, isFalse);
      expect(first.blocks, isEmpty);
      expect(identical(section.firstHeader, first), isTrue);
      _expectUnchanged(input, doc);
    });

    test('a bad index changes nothing', () {
      final Uint8List input = _sections(1);
      final DocxDocument doc = DocxDocument.open(input);
      final DocxSection section = doc.sections.single;
      expect(
        () => section.firstFooter.insertBlock(1, DocxParagraph.text('x')),
        throwsRangeError,
      );
      expect(section.titlePage, isFalse);
      _expectUnchanged(input, doc);
    });

    test('a save after an undo means what the input did', () {
      final Uint8List input = _sections(2);
      final DocxDocument doc = DocxDocument.open(input);
      final ChangeSet set = editsOf(doc).transaction(() {
        doc.sections.first.firstHeader.addParagraph('x');
        doc.sections.last.footer.addParagraph('y');
        doc.body.addSection();
      });
      changeLogOf(doc).revertSet(set);
      expect(comparePackages(input, doc.save().bytes), isEmpty);
    });

    test('an undo after a save brings back a broken reference, broken', () {
      final Uint8List input = _docx(
        '${_p('A')}<w:sectPr>${_h('default', 'rId1')}</w:sectPr>',
      );
      final DocxDocument doc = DocxDocument.open(input);
      final DocxSection section = doc.sections.single;
      final ChangeSet set = editsOf(doc).transaction(
        () => section.ownHeader(DocxHeaderFooterType.primary).addParagraph('x'),
      );
      final Map<String, String> saved = readDocxText(doc.save().bytes);
      expect(_rels(saved), isNot(contains('Id="rId1"')));
      changeLogOf(doc).revertSet(set);
      expect(section.header.blocks, isEmpty);
      final Uint8List bytes = doc.save().bytes;
      expect(
        readDocxText(bytes)['word/document.xml'],
        contains(_h('default', 'rId1')),
      );
      expect(DocxDocument.open(bytes).sections.single.header.blocks, isEmpty);
    });

    test('a redo gives the story and its reference back', () {
      final DocxDocument doc = DocxDocument();
      final DocxSection section = doc.sections.single;
      final DocxHeaderFooter header = section.firstHeader;
      final ChangeSet set = editsOf(
        doc,
      ).transaction(() => header.addParagraph('x'));
      changeLogOf(doc).revertSet(set);
      expect(section.firstHeader.blocks, isEmpty);
      changeLogOf(doc).reapplySet(set);
      expect(identical(section.firstHeader, header), isTrue);
      expect(_text(header), 'x');
      expect(section.titlePage, isTrue);
      expect(
        _text(DocxDocument.open(doc.save().bytes).sections.single.firstHeader),
        'x',
      );
    });

    test('an undo after a save leaves the part, with no reference', () {
      final DocxDocument doc = DocxDocument();
      final DocxSection section = doc.sections.single;
      final ChangeSet set = editsOf(
        doc,
      ).transaction(() => section.footer.addParagraph('x'));
      final Map<String, String> saved = readDocxText(doc.save().bytes);
      changeLogOf(doc).revertSet(set);
      final Uint8List bytes = doc.save().bytes;
      final Map<String, String> text = readDocxText(bytes);
      expect(text.keys, contains('word/footer1.xml'));
      expect(_rels(text), _rels(saved));
      expect(text['word/document.xml'], isNot(contains('footerReference')));
      expect(DocxDocument.open(bytes).sections.single.footer.blocks, isEmpty);

      changeLogOf(doc).reapplySet(set);
      expect(doc.save().bytes, isNotEmpty);
      expect(readDocxText(doc.save().bytes), saved);
    });
  });
}

/// A sink that collects what it is given in [_out].
final class _BytesSink implements Sink<List<int>> {
  _BytesSink(this._out);

  final BytesBuilder _out;

  @override
  void add(List<int> data) => _out.add(data);

  @override
  void close() {}
}
