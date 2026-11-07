/// The blocks of a body or a table cell: paragraphs, tables, and opaque blocks
/// for everything else.
///
/// Not ported from Quds; written for jet_office.
///
/// A [DocxParagraph] holds its inlines and its properties (`w:pPr`, a
/// [DocxParagraphProperties]). A [DocxTable] holds [DocxTableRow]s, a row
/// [DocxTableCell]s and a cell blocks again, so a table nests in a cell. A
/// [DocxOpaqueBlock] keeps an element the model does not type, such as a
/// content control, as written.
///
/// `w:tbl` and `w:tr` may hold other children between rows and cells (`w:sdt`,
/// `w:customXml`, bookmarks, `w:tblPrEx`). A table and a row keep them in a
/// private list in file order, with the rows or cells and the properties, and
/// show only the typed rows and cells: rows inside a `w:sdt` are not in
/// [DocxTable.rows]. An index of a row or a cell counts the typed ones: a
/// row or a cell inserted goes directly before the one at its index, or last
/// of all the children, and one removed leaves the others where they were.
/// [visitBlocks] is the walk of the tree.
///
/// A table, a row and a cell are edited the same in a document and in none:
/// the edits go through the [DocxEditSink] they report to, which records them
/// in a document and only applies them outside one.
///
/// The top-level functions are the model's internal surface for the reader,
/// the writer and the document; none of them is exported.
library;

import 'dart:collection';

import '../../opc/change_log.dart';
import '../../opc/ooxml.dart' show Ns;
import '../../opc/opaque_xml.dart';
import '../builtin_styles.dart' show DocxBuiltInStyle;
import '../properties.dart';
import '../units.dart';
import 'edit_sink.dart';
import 'inlines.dart';
import 'paragraph_properties.dart';
import 'primitives.dart' as primitives;
import 'property_set.dart';
import 'run_content.dart';
import 'styles.dart' show DocxStyleType;
import 'table_formatting.dart';
import 'table_properties.dart';

/// How deep tables may nest in a part that is read: a table in a cell of a
/// table is at nesting 2.
///
/// `DocxReadLimits.maxDepth` bounds it by itself at its default, some 84
/// tables deep. The reader, the writer and the walks of the tree recurse once
/// per table, so a raised `maxDepth` must not raise this: past it the read
/// fails the same way on every platform, and not with a stack overflow that
/// depends on the platform's stack. What the API may build is less:
/// [maxBuiltTableNesting].
const int maxTableNesting = 256;

/// How deep the API may nest tables, counted as [maxTableNesting] is.
///
/// A table takes three XML levels, so the default `DocxReadLimits.maxDepth`
/// stops near 84 tables: 80 leaves room for what the innermost cell holds, and
/// what the API builds opens again under the default limits. A file may nest
/// deeper, up to [maxTableNesting]; it reads and saves, and a row or a cell
/// holding no table still goes in there, as it deepens nothing.
const int maxBuiltTableNesting = 80;

/// The width of the text of a blank A4 page, in twips: what the columns of a
/// new table share.
const int _pageTextWidthTwips = 9062;

/// One child of a body or of a table cell.
///
/// A block is in at most one container at a time: inserting one that is
/// already in a body or a cell throws [StateError]; remove it there first.
sealed class DocxBlock {
  DocxBlock._();

  /// The container the block is in, such as a document's body, or `null`
  /// while it is in none.
  Object? _container;
}

/// A paragraph, `w:p`.
final class DocxParagraph extends DocxBlock {
  /// An empty paragraph: no inlines, no style and no other properties.
  ///
  /// It belongs to no document until it is inserted into one.
  DocxParagraph()
    : _source = const PropertyContainer.empty(),
      _attributes = const <KeptAttribute>[],
      super._();

  /// A paragraph with one run that holds [text], or none when [text] is
  /// empty. The text is split and scrubbed as [DocxRun.text] is when set.
  DocxParagraph.text(String text)
    : _source = const PropertyContainer.empty(),
      _attributes = const <KeptAttribute>[],
      super._() {
    if (text.isNotEmpty) {
      addRun(text);
    }
  }

  DocxParagraph._read(this._source, this._attributes) : super._();

  /// The paragraph's `w:pPr` as read.
  final PropertyContainer _source;

  /// The paragraph's properties: [_source] with the values set.
  late final DocxParagraphProperties _properties = newParagraphProperties(
    _source,
    () => _sink,
  );

  /// The attributes of `w:p` the reader kept, such as `w14:paraId`.
  final List<KeptAttribute> _attributes;

  final List<DocxInline> _inlines = <DocxInline>[];

  late final List<DocxInline> _inlinesView = UnmodifiableListView<DocxInline>(
    _inlines,
  );

  DocxEditSink _sink = DocxEditSink.none;

  /// The sink of the document the paragraph was read in; `null` for a new
  /// paragraph.
  DocxEditSink? _readIn;

  /// The formatting of the paragraph: its `w:pPr`.
  ///
  /// It is the same object every time.
  DocxParagraphProperties get properties => _properties;

  /// The id of the paragraph's style (`w:pStyle`), or `null` for none; a
  /// shortcut for [DocxParagraphProperties.style].
  ///
  /// A `w:pStyle` read from a file that the model does not type (no
  /// `w:val`, an empty one, another `w:` attribute, child elements) reads
  /// `null` and is written back as read until a style is set.
  ///
  /// Setting the empty string, or an id holding a character XML forbids,
  /// throws [ArgumentError]; set `null` to remove the style. The id set may
  /// read back as the document's own id for that style, and a set on a
  /// paragraph of a document throws a `DocxReadException` when its styles
  /// part cannot be read ([DocxParagraphProperties.style] has the rules).
  String? get style => _properties.style;

  set style(String? value) => _properties.style = value;

  /// The paragraph's inlines, in order. The list cannot be modified; use
  /// [addRun], [insertInline] and [removeInlineAt].
  List<DocxInline> get inlines => _inlinesView;

  /// The paragraph's visible text: the [DocxInline.text] of each inline, in
  /// order. A run gives its text and an opaque inline the visible text
  /// inside it, so inserted text counts and deleted text does not.
  String get text {
    final StringBuffer out = StringBuffer();
    for (final DocxInline inline in _inlines) {
      out.write(inline.text);
    }
    return out.toString();
  }

  /// Appends a new run that holds [text] and returns it. The text is split
  /// and scrubbed as [DocxRun.text] is when set.
  DocxRun addRun([String text = '']) {
    final DocxRun run = DocxRun(text);
    insertInline(_inlines.length, run);
    return run;
  }

  /// Inserts [inline] at [index], from 0 to the number of inlines.
  ///
  /// An [index] out of that range throws [RangeError]. An [inline] that is
  /// already in a paragraph, this one or another, throws [StateError]:
  /// remove it there first. In a paragraph of a document, the style set on
  /// a run is resolved against the document's styles (`DocxRun.style` has
  /// the rules), in the same edit; a styles part that cannot be read throws
  /// a `DocxReadException` naming it, and nothing changes. The `w:rStyle` of
  /// a run read in another document counts as set; `DocxBody.insertBlock`
  /// says what such a move does and does not do.
  void insertInline(int index, DocxInline inline) {
    RangeError.checkValueInInterval(index, 0, _inlines.length, 'index');
    _checkDetached(inline);
    _sink.atomically(() {
      _inlines.insert(index, inline);
      setParagraphOf(inline, this);
      _sink.inlineInserted(this, index, inline);
      if (inline is DocxRun) {
        _resolveRunStyle(inline, _sink);
      }
    });
  }

  /// Removes the inline at [index].
  ///
  /// An [index] that is not one of an inline throws [RangeError].
  void removeInlineAt(int index) {
    RangeError.checkValidIndex(index, _inlines, 'index');
    final DocxInline removed = _inlines.removeAt(index);
    setParagraphOf(removed, null);
    _sink.inlineRemoved(this, index, removed);
  }

  static void _checkDetached(DocxInline inline) {
    if (paragraphOf(inline) != null) {
      throw StateError('The inline is already in a paragraph.');
    }
  }
}

/// A table, `w:tbl`: its grid and its rows.
///
/// A table read from a file is written as read: the children it does not show
/// stay where they were, and a grid that does not fit its rows is kept. Only
/// the API checks the fit: [mergeCells], [insertRowAt],
/// [DocxTableRow.insertCellAt], [DocxTableCellProperties.gridSpan] and
/// [DocxTableCellProperties.verticalMerge].
///
/// The API nests tables at most 80 deep, so what it builds opens again under
/// the default read limits: an edit that puts tables past that throws
/// [ArgumentError]. A file may nest deeper, and is kept.
final class DocxTable extends DocxBlock {
  /// A table of [rows] rows of [columns] empty cells.
  ///
  /// The columns share the text width of a blank A4 page, 9062 twips, rounded
  /// down to whole twips: in the grid and in the width of each cell. The table
  /// has no style. It belongs to no document until it is inserted into one.
  ///
  /// A [columns] outside 1 to [maxTableColumns], or [rows] below 1, throws
  /// [RangeError].
  DocxTable({required int columns, int rows = 1})
    : this._read(
        const PropertyContainer.empty(),
        const <KeptAttribute>[],
        _equalGrid(columns),
        _emptyRows(columns, rows),
        isNew: true,
      );

  DocxTable._read(
    this._source,
    this._attributes,
    this._gridColumnsPt,
    this._children, {
    bool isNew = false,
  }) : _rows = _ofType<DocxTableRow>(_children),
       _gridRead = _gridColumnsPt,
       _isNew = isNew,
       super._() {
    for (final DocxTableRow row in _rows) {
      row._table = this;
    }
  }

  /// The grid of a new table of [columns] columns, each of an equal share of
  /// [widthTwips].
  static List<double?> _equalGrid(
    int columns, [
    int widthTwips = _pageTextWidthTwips,
  ]) {
    RangeError.checkValueInInterval(columns, 1, maxTableColumns, 'columns');
    return List<double?>.unmodifiable(
      List<double>.filled(columns, ptOfTwips(widthTwips ~/ columns)),
    );
  }

  /// The grid of a new table of [columns] columns, of the widths [widthsPt], or
  /// sharing [widthTwips] for `null`.
  static List<double?> _newGrid(
    int columns,
    List<double>? widthsPt,
    int widthTwips,
  ) {
    final List<double?> grid = _equalGrid(columns, widthTwips);
    if (widthsPt == null) return grid;
    if (widthsPt.length != columns) {
      throw ArgumentError.value(
        widthsPt,
        'columnWidthsPt',
        'must have one width for each of the $columns columns',
      );
    }
    return _checkedWidths(widthsPt, 'columnWidthsPt');
  }

  /// [widths] as the grid stores them, rounded to twips; throws what
  /// [gridColumnsPt] says of an entry, naming [name].
  static List<double?> _checkedWidths(List<double?> widths, String name) {
    return List<double?>.unmodifiable(<double>[
      for (final double? width in widths)
        ptOfTwips(
          twipsOf(
            width ?? (throw ArgumentError.notNull('$name entry')),
            name,
            min: 0,
            max: maxTwips,
          ),
        ),
    ]);
  }

  /// [rows] rows of [columns] empty cells of the width of a column.
  static List<Object> _emptyRows(int columns, int rows) {
    if (rows < 1) {
      throw RangeError.value(rows, 'rows', 'must be at least 1');
    }
    final DocxTableWidth width = DocxTableWidth.points(
      ptOfTwips(_pageTextWidthTwips ~/ columns),
    );
    return <Object>[
      for (int i = 0; i < rows; i++)
        DocxTableRow(cells: columns)
          .._cells.forEach((DocxTableCell c) => c.properties.width = width),
    ];
  }

  /// The table's `w:tblPr` as read, by `tablePropertiesSchema`.
  final PropertyContainer _source;

  /// The table's properties: [_source] with the values set.
  late final DocxTableProperties _properties = newTableProperties(
    _source,
    () => _sink,
  );

  /// The attributes of `w:tbl` the reader kept, such as `w:rsidR`.
  final List<KeptAttribute> _attributes;

  /// The widths of the grid now; the list read until [gridColumnsPt] is set.
  List<double?>? _gridColumnsPt;

  /// The widths of the grid as read, to know whether the grid is written as
  /// read.
  final List<double?>? _gridRead;

  /// Whether the table was built here and not read from a file, so it writes
  /// the `w:tblPr` the schema requires even when it is empty.
  final bool _isNew;

  DocxEditSink _sink = DocxEditSink.none;

  /// The sink of the document the table was read in; `null` for a new table.
  DocxEditSink? _readIn;

  /// The children of `w:tbl` in file order: the [_source] when the file has
  /// a `w:tblPr`, each [DocxTableRow], and an [OpaqueXml] for any other,
  /// `w:tblGrid` among them.
  final List<Object> _children;

  /// The typed rows of [_children], in order.
  final List<DocxTableRow> _rows;

  late final List<DocxTableRow> _rowsView = UnmodifiableListView<DocxTableRow>(
    _rows,
  );

  /// The table's rows, in order. The list cannot be modified.
  ///
  /// Only the `w:tr` children of `w:tbl` are rows: one inside a content
  /// control or another kept element is not listed, and is written as read.
  List<DocxTableRow> get rows => _rowsView;

  /// The formatting of the table: its `w:tblPr`.
  ///
  /// It is the same object every time.
  DocxTableProperties get properties => _properties;

  /// The width of each column of the grid (`w:tblGrid`), in points, or `null`
  /// for a table without a grid. The list cannot be modified.
  ///
  /// An entry is `null` for a `w:gridCol` whose `w:w` is missing or is not a
  /// whole number of twips.
  ///
  /// Setting replaces the widths of the grid as one change: the grid's other
  /// children (`w:tblGridChange`) stay, and a table without a grid gets one
  /// before its rows. Each cell's `w:tcW` stays, and Word lays a table out
  /// from those. A width is stored in twips, from 0 to 1584 points, and reads
  /// back rounded; setting what this reads, or the widths the grid holds,
  /// changes nothing, whatever it reads.
  ///
  /// A list of another length than the grid's, once the table has rows,
  /// throws [ArgumentError] (the cells of a row would no longer fit the
  /// grid); so does one of fewer columns than the widest row of a table
  /// without a grid, an empty list, `null` or an entry that is `null` or not
  /// finite, and an entry out of range throws [RangeError]. Nothing changes
  /// then.
  List<double?>? get gridColumnsPt => _gridColumnsPt;

  set gridColumnsPt(List<double?>? value) {
    final List<double?>? current = _gridColumnsPt;
    if (value == null && current == null) return;
    if (value != null && current != null && _sameWidths(current, value)) {
      return;
    }
    if (value == null) {
      throw ArgumentError.notNull('gridColumnsPt');
    }
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'gridColumnsPt', 'must not be empty');
    }
    final List<double?> columns = _checkedWidths(value, 'gridColumnsPt');
    if (current != null &&
        _rows.isNotEmpty &&
        current.length != columns.length) {
      throw ArgumentError.value(
        value,
        'gridColumnsPt',
        'must have the ${current.length} columns of the grid',
      );
    }
    if (current == null) {
      for (final DocxTableRow row in _rows) {
        if (row._gridTotal > columns.length) {
          throw ArgumentError.value(
            value,
            'gridColumnsPt',
            'must have the ${row._gridTotal} columns of the widest row',
          );
        }
      }
    }
    if (current != null && _sameWidths(current, columns)) {
      return;
    }
    _sink.apply(_GridSet(this, current, columns));
  }

  /// Inserts [row] at [index], from 0 to the number of rows: directly before
  /// the row at [index], or after the last child of the table for the last
  /// index, so what the table does not show stays where it was.
  ///
  /// An [index] out of that range throws [RangeError]. A [row] already in a
  /// table, this one or another, throws [StateError]: remove it there first. A
  /// [row] that holds this table, or whose tables would nest past 80 deep,
  /// throws [ArgumentError], and so does one whose spans, with its
  /// `w:gridBefore` and `w:gridAfter`, are more than the columns of the grid
  /// (a table without a grid checks nothing), or with a cell that continues a
  /// vertical merge and no cell of the same columns in the row that will be
  /// above it. Nothing changes then.
  ///
  /// In a table of a document, the styles set on what the row holds are
  /// resolved as `DocxBody.insertBlock` says, and it may throw the same
  /// `DocxReadException`.
  ///
  /// A row with no such cell may go inside a vertical merge, and a row removed
  /// may leave a merge without its start: neither is checked.
  void insertRowAt(int index, DocxTableRow row) {
    RangeError.checkValueInInterval(index, 0, _rows.length, 'index');
    if (row._table == null) {
      _checkFits(row._gridTotal);
      final Map<int, int> above = _endsByStart(_placedAt(index - 1));
      for (final _PlacedCell at in row._placed()) {
        if (at.cell._continues) _checkContinues(above, at.start, at.end);
      }
    }
    primitives.insertChild(_sink, this, _children, _rows, index, row);
  }

  /// Removes the row at [index]. The row is then in no table and can be
  /// inserted again; what the table does not show stays where it was.
  ///
  /// An [index] that is not one of a row throws [RangeError]. The last row
  /// throws [StateError]: Word repairs a table without rows, so remove the
  /// table instead. Nothing changes then.
  void removeRowAt(int index) =>
      primitives.removeChild(_sink, this, _children, _rows, index);

  /// Appends a row of the width of the grid that holds [values], one per
  /// column, and returns it.
  ///
  /// `null` is an empty cell, and the columns past the last value have empty
  /// cells; a cell holds one paragraph, with the text split and scrubbed as
  /// [DocxRun.text] is when set. Numbers are text here: how they show is the
  /// caller's. A cell takes the width of its column (`w:tcW`), when the grid
  /// has one that a cell can hold.
  ///
  /// With [header] the row repeats at the top of each page and stays on one
  /// page: [DocxTableRowProperties.repeatAsHeader] and
  /// [DocxTableRowProperties.cantSplit] are set. Word repeats only an unbroken
  /// run of header rows from the first row of the table.
  ///
  /// More [values] than columns throw [ArgumentError], and so does a table
  /// without a grid, or with an empty one, which says no width. Nothing
  /// changes then; otherwise the add is one edit.
  DocxTableRow addRow(List<String?> values, {bool header = false}) {
    final int? columns = _columnCount;
    if (columns == null) {
      throw ArgumentError('A table without a grid has no width for a row.');
    }
    if (values.length > columns) {
      throw ArgumentError.value(
        values,
        'values',
        'must be at most the $columns columns of the grid',
      );
    }
    final DocxTableRow row = DocxTableRow._read(
      const PropertyContainer.empty(),
      const <KeptAttribute>[],
      <Object>[
        for (int i = 0; i < columns; i++)
          DocxTableCell(i < values.length ? values[i] ?? '' : '')
            ..properties.width = _widthOfColumns(i, i),
      ],
    );
    if (header) {
      row.properties
        ..repeatAsHeader = true
        ..cantSplit = true;
    }
    insertRowAt(_rows.length, row);
    return row;
  }

  /// Merges the cells of a range of the grid and returns the top-left one.
  ///
  /// [firstRow] and [lastRow] are indexes of [rows], [firstColumn] and
  /// [lastColumn] columns of the grid, all inclusive. In each row the first
  /// cell of the range stays and spans the range (`w:gridSpan`), and the
  /// others go; a row is never removed, even when it keeps one cell. Over
  /// several rows the first of those cells restarts a vertical merge and the
  /// ones below continue it, with one empty paragraph each.
  ///
  /// The blocks of every merged cell move to the top-left cell in reading
  /// order, without empty paragraphs, as Word does; a merge of empty cells
  /// leaves one. A cell that stays and took the place of others gets the sum
  /// of the merged columns as its width (`w:tcW`), when each cell merged in
  /// that row has a width in twips, each column has a width and the sum is one
  /// a width can hold, else it keeps its own.
  ///
  /// A merged cell wholly inside the range joins the merge. A range of one
  /// cell changes nothing.
  ///
  /// It is one edit. Throws [ArgumentError], and nothing changes, for:
  ///
  /// - a table without a grid, or an empty one;
  /// - a range that is out of the table or runs backwards, or that spans more
  ///   than [maxTableColumns] columns;
  /// - a row of the range whose cells, `w:gridBefore` and `w:gridAfter` do not
  ///   fill the grid exactly, or that has no cell on a column of the range;
  /// - a range that cuts a merged cell: one that crosses its edge, starts on a
  ///   `w:vMerge` continue, runs on below the range or continues no cell of
  ///   the range above it;
  /// - a `w:sdt` or a `w:customXml` between the first and the last row, which
  ///   may hold rows the table does not show (a bookmark there is fine);
  /// - a nested table that would go past 80 tables deep.
  DocxTableCell mergeCells({
    required int firstRow,
    required int firstColumn,
    required int lastRow,
    required int lastColumn,
  }) {
    final List<List<DocxTableCell>> range = _cellsToMerge(
      firstRow,
      firstColumn,
      lastRow,
      lastColumn,
    );
    final DocxTableCell kept = range.first.first;
    final List<DocxTableCell> merged = range
        .expand((List<DocxTableCell> cells) => cells)
        .toList();
    if (merged.length == 1) return kept;
    for (final DocxTableCell cell in merged.skip(1)) {
      for (final DocxBlock block in cell._blocks) {
        if (block is DocxTable) checkFitsIn(block, kept);
      }
    }
    final int span = lastColumn - firstColumn + 1;
    final DocxTableWidth? width = _widthOfColumns(firstColumn, lastColumn);
    _sink.atomically(() {
      _gatherBlocks(kept, merged);
      for (int i = 0; i < range.length; i++) {
        _rows[firstRow + i]._mergeCells(range[i], span, width);
        if (range.length > 1) {
          final DocxTableCell first = range[i].first;
          if (i > 0) first.addParagraph();
          cellPropertySetOf(first).setValue(
            'vMerge',
            i == 0 ? DocxVerticalMerge.restart : DocxVerticalMerge.continuation,
          );
        }
      }
    });
    return kept;
  }

  /// The number of columns of the grid, or `null` for a table with no grid or
  /// an empty one, which nothing can fit.
  int? get _columnCount {
    final int? columns = _gridColumnsPt?.length;
    return columns == 0 ? null : columns;
  }

  /// Throws [ArgumentError] when a row taking [total] columns does not fit
  /// the grid; a table without a grid fits anything.
  void _checkFits(int total) {
    final int? columns = _columnCount;
    if (columns != null && total > columns) {
      throw ArgumentError.value(
        total,
        'columns',
        'must fit the $columns columns of the grid',
      );
    }
  }

  /// The cells of the row at [index], placed; none for no such row.
  List<_PlacedCell> _placedAt(int index) => index < 0 || index >= _rows.length
      ? const <_PlacedCell>[]
      : _rows[index]._placed();

  /// Throws [ArgumentError] when a child between the rows [r0] and [r1] may
  /// hold rows that [rows] does not list, which a merge would run across.
  void _checkNoRowsHidden(int r0, int r1) {
    final int last = _children.indexOf(_rows[r1]);
    for (int i = _children.indexOf(_rows[r0]) + 1; i < last; i++) {
      final Object child = _children[i];
      if (child is OpaqueXml &&
          child.namespaceUri == Ns.w &&
          (child.localName == 'sdt' || child.localName == 'customXml')) {
        throw ArgumentError(
          'Rows $r0 to $r1 are around a w:${child.localName}, which a merge '
          'cannot cross.',
        );
      }
    }
  }

  /// The cells of the range of [mergeCells], row by row; throws what it says.
  List<List<DocxTableCell>> _cellsToMerge(int r0, int c0, int r1, int c1) {
    final int? columns = _columnCount;
    if (columns == null) {
      throw ArgumentError('A table without a grid has no cells to merge.');
    }
    if (r0 < 0 || c0 < 0 || r0 > r1 || c0 > c1) {
      throw ArgumentError('Rows $r0 to $r1, columns $c0 to $c1 are no range.');
    }
    if (r1 >= _rows.length || c1 >= columns) {
      throw ArgumentError(
        'Rows $r0 to $r1, columns $c0 to $c1 are past the table of '
        '${_rows.length} rows and $columns columns.',
      );
    }
    if (c1 - c0 >= maxTableColumns) {
      throw ArgumentError('A cell spans at most $maxTableColumns columns.');
    }
    if (r0 < r1) _checkNoRowsHidden(r0, r1);
    final List<List<DocxTableCell>> range = <List<DocxTableCell>>[];
    List<_PlacedCell> above = const <_PlacedCell>[];
    for (int r = r0; r <= r1; r++) {
      final DocxTableRow row = _rows[r];
      if (row._gridTotal != columns) {
        throw ArgumentError('Row $r does not fill the grid.');
      }
      final List<_PlacedCell> placed = _placedInRange(row, r, c0, c1);
      for (final _PlacedCell at in placed) {
        if (at.cell._continues && !_continuesOneOf(at, above)) {
          throw ArgumentError('The range cuts a merged cell in row $r.');
        }
      }
      range.add(<DocxTableCell>[for (final _PlacedCell at in placed) at.cell]);
      above = placed;
    }
    if (r1 + 1 < _rows.length) {
      for (int column = c0; column <= c1; column++) {
        if (cellAtGrid(this, r1 + 1, column)?._continues ?? false) {
          throw ArgumentError('The range cuts a merged cell below row $r1.');
        }
      }
    }
    return range;
  }

  /// The cells of [row], at index [r], from column [c0] to [c1]; throws
  /// [ArgumentError] unless they cover those columns exactly.
  static List<_PlacedCell> _placedInRange(
    DocxTableRow row,
    int r,
    int c0,
    int c1,
  ) {
    final List<_PlacedCell> placed = <_PlacedCell>[
      for (final _PlacedCell at in row._placed())
        if (at.end > c0 && at.start <= c1) at,
    ];
    if (placed.isEmpty) {
      throw ArgumentError('Row $r has no cell in columns $c0 to $c1.');
    }
    if (placed.first.start != c0 || placed.last.end != c1 + 1) {
      throw ArgumentError(
        'The range cuts a cell of row $r, or passes its end.',
      );
    }
    return placed;
  }

  /// Whether a cell of [above], in a vertical merge, has the columns of [at].
  static bool _continuesOneOf(_PlacedCell at, List<_PlacedCell> above) {
    for (final _PlacedCell cell in above) {
      if (cell.start == at.start &&
          cell.end == at.end &&
          cell.cell.properties.verticalMerge != null) {
        return true;
      }
    }
    return false;
  }

  /// The width of the columns [first] to [last] together; `null` when one has
  /// no width, or the sum is none at all or more than a width holds.
  DocxTableWidth? _widthOfColumns(int first, int last) {
    final List<double?> grid = _gridColumnsPt!;
    double sum = 0;
    for (int column = first; column <= last; column++) {
      final double? width = grid[column];
      if (width == null) return null;
      sum += width;
    }
    if (sum == 0 || sum > ptOfTwips(maxTwips)) return null;
    return DocxTableWidth.points(sum);
  }

  /// Moves what [_blocksToKeep] gives of [merged], which starts with [kept],
  /// to [kept], in order; the other blocks go. A cell left with nothing gets
  /// an empty paragraph.
  static void _gatherBlocks(DocxTableCell kept, List<DocxTableCell> merged) {
    final Set<DocxBlock> keep = Set<DocxBlock>.identity()
      ..addAll(_blocksToKeep(merged));
    for (int i = kept._blocks.length - 1; i >= 0; i--) {
      if (!keep.contains(kept._blocks[i])) kept.removeBlockAt(i);
    }
    for (final DocxTableCell cell in merged.skip(1)) {
      final List<DocxBlock> blocks = List<DocxBlock>.of(cell._blocks);
      for (int i = blocks.length - 1; i >= 0; i--) {
        cell.removeBlockAt(i);
      }
      for (final DocxBlock block in blocks) {
        if (keep.contains(block)) {
          kept.insertBlock(kept._blocks.length, block);
        }
      }
    }
    if (kept._blocks.isEmpty) kept.addParagraph();
  }

  /// The blocks of [merged] in order, without empty paragraphs, but for one
  /// between two tables, which Word would otherwise join, and the first block
  /// when all of them are empty.
  static List<DocxBlock> _blocksToKeep(List<DocxTableCell> merged) {
    final List<DocxBlock> all = merged
        .expand((DocxTableCell cell) => cell._blocks)
        .toList();
    final List<bool> tableNext = List<bool>.filled(all.length, false);
    bool next = false;
    for (int i = all.length - 1; i >= 0; i--) {
      tableNext[i] = next;
      if (!_isEmptyParagraph(all[i])) next = all[i] is DocxTable;
    }
    final List<DocxBlock> keep = <DocxBlock>[];
    for (int i = 0; i < all.length; i++) {
      if (!_isEmptyParagraph(all[i]) ||
          (tableNext[i] && keep.lastOrNull is DocxTable)) {
        keep.add(all[i]);
      }
    }
    if (keep.isEmpty && all.isNotEmpty) keep.add(all.first);
    return keep;
  }
}

/// A cell of a row and the columns of the grid it takes, from `start` up to
/// and without `end`.
typedef _PlacedCell = ({DocxTableCell cell, int start, int end});

/// The column after each of [cells] by the column it starts on, so a row of
/// many cells is looked up, not searched cell by cell.
Map<int, int> _endsByStart(Iterable<_PlacedCell> cells) => <int, int>{
  for (final _PlacedCell cell in cells) cell.start: cell.end,
};

/// Throws [ArgumentError] unless [above], a row's [_endsByStart], has a cell of
/// the columns [start] up to and without [end], for a cell to continue.
void _checkContinues(Map<int, int> above, int start, int end) {
  if (above[start] == end) return;
  throw ArgumentError.value(
    DocxVerticalMerge.continuation,
    'verticalMerge',
    'must continue a cell of the same columns in the row above',
  );
}

/// Whether [block] is a paragraph that shows nothing and holds nothing: no
/// inline but runs without content or with empty text.
bool _isEmptyParagraph(DocxBlock block) {
  return block is DocxParagraph &&
      block._inlines.every(
        (DocxInline inline) =>
            inline is DocxRun &&
            inline.content.every(
              (DocxRunContent c) => c is DocxText && c.text.isEmpty,
            ),
      );
}

/// The cell of row [row] of [table] on the grid column [column], counting the
/// row's `w:gridBefore` and each cell's span, or `null` for a column no cell
/// takes. A [row] that is not an index of a row throws [RangeError].
DocxTableCell? cellAtGrid(DocxTable table, int row, int column) {
  for (final _PlacedCell at in table._rows[row]._placed()) {
    if (at.start <= column && column < at.end) return at.cell;
  }
  return null;
}

bool _sameWidths(List<double?> a, List<double?> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The widths of a table's grid set: reverts to the list before.
final class _GridSet implements Change {
  _GridSet(this._table, this._previous, this._next);

  final DocxTable _table;
  final List<double?>? _previous;
  final List<double?> _next;

  @override
  void revert() => _table._gridColumnsPt = _previous;

  @override
  void reapply() => _table._gridColumnsPt = _next;
}

/// A `w:tblGrid` as read: the element as written, for a grid nothing
/// changed, and the parts a grid with new widths is written from.
final class TableGrid {
  /// A grid whose element is [xml], whose own namespace declarations are
  /// [declared] and whose children that are no `w:gridCol` are the texts
  /// [keptChildren], as written.
  const TableGrid(this.xml, this.declared, this.keptChildren);

  /// The element as written.
  final OpaqueXml xml;

  /// The namespaces the element declared, prefix to URI.
  final Map<String, String> declared;

  /// The children that are not a `w:gridCol` of WordprocessingML, in order,
  /// as written, such as `w:tblGridChange`.
  final List<String> keptChildren;
}

/// A row of a table, `w:tr`.
final class DocxTableRow {
  /// A row of [cells] empty cells, each with one empty paragraph.
  ///
  /// It belongs to no table until it is inserted into one. A [cells] outside
  /// 1 to [maxTableColumns] throws [RangeError].
  DocxTableRow({int cells = 1})
    : this._read(
        const PropertyContainer.empty(),
        const <KeptAttribute>[],
        _emptyCells(cells),
      );

  DocxTableRow._read(this._source, this._attributes, this._children)
    : _cells = _ofType<DocxTableCell>(_children) {
    for (final DocxTableCell cell in _cells) {
      cell._row = this;
    }
  }

  /// [cells] empty cells.
  static List<Object> _emptyCells(int cells) {
    RangeError.checkValueInInterval(cells, 1, maxTableColumns, 'cells');
    return <Object>[for (int i = 0; i < cells; i++) DocxTableCell()];
  }

  /// The row's `w:trPr` as read, by `tableRowPropertiesSchema`.
  final PropertyContainer _source;

  /// The row's properties: [_source] with the values set.
  late final DocxTableRowProperties _properties = newTableRowProperties(
    _source,
    () => _sink,
  );

  DocxEditSink _sink = DocxEditSink.none;

  /// The table the row is in, or `null` while it is in none.
  DocxTable? _table;

  /// The attributes of `w:tr` the reader kept, such as `w14:paraId`.
  final List<KeptAttribute> _attributes;

  /// The children of `w:tr` in file order: the [_source] when the file has a
  /// `w:trPr`, each [DocxTableCell], and an [OpaqueXml] for any other,
  /// `w:tblPrEx` among them.
  final List<Object> _children;

  /// The typed cells of [_children], in order.
  final List<DocxTableCell> _cells;

  late final List<DocxTableCell> _cellsView =
      UnmodifiableListView<DocxTableCell>(_cells);

  /// The row's cells, in order. The list cannot be modified.
  ///
  /// Only the `w:tc` children of `w:tr` are cells: one inside a content
  /// control or another kept element is not listed, and is written as read.
  List<DocxTableCell> get cells => _cellsView;

  /// The formatting of the row: its `w:trPr`.
  ///
  /// It is the same object every time.
  DocxTableRowProperties get properties => _properties;

  /// Whether the row repeats as a header: a shortcut for
  /// [DocxTableRowProperties.repeatAsHeader] being `true`.
  ///
  /// Setting `true` sets `repeatAsHeader`; setting `false` removes it, so a
  /// `w:tblHeader w:val="0"` goes too.
  bool get isHeader => _properties.repeatAsHeader == true;

  set isHeader(bool value) => _properties.repeatAsHeader = value ? true : null;

  /// Inserts [cell] at [index], from 0 to the number of cells: directly before
  /// the cell at [index], or after the last child of the row for the last
  /// index, so what the row does not show stays where it was.
  ///
  /// An [index] out of that range throws [RangeError]. A [cell] already in a
  /// row, this one or another, throws [StateError]: remove it there first. A
  /// [cell] that holds this row, or whose tables would nest past 80 deep,
  /// throws [ArgumentError]; so does one that, in a row of a table with a
  /// grid, takes the row past the columns of the grid. Nothing changes then.
  ///
  /// In a row of a document, the styles set on what the cell holds are resolved
  /// as `DocxBody.insertBlock` says, and it may throw the same
  /// `DocxReadException`.
  void insertCellAt(int index, DocxTableCell cell) {
    RangeError.checkValueInInterval(index, 0, _cells.length, 'index');
    if (cell._row == null) _table?._checkFits(_gridTotal + cell._span);
    primitives.insertChild(_sink, this, _children, _cells, index, cell);
  }

  /// Removes the cell at [index]. The cell is then in no row and can be
  /// inserted again; what the row does not show stays where it was.
  ///
  /// An [index] that is not one of a cell throws [RangeError]. The last cell
  /// throws [StateError]: Word repairs a row without cells, so remove the row
  /// instead. Nothing changes then.
  void removeCellAt(int index) =>
      primitives.removeChild(_sink, this, _children, _cells, index);

  /// The columns of the grid the row skips for the child [name]
  /// (`gridBefore`, `gridAfter`) of its properties.
  int _skipped(String name) =>
      rowPropertySetOf(this).valueOf(name) as int? ?? 0;

  /// The cells of the row, each with the columns of the grid it takes.
  List<_PlacedCell> _placed() {
    int column = _skipped('gridBefore');
    return <_PlacedCell>[
      for (final DocxTableCell cell in _cells)
        (cell: cell, start: column, end: column += cell._span),
    ];
  }

  /// The columns of the grid the row takes: its cells and what it skips.
  int get _gridTotal {
    int columns = _skipped('gridBefore') + _skipped('gridAfter');
    for (final DocxTableCell cell in _cells) {
      columns += cell._span;
    }
    return columns;
  }

  /// Takes out every cell of [cells], neighbours in the row, but the first,
  /// which spans [span] columns from now on and takes [width] if it took the
  /// place of others, all of a width in twips. The span is set past the checks
  /// of [DocxTableCellProperties.gridSpan]: the merge has checked the whole
  /// range, and the rows around this one are half way through it.
  void _mergeCells(List<DocxTableCell> cells, int span, DocxTableWidth? width) {
    final int first = _cells.indexOf(cells.first);
    final bool inTwips = cells.every(
      (DocxTableCell cell) =>
          cell.properties.width?.kind == DocxTableWidthKind.points,
    );
    for (int i = cells.length - 1; i > 0; i--) {
      removeCellAt(first + i);
    }
    final DocxTableCell kept = cells.first;
    if (span > 1) cellPropertySetOf(kept).setValue('gridSpan', span);
    if (width != null && cells.length > 1 && inTwips) {
      kept.properties.width = width;
    }
  }
}

/// A cell of a table row, `w:tc`.
///
/// A saved cell ends in a paragraph: one whose last block is another is written
/// with an empty `w:p` after it, which is not in [blocks] until the file is
/// read again.
final class DocxTableCell {
  /// A cell of one paragraph that holds [text], or an empty paragraph for the
  /// empty text. The text is split and scrubbed as [DocxRun.text] is when set.
  ///
  /// It belongs to no row until it is inserted into one.
  DocxTableCell([String text = ''])
    : this._read(
        const PropertyContainer.empty(),
        const <KeptAttribute>[],
        <DocxBlock>[DocxParagraph.text(text)],
      );

  /// A cell of [_blocks], which are in it from now on. A block already in a
  /// container throws [StateError].
  DocxTableCell._read(this._source, this._attributes, this._blocks)
    : _readUnclosed = _blocks.lastOrNull is DocxParagraph
          ? null
          : List<DocxBlock>.of(_blocks) {
    for (final DocxBlock block in _blocks) {
      if (block._container != null) {
        throw StateError('The block is already in a container.');
      }
      block._container = this;
    }
  }

  /// The cell's `w:tcPr` as read, by `tableCellPropertiesSchema`.
  final PropertyContainer _source;

  /// The cell's properties: [_source] with the values set.
  late final DocxTableCellProperties _properties = newTableCellProperties(
    _source,
    () => _sink,
    checkGridSpan: _checkGridSpan,
    checkContinuation: _checkContinuation,
  );

  DocxEditSink _sink = DocxEditSink.none;

  /// The row the cell is in, or `null` while it is in none.
  DocxTableRow? _row;

  /// The attributes of `w:tc` the reader kept, such as `w:rsidR`.
  final List<KeptAttribute> _attributes;

  final List<DocxBlock> _blocks;

  late final List<DocxBlock> _blocksView = UnmodifiableListView<DocxBlock>(
    _blocks,
  );

  /// The blocks read, when the cell was read without a paragraph last; `null`
  /// for a cell read with one, which needs no such copy.
  final List<DocxBlock>? _readUnclosed;

  /// The cell's blocks, in order: paragraphs, tables and opaque blocks. The
  /// list cannot be modified, and shows later edits; use [addParagraph],
  /// [insertBlock], [removeBlockAt] and [replaceBlockAt].
  List<DocxBlock> get blocks => _blocksView;

  /// The formatting of the cell: its `w:tcPr`.
  ///
  /// It is the same object every time.
  DocxTableCellProperties get properties => _properties;

  /// The cell's text: the text of its paragraphs joined by `\n`. A nested
  /// table adds the text of its cells, row by row, in their place; an opaque
  /// block adds nothing.
  String get text {
    final List<String> lines = <String>[];
    _addLines(lines);
    return lines.join('\n');
  }

  /// Appends a new paragraph that holds [text] and returns it. The text is
  /// split and scrubbed as [DocxRun.text] is when set; the empty text gives a
  /// paragraph without runs.
  DocxParagraph addParagraph([String text = '']) {
    final DocxParagraph paragraph = DocxParagraph.text(text);
    insertBlock(_blocks.length, paragraph);
    return paragraph;
  }

  /// Appends a new table of [columns] columns, with no rows yet, and returns
  /// it; `DocxBody.addTable` has the rules and what it throws, but that without
  /// [columnWidthsPt] the columns share the cell's own width, when it has one
  /// in twips (`w:tcW`) that gives each a twip, so the table fits the cell.
  ///
  /// In a cell of a document it has the document's `Table Grid` style, as a
  /// table of the body. In a cell of no document it has no style, as
  /// [DocxTable.new]: set one on the table, and it resolves when the cell goes
  /// in a document.
  ///
  /// Whatever the cell held stays before the table, an empty paragraph too, and
  /// a table last in a cell is saved with an empty paragraph after it. A table
  /// that would nest past 80 deep throws [ArgumentError], and nothing changes.
  DocxTable addTable({required int columns, List<double>? columnWidthsPt}) {
    final DocxTable table = newTable(
      columns,
      columnWidthsPt,
      widthTwips: _widthToShare(columns),
    );
    _sink.atomically(() {
      table.properties.style = _sink.ensureStyle(DocxBuiltInStyle.tableGrid);
      insertBlock(_blocks.length, table);
    });
    return table;
  }

  /// The twips [columns] new columns share: the cell's own width when it has
  /// one in twips that gives each a twip, else the page's.
  int _widthToShare(int columns) {
    final double? pt = _properties.width?.widthPt;
    if (pt == null || pt < 0 || pt > ptOfTwips(maxTwips)) {
      return _pageTextWidthTwips;
    }
    final int twips = twipsOf(pt, 'width', min: 0, max: maxTwips);
    return twips >= columns ? twips : _pageTextWidthTwips;
  }

  /// Inserts [block] at [index], from 0 to the number of blocks.
  ///
  /// An [index] out of that range throws [RangeError]. A [block] already in a
  /// body or a cell throws [StateError]: remove it there first. A table that
  /// holds this cell, or that would nest tables past 80 deep, throws
  /// [ArgumentError]. Nothing changes then.
  ///
  /// In a cell of a document, the styles set on [block] are resolved as
  /// `DocxBody.insertBlock` says, and it may throw the same
  /// `DocxReadException`.
  void insertBlock(int index, DocxBlock block) =>
      primitives.insertBlock(_sink, this, _blocks, index, block);

  /// Removes the block at [index]. The block is then in no cell and can be
  /// inserted again. A cell left without blocks is written with an empty
  /// paragraph.
  ///
  /// An [index] that is not one of a block throws [RangeError].
  void removeBlockAt(int index) =>
      primitives.removeBlock(_sink, this, _blocks, index);

  /// Puts [block] in place of the block at [index]. The block replaced is
  /// then in no cell.
  ///
  /// An [index] that is not one of a block throws [RangeError], and the rest
  /// is as for [insertBlock].
  void replaceBlockAt(int index, DocxBlock block) =>
      primitives.replaceBlock(_sink, this, _blocks, index, block);

  /// The columns of the grid the cell takes.
  int get _span => _properties.gridSpan ?? 1;

  /// Whether the cell continues a vertical merge.
  bool get _continues =>
      _properties.verticalMerge == DocxVerticalMerge.continuation;

  /// Throws [ArgumentError] when [span], another than the cell has, does not
  /// fit the table the cell is in: a wider one past the grid, and any that
  /// takes the cell, or one after it in the row, out of line with a vertical
  /// merge. A narrower one adds no column, so the row of a file that does not
  /// fit the grid can still be narrowed.
  void _checkGridSpan(int span) {
    final DocxTableRow? row = _row;
    final DocxTable? table = row?._table;
    if (row == null || table == null || span == _span) return;
    final int change = span - _span;
    if (change > 0) table._checkFits(row._gridTotal + change);
    final int index = table._rows.indexOf(row);
    final Map<int, int> above = _endsByStart(table._placedAt(index - 1));
    final Map<int, int> continuedBelow = _endsByStart(
      table
          ._placedAt(index + 1)
          .where((_PlacedCell placed) => placed.cell._continues),
    );
    bool moves = false;
    for (final _PlacedCell at in row._placed()) {
      final bool isThis = identical(at.cell, this);
      moves = moves || isThis;
      if (!moves) continue;
      if (at.cell._continues) {
        final int start = isThis ? at.start : at.start + change;
        _checkContinues(above, start, at.end + change);
      }
      if (continuedBelow[at.start] == at.end) {
        throw ArgumentError.value(
          span,
          'gridSpan',
          'must keep the columns of the cell the row below continues',
        );
      }
    }
  }

  /// Throws [ArgumentError] when the cell, in a row of a table, has no cell of
  /// the same columns in the row above.
  void _checkContinuation() {
    final DocxTableRow? row = _row;
    final DocxTable? table = row?._table;
    if (row == null || table == null) return;
    final _PlacedCell at = row._placed().firstWhere(
      (_PlacedCell placed) => identical(placed.cell, this),
    );
    final Map<int, int> above = _endsByStart(
      table._placedAt(table._rows.indexOf(row) - 1),
    );
    _checkContinues(above, at.start, at.end);
  }

  void _addLines(List<String> lines) {
    for (final DocxBlock block in _blocks) {
      switch (block) {
        case DocxParagraph():
          lines.add(block.text);
        case DocxTable():
          for (final DocxTableRow row in block._rows) {
            for (final DocxTableCell cell in row._cells) {
              cell._addLines(lines);
            }
          }
        case DocxOpaqueBlock():
          break;
      }
    }
  }
}

/// A block the model does not type, kept as written.
final class DocxOpaqueBlock extends DocxBlock {
  DocxOpaqueBlock._(this._xml) : super._();

  final OpaqueXml _xml;

  /// The element's local name, such as `sdt` or `bookmarkStart`.
  String get localName => _xml.localName;

  /// The element's namespace URI, or the empty string.
  String get namespaceUri => _xml.namespaceUri;

  @override
  String toString() => 'DocxOpaqueBlock($localName)';
}

/// A paragraph as the reader builds it: its `w:pPr` as read (by
/// `paragraphPropertiesSchema`), the kept attributes of `w:p`, and its
/// inlines as read. Each inline must be in no paragraph, or [StateError] is
/// thrown.
DocxParagraph readParagraph({
  required PropertyContainer properties,
  required List<KeptAttribute> attributes,
  required List<DocxInline> inlines,
}) {
  final DocxParagraph p = DocxParagraph._read(properties, attributes);
  for (final DocxInline inline in inlines) {
    DocxParagraph._checkDetached(inline);
    p._inlines.add(inline);
    setParagraphOf(inline, p);
  }
  return p;
}

/// A table as the reader builds it: its `w:tblPr` as read (by
/// `tablePropertiesSchema`; an empty container for none), the kept attributes
/// of `w:tbl`, the widths of its grid, and its children in file order: the
/// [properties] when read, each [DocxTableRow], and an [OpaqueXml] for any
/// other.
DocxTable readTable({
  required PropertyContainer properties,
  required List<KeptAttribute> attributes,
  required List<double?>? gridColumnsPt,
  required List<Object> children,
}) => DocxTable._read(properties, attributes, gridColumnsPt, children);

/// A new table as `DocxBody.addTable` builds it, in no document yet, without a
/// style or rows: Word's width and look, and the grid of [columns] columns of
/// the widths [columnWidthsPt], or sharing [widthTwips], by default the page.
///
/// A [columns] outside 1 to [maxTableColumns], or a width out of range, throws
/// [RangeError]; [columnWidthsPt] of another length than [columns], or with a
/// width that is not finite, throws [ArgumentError].
DocxTable newTable(
  int columns,
  List<double>? columnWidthsPt, {
  int widthTwips = _pageTextWidthTwips,
}) {
  final DocxTable table = DocxTable._read(
    const PropertyContainer.empty(),
    const <KeptAttribute>[],
    DocxTable._newGrid(columns, columnWidthsPt, widthTwips),
    <Object>[],
    isNew: true,
  );
  table.properties
    ..width = const DocxTableWidth.auto()
    ..look = const DocxTableLook(
      firstRow: true,
      firstColumn: true,
      noVerticalBands: true,
    );
  return table;
}

/// A row as the reader builds it: its `w:trPr` as read (by
/// `tableRowPropertiesSchema`; an empty container for none), the kept
/// attributes of `w:tr`, and its children in file order: the [properties]
/// when read, each [DocxTableCell], and an [OpaqueXml] for any other.
DocxTableRow readTableRow({
  required PropertyContainer properties,
  required List<KeptAttribute> attributes,
  required List<Object> children,
}) => DocxTableRow._read(properties, attributes, children);

/// A cell as the reader builds it: its `w:tcPr` as read (by
/// `tableCellPropertiesSchema`; an empty container for none), the kept
/// attributes of `w:tc`, and its blocks as read, which are in the cell from
/// now on. Each block must be in no container, or [StateError] is thrown.
DocxTableCell readTableCell({
  required PropertyContainer properties,
  required List<KeptAttribute> attributes,
  required List<DocxBlock> blocks,
}) => DocxTableCell._read(properties, attributes, blocks);

/// The elements of type [T] among [children], in order.
List<T> _ofType<T>(List<Object> children) => children.whereType<T>().toList();

/// The one walk of the tree: calls [visit] with [item] (a block, a row or a
/// cell) and everything it holds in document order, each with the number of
/// tables around it, counted from [tables] for [item].
///
/// Rows and cells inside a kept element are not part of the tree.
void _walk(
  Object item,
  int tables,
  void Function(Object item, int tables) visit,
) {
  visit(item, tables);
  switch (item) {
    case DocxTable():
      for (final DocxTableRow row in item._rows) {
        _walk(row, tables + 1, visit);
      }
    case DocxTableRow():
      for (final DocxTableCell cell in item._cells) {
        _walk(cell, tables, visit);
      }
    case DocxTableCell():
      for (final DocxBlock block in item._blocks) {
        _walk(block, tables, visit);
      }
  }
}

/// Calls [visit] with [block], then with every block in the cells of a table,
/// nested tables included, in document order.
///
/// Rows and cells inside a kept element are not part of the tree.
void visitBlocks(DocxBlock block, void Function(DocxBlock block) visit) {
  _walk(block, 0, (Object item, int _) {
    if (item is DocxBlock) visit(item);
  });
}

/// Resolves the style set through the API on [run], which is in a paragraph
/// of the document of [sink] now; one read in another document counts as set.
void _resolveRunStyle(DocxRun run, DocxEditSink sink) {
  final PropertySet properties = runPropertySetOf(run);
  if (sink.isForeign(runReadInOf(run))) {
    properties.countReadAsSet('rStyle');
  }
  properties.resolveStyleIdSet('rStyle', DocxStyleType.character);
}

/// Resolves the styles set through the API on [paragraph] and its runs,
/// which are in a document now; what was read from that document's file
/// stays (plan Ruling 5), and what was read in another counts as set: the
/// `w:pStyle`, the `w:numPr` that the save checks, and each run's
/// `w:rStyle`.
void _resolveStylesSet(DocxParagraph paragraph) {
  final DocxEditSink sink = paragraph._sink;
  final PropertySet properties = paragraphPropertySetOf(paragraph);
  if (sink.isForeign(paragraph._readIn)) {
    properties
      ..countReadAsSet('pStyle')
      ..countReadAsSet('numPr');
  }
  properties.resolveStyleIdSet('pStyle', DocxStyleType.paragraph);
  for (final DocxInline inline in paragraph._inlines) {
    if (inline is DocxRun) {
      _resolveRunStyle(inline, sink);
    }
  }
}

/// Resolves the style set through the API on [table], which is in a document
/// now; one read in another document counts as set.
void _resolveTableStyle(DocxTable table) {
  final PropertySet properties = tablePropertySetOf(table);
  if (table._sink.isForeign(table._readIn)) {
    properties.countReadAsSet('tblStyle');
  }
  properties.resolveStyleIdSet('tblStyle', DocxStyleType.table);
}

/// Resolves the styles of [item] (a block, a row or a cell) and of everything
/// it holds, nested tables included, as [_resolveStylesSet] does for a
/// paragraph: what was read from the document [item] is in now stays, and what
/// was read in another counts as set, a table's `w:tblStyle` too.
void resolveStylesIn(Object item) {
  _walk(item, 0, (Object node, int _) {
    switch (node) {
      case DocxParagraph():
        _resolveStylesSet(node);
      case DocxTable():
        _resolveTableStyle(node);
    }
  });
}

/// Records that [paragraph] and its runs were read in the document of
/// [sink], so what they name counts as set in any other.
void markReadIn(DocxParagraph paragraph, DocxEditSink sink) {
  paragraph._readIn = sink;
  for (final DocxInline inline in paragraph._inlines) {
    if (inline is DocxRun) {
      setRunReadIn(inline, sink);
    }
  }
}

/// Records that [block] and everything in its cells were read in the document
/// of [sink] ([markReadIn]), so what they name counts as set in any other.
void markBlockReadIn(DocxBlock block, DocxEditSink sink) {
  visitBlocks(block, (DocxBlock b) {
    if (b is DocxParagraph) {
      markReadIn(b, sink);
    } else if (b is DocxTable) {
      b._readIn = sink;
    }
  });
}

/// The sink of the document [paragraph] was read in, or `null` for a new one.
DocxEditSink? paragraphReadInOf(DocxParagraph paragraph) => paragraph._readIn;

/// The `w:pPr` of [paragraph] as read, without the values set since.
PropertyContainer paragraphPropertiesOf(DocxParagraph paragraph) =>
    paragraph._source;

/// The properties of [paragraph], for the writer.
PropertySet paragraphPropertySetOf(DocxParagraph paragraph) =>
    propertySetOfParagraphProperties(paragraph._properties);

/// The attributes of `w:p` the reader kept on [paragraph], in source order.
List<KeptAttribute> paragraphAttributesOf(DocxParagraph paragraph) =>
    paragraph._attributes;

/// The sink [paragraph] and its runs report their edits to.
DocxEditSink editSinkOf(DocxParagraph paragraph) => paragraph._sink;

/// Makes [sink] receive the edits of [paragraph] and its runs from now on;
/// [DocxEditSink.none] detaches it.
void attachEditSink(DocxParagraph paragraph, DocxEditSink sink) {
  paragraph._sink = sink;
}

/// Puts [inline] in place of the inline at [index] of [paragraph], and
/// reports it to the paragraph's sink.
///
/// An [index] that is not one of an inline throws [RangeError], and an
/// [inline] already in a paragraph throws [StateError].
void replaceInlineAt(DocxParagraph paragraph, int index, DocxInline inline) {
  final List<DocxInline> inlines = paragraph._inlines;
  RangeError.checkValidIndex(index, inlines, 'index');
  DocxParagraph._checkDetached(inline);
  final DocxInline previous = inlines[index];
  inlines[index] = inline;
  setParagraphOf(previous, null);
  setParagraphOf(inline, paragraph);
  paragraph._sink.inlineReplaced(paragraph, index, previous, inline);
}

/// Makes [item] (a block, a row or a cell) and everything it holds report
/// its edits to [sink]; [DocxEditSink.none] detaches them.
void attachSink(Object item, DocxEditSink sink) {
  _walk(item, 0, (Object node, int _) {
    switch (node) {
      case DocxParagraph():
        node._sink = sink;
      case DocxTable():
        node._sink = sink;
      case DocxTableRow():
        node._sink = sink;
      case DocxTableCell():
        node._sink = sink;
    }
  });
}

/// Throws [ArgumentError] when [item] (a table, a row or a cell) cannot go in
/// [container]: it holds [container], or it holds tables that, with those
/// around [container], nest past [maxBuiltTableNesting]. An [item] that holds
/// no table deepens nothing and always fits, even in a file nested past that.
///
/// It walks up from [container] and through [item] only, once per edit, so an
/// edit costs what is inserted and not what the document holds.
void checkFitsIn(Object item, Object container) {
  int tables = 0;
  for (Object? at = container; at != null; at = parentOf(at)) {
    if (identical(at, item)) {
      throw ArgumentError.value(item, 'item', 'must not go inside itself');
    }
    if (at is DocxTable) tables++;
  }
  int deepest = 0;
  _walk(item, tables, (Object node, int around) {
    if (node is DocxTable && around >= deepest) deepest = around + 1;
  });
  if (deepest > maxBuiltTableNesting) {
    throw ArgumentError.value(
      item,
      'item',
      'must not nest tables past $maxBuiltTableNesting',
    );
  }
}

/// The `w:tblPr` of [table] as read; an empty container for none.
PropertyContainer tablePropertiesOf(DocxTable table) => table._source;

/// The properties of [table], for the writer.
PropertySet tablePropertySetOf(DocxTable table) =>
    propertySetOfTableProperties(table._properties);

/// The properties of [row], for the writer.
PropertySet rowPropertySetOf(DocxTableRow row) =>
    propertySetOfTableRowProperties(row._properties);

/// The properties of [cell], for the writer.
PropertySet cellPropertySetOf(DocxTableCell cell) =>
    propertySetOfTableCellProperties(cell._properties);

/// The widths of the grid of [table] now, and whether they are the ones the
/// file gave (the grid is then written as read).
List<double?>? tableGridWidthsOf(DocxTable table) => table._gridColumnsPt;

/// Whether the grid of [table] is the one the file gave, so it is written as
/// read.
bool tableGridAsRead(DocxTable table) =>
    identical(table._gridColumnsPt, table._gridRead);

/// Whether [table] was built here and not read from a file, so it writes a
/// `w:tblPr` even when empty.
bool tableIsNew(DocxTable table) => table._isNew;

/// The attributes of `w:tbl` the reader kept on [table], in source order.
List<KeptAttribute> tableAttributesOf(DocxTable table) => table._attributes;

/// The children of `w:tbl` of [table] in file order, for the writer: its
/// [tablePropertiesOf] when read, each [DocxTableRow], and an [OpaqueXml] for
/// any other.
List<Object> tableChildrenOf(DocxTable table) => table._children;

/// The `w:trPr` of [row] as read; an empty container for none.
PropertyContainer rowPropertiesOf(DocxTableRow row) => row._source;

/// The attributes of `w:tr` the reader kept on [row], in source order.
List<KeptAttribute> rowAttributesOf(DocxTableRow row) => row._attributes;

/// The children of `w:tr` of [row] in file order, for the writer: its
/// [rowPropertiesOf] when read, each [DocxTableCell], and an [OpaqueXml] for
/// any other.
List<Object> rowChildrenOf(DocxTableRow row) => row._children;

/// The `w:tcPr` of [cell] as read; an empty container for none.
PropertyContainer cellPropertiesOf(DocxTableCell cell) => cell._source;

/// The attributes of `w:tc` the reader kept on [cell], in source order.
List<KeptAttribute> cellAttributesOf(DocxTableCell cell) => cell._attributes;

/// The list of the blocks of [cell], for tests that call the block primitives
/// themselves.
List<DocxBlock> cellBlocksOf(DocxTableCell cell) => cell._blocks;

/// The range markers of `w:` that may stand at the block level: they show
/// nothing, so a paragraph before them still closes a cell.
const Set<String> _rangeMarkers = <String>{
  'bookmarkStart',
  'bookmarkEnd',
  'commentRangeStart',
  'commentRangeEnd',
  'permStart',
  'permEnd',
  'moveFromRangeStart',
  'moveFromRangeEnd',
  'moveToRangeStart',
  'moveToRangeEnd',
};

/// Whether [block] is one of the [_rangeMarkers].
bool _isRangeMarker(DocxBlock block) =>
    block is DocxOpaqueBlock &&
    block.namespaceUri == Ns.w &&
    _rangeMarkers.contains(block.localName);

/// Whether [cell] must be written with an empty `w:p` after its blocks: Word
/// repairs a cell that does not end in a paragraph, trailing range markers
/// aside. A cell with no paragraph at all gets one, whatever else it holds.
///
/// A cell read without one, whose blocks are still all the ones read, is
/// written as read; the blocks compare by identity, so an undo restores that,
/// and a cell read with no blocks stays empty. The paragraph added is not in
/// [DocxTableCell.blocks] until the file is read again.
bool cellNeedsClosingParagraph(DocxTableCell cell) {
  if (_blocksAsRead(cell)) return false;
  for (final DocxBlock block in cell._blocks.reversed) {
    if (!_isRangeMarker(block)) return block is! DocxParagraph;
  }
  return true;
}

/// Whether [cell] was read without a closing paragraph and holds exactly the
/// blocks it read, in order.
bool _blocksAsRead(DocxTableCell cell) {
  final List<DocxBlock>? read = cell._readUnclosed;
  final List<DocxBlock> blocks = cell._blocks;
  if (read == null || read.length != blocks.length) return false;
  for (int i = 0; i < read.length; i++) {
    if (!identical(read[i], blocks[i])) return false;
  }
  return true;
}

/// The container [block] is in, such as a document's body or a table cell, or
/// `null`.
Object? blockContainerOf(DocxBlock block) => block._container;

/// What holds [item]: the container of a block, the table of a row, the row
/// of a cell; `null` for one in nothing, or for anything else, such as a body.
Object? parentOf(Object item) => switch (item) {
  DocxBlock() => item._container,
  DocxTableRow() => item._table,
  DocxTableCell() => item._row,
  _ => null,
};

/// Records that [item] (a block, a row or a cell) is now in [parent] (`null`:
/// in nothing). Only the primitives call it.
void setParentOf(Object item, Object? parent) {
  switch (item) {
    case DocxBlock():
      item._container = parent;
    case DocxTableRow():
      item._table = parent as DocxTable?;
    case DocxTableCell():
      item._row = parent as DocxTableRow?;
  }
}

/// An opaque block for the element [xml] captured.
DocxOpaqueBlock opaqueBlock(OpaqueXml xml) => DocxOpaqueBlock._(xml);

/// The element [block] keeps, for the writer.
OpaqueXml opaqueBlockXml(DocxOpaqueBlock block) => block._xml;
