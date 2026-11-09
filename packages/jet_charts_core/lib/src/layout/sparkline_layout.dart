/// The layout of sparklines: a small line with no axes, grid or text.
library;

import 'dart:math' as math;

import '../model/chart.dart';
import '../model/chart_kind.dart';
import '../theme/chart_color.dart';
import '../theme/chart_theme.dart';
import 'chart_ids.dart' as ids;
import 'curve.dart';
import 'geometry.dart';
import 'primitives.dart';
import 'resolve.dart';

/// The laid out sparkline: what to draw, the plot, and a band per index.
typedef SparklineLayout = ({
  List<ChartPrimitive> primitives,
  ChartRect? plot,
  List<ChartRect> categoryBands,
});

/// Lays out [chart], a sparkline whose data is [resolved], on [size].
///
/// It draws the background (always, without the theme's border: a sparkline
/// is a mark inside a larger layout), then every series as a line and no
/// title, legend, axis, grid or text. The plot is the whole size inset by the
/// theme's `sparklineWidth`, so a line on its edge stays inside the size. A
/// size too small for a plot of more than 0 by 0 draws only the background.
///
/// Points are spread evenly over the plot's width by index (categories are
/// not read; one index sits in the middle). The value range is the value
/// axis' `min` and `max` where set, else the smallest and largest finite
/// value of all series; a value outside it is put on the plot's edge. When the
/// range is a single value the line is at the vertical centre, except that a
/// fixed `min` puts it on the bottom and, failing that, a fixed `max` on the
/// top.
///
/// Each series is one open path per run of finite values
/// (`series/<s>/line/<run>`, `sparklineWidth` wide, curved when the series is
/// `smooth`; a gap starts a run). A run of one value is a dot, a closed square
/// of side `sparklineWidth * 2` (`series/<s>/marker/<i>`). A series of
/// `kind: ChartKind.area` also fills each run down to the plot's bottom, or to
/// the value 0 when it lies inside the range, with the theme's `areaOpacity`
/// (`series/<s>/area`, one path per run, all with that id), under the lines.
/// This is an estimate of Excel's sparkline, not checked in Excel.
///
/// The bands are one per index, left to right, tiling the plot; the first and
/// last are half as wide, as an area chart's.
SparklineLayout layoutSparkline(
  Chart chart,
  ResolvedChart resolved, {
  required ChartTheme theme,
  required ChartSize size,
}) {
  final List<ChartPrimitive> primitives = <ChartPrimitive>[
    RectPrimitive(
      ids.background,
      ChartRect(0, 0, size.width, size.height),
      fill: theme.background,
    ),
  ];
  final double inset = theme.sparklineWidth;
  final ChartRect plot = ChartRect(
    inset,
    inset,
    size.width - 2 * inset,
    size.height - 2 * inset,
  );
  if (!(plot.width > 0 && plot.height > 0)) {
    return (
      primitives: primitives,
      plot: null,
      categoryBands: const <ChartRect>[],
    );
  }
  final int count = resolved.categoryCount;
  double x(int i) => count < 2
      ? plot.left + plot.width / 2
      : plot.left + plot.width * i / (count - 1);
  final List<ChartRect> bands = <ChartRect>[
    for (int i = 0; i < count; i++)
      ChartRect(
        count < 2 || i == 0 ? plot.left : (x(i - 1) + x(i)) / 2,
        plot.top,
        (count < 2 || i == count - 1 ? plot.right : (x(i) + x(i + 1)) / 2) -
            (count < 2 || i == 0 ? plot.left : (x(i - 1) + x(i)) / 2),
        plot.height,
      ),
  ];

  double? low;
  double? high;
  for (final List<double?> values in resolved.values) {
    for (final double? v in values) {
      if (v != null) {
        low = low == null ? v : math.min(low, v);
        high = high == null ? v : math.max(high, v);
      }
    }
  }
  if (low == null || high == null) {
    return (primitives: primitives, plot: plot, categoryBands: bands);
  }
  final double? fixedMin = _fixed(chart.valueAxis.min);
  final double? fixedMax = _fixed(chart.valueAxis.max);
  final double lo = fixedMin ?? low;
  final double hi = fixedMax ?? high;
  final bool degenerate = !(hi > lo);
  double y(double v) {
    if (degenerate) {
      return fixedMin != null
          ? plot.bottom
          : fixedMax != null
          ? plot.top
          : plot.top + plot.height / 2;
    }
    final double t = ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
    return plot.bottom - t * plot.height;
  }

  final double base = !degenerate && lo < 0 && hi > 0 ? y(0) : plot.bottom;
  final List<ChartPrimitive> areas = <ChartPrimitive>[];
  final List<ChartPrimitive> lines = <ChartPrimitive>[];
  for (int s = 0; s < resolved.values.length; s++) {
    final ChartColor color = resolved.colors[s];
    final bool area = chart.series[s].kind == ChartKind.area;
    final bool smooth = chart.series[s].smooth;
    int run = 0;
    final List<ChartPoint> points = <ChartPoint>[];
    int first = 0;
    void flush() {
      if (points.length > 1) {
        final List<ChartPoint> path = smooth
            ? <ChartPoint>[
                for (final ChartPoint p in smoothPolyline(points))
                  ChartPoint(p.x, p.y.clamp(plot.top, plot.bottom)),
              ]
            : List<ChartPoint>.of(points);
        if (area) {
          areas.add(
            PathPrimitive(
              ids.seriesAreaId(s),
              <ChartPoint>[
                ...path,
                ChartPoint(path.last.x, base),
                ChartPoint(path.first.x, base),
              ],
              closed: true,
              fill: color,
              fillOpacity: theme.areaOpacity,
            ),
          );
        }
        lines.add(
          PathPrimitive(
            ids.seriesLineId(s, run++),
            path,
            stroke: color,
            strokeWidth: theme.sparklineWidth,
          ),
        );
      } else if (points.length == 1) {
        final ChartPoint p = points.single;
        final double r = theme.sparklineWidth;
        lines.add(
          PathPrimitive(
            ids.seriesMarkerId(s, first),
            <ChartPoint>[
              ChartPoint(p.x - r, p.y - r),
              ChartPoint(p.x + r, p.y - r),
              ChartPoint(p.x + r, p.y + r),
              ChartPoint(p.x - r, p.y + r),
            ],
            closed: true,
            fill: color,
          ),
        );
      }
      points.clear();
    }

    final List<double?> values = resolved.values[s];
    for (int i = 0; i < values.length; i++) {
      final double? v = values[i];
      if (v == null) {
        flush();
        continue;
      }
      if (points.isEmpty) {
        first = i;
      }
      points.add(ChartPoint(x(i), y(v)));
    }
    flush();
  }
  primitives
    ..addAll(areas)
    ..addAll(lines);
  return (primitives: primitives, plot: plot, categoryBands: bands);
}

double? _fixed(double? value) => value != null && value.isFinite ? value : null;
