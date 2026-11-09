/// The frame's inputs, one attempt at it, and the primitives and hidden texts
/// of the attempt that fits.
///
/// The paint order: background, title, legend, plot, grid lines, the marks'
/// clip, axis lines, tick labels, category labels, axis titles, and last the
/// data labels.
library;

import 'dart:math' as math;

import 'package:jet_core/jet_core.dart';

import '../model/chart.dart';
import '../model/chart_kind.dart';
import '../scale/value_scale.dart';
import '../theme/chart_color.dart';
import '../theme/chart_theme.dart';
import 'axis_layout.dart';
import 'chart_ids.dart' as ids;
import 'data_labels.dart';
import 'degradation.dart';
import 'geometry.dart';
import 'legend_layout.dart';
import 'marks.dart';
import 'primitives.dart';
import 'resolve.dart';
import 'text_measurer.dart';

/// One try at the frame with what [FrameShown] allows.
final class FrameAttempt {
  /// Creates an attempt; one with no plot is a frame with no room at all.
  FrameAttempt({
    this.misfit,
    this.misfits = const <FrameMisfit>{FrameMisfit.space},
    this.title,
    this.legend,
    this.inner,
    this.plot,
    this.scale,
    this.valueLabels = const <MeasuredLabel>[],
    this.valueStride = 1,
    this.plan,
    this.categoryOffset = 0,
  });

  /// A part that does not fit its own space, to hide before trying again.
  final FramePart? misfit;

  /// Why the attempt does not fit; empty when it does. An attempt with no
  /// room at all does not fit for [FrameMisfit.space].
  final Set<FrameMisfit> misfits;

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

  /// Every how many tick labels one is drawn, from the first: 1 draws them
  /// all; more thins the labels of a fixed unit that crowd.
  final int valueStride;

  /// The category labels' plan.
  final CategoryLabelPlan? plan;

  /// The distance of the category labels from the plot.
  final double categoryOffset;
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
      onTicks = chart.kind == ChartKind.area,
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

  /// Whether the categories sit on tick marks, as Excel draws an area chart
  /// (`categoryPosition`): from the plot's one edge to the other.
  final bool onTicks;

  /// The data's extent under the chart's grouping.
  final ({double min, double max}) extent;

  /// The category labels, measured.
  final List<MeasuredLabel> categoryLabels;

  /// The gap between an axis and its labels.
  double get gap => theme.spacing.labelGap;

  /// The background, which fills the size.
  RectPrimitive background() => backgroundPrimitive(theme, size);

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

  /// Whether the chart fixes the value axis' major unit, which coarsening
  /// cannot change.
  bool get fixedUnit {
    final double? unit = chart.valueAxis.majorUnit;
    return unit != null && unit.isFinite && unit > 0;
  }

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
  ({List<ChartPrimitive> primitives, List<(String, String)> hiddenData}) paint(
    FrameAttempt a,
    FrameShown shown,
  ) {
    final ChartRect plot = a.plot!;
    final ValueScale scale = a.scale!;
    final ChartRect inner = a.inner!;
    final List<ChartPrimitive> out = <ChartPrimitive>[
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
          onTicks: onTicks,
        ),
      if (chart.valueAxis.gridLines)
        ...valueGridLines(
          scale,
          plot,
          horizontal: bar,
          color: theme.gridLine,
          width: theme.spacing.gridLineWidth,
        ),
      ClipPrimitive(
        ids.plotClip,
        plot,
        layoutMarks(chart, resolved, theme, plot, scale),
      ),
      if (chart.valueAxis.visible && theme.valueAxisLine)
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
          stride: a.valueStride,
        ),
      if (shown.categoryLabels)
        ...placeCategoryLabels(
          a.plan!,
          resolved.categoryCount,
          plot,
          theme.axisLabels,
          vertical: bar,
          offset: a.categoryOffset,
          onTicks: onTicks,
        ),
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
    // Data labels go last, on top of everything else.
    final DataLabelPlacement labels = shown.dataLabels
        ? placeDataLabels(
            chart: chart,
            resolved: resolved,
            theme: theme,
            measurer: measurer,
            formatter: formatter,
            plot: plot,
            scale: scale,
            existing: out,
          )
        : const DataLabelPlacement(<TextPrimitive>[], <(String, String)>[]);
    return (
      primitives: <ChartPrimitive>[...out, ...labels.primitives],
      hiddenData: labels.hidden,
    );
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

  /// The texts [wanted] that [shown] leaves out, grouped in the order of
  /// [DegradeStep]: data labels (the ones [hiddenData] lists, or all of them
  /// when [shown] has none), legend entries, axis titles, title, category
  /// labels (every one not shown and every cut one, with its full text),
  /// value labels (all of them when not shown, else the ones thinning left
  /// out).
  ///
  /// Value labels of an attempt with no room at all come from a fallback
  /// scale of at most `excelMaxIntervals(0, ...)` intervals: one.
  List<(String, String)> hiddenTexts(
    FrameShown wanted,
    FrameShown shown,
    FrameAttempt a,
    List<(String, String)> hiddenData,
  ) {
    final List<String> ticks = <String>[
      for (final MeasuredLabel label
          in a.valueLabels.isEmpty && wanted.valueLabels
              ? tickLabels(scaleFor(1))
              : a.valueLabels)
        label.text,
    ];
    final Map<int, String> drawn = <int, String>{
      if (shown.categoryLabels && a.plan != null)
        for (int k = 0; k < a.plan!.shown.length; k++)
          a.plan!.shown[k]: a.plan!.labels[k].text,
    };
    return <(String, String)>[
      ...(wanted.dataLabels && !shown.dataLabels
          ? dataLabelTexts(chart, resolved, formatter)
          : hiddenData),
      if (wanted.legend && !shown.legend)
        for (int s = 0; s < resolved.seriesNames.length; s++)
          (ids.legendTextId(s), resolved.seriesNames[s]),
      if (wanted.valueTitle && !shown.valueTitle)
        (ids.axisTitleId(ids.valueAxis), chart.valueAxis.title!),
      if (wanted.categoryTitle && !shown.categoryTitle)
        (ids.axisTitleId(ids.categoryAxis), chart.categoryAxis.title!),
      if (wanted.title && !shown.title) (ids.title, chart.title!.text),
      if (wanted.categoryLabels)
        for (int i = 0; i < resolved.categoryCount; i++)
          if (drawn[i] == null ||
              !isWrappingOf(drawn[i]!, resolved.categoryLabels[i]))
            (ids.axisLabelId(ids.categoryAxis, i), resolved.categoryLabels[i]),
      if (wanted.valueLabels)
        for (int i = 0; i < ticks.length; i++)
          if (!shown.valueLabels || i % a.valueStride != 0)
            (ids.axisLabelId(ids.valueAxis, i), ticks[i]),
    ];
  }
}

/// The background of a chart of [size]: the theme's fill over the whole size.
///
/// When the theme has a border, the rectangle carries it as its stroke. The
/// rectangle is inset by half the border's width, so the stroke stays inside
/// [size]; when the size is no larger than the border's width, no stroke is
/// drawn.
RectPrimitive backgroundPrimitive(ChartTheme theme, ChartSize size) {
  final ChartColor? border = theme.border;
  final double w = theme.borderWidth;
  if (border == null || !(w > 0) || size.width <= w || size.height <= w) {
    return RectPrimitive(
      ids.background,
      ChartRect(0, 0, size.width, size.height),
      fill: theme.background,
    );
  }
  return RectPrimitive(
    ids.background,
    ChartRect(w / 2, w / 2, size.width - w, size.height - w),
    fill: theme.background,
    stroke: border,
    strokeWidth: w,
  );
}
