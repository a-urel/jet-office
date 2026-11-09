/// Hit testing: which primitives of a layout lie under a point.
library;

import 'dart:math' as math;

import '../layout/chart_ids.dart' as ids;
import '../layout/chart_layout.dart';
import '../layout/geometry.dart';
import '../layout/primitives.dart';

/// Every primitive of [layout] under [point], topmost first.
///
/// The order is the reverse of paint order. A clip is entered only when
/// [point] lies inside its rectangle (edges included): its children come
/// first, topmost first, then the clip itself; outside it neither the clip
/// nor any child is hit, so a mark that overflows the clip is not hit where
/// it is not drawn. The clip of a line chart's markers (`plot/markers`) is
/// entered the same way but is never hit itself: it only lets the markers
/// reach past the plot, and the plot's clip (`plot/clip`) under it is hit
/// instead.
///
/// Each kind is hit as follows, edges included, with [tolerance] the extra
/// distance a point may be away:
///
/// * a rectangle: inside it grown by [tolerance] on every side;
/// * an open path: within half its stroke width plus [tolerance] of one of
///   its segments (a single point: of that point);
/// * a closed path with a fill: inside the polygon (even-odd rule), or within
///   [tolerance] (plus half the stroke width when it has a stroke) of an
///   edge;
/// * a closed path without a fill: as an open path, the closing edge
///   included;
/// * a text: inside its turned box, [TextPrimitive.corners], grown by
///   [tolerance] on every side;
/// * an arc: at a distance from the centre between its inner radius less
///   [tolerance] and its radius plus [tolerance] (each widened by half the
///   stroke width when it has a stroke), at an angle inside its sweep (the
///   centre itself counts as inside the sweep).
///
/// A [point] with a coordinate that is not finite hits nothing. Throws an
/// [ArgumentError] when [tolerance] is negative or not finite.
List<ChartPrimitive> hitTestLayout(
  ChartLayout layout,
  ChartPoint point, {
  double tolerance = 0,
}) {
  if (!tolerance.isFinite || tolerance < 0) {
    throw ArgumentError.value(
      tolerance,
      'tolerance',
      'must be finite and not negative',
    );
  }
  final List<ChartPrimitive> hits = <ChartPrimitive>[];
  if (point.x.isFinite && point.y.isFinite) {
    _hitAll(layout.primitives, point, tolerance, hits);
  }
  return hits;
}

void _hitAll(
  List<ChartPrimitive> primitives,
  ChartPoint p,
  double tolerance,
  List<ChartPrimitive> hits,
) {
  for (int i = primitives.length - 1; i >= 0; i--) {
    final ChartPrimitive primitive = primitives[i];
    if (primitive is ClipPrimitive) {
      if (_inRect(primitive.rect, p, 0)) {
        _hitAll(primitive.children, p, tolerance, hits);
        if (primitive.id != ids.markerClip) {
          hits.add(primitive);
        }
      }
    } else if (_hits(primitive, p, tolerance)) {
      hits.add(primitive);
    }
  }
}

bool _hits(ChartPrimitive primitive, ChartPoint p, double tolerance) {
  switch (primitive) {
    case RectPrimitive(:final ChartRect rect):
      return _inRect(rect, p, tolerance);
    case PathPrimitive():
      return _hitsPath(primitive, p, tolerance);
    case TextPrimitive():
      return _hitsText(primitive, p, tolerance);
    case ArcPrimitive():
      return _hitsArc(primitive, p, tolerance);
    case ClipPrimitive():
      return _inRect(primitive.rect, p, 0);
  }
}

/// Whether [p] lies inside [r] grown by [grow], edges included.
bool _inRect(ChartRect r, ChartPoint p, double grow) =>
    p.x >= r.left - grow &&
    p.x <= r.right + grow &&
    p.y >= r.top - grow &&
    p.y <= r.bottom + grow;

bool _hitsPath(PathPrimitive path, ChartPoint p, double tolerance) {
  final List<ChartPoint> points = path.points;
  if (points.isEmpty) {
    return false;
  }
  final double halfStroke = path.strokeWidth.isFinite && path.strokeWidth > 0
      ? path.strokeWidth / 2
      : 0;
  if (path.closed && path.fill != null) {
    if (_insidePolygon(points, p)) {
      return true;
    }
    final double reach = tolerance + (path.stroke == null ? 0 : halfStroke);
    return _distanceToPath(points, p, closed: true) <= reach;
  }
  return _distanceToPath(points, p, closed: path.closed) <=
      halfStroke + tolerance;
}

/// The least distance from [p] to the segments through [points], and from
/// the last point back to the first when [closed]; to the point itself when
/// there is only one.
double _distanceToPath(
  List<ChartPoint> points,
  ChartPoint p, {
  required bool closed,
}) {
  if (points.length == 1) {
    return _distance(points.first, p);
  }
  double best = double.infinity;
  for (int i = 0; i + 1 < points.length; i++) {
    best = math.min(best, _distanceToSegment(points[i], points[i + 1], p));
  }
  if (closed) {
    best = math.min(best, _distanceToSegment(points.last, points.first, p));
  }
  return best;
}

double _distance(ChartPoint a, ChartPoint b) {
  final double dx = a.x - b.x;
  final double dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

double _distanceToSegment(ChartPoint a, ChartPoint b, ChartPoint p) {
  final double dx = b.x - a.x;
  final double dy = b.y - a.y;
  final double lengthSquared = dx * dx + dy * dy;
  if (!(lengthSquared > 0)) {
    return _distance(a, p);
  }
  final double t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared)
      .clamp(0.0, 1.0);
  return _distance(ChartPoint(a.x + t * dx, a.y + t * dy), p);
}

/// Whether [p] lies inside the polygon of [points] by the even-odd rule.
bool _insidePolygon(List<ChartPoint> points, ChartPoint p) {
  bool inside = false;
  for (int i = 0, j = points.length - 1; i < points.length; j = i++) {
    final ChartPoint a = points[i];
    final ChartPoint b = points[j];
    if ((a.y > p.y) != (b.y > p.y) &&
        p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}

/// Whether [p] lies in [text]'s box, turned about its centre as
/// [TextPrimitive.corners] turns it, grown by [tolerance]: [p] is turned back
/// into the unturned box's frame.
bool _hitsText(TextPrimitive text, ChartPoint p, double tolerance) {
  final ChartRect r = text.rect;
  if (text.rotationDegrees == 0) {
    return _inRect(r, p, tolerance);
  }
  final double cx = r.left + r.width / 2;
  final double cy = r.top + r.height / 2;
  final double radians = -text.rotationDegrees * math.pi / 180;
  final double cosine = math.cos(radians);
  final double sine = math.sin(radians);
  final double dx = p.x - cx;
  final double dy = p.y - cy;
  return _inRect(
    r,
    ChartPoint(cx + dx * cosine - dy * sine, cy + dx * sine + dy * cosine),
    tolerance,
  );
}

bool _hitsArc(ArcPrimitive arc, ChartPoint p, double tolerance) {
  final double dx = p.x - arc.center.x;
  final double dy = p.y - arc.center.y;
  final double distance = math.sqrt(dx * dx + dy * dy);
  final double halfStroke =
      arc.stroke != null && arc.strokeWidth.isFinite && arc.strokeWidth > 0
      ? arc.strokeWidth / 2
      : 0;
  final double reach = tolerance + halfStroke;
  if (!(distance >= arc.innerRadius - reach &&
      distance <= arc.radius + reach)) {
    return false;
  }
  final double sweep = arc.sweepAngle;
  if (!sweep.isFinite || !arc.startAngle.isFinite) {
    return false;
  }
  if (distance == 0 || sweep.abs() >= 360) {
    return true;
  }
  // On a y-down canvas atan2 grows clockwise, as the sweep does.
  final double angle = math.atan2(dy, dx) * 180 / math.pi;
  final double from = sweep >= 0 ? arc.startAngle : arc.startAngle + sweep;
  return (angle - from) % 360 <= sweep.abs();
}
