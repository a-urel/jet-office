/// Structured references (`Sales[Amount]`, `[@Qty]`,
/// `Sales[[#Headers],[A]:[B]]`): their parts, and the mappers that rename a
/// table or one of its columns and that turn the references of a removed
/// table into plain ranges, as Excel's "Convert to Range" does.
///
/// This file is new in jet_office; Quds has no equivalent.
library;

import '../cell_ref.dart';
import '../range.dart';
import 'formula_reference.dart';
import 'formula_rewrite.dart';

/// A table as its structured references see it.
final class StructuredTable {
  /// The table [name] on [sheet] over [range], with its [columns] in order.
  const StructuredTable({
    required this.sheet,
    required this.name,
    required this.range,
    required this.columns,
    required this.headerRow,
    required this.totalsRow,
  });

  /// The sheet the table is on.
  final String sheet;

  /// The table's name in formulas.
  final String name;

  /// The cells it covers, header and totals rows included.
  final XlsxRange range;

  /// The column names, the first for the range's first column.
  final List<String> columns;

  /// Whether the first row is a header row.
  final bool headerRow;

  /// Whether the last row is a totals row.
  final bool totalsRow;

  /// Whether [name] names this table, ignoring case.
  bool isNamed(String name) => name.toLowerCase() == this.name.toLowerCase();

  /// Whether the cell at [row], [column] (0-based) of [sheet] is inside it.
  bool contains(String sheet, int? row, int? column) =>
      row != null &&
      column != null &&
      sheet.toLowerCase() == this.sheet.toLowerCase() &&
      row >= range.firstRow &&
      row <= range.lastRow &&
      column >= range.firstColumn &&
      column <= range.lastColumn;

  /// The index of the column [name], ignoring case, or -1.
  int columnIndex(String name) {
    final String key = name.toLowerCase();
    for (int i = 0; i < columns.length; i++) {
      if (columns[i].toLowerCase() == key) return i;
    }
    return -1;
  }
}

/// A column name inside a structured reference: its name unescaped, and
/// where its text stands in the bracket span (`start` to `end`).
typedef StructuredColumn = ({String name, int start, int end, bool bare});

/// The parts of a structured reference's bracket span.
final class StructuredSpec {
  StructuredSpec._(this.thisRow, this.items, this.columns);

  /// Whether it names the formula's own row (`@` or `#This Row`).
  final bool thisRow;

  /// The special items it names, lower case: `#all`, `#data`, `#headers`,
  /// `#totals`.
  final Set<String> items;

  /// The columns: none (every column), one, or the two ends of a range.
  final List<StructuredColumn> columns;
}

const Set<String> _items = <String>{'#all', '#data', '#headers', '#totals'};

/// Reads [spec], a bracket span such as `[Amount]`, `[@Qty]` or
/// `[[#Headers],[A]:[B]]`; `null` for a span it cannot read.
StructuredSpec? parseStructuredSpec(String spec) {
  if (spec.length < 2 || !spec.startsWith('[') || !spec.endsWith(']')) {
    return null;
  }
  bool thisRow = false;
  final Set<String> items = <String>{};
  final List<StructuredColumn> columns = <StructuredColumn>[];
  final int end = spec.length - 1;
  int i = _skipSpaces(spec, 1, end);
  if (i == end) return StructuredSpec._(false, items, columns);
  if (spec[i] == '@') {
    thisRow = true;
    i = _skipSpaces(spec, i + 1, end);
    if (i == end) return StructuredSpec._(true, items, columns);
    if (spec[i] != '[') {
      columns.add(_bare(spec, i, end));
      return StructuredSpec._(true, items, columns);
    }
  } else if (spec[i] != '[') {
    final String body = spec.substring(1, end);
    if (body.trimLeft().startsWith('#')) {
      final String item = body.trim().toLowerCase();
      if (item == '#this row') return StructuredSpec._(true, items, columns);
      if (!_items.contains(item)) return null;
      return StructuredSpec._(false, items..add(item), columns);
    }
    columns.add(_bare(spec, 1, end));
    return StructuredSpec._(false, items, columns);
  }
  // A list of bracketed items, a column item perhaps the start of a range.
  bool expectItem = true;
  bool range = false;
  while (i < end) {
    if (!expectItem) {
      if (spec[i] == ',') {
        expectItem = true;
      } else if (spec[i] == ':' && columns.isNotEmpty && !range) {
        expectItem = true;
        range = true;
      } else {
        return null;
      }
      i = _skipSpaces(spec, i + 1, end);
      continue;
    }
    if (spec[i] != '[') return null;
    final int close = _close(spec, i + 1, end);
    if (close < 0) return null;
    final String raw = spec.substring(i + 1, close);
    if (raw.startsWith('#')) {
      if (range) return null;
      final String item = raw.trim().toLowerCase();
      if (item == '#this row') {
        thisRow = true;
      } else if (_items.contains(item)) {
        items.add(item);
      } else {
        return null;
      }
    } else {
      if (range ? columns.length != 1 : columns.isNotEmpty) return null;
      columns.add((
        name: _unescape(raw),
        start: i + 1,
        end: close,
        bare: false,
      ));
    }
    expectItem = false;
    i = _skipSpaces(spec, close + 1, end);
  }
  if (expectItem) return null;
  return StructuredSpec._(thisRow, items, columns);
}

int _skipSpaces(String s, int i, int end) {
  while (i < end && s[i] == ' ') {
    i++;
  }
  return i;
}

/// The index of the `]` closing an item that opens before [from], `'`
/// escaping the next character; -1 when none does before [end].
int _close(String s, int from, int end) {
  for (int i = from; i < end; i++) {
    if (s[i] == "'") {
      i++;
    } else if (s[i] == '[') {
      return -1;
    } else if (s[i] == ']') {
      return i;
    }
  }
  return -1;
}

StructuredColumn _bare(String spec, int start, int end) => (
  name: _unescape(spec.substring(start, end)),
  start: start,
  end: end,
  bare: true,
);

String _unescape(String raw) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < raw.length; i++) {
    if (raw[i] == "'" && i + 1 < raw.length) i++;
    out.write(raw[i]);
  }
  return out.toString();
}

/// [name] escaped as a column name of a structured reference: `'` before
/// each `[`, `]`, `#` and `'`.
String escapeStructuredColumn(String name) =>
    name.replaceAllMapped(RegExp(r"[\[\]#']"), (Match m) => "'${m[0]}");

/// A mapper that sees where the formula it rewrites lives: the cell at
/// `row`, `column` (0-based) of the host sheet, or `null` when the formula
/// has no cell (a defined name, a rule).
abstract interface class PositionedStructuredMapper implements ReferenceMapper {
  /// As [ReferenceMapper.mapStructured], for a formula at [row], [column].
  String? mapStructuredAt(
    String table,
    String spec,
    String hostSheet,
    int? row,
    int? column,
  );
}

/// The table [table] renamed to [newName] and, or, its column [oldColumn]
/// renamed to [newColumn]: every structured reference to it follows, and
/// an unqualified one (`[@Qty]`) inside the table too.
final class StructuredRename implements PositionedStructuredMapper {
  /// The rename; [newName] `null` keeps the table's name, [oldColumn] `null`
  /// every column's.
  StructuredRename(this.table, {this.newName, this.oldColumn, this.newColumn});

  /// The table before the rename.
  final StructuredTable table;

  /// The table's new name, or `null`.
  final String? newName;

  /// The column renamed, or `null`.
  final String? oldColumn;

  /// Its new name.
  final String? newColumn;

  @override
  FormulaReferenceResult? mapReference(FormulaReference ref, String host) =>
      null;

  @override
  String? mapSheetName(String sheet) => null;

  @override
  String? mapStructured(String table, String spec, String hostSheet) =>
      mapStructuredAt(table, spec, hostSheet, null, null);

  @override
  String? mapStructuredAt(
    String table,
    String spec,
    String hostSheet,
    int? row,
    int? column,
  ) {
    final bool named = table.isNotEmpty && this.table.isNamed(table);
    final bool inside =
        table.isEmpty && this.table.contains(hostSheet, row, column);
    if (!named && !inside) return null;
    final String nextTable = named ? (newName ?? table) : table;
    final String nextSpec = _renamedColumns(spec) ?? spec;
    final String text = '$nextTable$nextSpec';
    return text == '$table$spec' ? null : text;
  }

  String? _renamedColumns(String spec) {
    final String? from = oldColumn;
    final String? to = newColumn;
    if (from == null || to == null) return null;
    final StructuredSpec? parsed = parseStructuredSpec(spec);
    if (parsed == null) return null;
    String out = spec;
    for (final StructuredColumn c in parsed.columns.reversed) {
      if (c.name.toLowerCase() != from.toLowerCase()) continue;
      final String escaped = escapeStructuredColumn(to);
      final bool wrap =
          c.bare &&
          parsed.thisRow &&
          !RegExp(r'^[\p{L}\p{N}_.]+$', unicode: true).hasMatch(to);
      out = out.replaceRange(c.start, c.end, wrap ? '[$escaped]' : escaped);
    }
    return out;
  }
}

/// The table [table] removed: every structured reference to it becomes the
/// plain range it covers (`Sales[Amount]` is `Sheet1!$B$2:$B$4` from another
/// sheet, `$B$2:$B$4` from its own; `[@Amount]` in row 3 is `$B3`, the whole
/// body `$A2:$C4` from a row outside the data, as Excel writes it), as Excel's "Convert to Range" does. A
/// reference to an item the table lacks (the totals of a table without them)
/// becomes `#REF!`.
///
/// Throws a [StateError] for a reference it cannot convert: a span it
/// cannot read, a column the table lacks, or the formula's own row where
/// the formula has no cell.
final class TableToRange implements PositionedStructuredMapper {
  /// The removal of [table].
  TableToRange(this.table);

  /// The table removed.
  final StructuredTable table;

  @override
  FormulaReferenceResult? mapReference(FormulaReference ref, String host) =>
      null;

  @override
  String? mapSheetName(String sheet) => null;

  @override
  String? mapStructured(String table, String spec, String hostSheet) =>
      mapStructuredAt(table, spec, hostSheet, null, null);

  @override
  String? mapStructuredAt(
    String table,
    String spec,
    String hostSheet,
    int? row,
    int? column,
  ) {
    final bool named = table.isNotEmpty && this.table.isNamed(table);
    final bool inside =
        table.isEmpty && this.table.contains(hostSheet, row, column);
    if (!named && !inside) return null;
    final StructuredSpec? parsed = parseStructuredSpec(spec);
    if (parsed == null) {
      throw StateError(
        'The reference "$table$spec" to the table "${this.table.name}" '
        'cannot be read, so it cannot become a range.',
      );
    }
    final XlsxRange r = this.table.range;
    int firstColumn = r.firstColumn;
    int lastColumn = r.lastColumn;
    if (parsed.columns.isNotEmpty) {
      final List<int> at = <int>[
        for (final StructuredColumn c in parsed.columns)
          this.table.columnIndex(c.name),
      ];
      final int missing = at.indexOf(-1);
      if (missing >= 0) {
        throw StateError(
          'The reference "$table$spec" names the column '
          '"${parsed.columns[missing].name}", which the table '
          '"${this.table.name}" lacks, so it cannot become a range.',
        );
      }
      final int a = at.first;
      final int b = at.last;
      firstColumn = r.firstColumn + (a < b ? a : b);
      lastColumn = r.firstColumn + (a < b ? b : a);
    }
    final bool sameSheet =
        hostSheet.toLowerCase() == this.table.sheet.toLowerCase();
    final String prefix = sameSheet ? '' : renderSheetPrefix(this.table.sheet);
    final int header = r.firstRow;
    final int bodyFirst = r.firstRow + (this.table.headerRow ? 1 : 0);
    final int bodyLast = r.lastRow - (this.table.totalsRow ? 1 : 0);
    if (parsed.thisRow) {
      if (row == null) {
        throw StateError(
          'The reference "$table$spec" names the row of its formula, which '
          'has no cell, so it cannot become a range.',
        );
      }
      // Outside the data rows Excel writes the whole body, rows relative,
      // where implicit intersection gives #VALUE! (the owner's W5 check).
      if (row < bodyFirst || row > bodyLast) {
        return '$prefix\$${columnName(r.firstColumn)}${bodyFirst + 1}:'
            '\$${columnName(r.lastColumn)}${bodyLast + 1}';
      }
      String at(int column) => '\$${columnName(column)}${row + 1}';
      return firstColumn == lastColumn
          ? '$prefix${at(firstColumn)}'
          : '$prefix${at(firstColumn)}:${at(lastColumn)}';
    }
    final Set<String> items = parsed.items.isEmpty
        ? <String>{'#data'}
        : parsed.items;
    int? firstRow;
    int? lastRow;
    void take(int from, int to) {
      if (firstRow == null || from < firstRow!) firstRow = from;
      if (lastRow == null || to > lastRow!) lastRow = to;
    }

    for (final String item in items) {
      switch (item) {
        case '#all':
          take(r.firstRow, r.lastRow);
        case '#data':
          take(bodyFirst, bodyLast);
        case '#headers':
          if (!this.table.headerRow) return '#REF!';
          take(header, header);
        case '#totals':
          if (!this.table.totalsRow) return '#REF!';
          take(r.lastRow, r.lastRow);
      }
    }
    String abs(int row, int column) => '\$${columnName(column)}\$${row + 1}';
    final String first = abs(firstRow!, firstColumn);
    if (firstRow == lastRow && firstColumn == lastColumn) {
      return '$prefix$first';
    }
    return '$prefix$first:${abs(lastRow!, lastColumn)}';
  }
}
