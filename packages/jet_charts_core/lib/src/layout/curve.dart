/// The curve of a smooth line, as a polyline.
///
/// Excel's own smoothing is not documented. This is a Catmull-Rom spline
/// through the points (each span a cubic Bezier), an estimate, not checked in
/// Excel; the owner's comparison is E2.
library;

import 'geometry.dart';

/// The curve through [points], as a polyline.
///
/// Each span `P1` to `P2` is a cubic Bezier with the control points
/// `P1 + (P2 - P0) / 6` and `P2 - (P3 - P1) / 6` (Catmull-Rom; `P0` is `P1`
/// at the start and `P3` is `P2` at the end). It is cut into pieces by
/// subdivision until the curve is within [tolerance] of its chord, at most 64
/// pieces a span, so the result holds every one of [points], and at most
/// `64 * (n - 1) + 1` points. Fewer than three points come back unchanged, and
/// so does a span with a point that is not finite.
///
/// This is an estimate of Excel's smoothing, not checked in Excel.
List<ChartPoint> smoothPolyline(
  List<ChartPoint> points, {
  double tolerance = 0.5,
}) {
  final int n = points.length;
  if (n < 3) {
    return List<ChartPoint>.of(points);
  }
  final List<ChartPoint> out = <ChartPoint>[points.first];
  for (int i = 0; i < n - 1; i++) {
    final ChartPoint p0 = points[i == 0 ? 0 : i - 1];
    final ChartPoint p1 = points[i];
    final ChartPoint p2 = points[i + 1];
    final ChartPoint p3 = points[i + 2 < n ? i + 2 : i + 1];
    final ChartPoint c1 = ChartPoint(
      p1.x + (p2.x - p0.x) / 6,
      p1.y + (p2.y - p0.y) / 6,
    );
    final ChartPoint c2 = ChartPoint(
      p2.x - (p3.x - p1.x) / 6,
      p2.y - (p3.y - p1.y) / 6,
    );
    if (_finite(p1) && _finite(c1) && _finite(c2) && _finite(p2)) {
      _flatten(p1, c1, c2, p2, tolerance, 0, out);
    }
    out.add(p2);
  }
  return out;
}

bool _finite(ChartPoint p) => p.x.isFinite && p.y.isFinite;

/// Adds the points strictly between the ends of the Bezier [a], [b], [c], [d]
/// to [out]: none when it is within [tolerance] of its chord or [depth] has
/// reached the piece limit (2 to the 6th is 64).
void _flatten(
  ChartPoint a,
  ChartPoint b,
  ChartPoint c,
  ChartPoint d,
  double tolerance,
  int depth,
  List<ChartPoint> out,
) {
  if (depth >= 6 || _flat(a, b, c, d, tolerance)) {
    return;
  }
  final ChartPoint ab = _mid(a, b);
  final ChartPoint bc = _mid(b, c);
  final ChartPoint cd = _mid(c, d);
  final ChartPoint abc = _mid(ab, bc);
  final ChartPoint bcd = _mid(bc, cd);
  final ChartPoint m = _mid(abc, bcd);
  _flatten(a, ab, abc, m, tolerance, depth + 1, out);
  out.add(m);
  _flatten(m, bcd, cd, d, tolerance, depth + 1, out);
}

ChartPoint _mid(ChartPoint p, ChartPoint q) =>
    ChartPoint((p.x + q.x) / 2, (p.y + q.y) / 2);

/// Whether the control points [b] and [c] lie within [tolerance] of the chord
/// from [a] to [d], which bounds the curve's distance from it.
bool _flat(
  ChartPoint a,
  ChartPoint b,
  ChartPoint c,
  ChartPoint d,
  double tolerance,
) {
  final double dx = d.x - a.x;
  final double dy = d.y - a.y;
  final double length = dx * dx + dy * dy;
  double distance(ChartPoint p) {
    if (length == 0) {
      final double ex = p.x - a.x;
      final double ey = p.y - a.y;
      return ex * ex + ey * ey;
    }
    final double cross = (p.x - a.x) * dy - (p.y - a.y) * dx;
    return cross * cross / length;
  }

  final double limit = tolerance * tolerance;
  return distance(b) <= limit && distance(c) <= limit;
}
