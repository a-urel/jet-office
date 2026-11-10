/// The drawing primitives layout produces and a backend paints.
///
/// A backend draws these and has no chart logic. Every primitive has an `id`
/// that is stable for the same chart, so hit testing and golden tests can name
/// a mark. Primitives are values; the lists they hold are copies and cannot be
/// changed.
library;

import 'dart:math' as math;

import '../model/equality.dart';
import '../theme/chart_color.dart';
import 'geometry.dart';

/// One thing to draw. A backend switches over the subclasses; there are five.
sealed class ChartPrimitive {
  /// Creates a primitive with the stable [id].
  const ChartPrimitive(this.id);

  /// The stable identifier of this primitive.
  final String id;
}

/// A rectangle, filled, stroked or both.
final class RectPrimitive extends ChartPrimitive {
  /// Creates a rectangle. A null [fill] or [stroke] is not drawn.
  const RectPrimitive(
    super.id,
    this.rect, {
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
  });

  /// The area.
  final ChartRect rect;

  /// The fill colour, or null for none.
  final ChartColor? fill;

  /// The outline colour, or null for none.
  final ChartColor? stroke;

  /// The outline width.
  final double strokeWidth;

  @override
  bool operator ==(Object other) {
    return other is RectPrimitive &&
        id == other.id &&
        rect == other.rect &&
        fill == other.fill &&
        stroke == other.stroke &&
        valueEquals(strokeWidth, other.strokeWidth);
  }

  @override
  int get hashCode =>
      Object.hash(id, rect, fill, stroke, valueHash(strokeWidth));

  @override
  String toString() => 'RectPrimitive($id, $rect)';
}

/// A polyline or polygon.
final class PathPrimitive extends ChartPrimitive {
  /// Creates a path through [points]; the lists are copied.
  PathPrimitive(
    super.id,
    List<ChartPoint> points, {
    this.closed = false,
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
    List<double>? dash,
    this.fillOpacity = 1,
  }) : points = List<ChartPoint>.unmodifiable(points),
       dash = dash == null ? null : List<double>.unmodifiable(dash) {
    if (!fillOpacity.isFinite || fillOpacity <= 0 || fillOpacity > 1) {
      throw ArgumentError.value(
        fillOpacity,
        'fillOpacity',
        'must be finite, above 0 and at most 1',
      );
    }
  }

  /// The vertices, in order.
  final List<ChartPoint> points;

  /// Whether the last point joins back to the first.
  final bool closed;

  /// The fill colour, or null for none.
  final ChartColor? fill;

  /// The line colour, or null for none.
  final ChartColor? stroke;

  /// The line width.
  final double strokeWidth;

  /// The lengths of the dashes and gaps, alternating, or null for a solid line.
  final List<double>? dash;

  /// The fill's opacity, above 0 and at most 1. The stroke stays opaque.
  final double fillOpacity;

  @override
  bool operator ==(Object other) {
    return other is PathPrimitive &&
        id == other.id &&
        listValueEquals(points, other.points) &&
        closed == other.closed &&
        fill == other.fill &&
        stroke == other.stroke &&
        valueEquals(strokeWidth, other.strokeWidth) &&
        (dash == null
            ? other.dash == null
            : other.dash != null && listValueEquals(dash!, other.dash!)) &&
        valueEquals(fillOpacity, other.fillOpacity);
  }

  @override
  int get hashCode => Object.hash(
    id,
    listValueHash(points),
    closed,
    fill,
    stroke,
    valueHash(strokeWidth),
    dash == null ? null : listValueHash(dash!),
    valueHash(fillOpacity),
  );

  @override
  String toString() => 'PathPrimitive($id, ${points.length} points)';
}

/// A pie slice or a donut segment.
///
/// Angles are in degrees on a y-down canvas: 0 is three o'clock and a positive
/// [sweepAngle] sweeps clockwise.
final class ArcPrimitive extends ChartPrimitive {
  /// Creates an arc around [center].
  ///
  /// An [innerRadius] of 0 makes a pie slice; a larger one cuts the middle out.
  const ArcPrimitive(
    super.id,
    this.center,
    this.radius,
    this.innerRadius,
    this.startAngle,
    this.sweepAngle, {
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
  });

  /// The centre of the circle.
  final ChartPoint center;

  /// The outer radius.
  final double radius;

  /// The inner radius; 0 is a pie slice.
  final double innerRadius;

  /// The start angle in degrees; 0 is three o'clock.
  final double startAngle;

  /// The sweep in degrees; positive is clockwise.
  final double sweepAngle;

  /// The fill colour, or null for none.
  final ChartColor? fill;

  /// The outline colour, or null for none.
  final ChartColor? stroke;

  /// The outline width, centred on the outline.
  final double strokeWidth;

  @override
  bool operator ==(Object other) {
    return other is ArcPrimitive &&
        id == other.id &&
        center == other.center &&
        valueEquals(radius, other.radius) &&
        valueEquals(innerRadius, other.innerRadius) &&
        valueEquals(startAngle, other.startAngle) &&
        valueEquals(sweepAngle, other.sweepAngle) &&
        fill == other.fill &&
        stroke == other.stroke &&
        valueEquals(strokeWidth, other.strokeWidth);
  }

  @override
  int get hashCode => Object.hash(
    id,
    center,
    valueHash(radius),
    valueHash(innerRadius),
    valueHash(startAngle),
    valueHash(sweepAngle),
    fill,
    stroke,
    valueHash(strokeWidth),
  );

  @override
  String toString() => 'ArcPrimitive($id, $center, $radius)';
}

/// A piece of text placed in a rectangle.
final class TextPrimitive extends ChartPrimitive {
  /// Creates text in [rect], turned by [rotationDegrees] clockwise.
  const TextPrimitive(
    super.id,
    this.text,
    this.rect,
    this.style, {
    this.rotationDegrees = 0,
  });

  /// The text; it may hold line breaks.
  final String text;

  /// The unrotated box the text is laid out in. [rotationDegrees] turns it
  /// clockwise about its centre.
  final ChartRect rect;

  /// The font, size and colour.
  final ChartTextStyle style;

  /// The clockwise rotation in degrees.
  final double rotationDegrees;

  /// The four corners of [rect] after the rotation, clockwise from the top
  /// left of the unrotated box.
  List<ChartPoint> get corners {
    final double cx = rect.left + rect.width / 2;
    final double cy = rect.top + rect.height / 2;
    final double radians = rotationDegrees * math.pi / 180;
    final double cosine = math.cos(radians);
    final double sine = math.sin(radians);
    ChartPoint turn(double x, double y) {
      final double dx = x - cx;
      final double dy = y - cy;
      return ChartPoint(
        cx + dx * cosine - dy * sine,
        cy + dx * sine + dy * cosine,
      );
    }

    if (rotationDegrees == 0) {
      return <ChartPoint>[
        ChartPoint(rect.left, rect.top),
        ChartPoint(rect.right, rect.top),
        ChartPoint(rect.right, rect.bottom),
        ChartPoint(rect.left, rect.bottom),
      ];
    }
    return <ChartPoint>[
      turn(rect.left, rect.top),
      turn(rect.right, rect.top),
      turn(rect.right, rect.bottom),
      turn(rect.left, rect.bottom),
    ];
  }

  /// The axis-aligned box that holds [corners].
  ChartRect get bounds {
    final List<ChartPoint> c = corners;
    double minX = c.first.x;
    double maxX = minX;
    double minY = c.first.y;
    double maxY = minY;
    for (final ChartPoint p in c.skip(1)) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
    return ChartRect(minX, minY, maxX - minX, maxY - minY);
  }

  @override
  bool operator ==(Object other) {
    return other is TextPrimitive &&
        id == other.id &&
        text == other.text &&
        rect == other.rect &&
        style == other.style &&
        valueEquals(rotationDegrees, other.rotationDegrees);
  }

  @override
  int get hashCode =>
      Object.hash(id, text, rect, style, valueHash(rotationDegrees));

  @override
  String toString() => 'TextPrimitive($id, "$text")';
}

/// Children drawn only inside [rect].
final class ClipPrimitive extends ChartPrimitive {
  /// Creates a clip of [rect] over [children]; the list is copied.
  ClipPrimitive(super.id, this.rect, List<ChartPrimitive> children)
    : children = List<ChartPrimitive>.unmodifiable(children);

  /// The clip area.
  final ChartRect rect;

  /// What is drawn inside, in paint order.
  final List<ChartPrimitive> children;

  @override
  bool operator ==(Object other) {
    return other is ClipPrimitive &&
        id == other.id &&
        rect == other.rect &&
        listValueEquals(children, other.children);
  }

  @override
  int get hashCode => Object.hash(id, rect, listValueHash(children));

  @override
  String toString() => 'ClipPrimitive($id, ${children.length} children)';
}
