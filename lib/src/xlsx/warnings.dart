/// Structured warnings about data the XLSX writer had to change or the reader
/// could not read exactly.
///
/// New in jet_office. A warning describes a data problem the writer repaired
/// instead of failing on (decision 0003): a cell lost characters, a sheet was
/// renamed. The reader reports the mirror problems the same way: a cell it
/// could not read exactly reads as empty and a warning says so. Cell-level
/// warnings are aggregated per sheet and code, so a column of 100,000 dirty
/// cells yields one warning with a count and the first ten references, not
/// 100,000 objects.
library;

import 'dart:collection';

import 'warning_messages.dart';

/// The language of a warning message.
enum XlsxLocale {
  /// English.
  en,

  /// German.
  de,

  /// Turkish.
  tr,
}

/// What kind of data problem an [XlsxWarning] reports.
enum XlsxWarningCode {
  /// Characters XML does not allow (control characters, lone surrogates) were
  /// removed from cell text.
  invalidCharactersRemoved,

  /// Cell text was cut to Excel's limit of 32,767 characters (UTF-16 code
  /// units).
  textTruncated,

  /// A sheet name Excel does not allow was replaced by a valid one.
  sheetNameChanged,

  /// A sheet name already in use (Excel compares names case-insensitively) was
  /// replaced by a unique one.
  sheetNameDuplicated,

  /// A whole number larger than Excel stores exactly (beyond 2^53) was
  /// written and may be rounded.
  intPrecisionLost,

  /// A date outside the range Excel can store as a date (before 1900-01-01 or
  /// after 9999-12-31) was written as text.
  dateOutsideExcelRange,

  /// A date was written with a number format that does not display dates.
  dateInNonDateFormat,

  /// Reading: a sheet is listed in the workbook but its part is missing from
  /// the package. The sheet is still listed; its rows are empty. One warning
  /// per sheet, no cell.
  sheetPartMissing,

  /// Reading: a `t="s"` cell points to a shared string that does not exist
  /// (index out of range, or the package has no shared strings). The cell's
  /// value is `null`.
  sharedStringInvalid,

  /// Reading: a numeric cell holds text that is not a finite number (for
  /// example `abc` or an exponent too large to represent). The cell's value
  /// is `null`.
  numberInvalid,

  /// Reading: a `t="b"` cell holds something other than `0` or `1`. The
  /// cell's value is `null`.
  booleanInvalid,

  /// Reading: a cell has a type the reader does not support (`inlineStr`,
  /// `e`, `d` or an unknown `t`). The cell's value is `null`.
  cellTypeUnsupported,

  /// Reading: a formula cell has no saved result (`<f>` without `<v>`). The
  /// cell's value is `null`.
  formulaWithoutValue,

  /// Reading: a cell's `r` attribute is not a valid A1 reference. The cell
  /// is placed in the column after the previous cell of its row, and keeps
  /// its value.
  cellReferenceInvalid,

  /// Reading: two cells of one row have the same reference. The last one is
  /// kept and replaces the first.
  cellDuplicated,

  /// Reading: a row's index is not greater than the previous row's. The row
  /// is still read, in file order; the warning names the row's first cell
  /// that holds data (`A<row>` for a hidden row without data).
  rowOutOfOrder,

  /// Reading: a cell lies outside Excel's grid (column beyond XFD or row
  /// beyond 1,048,576). The cell is skipped.
  cellOutsideSheet,
}

/// Something the writer changed or could not store exactly, or the reader
/// could not read exactly.
///
/// Cell-level warnings ([XlsxWarningCode.invalidCharactersRemoved],
/// [XlsxWarningCode.textTruncated], [XlsxWarningCode.intPrecisionLost],
/// [XlsxWarningCode.dateOutsideExcelRange],
/// [XlsxWarningCode.dateInNonDateFormat] and the reader's codes such as
/// [XlsxWarningCode.numberInvalid] and [XlsxWarningCode.cellDuplicated])
/// cover every affected cell of one sheet: [count] says how many and [cells]
/// names the first ten. Sheet-name warnings
/// ([XlsxWarningCode.sheetNameChanged], [XlsxWarningCode.sheetNameDuplicated])
/// are one per renamed sheet.
///
/// Library users never construct warnings; the writer and the reader return
/// them.
final class XlsxWarning {
  XlsxWarning._(this.code, this.sheet, this.originalName);

  /// How many cell references a warning keeps.
  static const int _maxCells = 10;

  /// The kind of problem.
  final XlsxWarningCode code;

  /// The sheet the problem is on. For sheet-name warnings this is the name
  /// the sheet has in the file.
  final String sheet;

  /// The name the caller asked for, for sheet-name warnings; otherwise null.
  final String? originalName;

  int _count = 0;
  final List<String> _cells = <String>[];
  late final List<String> _cellsView = UnmodifiableListView<String>(_cells);

  /// How many cells (or, for a sheet-name warning, sheets) are affected.
  int get count => _count;

  /// A1-style references of the first ten affected cells, in write order.
  ///
  /// Empty for sheet-name warnings. An unmodifiable view, the same object on
  /// every call, that shows references added later.
  List<String> get cells => _cellsView;

  /// A human-readable description in [locale].
  String message([XlsxLocale locale = XlsxLocale.en]) =>
      formatWarning(this, locale);

  /// The English [message].
  @override
  String toString() => message();
}

/// Collects warnings while a workbook is written or read.
///
/// Cell-level codes aggregate by `(sheet, code)`; sheet-name codes give one
/// warning per [add] call. Memory stays bounded: a warning keeps at most
/// ten references however often it recurs.
final class WarningCollector {
  final List<XlsxWarning> _warnings = <XlsxWarning>[];
  late final List<XlsxWarning> _warningsView =
      UnmodifiableListView<XlsxWarning>(_warnings);
  final Map<(String, XlsxWarningCode), XlsxWarning> _aggregated =
      <(String, XlsxWarningCode), XlsxWarning>{};

  /// Records one occurrence of [code] on [sheet].
  ///
  /// [cell] is the A1-style reference for cell-level codes. [originalName] is
  /// the requested name for sheet-name codes.
  void add(
    XlsxWarningCode code, {
    required String sheet,
    String? cell,
    String? originalName,
  }) {
    final bool perCall =
        code == XlsxWarningCode.sheetNameChanged ||
        code == XlsxWarningCode.sheetNameDuplicated;
    final XlsxWarning warning;
    if (perCall) {
      warning = XlsxWarning._(code, sheet, originalName);
      _warnings.add(warning);
    } else {
      warning = _aggregated.putIfAbsent((sheet, code), () {
        final XlsxWarning created = XlsxWarning._(code, sheet, null);
        _warnings.add(created);
        return created;
      });
    }
    warning._count++;
    if (cell != null && warning._cells.length < XlsxWarning._maxCells) {
      warning._cells.add(cell);
    }
  }

  /// The warnings so far, in first-occurrence order. An unmodifiable view,
  /// the same object on every call, that shows warnings added later.
  List<XlsxWarning> get warnings => _warningsView;

  /// Drops every warning on [sheet], keeping the order of the rest.
  ///
  /// The aggregation entries go too, so a later [add] on [sheet] starts a
  /// fresh warning. The reader uses it before it reads a sheet again.
  void removeSheet(String sheet) {
    _warnings.removeWhere((XlsxWarning w) => w.sheet == sheet);
    _aggregated.removeWhere(
      ((String, XlsxWarningCode) key, XlsxWarning _) => key.$1 == sheet,
    );
  }
}
