/// The frame of a worksheet part: everything before the first row (the
/// header) and everything after the last (the trailer).
///
/// Ported from quds_office_engine `lib/src/builders/xlsx_io.dart` at commit 15c5d29.
/// Ported: the `_sheetXml` frame and its `<cols>` writing. What changed: the
/// frame is assembled when the sheet is finished, around rows that were
/// encoded as they arrived, from settings frozen at the first row; widths,
/// heights and outline levels are checked; equal adjacent columns are joined
/// into one `<col>`; columns carry a style, visibility and outline level;
/// `sheetFormatPr` carries the default sizes and the deepest outline levels;
/// numbers are written with `formatXmlDouble`, so the VM and the browser
/// agree. Panes, filters and merges are not ported here yet.
///
/// Children follow the `CT_Worksheet` order: `sheetViews`, `sheetFormatPr`
/// and `cols` before `sheetData`.
library;

import '../opc/ooxml.dart';
import '../xml/xml_number.dart';
import '../xml/xml_writer.dart';
import 'limits.dart';

/// The width Excel gives a column of Calibri 11 when nothing sets one: 8.43
/// characters plus padding, as Excel itself writes it.
const double standardColumnWidth = 9.140625;

/// The row height Excel gives Calibri 11 when nothing sets one, in points.
const double standardRowHeight = 15;

/// One column of a worksheet as the header writes it.
///
/// `width` is `null` for the sheet's default width; `style` is a cell format
/// id, 0 for none. The other fields are those of `XlsxColumn`.
typedef WorksheetColumn = ({
  double? width,
  int style,
  bool hidden,
  int outlineLevel,
  bool collapsed,
});

/// What the header and the trailer of a worksheet are made from.
///
/// Plain, already checked values: the writer validates them when they are
/// set and resolves styles to cell format ids.
final class WorksheetSettings {
  /// Creates the settings of one worksheet.
  const WorksheetSettings({
    this.columns = const <WorksheetColumn?>[],
    this.defaultColumnWidth,
    this.defaultRowHeight,
    this.outlineLevelRow = 0,
  });

  /// The columns from A on; `null` keeps a column at its default.
  final List<WorksheetColumn?> columns;

  /// The sheet's default column width in characters, or `null` for Excel's.
  final double? defaultColumnWidth;

  /// The sheet's default row height in points, or `null` for Excel's.
  final double? defaultRowHeight;

  /// The deepest outline level of the rows written.
  final int outlineLevelRow;
}

/// The `<worksheet>` frame before the rows: the XML declaration, the
/// `<worksheet>` start tag, `sheetViews`, `sheetFormatPr` when a default
/// size or an outline level calls for it, `cols` when a column differs from
/// the default, and `<sheetData>`.
///
/// When [hasRows] is false, `sheetData` is written empty (`<sheetData/>`)
/// and [worksheetTrailer] must be called with `hasRows: false` too.
String worksheetHeader(WorksheetSettings settings, {required bool hasRows}) {
  final StringBuffer out = StringBuffer();
  final XmlWriter w = XmlWriter(out);
  w.declaration();
  w.raw('<worksheet xmlns="${Ns.main}" xmlns:r="${Ns.rel}">');
  w.raw('<sheetViews><sheetView workbookViewId="0"/></sheetViews>');
  final List<_ColumnRun> runs = _runs(settings.columns);
  _writeSheetFormat(w, settings, runs);
  _writeCols(w, settings, runs);
  w.raw(hasRows ? '<sheetData>' : '<sheetData/>');
  return out.toString();
}

/// The `<worksheet>` frame after the rows: `</sheetData>` when [hasRows],
/// then `</worksheet>`. [hasRows] must match the call to [worksheetHeader].
String worksheetTrailer(WorksheetSettings settings, {required bool hasRows}) =>
    hasRows ? '</sheetData></worksheet>' : '</worksheet>';

/// Adjacent columns that write the same `<col>`, from `min` to `max`
/// (1-based, inclusive).
typedef _ColumnRun = ({int min, int max, WorksheetColumn column});

/// Whether [c] differs from a default column at all.
bool _setsSomething(WorksheetColumn c) =>
    c.width != null ||
    c.style != 0 ||
    c.hidden ||
    c.outlineLevel != 0 ||
    c.collapsed;

/// [columns] as runs of equal adjacent columns, skipping those that set
/// nothing. Records compare by value, so equal columns join.
List<_ColumnRun> _runs(List<WorksheetColumn?> columns) {
  final List<_ColumnRun> runs = <_ColumnRun>[];
  for (int i = 0; i < columns.length; i++) {
    final WorksheetColumn? column = columns[i];
    if (column == null || !_setsSomething(column)) continue;
    final int number = i + 1;
    if (runs.isNotEmpty &&
        runs.last.max == number - 1 &&
        runs.last.column == column) {
      runs.last = (min: runs.last.min, max: number, column: column);
    } else {
      runs.add((min: number, max: number, column: column));
    }
  }
  return runs;
}

/// Writes `sheetFormatPr` when the sheet has a default size or an outline.
///
/// Attributes in `CT_SheetFormatPr` order; `defaultRowHeight` is required by
/// the schema, so it is written even when only an outline level calls for
/// the element.
void _writeSheetFormat(
  XmlWriter w,
  WorksheetSettings settings,
  List<_ColumnRun> runs,
) {
  int outlineLevelCol = 0;
  for (final _ColumnRun run in runs) {
    if (run.column.outlineLevel > outlineLevelCol) {
      outlineLevelCol = run.column.outlineLevel;
    }
  }
  final double? columnWidth = settings.defaultColumnWidth;
  final double? rowHeight = settings.defaultRowHeight;
  if (columnWidth == null &&
      rowHeight == null &&
      settings.outlineLevelRow == 0 &&
      outlineLevelCol == 0) {
    return;
  }
  w.start('sheetFormatPr');
  if (columnWidth != null) {
    w.attribute('defaultColWidth', formatXmlDouble(columnWidth));
  }
  w.attribute(
    'defaultRowHeight',
    formatXmlDouble(rowHeight ?? standardRowHeight),
  );
  if (rowHeight != null) w.attribute('customHeight', '1');
  if (settings.outlineLevelRow > 0) {
    w.attribute('outlineLevelRow', '${settings.outlineLevelRow}');
  }
  if (outlineLevelCol > 0) {
    w.attribute('outlineLevelCol', '$outlineLevelCol');
  }
  w.end();
}

/// Writes `cols` for [runs], unless there are none.
///
/// Attributes in `CT_Col` order. A column without its own width writes the
/// sheet's default width, or [standardColumnWidth], without `customWidth`:
/// `width` is required whenever a `<col>` is written.
void _writeCols(
  XmlWriter w,
  WorksheetSettings settings,
  List<_ColumnRun> runs,
) {
  if (runs.isEmpty) return;
  final double defaultWidth =
      settings.defaultColumnWidth ?? standardColumnWidth;
  w.start('cols');
  for (final _ColumnRun run in runs) {
    final WorksheetColumn c = run.column;
    w.start('col');
    w.attribute('min', '${run.min}');
    w.attribute('max', '${run.max}');
    w.attribute('width', formatXmlDouble(c.width ?? defaultWidth));
    if (c.style != 0) w.attribute('style', '${c.style}');
    if (c.hidden) w.attribute('hidden', '1');
    if (c.width != null) w.attribute('customWidth', '1');
    if (c.outlineLevel != 0) w.attribute('outlineLevel', '${c.outlineLevel}');
    if (c.collapsed) w.attribute('collapsed', '1');
    w.end();
  }
  w.end();
}

/// Throws [ArgumentError] named [name] unless [width] is a column width from
/// 0 to [XlsxLimits.maxColumnWidth] characters.
void checkColumnWidth(double width, String name) {
  // Written so that NaN fails too.
  if (!(width >= 0 && width <= XlsxLimits.maxColumnWidth)) {
    throw ArgumentError.value(
      width,
      name,
      'A column width must be between 0 and ${XlsxLimits.maxColumnWidth} '
      'characters.',
    );
  }
}

/// Throws [ArgumentError] named [name] unless [height] is a row height from
/// 0 to [XlsxLimits.maxRowHeight] points.
void checkRowHeight(double height, String name) {
  if (!(height >= 0 && height <= XlsxLimits.maxRowHeight)) {
    throw ArgumentError.value(
      height,
      name,
      'A row height must be between 0 and ${XlsxLimits.maxRowHeight} points.',
    );
  }
}

/// Throws [ArgumentError] named [name] unless [level] is an outline level
/// from 0 to [XlsxLimits.maxOutlineLevel].
void checkOutlineLevel(int level, String name) {
  if (level < 0 || level > XlsxLimits.maxOutlineLevel) {
    throw ArgumentError.value(
      level,
      name,
      'An outline level must be between 0 and ${XlsxLimits.maxOutlineLevel}.',
    );
  }
}
