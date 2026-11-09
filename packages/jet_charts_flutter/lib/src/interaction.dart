/// What a pointer over a `JetChart` finds: the hit a hover or a tap reports.
library;

import 'package:flutter/widgets.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_core/jet_core.dart';

/// How far, in logical pixels, a mouse pointer may be from a primitive and
/// still hit it.
const double mouseTolerance = 2;

/// How far, in logical pixels, a touch may be from a primitive and still hit
/// it: a finger is less precise than a mouse.
const double touchTolerance = 8;

/// What a pointer found on a `JetChart`: the topmost primitive under it, that
/// primitive's id read into its parts, the tooltip there and where the
/// pointer was.
///
/// Two hits are equal when all four parts are.
final class JetChartHit {
  /// Creates a hit of the primitive [id] at [position].
  const JetChartHit({
    required this.id,
    this.element,
    this.tooltip,
    required this.position,
  });

  /// The id of the topmost primitive under the pointer, in the scheme that
  /// `ChartLayout.primitives` describes.
  final String id;

  /// [id] read by `ChartElementId.parse`, or `null` when it does not parse.
  final ChartElementId? element;

  /// The tooltip at the pointer (`chartTooltipAt`), or `null` when nothing
  /// there has one. It may come from a primitive below the topmost one (a
  /// grid line over the plot gives the plot's category tooltip). It is
  /// computed even when the chart shows no tooltip box.
  final ChartTooltip? tooltip;

  /// Where the pointer was, in the chart's own coordinates (its top left
  /// corner is the origin), in logical pixels.
  final Offset position;

  @override
  bool operator ==(Object other) =>
      other is JetChartHit &&
      id == other.id &&
      element == other.element &&
      tooltip == other.tooltip &&
      position == other.position;

  @override
  int get hashCode => Object.hash(id, element, tooltip, position);

  @override
  String toString() => 'JetChartHit($id at $position, $tooltip)';
}

/// The hit at [position] of [layout], the layout of [chart] in [theme] and
/// [locale], with [tolerance]; `null` when no primitive is under it.
JetChartHit? chartHitAt(
  Chart chart,
  ChartLayout layout,
  Offset position, {
  required ChartTheme theme,
  required FormatLocale locale,
  required double tolerance,
}) {
  final ChartPoint point = ChartPoint(position.dx, position.dy);
  final List<ChartPrimitive> hits = hitTestLayout(
    layout,
    point,
    tolerance: tolerance,
  );
  if (hits.isEmpty) {
    return null;
  }
  final String id = hits.first.id;
  return JetChartHit(
    id: id,
    element: ChartElementId.parse(id),
    tooltip: chartTooltipAt(
      chart,
      layout,
      point,
      theme: theme,
      locale: locale,
      tolerance: tolerance,
    ),
    position: position,
  );
}
