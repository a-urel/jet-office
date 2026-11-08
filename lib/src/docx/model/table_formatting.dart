/// The values of table, row and cell properties: widths, layout, alignment,
/// borders, margins, the table look, row height, merging, vertical
/// alignment and text direction.
///
/// Not ported from Quds; written for jet_office.
///
/// Lengths are points at the API and twips in the file, rounded, as in
/// `formatting.dart`: a value set reads back rounded, two values are equal
/// when their stored numbers are. A bad argument throws [ArgumentError] (not
/// finite) or [RangeError] (out of range once rounded).
library;

import '../units.dart';
import 'formatting.dart';

/// The largest percentage of a [DocxTableWidth.percent]: 1000 per cent
/// (50,000 fiftieths of a per cent, which every platform reads exactly).
const int maxTableWidthFiftieths = 50000;

/// What a [DocxTableWidth] measures in.
enum DocxTableWidthKind {
  /// The width follows the content (`auto`).
  auto,

  /// A length in points (`dxa`, twips in the file).
  points,

  /// A share of the table or page width (`pct`, fiftieths in the file).
  percent,

  /// No width (`nil`).
  nil,
}

/// A width of a table (`w:tblW`) or a cell (`w:tcW`), in one of four kinds.
///
/// A `w:type` that is missing reads as `dxa` (points). A width in per cent
/// written as text with a `%` sign has no view, nor has a number that is out
/// of range or not whole.
final class DocxTableWidth {
  /// The width the content decides.
  const DocxTableWidth.auto() : this._(DocxTableWidthKind.auto, 0);

  /// No width.
  const DocxTableWidth.nil() : this._(DocxTableWidthKind.nil, 0);

  /// A width of [widthPt] points, from 0 to 1584, stored in twips.
  ///
  /// Throws [ArgumentError] when [widthPt] is not finite and [RangeError]
  /// when it is out of range once rounded.
  factory DocxTableWidth.points(double widthPt) => DocxTableWidth._(
    DocxTableWidthKind.points,
    twipsOf(widthPt, 'widthPt', min: 0, max: maxTwips),
  );

  /// A width of [percent] per cent, from 0 to 1000, stored in fiftieths of
  /// a per cent.
  ///
  /// Throws [ArgumentError] when [percent] is not finite and [RangeError]
  /// when it is out of range once rounded.
  factory DocxTableWidth.percent(double percent) {
    if (!percent.isFinite) {
      throw ArgumentError.value(percent, 'percent', 'must be a finite number');
    }
    final double scaled = percent * 50;
    final int n = scaled.abs() > 1e12
        ? (scaled < 0 ? -1 : maxTableWidthFiftieths + 1)
        : scaled.round();
    if (n < 0 || n > maxTableWidthFiftieths) {
      throw RangeError.range(
        n,
        0,
        maxTableWidthFiftieths,
        'percent',
        'must be from 0 to ${maxTableWidthFiftieths / 50} per cent',
      );
    }
    return DocxTableWidth._(DocxTableWidthKind.percent, n);
  }

  const DocxTableWidth._(this.kind, this._stored);

  /// What the width measures in.
  final DocxTableWidthKind kind;

  /// Twips for [DocxTableWidthKind.points], fiftieths of a per cent for
  /// [DocxTableWidthKind.percent], 0 otherwise.
  final int _stored;

  /// The width in points, or `null` unless [kind] is
  /// [DocxTableWidthKind.points].
  double? get widthPt =>
      kind == DocxTableWidthKind.points ? ptOfTwips(_stored) : null;

  /// The width in per cent, or `null` unless [kind] is
  /// [DocxTableWidthKind.percent].
  double? get percent =>
      kind == DocxTableWidthKind.percent ? _stored / 50 : null;

  @override
  bool operator ==(Object other) =>
      other is DocxTableWidth && other.kind == kind && other._stored == _stored;

  @override
  int get hashCode => Object.hash(kind, _stored);

  @override
  String toString() => switch (kind) {
    DocxTableWidthKind.auto => 'DocxTableWidth.auto()',
    DocxTableWidthKind.nil => 'DocxTableWidth.nil()',
    DocxTableWidthKind.points => 'DocxTableWidth.points($widthPt)',
    DocxTableWidthKind.percent => 'DocxTableWidth.percent($percent)',
  };
}

/// How a table lays out its columns (`w:tblLayout`).
enum DocxTableLayout {
  /// The columns keep the widths the file gives.
  fixed,

  /// The columns follow their content.
  autofit,
}

/// How a table lines up between the margins (`w:jc` of a table). `start`
/// and `end` and every other spelling have no view.
enum DocxTableAlignment {
  /// At the left margin.
  left,

  /// Centered.
  center,

  /// At the right margin.
  right,
}

/// The borders of a table (`w:tblBorders`): the four outer sides and the
/// lines between rows and between columns.
///
/// An element with a side named `w:start` or `w:end`, a side twice or a
/// child the model does not know has no view.
final class DocxTableBorders {
  /// The borders of the given sides.
  const DocxTableBorders({
    this.top,
    this.left,
    this.bottom,
    this.right,
    this.insideHorizontal,
    this.insideVertical,
  });

  /// The border above the table.
  final DocxBorder? top;

  /// The border at the left.
  final DocxBorder? left;

  /// The border below the table.
  final DocxBorder? bottom;

  /// The border at the right.
  final DocxBorder? right;

  /// The line between two rows.
  final DocxBorder? insideHorizontal;

  /// The line between two columns.
  final DocxBorder? insideVertical;

  @override
  bool operator ==(Object other) =>
      other is DocxTableBorders &&
      other.top == top &&
      other.left == left &&
      other.bottom == bottom &&
      other.right == right &&
      other.insideHorizontal == insideHorizontal &&
      other.insideVertical == insideVertical;

  @override
  int get hashCode =>
      Object.hash(top, left, bottom, right, insideHorizontal, insideVertical);

  @override
  String toString() =>
      'DocxTableBorders(top: $top, left: $left, bottom: $bottom, '
      'right: $right, insideHorizontal: $insideHorizontal, '
      'insideVertical: $insideVertical)';
}

/// The borders of a cell (`w:tcBorders`): the four sides, the lines inside a
/// merged cell and the two diagonals.
///
/// The same views and refusals as [DocxTableBorders].
final class DocxCellBorders {
  /// The borders of the given sides.
  const DocxCellBorders({
    this.top,
    this.left,
    this.bottom,
    this.right,
    this.insideHorizontal,
    this.insideVertical,
    this.topLeftToBottomRight,
    this.topRightToBottomLeft,
  });

  /// The border above the cell.
  final DocxBorder? top;

  /// The border at the left.
  final DocxBorder? left;

  /// The border below the cell.
  final DocxBorder? bottom;

  /// The border at the right.
  final DocxBorder? right;

  /// The line between the rows of a cell that spans rows.
  final DocxBorder? insideHorizontal;

  /// The line between the columns of a cell that spans columns.
  final DocxBorder? insideVertical;

  /// The diagonal from the top left corner to the bottom right one.
  final DocxBorder? topLeftToBottomRight;

  /// The diagonal from the top right corner to the bottom left one.
  final DocxBorder? topRightToBottomLeft;

  @override
  bool operator ==(Object other) =>
      other is DocxCellBorders &&
      other.top == top &&
      other.left == left &&
      other.bottom == bottom &&
      other.right == right &&
      other.insideHorizontal == insideHorizontal &&
      other.insideVertical == insideVertical &&
      other.topLeftToBottomRight == topLeftToBottomRight &&
      other.topRightToBottomLeft == topRightToBottomLeft;

  @override
  int get hashCode => Object.hash(
    top,
    left,
    bottom,
    right,
    insideHorizontal,
    insideVertical,
    topLeftToBottomRight,
    topRightToBottomLeft,
  );

  @override
  String toString() =>
      'DocxCellBorders(top: $top, left: $left, bottom: $bottom, '
      'right: $right, insideHorizontal: $insideHorizontal, '
      'insideVertical: $insideVertical, '
      'topLeftToBottomRight: $topLeftToBottomRight, '
      'topRightToBottomLeft: $topRightToBottomLeft)';
}

/// The default margins inside the cells of a table (`w:tblCellMar`), in
/// points.
///
/// Each member is `null` when the file has none. A value is stored in twips
/// (0 to 1584 points) and reads back rounded. A side that is not in `dxa`,
/// or named `w:start` or `w:end`, gives the element no view.
final class DocxTableMargins {
  /// Margins of the given sides, each from 0 to 1584 points.
  ///
  /// Throws [ArgumentError] for a value that is not finite and [RangeError]
  /// for one out of range once rounded.
  factory DocxTableMargins({
    double? topPt,
    double? leftPt,
    double? bottomPt,
    double? rightPt,
  }) {
    int? twips(double? v, String name) =>
        v == null ? null : twipsOf(v, name, min: 0, max: maxTwips);
    return DocxTableMargins._(
      twips(topPt, 'topPt'),
      twips(leftPt, 'leftPt'),
      twips(bottomPt, 'bottomPt'),
      twips(rightPt, 'rightPt'),
    );
  }

  const DocxTableMargins._(this._top, this._left, this._bottom, this._right);

  final int? _top;
  final int? _left;
  final int? _bottom;
  final int? _right;

  /// The margin above the text, or `null`.
  double? get topPt => _top == null ? null : ptOfTwips(_top);

  /// The margin at the left, or `null`.
  double? get leftPt => _left == null ? null : ptOfTwips(_left);

  /// The margin below the text, or `null`.
  double? get bottomPt => _bottom == null ? null : ptOfTwips(_bottom);

  /// The margin at the right, or `null`.
  double? get rightPt => _right == null ? null : ptOfTwips(_right);

  @override
  bool operator ==(Object other) =>
      other is DocxTableMargins &&
      other._top == _top &&
      other._left == _left &&
      other._bottom == _bottom &&
      other._right == _right;

  @override
  int get hashCode => Object.hash(_top, _left, _bottom, _right);

  @override
  String toString() =>
      'DocxTableMargins(topPt: $topPt, leftPt: $leftPt, '
      'bottomPt: $bottomPt, rightPt: $rightPt)';
}

/// Which parts of a table style apply (`w:tblLook`).
///
/// The file holds the flags twice, as six attributes and as the bits of
/// `w:val`; the reader takes the attributes when there is one, else the
/// bits, and the writer writes both, as Word does.
final class DocxTableLook {
  /// A look with the given flags, all off unless named.
  const DocxTableLook({
    this.firstRow = false,
    this.lastRow = false,
    this.firstColumn = false,
    this.lastColumn = false,
    this.noHorizontalBands = false,
    this.noVerticalBands = false,
  });

  /// Whether the style's first row formatting applies.
  final bool firstRow;

  /// Whether the style's last row formatting applies.
  final bool lastRow;

  /// Whether the style's first column formatting applies.
  final bool firstColumn;

  /// Whether the style's last column formatting applies.
  final bool lastColumn;

  /// Whether the style's row banding is off.
  final bool noHorizontalBands;

  /// Whether the style's column banding is off.
  final bool noVerticalBands;

  @override
  bool operator ==(Object other) =>
      other is DocxTableLook &&
      other.firstRow == firstRow &&
      other.lastRow == lastRow &&
      other.firstColumn == firstColumn &&
      other.lastColumn == lastColumn &&
      other.noHorizontalBands == noHorizontalBands &&
      other.noVerticalBands == noVerticalBands;

  @override
  int get hashCode => Object.hash(
    firstRow,
    lastRow,
    firstColumn,
    lastColumn,
    noHorizontalBands,
    noVerticalBands,
  );

  @override
  String toString() =>
      'DocxTableLook(firstRow: $firstRow, lastRow: $lastRow, '
      'firstColumn: $firstColumn, lastColumn: $lastColumn, '
      'noHorizontalBands: $noHorizontalBands, '
      'noVerticalBands: $noVerticalBands)';
}

/// How a [DocxRowHeight] holds (`w:hRule`).
enum DocxRowHeightRule {
  /// The row is at least this tall (no `w:hRule`, `auto` or `atLeast`).
  atLeast,

  /// The row is exactly this tall.
  exact,
}

/// The height of a row (`w:trHeight`).
///
/// The height is stored in twips (0 to 1584 points) and reads back rounded.
final class DocxRowHeight {
  /// A height of [heightPt] points, from 0 to 1584, by [rule].
  ///
  /// Throws [ArgumentError] when [heightPt] is not finite and [RangeError]
  /// when it is out of range once rounded.
  factory DocxRowHeight(
    double heightPt, {
    DocxRowHeightRule rule = DocxRowHeightRule.atLeast,
  }) => DocxRowHeight._(
    twipsOf(heightPt, 'heightPt', min: 0, max: maxTwips),
    rule,
  );

  const DocxRowHeight._(this._twips, this.rule);

  final int _twips;

  /// Whether the height is a minimum or exact.
  final DocxRowHeightRule rule;

  /// The height in points.
  double get heightPt => ptOfTwips(_twips);

  @override
  bool operator ==(Object other) =>
      other is DocxRowHeight && other._twips == _twips && other.rule == rule;

  @override
  int get hashCode => Object.hash(_twips, rule);

  @override
  String toString() => 'DocxRowHeight($heightPt, rule: ${rule.name})';
}

/// The part a cell takes in a vertical merge (`w:vMerge`).
enum DocxVerticalMerge {
  /// The cell starts a merged cell.
  restart,

  /// The cell continues the merged cell above it (no `w:val` is
  /// `continue`).
  continuation,
}

/// How a cell's content lines up between its top and bottom (`w:vAlign`).
/// `both` has no view.
enum DocxCellVerticalAlignment {
  /// At the top.
  top,

  /// Centered.
  center,

  /// At the bottom.
  bottom,
}

/// The direction of the text in a cell (`w:textDirection`). Every other
/// spelling of the schema has no view.
enum DocxTextDirection {
  /// Left to right, top to bottom (`lrTb`).
  leftToRightTopToBottom,

  /// Top to bottom, right to left (`tbRl`).
  topToBottomRightToLeft,

  /// Bottom to top, left to right (`btLr`).
  bottomToTopLeftToRight,

  /// Left to right, top to bottom, vertical glyphs (`lrTbV`).
  lrTbV,

  /// Top to bottom, right to left, vertical glyphs (`tbRlV`).
  tbRlV,

  /// Top to bottom, left to right, vertical glyphs (`tbLrV`).
  tbLrV,
}
