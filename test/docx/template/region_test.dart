// Tests the walk of a template region (a block range, a row range, an inline
// range) into its paragraphs, their entries and their section tag sites
// (T2 plan Rulings 8, 13, 14 and 15). Pure Dart, so it runs on the web too.
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/template/region.dart';
import 'package:jet_office/src/docx/template/sections.dart';
import 'package:jet_office/src/docx/template/tag_scanner.dart';
import 'package:jet_office/src/docx/template/template_walk.dart';
import 'package:test/test.dart';

import '../support/template_documents.dart';

/// A paragraph of one run of [text].
String _p(String text) => templateParagraph(templateRun(text));

/// A cell of [inner] (block XML) with the cell properties [tcPr].
String _tc(String inner, {String tcPr = ''}) =>
    '<w:tc>${tcPr.isEmpty ? '' : '<w:tcPr>$tcPr</w:tcPr>'}$inner</w:tc>';

/// A table of [rows], each a list of cell XML, on a grid of [columns].
String _tbl(List<List<String>> rows, {int columns = 1}) =>
    '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/></w:tblPr><w:tblGrid>'
    '${'<w:gridCol w:w="3000"/>' * columns}</w:tblGrid>'
    '${rows.map((List<String> r) => '<w:tr>${r.join()}</w:tr>').join()}'
    '</w:tbl>';

DocxDocument _doc(String body) => DocxDocument.open(
  templateWithStories(body: body, header: _p(''), footer: _p('')),
);

void main() {
  test('a block region lists paragraphs with the template paths it was '
      'given', () {
    final DocxDocument doc = _doc(
      '${_p('zero')}${_p('one')}${_p('x {{v}}')}'
      '${_tbl(<List<String>>[
        <String>[_tc(_p('in {{w}}'))],
      ])}${_p('last {{z}}')}',
    );
    final List<DocxBlock> blocks = doc.body.blocks;
    final List<RegionParagraph> scanned = scanRegion(
      BlockRegion(doc.body, blocks, 2, 4, <String>['body/p[1]', 'body/tbl[0]']),
      256,
    );
    expect(scanned.map((RegionParagraph p) => p.location), <String>[
      'body/p[1]',
      'body/tbl[0]/tr[0]/tc[0]/p[0]',
    ]);
    expect(scanned.first.paragraph, same(blocks[2]));
    expect(scanned.first.map!.text, 'x {{v}}');
    expect(scanned.map((RegionParagraph p) => p.entries.single.text), <String>[
      '{{v}}',
      '{{w}}',
    ]);
    expect(scanned.first.entries.single.problem, isNull);
    expect(scanned.every((RegionParagraph p) => p.sites.isEmpty), isTrue);
  });

  test('a block region names nested paragraphs, tables and opaque blocks as '
      'the walk does', () {
    final DocxDocument doc = _doc(
      '${_tbl(<List<String>>[
        <String>[
          _tc('${_p('a')}${_tbl(<List<String>>[
            <String>[_tc(_p('b'))],
          ])}${_p('c')}'),
        ],
      ])}'
      '<w:sdt><w:sdtPr/><w:sdtContent>${_p('{{s}}')}</w:sdtContent></w:sdt>'
      '${_p('end')}',
    );
    final List<RegionParagraph> scanned = scanRegion(
      BlockRegion(doc.body, doc.body.blocks, 0, 3, <String>[
        'body/tbl[0]',
        'body/sdt[0]',
        'body/p[0]',
      ]),
      256,
    );
    expect(scanned.map((RegionParagraph p) => p.location), <String>[
      'body/tbl[0]/tr[0]/tc[0]/p[0]',
      'body/tbl[0]/tr[0]/tc[0]/tbl[0]/tr[0]/tc[0]/p[0]',
      'body/tbl[0]/tr[0]/tc[0]/p[1]',
      'body/sdt[0]',
      'body/p[0]',
    ]);
    final RegionParagraph sdt = scanned[3];
    expect(sdt.paragraph, isNull);
    expect(sdt.map, isNull);
    expect(
      sdt.entries.single.problem,
      DocxWarningCode.templatePlaceholderInContentControl,
    );
  });

  test('a block region checks its range and paths', () {
    final DocxDocument doc = _doc(_p('a'));
    final List<DocxBlock> blocks = doc.body.blocks;
    expect(
      () => scanRegion(BlockRegion(doc.body, blocks, 0, 2, <String>['x']), 256),
      throwsRangeError,
    );
    expect(
      () => scanRegion(BlockRegion(doc.body, blocks, 0, 1, <String>[]), 256),
      throwsArgumentError,
    );
  });

  test('a row region names the template rows', () {
    final DocxDocument doc = _doc(
      '${_tbl(<List<String>>[
        for (int r = 0; r < 5; r++) <String>[_tc(_p('r$r {{v}}'))],
      ])}${_p('')}',
    );
    final DocxTable t = doc.body.blocks.first as DocxTable;
    final List<RegionParagraph> scanned = scanRegion(
      RowRegion(t, 3, 5, <int>[1, 1], 'body/tbl[0]'),
      256,
    );
    expect(scanned.map((RegionParagraph p) => p.location), <String>[
      'body/tbl[0]/tr[1]/tc[0]/p[0]',
      'body/tbl[0]/tr[1]/tc[0]/p[0]',
    ]);
    expect(scanned.map((RegionParagraph p) => p.map!.text), <String>[
      'r3 {{v}}',
      'r4 {{v}}',
    ]);
  });

  test('a row region gives sites steps from its table', () {
    final DocxDocument doc = _doc(
      '${_tbl(<List<String>>[
        <String>[_tc(_p('{{#a}} x'))],
        <String>[_tc(_p('y {{/a}}'))],
      ])}${_p('')}',
    );
    final DocxTable t = doc.body.blocks.first as DocxTable;
    final List<RegionParagraph> scanned = scanRegion(
      RowRegion(t, 0, 2, <int>[0, 1], 'body/tbl[0]'),
      256,
    );
    final SectionTagSite closer = scanned[1].sites.single;
    expect(closer.steps, hasLength(2));
    final CellStep cell = closer.steps.first as CellStep;
    expect(cell.table, same(t));
    expect((cell.row, cell.cell), (1, 0));
    final BlockStep block = closer.steps.last as BlockStep;
    expect(block.container, same(t.rows[1].cells[0]));
    expect(block.index, 0);
    final SectionLayout layout = pairSections(<SectionTagSite>[
      for (final RegionParagraph p in scanned) ...p.sites,
    ]);
    expect(layout.roots.single.form, SectionForm.rows);
  });

  test('an inline region scans only its inlines', () {
    final DocxDocument doc = _doc(
      templateParagraph(
        '${templateRun('{{a}} ')}${templateRun('{{#s}}')}'
        '${templateRun('{{b}}')}${templateRun('{{/s}}')}'
        '${templateRun(' {{c}}')}',
      ),
    );
    final DocxParagraph p = doc.body.blocks.first as DocxParagraph;
    final RegionParagraph inner = scanRegion(
      InlineRegion(p, p.inlines, 2, 3, 'body/p[0]'),
      256,
    ).single;
    expect(inner.location, 'body/p[0]');
    expect(inner.paragraph, same(p));
    expect(inner.map!.text, '{{b}}');
    expect(inner.entries.single.text, '{{b}}');
    expect(inner.entries.single.offset, 0);
    expect(inner.entries.single.problem, isNull);
    expect(inner.sites, isEmpty);

    final RegionParagraph wider = scanRegion(
      InlineRegion(p, p.inlines, 1, 4, 'body/p[0]'),
      256,
    ).single;
    expect(wider.entries.map((TemplateEntry e) => e.text), <String>[
      '{{#s}}',
      '{{b}}',
      '{{/s}}',
    ]);
    expect(wider.sites.map((SectionTagSite s) => s.text), <String>[
      '{{#s}}',
      '{{/s}}',
    ]);
    expect(wider.sites.first.level, same(p));
    expect(wider.sites.first.payload, same(wider.entries.first));
    expect(wider.sites.last.offset, 11);
    expect(pairSections(wider.sites).roots.single.form, SectionForm.inline);
  });

  test('section tags come as sites with steps, alone and level', () {
    final DocxDocument doc = _doc(
      '${_p('{{#a}}')}${_tbl(<List<String>>[
        <String>[_tc(_p('{{/a}}'))],
        <String>[_tc(_p('x {{/a}}'))],
      ])}${_p('')}',
    );
    final List<DocxBlock> blocks = doc.body.blocks;
    final DocxTable t = blocks[1] as DocxTable;
    final List<RegionParagraph> scanned = scanRegion(
      BlockRegion(doc.body, blocks, 0, 3, <String>[
        'body/p[0]',
        'body/tbl[0]',
        'body/p[1]',
      ]),
      256,
    );
    final List<SectionTagSite> sites = <SectionTagSite>[
      for (final RegionParagraph p in scanned) ...p.sites,
    ];
    expect(sites, hasLength(3));
    final SectionTagSite opener = sites[0];
    expect(opener.kind, TagKind.section);
    expect(opener.path, <String>['a']);
    expect(opener.text, '{{#a}}');
    expect(opener.steps, hasLength(1));
    expect((opener.steps.single as BlockStep).container, same(doc.body));
    expect((opener.steps.single as BlockStep).index, 0);
    expect(opener.level, same(blocks[0]));
    expect(opener.alone, isTrue);

    final SectionTagSite closer = sites[1];
    expect(closer.kind, TagKind.sectionEnd);
    expect(closer.steps, hasLength(3));
    expect((closer.steps[0] as BlockStep).container, same(doc.body));
    expect((closer.steps[0] as BlockStep).index, 1);
    expect((closer.steps[1] as CellStep).table, same(t));
    expect((closer.steps[1] as CellStep).row, 0);
    expect((closer.steps[1] as CellStep).cell, 0);
    expect((closer.steps[2] as BlockStep).container, same(t.rows[0].cells[0]));
    expect((closer.steps[2] as BlockStep).index, 0);
    expect(closer.alone, isTrue);
    expect(sites[2].alone, isFalse);
    expect(sites[2].offset, 2);
    expect(sites.every((SectionTagSite s) => !s.breaksSection), isTrue);
    expect(sites.every((SectionTagSite s) => !s.crossesMerge), isTrue);
  });

  test(
    'alone allows spaces, bookmarks, proofing marks and comment marks only',
    () {
      String alone(String inner) => templateParagraph(inner);
      final DocxDocument doc = _doc(
        '${alone(templateRun('  {{#a}}  '))}'
        '${alone('<w:bookmarkStart w:id="1" w:name="m"/>'
        '<w:proofErr w:type="spellStart"/>${templateRun('{{#a}}')}'
        '<w:bookmarkEnd w:id="1"/>')}'
        '${alone('${templateRun('{{#a}}')}<w:r><w:tab/></w:r>')}'
        '${alone('${templateRun('{{#a}}')}<w:fldSimple w:instr=" PAGE "/>')}'
        '${alone('${templateRun('{{#a}}')}${tagInFieldResult('')}')}'
        '${alone('${templateRun('{{#a}}')}${hyperlinkOf(<String>['x'])}')}'
        '${alone(templateRun('{{#a}}{{b}}'))}'
        '${alone('<w:commentRangeStart w:id="3"/>${templateRun('{{#a}}')}'
        '<w:commentRangeEnd w:id="3"/><w:r><w:rPr><w:rStyle '
        'w:val="CommentReference"/></w:rPr><w:commentReference w:id="3"/>'
        '</w:r>')}'
        '${alone('${templateRun('{{#a}}')}<w:r><w:footnoteReference w:id="1"/>'
        '</w:r>')}'
        '${alone('${templateRun('{{#a}}')}<w:r><w:commentReference w:id="3"/>'
        '<w:tab/></w:r>')}',
      );
      final List<DocxBlock> blocks = doc.body.blocks;
      final List<RegionParagraph> scanned = scanRegion(
        BlockRegion(doc.body, blocks, 0, blocks.length, <String>[
          for (int i = 0; i < blocks.length; i++) 'body/p[$i]',
        ]),
        256,
      );
      expect(scanned.map((RegionParagraph p) => p.sites.single.alone), <bool>[
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        // A comment's range and reference; a footnote reference; a
        // comment reference beside a tab.
        true,
        false,
        false,
      ]);
    },
  );

  test('a tag in a hyperlink has the hyperlink as its level', () {
    final DocxDocument doc = _doc(
      templateParagraph(
        '${templateRun('{{#a}}')}'
        '${hyperlinkOf(<String>['{{#b}}', 'y', '{{/b}}'])}'
        '${templateRun('{{/a}}')}',
      ),
    );
    final DocxParagraph p = doc.body.blocks.first as DocxParagraph;
    final DocxHyperlink link = p.inlines.whereType<DocxHyperlink>().single;
    final List<SectionTagSite> sites = scanRegion(
      InlineRegion(p, p.inlines, 0, p.inlines.length, 'body/p[0]'),
      256,
    ).single.sites;
    expect(sites.map((SectionTagSite s) => s.level), <Object>[
      p,
      link,
      link,
      p,
    ]);
    final SectionLayout layout = pairSections(sites);
    expect(layout.malformed, isEmpty);
    expect(layout.roots.single.children.single.form, SectionForm.inline);

    final List<SectionTagSite> inLink = scanRegion(
      InlineRegion(p, link.inlines, 0, 3, 'body/p[0]'),
      256,
    ).single.sites;
    expect(inLink.map((SectionTagSite s) => s.level), <Object>[link, link]);
  });

  test('a split section tag is one site', () {
    final DocxDocument doc = _doc(
      templateParagraph(wordSplitTag('{{#kalemler}}')),
    );
    final RegionParagraph p = scanRegion(
      BlockRegion(doc.body, doc.body.blocks, 0, 1, <String>['body/p[0]']),
      256,
    ).single;
    expect(p.sites.single.path, <String>['kalemler']);
    expect(p.sites.single.text, '{{#kalemler}}');
    expect(p.sites.single.alone, isTrue);
  });

  test('a section tag in a tracked insertion stays a problem, not a '
      'site', () {
    final DocxDocument doc = _doc(templateParagraph(tagInInsertion('{{#a}}')));
    final RegionParagraph p = scanRegion(
      BlockRegion(doc.body, doc.body.blocks, 0, 1, <String>['body/p[0]']),
      256,
    ).single;
    expect(p.sites, isEmpty);
    expect(
      p.entries.single.problem,
      DocxWarningCode.templatePlaceholderInRevision,
    );
  });

  test('crossesMerge is set on a tag in a row whose cell continues a merge '
      'from above', () {
    const String restart = '<w:vMerge w:val="restart"/>';
    const String continues = '<w:vMerge/>';
    final DocxDocument doc = _doc(
      '${_tbl(<List<String>>[
        <String>[_tc(_p('p'), tcPr: restart), _tc(_p('{{/b}}'))],
        <String>[_tc(_p(''), tcPr: continues), _tc(_p('{{#a}}'))],
        <String>[_tc(_p('q')), _tc(_p('{{/a}} {{#c}}'))],
      ], columns: 2)}${_p('')}',
    );
    final DocxTable t = doc.body.blocks.first as DocxTable;
    final List<SectionTagSite> sites = <SectionTagSite>[
      for (final RegionParagraph p in scanRegion(
        RowRegion(t, 0, 3, <int>[0, 1, 2], 'body/tbl[0]'),
        256,
      ))
        ...p.sites,
    ];
    expect(sites.map((SectionTagSite s) => s.text), <String>[
      '{{/b}}',
      '{{#a}}',
      '{{/a}}',
      '{{#c}}',
    ]);
    // A closer before a row that continues, an opener in such a row.
    expect(sites.map((SectionTagSite s) => s.crossesMerge), <bool>[
      true,
      true,
      false,
      false,
    ]);
  });

  test('breaksSection is set for a paragraph with a section break', () {
    final DocxDocument doc = _doc(
      '<w:p><w:pPr><w:sectPr><w:pgSz w:w="11906" w:h="16838"/></w:sectPr>'
      '</w:pPr>${templateRun('{{#a}}')}</w:p>${_p('{{/a}}')}',
    );
    final List<SectionTagSite> sites = <SectionTagSite>[
      for (final RegionParagraph p in scanRegion(
        BlockRegion(doc.body, doc.body.blocks, 0, 2, <String>[
          'body/p[0]',
          'body/p[1]',
        ]),
        256,
      ))
        ...p.sites,
    ];
    expect(sites.map((SectionTagSite s) => s.breaksSection), <bool>[
      true,
      false,
    ]);
    expect(pairSections(sites).malformed, hasLength(2));
  });

  test('T1 callers see section tags as problems still', () {
    final DocxDocument doc = _doc(_p('{{#a}}{{v}}{{/a}}'));
    final DocxParagraph p = doc.body.blocks.first as DocxParagraph;
    final List<TemplateEntry> t1 = paragraphEntries(p, 256);
    expect(t1.map((TemplateEntry e) => e.problem), <DocxWarningCode?>[
      DocxWarningCode.templateSectionMalformed,
      null,
      DocxWarningCode.templateSectionMalformed,
    ]);
    expect(t1.first.map, isNull);
    final List<TemplateEntry> t2 = paragraphEntries(p, 256, sections: true);
    expect(t2.map((TemplateEntry e) => e.problem), <DocxWarningCode?>[
      null,
      null,
      null,
    ]);
    expect(t2.first.map, isNotNull);
    expect(t2.first.match!.tag!.kind, TagKind.section);
  });
}
