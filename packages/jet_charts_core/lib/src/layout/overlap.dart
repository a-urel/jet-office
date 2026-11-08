/// Finds text that collides with other text, with the legend, or with the
/// edge of the chart.
///
/// Layout tests and the fuzz test run this over every picture: on screen, no
/// overlap beats matching Excel.
library;

import 'dart:math' as math;

import 'chart_ids.dart' as ids;
import 'geometry.dart';
import 'primitives.dart';

/// The overlap tolerance: shapes that penetrate each other by less than this
/// do not overlap.
const double _tolerance = 1e-6;

/// What kind of collision a [ChartOverlap] reports.
enum ChartOverlapKind {
  /// Two texts share area.
  textText,

  /// A text that is not part of the legend shares area with the legend.
  textLegend,

  /// A text leaves the chart's area.
  textOutside,

  /// The legend and the plot area share area.
  legendPlot,
}

/// One collision found by [findOverlaps].
final class ChartOverlap {
  /// Creates a collision of [kind] between [firstId] and, when there is a
  /// second shape, [secondId].
  const ChartOverlap(this.kind, this.firstId, [this.secondId]);

  /// What collides.
  final ChartOverlapKind kind;

  /// The id of the earlier primitive.
  final String firstId;

  /// The id of the other primitive, or null for [ChartOverlapKind.textOutside].
  final String? secondId;

  @override
  bool operator ==(Object other) {
    return other is ChartOverlap &&
        kind == other.kind &&
        firstId == other.firstId &&
        secondId == other.secondId;
  }

  @override
  int get hashCode => Object.hash(kind, firstId, secondId);

  @override
  String toString() => 'ChartOverlap(${kind.name}, $firstId, $secondId)';
}

/// Lists every collision among [primitives] on a chart of [size].
///
/// Clips are flattened. Texts are compared by their turned rectangles
/// (`TextPrimitive.corners`) with a separating axis test; touching shapes, and
/// shapes that penetrate by less than `1e-6`, do not overlap. A text with no
/// area overlaps nothing, but still counts as outside when its bounds leave
/// the chart. Each pair is reported once, in primitive order, with the earlier
/// primitive as `firstId`. Without a `legend` rectangle no legend check is
/// made, and without a `plot` rectangle no legend and plot check is made.
List<ChartOverlap> findOverlaps(
  List<ChartPrimitive> primitives,
  ChartSize size,
) {
  final List<ChartPrimitive> flat = <ChartPrimitive>[];
  void collect(List<ChartPrimitive> list) {
    for (final ChartPrimitive p in list) {
      flat.add(p);
      if (p is ClipPrimitive) {
        collect(p.children);
      }
    }
  }

  collect(primitives);

  final List<TextPrimitive> texts = flat.whereType<TextPrimitive>().toList();
  ChartRect? legendRect;
  ChartRect? plotRect;
  for (final ChartPrimitive p in flat) {
    if (p is RectPrimitive) {
      if (p.id == ids.legend) {
        legendRect ??= p.rect;
      } else if (p.id == ids.plot) {
        plotRect ??= p.rect;
      }
    }
  }

  final List<ChartOverlap> found = <ChartOverlap>[];
  for (int i = 0; i < texts.length; i++) {
    final TextPrimitive a = texts[i];
    final ChartRect b = a.bounds;
    if (b.left < -_tolerance ||
        b.top < -_tolerance ||
        b.right > size.width + _tolerance ||
        b.bottom > size.height + _tolerance) {
      found.add(ChartOverlap(ChartOverlapKind.textOutside, a.id));
    }
    if (legendRect != null &&
        !a.id.startsWith(ids.legendPrefix) &&
        _hasArea(a.rect) &&
        _overlaps(a.corners, _corners(legendRect))) {
      found.add(ChartOverlap(ChartOverlapKind.textLegend, a.id, ids.legend));
    }
    if (!_hasArea(a.rect)) {
      continue;
    }
    for (int j = i + 1; j < texts.length; j++) {
      final TextPrimitive other = texts[j];
      if (_hasArea(other.rect) && _overlaps(a.corners, other.corners)) {
        found.add(ChartOverlap(ChartOverlapKind.textText, a.id, other.id));
      }
    }
  }
  if (legendRect != null && plotRect != null) {
    if (_hasArea(legendRect) &&
        _hasArea(plotRect) &&
        _overlaps(_corners(legendRect), _corners(plotRect))) {
      found.add(
        const ChartOverlap(ChartOverlapKind.legendPlot, ids.legend, ids.plot),
      );
    }
  }
  return found;
}

/// Whether texts [a] and [b] share area, by the same test [findOverlaps]
/// uses; a text with no area overlaps nothing.
bool textsOverlap(TextPrimitive a, TextPrimitive b) =>
    _hasArea(a.rect) && _hasArea(b.rect) && _overlaps(a.corners, b.corners);

bool _hasArea(ChartRect r) => r.width > 0 && r.height > 0;

List<ChartPoint> _corners(ChartRect r) => <ChartPoint>[
  ChartPoint(r.left, r.top),
  ChartPoint(r.right, r.top),
  ChartPoint(r.right, r.bottom),
  ChartPoint(r.left, r.bottom),
];

/// Whether convex quadrilaterals [a] and [b] penetrate by more than the
/// tolerance on every edge normal of both.
bool _overlaps(List<ChartPoint> a, List<ChartPoint> b) {
  for (final List<ChartPoint> shape in <List<ChartPoint>>[a, b]) {
    for (int i = 0; i < shape.length; i++) {
      final ChartPoint p = shape[i];
      final ChartPoint q = shape[(i + 1) % shape.length];
      double nx = q.y - p.y;
      double ny = p.x - q.x;
      final double length = math.sqrt(nx * nx + ny * ny);
      if (length == 0) {
        continue;
      }
      nx /= length;
      ny /= length;
      final List<double> ra = _project(a, nx, ny);
      final List<double> rb = _project(b, nx, ny);
      final double penetration =
          math.min(ra[1], rb[1]) - math.max(ra[0], rb[0]);
      if (penetration <= _tolerance) {
        return false;
      }
    }
  }
  return true;
}

List<double> _project(List<ChartPoint> shape, double nx, double ny) {
  double lo = double.infinity;
  double hi = double.negativeInfinity;
  for (final ChartPoint p in shape) {
    final double d = p.x * nx + p.y * ny;
    lo = math.min(lo, d);
    hi = math.max(hi, d);
  }
  return <double>[lo, hi];
}
