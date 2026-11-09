/// The `JetChart` widget: a chart laid out by `jet_charts_core` and painted
/// on a canvas, with its loading, empty and error states.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_core/jet_core.dart';

import 'chart_layout_painter.dart';
import 'interaction.dart';
import 'states.dart';
import 'strings.dart';
import 'text_measurer.dart';
import 'tooltip_view.dart';

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
///
/// **Hover and touch.** A mouse over the chart finds the primitives within 2
/// pixels of it (`hitTestLayout`) and shows the tooltip there
/// (`chartTooltipAt`) in a box of the theme's `ChartTheme.tooltip` look; it
/// reports the topmost hit to [onHover], and `null` when it leaves. A tap
/// reports its hit to [onTap]. A tap of a touch (or a stylus) finds within 8
/// pixels and toggles the box: a tap where there is a tooltip shows it, and a
/// tap where there is none, or anywhere outside the chart (`TapRegion`),
/// closes it. With [tooltips] `false` no box shows, and the callbacks are
/// still called.
///
/// The box sits 12 pixels right of and below the pointer, and on the other
/// side of it when it would leave the chart. Under an `Overlay` it is shown in
/// that overlay (`OverlayPortal`), so it may extend past a small chart, kept
/// inside the overlay; with no `Overlay` above the chart it is drawn over the
/// chart and kept inside it. It is a live region for screen readers.
///
/// When the chart, its size, its theme or its locale changes while the box
/// shows, the tooltip is found again at the same pointer position in the new
/// layout, and the box closes when there is none there. No state look shows
/// a box.
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
    this.onHover,
    this.onTap,
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

  /// Whether hovering or tapping the chart shows a tooltip box. When `false`,
  /// [onHover] and [onTap] are still called, their hits with the tooltip.
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
  /// sentence (the kind and title), or `null` to keep it. A full stop is
  /// added when it does not end in `.`, `!`, `?` or `…`.
  final String? semanticsLabel;

  /// Called with the topmost hit as a mouse moves over the chart, and with
  /// `null` when it leaves.
  final ValueChanged<JetChartHit?>? onHover;

  /// Called with the hit of a tap on the chart.
  final ValueChanged<JetChartHit>? onTap;

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

/// [label] with a full stop added unless it ends in `.`, `!`, `?` or `…`,
/// so it does not run into the next sentence.
String _closed(String label) {
  final String trimmed = label.trimRight();
  if (trimmed.isEmpty || <String>['.', '!', '?', '…'].any(trimmed.endsWith)) {
    return trimmed;
  }
  return '$trimmed.';
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

  /// Shows the tooltip box in the nearest `Overlay`, when there is one. It is
  /// shown once and for all; the box's widget is empty while no tooltip is
  /// open.
  final OverlayPortalController _portal = OverlayPortalController();

  /// The open tooltip, or `null` when the box is closed; with the pointer
  /// position it was found at, the tolerance it was found with and the
  /// layout it was found in.
  ChartTooltip? _tip;
  Offset _tipPointer = Offset.zero;
  double _tipTolerance = mouseTolerance;
  ChartLayout? _tipLayout;

  /// The layout the chart paints, or `null` while a state look shows or the
  /// size has no area.
  @visibleForTesting
  ChartLayout? get currentLayout => _layout;

  /// How many times this state has laid the chart out.
  @visibleForTesting
  int get layoutCount => _layoutCount;

  @override
  void initState() {
    super.initState();
    _portal.show();
  }

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

  /// The hit at [position] of the current layout with [tolerance], or `null`
  /// when no chart is laid out or nothing is there.
  JetChartHit? _hitAt(Offset position, double tolerance) {
    final ChartLayout? layout = _layout;
    final Chart? chart = widget.chart;
    if (layout == null || chart == null) {
      return null;
    }
    return chartHitAt(
      chart,
      layout,
      position,
      theme: widget.theme ?? ChartTheme.office,
      locale: widget.locale,
      tolerance: tolerance,
    );
  }

  /// Opens the box on [tooltip] at [position], or closes it when [tooltip] is
  /// `null` or tooltips are off. Call inside `setState`, or from `build`.
  void _setTip(ChartTooltip? tooltip, Offset position, double tolerance) {
    if (tooltip == null || !widget.tooltips) {
      _tip = null;
      _tipLayout = null;
      return;
    }
    _tip = tooltip;
    _tipPointer = position;
    _tipTolerance = tolerance;
    _tipLayout = _layout;
  }

  void _closeTip() {
    if (_tip != null) {
      setState(() => _setTip(null, Offset.zero, mouseTolerance));
    }
  }

  void _onHover(PointerHoverEvent event) {
    final JetChartHit? hit = _hitAt(event.localPosition, mouseTolerance);
    if (widget.tooltips && (hit?.tooltip != null || _tip != null)) {
      setState(
        () => _setTip(hit?.tooltip, event.localPosition, mouseTolerance),
      );
    }
    widget.onHover?.call(hit);
  }

  void _onExit(PointerExitEvent event) {
    _closeTip();
    widget.onHover?.call(null);
  }

  void _onTapUp(TapUpDetails details) {
    final bool mouse = details.kind == PointerDeviceKind.mouse;
    final double tolerance = mouse ? mouseTolerance : touchTolerance;
    final JetChartHit? hit = _hitAt(details.localPosition, tolerance);
    if (!mouse && widget.tooltips) {
      setState(() => _setTip(hit?.tooltip, details.localPosition, tolerance));
    }
    if (hit != null) {
      widget.onTap?.call(hit);
    }
  }

  /// Finds the open tooltip again in [layout] when it was found in another
  /// one (the chart, its size, theme or locale changed), closing it when the
  /// same pointer position has none there.
  void _refreshTip(Chart chart, ChartTheme theme, ChartLayout layout) {
    if (_tip == null || identical(_tipLayout, layout)) {
      return;
    }
    final ChartTooltip? tooltip = chartTooltipAt(
      chart,
      layout,
      ChartPoint(_tipPointer.dx, _tipPointer.dy),
      theme: theme,
      locale: widget.locale,
      tolerance: _tipTolerance,
    );
    _setTip(tooltip, _tipPointer, _tipTolerance);
  }

  /// [paint] with the pointer handlers and the tooltip box.
  Widget _interactive(
    BuildContext context,
    ChartTheme theme,
    Size size,
    Widget paint,
  ) {
    final ChartTooltip? tip = _tip;
    Widget box(ChartTooltip tooltip) => TooltipView(
      tooltip: tooltip,
      style: theme.tooltip,
      symbolSize: theme.spacing.legendSymbol,
      symbolGap: theme.spacing.labelGap,
    );
    Widget content = paint;
    if (Overlay.maybeOf(context) != null) {
      final Offset pointer = _tipPointer;
      content = OverlayPortal.overlayChildLayoutBuilder(
        controller: _portal,
        overlayChildBuilder:
            (BuildContext context, OverlayChildLayoutInfo info) {
              if (tip == null) {
                return const SizedBox.shrink();
              }
              final Matrix4 transform = info.childPaintTransform;
              return placeTooltip(
                box: box(tip),
                pointer: MatrixUtils.transformPoint(transform, pointer),
                chart: MatrixUtils.transformRect(
                  transform,
                  Offset.zero & info.childSize,
                ),
                bounds: Offset.zero & info.overlaySize,
              );
            },
        child: content,
      );
    } else {
      // Always a stack, so the paint keeps its place in the tree as the box
      // opens and closes.
      final Rect chart = Offset.zero & size;
      content = Stack(
        children: <Widget>[
          content,
          if (tip != null)
            Positioned.fill(
              child: placeTooltip(
                box: box(tip),
                pointer: _tipPointer,
                chart: chart,
                bounds: chart,
              ),
            ),
        ],
      );
    }
    if (widget.tooltips || widget.onTap != null) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTapUp: _onTapUp,
        child: content,
      );
    }
    if (widget.tooltips || widget.onHover != null) {
      content = MouseRegion(onHover: _onHover, onExit: _onExit, child: content);
    }
    if (widget.tooltips) {
      content = TapRegion(
        onTapOutside: (PointerDownEvent event) => _closeTip(),
        child: content,
      );
    }
    return content;
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
      _setTip(null, Offset.zero, mouseTolerance);
      return widget.errorBuilder?.call(context, theme, error) ??
          MessageLook(theme: theme, measurer: measurer, message: strings.error);
    }
    if (widget.loading) {
      _layout = null;
      _setTip(null, Offset.zero, mouseTolerance);
      return widget.loadingBuilder?.call(context, theme) ??
          LoadingLook(theme: theme, label: strings.loading);
    }
    final ChartSummary? summary = chart == null
        ? null
        : _summaryOf(chart, widget.locale);
    if (chart == null || summary == null || summary.isEmpty) {
      _layout = null;
      _setTip(null, Offset.zero, mouseTolerance);
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
      sentences[0] = _closed(custom);
    }
    final Widget paint;
    if (size.isEmpty) {
      _layout = null;
      _setTip(null, Offset.zero, mouseTolerance);
      paint = const ExcludeSemantics(child: SizedBox.expand());
    } else {
      final ChartLayout layout = _layoutOf(
        chart,
        theme,
        size,
        scaler,
        measurer,
      );
      _refreshTip(chart, theme, layout);
      if (!widget.tooltips) {
        _setTip(null, Offset.zero, mouseTolerance);
      }
      paint = _interactive(
        context,
        theme,
        size,
        ExcludeSemantics(
          child: CustomPaint(
            size: size,
            painter: ChartLayoutPainter(
              primitives: layout.primitives,
              measurer: measurer,
            ),
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      label: sentences.join(' '),
      child: paint,
    );
  }
}
