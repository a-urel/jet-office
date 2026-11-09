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
///
/// The number format engine, in jet_core, names its own warnings
/// (`FormatWarning`); `XlsxFormatWarning.xlsxCode` maps them to the
/// formatting codes here.
library;

import 'dart:collection';

import '../common/locale.dart';
import '../common/warning_aggregator.dart';
import 'warning_messages.dart';

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

  /// Editing: a table's header cell was set, so its column was renamed to
  /// the new text, as Excel requires. Formulas that refer to the column by
  /// its old name are not updated.
  tableColumnRenamed,

  /// Editing: the text set on a table's header cell was changed, because a
  /// table's column names must be unique (ignoring case) and not empty:
  /// a number was appended, or an empty header became `ColumnN`, as Excel
  /// does.
  tableHeaderAdjusted,

  /// Editing: a structural edit (rows or columns inserted or deleted, a
  /// sheet renamed or moved) met a cell formula it cannot read fully, so its
  /// references were not rewritten; the formula is kept as read. The cells
  /// are the formulas' cells.
  formulaUnlexable,

  /// Reading: a sheet is listed in the workbook but its part is missing from
  /// the package. The sheet is still listed; its rows are empty. One warning
  /// per sheet, no cell.
  sheetPartMissing,

  /// Reading: a `t="s"` cell points to a shared string that does not exist
  /// (an index that is not a non-negative integer or is out of range, or the
  /// package has no shared strings). The cell's value is `null`.
  sharedStringInvalid,

  /// Reading: a numeric cell holds text that is not a finite number (for
  /// example `abc` or an exponent too large to represent). The cell's value
  /// is `null`.
  numberInvalid,

  /// Reading: a `t="b"` cell holds something other than `0` or `1`. The
  /// cell's value is `null`.
  booleanInvalid,

  /// Reading: a cell has a `t` the reader does not know, and its value is
  /// `null`; or it holds an inline string (`<is>`) although its `t` is not
  /// `inlineStr`, and that text is not read (the value comes from the `t`
  /// and any `<v>`).
  cellTypeUnsupported,

  /// Reading: a formula cell has no saved result (`<f>` without `<v>` or
  /// `<is>`). The cell's value is `null`; its formula text is kept.
  formulaWithoutValue,

  /// Reading: a cell's `r` attribute is not a valid A1 reference or names
  /// another row, or a row's `r` is not a row number from 1 up (`r="x"`,
  /// and `r="0"` too). For a row the warning names the row's first cell
  /// that holds data; a row without data gets none. A cell is placed in the
  /// column after the previous cell of its row and keeps its value; a row
  /// follows the previous row.
  cellReferenceInvalid,

  /// Reading: two cells of one row have the same column, or one cell
  /// repeats its `<v>`, `<f>` or `<is>`. The last one is kept and replaces
  /// the first.
  cellDuplicated,

  /// Reading: a row's index is not greater than the previous row's. The row
  /// is still read, in file order; the warning names the row's first cell
  /// that holds data (`A<row>` for a hidden row without data).
  rowOutOfOrder,

  /// Reading: a cell lies outside Excel's grid (column beyond XFD or row
  /// beyond 1,048,576). The cell is skipped.
  cellOutsideSheet,

  /// Reading: number cells use a number format whose code the file does not
  /// define and the reader cannot know: a built-in id whose code depends on
  /// the locale (23 to 36 or 50 to 163) or an id of 164 and up. They read as
  /// plain numbers, even if they show dates. [XlsxWarning.detail] is the
  /// format id in decimal, or null for the warning that gathers the ids after
  /// the first ten of a sheet.
  unresolvedNumberFormat,

  /// Reading: a number cell's style index points to a cell format that does
  /// not exist or cannot be read. The cell reads with the General format;
  /// a string, boolean or error cell with such a style gets no warning, as
  /// its value is intact.
  styleInvalid,

  /// Reading: a cell is formatted as a date or time but holds a number no
  /// date or time can have: for a date, negative or beyond 9999-12-31; for
  /// a time, 100,000 days or more either side of zero. It reads as a
  /// number.
  serialOutOfRange,

  /// Reading: a date-formatted cell of a 1900-based workbook holds the
  /// serial 60, 29 February 1900, a day that did not exist (Excel counts it
  /// for compatibility). It reads as a number.
  phantomLeapDay,

  /// Reading: a `t="d"` cell holds text that is not a valid ISO 8601 date.
  /// The cell's value is `null`.
  dateTextInvalid,

  /// Reading: a `t="e"` cell holds no error code. The cell's value is
  /// `null`.
  errorValueInvalid,

  /// Reading: a formula cell belongs to a shared, array or data-table
  /// formula the file does not define correctly (no master, a bad range or
  /// a missing attribute). The value is kept, without the formula group.
  formulaGroupInvalid,

  /// Reading: a merged range has a missing or invalid reference and was
  /// skipped. One warning per sheet, whose [XlsxWarning.count] is the
  /// number of ranges skipped; it names no cell.
  mergeRangeInvalid,

  /// Formatting: `NumberFormatter` cannot read a cell's number format
  /// code (an unterminated quote or bracket, more than four sections, more
  /// than two conditions, two conditions in one section, a condition
  /// without a number, a `[ColorN]` with N outside 1 to 56, more than 255
  /// characters) or the code would add more than 1,000 characters to the
  /// value. The cell shows with the General format.
  numberFormatInvalid,

  /// Formatting: a cell's number format code asks for a calendar other than
  /// the Gregorian (`B2`, a locale tag's calendar), a numeral system
  /// (`[DBNum1]`, `[NatNum1]`, a locale tag's numeral system), a language
  /// no format locale serves (`[$-40C]` in a date) or another bracket
  /// `NumberFormatter` does not render. The cell shows with Gregorian
  /// dates, Western digits and the default language.
  numberFormatUnsupported,

  /// Formatting: a cell uses a built-in number format whose code depends on
  /// the locale (ids 23 to 36 and 50 to 163) and the file does not hold its
  /// code. The cell shows with the closest built-in format: the format
  /// locale's short date (id 14) for ids 27 to 31, 36 and 50 to 58, its
  /// time (id 21) for ids 32 to 35, and the General format for the others.
  numberFormatLocaleDependent,

  /// Editing an opened workbook: a font, fill, border or cell format of its
  /// styles part cannot be read exactly: it holds a value the style types
  /// cannot hold (a font size of `abc`, a pattern called `zigzag`), or a
  /// cell format points at a font, fill or border that does not exist. What
  /// cannot be read takes its default, and the entry is saved as written.
  /// Reported once per entry, when it is first read. [XlsxWarning.detail]
  /// names the entry and the problem, in English, such as
  /// `font 3: The font size "abc" is not a finite number.`; after ten
  /// entries, one warning without a detail counts the rest. It names no
  /// cell.
  styleEntryInvalid,

  /// Editing an opened workbook: a row, column, sheet view, pane or merged
  /// range of a sheet has an attribute the model cannot read (a row height
  /// of `abc`, an outline level of 9). The typed value is the default, and
  /// the attribute is saved as written until it is set. Reported once per
  /// element and attribute, when it is first read. [XlsxWarning.detail]
  /// names the element and the problem, in English, such as
  /// `row 3: ht "abc" is not a row height.`; after ten, one warning without
  /// a detail counts the rest. It names no cell.
  layoutInvalid,

  /// Reading: an entry of a sheet or workbook feature could not be read; it
  /// is kept as written and left out of the typed list. The detail names the
  /// element, and the problem, in English; after ten, one warning without a
  /// detail counts the rest. A workbook's entry has an empty
  /// [XlsxWarning.sheet]. It names no cell.
  featureEntryInvalid,
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
  XlsxWarning._(this.sheet, this.originalName, this._entry);

  /// The aggregated entry that holds the code, detail, count and cells.
  final AggregatedWarning<XlsxWarningCode> _entry;

  /// The kind of problem.
  XlsxWarningCode get code => _entry.code;

  /// The sheet the problem is on. For sheet-name warnings this is the name
  /// the sheet has in the file.
  final String sheet;

  /// The name the caller asked for, for sheet-name warnings; otherwise null.
  final String? originalName;

  /// The parameter of the warning, or null when the code has none.
  ///
  /// [XlsxWarningCode.unresolvedNumberFormat] carries the number format id
  /// in decimal. Cell-level warnings of one code on one sheet are separate
  /// warnings for each distinct detail, for the first ten details; every
  /// later new detail joins one warning of that code whose detail is null,
  /// so a hostile file cannot make a warning per format id.
  String? get detail => _entry.detail;

  /// How many times the problem occurred: the affected cells of a
  /// cell-level warning, the skipped ranges of
  /// [XlsxWarningCode.mergeRangeInvalid], and 1 for a warning about a whole
  /// sheet (a sheet-name warning or [XlsxWarningCode.sheetPartMissing]).
  int get count => _entry.count;

  /// A1-style references of the first ten affected cells, in the order
  /// they were written or read.
  ///
  /// Empty for a warning that names no cell, such as a sheet-name warning.
  /// An unmodifiable view, the same object on every call, that shows
  /// references added later.
  List<String> get cells => _entry.locations;

  /// A human-readable description in [locale].
  String message([OfficeLocale locale = OfficeLocale.en]) =>
      formatWarning(this, locale);

  /// The English [message].
  @override
  String toString() => message();
}

/// Collects warnings while a workbook is written or read.
///
/// Cell-level codes aggregate by `(key, code, detail)`, where the key is the
/// one given to [add] or else the sheet name; sheet-name codes give one
/// warning per [add] call. Memory stays bounded: a warning keeps at most
/// ten references however often it recurs, and a key and code keep at most
/// ten distinct non-null details. An [add] with an eleventh or later new
/// detail aggregates into the one warning for `(key, code, null)`.
final class WarningCollector {
  final WarningAggregator<XlsxWarningCode> _aggregator =
      WarningAggregator<XlsxWarningCode>();
  final List<XlsxWarning> _warnings = <XlsxWarning>[];
  late final List<XlsxWarning> _warningsView =
      UnmodifiableListView<XlsxWarning>(_warnings);

  /// Records one occurrence of [code] on [sheet].
  ///
  /// [cell] is the A1-style reference for cell-level codes. [originalName] is
  /// the requested name for sheet-name codes. [detail] is the parameter of
  /// the code, if it has one; occurrences with different details are
  /// separate warnings, up to ten details per key and code, after which a
  /// new detail is recorded as null. [key] identifies the sheet for
  /// aggregation and [removeSheet]; it defaults to [sheet], so sheets that
  /// share a name can pass their index to stay apart.
  void add(
    XlsxWarningCode code, {
    required String sheet,
    String? cell,
    String? originalName,
    String? detail,
    Object? key,
  }) {
    final Object owner = key ?? sheet;
    final bool perCall =
        code == XlsxWarningCode.sheetNameChanged ||
        code == XlsxWarningCode.sheetNameDuplicated;
    final int before = _aggregator.all.length;
    final AggregatedWarning<XlsxWarningCode> entry = perCall
        ? _aggregator.addUnaggregated(
            code,
            scope: owner,
            location: cell,
            detail: detail,
          )
        : _aggregator.add(code, scope: owner, location: cell, detail: detail);
    // A new entry is appended; an aggregated one is already wrapped.
    if (_aggregator.all.length > before) {
      _warnings.add(XlsxWarning._(sheet, perCall ? originalName : null, entry));
    }
  }

  /// The warnings so far, in first-occurrence order. An unmodifiable view,
  /// the same object on every call, that shows warnings added later.
  List<XlsxWarning> get warnings => _warningsView;

  /// Drops every warning added under [key], keeping the order of the rest.
  ///
  /// [key] is the `key` given to [add], or the sheet name when none was.
  /// Warnings whose code is in [keep] stay. The aggregation entries of the
  /// dropped warnings go too, so a later [add] starts a fresh warning. The
  /// reader uses it before it reads a sheet again.
  void removeSheet(
    Object key, {
    Set<XlsxWarningCode> keep = const <XlsxWarningCode>{},
  }) {
    _aggregator.removeScope(key, keep: keep);
    _warnings.removeWhere(
      (XlsxWarning w) => w._entry.scope == key && !keep.contains(w.code),
    );
  }
}
