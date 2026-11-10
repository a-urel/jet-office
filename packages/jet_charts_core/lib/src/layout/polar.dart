/// The frame and geometry of a polar chart: a pie or a donut now, and later
/// any kind laid out around a centre (a radar, a 3D pie).
///
/// Angles here are clock angles in degrees: 0 is twelve o'clock and they grow
/// clockwise, on a y-down canvas. [arcAngle] turns one into the angle of an
/// `ArcPrimitive`, whose 0 is three o'clock.
///
/// The frame of a polar chart: the background fills the size; `padding`
/// inside it the title takes the top, then the legend its side (as the frame
/// of a cartesian chart places them), and the plot is the largest square of
/// what is left, centred in it.
library;

import 'dart:math' as math;

import '../model/chart_kind.dart';
import '../theme/chart_color.dart';
import '../theme/chart_theme.dart';
import 'geometry.dart';
import 'legend_layout.dart';
import 'primitives.dart';
import 'text_measurer.dart';

/// The angle of an `ArcPrimitive` (0 at three o'clock) of the clock angle
/// [clockDegrees] (0 at twelve o'clock, clockwise).
double arcAngle(double clockDegrees) => clockDegrees - 90;

/// The point at [radius] from [center] at the clock angle [clockDegrees].
ChartPoint polarPoint(ChartPoint center, double radius, double clockDegrees) {
  final double a = clockDegrees * math.pi / 180;
  return ChartPoint(
    center.x + radius * math.sin(a),
    center.y - radius * math.cos(a),
  );
}

/// The least distance from [p] to the rectangle [r]; 0 when [p] lies in it.
double distanceToRect(ChartPoint p, ChartRect r) {
  final double dx = math.max(math.max(r.left - p.x, 0), p.x - r.right);
  final double dy = math.max(math.max(r.top - p.y, 0), p.y - r.bottom);
  return math.sqrt(dx * dx + dy * dy);
}

/// A laid out polar frame: what the title and legend draw, the area left
/// for the plot and its labels, and the plot's square.
final class PolarFrame {
  /// Creates a frame.
  const PolarFrame({
    required this.primitives,
    required this.rest,
    required this.square,
    required this.title,
    required this.legend,
  });

  /// The title's and the legend's primitives, in paint order.
  final List<ChartPrimitive> primitives;

  /// The area left once the title and legend took theirs: where the plot
  /// and its data labels lie.
  final ChartRect rest;

  /// The plot: the largest square of [rest], centred in it.
  final ChartRect square;

  /// Whether the title is drawn.
  final bool title;

  /// Whether the legend is drawn.
  final bool legend;

  /// The centre of [square].
  ChartPoint get center => ChartPoint(
    square.left + square.width / 2,
    square.top + square.height / 2,
  );
}

/// Lays out the frame of a polar chart on [size]: the [title] (none when
/// `null` or empty) and a legend of [names] in [colors] on [position] (none
/// when not [legendVisible] or there are no names).
///
/// A title or legend that does not fit its space is left out; so is the
/// legend, then the title, while the square left would be smaller than
/// [minSide]. Returns `null` when even without them there is no square of
/// [minSide]: the chart then draws only its background.
PolarFrame? layoutPolarFrame({
  required String? title,
  required List<String> names,
  required List<ChartColor> colors,
  required ChartLegendPosition position,
  required bool legendVisible,
  required ChartTheme theme,
  required ChartSize size,
  required TextMeasurer measurer,
  required double minSide,
}) {
  bool showTitle = title != null && title.isNotEmpty;
  bool showLegend = legendVisible && names.isNotEmpty;
  final double p = theme.spacing.padding;
  final ChartRect content = ChartRect(
    p,
    p,
    size.width - 2 * p,
    size.height - 2 * p,
  );
  if (!(content.width > 0 && content.height > 0)) {
    return null;
  }
  while (true) {
    ChartRect area = content;
    final List<ChartPrimitive> out = <ChartPrimitive>[];
    if (showTitle) {
      final Placed? placed = placeTitle(
        title!,
        area,
        theme.titleText,
        measurer,
        theme.spacing,
      );
      if (placed == null) {
        showTitle = false;
        continue;
      }
      out.addAll(placed.primitives);
      area = placed.rest;
    }
    if (showLegend) {
      final Placed? placed = placeLegend(
        names,
        colors,
        position,
        area,
        content,
        theme.legendText,
        measurer,
        theme.spacing,
      );
      if (placed == null) {
        showLegend = false;
        continue;
      }
      out.addAll(placed.primitives);
      area = placed.rest;
    }
    final double side = math.min(area.width, area.height);
    if (!(side >= minSide)) {
      if (showLegend) {
        showLegend = false;
        continue;
      }
      if (showTitle) {
        showTitle = false;
        continue;
      }
      return null;
    }
    return PolarFrame(
      primitives: out,
      rest: area,
      square: ChartRect(
        area.left + (area.width - side) / 2,
        area.top + (area.height - side) / 2,
        side,
        side,
      ),
      title: showTitle,
      legend: showLegend,
    );
  }
}
