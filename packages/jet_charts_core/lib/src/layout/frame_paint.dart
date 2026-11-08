/// The frame's inputs, one attempt at it, and the primitives and hidden texts
/// of the attempt that fits.
///
/// The paint order: background, title, legend, plot, grid lines, the marks'
/// clip (Task 6 fills it), axis lines, tick labels, category labels, (Task 8's
/// data labels), axis titles.
library;

import 'dart:math' as math;

import 'package:jet_core/jet_core.dart';

import '../model/chart.dart';
import '../model/chart_kind.dart';
import '../scale/value_scale.dart';
import '../theme/chart_theme.dart';
import 'axis_layout.dart';
import 'chart_ids.dart' as ids;
import 'degradation.dart';
import 'geometry.dart';
import 'legend_layout.dart';
import 'primitives.dart';
import 'resolve.dart';
import 'text_measurer.dart';

/// One try at the frame with what [FrameShown] allows.
final class FrameAttempt {
  /// Creates an attempt; one with no plot is a frame with no room at all.
  FrameAttempt({
    this.misfit,
    this.fits = false,
    this.title,
    this.legend,
    this.inner,
    this.plot,
    this.scale,
    this.valueLabels = const <MeasuredLabel>[],
    this.plan,
  });

  /// A part that does not fit its own space, to hide before trying again.
  final FramePart? misfit;

  /// Whether the plot is at least 1 by 1 and no labels collide.
  final bool fits;

  /// The placed title, or `null` when it is not shown.
  final Placed? title;

  /// The placed legend, or `null` when it is not shown.
  final Placed? legend;

  /// The area of the axes and the plot.
  final ChartRect? inner;

  /// The plot area.
  final ChartRect? plot;

  /// The value axis' scale.
  final ValueScale? scale;

  /// The value axis' tick labels, measured.
  final List<MeasuredLabel> valueLabels;

  /// The category labels' plan.
  final CategoryLabelPlan? plan;
}

/// The inputs of a frame and what is derived from them once.
final class FrameContext {
  /// Creates the context of laying out [chart], whose data is [resolved].
  FrameContext(
    this.chart,
    this.resolved,
    this.theme,
    this.size,
    this.measurer,
    this.formatter,
  ) : bar = chart.kind == ChartKind.bar,
      extent = dataExtent(resolved.values, resolved.grouping),
      categoryLabels = measureLabels(
        resolved.categoryLabels,
        theme.axisLabels,
        measurer,
      );

  /// The chart.
  final Chart chart;

  /// The chart's resolved data.
  final ResolvedChart resolved;

  /// The theme.
  final ChartTheme theme;

  /// The size laid out on.
  final ChartSize size;

  /// The text measurer.
  final TextMeasurer measurer;

  /// The number formatter of the labels.
  final NumberFormatter formatter;

  /// Whether the value axis is horizontal: a bar chart.
  final bool bar;

  /// The data's extent under the chart's grouping.
  final ({double min, double max}) extent;

  /// The category labels, measured.
  final List<MeasuredLabel> categoryLabels;

  /// The gap between an axis and its labels.
  double get gap => theme.spacing.labelGap;

  /// The background, which fills the size.
  RectPrimitive background() => RectPrimitive(
    ids.background,
    ChartRect(0, 0, size.width, size.height),
    fill: theme.background,
  );

  /// The scale with at most [maxIntervals] intervals.
  ValueScale scaleFor(int maxIntervals) => autoValueScale(
    dataMin: extent.min,
    dataMax: extent.max,
    maxIntervals: maxIntervals,
    fixedMin: chart.valueAxis.min,
    fixedMax: chart.valueAxis.max,
    fixedMajorUnit: chart.valueAxis.majorUnit,
    percent: resolved.percent,
  );

  /// The tick labels of [scale], measured.
  List<MeasuredLabel> tickLabels(ValueScale scale) => measureLabels(
    <String>[
      for (final double tick in scale.ticks)
        formatTick(tick, resolved.tickFormatCode, formatter),
    ],
    theme.axisLabels,
    measurer,
  );

  /// The size of an axis title of [text], or `null` when not [shown].
  ChartSize? titleSize(bool shown, String? text) =>
      shown ? measurer.measure(text!, theme.axisLabels) : null;
}

/// Painting a frame.
extension FramePaint on FrameContext {
  /// What the frame of [a] draws with what [shown] allows, in paint order.
  List<ChartPrimitive> paint(FrameAttempt a, FrameShown shown) {
    final ChartRect plot = a.plot!;
    final ValueScale scale = a.scale!;
    final ChartRect inner = a.inner!;
    return <ChartPrimitive>[
      background(),
      ...?a.title?.primitives,
      ...?a.legend?.primitives,
      RectPrimitive(ids.plot, plot),
      if (chart.categoryAxis.gridLines)
        ...categoryGridLines(
          resolved.categoryCount,
          plot,
          vertical: bar,
          color: theme.gridLine,
          width: theme.spacing.gridLineWidth,
        ),
      if (chart.valueAxis.gridLines)
        ...valueGridLines(
          scale,
          plot,
          horizontal: bar,
          color: theme.gridLine,
          width: theme.spacing.gridLineWidth,
        ),
      // Task 6: the series marks go inside this clip, after the grid and
      // before the axis lines and labels.
      ClipPrimitive(ids.plotClip, plot, const <ChartPrimitive>[]),
      if (chart.valueAxis.visible)
        valueAxisLine(
          plot,
          horizontal: bar,
          color: theme.axisLine,
          width: theme.spacing.axisLineWidth,
        ),
      if (chart.categoryAxis.visible)
        categoryAxisLine(
          scale,
          plot,
          horizontal: bar,
          color: theme.axisLine,
          width: theme.spacing.axisLineWidth,
        ),
      if (shown.valueLabels)
        ...valueLabelPrimitives(
          a.valueLabels,
          scale,
          plot,
          theme.axisLabels,
          horizontal: bar,
          labelGap: gap,
        ),
      if (shown.categoryLabels)
        ...placeCategoryLabels(
          a.plan!,
          categoryLabels,
          plot,
          theme.axisLabels,
          vertical: bar,
          spacing: theme.spacing,
        ),
      // Task 8: the data labels go here, above everything else.
      if (shown.valueTitle)
        _axisTitle(
          ids.axisTitleId(ids.valueAxis),
          chart.valueAxis.title!,
          inner,
          plot,
          rotated: !bar,
        ),
      if (shown.categoryTitle)
        _axisTitle(
          ids.axisTitleId(ids.categoryAxis),
          chart.categoryAxis.title!,
          inner,
          plot,
          rotated: bar,
        ),
    ];
  }

  /// An axis title: turned -90 degrees at the left of [inner], centred on the
  /// plot's height as far as its span allows, or level at the bottom of
  /// [inner], centred on the plot's width.
  TextPrimitive _axisTitle(
    String id,
    String text,
    ChartRect inner,
    ChartRect plot, {
    required bool rotated,
  }) {
    final ChartSize s = measurer.measure(text, theme.axisLabels);
    if (rotated) {
      final double cy = (plot.top + plot.height / 2).clamp(
        inner.top + s.width / 2,
        math.max(inner.top + s.width / 2, plot.bottom - s.width / 2),
      );
      final double cx = inner.left + s.height / 2;
      return TextPrimitive(
        id,
        text,
        ChartRect(cx - s.width / 2, cy - s.height / 2, s.width, s.height),
        theme.axisLabels,
        rotationDegrees: -90,
      );
    }
    return TextPrimitive(
      id,
      text,
      ChartRect(
        plot.left + (plot.width - s.width) / 2,
        inner.bottom - s.height,
        s.width,
        s.height,
      ),
      theme.axisLabels,
    );
  }

  /// The texts [wanted] that [shown] leaves out, in the order of
  /// [DegradeStep].
  List<(String, String)> hiddenTexts(
    FrameShown wanted,
    FrameShown shown,
    FrameAttempt a,
  ) {
    final List<String> ticks = <String>[
      for (final MeasuredLabel label in a.valueLabels) label.text,
    ];
    return <(String, String)>[
      // Task 8: hidden data labels come first.
      if (wanted.legend && !shown.legend)
        for (int s = 0; s < resolved.seriesNames.length; s++)
          (ids.legendTextId(s), resolved.seriesNames[s]),
      if (wanted.valueTitle && !shown.valueTitle)
        (ids.axisTitleId(ids.valueAxis), chart.valueAxis.title!),
      if (wanted.categoryTitle && !shown.categoryTitle)
        (ids.axisTitleId(ids.categoryAxis), chart.categoryAxis.title!),
      if (wanted.title && !shown.title) (ids.title, chart.title!.text),
      if (wanted.categoryLabels && !shown.categoryLabels)
        for (int i = 0; i < resolved.categoryCount; i++)
          (ids.axisLabelId(ids.categoryAxis, i), resolved.categoryLabels[i]),
      if (wanted.valueLabels && !shown.valueLabels)
        for (int i = 0; i < ticks.length; i++)
          (ids.axisLabelId(ids.valueAxis, i), ticks[i]),
    ];
  }
}
