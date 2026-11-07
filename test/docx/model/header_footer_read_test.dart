// Tests reading headers and footers: which story a section gets, through its
// own reference or a previous section's; that a story loads on first `blocks`
// and saves as read until the model writes something else; what a reference
// that names nothing does; and that a story's blocks edit and report as the
// body's do. They build documents in memory, so they run on the web as well;
// `owner_files_test.dart` reads the owner's `features.docx`.
import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart'
    show changeLogOf, editsOf;
import 'package:jet_office/src/docx/model/blocks.dart' show blockContainerOf;
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:test/test.dart';

import '../../support/read_xlsx.dart';
import '../support/docx_builder.dart';
import '../support/styles_documents.dart';

const String _decls = 'xmlns:w="${Ns.w}" xmlns:r="${Ns.rel}"';

/// A relationship of the main part.
String _rel(
  String id,
  String target, {
  String type = RelType.header,
  bool external = false,
}) =>
    '<Relationship Id="$id" Type="$type" Target="$target"'
    '${external ? ' TargetMode="External"' : ''}/>';

/// A `w:headerReference` of [type] through [id].
String _h(String type, String id) =>
    '<w:headerReference w:type="$type" r:id="$id"/>';

/// A `w:footerReference` of [type] through [id].
String _f(String type, String id) =>
    '<w:footerReference w:type="$type" r:id="$id"/>';

/// A paragraph that holds [text].
String _p(String text) => '<w:p><w:r><w:t>$text</w:t></w:r></w:p>';

/// A paragraph that holds [text] and ends a section of [references].
String _break(String text, String references) =>
    '<w:p><w:pPr><w:sectPr>$references</w:sectPr></w:pPr>'
    '<w:r><w:t>$text</w:t></w:r></w:p>';

/// A `w:hdr` that holds [content].
String _hdr(String content) => '<w:hdr $_decls>$content</w:hdr>';

/// A `w:ftr` that holds [content].
String _ftr(String content) => '<w:ftr $_decls>$content</w:ftr>';

/// A package whose body holds [body], whose main part has the relationships
/// [rels], and which has [parts] (a ZIP entry name and its text), each with
/// the content type of [types] or, for a name holding `header` or `footer`,
/// Word's.
Uint8List _docx(
  String body, {
  String rels = '',
  Map<String, String> parts = const <String, String>{},
  Map<String, String> types = const <String, String>{},
}) {
  final StringBuffer overrides = StringBuffer();
  for (final String name in parts.keys) {
    final String? type =
        types[name] ??
        (name.contains('_rels/')
            ? null
            : name.contains('header')
            ? ContentType.wmlHeader
            : name.contains('footer')
            ? ContentType.wmlFooter
            : null);
    if (type != null) {
      overrides.write('<Override PartName="/$name" ContentType="$type"/>');
    }
  }
  return buildDocx(
    document: '<w:document $_decls><w:body>$body</w:body></w:document>',
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

/// A document of one section with the default header [content].
Uint8List _withHeader(String content) => _docx(
  '${_p('Body')}<w:sectPr>${_h('default', 'rId1')}</w:sectPr>',
  rels: _rel('rId1', 'header1.xml'),
  parts: <String, String>{'word/header1.xml': content},
);

/// The text of the paragraph [index] of [story].
String _text(DocxStory story, [int index = 0]) =>
    (story.blocks[index] as DocxParagraph).text;

/// [xml] without a leading XML declaration of the package's.
String _noDeclaration(String xml) => xml.replaceFirst(
  '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
  '',
);

/// The first run of the first paragraph of [story].
DocxRun _firstRun(DocxStory story) =>
    (story.blocks.first as DocxParagraph).inlines.first as DocxRun;

/// Expects that every entry of [saved] is the one of [input], but [changed]
/// and `[Content_Types].xml`; the package writes that one itself, and gives
/// a relationships part a declaration.
void _expectSame(
  Uint8List input,
  Uint8List saved, {
  Set<String> changed = const <String>{},
}) {
  final Map<String, String> before = readDocxText(input);
  final Map<String, String> after = readDocxText(saved);
  expect(after.keys, unorderedEquals(before.keys));
  for (final String name in before.keys) {
    if (changed.contains(name) || name == '[Content_Types].xml') continue;
    expect(_noDeclaration(after[name]!), before[name], reason: name);
  }
}

void main() {
  group('the six getters', () {
    final Uint8List file = _docx(
      '${_p('Body')}<w:sectPr>'
      '${_h('even', 'rId1')}${_h('default', 'rId2')}${_h('first', 'rId3')}'
      '${_f('even', 'rId4')}${_f('default', 'rId5')}${_f('first', 'rId6')}'
      '</w:sectPr>',
      rels:
          '${_rel('rId1', 'header1.xml')}${_rel('rId2', 'header2.xml')}'
          '${_rel('rId3', 'header3.xml')}'
          '${_rel('rId4', 'footer1.xml', type: RelType.footer)}'
          '${_rel('rId5', 'footer2.xml', type: RelType.footer)}'
          '${_rel('rId6', 'footer3.xml', type: RelType.footer)}',
      parts: <String, String>{
        'word/header1.xml': _hdr(_p('even header')),
        'word/header2.xml': _hdr(_p('header')),
        'word/header3.xml': _hdr(_p('first header')),
        'word/footer1.xml': _ftr(_p('even footer')),
        'word/footer2.xml': _ftr(_p('footer')),
        'word/footer3.xml': _ftr(_p('first footer')),
      },
    );

    test('read the story of each type', () {
      final DocxSection section = DocxDocument.open(file).sections.single;
      expect(_text(section.header), 'header');
      expect(_text(section.firstHeader), 'first header');
      expect(_text(section.evenHeader), 'even header');
      expect(_text(section.footer), 'footer');
      expect(_text(section.firstFooter), 'first footer');
      expect(_text(section.evenFooter), 'even footer');
    });

    test('say what they are', () {
      final DocxSection section = DocxDocument.open(file).sections.single;
      final List<DocxHeaderFooter> stories = <DocxHeaderFooter>[
        section.header,
        section.firstHeader,
        section.evenHeader,
        section.footer,
        section.firstFooter,
        section.evenFooter,
      ];
      expect(
        <bool>[for (final DocxHeaderFooter s in stories) s.isHeader],
        <bool>[true, true, true, false, false, false],
      );
      expect(
        <DocxHeaderFooterType>[
          for (final DocxHeaderFooter s in stories) s.type,
        ],
        <DocxHeaderFooterType>[
          DocxHeaderFooterType.primary,
          DocxHeaderFooterType.first,
          DocxHeaderFooterType.even,
          DocxHeaderFooterType.primary,
          DocxHeaderFooterType.first,
          DocxHeaderFooterType.even,
        ],
      );
      expect(stories.any((DocxHeaderFooter s) => s.isInherited), isFalse);
    });

    test('a section without references has empty stories', () {
      final Uint8List input = _docx(
        _p('Body'),
        rels: _rel('rId1', 'styles.xml', type: RelType.styles),
      );
      final DocxDocument doc = DocxDocument.open(input);
      final DocxSection section = doc.sections.single;
      final DocxHeaderFooter header = section.header;
      expect(header.blocks, isEmpty);
      expect(header.isInherited, isFalse);
      expect(header.isHeader, isTrue);
      expect(section.evenFooter.blocks, isEmpty);
      expect(section.evenFooter.isHeader, isFalse);
      expect(section.evenFooter.type, DocxHeaderFooterType.even);
      _expectSame(input, doc.save().bytes);
    });

    test('the same getter gives the same story, also for no reference', () {
      final DocxSection withOne = DocxDocument.open(file).sections.single;
      expect(identical(withOne.header, withOne.header), isTrue);
      final DocxSection without = DocxDocument.open(
        _docx(_p('Body')),
      ).sections.single;
      expect(identical(without.footer, without.footer), isTrue);
    });
  });

  group('reading', () {
    // A comment, an odd declaration and a run property out of order: what
    // the model cannot write back the same.
    const String odd =
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!-- kept --><w:hdr $_decls xmlns:x="urn:x"  ><w:p><w:r><w:rPr>'
        '<w:sz w:val="20"/><w:b/></w:rPr><w:t>Odd</w:t></w:r></w:p>'
        '<!-- kept too --></w:hdr>';

    test('changes nothing at save', () {
      final Uint8List input = _withHeader(odd);
      final DocxDocument doc = DocxDocument.open(input);
      expect(_text(doc.sections.single.header), 'Odd');
      _expectSame(input, doc.save().bytes);
    });

    test('a story loads only on first blocks', () {
      final Uint8List input = _withHeader('<w:hdr $_decls><w:p>');
      final DocxDocument doc = DocxDocument.open(input);
      final DocxHeaderFooter header = doc.sections.single.header;
      expect(header.isHeader, isTrue);
      expect(header.isInherited, isFalse);
      _expectSame(input, doc.save().bytes);
      for (int i = 0; i < 2; i++) {
        expect(
          () => header.blocks,
          throwsA(
            isA<DocxReadException>().having(
              (DocxReadException e) => e.part,
              'part',
              '/word/header1.xml',
            ),
          ),
        );
      }
      expect(() => header.addParagraph('x'), throwsA(isA<DocxReadException>()));
      expect(changeLogOf(doc).hasChanges, isFalse);
      _expectSame(input, doc.save().bytes);
    });

    test('a broken story leaves the others readable', () {
      final Uint8List input = _docx(
        '<w:sectPr>${_h('default', 'rId1')}${_f('default', 'rId2')}</w:sectPr>',
        rels:
            '${_rel('rId1', 'header1.xml')}'
            '${_rel('rId2', 'footer1.xml', type: RelType.footer)}',
        parts: <String, String>{
          'word/header1.xml': '<w:hdr',
          'word/footer1.xml': _ftr(_p('Footer')),
        },
      );
      final DocxDocument doc = DocxDocument.open(input);
      expect(_text(doc.sections.single.footer), 'Footer');
    });

    test('reading leaves the relationships part of a story unread', () {
      const String rels =
          '<?xml version="1.0" encoding="UTF-8"?>\n<!-- kept -->'
          '<Relationships xmlns="$packageRelsNs"></Relationships>\n';
      final Uint8List input = _docx(
        '<w:sectPr>${_h('default', 'rId1')}</w:sectPr>',
        rels: _rel('rId1', 'header1.xml'),
        parts: <String, String>{
          'word/header1.xml': _hdr(_p('Header')),
          'word/_rels/header1.xml.rels': rels,
        },
      );
      final DocxDocument doc = DocxDocument.open(input);
      expect(_text(doc.sections.single.header), 'Header');
      expect(
        readXlsxBytes(doc.save().bytes)['word/_rels/header1.xml.rels'],
        utf8.encode(rels),
      );
    });

    test('a damaged relationships part of a story opens, reads and saves', () {
      final Uint8List input = _docx(
        '<w:sectPr>${_h('default', 'rId1')}</w:sectPr>',
        rels: _rel('rId1', 'header1.xml'),
        parts: <String, String>{
          'word/header1.xml': _hdr(_p('Header')),
          'word/_rels/header1.xml.rels': '<Relationships',
        },
      );
      final DocxDocument doc = DocxDocument.open(input);
      expect(_text(doc.sections.single.header), 'Header');
      expect(
        readXlsxBytes(doc.save().bytes)['word/_rels/header1.xml.rels'],
        utf8.encode('<Relationships'),
      );
    });

    test('a story keeps its own relationships', () {
      final Uint8List input = _docx(
        '<w:sectPr>${_h('default', 'rId1')}</w:sectPr>',
        rels: _rel('rId1', 'header1.xml'),
        parts: <String, String>{
          'word/header1.xml': _hdr(_p('Header')),
          'word/_rels/header1.xml.rels':
              '<Relationships xmlns="$packageRelsNs">'
              '${_rel('rId1', 'x', type: RelType.hyperlink, external: true)}'
              '</Relationships>',
        },
      );
      final DocxDocument doc = DocxDocument.open(input);
      _firstRun(doc.sections.single.header).text = 'New';
      final Uint8List saved = doc.save().bytes;
      _expectSame(
        input,
        saved,
        changed: <String>{'word/document.xml', 'word/header1.xml'},
      );
    });

    test('a root that is not w:hdr throws as styles does', () {
      final DocxDocument doc = DocxDocument.open(_withHeader(_ftr(_p('x'))));
      expect(
        () => doc.sections.single.header.blocks,
        throwsA(
          isA<DocxReadException>()
              .having(
                (DocxReadException e) => e.reason,
                'reason',
                DocxReadFailure.malformedXml,
              )
              .having(
                (DocxReadException e) => e.part,
                'part',
                '/word/header1.xml',
              ),
        ),
      );
    });

    test('a root that is not w:ftr throws for a footer', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '<w:sectPr>${_f('default', 'rId1')}</w:sectPr>',
          rels: _rel('rId1', 'footer1.xml', type: RelType.footer),
          parts: <String, String>{'word/footer1.xml': _hdr(_p('x'))},
        ),
      );
      expect(
        () => doc.sections.single.footer.blocks,
        throwsA(isA<DocxReadException>()),
      );
    });

    test('an empty root reads no blocks and saves as read', () {
      final Uint8List input = _withHeader('<w:hdr $_decls/>');
      final DocxDocument doc = DocxDocument.open(input);
      expect(doc.sections.single.header.blocks, isEmpty);
      _expectSame(input, doc.save().bytes);
    });

    test('elements match by namespace, not by prefix', () {
      final DocxDocument doc = DocxDocument.open(
        _withHeader(
          '<ns0:hdr xmlns:ns0="${Ns.w}"><ns0:p><ns0:r><ns0:t>Prefixed</ns0:t>'
          '</ns0:r></ns0:p></ns0:hdr>',
        ),
      );
      final DocxHeaderFooter header = doc.sections.single.header;
      expect(_text(header), 'Prefixed');
      header.addParagraph('Added');
      expect(
        readDocxText(doc.save().bytes)['word/header1.xml'],
        contains('<ns0:p><ns0:r><ns0:t>Added</ns0:t>'),
      );
    });

    test('tables, lists and other blocks type as in the body', () {
      final DocxDocument doc = DocxDocument.open(
        _withHeader(
          _hdr(
            '<w:tbl><w:tblGrid><w:gridCol w:w="100"/></w:tblGrid><w:tr><w:tc>'
            '${_p('Cell')}</w:tc></w:tr></w:tbl>'
            '<w:p><w:pPr><w:numPr><w:ilvl w:val="1"/><w:numId w:val="3"/>'
            '</w:numPr></w:pPr><w:r><w:t>Item</w:t></w:r></w:p>'
            '<w:sdt><w:sdtContent>${_p('Kept')}</w:sdtContent></w:sdt>',
          ),
        ),
      );
      final List<DocxBlock> blocks = doc.sections.single.header.blocks;
      expect(blocks, hasLength(3));
      final DocxTable table = blocks[0] as DocxTable;
      expect(
        (table.rows.single.cells.single.blocks.single as DocxParagraph).text,
        'Cell',
      );
      final DocxParagraph item = blocks[1] as DocxParagraph;
      expect(item.text, 'Item');
      expect(item.properties.numbering, DocxNumberingRef(3, level: 1));
      expect(blocks[2], isA<DocxOpaqueBlock>());
    });

    test('a break in a story starts no section', () {
      final DocxDocument doc = DocxDocument.open(
        _withHeader(_hdr('<w:p><w:pPr><w:sectPr/></w:pPr></w:p>')),
      );
      final DocxHeaderFooter header = doc.sections.single.header;
      expect((header.blocks.single as DocxParagraph).section, isNull);
      expect(doc.sections, hasLength(1));
    });

    test('a text past the limit names the paragraph in the part', () {
      final DocxDocument doc = DocxDocument.open(
        _withHeader(_hdr('<w:p/>${_p('toolong')}')),
        limits: const DocxReadLimits(maxTextLength: 4),
      );
      expect(
        () => doc.sections.single.header.blocks,
        throwsA(
          isA<DocxReadException>()
              .having(
                (DocxReadException e) => e.reason,
                'reason',
                DocxReadFailure.limitExceeded,
              )
              .having(
                (DocxReadException e) => e.message,
                'message',
                contains('word/header1.xml/p[1]'),
              ),
        ),
      );
    });
  });

  group('inheritance', () {
    /// Three sections; the second alone has a footer.
    final Uint8List middle = _docx(
      '${_break('One', '')}${_break('Two', _f('default', 'rId1'))}'
      '${_p('Three')}<w:sectPr/>',
      rels: _rel('rId1', 'footer1.xml', type: RelType.footer),
      parts: <String, String>{'word/footer1.xml': _ftr(_p('Footer'))},
    );

    test('a footer of section 2 of 3 reaches section 3, not section 1', () {
      final List<DocxSection> sections = DocxDocument.open(middle).sections;
      expect(sections[0].footer.blocks, isEmpty);
      expect(sections[0].footer.isInherited, isFalse);
      expect(_text(sections[1].footer), 'Footer');
      expect(sections[1].footer.isInherited, isFalse);
      expect(_text(sections[2].footer), 'Footer');
      expect(sections[2].footer.isInherited, isTrue);
    });

    test('the nearest previous section wins, by type', () {
      final List<DocxSection> sections = DocxDocument.open(
        _docx(
          '${_break('One', _h('default', 'rId1') + _h('first', 'rId3'))}'
          '${_break('Two', _h('default', 'rId2'))}${_p('Three')}<w:sectPr/>',
          rels:
              '${_rel('rId1', 'header1.xml')}${_rel('rId2', 'header2.xml')}'
              '${_rel('rId3', 'header3.xml')}',
          parts: <String, String>{
            'word/header1.xml': _hdr(_p('First section')),
            'word/header2.xml': _hdr(_p('Second section')),
            'word/header3.xml': _hdr(_p('Title')),
          },
        ),
      ).sections;
      expect(_text(sections[2].header), 'Second section');
      expect(_text(sections[2].firstHeader), 'Title');
      expect(sections[2].firstHeader.isInherited, isTrue);
      expect(sections[2].evenHeader.blocks, isEmpty);
    });

    test('an edit of an inherited story reaches every section using it', () {
      final DocxDocument doc = DocxDocument.open(middle);
      final List<DocxSection> sections = doc.sections;
      sections[2].footer.addParagraph('Added');
      expect(_text(sections[1].footer, 1), 'Added');
      expect(
        readDocxText(doc.save().bytes)['word/footer1.xml'],
        contains('Added'),
      );
    });

    test('a section that left the document keeps only its own story', () {
      final DocxDocument doc = DocxDocument.open(middle);
      final DocxSection first = doc.sections[0];
      final DocxSection second = doc.sections[1];
      doc.body.removeBlockAt(1);
      expect(doc.sections, hasLength(2));
      expect(_text(second.footer), 'Footer');
      expect(first.footer.blocks, isEmpty);
      expect(doc.sections[1].footer.blocks, isEmpty);
    });
  });

  group('references that name nothing', () {
    /// A last section of [references] and the relationships [rels], with
    /// a good `header1.xml` at `rId1` and the part `word/other.xml`.
    Uint8List file(
      String references,
      String rels, {
      String? otherType,
      String other = '<w:hdr xmlns:w="${Ns.w}"/>',
    }) => _docx(
      '${_p('Body')}<w:sectPr>$references</w:sectPr>',
      rels: '${_rel('rId1', 'header1.xml')}$rels',
      parts: <String, String>{
        'word/header1.xml': _hdr(_p('Good')),
        'word/other.xml': other,
      },
      types: <String, String>{
        'word/other.xml': otherType ?? ContentType.wmlStyles,
      },
    );

    final Map<String, Uint8List> broken = <String, Uint8List>{
      'no r:id': file('<w:headerReference w:type="default"/>', ''),
      'an empty r:id': file(
        '<w:headerReference w:type="default" r:id=""/>',
        '',
      ),
      'no relationship of that id': file(_h('default', 'rId9'), ''),
      'an unknown type': file(
        '<w:headerReference w:type="odd" r:id="rId1"/>',
        '',
      ),
      'no type': file('<w:headerReference r:id="rId1"/>', ''),
      'an external target': file(
        _h('default', 'rId2'),
        _rel('rId2', 'https://example.com/h.xml', external: true),
      ),
      'a missing part': file(
        _h('default', 'rId2'),
        _rel('rId2', 'header9.xml'),
      ),
      'a relationship of another type': file(
        _h('default', 'rId2'),
        _rel('rId2', 'other.xml', type: RelType.styles),
        otherType: ContentType.wmlHeader,
      ),
      'a relationship of the other story kind': file(
        _h('default', 'rId2'),
        _rel('rId2', 'other.xml', type: RelType.footer),
        otherType: ContentType.wmlHeader,
      ),
      'a part of another content type': file(
        _h('default', 'rId2'),
        _rel('rId2', 'other.xml'),
      ),
      'the main part': file(
        _h('default', 'rId2'),
        _rel('rId2', 'document.xml'),
      ),
    };

    broken.forEach((String name, Uint8List input) {
      test('$name counts as none and round trips', () {
        final DocxDocument doc = DocxDocument.open(input);
        final DocxSection section = doc.sections.single;
        expect(section.header.blocks, isEmpty);
        expect(section.header.isInherited, isFalse);
        _expectSame(input, doc.save().bytes);
      });
    });

    broken.forEach((String name, Uint8List input) {
      test('$name stays in the file after an edit', () {
        final DocxDocument doc = DocxDocument.open(input);
        doc.body.addParagraph('More');
        final String before = readDocxText(input)['word/document.xml']!;
        final String sectPr = before.substring(before.indexOf('<w:sectPr'));
        expect(
          readDocxText(doc.save().bytes)['word/document.xml'],
          endsWith(sectPr),
        );
      });
    });

    test('a broken reference inherits as no reference does', () {
      final List<DocxSection> sections = DocxDocument.open(
        _docx(
          '${_break('One', _h('default', 'rId1'))}${_p('Two')}'
          '<w:sectPr>${_h('default', 'rId9')}</w:sectPr>',
          rels: _rel('rId1', 'header1.xml'),
          parts: <String, String>{'word/header1.xml': _hdr(_p('Good'))},
        ),
      ).sections;
      expect(_text(sections[1].header), 'Good');
      expect(sections[1].header.isInherited, isTrue);
    });

    test('the first of a type is the section\'s, a later one is kept', () {
      final Uint8List input = file(
        '${_h('default', 'rId1')}${_h('default', 'rId2')}',
        _rel('rId2', 'header2.xml'),
      );
      final DocxDocument doc = DocxDocument.open(input);
      expect(_text(doc.sections.single.header), 'Good');
      doc.body.addParagraph('More');
      expect(
        readDocxText(doc.save().bytes)['word/document.xml'],
        contains('r:id="rId2"'),
      );
    });

    test('a broken first reference leaves the next of its type', () {
      final Uint8List input = file(
        '${_h('default', 'rId9')}${_h('default', 'rId1')}',
        '',
      );
      expect(_text(DocxDocument.open(input).sections.single.header), 'Good');
    });

    test('r:id is found by its namespace, under any prefix', () {
      final DocxDocument doc = DocxDocument.open(
        buildDocx(
          document:
              '<w:document xmlns:w="${Ns.w}" xmlns:x="${Ns.rel}"><w:body>'
              '<w:sectPr><w:headerReference w:type="default" x:id="rId1"/>'
              '</w:sectPr></w:body></w:document>',
          extra: <String, List<int>>{
            'word/_rels/document.xml.rels': utf8.encode(
              '<Relationships xmlns="$packageRelsNs">'
              '${_rel('rId1', 'header1.xml')}</Relationships>',
            ),
            'word/header1.xml': utf8.encode(_hdr(_p('Good'))),
            '[Content_Types].xml': utf8.encode(
              '<Types xmlns="$contentTypesNs"><Default Extension="rels" '
              'ContentType="${ContentType.relationships}"/>'
              '<Override PartName="/word/document.xml" '
              'ContentType="${ContentType.wmlDocument}"/>'
              '<Override PartName="/word/header1.xml" '
              'ContentType="${ContentType.wmlHeader}"/></Types>',
            ),
          },
        ),
      );
      expect(_text(doc.sections.single.header), 'Good');
    });

    test('a part of the generic XML type is read', () {
      final DocxDocument doc = DocxDocument.open(
        file(
          _h('default', 'rId2'),
          _rel('rId2', 'other.xml'),
          otherType: ContentType.xml,
          other: _hdr(_p('Generic')),
        ),
      );
      expect(_text(doc.sections.single.header), 'Generic');
    });

    group('a generic part named as a header and as a footer', () {
      Uint8List both() => file(
        '${_h('default', 'rId2')}${_f('default', 'rId3')}',
        '${_rel('rId2', 'other.xml')}'
            '${_rel('rId3', 'other.xml', type: RelType.footer)}',
        otherType: ContentType.xml,
        other: _hdr(_p('Generic')),
      );

      test('counts as none for both, the header read first', () {
        final DocxSection section = DocxDocument.open(both()).sections.single;
        expect(section.header.blocks, isEmpty);
        expect(section.footer.blocks, isEmpty);
      });

      test('counts as none for both, the footer read first', () {
        final DocxSection section = DocxDocument.open(both()).sections.single;
        expect(section.footer.blocks, isEmpty);
        expect(section.header.blocks, isEmpty);
      });

      test('counts as none when only the other kind is referenced', () {
        final DocxDocument doc = DocxDocument.open(
          file(
            _h('default', 'rId2'),
            '${_rel('rId2', 'other.xml')}'
            '${_rel('rId3', 'other.xml', type: RelType.footer)}',
            otherType: ContentType.xml,
            other: _hdr(_p('Generic')),
          ),
        );
        expect(doc.sections.single.header.blocks, isEmpty);
      });
    });
  });

  group('one part named by several references', () {
    final Uint8List input = _docx(
      '${_break('One', _h('default', 'rId1'))}${_p('Two')}'
      '<w:sectPr>${_h('default', 'rId2')}${_h('first', 'rId1')}</w:sectPr>',
      rels:
          '${_rel('rId1', 'header1.xml')}'
          '${_rel('rId2', '/WORD/Header1.xml')}',
      parts: <String, String>{'word/header1.xml': _hdr(_p('Shared'))},
    );

    test('is one story', () {
      final List<DocxSection> sections = DocxDocument.open(input).sections;
      expect(identical(sections[0].header, sections[1].header), isTrue);
      expect(
        identical(
          sections[0].header.blocks[0],
          sections[1].firstHeader.blocks[0],
        ),
        isTrue,
      );
      expect(sections[1].firstHeader.type, DocxHeaderFooterType.first);
      expect(sections[1].header.isInherited, isFalse);
    });

    test('round trips, and an edit reaches every reference', () {
      final DocxDocument doc = DocxDocument.open(input);
      final List<DocxSection> sections = doc.sections;
      sections[0].header.blocks;
      _expectSame(input, doc.save().bytes);
      sections[0].header.addParagraph('Added');
      expect(_text(sections[1].firstHeader, 1), 'Added');
      expect(
        RegExp(
          'Added',
        ).allMatches(readDocxText(doc.save().bytes)['word/header1.xml']!),
        hasLength(1),
      );
    });
  });

  group('editing a story with a part', () {
    final Uint8List input = _withHeader(
      '<!-- a comment -->${_hdr(_p('Header'))}',
    );

    test('saves through the part', () {
      final DocxDocument doc = DocxDocument.open(input);
      final DocxHeaderFooter header = doc.sections.single.header;
      _firstRun(header).text = 'Changed';
      header.addParagraph('Added');
      final Uint8List saved = doc.save().bytes;
      _expectSame(
        input,
        saved,
        changed: <String>{'word/document.xml', 'word/header1.xml'},
      );
      final DocxHeaderFooter again = DocxDocument.open(
        saved,
      ).sections.single.header;
      expect(_text(again), 'Changed');
      expect(_text(again, 1), 'Added');
    });

    test('an edit of the body leaves the story as read', () {
      final DocxDocument doc = DocxDocument.open(input);
      doc.sections.single.header.blocks;
      doc.body.addParagraph('More');
      _expectSame(
        input,
        doc.save().bytes,
        changed: <String>{'word/document.xml'},
      );
    });

    test('an edit undone saves the bytes of the part', () {
      final DocxDocument doc = DocxDocument.open(input);
      final DocxHeaderFooter header = doc.sections.single.header;
      final ChangeSet edit = editsOf(doc).transaction(() {
        header.addParagraph('Added');
      });
      editsOf(doc).log.revertSet(edit);
      expect(header.blocks, hasLength(1));
      _expectSame(
        input,
        doc.save().bytes,
        changed: <String>{'word/document.xml'},
      );
    });

    test('an edit that fails leaves the story as it was', () {
      final DocxDocument doc = DocxDocument.open(input);
      final DocxHeaderFooter header = doc.sections.single.header;
      header.blocks;
      editsOf(doc).afterRecord = () => throw StateError('failed');
      expect(() => header.addParagraph('Added'), throwsStateError);
      editsOf(doc).afterRecord = null;
      expect(header.blocks, hasLength(1));
      _expectSame(input, doc.save().bytes);
    });

    test('a block of a story is in that story', () {
      final DocxDocument doc = DocxDocument.open(input);
      final DocxHeaderFooter header = doc.sections.single.header;
      final DocxBlock block = header.blocks.single;
      expect(() => doc.body.insertBlock(0, block), throwsStateError);
      header.removeBlockAt(0);
      doc.body.insertBlock(0, block);
      expect(header.blocks, isEmpty);
      expect(doc.body.blocks.first, same(block));
    });

    test('a paragraph with a section break cannot go in a story', () {
      final Uint8List file = _docx(
        '${_break('One', '')}${_p('Two')}'
        '<w:sectPr>${_h('default', 'rId1')}</w:sectPr>',
        rels: _rel('rId1', 'header1.xml'),
        parts: <String, String>{'word/header1.xml': _hdr(_p('Header'))},
      );
      final DocxDocument doc = DocxDocument.open(file);
      final DocxHeaderFooter header = doc.sections.last.header;
      final DocxBlock moved = doc.body.blocks.first;
      doc.body.removeBlockAt(0);
      final int sections = doc.sections.length;
      expect(() => header.insertBlock(0, moved), throwsArgumentError);
      expect(() => header.replaceBlockAt(0, moved), throwsArgumentError);
      expect(header.blocks, hasLength(1));
      expect(_text(header), 'Header');
      expect(blockContainerOf(moved), isNull);
      expect(doc.sections, hasLength(sections));
    });

    test('a break of another document cannot go in a story either', () {
      final DocxDocument other = DocxDocument.open(
        _docx('${_break('One', '')}<w:sectPr/>'),
      );
      final DocxBlock moved = other.body.blocks.first;
      other.body.removeBlockAt(0);
      final DocxDocument doc = DocxDocument.open(input);
      final DocxHeaderFooter header = doc.sections.single.header;
      expect(() => header.insertBlock(0, moved), throwsArgumentError);
      expect(changeLogOf(doc).hasChanges, isFalse);
    });

    test('a break read in a story cannot go back in, and undo restores it', () {
      final DocxDocument doc = DocxDocument.open(
        _withHeader(_hdr('<w:p><w:pPr><w:sectPr/></w:pPr></w:p>')),
      );
      final DocxHeaderFooter header = doc.sections.single.header;
      final DocxBlock read = header.blocks.single;
      final ChangeSet removal = editsOf(doc).transaction(() {
        header.removeBlockAt(0);
      });
      expect(() => header.insertBlock(0, read), throwsArgumentError);
      editsOf(doc).log.revertSet(removal);
      expect(header.blocks.single, same(read));
    });

    test('addTable shares the width of the last section', () {
      final DocxDocument doc = DocxDocument.open(
        _docx(
          '<w:sectPr>${_h('default', 'rId1')}'
          '<w:pgSz w:w="6000" w:h="16838"/><w:pgMar w:top="0" w:right="500" '
          'w:bottom="0" w:left="500" w:header="0" w:footer="0" w:gutter="0"/>'
          '</w:sectPr>',
          rels: _rel('rId1', 'header1.xml'),
          parts: <String, String>{'word/header1.xml': _hdr(_p('Header'))},
        ),
      );
      final DocxTable table = doc.sections.single.header.addTable(columns: 2);
      table.addRow(<String?>['a', 'b']);
      expect(table.gridColumnsPt, <double>[124.75, 124.75]);
    });

    test('a built table left without rows stops the save, by location', () {
      final DocxDocument doc = DocxDocument.open(input);
      final DocxHeaderFooter header = doc.sections.single.header;
      header.addTable(columns: 1);
      expect(
        doc.save,
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('word/header1.xml/tbl[0]'),
          ),
        ),
      );
    });
  });

  group('the save warnings of a story', () {
    test('characters removed are reported at the run, in the part', () {
      final DocxDocument doc = DocxDocument.open(
        _withHeader(_hdr('<w:p/><w:p><w:r/><w:r><w:t>x</w:t></w:r></w:p>')),
      );
      final DocxHeaderFooter header = doc.sections.single.header;
      final DocxParagraph paragraph = header.blocks[1] as DocxParagraph;
      (paragraph.inlines[1] as DocxRun).text = 'a\u0001b';
      final List<DocxWarning> warnings = doc.save().warnings;
      expect(warnings, hasLength(1));
      expect(warnings.single.code, DocxWarningCode.invalidCharactersRemoved);
      expect(warnings.single.part, '/word/header1.xml');
      expect(warnings.single.locations, <String>['word/header1.xml/p[1]/r[1]']);
    });

    test('a style the document lacks is reported', () {
      final DocxDocument doc = DocxDocument.open(_withHeader(_hdr(_p('x'))));
      (doc.sections.single.header.blocks.single as DocxParagraph).style =
          'Missing';
      final DocxWarning warning = doc.save().warnings.single;
      expect(warning.code, DocxWarningCode.styleNotFound);
      expect(warning.locations, <String>['word/header1.xml/p[0]']);
    });

    test('a list the document lacks is reported', () {
      final DocxDocument doc = DocxDocument.open(_withHeader(_hdr(_p('x'))));
      (doc.sections.single.header.blocks.single as DocxParagraph)
          .properties
          .numbering = DocxNumberingRef(
        7,
      );
      final DocxWarning warning = doc.save().warnings.single;
      expect(warning.code, DocxWarningCode.numberingNotFound);
      expect(warning.locations, <String>['word/header1.xml/p[0]']);
    });

    test('addListItem in a story saves its list', () {
      final DocxDocument doc = DocxDocument.open(_withHeader(_hdr(_p('x'))));
      final DocxNumberingInstance list = doc.numbering.addBulletList();
      doc.sections.single.header.addListItem(list, 'Item');
      final DocxResult result = doc.save();
      expect(result.warnings, isEmpty);
      expect(readDocxText(result.bytes)['word/header1.xml'], contains('Item'));
    });
  });
}
