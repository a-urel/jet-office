/// The `JetChart` widget: a chart laid out by `jet_charts_core` and painted
/// on a canvas, with its loading, empty and error states.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_core/jet_core.dart';

import 'animation.dart';
import 'chart_layout_painter.dart';
import 'chart_semantics.dart';
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
/// An app depends on `jet_charts_flutter`, `jet_charts_core` (the chart
/// model and themes) and `jet_core` (`FormatLocale`). A Turkish app sets both
/// [locale] and [strings]:
///
/// ```dart
/// JetChart(
///   chart: Chart(
///     kind: ChartKind.column,
///     title: const ChartTitle(text: 'Satışlar'),
///     series: <ChartSeries>[
///       ChartSeries(
///         name: ChartData<String>(values: <String?>['Kuzey']),
///         categories: ChartData<Object>(values: <Object?>['Ç1', 'Ç2']),
///         values: ChartData<double>(values: <double?>[1250.5, 1800]),
///       ),
///     ],
///   ),
///   locale: FormatLocale.trTR,
///   strings: JetChartStrings.tr,
/// )
/// ```
///
/// **Size.** A bounded side of the constraints is used as is. An unbounded
/// width is 360 (Excel's 5 inch default), or the height divided by 0.6 when
/// the height is bounded; an unbounded height is 216, or the width times 0.6
/// when the width is bounded. The result is then fitted to the constraints'
/// minimums. A size with no area paints nothing.
///
/// Asked for its intrinsic size (under an `IntrinsicHeight` or an
/// `IntrinsicWidth`, as in a dashboard row of equal heights), the chart
/// answers by the same rule: its minimum and maximum intrinsic height for a
/// given width are the width times 0.6, or 216 for an unbounded width; its
/// minimum and maximum intrinsic width for a given height are the height
/// divided by 0.6, or 360 for an unbounded height.
///
/// **Loading.** The default loading look repeats its animation for as long
/// as [loading] is `true` (unless animations are disabled), so a widget test
/// must not call `pumpAndSettle` while a chart loads: it never settles. Pump
/// a fixed duration instead.
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
/// Below it, the chart gives one node per point, in order, each over its
/// place on the chart and labelled by the tooltip's text joined (`title:
/// row label row value, …`, as `Q1: North 12, South 9`): in a column, bar,
/// line, area or combination chart and in a sparkline one per category band,
/// with every series at that category; in a pie or donut one per slice of
/// the first series, with its share; in a scatter chart one per marker. A
/// chart that would need more than [JetChartStrings.maxPointNodes] gets
/// none, and the description speaks for it; a state look has none. The
/// chart node is marked focusable when [focusable], and focused while it has
/// the keyboard's focus.
///
/// **Keyboard.** Unless [focusable] is `false`, the chart takes part in the
/// focus order (Tab reaches it), through [focusNode] when given. While it has
/// focus, Right or Down moves to the next point, Left or Up to the previous
/// one (from no point, Right goes to the first and Left to the last), Home
/// to the first and End to the last; the first and last points stay where
/// they are. A column or bar chart walks its bars, series-major: series 0's
/// bars by category, then series 1's. A pie or donut walks the slices of its
/// first series, and a scatter chart its markers, series-major. A line,
/// area or combination chart and a sparkline walk their category bands, in
/// category order, each showing the category's tooltip with every series
/// (a combination's columns too), whatever markers the lines draw.
/// The focused point's tooltip shows as on hover (`chartTooltipFor` of the
/// point's primitive, or a band's category tooltip), with the box placed at
/// the point's (the bar's, slice's, marker's or band's) centre, so a screen
/// reader announces it; a focus ring of 1.5 pixels in the theme's axis label
/// colour is drawn around the point.
/// Escape closes the box and the ring, as does focus leaving the chart, a
/// state look, and a hover or tap that opens or closes the box. When the
/// layout changes, the same point (by its id) stays focused, or the focus
/// on a point ends when the new layout has no such point. With [tooltips]
/// `false` only the ring shows.
///
/// **Hover and touch.** A mouse over the chart finds the primitives within 2
/// pixels of it (`hitTestLayout`) and shows the tooltip there
/// (`chartTooltipAt`) in a box of the theme's `ChartTheme.tooltip` look; it
/// reports the topmost hit to [onHover], and `null` when it leaves. A tap of
/// a touch (or a stylus) finds within 8 pixels and toggles the box: a tap
/// where there is a tooltip shows it, and a tap where there is none, or
/// anywhere outside the chart (`TapRegion`), closes it. A touch is a tap when
/// it lifts within the touch slop of where it went down. The toggle only
/// listens to the pointer and takes no part in the gesture arena, so a
/// tappable parent (a card, a dashboard tile) still receives the tap. With
/// [tooltips] `false` no box shows, and the callbacks are still called.
///
/// The box sits 12 pixels right of and below the pointer, and on the other
/// side of it when it would leave the chart. Under an `Overlay` it is shown in
/// that overlay (`OverlayPortal`), so it may extend past a small chart, kept
/// inside the overlay; with no `Overlay` above the chart it is drawn over the
/// chart and kept inside it. It is a live region for screen readers, so a
/// screen reader announces it each time its text changes, as the pointer
/// moves from one point to the next.
///
/// When the chart, its size, its theme or its locale changes while the box
/// shows, the tooltip is found again at the same pointer position in the new
/// layout, and the box closes when there is none there. No state look shows
/// a box.
///
/// **Animation.** When [chart] changes and the chart keeps its size, its marks
/// (bars, lines, markers and areas) move from where they are on screen to
/// their new places over [animationDuration] with an ease out cubic curve;
/// the rest of the chart shows its new look at once, and data labels show when
/// the marks arrive. A change during an animation starts from the marks on
/// screen. The first chart, a resize, and a change of theme, locale or text
/// size do not animate: they show the new layout at once, ending a running
/// animation, as do a state look and turning `MediaQuery.disableAnimationsOf`
/// on. Nothing animates when [animationDuration] is zero or animations are
/// disabled. Hover and taps always use the new layout.
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
    this.focusable = true,
    this.focusNode,
    this.tooltipLines,
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

  /// How long a change of [chart] animates its marks; zero shows the new
  /// chart at once. See "Animation" on [JetChart].
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

  /// Called with the hit of a tap on the chart, by mouse or touch.
  ///
  /// When it is set, the chart recognizes taps in the gesture arena and so
  /// takes them: a tappable parent no longer receives a tap on the chart.
  /// When it is `null`, the chart recognizes no tap, and the touch toggle of
  /// the tooltip box leaves the tap to the parent.
  final ValueChanged<JetChartHit>? onTap;

  /// Whether the chart takes part in the focus order, so a keyboard can walk
  /// its points; `false` takes it out, as a sparkline in a dense dashboard
  /// tile wants. See "Keyboard" on [JetChart].
  final bool focusable;

  /// The focus node of the chart, or `null` for one the chart owns. The
  /// chart sets its `canRequestFocus` and `skipTraversal` by [focusable],
  /// and its key handler.
  final FocusNode? focusNode;

  /// Extra lines for a tooltip, under its rows, or `null` for none.
  ///
  /// Called with the chart's own tooltip whenever the box opens on one (by
  /// hover, tap or keyboard) and for each screen reader point node; each
  /// line it returns shows as a row of its label alone, in the box and in
  /// the node's text, after the rows. The app words and formats the lines
  /// itself, such as `12 işlem` under a value. The hits [onHover] and
  /// [onTap] report keep the chart's own tooltip, without the lines, and the
  /// lines are never written to a file.
  final JetChartTooltipLines? tooltipLines;

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
final class JetChartState extends State<JetChart>
    with SingleTickerProviderStateMixin {
  FlutterTextMeasurer? _measurer;

  ChartSummary? _summary;
  Chart? _summaryChart;
  FormatLocale? _summaryLocale;

  /// The screen reader label of [_labelSummary] in [_labelStrings] with
  /// [_labelCustom] in place of its first sentence.
  String? _label;
  ChartSummary? _labelSummary;
  JetChartStrings? _labelStrings;
  String? _labelCustom;

  ChartLayout? _layout;
  Chart? _layoutChart;
  ChartTheme? _layoutTheme;
  Size? _layoutSize;
  FormatLocale? _layoutLocale;
  TextScaler? _layoutScaler;
  int _layoutCount = 0;

  /// Runs the animation of the marks after a change of the chart. Created in
  /// [initState], so [dispose] never creates a ticker.
  late final AnimationController _controller;

  /// [_controller] on the ease out cubic curve.
  late final CurvedAnimation _curve;

  /// The primitives the running animation starts from, or `null` when none
  /// runs: the painted ones are [_layout]'s.
  List<ChartPrimitive>? _from;

  /// Whether the last build saw animations disabled
  /// (`MediaQuery.disableAnimationsOf`).
  bool _reduceMotion = false;

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

  /// The touch that went down on the chart and may become a tap: its
  /// pointer and where it went down; `null` when none is in progress.
  int? _touchPointer;
  Offset _touchDown = Offset.zero;

  /// The focus node the chart owns when [JetChart.focusNode] is `null`.
  FocusNode? _ownFocusNode;

  /// The keyboard's points of [_pointsLayout], computed once per layout.
  List<ChartKeyPoint>? _points;
  ChartLayout? _pointsLayout;

  /// The screen reader nodes of [_nodesLayout], computed once per layout.
  List<ChartPointNode>? _nodes;
  ChartLayout? _nodesLayout;

  /// The point the keyboard focused, or `null` when none is: its key, and the
  /// layout it was found in.
  ChartKeyPoint? _keyPoint;
  ChartLayout? _keyLayout;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownFocusNode ??= FocusNode(debugLabel: 'JetChart'));

  /// Whether the chart has the keyboard's focus.
  @visibleForTesting
  bool get hasFocus => _focusNode.hasFocus;

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
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _portal.show();
  }

  @override
  void didUpdateWidget(JetChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.animationDuration;
    if (oldWidget.tooltipLines != widget.tooltipLines) {
      _nodes = null;
    }
    final ChartLayout? shown = _layout;
    if (oldWidget.chart == widget.chart || shown == null) {
      return;
    }
    if (_reduceMotion || widget.animationDuration == Duration.zero) {
      _stopAnimation();
      return;
    }
    _from = _painted(shown);
    _controller.forward(from: 0);
  }

  /// Ends the running animation, if any, so the new layout shows at once.
  void _stopAnimation() {
    _controller.stop();
    _from = null;
  }

  /// The primitives to paint for [layout], the target: between [_from] and
  /// [layout]'s while an animation runs.
  List<ChartPrimitive> _painted(ChartLayout layout) {
    final List<ChartPrimitive>? from = _from;
    if (from == null || !_controller.isAnimating) {
      return layout.primitives;
    }
    return lerpChartPrimitives(from, layout.primitives, _curve.value);
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    _measurer?.dispose();
    _ownFocusNode?.dispose();
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

  /// The screen reader label of [summary]: see "Screen readers" on
  /// [JetChart]. Computed again only when the summary (the chart or the
  /// locale), the strings or [JetChart.semanticsLabel] changed.
  String _labelOf(ChartSummary summary) {
    final String? cached = _label;
    final JetChartStrings strings = widget.strings;
    final String? custom = widget.semanticsLabel;
    if (cached != null &&
        identical(_labelSummary, summary) &&
        _labelStrings == strings &&
        _labelCustom == custom) {
      return cached;
    }
    final List<String> sentences = strings.sentences(summary);
    if (custom != null) {
      sentences[0] = _closed(custom);
    }
    _labelSummary = summary;
    _labelStrings = strings;
    _labelCustom = custom;
    return _label = sentences.join(' ');
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
    // Only a change of the chart animates: a new size, theme, locale or text
    // scale shows the new layout at once, even during an animation.
    if (_layoutSize != size ||
        _layoutTheme != theme ||
        _layoutLocale != widget.locale ||
        _layoutScaler != scaler) {
      _stopAnimation();
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
    if (_tip != null || _keyPoint != null) {
      setState(() {
        _keyPoint = null;
        _setTip(null, Offset.zero, mouseTolerance);
      });
    }
  }

  /// The keyboard's points of [layout], computed once per layout.
  List<ChartKeyPoint> _pointsOf(Chart chart, ChartLayout layout) {
    final List<ChartKeyPoint>? cached = _points;
    if (cached != null && identical(_pointsLayout, layout)) {
      return cached;
    }
    _pointsLayout = layout;
    return _points = chartKeyPoints(chart, layout);
  }

  /// The screen reader nodes of [layout], computed once per layout.
  List<ChartPointNode> _nodesOf(
    Chart chart,
    ChartLayout layout,
    ChartTheme theme,
  ) {
    final List<ChartPointNode>? cached = _nodes;
    if (cached != null && identical(_nodesLayout, layout)) {
      return cached;
    }
    _nodesLayout = layout;
    return _nodes = chartPointNodes(
      chart,
      layout,
      theme: theme,
      locale: widget.locale,
      lines: widget.tooltipLines,
    );
  }

  /// Focuses [point] of [layout] and opens its tooltip at its centre. Call
  /// inside `setState`, or from `build`.
  void _showPoint(ChartKeyPoint point, Chart chart, ChartLayout layout) {
    _keyPoint = point;
    _keyLayout = layout;
    final ChartTooltip? tooltip = keyPointTooltip(
      chart,
      layout,
      point,
      theme: widget.theme ?? ChartTheme.office,
      locale: widget.locale,
    );
    _setTip(tooltip, point.bounds.center, mouseTolerance);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_keyPoint == null && _tip == null) {
        return KeyEventResult.ignored;
      }
      _closeTip();
      return KeyEventResult.handled;
    }
    final ChartLayout? layout = _layout;
    final Chart? chart = widget.chart;
    if (layout == null || chart == null) {
      return KeyEventResult.ignored;
    }
    final List<ChartKeyPoint> points = _pointsOf(chart, layout);
    if (points.isEmpty) {
      return KeyEventResult.ignored;
    }
    final String? focused = _keyPoint?.key;
    final int current = focused == null
        ? -1
        : points.indexWhere((ChartKeyPoint p) => p.key == focused);
    final int last = points.length - 1;
    final int next;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      next = current < 0 ? 0 : (current + 1).clamp(0, last);
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      next = current < 0 ? last : (current - 1).clamp(0, last);
    } else if (key == LogicalKeyboardKey.home) {
      next = 0;
    } else if (key == LogicalKeyboardKey.end) {
      next = last;
    } else {
      return KeyEventResult.ignored;
    }
    setState(() => _showPoint(points[next], chart, layout));
    return KeyEventResult.handled;
  }

  void _onFocusChange(bool focused) {
    setState(() {
      if (!focused && _keyPoint != null) {
        _keyPoint = null;
        _setTip(null, Offset.zero, mouseTolerance);
      }
    });
  }

  void _onHover(PointerHoverEvent event) {
    final JetChartHit? hit = _hitAt(event.localPosition, mouseTolerance);
    if (widget.tooltips && (hit?.tooltip != null || _tip != null)) {
      setState(() {
        _keyPoint = null;
        _setTip(hit?.tooltip, event.localPosition, mouseTolerance);
      });
    }
    widget.onHover?.call(hit);
  }

  void _onExit(PointerExitEvent event) {
    _closeTip();
    widget.onHover?.call(null);
  }

  void _onTapUp(TapUpDetails details) {
    final bool mouse = details.kind == PointerDeviceKind.mouse;
    final JetChartHit? hit = _hitAt(
      details.localPosition,
      mouse ? mouseTolerance : touchTolerance,
    );
    if (hit != null) {
      widget.onTap?.call(hit);
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse ||
        event.kind == PointerDeviceKind.trackpad) {
      return;
    }
    _touchPointer = event.pointer;
    _touchDown = event.localPosition;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _touchPointer) {
      return;
    }
    _touchPointer = null;
    if ((event.localPosition - _touchDown).distance > kTouchSlop) {
      return;
    }
    final JetChartHit? hit = _hitAt(event.localPosition, touchTolerance);
    setState(() {
      _keyPoint = null;
      _setTip(hit?.tooltip, event.localPosition, touchTolerance);
    });
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer == _touchPointer) {
      _touchPointer = null;
    }
  }

  /// Finds the open tooltip again in [layout] when it was found in another
  /// one (the chart, its size, theme or locale changed), closing it when the
  /// same pointer position has none there.
  void _refreshTip(Chart chart, ChartTheme theme, ChartLayout layout) {
    final ChartKeyPoint? point = _keyPoint;
    if (point != null) {
      if (identical(_keyLayout, layout)) {
        return;
      }
      final List<ChartKeyPoint> points = _pointsOf(chart, layout);
      final int i = points.indexWhere((ChartKeyPoint p) => p.key == point.key);
      if (i < 0) {
        _keyPoint = null;
        _setTip(null, Offset.zero, mouseTolerance);
      } else {
        _showPoint(points[i], chart, layout);
      }
      return;
    }
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
      tooltip: withTooltipLines(tooltip, widget.tooltipLines),
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
    if (widget.tooltips) {
      content = Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: content,
      );
    }
    if (widget.onTap != null) {
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
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduceMotion) {
      _stopAnimation();
    }
    final FlutterTextMeasurer measurer = _measurerFor(scaler);
    return Focus(
      focusNode: _focusNode,
      canRequestFocus: widget.focusable,
      skipTraversal: !widget.focusable,
      includeSemantics: false,
      onKeyEvent: _onKey,
      onFocusChange: _onFocusChange,
      child: _sized(theme, scaler, measurer),
    );
  }

  Widget _sized(
    ChartTheme theme,
    TextScaler scaler,
    FlutterTextMeasurer measurer,
  ) {
    return _ChartSizing(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Size size = _chartSize(constraints);
          return SizedBox(
            width: size.width,
            height: size.height,
            child: _look(context, theme, scaler, measurer, size),
          );
        },
      ),
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
      _stopAnimation();
      _keyPoint = null;
      _setTip(null, Offset.zero, mouseTolerance);
      return widget.errorBuilder?.call(context, theme, error) ??
          MessageLook(theme: theme, measurer: measurer, message: strings.error);
    }
    if (widget.loading) {
      _layout = null;
      _stopAnimation();
      _keyPoint = null;
      _setTip(null, Offset.zero, mouseTolerance);
      return widget.loadingBuilder?.call(context, theme) ??
          LoadingLook(theme: theme, label: strings.loading);
    }
    final ChartSummary? summary = chart == null
        ? null
        : _summaryOf(chart, widget.locale);
    if (chart == null || summary == null || summary.isEmpty) {
      _layout = null;
      _stopAnimation();
      _keyPoint = null;
      _setTip(null, Offset.zero, mouseTolerance);
      return widget.emptyBuilder?.call(context, theme) ??
          MessageLook(
            theme: theme,
            measurer: measurer,
            message: strings.empty,
            title: summary?.title,
          );
    }
    final String label = _labelOf(summary);
    final TextDirection direction =
        Directionality.maybeOf(context) ?? TextDirection.ltr;
    final Widget paint;
    if (size.isEmpty) {
      _layout = null;
      _stopAnimation();
      _keyPoint = null;
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
      final ChartKeyPoint? point = _focusNode.hasFocus ? _keyPoint : null;
      paint = _interactive(
        context,
        theme,
        size,
        Stack(
          children: <Widget>[
            ExcludeSemantics(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (BuildContext context, Widget? child) => CustomPaint(
                  size: size,
                  painter: ChartLayoutPainter(
                    primitives: _painted(layout),
                    measurer: measurer,
                  ),
                ),
              ),
            ),
            if (point != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: FocusRingPainter(
                      rect: focusRingRect(point.bounds, size),
                      color: Color(0xFF000000 | theme.axisLabels.color.rgb),
                    ),
                  ),
                ),
              ),
            ...pointNodeWidgets(_nodesOf(chart, layout, theme), direction),
          ],
        ),
      );
    }
    return Semantics(
      container: true,
      textDirection: direction,
      label: label,
      focusable: widget.focusable,
      focused: _focusNode.hasFocus,
      child: paint,
    );
  }
}

/// Answers intrinsic size and dry layout queries for [JetChart] by its size
/// rule, which a `LayoutBuilder` cannot answer: see "Size" on [JetChart].
final class _ChartSizing extends SingleChildRenderObjectWidget {
  const _ChartSizing({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderChartSizing();
}

/// The render object of [_ChartSizing]: it lays its child out as a proxy and
/// answers the queries the child cannot.
final class _RenderChartSizing extends RenderProxyBox {
  /// The width of a chart [height] high: [height] / 0.6, or 360 when
  /// [height] is unbounded.
  static double _width(double height) => height.isFinite ? height / 0.6 : 360;

  /// The height of a chart [width] wide: [width] times 0.6, or 216 when
  /// [width] is unbounded.
  static double _height(double width) => width.isFinite ? width * 0.6 : 216;

  @override
  double computeMinIntrinsicWidth(double height) => _width(height);

  @override
  double computeMaxIntrinsicWidth(double height) => _width(height);

  @override
  double computeMinIntrinsicHeight(double width) => _height(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _height(width);

  @override
  Size computeDryLayout(BoxConstraints constraints) => _chartSize(constraints);

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => null;
}
