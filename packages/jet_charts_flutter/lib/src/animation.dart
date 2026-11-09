/// The light animation of a chart's marks between two layouts.
library;

import 'package:jet_charts_core/jet_charts_core.dart';

/// The primitives shown at [t] of the way from [from] to [to], two layouts of
/// a chart at the same size.
///
/// Only marks move: bars, lines, markers and areas (`ChartElementId.kind`
/// `bar`, `line`, `marker` and `area`). A mark whose id is in both lists, as
/// the same type of primitive, is interpolated: a rectangle by its left, top,
/// width and height; a path point by point when both have as many points,
/// else it is `to`'s path. Its colours, widths and dashes are `to`'s. A mark
/// only in [to] shows from the start, and a mark only in [from] is dropped.
/// Every other primitive is [to]'s, in [to]'s order, except data labels
/// (`dataLabel`), which are left out until [t] is 1, so no text crosses a
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
  return _lerpList(from, to, at);
}

List<ChartPrimitive> _lerpList(
  List<ChartPrimitive> from,
  List<ChartPrimitive> to,
  double t,
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
          ),
        ),
      );
      continue;
    }
    switch (ChartElementId.parse(target.id)?.kind) {
      case ChartElementKind.dataLabel:
        break;
      case ChartElementKind.bar ||
          ChartElementKind.line ||
          ChartElementKind.marker ||
          ChartElementKind.area:
        result.add(source == null ? target : _lerpMark(source, target, t));
      default:
        result.add(target);
    }
  }
  return result;
}

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
      stroke: target.stroke,
      strokeWidth: target.strokeWidth,
      dash: target.dash,
    );
  }
  return target;
}
