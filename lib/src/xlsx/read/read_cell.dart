/// The values the reader hands out: rows, cells, error values and formula
/// groups.
///
/// `XlsxReadCell` and `XlsxReadRow` were written for jet_office in R1 (in
/// `sheet_reader.dart`) and moved here in R2, which adds the cell's number
/// format, `isDate` and formula group, the `XlsxErrorValue` of an error cell
/// and `XlsxFormulaGroup`. Quds' reader returned a dense grid of strings and
/// has no counterpart.
///
/// @docImport '../values.dart';
/// @docImport '../warnings.dart';
library;

import '../range.dart';

/// The error value of a cell (`t="e"`), such as `#N/A`.
///
/// The seven [classic] codes have constants. A newer code a file may hold,
/// such as `#SPILL!` or `#CALC!`, is kept as written and is not [isClassic].
final class XlsxErrorValue {
  /// The error value written as [code], such as `#N/A`.
  const XlsxErrorValue(this.code);

  /// `#NULL!`: two ranges that do not intersect.
  static const XlsxErrorValue nullError = XlsxErrorValue('#NULL!');

  /// `#DIV/0!`: a division by zero.
  static const XlsxErrorValue div0 = XlsxErrorValue('#DIV/0!');

  /// `#VALUE!`: an argument of the wrong type.
  static const XlsxErrorValue value = XlsxErrorValue('#VALUE!');

  /// `#REF!`: a reference to a cell that does not exist.
  static const XlsxErrorValue ref = XlsxErrorValue('#REF!');

  /// `#NAME?`: a name the formula does not know.
  static const XlsxErrorValue name = XlsxErrorValue('#NAME?');

  /// `#NUM!`: a number that cannot be computed or shown.
  static const XlsxErrorValue num = XlsxErrorValue('#NUM!');

  /// `#N/A`: a value that is not available.
  static const XlsxErrorValue na = XlsxErrorValue('#N/A');

  /// The seven error values every spreadsheet application knows, in the
  /// order of their Excel error numbers.
  static const List<XlsxErrorValue> classic = <XlsxErrorValue>[
    nullError,
    div0,
    value,
    ref,
    name,
    num,
    na,
  ];

  /// The code as the file wrote it, trimmed and XML-string decoded.
  final String code;

  /// Whether [code] is one of the [classic] seven (compared exactly, so
  /// `#n/a` is not).
  bool get isClassic => classic.contains(this);

  @override
  bool operator ==(Object other) =>
      other is XlsxErrorValue && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'XlsxErrorValue($code)';
}

/// The kind of formula group a cell belongs to.
enum XlsxFormulaGroupKind {
  /// A shared formula (`<f t="shared">`): one formula text, written once in
  /// the master cell, that the other cells of the range repeat with their
  /// references shifted.
  shared,

  /// An array formula (`<f t="array">`): one formula whose result fills the
  /// range.
  array,

  /// A data table (`<f t="dataTable">`, Excel's What-If Analysis): the
  /// range holds the results of a formula for a list of inputs.
  dataTable,
}

/// The formula group of a cell: its [kind], its [range] and whether the cell
/// is the group's master.
///
/// The master is the cell whose `<f>` defines the group; the other cells of
/// the group follow it. Every cell of one group has an equal [range] and
/// [kind]; only [isMaster] tells the master from its followers.
final class XlsxFormulaGroup {
  /// A group of [kind] covering [range]; [isMaster] whether the cell that
  /// holds it is the master.
  const XlsxFormulaGroup(this.kind, this.range, {required this.isMaster});

  /// Whether the group is a shared formula, an array formula or a data
  /// table.
  final XlsxFormulaGroupKind kind;

  /// The cells of the group, the master included.
  final XlsxRange range;

  /// Whether the cell is the master, the one whose `<f>` defines the group.
  final bool isMaster;

  @override
  bool operator ==(Object other) =>
      other is XlsxFormulaGroup &&
      other.kind == kind &&
      other.range == range &&
      other.isMaster == isMaster;

  @override
  int get hashCode => Object.hash(kind, range, isMaster);

  @override
  String toString() =>
      'XlsxFormulaGroup(${kind.name}, $range'
      '${isMaster ? ', master' : ''})';
}

/// One cell of a row read from a worksheet.
final class XlsxReadCell {
  /// A cell in the 0-based [column] holding [value] and, when it has one,
  /// [formula] and [formulaGroup], shown with the number format
  /// [numberFormatId] whose code is [numberFormat]; [isDate] whether that
  /// format shows a date or a time.
  const XlsxReadCell(
    this.column,
    this.value, {
    this.formula,
    this.formulaGroup,
    this.numberFormatId = 0,
    this.numberFormat = 'General',
    this.isDate = false,
  });

  /// The 0-based column: 0 is `A`.
  final int column;

  /// The value: `null`, a `String`, a `bool`, an [XlsxDecimal], a
  /// `DateTime`, a `Duration` or an [XlsxErrorValue].
  ///
  /// A number whose format shows a date is a UTC `DateTime` built from the
  /// wall clock the file means; one whose format shows only a time is a
  /// `Duration` of that many days. `null` when the file holds no value for
  /// the cell or the value could not be read; the second case is reported
  /// as an [XlsxWarning]. A number that cannot be a date or a duration stays
  /// an [XlsxDecimal], also with a warning.
  final Object? value;

  /// The formula text as written in the file, only `_xHHHH_` decoded (a
  /// leading `=` is not removed or added), or `null` when the cell has no
  /// formula text. [value] is the result the file cached for the formula.
  ///
  /// A cell that follows a shared formula (`<f t="shared" si="0"/>`, empty)
  /// has a formula in the file but no text of its own, so this is `null`;
  /// [formulaGroup] names the shared formula, whose text is the master's,
  /// and [value] still holds the cell's cached result. The cells of an
  /// array or data table other than its master have no `<f>` either.
  final String? formula;

  /// The shared, array or data-table formula the cell belongs to, or `null`
  /// when it belongs to none.
  final XlsxFormulaGroup? formulaGroup;

  /// The number format id (`numFmtId`) of the cell's style; 0 is `General`.
  final int numberFormatId;

  /// The format code of [numberFormatId], such as `dd.mm.yyyy`, or `null`
  /// for a built-in id whose code depends on the locale and that the file
  /// does not define.
  final String? numberFormat;

  /// Whether [numberFormat] shows a date or a time. [value] tells which: a
  /// `DateTime` or a `Duration`, unless the number could not be mapped.
  final bool isDate;

  @override
  bool operator ==(Object other) =>
      other is XlsxReadCell &&
      other.column == column &&
      other.value == value &&
      other.formula == formula &&
      other.formulaGroup == formulaGroup &&
      other.numberFormatId == numberFormatId &&
      other.numberFormat == numberFormat &&
      other.isDate == isDate;

  @override
  int get hashCode => Object.hash(
    column,
    value,
    formula,
    formulaGroup,
    numberFormatId,
    numberFormat,
    isDate,
  );

  /// `XlsxReadCell(column, value, ...)`, naming only what differs from the
  /// defaults.
  @override
  String toString() {
    final bool general = numberFormatId == 0 && numberFormat == 'General';
    return 'XlsxReadCell($column, $value'
        '${formula == null ? '' : ', formula: $formula'}'
        '${formulaGroup == null ? '' : ', group: $formulaGroup'}'
        '${general ? '' : ', format: $numberFormatId $numberFormat'}'
        '${isDate ? ', date' : ''})';
  }
}

/// One row read from a worksheet.
final class XlsxReadRow {
  /// A row at the 0-based [index] holding [cells], which must be in column
  /// order; [hidden] whether the file hides it.
  XlsxReadRow(this.index, List<XlsxReadCell> cells, {this.hidden = false})
    : cells = List<XlsxReadCell>.unmodifiable(cells);

  /// The 0-based row index: 0 is row 1.
  final int index;

  /// Whether the row is hidden in the file.
  final bool hidden;

  /// The cells of the row that hold data, in column order. Empty only for a
  /// hidden row without data. Unmodifiable.
  final List<XlsxReadCell> cells;

  @override
  bool operator ==(Object other) {
    if (other is! XlsxReadRow ||
        other.index != index ||
        other.hidden != hidden ||
        other.cells.length != cells.length) {
      return false;
    }
    for (int i = 0; i < cells.length; i++) {
      if (other.cells[i] != cells[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(index, hidden, Object.hashAll(cells));

  @override
  String toString() => 'XlsxReadRow($index${hidden ? ', hidden' : ''}, $cells)';
}
