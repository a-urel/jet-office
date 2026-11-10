/// The light animation of a chart's marks between two layouts.
library;

import 'package:jet_charts_core/jet_charts_core.dart';

/// The primitives shown at [t] of the way from [from] to [to], two layouts of
/// a chart at the same size.
///
/// Only marks move: bars, lines, markers, areas and pie or donut slices
/// (`ChartElementId.kind` `bar`, `line`, `marker`, `area` and `slice`). A mark whose id is in both lists, as
/// the same type of primitive, is interpolated: a rectangle by its left, top,
/// width and height; a path point by point when both have as many points,
/// else it is `to`'s path; an arc (a line's marker) by its centre, radii and
/// angles (a slice is an arc: its start and sweep angles and its radii move
/// linearly; one only in [to] grows from a sweep of 0 at its final start
/// angle). Its colours, widths and dashes are `to`'s. A mark
/// only in [to] shows from the start, and a mark only in [from] is dropped.
/// A series' markers are `to`'s when any run of its line is `to`'s (its point
/// count changed, or the run is only in [to]), so they never leave the line.
/// Every other primitive is [to]'s, in [to]'s order, except data labels
/// (`dataLabel`) and their leader lines (`leaderLine`), which are left out until [t] is 1, so no text crosses a
/// moving mark. A clip holds what this gives for its children and the
/// children of the clip of the same id in [from].
///
/// [t] is clamped to 0 to 1; at 1 the result is [to] itself.
List<ChartPrimitive> lerpChartPrimitives(
  List<ChartPrimitive> from,
  List<ChartPrimitive> to,
  double t,
) {
  final double at = t.isNaN ? 1 : t.clamp(0, 1).toDouble();
  if (at == 1) {
    return to;
  }
  return _lerpList(from, to, at, _snappedSeries(from, to));
}

/// Every primitive of [primitives], the children of clips included.
Iterable<ChartPrimitive> _flat(List<ChartPrimitive> primitives) sync* {
  for (final ChartPrimitive p in primitives) {
    yield p;
    if (p is ClipPrimitive) {
      yield* _flat(p.children);
    }
  }
}

/// The series of which a line run of [to] cannot be interpolated from [from]
/// (no path of the same id and point count there), so it snaps.
Set<int> _snappedSeries(List<ChartPrimitive> from, List<ChartPrimitive> to) {
  final Map<String, ChartPrimitive> before = <String, ChartPrimitive>{
    for (final ChartPrimitive p in _flat(from)) p.id: p,
  };
  final Set<int> snapped = <int>{};
  for (final ChartPrimitive p in _flat(to)) {
    final ChartElementId? element = ChartElementId.parse(p.id);
    if (element?.kind != ChartElementKind.line || p is! PathPrimitive) {
      continue;
    }
    final ChartPrimitive? source = before[p.id];
    if (source is! PathPrimitive || source.points.length != p.points.length) {
      snapped.add(element!.series!);
    }
  }
  return snapped;
}

List<ChartPrimitive> _lerpList(
  List<ChartPrimitive> from,
  List<ChartPrimitive> to,
  double t,
  Set<int> snapped,
) {
  final Map<String, ChartPrimitive> before = <String, ChartPrimitive>{
    for (final ChartPrimitive p in from) p.id: p,
  };
  final List<ChartPrimitive> result = <ChartPrimitive>[];
  for (final ChartPrimitive target in to) {
    final ChartPrimitive? source = before[target.id];
    if (target is ClipPrimitive) {
      result.add(
        ClipPrimitive(
          target.id,
          target.rect,
          _lerpList(
            source is ClipPrimitive
                ? source.children
                : const <ChartPrimitive>[],
            target.children,
            t,
            snapped,
          ),
        ),
      );
      continue;
    }
    final ChartElementId? element = ChartElementId.parse(target.id);
    switch (element?.kind) {
      case ChartElementKind.dataLabel || ChartElementKind.leaderLine:
        break;
      case ChartElementKind.slice when source == null && target is ArcPrimitive:
        result.add(_grownSlice(target, t));
      case ChartElementKind.marker when snapped.contains(element!.series):
        result.add(target);
      case ChartElementKind.bar ||
          ChartElementKind.line ||
          ChartElementKind.marker ||
          ChartElementKind.area ||
          ChartElementKind.slice:
        result.add(source == null ? target : _lerpMark(source, target, t));
      default:
        result.add(target);
    }
  }
  return result;
}

/// A slice that only [target] has, [t] of the way grown: it keeps its final
/// start angle and sweeps [t] of its final sweep.
ArcPrimitive _grownSlice(ArcPrimitive target, double t) => ArcPrimitive(
  target.id,
  target.center,
  target.radius,
  target.innerRadius,
  target.startAngle,
  target.sweepAngle * t,
  fill: target.fill,
  stroke: target.stroke,
  strokeWidth: target.strokeWidth,
);

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// [target] moved [t] of the way from [source], or [target] when the two
/// cannot be interpolated.
ChartPrimitive _lerpMark(
  ChartPrimitive source,
  ChartPrimitive target,
  double t,
) {
  if (source is RectPrimitive && target is RectPrimitive) {
    final ChartRect a = source.rect;
    final ChartRect b = target.rect;
    return RectPrimitive(
      target.id,
      ChartRect(
        _lerp(a.left, b.left, t),
        _lerp(a.top, b.top, t),
        _lerp(a.width, b.width, t),
        _lerp(a.height, b.height, t),
      ),
      fill: target.fill,
      stroke: target.stroke,
      strokeWidth: target.strokeWidth,
    );
  }
  if (source is PathPrimitive &&
      target is PathPrimitive &&
      source.points.length == target.points.length) {
    return PathPrimitive(
      target.id,
      <ChartPoint>[
        for (int i = 0; i < target.points.length; i++)
          ChartPoint(
            _lerp(source.points[i].x, target.points[i].x, t),
            _lerp(source.points[i].y, target.points[i].y, t),
          ),
      ],
      closed: target.closed,
      fill: target.fill,
      fillOpacity: target.fillOpacity,
      stroke: target.stroke,
      strokeWidth: target.strokeWidth,
      dash: target.dash,
    );
  }
  if (source is ArcPrimitive && target is ArcPrimitive) {
    return ArcPrimitive(
      target.id,
      ChartPoint(
        _lerp(source.center.x, target.center.x, t),
        _lerp(source.center.y, target.center.y, t),
      ),
      _lerp(source.radius, target.radius, t),
      _lerp(source.innerRadius, target.innerRadius, t),
      _lerp(source.startAngle, target.startAngle, t),
      _lerp(source.sweepAngle, target.sweepAngle, t),
      fill: target.fill,
      stroke: target.stroke,
      strokeWidth: target.strokeWidth,
    );
  }
  return target;
}
