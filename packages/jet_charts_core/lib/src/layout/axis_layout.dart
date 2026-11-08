/// The axes of a cartesian chart: tick labels, category labels, grid lines and
/// axis lines.
///
/// The value axis is vertical at the left of the plot for column, line and
/// area charts and horizontal under it for bar charts; the category axis takes
/// the other side. Tick labels sit outside the plot, `labelGap` from it, and
/// never inside the plot. Category labels never collide: [planCategoryLabels]
/// skips, then turns, then cuts them, and [placeCategoryLabels] puts them
/// down.
library;

import 'dart:math' as math;

import '../model/equality.dart';
import '../scale/value_scale.dart';
import '../theme/chart_color.dart';
import '../theme/chart_spacing.dart';
import 'chart_ids.dart' as ids;
import 'geometry.dart';
import 'primitives.dart';
import 'text_measurer.dart';

/// A label's text and its measured size.
final class MeasuredLabel {
  /// Creates a label of [text] that measures [size].
  const MeasuredLabel(this.text, this.size);

  /// The text.
  final String text;

  /// The size the measurer gave.
  final ChartSize size;

  @override
  bool operator ==(Object other) =>
      other is MeasuredLabel && text == other.text && size == other.size;

  @override
  int get hashCode => Object.hash(text, size);

  @override
  String toString() => 'MeasuredLabel("$text", $size)';
}

/// [texts] measured in [style].
List<MeasuredLabel> measureLabels(
  List<String> texts,
  ChartTextStyle style,
  TextMeasurer measurer,
) => <MeasuredLabel>[
  for (final String text in texts)
    MeasuredLabel(text, measurer.measure(text, style)),
];

/// The position of [value] on a value axis of [scale] over [plot].
///
/// Vertical (`horizontal` false), the minimum is at the plot's bottom;
/// horizontal, at its left. A scale of no span puts every value at the
/// minimum's edge.
double valuePosition(
  double value,
  ValueScale scale,
  ChartRect plot, {
  required bool horizontal,
}) {
  final double span = scale.max - scale.min;
  final double t = span > 0 && span.isFinite
      ? ((value - scale.min) / span).clamp(0.0, 1.0)
      : 0.0;
  return horizontal
      ? plot.left + t * plot.width
      : plot.bottom - t * plot.height;
}

/// The value the category axis crosses the value axis at: 0 when it is in the
/// scale, else the bound nearer 0.
double crossingValue(ValueScale scale) {
  if (scale.min <= 0 && scale.max >= 0) {
    return 0;
  }
  return scale.min > 0 ? scale.min : scale.max;
}

/// Whether the tick [labels] of [scale] keep `minTextGap` apart on a value
/// axis of [plot].
///
/// Vertical, adjacent labels' centres must lie half their heights plus the gap
/// apart; horizontal, half their widths plus the gap.
bool valueLabelsFit(
  List<MeasuredLabel> labels,
  ValueScale scale,
  ChartRect plot, {
  required bool horizontal,
  required double minTextGap,
}) {
  for (int i = 1; i < labels.length && i < scale.ticks.length; i++) {
    final double distance =
        (valuePosition(scale.ticks[i], scale, plot, horizontal: horizontal) -
                valuePosition(
                  scale.ticks[i - 1],
                  scale,
                  plot,
                  horizontal: horizontal,
                ))
            .abs();
    final ChartSize a = labels[i - 1].size;
    final ChartSize b = labels[i].size;
    final double need = horizontal
        ? (a.width + b.width) / 2
        : (a.height + b.height) / 2;
    if (distance < need + minTextGap) {
      return false;
    }
  }
  return true;
}

/// The value axis' tick labels of [scale], outside [plot].
///
/// Vertical, each is right-aligned `labelGap` left of the plot and centred on
/// its tick; horizontal, each is centred under its tick, `labelGap` below.
List<TextPrimitive> valueLabelPrimitives(
  List<MeasuredLabel> labels,
  ValueScale scale,
  ChartRect plot,
  ChartTextStyle style, {
  required bool horizontal,
  required double labelGap,
}) {
  return <TextPrimitive>[
    for (int i = 0; i < labels.length && i < scale.ticks.length; i++)
      _valueLabel(
        i,
        labels[i],
        valuePosition(scale.ticks[i], scale, plot, horizontal: horizontal),
        plot,
        style,
        horizontal: horizontal,
        labelGap: labelGap,
      ),
  ];
}

TextPrimitive _valueLabel(
  int index,
  MeasuredLabel label,
  double at,
  ChartRect plot,
  ChartTextStyle style, {
  required bool horizontal,
  required double labelGap,
}) {
  final double w = label.size.width;
  final double h = label.size.height;
  final ChartRect rect = horizontal
      ? ChartRect(at - w / 2, plot.bottom + labelGap, w, h)
      : ChartRect(plot.left - labelGap - w, at - h / 2, w, h);
  return TextPrimitive(
    ids.axisLabelId(ids.valueAxis, index),
    label.text,
    rect,
    style,
  );
}

/// How the category labels go: which are shown, how they are turned and cut,
/// how deep their band is and how far they reach past the axis' ends.
final class CategoryLabelPlan {
  /// Creates a plan.
  CategoryLabelPlan({
    required this.fits,
    this.thickness = 0,
    this.rotationDegrees = 0,
    List<int> shown = const <int>[],
    List<MeasuredLabel> labels = const <MeasuredLabel>[],
    this.before = 0,
    this.after = 0,
    this.reserveBefore = 0,
    this.cramped = false,
  }) : shown = List<int>.unmodifiable(shown),
       labels = List<MeasuredLabel>.unmodifiable(labels);

  /// The plan of no labels: it fits and takes no room.
  factory CategoryLabelPlan.none() => CategoryLabelPlan(fits: true);

  /// Whether the shown labels keep `minTextGap` apart and stay within the
  /// band limit.
  final bool fits;

  /// The depth of the shown labels across the axis (without the label gap):
  /// the height of their turned boxes under a horizontal axis, their widest
  /// width beside a vertical one.
  final double thickness;

  /// The labels' clockwise rotation: 0, -45 or -90 (rising to the right).
  final double rotationDegrees;

  /// The indexes of the categories whose labels are shown, ascending.
  final List<int> shown;

  /// The shown labels as drawn, one for each of [shown]: the full text, or
  /// the text cut with `…`.
  final List<MeasuredLabel> labels;

  /// How far the shown labels reach before the axis' start (the plot's left,
  /// or a bar chart's plot bottom), within the room the frame gave.
  final double before;

  /// How far the shown labels reach past the axis' end (the plot's right, or
  /// a bar chart's plot top), within the room the frame gave.
  final double after;

  /// The room before the axis' start that the labels ask the frame to keep:
  /// the reach of the first label as if its tick were at the axis' start. At
  /// -45 degrees it is that of the first label cut to the band limit alone;
  /// at -90 degrees, and beside a bar chart's axis, half the label's height;
  /// at 0 degrees under a horizontal axis 0, as those labels use only the
  /// room the frame has anyway. Kept, it lets the first label stand whole,
  /// and as it does not depend on the axis' length, keeping it does not feed
  /// back into the plan.
  final double reserveBefore;

  /// Whether a plan that does not fit failed only for want of room past the
  /// axis' ends: some try kept its labels apart and within the band limit.
  /// Such a plan's [reserveBefore] is the largest of those tries', so the
  /// frame can keep the room and try again; if the room still lacks, only
  /// hiding the category labels relieves it.
  final bool cramped;

  @override
  bool operator ==(Object other) =>
      other is CategoryLabelPlan &&
      fits == other.fits &&
      thickness == other.thickness &&
      rotationDegrees == other.rotationDegrees &&
      before == other.before &&
      after == other.after &&
      reserveBefore == other.reserveBefore &&
      cramped == other.cramped &&
      listValueEquals(shown, other.shown) &&
      listValueEquals(labels, other.labels);

  @override
  int get hashCode => Object.hash(
    fits,
    thickness,
    rotationDegrees,
    before,
    after,
    reserveBefore,
    cramped,
    listValueHash(shown),
    listValueHash(labels),
  );

  @override
  String toString() =>
      'CategoryLabelPlan(fits: $fits, $rotationDegrees°, '
      '${shown.length} shown, thickness $thickness)';
}

/// The ellipsis a cut label ends in.
const String ellipsis = '…';

/// Plans the category [labels] along an axis of [axisLength], their band at
/// most [maxDepth] deep (40% of the space left for the plot and the band,
/// less the labels' offset from the plot).
///
/// Under a horizontal axis it tries, in order, 0 degrees showing every `N`th
/// label for `N` = 1, 2, 3; then -45 degrees for `N` = 1, 2, 3; then -90
/// degrees for `N` = 1, 2, … until they fit. Shown labels fit when no two come
/// closer than `minTextGap`, their band is no deeper than [maxDepth], and they
/// reach no further than [roomBefore] before the axis' start and [roomAfter]
/// past its end: the room the frame has there anyway, which the labels never
/// widen, so the plot does not depend on them along the axis. At -45 and -90
/// degrees, and beside a vertical axis, the room before is
/// [turnedRoomBefore], which also holds what the frame keeps for a plan's
/// [CategoryLabelPlan.reserveBefore]. A plan that fails only for want of room
/// is [CategoryLabelPlan.cramped]. At -45 and -90
/// degrees a label deeper than [maxDepth] is cut with `…`, and at -45 degrees
/// also one that would reach further than [turnedRoomBefore]; at 0 degrees
/// none is.
/// A turned label's end sits at its tick.
///
/// Beside a vertical axis (`vertical`, a bar chart) labels stay level: every
/// label wider than [maxDepth] is cut, and every `N`th is shown for the least
/// `N` that keeps them apart and within the room.
///
/// The plan does not fit when no try does: the band limit is too small for a
/// label (or a lone `…`), or the axis has no length.
CategoryLabelPlan planCategoryLabels(
  List<MeasuredLabel> labels,
  double axisLength, {
  required double maxDepth,
  required double roomBefore,
  required double turnedRoomBefore,
  required double roomAfter,
  required bool vertical,
  required ChartSpacing spacing,
  required TextMeasurer measurer,
  required ChartTextStyle style,
}) {
  if (labels.isEmpty) {
    return CategoryLabelPlan.none();
  }
  final _Planner planner = _Planner(
    labels,
    axisLength,
    maxDepth,
    roomBefore,
    turnedRoomBefore,
    roomAfter,
    spacing.minTextGap,
    vertical: vertical,
  );
  if (!(planner.band > 0) || !(maxDepth > 0) || !axisLength.isFinite) {
    return CategoryLabelPlan(fits: false);
  }
  final List<(int, int)> tries = vertical
      ? <(int, int)>[for (int n = 1; n <= labels.length; n++) (0, n)]
      : <(int, int)>[
          for (int n = 1; n <= 3; n++) (0, n),
          for (int n = 1; n <= 3; n++) (45, n),
          for (int n = 1; n <= labels.length; n++) (90, n),
        ];
  final Map<int, List<MeasuredLabel?>> cut = <int, List<MeasuredLabel?>>{};
  for (final (int angle, int every) in tries) {
    final List<MeasuredLabel?> drawn = angle == 0 && !vertical
        ? labels
        : cut.putIfAbsent(angle, () => planner.cut(angle, measurer, style));
    final CategoryLabelPlan? plan = planner.attempt(drawn, angle, every);
    if (plan != null) {
      return planner.reserved(plan, angle, measurer, style);
    }
  }
  if (planner.crampedAngles.isEmpty) {
    return CategoryLabelPlan(fits: false);
  }
  double reserve = 0;
  for (final int angle in planner.crampedAngles) {
    reserve = math.max(reserve, planner.reserve(angle, measurer, style));
  }
  return CategoryLabelPlan(fits: false, cramped: true, reserveBefore: reserve);
}

/// The tries of [planCategoryLabels]. Angles are counter-clockwise, in
/// degrees: 0, 45 or 90.
final class _Planner {
  _Planner(
    this.labels,
    this.axisLength,
    this.maxDepth,
    this.roomBefore,
    this.turnedRoomBefore,
    this.roomAfter,
    this.minTextGap, {
    required this.vertical,
  }) : band = axisLength / labels.length;

  final List<MeasuredLabel> labels;
  final double axisLength;
  final double band;
  final double maxDepth;
  final double roomBefore;
  final double turnedRoomBefore;
  final double roomAfter;
  final double minTextGap;
  final bool vertical;

  static const double _tolerance = 1e-9;

  /// The angles of the tries that failed only for want of room past the
  /// axis' ends.
  final Set<int> crampedAngles = <int>{};

  /// The depth across the axis of a label of [size] at [angle].
  double depth(ChartSize size, int angle) {
    if (vertical) {
      return size.width;
    }
    return switch (angle) {
      0 => size.height,
      90 => size.width,
      _ => (size.width + size.height) * math.sqrt1_2,
    };
  }

  /// The extent along the axis, from the axis' start, of a label of [size]
  /// at [angle] whose tick is that of category [index].
  (double, double) extent(ChartSize size, int angle, int index) {
    final double tick = (index + 0.5) * band;
    if (vertical) {
      return (tick - size.height / 2, tick + size.height / 2);
    }
    switch (angle) {
      case 0:
        return (tick - size.width / 2, tick + size.width / 2);
      case 90:
        return (tick - size.height / 2, tick + size.height / 2);
      default:
        final double half = size.height / 2 * math.sqrt1_2;
        return (tick - size.width * math.sqrt1_2 - half, tick + half);
    }
  }

  /// Whether the label of category [index] at [size] may be drawn at
  /// [angle] without a cut: within the depth, and at -45 degrees, when [room]
  /// counts, within the room before the axis.
  bool whole(ChartSize size, int angle, int index, {bool room = true}) =>
      depth(size, angle) <= maxDepth + _tolerance &&
      (!room ||
          vertical ||
          angle != 45 ||
          extent(size, angle, index).$1 >= -turnedRoomBefore - _tolerance);

  /// [labels], each cut with `…` until [whole] holds at [angle]; `null` for a
  /// label that a lone `…` still does not fit.
  List<MeasuredLabel?> cut(
    int angle,
    TextMeasurer measurer,
    ChartTextStyle style,
  ) => <MeasuredLabel?>[
    for (int index = 0; index < labels.length; index++)
      cutOne(index, angle, measurer, style),
  ];

  /// [plan], tried at [angle], with its [CategoryLabelPlan.reserveBefore].
  CategoryLabelPlan reserved(
    CategoryLabelPlan plan,
    int angle,
    TextMeasurer measurer,
    ChartTextStyle style,
  ) => CategoryLabelPlan(
    fits: plan.fits,
    thickness: plan.thickness,
    rotationDegrees: plan.rotationDegrees,
    shown: plan.shown,
    labels: plan.labels,
    before: plan.before,
    after: plan.after,
    reserveBefore: reserve(angle, measurer, style),
  );

  /// The [CategoryLabelPlan.reserveBefore] of a try at [angle].
  double reserve(int angle, TextMeasurer measurer, ChartTextStyle style) {
    if (vertical || angle == 90) {
      return labels.first.size.height / 2;
    }
    if (angle == 45) {
      final MeasuredLabel? first = cutOne(0, 45, measurer, style, room: false);
      final ChartSize size = first?.size ?? const ChartSize(0, 0);
      return (size.width + size.height / 2) * math.sqrt1_2;
    }
    return 0;
  }

  /// The label of category [index] cut with `…` until [whole] holds at
  /// [angle]; `null` when a lone `…` still does not fit.
  MeasuredLabel? cutOne(
    int index,
    int angle,
    TextMeasurer measurer,
    ChartTextStyle style, {
    bool room = true,
  }) {
    final MeasuredLabel label = labels[index];
    if (whole(label.size, angle, index, room: room)) {
      return label;
    }
    final List<int> runes = label.text.runes.toList();
    MeasuredLabel cutTo(int keep) {
      final String text =
          '${String.fromCharCodes(runes.take(keep)).trimRight()}$ellipsis';
      return MeasuredLabel(text, measurer.measure(text, style));
    }

    MeasuredLabel best = cutTo(0);
    if (!whole(best.size, angle, index, room: room)) {
      return null;
    }
    int low = 0;
    int high = runes.length - 1;
    while (low < high) {
      final int mid = (low + high + 1) ~/ 2;
      final MeasuredLabel tried = cutTo(mid);
      if (whole(tried.size, angle, index, room: room)) {
        low = mid;
        best = tried;
      } else {
        high = mid - 1;
      }
    }
    return best;
  }

  /// The plan that shows every [every]th of [drawn] at [angle], or `null`
  /// when it does not fit.
  CategoryLabelPlan? attempt(List<MeasuredLabel?> drawn, int angle, int every) {
    final List<int> shown = <int>[
      for (int i = 0; i < drawn.length; i += every) i,
    ];
    double thickness = 0;
    double before = 0;
    double after = 0;
    for (final int i in shown) {
      final MeasuredLabel? label = drawn[i];
      if (label == null) {
        return null;
      }
      thickness = math.max(thickness, depth(label.size, angle));
      final (double lo, double hi) = extent(label.size, angle, i);
      before = math.max(before, -lo);
      after = math.max(after, hi - axisLength);
    }
    if (thickness > maxDepth + _tolerance) {
      return null;
    }
    final bool roomy =
        before <= (angle == 0 ? roomBefore : turnedRoomBefore) + _tolerance &&
        after <= roomAfter + _tolerance;
    final double distance = every * band;
    for (int k = 1; k < shown.length; k++) {
      final ChartSize a = drawn[shown[k - 1]]!.size;
      final ChartSize b = drawn[shown[k]]!.size;
      final bool apart = vertical
          ? distance >= (a.height + b.height) / 2 + minTextGap
          : switch (angle) {
              0 => distance >= (a.width + b.width) / 2 + minTextGap,
              90 => distance >= math.max(a.height, b.height) + minTextGap,
              _ =>
                distance * math.sqrt1_2 >=
                    math.max(a.height, b.height) + minTextGap,
            };
      if (!apart) {
        return null;
      }
    }
    if (!roomy) {
      crampedAngles.add(angle);
      return null;
    }
    return CategoryLabelPlan(
      fits: true,
      thickness: thickness,
      rotationDegrees: angle == 0 ? 0 : -angle.toDouble(),
      shown: shown,
      labels: <MeasuredLabel>[for (final int i in shown) drawn[i]!],
      before: before,
      after: after,
    );
  }
}

/// The category labels of [plan] outside [plot], [offset] from it.
///
/// Under a horizontal axis a level label is centred on its category's tick
/// (the middle of its band) and a turned one has its end, the middle of its
/// right edge, at the tick; the top of every label's turned box is [offset]
/// below the plot. Beside a vertical one (a bar chart) each is right-aligned
/// [offset] left of the plot and centred on its band, the first category at
/// the bottom, as Excel draws it. A label keeps its category's index in its
/// id.
List<TextPrimitive> placeCategoryLabels(
  CategoryLabelPlan plan,
  int categoryCount,
  ChartRect plot,
  ChartTextStyle style, {
  required bool vertical,
  required double offset,
}) {
  final List<TextPrimitive> placed = <TextPrimitive>[];
  final double radians = -plan.rotationDegrees * math.pi / 180;
  final double sine = math.sin(radians);
  final double cosine = math.cos(radians);
  for (int k = 0; k < plan.shown.length; k++) {
    final int i = plan.shown[k];
    final MeasuredLabel label = plan.labels[k];
    final double w = label.size.width;
    final double h = label.size.height;
    final ChartRect rect;
    if (vertical) {
      final double cy = plot.bottom - (i + 0.5) * plot.height / categoryCount;
      rect = ChartRect(plot.left - offset - w, cy - h / 2, w, h);
    } else {
      final double tick = plot.left + (i + 0.5) * plot.width / categoryCount;
      final double top = plot.bottom + offset;
      if (plan.rotationDegrees == 0) {
        rect = ChartRect(tick - w / 2, top, w, h);
      } else {
        final double cx = tick - w / 2 * cosine;
        final double cy = top + w / 2 * sine + h / 2 * cosine;
        rect = ChartRect(cx - w / 2, cy - h / 2, w, h);
      }
    }
    placed.add(
      TextPrimitive(
        ids.axisLabelId(ids.categoryAxis, i),
        label.text,
        rect,
        style,
        rotationDegrees: plan.rotationDegrees,
      ),
    );
  }
  return placed;
}

/// A grid line at each tick of [scale] across [plot].
List<PathPrimitive> valueGridLines(
  ValueScale scale,
  ChartRect plot, {
  required bool horizontal,
  required ChartColor color,
  required double width,
}) {
  return <PathPrimitive>[
    for (int i = 0; i < scale.ticks.length; i++)
      _line(
        ids.gridId(ids.valueAxis, i),
        valuePosition(scale.ticks[i], scale, plot, horizontal: horizontal),
        plot,
        across: horizontal,
        color: color,
        width: width,
      ),
  ];
}

/// A grid line at each edge between [categories] bands across [plot], the two
/// outer edges included.
List<PathPrimitive> categoryGridLines(
  int categories,
  ChartRect plot, {
  required bool vertical,
  required ChartColor color,
  required double width,
}) {
  if (categories <= 0) {
    return const <PathPrimitive>[];
  }
  return <PathPrimitive>[
    for (int i = 0; i <= categories; i++)
      _line(
        ids.gridId(ids.categoryAxis, i),
        vertical
            ? plot.bottom - i * plot.height / categories
            : plot.left + i * plot.width / categories,
        plot,
        across: !vertical,
        color: color,
        width: width,
      ),
  ];
}

/// The value axis' line along the plot's left edge (vertical) or bottom edge
/// (horizontal).
PathPrimitive valueAxisLine(
  ChartRect plot, {
  required bool horizontal,
  required ChartColor color,
  required double width,
}) {
  return _line(
    ids.axisLineId(ids.valueAxis),
    horizontal ? plot.bottom : plot.left,
    plot,
    across: !horizontal,
    color: color,
    width: width,
  );
}

/// The category axis' line, at the value of [crossingValue] of [scale].
PathPrimitive categoryAxisLine(
  ValueScale scale,
  ChartRect plot, {
  required bool horizontal,
  required ChartColor color,
  required double width,
}) {
  return _line(
    ids.axisLineId(ids.categoryAxis),
    valuePosition(crossingValue(scale), scale, plot, horizontal: horizontal),
    plot,
    across: horizontal,
    color: color,
    width: width,
  );
}

/// A line at [at] across [plot]: vertical, at x = [at], when [across] is true;
/// horizontal, at y = [at], when it is false.
PathPrimitive _line(
  String id,
  double at,
  ChartRect plot, {
  required bool across,
  required ChartColor color,
  required double width,
}) {
  return PathPrimitive(
    id,
    across
        ? <ChartPoint>[ChartPoint(at, plot.top), ChartPoint(at, plot.bottom)]
        : <ChartPoint>[ChartPoint(plot.left, at), ChartPoint(plot.right, at)],
    stroke: color,
    strokeWidth: width,
  );
}
