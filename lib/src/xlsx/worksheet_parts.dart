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
/// agree; `sheetPr` carries the tab color and the outline summary position;
/// `sheetView` carries zoom, gridlines, headings, zeros, formulas and
/// right-to-left, and the pane of `sheet_view.dart` with its `selection`;
/// the trailer writes `autoFilter` and `mergeCells` from ranges that the
/// writer has validated (Quds wrote any filter string unchecked and accepted
/// overlapping merges); `hyperlinks` come from links the writer has
/// validated, and the sheet's relationships part, which Quds did not write,
/// carries their external targets; `dataValidations` (see
/// `data_validation.dart`) come between them, where Quds wrote them before
/// `mergeCells`.
///
/// Children follow the `CT_Worksheet` order: `sheetPr`, `sheetViews`,
/// `sheetFormatPr` and `cols` before `sheetData`, then `autoFilter`,
/// `mergeCells`, `dataValidations` and `hyperlinks`.
library;

import '../opc/ooxml.dart';
import '../opc/relationships.dart';
import '../xml/xml_escape.dart';
import '../xml/xml_number.dart';
import '../xml/xml_writer.dart';
import 'cell_ref.dart';
import 'color.dart';
import 'data_validation.dart';
import 'limits.dart';
import 'range.dart';
import 'sheet_view.dart';

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

/// One `hyperlink` element as the trailer writes it.
///
/// `relationshipId` is the `r:id` of an external link, `null` for an
/// internal one; `location` and `tooltip` are `null` when absent. The
/// strings are unescaped: the trailer applies `escapeXstring`.
typedef WorksheetHyperlink = ({
  String ref,
  String? relationshipId,
  String? location,
  String? tooltip,
  String display,
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
    this.view = const XlsxSheetView(),
    this.tabColor,
    this.summaryBelow = true,
    this.summaryRight = true,
    this.autoFilter,
    this.merges = const <XlsxRange>[],
    this.dataValidations = const <XlsxDataValidation>[],
    this.hyperlinks = const <WorksheetHyperlink>[],
  });

  /// The columns from A on; `null` keeps a column at its default.
  final List<WorksheetColumn?> columns;

  /// The sheet's default column width in characters, or `null` for Excel's.
  final double? defaultColumnWidth;

  /// The sheet's default row height in points, or `null` for Excel's.
  final double? defaultRowHeight;

  /// The deepest outline level of the rows written.
  final int outlineLevelRow;

  /// How the sheet is shown: zoom, gridlines, headings and panes.
  final XlsxSheetView view;

  /// The color of the sheet's tab, or `null` for none.
  final XlsxColor? tabColor;

  /// Whether the summary row of an outline group is below its detail rows.
  final bool summaryBelow;

  /// Whether the summary column of an outline group is right of its detail
  /// columns.
  final bool summaryRight;

  /// The range of the sheet's auto filter, or `null` for none.
  final XlsxRange? autoFilter;

  /// The merged ranges, in the order they were merged.
  final List<XlsxRange> merges;

  /// The data validations, in the order they were added.
  final List<XlsxDataValidation> dataValidations;

  /// The hyperlinks, in cell order of writing.
  final List<WorksheetHyperlink> hyperlinks;
}

/// The `<worksheet>` frame before the rows: the XML declaration, the
/// `<worksheet>` start tag, `sheetPr` when a tab color or an outline summary
/// position calls for it, `sheetViews`, `sheetFormatPr` when a default
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
  _writeSheetPr(w, settings);
  _writeSheetViews(w, settings.view);
  final List<_ColumnRun> runs = _runs(settings.columns);
  _writeSheetFormat(w, settings, runs);
  _writeCols(w, settings, runs);
  w.raw(hasRows ? '<sheetData>' : '<sheetData/>');
  return out.toString();
}

/// The `<worksheet>` frame after the rows: `</sheetData>` when [hasRows],
/// then `autoFilter`, `mergeCells`, `dataValidations` and `hyperlinks` when
/// the sheet has them,
/// then `</worksheet>`. [hasRows] must match the call to [worksheetHeader].
String worksheetTrailer(WorksheetSettings settings, {required bool hasRows}) {
  final StringBuffer out = StringBuffer();
  final XmlWriter w = XmlWriter(out);
  if (hasRows) w.raw('</sheetData>');
  final XlsxRange? filter = settings.autoFilter;
  if (filter != null) {
    w.empty('autoFilter', <String, String>{'ref': filter.ref});
  }
  if (settings.merges.isNotEmpty) {
    w.start('mergeCells');
    w.attribute('count', '${settings.merges.length}');
    for (final XlsxRange merge in settings.merges) {
      w.empty('mergeCell', <String, String>{'ref': merge.ref});
    }
    w.end();
  }
  writeDataValidations(w, settings.dataValidations);
  if (settings.hyperlinks.isNotEmpty) {
    w.start('hyperlinks');
    for (final WorksheetHyperlink link in settings.hyperlinks) {
      // CT_Hyperlink attribute order: ref, r:id, location, tooltip, display.
      final String? id = link.relationshipId;
      final String? location = link.location;
      final String? tooltip = link.tooltip;
      w.empty('hyperlink', <String, String>{
        'ref': link.ref,
        'r:id': ?id,
        if (location != null) 'location': escapeXstring(location),
        if (tooltip != null) 'tooltip': escapeXstring(tooltip),
        'display': escapeXstring(link.display),
      });
    }
    w.end();
  }
  w.raw('</worksheet>');
  return out.toString();
}

/// The ZIP entry name of the relationships part of the worksheet created
/// [number]th (1-based).
String worksheetRelsPartName(int number) =>
    'xl/worksheets/_rels/sheet$number.xml.rels';

/// Renders the relationships part of a worksheet whose external hyperlink
/// targets are [addresses], or returns `null` when there are none.
///
/// The relationship ids are `rId1`, `rId2`, ... in the order of [addresses],
/// so address `i` is `rId${i + 1}`. The targets are written as given; the
/// caller has percent-encoded them.
String? worksheetRelationshipsXml(List<String> addresses) {
  if (addresses.isEmpty) return null;
  final Relationships rels = Relationships();
  for (final String address in addresses) {
    rels.add(RelType.hyperlink, address, external: true);
  }
  final StringBuffer out = StringBuffer();
  rels.write(XmlWriter(out));
  return out.toString();
}

/// Writes `sheetPr` when the sheet has a tab color or an outline summary
/// that is not Excel's default (below and right).
void _writeSheetPr(XmlWriter w, WorksheetSettings settings) {
  final XlsxColor? tabColor = settings.tabColor;
  if (tabColor == null && settings.summaryBelow && settings.summaryRight) {
    return;
  }
  w.start('sheetPr');
  if (tabColor != null) {
    w.start('tabColor');
    writeColorAttributes(w, tabColor);
    w.end();
  }
  if (!settings.summaryBelow || !settings.summaryRight) {
    w.start('outlinePr');
    if (!settings.summaryBelow) w.attribute('summaryBelow', '0');
    if (!settings.summaryRight) w.attribute('summaryRight', '0');
    w.end();
  }
  w.end();
}

/// Writes `sheetViews` with the one view of [view].
///
/// Attributes in `CT_SheetView` order, those that differ from Excel's
/// default only, then `pane` and `selection`.
void _writeSheetViews(XmlWriter w, XlsxSheetView view) {
  w.start('sheetViews');
  w.start('sheetView');
  if (view.showFormulas) w.attribute('showFormulas', '1');
  if (!view.showGridLines) w.attribute('showGridLines', '0');
  if (!view.showHeadings) w.attribute('showRowColHeaders', '0');
  if (!view.showZeros) w.attribute('showZeros', '0');
  if (view.rightToLeft) w.attribute('rightToLeft', '1');
  if (view.zoom != 100) w.attribute('zoomScale', '${view.zoom}');
  w.attribute('workbookViewId', '0');
  final XlsxPane? pane = view.pane;
  if (pane != null) _writePane(w, pane);
  w.end();
  w.end();
}

/// The twips in a point: split offsets are stored in twentieths of a point.
const int _twipsPerPoint = 20;

/// Writes `pane` and `selection` for [pane], or nothing when it splits
/// nothing.
///
/// A split offset is rounded to whole twips; an axis that rounds to 0 does
/// not split. The active part is the one the splits leave: `topRight` when
/// only the columns split, `bottomLeft` when only the rows do, `bottomRight`
/// when both do. A frozen pane also gives the top-left cell of that part.
void _writePane(XmlWriter w, XlsxPane pane) {
  final int x = pane.isFrozen
      ? pane.columns
      : (pane.x * _twipsPerPoint).round();
  final int y = pane.isFrozen ? pane.rows : (pane.y * _twipsPerPoint).round();
  if (x == 0 && y == 0) return;
  final String active = x == 0
      ? 'bottomLeft'
      : y == 0
      ? 'topRight'
      : 'bottomRight';
  w.start('pane');
  if (x != 0) w.attribute('xSplit', '$x');
  if (y != 0) w.attribute('ySplit', '$y');
  if (pane.isFrozen) {
    w.attribute('topLeftCell', cellRef(pane.rows, pane.columns));
  }
  w.attribute('activePane', active);
  if (pane.isFrozen) w.attribute('state', 'frozen');
  w.end();
  w.empty('selection', <String, String>{'pane': active});
}

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
