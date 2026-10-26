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
/// carries their external targets and then the sheet's drawing, VML
/// drawing, comments and tables, all with ids that [SheetRelationships]
/// assigns in one place; `conditionalFormatting` (see
/// `conditional_format.dart`) and `dataValidations` (see
/// `data_validation.dart`) come between them, where Quds wrote both before
/// `mergeCells`; the `extLst` of the Excel 2010 conditional formats (see
/// `conditional_format_x14.dart`) comes last; the page setup (see
/// `page_setup.dart`) writes `pageSetUpPr` in `sheetPr` and, after
/// `hyperlinks`, `printOptions`, `pageMargins` and `pageSetup`; the header and
/// footer (see `header_footer.dart`) write `headerFooter` after `pageSetup`;
/// the protection (see `sheet_protection.dart`) writes `sheetProtection`
/// right after `sheetData`, where Quds wrote it after `autoFilter`;
/// `drawing`, `legacyDrawing` and `tableParts` refer to the sheet's
/// pictures, notes and tables by relationship id.
///
/// Children follow the `CT_Worksheet` order: `sheetPr`, `sheetViews`,
/// `sheetFormatPr` and `cols` before `sheetData`, then `sheetProtection`,
/// `autoFilter`, `mergeCells`, `conditionalFormatting`, `dataValidations`,
/// `hyperlinks`, `printOptions`, `pageMargins`, `pageSetup`, `headerFooter`,
/// `drawing`, `legacyDrawing`, `tableParts` and `extLst`.
library;

import '../opc/ooxml.dart';
import '../opc/relationships.dart';
import '../xml/xml_escape.dart';
import '../xml/xml_number.dart';
import '../xml/xml_writer.dart';
import 'cell_ref.dart';
import 'color.dart';
import 'conditional_format.dart';
import 'conditional_format_x14.dart';
import 'data_validation.dart';
import 'header_footer.dart';
import 'limits.dart';
import 'page_setup.dart';
import 'range.dart';
import 'sheet_protection.dart';
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
    required this.sheetNumber,
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
    this.conditionalFormats = const <WorksheetConditionalFormat>[],
    this.dataValidations = const <XlsxDataValidation>[],
    this.hyperlinks = const <WorksheetHyperlink>[],
    this.pageSetup,
    this.headerFooter,
    this.protection,
    this.drawingId,
    this.legacyDrawingId,
    this.tablePartIds = const <String>[],
  });

  /// The sheet's 1-based creation order, which the ids of its Excel 2010
  /// conditional-format rules carry.
  final int sheetNumber;

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

  /// The conditional formats, in the order they were registered, with
  /// their dxf ids and priorities.
  final List<WorksheetConditionalFormat> conditionalFormats;

  /// The data validations, in the order they were added.
  final List<XlsxDataValidation> dataValidations;

  /// The hyperlinks, in cell order of writing.
  final List<WorksheetHyperlink> hyperlinks;

  /// How the sheet prints, or `null` for no page setup.
  final XlsxPageSetup? pageSetup;

  /// The text printed in the margins, or `null` for none.
  final XlsxHeaderFooter? headerFooter;

  /// What the sheet's protection allows, or `null` for an unprotected sheet.
  final XlsxSheetProtection? protection;

  /// The relationship id of the sheet's drawing part, its pictures, or
  /// `null` for none (see [SheetRelationships.drawingId]).
  final String? drawingId;

  /// The relationship id of the sheet's VML drawing part, the boxes of its
  /// notes, or `null` for none (see [SheetRelationships.vmlDrawingId]).
  final String? legacyDrawingId;

  /// The relationship ids of the sheet's table parts, in table order (see
  /// [SheetRelationships.tableIds]).
  final List<String> tablePartIds;
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
/// then `sheetProtection`, `autoFilter`, `mergeCells`, `conditionalFormatting`,
/// `dataValidations`, `hyperlinks`, the page setup's `printOptions`,
/// `pageMargins`, `pageSetup` and `headerFooter`, the `drawing`,
/// `legacyDrawing` and `tableParts` references, and the `extLst` of the
/// Excel 2010 conditional formats when the sheet has them, then `</worksheet>`.
/// [hasRows] must match the call to [worksheetHeader].
String worksheetTrailer(WorksheetSettings settings, {required bool hasRows}) {
  final StringBuffer out = StringBuffer();
  final XmlWriter w = XmlWriter(out);
  if (hasRows) w.raw('</sheetData>');
  final XlsxSheetProtection? protection = settings.protection;
  if (protection != null) writeSheetProtection(w, protection);
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
  writeConditionalFormats(w, settings.conditionalFormats, settings.sheetNumber);
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
  final XlsxPageSetup? pageSetup = settings.pageSetup;
  if (pageSetup != null) writePageSetup(w, pageSetup);
  final XlsxHeaderFooter? headerFooter = settings.headerFooter;
  if (headerFooter != null) writeHeaderFooter(w, headerFooter);
  final String? drawingId = settings.drawingId;
  if (drawingId != null) {
    w.empty('drawing', <String, String>{'r:id': drawingId});
  }
  final String? legacyDrawingId = settings.legacyDrawingId;
  if (legacyDrawingId != null) {
    w.empty('legacyDrawing', <String, String>{'r:id': legacyDrawingId});
  }
  if (settings.tablePartIds.isNotEmpty) {
    w.start('tableParts');
    w.attribute('count', '${settings.tablePartIds.length}');
    for (final String id in settings.tablePartIds) {
      w.empty('tablePart', <String, String>{'r:id': id});
    }
    w.end();
  }
  // Last: CT_Worksheet ends with extLst.
  writeX14ConditionalFormats(
    w,
    settings.conditionalFormats,
    settings.sheetNumber,
  );
  w.raw('</worksheet>');
  return out.toString();
}

/// The ZIP entry name of the relationships part of the worksheet created
/// [number]th (1-based).
String worksheetRelsPartName(int number) =>
    'xl/worksheets/_rels/sheet$number.xml.rels';

/// The ZIP entry name of the drawing part, the pictures, of the worksheet
/// created [sheetNumber]th (1-based).
String drawingPartName(int sheetNumber) =>
    'xl/drawings/drawing$sheetNumber.xml';

/// The ZIP entry name of the relationships part of the drawing of the
/// worksheet created [sheetNumber]th (1-based).
String drawingRelsPartName(int sheetNumber) =>
    'xl/drawings/_rels/drawing$sheetNumber.xml.rels';

/// The ZIP entry name of the VML drawing part, the boxes of the notes, of
/// the worksheet created [sheetNumber]th (1-based).
String vmlDrawingPartName(int sheetNumber) =>
    'xl/drawings/vmlDrawing$sheetNumber.vml';

/// The ZIP entry name of the comments part, the text of the notes, of the
/// worksheet created [sheetNumber]th (1-based).
String commentsPartName(int sheetNumber) => 'xl/comments$sheetNumber.xml';

/// The ZIP entry name of the table numbered [id], counted across the
/// workbook.
String tablePartName(int id) => 'xl/tables/table$id.xml';

/// The ZIP entry name of the image numbered [number], counted across the
/// workbook, with the file [extension] (without the dot).
String mediaPartName(int number, String extension) =>
    'xl/media/image$number.$extension';

/// The target of the part [partName], under `xl/`, relative to a worksheet
/// part in `xl/worksheets/`.
String _fromWorksheet(String partName) =>
    '../${partName.substring('xl/'.length)}';

/// The relationships of one worksheet: the one place their ids are
/// assigned.
///
/// The worksheet refers to its objects by these ids (`hyperlink`,
/// `drawing`, `legacyDrawing`, `tablePart`) and [toXml] declares them, so
/// both take them from here. Ids are `rId1`, `rId2`, ... with no gap,
/// counting across the kinds in this order: the hyperlink targets, the
/// drawing, the VML drawing, the comments, then the tables. A kind the
/// sheet does not have takes no id, so the ids depend only on what the
/// sheet holds (spec §4.6).
final class SheetRelationships {
  /// Assigns the ids of a worksheet created [sheetNumber]th (1-based).
  ///
  /// [hyperlinkTargets] are the distinct addresses of its external links,
  /// in first-use order; a repeated address keeps its first id. [drawing]
  /// asks for a drawing part, [notes] for a VML drawing and a comments
  /// part, and [tableIds] lists the workbook-wide ids of its tables, in the
  /// order they were added.
  factory SheetRelationships({
    required int sheetNumber,
    Iterable<String> hyperlinkTargets = const <String>[],
    bool drawing = false,
    bool notes = false,
    List<int> tableIds = const <int>[],
  }) {
    int count = 0;
    String next() => 'rId${++count}';
    final Map<String, String> links = <String, String>{};
    for (final String target in hyperlinkTargets) {
      links.putIfAbsent(target, next);
    }
    final String? drawingId = drawing ? next() : null;
    final String? vmlDrawingId = notes ? next() : null;
    final String? commentsId = notes ? next() : null;
    final List<int> tables = List<int>.unmodifiable(tableIds);
    return SheetRelationships._(
      sheetNumber,
      Map<String, String>.unmodifiable(links),
      drawingId,
      vmlDrawingId,
      commentsId,
      tables,
      List<String>.unmodifiable(<String>[for (final int _ in tables) next()]),
    );
  }

  SheetRelationships._(
    this.sheetNumber,
    this.hyperlinkIds,
    this.drawingId,
    this.vmlDrawingId,
    this.commentsId,
    this._tables,
    this.tableIds,
  );

  /// The 1-based creation order of the worksheet, which numbers its
  /// drawing, VML drawing and comments parts.
  final int sheetNumber;

  /// Each external link address and its relationship id, in first-use
  /// order: `rId1`, `rId2`, ...
  final Map<String, String> hyperlinkIds;

  /// The relationship id of the drawing part, or `null` when the sheet has
  /// no drawing.
  final String? drawingId;

  /// The relationship id of the VML drawing part, or `null` when the sheet
  /// has no notes.
  final String? vmlDrawingId;

  /// The relationship id of the comments part, or `null` when the sheet has
  /// no notes.
  final String? commentsId;

  /// The workbook-wide ids of the sheet's tables, in [tableIds] order.
  final List<int> _tables;

  /// The relationship ids of the table parts, in the order of the tables.
  final List<String> tableIds;

  /// Renders the worksheet's relationships part, or returns `null` when
  /// the sheet has no relationship.
  ///
  /// Relationships are written in id order. Link targets are external and
  /// written as given (the caller has percent-encoded them); the other
  /// targets are relative to the worksheet: `../drawings/drawing{n}.xml`,
  /// `../drawings/vmlDrawing{n}.vml`, `../comments{n}.xml`, with `n` the
  /// [sheetNumber], and `../tables/table{id}.xml`.
  String? toXml() {
    // A comments id comes only with a VML drawing id: no check of its own.
    if (hyperlinkIds.isEmpty &&
        drawingId == null &&
        vmlDrawingId == null &&
        tableIds.isEmpty) {
      return null;
    }
    final Relationships rels = Relationships();
    for (final MapEntry<String, String> e in hyperlinkIds.entries) {
      rels.add(RelType.hyperlink, e.key, id: e.value, external: true);
    }
    final String? drawing = drawingId;
    if (drawing != null) {
      rels.add(
        RelType.drawing,
        _fromWorksheet(drawingPartName(sheetNumber)),
        id: drawing,
      );
    }
    final String? vml = vmlDrawingId;
    if (vml != null) {
      rels.add(
        RelType.vmlDrawing,
        _fromWorksheet(vmlDrawingPartName(sheetNumber)),
        id: vml,
      );
    }
    final String? comments = commentsId;
    if (comments != null) {
      rels.add(
        RelType.comments,
        _fromWorksheet(commentsPartName(sheetNumber)),
        id: comments,
      );
    }
    for (int i = 0; i < _tables.length; i++) {
      rels.add(
        RelType.table,
        _fromWorksheet(tablePartName(_tables[i])),
        id: tableIds[i],
      );
    }
    final StringBuffer out = StringBuffer();
    rels.write(XmlWriter(out));
    return out.toString();
  }
}

/// Writes `sheetPr` when the sheet has a tab color, an outline summary that
/// is not Excel's default (below and right) or a page setup that fits the
/// sheet to pages.
void _writeSheetPr(XmlWriter w, WorksheetSettings settings) {
  final XlsxColor? tabColor = settings.tabColor;
  final XlsxPageSetup? pageSetup = settings.pageSetup;
  final bool fitToPage = pageSetup != null && pageSetupFitsToPage(pageSetup);
  if (tabColor == null &&
      settings.summaryBelow &&
      settings.summaryRight &&
      !fitToPage) {
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
  if (fitToPage) w.empty('pageSetUpPr', <String, String>{'fitToPage': '1'});
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
