/// The `JetChart` widget: a chart laid out by `jet_charts_core` and painted
/// on a canvas, with its loading, empty and error states.
library;

import 'package:flutter/widgets.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_core/jet_core.dart';

import 'chart_layout_painter.dart';
import 'states.dart';
import 'strings.dart';
import 'text_measurer.dart';

/// Builds the look of a state of [JetChart] (loading or empty) in its
/// [theme], filling the chart's size.
typedef JetChartStateBuilder =
    Widget Function(BuildContext context, ChartTheme theme);

/// Builds the error look of [JetChart] for [error] in its [theme], filling
/// the chart's size.
typedef JetChartErrorBuilder =
    Widget Function(BuildContext context, ChartTheme theme, Object error);

/// A chart: [chart] laid out with `layoutChart` in [theme] and painted.
///
/// It shows one of four looks, in this order: the error look when [error] is
/// not `null`; the loading look when [loading]; the empty look when [chart]
/// is `null` or has no finite value (`summarizeChart`); else the chart. A kind
/// the layout does not draw yet (a pie in this version) shows the layout's
/// placeholder, not the empty look.
///
/// **Size.** A bounded side of the constraints is used as is. An unbounded
/// width is 360 (Excel's 5 inch default), or the height divided by 0.6 when
/// the height is bounded; an unbounded height is 216, or the width times 0.6
/// when the width is bounded. The result is then fitted to the constraints'
/// minimums. A size with no area paints nothing.
///
/// **Text.** Text is measured and drawn with a `FlutterTextMeasurer` that
/// scales by `MediaQuery.textScalerOf`, so a user's larger text size gives
/// larger text, laid out again without overlap.
///
/// **Screen readers.** The chart is one node whose label is
/// [JetChartStrings.describe] of the chart's summary (its kind and title, its
/// series and categories, its value range and its values), with
/// [semanticsLabel] in place of the first sentence when given. Each default
/// state look is a node of its string.
final class JetChart extends StatefulWidget {
  /// Creates a chart widget.
  const JetChart({
    super.key,
    this.chart,
    this.theme,
    this.locale = FormatLocale.enUS,
    this.strings = JetChartStrings.en,
    this.loading = false,
    this.error,
    this.tooltips = true,
    this.animationDuration = const Duration(milliseconds: 300),
    this.loadingBuilder,
    this.emptyBuilder,
    this.errorBuilder,
    this.semanticsLabel,
  });

  /// The chart to draw, or `null` for the empty look.
  final Chart? chart;

  /// The look; `null` is `ChartTheme.office`.
  final ChartTheme? theme;

  /// The locale numbers and dates are formatted for, in the chart and in its
  /// description.
  final FormatLocale locale;

  /// The texts of the state looks and of the description.
  final JetChartStrings strings;

  /// Whether the data is still loading; shows the loading look unless
  /// [error] is set.
  final bool loading;

  /// What went wrong, or `null`; any value shows the error look. The error
  /// look never shows the object, only [JetChartStrings.error]; an
  /// [errorBuilder] receives it.
  final Object? error;

  /// Whether hovering or tapping the chart shows tooltips. Hover and tap are
  /// wired in a later version; the value is kept for them.
  final bool tooltips;

  /// How long a change of [chart] animates. Animation is wired in a later
  /// version; the value is kept for it.
  final Duration animationDuration;

  /// Replaces the default loading look, or `null` for the default. It
  /// replaces the look entirely, its semantics too.
  final JetChartStateBuilder? loadingBuilder;

  /// Replaces the default empty look, or `null` for the default. It replaces
  /// the look entirely, its semantics too.
  final JetChartStateBuilder? emptyBuilder;

  /// Replaces the default error look, or `null` for the default. It replaces
  /// the look entirely, its semantics too.
  final JetChartErrorBuilder? errorBuilder;

  /// What a screen reader reads in place of the description's first
  /// sentence (the kind and title), or `null` to keep it.
  final String? semanticsLabel;

  @override
  State<JetChart> createState() => JetChartState();
}

/// The size of a [JetChart] under [constraints]: see "Size" on [JetChart].
Size _chartSize(BoxConstraints constraints) {
  final bool wide = constraints.hasBoundedWidth;
  final bool tall = constraints.hasBoundedHeight;
  final double width;
  final double height;
  if (wide && tall) {
    width = constraints.maxWidth;
    height = constraints.maxHeight;
  } else if (wide) {
    width = constraints.maxWidth;
    height = width * 0.6;
  } else if (tall) {
    height = constraints.maxHeight;
    width = height / 0.6;
  } else {
    width = 360;
    height = 216;
  }
  return constraints.constrain(Size(width, height));
}

/// The state of [JetChart]: it owns the text measurer and caches the summary
/// and the layout.
///
/// Not exported; tests reach it through its library.
final class JetChartState extends State<JetChart> {
  FlutterTextMeasurer? _measurer;

  ChartSummary? _summary;
  Chart? _summaryChart;
  FormatLocale? _summaryLocale;

  ChartLayout? _layout;
  Chart? _layoutChart;
  ChartTheme? _layoutTheme;
  Size? _layoutSize;
  FormatLocale? _layoutLocale;
  TextScaler? _layoutScaler;
  int _layoutCount = 0;

  /// The layout the chart paints, or `null` while a state look shows or the
  /// size has no area.
  @visibleForTesting
  ChartLayout? get currentLayout => _layout;

  /// How many times this state has laid the chart out.
  @visibleForTesting
  int get layoutCount => _layoutCount;

  @override
  void dispose() {
    _measurer?.dispose();
    super.dispose();
  }

  /// The measurer for [scaler], a new one (and the old one disposed) when the
  /// scaler changed, as the measurer's cache does not key on it.
  FlutterTextMeasurer _measurerFor(TextScaler scaler) {
    final FlutterTextMeasurer? current = _measurer;
    if (current != null && current.textScaler == scaler) {
      return current;
    }
    current?.dispose();
    return _measurer = FlutterTextMeasurer(textScaler: scaler);
  }

  ChartSummary _summaryOf(Chart chart, FormatLocale locale) {
    final ChartSummary? cached = _summary;
    if (cached != null && _summaryChart == chart && _summaryLocale == locale) {
      return cached;
    }
    _summaryChart = chart;
    _summaryLocale = locale;
    return _summary = summarizeChart(chart, locale: locale);
  }

  ChartLayout _layoutOf(
    Chart chart,
    ChartTheme theme,
    Size size,
    TextScaler scaler,
    FlutterTextMeasurer measurer,
  ) {
    final ChartLayout? cached = _layout;
    if (cached != null &&
        _layoutChart == chart &&
        _layoutTheme == theme &&
        _layoutSize == size &&
        _layoutLocale == widget.locale &&
        _layoutScaler == scaler) {
      return cached;
    }
    _layoutChart = chart;
    _layoutTheme = theme;
    _layoutSize = size;
    _layoutLocale = widget.locale;
    _layoutScaler = scaler;
    _layoutCount++;
    return _layout = layoutChart(
      chart,
      theme: theme,
      size: ChartSize(size.width, size.height),
      measurer: measurer,
      locale: widget.locale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ChartTheme theme = widget.theme ?? ChartTheme.office;
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final FlutterTextMeasurer measurer = _measurerFor(scaler);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = _chartSize(constraints);
        return SizedBox(
          width: size.width,
          height: size.height,
          child: _look(context, theme, scaler, measurer, size),
        );
      },
    );
  }

  Widget _look(
    BuildContext context,
    ChartTheme theme,
    TextScaler scaler,
    FlutterTextMeasurer measurer,
    Size size,
  ) {
    final JetChartStrings strings = widget.strings;
    final Object? error = widget.error;
    final Chart? chart = widget.chart;
    if (error != null) {
      _layout = null;
      return widget.errorBuilder?.call(context, theme, error) ??
          MessageLook(theme: theme, measurer: measurer, message: strings.error);
    }
    if (widget.loading) {
      _layout = null;
      return widget.loadingBuilder?.call(context, theme) ??
          LoadingLook(theme: theme, label: strings.loading);
    }
    final ChartSummary? summary = chart == null
        ? null
        : _summaryOf(chart, widget.locale);
    if (chart == null || summary == null || summary.isEmpty) {
      _layout = null;
      return widget.emptyBuilder?.call(context, theme) ??
          MessageLook(
            theme: theme,
            measurer: measurer,
            message: strings.empty,
            title: summary?.title,
          );
    }
    final List<String> sentences = strings.sentences(summary);
    final String? custom = widget.semanticsLabel;
    if (custom != null) {
      sentences[0] = custom;
    }
    final Widget paint;
    if (size.isEmpty) {
      _layout = null;
      paint = const SizedBox.expand();
    } else {
      final ChartLayout layout = _layoutOf(
        chart,
        theme,
        size,
        scaler,
        measurer,
      );
      paint = CustomPaint(
        size: size,
        painter: ChartLayoutPainter(
          primitives: layout.primitives,
          measurer: measurer,
        ),
      );
    }
    return Semantics(
      container: true,
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      label: sentences.join(' '),
      child: ExcludeSemantics(child: paint),
    );
  }
}
