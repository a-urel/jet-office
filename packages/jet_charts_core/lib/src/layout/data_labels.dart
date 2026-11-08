/// Data labels: the value of each point, placed without overlap.
///
/// A label takes the first of its candidate places that lies inside the plot
/// and shares no area with a text already drawn (axis labels, titles, the
/// legend) or a label already placed. Labels are placed in series order, then
/// category order, so an earlier one wins a place. A label with no such place
/// is hidden.
library;

import 'dart:math' as math;

import 'package:jet_core/jet_core.dart';

import '../model/chart.dart';
import '../model/chart_kind.dart';
import '../scale/value_scale.dart';
import '../theme/chart_theme.dart';
import 'axis_layout.dart';
import 'chart_ids.dart' as ids;
import 'geometry.dart';
import 'marks.dart';
import 'overlap.dart';
import 'primitives.dart';
import 'resolve.dart';
import 'text_measurer.dart';

/// The data labels that were placed, and the texts that were not.
final class DataLabelPlacement {
  /// Creates a placement of [primitives] and [hidden].
  const DataLabelPlacement(this.primitives, this.hidden);

  /// The placed labels, in series then category order.
  final List<TextPrimitive> primitives;

  /// The id and full text of each label that found no place.
  final List<(String, String)> hidden;
}

/// The id and text of every data label [chart] asks for, in series then
/// category order: one per value that is not missing.
///
/// A label's number format code is the data labels' code, else its series',
/// else `General`.
List<(String, String)> dataLabelTexts(
  Chart chart,
  ResolvedChart resolved,
  NumberFormatter formatter,
) {
  if (!chart.dataLabels.visible) {
    return const <(String, String)>[];
  }
  return <(String, String)>[
    for (int s = 0; s < resolved.values.length; s++)
      for (int c = 0; c < resolved.values[s].length; c++)
        if (resolved.values[s][c] != null)
          (
            ids.dataLabelId(s, c),
            formatTick(
              resolved.values[s][c]!,
              chart.dataLabels.formatCode ??
                  (s < chart.series.length
                      ? chart.series[s].formatCode
                      : null) ??
                  'General',
              formatter,
            ),
          ),
  ];
}

/// Places the data labels of [chart] on [plot], clear of [existing] texts.
///
/// Column and bar labels try outside end, inside end, then centre (stacked
/// ones only centre); line labels above, below, right, then left of the
/// point; an area label is centred on the column under its point, halfway
/// between the point and the area's base. Nothing is placed unless the chart
/// asks for data labels.
DataLabelPlacement placeDataLabels({
  required Chart chart,
  required ResolvedChart resolved,
  required ChartTheme theme,
  required TextMeasurer measurer,
  required NumberFormatter formatter,
  required ChartRect plot,
  required ValueScale scale,
  required List<ChartPrimitive> existing,
}) {
  final List<(String, String)> texts = dataLabelTexts(
    chart,
    resolved,
    formatter,
  );
  if (texts.isEmpty) {
    return const DataLabelPlacement(<TextPrimitive>[], <(String, String)>[]);
  }
  final Map<String, String> textById = <String, String>{
    for (final (String, String) t in texts) t.$1: t.$2,
  };
  final Map<String, MarkAnchor> anchors = <String, MarkAnchor>{
    for (final MarkAnchor a in layoutAnchors(
      chart,
      resolved,
      theme,
      plot,
      scale,
    ))
      ids.dataLabelId(a.series, a.category): a,
  };
  final List<TextPrimitive> obstacles = <TextPrimitive>[
    for (final ChartPrimitive p in _flat(existing))
      if (p is TextPrimitive) p,
  ];
  final bool bar = chart.kind == ChartKind.bar;
  final bool stacked = resolved.grouping != ChartGrouping.clustered;
  final double crossing = crossingValue(scale);
  final double gap = theme.spacing.labelGap;
  final double apart = theme.spacing.minTextGap;
  final List<TextPrimitive> placed = <TextPrimitive>[];
  final List<(String, String)> hidden = <(String, String)>[];
  for (final (String, String) t in texts) {
    final MarkAnchor? anchor = anchors[t.$1];
    final ChartSize size = measurer.measure(t.$2, theme.dataLabels);
    TextPrimitive? chosen;
    if (anchor != null) {
      final double value = _valueOf(resolved, anchor);
      for (final ChartRect candidate in _candidates(
        chart.kind,
        anchor,
        size,
        plot,
        stacked: stacked,
        bar: bar,
        negative: value < crossing,
        gap: gap,
        markerGap: gap + theme.markerSize / 2,
        sideGap: gap + theme.markerSize / 2 + apart,
      )) {
        if (!plot.contains(candidate)) {
          continue;
        }
        final TextPrimitive probe = TextPrimitive(
          t.$1,
          t.$2,
          ChartRect(
            candidate.left - apart,
            candidate.top - apart,
            candidate.width + 2 * apart,
            candidate.height + 2 * apart,
          ),
          theme.dataLabels,
        );
        if (obstacles.any((TextPrimitive o) => textsOverlap(probe, o)) ||
            placed.any((TextPrimitive o) => textsOverlap(probe, o))) {
          continue;
        }
        chosen = TextPrimitive(t.$1, t.$2, candidate, theme.dataLabels);
        break;
      }
    }
    if (chosen == null) {
      hidden.add((t.$1, textById[t.$1]!));
    } else {
      placed.add(chosen);
    }
  }
  return DataLabelPlacement(placed, hidden);
}

double _valueOf(ResolvedChart resolved, MarkAnchor a) =>
    resolved.values[a.series][a.category] ?? 0;

Iterable<ChartPrimitive> _flat(List<ChartPrimitive> list) sync* {
  for (final ChartPrimitive p in list) {
    yield p;
    if (p is ClipPrimitive) {
      yield* _flat(p.children);
    }
  }
}

/// The places to try for a label of [size], in order.
///
/// A line label is [markerGap] from its point above or below it, and
/// [sideGap] (a minimum text gap more) beside it, so that a label beside a
/// point is not a hair's breadth from one above or below it.
List<ChartRect> _candidates(
  ChartKind kind,
  MarkAnchor anchor,
  ChartSize size,
  ChartRect plot, {
  required bool stacked,
  required bool bar,
  required bool negative,
  required double gap,
  required double markerGap,
  required double sideGap,
}) {
  final double w = size.width;
  final double h = size.height;
  ChartRect around(double cx, double cy) =>
      ChartRect(cx - w / 2, cy - h / 2, w, h);
  switch (kind) {
    case ChartKind.column:
    case ChartKind.bar:
      final ChartRect r = _visible(anchor.bar!, plot);
      final double cx = r.left + r.width / 2;
      final double cy = r.top + r.height / 2;
      final ChartRect centre = around(cx, cy);
      if (stacked) {
        return <ChartRect>[centre];
      }
      if (bar) {
        return negative
            ? <ChartRect>[
                ChartRect(r.left - gap - w, cy - h / 2, w, h),
                ChartRect(r.left + gap, cy - h / 2, w, h),
                centre,
              ]
            : <ChartRect>[
                ChartRect(r.right + gap, cy - h / 2, w, h),
                ChartRect(r.right - gap - w, cy - h / 2, w, h),
                centre,
              ];
      }
      return negative
          ? <ChartRect>[
              ChartRect(cx - w / 2, r.bottom + gap, w, h),
              ChartRect(cx - w / 2, r.bottom - gap - h, w, h),
              centre,
            ]
          : <ChartRect>[
              ChartRect(cx - w / 2, r.top - gap - h, w, h),
              ChartRect(cx - w / 2, r.top + gap, w, h),
              centre,
            ];
    case ChartKind.line:
      final ChartPoint p = anchor.point!;
      return <ChartRect>[
        ChartRect(p.x - w / 2, p.y - markerGap - h, w, h),
        ChartRect(p.x - w / 2, p.y + markerGap, w, h),
        ChartRect(p.x + sideGap, p.y - h / 2, w, h),
        ChartRect(p.x - sideGap - w, p.y - h / 2, w, h),
      ];
    case ChartKind.area:
      final ChartPoint p = anchor.point!;
      final ChartPoint b = anchor.base!;
      return <ChartRect>[around((p.x + b.x) / 2, (p.y + b.y) / 2)];
    default:
      return const <ChartRect>[];
  }
}

/// The part of [bar] inside [plot]; where they share nothing, a rectangle
/// with no area on [bar]'s nearest edge (which no label fits in).
ChartRect _visible(ChartRect bar, ChartRect plot) {
  final double left = math.min(math.max(bar.left, plot.left), plot.right);
  final double top = math.min(math.max(bar.top, plot.top), plot.bottom);
  final double right = math.max(math.min(bar.right, plot.right), left);
  final double bottom = math.max(math.min(bar.bottom, plot.bottom), top);
  return ChartRect(left, top, right - left, bottom - top);
}
