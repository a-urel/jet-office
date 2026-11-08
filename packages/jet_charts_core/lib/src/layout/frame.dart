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
/// intervals come from the plot's length and the tick labels' font size
/// (`excelMaxIntervals`, fitted on the owner's full Excel run), the
/// tick labels from the scale, and the bands from the labels. [layoutFrame]
/// starts from the plot without bands and repeats until the scale and bands
/// stay the same, at most 12 passes, keeping the last: the first four take
/// the bands each pass needs, and from the fifth the bands only widen, so the
/// plot only shrinks and the passes settle. When adjacent tick labels would
/// then come closer than `minTextGap`, it asks for fewer intervals until they
/// fit or only one is left: the next coarser step. A fixed major unit cannot
/// be coarsened, so its tick labels are thinned instead: every k-th is drawn,
/// from the first, for the smallest k that fits, with every grid line kept.
/// Excel lets such labels collide; taking the coarser step or thinning is a
/// deliberate difference (Task 11 lists it in `docs/parity.md`).
library;

import 'dart:math' as math;

import 'package:jet_core/jet_core.dart';

import '../model/chart.dart';
import '../model/chart_kind.dart';
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

/// Where the frame put the plot and its scale.
final class FrameGeometry {
  /// Creates the geometry of a laid out frame.
  const FrameGeometry({required this.plot, required this.scale});

  /// The plot area.
  final ChartRect plot;

  /// The value axis' scale.
  final ValueScale scale;
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

  /// The texts the frame hid, as id and text, grouped in the order of
  /// [DegradeStep].
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
  while (true) {
    final FrameAttempt attempt = frame.attempt(shown);
    if (attempt.misfit != null) {
      shown.hide(attempt.misfit!);
      continue;
    }
    if (attempt.misfits.isEmpty) {
      final painted = frame.paint(attempt, shown);
      return FrameLayout(
        primitives: painted.primitives,
        hidden: frame.hiddenTexts(wanted, shown, attempt, painted.hiddenData),
        geometry: FrameGeometry(plot: attempt.plot!, scale: attempt.scale!),
      );
    }
    DegradeStep? next;
    for (final DegradeStep step in DegradeStep.values) {
      if (shown.relieves(
        step,
        attempt.misfits,
        bar: frame.bar,
        legendPosition: chart.legend.position,
      )) {
        next = step;
        break;
      }
    }
    if (next == null) {
      shown.hideAll();
      return FrameLayout(
        primitives: <ChartPrimitive>[frame.background()],
        hidden: frame.hiddenTexts(
          wanted,
          shown,
          attempt,
          const <(String, String)>[],
        ),
      );
    }
    shown.take(next);
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
    _Bands need(List<MeasuredLabel> labels, ChartRect plot) => _bandsFor(
      inner,
      shown,
      labels,
      _plan(shown, inner, plot, labels, valueTitle, categoryTitle),
      valueTitle,
      categoryTitle,
    );
    // At most 12 passes: from the fifth the bands only widen, so the plot
    // only shrinks and the passes settle.
    for (int pass = 0; pass < 12; pass++) {
      final ChartRect plot = _deflate(inner, bands);
      final ValueScale next = scaleFor(_maxIntervals(plot));
      final List<MeasuredLabel> nextLabels = next == scale
          ? labels
          : tickLabels(next);
      final _Bands needed = need(nextLabels, plot);
      final _Bands nextBands = pass < 4 ? needed : _widest(bands, needed);
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
        bands = need(labels, plot);
        plot = _deflate(inner, bands);
      }
    }
    // The category labels' plan on the final plot must fit the bands kept
    // for it; widen them a few times if not.
    CategoryLabelPlan plan = _plan(
      shown,
      inner,
      plot,
      labels,
      valueTitle,
      categoryTitle,
    );
    bool settled = false;
    for (int i = 0; i < 4; i++) {
      final _Bands needed = _bandsFor(
        inner,
        shown,
        labels,
        plan,
        valueTitle,
        categoryTitle,
      );
      if (_within(needed, bands)) {
        settled = true;
        break;
      }
      bands = _widest(bands, needed);
      plot = _deflate(inner, bands);
      plan = _plan(shown, inner, plot, labels, valueTitle, categoryTitle);
    }
    // A fixed unit cannot be coarsened: draw every stride-th tick label
    // instead, the smallest stride whose labels keep apart and stay inside
    // [inner] (the bands cover the first and last label, not a wider one
    // thinning keeps between them).
    final ValueScale finalScale = scale!;
    int stride = 1;
    bool valueLabelsFit() =>
        _valueLabelsFit(labels, finalScale, plot, stride: stride) &&
        (!fixedUnit ||
            _valueLabelsInside(labels, finalScale, plot, inner, stride));
    if (shown.valueLabels && fixedUnit) {
      while (stride < labels.length && !valueLabelsFit()) {
        stride++;
      }
    }
    final Set<FrameMisfit> misfits = <FrameMisfit>{
      if (!settled || !(plot.width >= 1 && plot.height >= 1)) FrameMisfit.space,
      if (shown.valueLabels && !valueLabelsFit()) FrameMisfit.valueLabels,
      if (shown.categoryLabels && !plan.fits)
        plan.cramped ? FrameMisfit.categoryRoom : FrameMisfit.categoryLabels,
    };
    if (misfits.isEmpty) {
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
      misfits: misfits,
      title: title,
      legend: legend,
      inner: inner,
      plot: plot,
      scale: scale,
      valueLabels: labels,
      valueStride: stride,
      plan: plan,
      categoryOffset: _categoryOffset(shown, labels, plan),
    );
  }

  /// The most intervals of the value axis of [plot]; 1 when it has no length.
  /// A theme's tick label size that is not a finite positive number is read
  /// as 0, so layout never throws on it.
  int _maxIntervals(ChartRect plot) {
    final double length = bar ? plot.width : plot.height;
    final double size = theme.axisLabels.size;
    return length > 0
        ? excelMaxIntervals(
            length,
            horizontal: bar,
            fontSize: size.isFinite && size > 0 ? size : 0,
          )
        : 1;
  }

  bool _valueLabelsFit(
    List<MeasuredLabel> labels,
    ValueScale scale,
    ChartRect plot, {
    int stride = 1,
  }) => valueLabelsFit(
    labels,
    scale,
    plot,
    horizontal: bar,
    minTextGap: theme.spacing.minTextGap,
    stride: stride,
  );

  /// Whether every [stride]-th tick label, from the first, lies inside
  /// [inner].
  bool _valueLabelsInside(
    List<MeasuredLabel> labels,
    ValueScale scale,
    ChartRect plot,
    ChartRect inner,
    int stride,
  ) {
    for (final TextPrimitive label in valueLabelPrimitives(
      labels,
      scale,
      plot,
      theme.axisLabels,
      horizontal: bar,
      labelGap: gap,
      stride: stride,
    )) {
      final ChartRect r = label.rect;
      if (r.left < inner.left - 1e-9 ||
          r.top < inner.top - 1e-9 ||
          r.right > inner.right + 1e-9 ||
          r.bottom > inner.bottom + 1e-9) {
        return false;
      }
    }
    return true;
  }

  /// The category labels' plan on [plot], whose band may take 40% of the
  /// space left for the plot and the band across the category axis: [inner]
  /// less the category title's band and the tick labels' overhang at the
  /// far end, less the label gap (or the larger offset of
  /// [_categoryOffset]).
  CategoryLabelPlan _plan(
    FrameShown shown,
    ChartRect inner,
    ChartRect plot,
    List<MeasuredLabel> labels,
    ChartSize? valueTitle,
    ChartSize? categoryTitle,
  ) {
    if (!shown.categoryLabels) {
      return CategoryLabelPlan.none();
    }
    double widest = 0;
    for (final MeasuredLabel label in labels) {
      widest = math.max(widest, label.size.width);
    }
    final (double edgeBefore, double edgeAfter) = _edges(shown, inner);
    // The room before the axis' start: past [inner], the edge room; inside
    // it, the band the tick labels and the value title make, and (for turned
    // labels and a bar chart) what the frame keeps for the plan's reserve.
    final double turnedRoom =
        edgeBefore +
        (bar ? inner.bottom - plot.bottom : plot.left - inner.left);
    final double room = bar
        ? turnedRoom
        : math.min(
            turnedRoom,
            edgeBefore +
                (valueTitle == null ? 0 : valueTitle.height + gap) +
                (shown.valueLabels && labels.isNotEmpty ? widest + gap : 0),
          );
    final bool ticks = shown.valueLabels && labels.isNotEmpty;
    final double overhang = !ticks
        ? 0
        : bar
        ? labels.last.size.width / 2
        : labels.last.size.height / 2;
    final double titleBand = categoryTitle == null
        ? 0
        : categoryTitle.height + gap;
    final double cross =
        (bar ? inner.width : inner.height) - overhang - titleBand;
    return planCategoryLabels(
      categoryLabels,
      bar ? plot.height : plot.width,
      maxDepth: 0.4 * cross - _largestOffset(shown, labels),
      roomBefore: room,
      turnedRoomBefore: turnedRoom,
      roomAfter:
          edgeAfter + (bar ? plot.top - inner.top : inner.right - plot.right),
      vertical: bar,
      spacing: theme.spacing,
      measurer: measurer,
      style: theme.axisLabels,
    );
  }

  /// The room past [inner] before the category axis' start and past its
  /// end that category labels may reach into: the chart's padding, or
  /// beside a legend (or, above a bar chart's plot, under the title) its gap
  /// less `minTextGap`. Nothing else stands there in the labels' way: under
  /// a column chart's plot the turned value title ends at the plot's bottom,
  /// and beside a bar chart's plot the value title starts at its left.
  (double, double) _edges(FrameShown shown, ChartRect inner) {
    final ChartLegendPosition? legend = shown.legend
        ? chart.legend.position
        : null;
    double beside(double gapToIt) =>
        math.max(0, gapToIt - theme.spacing.minTextGap);
    if (bar) {
      return (
        legend == ChartLegendPosition.bottom
            ? beside(theme.spacing.legendGap)
            : size.height - inner.bottom,
        legend == ChartLegendPosition.top
            ? beside(theme.spacing.legendGap)
            : shown.title
            ? beside(theme.spacing.titleGap)
            : inner.top,
      );
    }
    return (
      legend == ChartLegendPosition.left
          ? beside(theme.spacing.legendGap)
          : inner.left,
      legend == ChartLegendPosition.right
          ? beside(theme.spacing.legendGap)
          : size.width - inner.right,
    );
  }

  /// The category labels' offset from the plot when they reach past the
  /// axis' start under the first tick label: clear of that label.
  double _largestOffset(FrameShown shown, List<MeasuredLabel> labels) {
    if (!shown.valueLabels || labels.isEmpty) {
      return gap;
    }
    final ChartSize first = labels.first.size;
    return math.max(
      gap,
      (bar ? first.width : first.height) / 2 + theme.spacing.minTextGap,
    );
  }

  /// The category labels' offset from the plot: the label gap, or clear of
  /// the first tick label (at the axis' start) when [plan]'s labels reach
  /// further than the label gap past that start.
  double _categoryOffset(
    FrameShown shown,
    List<MeasuredLabel> labels,
    CategoryLabelPlan plan,
  ) => plan.before > gap ? _largestOffset(shown, labels) : gap;

  /// The bands around the plot for the tick [labels], the category [plan] and
  /// the axis titles. The category labels' reach past the axis' ends stays
  /// within those bands and the edge room past [inner] (`_edges`); the band
  /// before the axis' start widens to what the labels'
  /// [CategoryLabelPlan.reserveBefore] needs beyond the edge room.
  _Bands _bandsFor(
    ChartRect inner,
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
    final double categoryBand = shown.categoryLabels
        ? _categoryOffset(shown, labels, plan) + plan.thickness
        : 0;
    double widest = 0;
    double tallest = 0;
    for (final MeasuredLabel label in labels) {
      widest = math.max(widest, label.size.width);
      tallest = math.max(tallest, label.size.height);
    }
    // What the plan's reserve needs inside [inner] past the edge room.
    final double reserve = shown.categoryLabels
        ? plan.reserveBefore - _edges(shown, inner).$1
        : 0;
    if (bar) {
      return (
        left: math.max(
          categoryTitleBand + categoryBand,
          ticks ? labels.first.size.width / 2 : 0,
        ),
        top: 0,
        right: ticks ? labels.last.size.width / 2 : 0,
        bottom: math.max(valueTitleBand + (ticks ? tallest + gap : 0), reserve),
      );
    }
    return (
      left: math.max(valueTitleBand + (ticks ? widest + gap : 0), reserve),
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

/// Each side of [a] and [b], the larger.
_Bands _widest(_Bands a, _Bands b) => (
  left: math.max(a.left, b.left),
  top: math.max(a.top, b.top),
  right: math.max(a.right, b.right),
  bottom: math.max(a.bottom, b.bottom),
);

/// Whether no side of [a] is wider than that of [b].
bool _within(_Bands a, _Bands b) =>
    a.left <= b.left + 1e-9 &&
    a.top <= b.top + 1e-9 &&
    a.right <= b.right + 1e-9 &&
    a.bottom <= b.bottom + 1e-9;

ChartRect _deflate(ChartRect r, _Bands b) => ChartRect(
  r.left + b.left,
  r.top + b.top,
  r.width - b.left - b.right,
  r.height - b.top - b.bottom,
);
