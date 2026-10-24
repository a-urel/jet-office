/// Structured warnings about data the XLSX writer had to change.
///
/// New in jet_office. A warning describes a data problem the writer repaired
/// instead of failing on (decision 0003): a cell lost characters, a sheet was
/// renamed. Cell-level warnings are aggregated per sheet and code, so a column
/// of 100,000 dirty cells yields one warning with a count and the first ten
/// references, not 100,000 objects.
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
}

/// Something the writer changed or could not store exactly.
///
/// Cell-level warnings ([XlsxWarningCode.invalidCharactersRemoved],
/// [XlsxWarningCode.textTruncated], [XlsxWarningCode.intPrecisionLost],
/// [XlsxWarningCode.dateOutsideExcelRange],
/// [XlsxWarningCode.dateInNonDateFormat])
/// cover every affected cell of one sheet: [count] says how many and [cells]
/// names the first ten. Sheet-name warnings
/// ([XlsxWarningCode.sheetNameChanged], [XlsxWarningCode.sheetNameDuplicated])
/// are one per renamed sheet.
///
/// Library users never construct warnings; the writer returns them.
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

/// Collects warnings while a workbook is written.
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
}
