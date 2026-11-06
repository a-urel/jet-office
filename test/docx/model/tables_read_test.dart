// Tests reading `w:tbl` as a tree of blocks: rows, cells and what a cell
// holds, the grid, the properties kept for the typed API, the kept children
// around rows and cells, the read limits, and that a paragraph in a cell of
// an opened document records its edits. They build XML in memory, so they run
// on the web as well.
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/document_part.dart';
import 'package:jet_office/src/docx/docx_document.dart' show editsOf;
import 'package:jet_office/src/docx/model/blocks.dart';
import 'package:jet_office/src/docx/model/edit_sink.dart';
import 'package:jet_office/src/docx/model/inlines.dart';
import 'package:jet_office/src/docx/model/primitives.dart';
import 'package:jet_office/src/docx/properties.dart';
import 'package:jet_office/src/docx/warnings.dart' show DocxWarningCollector;
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:jet_office/src/opc/opaque_xml.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

import '../../../tool/src/part_compare.dart';
import '../support/docx_builder.dart';

const String _decls = 'xmlns:w="${Ns.w}" xmlns:w14="${Ns.w14}"';

/// The document whose body holds [body].
String _doc(String body) =>
    '<w:document $_decls><w:body>$body</w:body></w:document>';

/// Reads the document whose body holds [body].
DocumentPart _read(
  String body, {
  DocxReadLimits limits = const DocxReadLimits(),
}) => DocumentPart.read(
  XmlPullReader(_doc(body), maxDepth: limits.maxDepth),
  DocxWarningCollector(),
  '/word/document.xml',
  limits: limits,
);

/// A paragraph that holds [text].
String _p(String text) => '<w:p><w:r><w:t>$text</w:t></w:r></w:p>';

/// A cell of one paragraph that holds [text].
String _tc(String text) => '<w:tc>${_p(text)}</w:tc>';

/// The table at [index] of the blocks of [part].
DocxTable _table(DocumentPart part, [int index = 0]) =>
    part.blocks[index] as DocxTable;

/// [levels] tables each in the only cell of the one before, the innermost
/// cell holding `x`.
String _nested(int levels) =>
    '${'<w:tbl><w:tr><w:tc>' * levels}${_p('x')}'
    '${'</w:tc></w:tr></w:tbl>' * levels}';

/// The local names of [blocks], in order.
List<String> _names(List<DocxBlock> blocks) => <String>[
  for (final DocxBlock b in blocks)
    switch (b) {
      DocxParagraph() => 'p',
      DocxTable() => 'tbl',
      DocxOpaqueBlock() => b.localName,
    },
];

void main() {
  test('a table reads rows, cells and paragraphs', () {
    final DocumentPart part = _read(
      '${_p('before')}'
      '<w:tbl><w:tblGrid><w:gridCol w:w="4531"/><w:gridCol w:w="20"/>'
      '</w:tblGrid>'
      '<w:tr>${_tc('A')}${_tc('B')}</w:tr>'
      '<w:tr><w:tc>${_p('C')}<w:p/>${_p('D')}</w:tc></w:tr>'
      '</w:tbl>'
      '${_p('after')}',
    );
    expect(_names(part.blocks), <String>['p', 'tbl', 'p']);
    final DocxTable table = _table(part, 1);
    expect(table.gridColumnsPt, <double>[226.55, 1]);
    expect(table.rows, hasLength(2));
    expect(table.rows[0].cells, hasLength(2));
    expect(table.rows[1].cells, hasLength(1));
    expect((table.rows[0].cells[1].blocks.single as DocxParagraph).text, 'B');
    expect(table.rows[0].cells[0].text, 'A');
    expect(table.rows[1].cells[0].blocks, hasLength(3));
    expect(table.rows[1].cells[0].text, 'C\n\nD');
  });

  test('the lists of a table, a row and a cell cannot be modified', () {
    final DocxTable table = _table(
      _read('<w:tbl><w:tr>${_tc('a')}</w:tr></w:tbl>'),
    );
    final DocxTableRow row = table.rows.single;
    final DocxTableCell cell = row.cells.single;
    expect(() => table.rows.clear(), throwsUnsupportedError);
    expect(() => row.cells.clear(), throwsUnsupportedError);
    expect(() => cell.blocks.clear(), throwsUnsupportedError);
  });

  test('a nested table is a block of its cell', () {
    final DocxTable table = _table(
      _read(
        '<w:tbl><w:tr><w:tc>${_p('top')}'
        '<w:tbl><w:tr>${_tc('a')}${_tc('b')}</w:tr><w:tr>${_tc('c')}</w:tr>'
        '</w:tbl>${_p('end')}</w:tc></w:tr></w:tbl>',
      ),
    );
    final DocxTableCell cell = table.rows.single.cells.single;
    expect(_names(cell.blocks), <String>['p', 'tbl', 'p']);
    final DocxTable nested = cell.blocks[1] as DocxTable;
    expect(nested.rows[1].cells.single.text, 'c');
    expect(blockContainerOf(nested), same(cell));
    expect(blockContainerOf(nested.rows[0].cells[1].blocks.single), isNotNull);
    expect(cell.text, 'top\na\nb\nc\nend');
  });

  test('a cell of no paragraphs reads no text', () {
    final DocxTable table = _table(
      _read(
        '<w:tbl><w:tr><w:tc/>'
        '<w:tc><w:sdt><w:sdtContent>${_p('kept')}</w:sdtContent></w:sdt></w:tc>'
        '</w:tr></w:tbl>',
      ),
    );
    expect(table.rows.single.cells[0].blocks, isEmpty);
    expect(table.rows.single.cells[0].text, '');
    expect(table.rows.single.cells[1].text, '');
  });

  test('a w:tbl inside a w:sdt stays opaque', () {
    final DocumentPart part = _read(
      '<w:sdt><w:sdtContent><w:tbl><w:tr>${_tc('a')}</w:tr></w:tbl>'
      '</w:sdtContent></w:sdt>',
    );
    expect(part.blocks.single, isA<DocxOpaqueBlock>());
    final DocxTable table = _table(
      _read(
        '<w:tbl><w:tr><w:tc><w:sdt><w:sdtContent>'
        '<w:tbl><w:tr>${_tc('a')}</w:tr></w:tbl>'
        '</w:sdtContent></w:sdt><w:p/></w:tc></w:tr></w:tbl>',
      ),
    );
    expect(_names(table.rows.single.cells.single.blocks), <String>['sdt', 'p']);
  });

  test('w:tr and w:tc out of place are opaque', () {
    final DocumentPart part = _read(
      '<w:tr/><w:tc/><w:tbl><w:tc/><w:tr><w:tr/><w:p/></w:tr></w:tbl>',
    );
    expect(_names(part.blocks), <String>['tr', 'tc', 'tbl']);
    final DocxTable table = _table(part, 2);
    expect(table.rows, hasLength(1));
    expect(table.rows.single.cells, isEmpty);
  });

  test('an element of another namespace named tbl, tr or tc is not typed', () {
    final DocumentPart part = _read(
      '<x:tbl xmlns:x="urn:x"/>'
      '<w:tbl><x:tr xmlns:x="urn:x"/><w:tr><x:tc xmlns:x="urn:x"/></w:tr>'
      '</w:tbl>',
    );
    expect(part.blocks.first, isA<DocxOpaqueBlock>());
    expect(_table(part, 1).rows, hasLength(1));
    expect(_table(part, 1).rows.single.cells, isEmpty);
  });

  test('a w:sectPr in a cell is a block of the cell', () {
    final DocumentPart part = _read(
      '<w:tbl><w:tr><w:tc><w:sectPr/></w:tc></w:tr></w:tbl><w:sectPr/>',
    );
    expect(part.finalSectPr, isNotNull);
    expect(_names(_table(part).rows.single.cells.single.blocks), <String>[
      'sectPr',
    ]);
  });

  test('a table last in the body comes before the final sectPr', () {
    final DocumentPart part = _read(
      '<w:sectPr/><w:tbl><w:tr>${_tc('a')}</w:tr></w:tbl><w:sectPr/>',
    );
    expect(_names(part.blocks), <String>['sectPr', 'tbl']);
    expect(part.finalSectPr, isNotNull);
  });

  group('gridColumnsPt', () {
    DocxTable grid(String xml) => _table(_read('<w:tbl>$xml</w:tbl>'));

    test('is null with no w:tblGrid', () {
      expect(grid('<w:tr/>').gridColumnsPt, isNull);
    });

    test('is empty for an empty grid', () {
      expect(grid('<w:tblGrid/>').gridColumnsPt, isEmpty);
      expect(grid('<w:tblGrid></w:tblGrid>').gridColumnsPt, isEmpty);
    });

    test('an entry that does not parse is null', () {
      expect(
        grid(
          '<w:tblGrid><w:gridCol w:w="100"/><w:gridCol/>'
          '<w:gridCol w:w="abc"/><w:gridCol w:w="1in"/>'
          '<w:gridCol w:w="12.5"/><w:gridCol w:w="-20"/>'
          '<w:gridCol w:w="99999999999999999999"/><w:gridCol w:w="0"/>'
          '</w:tblGrid>',
        ).gridColumnsPt,
        <double?>[5, null, null, null, null, null, null, 0],
      );
    });

    test('only the direct w:gridCol children count', () {
      expect(
        grid(
          '<w:tblGrid><w:gridCol w:w="20"/>'
          '<w:tblGridChange w:id="1"><w:gridCol w:w="40"/></w:tblGridChange>'
          '<x:gridCol xmlns:x="urn:x" w:w="60"/></w:tblGrid>',
        ).gridColumnsPt,
        <double>[1],
      );
    });

    test('a second w:tblGrid, or one after a row, is not read', () {
      expect(
        grid(
          '<w:tblGrid><w:gridCol w:w="20"/></w:tblGrid>'
          '<w:tblGrid><w:gridCol w:w="40"/></w:tblGrid>',
        ).gridColumnsPt,
        <double>[1],
      );
      expect(
        grid(
          '<w:tr/><w:tblGrid><w:gridCol w:w="40"/></w:tblGrid>',
        ).gridColumnsPt,
        isNull,
      );
    });

    test('cannot be modified', () {
      final List<double?> columns = grid(
        '<w:tblGrid><w:gridCol w:w="20"/></w:tblGrid>',
      ).gridColumnsPt!;
      expect(() => columns[0] = 2, throwsUnsupportedError);
    });
  });

  group('properties', () {
    final DocxTable table = _table(
      _read(
        '<w:tbl><w:tblPr><w:tblW w:w="5000" w:type="pct"/><w:tblCaption '
        'w:val="c"/></w:tblPr><w:tr><w:trPr><w:cantSplit/><w:hidden/></w:trPr>'
        '<w:tc><w:tcPr><w:gridSpan w:val="2"/><w:noWrap/></w:tcPr><w:p/></w:tc>'
        '</w:tr></w:tbl>',
      ),
    );

    test('of a table, read by its schema', () {
      final PropertyContainer tblPr = tablePropertiesOf(table);
      expect(tblPr.isRead, isTrue);
      expect(tblPr.viewOf('tblW'), DocxTableWidth.percent(100));
      expect(tblPr.kept.map((OpaqueXml k) => k.localName), <String>[
        'tblCaption',
      ]);
    });

    test('of a row, read by its schema', () {
      final PropertyContainer trPr = rowPropertiesOf(table.rows.single);
      expect(trPr.viewOf('cantSplit'), isTrue);
      expect(trPr.kept.map((OpaqueXml k) => k.localName), <String>['hidden']);
    });

    test('of a cell, read by its schema', () {
      final PropertyContainer tcPr = cellPropertiesOf(
        table.rows.single.cells.single,
      );
      expect(tcPr.viewOf('gridSpan'), 2);
      expect(tcPr.kept.map((OpaqueXml k) => k.localName), <String>['noWrap']);
    });

    test('none read is an empty container', () {
      final DocxTable bare = _table(
        _read('<w:tbl><w:tr><w:tc/></w:tr></w:tbl>'),
      );
      expect(tablePropertiesOf(bare).isRead, isFalse);
      expect(rowPropertiesOf(bare.rows.single).isRead, isFalse);
      expect(cellPropertiesOf(bare.rows.single.cells.single).isRead, isFalse);
    });

    test('a second one is kept and the first is typed', () {
      final DocxTable twice = _table(
        _read(
          '<w:tbl><w:tblPr><w:tblW w:w="20" w:type="dxa"/></w:tblPr>'
          '<w:tblPr/>'
          '<w:tr><w:trPr><w:cantSplit/></w:trPr><w:trPr/>'
          '<w:tc><w:tcPr><w:gridSpan w:val="2"/></w:tcPr><w:tcPr/></w:tc>'
          '</w:tr></w:tbl>',
        ),
      );
      expect(tablePropertiesOf(twice).viewOf('tblW'), DocxTableWidth.points(1));
      final DocxTableRow row = twice.rows.single;
      expect(rowPropertiesOf(row).viewOf('cantSplit'), isTrue);
      expect(cellPropertiesOf(row.cells.single).viewOf('gridSpan'), 2);
      expect(_names(row.cells.single.blocks), <String>['tcPr']);
    });

    test('one after a row, a cell or a block is not typed', () {
      final DocxTable late = _table(
        _read(
          '<w:tbl><w:tr><w:tc><w:p/><w:tcPr/></w:tc><w:trPr/></w:tr>'
          '<w:tblPr/></w:tbl>',
        ),
      );
      expect(tablePropertiesOf(late).isRead, isFalse);
      expect(rowPropertiesOf(late.rows.single).isRead, isFalse);
      final DocxTableCell cell = late.rows.single.cells.single;
      expect(cellPropertiesOf(cell).isRead, isFalse);
      expect(_names(cell.blocks), <String>['p', 'tcPr']);
    });
  });

  test('bookmarks, sdt and tblPrEx stay in place', () {
    final DocxTable table = _table(
      _read(
        '<w:tbl><w:bookmarkStart w:id="0" w:name="a"/><w:tblPr/><w:tblGrid/>'
        '<w:bookmarkEnd w:id="0"/>'
        '<w:tr><w:tblPrEx><w:tblW w:w="0" w:type="auto"/></w:tblPrEx><w:trPr/>'
        '<w:bookmarkStart w:id="1" w:name="b"/>${_tc('a')}'
        '<w:sdt><w:sdtContent>${_tc('hidden')}</w:sdtContent></w:sdt>'
        '${_tc('b')}<w:bookmarkEnd w:id="1"/></w:tr>'
        '<w:customXml><w:tr>${_tc('hidden')}</w:tr></w:customXml>'
        '<w:tr>${_tc('c')}</w:tr></w:tbl>',
      ),
    );
    // Ruling 1: only typed rows and cells are shown.
    expect(table.rows, hasLength(2));
    expect(table.rows[0].cells.map((DocxTableCell c) => c.text), <String>[
      'a',
      'b',
    ]);
    expect(table.rows[1].cells.single.text, 'c');
    String name(Object child) => switch (child) {
      final OpaqueXml x => x.localName,
      PropertyContainer() => 'properties',
      DocxTableRow() => 'row',
      DocxTableCell() => 'cell',
      _ => '$child',
    };
    expect(tableChildrenOf(table).map(name), <String>[
      'bookmarkStart',
      'properties',
      'tblGrid',
      'bookmarkEnd',
      'row',
      'customXml',
      'row',
    ]);
    expect(rowChildrenOf(table.rows[0]).map(name), <String>[
      'tblPrEx',
      'properties',
      'bookmarkStart',
      'cell',
      'sdt',
      'cell',
      'bookmarkEnd',
    ]);
  });

  test('attributes of w:tbl, w:tr and w:tc are kept', () {
    final DocxTable table = _table(
      _read(
        '<w:tbl w:rsidR="1"><w:tr w:rsidR="2" w14:paraId="3">'
        '<w:tc w:rsidR="4"/></w:tr></w:tbl>',
      ),
    );
    final DocxTableRow row = table.rows.single;
    expect(tableAttributesOf(table).map((KeptAttribute a) => a.value), <String>[
      '1',
    ]);
    expect(
      rowAttributesOf(row).map((KeptAttribute a) => a.qualifiedName),
      <String>['w:rsidR', 'w14:paraId'],
    );
    expect(
      cellAttributesOf(row.cells.single).map((KeptAttribute a) => a.value),
      <String>['4'],
    );
  });

  group('maxDepth', () {
    /// Reads the document holding [levels] nested tables within [maxDepth].
    DocxDocument open(int levels, int maxDepth) => DocxDocument.open(
      buildDocx(document: _doc(_nested(levels))),
      limits: DocxReadLimits(maxDepth: maxDepth),
    );

    /// The deepest element of [levels] nested tables: `w:document`,
    /// `w:body`, three for each table, then `w:p`, `w:r` and `w:t`.
    int depthOf(int levels) => 2 + 3 * levels + 3;

    test('a table at maxDepth reads or fails as limitExceeded', () {
      for (final int levels in <int>[1, 2, 10, 80]) {
        final DocxDocument doc = open(levels, depthOf(levels));
        DocxBlock block = doc.body.blocks.single;
        for (int i = 1; i < levels; i++) {
          block = (block as DocxTable).rows.single.cells.single.blocks.single;
        }
        expect((block as DocxTable).rows.single.cells.single.text, 'x');
        expect(
          () => open(levels, depthOf(levels) - 1).body,
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
                  contains('maxDepth (${depthOf(levels) - 1})'),
                ),
          ),
        );
      }
    });

    test('the deepest tables the default limit allows save', () {
      const int levels = 83;
      expect(depthOf(levels), lessThanOrEqualTo(256));
      final DocxDocument doc = open(levels, 256);
      DocxBlock block = doc.body.blocks.single;
      while (block is DocxTable) {
        block = block.rows.single.cells.single.blocks.single;
      }
      (block as DocxParagraph).addRun('y');
      final DocxBlock top = DocxDocument.open(doc.save().bytes).body.blocks[0];
      expect((top as DocxTable).rows.single.cells.single.text, 'xy');
    });

    test('tables past the nesting a raised limit allows fail as '
        'limitExceeded, on every platform', () {
      final DocxDocument deepest = open(maxTableNesting, 1 << 20);
      deepest.body.insertBlock(0, DocxParagraph.text('edited'));
      expect(
        DocxDocument.open(
          deepest.save().bytes,
          limits: const DocxReadLimits(maxDepth: 1 << 20),
        ).body.blocks,
        hasLength(2),
      );
      for (final int levels in <int>[maxTableNesting + 1, 20000]) {
        expect(
          () => open(levels, 1 << 20).body,
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
                  contains('table nesting ($maxTableNesting)'),
                ),
          ),
        );
      }
    });
  });

  group('maxTextLength', () {
    DocxReadException refused(String body) {
      try {
        _read(body, limits: const DocxReadLimits(maxTextLength: 4));
      } on DocxReadException catch (e) {
        return e;
      }
      fail('no DocxReadException');
    }

    test('text past maxTextLength in a cell names '
        'body/tbl[0]/tr[0]/tc[0]/p[0]', () {
      final DocxReadException e = refused(
        '<w:p/><w:tbl><w:tr>${_tc('abcde')}</w:tr></w:tbl>',
      );
      expect(e.reason, DocxReadFailure.limitExceeded);
      expect(
        e.message,
        'Limit maxTextLength (4) exceeded by body/tbl[0]/tr[0]/tc[0]/p[0].',
      );
    });

    test('indexes count typed rows, cells, tables and paragraphs', () {
      final DocxReadException e = refused(
        '<w:tbl/><w:sdt/><w:tbl><w:bookmarkStart/><w:tr/><w:tr>'
        '<w:bookmarkStart/><w:tc/><w:tc><w:sdt/><w:p/><w:tbl/>'
        '<w:tbl><w:tr>${_tc('abcde')}</w:tr></w:tbl></w:tc></w:tr></w:tbl>',
      );
      expect(
        e.message,
        'Limit maxTextLength (4) exceeded by '
        'body/tbl[1]/tr[1]/tc[1]/tbl[1]/tr[0]/tc[0]/p[0].',
      );
    });

    test('the visible text of an opaque inline in a cell names its path', () {
      final DocxReadException e = refused(
        '<w:tbl><w:tr><w:tc><w:p/><w:p><w:ins><w:r><w:t>abcde</w:t></w:r>'
        '</w:ins></w:p></w:tc></w:tr></w:tbl>',
      );
      expect(
        e.message,
        'Limit maxTextLength (4) exceeded by body/tbl[0]/tr[0]/tc[0]/p[1].',
      );
    });

    test('paragraphs in a cell do not shift body/p[i]', () {
      final DocxReadException e = refused(
        '<w:p/><w:tbl><w:tr><w:tc><w:p/><w:p/></w:tc></w:tr></w:tbl>'
        '${_p('abcde')}',
      );
      expect(e.message, 'Limit maxTextLength (4) exceeded by body/p[1].');
    });
  });

  group('the walk of the tree', () {
    final DocumentPart part = _read(
      '${_p('a')}<w:tbl><w:tr><w:tc>${_p('b')}'
      '<w:tbl><w:tr>${_tc('c')}</w:tr></w:tbl></w:tc>'
      '<w:tc><w:bookmarkStart/>${_p('d')}</w:tc></w:tr></w:tbl>',
    );

    test('visits a block and everything in its cells, in order', () {
      final List<String> seen = <String>[];
      for (final DocxBlock block in part.blocks) {
        visitBlocks(block, (DocxBlock b) {
          seen.add(b is DocxParagraph ? b.text : _names(<DocxBlock>[b]).single);
        });
      }
      expect(seen, <String>['a', 'tbl', 'b', 'tbl', 'c', 'bookmarkStart', 'd']);
    });

    test('markBlockReadIn marks what a table holds', () {
      final DocxEdits edits = DocxEdits();
      final DocxEdits other = DocxEdits();
      markBlockReadIn(part.blocks[1], edits);
      final DocxTableCell cell = _table(part, 1).rows.single.cells.first;
      final DocxParagraph p = cell.blocks.first as DocxParagraph;
      expect(edits.isForeign(paragraphReadInOf(p)), isFalse);
      expect(other.isForeign(paragraphReadInOf(p)), isTrue);
      expect(other.isForeign(runReadInOf(p.inlines.single as DocxRun)), isTrue);
    });
  });

  test('a block already in a container cannot be read into a cell', () {
    final DocxParagraph p = DocxParagraph();
    setBlockContainerOf(p, Object());
    expect(
      () => readTableCell(
        properties: const PropertyContainer.empty(),
        attributes: const <KeptAttribute>[],
        blocks: <DocxBlock>[p],
      ),
      throwsStateError,
    );
  });

  group('in an opened document', () {
    const String body =
        '<w:p/><w:tbl><w:tr><w:tc><w:p><w:r><w:t>a</w:t></w:r></w:p>'
        '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>deep</w:t></w:r></w:p></w:tc></w:tr>'
        '</w:tbl><w:p/></w:tc></w:tr></w:tbl>';

    /// The document, its edits, and the paragraphs of its two cells.
    (DocxDocument, DocxEdits, DocxParagraph, DocxParagraph) open() {
      final DocxDocument doc = DocxDocument.open(
        buildDocx(document: _doc(body)),
      );
      final DocxTableCell cell =
          (doc.body.blocks[1] as DocxTable).rows.single.cells.single;
      final DocxTable nested = cell.blocks[1] as DocxTable;
      return (
        doc,
        editsOf(doc),
        cell.blocks.first as DocxParagraph,
        nested.rows.single.cells.single.blocks.single as DocxParagraph,
      );
    }

    test('an edit to a paragraph in a cell records a change and undoes', () {
      final (DocxDocument doc, DocxEdits edits, DocxParagraph p, _) = open();
      expect(edits.log.hasChanges, isFalse);
      final ChangeSet set = edits.transaction(
        () => (p.inlines.single as DocxRun).text = 'edited',
      );
      expect(set.changes, hasLength(1));
      expect(edits.log.hasChanges, isTrue);
      expect(p.text, 'edited');
      final DocxDocument saved = DocxDocument.open(doc.save().bytes);
      expect(
        (saved.body.blocks[1] as DocxTable).rows.single.cells.single.text,
        'edited\ndeep\n',
      );
      edits.log.revertSet(set);
      expect(p.text, 'a');
      edits.log.reapplySet(set);
      expect(p.text, 'edited');
    });

    test('an edit deep in a nested table records and undoes', () {
      final (_, DocxEdits edits, _, DocxParagraph deep) = open();
      final ChangeSet set = edits.transaction(() => deep.addRun('er'));
      expect(deep.text, 'deeper');
      expect(set.changes, hasLength(1));
      edits.log.revertSet(set);
      expect(deep.text, 'deep');
    });

    test('a property set in a cell records and undoes', () {
      final (_, DocxEdits edits, DocxParagraph p, _) = open();
      final ChangeSet set = edits.transaction(
        () => p.properties.alignment = DocxAlignment.center,
      );
      expect(set.changes, hasLength(1));
      edits.log.revertSet(set);
      expect(p.properties.alignment, isNull);
    });

    test('a table taken out reports nothing until it is back', () {
      final (DocxDocument doc, DocxEdits edits, _, DocxParagraph deep) = open();
      final ChangeSet removal = edits.transaction(
        () => doc.body.removeBlockAt(1),
      );
      expect(editSinkOf(deep), same(DocxEditSink.none));
      expect(edits.transaction(() => deep.addRun('x')).changes, isEmpty);
      edits.log.revertSet(removal);
      expect(editSinkOf(deep), same(edits));
      expect(edits.transaction(() => deep.addRun('y')).changes, hasLength(1));
    });
  });

  test('a document with no edit saves its bytes', () {
    final Uint8List bytes = buildDocx(
      document: _doc('<w:tbl><w:tr>${_tc('a')}</w:tr></w:tbl>'),
    );
    final DocxDocument doc = DocxDocument.open(bytes);
    expect(doc.body.blocks.single, isA<DocxTable>());
    expect(comparePackages(bytes, doc.save().bytes), isEmpty);
  });
}
