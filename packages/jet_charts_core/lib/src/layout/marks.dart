/// The series marks: columns and bars, lines and areas.
///
/// A category's band is the plot's length along the category axis over the
/// category count. Every coordinate is finite: a value outside the axis range
/// is mapped no further than one plot length beyond the plot's edge, where the
/// plot's clip cuts it off.
library;

import 'dart:math' as math;

import '../model/chart.dart';
import '../model/chart_kind.dart';
import '../scale/value_scale.dart';
import '../theme/chart_theme.dart';
import 'axis_layout.dart';
import 'chart_ids.dart' as ids;
import 'geometry.dart';
import 'primitives.dart';
import 'resolve.dart';

/// The marks of [chart] on [plot], in paint order, for the clip of the plot.
///
/// Column and bar charts draw rectangles, line charts one path per run of
/// values, area charts one closed path per series. Any other kind draws none.
List<ChartPrimitive> layoutMarks(
  Chart chart,
  ResolvedChart resolved,
  ChartTheme theme,
  ChartRect plot,
  ValueScale scale,
) {
  final MarkAxes axes = MarkAxes(
    plot,
    scale,
    horizontal: chart.kind == ChartKind.bar,
  );
  final List<List<double?>> values = shapedValues(resolved);
  switch (chart.kind) {
    case ChartKind.column:
    case ChartKind.bar:
      return _bars(resolved, values, theme, axes);
    case ChartKind.line:
      return _lines(resolved, values, theme, axes);
    case ChartKind.area:
      return _areas(resolved, values, axes);
    default:
      return const <ChartPrimitive>[];
  }
}

/// The value axis and the category bands a chart's marks are placed on.
final class MarkAxes {
  /// Creates the axes of [plot] with [scale]; [horizontal] is a value axis
  /// that runs left to right (a bar chart).
  MarkAxes(this.plot, this.scale, {required this.horizontal});

  /// The plot area.
  final ChartRect plot;

  /// The value axis' scale.
  final ValueScale scale;

  /// Whether the value axis is horizontal.
  final bool horizontal;

  /// The value the category axis crosses at.
  double get crossing => crossingValue(scale);

  /// The plot's length along the category axis.
  double get categoryLength => horizontal ? plot.height : plot.width;

  /// The position of [value] on the value axis, kept within one plot length
  /// of the plot's edges.
  double position(double value) {
    final double span = scale.max - scale.min;
    double t = span > 0 && span.isFinite ? (value - scale.min) / span : 0.0;
    if (t.isNaN) {
      t = 0;
    }
    t = t.clamp(-1.0, 2.0);
    return horizontal
        ? plot.left + t * plot.width
        : plot.bottom - t * plot.height;
  }

  /// The point at [along] the category axis from its start (the left, or the
  /// bottom of a bar chart) and [value] on the value axis.
  ChartPoint point(double along, double value) {
    final double v = position(value);
    return horizontal
        ? ChartPoint(v, plot.bottom - along)
        : ChartPoint(plot.left + along, v);
  }

  /// The rectangle from value [from] to value [to], [width] thick from
  /// [along] on the category axis.
  ChartRect rect(double along, double width, double from, double to) {
    final double a = position(from);
    final double b = position(to);
    final double low = math.min(a, b);
    final double length = (a - b).abs();
    return horizontal
        ? ChartRect(low, plot.bottom - along - width, length, width)
        : ChartRect(plot.left + along, low, width, length);
  }
}

/// The values the marks use: the resolved ones, or on a percent stacked chart
/// each as its share of the category's absolute sum (a category of sum 0 has
/// no value). Tooltips read the share from here too.
List<List<double?>> shapedValues(ResolvedChart resolved) {
  if (!resolved.percent) {
    return resolved.values;
  }
  final List<double> sums = <double>[
    for (int c = 0; c < resolved.categoryCount; c++)
      resolved.values.fold<double>(
        0,
        (double sum, List<double?> v) => sum + (v[c] ?? 0).abs(),
      ),
  ];
  return <List<double?>>[
    for (final List<double?> series in resolved.values)
      <double?>[
        for (int c = 0; c < series.length; c++)
          series[c] == null || !(sums[c] > 0) ? null : series[c]! / sums[c],
      ],
  ];
}

/// [value] percent as a fraction, kept between [low] and [high] percent; a
/// value that is not a number counts as [low].
double _percent(double value, double low, double high) =>
    (value.isNaN ? low : value.clamp(low, high)) / 100;

bool _stacked(ResolvedChart r) => r.grouping != ChartGrouping.clustered;

List<ChartPrimitive> _bars(
  ResolvedChart resolved,
  List<List<double?>> values,
  ChartTheme theme,
  MarkAxes axes,
) {
  return <ChartPrimitive>[
    for (final MarkAnchor a in _barAnchors(resolved, values, theme, axes))
      RectPrimitive(
        ids.seriesBarId(a.series, a.category),
        a.bar!,
        fill: resolved.colors[a.series],
      ),
  ];
}

/// The rectangle of every bar that has a value, in series then category order.
List<MarkAnchor> _barAnchors(
  ResolvedChart resolved,
  List<List<double?>> values,
  ChartTheme theme,
  MarkAxes axes,
) {
  final int n = values.length;
  final bool stacked = _stacked(resolved);
  // Excel's ranges: gap 0 to 500, overlap -100 to 100. Kept to them, the
  // width's denominator is at least 1 (one series, no gap) and never 0.
  final double g = _percent(theme.gapWidthPercent, 0, 500);
  final double o = stacked
      ? 1
      : _percent(theme.spacing.overlapPercent, -100, 100);
  final double band = axes.categoryLength / math.max(1, resolved.categoryCount);
  final double w = band / (g + n - (n - 1) * o);
  final List<MarkAnchor> out = <MarkAnchor>[];
  final List<double> up = List<double>.filled(resolved.categoryCount, 0);
  final List<double> down = List<double>.filled(resolved.categoryCount, 0);
  for (int s = 0; s < n; s++) {
    for (int c = 0; c < values[s].length; c++) {
      final double? v = values[s][c];
      if (v == null) {
        continue;
      }
      final double along =
          c * band + g * w / 2 + (stacked ? 0 : s * w * (1 - o));
      double from = axes.crossing;
      double to = v;
      if (stacked) {
        if (v >= 0) {
          from = up[c];
          to = up[c] += v;
        } else {
          from = down[c];
          to = down[c] += v;
        }
      }
      out.add(MarkAnchor(s, c, bar: axes.rect(along, w, from, to)));
    }
  }
  return out;
}

/// The values of a line or an area, stacked when the chart is: each is the
/// running sum over the series so far, a `null` adding 0.
List<List<double?>> _cumulative(
  ResolvedChart resolved,
  List<List<double?>> values, {
  required bool nullIsZero,
}) {
  if (!_stacked(resolved)) {
    return <List<double?>>[
      for (final List<double?> v in values)
        <double?>[for (final double? x in v) x ?? (nullIsZero ? 0 : null)],
    ];
  }
  final List<double> sum = List<double>.filled(resolved.categoryCount, 0);
  return <List<double?>>[
    for (final List<double?> v in values)
      <double?>[
        for (int c = 0; c < v.length; c++)
          () {
            sum[c] += v[c] ?? 0;
            return v[c] == null && !nullIsZero ? null : sum[c];
          }(),
      ],
  ];
}

/// The point of every line value, per series and category (`null` for a gap).
List<List<ChartPoint?>> _linePoints(
  ResolvedChart resolved,
  List<List<double?>> values,
  MarkAxes axes,
) {
  final List<List<double?>> tops = _cumulative(
    resolved,
    values,
    nullIsZero: false,
  );
  final double band = axes.categoryLength / math.max(1, resolved.categoryCount);
  return <List<ChartPoint?>>[
    for (final List<double?> series in tops)
      <ChartPoint?>[
        for (int c = 0; c < series.length; c++)
          series[c] == null ? null : axes.point((c + 0.5) * band, series[c]!),
      ],
  ];
}

List<ChartPrimitive> _lines(
  ResolvedChart resolved,
  List<List<double?>> values,
  ChartTheme theme,
  MarkAxes axes,
) {
  final List<List<ChartPoint?>> tops = _linePoints(resolved, values, axes);
  final double h = theme.markerSize / 2;
  final List<ChartPrimitive> out = <ChartPrimitive>[];
  for (int s = 0; s < tops.length; s++) {
    int run = 0;
    final List<ChartPoint> points = <ChartPoint>[];
    int first = 0;
    void flush() {
      if (points.length > 1) {
        out.add(
          PathPrimitive(
            ids.seriesLineId(s, run++),
            points,
            stroke: resolved.colors[s],
            strokeWidth: theme.lineWidth,
          ),
        );
      } else if (points.length == 1) {
        final ChartPoint p = points.first;
        out.add(
          PathPrimitive(
            ids.seriesMarkerId(s, first),
            <ChartPoint>[
              ChartPoint(p.x - h, p.y - h),
              ChartPoint(p.x + h, p.y - h),
              ChartPoint(p.x + h, p.y + h),
              ChartPoint(p.x - h, p.y + h),
            ],
            closed: true,
            fill: resolved.colors[s],
          ),
        );
      }
      points.clear();
    }

    for (int c = 0; c < tops[s].length; c++) {
      final ChartPoint? p = tops[s][c];
      if (p == null) {
        flush();
        continue;
      }
      if (points.isEmpty) {
        first = c;
      }
      points.add(p);
    }
    flush();
  }
  return out;
}

/// The top and the base of the area column under every value, per series.
///
/// A missing value counts as 0 for the area's outline and has no anchor.
List<List<({ChartPoint top, ChartPoint base})>> _areaColumns(
  ResolvedChart resolved,
  List<List<double?>> values,
  MarkAxes axes,
) {
  final List<List<double?>> tops = _cumulative(
    resolved,
    values,
    nullIsZero: true,
  );
  final double band = axes.categoryLength / math.max(1, resolved.categoryCount);
  final bool stacked = _stacked(resolved);
  return <List<({ChartPoint top, ChartPoint base})>>[
    for (int s = 0; s < tops.length; s++)
      <({ChartPoint top, ChartPoint base})>[
        for (int c = 0; c < tops[s].length; c++)
          (
            top: axes.point((c + 0.5) * band, tops[s][c]!),
            base: axes.point(
              (c + 0.5) * band,
              stacked && s > 0 ? tops[s - 1][c]! : axes.crossing,
            ),
          ),
      ],
  ];
}

List<ChartPrimitive> _areas(
  ResolvedChart resolved,
  List<List<double?>> values,
  MarkAxes axes,
) {
  final List<List<({ChartPoint top, ChartPoint base})>> columns = _areaColumns(
    resolved,
    values,
    axes,
  );
  final List<ChartPrimitive> out = <ChartPrimitive>[];
  for (int s = 0; s < columns.length; s++) {
    if (columns[s].isEmpty) {
      continue;
    }
    out.add(
      PathPrimitive(
        ids.seriesAreaId(s),
        <ChartPoint>[
          for (final column in columns[s]) column.top,
          for (final column in columns[s].reversed) column.base,
        ],
        closed: true,
        fill: resolved.colors[s],
      ),
    );
  }
  return out;
}

/// Where a value's mark is, for the data label that goes with it.
final class MarkAnchor {
  /// Creates the anchor of series [series] at [category]; a bar has [bar], a
  /// line or area value has [point] and an area also its [base].
  const MarkAnchor(
    this.series,
    this.category, {
    this.bar,
    this.point,
    this.base,
  });

  /// The series' index.
  final int series;

  /// The category's index.
  final int category;

  /// The bar's rectangle, when the mark is a bar.
  final ChartRect? bar;

  /// The value's point, when the mark is a line or an area.
  final ChartPoint? point;

  /// The point on the area's base below [point], for an area.
  final ChartPoint? base;
}

/// The anchors of every value that has a mark, in series then category order.
///
/// They are the geometry [layoutMarks] draws, so a label sits where its mark
/// is. Kinds without marks have none.
List<MarkAnchor> layoutAnchors(
  Chart chart,
  ResolvedChart resolved,
  ChartTheme theme,
  ChartRect plot,
  ValueScale scale,
) {
  final MarkAxes axes = MarkAxes(
    plot,
    scale,
    horizontal: chart.kind == ChartKind.bar,
  );
  final List<List<double?>> values = shapedValues(resolved);
  switch (chart.kind) {
    case ChartKind.column:
    case ChartKind.bar:
      return _barAnchors(resolved, values, theme, axes);
    case ChartKind.line:
      final List<List<ChartPoint?>> points = _linePoints(
        resolved,
        values,
        axes,
      );
      return <MarkAnchor>[
        for (int s = 0; s < points.length; s++)
          for (int c = 0; c < points[s].length; c++)
            if (points[s][c] != null) MarkAnchor(s, c, point: points[s][c]),
      ];
    case ChartKind.area:
      final List<List<({ChartPoint top, ChartPoint base})>> columns =
          _areaColumns(resolved, values, axes);
      return <MarkAnchor>[
        for (int s = 0; s < columns.length; s++)
          for (int c = 0; c < columns[s].length; c++)
            if (values[s][c] != null)
              MarkAnchor(
                s,
                c,
                point: columns[s][c].top,
                base: columns[s][c].base,
              ),
      ];
    default:
      return const <MarkAnchor>[];
  }
}
