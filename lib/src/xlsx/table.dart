/// Tables, Excel's formatted ranges with a header row, filter buttons and
/// an optional totals row: [XlsxTable], its columns and style, the checks a
/// table passes when it is added to a sheet, the cells the writer fills in
/// its header and totals rows, and its part, `xl/tables/table{id}.xml`.
///
/// New in jet_office. quds_office_engine's table writer
/// (`_writeSheetExtras` in `lib/src/sheet/serial/sheet_serial.dart` at
/// commit 15c5d29) is broken, so nothing of it is ported. It writes every
/// table of a sheet into one part, `/xl/tables{n}.xml`, under a `<tables>`
/// root that the schema does not know, without the SpreadsheetML namespace,
/// and gives each `<table>` only `name`, `ref` and the invented attributes
/// `headerRow` and `bandedRows`: no `id`, no `displayName`, no
/// `tableColumns` and no `tableStyleInfo`. It registers the part with the
/// worksheet content type and writes no relationship and no `tableParts`,
/// so Excel never sees a table. It checks neither the name nor overlaps,
/// and leaves the header cells to whatever the caller wrote.
library;

import '../opc/ooxml.dart';
import '../xml/xml_escape.dart';
import '../xml/xml_writer.dart';
import 'defined_name.dart';
import 'formula_text.dart';
import 'limits.dart';
import 'range.dart';
import 'sheet_name.dart';
import 'values.dart';

/// What the totals row of a table shows under a column.
///
/// Every function but [none] and [custom] is written as Excel writes it: the
/// column's `totalsRowFunction`, which drives Excel's drop-down, and in the
/// totals cell a `SUBTOTAL` over the column's data rows that skips rows a
/// filter hides.
enum XlsxTotalsFunction {
  /// Nothing, or the column's label (see [XlsxTableColumn.totalsLabel]).
  none,

  /// The sum, `SUBTOTAL(109, …)`.
  sum,

  /// The smallest number, `SUBTOTAL(105, …)`.
  min,

  /// The largest number, `SUBTOTAL(104, …)`.
  max,

  /// The mean, `SUBTOTAL(101, …)`.
  average,

  /// The number of non-empty cells, `SUBTOTAL(103, …)`.
  count,

  /// The number of cells holding numbers, `SUBTOTAL(102, …)`.
  countNums,

  /// The sample standard deviation, `SUBTOTAL(107, …)`.
  stdDev,

  /// The sample variance, `SUBTOTAL(110, …)`; written `var`.
  variance,

  /// The column's own formula (see [XlsxTableColumn.totalsFormula]).
  custom,
}

/// The `ST_TotalsRowFunction` value of [function]: its name, except `var`
/// for [XlsxTotalsFunction.variance].
String totalsFunctionXml(XlsxTotalsFunction function) =>
    function == XlsxTotalsFunction.variance ? 'var' : function.name;

/// The `SUBTOTAL` function number of [function], the one that skips hidden
/// rows (100 and up), or `null` for [XlsxTotalsFunction.none] and
/// [XlsxTotalsFunction.custom].
int? subtotalCode(XlsxTotalsFunction function) => switch (function) {
  XlsxTotalsFunction.none || XlsxTotalsFunction.custom => null,
  XlsxTotalsFunction.average => 101,
  XlsxTotalsFunction.countNums => 102,
  XlsxTotalsFunction.count => 103,
  XlsxTotalsFunction.max => 104,
  XlsxTotalsFunction.min => 105,
  XlsxTotalsFunction.stdDev => 107,
  XlsxTotalsFunction.sum => 109,
  XlsxTotalsFunction.variance => 110,
};

/// One column of an [XlsxTable]: its header [name] and what its totals row
/// shows.
///
/// The `const` constructor checks nothing; the sheet writer does when the
/// table is added (see `XlsxSheetWriter.table`).
final class XlsxTableColumn {
  /// A column named [name] whose totals row shows [totalsFunction], or
  /// [totalsLabel] with [XlsxTotalsFunction.none], or [totalsFormula] with
  /// [XlsxTotalsFunction.custom].
  const XlsxTableColumn(
    this.name, {
    this.totalsFunction = XlsxTotalsFunction.none,
    this.totalsLabel,
    this.totalsFormula,
  });

  /// The column's name, the text of its header cell: 1 to
  /// [XlsxLimits.maxTableColumnNameLength] UTF-16 code units, no line
  /// break, tab or character XML forbids, and unique in its table ignoring
  /// case.
  final String name;

  /// What the totals row shows under the column.
  final XlsxTotalsFunction totalsFunction;

  /// The text the totals row shows under the column, only with
  /// [XlsxTotalsFunction.none]; `null` for none.
  final String? totalsLabel;

  /// The formula the totals row computes under the column, with or without
  /// its leading `=`; required with [XlsxTotalsFunction.custom] and refused
  /// with any other function.
  final String? totalsFormula;

  @override
  bool operator ==(Object other) =>
      other is XlsxTableColumn &&
      other.name == name &&
      other.totalsFunction == totalsFunction &&
      other.totalsLabel == totalsLabel &&
      other.totalsFormula == totalsFormula;

  @override
  int get hashCode =>
      Object.hash(name, totalsFunction, totalsLabel, totalsFormula);

  @override
  String toString() =>
      'XlsxTableColumn($name, totalsFunction: ${totalsFunction.name}, '
      'totalsLabel: $totalsLabel, totalsFormula: $totalsFormula)';
}

/// The look of an [XlsxTable]: one of Excel's built-in table styles and
/// which of its parts are shown.
///
/// [name] is `TableStyleLight1` to `TableStyleLight21`,
/// `TableStyleMedium1` to `TableStyleMedium28` or `TableStyleDark1` to
/// `TableStyleDark11`, spelled exactly so; the writer refuses any other
/// when the table is added. Custom table styles are not written.
final class XlsxTableStyle {
  /// The built-in style [name] with the given parts shown.
  const XlsxTableStyle(
    this.name, {
    this.showFirstColumn = false,
    this.showLastColumn = false,
    this.showRowStripes = true,
    this.showColumnStripes = false,
  });

  /// `TableStyleLight{n}`, n from 1 to 21.
  factory XlsxTableStyle.light(
    int n, {
    bool showFirstColumn = false,
    bool showLastColumn = false,
    bool showRowStripes = true,
    bool showColumnStripes = false,
  }) => XlsxTableStyle(
    'TableStyleLight$n',
    showFirstColumn: showFirstColumn,
    showLastColumn: showLastColumn,
    showRowStripes: showRowStripes,
    showColumnStripes: showColumnStripes,
  );

  /// `TableStyleMedium{n}`, n from 1 to 28.
  factory XlsxTableStyle.medium(
    int n, {
    bool showFirstColumn = false,
    bool showLastColumn = false,
    bool showRowStripes = true,
    bool showColumnStripes = false,
  }) => XlsxTableStyle(
    'TableStyleMedium$n',
    showFirstColumn: showFirstColumn,
    showLastColumn: showLastColumn,
    showRowStripes: showRowStripes,
    showColumnStripes: showColumnStripes,
  );

  /// `TableStyleDark{n}`, n from 1 to 11.
  factory XlsxTableStyle.dark(
    int n, {
    bool showFirstColumn = false,
    bool showLastColumn = false,
    bool showRowStripes = true,
    bool showColumnStripes = false,
  }) => XlsxTableStyle(
    'TableStyleDark$n',
    showFirstColumn: showFirstColumn,
    showLastColumn: showLastColumn,
    showRowStripes: showRowStripes,
    showColumnStripes: showColumnStripes,
  );

  /// Excel's default for a new table: `TableStyleMedium2` with row stripes.
  static const XlsxTableStyle defaultStyle = XlsxTableStyle(
    'TableStyleMedium2',
  );

  /// The built-in style's name.
  final String name;

  /// Whether the first column is set off.
  final bool showFirstColumn;

  /// Whether the last column is set off.
  final bool showLastColumn;

  /// Whether rows are banded.
  final bool showRowStripes;

  /// Whether columns are banded.
  final bool showColumnStripes;

  @override
  bool operator ==(Object other) =>
      other is XlsxTableStyle &&
      other.name == name &&
      other.showFirstColumn == showFirstColumn &&
      other.showLastColumn == showLastColumn &&
      other.showRowStripes == showRowStripes &&
      other.showColumnStripes == showColumnStripes;

  @override
  int get hashCode => Object.hash(
    name,
    showFirstColumn,
    showLastColumn,
    showRowStripes,
    showColumnStripes,
  );

  @override
  String toString() =>
      'XlsxTableStyle($name, showFirstColumn: $showFirstColumn, '
      'showLastColumn: $showLastColumn, showRowStripes: $showRowStripes, '
      'showColumnStripes: $showColumnStripes)';
}

/// A table over [range]: an optional header row, its data rows and an
/// optional totals row, one [XlsxTableColumn] per column.
///
/// The writer fills in the header row with the column names and the totals
/// row with the columns' labels and formulas wherever the caller leaves a
/// cell `null` (see `XlsxSheetWriter.table`). The constructor checks
/// nothing; the sheet writer does when the table is added and throws
/// [ArgumentError] naming the field.
///
/// ```dart
/// sheet.table(XlsxTable(
///   'Sales',
///   XlsxRange.parse('A1:B4'),
///   const <XlsxTableColumn>[
///     XlsxTableColumn('Region', totalsLabel: 'Total'),
///     XlsxTableColumn('Amount', totalsFunction: XlsxTotalsFunction.sum),
///   ],
///   totalsRow: true,
/// ));
/// sheet.row(<Object?>[null, null]); // the header: Region, Amount
/// sheet.row(<Object?>['North', 120]);
/// sheet.row(<Object?>['South', 80]);
/// sheet.row(<Object?>[null, null]); // Total, SUBTOTAL(109,B2:B3)
/// ```
final class XlsxTable {
  /// A table named [name] over [range] with [columns], one per column of
  /// the range. [headerRow] makes the first row the header, [totalsRow]
  /// the last row the totals; [autoFilter] puts filter buttons on the
  /// header (only with a header row); [style] is the look, `null` for
  /// none.
  XlsxTable(
    this.name,
    this.range,
    List<XlsxTableColumn> columns, {
    this.headerRow = true,
    this.totalsRow = false,
    this.autoFilter = true,
    this.style = XlsxTableStyle.defaultStyle,
  }) : columns = List<XlsxTableColumn>.unmodifiable(columns);

  /// The table's name, by which formulas refer to it (`Sales[Amount]`).
  ///
  /// It follows the defined-name rules (see `XlsxDefinedName.name`), is at
  /// most [XlsxLimits.maxTableNameLength] UTF-16 code units, and no other
  /// table or defined name of the workbook has it, ignoring case.
  final String name;

  /// The cells the table covers, header and totals rows included.
  final XlsxRange range;

  /// The columns from the range's first on; an unmodifiable copy.
  final List<XlsxTableColumn> columns;

  /// Whether the first row of [range] is a header of column names.
  final bool headerRow;

  /// Whether the last row of [range] is a totals row.
  final bool totalsRow;

  /// Whether the header row has filter buttons.
  final bool autoFilter;

  /// The look of the table, or `null` for none.
  final XlsxTableStyle? style;

  @override
  bool operator ==(Object other) {
    if (other is! XlsxTable ||
        other.name != name ||
        other.range != range ||
        other.headerRow != headerRow ||
        other.totalsRow != totalsRow ||
        other.autoFilter != autoFilter ||
        other.style != style ||
        other.columns.length != columns.length) {
      return false;
    }
    for (int i = 0; i < columns.length; i++) {
      if (other.columns[i] != columns[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    name,
    range,
    Object.hashAll(columns),
    headerRow,
    totalsRow,
    autoFilter,
    style,
  );

  @override
  String toString() =>
      'XlsxTable($name, $range, $columns, headerRow: $headerRow, '
      'totalsRow: $totalsRow, autoFilter: $autoFilter, style: $style)';
}

/// The built-in table style names Excel knows.
final RegExp _styleName = RegExp(
  r'^TableStyle(Light([1-9]|1[0-9]|2[01])|Medium([1-9]|1[0-9]|2[0-8])'
  r'|Dark([1-9]|1[01]))$',
);

/// Checks what [table] says about itself: its name's shape, its range, its
/// columns, its rows, its totals and its style. What depends on the sheet
/// and the workbook (a name already taken, an overlap, a header row already
/// written) the sheet writer checks.
///
/// Throws [ArgumentError] named `name` for a name failing
/// [checkNameSyntax] as a table name, which holds it to
/// [XlsxLimits.maxTableNameLength]; `range` for a range outside the sheet,
/// in reverse, or with fewer rows than the header row, one data row and
/// the totals row need; `columns` when there
/// is not one column per column of the range; `columns[i].name` for an
/// empty name, one longer than [XlsxLimits.maxTableColumnNameLength], one
/// holding a line break, a tab or a character XML forbids, or one an
/// earlier column has, ignoring case; `columns[i].totalsLabel` for a label
/// with a function other than [XlsxTotalsFunction.none] or holding a
/// character XML forbids; `columns[i].totalsFormula` for a formula missing
/// with [XlsxTotalsFunction.custom], given with another function, or
/// failing `checkFormulaText`; and `style` for a name that is not a
/// built-in table style.
void checkTable(XlsxTable table) {
  final String name = table.name;
  checkNameSyntax(name, 'name', table: true);
  final XlsxRange range = table.range;
  validateRange(range, 'range');
  final List<XlsxTableColumn> columns = table.columns;
  if (columns.length != range.columnCount) {
    throw ArgumentError.value(
      columns.length,
      'columns',
      'The table "$name" over ${range.ref} needs ${range.columnCount} '
          'columns, one per column of its range.',
    );
  }
  final Map<String, String> seen = <String, String>{};
  for (int i = 0; i < columns.length; i++) {
    _checkColumnName(columns[i].name, 'columns[$i].name', seen);
  }
  final int least = (table.headerRow ? 1 : 0) + 1 + (table.totalsRow ? 1 : 0);
  if (range.rowCount < least) {
    throw ArgumentError.value(
      range,
      'range',
      'The table "$name" needs at least $least rows: '
          '${table.headerRow ? 'its header row, ' : ''}one data row'
          '${table.totalsRow ? ' and its totals row' : ''}.',
    );
  }
  for (int i = 0; i < columns.length; i++) {
    _checkTotals(columns[i], 'columns[$i]');
  }
  final XlsxTableStyle? style = table.style;
  if (style != null && !_styleName.hasMatch(style.name)) {
    throw ArgumentError.value(
      style.name,
      'style',
      'A table style is one of Excel\'s built-in styles: TableStyleLight1 to '
          '21, TableStyleMedium1 to 28 or TableStyleDark1 to 11.',
    );
  }
}

/// Throws [ArgumentError] named [field] unless [name] can name a table
/// column; adds it to [seen], keyed ignoring case, when it can.
void _checkColumnName(String name, String field, Map<String, String> seen) {
  if (name.isEmpty) {
    throw ArgumentError.value(name, field, 'A column name must not be empty.');
  }
  if (name.length > XlsxLimits.maxTableColumnNameLength) {
    throw ArgumentError.value(
      '${name.length} characters',
      field,
      'A column name has at most ${XlsxLimits.maxTableColumnNameLength} '
          'characters.',
    );
  }
  if (name.contains('\n') ||
      name.contains('\r') ||
      name.contains('\t') ||
      scrubXmlText(name).removed > 0) {
    throw ArgumentError.value(
      name,
      field,
      'A column name must not contain a line break, a tab or characters XML '
      'forbids.',
    );
  }
  final String key = sheetNameKey(name);
  final String? earlier = seen[key];
  if (earlier != null) {
    throw ArgumentError.value(
      name,
      field,
      'The column name "$name" repeats "$earlier"; column names are compared '
      'ignoring case.',
    );
  }
  seen[key] = name;
}

/// Throws [ArgumentError] named `<field>.totalsLabel` or
/// `<field>.totalsFormula` when [column]'s totals settings do not go
/// together.
void _checkTotals(XlsxTableColumn column, String field) {
  final String? label = column.totalsLabel;
  final String? formula = column.totalsFormula;
  final bool custom = column.totalsFunction == XlsxTotalsFunction.custom;
  if (label != null) {
    if (column.totalsFunction != XlsxTotalsFunction.none) {
      throw ArgumentError.value(
        label,
        '$field.totalsLabel',
        'A totals label goes only with XlsxTotalsFunction.none; the column '
            '"${column.name}" has ${column.totalsFunction.name}.',
      );
    }
    if (scrubXmlText(label).removed > 0) {
      throw ArgumentError.value(
        label,
        '$field.totalsLabel',
        'A totals label must not contain characters XML forbids.',
      );
    }
  }
  if (custom && formula == null) {
    throw ArgumentError.value(
      formula,
      '$field.totalsFormula',
      'The column "${column.name}" has a custom total and needs its '
          'totalsFormula.',
    );
  }
  if (formula != null) {
    if (!custom) {
      throw ArgumentError.value(
        formula,
        '$field.totalsFormula',
        'A totals formula goes only with XlsxTotalsFunction.custom; the '
            'column "${column.name}" has ${column.totalsFunction.name}.',
      );
    }
    checkFormulaText(formula, '$field.totalsFormula');
  }
}

/// The data rows of [table]: its range without the header and totals rows.
XlsxRange tableDataRange(XlsxTable table) {
  final XlsxRange r = table.range;
  return XlsxRange(
    r.firstRow + (table.headerRow ? 1 : 0),
    r.firstColumn,
    r.lastRow - (table.totalsRow ? 1 : 0),
    r.lastColumn,
  );
}

/// Whether the zero-based [row] is the header row of [table].
bool isTableHeaderRow(XlsxTable table, int row) =>
    table.headerRow && row == table.range.firstRow;

/// Whether the zero-based [row] is the totals row of [table].
bool isTableTotalsRow(XlsxTable table, int row) =>
    table.totalsRow && row == table.range.lastRow;

/// The value written in the header cell of [table]'s zero-based sheet
/// [column], given [value] there (`null` when the row is shorter).
///
/// `null` becomes the column's name, and an [XlsxCell] holding `null`
/// becomes an [XlsxCell] of the name with that cell's style. A `String`,
/// or an [XlsxCell] holding one, equal to the name is kept as given, its
/// style included. Anything else throws [ArgumentError] named
/// `values[column]`: Excel repairs a table whose header cells differ from
/// its column names.
Object? tableHeaderCell(XlsxTable table, int column, Object? value) {
  final String name = table.columns[column - table.range.firstColumn].name;
  if (value == null) return name;
  if (value is XlsxCell && value.value == null) {
    return XlsxCell(name, style: value.style);
  }
  final Object? text = value is XlsxCell ? value.value : value;
  if (text is String && text == name) return value;
  throw ArgumentError.value(
    value,
    'values[$column]',
    'The header cell of the column "$name" of the table "${table.name}" '
        'must be null or "$name".',
  );
}

/// The value written in the totals cell of [table]'s zero-based sheet
/// [column], given [value] there (`null` when the row is shorter).
///
/// A given value is kept. `null` becomes the column's label, a `SUBTOTAL`
/// over the column's data rows for a function (`SUBTOTAL(109,B2:B4)`, an
/// A1 range, not a structured reference), its formula for a custom total,
/// and stays `null` for none. An [XlsxCell] holding `null` is filled in
/// the same way and keeps its style; for none it stays as given, a styled
/// empty cell.
Object? tableTotalsCell(XlsxTable table, int column, Object? value) {
  if (value is XlsxCell && value.value == null) {
    final Object? total = _totalOf(table, column);
    return total == null ? value : XlsxCell(total, style: value.style);
  }
  return value ?? _totalOf(table, column);
}

/// The total of [table]'s zero-based sheet [column] (see
/// [tableTotalsCell]), `null` for none.
Object? _totalOf(XlsxTable table, int column) {
  final XlsxTableColumn c = table.columns[column - table.range.firstColumn];
  final String? label = c.totalsLabel;
  if (label != null) return label;
  final int? code = subtotalCode(c.totalsFunction);
  if (code != null) {
    final XlsxRange data = tableDataRange(table);
    final String ref = XlsxRange(data.firstRow, column, data.lastRow).ref;
    return XlsxFormula('SUBTOTAL($code,$ref)');
  }
  final String? formula = c.totalsFormula;
  return formula == null ? null : XlsxFormula(formula);
}

/// Writes the part of [table], whose workbook-wide id is [id].
///
/// `CT_Table` attributes in schema order: `id`, `name`, `displayName`
/// (both the name), `ref`, `headerRowCount="0"` without a header row, then
/// `totalsRowCount="1"` with a totals row or `totalsRowShown="0"` without.
/// Children: `autoFilter` over the range without its totals row (only with
/// a header row and [XlsxTable.autoFilter]), `tableColumns` and
/// `tableStyleInfo` (when the table has a style). Names, column names and
/// labels go through `escapeXstring`, a totals formula through
/// `escapeFormulaText`.
void writeTable(XmlWriter w, int id, XlsxTable table) {
  final XlsxRange range = table.range;
  final String name = escapeXstring(table.name);
  w.declaration();
  w.start('table');
  w.attribute('xmlns', Ns.main);
  w.attribute('id', '$id');
  w.attribute('name', name);
  w.attribute('displayName', name);
  w.attribute('ref', range.ref);
  if (!table.headerRow) w.attribute('headerRowCount', '0');
  if (table.totalsRow) {
    w.attribute('totalsRowCount', '1');
  } else {
    w.attribute('totalsRowShown', '0');
  }
  if (table.headerRow && table.autoFilter) {
    final XlsxRange filter = XlsxRange(
      range.firstRow,
      range.firstColumn,
      range.lastRow - (table.totalsRow ? 1 : 0),
      range.lastColumn,
    );
    w.empty('autoFilter', <String, String>{'ref': filter.ref});
  }
  w.start('tableColumns');
  w.attribute('count', '${table.columns.length}');
  for (int i = 0; i < table.columns.length; i++) {
    final XlsxTableColumn column = table.columns[i];
    w.start('tableColumn');
    w.attribute('id', '${i + 1}');
    w.attribute('name', escapeXstring(column.name));
    if (column.totalsFunction != XlsxTotalsFunction.none) {
      w.attribute(
        'totalsRowFunction',
        totalsFunctionXml(column.totalsFunction),
      );
    }
    final String? label = column.totalsLabel;
    if (label != null) w.attribute('totalsRowLabel', escapeXstring(label));
    final String? formula = column.totalsFormula;
    if (formula != null) {
      w.start('totalsRowFormula');
      w.raw(escapeFormulaText(writtenFormulaText(formula)));
      w.end();
    }
    w.end();
  }
  w.end();
  final XlsxTableStyle? style = table.style;
  if (style != null) {
    w.empty('tableStyleInfo', <String, String>{
      'name': style.name,
      'showFirstColumn': style.showFirstColumn ? '1' : '0',
      'showLastColumn': style.showLastColumn ? '1' : '0',
      'showRowStripes': style.showRowStripes ? '1' : '0',
      'showColumnStripes': style.showColumnStripes ? '1' : '0',
    });
  }
  w.end();
}
