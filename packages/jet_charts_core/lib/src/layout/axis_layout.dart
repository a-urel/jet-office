/// The axes of a cartesian chart: tick labels, category labels, grid lines and
/// axis lines.
///
/// The value axis is vertical at the left of the plot for column, line and
/// area charts and horizontal under it for bar charts; the category axis takes
/// the other side. Tick labels sit outside the plot, `labelGap` from it, and
/// never inside the plot. Category labels never collide: [planCategoryLabels]
/// wraps, skips, then turns, then cuts them, and [placeCategoryLabels] puts
/// them down.
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
/// axis of [plot], when every [stride]-th of them is drawn (from the first).
///
/// Vertical, adjacent drawn labels' centres must lie half their heights plus
/// the gap apart; horizontal, half their widths plus the gap.
bool valueLabelsFit(
  List<MeasuredLabel> labels,
  ValueScale scale,
  ChartRect plot, {
  required bool horizontal,
  required double minTextGap,
  int stride = 1,
}) {
  for (
    int i = stride;
    i < labels.length && i < scale.ticks.length;
    i += stride
  ) {
    final double distance =
        (valuePosition(scale.ticks[i], scale, plot, horizontal: horizontal) -
                valuePosition(
                  scale.ticks[i - stride],
                  scale,
                  plot,
                  horizontal: horizontal,
                ))
            .abs();
    final ChartSize a = labels[i - stride].size;
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

/// The value axis' tick labels of [scale], outside [plot]: every [stride]-th
/// of them, from the first.
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
  int stride = 1,
}) {
  return <TextPrimitive>[
    for (int i = 0; i < labels.length && i < scale.ticks.length; i += stride)
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

/// The position of category [index] of [categories] along a category axis of
/// [length], from the axis' start.
///
/// Between tick marks (columns, bars and lines), a category sits in the middle
/// of its band, `(index + 0.5) * length / categories`. On tick marks
/// ([onTicks], an area chart, as Excel draws one: `c:crossBetween midCat`), the
/// first category sits at the axis' start and the last at its end,
/// `index * length / (categories - 1)`; a lone category sits in the middle.
double categoryPosition(
  int index,
  int categories,
  double length, {
  required bool onTicks,
}) {
  if (onTicks && categories > 1) {
    return index * length / (categories - 1);
  }
  return (index + 0.5) * length / math.max(1, categories);
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
    this.reserveAfter = 0,
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

  /// The shown labels as drawn, one for each of [shown]: the full text, the
  /// text wrapped onto lines at spaces (see [isWrappingOf]), or the text cut
  /// with `…`.
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

  /// The room past the axis' end that the labels ask the frame to keep: on
  /// tick marks, the reach of the last label as if its tick were at the axis'
  /// end (half its width at 0 degrees, half its height at -90 degrees and
  /// beside a vertical axis, and at -45 degrees that of its turned box's
  /// lower corner); between tick marks 0, as those labels use only the room
  /// the frame has anyway.
  final double reserveAfter;

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
      reserveAfter == other.reserveAfter &&
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
    reserveAfter,
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

/// The most lines a level category label is wrapped onto.
const int maxWrappedLines = 3;

/// Whether [drawn] is [text] whole: equal to it, or wrapped, with some of
/// its spaces turned into line breaks and nothing else changed.
bool isWrappingOf(String drawn, String text) {
  if (drawn == text) {
    return true;
  }
  if (drawn.length != text.length) {
    return false;
  }
  for (int i = 0; i < drawn.length; i++) {
    final int a = drawn.codeUnitAt(i);
    final int b = text.codeUnitAt(i);
    if (a != b && (a != 0x0A || b != 0x20)) {
      return false;
    }
  }
  return true;
}

/// Plans the category [labels] along an axis of [axisLength], their band at
/// most [maxDepth] deep (40% of the space left for the plot and the band,
/// less the labels' offset from the plot).
///
/// Under a horizontal axis it tries, in order, 0 degrees showing every label;
/// 0 degrees showing every label, each wrapped at spaces onto at most
/// [maxWrappedLines] lines no wider than its slot (the distance between
/// ticks less `minTextGap`; a word wider than the slot cannot wrap and fails
/// the try), as Excel for Mac keeps long labels level on two lines (the
/// owner's J3 gallery check, `column_long_labels`); 0 degrees showing every
/// second label; then -45 degrees for `N` = 1, 2, 3; then -90 degrees for
/// `N` = 1, 2, … until they fit. Level labels skip at most every second
/// because Excel's label spacing never exceeded 2 in the owner's full run
/// (the C group, 3 to 30 characters at 180 to 720 points wide). Shown
/// labels fit when no two come closer than `minTextGap`, their band is no
/// deeper than [maxDepth], and they reach no further than [roomBefore]
/// before the axis' start and [roomAfter] past its end: the room the frame
/// has there anyway, which the labels never widen, so the plot does not
/// depend on them along the axis. At -45 and -90 degrees, and beside a
/// vertical axis, the room before is [turnedRoomBefore], which also holds
/// what the frame keeps for a plan's [CategoryLabelPlan.reserveBefore]. A
/// plan that fails only for want of room is [CategoryLabelPlan.cramped]. At
/// -45 and -90 degrees a label deeper than [maxDepth] is cut with `…`, and
/// at -45 degrees also one that would reach further than [turnedRoomBefore];
/// at 0 degrees none is. A turned label's end sits at its tick.
///
/// Beside a vertical axis (`vertical`, a bar chart) labels stay level: every
/// label wider than [maxDepth] is cut, and every `N`th is shown for the least
/// `N` that keeps them apart and within the room.
///
/// On tick marks ([onTicks], an area chart) each label's tick is its
/// category's [categoryPosition], so the first and last labels reach past
/// the axis' ends: shown labels are kept apart by the distance between their
/// ticks, the room before is [turnedRoomBefore] at every angle, and the plan
/// asks the frame for [CategoryLabelPlan.reserveBefore] and
/// [CategoryLabelPlan.reserveAfter] so that both stand whole within the
/// chart.
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
  bool onTicks = false,
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
    onTicks: onTicks,
  );
  if (!(planner.step > 0) || !(maxDepth > 0) || !axisLength.isFinite) {
    return CategoryLabelPlan(fits: false);
  }
  // A try is an angle, a stride and whether level labels are wrapped.
  final List<(int, int, bool)> tries = vertical
      ? <(int, int, bool)>[
          for (int n = 1; n <= labels.length; n++) (0, n, false),
        ]
      : <(int, int, bool)>[
          (0, 1, false),
          (0, 1, true),
          (0, 2, false),
          for (int n = 1; n <= 3; n++) (45, n, false),
          for (int n = 1; n <= labels.length; n++) (90, n, false),
        ];
  final Map<int, List<MeasuredLabel?>> cut = <int, List<MeasuredLabel?>>{};
  List<MeasuredLabel>? wrapped;
  bool wrapTried = false;
  for (final (int angle, int every, bool wrap) in tries) {
    final List<MeasuredLabel?> drawn;
    if (wrap) {
      if (!wrapTried) {
        wrapTried = true;
        wrapped = planner.wrap(measurer, style);
      }
      if (wrapped == null) {
        continue;
      }
      drawn = wrapped;
    } else {
      drawn = angle == 0 && !vertical
          ? labels
          : cut.putIfAbsent(angle, () => planner.cut(angle, measurer, style));
    }
    final CategoryLabelPlan? plan = planner.attempt(drawn, angle, every);
    if (plan != null) {
      return planner.reserved(plan, angle, drawn, measurer, style);
    }
  }
  if (planner.cramped.isEmpty) {
    return CategoryLabelPlan(fits: false);
  }
  double reserve = 0;
  double reserveAfter = 0;
  for (final (int angle, List<MeasuredLabel?> drawn, bool _)
      in planner.cramped) {
    reserve = math.max(reserve, planner.reserve(angle, drawn, measurer, style));
    reserveAfter = math.max(
      reserveAfter,
      planner.reserveAfter(angle, drawn, measurer, style),
    );
  }
  return CategoryLabelPlan(
    fits: false,
    cramped: true,
    reserveBefore: reserve,
    reserveAfter: reserveAfter,
  );
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
    required this.onTicks,
  }) : step = onTicks && labels.length > 1
           ? axisLength / (labels.length - 1)
           : axisLength / labels.length;

  final List<MeasuredLabel> labels;
  final double axisLength;

  /// The distance between adjacent categories' ticks.
  final double step;
  final double maxDepth;
  final double roomBefore;
  final double turnedRoomBefore;
  final double roomAfter;
  final double minTextGap;
  final bool vertical;
  final bool onTicks;

  static const double _tolerance = 1e-9;

  /// The angles, the labels as drawn, and whether they would still keep
  /// apart on the axis shortened by the room they lack, of the tries that
  /// failed only for want of room past the axis' ends.
  final List<(int, List<MeasuredLabel?>, bool)> cramped =
      <(int, List<MeasuredLabel?>, bool)>[];

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
    final double tick = categoryPosition(
      index,
      labels.length,
      axisLength,
      onTicks: onTicks,
    );
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

  /// [labels], each wrapped at spaces onto at most [maxWrappedLines] lines
  /// no wider than the slot ([step] less [minTextGap]); `null` when some
  /// label cannot be, or when wrapping changes no label.
  List<MeasuredLabel>? wrap(TextMeasurer measurer, ChartTextStyle style) {
    final double slot = step - minTextGap;
    if (!(slot > 0)) {
      return null;
    }
    bool changed = false;
    final List<MeasuredLabel> wrapped = <MeasuredLabel>[];
    for (final MeasuredLabel label in labels) {
      final MeasuredLabel? one = wrapOne(label, slot, measurer, style);
      if (one == null) {
        return null;
      }
      changed = changed || !identical(one, label);
      wrapped.add(one);
    }
    return changed ? wrapped : null;
  }

  /// [label] wrapped at spaces onto lines no wider than [slot], each line
  /// taking as many words as fit; [label] itself when it fits whole, and
  /// `null` when a word is wider than [slot] or more than
  /// [maxWrappedLines] lines are needed.
  MeasuredLabel? wrapOne(
    MeasuredLabel label,
    double slot,
    TextMeasurer measurer,
    ChartTextStyle style,
  ) {
    if (label.size.width <= slot + _tolerance) {
      return label;
    }
    bool fits(String text) =>
        measurer.measure(text, style).width <= slot + _tolerance;
    final List<String> lines = <String>[];
    for (final String line in label.text.split('\n')) {
      final List<String> words = line.split(' ');
      String current = words.first;
      for (final String word in words.skip(1)) {
        final String joined = '$current $word';
        if (fits(joined)) {
          current = joined;
        } else {
          if (!fits(current)) {
            return null;
          }
          lines.add(current);
          current = word;
        }
        if (lines.length >= maxWrappedLines) {
          return null;
        }
      }
      if (!fits(current)) {
        return null;
      }
      lines.add(current);
      if (lines.length > maxWrappedLines) {
        return null;
      }
    }
    final String text = lines.join('\n');
    return MeasuredLabel(text, measurer.measure(text, style));
  }

  /// [plan], tried at [angle] with the labels as [drawn], with its
  /// [CategoryLabelPlan.reserveBefore] and [CategoryLabelPlan.reserveAfter].
  ///
  /// When an earlier level try failed only for want of room (on tick marks,
  /// where level labels reach past the axis' ends) and would still keep
  /// apart on the axis shortened by that room, the reserves are at least
  /// that try's, so the frame keeps the room and the level labels fit on its
  /// next plan.
  CategoryLabelPlan reserved(
    CategoryLabelPlan plan,
    int angle,
    List<MeasuredLabel?> drawn,
    TextMeasurer measurer,
    ChartTextStyle style,
  ) {
    double before = reserve(angle, drawn, measurer, style);
    double after = reserveAfter(angle, drawn, measurer, style);
    for (final (int crampedAngle, List<MeasuredLabel?> level, bool shorter)
        in cramped) {
      if (crampedAngle == 0 && shorter) {
        before = math.max(before, reserve(0, level, measurer, style));
        after = math.max(after, reserveAfter(0, level, measurer, style));
      }
    }
    return CategoryLabelPlan(
      fits: plan.fits,
      thickness: plan.thickness,
      rotationDegrees: plan.rotationDegrees,
      shown: plan.shown,
      labels: plan.labels,
      before: plan.before,
      after: plan.after,
      reserveBefore: before,
      reserveAfter: after,
    );
  }

  /// The [CategoryLabelPlan.reserveBefore] of a try at [angle] with the
  /// labels as [drawn] (level ones may be wrapped).
  double reserve(
    int angle,
    List<MeasuredLabel?> drawn,
    TextMeasurer measurer,
    ChartTextStyle style,
  ) {
    if (vertical || angle == 90) {
      return labels.first.size.height / 2;
    }
    if (angle == 45) {
      final MeasuredLabel? first = cutOne(0, 45, measurer, style, room: false);
      final ChartSize size = first?.size ?? const ChartSize(0, 0);
      return (size.width + size.height / 2) * math.sqrt1_2;
    }
    return onTicks ? (drawn.first ?? labels.first).size.width / 2 : 0;
  }

  /// The [CategoryLabelPlan.reserveAfter] of a try at [angle] with the
  /// labels as [drawn] (level ones may be wrapped).
  double reserveAfter(
    int angle,
    List<MeasuredLabel?> drawn,
    TextMeasurer measurer,
    ChartTextStyle style,
  ) {
    if (!onTicks) {
      return 0;
    }
    final int last = labels.length - 1;
    if (vertical || angle == 90) {
      return labels[last].size.height / 2;
    }
    if (angle == 45) {
      final MeasuredLabel? label = cutOne(
        last,
        45,
        measurer,
        style,
        room: false,
      );
      return (label?.size.height ?? 0) / 2 * math.sqrt1_2;
    }
    return (drawn[last] ?? labels[last]).size.width / 2;
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
    final double shortBefore = math.max(
      0,
      before - (angle == 0 && !onTicks ? roomBefore : turnedRoomBefore),
    );
    final double shortAfter = math.max(0, after - roomAfter);
    final bool roomy = shortBefore <= _tolerance && shortAfter <= _tolerance;
    bool apart(double distance) {
      for (int k = 1; k < shown.length; k++) {
        final ChartSize a = drawn[shown[k - 1]]!.size;
        final ChartSize b = drawn[shown[k]]!.size;
        final bool fits = vertical
            ? distance >= (a.height + b.height) / 2 + minTextGap
            : switch (angle) {
                0 => distance >= (a.width + b.width) / 2 + minTextGap,
                90 => distance >= math.max(a.height, b.height) + minTextGap,
                _ =>
                  distance * math.sqrt1_2 >=
                      math.max(a.height, b.height) + minTextGap,
              };
        if (!fits) {
          return false;
        }
      }
      return true;
    }

    final double distance = every * step;
    if (!apart(distance)) {
      return null;
    }
    if (!roomy) {
      // Whether the labels would still keep apart on the axis shortened by
      // the room they lack, which the frame takes from the plot.
      final double shorter = axisLength > 0
          ? distance * (axisLength - shortBefore - shortAfter) / axisLength
          : 0;
      cramped.add((angle, drawn, apart(shorter)));
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
/// the bottom, as Excel draws it. On tick marks ([onTicks], an area chart)
/// a label's tick is its category's [categoryPosition] instead of its band's
/// middle. A label keeps its category's index in its id.
List<TextPrimitive> placeCategoryLabels(
  CategoryLabelPlan plan,
  int categoryCount,
  ChartRect plot,
  ChartTextStyle style, {
  required bool vertical,
  required double offset,
  bool onTicks = false,
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
      final double cy =
          plot.bottom -
          categoryPosition(i, categoryCount, plot.height, onTicks: onTicks);
      rect = ChartRect(plot.left - offset - w, cy - h / 2, w, h);
    } else {
      final double tick =
          plot.left +
          categoryPosition(i, categoryCount, plot.width, onTicks: onTicks);
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

/// Edge [i] of the [categories] bands of [plot] along the category axis, from
/// its start: an x for a horizontal axis (edge 0 the plot's left), a y for a
/// [vertical] one (edge 0 the plot's bottom, as a bar chart's first category
/// sits at the bottom). Edge `categories` is the axis' end. Between tick
/// marks the category grid lines and [categoryBands] both take their edges
/// from here. On tick marks ([onTicks], an area chart) an inner edge lies
/// halfway between the [categoryPosition]s of its two categories, and the
/// outer edges are the axis' ends.
double categoryEdge(
  int i,
  int categories,
  ChartRect plot, {
  required bool vertical,
  bool onTicks = false,
}) {
  final double length = vertical ? plot.height : plot.width;
  final double along;
  if (!onTicks || i <= 0 || i >= categories) {
    along = i * length / categories;
  } else {
    along =
        (categoryPosition(i - 1, categories, length, onTicks: true) +
            categoryPosition(i, categories, length, onTicks: true)) /
        2;
  }
  return vertical ? plot.bottom - along : plot.left + along;
}

/// The band of each of [categories] across [plot], in category order: the
/// slice between [categoryEdge] `i` and `i + 1`, the plot's full height
/// across a horizontal axis, its full width beside a [vertical] one. On tick
/// marks ([onTicks]) the edges lie halfway between categories, so a point
/// falls in the band of the nearest category. Empty for no categories.
List<ChartRect> categoryBands(
  int categories,
  ChartRect plot, {
  required bool vertical,
  bool onTicks = false,
}) {
  if (categories <= 0) {
    return const <ChartRect>[];
  }
  return <ChartRect>[
    for (int i = 0; i < categories; i++)
      if (vertical)
        ChartRect(
          plot.left,
          categoryEdge(
            i + 1,
            categories,
            plot,
            vertical: true,
            onTicks: onTicks,
          ),
          plot.width,
          categoryEdge(i, categories, plot, vertical: true, onTicks: onTicks) -
              categoryEdge(
                i + 1,
                categories,
                plot,
                vertical: true,
                onTicks: onTicks,
              ),
        )
      else
        ChartRect(
          categoryEdge(i, categories, plot, vertical: false, onTicks: onTicks),
          plot.top,
          categoryEdge(
                i + 1,
                categories,
                plot,
                vertical: false,
                onTicks: onTicks,
              ) -
              categoryEdge(
                i,
                categories,
                plot,
                vertical: false,
                onTicks: onTicks,
              ),
          plot.height,
        ),
  ];
}

/// A grid line at each edge between [categories] bands across [plot], the two
/// outer edges included; on tick marks ([onTicks], an area chart) one through
/// each category's [categoryPosition] instead.
List<PathPrimitive> categoryGridLines(
  int categories,
  ChartRect plot, {
  required bool vertical,
  required ChartColor color,
  required double width,
  bool onTicks = false,
}) {
  if (categories <= 0) {
    return const <PathPrimitive>[];
  }
  if (onTicks) {
    final double length = vertical ? plot.height : plot.width;
    return <PathPrimitive>[
      for (int i = 0; i < categories; i++)
        _line(
          ids.gridId(ids.categoryAxis, i),
          vertical
              ? plot.bottom -
                    categoryPosition(i, categories, length, onTicks: true)
              : plot.left +
                    categoryPosition(i, categories, length, onTicks: true),
          plot,
          across: !vertical,
          color: color,
          width: width,
        ),
    ];
  }
  return <PathPrimitive>[
    for (int i = 0; i <= categories; i++)
      _line(
        ids.gridId(ids.categoryAxis, i),
        categoryEdge(i, categories, plot, vertical: vertical),
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
