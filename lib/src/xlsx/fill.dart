/// Fills for cell formats.
///
/// New in jet_office. Quds keeps a fill as a private `_Fill` class inside
/// `builders/xlsx_io.dart` that holds one solid color; here a fill is a
/// public, model-neutral value type covering all 19 pattern types and linear
/// and path gradients, checked when it is registered with the writer.
library;

import '../xml/xml_number.dart';
import '../xml/xml_writer.dart';
import 'color.dart';

/// The pattern of a pattern fill (`ST_PatternType`).
enum XlsxPatternType {
  /// No fill.
  none,

  /// The foreground color covers the cell.
  solid,

  /// 50% gray.
  mediumGray,

  /// 75% gray.
  darkGray,

  /// 25% gray.
  lightGray,

  /// Thick horizontal stripes.
  darkHorizontal,

  /// Thick vertical stripes.
  darkVertical,

  /// Thick stripes falling to the right.
  darkDown,

  /// Thick stripes rising to the right.
  darkUp,

  /// Thick grid.
  darkGrid,

  /// Thick diagonal crosshatch.
  darkTrellis,

  /// Thin horizontal stripes.
  lightHorizontal,

  /// Thin vertical stripes.
  lightVertical,

  /// Thin stripes falling to the right.
  lightDown,

  /// Thin stripes rising to the right.
  lightUp,

  /// Thin grid.
  lightGrid,

  /// Thin diagonal crosshatch.
  lightTrellis,

  /// 12.5% gray.
  gray125,

  /// 6.25% gray.
  gray0625,
}

/// How a cell is filled: a [XlsxPatternFill] or a [XlsxGradientFill].
///
/// A fill is replaced whole, never merged. The `const` constructors cannot
/// check their arguments; the writer does, when the fill is registered, and
/// throws [ArgumentError].
sealed class XlsxFill {
  /// A fill of the single [color].
  const factory XlsxFill.solid(XlsxColor color) = XlsxPatternFill._solid;

  /// A pattern fill of [type] with an optional [foreground] and [background].
  const factory XlsxFill.pattern(
    XlsxPatternType type, {
    XlsxColor? foreground,
    XlsxColor? background,
  }) = XlsxPatternFill;
}

/// A fill made of a [type] pattern in a [foreground] and [background] color
/// (`CT_PatternFill`).
///
/// For a solid fill the cell shows [foreground].
final class XlsxPatternFill implements XlsxFill {
  /// Creates a pattern fill.
  const XlsxPatternFill(this.type, {this.foreground, this.background});

  const XlsxPatternFill._solid(XlsxColor color)
    : type = XlsxPatternType.solid,
      foreground = color,
      background = null;

  /// The pattern.
  final XlsxPatternType type;

  /// The pattern's color, or null for the application default.
  final XlsxColor? foreground;

  /// The color behind the pattern, or null for the application default.
  final XlsxColor? background;

  @override
  bool operator ==(Object other) =>
      other is XlsxPatternFill &&
      other.type == type &&
      other.foreground == foreground &&
      other.background == background;

  @override
  int get hashCode => Object.hash(type, foreground, background);

  @override
  String toString() =>
      'XlsxFill.pattern($type, foreground: $foreground, '
      'background: $background)';
}

/// One color of a gradient at a [position] within `0..1`.
final class XlsxGradientStop {
  /// Creates a stop of [color] at [position].
  const XlsxGradientStop(this.position, this.color);

  /// Where the color sits along the gradient, `0` to `1`.
  final double position;

  /// The color at [position].
  final XlsxColor color;

  @override
  bool operator ==(Object other) =>
      other is XlsxGradientStop &&
      other.position == position &&
      other.color == color;

  @override
  int get hashCode => Object.hash(position, color);

  @override
  String toString() => 'XlsxGradientStop($position, $color)';
}

/// A gradient fill (`CT_GradientFill`): linear at an angle, or radiating
/// from a rectangle inside the cell.
final class XlsxGradientFill implements XlsxFill {
  /// A linear gradient at [degree] degrees, through [stops] (at least two,
  /// positions non-decreasing within `0..1`).
  XlsxGradientFill.linear({
    this.degree = 0,
    required List<XlsxGradientStop> stops,
  }) : isPath = false,
       left = 0,
       right = 0,
       top = 0,
       bottom = 0,
       stops = List<XlsxGradientStop>.unmodifiable(stops);

  /// A path gradient that radiates from the rectangle given by [left],
  /// [right], [top] and [bottom], each a fraction of the cell within `0..1`,
  /// through [stops] (at least two, positions non-decreasing within `0..1`).
  XlsxGradientFill.path({
    this.left = 0,
    this.right = 0,
    this.top = 0,
    this.bottom = 0,
    required List<XlsxGradientStop> stops,
  }) : isPath = true,
       degree = 0,
       stops = List<XlsxGradientStop>.unmodifiable(stops);

  /// Whether this is a path gradient rather than a linear one.
  final bool isPath;

  /// The angle of a linear gradient in degrees; `0` for a path gradient.
  final double degree;

  /// The left edge of a path gradient's rectangle; `0` for a linear one.
  final double left;

  /// The right edge of a path gradient's rectangle; `0` for a linear one.
  final double right;

  /// The top edge of a path gradient's rectangle; `0` for a linear one.
  final double top;

  /// The bottom edge of a path gradient's rectangle; `0` for a linear one.
  final double bottom;

  /// The gradient's colors, an unmodifiable copy.
  final List<XlsxGradientStop> stops;

  @override
  bool operator ==(Object other) {
    if (other is! XlsxGradientFill ||
        other.isPath != isPath ||
        other.degree != degree ||
        other.left != left ||
        other.right != right ||
        other.top != top ||
        other.bottom != bottom ||
        other.stops.length != stops.length) {
      return false;
    }
    for (int i = 0; i < stops.length; i++) {
      if (other.stops[i] != stops[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    isPath,
    degree,
    left,
    right,
    top,
    bottom,
    Object.hashAll(stops),
  );

  @override
  String toString() => isPath
      ? 'XlsxGradientFill.path(left: $left, right: $right, top: $top, '
            'bottom: $bottom, stops: $stops)'
      : 'XlsxGradientFill.linear(degree: $degree, stops: $stops)';
}

bool _unit(double v) => v.isFinite && v >= 0 && v <= 1;

/// Checks [fill]: a gradient has at least two stops with positions within
/// `0..1` that never decrease, its degree and edges are finite and the edges
/// lie within `0..1`, and every color is valid.
///
/// Throws [ArgumentError] naming the field.
void validateFill(XlsxFill fill) {
  switch (fill) {
    case XlsxPatternFill():
      final XlsxColor? fg = fill.foreground;
      if (fg != null) {
        validateColor(fg, 'foreground');
      }
      final XlsxColor? bg = fill.background;
      if (bg != null) {
        validateColor(bg, 'background');
      }
    case XlsxGradientFill():
      if (fill.stops.length < 2) {
        throw ArgumentError.value(
          fill.stops.length,
          'stops',
          'A gradient needs at least 2 stops.',
        );
      }
      if (!fill.degree.isFinite) {
        throw ArgumentError.value(
          fill.degree,
          'degree',
          'A gradient degree must be finite.',
        );
      }
      for (final (String, double) edge in <(String, double)>[
        ('left', fill.left),
        ('right', fill.right),
        ('top', fill.top),
        ('bottom', fill.bottom),
      ]) {
        if (!_unit(edge.$2)) {
          throw ArgumentError.value(
            edge.$2,
            edge.$1,
            'A gradient edge must be finite and within 0..1.',
          );
        }
      }
      double previous = 0;
      for (final XlsxGradientStop stop in fill.stops) {
        if (!_unit(stop.position) || stop.position < previous) {
          throw ArgumentError.value(
            stop.position,
            'stops',
            'Stop positions must be within 0..1 and never decrease.',
          );
        }
        previous = stop.position;
        validateColor(stop.color, 'stops');
      }
  }
}

void _writeColorElement(XmlWriter w, String name, XlsxColor color) {
  w.start(name);
  writeColorAttributes(w, color);
  w.end();
}

/// Writes [fill] as one `<fill>` element.
///
/// The fill must have passed [validateFill].
void writeFillXml(XmlWriter w, XlsxFill fill) {
  w.start('fill');
  switch (fill) {
    case XlsxPatternFill():
      w.start('patternFill');
      w.attribute('patternType', fill.type.name);
      final XlsxColor? fg = fill.foreground;
      if (fg != null) {
        _writeColorElement(w, 'fgColor', fg);
      }
      final XlsxColor? bg = fill.background;
      if (bg != null) {
        _writeColorElement(w, 'bgColor', bg);
      }
      w.end();
    case XlsxGradientFill():
      w.start('gradientFill');
      if (fill.isPath) {
        w.attribute('type', 'path');
        w.attribute('left', formatXmlDouble(fill.left));
        w.attribute('right', formatXmlDouble(fill.right));
        w.attribute('top', formatXmlDouble(fill.top));
        w.attribute('bottom', formatXmlDouble(fill.bottom));
      } else if (fill.degree != 0) {
        w.attribute('degree', formatXmlDouble(fill.degree));
      }
      for (final XlsxGradientStop stop in fill.stops) {
        w.start('stop');
        w.attribute('position', formatXmlDouble(stop.position));
        _writeColorElement(w, 'color', stop.color);
        w.end();
      }
      w.end();
  }
  w.end();
}
