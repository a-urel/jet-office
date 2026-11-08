/// The layout's entry point: [layoutChart] turns a chart, a theme and a size
/// into primitives, a [ChartLayout].
library;

import 'package:jet_core/jet_core.dart';

import '../model/chart.dart';
import '../model/chart_kind.dart';
import '../model/equality.dart';
import '../scale/value_scale.dart';
import '../theme/chart_theme.dart';
import 'chart_ids.dart' as ids;
import 'frame.dart';
import 'geometry.dart';
import 'legend_layout.dart';
import 'primitives.dart';
import 'resolve.dart';
import 'text_measurer.dart';

/// A text the layout did not draw, kept so a tooltip can still show it.
final class ChartHiddenLabel {
  /// Creates a hidden label of [text] that would have had the primitive [id].
  const ChartHiddenLabel(this.id, this.text);

  /// The id the text's primitive would have had (`chart_ids.dart`'s scheme).
  final String id;

  /// The text.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is ChartHiddenLabel && id == other.id && text == other.text;

  @override
  int get hashCode => Object.hash(id, text);

  @override
  String toString() => 'ChartHiddenLabel($id, "$text")';
}

/// A laid out chart: what to draw on a size, and what was left out.
final class ChartLayout {
  /// Creates a layout; the lists are copied into unmodifiable ones.
  ChartLayout({
    required this.size,
    required List<ChartPrimitive> primitives,
    this.plotArea,
    this.valueScale,
    List<ChartHiddenLabel> hidden = const <ChartHiddenLabel>[],
  }) : primitives = List<ChartPrimitive>.unmodifiable(primitives),
       hidden = List<ChartHiddenLabel>.unmodifiable(hidden);

  /// The size laid out on.
  final ChartSize size;

  /// What to draw, in paint order: the first is the `background` rectangle,
  /// which covers the size exactly.
  final List<ChartPrimitive> primitives;

  /// The plot area, or `null` when there is none: a kind this version does
  /// not draw, or a chart too small for one.
  final ChartRect? plotArea;

  /// The value axis' scale, or `null` when there is no plot area.
  final ValueScale? valueScale;

  /// The texts left out because they did not fit, in the order they were
  /// taken away.
  final List<ChartHiddenLabel> hidden;

  @override
  bool operator ==(Object other) =>
      other is ChartLayout &&
      size == other.size &&
      plotArea == other.plotArea &&
      valueScale == other.valueScale &&
      listValueEquals(primitives, other.primitives) &&
      listValueEquals(hidden, other.hidden);

  @override
  int get hashCode => Object.hash(
    size,
    plotArea,
    valueScale,
    listValueHash(primitives),
    listValueHash(hidden),
  );

  @override
  String toString() =>
      'ChartLayout($size, ${primitives.length} primitives, '
      '${hidden.length} hidden)';
}

/// Lays out [chart] with [theme] on [size], measuring text with [measurer]
/// and formatting labels for [locale].
///
/// Column, bar, line and area charts get a frame: background, title, legend,
/// axis titles, tick and category labels, grid lines, axis lines and the plot.
/// Every other kind draws the background, the title if any, and a
/// `placeholder` text of the chart's `unsupportedName`, else its kind's name,
/// centred in what is left; the placeholder is hidden when it does not fit.
///
/// Content that does not fit is taken away in a fixed order (data labels,
/// legend, axis titles, title, category labels, value labels) and listed in
/// [ChartLayout.hidden]; a chart too small for a 1 by 1 plot draws only its
/// background. No text overlaps another and every primitive lies inside
/// [size].
///
/// Throws an [ArgumentError] for a negative or non-finite size. Bad data,
/// tiny sizes and unknown kinds never throw.
ChartLayout layoutChart(
  Chart chart, {
  required ChartTheme theme,
  required ChartSize size,
  required TextMeasurer measurer,
  FormatLocale locale = FormatLocale.enUS,
}) {
  for (final (String name, double value) in <(String, double)>[
    ('size.width', size.width),
    ('size.height', size.height),
  ]) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(value, name, 'must be finite and not negative');
    }
  }
  final NumberFormatter formatter = NumberFormatter(locale: locale);
  switch (chart.kind) {
    case ChartKind.column:
    case ChartKind.bar:
    case ChartKind.line:
    case ChartKind.area:
      final FrameLayout frame = layoutFrame(
        chart,
        resolveChart(chart, theme, formatter),
        theme: theme,
        size: size,
        measurer: measurer,
        formatter: formatter,
      );
      return ChartLayout(
        size: size,
        primitives: frame.primitives,
        plotArea: frame.geometry?.plot,
        valueScale: frame.geometry?.scale,
        hidden: <ChartHiddenLabel>[
          for (final (String id, String text) in frame.hidden)
            ChartHiddenLabel(id, text),
        ],
      );
    case ChartKind.pie:
    case ChartKind.donut:
    case ChartKind.scatter:
    case ChartKind.sparkline:
    case ChartKind.combination:
    case ChartKind.unsupported:
      return _placeholder(chart, theme, size, measurer);
  }
}

/// The picture of a kind this version does not draw.
ChartLayout _placeholder(
  Chart chart,
  ChartTheme theme,
  ChartSize size,
  TextMeasurer measurer,
) {
  final List<ChartPrimitive> primitives = <ChartPrimitive>[
    RectPrimitive(
      ids.background,
      ChartRect(0, 0, size.width, size.height),
      fill: theme.background,
    ),
  ];
  final List<ChartHiddenLabel> hidden = <ChartHiddenLabel>[];
  final double p = theme.spacing.padding;
  ChartRect area = ChartRect(p, p, size.width - 2 * p, size.height - 2 * p);
  final String title = chart.title?.text ?? '';
  if (title.isNotEmpty) {
    final Placed? placed = area.width > 0 && area.height > 0
        ? placeTitle(title, area, theme.titleText, measurer, theme.spacing)
        : null;
    if (placed == null) {
      hidden.add(ChartHiddenLabel(ids.title, title));
    } else {
      primitives.addAll(placed.primitives);
      area = placed.rest;
    }
  }
  final String text = chart.unsupportedName ?? chart.kind.name;
  final ChartSize s = measurer.measure(text, theme.axisLabels);
  if (s.width <= area.width && s.height <= area.height) {
    primitives.add(
      TextPrimitive(
        ids.placeholder,
        text,
        ChartRect(
          area.left + (area.width - s.width) / 2,
          area.top + (area.height - s.height) / 2,
          s.width,
          s.height,
        ),
        theme.axisLabels,
      ),
    );
  } else {
    hidden.add(ChartHiddenLabel(ids.placeholder, text));
  }
  return ChartLayout(size: size, primitives: primitives, hidden: hidden);
}
