/// The compact store of a loaded worksheet's cells.
///
/// Not ported from Quds; written for jet_office.
///
/// A loaded sheet must not cost one Dart object per cell (spec §4.5): a
/// 100,000 × 12 sheet has to open, change and save in a browser, and its
/// store should take less memory than its sheet XML did. [CellStore] keeps
/// cells in typed arrays and builds a [RawCell] only when one is asked for
/// ([CellStore.cellAt], [CellStore.forEachInRow]); [CellStore.put] takes a
/// [RawCell] apart and keeps nothing of it but its rare parts.
///
/// Layout. Rows are kept in ascending order, split into blocks of about
/// [_blockTarget] cells and rows. A block holds, in compressed-row form:
///
/// - per row: its index and the position of its first cell (two `Int32List`
///   entries, 8 bytes);
/// - per cell: a packed word of column, kind and flags (`Int32List`), the
///   style index or `-1` (`Int32List`) and the value (`Float64List`): 16
///   bytes.
///
/// A value is stored as a double when its text is exactly what
/// [formatXmlDouble] prints for that double, so it comes back as written
/// (`'0.1'` stays `'0.1'`; `'1.50'` and `'1e5'` do not qualify). Shared
/// string indexes and booleans qualify too. Any other text goes into a
/// per-store string pool and the double holds its pool index.
///
/// Formulas can be on every cell, so they cost no object per cell either. A
/// formula is split into its template (type, `ref`, `si` and attributes:
/// everything but the text), interned, and its text. The store keeps a
/// table of formula entries, each a template and a text range in one
/// code-unit buffer (8 bytes plus the text). A formula without text (a
/// shared formula's follower) uses its template's one textless entry, so
/// every follower of a group shares one entry; a formula equal to the entry
/// added last reuses it too. A block that holds a formula gets one more
/// `Int32List` entry per cell, the formula entry (4 bytes); a block without
/// formulas has none.
///
/// The inline string, unknown `t` text, kept attributes and other children
/// are rare: they live in a map keyed by position, and a flag in the packed
/// word says whether a cell has an entry.
///
/// Rows come from the reader in ascending order with ascending columns, so
/// loading only appends: [CellStore.put] has a fast path for a cell after
/// the last one, and a block that fills up is trimmed to its exact size
/// before the next one starts. Any other put inserts into its block, which
/// shifts at most one block's entries, and a block that grows past twice
/// the target is split.
///
/// Only typed lists dart2js supports are used (no `Int64List`), so the
/// store behaves the same on the VM and on the web.
library;

import 'dart:typed_data';

import '../../opc/opaque_xml.dart';
import '../../xml/xml_number.dart';
import '../limits.dart';
import '../raw_cell.dart';

// The packed word of a cell: bits 0 to 2 are the kind, bits 3 and 4 how the
// value is stored, bit 5 whether the cell has rare parts, and the bits from
// 6 up the column.
const int _kindMask = 0x7;
const int _valueShift = 3;
const int _valueMask = 0x3;
const int _valueNone = 0;
const int _valueDouble = 1;
const int _valuePooled = 2;
const int _extrasFlag = 0x20;
const int _columnShift = 6;

/// The number of cells plus rows a block aims at. A block is split when it
/// holds more than twice this, and on load a new block starts once the
/// last one reaches it.
const int _blockTarget = 4096;

/// The rare parts of a cell, kept outside the typed arrays.
final class _Extras {
  _Extras(this.inline, this.typeText, this.attributes, this.extraChildren);

  final OpaqueXml? inline;
  final String? typeText;
  final List<KeptAttribute> attributes;
  final List<OpaqueXml> extraChildren;
}

/// A run of consecutive rows in compressed-row form.
///
/// Row `i` of the block is [rows]`[i]` and owns the cells from
/// [rowStart]`[i]` up to [rowStart]`[i + 1]`, in ascending column order.
/// The lists may be longer than [rowCount] and [cellCount]; the rest is
/// spare capacity.
///
/// [formulas] is `null` until the block holds a formula; then it is as long
/// as [words], and a cell's entry is the index of its formula entry plus
/// one, `0` without a formula.
final class _Block {
  _Block(int rowCapacity, int cellCapacity)
    : rows = Int32List(rowCapacity),
      rowStart = Int32List(rowCapacity + 1),
      words = Int32List(cellCapacity),
      styles = Int32List(cellCapacity),
      values = Float64List(cellCapacity);

  Int32List rows;
  Int32List rowStart;
  Int32List words;
  Int32List styles;
  Float64List values;
  Int32List? formulas;
  int rowCount = 0;
  int cellCount = 0;

  int get firstRow => rows[0];
  int get lastRow => rows[rowCount - 1];

  /// The position of [row] in this block, or `-(insertion point) - 1`.
  int findRow(int row) {
    int lo = 0;
    int hi = rowCount - 1;
    while (lo <= hi) {
      final int mid = (lo + hi) >> 1;
      final int r = rows[mid];
      if (r < row) {
        lo = mid + 1;
      } else if (r > row) {
        hi = mid - 1;
      } else {
        return mid;
      }
    }
    return -lo - 1;
  }

  /// The cell position of [column] in row position [r], or
  /// `-(insertion point) - 1`.
  int findCell(int r, int column) {
    int lo = rowStart[r];
    int hi = rowStart[r + 1] - 1;
    while (lo <= hi) {
      final int mid = (lo + hi) >> 1;
      final int c = words[mid] >> _columnShift;
      if (c < column) {
        lo = mid + 1;
      } else if (c > column) {
        hi = mid - 1;
      } else {
        return mid;
      }
    }
    return -lo - 1;
  }

  /// Makes room for at least [rowsNeeded] rows.
  void ensureRows(int rowsNeeded) {
    if (rowsNeeded <= rows.length) return;
    final int capacity = _grown(rows.length, rowsNeeded);
    rows = Int32List(capacity)..setRange(0, rowCount, rows);
    rowStart = Int32List(capacity + 1)..setRange(0, rowCount + 1, rowStart);
  }

  /// Makes room for at least [cellsNeeded] cells.
  void ensureCells(int cellsNeeded) {
    if (cellsNeeded <= words.length) return;
    _resizeCells(_grown(words.length, cellsNeeded));
  }

  /// Gives the block its formula list, when it has none, and returns it.
  Int32List ensureFormulas() => formulas ??= Int32List(words.length);

  /// Reallocates the cell lists to [capacity], keeping the cells.
  void _resizeCells(int capacity) {
    words = Int32List(capacity)..setRange(0, cellCount, words);
    styles = Int32List(capacity)..setRange(0, cellCount, styles);
    values = Float64List(capacity)..setRange(0, cellCount, values);
    final Int32List? f = formulas;
    if (f != null) formulas = Int32List(capacity)..setRange(0, cellCount, f);
  }

  /// Drops the spare capacity.
  void trim() {
    if (rows.length != rowCount) {
      rows = Int32List(rowCount)..setRange(0, rowCount, rows);
      rowStart = Int32List(rowCount + 1)..setRange(0, rowCount + 1, rowStart);
    }
    if (words.length != cellCount) _resizeCells(cellCount);
  }

  /// Inserts an empty row [row] at row position [r].
  void insertRow(int r, int row) {
    ensureRows(rowCount + 1);
    rows.setRange(r + 1, rowCount + 1, rows, r);
    rowStart.setRange(r + 1, rowCount + 2, rowStart, r);
    rows[r] = row;
    rowCount++;
  }

  /// Removes the row at row position [r], which has no cells.
  void removeRow(int r) {
    rows.setRange(r, rowCount - 1, rows, r + 1);
    rowStart.setRange(r + 1, rowCount, rowStart, r + 2);
    rowCount--;
  }

  /// Inserts a cell at cell position [at] of row position [r], without a
  /// formula.
  void insertCell(int r, int at, int word, int style, double value) {
    ensureCells(cellCount + 1);
    words.setRange(at + 1, cellCount + 1, words, at);
    styles.setRange(at + 1, cellCount + 1, styles, at);
    values.setRange(at + 1, cellCount + 1, values, at);
    words[at] = word;
    styles[at] = style;
    values[at] = value;
    final Int32List? f = formulas;
    if (f != null) {
      f.setRange(at + 1, cellCount + 1, f, at);
      f[at] = 0;
    }
    cellCount++;
    for (int i = r + 1; i <= rowCount; i++) {
      rowStart[i]++;
    }
  }

  /// Removes the cell at cell position [at] of row position [r].
  void removeCell(int r, int at) {
    words.setRange(at, cellCount - 1, words, at + 1);
    styles.setRange(at, cellCount - 1, styles, at + 1);
    values.setRange(at, cellCount - 1, values, at + 1);
    final Int32List? f = formulas;
    if (f != null) {
      f.setRange(at, cellCount - 1, f, at + 1);
      f[cellCount - 1] = 0;
    }
    cellCount--;
    for (int i = r + 1; i <= rowCount; i++) {
      rowStart[i]--;
    }
  }

  /// Moves the rows from row position [r] on into a new block, which it
  /// returns, and trims both.
  _Block splitAt(int r) {
    final int movedRows = rowCount - r;
    final int firstCell = rowStart[r];
    final int movedCells = cellCount - firstCell;
    final _Block tail = _Block(movedRows, movedCells)
      ..rows.setRange(0, movedRows, rows, r)
      ..words.setRange(0, movedCells, words, firstCell)
      ..styles.setRange(0, movedCells, styles, firstCell)
      ..values.setRange(0, movedCells, values, firstCell)
      ..rowCount = movedRows
      ..cellCount = movedCells;
    final Int32List? f = formulas;
    if (f != null) {
      tail.ensureFormulas().setRange(0, movedCells, f, firstCell);
    }
    for (int i = 0; i <= movedRows; i++) {
      tail.rowStart[i] = rowStart[r + i] - firstCell;
    }
    rowCount = r;
    cellCount = firstCell;
    trim();
    return tail;
  }

  static int _grown(int current, int needed) {
    int capacity = current < 8 ? 8 : current * 2;
    if (capacity < needed) capacity = needed;
    return capacity;
  }
}

/// The cells and row attributes of one loaded worksheet, without an object
/// per cell.
///
/// Rows and columns are 0-based and must lie inside the sheet
/// ([XlsxLimits.maxRows], [XlsxLimits.maxColumns]); any method given one
/// outside throws a [RangeError]. A row is present while it has a cell or
/// row attributes, so a hidden row without cells is kept.
///
/// The store does not copy the lists inside a [RawCell] it is given (its
/// formula, attributes and other children); it keeps them and returns them
/// as they are. The string pool behind values that are not plain doubles
/// only grows: a removed or replaced cell's text stays pooled.
///
/// Changing the store while [rowIndexes] or [forEachInRow] iterates it is
/// not supported.
final class CellStore {
  /// An empty store.
  CellStore();

  final List<_Block> _blocks = <_Block>[];

  /// The number of recorded edits that changed a cell's value or formula
  /// and are applied now: `SetCellChange` adds one when it is applied and
  /// takes it back when it is reverted (a rolled-back transaction, an
  /// undo). A style-only edit does not count. A save recalculates when any
  /// sheet's count is above 0.
  int valueEdits = 0;

  /// The rare parts of cells, keyed by `row * XlsxLimits.maxColumns +
  /// column`.
  final Map<int, _Extras> _extras = <int, _Extras>{};

  /// The formula templates (formulas without their text), by index, and
  /// the index of each by its key.
  final List<RawFormula> _templates = <RawFormula>[];
  final Map<Object, int> _templateIndexes = <Object, int>{};

  /// The formula entries. Entry `i` has the template
  /// `_entryTemplates[i] >> 1`, and text when bit 0 is set: the UTF-16
  /// code units `_textUnits[_entryStarts[i]]` up to
  /// `_textUnits[_entryStarts[i + 1]]`.
  Int32List _entryTemplates = Int32List(0);
  Int32List _entryStarts = Int32List(0);
  int _entryCount = 0;
  Uint16List _textUnits = Uint16List(0);
  int _textUnitCount = 0;

  /// The textless entry of each template that has one, by template index.
  final Map<int, int> _textlessEntries = <int, int>{};

  final Map<int, List<KeptAttribute>> _rowAttributes =
      <int, List<KeptAttribute>>{};

  /// The children of rows other than cells (an `extLst`, say), by row.
  final Map<int, List<OpaqueXml>> _rowChildren = <int, List<OpaqueXml>>{};

  /// The formulas that define a group (array, data table, shared with a
  /// `ref`), keyed like [_extras].
  final Map<int, RawFormula> _groupMasters = <int, RawFormula>{};

  /// The last row attributes stored; an equal list is stored as this one,
  /// so a file that gives every row the same attributes keeps one list.
  List<KeptAttribute>? _lastRowAttributes;

  final List<String> _strings = <String>[];
  final Map<String, int> _stringIndexes = <String, int>{};

  int _cellCount = 0;
  int _formulaCount = 0;

  /// The number of cells, styled empty cells included.
  int get cellCount => _cellCount;

  /// An estimate of the memory the store retains, in bytes, for benchmarks.
  ///
  /// The sum of the typed lists' `lengthInBytes` (spare capacity included:
  /// the cells, their formula references, the formula entries and the
  /// formula text buffer), two bytes for each UTF-16 unit of the pooled
  /// strings, and a constant per map entry that stands for the entry and
  /// the object it holds: 96 bytes for each cell with extras, 48 for each
  /// pooled string, row with attributes or children, group master and
  /// template's textless formula entry. A formula template counts
  /// 96 bytes (its object and its interning entry) plus 48 per attribute
  /// and two per UTF-16 unit of its `ref`, `si` and attributes; a group
  /// master's formula text counts two bytes per unit. The objects the other
  /// entries point to (kept attributes, opaque XML) are not counted. It
  /// does not depend on the platform, unlike a reading of the process's
  /// memory, so it is the figure to compare with the sheet's XML.
  int get retainedBytesEstimate {
    int bytes =
        _textUnits.lengthInBytes +
        _entryTemplates.lengthInBytes +
        _entryStarts.lengthInBytes +
        48 * _textlessEntries.length;
    for (final _Block b in _blocks) {
      bytes +=
          b.rows.lengthInBytes +
          b.rowStart.lengthInBytes +
          b.words.lengthInBytes +
          b.styles.lengthInBytes +
          b.values.lengthInBytes +
          (b.formulas?.lengthInBytes ?? 0);
    }
    for (final String text in _strings) {
      bytes += 2 * text.length + 48;
    }
    for (final RawFormula t in _templates) {
      bytes += 96 + 2 * ((t.ref?.length ?? 0) + (t.si?.length ?? 0));
      for (final KeptAttribute a in t.attributes) {
        bytes += 48 + 2 * (a.qualifiedName.length + a.value.length);
      }
    }
    for (final RawFormula f in _groupMasters.values) {
      bytes += 2 * (f.text?.length ?? 0);
    }
    return bytes +
        96 * _extras.length +
        48 *
            (_rowAttributes.length +
                _rowChildren.length +
                _groupMasters.length);
  }

  /// Drops the spare capacity of the last block and of the formula text
  /// buffer; the store stays usable. Called once a sheet has loaded.
  void trim() {
    if (_blocks.isNotEmpty) _blocks.last.trim();
    if (_textUnits.length != _textUnitCount) {
      _textUnits = Uint16List(_textUnitCount)
        ..setRange(0, _textUnitCount, _textUnits);
    }
    if (_entryCount > 0 && _entryTemplates.length != _entryCount) {
      _entryTemplates = Int32List(_entryCount)
        ..setRange(0, _entryCount, _entryTemplates);
      _entryStarts = Int32List(_entryCount + 1)
        ..setRange(0, _entryCount + 1, _entryStarts);
    }
  }

  /// Whether any cell has a formula.
  bool get hasFormulas => _formulaCount > 0;

  /// The cells whose formula defines a group: an array or data-table
  /// formula, or a shared formula with a `ref` (a shared master), in no
  /// particular order.
  ///
  /// Kept up to date by [put] and [remove], so finding a cell's group costs
  /// time in proportion to the number of groups, not of cells.
  Iterable<({int row, int column, RawFormula formula})> get groupMasters =>
      _groupMasters.entries.map(
        (MapEntry<int, RawFormula> e) => (
          row: e.key ~/ XlsxLimits.maxColumns,
          column: e.key % XlsxLimits.maxColumns,
          formula: e.value,
        ),
      );

  /// The number of cells of [kind]. Takes time in proportion to the number
  /// of cells.
  int countOf(RawCellKind kind) {
    int n = 0;
    for (final _Block b in _blocks) {
      for (int at = 0; at < b.cellCount; at++) {
        if (b.words[at] & _kindMask == kind.index) n++;
      }
    }
    return n;
  }

  /// The present rows, ascending: every row with a cell, row attributes or
  /// row children.
  Iterable<int> get rowIndexes sync* {
    for (final _Block b in _blocks) {
      for (int i = 0; i < b.rowCount; i++) {
        yield b.rows[i];
      }
    }
  }

  /// The smallest range holding every cell, or `null` without cells.
  ///
  /// Rows that only have attributes do not count. Takes time in proportion
  /// to the number of rows.
  ({int firstRow, int lastRow, int firstColumn, int lastColumn})? get bounds {
    if (_cellCount == 0) return null;
    int firstRow = -1;
    int lastRow = -1;
    int firstColumn = XlsxLimits.maxColumns;
    int lastColumn = -1;
    for (final _Block b in _blocks) {
      for (int i = 0; i < b.rowCount; i++) {
        final int start = b.rowStart[i];
        final int end = b.rowStart[i + 1];
        if (start == end) continue;
        if (firstRow < 0) firstRow = b.rows[i];
        lastRow = b.rows[i];
        final int first = b.words[start] >> _columnShift;
        final int last = b.words[end - 1] >> _columnShift;
        if (first < firstColumn) firstColumn = first;
        if (last > lastColumn) lastColumn = last;
      }
    }
    return (
      firstRow: firstRow,
      lastRow: lastRow,
      firstColumn: firstColumn,
      lastColumn: lastColumn,
    );
  }

  /// The cell at [row] and [column], built on each call, or `null` when
  /// there is none.
  RawCell? cellAt(int row, int column) {
    _checkCell(row, column);
    final int bi = _blockFor(row);
    if (bi < 0) return null;
    final _Block b = _blocks[bi];
    final int r = b.findRow(row);
    if (r < 0) return null;
    final int at = b.findCell(r, column);
    if (at < 0) return null;
    return _build(b, at, row, column);
  }

  /// Calls [f] with each cell of [row], in ascending column order.
  void forEachInRow(int row, void Function(int column, RawCell cell) f) {
    _checkRow(row);
    final int bi = _blockFor(row);
    if (bi < 0) return;
    final _Block b = _blocks[bi];
    final int r = b.findRow(row);
    if (r < 0) return;
    final int end = b.rowStart[r + 1];
    for (int at = b.rowStart[r]; at < end; at++) {
      final int column = b.words[at] >> _columnShift;
      f(column, _build(b, at, row, column));
    }
  }

  /// Stores [cell] at [row] and [column], replacing any cell there.
  ///
  /// The cell's formula is kept as its template and text, so [cellAt]
  /// returns an equal formula, not necessarily the same object.
  ///
  /// Throws a [RangeError] when [row] or [column] is outside the sheet or
  /// the cell's style is negative.
  void put(int row, int column, RawCell cell) {
    _checkCell(row, column);
    final int? style = cell.style;
    if (style != null) {
      RangeError.checkValueInInterval(style, 0, 0x7FFFFFFF, 'cell.style');
    }
    int word = (column << _columnShift) | cell.kind.index;
    double number = 0;
    final String? value = cell.value;
    if (value != null) {
      final double? d = double.tryParse(value);
      if (d != null && d.isFinite && formatXmlDouble(d) == value) {
        word |= _valueDouble << _valueShift;
        number = d;
      } else {
        word |= _valuePooled << _valueShift;
        number = _pool(value).toDouble();
      }
    }
    final bool hasExtras =
        cell.inline != null ||
        cell.typeText != null ||
        cell.attributes.isNotEmpty ||
        cell.extraChildren.isNotEmpty;
    if (hasExtras) word |= _extrasFlag;
    final int styleWord = style ?? -1;

    final (_Block b, int at) =
        _appendFast(row, column, word, styleWord, number) ??
        _insert(row, column, word, styleWord, number);
    if (hasExtras) {
      _extras[_key(row, column)] = _Extras(
        cell.inline,
        cell.typeText,
        cell.attributes,
        cell.extraChildren,
      );
    }
    final RawFormula? formula = cell.formula;
    if (formula != null) {
      b.ensureFormulas()[at] = _entryFor(formula) + 1;
      _formulaCount++;
      if (_definesGroup(formula)) {
        _groupMasters[_key(row, column)] = formula;
      }
    }
  }

  static bool _definesGroup(RawFormula f) => switch (f.type) {
    FormulaType.array || FormulaType.dataTable => true,
    FormulaType.shared => f.ref != null,
    FormulaType.normal => false,
  };

  /// Removes the cell at [row] and [column], and returns whether there was
  /// one.
  ///
  /// A row left without cells stays while it has row attributes or row
  /// children.
  bool remove(int row, int column) {
    _checkCell(row, column);
    final int bi = _blockFor(row);
    if (bi < 0) return false;
    final _Block b = _blocks[bi];
    final int r = b.findRow(row);
    if (r < 0) return false;
    final int at = b.findCell(r, column);
    if (at < 0) return false;
    _dropCellData(b, at, row, column);
    b.removeCell(r, at);
    _cellCount--;
    if (b.rowStart[r] == b.rowStart[r + 1] && !_hasRowExtras(row)) {
      _removeRow(bi, r);
    }
    return true;
  }

  /// The attributes of [row]'s `<row>` (all but `r` and `spans`), in source
  /// order; empty when it has none.
  List<KeptAttribute> rowAttributes(int row) {
    _checkRow(row);
    return _rowAttributes[row] ?? const <KeptAttribute>[];
  }

  /// Sets the attributes of [row]'s `<row>`.
  ///
  /// A row with attributes is present even without cells. Setting none
  /// removes a row that has no cells.
  void setRowAttributes(int row, List<KeptAttribute> attributes) {
    _checkRow(row);
    if (attributes.isEmpty) {
      if (_rowAttributes.remove(row) != null) _dropBareRow(row);
      return;
    }
    final List<KeptAttribute>? last = _lastRowAttributes;
    final List<KeptAttribute> kept;
    if (last != null && _sameAttributes(last, attributes)) {
      kept = last;
    } else {
      kept = List<KeptAttribute>.unmodifiable(attributes);
      _lastRowAttributes = kept;
    }
    _rowAttributes[row] = kept;
    _ensureRow(row);
  }

  /// The children of [row]'s `<row>` other than cells, in source order;
  /// empty when it has none.
  List<OpaqueXml> rowChildren(int row) {
    _checkRow(row);
    return _rowChildren[row] ?? const <OpaqueXml>[];
  }

  /// Sets the children of [row]'s `<row>` other than cells, written after
  /// its cells.
  ///
  /// A row with children is present even without cells. Setting none
  /// removes a row that has no cells and no attributes.
  void setRowChildren(int row, List<OpaqueXml> children) {
    _checkRow(row);
    if (children.isEmpty) {
      if (_rowChildren.remove(row) != null) _dropBareRow(row);
      return;
    }
    _rowChildren[row] = List<OpaqueXml>.unmodifiable(children);
    _ensureRow(row);
  }

  bool _hasRowExtras(int row) =>
      _rowAttributes.containsKey(row) || _rowChildren.containsKey(row);

  /// Removes [row] when it has no cells, attributes or children.
  void _dropBareRow(int row) {
    if (_hasRowExtras(row)) return;
    final int bi = _blockFor(row);
    if (bi < 0) return;
    final _Block b = _blocks[bi];
    final int r = b.findRow(row);
    if (r >= 0 && b.rowStart[r] == b.rowStart[r + 1]) _removeRow(bi, r);
  }

  // ---------------------------------------------------------------------
  // Building and taking apart.

  RawCell _build(_Block b, int at, int row, int column) {
    final int word = b.words[at];
    final int s = b.styles[at];
    final String? value = switch ((word >> _valueShift) & _valueMask) {
      _valueNone => null,
      _valueDouble => formatXmlDouble(b.values[at]),
      _ => _strings[b.values[at].toInt()],
    };
    final RawCellKind kind = RawCellKind.values[word & _kindMask];
    final RawFormula? formula = _formulaAt(b, at);
    if (word & _extrasFlag == 0) {
      return RawCell(
        kind: kind,
        style: s < 0 ? null : s,
        value: value,
        formula: formula,
      );
    }
    final _Extras e = _extras[_key(row, column)]!;
    return RawCell(
      kind: kind,
      style: s < 0 ? null : s,
      value: value,
      formula: formula,
      inline: e.inline,
      typeText: e.typeText,
      attributes: e.attributes,
      extraChildren: e.extraChildren,
    );
  }

  int _pool(String text) {
    final int? known = _stringIndexes[text];
    if (known != null) return known;
    final int index = _strings.length;
    _strings.add(text);
    _stringIndexes[text] = index;
    return index;
  }

  /// The formula of the cell at position [at] of [b], or `null`.
  RawFormula? _formulaAt(_Block b, int at) {
    final Int32List? formulas = b.formulas;
    if (formulas == null) return null;
    final int e = formulas[at] - 1;
    if (e < 0) return null;
    final int t = _entryTemplates[e];
    final RawFormula template = _templates[t >> 1];
    if (t & 1 == 0) return template;
    return RawFormula(
      type: template.type,
      text: String.fromCharCodes(
        _textUnits,
        _entryStarts[e],
        _entryStarts[e + 1],
      ),
      ref: template.ref,
      si: template.si,
      attributes: template.attributes,
    );
  }

  /// The index of the formula entry for [formula], added when needed.
  int _entryFor(RawFormula formula) {
    final int template = _intern(formula);
    final String? text = formula.text;
    if (text == null) {
      return _textlessEntries[template] ??= _addEntry(template << 1, '');
    }
    final int tagged = (template << 1) | 1;
    if (_entryCount > 0 && _entryTemplates[_entryCount - 1] == tagged) {
      final int start = _entryStarts[_entryCount - 1];
      final int n = text.length;
      if (_entryStarts[_entryCount] - start == n) {
        int i = 0;
        while (i < n && _textUnits[start + i] == text.codeUnitAt(i)) {
          i++;
        }
        if (i == n) return _entryCount - 1;
      }
    }
    return _addEntry(tagged, text);
  }

  /// Appends an entry of [tagged] template with [text], and returns its
  /// index.
  int _addEntry(int tagged, String text) {
    final int n = text.length;
    if (_textUnitCount + n > _textUnits.length) {
      final int capacity = _Block._grown(_textUnits.length, _textUnitCount + n);
      _textUnits = Uint16List(capacity)
        ..setRange(0, _textUnitCount, _textUnits);
    }
    for (int i = 0; i < n; i++) {
      _textUnits[_textUnitCount + i] = text.codeUnitAt(i);
    }
    _textUnitCount += n;
    if (_entryCount + 1 > _entryTemplates.length) {
      final int capacity = _Block._grown(
        _entryTemplates.length,
        _entryCount + 1,
      );
      _entryTemplates = Int32List(capacity)
        ..setRange(0, _entryCount, _entryTemplates);
      _entryStarts = Int32List(capacity + 1)
        ..setRange(0, _entryStarts.length, _entryStarts);
    }
    _entryTemplates[_entryCount] = tagged;
    _entryCount++;
    _entryStarts[_entryCount] = _textUnitCount;
    return _entryCount - 1;
  }

  /// The index of [formula]'s template, interned on first use.
  int _intern(RawFormula formula) {
    final Object key = _templateKey(formula);
    final int? known = _templateIndexes[key];
    if (known != null) return known;
    final int index = _templates.length;
    _templates.add(
      formula.text == null
          ? formula
          : RawFormula(
              type: formula.type,
              ref: formula.ref,
              si: formula.si,
              attributes: formula.attributes,
            ),
    );
    _templateIndexes[key] = index;
    return index;
  }

  /// A key equal for formulas whose templates are equal.
  static Object _templateKey(RawFormula f) {
    if (f.attributes.isEmpty) return (f.type, f.ref, f.si);
    final StringBuffer b = StringBuffer();
    for (final KeptAttribute a in f.attributes) {
      b
        ..write(a.qualifiedName)
        ..write('\u0000')
        ..write(a.namespaceUri)
        ..write('\u0000')
        ..write(a.value)
        ..write('\u0000');
    }
    return (f.type, f.ref, f.si, b.toString());
  }

  /// Forgets the extras and formula of the cell at position [at] of [b].
  void _dropCellData(_Block b, int at, int row, int column) {
    if (b.words[at] & _extrasFlag != 0) _extras.remove(_key(row, column));
    final Int32List? formulas = b.formulas;
    if (formulas != null && formulas[at] != 0) {
      formulas[at] = 0;
      _formulaCount--;
      _groupMasters.remove(_key(row, column));
    }
  }

  // ---------------------------------------------------------------------
  // Placement.

  /// Appends the cell when it goes after the last one, and returns its
  /// block and position; `null` when it does not go there.
  (_Block, int)? _appendFast(
    int row,
    int column,
    int word,
    int style,
    double value,
  ) {
    if (_blocks.isEmpty) {
      final _Block b = _Block(8, 8);
      _blocks.add(b);
      _appendRow(b, row);
      return (b, _appendCell(b, word, style, value));
    }
    _Block b = _blocks.last;
    final int last = b.lastRow;
    if (row > last) {
      if (b.cellCount + b.rowCount >= _blockTarget) {
        b.trim();
        b = _Block(8, 8);
        _blocks.add(b);
      }
      _appendRow(b, row);
    } else if (row == last) {
      final int end = b.rowStart[b.rowCount];
      if (end > b.rowStart[b.rowCount - 1] &&
          b.words[end - 1] >> _columnShift >= column) {
        return null;
      }
    } else {
      return null;
    }
    return (b, _appendCell(b, word, style, value));
  }

  void _appendRow(_Block b, int row) {
    b.ensureRows(b.rowCount + 1);
    b.rows[b.rowCount] = row;
    b.rowStart[b.rowCount + 1] = b.cellCount;
    b.rowCount++;
  }

  /// Appends a cell without a formula to [b], and returns its position.
  int _appendCell(_Block b, int word, int style, double value) {
    b.ensureCells(b.cellCount + 1);
    final int at = b.cellCount;
    b.words[at] = word;
    b.styles[at] = style;
    b.values[at] = value;
    // Spare capacity past the last cell holds no formula: removeCell and
    // splitAt leave it cleared.
    b.cellCount++;
    b.rowStart[b.rowCount] = b.cellCount;
    _cellCount++;
    return at;
  }

  /// Puts the cell anywhere, replacing a cell already at its place, and
  /// returns its block and position.
  (_Block, int) _insert(
    int row,
    int column,
    int word,
    int style,
    double value,
  ) {
    final int bi = _ensureRow(row);
    final _Block b = _blocks[bi];
    final int r = b.findRow(row);
    final int at = b.findCell(r, column);
    if (at >= 0) {
      _dropCellData(b, at, row, column);
      b.words[at] = word;
      b.styles[at] = style;
      b.values[at] = value;
      return (b, at);
    }
    b.insertCell(r, -at - 1, word, style, value);
    _cellCount++;
    _splitIfLarge(bi);
    return _locate(row, column);
  }

  /// The block and position of the cell at [row] and [column], which is
  /// present.
  (_Block, int) _locate(int row, int column) {
    final _Block b = _blocks[_blockFor(row)];
    return (b, b.findCell(b.findRow(row), column));
  }

  /// Makes [row] present, and returns the position of its block.
  int _ensureRow(int row) {
    if (_blocks.isEmpty) {
      final _Block b = _Block(8, 8);
      _blocks.add(b);
      _appendRow(b, row);
      return 0;
    }
    int bi = _blockFor(row);
    if (bi < 0) bi = 0;
    final _Block b = _blocks[bi];
    final int r = b.findRow(row);
    if (r < 0) {
      b.insertRow(-r - 1, row);
      _splitIfLarge(bi);
      // A split may have moved the row into the next block.
      if (bi + 1 < _blocks.length && _blocks[bi + 1].firstRow <= row) {
        return bi + 1;
      }
    }
    return bi;
  }

  void _removeRow(int bi, int r) {
    final _Block b = _blocks[bi];
    b.removeRow(r);
    if (b.rowCount == 0) _blocks.removeAt(bi);
  }

  /// Splits the block at [bi] in two when it holds more than twice the
  /// target, at the row where half its weight is reached.
  void _splitIfLarge(int bi) {
    final _Block b = _blocks[bi];
    final int weight = b.cellCount + b.rowCount;
    if (weight <= 2 * _blockTarget || b.rowCount < 2) return;
    int r = 1;
    while (r < b.rowCount - 1 && b.rowStart[r] + r < weight ~/ 2) {
      r++;
    }
    _blocks.insert(bi + 1, b.splitAt(r));
  }

  /// The position of the last block whose first row is at most [row], or
  /// `-1` when there is none.
  int _blockFor(int row) {
    int lo = 0;
    int hi = _blocks.length - 1;
    int found = -1;
    while (lo <= hi) {
      final int mid = (lo + hi) >> 1;
      if (_blocks[mid].firstRow <= row) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  static int _key(int row, int column) => row * XlsxLimits.maxColumns + column;

  static void _checkRow(int row) {
    RangeError.checkValueInInterval(row, 0, XlsxLimits.maxRows - 1, 'row');
  }

  static void _checkCell(int row, int column) {
    _checkRow(row);
    RangeError.checkValueInInterval(
      column,
      0,
      XlsxLimits.maxColumns - 1,
      'column',
    );
  }

  static bool _sameAttributes(List<KeptAttribute> a, List<KeptAttribute> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
