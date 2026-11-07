/// Points, sizes and rectangles of the layout, in a y-down canvas.
///
/// The unit is the backend's: logical pixels on screen, points in a PDF. Every
/// type is an immutable value.
library;

import '../model/equality.dart';

/// A position on the canvas.
final class ChartPoint {
  /// Creates a point at [x] from the left and [y] from the top.
  const ChartPoint(this.x, this.y);

  /// The distance from the left edge.
  final double x;

  /// The distance from the top edge.
  final double y;

  @override
  bool operator ==(Object other) {
    return other is ChartPoint &&
        valueEquals(x, other.x) &&
        valueEquals(y, other.y);
  }

  @override
  int get hashCode => Object.hash(valueHash(x), valueHash(y));

  @override
  String toString() => 'ChartPoint($x, $y)';
}

/// A width and a height.
final class ChartSize {
  /// Creates a size.
  const ChartSize(this.width, this.height);

  /// The width.
  final double width;

  /// The height.
  final double height;

  @override
  bool operator ==(Object other) {
    return other is ChartSize &&
        valueEquals(width, other.width) &&
        valueEquals(height, other.height);
  }

  @override
  int get hashCode => Object.hash(valueHash(width), valueHash(height));

  @override
  String toString() => 'ChartSize($width, $height)';
}

/// An axis-aligned rectangle.
///
/// A rectangle with a `NaN` or negative width or height is not an error.
/// [intersects] is false for such a rectangle, on either side. [contains]
/// compares plain edges and does not check the size, so a rectangle with a
/// negative size may be contained by another, and one with a `NaN` size
/// never is.
final class ChartRect {
  /// Creates a rectangle whose top left corner is ([left], [top]).
  const ChartRect(this.left, this.top, this.width, this.height);

  /// The left edge.
  final double left;

  /// The top edge.
  final double top;

  /// The width.
  final double width;

  /// The height.
  final double height;

  /// The right edge, `left + width`.
  double get right => left + width;

  /// The bottom edge, `top + height`.
  double get bottom => top + height;

  /// Whether this and [other] share area.
  ///
  /// Touching edges do not intersect. A rectangle with zero width or height
  /// has no area and intersects nothing, itself included.
  bool intersects(ChartRect other) {
    if (!(width > 0 && height > 0 && other.width > 0 && other.height > 0)) {
      return false;
    }
    return left < other.right &&
        other.left < right &&
        top < other.bottom &&
        other.top < bottom;
  }

  /// Whether [other] lies inside this rectangle, edges included.
  bool contains(ChartRect other) {
    return left <= other.left &&
        top <= other.top &&
        other.right <= right &&
        other.bottom <= bottom;
  }

  @override
  bool operator ==(Object other) {
    return other is ChartRect &&
        valueEquals(left, other.left) &&
        valueEquals(top, other.top) &&
        valueEquals(width, other.width) &&
        valueEquals(height, other.height);
  }

  @override
  int get hashCode => Object.hash(
    valueHash(left),
    valueHash(top),
    valueHash(width),
    valueHash(height),
  );

  @override
  String toString() => 'ChartRect($left, $top, $width, $height)';
}
