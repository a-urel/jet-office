/// The tooltip box of `JetChart` and where it is placed.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:jet_charts_core/jet_charts_core.dart';

/// How far the box sits from the pointer, right and below it (or left and
/// above it when flipped), in logical pixels.
const double tooltipOffset = 12;

/// The space between two lines of the box, in logical pixels.
const double _lineGap = 2;

/// The least space between a row's label and its value, in logical pixels.
const double _valueGap = 12;

Color _color(ChartColor c) => Color(0xFF000000 | c.rgb);

/// The text style of the box: [style]'s font, size and colour, bold or not,
/// and nothing from the host's `DefaultTextStyle` (`inherit: false`).
TextStyle _textStyle(ChartTextStyle style, {required bool bold}) => TextStyle(
  inherit: false,
  fontFamily: style.fontFamily,
  fontSize: style.size,
  fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
  color: _color(style.color),
);

/// The text a screen reader reads for [tooltip]: its title, then each row's
/// label and value, one line each.
String tooltipText(ChartTooltip tooltip) => <String>[
  ?tooltip.title,
  for (final ChartTooltipRow row in tooltip.rows)
    row.value.isEmpty ? row.label : '${row.label} ${row.value}',
].join('\n');

/// The box that shows [tooltip] in [style].
///
/// It is filled with the style's background and drawn with a border of its
/// border colour, [ChartTooltipStyle.padding] inside it. The title comes first,
/// in the style's text bold; then each row: a square of the row's colour,
/// [symbolSize] wide, [symbolGap] before the label, then the value in bold,
/// right-aligned with the other rows' values. A row without a colour has no
/// square, and a row without a value is its label alone. The box takes the
/// width its widest line needs, so no text wraps or overflows.
///
/// It looks the same whatever the host's `DefaultTextStyle` is: its text
/// styles inherit nothing (no decoration, letter or word spacing, line height
/// or shadow of the host's), and every text shows in full (no `maxLines`, no
/// ellipsis, aligned to the start).
///
/// It is one screen reader node, a live region, whose label is
/// [tooltipText].
final class TooltipView extends StatelessWidget {
  /// Creates the box of [tooltip].
  const TooltipView({
    super.key,
    required this.tooltip,
    required this.style,
    required this.symbolSize,
    required this.symbolGap,
  });

  /// What the box shows.
  final ChartTooltip tooltip;

  /// The look of the box.
  final ChartTooltipStyle style;

  /// The side of a row's colour square: the theme's legend symbol size.
  final double symbolSize;

  /// The space between a row's colour square and its label.
  final double symbolGap;

  @override
  Widget build(BuildContext context) {
    final TextStyle plain = _textStyle(style.text, bold: false);
    final TextStyle bold = _textStyle(style.text, bold: true);
    final List<Widget> lines = <Widget>[
      if (tooltip.title case final String title) Text(title, style: bold),
      for (final ChartTooltipRow row in tooltip.rows) _row(row, plain, bold),
    ];
    return Semantics(
      container: true,
      liveRegion: true,
      label: tooltipText(tooltip),
      child: ExcludeSemantics(
        child: DefaultTextStyle(
          style: plain,
          textAlign: TextAlign.start,
          overflow: TextOverflow.visible,
          textWidthBasis: TextWidthBasis.parent,
          textHeightBehavior: const TextHeightBehavior(),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _color(style.background),
              border: Border.all(color: _color(style.border)),
            ),
            child: Padding(
              padding: EdgeInsets.all(style.padding),
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (int i = 0; i < lines.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(height: _lineGap),
                      lines[i],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(ChartTooltipRow row, TextStyle plain, TextStyle bold) {
    final ChartColor? color = row.color;
    return Row(
      children: <Widget>[
        if (color != null) ...<Widget>[
          SizedBox(
            width: symbolSize,
            height: symbolSize,
            child: DecoratedBox(
              decoration: BoxDecoration(color: _color(color)),
            ),
          ),
          SizedBox(width: symbolGap),
        ],
        Text(row.label, style: plain),
        if (row.value.isNotEmpty) ...<Widget>[
          const SizedBox(width: _valueGap),
          const Spacer(),
          Text(row.value, style: bold),
        ],
      ],
    );
  }
}

/// Where the top left corner of a tooltip box of size [box] goes for a
/// pointer at [pointer] over a chart at [chart], kept inside [bounds].
///
/// The box sits [tooltipOffset] right of and below the pointer. When its
/// right edge would leave [chart], it goes [tooltipOffset] left of the pointer
/// instead, and when its bottom edge would, above it. The result is then
/// moved inside [bounds] as far as it fits; a box wider or taller than
/// [bounds] starts at their left or top edge. All values are in one
/// coordinate space.
Offset tooltipOrigin({
  required Offset pointer,
  required Size box,
  required Rect chart,
  required Rect bounds,
}) {
  double x = pointer.dx + tooltipOffset;
  if (x + box.width > chart.right) {
    x = pointer.dx - tooltipOffset - box.width;
  }
  double y = pointer.dy + tooltipOffset;
  if (y + box.height > chart.bottom) {
    y = pointer.dy - tooltipOffset - box.height;
  }
  x = math.max(bounds.left, math.min(x, bounds.right - box.width));
  y = math.max(bounds.top, math.min(y, bounds.bottom - box.height));
  return Offset(x, y);
}

/// [box] placed by [tooltipOrigin] for [pointer] over [chart] inside
/// [bounds], in the coordinates of the space this widget fills.
///
/// The box takes no pointer events, so it never hides the chart from the
/// pointer, and it is scaled down to fit [bounds] when larger.
Widget placeTooltip({
  required Widget box,
  required Offset pointer,
  required Rect chart,
  required Rect bounds,
}) => CustomSingleChildLayout(
  delegate: _TooltipPlacement(pointer: pointer, chart: chart, bounds: bounds),
  child: IgnorePointer(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topLeft,
      child: box,
    ),
  ),
);

final class _TooltipPlacement extends SingleChildLayoutDelegate {
  const _TooltipPlacement({
    required this.pointer,
    required this.chart,
    required this.bounds,
  });

  final Offset pointer;
  final Rect chart;
  final Rect bounds;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(bounds.size);

  @override
  Offset getPositionForChild(Size size, Size childSize) => tooltipOrigin(
    pointer: pointer,
    box: childSize,
    chart: chart,
    bounds: bounds,
  );

  @override
  bool shouldRelayout(_TooltipPlacement oldDelegate) =>
      pointer != oldDelegate.pointer ||
      chart != oldDelegate.chart ||
      bounds != oldDelegate.bounds;
}
