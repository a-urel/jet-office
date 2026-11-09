/// The layout of pie and donut charts, on the polar frame (`polar.dart`).
library;

import 'dart:math' as math;

import 'package:jet_core/jet_core.dart';

import '../model/chart.dart';
import '../model/chart_kind.dart';
import '../model/chart_series.dart';
import '../theme/chart_color.dart';
import '../theme/chart_theme.dart';
import 'chart_ids.dart' as ids;
import 'frame_paint.dart' show backgroundPrimitive;
import 'geometry.dart';
import 'overlap.dart' show arcShapeClearance;
import 'pie_labels.dart';
import 'polar.dart';
import 'primitives.dart';
import 'resolve.dart';
import 'text_measurer.dart';

/// Each value's share of the whole: `|v| / Σ|v|` over the finite values
/// (a negative value counts as its absolute value, an estimate, not checked
/// in Excel), `null` for a missing or non-finite value, and every share
/// `null` when the sum is zero. The sum is taken of the values divided by
/// the largest, so that huge values do not overflow it.
List<double?> sliceShares(List<double?> values) {
  double largest = 0;
  for (final double? v in values) {
    if (v != null && v.isFinite) {
      largest = math.max(largest, v.abs());
    }
  }
  if (!(largest > 0)) {
    return List<double?>.filled(values.length, null);
  }
  double sum = 0;
  for (final double? v in values) {
    if (v != null && v.isFinite) {
      sum += v.abs() / largest;
    }
  }
  return <double?>[
    for (final double? v in values)
      v != null && v.isFinite ? (v.abs() / largest) / sum : null,
  ];
}

/// The colour of the slice of [series] at [category]: its point colour,
/// else [theme]'s colour of [category] (a pie of one series varies its
/// colours by category, in palette order: an estimate, not checked in
/// Excel).
ChartColor sliceColor(ChartSeries series, int category, ChartTheme theme) {
  final List<ChartColor?> points = series.pointColors;
  return (category < points.length ? points[category] : null) ??
      theme.seriesColor(category);
}

/// The text of a pie or donut data label of [value], whose share is
/// [share]: the value in the data labels' format code, else the series',
/// else `General`, as a column chart's data label; the share in `0%`; or
/// both on two lines, as [chart]'s data labels ask. `null` when they ask for
/// neither.
String? sliceLabelText(
  Chart chart,
  int series,
  double value,
  double share,
  NumberFormatter formatter,
) {
  final bool showValue = chart.dataLabels.showValue;
  final bool showPercent = chart.dataLabels.showPercent;
  if (!showValue && !showPercent) {
    return null;
  }
  final String code =
      chart.dataLabels.formatCode ??
      chart.series[series].formatCode ??
      'General';
  final String valueText = formatter.format(value, numberFormat: code).text;
  final String percentText = formatter.format(share, numberFormat: '0%').text;
  return showValue && showPercent
      ? '$valueText\n$percentText'
      : showValue
      ? valueText
      : percentText;
}

/// The laid out pie or donut: what to draw, what was left out, the plot.
typedef PieLayout = ({
  List<ChartPrimitive> primitives,
  List<(String, String)> hidden,
  ChartRect? plot,
});

/// Lays out [chart], a pie or a donut whose data is [resolved], on [size].
///
/// The frame is the polar frame (`layoutPolarFrame`): the legend lists the
/// categories (entry `i` is category `i`) in the colours of the first
/// series' slices, and the plot is the largest square of the space left.
/// The pie's radius is half the square less half the slice outline, so the
/// outline stays inside it.
///
/// A pie draws its first series; a donut every series as a ring, the first
/// innermost (an estimate, not checked in Excel), the rings of equal width
/// between the hole (`holeSizePercent` of the outer diameter) and the outer
/// radius. Each value with a share above 0 (`sliceShares`) is a slice, from
/// twelve o'clock clockwise (an estimate, not checked in Excel), filled in
/// its `sliceColor` and outlined in the theme's background colour,
/// `sliceBorderWidth` wide (none at 0). Paint order: background, title,
/// legend, the plot's rectangle, the slices, leader lines, the centre text,
/// data labels.
///
/// Data labels (when visible and showing the value or the percent) are
/// placed by `placePieLabels`; a slice whose share is below the data labels'
/// `minShare` has none. When a pie label could not stay inside its slice,
/// the radius shrinks once by that tallest label's height and `labelGap`,
/// to no less than half of it, and the slices and labels are laid out again.
///
/// A donut's centre text, in the theme's `centerTextStyle`, is drawn centred
/// when its box fits in the circle the slices leave free in the hole
/// (`arcShapeClearance` of the hole) shrunk by `minTextGap`: every corner
/// inside it, so a wide text may use more of the hole than its inscribed
/// square, and the text keeps `minTextGap` from the ring. Else it is hidden;
/// a pie draws none.
///
/// The hidden texts come in the order data labels, legend entries, title,
/// centre text. A chart too small for a square of 1 pt plus the outline
/// draws only its background and hides every text it asks for.
PieLayout layoutPie(
  Chart chart,
  ResolvedChart resolved, {
  required ChartTheme theme,
  required ChartSize size,
  required TextMeasurer measurer,
  required NumberFormatter formatter,
}) {
  final bool donut = chart.kind == ChartKind.donut;
  final int drawn = chart.series.isEmpty
      ? 0
      : donut
      ? chart.series.length
      : 1;
  final List<List<double?>> shares = <List<double?>>[
    for (int s = 0; s < drawn; s++) sliceShares(resolved.values[s]),
  ];
  final double border = theme.sliceBorderWidth;
  final bool outlined = border > 0;
  final double halfBorder = outlined ? border / 2 : 0;
  final String? centerText = donut && (chart.centerText ?? '').isNotEmpty
      ? chart.centerText
      : null;

  // The labels each slice asks for.
  final Map<(int, int), String> labelTexts = <(int, int), String>{};
  if (chart.dataLabels.visible) {
    for (int s = 0; s < drawn; s++) {
      for (int c = 0; c < resolved.categoryCount; c++) {
        final double? share = shares[s][c];
        final double? value = resolved.values[s][c];
        if (share == null ||
            value == null ||
            !(share > 0) ||
            share < chart.dataLabels.minShare) {
          continue;
        }
        final String? text = sliceLabelText(chart, s, value, share, formatter);
        if (text != null) {
          labelTexts[(s, c)] = text;
        }
      }
    }
  }
  List<(String, String)> allLabels() => <(String, String)>[
    for (final MapEntry<(int, int), String> e in labelTexts.entries)
      (ids.dataLabelId(e.key.$1, e.key.$2), e.value),
  ];

  final String? title = chart.title?.text;
  final List<String> names = resolved.categoryLabels;
  final PolarFrame? frame = layoutPolarFrame(
    title: title,
    names: names,
    colors: <ChartColor>[
      for (int c = 0; c < names.length; c++)
        chart.series.isEmpty
            ? theme.seriesColor(c)
            : sliceColor(chart.series.first, c, theme),
    ],
    position: chart.legend.position,
    legendVisible: chart.legend.visible,
    theme: theme,
    size: size,
    measurer: measurer,
    minSide: 1 + 2 * halfBorder,
  );
  List<(String, String)> hiddenFrame({
    required bool legend,
    required bool t,
  }) => <(String, String)>[
    if (!legend && chart.legend.visible)
      for (int c = 0; c < names.length; c++) (ids.legendTextId(c), names[c]),
    if (!t && title != null && title.isNotEmpty) (ids.title, title),
  ];
  if (frame == null) {
    return (
      primitives: <ChartPrimitive>[backgroundPrimitive(theme, size)],
      hidden: <(String, String)>[
        ...allLabels(),
        ...hiddenFrame(legend: false, t: false),
        if (centerText != null) (ids.centerTextId, centerText),
      ],
      plot: null,
    );
  }

  final ChartPoint center = frame.center;
  List<PieSlice> slicesFor(double radius) {
    final double hole = donut ? radius * chart.holeSizePercent / 100 : 0;
    final double ring = drawn == 0 ? 0 : (radius - hole) / drawn;
    final List<PieSlice> out = <PieSlice>[];
    for (int s = 0; s < drawn; s++) {
      final double inner = donut ? hole + s * ring : 0;
      final double outer = donut ? hole + (s + 1) * ring : radius;
      double clock = 0;
      for (int c = 0; c < resolved.categoryCount; c++) {
        final double? share = shares[s][c];
        if (share == null || !(share > 0)) {
          continue;
        }
        final double sweep = share * 360;
        out.add(
          PieSlice(
            series: s,
            category: c,
            startClock: clock,
            sweep: sweep,
            label: labelTexts[(s, c)],
            arc: ArcPrimitive(
              ids.seriesSliceId(s, c),
              center,
              outer,
              inner,
              arcAngle(clock),
              sweep,
              fill: sliceColor(chart.series[s], c, theme),
              stroke: outlined ? theme.background : null,
              strokeWidth: outlined ? border : 1,
            ),
          ),
        );
        clock += sweep;
      }
    }
    return out;
  }

  // The centre text.
  final double fullRadius = frame.square.width / 2 - halfBorder;
  TextPrimitive? centerPrimitive;
  if (centerText != null) {
    final double clear = arcShapeClearance(
      fullRadius * chart.holeSizePercent / 100,
      border,
      stroked: outlined,
    );
    final ChartSize s = measurer.measure(centerText, theme.centerTextStyle);
    // The box fits when its corners lie within the free circle shrunk by
    // the minimum text gap: its half diagonal is no longer than that radius.
    final double room = clear - theme.spacing.minTextGap;
    if (room > 0 &&
        s.width * s.width + s.height * s.height <= 4 * room * room) {
      centerPrimitive = TextPrimitive(
        ids.centerTextId,
        centerText,
        ChartRect(
          center.x - s.width / 2,
          center.y - s.height / 2,
          s.width,
          s.height,
        ),
        theme.centerTextStyle,
      );
    }
  }

  _Attempt attempt(double radius) {
    final List<PieSlice> slices = slicesFor(radius);
    final PieLabelPlacement labels = placePieLabels(
      slices: slices,
      center: center,
      bounds: frame.rest,
      existing: <ChartPrimitive>[
        ...frame.primitives,
        for (final PieSlice slice in slices) slice.arc,
        ?centerPrimitive,
      ],
      outside: !donut,
      theme: theme,
      measurer: measurer,
    );
    return (slices: slices, labels: labels, radius: radius);
  }

  _Attempt result = attempt(fullRadius);
  final double? tallest = result.labels.tallestOutside;
  if (tallest != null) {
    result = attempt(
      math.max(fullRadius / 2, fullRadius - tallest - theme.spacing.labelGap),
    );
  }
  final double reach = result.radius + halfBorder;
  final ChartRect plot = result.radius == fullRadius
      ? frame.square
      : ChartRect(center.x - reach, center.y - reach, 2 * reach, 2 * reach);
  return (
    primitives: <ChartPrimitive>[
      backgroundPrimitive(theme, size),
      ...frame.primitives,
      RectPrimitive(ids.plot, plot),
      for (final PieSlice slice in result.slices) slice.arc,
      ...result.labels.leaders,
      ?centerPrimitive,
      ...result.labels.labels,
    ],
    hidden: <(String, String)>[
      ...result.labels.hidden,
      ...hiddenFrame(legend: frame.legend, t: frame.title),
      if (centerText != null && centerPrimitive == null)
        (ids.centerTextId, centerText),
    ],
    plot: plot,
  );
}

/// One try at a pie's slices and labels at a radius.
typedef _Attempt = ({
  List<PieSlice> slices,
  PieLabelPlacement labels,
  double radius,
});
