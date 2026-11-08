/// The axes of a cartesian chart: tick labels, category labels, grid lines and
/// axis lines.
///
/// The value axis is vertical at the left of the plot for column, line and
/// area charts and horizontal under it for bar charts; the category axis takes
/// the other side. Tick labels sit outside the plot, `labelGap` from it, and
/// never inside the plot. The category labels' plan and placement
/// ([planCategoryLabels], [placeCategoryLabels]) are the one place Task 7
/// replaces with skip, rotate and truncate.
library;

import 'dart:math' as math;

import '../scale/value_scale.dart';
import '../theme/chart_color.dart';
import '../theme/chart_spacing.dart';
import 'chart_ids.dart' as ids;
import 'geometry.dart';
import 'primitives.dart';
import 'text_measurer.dart';

/// A label's text and its measured size.
final class MeasuredLabel {
  /// Creates a label of [text] that measures [size].
  const MeasuredLabel(this.text, this.size);

  /// The text.
  final String text;

  /// The size the measurer gave.
  final ChartSize size;

  @override
  bool operator ==(Object other) =>
      other is MeasuredLabel && text == other.text && size == other.size;

  @override
  int get hashCode => Object.hash(text, size);

  @override
  String toString() => 'MeasuredLabel("$text", $size)';
}

/// [texts] measured in [style].
List<MeasuredLabel> measureLabels(
  List<String> texts,
  ChartTextStyle style,
  TextMeasurer measurer,
) => <MeasuredLabel>[
  for (final String text in texts)
    MeasuredLabel(text, measurer.measure(text, style)),
];

/// The position of [value] on a value axis of [scale] over [plot].
///
/// Vertical (`horizontal` false), the minimum is at the plot's bottom;
/// horizontal, at its left. A scale of no span puts every value at the
/// minimum's edge.
double valuePosition(
  double value,
  ValueScale scale,
  ChartRect plot, {
  required bool horizontal,
}) {
  final double span = scale.max - scale.min;
  final double t = span > 0 && span.isFinite
      ? ((value - scale.min) / span).clamp(0.0, 1.0)
      : 0.0;
  return horizontal
      ? plot.left + t * plot.width
      : plot.bottom - t * plot.height;
}

/// The value the category axis crosses the value axis at: 0 when it is in the
/// scale, else the bound nearer 0.
double crossingValue(ValueScale scale) {
  if (scale.min <= 0 && scale.max >= 0) {
    return 0;
  }
  return scale.min > 0 ? scale.min : scale.max;
}

/// Whether the tick [labels] of [scale] keep `minTextGap` apart on a value
/// axis of [plot].
///
/// Vertical, adjacent labels' centres must lie half their heights plus the gap
/// apart; horizontal, half their widths plus the gap.
bool valueLabelsFit(
  List<MeasuredLabel> labels,
  ValueScale scale,
  ChartRect plot, {
  required bool horizontal,
  required double minTextGap,
}) {
  for (int i = 1; i < labels.length && i < scale.ticks.length; i++) {
    final double distance =
        (valuePosition(scale.ticks[i], scale, plot, horizontal: horizontal) -
                valuePosition(
                  scale.ticks[i - 1],
                  scale,
                  plot,
                  horizontal: horizontal,
                ))
            .abs();
    final ChartSize a = labels[i - 1].size;
    final ChartSize b = labels[i].size;
    final double need = horizontal
        ? (a.width + b.width) / 2
        : (a.height + b.height) / 2;
    if (distance < need + minTextGap) {
      return false;
    }
  }
  return true;
}

/// The value axis' tick labels of [scale], outside [plot].
///
/// Vertical, each is right-aligned `labelGap` left of the plot and centred on
/// its tick; horizontal, each is centred under its tick, `labelGap` below.
List<TextPrimitive> valueLabelPrimitives(
  List<MeasuredLabel> labels,
  ValueScale scale,
  ChartRect plot,
  ChartTextStyle style, {
  required bool horizontal,
  required double labelGap,
}) {
  return <TextPrimitive>[
    for (int i = 0; i < labels.length && i < scale.ticks.length; i++)
      _valueLabel(
        i,
        labels[i],
        valuePosition(scale.ticks[i], scale, plot, horizontal: horizontal),
        plot,
        style,
        horizontal: horizontal,
        labelGap: labelGap,
      ),
  ];
}

TextPrimitive _valueLabel(
  int index,
  MeasuredLabel label,
  double at,
  ChartRect plot,
  ChartTextStyle style, {
  required bool horizontal,
  required double labelGap,
}) {
  final double w = label.size.width;
  final double h = label.size.height;
  final ChartRect rect = horizontal
      ? ChartRect(at - w / 2, plot.bottom + labelGap, w, h)
      : ChartRect(plot.left - labelGap - w, at - h / 2, w, h);
  return TextPrimitive(
    ids.axisLabelId(ids.valueAxis, index),
    label.text,
    rect,
    style,
  );
}

/// How the category labels go: how thick their band is and whether they fit.
///
/// Task 7 adds which labels are shown, the rotation and the cut texts.
final class CategoryLabelPlan {
  /// Creates a plan of a band [thickness] (without the label gap).
  const CategoryLabelPlan({required this.thickness, required this.fits});

  /// The depth of the labels across the axis: their tallest height under a
  /// horizontal axis, their widest width beside a vertical one.
  final double thickness;

  /// Whether every label fits along the axis without coming closer than
  /// `minTextGap` to its neighbour and without leaving the plot's extent.
  final bool fits;

  @override
  bool operator ==(Object other) =>
      other is CategoryLabelPlan &&
      thickness == other.thickness &&
      fits == other.fits;

  @override
  int get hashCode => Object.hash(thickness, fits);

  @override
  String toString() => 'CategoryLabelPlan($thickness, fits: $fits)';
}

/// Plans the category [labels] along an axis of [axisLength].
///
/// For now every label is shown, horizontal: they fit when the band of each
/// category holds half of each neighbour plus `minTextGap`, and the first and
/// last stay inside the axis. `vertical` is a bar chart's category axis, where
/// heights count instead of widths. Task 7 replaces this.
CategoryLabelPlan planCategoryLabels(
  List<MeasuredLabel> labels,
  double axisLength, {
  required bool vertical,
  required ChartSpacing spacing,
}) {
  if (labels.isEmpty) {
    return const CategoryLabelPlan(thickness: 0, fits: true);
  }
  double thickness = 0;
  for (final MeasuredLabel label in labels) {
    thickness = math.max(
      thickness,
      vertical ? label.size.width : label.size.height,
    );
  }
  final double band = axisLength / labels.length;
  double along(int i) =>
      vertical ? labels[i].size.height : labels[i].size.width;
  bool fits = band > 0 && along(0) <= band && along(labels.length - 1) <= band;
  for (int i = 1; fits && i < labels.length; i++) {
    if (band < (along(i - 1) + along(i)) / 2 + spacing.minTextGap) {
      fits = false;
    }
  }
  return CategoryLabelPlan(thickness: thickness, fits: fits);
}

/// The category [labels] of [plan], outside [plot].
///
/// Under a horizontal axis each is centred under its category's band,
/// `labelGap` below the plot. Beside a vertical one (a bar chart) each is
/// right-aligned `labelGap` left of the plot and centred on its band, the
/// first category at the bottom, as Excel draws it.
List<TextPrimitive> placeCategoryLabels(
  CategoryLabelPlan plan,
  List<MeasuredLabel> labels,
  ChartRect plot,
  ChartTextStyle style, {
  required bool vertical,
  required ChartSpacing spacing,
}) {
  final int n = labels.length;
  final List<TextPrimitive> placed = <TextPrimitive>[];
  for (int i = 0; i < n; i++) {
    final double w = labels[i].size.width;
    final double h = labels[i].size.height;
    final ChartRect rect;
    if (vertical) {
      final double cy = plot.bottom - (i + 0.5) * plot.height / n;
      rect = ChartRect(plot.left - spacing.labelGap - w, cy - h / 2, w, h);
    } else {
      final double cx = plot.left + (i + 0.5) * plot.width / n;
      rect = ChartRect(cx - w / 2, plot.bottom + spacing.labelGap, w, h);
    }
    placed.add(
      TextPrimitive(
        ids.axisLabelId(ids.categoryAxis, i),
        labels[i].text,
        rect,
        style,
      ),
    );
  }
  return placed;
}

/// A grid line at each tick of [scale] across [plot].
List<PathPrimitive> valueGridLines(
  ValueScale scale,
  ChartRect plot, {
  required bool horizontal,
  required ChartColor color,
  required double width,
}) {
  return <PathPrimitive>[
    for (int i = 0; i < scale.ticks.length; i++)
      _line(
        ids.gridId(ids.valueAxis, i),
        valuePosition(scale.ticks[i], scale, plot, horizontal: horizontal),
        plot,
        across: horizontal,
        color: color,
        width: width,
      ),
  ];
}

/// A grid line at each edge between [categories] bands across [plot], the two
/// outer edges included.
List<PathPrimitive> categoryGridLines(
  int categories,
  ChartRect plot, {
  required bool vertical,
  required ChartColor color,
  required double width,
}) {
  if (categories <= 0) {
    return const <PathPrimitive>[];
  }
  return <PathPrimitive>[
    for (int i = 0; i <= categories; i++)
      _line(
        ids.gridId(ids.categoryAxis, i),
        vertical
            ? plot.bottom - i * plot.height / categories
            : plot.left + i * plot.width / categories,
        plot,
        across: !vertical,
        color: color,
        width: width,
      ),
  ];
}

/// The value axis' line along the plot's left edge (vertical) or bottom edge
/// (horizontal).
PathPrimitive valueAxisLine(
  ChartRect plot, {
  required bool horizontal,
  required ChartColor color,
  required double width,
}) {
  return _line(
    ids.axisLineId(ids.valueAxis),
    horizontal ? plot.bottom : plot.left,
    plot,
    across: !horizontal,
    color: color,
    width: width,
  );
}

/// The category axis' line, at the value of [crossingValue] of [scale].
PathPrimitive categoryAxisLine(
  ValueScale scale,
  ChartRect plot, {
  required bool horizontal,
  required ChartColor color,
  required double width,
}) {
  return _line(
    ids.axisLineId(ids.categoryAxis),
    valuePosition(crossingValue(scale), scale, plot, horizontal: horizontal),
    plot,
    across: horizontal,
    color: color,
    width: width,
  );
}

/// A line at [at] across [plot]: vertical, at x = [at], when [across] is true;
/// horizontal, at y = [at], when it is false.
PathPrimitive _line(
  String id,
  double at,
  ChartRect plot, {
  required bool across,
  required ChartColor color,
  required double width,
}) {
  return PathPrimitive(
    id,
    across
        ? <ChartPoint>[ChartPoint(at, plot.top), ChartPoint(at, plot.bottom)]
        : <ChartPoint>[ChartPoint(plot.left, at), ChartPoint(plot.right, at)],
    stroke: color,
    strokeWidth: width,
  );
}
