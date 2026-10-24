/// How a worksheet is shown when it is opened: zoom, gridlines, headings,
/// frozen or split panes, and whether the sheet is visible at all.
///
/// Ported from quds_office_engine `lib/src/builders/xlsx_io.dart` at commit 15c5d29.
/// Ported: `freezeRows`, `freezeCols` and `rightToLeft`. What changed: the
/// pane's active part follows the split (Quds wrote `bottomRight` for a
/// rows-only freeze, which Excel does not accept as the active part of a
/// pane that has no right side), a `selection` is written for it, and zoom,
/// gridlines, headings, zeros and formula display are options too. Panes
/// can also be split, not only frozen, and a sheet can be hidden.
library;

import '../xml/xml_number.dart';
import 'limits.dart';

/// The panes of a sheet: frozen at a number of rows and columns, or split
/// at an offset in points.
///
/// Passed in [XlsxSheetView.pane]. Values are compared by their contents.
/// The `const` constructors cannot check their fields; the writer checks
/// them when the view is set and throws [ArgumentError] naming the field.
final class XlsxPane {
  /// A pane frozen below the first [rows] rows and to the right of the
  /// first [columns] columns, which then stay in view while the rest
  /// scrolls. Both are counts, from 0 to the last row (1,048,575) and the
  /// last column (16,383). A pane of 0 rows and 0 columns is no pane.
  const XlsxPane.frozen({this.rows = 0, this.columns = 0})
    : isFrozen = true,
      x = 0,
      y = 0;

  /// A pane split at [x] points from the left edge and [y] points from the
  /// top, both finite and at least 0. The writer stores the offsets in
  /// whole twentieths of a point (twips), rounded: an axis whose offset
  /// rounds to 0 twips does not split, a split of 0 on both axes is no
  /// pane, and an offset of more than 2^31 - 1 twips (above 107,374,182.35
  /// points) is rejected.
  const XlsxPane.split({this.x = 0, this.y = 0})
    : isFrozen = false,
      rows = 0,
      columns = 0;

  /// Whether the panes are frozen; otherwise they are split.
  final bool isFrozen;

  /// The number of frozen rows; 0 for a split.
  final int rows;

  /// The number of frozen columns; 0 for a split.
  final int columns;

  /// The split offset from the left edge in points; 0 for a freeze.
  final double x;

  /// The split offset from the top edge in points; 0 for a freeze.
  final double y;

  @override
  bool operator ==(Object other) =>
      other is XlsxPane &&
      other.isFrozen == isFrozen &&
      other.rows == rows &&
      other.columns == columns &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(isFrozen, rows, columns, x, y);

  @override
  String toString() => isFrozen
      ? 'XlsxPane.frozen(rows: $rows, columns: $columns)'
      : 'XlsxPane.split(x: ${formatXmlDouble(x)}, y: ${formatXmlDouble(y)})';
}

/// The view of one worksheet: how it is displayed when it is opened.
///
/// Passed to `XlsxSheetWriter.view`. Values are compared by their contents.
/// The `const` constructor cannot check its fields; the writer checks them
/// when the view is set and throws [ArgumentError] naming the field.
final class XlsxSheetView {
  /// Creates a view. The defaults are Excel's own.
  ///
  /// [zoom] is a percentage from 10 to 400. [showGridLines] and
  /// [showHeadings] (the row numbers and column letters) show them;
  /// [rightToLeft] mirrors the sheet for right-to-left languages, putting
  /// column A on the right; [showZeros] shows a cell that holds 0, instead
  /// of an empty one; [showFormulas] shows formulas instead of results.
  /// [pane] freezes or splits the sheet, or `null` for neither.
  const XlsxSheetView({
    this.zoom = 100,
    this.showGridLines = true,
    this.showHeadings = true,
    this.rightToLeft = false,
    this.showZeros = true,
    this.showFormulas = false,
    this.pane,
  });

  /// The zoom as a percentage, 10 to 400.
  final int zoom;

  /// Whether the gridlines are shown.
  final bool showGridLines;

  /// Whether the row numbers and column letters are shown.
  final bool showHeadings;

  /// Whether the sheet is laid out right to left.
  final bool rightToLeft;

  /// Whether a cell holding 0 shows the 0.
  final bool showZeros;

  /// Whether formulas are shown instead of their results.
  final bool showFormulas;

  /// The frozen or split panes, or `null` for none.
  final XlsxPane? pane;

  /// A copy in which each given field is replaced.
  ///
  /// A `null` [pane] keeps the current one; to remove it, build a new view.
  XlsxSheetView copyWith({
    int? zoom,
    bool? showGridLines,
    bool? showHeadings,
    bool? rightToLeft,
    bool? showZeros,
    bool? showFormulas,
    XlsxPane? pane,
  }) => XlsxSheetView(
    zoom: zoom ?? this.zoom,
    showGridLines: showGridLines ?? this.showGridLines,
    showHeadings: showHeadings ?? this.showHeadings,
    rightToLeft: rightToLeft ?? this.rightToLeft,
    showZeros: showZeros ?? this.showZeros,
    showFormulas: showFormulas ?? this.showFormulas,
    pane: pane ?? this.pane,
  );

  @override
  bool operator ==(Object other) =>
      other is XlsxSheetView &&
      other.zoom == zoom &&
      other.showGridLines == showGridLines &&
      other.showHeadings == showHeadings &&
      other.rightToLeft == rightToLeft &&
      other.showZeros == showZeros &&
      other.showFormulas == showFormulas &&
      other.pane == pane;

  @override
  int get hashCode => Object.hash(
    zoom,
    showGridLines,
    showHeadings,
    rightToLeft,
    showZeros,
    showFormulas,
    pane,
  );

  @override
  String toString() {
    final List<String> fields = <String>[
      if (zoom != 100) 'zoom: $zoom',
      if (!showGridLines) 'showGridLines: false',
      if (!showHeadings) 'showHeadings: false',
      if (rightToLeft) 'rightToLeft: true',
      if (!showZeros) 'showZeros: false',
      if (showFormulas) 'showFormulas: true',
      if (pane != null) 'pane: $pane',
    ];
    return 'XlsxSheetView(${fields.join(', ')})';
  }
}

/// Whether a worksheet appears among the tabs.
enum XlsxSheetVisibility {
  /// Shown as a tab.
  visible,

  /// Hidden; the user can unhide it from Excel's context menu.
  hidden,

  /// Hidden so that Excel's menus do not offer to unhide it; only a macro
  /// can show it again.
  veryHidden,
}

/// Throws [ArgumentError] unless [view] is within Excel's limits: a zoom
/// from [XlsxLimits.minZoom] to [XlsxLimits.maxZoom] and a valid [XlsxPane].
void checkSheetView(XlsxSheetView view) {
  if (view.zoom < XlsxLimits.minZoom || view.zoom > XlsxLimits.maxZoom) {
    throw ArgumentError.value(
      view.zoom,
      'zoom',
      'A zoom must be between ${XlsxLimits.minZoom} and '
          '${XlsxLimits.maxZoom} percent.',
    );
  }
  final XlsxPane? pane = view.pane;
  if (pane != null) checkPane(pane);
}

/// Throws [ArgumentError] unless [pane] freezes a number of rows from 0 to
/// the last row and of columns from 0 to the last column, or splits at
/// finite offsets of at least 0 and at most 2^31 - 1 twips each.
void checkPane(XlsxPane pane) {
  if (pane.isFrozen) {
    if (pane.rows < 0 || pane.rows >= XlsxLimits.maxRows) {
      throw ArgumentError.value(
        pane.rows,
        'rows',
        'Frozen rows must be between 0 and ${XlsxLimits.maxRows - 1}.',
      );
    }
    if (pane.columns < 0 || pane.columns >= XlsxLimits.maxColumns) {
      throw ArgumentError.value(
        pane.columns,
        'columns',
        'Frozen columns must be between 0 and ${XlsxLimits.maxColumns - 1}.',
      );
    }
    return;
  }
  _checkOffset(pane.x, 'x');
  _checkOffset(pane.y, 'y');
}

/// The largest split offset the writer stores, in twips. `xSplit` and
/// `ySplit` are read as 32-bit signed integers; a larger offset also made
/// `close()` fail on the VM, and the VM and the browser printed huge
/// rounded offsets differently.
const double _maxSplitTwips = 2147483647;

/// Throws unless [offset] is a finite number of points, at least 0, whose
/// twips (`offset * 20`, rounded) do not exceed 2^31 - 1 (ruling R12).
void _checkOffset(double offset, String name) {
  // Written so that NaN fails too.
  if (!(offset >= 0 && offset.isFinite)) {
    throw ArgumentError.value(
      offset,
      name,
      'A split offset must be a finite number of points, at least 0.',
    );
  }
  // In doubles: the product of a huge offset is infinite, and rounding it
  // to an int would throw.
  if ((offset * 20).roundToDouble() > _maxSplitTwips) {
    throw ArgumentError.value(
      offset,
      name,
      'A split offset must be at most 107374182.35 points '
      '(2147483647 twips).',
    );
  }
}
