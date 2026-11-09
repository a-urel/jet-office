/// Finds text that collides with other text, with the legend, with a series
/// mark, or with the edge of the chart.
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

  /// A text shares area with a series mark (a bar, a line, a marker or an
  /// area) that is not its own: a data label may lie on its own bar and on
  /// its own series' area.
  textMark,
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
///
/// Text is also checked against every series mark (a primitive whose id
/// starts with `series/`), as far as the mark lies inside the clips that hold
/// it: a bar by its rectangle, a marker (an arc) by the square around its
/// outline, a line by each segment widened to its stroke width (and lengthened
/// by half of it at both ends, for round caps), an area by its outline. A
/// data label `label/<s>/<c>` may lie on its own bar `series/<s>/bar/<c>` and
/// on its own series' area `series/<s>/area`; every other mark counts. Grid
/// lines, axis lines, the background, the plot rectangle and legend symbols
/// are not marks, and a text crossing the plot's edge is not reported.
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
  final List<LaidMark> marks = laidMarks(primitives);
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
    for (final LaidMark mark in marks) {
      if (!isOwnMark(a.id, mark.mark.id) && textOverlapsMark(a, mark)) {
        found.add(ChartOverlap(ChartOverlapKind.textMark, a.id, mark.mark.id));
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

/// A series mark and the part of the chart its clips leave visible.
final class LaidMark {
  /// Creates the mark [mark], visible inside [clip] (everywhere when null).
  LaidMark(this.mark, this.clip) : shapes = _shapes(mark), box = _box(mark);

  /// The mark.
  final ChartPrimitive mark;

  /// The intersection of the clips that hold [mark], or null for none.
  final ChartRect? clip;

  /// The shapes the mark covers, as polygons (see [findOverlaps]).
  final List<List<ChartPoint>> shapes;

  /// The axis-aligned box of [shapes], or null when there are none.
  final ChartRect? box;
}

/// Every series mark of [primitives] (an id starting with `series/`), in
/// paint order, with the clips that hold it.
List<LaidMark> laidMarks(List<ChartPrimitive> primitives) {
  final List<LaidMark> out = <LaidMark>[];
  void collect(List<ChartPrimitive> list, ChartRect? clip) {
    for (final ChartPrimitive p in list) {
      if (p is ClipPrimitive) {
        collect(
          p.children,
          clip == null ? p.rect : _intersection(clip, p.rect),
        );
      } else if (p.id.startsWith(ids.seriesPrefix) &&
          (p is RectPrimitive || p is PathPrimitive || p is ArcPrimitive)) {
        out.add(LaidMark(p, clip));
      }
    }
  }

  collect(primitives, null);
  return out;
}

/// Whether [markId] is the own mark of the text [textId]: the bar of a data
/// label's value, or the area of its series.
bool isOwnMark(String textId, String markId) {
  if (!textId.startsWith(ids.dataLabelPrefix)) {
    return false;
  }
  final List<String> parts = textId.split('/');
  if (parts.length != 3) {
    return false;
  }
  return markId == 'series/${parts[1]}/bar/${parts[2]}' ||
      markId == 'series/${parts[1]}/area';
}

/// Whether [text] and the visible part of [mark] share area, by more than
/// the overlap tolerance; a text with no area overlaps nothing.
bool textOverlapsMark(TextPrimitive text, LaidMark mark) {
  if (!_hasArea(text.rect) || mark.box == null) {
    return false;
  }
  final ChartRect bounds = text.bounds;
  final ChartRect? clip = mark.clip;
  if (!_boxesMeet(bounds, mark.box!) ||
      (clip != null && !_boxesMeet(bounds, clip))) {
    return false;
  }
  final List<_HalfPlane> planes = <_HalfPlane>[
    ..._planes(text.corners),
    if (clip != null) ..._planes(_corners(clip)),
  ];
  List<ChartPoint> region = text.corners;
  for (final _HalfPlane h in planes) {
    region = h.clip(region);
    if (region.isEmpty) {
      return false;
    }
  }
  if (region.length < 3) {
    return false;
  }
  final ChartPoint centre = _centroid(region);
  for (final List<ChartPoint> shape in mark.shapes) {
    for (int i = 0; i < shape.length; i++) {
      if (_crosses(shape[i], shape[(i + 1) % shape.length], planes)) {
        return true;
      }
    }
    if (_inside(centre, shape)) {
      return true;
    }
  }
  return false;
}

bool _boxesMeet(ChartRect a, ChartRect b) =>
    a.left < b.right &&
    b.left < a.right &&
    a.top < b.bottom &&
    b.top < a.bottom;

ChartRect _intersection(ChartRect a, ChartRect b) {
  final double left = math.max(a.left, b.left);
  final double top = math.max(a.top, b.top);
  final double right = math.max(left, math.min(a.right, b.right));
  final double bottom = math.max(top, math.min(a.bottom, b.bottom));
  return ChartRect(left, top, right - left, bottom - top);
}

List<List<ChartPoint>> _shapes(ChartPrimitive p) {
  switch (p) {
    case RectPrimitive(:final ChartRect rect):
      return _hasArea(rect) ? <List<ChartPoint>>[_corners(rect)] : const [];
    case ArcPrimitive():
      final double r =
          p.radius + (p.stroke == null ? 0 : math.max(0, p.strokeWidth) / 2);
      if (!(r > 0)) {
        return const <List<ChartPoint>>[];
      }
      return <List<ChartPoint>>[
        _corners(ChartRect(p.center.x - r, p.center.y - r, 2 * r, 2 * r)),
      ];
    case PathPrimitive():
      final List<ChartPoint> points = p.points;
      final List<List<ChartPoint>> out = <List<ChartPoint>>[
        if (p.closed && p.fill != null && points.length > 2) points,
      ];
      final double half = math.max(0, p.strokeWidth) / 2;
      if (p.stroke != null && half > 0) {
        final int segments = p.closed && points.length > 2
            ? points.length
            : points.length - 1;
        for (int i = 0; i < segments; i++) {
          final List<ChartPoint>? band = _band(
            points[i],
            points[(i + 1) % points.length],
            half,
          );
          if (band != null) {
            out.add(band);
          }
        }
      }
      return out;
    default:
      return const <List<ChartPoint>>[];
  }
}

/// The segment from [a] to [b] widened by [half] on each side and lengthened
/// by [half] at each end; null for a segment of no length.
List<ChartPoint>? _band(ChartPoint a, ChartPoint b, double half) {
  final double dx = b.x - a.x;
  final double dy = b.y - a.y;
  final double length = math.sqrt(dx * dx + dy * dy);
  if (!(length > 0) || !length.isFinite) {
    return null;
  }
  final double ux = dx / length * half;
  final double uy = dy / length * half;
  return <ChartPoint>[
    ChartPoint(a.x - ux - uy, a.y - uy + ux),
    ChartPoint(b.x + ux - uy, b.y + uy + ux),
    ChartPoint(b.x + ux + uy, b.y + uy - ux),
    ChartPoint(a.x - ux + uy, a.y - uy - ux),
  ];
}

ChartRect? _box(ChartPrimitive p) {
  final List<List<ChartPoint>> shapes = _shapes(p);
  if (shapes.isEmpty) {
    return null;
  }
  double left = double.infinity;
  double top = double.infinity;
  double right = double.negativeInfinity;
  double bottom = double.negativeInfinity;
  for (final List<ChartPoint> shape in shapes) {
    for (final ChartPoint q in shape) {
      left = math.min(left, q.x);
      top = math.min(top, q.y);
      right = math.max(right, q.x);
      bottom = math.max(bottom, q.y);
    }
  }
  return ChartRect(left, top, right - left, bottom - top);
}

/// The half-plane `n . p <= d` of the inside of a convex polygon's edge.
final class _HalfPlane {
  const _HalfPlane(this.nx, this.ny, this.d);

  final double nx;
  final double ny;
  final double d;

  double _side(ChartPoint p) => nx * p.x + ny * p.y - d;

  /// The part of convex [polygon] inside this half-plane.
  List<ChartPoint> clip(List<ChartPoint> polygon) {
    final List<ChartPoint> out = <ChartPoint>[];
    for (int i = 0; i < polygon.length; i++) {
      final ChartPoint p = polygon[i];
      final ChartPoint q = polygon[(i + 1) % polygon.length];
      final double sp = _side(p);
      final double sq = _side(q);
      if (sp <= 0) {
        out.add(p);
      }
      if ((sp < 0 && sq > 0) || (sp > 0 && sq < 0)) {
        final double t = sp / (sp - sq);
        out.add(ChartPoint(p.x + t * (q.x - p.x), p.y + t * (q.y - p.y)));
      }
    }
    return out;
  }
}

/// The half-planes of convex [polygon]'s edges, each moved inward by the
/// overlap tolerance.
List<_HalfPlane> _planes(List<ChartPoint> polygon) {
  double area = 0;
  for (int i = 0; i < polygon.length; i++) {
    final ChartPoint p = polygon[i];
    final ChartPoint q = polygon[(i + 1) % polygon.length];
    area += p.x * q.y - q.x * p.y;
  }
  final double sign = area >= 0 ? 1 : -1;
  final List<_HalfPlane> out = <_HalfPlane>[];
  for (int i = 0; i < polygon.length; i++) {
    final ChartPoint p = polygon[i];
    final ChartPoint q = polygon[(i + 1) % polygon.length];
    double nx = sign * (q.y - p.y);
    double ny = sign * -(q.x - p.x);
    final double length = math.sqrt(nx * nx + ny * ny);
    if (length == 0) {
      continue;
    }
    nx /= length;
    ny /= length;
    out.add(_HalfPlane(nx, ny, nx * p.x + ny * p.y - _tolerance));
  }
  return out;
}

/// Whether some of the segment from [a] to [b] lies inside every one of
/// [planes].
bool _crosses(ChartPoint a, ChartPoint b, List<_HalfPlane> planes) {
  double t0 = 0;
  double t1 = 1;
  for (final _HalfPlane h in planes) {
    final double fa = h._side(a);
    final double fb = h._side(b);
    if (fa > 0 && fb > 0) {
      return false;
    }
    if (fa > 0) {
      t0 = math.max(t0, fa / (fa - fb));
    } else if (fb > 0) {
      t1 = math.min(t1, fa / (fa - fb));
    }
    if (t0 >= t1) {
      return false;
    }
  }
  return true;
}

ChartPoint _centroid(List<ChartPoint> polygon) {
  double x = 0;
  double y = 0;
  for (final ChartPoint p in polygon) {
    x += p.x;
    y += p.y;
  }
  return ChartPoint(x / polygon.length, y / polygon.length);
}

/// Whether [p] lies inside [polygon], by the even-odd rule.
bool _inside(ChartPoint p, List<ChartPoint> polygon) {
  bool inside = false;
  for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final ChartPoint a = polygon[i];
    final ChartPoint b = polygon[j];
    if ((a.y > p.y) != (b.y > p.y) &&
        p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}

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
