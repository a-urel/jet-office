// Tests merging the cells of a table and the fit of a table's rows in its grid:
// mergeCells keeps the text of every merged cell in order, spans, restarts and
// continues as Word does, refuses what does not fit before anything changes and
// undoes in one step; gridSpan, verticalMerge and a row inserted are checked
// through the API and a file never is. They build documents in memory, so they
// run on the web as well.
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart' show editsOf;
import 'package:jet_office/src/docx/model/blocks.dart';
import 'package:jet_office/src/docx/model/edit_sink.dart';
import 'package:jet_office/src/docx/model/inlines.dart';
import 'package:jet_office/src/docx/model/primitives.dart';
import 'package:jet_office/src/docx/model/property_set.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:test/test.dart';

import '../support/docx_builder.dart';
import '../support/styles_documents.dart';

const String _head = '<w:document xmlns:w="${Ns.w}"><w:body>';
const String _tail = '</w:body></w:document>';

/// Opens the document whose body holds [body].
DocxDocument _open(
  String body, {
  DocxReadLimits limits = const DocxReadLimits(),
}) =>
    DocxDocument.open(buildDocx(document: '$_head$body$_tail'), limits: limits);

/// The first block of [doc], a table.
DocxTable _table(DocxDocument doc) => doc.body.blocks.first as DocxTable;

/// The `w:tblGrid` of [columns] columns of 1000 twips (50 points).
String _grid(int columns) =>
    '<w:tblGrid>${'<w:gridCol w:w="1000"/>' * columns}</w:tblGrid>';

/// A cell that holds [text], with the `w:tcPr` children [pr].
String _tc(String text, [String pr = '']) =>
    '<w:tc>${pr.isEmpty ? '' : '<w:tcPr>$pr</w:tcPr>'}'
    '<w:p><w:r><w:t>$text</w:t></w:r></w:p></w:tc>';

/// A cell of one empty paragraph, with the `w:tcPr` children [pr].
String _empty([String pr = '']) =>
    '<w:tc>${pr.isEmpty ? '' : '<w:tcPr>$pr</w:tcPr>'}<w:p/></w:tc>';

const String _width = '<w:tcW w:w="1000" w:type="dxa"/>';
const String _span2 = '<w:gridSpan w:val="2"/>';
const String _restart = '<w:vMerge w:val="restart"/>';
const String _continue = '<w:vMerge/>';

/// A row of [cells].
String _tr(List<String> cells, [String trPr = '']) =>
    '<w:tr>${trPr.isEmpty ? '' : '<w:trPr>$trPr</w:trPr>'}${cells.join()}'
    '</w:tr>';

/// The table of three rows of three cells, `A` to `I`, each 50 points wide.
const String _letters = 'ABCDEFGHI';

String _threeByThree() => <String>[
  '<w:tbl>',
  _grid(3),
  for (int r = 0; r < 3; r++)
    _tr(<String>[for (int c = 0; c < 3; c++) _tc(_letters[r * 3 + c], _width)]),
  '</w:tbl>',
].join();

/// A table of [rows], in a grid of [columns] columns.
DocxDocument _tableOf(int columns, List<String> rows) =>
    _open('<w:tbl>${_grid(columns)}${rows.join()}</w:tbl>');

/// The text of each row of [table], its cells joined by `|`.
List<String> _rows(DocxTable table) => <String>[
  for (final DocxTableRow row in table.rows)
    row.cells.map((DocxTableCell c) => c.text.replaceAll('\n', '/')).join('|'),
];

/// The main part of [doc] as saved.
String _saved(DocxDocument doc) =>
    readDocxText(doc.save().bytes)['word/document.xml']!;

/// [doc] saved and read again.
DocxDocument _reopen(DocxDocument doc) => DocxDocument.open(doc.save().bytes);

/// Merges the range of [table] given as first row, first column, last row and
/// last column.
DocxTableCell _merge(DocxTable table, int r0, int c0, int r1, int c1) => table
    .mergeCells(firstRow: r0, firstColumn: c0, lastRow: r1, lastColumn: c1);

/// A sink that passes everything to [_edits] and keeps the change set of each
/// outermost [atomically], so a test can undo an edit that opened no
/// transaction of its own, and counts what is reported outside one.
final class _RecordingSink implements DocxEditSink {
  _RecordingSink(this._edits);

  final DocxEdits _edits;
  final List<ChangeSet> sets = <ChangeSet>[];
  int outside = 0;
  int _depth = 0;

  void _report() {
    if (_depth == 0) outside++;
  }

  @override
  DocxHeaderFooter? ownHeaderFooter(
    DocxSection section,
    DocxHeaderFooterType type, {
    required bool isHeader,
  }) => null;

  @override
  void removeHeaderFooter(
    DocxSection section,
    DocxHeaderFooterType type, {
    required bool isHeader,
  }) {}

  @override
  DocxHeaderFooter? headerFooterOf(
    DocxSection section,
    DocxHeaderFooterType type, {
    required bool isHeader,
  }) => null;

  @override
  void atomically(void Function() body) {
    if (_depth > 0) {
      body();
      return;
    }
    _depth++;
    try {
      sets.add(_edits.transaction(body));
    } finally {
      _depth--;
    }
  }

  @override
  void apply(Change change) {
    _report();
    _edits.apply(change);
  }

  @override
  void inlineInserted(DocxParagraph paragraph, int index, DocxInline inline) {
    _report();
    _edits.inlineInserted(paragraph, index, inline);
  }

  @override
  void inlineRemoved(DocxParagraph paragraph, int index, DocxInline inline) {
    _report();
    _edits.inlineRemoved(paragraph, index, inline);
  }

  @override
  void inlineReplaced(
    DocxParagraph paragraph,
    int index,
    DocxInline previous,
    DocxInline replacement,
  ) {
    _report();
    _edits.inlineReplaced(paragraph, index, previous, replacement);
  }

  @override
  void runTextSet(DocxRun run, DocxRunText previous) {
    _report();
    _edits.runTextSet(run, previous);
  }

  @override
  void propertySet(
    PropertySet properties,
    String localName,
    PropertyState previous,
  ) {
    _report();
    _edits.propertySet(properties, localName, previous);
  }

  @override
  String resolveStyleId(String id, DocxStyleType type) =>
      _edits.resolveStyleId(id, type);

  @override
  String? ensureStyle(DocxBuiltInStyle style) => _edits.ensureStyle(style);

  @override
  bool isForeign(DocxEditSink? readIn) => _edits.isForeign(readIn);
}

void main() {
  group('a merge of a 3 x 3 table', () {
    test('of a whole row leaves one cell, with the text in order', () {
      final DocxDocument doc = _open(_threeByThree());
      final DocxTable table = _table(doc);
      final DocxTableCell first = table.rows[0].cells[0];
      final DocxTableCell merged = _merge(table, 0, 0, 0, 2);
      expect(merged, same(first));
      expect(_rows(table), <String>['A/B/C', 'D|E|F', 'G|H|I']);
      expect(merged.properties.gridSpan, 3);
      expect(merged.properties.verticalMerge, isNull);
    });

    test('of part of a row spans what it covers', () {
      final DocxDocument doc = _open(_threeByThree());
      final DocxTable table = _table(doc);
      final DocxTableCell merged = _merge(table, 1, 1, 1, 2);
      expect(merged, same(table.rows[1].cells[1]));
      expect(_rows(table), <String>['A|B|C', 'D|E/F', 'G|H|I']);
      expect(merged.properties.gridSpan, 2);
      expect(table.rows[1].cells[0].properties.gridSpan, isNull);
    });

    test('of a column restarts, continues and removes no cell', () {
      final DocxDocument doc = _open(_threeByThree());
      final DocxTable table = _table(doc);
      final DocxTableCell merged = _merge(table, 0, 1, 2, 1);
      expect(merged, same(table.rows[0].cells[1]));
      expect(_rows(table), <String>['A|B/E/H|C', 'D||F', 'G||I']);
      expect(merged.properties.verticalMerge, DocxVerticalMerge.restart);
      expect(merged.properties.gridSpan, isNull);
      for (final int r in <int>[1, 2]) {
        final DocxTableCell cell = table.rows[r].cells[1];
        expect(cell.properties.verticalMerge, DocxVerticalMerge.continuation);
        expect(cell.blocks, hasLength(1));
        expect(cell.blocks.single, isA<DocxParagraph>());
      }
    });

    test('of a block spans in each row and continues below the first', () {
      final DocxDocument doc = _open(_threeByThree());
      final DocxTable table = _table(doc);
      final DocxTableCell merged = _merge(table, 1, 1, 2, 2);
      expect(merged, same(table.rows[1].cells[1]));
      expect(_rows(table), <String>['A|B|C', 'D|E/F/H/I', 'G|']);
      expect(merged.properties.gridSpan, 2);
      expect(merged.properties.verticalMerge, DocxVerticalMerge.restart);
      final DocxTableCell below = table.rows[2].cells[1];
      expect(below.properties.gridSpan, 2);
      expect(below.properties.verticalMerge, DocxVerticalMerge.continuation);
    });

    test('of the whole table keeps every row, with its one cell', () {
      final DocxDocument doc = _open(_threeByThree());
      final DocxTable table = _table(doc);
      _merge(table, 0, 0, 2, 2);
      expect(_rows(table), <String>['A/B/C/D/E/F/G/H/I', '', '']);
      for (final DocxTableRow row in table.rows) {
        expect(row.cells.single.properties.gridSpan, 3);
      }
    });

    test('saves and reads back the same', () {
      final DocxDocument doc = _open(_threeByThree());
      _merge(_table(doc), 1, 1, 2, 2);
      final String saved = _saved(doc);
      expect(saved, contains('<w:gridSpan w:val="2"/>$_restart'));
      expect(saved, contains('<w:gridSpan w:val="2"/>$_continue'));
      final DocxTable back = _table(_reopen(doc));
      expect(_rows(back), <String>['A|B|C', 'D|E/F/H/I', 'G|']);
      expect(
        back.rows[2].cells[1].properties.verticalMerge,
        DocxVerticalMerge.continuation,
      );
    });

    test('works the same on a table in no document', () {
      final DocxTable table = DocxTable(columns: 3, rows: 3);
      table.rows[0].cells[1].addParagraph('x');
      table.rows[1].cells[2].addParagraph('y');
      final DocxTableCell merged = _merge(table, 0, 1, 1, 2);
      expect(merged.text, 'x\ny');
      expect(merged.properties.gridSpan, 2);
      expect(table.rows[1].cells, hasLength(2));
    });
  });

  group('the blocks of a merge', () {
    test('lose their empty paragraphs, in the first cell too', () {
      final DocxDocument doc = _tableOf(3, <String>[
        _tr(<String>[_empty(), _tc('B'), _empty()]),
      ]);
      final DocxTable table = _table(doc);
      final DocxTableCell merged = _merge(table, 0, 0, 0, 2);
      expect(merged.blocks, hasLength(1));
      expect(merged.text, 'B');
    });

    test('count a run without text as empty', () {
      final DocxDocument doc = _tableOf(2, <String>[
        _tr(<String>[
          '<w:tc><w:p><w:r><w:t></w:t></w:r></w:p></w:tc>',
          _tc('B'),
        ]),
      ]);
      final DocxTableCell merged = _merge(_table(doc), 0, 0, 0, 1);
      expect(merged.blocks, hasLength(1));
    });

    test('keep a paragraph that holds a tab or a bookmark', () {
      final DocxDocument doc = _tableOf(2, <String>[
        _tr(<String>[
          '<w:tc><w:p><w:bookmarkStart w:id="1" w:name="b"/></w:p></w:tc>',
          '<w:tc><w:p><w:r><w:tab/></w:r></w:p></w:tc>',
        ]),
      ]);
      expect(_merge(_table(doc), 0, 0, 0, 1).blocks, hasLength(2));
    });

    test('a merge of empty cells leaves one empty paragraph', () {
      final DocxDocument doc = _tableOf(2, <String>[
        _tr(<String>[_empty(), _empty()]),
        _tr(<String>[_empty(), _empty()]),
      ]);
      final DocxTable table = _table(doc);
      final DocxTableCell merged = _merge(table, 0, 0, 1, 1);
      expect(merged.blocks, hasLength(1));
      expect(merged.blocks.single, isA<DocxParagraph>());
      expect(merged.text, '');
    });

    test('a merge of cells without blocks leaves one empty paragraph', () {
      final DocxDocument doc = _tableOf(2, <String>[
        _tr(<String>['<w:tc/>', '<w:tc/>']),
        _tr(<String>['<w:tc/>', '<w:tc/>']),
      ]);
      final DocxTable table = _table(doc);
      final DocxTableCell merged = _merge(table, 0, 0, 1, 1);
      expect(merged.blocks.single, isA<DocxParagraph>());
      expect(table.rows[1].cells.single.blocks.single, isA<DocxParagraph>());
    });

    test('tables and opaque blocks move in reading order', () {
      final DocxDocument doc = _tableOf(2, <String>[
        _tr(<String>[
          _tc('A'),
          '<w:tc><w:tbl>${_grid(1)}${_tr(<String>[_tc('in')])}</w:tbl>'
              '<w:p/></w:tc>',
        ]),
        _tr(<String>[
          '<w:tc><w:bookmarkStart w:id="1" w:name="b"/><w:p/></w:tc>',
          _tc('D'),
        ]),
      ]);
      final DocxTable table = _table(doc);
      final DocxTableCell merged = _merge(table, 0, 0, 1, 1);
      expect(merged.text, 'A\nin\nD');
      expect(merged.blocks, hasLength(4));
      expect(merged.blocks[1], isA<DocxTable>());
      expect(merged.blocks[2], isA<DocxOpaqueBlock>());
    });

    test('a table moved last leaves a cell that saves with a paragraph', () {
      final String inner =
          '<w:tbl>${_grid(1)}${_tr(<String>[_tc('in')])}'
          '</w:tbl>';
      final DocxDocument doc = _tableOf(2, <String>[
        _tr(<String>[_tc('A'), '<w:tc>$inner<w:p/></w:tc>']),
      ]);
      final DocxTableCell merged = _merge(_table(doc), 0, 0, 0, 1);
      expect(merged.blocks.last, isA<DocxTable>());
      expect(_saved(doc), contains('</w:tbl><w:p/></w:tc>'));
    });

    group('between two tables', () {
      final String inner =
          '<w:tbl>${_grid(1)}${_tr(<String>[_tc('in')])}</w:tbl>';

      /// The kinds of the blocks of the merge of a row of [cells].
      List<Type> merged(List<String> cells) {
        final DocxDocument doc = _tableOf(cells.length, <String>[_tr(cells)]);
        final DocxTableCell cell = _merge(
          _table(doc),
          0,
          0,
          0,
          cells.length - 1,
        );
        expect(_saved(doc), isNot(contains('</w:tbl><w:tbl>')));
        return cell.blocks.map((DocxBlock b) => b.runtimeType).toList();
      }

      test('an empty paragraph stays, so Word does not join them', () {
        expect(
          merged(<String>[
            '<w:tc>$inner<w:p/></w:tc>',
            '<w:tc>$inner<w:p/></w:tc>',
          ]),
          <Type>[DocxTable, DocxParagraph, DocxTable],
        );
      });

      test('one empty paragraph stays of several', () {
        expect(
          merged(<String>[
            '<w:tc>$inner<w:p/><w:p/></w:tc>',
            '<w:tc><w:p/>$inner</w:tc>',
          ]),
          <Type>[DocxTable, DocxParagraph, DocxTable],
        );
      });

      test('none stays where another block is between them', () {
        expect(
          merged(<String>[
            '<w:tc>$inner<w:p/></w:tc>',
            _tc('B'),
            '<w:tc><w:p/>$inner<w:p/></w:tc>',
          ]),
          <Type>[DocxTable, DocxParagraph, DocxTable],
        );
      });
    });

    test('an edit of a moved paragraph is recorded by the document', () {
      final DocxDocument doc = _open(_threeByThree());
      final DocxTableCell merged = _merge(_table(doc), 0, 0, 0, 1);
      final DocxParagraph moved = merged.blocks[1] as DocxParagraph;
      final ChangeSet set = editsOf(doc).transaction(() => moved.addRun('x'));
      expect(set.changes, hasLength(1));
    });
  });

  group('the width of a merged cell', () {
    test('is the sum of the merged columns, in each row of the merge', () {
      final DocxDocument doc = _open(_threeByThree());
      final DocxTable table = _table(doc);
      _merge(table, 0, 0, 1, 1);
      final DocxTableWidth sum = DocxTableWidth.points(100);
      expect(table.rows[0].cells[0].properties.width, sum);
      expect(table.rows[1].cells[0].properties.width, sum);
      expect(table.rows[0].cells[1].properties.width?.widthPt, 50);
    });

    test('stays when a merged column has no width', () {
      final DocxDocument doc = _open(
        '<w:tbl><w:tblGrid><w:gridCol w:w="1000"/><w:gridCol/></w:tblGrid>'
        '${_tr(<String>[_tc('A', _width), _tc('B', _width)])}</w:tbl>',
      );
      final DocxTableCell merged = _merge(_table(doc), 0, 0, 0, 1);
      expect(merged.properties.width, DocxTableWidth.points(50));
    });

    test('stays when the sum is more than a width holds', () {
      final DocxDocument doc = _open(
        '<w:tbl><w:tblGrid><w:gridCol w:w="20000"/><w:gridCol w:w="20000"/>'
        '</w:tblGrid>${_tr(<String>[_tc('A', _width), _tc('B', _width)])}'
        '</w:tbl>',
      );
      final DocxTableCell merged = _merge(_table(doc), 0, 0, 0, 1);
      expect(merged.properties.width, DocxTableWidth.points(50));
    });

    test('stays when the merged columns have no width between them', () {
      final DocxDocument doc = _open(
        '<w:tbl><w:tblGrid><w:gridCol w:w="0"/><w:gridCol w:w="0"/>'
        '</w:tblGrid>${_tr(<String>[_tc('A', _width), _tc('B', _width)])}'
        '</w:tbl>',
      );
      final DocxTableCell merged = _merge(_table(doc), 0, 0, 0, 1);
      expect(merged.properties.width, DocxTableWidth.points(50));
    });

    test('stays when the merged cells are not in twips', () {
      const String percent = '<w:tcW w:w="2500" w:type="pct"/>';
      const String auto = '<w:tcW w:w="0" w:type="auto"/>';
      for (final (String, String, DocxTableWidth?) c
          in <(String, String, DocxTableWidth?)>[
            (percent, percent, DocxTableWidth.percent(50)),
            (auto, auto, const DocxTableWidth.auto()),
            ('', '', null),
            (percent, _width, DocxTableWidth.percent(50)),
            (_width, percent, DocxTableWidth.points(50)),
          ]) {
        final DocxDocument doc = _tableOf(2, <String>[
          _tr(<String>[_tc('A', c.$1), _tc('B', c.$2)]),
        ]);
        final DocxTableCell merged = _merge(_table(doc), 0, 0, 0, 1);
        expect(merged.properties.width, c.$3, reason: '${c.$1} ${c.$2}');
      }
    });

    test('stays when no cell of the row goes', () {
      const String auto = '<w:tcW w:w="0" w:type="auto"/>';
      final DocxDocument doc = _tableOf(1, <String>[
        _tr(<String>[_tc('A', auto)]),
        _tr(<String>[_tc('B', auto)]),
      ]);
      final DocxTableCell merged = _merge(_table(doc), 0, 0, 1, 0);
      expect(merged.properties.width, const DocxTableWidth.auto());
    });
  });

  group('a merge over what is merged', () {
    test('holds a cell spanning columns inside the range', () {
      final DocxDocument doc = _tableOf(3, <String>[
        _tr(<String>[_tc('A', _span2), _tc('C')]),
      ]);
      final DocxTableCell merged = _merge(_table(doc), 0, 0, 0, 2);
      expect(merged.properties.gridSpan, 3);
      expect(merged.text, 'A\nC');
    });

    test('holds a vertical merge inside the range', () {
      final DocxDocument doc = _tableOf(2, <String>[
        _tr(<String>[_tc('A', _restart), _tc('B')]),
        _tr(<String>[_empty(_continue), _tc('D')]),
      ]);
      final DocxTable table = _table(doc);
      _merge(table, 0, 0, 1, 1);
      expect(_rows(table), <String>['A/B/D', '']);
      expect(
        table.rows[0].cells.single.properties.verticalMerge,
        DocxVerticalMerge.restart,
      );
      expect(
        table.rows[1].cells.single.properties.verticalMerge,
        DocxVerticalMerge.continuation,
      );
    });

    test('of rows of different cells goes by the grid', () {
      final DocxDocument doc = _tableOf(3, <String>[
        _tr(<String>[_tc('A', _span2), _tc('C')]),
        _tr(<String>[_tc('D'), _tc('E'), _tc('F')]),
      ]);
      final DocxTable table = _table(doc);
      _merge(table, 0, 0, 1, 1);
      expect(_rows(table), <String>['A/D/E|C', '|F']);
      expect(table.rows[1].cells[0].properties.gridSpan, 2);
    });

    test('of rows around a bookmark keeps the bookmark', () {
      const String bookmark = '<w:bookmarkStart w:id="1" w:name="b"/>';
      final DocxDocument doc = _tableOf(1, <String>[
        _tr(<String>[_tc('A')]),
        bookmark,
        _tr(<String>[_tc('C')]),
      ]);
      expect(_merge(_table(doc), 0, 0, 1, 0).text, 'A\nC');
      expect(_saved(doc), contains(bookmark));
    });

    test('of rows next to a w:sdt that is outside the range goes', () {
      const String sdt =
          '<w:sdt><w:sdtContent><w:tr><w:tc><w:p/></w:tc></w:tr></w:sdtContent>'
          '</w:sdt>';
      final DocxDocument doc = _tableOf(1, <String>[
        sdt,
        _tr(<String>[_tc('A')]),
        _tr(<String>[_tc('B')]),
        sdt,
        _tr(<String>[_tc('C')]),
      ]);
      expect(_merge(_table(doc), 0, 0, 1, 0).text, 'A\nB');
    });

    test('of a range that is one cell changes nothing', () {
      final DocxDocument doc = _tableOf(3, <String>[
        _tr(<String>[_tc('A', _span2), _tc('C')]),
      ]);
      final DocxTable table = _table(doc);
      final ChangeSet set = editsOf(doc).transaction(() {
        expect(_merge(table, 0, 0, 0, 1), same(table.rows[0].cells[0]));
        expect(_merge(table, 0, 2, 0, 2), same(table.rows[0].cells[1]));
      });
      expect(set.isEmpty, isTrue);
    });

    test('w:gridBefore and w:gridAfter shift the columns', () {
      final DocxDocument doc = _tableOf(4, <String>[
        _tr(<String>[
          _tc('B'),
          _tc('C'),
        ], '<w:gridBefore w:val="1"/><w:gridAfter w:val="1"/>'),
      ]);
      final DocxTable table = _table(doc);
      final DocxTableCell merged = _merge(table, 0, 1, 0, 2);
      expect(merged.text, 'B\nC');
      expect(merged.properties.gridSpan, 2);
    });
  });

  group('a merge that does not fit', () {
    /// Expects the merge of the range to throw [ArgumentError] and change
    /// nothing.
    void refuses(DocxDocument doc, int r0, int c0, int r1, int c1) {
      final DocxTable table = _table(doc);
      final List<String> before = _rows(table);
      expect(() => _merge(table, r0, c0, r1, c1), throwsArgumentError);
      expect(_rows(table), before);
      expect(editsOf(doc).log.hasChanges, isFalse);
    }

    test('a merge past the grid throws ArgumentError', () {
      refuses(_open(_threeByThree()), 0, 0, 0, 3);
      refuses(_open(_threeByThree()), 0, 0, 3, 0);
      refuses(_open(_threeByThree()), -1, 0, 0, 0);
      refuses(_open(_threeByThree()), 0, -1, 0, 0);
    });

    test('a range that runs backwards throws ArgumentError', () {
      refuses(_open(_threeByThree()), 1, 0, 0, 0);
      refuses(_open(_threeByThree()), 0, 1, 0, 0);
    });

    test('a merge that splits a merged cell throws ArgumentError', () {
      final List<String> spanned = <String>[
        _tr(<String>[_tc('A', _span2), _tc('C')]),
      ];
      refuses(_tableOf(3, spanned), 0, 1, 0, 2);
      refuses(_tableOf(3, spanned), 0, 0, 0, 0);
      final List<String> stacked = <String>[
        _tr(<String>[_tc('A', _restart), _tc('B')]),
        _tr(<String>[_empty(_continue), _tc('D')]),
        _tr(<String>[_tc('E'), _tc('F')]),
      ];
      // Cut from above: the range starts on a continuation.
      refuses(_tableOf(2, stacked), 1, 0, 2, 0);
      refuses(_tableOf(2, stacked), 1, 0, 1, 1);
      // Cut from below: the merged cell runs on past the last row.
      refuses(_tableOf(2, stacked), 0, 0, 0, 1);
    });

    test('a range on the columns of w:gridBefore throws ArgumentError', () {
      final List<String> rows = <String>[
        _tr(<String>[_tc('B'), _tc('C')], '<w:gridBefore w:val="1"/>'),
      ];
      refuses(_tableOf(3, rows), 0, 0, 0, 1);
    });

    test('a range on the columns of w:gridAfter throws ArgumentError', () {
      final List<String> rows = <String>[
        _tr(<String>[_tc('A'), _tc('B')], '<w:gridAfter w:val="1"/>'),
      ];
      refuses(_tableOf(3, rows), 0, 1, 0, 2);
    });

    final Map<String, String> hiding = <String, String>{
      'w:sdt':
          '<w:sdt><w:sdtContent>${_tr(<String>[_tc('H')])}</w:sdtContent>'
          '</w:sdt>',
      'w:customXml':
          '<w:customXml w:element="x">${_tr(<String>[_tc('H')])}</w:customXml>',
    };
    for (final MapEntry<String, String> kept in hiding.entries) {
      test('rows around a ${kept.key} throw ArgumentError', () {
        refuses(
          _tableOf(1, <String>[
            _tr(<String>[_tc('A')]),
            kept.value,
            _tr(<String>[_tc('C')]),
          ]),
          0,
          0,
          1,
          0,
        );
      });
    }

    test('a span past 63 columns throws ArgumentError', () {
      final DocxDocument doc = _tableOf(64, <String>[
        _tr(<String>[for (int c = 0; c < 64; c++) _tc('x')]),
      ]);
      refuses(doc, 0, 0, 0, 63);
    });

    test('a table that would nest past 80 deep throws ArgumentError', () {
      final String chain =
          '${'<w:tbl><w:tr><w:tc>' * 81}<w:p/>'
          '${'</w:tc></w:tr></w:tbl><w:p/>' * 81}';
      final DocxDocument doc = _open(
        '<w:tbl>${_grid(2)}'
        '${_tr(<String>[_tc('A'), '<w:tc>$chain</w:tc>'])}</w:tbl>',
        limits: const DocxReadLimits(maxDepth: 1000),
      );
      refuses(doc, 0, 0, 0, 1);
    });
  });

  group('an irregular file', () {
    final Map<String, String> files = <String, String>{
      'rows of unequal cell counts':
          '<w:tbl>${_grid(3)}${_tr(<String>[_tc('A'), _tc('B'), _tc('C')])}'
          '${_tr(<String>[_tc('D'), _tc('E')])}</w:tbl>',
      'a w:gridSpan past the grid':
          '<w:tbl>${_grid(2)}${_tr(<String>[_tc('A'), _tc('B')])}'
          '${_tr(<String>[_tc('C', '<w:gridSpan w:val="3"/>')])}</w:tbl>',
      'a w:vMerge continue with no restart':
          '<w:tbl>${_grid(2)}${_tr(<String>[_tc('A'), _tc('B')])}'
          '${_tr(<String>[_tc('C', _continue), _tc('D')])}</w:tbl>',
      'no w:tblGrid':
          '<w:tbl>${_tr(<String>[_tc('A'), _tc('B')])}'
          '${_tr(<String>[_tc('C'), _tc('D')])}</w:tbl>',
    };

    for (final MapEntry<String, String> file in files.entries) {
      test('${file.key}: opens, reads, round trips, and mergeCells throws '
          'ArgumentError', () {
        final DocxDocument doc = _open(file.value);
        final DocxTable table = _table(doc);
        final List<String> rows = _rows(table);
        expect(rows, hasLength(2));
        expect(_saved(doc), contains(file.value));
        expect(() => _merge(table, 0, 0, 1, 1), throwsArgumentError);
        expect(_rows(table), rows);
        expect(editsOf(doc).log.hasChanges, isFalse);
        expect(_saved(doc), contains(file.value));
      });
    }

    test('a continue with no restart inside the range throws too', () {
      final DocxDocument doc = _tableOf(2, <String>[
        _tr(<String>[_tc('A'), _tc('B')]),
        _tr(<String>[_tc('C', _continue), _tc('D')]),
      ]);
      expect(() => _merge(_table(doc), 0, 0, 1, 0), throwsArgumentError);
    });

    test('a continue under another span inside the range throws too', () {
      final DocxDocument doc = _tableOf(2, <String>[
        _tr(<String>[_tc('A', _restart), _tc('B')]),
        _tr(<String>[_tc('C', '$_span2$_continue')]),
      ]);
      expect(() => _merge(_table(doc), 0, 0, 1, 1), throwsArgumentError);
    });

    test('a row with fewer cells throws even in the columns it has', () {
      final DocxDocument doc = _tableOf(3, <String>[
        _tr(<String>[_tc('A'), _tc('B')]),
      ]);
      expect(() => _merge(_table(doc), 0, 0, 0, 1), throwsArgumentError);
    });

    test('an irregular row outside the range does not matter', () {
      final DocxDocument doc = _tableOf(2, <String>[
        _tr(<String>[_tc('A'), _tc('B')]),
        _tr(<String>[_tc('C')]),
      ]);
      final DocxTable table = _table(doc);
      _merge(table, 0, 0, 0, 1);
      expect(_rows(table), <String>['A/B', 'C']);
    });

    test('an empty w:tblGrid throws ArgumentError', () {
      final DocxDocument doc = _open(
        '<w:tbl><w:tblGrid/>${_tr(<String>[_tc('A'), _tc('B')])}</w:tbl>',
      );
      expect(() => _merge(_table(doc), 0, 0, 0, 1), throwsArgumentError);
    });
  });

  group('undo', () {
    test('a merge undoes in one step', () {
      final String body = _threeByThree();
      final DocxDocument doc = _open(body);
      final DocxTable table = _table(doc);
      final DocxTableCell first = table.rows[1].cells[1];
      final ChangeLog log = editsOf(doc).log;
      final _RecordingSink sink = _RecordingSink(editsOf(doc));
      attachSink(table, sink);
      _merge(table, 1, 1, 2, 2);
      expect(sink.outside, 0);
      final ChangeSet set = sink.sets.single;
      expect(set.isEmpty, isFalse);
      log.revertSet(set);
      expect(_rows(table), <String>['A|B|C', 'D|E|F', 'G|H|I']);
      expect(first.properties.gridSpan, isNull);
      expect(first.properties.verticalMerge, isNull);
      expect(_saved(doc), contains(body));
      log.reapplySet(set);
      expect(_rows(table), <String>['A|B|C', 'D|E/F/H/I', 'G|']);
      expect(first.properties.gridSpan, 2);
      log.revertSet(set);
      expect(_saved(doc), contains(body));
    });

    test('a merge that fails half way rolls back', () {
      final String body = _threeByThree();
      final DocxDocument doc = _open(body);
      final DocxTable table = _table(doc);
      final DocxEdits edits = editsOf(doc);
      int records = 0;
      edits.afterRecord = () {
        if (++records == 6) throw StateError('hook');
      };
      expect(() => _merge(table, 1, 1, 2, 2), throwsStateError);
      edits.afterRecord = null;
      expect(_rows(table), <String>['A|B|C', 'D|E|F', 'G|H|I']);
      expect(_saved(doc), contains(body));
    });
  });

  group('cellAtGrid', () {
    test('counts w:gridBefore and each span', () {
      final DocxDocument doc = _tableOf(5, <String>[
        _tr(<String>[_tc('B', _span2), _tc('D')], '<w:gridBefore w:val="1"/>'),
      ]);
      final DocxTable table = _table(doc);
      final List<DocxTableCell> cells = table.rows.single.cells;
      expect(cellAtGrid(table, 0, 0), isNull);
      expect(cellAtGrid(table, 0, 1), same(cells[0]));
      expect(cellAtGrid(table, 0, 2), same(cells[0]));
      expect(cellAtGrid(table, 0, 3), same(cells[1]));
      expect(cellAtGrid(table, 0, 4), isNull);
    });

    test('reads a span set since', () {
      final DocxDocument doc = _tableOf(2, <String>[
        _tr(<String>[_tc('A')]),
      ]);
      final DocxTable table = _table(doc);
      expect(cellAtGrid(table, 0, 1), isNull);
      table.rows.single.cells.single.properties.gridSpan = 2;
      expect(cellAtGrid(table, 0, 1), same(table.rows.single.cells.single));
    });
  });

  group('gridSpan', () {
    test('past the grid throws ArgumentError, and nothing changes', () {
      final DocxDocument doc = _open(_threeByThree());
      final DocxTableCell cell = _table(doc).rows[0].cells[0];
      expect(() => cell.properties.gridSpan = 2, throwsArgumentError);
      expect(cell.properties.gridSpan, isNull);
      expect(editsOf(doc).log.hasChanges, isFalse);
    });

    test('out of range is still a RangeError', () {
      final DocxDocument doc = _open(_threeByThree());
      final DocxTableCell cell = _table(doc).rows[0].cells[0];
      expect(() => cell.properties.gridSpan = 64, throwsRangeError);
    });

    test('fits once a cell is removed first', () {
      final DocxDocument doc = _open(_threeByThree());
      final DocxTableRow row = _table(doc).rows[0];
      row.removeCellAt(2);
      row.cells[0].properties.gridSpan = 2;
      expect(row.cells[0].properties.gridSpan, 2);
    });

    test('counts w:gridBefore and w:gridAfter', () {
      final List<String> rows = <String>[
        _tr(<String>[
          _tc('B'),
        ], '<w:gridBefore w:val="1"/><w:gridAfter w:val="1"/>'),
      ];
      final DocxTableCell fits = _table(
        _tableOf(4, rows),
      ).rows.single.cells.single;
      fits.properties.gridSpan = 2;
      expect(fits.properties.gridSpan, 2);
      final DocxTableCell over = _table(
        _tableOf(3, rows),
      ).rows.single.cells.single;
      expect(() => over.properties.gridSpan = 2, throwsArgumentError);
    });

    test('is not checked in a row in no table, or in no row', () {
      final DocxTableRow row = DocxTableRow(cells: 2);
      row.cells[0].properties.gridSpan = 63;
      expect(row.cells[0].properties.gridSpan, 63);
      final DocxTableCell cell = DocxTableCell();
      cell.properties.gridSpan = 63;
      expect(cell.properties.gridSpan, 63);
    });

    test('is not checked in a table without a grid', () {
      final DocxDocument doc = _open(
        '<w:tbl>${_tr(<String>[_tc('A')])}</w:tbl>',
      );
      final DocxTableCell cell = _table(doc).rows.single.cells.single;
      cell.properties.gridSpan = 5;
      expect(cell.properties.gridSpan, 5);
    });

    test('a file that does not fit reads, and can be narrowed', () {
      const String span = '<w:gridSpan w:val="3"/>';
      final DocxDocument doc = _tableOf(2, <String>[
        _tr(<String>[_tc('A', span), _tc('B')]),
      ]);
      final DocxTableCell cell = _table(doc).rows.single.cells.first;
      expect(cell.properties.gridSpan, 3);
      cell.properties.gridSpan = cell.properties.gridSpan;
      expect(editsOf(doc).log.hasChanges, isFalse);
      cell.properties.gridSpan = 2;
      expect(cell.properties.gridSpan, 2);
      expect(() => cell.properties.gridSpan = 3, throwsArgumentError);
    });
  });

  group('gridSpan in a vertical merge', () {
    /// `[A restart][B]` over `[continue][D]`, in a grid of two columns.
    DocxDocument stacked() => _tableOf(2, <String>[
      _tr(<String>[_tc('A', _restart), _tc('B')]),
      _tr(<String>[_empty(_continue), _tc('D')]),
    ]);

    /// One cell of two columns restarting, one continuing below it.
    DocxDocument wide() => _tableOf(2, <String>[
      _tr(<String>[_tc('A', '$_span2$_restart')]),
      _tr(<String>[_empty('$_span2$_continue')]),
    ]);

    test('a continuation widened past the cell above throws', () {
      final DocxDocument doc = stacked();
      final DocxTableRow row = _table(doc).rows[1];
      row.removeCellAt(1);
      final String saved = _saved(doc);
      expect(
        () => row.cells.single.properties.gridSpan = 2,
        throwsArgumentError,
      );
      expect(row.cells.single.properties.gridSpan, isNull);
      expect(_saved(doc), saved);
    });

    test('a cell widened past the continuation below throws', () {
      final DocxDocument doc = stacked();
      final DocxTableRow row = _table(doc).rows[0];
      row.removeCellAt(1);
      expect(
        () => row.cells.single.properties.gridSpan = 2,
        throwsArgumentError,
      );
      expect(row.cells.single.properties.gridSpan, isNull);
    });

    test('a continuation narrowed under the cell above throws', () {
      final DocxTableCellProperties p = _table(
        wide(),
      ).rows[1].cells.single.properties;
      expect(() => p.gridSpan = 1, throwsArgumentError);
      expect(() => p.gridSpan = null, throwsArgumentError);
      expect(
        () => p.clear(DocxTableCellProperty.gridSpan),
        throwsArgumentError,
      );
      expect(p.gridSpan, 2);
    });

    test('a cell narrowed over the continuation below throws', () {
      final DocxTableCellProperties p = _table(
        wide(),
      ).rows[0].cells.single.properties;
      expect(() => p.gridSpan = 1, throwsArgumentError);
      expect(() => p.gridSpan = null, throwsArgumentError);
      expect(
        () => p.clear(DocxTableCellProperty.gridSpan),
        throwsArgumentError,
      );
      expect(p.gridSpan, 2);
    });

    test('a span that moves a merged cell along the row throws', () {
      final DocxDocument doc = _tableOf(3, <String>[
        _tr(<String>[_tc('A'), _tc('B', _restart)]),
        _tr(<String>[_tc('C'), _empty(_continue)]),
      ]);
      final DocxTable table = _table(doc);
      expect(
        () => table.rows[0].cells[0].properties.gridSpan = 2,
        throwsArgumentError,
      );
      expect(
        () => table.rows[1].cells[0].properties.gridSpan = 2,
        throwsArgumentError,
      );
    });

    test('a span that changes nothing is no change', () {
      final DocxDocument doc = stacked();
      final DocxTable table = _table(doc);
      final DocxTableCellProperties p = table.rows[1].cells[0].properties;
      p.gridSpan = p.gridSpan;
      final DocxDocument other = wide();
      final DocxTableCellProperties q = _table(
        other,
      ).rows[0].cells.single.properties;
      q.gridSpan = 2;
      expect(editsOf(doc).log.hasChanges, isFalse);
      expect(editsOf(other).log.hasChanges, isFalse);
    });

    test('a cell away from the merge still takes a span', () {
      final DocxDocument doc = _tableOf(3, <String>[
        _tr(<String>[_tc('A', _restart), _tc('B')]),
        _tr(<String>[_empty(_continue), _tc('D')]),
      ]);
      final DocxTableCell cell = _table(doc).rows[0].cells[1];
      cell.properties.gridSpan = 2;
      expect(cell.properties.gridSpan, 2);
    });

    test('a continuation read out of line can be brought into line', () {
      final DocxDocument doc = _tableOf(2, <String>[
        _tr(<String>[_tc('A', _span2)]),
        _tr(<String>[_empty(_continue), _tc('D')]),
      ]);
      final DocxTableRow row = _table(doc).rows[1];
      row.removeCellAt(1);
      row.cells.single.properties.gridSpan = 2;
      expect(row.cells.single.properties.gridSpan, 2);
    });

    test('spans first, then verticalMerge, builds a merge by hand', () {
      final DocxTable table = DocxTable(columns: 2, rows: 2);
      for (final DocxTableRow row in table.rows) {
        row.removeCellAt(1);
        row.cells.single.properties.gridSpan = 2;
      }
      table.rows[0].cells.single.properties.verticalMerge =
          DocxVerticalMerge.restart;
      table.rows[1].cells.single.properties.verticalMerge =
          DocxVerticalMerge.continuation;
      expect(
        table.rows[1].cells.single.properties.verticalMerge,
        DocxVerticalMerge.continuation,
      );
    });

    test('a merge widens merged cells past its own transient states', () {
      final DocxDocument doc = _tableOf(3, <String>[
        _tr(<String>[_tc('A', _restart), _tc('B'), _tc('C')]),
        _tr(<String>[_empty(_continue), _tc('E'), _tc('F')]),
      ]);
      final DocxTable table = _table(doc);
      _merge(table, 0, 0, 1, 1);
      expect(table.rows[0].cells[0].properties.gridSpan, 2);
      expect(table.rows[1].cells[0].properties.gridSpan, 2);
    });
  });

  group('verticalMerge', () {
    test('continuation in the first row throws ArgumentError', () {
      final DocxDocument doc = _open(_threeByThree());
      final DocxTableCell cell = _table(doc).rows[0].cells[0];
      expect(
        () => cell.properties.verticalMerge = DocxVerticalMerge.continuation,
        throwsArgumentError,
      );
      expect(cell.properties.verticalMerge, isNull);
      expect(editsOf(doc).log.hasChanges, isFalse);
    });

    test('continuation under another span throws ArgumentError', () {
      final DocxDocument doc = _tableOf(2, <String>[
        _tr(<String>[_tc('A', _span2)]),
        _tr(<String>[_tc('C'), _tc('D')]),
      ]);
      final DocxTableCell cell = _table(doc).rows[1].cells[0];
      expect(
        () => cell.properties.verticalMerge = DocxVerticalMerge.continuation,
        throwsArgumentError,
      );
    });

    test('continuation with nothing above throws ArgumentError', () {
      final DocxDocument doc = _tableOf(2, <String>[
        _tr(<String>[_tc('A')]),
        _tr(<String>[_tc('C'), _tc('D')]),
      ]);
      final DocxTableCell cell = _table(doc).rows[1].cells[1];
      expect(
        () => cell.properties.verticalMerge = DocxVerticalMerge.continuation,
        throwsArgumentError,
      );
    });

    test('continuation under a cell of the same span sets', () {
      final DocxDocument doc = _open(_threeByThree());
      final DocxTable table = _table(doc);
      table.rows[0].cells[1].properties.verticalMerge =
          DocxVerticalMerge.restart;
      table.rows[1].cells[1].properties.verticalMerge =
          DocxVerticalMerge.continuation;
      expect(
        table.rows[1].cells[1].properties.verticalMerge,
        DocxVerticalMerge.continuation,
      );
    });

    test('restart and null are not checked', () {
      final DocxDocument doc = _open(_threeByThree());
      final DocxTableCell cell = _table(doc).rows[0].cells[0];
      cell.properties.verticalMerge = DocxVerticalMerge.restart;
      cell.properties.verticalMerge = null;
      expect(cell.properties.verticalMerge, isNull);
    });

    test('is not checked in a row in no table', () {
      final DocxTableRow row = DocxTableRow();
      row.cells.single.properties.verticalMerge =
          DocxVerticalMerge.continuation;
      expect(
        row.cells.single.properties.verticalMerge,
        DocxVerticalMerge.continuation,
      );
    });

    test('a continue read with no restart can be set to what it reads', () {
      final DocxDocument doc = _tableOf(1, <String>[
        _tr(<String>[_tc('A', _continue)]),
      ]);
      final DocxTableCell cell = _table(doc).rows.single.cells.single;
      cell.properties.verticalMerge = cell.properties.verticalMerge;
      expect(editsOf(doc).log.hasChanges, isFalse);
    });
  });

  group('a row inserted', () {
    test('whose spans exceed the grid throws, and nothing changes', () {
      final DocxDocument doc = _open(_threeByThree());
      final DocxTable table = _table(doc);
      final DocxTableRow row = DocxTableRow(cells: 4);
      expect(() => table.insertRowAt(0, row), throwsArgumentError);
      expect(table.rows, hasLength(3));
      expect(parentOf(row), isNull);
      expect(editsOf(doc).log.hasChanges, isFalse);
    });

    test('counts the spans of its cells', () {
      final DocxDocument doc = _open(_threeByThree());
      final DocxTable table = _table(doc);
      final DocxTableRow row = DocxTableRow(cells: 2);
      row.cells[0].properties.gridSpan = 3;
      expect(() => table.insertRowAt(3, row), throwsArgumentError);
      row.cells[0].properties.gridSpan = 2;
      table.insertRowAt(3, row);
      expect(table.rows, hasLength(4));
    });

    test('that fits, with fewer columns, goes in', () {
      final DocxTable table = DocxTable(columns: 3);
      table.insertRowAt(1, DocxTableRow(cells: 2));
      expect(table.rows, hasLength(2));
    });

    test('counts w:gridBefore and w:gridAfter, moved from another table', () {
      final DocxDocument source = _tableOf(3, <String>[
        _tr(<String>[_tc('x')]),
        _tr(<String>[
          _tc('B'),
          _tc('C'),
        ], '<w:gridBefore w:val="1"/><w:gridAfter w:val="0"/>'),
      ]);
      final DocxTableRow row = _table(source).rows[1];
      _table(source).removeRowAt(1);
      final DocxTable narrow = DocxTable(columns: 2);
      expect(() => narrow.insertRowAt(0, row), throwsArgumentError);
      final DocxTable wide = DocxTable(columns: 3);
      wide.insertRowAt(0, row);
      expect(wide.rows, hasLength(2));
    });

    /// A new row of [cells] cells, the first a continuation.
    DocxTableRow continuing(int cells) {
      final DocxTableRow row = DocxTableRow(cells: cells);
      row.cells.first.properties.verticalMerge = DocxVerticalMerge.continuation;
      return row;
    }

    test('with a continuation first in the table throws', () {
      final DocxDocument doc = _open(_threeByThree());
      final DocxTable table = _table(doc);
      final DocxTableRow row = continuing(3);
      expect(() => table.insertRowAt(0, row), throwsArgumentError);
      expect(table.rows, hasLength(3));
      expect(parentOf(row), isNull);
      expect(editsOf(doc).log.hasChanges, isFalse);
    });

    test('with a continuation under another span throws', () {
      final DocxDocument doc = _tableOf(2, <String>[
        _tr(<String>[_tc('A', _span2)]),
      ]);
      final DocxTable table = _table(doc);
      expect(() => table.insertRowAt(1, continuing(2)), throwsArgumentError);
      expect(table.rows, hasLength(1));
    });

    test('with a continuation is judged by the row above its index', () {
      final DocxDocument doc = _tableOf(2, <String>[
        _tr(<String>[_tc('A', _span2)]),
        _tr(<String>[_tc('C'), _tc('D')]),
      ]);
      final DocxTable table = _table(doc);
      expect(() => table.insertRowAt(1, continuing(2)), throwsArgumentError);
      table.insertRowAt(2, continuing(2));
      expect(table.rows, hasLength(3));
    });

    test('with a continuation in a table without a grid is checked', () {
      final DocxDocument doc = _open(
        '<w:tbl>${_tr(<String>[_tc('A')])}</w:tbl>',
      );
      expect(
        () => _table(doc).insertRowAt(0, continuing(1)),
        throwsArgumentError,
      );
    });

    test('at an index out of range is a RangeError', () {
      final DocxTable table = DocxTable(columns: 1);
      expect(() => table.insertRowAt(5, continuing(1)), throwsRangeError);
    });

    test('that is plain may go inside a vertical merge', () {
      final DocxDocument doc = _tableOf(2, <String>[
        _tr(<String>[_tc('A', _restart), _tc('B')]),
        _tr(<String>[_empty(_continue), _tc('D')]),
      ]);
      _table(doc).insertRowAt(1, DocxTableRow(cells: 2));
      expect(_table(doc).rows, hasLength(3));
    });

    test('a removal that orphans a merge is allowed', () {
      final DocxDocument doc = _tableOf(2, <String>[
        _tr(<String>[_tc('A', _restart), _tc('B')]),
        _tr(<String>[_empty(_continue), _tc('D')]),
      ]);
      _table(doc).removeRowAt(0);
      expect(_table(doc).rows, hasLength(1));
    });

    test('in a table without a grid is not checked', () {
      final DocxDocument doc = _open(
        '<w:tbl>${_tr(<String>[_tc('A')])}</w:tbl>',
      );
      _table(doc).insertRowAt(1, DocxTableRow(cells: 5));
      expect(_table(doc).rows, hasLength(2));
    });

    test('that is in a table still throws StateError', () {
      final DocxTable table = DocxTable(columns: 1, rows: 2);
      expect(() => table.insertRowAt(0, table.rows.first), throwsStateError);
    });
  });

  group('a cell inserted', () {
    test('past the grid throws, and nothing changes', () {
      final DocxDocument doc = _open(_threeByThree());
      final DocxTableRow row = _table(doc).rows[0];
      final DocxTableCell cell = DocxTableCell();
      expect(() => row.insertCellAt(0, cell), throwsArgumentError);
      expect(row.cells, hasLength(3));
      expect(parentOf(cell), isNull);
      expect(editsOf(doc).log.hasChanges, isFalse);
    });

    test('counts its span and what the row skips', () {
      final DocxDocument doc = _tableOf(4, <String>[
        _tr(<String>[_tc('B')], '<w:gridBefore w:val="1"/>'),
      ]);
      final DocxTableRow row = _table(doc).rows.single;
      final DocxTableCell cell = DocxTableCell();
      cell.properties.gridSpan = 3;
      expect(() => row.insertCellAt(1, cell), throwsArgumentError);
      cell.properties.gridSpan = 2;
      row.insertCellAt(1, cell);
      expect(row.cells, hasLength(2));
    });

    test('in a row in no table is not checked', () {
      final DocxTableRow row = DocxTableRow(cells: 63);
      row.insertCellAt(0, DocxTableCell());
      expect(row.cells, hasLength(64));
    });

    test('in a table without a grid is not checked', () {
      final DocxDocument doc = _open(
        '<w:tbl>${_tr(<String>[_tc('A')])}</w:tbl>',
      );
      final DocxTableRow row = _table(doc).rows.single;
      row.insertCellAt(1, DocxTableCell());
      expect(row.cells, hasLength(2));
    });

    test('that is in a row still throws StateError', () {
      final DocxTable table = DocxTable(columns: 1);
      final DocxTableRow row = table.rows.single;
      expect(() => row.insertCellAt(0, row.cells.single), throwsStateError);
    });
  });
}
