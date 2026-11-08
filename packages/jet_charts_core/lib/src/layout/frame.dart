/// The frame of a cartesian chart: title, legend, axis titles, axis bands and
/// the plot area, found by iterating with the value scale, and degraded in a
/// fixed order when the content does not fit.
///
/// The frame, y-down: the background fills the size; `padding` inside it the
/// title takes the top, then the legend its side, and what is left holds the
/// axis titles, the axis bands and the plot. Title and legend shrink the plot,
/// never the reverse.
///
/// The value scale and the axis bands depend on each other: the scale's most
/// intervals come from the plot's length (`provisionalMaxIntervals`), the
/// tick labels from the scale, and the bands from the labels. [layoutFrame]
/// starts from the plot without bands and repeats until the scale and bands
/// stay the same, at most four passes, keeping the last. When adjacent tick
/// labels would then come closer than `minTextGap`, it asks for fewer
/// intervals until they fit or only one is left: the next coarser step. Excel
/// lets such labels collide; taking the coarser step is a deliberate
/// difference (Task 11 lists it in `docs/parity.md`).
library;

import 'dart:math' as math;

import 'package:jet_core/jet_core.dart';

import '../model/chart.dart';
import '../scale/value_scale.dart';
import '../theme/chart_theme.dart';
import 'axis_layout.dart';
import 'degradation.dart';
import 'frame_paint.dart';
import 'geometry.dart';
import 'legend_layout.dart';
import 'primitives.dart';
import 'resolve.dart';
import 'text_measurer.dart';

/// Where the frame put the plot and its scale, for the marks (Task 6) and the
/// data labels (Task 8).
final class FrameGeometry {
  /// Creates the geometry of a laid out frame.
  const FrameGeometry({
    required this.plot,
    required this.scale,
    required this.valueAxisHorizontal,
    required this.resolved,
  });

  /// The plot area.
  final ChartRect plot;

  /// The value axis' scale.
  final ValueScale scale;

  /// Whether the value axis runs horizontally (a bar chart).
  final bool valueAxisHorizontal;

  /// The chart's resolved data.
  final ResolvedChart resolved;

  /// The value the category axis crosses at (`crossingValue`).
  double get crossing => crossingValue(scale);

  /// The position of [value] along the value axis.
  double position(double value) =>
      valuePosition(value, scale, plot, horizontal: valueAxisHorizontal);
}

/// A laid out frame.
final class FrameLayout {
  /// Creates a frame layout.
  const FrameLayout({
    required this.primitives,
    required this.hidden,
    this.geometry,
  });

  /// What to draw, in paint order.
  final List<ChartPrimitive> primitives;

  /// The texts the frame hid, as id and text, in the order of [DegradeStep].
  final List<(String, String)> hidden;

  /// The plot and scale, or `null` when only the background is drawn.
  final FrameGeometry? geometry;
}

/// Lays out the frame of [chart] (column, bar, line or area), whose data is
/// [resolved], on [size].
FrameLayout layoutFrame(
  Chart chart,
  ResolvedChart resolved, {
  required ChartTheme theme,
  required ChartSize size,
  required TextMeasurer measurer,
  required NumberFormatter formatter,
}) {
  final FrameContext frame = FrameContext(
    chart,
    resolved,
    theme,
    size,
    measurer,
    formatter,
  );
  final FrameShown wanted = FrameShown.wanted(chart, resolved);
  final FrameShown shown = FrameShown.wanted(chart, resolved);
  int step = 0;
  while (true) {
    final FrameAttempt attempt = frame.attempt(shown);
    if (attempt.misfit != null) {
      shown.hide(attempt.misfit!);
      continue;
    }
    if (attempt.fits) {
      return FrameLayout(
        primitives: frame.paint(attempt, shown),
        hidden: frame.hiddenTexts(wanted, shown, attempt),
        geometry: FrameGeometry(
          plot: attempt.plot!,
          scale: attempt.scale!,
          valueAxisHorizontal: frame.bar,
          resolved: resolved,
        ),
      );
    }
    if (step == DegradeStep.values.length) {
      shown.hideAll();
      return FrameLayout(
        primitives: <ChartPrimitive>[frame.background()],
        hidden: frame.hiddenTexts(wanted, shown, attempt),
      );
    }
    shown.take(DegradeStep.values[step++]);
  }
}

/// The insets of the plot from the area the axes share with it.
typedef _Bands = ({double left, double top, double right, double bottom});

/// Trying the frame: the iteration of scale and bands.
extension on FrameContext {
  FrameAttempt attempt(FrameShown shown) {
    final double p = theme.spacing.padding;
    final ChartRect content = ChartRect(
      p,
      p,
      size.width - 2 * p,
      size.height - 2 * p,
    );
    if (!(content.width > 0 && content.height > 0)) {
      return FrameAttempt();
    }
    ChartRect area = content;
    Placed? title;
    if (shown.title) {
      title = placeTitle(
        chart.title!.text,
        area,
        theme.titleText,
        measurer,
        theme.spacing,
      );
      if (title == null) {
        return FrameAttempt(misfit: FramePart.title);
      }
      area = title.rest;
    }
    Placed? legend;
    if (shown.legend) {
      legend = placeLegend(
        resolved.seriesNames,
        resolved.colors,
        chart.legend.position,
        area,
        content,
        theme.legendText,
        measurer,
        theme.spacing,
      );
      if (legend == null) {
        return FrameAttempt(misfit: FramePart.legend);
      }
      area = legend.rest;
    }
    final ChartRect inner = area;
    final ChartSize? valueTitle = titleSize(
      shown.valueTitle,
      chart.valueAxis.title,
    );
    final ChartSize? categoryTitle = titleSize(
      shown.categoryTitle,
      chart.categoryAxis.title,
    );

    _Bands bands = (left: 0, top: 0, right: 0, bottom: 0);
    ValueScale? scale;
    List<MeasuredLabel> labels = const <MeasuredLabel>[];
    for (int pass = 0; pass < 4; pass++) {
      final ChartRect plot = _deflate(inner, bands);
      final ValueScale next = scaleFor(_maxIntervals(plot));
      final List<MeasuredLabel> nextLabels = next == scale
          ? labels
          : tickLabels(next);
      final _Bands nextBands = _bandsFor(
        shown,
        nextLabels,
        _plan(shown, plot),
        valueTitle,
        categoryTitle,
      );
      final bool same = next == scale && nextBands == bands;
      scale = next;
      labels = nextLabels;
      bands = nextBands;
      if (same) {
        break;
      }
    }
    ChartRect plot = _deflate(inner, bands);
    // The next coarser step, while the tick labels collide.
    if (shown.valueLabels) {
      for (
        int intervals = _maxIntervals(plot) - 1;
        intervals >= 1 && !_valueLabelsFit(labels, scale!, plot);
        intervals--
      ) {
        final ValueScale coarser = scaleFor(intervals);
        if (coarser == scale) {
          continue;
        }
        scale = coarser;
        labels = tickLabels(coarser);
        bands = _bandsFor(
          shown,
          labels,
          _plan(shown, plot),
          valueTitle,
          categoryTitle,
        );
        plot = _deflate(inner, bands);
      }
    }
    final CategoryLabelPlan plan = _plan(shown, plot);
    final bool fits =
        plot.width >= 1 &&
        plot.height >= 1 &&
        (!shown.valueLabels || _valueLabelsFit(labels, scale!, plot)) &&
        (!shown.categoryLabels || plan.fits);
    if (fits) {
      if (valueTitle != null &&
          valueTitle.width > _titleSpan(inner, plot, rotated: !bar)) {
        return FrameAttempt(misfit: FramePart.valueTitle);
      }
      if (categoryTitle != null &&
          categoryTitle.width > _titleSpan(inner, plot, rotated: bar)) {
        return FrameAttempt(misfit: FramePart.categoryTitle);
      }
    }
    return FrameAttempt(
      fits: fits,
      title: title,
      legend: legend,
      inner: inner,
      plot: plot,
      scale: scale,
      valueLabels: labels,
      plan: plan,
    );
  }

  /// The most intervals of the value axis of [plot]; 1 when it has no length.

  int _maxIntervals(ChartRect plot) {
    final double length = bar ? plot.width : plot.height;
    return length > 0 ? provisionalMaxIntervals(length) : 1;
  }

  bool _valueLabelsFit(
    List<MeasuredLabel> labels,
    ValueScale scale,
    ChartRect plot,
  ) => valueLabelsFit(
    labels,
    scale,
    plot,
    horizontal: bar,
    minTextGap: theme.spacing.minTextGap,
  );

  CategoryLabelPlan _plan(FrameShown shown, ChartRect plot) =>
      shown.categoryLabels
      ? planCategoryLabels(
          categoryLabels,
          bar ? plot.height : plot.width,
          vertical: bar,
          spacing: theme.spacing,
        )
      : const CategoryLabelPlan(thickness: 0, fits: true);

  /// The bands around the plot for the tick [labels], the category [plan] and
  /// the axis titles.
  _Bands _bandsFor(
    FrameShown shown,
    List<MeasuredLabel> labels,
    CategoryLabelPlan plan,
    ChartSize? valueTitle,
    ChartSize? categoryTitle,
  ) {
    final bool ticks = shown.valueLabels && labels.isNotEmpty;
    final double valueTitleBand = valueTitle == null
        ? 0
        : valueTitle.height + gap;
    final double categoryTitleBand = categoryTitle == null
        ? 0
        : categoryTitle.height + gap;
    final double categoryBand = shown.categoryLabels ? plan.thickness + gap : 0;
    double widest = 0;
    double tallest = 0;
    for (final MeasuredLabel label in labels) {
      widest = math.max(widest, label.size.width);
      tallest = math.max(tallest, label.size.height);
    }
    if (bar) {
      return (
        left: math.max(
          categoryTitleBand + categoryBand,
          ticks ? labels.first.size.width / 2 : 0,
        ),
        top: 0,
        right: ticks ? labels.last.size.width / 2 : 0,
        bottom: valueTitleBand + (ticks ? tallest + gap : 0),
      );
    }
    return (
      left: valueTitleBand + (ticks ? widest + gap : 0),
      top: ticks ? labels.last.size.height / 2 : 0,
      right: 0,
      bottom: math.max(
        categoryTitleBand + categoryBand,
        ticks ? labels.first.size.height / 2 : 0,
      ),
    );
  }

  /// The length an axis title may take: a turned one (at the left) from the
  /// top of [inner] to the plot's bottom, a level one (at the bottom) the
  /// plot's width. Neither then reaches the other or the tick labels.
  double _titleSpan(ChartRect inner, ChartRect plot, {required bool rotated}) =>
      rotated ? plot.bottom - inner.top : plot.width;
}

ChartRect _deflate(ChartRect r, _Bands b) => ChartRect(
  r.left + b.left,
  r.top + b.top,
  r.width - b.left - b.right,
  r.height - b.top - b.bottom,
);
