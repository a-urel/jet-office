// Tests the section model: what `sections` lists, what a section reads and
// writes, how `addSection` ends the last section, that a break stays in its
// document, and what `addTable` takes from the last section. They build
// documents in memory, so they run on the web as well.
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart'
    show editsOf, isBodyLoaded;
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:test/test.dart';

import '../support/docx_builder.dart';
import '../support/styles_documents.dart';

const String _decls = 'xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}"';

const String _margins =
    '<w:pgMar w:top="1417" w:right="1417" w:bottom="1417" w:left="1417" '
    'w:header="708" w:footer="708" w:gutter="0"/>';

/// The `w:sectPr` of the owner's `blank.docx`.
const String _a4 =
    '<w:sectPr w:rsidR="00365787"><w:pgSz w:w="11906" w:h="16838"/>$_margins'
    '<w:cols w:space="708"/><w:docGrid w:linePitch="360"/></w:sectPr>';

/// A paragraph that holds [text].
String _p(String text) => '<w:p><w:r><w:t>$text</w:t></w:r></w:p>';

/// A paragraph that holds [text] and ends a section of the page width
/// [width], in twips.
String _break(String text, int width) =>
    '<w:p><w:pPr><w:sectPr><w:pgSz w:w="$width" w:h="16838"/></w:sectPr>'
    '</w:pPr><w:r><w:t>$text</w:t></w:r></w:p>';

/// A table of one cell that holds [blocks].
String _table(String blocks) =>
    '<w:tbl><w:tblGrid><w:gridCol w:w="100"/></w:tblGrid><w:tr><w:tc>$blocks'
    '</w:tc></w:tr></w:tbl>';

/// The document whose part is [xml].
DocxDocument _openXml(String xml) =>
    DocxDocument.open(buildDocx(document: xml));

/// The document whose body holds [body].
DocxDocument _open(String body) =>
    _openXml('<w:document $_decls><w:body>$body</w:body></w:document>');

/// The main part of [doc] as saved.
String _main(DocxDocument doc) =>
    readDocxText(doc.save().bytes)['word/document.xml']!;

/// What the saved `w:body` of [doc] holds.
String _saved(DocxDocument doc) {
  final String xml = _main(doc);
  return xml.substring(
    xml.indexOf('<w:body>') + '<w:body>'.length,
    xml.indexOf('</w:body>'),
  );
}

/// The page widths of the sections of [doc], in points.
List<double?> _widths(DocxDocument doc) => <double?>[
  for (final DocxSection s in doc.sections) s.pageSize?.widthPt,
];

void main() {
  group('sections', () {
    test('a new document has one A4 section with the margins of the file', () {
      final DocxSection section = DocxDocument().sections.single;
      expect(section.pageSize, DocxPageSize.a4());
      expect(
        section.margins,
        DocxPageMargins(
          top: 70.85,
          right: 70.85,
          bottom: 70.85,
          left: 70.85,
          header: 35.4,
          footer: 35.4,
          gutter: 0,
        ),
      );
      expect(section.columns, DocxColumns(spacingPt: 35.4));
      expect(section.textWidthPt, 453.6);
    });

    test('stray text in a final w:sectPr is dropped when it is edited', () {
      const String stray =
          '<w:sectPr>junk<w:pgSz w:w="1000" w:h="2000"/>'
          '</w:sectPr>';
      final DocxDocument kept = _open('${_p('a')}$stray');
      expect(_saved(kept), contains('junk'));
      final DocxDocument doc = _open('${_p('a')}$stray');
      doc.sections.single.pageSize = DocxPageSize.a4();
      expect(_saved(doc), isNot(contains('junk')));
    });

    test('a body of two breaks gives three sections, in order', () {
      final DocxDocument doc = _open(
        '${_break('a', 1000)}${_p('b')}${_break('c', 2000)}${_p('d')}$_a4',
      );
      expect(_widths(doc), <double>[50, 100, 595.3]);
      final List<DocxBlock> blocks = doc.body.blocks;
      expect((blocks[0] as DocxParagraph).section, same(doc.sections[0]));
      expect((blocks[1] as DocxParagraph).section, isNull);
      expect((blocks[2] as DocxParagraph).section, same(doc.sections[1]));
    });

    test('a section is the same object every time', () {
      final DocxDocument doc = _open('${_break('a', 1000)}$_a4');
      expect(doc.sections.first, same(doc.sections.first));
      expect(doc.sections.last, same(doc.sections.last));
    });

    test('the list cannot be changed and is a snapshot', () {
      final DocxDocument doc = _open('${_p('a')}$_a4');
      final List<DocxSection> before = doc.sections;
      expect(() => before.add(before.first), throwsUnsupportedError);
      doc.body.addSection();
      expect(before, hasLength(1));
      expect(doc.sections, hasLength(2));
    });

    test('it loads the body and throws what the body throws', () {
      final DocxDocument doc = _open(_p('a'));
      expect(isBodyLoaded(doc), isFalse);
      expect(doc.sections, hasLength(1));
      expect(isBodyLoaded(doc), isTrue);
      final DocxDocument broken = _openXml('<w:document $_decls><w:body>');
      expect(() => broken.sections, throwsA(isA<DocxReadException>()));
    });

    test('a body without a final sectPr has a last section of no values', () {
      final DocxDocument doc = _open(_p('a'));
      final DocxSection section = doc.sections.single;
      expect(section.pageSize, isNull);
      expect(section.margins, isNull);
      expect(section.columns, isNull);
      expect(section.start, isNull);
      expect(section.titlePage, isFalse);
      expect(section.verticalAlignment, isNull);
      expect(section.pageNumbering, isNull);
      expect(section.lineNumbering, isNull);
      expect(section.textWidthPt, isNull);
    });

    test('that section is written only once something is set', () {
      final DocxDocument doc = _open(_p('a'));
      doc.body.addParagraph('b');
      expect(_saved(doc), '${_p('a')}${_p('b')}');
      final DocxSection section = doc.sections.single;
      section.verticalAlignment = DocxSectionVerticalAlignment.center;
      expect(
        _saved(doc),
        '${_p('a')}${_p('b')}<w:sectPr><w:vAlign w:val="center"/></w:sectPr>',
      );
      section.verticalAlignment = null;
      expect(_saved(doc), '${_p('a')}${_p('b')}');
    });

    test('a document without a body gains one for a value set', () {
      final DocxDocument doc = _openXml('<w:document $_decls/>');
      final DocxSection section = doc.sections.single;
      section.titlePage = true;
      expect(_saved(doc), '<w:sectPr><w:titlePg/></w:sectPr>');
    });

    test('a mid-body sectPr stays an opaque block and starts no section', () {
      const String middle = '<w:sectPr><w:cols/></w:sectPr>';
      final DocxDocument doc = _open('$middle${_p('a')}$_a4');
      expect(doc.body.blocks.first, isA<DocxOpaqueBlock>());
      expect(doc.sections, hasLength(1));
      doc.body.addParagraph('b');
      expect(_saved(doc), '$middle${_p('a')}${_p('b')}$_a4');
    });

    test('a sectPr in a cell or a content control starts no section', () {
      final String inCell = _table(_break('a', 1000));
      final String inSdt =
          '<w:sdt><w:sdtContent>${_break('b', 2000)}</w:sdtContent></w:sdt>';
      final DocxDocument doc = _open('$inCell$inSdt${_p('c')}$_a4');
      expect(doc.sections, hasLength(1));
      final DocxTable table = doc.body.blocks.first as DocxTable;
      final DocxTableCell cell = table.rows.single.cells.single;
      expect((cell.blocks.single as DocxParagraph).section, isNull);
      doc.body.addParagraph('d');
      expect(_saved(doc), '$inCell$inSdt${_p('c')}${_p('d')}$_a4');
    });

    test('removing a paragraph with a break removes its section', () {
      final DocxDocument doc = _open(
        '${_break('a', 1000)}${_p('b')}${_break('c', 2000)}$_a4',
      );
      final ChangeSet set = editsOf(
        doc,
      ).transaction(() => doc.body.removeBlockAt(0));
      expect(_widths(doc), <double>[100, 595.3]);
      editsOf(doc).log.revertSet(set);
      expect(_widths(doc), <double>[50, 100, 595.3]);
    });

    test('a break moved out of a cell starts a section', () {
      final DocxDocument doc = _open('${_table(_break('a', 1000))}$_a4');
      final DocxTable table = doc.body.blocks.first as DocxTable;
      final DocxTableCell cell = table.rows.single.cells.single;
      final DocxParagraph paragraph = cell.blocks.single as DocxParagraph;
      cell.removeBlockAt(0);
      doc.body.insertBlock(0, paragraph);
      expect(_widths(doc), <double>[50, 595.3]);
      expect(paragraph.section, same(doc.sections.first));
    });
  });

  group('DocxSection', () {
    test('reads every value', () {
      final DocxDocument doc = _open(
        '<w:sectPr><w:type w:val="evenPage"/>'
        '<w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/>'
        '<w:pgMar w:top="-20" w:right="40" w:bottom="60" w:left="80" '
        'w:header="100" w:footer="120" w:gutter="140"/>'
        '<w:lnNumType w:countBy="2" w:start="1" w:distance="20" '
        'w:restart="newPage"/>'
        '<w:pgNumType w:fmt="upperRoman" w:start="3"/>'
        '<w:cols w:num="2" w:space="360" w:sep="1"/>'
        '<w:vAlign w:val="both"/><w:titlePg/></w:sectPr>',
      );
      final DocxSection section = doc.sections.single;
      expect(section.start, DocxSectionStart.evenPage);
      expect(section.pageSize, DocxPageSize.a4(landscape: true));
      expect(section.margins!.topPt, -1);
      expect(section.lineNumbering!.countBy, 2);
      expect(section.lineNumbering!.restart, DocxLineNumberRestart.newPage);
      expect(
        section.pageNumbering,
        DocxPageNumbering(format: DocxNumberFormat.upperRoman, start: 3),
      );
      expect(
        section.columns,
        DocxColumns(count: 2, spacingPt: 18, separator: true),
      );
      expect(section.verticalAlignment, DocxSectionVerticalAlignment.both);
      expect(section.titlePage, isTrue);
    });

    test('textWidthPt takes the side margins and the gutter off the page', () {
      final DocxDocument doc = _open(
        '<w:sectPr><w:pgSz w:w="2000" w:h="3000"/><w:pgMar w:top="1" '
        'w:right="200" w:bottom="1" w:left="300" w:header="0" w:footer="0" '
        'w:gutter="100"/></w:sectPr>',
      );
      expect(doc.sections.single.textWidthPt, 70);
    });

    test('textWidthPt is null when the page or a margin is unread', () {
      final DocxDocument noMargins = _open(
        '<w:sectPr><w:pgSz w:w="2000" w:h="3000"/></w:sectPr>',
      );
      expect(noMargins.sections.single.textWidthPt, isNull);
      final DocxDocument noPage = _open('<w:sectPr>$_margins</w:sectPr>');
      expect(noPage.sections.single.textWidthPt, isNull);
      final DocxDocument badPage = _open(
        '<w:sectPr><w:pgSz w:w="1in" w:h="3000"/>$_margins</w:sectPr>',
      );
      expect(badPage.sections.single.textWidthPt, isNull);
    });

    test('a child the model cannot type reads null and stays', () {
      const String odd =
          '<w:sectPr><w:pgSz w:w="1in" w:h="3000"/><w:titlePg w:val="x"/>'
          '</w:sectPr>';
      final DocxDocument doc = _open('${_p('a')}$odd');
      final DocxSection section = doc.sections.single;
      expect(section.pageSize, isNull);
      expect(section.titlePage, isFalse);
      section.titlePage = false;
      section.pageSize = null;
      doc.body.addParagraph('b');
      expect(_saved(doc), '${_p('a')}${_p('b')}$odd');
    });

    test('setting pageSize changes only w:pgSz', () {
      final DocxDocument doc = _open('${_p('a')}$_a4');
      doc.sections.single.pageSize = DocxPageSize.a4(landscape: true);
      expect(
        _saved(doc),
        '${_p('a')}${_a4.replaceFirst('<w:pgSz w:w="11906" w:h="16838"/>', '<w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/>')}',
      );
    });

    test('a set on a section of a break is written in its paragraph', () {
      final DocxDocument doc = _open('${_break('a', 1000)}$_a4');
      doc.sections.first.start = DocxSectionStart.continuous;
      expect(
        _saved(doc),
        '<w:p><w:pPr><w:sectPr><w:type w:val="continuous"/>'
        '<w:pgSz w:w="1000" w:h="16838"/></w:sectPr></w:pPr>'
        '<w:r><w:t>a</w:t></w:r></w:p>$_a4',
      );
    });

    test('every value is set and reads back', () {
      final DocxSection section = _open(_p('a')).sections.single;
      final DocxPageMargins margins = DocxPageMargins(
        top: 1,
        right: 2,
        bottom: 3,
        left: 4,
        header: 5,
        footer: 6,
        gutter: 7,
      );
      section
        ..pageSize = DocxPageSize.letter()
        ..margins = margins
        ..columns = DocxColumns(count: 3)
        ..start = DocxSectionStart.oddPage
        ..titlePage = true
        ..verticalAlignment = DocxSectionVerticalAlignment.bottom
        ..pageNumbering = DocxPageNumbering(start: 9)
        ..lineNumbering = DocxLineNumbering(countBy: 5);
      expect(section.pageSize, DocxPageSize.letter());
      expect(section.margins, margins);
      expect(section.columns, DocxColumns(count: 3));
      expect(section.start, DocxSectionStart.oddPage);
      expect(section.titlePage, isTrue);
      expect(section.verticalAlignment, DocxSectionVerticalAlignment.bottom);
      expect(section.pageNumbering, DocxPageNumbering(start: 9));
      expect(section.lineNumbering, DocxLineNumbering(countBy: 5));
      expect(section.textWidthPt, 612 - 2 - 4 - 7);
    });

    test('titlePage set to false removes the child', () {
      final DocxDocument doc = _open(
        '${_p('a')}<w:sectPr><w:titlePg/></w:sectPr>',
      );
      doc.sections.single.titlePage = false;
      expect(_saved(doc), '${_p('a')}<w:sectPr/>');
    });

    test('titlePage set to what it reads records nothing', () {
      final DocxDocument doc = _open(
        '${_p('a')}<w:sectPr><w:titlePg w:val="0"/></w:sectPr>',
      );
      doc.sections.single.titlePage = false;
      expect(editsOf(doc).log.hasChanges, isFalse);
    });

    test('a set is one change, and the save writes the model', () {
      final DocxDocument doc = _open('${_p('a')}$_a4');
      final DocxSection section = doc.sections.single;
      final ChangeSet set = editsOf(doc).transaction(() {
        section.start = DocxSectionStart.continuous;
      });
      expect(set.changes, hasLength(1));
      expect(editsOf(doc).log.hasChanges, isTrue);
      expect(_saved(doc), contains('<w:type w:val="continuous"/>'));
    });

    test('undoing a set restores the bytes of the part', () {
      final String body = '${_break('a', 1000)}$_a4';
      final DocxDocument doc = _open(body);
      final ChangeSet set = editsOf(doc).transaction(() {
        doc.sections.first.pageSize = DocxPageSize.letter();
        doc.sections.last.pageSize = DocxPageSize.a4(landscape: true);
      });
      editsOf(doc).log.revertSet(set);
      expect(_saved(doc), body);
      editsOf(doc).log.reapplySet(set);
      expect(doc.sections.first.pageSize, DocxPageSize.letter());
      expect(doc.sections.last.pageSize, DocxPageSize.a4(landscape: true));
    });

    test('a failed edit leaves the section as it was', () {
      final DocxDocument doc = _open('${_p('a')}$_a4');
      final DocxSection section = doc.sections.single;
      editsOf(doc).afterRecord = () => throw StateError('failed');
      expect(
        () => section.start = DocxSectionStart.continuous,
        throwsStateError,
      );
      editsOf(doc).afterRecord = null;
      expect(section.start, isNull);
      expect(editsOf(doc).log.hasChanges, isFalse);
    });

    test('references survive an edit, and any other child too', () {
      const String kept =
          '<w:headerReference w:type="default" r:id="rId7"/>'
          '<w:footerReference w:type="first" r:id="rId8"/>'
          '<w:footnotePr><w:numRestart w:val="eachPage"/></w:footnotePr>';
      const String after = '<w:pgBorders w:offsetFrom="page"/>';
      final DocxDocument doc = _open(
        '<w:p><w:pPr><w:sectPr>$kept<w:pgSz w:w="1000" w:h="16838"/>$after'
        '</w:sectPr></w:pPr></w:p>'
        '<w:sectPr>$kept<w:pgSz w:w="2000" w:h="16838"/>$after</w:sectPr>',
      );
      for (final DocxSection section in doc.sections) {
        section.pageSize = DocxPageSize.letter();
      }
      const String pgSz = '<w:pgSz w:w="12240" w:h="15840"/>';
      expect(
        _saved(doc),
        '<w:p><w:pPr><w:sectPr>$kept$pgSz$after</w:sectPr></w:pPr></w:p>'
        '<w:sectPr>$kept$pgSz$after</w:sectPr>',
      );
    });

    test('references keep the order of the file, as Word mixes them', () {
      const String references =
          '<w:headerReference w:type="even" r:id="rId1"/>'
          '<w:headerReference w:type="default" r:id="rId2"/>'
          '<w:footerReference w:type="even" r:id="rId3"/>'
          '<w:footerReference w:type="default" r:id="rId4"/>'
          '<w:headerReference w:type="first" r:id="rId5"/>'
          '<w:footerReference w:type="first" r:id="rId6"/>';
      final DocxDocument doc = _open(
        '${_p('a')}<w:sectPr>$references<w:cols/></w:sectPr>',
      );
      doc.sections.single.start = DocxSectionStart.continuous;
      expect(
        _saved(doc),
        '${_p('a')}<w:sectPr>$references<w:type w:val="continuous"/><w:cols/>'
        '</w:sectPr>',
      );
    });

    test('a final sectPr of its own prefix reads and writes the same', () {
      final DocxDocument doc = _open(
        '${_p('a')}<x:sectPr xmlns:x="${Ns.w}" xmlns:y="urn:y" y:z="1">'
        '<x:pgSz x:w="2000" x:h="3000"/><y:kept/></x:sectPr>',
      );
      final DocxSection section = doc.sections.single;
      expect(section.pageSize, DocxPageSize(100, 150));
      section.start = DocxSectionStart.continuous;
      final String saved = _saved(doc);
      expect(saved, contains('xmlns:y="urn:y"'));
      expect(saved, contains('y:z="1"'));
      expect(saved, contains('<y:kept/>'));
      final DocxSection again = DocxDocument.open(
        doc.save().bytes,
      ).sections.single;
      expect(again.pageSize, DocxPageSize(100, 150));
      expect(again.start, DocxSectionStart.continuous);
    });
  });

  group('addSection', () {
    test('the last paragraph takes the break', () {
      final DocxDocument doc = _open('${_p('a')}$_a4');
      final DocxSection held = doc.sections.single;
      final DocxSection added = doc.body.addSection();
      expect(doc.body.blocks, hasLength(1));
      final DocxParagraph paragraph = doc.body.blocks.single as DocxParagraph;
      expect(paragraph.section, same(held));
      expect(doc.sections, <DocxSection>[held, added]);
      expect(
        _saved(doc),
        '<w:p><w:pPr>$_a4</w:pPr><w:r><w:t>a</w:t></w:r></w:p>'
        '<w:sectPr><w:type w:val="nextPage"/>'
        '<w:pgSz w:w="11906" w:h="16838"/>$_margins<w:cols w:space="708"/>'
        '<w:docGrid w:linePitch="360"/></w:sectPr>',
      );
    });

    test('a body ending in a table gets an empty paragraph for the break', () {
      final DocxDocument doc = _open('${_table(_p('a'))}$_a4');
      final DocxSection held = doc.sections.single;
      doc.body.addSection();
      expect(doc.body.blocks, hasLength(2));
      final DocxParagraph paragraph = doc.body.blocks.last as DocxParagraph;
      expect(paragraph.text, '');
      expect(paragraph.section, same(held));
    });

    test('a last paragraph that has a break gets one after it', () {
      final DocxDocument doc = _open('${_break('a', 1000)}$_a4');
      final DocxSection first = doc.sections.first;
      final DocxSection held = doc.sections.last;
      doc.body.addSection();
      expect(doc.body.blocks, hasLength(2));
      expect((doc.body.blocks.first as DocxParagraph).section, same(first));
      final DocxParagraph paragraph = doc.body.blocks.last as DocxParagraph;
      expect(paragraph.text, '');
      expect(paragraph.section, same(held));
      expect(doc.sections, hasLength(3));
    });

    test('an empty body or an opaque block gets an empty paragraph', () {
      final DocxDocument empty = _open(_a4);
      empty.body.addSection();
      expect(empty.body.blocks.single, isA<DocxParagraph>());
      final DocxDocument opaque = _open('<w:bookmarkEnd w:id="1"/>$_a4');
      opaque.body.addSection();
      expect(opaque.body.blocks, hasLength(2));
      expect(opaque.sections, hasLength(2));
    });

    test('a held section keeps its values and stays editable', () {
      final DocxDocument doc = _open('${_p('a')}$_a4');
      final DocxSection held = doc.sections.single;
      final DocxSection added = doc.body.addSection();
      expect(held.start, isNull);
      held.pageSize = DocxPageSize.letter();
      added.start = DocxSectionStart.oddPage;
      expect(added.pageSize, DocxPageSize.a4());
      final String saved = _saved(doc);
      expect(
        saved,
        startsWith(
          '<w:p><w:pPr><w:sectPr w:rsidR="00365787">'
          '<w:pgSz w:w="12240" w:h="15840"/>',
        ),
      );
      expect(saved, contains('<w:sectPr><w:type w:val="oddPage"/>'));
    });

    test('the new section copies what Ruling 8 lists, and nothing else', () {
      final DocxDocument doc = _open(
        '${_p('a')}<w:sectPr w:rsidR="00A1">'
        '<w:headerReference w:type="default" r:id="rId7"/>'
        '<w:footerReference w:type="default" r:id="rId8"/>'
        '<w:footnotePr><w:numRestart w:val="eachPage"/></w:footnotePr>'
        '<w:type w:val="evenPage"/><w:pgSz w:w="2000" w:h="3000"/>$_margins'
        '<w:pgBorders w:offsetFrom="page"/>'
        '<w:lnNumType w:countBy="2"/>'
        '<w:pgNumType w:fmt="upperRoman" w:start="3" w:chapStyle="1"/>'
        '<w:cols w:num="2" w:space="360"/><w:vAlign w:val="center"/>'
        '<w:titlePg/><w:docGrid w:linePitch="360"/></w:sectPr>',
      );
      final DocxSection held = doc.sections.single;
      final DocxSection added = doc.body.addSection(
        start: DocxSectionStart.continuous,
      );
      expect(added.start, DocxSectionStart.continuous);
      expect(added.pageSize, held.pageSize);
      expect(added.margins, held.margins);
      expect(added.columns, held.columns);
      expect(added.lineNumbering, held.lineNumbering);
      expect(added.verticalAlignment, held.verticalAlignment);
      expect(added.titlePage, isFalse);
      expect(
        added.pageNumbering,
        DocxPageNumbering(format: DocxNumberFormat.upperRoman),
      );
      expect(held.start, DocxSectionStart.evenPage);
      expect(held.titlePage, isTrue);
      expect(held.pageNumbering!.start, 3);
      final String saved = _saved(doc);
      expect(
        saved.substring(saved.lastIndexOf('<w:sectPr>')),
        '<w:sectPr><w:type w:val="continuous"/>'
        '<w:pgSz w:w="2000" w:h="3000"/>$_margins'
        '<w:lnNumType w:countBy="2"/>'
        '<w:pgNumType w:fmt="upperRoman" w:chapStyle="1"/>'
        '<w:cols w:num="2" w:space="360"/><w:vAlign w:val="center"/>'
        '<w:docGrid w:linePitch="360"/></w:sectPr>',
      );
    });

    test('a page numbering of only a start is not copied', () {
      final DocxDocument doc = _open(
        '${_p('a')}<w:sectPr><w:pgNumType w:start="3"/></w:sectPr>',
      );
      final DocxSection added = doc.body.addSection();
      expect(added.pageNumbering, isNull);
      expect(
        _saved(doc),
        endsWith('<w:sectPr><w:type w:val="nextPage"/></w:sectPr>'),
      );
    });

    test('a page numbering the model cannot type is not copied', () {
      final DocxDocument doc = _open(
        '${_p('a')}<w:sectPr><w:pgNumType w:fmt="chicago" w:start="3"/>'
        '</w:sectPr>',
      );
      doc.body.addSection();
      expect(
        _saved(doc),
        endsWith('</w:p><w:sectPr><w:type w:val="nextPage"/></w:sectPr>'),
      );
    });

    test('the copy takes the values set since the file was read', () {
      final DocxDocument doc = _open('${_p('a')}$_a4');
      final DocxSection held = doc.sections.single;
      held
        ..pageSize = DocxPageSize.letter()
        ..columns = null
        ..pageNumbering = DocxPageNumbering(start: 4)
        ..titlePage = true;
      final DocxSection added = doc.body.addSection();
      expect(added.pageSize, DocxPageSize.letter());
      expect(added.columns, isNull);
      expect(added.pageNumbering, isNull);
      expect(added.titlePage, isFalse);
      expect(held.pageNumbering!.start, 4);
    });

    test('a last section of no values still writes its break', () {
      final DocxDocument doc = _open(_p('a'));
      final DocxSection held = doc.sections.single;
      final DocxSection added = doc.body.addSection();
      expect(added.start, DocxSectionStart.nextPage);
      expect(held.pageSize, isNull);
      expect(
        _saved(doc),
        '<w:p><w:pPr><w:sectPr/></w:pPr><w:r><w:t>a</w:t></w:r></w:p>'
        '<w:sectPr><w:type w:val="nextPage"/></w:sectPr>',
      );
    });

    test('what is added after it joins the new last section', () {
      final DocxDocument doc = _open('${_p('a')}$_a4');
      doc.body.addSection();
      doc.body.addParagraph('b');
      final DocxDocument again = DocxDocument.open(doc.save().bytes);
      expect(again.sections, hasLength(2));
      expect((again.body.blocks.first as DocxParagraph).section, isNotNull);
      expect((again.body.blocks.last as DocxParagraph).section, isNull);
      expect(again.sections.last.start, DocxSectionStart.nextPage);
      expect(again.sections.last.pageSize, DocxPageSize.a4());
    });

    test('two sections add up, each section held', () {
      final DocxDocument doc = _open('${_p('a')}$_a4');
      final DocxSection first = doc.sections.single;
      final DocxSection second = doc.body.addSection();
      final DocxSection third = doc.body.addSection();
      expect(doc.sections, <DocxSection>[first, second, third]);
      expect(doc.body.blocks, hasLength(2));
    });

    test('undo restores the bytes of the part, and redo the sections', () {
      for (final String body in <String>[
        '${_p('a')}$_a4',
        '${_table(_p('a'))}$_a4',
        '${_break('a', 1000)}$_a4',
        _p('a'),
      ]) {
        final DocxDocument doc = _open(body);
        final DocxSection held = doc.sections.last;
        late DocxSection added;
        final ChangeSet set = editsOf(doc).transaction(() {
          added = doc.body.addSection();
        });
        final String after = _saved(doc);
        editsOf(doc).log.revertSet(set);
        expect(doc.sections.last, same(held), reason: body);
        expect(_saved(doc), body, reason: body);
        held.start = DocxSectionStart.continuous;
        held.start = null;
        editsOf(doc).log.reapplySet(set);
        expect(doc.sections.last, same(added), reason: body);
        expect(_saved(doc), after, reason: body);
      }
    });

    test('a set on the held section is recorded after the swap', () {
      final DocxDocument doc = _open('${_p('a')}$_a4');
      final DocxSection held = doc.sections.single;
      doc.body.addSection();
      final ChangeSet set = editsOf(doc).transaction(() {
        held.start = DocxSectionStart.continuous;
      });
      expect(set.changes, hasLength(1));
    });

    test('a failure takes everything back', () {
      for (final String body in <String>[
        '${_p('a')}$_a4',
        '${_table(_p('a'))}$_a4',
      ]) {
        final DocxDocument doc = _open(body);
        final DocxSection held = doc.sections.single;
        int records = 0;
        editsOf(doc).afterRecord = () {
          if (++records == (body.startsWith('<w:tbl') ? 2 : 1)) {
            throw StateError('failed');
          }
        };
        expect(() => doc.body.addSection(), throwsStateError, reason: body);
        editsOf(doc).afterRecord = null;
        expect(doc.sections.single, same(held), reason: body);
        expect(doc.body.blocks, hasLength(1), reason: body);
        expect(editsOf(doc).log.hasChanges, isFalse, reason: body);
        expect(
          (doc.body.blocks.single is DocxParagraph)
              ? (doc.body.blocks.single as DocxParagraph).section
              : null,
          isNull,
          reason: body,
        );
      }
    });
  });

  group('a section break between documents', () {
    /// A break of [doc] taken out of its body.
    DocxParagraph taken(DocxDocument doc) {
      final DocxParagraph paragraph = doc.body.blocks.first as DocxParagraph;
      doc.body.removeBlockAt(0);
      return paragraph;
    }

    test('a read break does not go in another body', () {
      final DocxParagraph paragraph = taken(_open(_break('a', 1000)));
      final DocxDocument other = _open(_p('b'));
      expect(() => other.body.insertBlock(0, paragraph), throwsArgumentError);
      expect(
        () => other.body.replaceBlockAt(0, paragraph),
        throwsArgumentError,
      );
      expect(other.body.blocks, hasLength(1));
      expect(other.sections, hasLength(1));
      expect(editsOf(other).log.hasChanges, isFalse);
    });

    test('nor does a break addSection made there', () {
      final DocxDocument doc = _open('<w:bookmarkEnd w:id="1"/>$_a4');
      doc.body.addSection();
      final DocxParagraph paragraph = doc.body.blocks.last as DocxParagraph;
      doc.body.removeBlockAt(1);
      expect(
        () => _open(_p('b')).body.insertBlock(0, paragraph),
        throwsArgumentError,
      );
    });

    test('it goes back in its own body', () {
      final DocxDocument doc = _open('${_break('a', 1000)}$_a4');
      final DocxParagraph paragraph = taken(doc);
      doc.body.insertBlock(0, paragraph);
      expect(doc.sections, hasLength(2));
    });

    test('a block still in a body throws StateError first', () {
      final DocxDocument doc = _open(_break('a', 1000));
      expect(
        () => _open(_p('b')).body.insertBlock(0, doc.body.blocks.first),
        throwsStateError,
      );
    });

    test('in a cell it stays as read, and starts no section', () {
      final DocxParagraph paragraph = taken(_open(_break('a', 1000)));
      final DocxDocument other = _open('${_table(_p('b'))}$_a4');
      final DocxTable table = other.body.blocks.first as DocxTable;
      table.rows.single.cells.single.insertBlock(0, paragraph);
      expect(other.sections, hasLength(1));
      expect(paragraph.section, isNull);
      expect(_saved(other), contains('<w:pgSz w:w="1000" w:h="16838"/>'));
    });

    test('a paragraph with no break moves as before', () {
      final DocxDocument doc = _open(_p('a'));
      final DocxParagraph paragraph = taken(doc);
      final DocxDocument other = _open(_p('b'));
      other.body.insertBlock(0, paragraph);
      expect(other.body.blocks, hasLength(2));
    });
  });

  group('addTable', () {
    /// The last table of [doc]'s widths, in twips.
    List<int> grid(DocxDocument doc, {int columns = 2}) => <int>[
      for (final double? w
          in doc.body.addTable(columns: columns).gridColumnsPt!)
        (w! * 20).round(),
    ];

    test('a blank document shares 9062 twips still', () {
      expect(grid(DocxDocument()), <int>[4531, 4531]);
    });

    test('a landscape section gives the columns its width', () {
      final DocxDocument doc = DocxDocument();
      doc.sections.last.pageSize = DocxPageSize.a4(landscape: true);
      // 16838 less the margins of 1417 is 14004, and Word's Insert Table
      // stays 10 twips inside it, as it does on the blank page.
      expect(grid(doc), <int>[6997, 6997]);
      expect(grid(doc, columns: 3), <int>[4664, 4664, 4664]);
    });

    test('it takes the last section, not the first', () {
      final DocxDocument doc = _open(
        '<w:p><w:pPr><w:sectPr><w:pgSz w:w="30000" w:h="1000"/>$_margins'
        '</w:sectPr></w:pPr></w:p>'
        '<w:sectPr><w:pgSz w:w="10000" w:h="1000"/>$_margins</w:sectPr>',
      );
      expect(grid(doc), <int>[3578, 3578]);
    });

    test('a section that does not read shares 9062 twips', () {
      expect(grid(_open(_p('a'))), <int>[4531, 4531]);
      expect(
        grid(_open('<w:sectPr><w:pgSz w:w="2000" w:h="1"/></w:sectPr>')),
        <int>[4531, 4531],
      );
    });

    test('a text width that gives no column a twip shares 9062 twips', () {
      final DocxDocument doc = _open(
        '<w:sectPr><w:pgSz w:w="2000" w:h="3000"/>$_margins</w:sectPr>',
      );
      expect(doc.sections.single.textWidthPt, lessThan(0));
      expect(grid(doc), <int>[4531, 4531]);
    });

    test('columnWidthsPt still wins', () {
      final DocxDocument doc = DocxDocument();
      doc.sections.last.pageSize = DocxPageSize.a4(landscape: true);
      expect(
        doc.body
            .addTable(columns: 1, columnWidthsPt: <double>[10])
            .gridColumnsPt,
        <double>[10],
      );
    });

    test('a table made by hand or nested stays as it was', () {
      final DocxDocument doc = DocxDocument();
      doc.sections.last.pageSize = DocxPageSize.a4(landscape: true);
      expect(DocxTable(columns: 2).gridColumnsPt, <double>[226.55, 226.55]);
    });
  });
}
