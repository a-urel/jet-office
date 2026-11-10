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
import '../model/chart_axis.dart';
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
import 'scatter_layout.dart';
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
    this.xScale,
    this.xLabels = const <MeasuredLabel>[],
    this.xStride = 1,
    this.secondaryScale,
    this.secondaryLabels = const <MeasuredLabel>[],
    this.secondaryStride = 1,
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

  /// A scatter chart's horizontal value axis' scale; `null` for another kind.
  final ValueScale? xScale;

  /// A scatter chart's horizontal tick labels, measured: every one of
  /// [xScale]'s ticks, drawn or not.
  final List<MeasuredLabel> xLabels;

  /// Every how many horizontal tick labels one is drawn, from the first, as
  /// [valueStride] for the vertical ones.
  final int xStride;

  /// The secondary value axis' scale; `null` when the chart has none to
  /// draw.
  final ValueScale? secondaryScale;

  /// The secondary value axis' tick labels, measured: every one of
  /// [secondaryScale]'s ticks, drawn or not.
  final List<MeasuredLabel> secondaryLabels;

  /// Every how many secondary tick labels one is drawn, from the first, as
  /// [valueStride] for the primary ones.
  final int secondaryStride;
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
      onTicks = categoriesOnTicks(chart, resolved),
      scatter = chart.kind == ChartKind.scatter,
      secondary = resolved.drawsSecondaryAxis,
      secondaryAxis = chart.secondaryValueAxis ?? const ChartAxis(),
      extent = resolved.primaryExtent,
      secondaryExtent = resolved.secondaryExtent,
      xValues = chart.kind == ChartKind.scatter
          ? scatterXValues(chart, resolved.categoryCount)
          : const <List<double>>[],
      categoryLabels = chart.kind == ChartKind.scatter
          ? const <MeasuredLabel>[]
          : measureLabels(resolved.categoryLabels, theme.axisLabels, measurer);

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
  /// (`categoriesOnTicks`): from the plot's one edge to the other.
  final bool onTicks;

  /// Whether the chart has a secondary value axis to draw
  /// (`ResolvedChart.drawsSecondaryAxis`), on the plot's right.
  final bool secondary;

  /// The secondary value axis' settings: the chart's, else an axis with no
  /// gridlines.
  final ChartAxis secondaryAxis;

  /// The extent of the values measured on the secondary value axis.
  final ({double min, double max}) secondaryExtent;

  /// Whether the chart is a scatter chart, whose category axis is a second
  /// value axis, horizontal, of the x values (`scatter_layout.dart`).
  final bool scatter;

  /// The extent of the values measured on the primary value axis, each
  /// group under its grouping (`axisExtent`).
  final ({double min, double max}) extent;

  /// A scatter chart's x values (`scatterXValues`); empty for another kind.
  final List<List<double>> xValues;

  /// The extent of a scatter chart's x values (`scatterXExtent`).
  late final ({double min, double max}) xExtent = scatterXExtent(
    xValues,
    resolved.values,
  );

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
  bool get fixedUnit => _fixed(chart.valueAxis.majorUnit);

  /// The secondary value axis' scale with at most [maxIntervals] intervals,
  /// from the extent of its series and its own bounds and unit.
  ValueScale secondaryScaleFor(int maxIntervals) => autoValueScale(
    dataMin: secondaryExtent.min,
    dataMax: secondaryExtent.max,
    maxIntervals: maxIntervals,
    fixedMin: secondaryAxis.min,
    fixedMax: secondaryAxis.max,
    fixedMajorUnit: secondaryAxis.majorUnit,
    percent: resolved.secondaryPercent,
  );

  /// Whether the chart fixes the secondary value axis' major unit.
  bool get fixedSecondaryUnit => _fixed(secondaryAxis.majorUnit);

  /// The secondary value axis' tick labels of [scale], measured.
  List<MeasuredLabel> secondaryTickLabels(ValueScale scale) => measureLabels(
    <String>[
      for (final double tick in scale.ticks)
        formatTick(tick, resolved.secondaryTickFormatCode, formatter),
    ],
    theme.axisLabels,
    measurer,
  );

  /// A scatter chart's horizontal scale with at most [maxIntervals]
  /// intervals, from the x values' extent and the category axis' bounds and
  /// unit.
  ValueScale xScaleFor(int maxIntervals) => autoValueScale(
    dataMin: xExtent.min,
    dataMax: xExtent.max,
    maxIntervals: maxIntervals,
    fixedMin: chart.categoryAxis.min,
    fixedMax: chart.categoryAxis.max,
    fixedMajorUnit: chart.categoryAxis.majorUnit,
  );

  /// Whether a scatter chart fixes its horizontal axis' major unit.
  bool get fixedXUnit => _fixed(chart.categoryAxis.majorUnit);

  static bool _fixed(double? unit) => unit != null && unit.isFinite && unit > 0;

  /// A scatter chart's horizontal tick labels of [scale] (`scatterXText`),
  /// measured.
  List<MeasuredLabel> xTickLabels(ValueScale scale) => measureLabels(
    <String>[
      for (final double tick in scale.ticks)
        scatterXText(tick, chart, formatter),
    ],
    theme.axisLabels,
    measurer,
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
  ({List<ChartPrimitive> primitives, List<(String, String)> hiddenData}) paint(
    FrameAttempt a,
    FrameShown shown,
  ) {
    final ChartRect plot = a.plot!;
    final ValueScale scale = a.scale!;
    final ChartRect inner = a.inner!;
    final ValueScale? xScale = a.xScale;
    final ScatterAxis? scatterAxis = xScale == null
        ? null
        : (scale: xScale, values: xValues);
    final ({List<ChartPrimitive> shapes, List<ChartPrimitive> markers}) marks =
        _splitMarkers(
          layoutMarks(
            chart,
            resolved,
            theme,
            plot,
            scale,
            scatterAxis: scatterAxis,
            secondaryScale: a.secondaryScale,
          ),
        );
    final List<ChartPrimitive> out = <ChartPrimitive>[
      background(),
      ...?a.title?.primitives,
      ...?a.legend?.primitives,
      RectPrimitive(ids.plot, plot),
      if (chart.categoryAxis.gridLines && xScale != null)
        ...valueGridLines(
          xScale,
          plot,
          horizontal: true,
          color: theme.gridLine,
          width: theme.spacing.gridLineWidth,
          axis: ids.categoryAxis,
        )
      else if (chart.categoryAxis.gridLines)
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
      if (a.secondaryScale != null && secondaryAxis.gridLines)
        ...valueGridLines(
          a.secondaryScale!,
          plot,
          horizontal: false,
          color: theme.gridLine,
          width: theme.spacing.gridLineWidth,
          axis: ids.secondaryAxis,
        ),
      ClipPrimitive(ids.plotClip, plot, marks.shapes),
      if (marks.markers.isNotEmpty)
        ClipPrimitive(ids.markerClip, _markerClip(plot), marks.markers),
      if (chart.valueAxis.visible && theme.valueAxisLine)
        valueAxisLine(
          plot,
          horizontal: bar,
          color: theme.axisLine,
          width: theme.spacing.axisLineWidth,
          crossScale: xScale,
        ),
      if (a.secondaryScale != null &&
          secondaryAxis.visible &&
          theme.valueAxisLine)
        valueAxisLine(
          plot,
          horizontal: false,
          color: theme.axisLine,
          width: theme.spacing.axisLineWidth,
          axis: ids.secondaryAxis,
          far: true,
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
      if (shown.secondaryLabels && a.secondaryScale != null)
        ...valueLabelPrimitives(
          a.secondaryLabels,
          a.secondaryScale!,
          plot,
          theme.axisLabels,
          horizontal: false,
          labelGap: gap,
          stride: a.secondaryStride,
          axis: ids.secondaryAxis,
          far: true,
        ),
      if (shown.categoryLabels && xScale != null)
        ...valueLabelPrimitives(
          a.xLabels,
          xScale,
          plot,
          theme.axisLabels,
          horizontal: true,
          labelGap: a.categoryOffset,
          stride: a.xStride,
          axis: ids.categoryAxis,
        )
      else if (shown.categoryLabels)
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
      if (shown.secondaryTitle)
        _axisTitle(
          ids.axisTitleId(ids.secondaryAxis),
          secondaryAxis.title!,
          inner,
          plot,
          rotated: true,
          far: true,
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
            area: inner,
            scale: scale,
            existing: out,
            scatterAxis: scatterAxis,
            secondaryScale: a.secondaryScale,
          )
        : const DataLabelPlacement(<TextPrimitive>[], <(String, String)>[]);
    return (
      primitives: <ChartPrimitive>[...out, ...labels.primitives],
      hiddenData: labels.hidden,
    );
  }

  /// [marks] parted into the line markers and every other mark, each in
  /// paint order.
  ({List<ChartPrimitive> shapes, List<ChartPrimitive> markers}) _splitMarkers(
    List<ChartPrimitive> marks,
  ) {
    final List<ChartPrimitive> shapes = <ChartPrimitive>[];
    final List<ChartPrimitive> markers = <ChartPrimitive>[];
    for (final ChartPrimitive m in marks) {
      (m is ArcPrimitive ? markers : shapes).add(m);
    }
    return (shapes: shapes, markers: markers);
  }

  /// The clip of the line markers: [plot] grown on every side by a marker's
  /// reach (half the theme's `markerSize` and half its outline), so a marker
  /// centred on the plot's edge is drawn whole, and kept inside the chart.
  ChartRect _markerClip(ChartRect plot) {
    final double reach = theme.markerSize / 2 + markerOutlineWidth / 2;
    final double left = math.max(0, plot.left - reach);
    final double top = math.max(0, plot.top - reach);
    final double right = math.min(size.width, plot.right + reach);
    final double bottom = math.min(size.height, plot.bottom + reach);
    return ChartRect(
      left,
      top,
      math.max(0, right - left),
      math.max(0, bottom - top),
    );
  }

  /// An axis title: turned -90 degrees at the left of [inner] (at its right
  /// on the [far] side, the secondary value axis'), centred on the plot's
  /// height as far as its span allows, or level at the bottom of [inner],
  /// centred on the plot's width. The secondary title's turn is an estimate,
  /// not checked in Excel.
  TextPrimitive _axisTitle(
    String id,
    String text,
    ChartRect inner,
    ChartRect plot, {
    required bool rotated,
    bool far = false,
  }) {
    final ChartSize s = measurer.measure(text, theme.axisLabels);
    if (rotated) {
      final double cy = (plot.top + plot.height / 2).clamp(
        inner.top + s.width / 2,
        math.max(inner.top + s.width / 2, plot.bottom - s.width / 2),
      );
      final double cx = far
          ? inner.right - s.height / 2
          : inner.left + s.height / 2;
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
  /// labels (every one not shown and every cut one, with its full text; a
  /// scatter chart's horizontal tick labels as the value labels), value
  /// labels (all of them when not shown, else the ones thinning left
  /// out), then the secondary value axis' tick labels in the same way.
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
    final List<String> secondaryTicks = <String>[
      if (secondary)
        for (final MeasuredLabel label
            in a.secondaryLabels.isEmpty && wanted.secondaryLabels
                ? secondaryTickLabels(secondaryScaleFor(1))
                : a.secondaryLabels)
          label.text,
    ];
    final List<String> xTicks = !scatter
        ? const <String>[]
        : <String>[
            for (final MeasuredLabel label
                in a.xLabels.isEmpty && wanted.categoryLabels
                    ? xTickLabels(xScaleFor(1))
                    : a.xLabels)
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
      if (wanted.secondaryTitle && !shown.secondaryTitle)
        (ids.axisTitleId(ids.secondaryAxis), secondaryAxis.title!),
      if (wanted.title && !shown.title) (ids.title, chart.title!.text),
      if (wanted.categoryLabels && scatter)
        for (int i = 0; i < xTicks.length; i++)
          if (!shown.categoryLabels || i % a.xStride != 0)
            (ids.axisLabelId(ids.categoryAxis, i), xTicks[i]),
      if (wanted.categoryLabels && !scatter)
        for (int i = 0; i < resolved.categoryCount; i++)
          if (drawn[i] == null ||
              !isWrappingOf(drawn[i]!, resolved.categoryLabels[i]))
            (ids.axisLabelId(ids.categoryAxis, i), resolved.categoryLabels[i]),
      if (wanted.valueLabels)
        for (int i = 0; i < ticks.length; i++)
          if (!shown.valueLabels || i % a.valueStride != 0)
            (ids.axisLabelId(ids.valueAxis, i), ticks[i]),
      if (wanted.secondaryLabels)
        for (int i = 0; i < secondaryTicks.length; i++)
          if (!shown.secondaryLabels || i % a.secondaryStride != 0)
            (ids.axisLabelId(ids.secondaryAxis, i), secondaryTicks[i]),
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
