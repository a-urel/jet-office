/// The data labels of a pie or donut: inside their slices, or for a pie
/// outside it, with leader lines, and never over another text or slice.
library;

import 'dart:math' as math;

import '../theme/chart_color.dart';
import '../theme/chart_theme.dart';
import 'chart_ids.dart' as ids;
import 'data_labels.dart' show insideLabelStyle;
import 'geometry.dart';
import 'overlap.dart';
import 'polar.dart';
import 'primitives.dart';
import 'text_measurer.dart';

/// One slice of a pie or donut and the label it asks for.
final class PieSlice {
  /// Creates the slice of [series] at [category], drawn as [arc], from the
  /// clock angle [startClock] over [sweep] degrees, with the label [label].
  const PieSlice({
    required this.series,
    required this.category,
    required this.arc,
    required this.startClock,
    required this.sweep,
    this.label,
  });

  /// The series.
  final int series;

  /// The category.
  final int category;

  /// The slice as it is drawn.
  final ArcPrimitive arc;

  /// Where the slice starts, as a clock angle (`polar.dart`).
  final double startClock;

  /// The slice's sweep in degrees, clockwise.
  final double sweep;

  /// The text of the slice's data label, or `null` when it has none.
  final String? label;

  /// The clock angle of the slice's middle.
  double get middle => startClock + sweep / 2;

  /// The id of the slice's data label.
  String get labelId => ids.dataLabelId(series, category);
}

/// The data labels of a pie or donut that were placed, their leader lines,
/// and the texts that were not placed.
final class PieLabelPlacement {
  /// Creates a placement.
  const PieLabelPlacement({
    required this.labels,
    required this.leaders,
    required this.hidden,
    required this.tallestOutside,
  });

  /// The placed labels, in series then category order.
  final List<TextPrimitive> labels;

  /// The leader lines of labels placed outside, in category order.
  final List<PathPrimitive> leaders;

  /// The id and text of each label that found no place.
  final List<(String, String)> hidden;

  /// The height of the tallest label that did not fit inside its slice and
  /// was tried outside the pie, or `null` when none was.
  final double? tallestOutside;
}

/// Places the labels of [slices] around [center], clear of the texts, the
/// legend and the slices of [existing], inside [bounds].
///
/// The rule, in order:
///
/// 1. Each label is first tried inside its slice, centred on the slice's
///    middle angle at 0.6 of the radius in a pie, or in the middle of its
///    ring in a donut. It fits when its box lies within the slice's outer
///    radius and outside its inner one (and, in a pie, does not hold the
///    centre unless the slice is the whole disc), shares no area with
///    another slice or leader line (as `findOverlaps` reads them) and keeps
///    `minTextGap` from every text. Inside a slice its colour reads against
///    the fill (`insideLabelStyle`), as a label inside a bar does.
/// 2. In a donut ([outside] false) a label that does not fit is hidden.
/// 3. In a pie the others are tried outside: first at `labelGap` beyond the
///    slices' reach (`arcShapeReach`) along the middle angle, on the right
///    of the pie when that angle is below 180 degrees, else on the left,
///    with its edge towards the pie as close to it as that gap allows. On
///    each side the labels, from the top, are then pushed apart to
///    `minTextGap` (downwards first, then upwards from the bottom of
///    [bounds]), and each again drawn as close to the pie as the gap allows
///    at its new height. A label more than `labelGap` from its first place
///    gets a leader line: from its slice's outer edge out along the middle
///    angle to half `labelGap` beyond the slices' reach, then straight to
///    the nearest point of the label's box. While that second segment would
///    come closer to the centre than the radius and half the outline, the
///    label moves away from the pie, a point at a time, so no part of the
///    line enters the pie. It is drawn in the theme's axis line colour and
///    width (an estimate, not checked in Excel). The labels are then taken
///    in category order: one that leaves [bounds], meets another slice or
///    leader line, keeps less than `minTextGap` from a text, or whose leader
///    line meets a text, is hidden with its leader line.
///
/// A label is never placed over another one, and every one placed lies
/// inside [bounds].
PieLabelPlacement placePieLabels({
  required List<PieSlice> slices,
  required ChartPoint center,
  required ChartRect bounds,
  required List<ChartPrimitive> existing,
  required bool outside,
  required ChartTheme theme,
  required TextMeasurer measurer,
}) {
  final ChartTextStyle style = theme.dataLabels;
  final double gap = theme.spacing.labelGap;
  final double apart = theme.spacing.minTextGap;
  final BoxGrid<TextPrimitive> taken = BoxGrid<TextPrimitive>();
  for (final ChartPrimitive p in existing) {
    if (p is TextPrimitive) {
      taken.add(p, p.bounds);
    } else if (p is RectPrimitive && p.id == ids.legend) {
      taken.add(TextPrimitive(p.id, '', p.rect, style), p.rect);
    }
  }
  final BoxGrid<LaidMark> marks = BoxGrid<LaidMark>();
  for (final LaidMark m in laidMarks(existing)) {
    if (m.box != null) {
      marks.add(m, m.box!);
    }
  }

  bool clearOfMarks(TextPrimitive label) => !marks.any(
    label.bounds,
    (LaidMark m) =>
        !isOwnMark(label.id, m.mark.id) && textOverlapsMark(label, m),
  );

  bool clearOfTexts(TextPrimitive label) {
    final TextPrimitive probe = TextPrimitive(
      label.id,
      label.text,
      ChartRect(
        label.rect.left - apart,
        label.rect.top - apart,
        label.rect.width + 2 * apart,
        label.rect.height + 2 * apart,
      ),
      style,
    );
    return !taken.any(
      probe.bounds,
      (TextPrimitive o) => textsOverlap(probe, o),
    );
  }

  final Map<String, TextPrimitive> placed = <String, TextPrimitive>{};
  final Set<String> hiddenIds = <String>{};
  final List<_Outside> tryOutside = <_Outside>[];
  for (final PieSlice slice in slices) {
    final String? text = slice.label;
    if (text == null) {
      continue;
    }
    final ChartSize size = measurer.measure(text, style);
    final ArcPrimitive arc = slice.arc;
    final double r = arc.innerRadius > 0
        ? (arc.radius + arc.innerRadius) / 2
        : 0.6 * arc.radius;
    final ChartPoint c = polarPoint(arc.center, r, slice.middle);
    final ChartRect rect = ChartRect(
      c.x - size.width / 2,
      c.y - size.height / 2,
      size.width,
      size.height,
    );
    final TextPrimitive label = TextPrimitive(
      slice.labelId,
      text,
      rect,
      insideLabelStyle(style, theme.background, arc.fill ?? style.color),
    );
    if (_inRing(rect, slice) &&
        bounds.contains(rect) &&
        clearOfMarks(label) &&
        clearOfTexts(label)) {
      placed[label.id] = label;
      taken.add(label, label.bounds);
    } else if (outside) {
      tryOutside.add(_Outside(slice, text, size));
    } else {
      hiddenIds.add(label.id);
    }
  }

  final List<PathPrimitive> leaders = <PathPrimitive>[];
  double? tallest;
  if (tryOutside.isNotEmpty) {
    final ArcPrimitive any = tryOutside.first.slice.arc;
    final double reach =
        arcShapeReach(
          any.radius,
          any.strokeWidth,
          stroked: any.stroke != null,
        ) +
        gap;
    for (final _Outside o in tryOutside) {
      tallest = math.max(tallest ?? 0, o.size.height);
      final double theta = o.slice.middle % 360;
      o.right = theta < 180;
      final ChartPoint p = polarPoint(center, reach, theta);
      final double down = -math.cos(theta * math.pi / 180);
      o.firstTop = p.y + down * o.size.height / 2 - o.size.height / 2;
      o.top = o.firstTop;
    }
    for (final bool right in <bool>[true, false]) {
      final List<_Outside> side =
          tryOutside.where((_Outside o) => o.right == right).toList()..sort(
            (_Outside a, _Outside b) => a.firstTop.compareTo(b.firstTop),
          );
      for (int i = 1; i < side.length; i++) {
        side[i].top = math.max(
          side[i].top,
          side[i - 1].top + side[i - 1].size.height + apart,
        );
      }
      if (side.isNotEmpty) {
        side.last.top = math.min(
          side.last.top,
          bounds.bottom - side.last.size.height,
        );
      }
      for (int i = side.length - 2; i >= 0; i--) {
        side[i].top = math.min(
          side[i].top,
          side[i + 1].top - apart - side[i].size.height,
        );
      }
    }
    for (final _Outside o in tryOutside) {
      final ChartRect first = _hug(o, o.firstTop, center, reach);
      ChartRect rect = _hug(o, o.top, center, reach);
      PathPrimitive? leader;
      final double moved = math.sqrt(
        math.pow(rect.left - first.left, 2) + math.pow(rect.top - first.top, 2),
      );
      if (moved > gap) {
        // Out along the middle angle to halfway into the gap, then
        // straight to the nearest point of the label, which moves away from
        // the pie, a point at a time, until that segment keeps clear of the
        // pie's outline. No part of the line enters the pie.
        final ArcPrimitive arc = o.slice.arc;
        final double clear =
            arc.radius + (arc.stroke == null ? 0 : arc.strokeWidth / 2);
        final ChartPoint from = polarPoint(center, arc.radius, o.slice.middle);
        final ChartPoint out = polarPoint(
          center,
          reach - gap / 2,
          o.slice.middle,
        );
        ChartPoint nearest(ChartRect r) => ChartPoint(
          out.x.clamp(r.left, r.right),
          out.y.clamp(r.top, r.bottom),
        );
        final double step = o.right ? 1 : -1;
        while (_segmentDistance(out, nearest(rect), center) < clear &&
            rect.left >= bounds.left - o.size.width &&
            rect.right <= bounds.right + o.size.width) {
          rect = ChartRect(rect.left + step, rect.top, rect.width, rect.height);
        }
        leader = PathPrimitive(
          ids.dataLabelLeaderId(o.slice.series, o.slice.category),
          <ChartPoint>[from, out, nearest(rect)],
          stroke: theme.axisLine,
          strokeWidth: theme.spacing.axisLineWidth,
        );
      }
      final TextPrimitive label = TextPrimitive(
        o.slice.labelId,
        o.text,
        rect,
        style,
      );
      final LaidMark? laid = leader == null ? null : LaidMark(leader, null);
      final bool fits =
          bounds.contains(rect) &&
          clearOfMarks(label) &&
          clearOfTexts(label) &&
          (laid == null ||
              laid.box == null ||
              !taken.any(
                laid.box!,
                (TextPrimitive t) =>
                    t.id != label.id && textOverlapsMark(t, laid),
              ));
      if (!fits) {
        hiddenIds.add(label.id);
        continue;
      }
      placed[label.id] = label;
      taken.add(label, label.bounds);
      if (leader != null) {
        leaders.add(leader);
        if (laid!.box != null) {
          marks.add(laid, laid.box!);
        }
      }
    }
  }
  final List<TextPrimitive> labels = <TextPrimitive>[];
  final List<(String, String)> hidden = <(String, String)>[];
  for (final PieSlice slice in slices) {
    if (slice.label == null) {
      continue;
    }
    final TextPrimitive? label = placed[slice.labelId];
    if (label != null) {
      labels.add(label);
    } else if (hiddenIds.contains(slice.labelId)) {
      hidden.add((slice.labelId, slice.label!));
    }
  }
  leaders.sort(
    (PathPrimitive a, PathPrimitive b) => _order(a.id).compareTo(_order(b.id)),
  );
  return PieLabelPlacement(
    labels: labels,
    leaders: leaders,
    hidden: hidden,
    tallestOutside: tallest,
  );
}

/// The category of the leader line [id], `label/<s>/<c>/leader`.
int _order(String id) => int.parse(id.split('/')[2]);

/// A label tried outside the pie, and where it goes.
final class _Outside {
  _Outside(this.slice, this.text, this.size);

  final PieSlice slice;
  final String text;
  final ChartSize size;

  /// Whether it goes on the pie's right.
  bool right = true;

  /// The top of its first place.
  double firstTop = 0;

  /// The top it was pushed to.
  double top = 0;
}

/// The box of [o] with its top at [top], on its side of the pie, with its
/// edge towards [center] as close as [reach] from it allows.
ChartRect _hug(_Outside o, double top, ChartPoint center, double reach) {
  final double bottom = top + o.size.height;
  final double dy = center.y < top
      ? top - center.y
      : center.y > bottom
      ? center.y - bottom
      : 0;
  final double dx = math.sqrt(math.max(0, reach * reach - dy * dy));
  final double left = o.right ? center.x + dx : center.x - dx - o.size.width;
  return ChartRect(left, top, o.size.width, o.size.height);
}

/// Whether [rect] lies within [slice]'s outer radius and outside its inner
/// one, and, in a pie slice that is not the whole disc, does not hold the
/// centre.
bool _inRing(ChartRect rect, PieSlice slice) {
  final ArcPrimitive arc = slice.arc;
  final ChartPoint c = arc.center;
  for (final ChartPoint corner in <ChartPoint>[
    ChartPoint(rect.left, rect.top),
    ChartPoint(rect.right, rect.top),
    ChartPoint(rect.right, rect.bottom),
    ChartPoint(rect.left, rect.bottom),
  ]) {
    final double dx = corner.x - c.x;
    final double dy = corner.y - c.y;
    if (dx * dx + dy * dy > arc.radius * arc.radius) {
      return false;
    }
  }
  final double near = distanceToRect(c, rect);
  if (arc.innerRadius > 0) {
    return near >= arc.innerRadius;
  }
  return slice.sweep >= 360 || near > 0;
}

/// The least distance from [p] to the segment from [a] to [b].
double _segmentDistance(ChartPoint a, ChartPoint b, ChartPoint p) {
  final double dx = b.x - a.x;
  final double dy = b.y - a.y;
  final double lengthSquared = dx * dx + dy * dy;
  final double t = lengthSquared > 0
      ? (((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared).clamp(0.0, 1.0)
      : 0;
  final double x = a.x + t * dx - p.x;
  final double y = a.y + t * dy - p.y;
  return math.sqrt(x * x + y * y);
}
