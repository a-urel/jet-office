/// The points of a `JetChart` a keyboard walks, the screen reader node of
/// each point, and the focus ring drawn around the focused one.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_core/jet_core.dart';

import 'strings.dart';

/// A point of a chart that the keyboard walks: a primitive (a bar, a marker
/// or a slice) or, in a sparkline, a category band.
final class ChartKeyPoint {
  /// Creates the point [key] with its [bounds], the primitive [id] or the
  /// [band] it stands for.
  const ChartKeyPoint({
    required this.key,
    required this.bounds,
    this.id,
    this.band,
  });

  /// What names the point across layouts: the primitive's id, or
  /// `band/<i>` for a sparkline's band `i`.
  final String key;

  /// Where it is on the chart, in the chart's own coordinates.
  final Rect bounds;

  /// The primitive's id, or `null` for a band.
  final String? id;

  /// The band's category, or `null` for a primitive.
  final int? band;

  @override
  bool operator ==(Object other) =>
      other is ChartKeyPoint &&
      key == other.key &&
      bounds == other.bounds &&
      id == other.id &&
      band == other.band;

  @override
  int get hashCode => Object.hash(key, bounds, id, band);
}

/// A screen reader node of one point: its `rect` and `label`.
typedef ChartPointNode = ({Rect rect, String label});

Rect _rect(ChartRect r) => Rect.fromLTWH(r.left, r.top, r.width, r.height);

/// Every primitive of [primitives], each clip's children after it.
Iterable<ChartPrimitive> _flat(List<ChartPrimitive> primitives) sync* {
  for (final ChartPrimitive p in primitives) {
    yield p;
    if (p is ClipPrimitive) {
      yield* _flat(p.children);
    }
  }
}

/// The axis-aligned box that holds [primitive]'s shape (its stroke not
/// counted).
Rect primitiveBounds(ChartPrimitive primitive) {
  switch (primitive) {
    case RectPrimitive(:final ChartRect rect):
    case ClipPrimitive(:final ChartRect rect):
      return _rect(rect);
    case TextPrimitive():
      return _rect(primitive.bounds);
    case PathPrimitive(:final List<ChartPoint> points):
      if (points.isEmpty) {
        return Rect.zero;
      }
      double left = points.first.x;
      double right = left;
      double top = points.first.y;
      double bottom = top;
      for (final ChartPoint p in points) {
        left = math.min(left, p.x);
        right = math.max(right, p.x);
        top = math.min(top, p.y);
        bottom = math.max(bottom, p.y);
      }
      return Rect.fromLTRB(left, top, right, bottom);
    case ArcPrimitive():
      return _arcBounds(primitive);
  }
}

/// The box of [arc]: its ends on both radii and every quarter turn its
/// sweep passes.
Rect _arcBounds(ArcPrimitive arc) {
  final double start = math.min(arc.startAngle, arc.startAngle + arc.sweep);
  final double end = math.max(arc.startAngle, arc.startAngle + arc.sweep);
  final List<double> angles = <double>[start, end];
  for (double a = (start / 90).ceilToDouble() * 90; a < end; a += 90) {
    angles.add(a);
  }
  double left = double.infinity;
  double right = double.negativeInfinity;
  double top = double.infinity;
  double bottom = double.negativeInfinity;
  for (final double a in angles) {
    final double rad = a * math.pi / 180;
    for (final double r in <double>[arc.innerRadius, arc.radius]) {
      final double x = arc.center.x + r * math.cos(rad);
      final double y = arc.center.y + r * math.sin(rad);
      left = math.min(left, x);
      right = math.max(right, x);
      top = math.min(top, y);
      bottom = math.max(bottom, y);
    }
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

extension on ArcPrimitive {
  /// The sweep, 360 at most either way.
  double get sweep => sweepAngle.clamp(-360, 360).toDouble();
}

/// The category bands of [layout] as points, in category order.
List<ChartKeyPoint> _bandPoints(ChartLayout layout) => <ChartKeyPoint>[
  for (int i = 0; i < layout.categoryBands.length; i++)
    ChartKeyPoint(
      key: 'band/$i',
      bounds: _rect(layout.categoryBands[i]),
      band: i,
    ),
];

/// The primitives of [layout] whose id is of [kind] (and of series 0 when
/// [firstSeries]), series-major: series 0's by category, then series 1's.
List<ChartKeyPoint> _primitivePoints(
  ChartLayout layout,
  ChartElementKind kind, {
  bool firstSeries = false,
}) {
  final List<(int, int, ChartKeyPoint)> found = <(int, int, ChartKeyPoint)>[];
  final Set<String> seen = <String>{};
  for (final ChartPrimitive p in _flat(layout.primitives)) {
    final ChartElementId? element = ChartElementId.parse(p.id);
    if (element == null ||
        element.kind != kind ||
        (firstSeries && element.series != 0) ||
        !seen.add(p.id)) {
      continue;
    }
    found.add((
      element.series!,
      element.category!,
      ChartKeyPoint(key: p.id, bounds: primitiveBounds(p), id: p.id),
    ));
  }
  found.sort(
    ((int, int, ChartKeyPoint) a, (int, int, ChartKeyPoint) b) =>
        a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
  );
  return <ChartKeyPoint>[for (final (int, int, ChartKeyPoint) f in found) f.$3];
}

/// The points of [layout], the layout of [chart], in the order the keyboard
/// walks them: see "Keyboard" on `JetChart`.
///
/// A column or bar chart walks its bars, series-major (series 0's by
/// category, then series 1's); a pie or donut the slices of its first
/// series; a scatter chart its markers, series-major. A line, area,
/// combination chart or sparkline walks its category bands in category
/// order, whatever markers it draws. Another kind has none.
List<ChartKeyPoint> chartKeyPoints(Chart chart, ChartLayout layout) {
  switch (chart.kind) {
    case ChartKind.column:
    case ChartKind.bar:
      return _primitivePoints(layout, ChartElementKind.bar);
    case ChartKind.pie:
    case ChartKind.donut:
      return _primitivePoints(
        layout,
        ChartElementKind.slice,
        firstSeries: true,
      );
    case ChartKind.scatter:
      return _primitivePoints(layout, ChartElementKind.marker);
    case ChartKind.line:
    case ChartKind.area:
    case ChartKind.combination:
    case ChartKind.sparkline:
      return _bandPoints(layout);
    default:
      return const <ChartKeyPoint>[];
  }
}

/// The tooltip of category [category] of [layout]: every series at it.
ChartTooltip? _categoryTooltip(
  Chart chart,
  ChartLayout layout,
  int category, {
  required ChartTheme theme,
  required FormatLocale locale,
}) {
  if (chart.kind == ChartKind.sparkline) {
    // A sparkline has no category axis: its background gives the band's
    // tooltip at a point inside the band.
    final ChartRect band = layout.categoryBands[category];
    return chartTooltipAt(
      chart,
      layout,
      ChartPoint(band.left + band.width / 2, band.top + band.height / 2),
      theme: theme,
      locale: locale,
      hits: <ChartPrimitive>[
        layout.primitives.firstWhere(
          (ChartPrimitive p) => p.id == 'background',
          orElse: () => layout.primitives.first,
        ),
      ],
    );
  }
  return chartTooltipFor(
    chart,
    layout,
    'axis/category/label/$category',
    theme: theme,
    locale: locale,
  );
}

/// The tooltip [point] of [layout] shows: its primitive's
/// (`chartTooltipFor`), or its band's category with every series.
ChartTooltip? keyPointTooltip(
  Chart chart,
  ChartLayout layout,
  ChartKeyPoint point, {
  required ChartTheme theme,
  required FormatLocale locale,
}) {
  final int? band = point.band;
  if (band != null) {
    return _categoryTooltip(chart, layout, band, theme: theme, locale: locale);
  }
  return chartTooltipFor(
    chart,
    layout,
    point.id!,
    theme: theme,
    locale: locale,
  );
}

/// [tooltip] read as one line: `title: label value, label value`.
String tooltipText(ChartTooltip tooltip) {
  final String rows = tooltip.rows
      .map(
        (ChartTooltipRow r) =>
            r.value.isEmpty ? r.label : '${r.label} ${r.value}',
      )
      .join(', ');
  final String? title = tooltip.title;
  if (title == null || title.isEmpty) {
    return rows;
  }
  return rows.isEmpty ? title : '$title: $rows';
}

/// The screen reader nodes of [layout], the layout of [chart]: see "Screen
/// readers" on `JetChart`.
///
/// One per category band in a column, bar, line, area, combination chart or
/// sparkline; one per slice of the first series in a pie or donut; one per
/// marker in a scatter chart; none in another kind. Each is labelled by
/// [tooltipText] of its tooltip; a point with no tooltip has no node. More
/// than [JetChartStrings.maxPointNodes] give none.
List<ChartPointNode> chartPointNodes(
  Chart chart,
  ChartLayout layout, {
  required ChartTheme theme,
  required FormatLocale locale,
}) {
  final List<ChartKeyPoint> points;
  switch (chart.kind) {
    case ChartKind.column:
    case ChartKind.bar:
    case ChartKind.line:
    case ChartKind.area:
    case ChartKind.combination:
    case ChartKind.sparkline:
      points = _bandPoints(layout);
    case ChartKind.pie:
    case ChartKind.donut:
    case ChartKind.scatter:
      points = chartKeyPoints(chart, layout);
    default:
      points = const <ChartKeyPoint>[];
  }
  if (points.length > JetChartStrings.maxPointNodes) {
    return const <ChartPointNode>[];
  }
  return <ChartPointNode>[
    for (final ChartKeyPoint p in points)
      if (keyPointTooltip(chart, layout, p, theme: theme, locale: locale)
          case final ChartTooltip tooltip)
        (rect: p.bounds, label: tooltipText(tooltip)),
  ];
}

/// The screen reader nodes [nodes] placed over the chart, in their order.
List<Widget> pointNodeWidgets(
  List<ChartPointNode> nodes,
  TextDirection direction,
) => <Widget>[
  for (int i = 0; i < nodes.length; i++)
    Positioned.fromRect(
      rect: nodes[i].rect,
      child: Semantics(
        container: true,
        sortKey: OrdinalSortKey(i.toDouble()),
        textDirection: direction,
        label: nodes[i].label,
        child: const SizedBox.expand(),
      ),
    ),
];

/// Paints the keyboard's focus ring: a [strokeWidth] wide outline of
/// [rect] in [color].
final class FocusRingPainter extends CustomPainter {
  /// Creates the painter of a ring along [rect].
  const FocusRingPainter({
    required this.rect,
    required this.color,
    this.strokeWidth = 1.5,
  });

  /// Where the ring is drawn, centred on its stroke.
  final Rect rect;

  /// The ring's colour.
  final Color color;

  /// The ring's width.
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(FocusRingPainter oldDelegate) =>
      rect != oldDelegate.rect ||
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth;
}

/// The ring around [bounds]: grown by the ring's half width and a pixel, so
/// it lies just outside the mark, kept inside [size].
Rect focusRingRect(Rect bounds, Size size) {
  final Rect grown = bounds.inflate(1.5 / 2 + 1);
  final Rect chart = (Offset.zero & size).deflate(1.5 / 2);
  return grown.intersect(chart);
}
