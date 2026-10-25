/// Borders for cell formats.
///
/// New in jet_office. Quds keeps a border as a private `_Border` class inside
/// `builders/xlsx_io.dart` with four sides of one style and color; here a
/// border is a public, model-neutral value type with every `CT_Border`
/// property, and the writer checks it when it is registered.
library;

import '../xml/xml_writer.dart';
import 'color.dart';

/// The line style of a border side (`ST_BorderStyle`).
enum XlsxBorderStyle {
  /// No line.
  none,

  /// A thin line.
  thin,

  /// A medium line.
  medium,

  /// A thin dashed line.
  dashed,

  /// A thin dotted line.
  dotted,

  /// A thick line.
  thick,

  /// A double line; written as `double`.
  doubleLine,

  /// The thinnest line.
  hair,

  /// A medium dashed line.
  mediumDashed,

  /// A thin line of dashes and dots.
  dashDot,

  /// A medium line of dashes and dots.
  mediumDashDot,

  /// A thin line of a dash and two dots.
  dashDotDot,

  /// A medium line of a dash and two dots.
  mediumDashDotDot,

  /// A slanted line of dashes and dots.
  slantDashDot,
}

/// One side of a border: a line [style] in a [color] (`CT_BorderPr`).
///
/// Both fields are nullable. A side with no [style], or the `none` style,
/// draws no line.
final class XlsxBorderSide {
  /// Creates a border side.
  const XlsxBorderSide({this.style, this.color});

  /// The line style.
  final XlsxBorderStyle? style;

  /// The line color, or null for the application default.
  final XlsxColor? color;

  @override
  bool operator ==(Object other) =>
      other is XlsxBorderSide && other.style == style && other.color == color;

  @override
  int get hashCode => Object.hash(style, color);

  @override
  String toString() => 'XlsxBorderSide(style: $style, color: $color)';
}

/// A border as SpreadsheetML (`CT_Border`) describes it.
///
/// Every field is nullable, and `null` means "inherit": [merge] lets a
/// non-null side of one border replace the same side of another, whole. The
/// `const` constructors cannot check their arguments; the writer does, when
/// the border is registered, and throws [ArgumentError] naming the side.
final class XlsxBorder {
  /// Creates a border.
  const XlsxBorder({
    this.left,
    this.right,
    this.top,
    this.bottom,
    this.diagonal,
    this.vertical,
    this.horizontal,
    this.diagonalUp,
    this.diagonalDown,
    this.outline,
  });

  /// A border whose [left], [right], [top] and [bottom] are all [side].
  const XlsxBorder.all(XlsxBorderSide side)
    : left = side,
      right = side,
      top = side,
      bottom = side,
      diagonal = null,
      vertical = null,
      horizontal = null,
      diagonalUp = null,
      diagonalDown = null,
      outline = null;

  /// The left side.
  final XlsxBorderSide? left;

  /// The right side.
  final XlsxBorderSide? right;

  /// The top side.
  final XlsxBorderSide? top;

  /// The bottom side.
  final XlsxBorderSide? bottom;

  /// The diagonal line, drawn according to [diagonalUp] and [diagonalDown].
  final XlsxBorderSide? diagonal;

  /// The line between the cells of a range, used by differential formats.
  final XlsxBorderSide? vertical;

  /// The line between the rows of a range, used by differential formats.
  final XlsxBorderSide? horizontal;

  /// Whether [diagonal] rises from the bottom left to the top right.
  final bool? diagonalUp;

  /// Whether [diagonal] falls from the top left to the bottom right.
  final bool? diagonalDown;

  /// Whether the border applies to the outline of a range only (`true` is
  /// Excel's default).
  final bool? outline;

  /// This border with every non-null field of [other] applied on top.
  ///
  /// A side of [other] replaces the whole side, line style and color
  /// together. A null [other] changes nothing.
  XlsxBorder merge(XlsxBorder? other) {
    if (other == null) {
      return this;
    }
    return XlsxBorder(
      left: other.left ?? left,
      right: other.right ?? right,
      top: other.top ?? top,
      bottom: other.bottom ?? bottom,
      diagonal: other.diagonal ?? diagonal,
      vertical: other.vertical ?? vertical,
      horizontal: other.horizontal ?? horizontal,
      diagonalUp: other.diagonalUp ?? diagonalUp,
      diagonalDown: other.diagonalDown ?? diagonalDown,
      outline: other.outline ?? outline,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is XlsxBorder &&
      other.left == left &&
      other.right == right &&
      other.top == top &&
      other.bottom == bottom &&
      other.diagonal == diagonal &&
      other.vertical == vertical &&
      other.horizontal == horizontal &&
      other.diagonalUp == diagonalUp &&
      other.diagonalDown == diagonalDown &&
      other.outline == outline;

  @override
  int get hashCode => Object.hash(
    left,
    right,
    top,
    bottom,
    diagonal,
    vertical,
    horizontal,
    diagonalUp,
    diagonalDown,
    outline,
  );

  @override
  String toString() {
    final List<String> parts = <String>[
      if (left != null) 'left: $left',
      if (right != null) 'right: $right',
      if (top != null) 'top: $top',
      if (bottom != null) 'bottom: $bottom',
      if (diagonal != null) 'diagonal: $diagonal',
      if (vertical != null) 'vertical: $vertical',
      if (horizontal != null) 'horizontal: $horizontal',
      if (diagonalUp != null) 'diagonalUp: $diagonalUp',
      if (diagonalDown != null) 'diagonalDown: $diagonalDown',
      if (outline != null) 'outline: $outline',
    ];
    return 'XlsxBorder(${parts.join(', ')})';
  }
}

/// Checks the color of every side of [border].
///
/// Throws [ArgumentError] naming the side.
void validateBorder(XlsxBorder border) {
  for (final (String, XlsxBorderSide?) side in <(String, XlsxBorderSide?)>[
    ('left', border.left),
    ('right', border.right),
    ('top', border.top),
    ('bottom', border.bottom),
    ('diagonal', border.diagonal),
    ('vertical', border.vertical),
    ('horizontal', border.horizontal),
  ]) {
    final XlsxColor? color = side.$2?.color;
    if (color != null) {
      validateColor(color, side.$1);
    }
  }
}

/// Whether [side] draws a line: it has a style other than `none`.
bool _draws(XlsxBorderSide? side) {
  final XlsxBorderStyle? style = side?.style;
  return style != null && style != XlsxBorderStyle.none;
}

/// Writes [side] as the element [name]. A side that draws no line is
/// written empty, its color dropped, so it reads like an unset side.
void _writeSide(XmlWriter w, String name, XlsxBorderSide? side) {
  w.start(name);
  if (side != null && _draws(side)) {
    final XlsxBorderStyle style = side.style!;
    w.attribute(
      'style',
      style == XlsxBorderStyle.doubleLine ? 'double' : style.name,
    );
    final XlsxColor? color = side.color;
    if (color != null) {
      w.start('color');
      writeColorAttributes(w, color);
      w.end();
    }
  }
  w.end();
}

/// Writes [border] as one `<border>` element, children in `CT_Border` order.
///
/// `left`, `right`, `top`, `bottom` and `diagonal` are always written;
/// `vertical` and `horizontal` only when they draw a line. A side that draws
/// no line (no style, or `none`) is written empty and without its color, so
/// it reads like an unset side. `diagonalUp` and `diagonalDown` are written
/// when `true`, `outline` when `false`. The `diagonal` side's line is
/// written only when `diagonalUp` or `diagonalDown` is set; without a
/// direction Excel draws no diagonal, so it is written empty. Borders that
/// look the same therefore write the same text, which the registry dedupes
/// on. The border must have passed [validateBorder].
void writeBorderXml(XmlWriter w, XlsxBorder border) {
  w.start('border');
  if (border.diagonalUp ?? false) {
    w.attribute('diagonalUp', '1');
  }
  if (border.diagonalDown ?? false) {
    w.attribute('diagonalDown', '1');
  }
  if (border.outline == false) {
    w.attribute('outline', '0');
  }
  _writeSide(w, 'left', border.left);
  _writeSide(w, 'right', border.right);
  _writeSide(w, 'top', border.top);
  _writeSide(w, 'bottom', border.bottom);
  // Without a direction the diagonal side is never drawn; written empty, the
  // border dedupes with the same border without one.
  final bool diagonal =
      (border.diagonalUp ?? false) || (border.diagonalDown ?? false);
  _writeSide(w, 'diagonal', diagonal ? border.diagonal : null);
  if (_draws(border.vertical)) {
    _writeSide(w, 'vertical', border.vertical);
  }
  if (_draws(border.horizontal)) {
    _writeSide(w, 'horizontal', border.horizontal);
  }
  w.end();
}
