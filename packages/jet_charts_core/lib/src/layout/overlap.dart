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

  /// A text shares area with a series mark (a bar, a line, a marker or a
  /// slice) or a leader line that is not its own: a data label may lie on
  /// its own bar or slice and touch its own leader line. Area fills are not
  /// marks here: labels are painted over them.
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
/// starts with `series/`) and leader line (`label/<s>/<c>/leader`), as far as
/// the mark lies inside the clips that hold it: a bar by its rectangle, a
/// marker (a full disc) by the square around its outline, a slice or ring
/// (any other arc) by polygons of its sector that hold its outline
/// (`arcShapeReach`), a line (or a closed path's outline, when stroked) by
/// each segment widened to its stroke width and lengthened by half of it at
/// both ends, for round caps. A data label `label/<s>/<c>` may lie on its own
/// bar `series/<s>/bar/<c>` or slice `series/<s>/slice/<c>` and on its own
/// leader line; every other mark counts (in a pie or donut, the slices of
/// other labels, and every slice for the centre text). The fill of a closed path
/// (an area) does not count: data labels are painted after every mark, over
/// area fills, as Excel draws them. Grid lines, axis lines, the background,
/// the plot rectangle and legend symbols are not marks, and a text crossing
/// the plot's edge is not reported.
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
  final BoxGrid<int> markGrid = BoxGrid<int>();
  for (int m = 0; m < marks.length; m++) {
    if (marks[m].box != null) {
      markGrid.add(m, marks[m].box!);
    }
  }
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
    final Set<int> near = <int>{};
    markGrid.any(a.bounds, (int m) {
      near.add(m);
      return false;
    });
    for (final int m in near.toList()..sort()) {
      final LaidMark mark = marks[m];
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

/// Items filed by the cells of a square grid their boxes cover, so that a
/// query looks only at the items near its box: placing data labels and
/// checking text against marks stay near linear in the number of labels.
final class BoxGrid<T> {
  /// The side of a cell, in points: about a short label's size.
  static const double _cell = 32;

  /// The most cells one item is filed in; a larger one goes in [_wide].
  static const int _maxCells = 4096;

  final Map<int, List<T>> _cells = <int, List<T>>{};
  final List<T> _wide = <T>[];

  /// The cells [box] covers, or null when it is too large or not finite.
  static (int, int, int, int)? _span(ChartRect box) {
    final double x0 = (box.left / _cell).floorToDouble();
    final double y0 = (box.top / _cell).floorToDouble();
    final double x1 = (box.right / _cell).floorToDouble();
    final double y1 = (box.bottom / _cell).floorToDouble();
    for (final double v in <double>[x0, y0, x1, y1]) {
      if (!v.isFinite || v.abs() > 1e6) {
        return null;
      }
    }
    if ((x1 - x0 + 1) * (y1 - y0 + 1) > _maxCells) {
      return null;
    }
    return (x0.toInt(), y0.toInt(), x1.toInt(), y1.toInt());
  }

  static int _key(int x, int y) => (x + 2000000) * 4000001 + (y + 2000000);

  /// Files [item], whose shapes lie within [box].
  void add(T item, ChartRect box) {
    final (int, int, int, int)? span = _span(box);
    if (span == null) {
      _wide.add(item);
      return;
    }
    for (int x = span.$1; x <= span.$3; x++) {
      for (int y = span.$2; y <= span.$4; y++) {
        (_cells[_key(x, y)] ??= <T>[]).add(item);
      }
    }
  }

  /// Whether [test] holds for an item that may meet [box]; it is called on
  /// every item filed in a cell [box] covers (an item may come more than
  /// once) and every item too large to file, until it returns true.
  bool any(ChartRect box, bool Function(T item) test) {
    if (_wide.any(test)) {
      return true;
    }
    final (int, int, int, int)? span = _span(box);
    if (span == null) {
      return _cells.values.any((List<T> cell) => cell.any(test));
    }
    for (int x = span.$1; x <= span.$3; x++) {
      for (int y = span.$2; y <= span.$4; y++) {
        final List<T>? cell = _cells[_key(x, y)];
        if (cell != null && cell.any(test)) {
          return true;
        }
      }
    }
    return false;
  }
}

/// A series mark and the part of the chart its clips leave visible.
///
/// Its shapes are sorted by the left edge of their boxes, so that a text is
/// compared only with the shapes whose boxes can reach it: a long line's
/// segments are found by a binary search, not one by one.
final class LaidMark {
  /// Creates the mark [mark], visible inside [clip] (everywhere when null).
  factory LaidMark(ChartPrimitive mark, ChartRect? clip) {
    final List<(List<ChartPoint>, ChartRect)> shapes =
        <(List<ChartPoint>, ChartRect)>[
          for (final List<ChartPoint> shape in _shapes(mark))
            (shape, _boxOf(<List<ChartPoint>>[shape])),
        ]..sort(
          ((List<ChartPoint>, ChartRect) a, (List<ChartPoint>, ChartRect) b) =>
              a.$2.left.compareTo(b.$2.left),
        );
    double widest = 0;
    for (final (List<ChartPoint>, ChartRect) shape in shapes) {
      widest = math.max(widest, shape.$2.width);
    }
    return LaidMark._(
      mark,
      clip,
      <List<ChartPoint>>[
        for (final (List<ChartPoint>, ChartRect) x in shapes) x.$1,
      ],
      <ChartRect>[for (final (List<ChartPoint>, ChartRect) x in shapes) x.$2],
      widest,
      shapes.isEmpty
          ? null
          : _boxOf(<List<ChartPoint>>[
              for (final (List<ChartPoint>, ChartRect) x in shapes)
                _corners(x.$2),
            ]),
    );
  }

  LaidMark._(
    this.mark,
    this.clip,
    this.shapes,
    this._boxes,
    this._widest,
    this.box,
  );

  /// The mark.
  final ChartPrimitive mark;

  /// The intersection of the clips that hold [mark], or null for none.
  final ChartRect? clip;

  /// The shapes the mark covers, as polygons (see [findOverlaps]), sorted by
  /// the left edge of their boxes.
  final List<List<ChartPoint>> shapes;

  /// The box of each of [shapes].
  final List<ChartRect> _boxes;

  /// The width of the widest of [_boxes].
  final double _widest;

  /// The axis-aligned box of [shapes], or null when there are none.
  final ChartRect? box;

  /// The indexes of the shapes whose boxes may meet [bounds], in order.
  Iterable<int> _near(ChartRect bounds) sync* {
    // The first shape whose box's left edge is past bounds.left - widest:
    // no earlier box reaches bounds.
    int lo = 0;
    int hi = _boxes.length;
    final double from = bounds.left - _widest;
    while (lo < hi) {
      final int mid = (lo + hi) >> 1;
      if (_boxes[mid].left < from) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (int i = lo; i < _boxes.length && _boxes[i].left < bounds.right; i++) {
      if (_boxesMeet(bounds, _boxes[i])) {
        yield i;
      }
    }
  }
}

/// Every series mark of [primitives] (an id starting with `series/`) and
/// every leader line (`label/<s>/<c>/leader`), in paint order, with the clips
/// that hold it.
List<LaidMark> laidMarks(List<ChartPrimitive> primitives) {
  final List<LaidMark> out = <LaidMark>[];
  void collect(List<ChartPrimitive> list, ChartRect? clip) {
    for (final ChartPrimitive p in list) {
      if (p is ClipPrimitive) {
        collect(
          p.children,
          clip == null ? p.rect : _intersection(clip, p.rect),
        );
      } else if ((p.id.startsWith(ids.seriesPrefix) &&
              (p is RectPrimitive ||
                  p is PathPrimitive ||
                  p is ArcPrimitive)) ||
          (p is PathPrimitive && _isLeader(p.id))) {
        out.add(LaidMark(p, clip));
      }
    }
  }

  collect(primitives, null);
  return out;
}

/// Whether [markId] is the own mark of the text [textId]: the bar or the
/// slice of a data label's value, or the label's leader line.
bool isOwnMark(String textId, String markId) {
  if (!textId.startsWith(ids.dataLabelPrefix)) {
    return false;
  }
  final List<String> parts = textId.split('/');
  if (parts.length != 3) {
    return false;
  }
  return markId == 'series/${parts[1]}/bar/${parts[2]}' ||
      markId == 'series/${parts[1]}/slice/${parts[2]}' ||
      markId == '$textId/leader';
}

/// Whether [id] is a leader line's, `label/<s>/<c>/leader`.
bool _isLeader(String id) =>
    id.startsWith(ids.dataLabelPrefix) &&
    id.endsWith('/leader') &&
    id.split('/').length == 4;

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
  for (final int index in mark._near(bounds)) {
    final List<ChartPoint> shape = mark.shapes[index];
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
      return _arcShapes(p);
    case PathPrimitive():
      final List<ChartPoint> points = p.points;
      // A closed path's fill (an area) is not a shape: labels are painted
      // over it.
      final List<List<ChartPoint>> out = <List<ChartPoint>>[];
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

/// The most degrees one edge of an arc's polygon spans.
const double _arcStep = 3;

/// The pieces an arc's shape is cut into span at most this many degrees.
const double _arcPiece = 90;

/// How far the outline of an arc of [radius] drawn with a stroke of
/// [strokeWidth] (none when [stroked] is false) may reach from its centre in
/// [findOverlaps]: the radius and half the stroke, grown so that the polygon
/// of edges of at most 3 degrees holds the circle.
double arcShapeReach(
  double radius,
  double strokeWidth, {
  bool stroked = true,
}) =>
    (radius + (stroked ? math.max(0, strokeWidth) / 2 : 0)) /
    math.cos(_arcStep / 2 * math.pi / 180);

/// The distance from an arc's centre within which [findOverlaps] finds none
/// of its shape, for an arc of [innerRadius] drawn with a stroke of
/// [strokeWidth] (none when [stroked] is false): the inner radius less half
/// the stroke, less how far the chords of its polygon cut into the hole.
double arcShapeClearance(
  double innerRadius,
  double strokeWidth, {
  bool stroked = true,
}) => math.max(
  0,
  (innerRadius - (stroked ? math.max(0, strokeWidth) / 2 : 0)) *
      math.cos(_arcStep / 2 * math.pi / 180),
);

/// The shapes of [arc]: a full disc (a marker) by the square around its
/// outline; any other arc (a slice or a ring) by polygons of its sector, cut
/// in pieces of at most 90 degrees, whose outer edges span at most 3 degrees
/// and hold the outline ([arcShapeReach]) and whose inner points lie on the
/// inner radius less half the stroke ([arcShapeClearance]).
List<List<ChartPoint>> _arcShapes(ArcPrimitive arc) {
  final bool stroked = arc.stroke != null;
  final double outer = arcShapeReach(
    arc.radius,
    arc.strokeWidth,
    stroked: stroked,
  );
  final double sweep = arc.sweepAngle;
  if (!(outer > 0) ||
      !outer.isFinite ||
      !sweep.isFinite ||
      !arc.startAngle.isFinite ||
      !arc.center.x.isFinite ||
      !arc.center.y.isFinite) {
    return const <List<ChartPoint>>[];
  }
  final double inner = math.max(
    0,
    arc.innerRadius - (stroked ? math.max(0, arc.strokeWidth) / 2 : 0),
  );
  if (inner <= 0 && sweep.abs() >= 360) {
    final double r =
        arc.radius + (stroked ? math.max(0, arc.strokeWidth) / 2 : 0);
    return <List<ChartPoint>>[
      _corners(ChartRect(arc.center.x - r, arc.center.y - r, 2 * r, 2 * r)),
    ];
  }
  final double total = math.min(sweep.abs(), 360);
  if (!(total > 0)) {
    return const <List<ChartPoint>>[];
  }
  final double from = sweep >= 0 ? arc.startAngle : arc.startAngle - total;
  ChartPoint at(double degrees, double r) {
    final double a = degrees * math.pi / 180;
    return ChartPoint(
      arc.center.x + r * math.cos(a),
      arc.center.y + r * math.sin(a),
    );
  }

  final int pieces = (total / _arcPiece).ceil();
  final List<List<ChartPoint>> out = <List<ChartPoint>>[];
  for (int k = 0; k < pieces; k++) {
    final double a0 = from + total * k / pieces;
    final double span = total / pieces;
    final int edges = math.max(1, (span / _arcStep).ceil());
    final List<ChartPoint> shape = <ChartPoint>[
      // The outer points sit on the grown reach, so the polygon's chords
      // hold the arc.
      at(a0, outer),
      for (int i = 1; i < edges; i++) at(a0 + span * i / edges, outer),
      at(a0 + span, outer),
    ];
    if (inner > 0) {
      for (int i = edges; i >= 0; i--) {
        shape.add(at(a0 + span * i / edges, inner));
      }
    } else {
      shape.add(arc.center);
    }
    out.add(shape);
  }
  return out;
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

/// The axis-aligned box of the points of [shapes], none of them empty.
ChartRect _boxOf(List<List<ChartPoint>> shapes) {
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
