/// The series marks: columns and bars, lines and areas.
///
/// A category's band is the plot's length along the category axis over the
/// category count. Columns, bars and lines sit in the middle of their bands;
/// an area's points sit on tick marks (`categoryPosition`), from the plot's
/// one edge to the other, as Excel draws one. Every coordinate is finite: a
/// value outside the axis range is mapped no further than one plot length
/// beyond the plot's edge, where the plot's clip cuts it off.
///
/// The series are drawn in groups (`markGroups`): the series of one drawn
/// kind on one value axis. A column, bar, line or area chart has one group
/// per axis; a combination chart one per kind and axis.
library;

import 'dart:math' as math;

import '../model/chart.dart';
import '../model/chart_kind.dart';
import '../scale/value_scale.dart';
import '../theme/chart_color.dart';
import '../theme/chart_theme.dart';
import 'axis_layout.dart';
import 'chart_ids.dart' as ids;
import 'curve.dart';
import 'geometry.dart';
import 'primitives.dart';
import 'resolve.dart';
import 'scatter_layout.dart';

/// The marks of [chart] on [plot], in paint order.
///
/// Column and bar charts draw rectangles, line charts one path per run of
/// values and then, per series, a circle marker on every point (on a point
/// with no neighbour only, when the theme's `lineMarkers` is off or the
/// markers do not fit: [lineMarkersFit]), area charts
/// one closed path per series (with the theme's `areaOpacity`) and, when the
/// theme's `areaLine` is on, an open path along each area's top, after all the
/// areas of its group. A series with `smooth` set draws its line runs, or its
/// area's top and edge line, as curves (`smoothPolyline`; an area's curve is
/// screen only, as Excel's area has no `c:smooth`), and a stacked area sits
/// on the top of the one below it, curved or not. A scatter chart, given the
/// horizontal axis [scatterAxis], draws a marker per point (`scatterMarks`).
/// Any other kind draws none. The frame puts the markers in a clip of their
/// own, after the others, which go in the plot's clip.
///
/// The groups of `markGroups` are drawn in their order: areas, then columns
/// or bars, then lines, the primary axis' group of a kind before the
/// secondary axis' one. A secondary group is measured on
/// [secondaryScale] (on [scale] when that is `null`). In a combination chart
/// each group is drawn as a chart of its own kind of only its series would
/// be, on the category positions of [categoriesOnTicks].
List<ChartPrimitive> layoutMarks(
  Chart chart,
  ResolvedChart resolved,
  ChartTheme theme,
  ChartRect plot,
  ValueScale scale, {
  ScatterAxis? scatterAxis,
  ValueScale? secondaryScale,
}) {
  if (chart.kind == ChartKind.scatter) {
    return scatterAxis == null
        ? const <ChartPrimitive>[]
        : scatterMarks(resolved, theme, plot, scale, scatterAxis);
  }
  final List<List<double?>> values = resolved.shaped;
  final bool onTicks = categoriesOnTicks(chart, resolved);
  final List<ChartPrimitive> out = <ChartPrimitive>[];
  for (final MarkGroup group in resolved.groups) {
    final MarkAxes axes = MarkAxes(
      plot,
      group.secondary ? secondaryScale ?? scale : scale,
      horizontal: chart.kind == ChartKind.bar,
      onTicks: onTicks,
    );
    switch (group.kind) {
      case ChartKind.column:
      case ChartKind.bar:
        out.addAll(_bars(group, resolved, values, theme, axes));
      case ChartKind.line:
        out.addAll(_lines(group, chart, resolved, values, theme, axes));
      case ChartKind.area:
        out.addAll(_areas(group, chart, resolved, values, theme, axes));
      default:
        break;
    }
  }
  return out;
}

/// Whether [chart]'s categories sit on tick marks (`categoryPosition`): an
/// area chart, as Excel draws one (`c:crossBetween midCat`), and a
/// combination chart with an area series and no column series. With a
/// column series the categories sit between tick marks, and the areas and
/// lines go through the middle of the bands; a combination of lines alone
/// sits between them too, as a line chart does.
bool categoriesOnTicks(Chart chart, ResolvedChart resolved) {
  if (chart.kind == ChartKind.area) {
    return true;
  }
  if (chart.kind != ChartKind.combination) {
    return false;
  }
  return !resolved.seriesKinds.contains(ChartKind.column) &&
      resolved.seriesKinds.contains(ChartKind.area);
}

/// The value axis and the category bands a chart's marks are placed on.
final class MarkAxes {
  /// Creates the axes of [plot] with [scale]; [horizontal] is a value axis
  /// that runs left to right (a bar chart), and [onTicks] puts the
  /// categories of lines and areas on tick marks (`categoryPosition`).
  MarkAxes(
    this.plot,
    this.scale, {
    required this.horizontal,
    this.onTicks = false,
  });

  /// The plot area.
  final ChartRect plot;

  /// The value axis' scale.
  final ValueScale scale;

  /// Whether the value axis is horizontal.
  final bool horizontal;

  /// Whether the points of lines and areas sit on tick marks.
  final bool onTicks;

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

/// [value] percent as a fraction, kept between [low] and [high] percent; a
/// value that is not a number counts as [low].
double _percent(double value, double low, double high) =>
    (value.isNaN ? low : value.clamp(low, high)) / 100;

List<ChartPrimitive> _bars(
  MarkGroup group,
  ResolvedChart resolved,
  List<List<double?>> values,
  ChartTheme theme,
  MarkAxes axes,
) {
  return <ChartPrimitive>[
    for (final MarkAnchor a in _barAnchors(
      group,
      resolved,
      values,
      theme,
      axes,
    ))
      RectPrimitive(
        ids.seriesBarId(a.series, a.category),
        a.bar!,
        fill: resolved.colorAt(a.series, a.category),
      ),
  ];
}

/// The rectangle of every bar of [group] that has a value, in series then
/// category order. The group's series share each category's slot as a chart
/// of them alone would.
List<MarkAnchor> _barAnchors(
  MarkGroup group,
  ResolvedChart resolved,
  List<List<double?>> values,
  ChartTheme theme,
  MarkAxes axes,
) {
  final int n = group.members.length;
  final bool stacked = group.stacked;
  // Excel's ranges: gap 0 to 500, overlap -100 to 100. Kept to them, the
  // width's denominator is at least 1 (one series, no gap) and never 0.
  // A bar chart's value axis runs left to right; the theme gives each kind
  // and grouping its gap and overlap (Excel's defaults differ by both).
  final ChartKind kind = axes.horizontal ? ChartKind.bar : ChartKind.column;
  final double g = _percent(
    theme.gapWidthPercentOf(kind, group.grouping),
    0,
    500,
  );
  final double o = stacked
      ? 1
      : _percent(theme.overlapPercentOf(kind, group.grouping), -100, 100);
  final double band = axes.categoryLength / math.max(1, resolved.categoryCount);
  final double w = band / (g + n - (n - 1) * o);
  final List<MarkAnchor> out = <MarkAnchor>[];
  final List<double> up = List<double>.filled(resolved.categoryCount, 0);
  final List<double> down = List<double>.filled(resolved.categoryCount, 0);
  for (int k = 0; k < n; k++) {
    final int s = group.members[k];
    for (int c = 0; c < values[s].length; c++) {
      final double? v = values[s][c];
      if (v == null) {
        continue;
      }
      final double along =
          c * band + g * w / 2 + (stacked ? 0 : k * w * (1 - o));
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

/// The values of [group]'s lines or areas, one list per member, stacked when
/// the group is: each is the running sum over the group's series so far, a
/// `null` adding 0.
List<List<double?>> _cumulative(
  MarkGroup group,
  ResolvedChart resolved,
  List<List<double?>> values, {
  required bool nullIsZero,
}) {
  if (!group.stacked) {
    return <List<double?>>[
      for (final int s in group.members)
        <double?>[
          for (final double? x in values[s]) x ?? (nullIsZero ? 0 : null),
        ],
    ];
  }
  final List<double> sum = List<double>.filled(resolved.categoryCount, 0);
  return <List<double?>>[
    for (final int s in group.members)
      <double?>[
        for (int c = 0; c < values[s].length; c++)
          () {
            sum[c] += values[s][c] ?? 0;
            return values[s][c] == null && !nullIsZero ? null : sum[c];
          }(),
      ],
  ];
}

/// The point of every line value of [group], one list per member, per
/// category (`null` for a gap).
List<List<ChartPoint?>> _linePoints(
  MarkGroup group,
  ResolvedChart resolved,
  List<List<double?>> values,
  MarkAxes axes,
) {
  final List<List<double?>> tops = _cumulative(
    group,
    resolved,
    values,
    nullIsZero: false,
  );
  double along(int c) => categoryPosition(
    c,
    resolved.categoryCount,
    axes.categoryLength,
    onTicks: axes.onTicks,
  );
  return <List<ChartPoint?>>[
    for (final List<double?> series in tops)
      <ChartPoint?>[
        for (int c = 0; c < series.length; c++)
          series[c] == null ? null : axes.point(along(c), series[c]!),
      ],
  ];
}

List<ChartPrimitive> _lines(
  MarkGroup group,
  Chart chart,
  ResolvedChart resolved,
  List<List<double?>> values,
  ChartTheme theme,
  MarkAxes axes,
) {
  final List<List<ChartPoint?>> tops = _linePoints(
    group,
    resolved,
    values,
    axes,
  );
  final bool everyPoint =
      theme.lineMarkers &&
      lineMarkersFit(axes.categoryLength, resolved.categoryCount, theme);
  final List<ChartPrimitive> out = <ChartPrimitive>[];
  for (int k = 0; k < tops.length; k++) {
    final int s = group.members[k];
    final ChartColor color = resolved.colors[s];
    final bool smooth = chart.series[s].smooth;
    int run = 0;
    final List<ChartPoint> points = <ChartPoint>[];
    // The categories that get a marker, drawn after the series' runs.
    final List<int> marked = <int>[];
    int first = 0;
    void flush() {
      if (points.length > 1) {
        out.add(
          PathPrimitive(
            ids.seriesLineId(s, run++),
            smooth ? smoothPolyline(points) : points,
            stroke: color,
            strokeWidth: theme.lineWidth,
          ),
        );
      } else if (points.length == 1 && !everyPoint) {
        marked.add(first);
      }
      points.clear();
    }

    for (int c = 0; c < tops[k].length; c++) {
      final ChartPoint? p = tops[k][c];
      if (p == null) {
        flush();
        continue;
      }
      if (points.isEmpty) {
        first = c;
      }
      points.add(p);
      if (everyPoint) {
        marked.add(c);
      }
    }
    flush();
    // A point with a point colour keeps its marker, in that colour, even
    // when the line marks no other point: the DrawingML writer writes a
    // marker there too, so the screen shows what the file does.
    final Set<int> drawn = marked.toSet();
    for (int c = 0; c < tops[k].length; c++) {
      if (tops[k][c] != null &&
          resolved.pointColorAt(s, c) != null &&
          drawn.add(c)) {
        marked.add(c);
      }
    }
    marked.sort();
    for (final int c in marked) {
      out.add(
        lineMarker(
          ids.seriesMarkerId(s, c),
          tops[k][c]!,
          resolved.colorAt(s, c),
          theme,
        ),
      );
    }
  }
  return out;
}

/// Whether a line's markers fit on every point: when the category step, the
/// distance between neighbouring categories along the category axis
/// ([categoryLength] over [categoryCount]), is at least the theme's
/// `markerSize` plus 2 pt.
///
/// On a denser line the markers would touch and hide the line, and on a
/// large series they cost far more to draw than the line, so only a point
/// with no neighbour keeps its marker, as it would not show otherwise. Excel's
/// behaviour on dense lines was not checked (`docs/parity.md`). The legend
/// keeps its marker either way, and a written chart part says what the theme
/// says.
bool lineMarkersFit(
  double categoryLength,
  int categoryCount,
  ChartTheme theme,
) =>
    categoryCount > 0 && categoryLength / categoryCount >= theme.markerSize + 2;

/// The width of a marker's outline: Excel's 0.75 pt (`chart_defaults.xlsx`).
const double markerOutlineWidth = 0.75;

/// The marker [id] of a line point at [center]: a full circle of the theme's
/// `markerSize`, filled and outlined in [color].
ArcPrimitive lineMarker(
  String id,
  ChartPoint center,
  ChartColor color,
  ChartTheme theme,
) => ArcPrimitive(
  id,
  center,
  theme.markerSize / 2,
  0,
  0,
  360,
  fill: color,
  stroke: color,
  strokeWidth: markerOutlineWidth,
);

/// The top and the base of the area column under every value of [group],
/// one list per member.
///
/// A missing value counts as 0 for the area's outline and has no anchor.
List<List<({ChartPoint top, ChartPoint base})>> _areaColumns(
  MarkGroup group,
  ResolvedChart resolved,
  List<List<double?>> values,
  MarkAxes axes,
) {
  final List<List<double?>> tops = _cumulative(
    group,
    resolved,
    values,
    nullIsZero: true,
  );
  double along(int c) => categoryPosition(
    c,
    resolved.categoryCount,
    axes.categoryLength,
    onTicks: axes.onTicks,
  );
  final bool stacked = group.stacked;
  return <List<({ChartPoint top, ChartPoint base})>>[
    for (int k = 0; k < tops.length; k++)
      <({ChartPoint top, ChartPoint base})>[
        for (int c = 0; c < tops[k].length; c++)
          (
            top: axes.point(along(c), tops[k][c]!),
            base: axes.point(
              along(c),
              stacked && k > 0 ? tops[k - 1][c]! : axes.crossing,
            ),
          ),
      ],
  ];
}

List<ChartPrimitive> _areas(
  MarkGroup group,
  Chart chart,
  ResolvedChart resolved,
  List<List<double?>> values,
  ChartTheme theme,
  MarkAxes axes,
) {
  final List<List<({ChartPoint top, ChartPoint base})>> columns = _areaColumns(
    group,
    resolved,
    values,
    axes,
  );
  // The top of each area: a smooth series' is its curve. A stacked area
  // sits on the top of the one below it, curve or not, so the two share
  // their edge.
  final List<List<ChartPoint>> tops = <List<ChartPoint>>[
    for (int k = 0; k < columns.length; k++)
      _areaTop(<ChartPoint>[
        for (final column in columns[k]) column.top,
      ], smooth: chart.series[group.members[k]].smooth),
  ];
  final List<ChartPrimitive> out = <ChartPrimitive>[];
  for (int k = 0; k < columns.length; k++) {
    if (columns[k].isEmpty) {
      continue;
    }
    final int s = group.members[k];
    out.add(
      PathPrimitive(
        ids.seriesAreaId(s),
        <ChartPoint>[
          ...tops[k],
          if (group.stacked && k > 0)
            ...tops[k - 1].reversed
          else
            for (final column in columns[k].reversed) column.base,
        ],
        closed: true,
        fill: resolved.colors[s],
        fillOpacity: theme.areaOpacity,
      ),
    );
  }
  if (theme.areaLine) {
    // The edge line follows each area's top, over all the group's fills.
    for (int k = 0; k < columns.length; k++) {
      if (columns[k].length > 1) {
        final int s = group.members[k];
        out.add(
          PathPrimitive(
            ids.seriesLineId(s, 0),
            tops[k],
            stroke: resolved.colors[s],
            strokeWidth: theme.lineWidth,
          ),
        );
      }
    }
  }
  return out;
}

/// The top edge of an area through [points]: their curve when [smooth]
/// (`smoothPolyline`), else the points themselves.
List<ChartPoint> _areaTop(List<ChartPoint> points, {required bool smooth}) =>
    smooth ? smoothPolyline(points) : points;

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

/// The anchors of every value that has a mark, by group (`markGroups`),
/// each in series then category order.
///
/// They are the geometry [layoutMarks] draws, with the same [scatterAxis]
/// and [secondaryScale], so a label sits where its mark is. Kinds without
/// marks have none.
List<MarkAnchor> layoutAnchors(
  Chart chart,
  ResolvedChart resolved,
  ChartTheme theme,
  ChartRect plot,
  ValueScale scale, {
  ScatterAxis? scatterAxis,
  ValueScale? secondaryScale,
}) {
  if (chart.kind == ChartKind.scatter) {
    return scatterAxis == null
        ? const <MarkAnchor>[]
        : scatterAnchors(chart, resolved, plot, scale, scatterAxis);
  }
  final List<List<double?>> values = resolved.shaped;
  final bool onTicks = categoriesOnTicks(chart, resolved);
  final List<MarkAnchor> out = <MarkAnchor>[];
  for (final MarkGroup group in resolved.groups) {
    final MarkAxes axes = MarkAxes(
      plot,
      group.secondary ? secondaryScale ?? scale : scale,
      horizontal: chart.kind == ChartKind.bar,
      onTicks: onTicks,
    );
    switch (group.kind) {
      case ChartKind.column:
      case ChartKind.bar:
        out.addAll(_barAnchors(group, resolved, values, theme, axes));
      case ChartKind.line:
        final List<List<ChartPoint?>> points = _linePoints(
          group,
          resolved,
          values,
          axes,
        );
        for (int k = 0; k < points.length; k++) {
          for (int c = 0; c < points[k].length; c++) {
            if (points[k][c] != null) {
              out.add(MarkAnchor(group.members[k], c, point: points[k][c]));
            }
          }
        }
      case ChartKind.area:
        final List<List<({ChartPoint top, ChartPoint base})>> columns =
            _areaColumns(group, resolved, values, axes);
        for (int k = 0; k < columns.length; k++) {
          final int s = group.members[k];
          for (int c = 0; c < columns[k].length; c++) {
            if (values[s][c] != null) {
              out.add(
                MarkAnchor(
                  s,
                  c,
                  point: columns[k][c].top,
                  base: columns[k][c].base,
                ),
              );
            }
          }
        }
      default:
        break;
    }
  }
  return out;
}
