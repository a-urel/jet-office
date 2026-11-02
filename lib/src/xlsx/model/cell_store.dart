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
/// per-store string pool and the double holds its pool index. The formula,
/// inline string, unknown `t` text, kept attributes and other children are
/// rare: they live in a map keyed by position, and a flag in the packed word
/// says whether a cell has an entry.
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
  _Extras(
    this.formula,
    this.inline,
    this.typeText,
    this.attributes,
    this.extraChildren,
  );

  final RawFormula? formula;
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
    final int capacity = _grown(words.length, cellsNeeded);
    words = Int32List(capacity)..setRange(0, cellCount, words);
    styles = Int32List(capacity)..setRange(0, cellCount, styles);
    values = Float64List(capacity)..setRange(0, cellCount, values);
  }

  /// Drops the spare capacity.
  void trim() {
    if (rows.length != rowCount) {
      rows = Int32List(rowCount)..setRange(0, rowCount, rows);
      rowStart = Int32List(rowCount + 1)..setRange(0, rowCount + 1, rowStart);
    }
    if (words.length != cellCount) {
      words = Int32List(cellCount)..setRange(0, cellCount, words);
      styles = Int32List(cellCount)..setRange(0, cellCount, styles);
      values = Float64List(cellCount)..setRange(0, cellCount, values);
    }
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

  /// Inserts a cell at cell position [at] of row position [r].
  void insertCell(int r, int at, int word, int style, double value) {
    ensureCells(cellCount + 1);
    words.setRange(at + 1, cellCount + 1, words, at);
    styles.setRange(at + 1, cellCount + 1, styles, at);
    values.setRange(at + 1, cellCount + 1, values, at);
    words[at] = word;
    styles[at] = style;
    values[at] = value;
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

  /// The rare parts of cells, keyed by `row * XlsxLimits.maxColumns +
  /// column`.
  final Map<int, _Extras> _extras = <int, _Extras>{};

  final Map<int, List<KeptAttribute>> _rowAttributes =
      <int, List<KeptAttribute>>{};

  /// The last row attributes stored; an equal list is stored as this one,
  /// so a file that gives every row the same attributes keeps one list.
  List<KeptAttribute>? _lastRowAttributes;

  final List<String> _strings = <String>[];
  final Map<String, int> _stringIndexes = <String, int>{};

  int _cellCount = 0;
  int _formulaCount = 0;

  /// The number of cells, styled empty cells included.
  int get cellCount => _cellCount;

  /// Whether any cell has a formula.
  bool get hasFormulas => _formulaCount > 0;

  /// The present rows, ascending: every row with a cell or row attributes.
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
        cell.formula != null ||
        cell.inline != null ||
        cell.typeText != null ||
        cell.attributes.isNotEmpty ||
        cell.extraChildren.isNotEmpty;
    if (hasExtras) word |= _extrasFlag;
    final int styleWord = style ?? -1;

    if (!_appendFast(row, column, word, styleWord, number)) {
      _insert(row, column, word, styleWord, number);
    }
    if (hasExtras) {
      _extras[_key(row, column)] = _Extras(
        cell.formula,
        cell.inline,
        cell.typeText,
        cell.attributes,
        cell.extraChildren,
      );
      if (cell.formula != null) _formulaCount++;
    }
  }

  /// Removes the cell at [row] and [column], and returns whether there was
  /// one.
  ///
  /// A row left without cells stays while it has row attributes.
  bool remove(int row, int column) {
    _checkCell(row, column);
    final int bi = _blockFor(row);
    if (bi < 0) return false;
    final _Block b = _blocks[bi];
    final int r = b.findRow(row);
    if (r < 0) return false;
    final int at = b.findCell(r, column);
    if (at < 0) return false;
    _dropExtras(b.words[at], row, column);
    b.removeCell(r, at);
    _cellCount--;
    if (b.rowStart[r] == b.rowStart[r + 1] &&
        !_rowAttributes.containsKey(row)) {
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
      if (_rowAttributes.remove(row) == null) return;
      final int bi = _blockFor(row);
      if (bi < 0) return;
      final _Block b = _blocks[bi];
      final int r = b.findRow(row);
      if (r >= 0 && b.rowStart[r] == b.rowStart[r + 1]) _removeRow(bi, r);
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
    if (word & _extrasFlag == 0) {
      return RawCell(kind: kind, style: s < 0 ? null : s, value: value);
    }
    final _Extras e = _extras[_key(row, column)]!;
    return RawCell(
      kind: kind,
      style: s < 0 ? null : s,
      value: value,
      formula: e.formula,
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

  void _dropExtras(int word, int row, int column) {
    if (word & _extrasFlag == 0) return;
    final _Extras? old = _extras.remove(_key(row, column));
    if (old?.formula != null) _formulaCount--;
  }

  // ---------------------------------------------------------------------
  // Placement.

  /// Appends the cell when it goes after the last one, and returns whether
  /// it did.
  bool _appendFast(int row, int column, int word, int style, double value) {
    if (_blocks.isEmpty) {
      final _Block b = _Block(8, 8);
      _blocks.add(b);
      _appendRow(b, row);
      _appendCell(b, word, style, value);
      return true;
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
        return false;
      }
    } else {
      return false;
    }
    _appendCell(b, word, style, value);
    return true;
  }

  void _appendRow(_Block b, int row) {
    b.ensureRows(b.rowCount + 1);
    b.rows[b.rowCount] = row;
    b.rowStart[b.rowCount + 1] = b.cellCount;
    b.rowCount++;
  }

  void _appendCell(_Block b, int word, int style, double value) {
    b.ensureCells(b.cellCount + 1);
    b.words[b.cellCount] = word;
    b.styles[b.cellCount] = style;
    b.values[b.cellCount] = value;
    b.cellCount++;
    b.rowStart[b.rowCount] = b.cellCount;
    _cellCount++;
  }

  /// Puts the cell anywhere, replacing a cell already at its place.
  void _insert(int row, int column, int word, int style, double value) {
    final int bi = _ensureRow(row);
    final _Block b = _blocks[bi];
    final int r = b.findRow(row);
    final int at = b.findCell(r, column);
    if (at >= 0) {
      _dropExtras(b.words[at], row, column);
      b.words[at] = word;
      b.styles[at] = style;
      b.values[at] = value;
      return;
    }
    b.insertCell(r, -at - 1, word, style, value);
    _cellCount++;
    _splitIfLarge(bi);
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
