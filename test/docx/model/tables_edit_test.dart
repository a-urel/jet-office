// Tests editing a table: rows, cells and the blocks of a cell, in a document
// and in none. A table built with the API writes what the schema requires, an
// index counts the typed rows and cells only, what the model does not show
// stays where it was, every edit undoes, and a tree cannot hold itself or nest
// past what a read accepts. They build documents in memory, so they run on the
// web as well.
import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/docx/docx_document.dart' show editsOf;
import 'package:jet_office/src/docx/model/blocks.dart';
import 'package:jet_office/src/docx/model/edit_sink.dart';
import 'package:jet_office/src/docx/model/primitives.dart';
import 'package:jet_office/src/opc/change_log.dart';
import 'package:jet_office/src/opc/ooxml.dart' show Ns;
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../support/docx_builder.dart';
import '../support/styles_documents.dart';

const String _decls = 'xmlns:w="${Ns.w}" xmlns:x="urn:x"';

/// Opens the document whose body holds [body].
DocxDocument _open(
  String body, {
  DocxReadLimits limits = const DocxReadLimits(),
}) => DocxDocument.open(
  buildDocx(
    document: '<w:document $_decls><w:body>$body</w:body></w:document>',
  ),
  limits: limits,
);

/// A paragraph that holds [text].
String _p(String text) => '<w:p><w:r><w:t>$text</w:t></w:r></w:p>';

/// A cell of one paragraph that holds [text].
String _tc(String text) => '<w:tc>${_p(text)}</w:tc>';

/// A row of one cell that holds [text].
String _tr(String text) => '<w:tr>${_tc(text)}</w:tr>';

/// A document of one table of the rows `A` and `B`, one cell each.
DocxDocument _twoRows() => _open('<w:tbl>${_tr('A')}${_tr('B')}</w:tbl>');

/// The first block of [doc], a table.
DocxTable _table(DocxDocument doc) => doc.body.blocks.first as DocxTable;

/// The only cell of a table of one row.
DocxTableCell _cell(DocxTable table) => table.rows.single.cells.single;

/// The main part of [doc] as saved.
XmlDocument _saved(DocxDocument doc) =>
    XmlDocument.parse(readDocxText(doc.save().bytes)['word/document.xml']!);

/// The elements `w:<name>` of [xml], in document order.
List<XmlElement> _all(XmlDocument xml, String name) =>
    xml.findAllElements(name, namespaceUri: Ns.w).toList();

/// The local names of the children of [element], in order.
List<String> _names(XmlElement element) => <String>[
  for (final XmlElement e in element.childElements) e.localName,
];

/// The text of each row of [table], its cells joined by `|`.
List<String> _rows(DocxTable table) => <String>[
  for (final DocxTableRow row in table.rows)
    row.cells.map((DocxTableCell c) => c.text).join('|'),
];

/// A new row of one cell that holds [text].
DocxTableRow _row(String text) {
  final DocxTableRow row = DocxTableRow();
  (row.cells.single.blocks.single as DocxParagraph).addRun(text);
  return row;
}

/// [levels] new tables, each in the only cell of the one before.
DocxTable _chain(int levels) {
  final DocxTable top = DocxTable(columns: 1);
  DocxTable at = top;
  for (int i = 1; i < levels; i++) {
    final DocxTable inner = DocxTable(columns: 1);
    _cell(at).insertBlock(0, inner);
    at = inner;
  }
  return top;
}

/// The cell at the bottom of a chain of tables.
DocxTableCell _bottom(DocxTable top) {
  DocxTableCell cell = _cell(top);
  while (cell.blocks.first is DocxTable) {
    cell = _cell(cell.blocks.first as DocxTable);
  }
  return cell;
}

/// The innermost table of a chain of tables.
DocxTable _deepest(DocxTable top) {
  DocxTable at = top;
  while (_cell(at).blocks.first is DocxTable) {
    at = _cell(at).blocks.first as DocxTable;
  }
  return at;
}

void main() {
  group('a new table', () {
    test('has the rows and columns asked for, with empty cells', () {
      final DocxTable table = DocxTable(columns: 3, rows: 2);
      expect(table.rows, hasLength(2));
      for (final DocxTableRow row in table.rows) {
        expect(row.cells, hasLength(3));
        for (final DocxTableCell cell in row.cells) {
          expect(cell.blocks.single, isA<DocxParagraph>());
          expect(cell.text, '');
        }
      }
    });

    test('has one row by default', () {
      expect(DocxTable(columns: 2).rows, hasLength(1));
    });

    test('divides 9062 twips among its columns, rounded down', () {
      expect(DocxTable(columns: 3).gridColumnsPt, <double>[151, 151, 151]);
      final DocxTable seven = DocxTable(columns: 7);
      expect(seven.gridColumnsPt, List<double>.filled(7, 1294 / 20));
      expect(
        seven.rows.single.cells.first.properties.width,
        DocxTableWidth.points(1294 / 20),
      );
    });

    test('takes 1 to 63 columns and at least one row', () {
      expect(DocxTable(columns: 63).rows.single.cells, hasLength(63));
      expect(() => DocxTable(columns: 0), throwsRangeError);
      expect(() => DocxTable(columns: 64), throwsRangeError);
      expect(() => DocxTable(columns: 1, rows: 0), throwsRangeError);
    });

    test('writes w:tblPr and w:tblGrid, and each w:tcW in twips', () {
      final DocxDocument doc = _open(_p('a'));
      doc.body.insertBlock(1, DocxTable(columns: 3, rows: 2));
      final XmlDocument xml = _saved(doc);
      final XmlElement tbl = _all(xml, 'tbl').single;
      expect(_names(tbl), <String>['tblPr', 'tblGrid', 'tr', 'tr']);
      expect(tbl.childElements.first.childElements, isEmpty);
      final List<XmlElement> columns = _all(xml, 'gridCol');
      expect(columns, hasLength(3));
      for (final XmlElement column in columns) {
        expect(column.getAttribute('w', namespaceUri: Ns.w), '3020');
      }
      final List<XmlElement> widths = _all(xml, 'tcW');
      expect(widths, hasLength(6));
      for (final XmlElement width in widths) {
        expect(width.getAttribute('w', namespaceUri: Ns.w), '3020');
        expect(width.getAttribute('type', namespaceUri: Ns.w), 'dxa');
      }
      for (final XmlElement tc in _all(xml, 'tc')) {
        expect(_names(tc), <String>['tcPr', 'p']);
      }
    });

    test('writes w:tblPr once when a value was set', () {
      final DocxDocument doc = _open(_p('a'));
      final DocxTable table = DocxTable(columns: 1);
      table.properties.alignment = DocxTableAlignment.center;
      doc.body.insertBlock(1, table);
      final XmlElement tbl = _all(_saved(doc), 'tbl').single;
      expect(_names(tbl), <String>['tblPr', 'tblGrid', 'tr']);
      expect(_names(tbl.childElements.first), <String>['jc']);
    });

    test('a table read without w:tblPr still writes none', () {
      final DocxDocument doc = _open('<w:tbl>${_tr('A')}</w:tbl>');
      _cell(_table(doc)).addParagraph('b');
      expect(_names(_all(_saved(doc), 'tbl').single), <String>['tr']);
    });

    test('a new row has the cells asked for, one by default', () {
      expect(DocxTableRow().cells, hasLength(1));
      expect(DocxTableRow(cells: 4).cells, hasLength(4));
      expect(() => DocxTableRow(cells: 0), throwsRangeError);
      expect(() => DocxTableRow(cells: 64), throwsRangeError);
    });

    test('a new cell holds one paragraph of its text', () {
      expect(DocxTableCell().blocks.single, isA<DocxParagraph>());
      expect(DocxTableCell().text, '');
      expect(DocxTableCell('x').text, 'x');
      expect(
        blockContainerOf(DocxTableCell('x').blocks.single),
        isA<DocxTableCell>(),
      );
    });
  });

  group('rows', () {
    test('an inserted row is at its index, and undoes and redoes', () {
      final DocxDocument doc = _twoRows();
      final DocxTable table = _table(doc);
      final DocxTableRow row = _row('N');
      final ChangeSet set = editsOf(
        doc,
      ).transaction(() => table.insertRowAt(1, row));
      expect(set.changes, hasLength(1));
      expect(_rows(table), <String>['A', 'N', 'B']);
      editsOf(doc).log.revertSet(set);
      expect(_rows(table), <String>['A', 'B']);
      editsOf(doc).log.reapplySet(set);
      expect(_rows(table), <String>['A', 'N', 'B']);
    });

    test('a removed row can go in again, and the removal undoes', () {
      final DocxDocument doc = _twoRows();
      final DocxTable table = _table(doc);
      final DocxTableRow first = table.rows.first;
      final ChangeSet set = editsOf(
        doc,
      ).transaction(() => table.removeRowAt(0));
      expect(_rows(table), <String>['B']);
      editsOf(doc).log.revertSet(set);
      expect(_rows(table), <String>['A', 'B']);
      expect(table.rows.first, same(first));
      editsOf(doc).log.reapplySet(set);
      expect(_rows(table), <String>['B']);
      table.insertRowAt(1, first);
      expect(_rows(table), <String>['B', 'A']);
    });

    test('an index out of range throws RangeError', () {
      final DocxTable table = _table(_twoRows());
      expect(() => table.insertRowAt(-1, DocxTableRow()), throwsRangeError);
      expect(() => table.insertRowAt(3, DocxTableRow()), throwsRangeError);
      expect(() => table.removeRowAt(2), throwsRangeError);
      expect(_rows(table), <String>['A', 'B']);
    });

    test('removing the last row throws StateError and changes nothing', () {
      final DocxDocument doc = _open('<w:tbl>${_tr('A')}</w:tbl>');
      final DocxTable table = _table(doc);
      expect(() => table.removeRowAt(0), throwsStateError);
      expect(_rows(table), <String>['A']);
      expect(editsOf(doc).log.hasChanges, isFalse);
    });

    test('a file\'s empty table is kept as read and takes a row', () {
      final DocxDocument doc = _open('<w:tbl><w:tblGrid/></w:tbl>');
      final DocxTable table = _table(doc);
      expect(() => table.removeRowAt(0), throwsRangeError);
      table.insertRowAt(0, DocxTableRow());
      expect(_names(_all(_saved(doc), 'tbl').single), <String>[
        'tblGrid',
        'tr',
      ]);
    });

    test('a row in a table cannot go in another', () {
      final DocxTable one = DocxTable(columns: 1);
      final DocxTable two = DocxTable(columns: 1);
      final DocxTableRow row = one.rows.single;
      expect(() => two.insertRowAt(0, row), throwsStateError);
      expect(() => one.insertRowAt(0, row), throwsStateError);
      expect(two.rows, hasLength(1));
      expect(one.rows, hasLength(1));
    });

    test('a row read in a document cannot go in another table', () {
      final DocxTableRow row = _table(_twoRows()).rows.first;
      expect(() => DocxTable(columns: 1).insertRowAt(0, row), throwsStateError);
    });

    test('a row of fewer cells than the grid goes in', () {
      final DocxTable table = DocxTable(columns: 2);
      table.insertRowAt(1, DocxTableRow());
      expect(table.rows.last.cells, hasLength(1));
    });

    test('a row in a table reports to its document until it is out', () {
      final DocxDocument doc = _twoRows();
      final DocxEdits edits = editsOf(doc);
      final DocxTable table = _table(doc);
      final DocxTableRow row = DocxTableRow();
      final DocxTableCell cell = row.cells.single;
      table.insertRowAt(2, row);
      expect(
        edits.transaction(() => row.isHeader = true).changes,
        hasLength(1),
      );
      expect(
        edits.transaction(() => cell.addParagraph('x')).changes,
        hasLength(1),
      );
      table.removeRowAt(2);
      expect(edits.transaction(() => row.isHeader = false).isEmpty, isTrue);
      expect(edits.transaction(() => cell.addParagraph('y')).isEmpty, isTrue);
    });
  });

  group('cells', () {
    /// A document of one row of the cells `A` and `B`.
    DocxDocument twoCells() =>
        _open('<w:tbl><w:tr>${_tc('A')}${_tc('B')}</w:tr></w:tbl>');

    test('an inserted cell is at its index, and undoes and redoes', () {
      final DocxDocument doc = twoCells();
      final DocxTable table = _table(doc);
      final DocxTableRow row = table.rows.single;
      final ChangeSet set = editsOf(
        doc,
      ).transaction(() => row.insertCellAt(1, DocxTableCell('N')));
      expect(set.changes, hasLength(1));
      expect(_rows(table), <String>['A|N|B']);
      editsOf(doc).log.revertSet(set);
      expect(_rows(table), <String>['A|B']);
      editsOf(doc).log.reapplySet(set);
      expect(_rows(table), <String>['A|N|B']);
    });

    test('a removed cell undoes, and can go in again', () {
      final DocxDocument doc = twoCells();
      final DocxTable table = _table(doc);
      final DocxTableRow row = table.rows.single;
      final DocxTableCell first = row.cells.first;
      final ChangeSet set = editsOf(doc).transaction(() => row.removeCellAt(0));
      expect(_rows(table), <String>['B']);
      editsOf(doc).log.revertSet(set);
      expect(_rows(table), <String>['A|B']);
      editsOf(doc).log.reapplySet(set);
      row.insertCellAt(1, first);
      expect(_rows(table), <String>['B|A']);
    });

    test('an index out of range throws RangeError', () {
      final DocxTableRow row = _table(twoCells()).rows.single;
      expect(() => row.insertCellAt(-1, DocxTableCell()), throwsRangeError);
      expect(() => row.insertCellAt(3, DocxTableCell()), throwsRangeError);
      expect(() => row.removeCellAt(2), throwsRangeError);
    });

    test('removing the last cell throws StateError and changes nothing', () {
      final DocxDocument doc = _open('<w:tbl>${_tr('A')}</w:tbl>');
      final DocxTableRow row = _table(doc).rows.single;
      expect(() => row.removeCellAt(0), throwsStateError);
      expect(row.cells, hasLength(1));
      expect(editsOf(doc).log.hasChanges, isFalse);
    });

    test('a cell in a row cannot go in another', () {
      final DocxTableRow one = DocxTableRow();
      final DocxTableRow two = DocxTableRow();
      expect(() => two.insertCellAt(0, one.cells.single), throwsStateError);
      expect(two.cells, hasLength(1));
    });

    test('a cell in a row reports to its document until it is out', () {
      final DocxDocument doc = twoCells();
      final DocxEdits edits = editsOf(doc);
      final DocxTableRow row = _table(doc).rows.single;
      final DocxTableCell cell = DocxTableCell();
      row.insertCellAt(2, cell);
      expect(
        edits.transaction(() => cell.addParagraph('x')).changes,
        hasLength(1),
      );
      row.removeCellAt(2);
      expect(edits.transaction(() => cell.addParagraph('y')).isEmpty, isTrue);
    });
  });

  group('the blocks of a cell', () {
    test('outside a document they change and record nothing', () {
      final DocxTableCell cell = DocxTableCell('a');
      final DocxParagraph added = cell.addParagraph('b');
      final DocxParagraph inserted = DocxParagraph.text('c');
      cell.insertBlock(1, inserted);
      expect(cell.text, 'a\nc\nb');
      expect(blockContainerOf(added), same(cell));
      expect(editSinkOf(added), same(DocxEditSink.none));
      final DocxParagraph replacing = DocxParagraph.text('d');
      cell.replaceBlockAt(0, replacing);
      expect(cell.text, 'd\nc\nb');
      cell.removeBlockAt(1);
      expect(cell.text, 'd\nb');
      expect(blockContainerOf(inserted), isNull);
    });

    test('in a document each edit is one change that undoes', () {
      final DocxDocument doc = _open('<w:tbl>${_tr('A')}</w:tbl>');
      final DocxEdits edits = editsOf(doc);
      final DocxTableCell cell = _cell(_table(doc));
      final DocxParagraph added = DocxParagraph.text('b');

      final ChangeSet insert = edits.transaction(
        () => cell.insertBlock(1, added),
      );
      expect(insert.changes, hasLength(1));
      expect(editSinkOf(added), same(edits));
      final ChangeSet replace = edits.transaction(
        () => cell.replaceBlockAt(0, DocxParagraph.text('c')),
      );
      expect(replace.changes, hasLength(1));
      final ChangeSet remove = edits.transaction(() => cell.removeBlockAt(1));
      expect(remove.changes, hasLength(1));
      expect(cell.text, 'c');
      expect(editSinkOf(added), same(DocxEditSink.none));

      edits.log
        ..revertSet(remove)
        ..revertSet(replace);
      expect(cell.text, 'A\nb');
      expect(editSinkOf(added), same(edits));
      edits.log.revertSet(insert);
      expect(cell.text, 'A');
      expect(blockContainerOf(added), isNull);
    });

    test('addParagraph is one change', () {
      final DocxDocument doc = _open('<w:tbl>${_tr('A')}</w:tbl>');
      final DocxTableCell cell = _cell(_table(doc));
      final ChangeSet set = editsOf(
        doc,
      ).transaction(() => cell.addParagraph('b'));
      expect(set.changes, hasLength(1));
      expect(cell.text, 'A\nb');
    });

    test('a bad index or a block in a container changes nothing', () {
      final DocxTableCell cell = DocxTableCell('a');
      final DocxParagraph other =
          DocxTableCell('b').blocks.single as DocxParagraph;
      expect(() => cell.insertBlock(2, DocxParagraph()), throwsRangeError);
      expect(() => cell.removeBlockAt(1), throwsRangeError);
      expect(() => cell.replaceBlockAt(1, DocxParagraph()), throwsRangeError);
      expect(() => cell.insertBlock(0, other), throwsStateError);
      expect(() => cell.replaceBlockAt(0, other), throwsStateError);
      expect(cell.text, 'a');
    });

    test('a style set on a paragraph resolves as it goes in a cell', () {
      final DocxDocument doc = _open('<w:tbl>${_tr('A')}</w:tbl>');
      final DocxParagraph p = DocxParagraph.text('x')..style = 'Heading1';
      _cell(_table(doc)).insertBlock(0, p);
      expect(doc.styles.byId(p.style!), isNotNull);
    });
  });

  group('a failed edit rolls back', () {
    /// Runs [edit] on a table of the rows `A` and `B` of one cell each, with
    /// a hook that fails it after it was recorded, and checks that the table
    /// is as it was.
    void rollsBack(void Function(DocxTable table) edit) {
      final DocxDocument doc = _twoRows();
      final DocxEdits edits = editsOf(doc);
      final DocxTable table = _table(doc);
      final List<DocxTableRow> rows = List<DocxTableRow>.of(table.rows);
      final List<DocxBlock> blocks = List<DocxBlock>.of(
        rows.first.cells.single.blocks,
      );
      final List<Object> tableChildren = List<Object>.of(
        tableChildrenOf(table),
      );
      final List<Object> rowChildren = List<Object>.of(
        rowChildrenOf(rows.first),
      );
      edits.afterRecord = () => throw StateError('hook');
      expect(
        () => edit(table),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            'hook',
          ),
        ),
      );
      edits.afterRecord = null;
      expect(table.rows, orderedEquals(rows));
      expect(_rows(table), <String>['A', 'B']);
      expect(rows.first.cells.single.blocks, orderedEquals(blocks));
      expect(tableChildrenOf(table), orderedEquals(tableChildren));
      expect(rowChildrenOf(rows.first), orderedEquals(rowChildren));
      expect(edits.log.hasChanges, isFalse);
    }

    test('inserting a row', () {
      final DocxTableRow row = DocxTableRow();
      rollsBack((DocxTable t) => t.insertRowAt(1, row));
      DocxTable(columns: 1).insertRowAt(0, row);
    });

    test('removing a row', () {
      rollsBack((DocxTable t) => t.removeRowAt(0));
    });

    test('inserting a cell', () {
      final DocxTableCell cell = DocxTableCell();
      rollsBack((DocxTable t) => t.rows.first.insertCellAt(0, cell));
      DocxTableRow().insertCellAt(0, cell);
    });

    test('removing a cell', () {
      final DocxDocument doc = _open(
        '<w:tbl><w:tr>${_tc('A')}${_tc('B')}</w:tr></w:tbl>',
      );
      final DocxTable table = _table(doc);
      final List<Object> children = List<Object>.of(
        rowChildrenOf(table.rows.single),
      );
      editsOf(doc).afterRecord = () => throw StateError('hook');
      expect(() => table.rows.single.removeCellAt(0), throwsStateError);
      expect(_rows(table), <String>['A|B']);
      expect(rowChildrenOf(table.rows.single), orderedEquals(children));
      expect(editsOf(doc).log.hasChanges, isFalse);
    });

    test('inserting a block', () {
      final DocxParagraph p = DocxParagraph();
      rollsBack((DocxTable t) => t.rows.first.cells.single.insertBlock(0, p));
      expect(blockContainerOf(p), isNull);
      expect(editSinkOf(p), same(DocxEditSink.none));
    });

    test('removing a block', () {
      rollsBack((DocxTable t) => t.rows.first.cells.single.removeBlockAt(0));
    });

    test('replacing a block', () {
      final DocxParagraph p = DocxParagraph();
      rollsBack(
        (DocxTable t) => t.rows.first.cells.single.replaceBlockAt(0, p),
      );
      expect(blockContainerOf(p), isNull);
    });
  });

  group('a table cannot go inside itself', () {
    test('in a cell of the table', () {
      final DocxTable table = DocxTable(columns: 1);
      final DocxTableCell cell = _cell(table);
      expect(() => cell.insertBlock(0, table), throwsArgumentError);
      expect(() => cell.replaceBlockAt(0, table), throwsArgumentError);
      expect(cell.blocks.single, isA<DocxParagraph>());
      expect(blockContainerOf(table), isNull);
    });

    test('in a cell of a nested table', () {
      final DocxTable table = _chain(3);
      final DocxTableCell cell = _bottom(table);
      expect(() => cell.insertBlock(0, table), throwsArgumentError);
      expect(cell.blocks.single, isA<DocxParagraph>());
    });

    test('nor a row in a table it holds, nor a cell', () {
      final DocxTableRow row = DocxTableRow();
      final DocxTable inner = DocxTable(columns: 1);
      row.cells.single.insertBlock(0, inner);
      expect(() => inner.insertRowAt(0, row), throwsArgumentError);
      expect(inner.rows, hasLength(1));

      final DocxTableCell cell = DocxTableCell();
      final DocxTable holder = DocxTable(columns: 1);
      cell.insertBlock(0, holder);
      expect(
        () => holder.rows.single.insertCellAt(0, cell),
        throwsArgumentError,
      );
      expect(holder.rows.single.cells, hasLength(1));
    });
  });

  group('the nesting of tables', () {
    test('reaches the limit of the API and goes no further', () {
      final DocxTable top = _chain(maxBuiltTableNesting);
      final DocxTableCell bottom = _bottom(top);
      expect(
        () => bottom.insertBlock(0, DocxTable(columns: 1)),
        throwsArgumentError,
      );
      expect(bottom.blocks.single, isA<DocxParagraph>());
      expect(
        () => bottom.replaceBlockAt(0, DocxTable(columns: 1)),
        throwsArgumentError,
      );
    });

    test('counts what goes in, and where it goes', () {
      final DocxTableCell bottom = _bottom(_chain(40));
      expect(() => bottom.insertBlock(0, _chain(41)), throwsArgumentError);
      bottom.insertBlock(0, _chain(40));
    });

    test('counts a row and a cell that go in', () {
      final DocxTable last = _deepest(_chain(maxBuiltTableNesting));

      final DocxTableRow row = DocxTableRow();
      row.cells.single.insertBlock(0, DocxTable(columns: 1));
      expect(() => last.insertRowAt(0, row), throwsArgumentError);
      expect(last.rows, hasLength(1));

      final DocxTableCell cell = DocxTableCell();
      cell.insertBlock(0, DocxTable(columns: 1));
      expect(() => last.rows.single.insertCellAt(0, cell), throwsArgumentError);
      expect(last.rows.single.cells, hasLength(1));
    });

    test('at its deepest, what saves opens under the default limits', () {
      final DocxDocument doc = _open(_p('a'));
      doc.body.insertBlock(1, _chain(maxBuiltTableNesting));
      final DocxDocument again = DocxDocument.open(doc.save().bytes);
      DocxTable at = again.body.blocks[1] as DocxTable;
      int levels = 1;
      while (_cell(at).blocks.first is DocxTable) {
        at = _cell(at).blocks.first as DocxTable;
        levels++;
      }
      expect(levels, maxBuiltTableNesting);
    });

    group('in a file nested past the limit of the API', () {
      const int levels = maxBuiltTableNesting + 2;

      /// The innermost table of a file of [levels] nested tables.
      DocxTable innermost() => _deepest(
        _table(
          _open(
            '${'<w:tbl><w:tr><w:tc>' * levels}${_p('x')}'
            '${'</w:tc></w:tr></w:tbl>' * levels}',
          ),
        ),
      );

      test('a plain row goes in, as it deepens nothing', () {
        final DocxTable table = innermost();
        table.insertRowAt(1, DocxTableRow());
        expect(table.rows, hasLength(2));
      });

      test('a plain cell goes in, as it deepens nothing', () {
        final DocxTableRow row = innermost().rows.single;
        row.insertCellAt(1, DocxTableCell('y'));
        expect(row.cells, hasLength(2));
      });

      test('a table read that deep cannot go back in the API', () {
        final DocxDocument doc = _open(
          '${'<w:tbl><w:tr><w:tc>' * levels}${_p('x')}'
          '${'</w:tc></w:tr></w:tbl>' * levels}',
        );
        final DocxBlock table = doc.body.blocks.single;
        final ChangeSet removal = editsOf(
          doc,
        ).transaction(() => doc.body.removeBlockAt(0));
        expect(() => doc.body.insertBlock(0, table), throwsArgumentError);
        editsOf(doc).log.revertSet(removal);
        expect(doc.body.blocks.single, same(table));
      });

      test('a nested table throws, and changes nothing', () {
        final DocxTable table = innermost();
        final DocxTableCell cell = _cell(table);
        expect(
          () => cell.insertBlock(0, DocxTable(columns: 1)),
          throwsArgumentError,
        );
        expect(cell.blocks, hasLength(1));

        final DocxTableRow row = DocxTableRow();
        row.cells.single.insertBlock(0, DocxTable(columns: 1));
        expect(() => table.insertRowAt(1, row), throwsArgumentError);
        expect(table.rows, hasLength(1));
      });
    });
  });

  group('every saved cell ends in a paragraph', () {
    /// Whether every `w:tc` of [doc] as saved has a `w:p` last.
    void expectClosed(DocxDocument doc) {
      final List<XmlElement> cells = _all(_saved(doc), 'tc');
      expect(cells, isNotEmpty);
      for (final XmlElement tc in cells) {
        expect(tc.childElements.last.localName, 'p');
      }
    }

    test('a table last in a cell', () {
      final DocxDocument doc = _open('<w:tbl>${_tr('A')}</w:tbl>');
      final DocxTableCell cell = _cell(_table(doc));
      cell.insertBlock(1, DocxTable(columns: 1));
      expectClosed(doc);
      expect(cell.blocks, hasLength(2));
    });

    test('a table last in the body', () {
      final DocxDocument doc = _open(_p('a'));
      doc.body.insertBlock(1, DocxTable(columns: 2, rows: 2));
      expectClosed(doc);
      expect(doc.body.blocks.last, isA<DocxTable>());
    });

    test('a cell whose only block was removed', () {
      final DocxDocument doc = _open('<w:tbl>${_tr('A')}</w:tbl>');
      final DocxTableCell cell = _cell(_table(doc));
      cell.removeBlockAt(0);
      expect(cell.blocks, isEmpty);
      expectClosed(doc);
    });

    test('a new cell whose only block was removed', () {
      final DocxDocument doc = _open(_p('a'));
      final DocxTable table = DocxTable(columns: 1);
      _cell(table).removeBlockAt(0);
      doc.body.insertBlock(1, table);
      expectClosed(doc);
    });

    test('a cell whose paragraph was replaced by a table, in a table', () {
      final DocxDocument doc = _open('<w:tbl>${_tr('A')}</w:tbl>');
      final DocxTable inner = DocxTable(columns: 1);
      _cell(inner).replaceBlockAt(0, DocxTable(columns: 1));
      _cell(_table(doc)).replaceBlockAt(0, inner);
      expectClosed(doc);
    });
  });

  group('what the model does not show stays where it was', () {
    const String bookmark = '<w:bookmarkStart w:id="1" w:name="b"/>';
    const String bookmarkEnd = '<w:bookmarkEnd w:id="1"/>';
    final String sdt =
        '<w:sdt><w:sdtContent>${_tr('hidden')}</w:sdtContent></w:sdt>';

    /// A table of the rows `A` and `B`, with a bookmark and a content control
    /// between them and the end of the bookmark after them.
    DocxDocument keptBetweenRows() => _open(
      '<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w="100"/></w:tblGrid>'
      '${_tr('A')}$bookmark$sdt${_tr('B')}$bookmarkEnd</w:tbl>',
    );

    /// The children of the top table of [doc] as saved.
    List<String> tblNames(DocxDocument doc) =>
        _names(_all(_saved(doc), 'tbl').first);

    test('an inserted row goes directly before the row at its index', () {
      final DocxDocument doc = keptBetweenRows();
      _table(doc).insertRowAt(1, _row('N'));
      expect(tblNames(doc), <String>[
        'tblPr',
        'tblGrid',
        'tr',
        'bookmarkStart',
        'sdt',
        'tr',
        'tr',
        'bookmarkEnd',
      ]);
      expect(_rows(_table(doc)), <String>['A', 'N', 'B']);
      final List<XmlElement> tr = _all(_saved(doc), 'tbl').first.childElements
          .where((XmlElement e) => e.localName == 'tr')
          .toList();
      expect(tr.map((XmlElement e) => e.innerText), <String>['A', 'N', 'B']);
    });

    test('a row inserted first goes before the first row', () {
      final DocxDocument doc = keptBetweenRows();
      _table(doc).insertRowAt(0, DocxTableRow());
      expect(tblNames(doc).sublist(0, 4), <String>[
        'tblPr',
        'tblGrid',
        'tr',
        'tr',
      ]);
    });

    test('a row inserted last goes after the last child', () {
      final DocxDocument doc = keptBetweenRows();
      _table(doc).insertRowAt(2, DocxTableRow());
      expect(tblNames(doc).sublist(5), <String>['tr', 'bookmarkEnd', 'tr']);
    });

    test('a removed row leaves them, and the undo puts it back', () {
      final DocxDocument doc = keptBetweenRows();
      final DocxTable table = _table(doc);
      final ChangeSet remove = editsOf(
        doc,
      ).transaction(() => table.removeRowAt(0));
      expect(tblNames(doc), <String>[
        'tblPr',
        'tblGrid',
        'bookmarkStart',
        'sdt',
        'tr',
        'bookmarkEnd',
      ]);
      editsOf(doc).log.revertSet(remove);
      expect(tblNames(doc), <String>[
        'tblPr',
        'tblGrid',
        'tr',
        'bookmarkStart',
        'sdt',
        'tr',
        'bookmarkEnd',
      ]);
      expect(_rows(table), <String>['A', 'B']);
    });

    test('an undone insert leaves the file as it read', () {
      final DocxDocument doc = keptBetweenRows();
      final DocxTable table = _table(doc);
      final List<String> before = tblNames(doc);
      final ChangeSet insert = editsOf(
        doc,
      ).transaction(() => table.insertRowAt(1, DocxTableRow()));
      editsOf(doc).log.revertSet(insert);
      expect(tblNames(doc), before);
      editsOf(doc).log.reapplySet(insert);
      expect(tblNames(doc), hasLength(before.length + 1));
    });

    test('between cells it is the same', () {
      final DocxDocument doc = _open(
        '<w:tbl><w:tr><w:trPr><w:cantSplit/></w:trPr>${_tc('A')}$bookmark'
        '${_tc('B')}$bookmarkEnd</w:tr></w:tbl>',
      );
      final DocxTableRow row = _table(doc).rows.single;
      List<String> trNames() => _names(_all(_saved(doc), 'tr').single);

      row.insertCellAt(1, DocxTableCell('N'));
      expect(trNames(), <String>[
        'trPr',
        'tc',
        'bookmarkStart',
        'tc',
        'tc',
        'bookmarkEnd',
      ]);
      expect(_rows(_table(doc)), <String>['A|N|B']);
      row.removeCellAt(0);
      expect(trNames(), <String>[
        'trPr',
        'bookmarkStart',
        'tc',
        'tc',
        'bookmarkEnd',
      ]);
      row.insertCellAt(2, DocxTableCell('E'));
      expect(trNames().last, 'tc');
      expect(_rows(_table(doc)), <String>['N|B|E']);
    });

    test('the rows in a content control are not counted', () {
      final DocxTable table = _table(keptBetweenRows());
      expect(table.rows, hasLength(2));
      expect(() => table.removeRowAt(2), throwsRangeError);
    });
  });

  group('a prebuilt nested table', () {
    test('records an edit only while it is in the document', () {
      final DocxDocument doc = _open(_p('a'));
      final DocxEdits edits = editsOf(doc);
      final DocxTable outer = DocxTable(columns: 1);
      final DocxTable inner = DocxTable(columns: 1);
      _cell(outer).insertBlock(0, inner);
      final DocxParagraph deep = _cell(inner).blocks.single as DocxParagraph;

      /// The changes an edit of the deep paragraph records, undone again.
      int recorded() {
        final ChangeSet set = edits.transaction(() => deep.addRun('x'));
        edits.log.revertSet(set);
        return set.changes.length;
      }

      expect(recorded(), 0);
      final ChangeSet insert = edits.transaction(
        () => doc.body.insertBlock(1, outer),
      );
      expect(recorded(), 1);
      edits.log.revertSet(insert);
      expect(blockContainerOf(outer), isNull);
      expect(recorded(), 0);
      edits.log.reapplySet(insert);
      expect(blockContainerOf(outer), isNotNull);
      expect(recorded(), 1);
      final ChangeSet remove = edits.transaction(
        () => doc.body.removeBlockAt(1),
      );
      expect(recorded(), 0);
      edits.log.revertSet(remove);
      expect(recorded(), 1);
    });

    test('a row and a cell of it follow too', () {
      final DocxDocument doc = _open(_p('a'));
      final DocxEdits edits = editsOf(doc);
      final DocxTable outer = DocxTable(columns: 1);
      final DocxTable inner = DocxTable(columns: 1);
      _cell(outer).insertBlock(0, inner);
      doc.body.insertBlock(1, outer);
      expect(
        edits.transaction(() => inner.insertRowAt(1, DocxTableRow())).changes,
        hasLength(1),
      );
      expect(
        edits
            .transaction(
              () => inner.rows.first.insertCellAt(0, DocxTableCell()),
            )
            .changes,
        hasLength(1),
      );
      doc.body.removeBlockAt(1);
      expect(
        edits.transaction(() => inner.insertRowAt(1, DocxTableRow())).isEmpty,
        isTrue,
      );
    });

    test('a table moved between cells keeps reporting', () {
      final DocxDocument doc = _open('<w:tbl>${_tr('A')}${_tr('B')}</w:tbl>');
      final DocxEdits edits = editsOf(doc);
      final DocxTable table = _table(doc);
      final DocxTable inner = DocxTable(columns: 1);
      table.rows.first.cells.single.insertBlock(0, inner);
      table.rows.first.cells.single.removeBlockAt(0);
      table.rows.last.cells.single.insertBlock(0, inner);
      expect(blockContainerOf(inner), same(table.rows.last.cells.single));
      expect(
        edits.transaction(() => _cell(inner).addParagraph('x')).changes,
        hasLength(1),
      );
    });
  });

  group('200,000 kept children', () {
    const int count = 200000;
    final String kept = '<x:a/>' * count;
    const DocxReadLimits limits = DocxReadLimits(maxCompressionRatio: 1000000);

    test('a row with 200,000 kept children inserts in time', () {
      final DocxDocument doc = _open(
        '<w:tbl><w:tr>$kept${_tc('A')}</w:tr></w:tbl>',
        limits: limits,
      );
      final DocxTableRow row = _table(doc).rows.single;
      for (int i = 0; i < 100; i++) {
        row.insertCellAt(0, DocxTableCell());
        row.insertCellAt(row.cells.length, DocxTableCell());
      }
      expect(row.cells, hasLength(201));
      final String xml = readDocxText(doc.save().bytes)['word/document.xml']!;
      expect('<x:a/>'.allMatches(xml), hasLength(count));
      expect(xml.indexOf('<x:a/>'), lessThan(xml.indexOf('<w:tc>')));
    });

    test('a table with as many inserts in time', () {
      final DocxDocument doc = _open(
        '<w:tbl>$kept${_tr('A')}</w:tbl>',
        limits: limits,
      );
      final DocxTable table = _table(doc);
      for (int i = 0; i < 100; i++) {
        table.insertRowAt(0, DocxTableRow());
      }
      expect(table.rows, hasLength(101));
    });
  });
}
