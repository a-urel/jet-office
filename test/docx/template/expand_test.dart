// Tests the section edits of the template fill on the model (T2 plan Rulings
// 9 to 11, 13, 14 and 17): an inline, rows or blocks section repeated,
// removed or shown once, the refusals across a vertical merge and over a
// section break, and annotations in copies and removals. Each document is
// saved and reopened. Pure Dart, so it runs on the web too.
import 'dart:convert';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart'
    show changeLogOf, documentTransaction;
import 'package:jet_office/src/docx/template/expand.dart';
import 'package:jet_office/src/docx/template/region.dart';
import 'package:jet_office/src/docx/template/sections.dart';
import 'package:jet_office/src/opc/change_log.dart' show ChangeSet;
import 'package:test/test.dart';

import '../../support/read_xlsx.dart';
import '../support/template_documents.dart';

String _p(String text, {String rPr = ''}) =>
    templateParagraph(templateRun(text, rPr: rPr));

String _tc(String inner, {String tcPr = ''}) =>
    '<w:tc>${tcPr.isEmpty ? '' : '<w:tcPr>$tcPr</w:tcPr>'}$inner</w:tc>';

String _tr(List<String> cells, {String trPr = ''}) =>
    '<w:tr>${trPr.isEmpty ? '' : '<w:trPr>$trPr</w:trPr>'}${cells.join()}'
    '</w:tr>';

String _tbl(List<String> rows, {int columns = 1}) =>
    '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/></w:tblPr><w:tblGrid>'
    '${'<w:gridCol w:w="3000"/>' * columns}</w:tblGrid>${rows.join()}</w:tbl>';

DocxDocument _doc(String body) => DocxDocument.open(
  templateWithStories(body: body, header: _p(''), footer: _p('')),
);

BlockRegion _bodyRegion(DocxDocument doc) {
  final List<DocxBlock> blocks = doc.body.blocks;
  int p = 0;
  int t = 0;
  return BlockRegion(doc.body, blocks, 0, blocks.length, <String>[
    for (final DocxBlock b in blocks)
      b is DocxTable ? 'body/tbl[${t++}]' : 'body/p[${p++}]',
  ]);
}

/// The top-level pairs of [doc]'s body, with the region and the template
/// path of each pair's opening tag.
({BlockRegion region, List<SectionPair> pairs, Map<SectionTagSite, String> at})
_pairs(DocxDocument doc) {
  final BlockRegion region = _bodyRegion(doc);
  final List<RegionParagraph> scanned = scanRegion(region, 256);
  final Map<SectionTagSite, String> at = Map<SectionTagSite, String>.identity();
  for (final RegionParagraph p in scanned) {
    for (final SectionTagSite s in p.sites) {
      at[s] = p.location;
    }
  }
  final SectionLayout layout = pairSections(<SectionTagSite>[
    for (final RegionParagraph p in scanned) ...p.sites,
  ]);
  expect(layout.malformed, isEmpty);
  return (region: region, pairs: layout.roots, at: at);
}

List<String> _texts(DocxDocument doc) {
  final DocxDocument reopened = DocxDocument.open(doc.save().bytes);
  final List<String> out = <String>[];
  void walk(List<DocxBlock> blocks) {
    for (final DocxBlock b in blocks) {
      if (b is DocxParagraph) out.add(b.text);
      if (b is DocxTable) {
        for (final DocxTableRow r in b.rows) {
          out.add(
            r.cells
                .map(
                  (DocxTableCell c) => c.blocks
                      .whereType<DocxParagraph>()
                      .map((DocxParagraph p) => p.text)
                      .join('|'),
                )
                .join('\t'),
          );
        }
      }
    }
  }

  walk(reopened.body.blocks);
  return out;
}

String _documentXml(DocxDocument doc) =>
    utf8.decode(readXlsxBytes(doc.save().bytes)['word/document.xml']!);

RepeatResult _repeat(DocxDocument doc, int count, {int pair = 0}) {
  final (:region, :pairs, :at) = _pairs(doc);
  return repeatSection(
    pairs[pair],
    region,
    count,
    256,
    openLocation: at[pairs[pair].open]!,
    story: doc.body,
  );
}

void main() {
  test('an inline repeat copies the inlines between the tags', () {
    final DocxDocument doc = _doc(
      templateParagraph(
        '${templateRun('Ürünler: ', rPr: '<w:b/>')}'
        '${templateRun('{{#a}}x, {{/a}}')}'
        '${templateRun('son', rPr: '<w:i/>')}',
      ),
    );
    final RepeatResult result = _repeat(doc, 3);
    expect(result.dropped, isEmpty);
    expect(result.regions, hasLength(3));
    final InlineRegion first = result.regions.first as InlineRegion;
    expect(first.path, 'body/p[0]');
    expect(first.end - first.start, 1);
    expect(_texts(doc), <String>['Ürünler: x, x, x, son']);
    final String xml = _documentXml(doc);
    expect(RegExp('<w:b/>').allMatches(xml), hasLength(1));
    expect(RegExp('<w:i/>').allMatches(xml), hasLength(1));
  });

  test('an inline removal deletes the inlines and both tags', () {
    final DocxDocument doc = _doc(_p('a {{#a}}x{{/a}} b'));
    final (:region, :pairs, :at) = _pairs(doc);
    expect(removeSection(pairs.single, region, doc.body, 256), isFalse);
    expect(_texts(doc), <String>['a  b']);
  });

  test('show once removes the tags only', () {
    final DocxDocument doc = _doc(
      templateParagraph(
        '${templateRun('a ')}${wordSplitTag('{{#a}}')}'
        '${templateRun('x')}${wordSplitTag('{{/a}}')}${templateRun(' b')}',
      ),
    );
    final (:region, :pairs, :at) = _pairs(doc);
    final ShowResult shown = showSection(
      pairs.single,
      region,
      256,
      openLocation: at[pairs.single.open]!,
      story: doc.body,
    );
    expect(shown.halves, isFalse);
    expect(_texts(doc), <String>['a x b']);
  });

  test('an inline section in a hyperlink repeats there', () {
    final DocxDocument doc = _doc(
      templateParagraph(hyperlinkOf(<String>['[', '{{#a}}y{{/a}}', ']'])),
    );
    _repeat(doc, 2);
    expect(_texts(doc), <String>['[yy]']);
    final DocxParagraph p =
        DocxDocument.open(doc.save().bytes).body.blocks.single as DocxParagraph;
    expect(p.inlines.single, isA<DocxHyperlink>());
  });

  test('a rows repeat copies rows a to b after b, keeping their properties', () {
    final DocxDocument doc = _doc(
      '${_tbl(<String>[
        _tr(<String>[_tc(_p('head'))]),
        _tr(<String>[_tc(_p('{{#a}}one'))], trPr: '<w:trHeight w:val="400"/>'),
        _tr(<String>[_tc(_p('two{{/a}}'))], trPr: '<w:cantSplit/>'),
        _tr(<String>[_tc(_p('total'))]),
      ])}${_p('end')}',
    );
    final RepeatResult result = _repeat(doc, 2);
    expect(result.regions, hasLength(2));
    final RowRegion copy = result.regions.last as RowRegion;
    expect(copy.start, 3);
    expect(copy.end, 5);
    expect(copy.templateRows, <int>[1, 2]);
    expect(copy.tablePath, 'body/tbl[0]');
    expect(_texts(doc), <String>[
      'head',
      'one',
      'two',
      'one',
      'two',
      'total',
      'end',
    ]);
    final String xml = _documentXml(doc);
    expect(RegExp('<w:trHeight w:val="400"/>').allMatches(xml), hasLength(2));
    expect(RegExp('<w:cantSplit/>').allMatches(xml), hasLength(2));
  });

  test('removing every row of a table removes the table', () {
    final DocxDocument doc = _doc(
      '${_p('before')}${_tbl(<String>[
        _tr(<String>[_tc(_p('{{#a}}one'))]),
        _tr(<String>[_tc(_p('two{{/a}}'))]),
      ])}${_p('after')}',
    );
    final (:region, :pairs, :at) = _pairs(doc);
    removeSection(pairs.single, region, doc.body, 256);
    expect(_texts(doc), <String>['before', 'after']);
  });

  test('a cell left without a paragraph gets an empty one', () {
    final DocxDocument doc = _doc(
      '${_tbl(<String>[
        _tr(<String>[_tc('${_p('{{#a}}')}${_p('x')}${_p('{{/a}}')}')]),
      ])}${_p('after')}',
    );
    final (:region, :pairs, :at) = _pairs(doc);
    expect(pairs.single.form, SectionForm.blocks);
    removeSection(pairs.single, region, doc.body, 256);
    expect(_texts(doc), <String>['', 'after']);
  });

  test('a blocks repeat copies the blocks between the tag paragraphs, and '
      'removes those paragraphs', () {
    final DocxDocument doc = _doc(
      '${_p('first')}${_p('{{#a}}')}${_p('x')}'
      '${_tbl(<String>[
        _tr(<String>[_tc(_p('cell'))]),
      ])}${_p('{{/a}}')}${_p('last')}',
    );
    final RepeatResult result = _repeat(doc, 3);
    final List<BlockRegion> regions = result.regions.cast<BlockRegion>();
    expect(regions.map((BlockRegion r) => (r.start, r.end)), <(int, int)>[
      (1, 3),
      (3, 5),
      (5, 7),
    ]);
    expect(regions.first.paths, <String>['body/p[2]', 'body/tbl[0]']);
    expect(regions.last.paths, regions.first.paths);
    expect(_texts(doc), <String>[
      'first',
      'x',
      'cell',
      'x',
      'cell',
      'x',
      'cell',
      'last',
    ]);
  });

  test('blocks in a cell carry the cell\'s template paths', () {
    final DocxDocument doc = _doc(
      '${_tbl(<String>[
        _tr(<String>[_tc('${_p('lead')}${_p('{{#a}}')}${_p('x')}${_p('{{/a}}')}')]),
      ])}${_p('after')}',
    );
    final RepeatResult result = _repeat(doc, 2);
    expect((result.regions.last as BlockRegion).paths, <String>[
      'body/tbl[0]/tr[0]/tc[0]/p[2]',
    ]);
    expect(_texts(doc).first, 'lead|x|x');
  });

  test('a repeat across a vertical merge is refused', () {
    const String restart = '<w:vMerge w:val="restart"/>';
    const String continues = '<w:vMerge/>';
    final DocxDocument doc = _doc(
      '${_tbl(<String>[
        _tr(<String>[_tc(_p('a'), tcPr: restart)]),
        _tr(<String>[_tc(_p('b'), tcPr: continues)]),
        _tr(<String>[_tc(_p('c'))]),
      ])}${_p('after')}',
    );
    final DocxTable table = doc.body.blocks.first as DocxTable;
    expect(crossesVerticalMerge(table, 0, 0), isTrue);
    expect(crossesVerticalMerge(table, 1, 1), isTrue);
    expect(crossesVerticalMerge(table, 0, 1), isFalse);
    expect(crossesVerticalMerge(table, 2, 2), isFalse);
  });

  test('content holding a section break is not copied or removed', () {
    const String breakP =
        '<w:p><w:pPr><w:sectPr><w:pgSz w:w="11906" w:h="16838"/></w:sectPr>'
        '</w:pPr><w:r><w:t>broken</w:t></w:r></w:p>';
    final DocxDocument doc = _doc(
      '${_p('{{#a}}')}$breakP${_p('{{/a}}')}${_p('last')}',
    );
    expect(holdsSectionBreak(doc.body.blocks), isTrue);
    expect(holdsSectionBreak(doc.body.blocks.skip(2)), isFalse);
    final (:region, :pairs, :at) = _pairs(doc);
    expect(sectionHoldsBreak(pairs.single), isTrue);
    expect(
      () => removeSection(pairs.single, region, doc.body, 256),
      throwsArgumentError,
    );
    expect(
      () => repeatSection(
        pairs.single,
        region,
        2,
        256,
        openLocation: 'body/p[0]',
        story: doc.body,
      ),
      throwsArgumentError,
    );
  });

  test('copies leave the bookmark in the first copy only', () {
    final DocxDocument doc = _doc(
      '${_p('{{#a}}')}'
      '${templateParagraph('<w:bookmarkStart w:id="3" w:name="kalem"/>'
      '${templateRun('x')}<w:bookmarkEnd w:id="3"/>')}'
      '${_p('{{/a}}')}${_p('last')}',
    );
    final RepeatResult result = _repeat(doc, 3);
    expect(
      result.dropped,
      containsAll(<String>['bookmarkStart', 'bookmarkEnd']),
    );
    expect(result.halves, isFalse);
    expect(_texts(doc), <String>['x', 'x', 'x', 'last']);
    expect(
      RegExp('w:name="kalem"').allMatches(_documentXml(doc)),
      hasLength(1),
    );
  });

  test('removing half a bookmark removes the other half', () {
    final DocxDocument doc = _doc(
      '${_p('{{#a}}')}'
      '${templateParagraph('<w:bookmarkStart w:id="5" w:name="half"/>'
      '${templateRun('x')}')}'
      '${_p('{{/a}}')}'
      '${templateParagraph('${templateRun('y')}<w:bookmarkEnd w:id="5"/>')}',
    );
    final (:region, :pairs, :at) = _pairs(doc);
    expect(removeSection(pairs.single, region, doc.body, 256), isTrue);
    final String xml = _documentXml(doc);
    expect(xml, isNot(contains('bookmarkStart')));
    expect(xml, isNot(contains('bookmarkEnd')));
    expect(_texts(doc), <String>['y']);
  });

  test('removing a comment range start removes its end', () {
    final DocxDocument doc = _doc(
      templateParagraph(
        '${templateRun('a {{#a}}')}'
        '<w:commentRangeStart w:id="9"/>${templateRun('x{{/a}} b')}'
        '<w:commentRangeEnd w:id="9"/>',
      ),
    );
    final (:region, :pairs, :at) = _pairs(doc);
    expect(removeSection(pairs.single, region, doc.body, 256), isTrue);
    expect(_documentXml(doc), isNot(contains('commentRange')));
    expect(_texts(doc), <String>['a  b']);
  });

  test('a body left without a paragraph gets an empty one', () {
    final DocxDocument doc = _doc('${_p('{{#a}}')}${_p('x')}${_p('{{/a}}')}');
    final (:region, :pairs, :at) = _pairs(doc);
    removeSection(pairs.single, region, doc.body, 256);
    expect(_texts(doc), <String>['']);
  });

  test('a repeat is undone with its transaction', () {
    final DocxDocument doc = _doc(
      '${_p('{{#a}}')}${_p('x')}${_p('{{/a}}')}${_p('last')}',
    );
    final List<String> before = _texts(doc);
    final ChangeSet set = documentTransaction(doc, () => _repeat(doc, 4));
    expect(doc.body.blocks, hasLength(5));
    changeLogOf(doc).undo(set);
    expect(doc.body.blocks, hasLength(4));
    expect(_texts(doc), before);
  });
}
