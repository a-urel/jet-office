/// Data labels: the value of each point, placed without overlap.
///
/// A label takes the first of its candidate places that lies where that place
/// allows (see [placeDataLabels]), keeps the minimum text gap from every text
/// already drawn (axis labels, titles, the legend) and every label already
/// placed, stays off the legend's rectangle and shares no area with a series
/// mark other than its own bar or its own series' area (`findOverlaps`'s
/// rule). Labels are placed in series order, then category order, so an
/// earlier one wins a place. A label with no such place is hidden.
library;

import 'dart:math' as math;

import 'package:jet_core/jet_core.dart';

import '../model/chart.dart';
import '../model/chart_kind.dart';
import '../scale/value_scale.dart';
import '../theme/chart_color.dart';
import '../theme/chart_theme.dart';
import 'axis_layout.dart';
import 'chart_ids.dart' as ids;
import 'geometry.dart';
import 'marks.dart';
import 'overlap.dart';
import 'primitives.dart';
import 'resolve.dart';
import 'text_measurer.dart';

/// The data labels that were placed, and the texts that were not.
final class DataLabelPlacement {
  /// Creates a placement of [primitives] and [hidden].
  const DataLabelPlacement(this.primitives, this.hidden);

  /// The placed labels, in series then category order.
  final List<TextPrimitive> primitives;

  /// The id and full text of each label that found no place.
  final List<(String, String)> hidden;
}

/// The id and text of every data label [chart] asks for, in series then
/// category order: one per value that is not missing.
///
/// A label's number format code is the data labels' code, else its series',
/// else `General`.
List<(String, String)> dataLabelTexts(
  Chart chart,
  ResolvedChart resolved,
  NumberFormatter formatter,
) {
  if (!chart.dataLabels.visible) {
    return const <(String, String)>[];
  }
  return <(String, String)>[
    for (int s = 0; s < resolved.values.length; s++)
      for (int c = 0; c < resolved.values[s].length; c++)
        if (resolved.values[s][c] != null)
          (
            ids.dataLabelId(s, c),
            formatTick(
              resolved.values[s][c]!,
              chart.dataLabels.formatCode ??
                  (s < chart.series.length
                      ? chart.series[s].formatCode
                      : null) ??
                  'General',
              formatter,
            ),
          ),
  ];
}

/// Places the data labels of [chart] on [plot], clear of the texts, the
/// legend and the marks of [existing].
///
/// A clustered column or bar label tries outside end, then inside end; a
/// stacked one only the centre of its bar. Outside end may leave the plot
/// but not [area] (the chart's area inside its padding), as Excel's label of
/// a bar that reaches the axis' maximum sits above the plot; a label inside a
/// bar must lie wholly inside the bar's visible part, and is drawn white
/// (`FFFFFF`) when the bar's colour has a relative luminance below 0.5, so
/// it reads on a dark bar, else in the theme's data label colour. Line labels
/// try above, below, right, then left of the point; an area label is centred
/// on the column under its point, halfway between the point and the area's
/// base; both must lie inside the plot. Nothing is placed unless the chart
/// asks for data labels.
DataLabelPlacement placeDataLabels({
  required Chart chart,
  required ResolvedChart resolved,
  required ChartTheme theme,
  required TextMeasurer measurer,
  required NumberFormatter formatter,
  required ChartRect plot,
  required ChartRect area,
  required ValueScale scale,
  required List<ChartPrimitive> existing,
}) {
  final List<(String, String)> texts = dataLabelTexts(
    chart,
    resolved,
    formatter,
  );
  if (texts.isEmpty) {
    return const DataLabelPlacement(<TextPrimitive>[], <(String, String)>[]);
  }
  final Map<String, String> textById = <String, String>{
    for (final (String, String) t in texts) t.$1: t.$2,
  };
  final Map<String, MarkAnchor> anchors = <String, MarkAnchor>{
    for (final MarkAnchor a in layoutAnchors(
      chart,
      resolved,
      theme,
      plot,
      scale,
    ))
      ids.dataLabelId(a.series, a.category): a,
  };
  final List<TextPrimitive> obstacles = <TextPrimitive>[
    for (final ChartPrimitive p in _flat(existing))
      if (p is TextPrimitive) p,
  ];
  // The legend's rectangle, as a text no label may enter.
  for (final ChartPrimitive p in _flat(existing)) {
    if (p is RectPrimitive && p.id == ids.legend) {
      obstacles.add(TextPrimitive(p.id, '', p.rect, theme.dataLabels));
    }
  }
  final List<LaidMark> marks = laidMarks(existing);
  final bool bar = chart.kind == ChartKind.bar;
  final bool stacked = resolved.grouping != ChartGrouping.clustered;
  final double crossing = crossingValue(scale);
  final double gap = theme.spacing.labelGap;
  final double apart = theme.spacing.minTextGap;
  final List<TextPrimitive> placed = <TextPrimitive>[];
  final List<(String, String)> hidden = <(String, String)>[];
  for (final (String, String) t in texts) {
    final MarkAnchor? anchor = anchors[t.$1];
    final ChartSize size = measurer.measure(t.$2, theme.dataLabels);
    TextPrimitive? chosen;
    if (anchor != null) {
      final double value = _valueOf(resolved, anchor);
      for (final _Candidate place in _candidates(
        chart.kind,
        anchor,
        size,
        plot,
        stacked: stacked,
        bar: bar,
        negative: value < crossing,
        gap: gap,
        markerGap: gap + theme.markerSize / 2,
        sideGap: gap + theme.markerSize / 2 + apart,
      )) {
        final ChartRect candidate = place.rect;
        final ChartRect bounds = switch (place.where) {
          _Where.outside => area,
          _Where.inside => _visible(anchor.bar!, plot),
          _Where.plot => plot,
        };
        if (!bounds.contains(candidate)) {
          continue;
        }
        final ChartTextStyle style = place.where == _Where.inside
            ? _insideStyle(theme.dataLabels, resolved.colors[anchor.series])
            : theme.dataLabels;
        final TextPrimitive label = TextPrimitive(t.$1, t.$2, candidate, style);
        if (marks.any(
          (LaidMark m) =>
              !isOwnMark(t.$1, m.mark.id) && textOverlapsMark(label, m),
        )) {
          continue;
        }
        final TextPrimitive probe = TextPrimitive(
          t.$1,
          t.$2,
          ChartRect(
            candidate.left - apart,
            candidate.top - apart,
            candidate.width + 2 * apart,
            candidate.height + 2 * apart,
          ),
          theme.dataLabels,
        );
        if (obstacles.any((TextPrimitive o) => textsOverlap(probe, o)) ||
            placed.any((TextPrimitive o) => textsOverlap(probe, o))) {
          continue;
        }
        chosen = label;
        break;
      }
    }
    if (chosen == null) {
      hidden.add((t.$1, textById[t.$1]!));
    } else {
      placed.add(chosen);
    }
  }
  return DataLabelPlacement(placed, hidden);
}

double _valueOf(ResolvedChart resolved, MarkAnchor a) =>
    resolved.values[a.series][a.category] ?? 0;

Iterable<ChartPrimitive> _flat(List<ChartPrimitive> list) sync* {
  for (final ChartPrimitive p in list) {
    yield p;
    if (p is ClipPrimitive) {
      yield* _flat(p.children);
    }
  }
}

/// The colour a label inside a bar of [bar] colour is drawn in: white when
/// the bar's relative luminance is below 0.5, else [style]'s own.
ChartTextStyle _insideStyle(ChartTextStyle style, ChartColor bar) =>
    relativeLuminance(bar.rgb) < 0.5 ? style.copyWith(color: _white) : style;

final ChartColor _white = ChartColor.rgb(0xFFFFFF);

/// The relative luminance of the colour [rgb] (`0xRRGGBB`), from 0 (black)
/// to 1 (white), as WCAG 2 defines it for sRGB.
double relativeLuminance(int rgb) {
  double channel(int shift) {
    final double c = ((rgb >> shift) & 0xFF) / 255;
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0);
}

/// Where a candidate place must lie.
enum _Where {
  /// Inside the chart's area: a column or bar label outside its bar's end.
  outside,

  /// Inside the visible part of its bar.
  inside,

  /// Inside the plot: a line or area label.
  plot,
}

/// A place to try for a label, and where it must lie.
typedef _Candidate = ({ChartRect rect, _Where where});

/// The places to try for a label of [size], in order.
///
/// A line label is [markerGap] from its point above or below it, and
/// [sideGap] (a minimum text gap more) beside it, so that a label beside a
/// point is not a hair's breadth from one above or below it.
List<_Candidate> _candidates(
  ChartKind kind,
  MarkAnchor anchor,
  ChartSize size,
  ChartRect plot, {
  required bool stacked,
  required bool bar,
  required bool negative,
  required double gap,
  required double markerGap,
  required double sideGap,
}) {
  final double w = size.width;
  final double h = size.height;
  ChartRect around(double cx, double cy) =>
      ChartRect(cx - w / 2, cy - h / 2, w, h);
  _Candidate outside(ChartRect rect) => (rect: rect, where: _Where.outside);
  _Candidate inside(ChartRect rect) => (rect: rect, where: _Where.inside);
  _Candidate inPlot(ChartRect rect) => (rect: rect, where: _Where.plot);
  switch (kind) {
    case ChartKind.column:
    case ChartKind.bar:
      final ChartRect r = _visible(anchor.bar!, plot);
      final double cx = r.left + r.width / 2;
      final double cy = r.top + r.height / 2;
      if (stacked) {
        return <_Candidate>[inside(around(cx, cy))];
      }
      if (bar) {
        return negative
            ? <_Candidate>[
                outside(ChartRect(r.left - gap - w, cy - h / 2, w, h)),
                inside(ChartRect(r.left + gap, cy - h / 2, w, h)),
              ]
            : <_Candidate>[
                outside(ChartRect(r.right + gap, cy - h / 2, w, h)),
                inside(ChartRect(r.right - gap - w, cy - h / 2, w, h)),
              ];
      }
      return negative
          ? <_Candidate>[
              outside(ChartRect(cx - w / 2, r.bottom + gap, w, h)),
              inside(ChartRect(cx - w / 2, r.bottom - gap - h, w, h)),
            ]
          : <_Candidate>[
              outside(ChartRect(cx - w / 2, r.top - gap - h, w, h)),
              inside(ChartRect(cx - w / 2, r.top + gap, w, h)),
            ];
    case ChartKind.line:
      final ChartPoint p = anchor.point!;
      return <_Candidate>[
        inPlot(ChartRect(p.x - w / 2, p.y - markerGap - h, w, h)),
        inPlot(ChartRect(p.x - w / 2, p.y + markerGap, w, h)),
        inPlot(ChartRect(p.x + sideGap, p.y - h / 2, w, h)),
        inPlot(ChartRect(p.x - sideGap - w, p.y - h / 2, w, h)),
      ];
    case ChartKind.area:
      final ChartPoint p = anchor.point!;
      final ChartPoint b = anchor.base!;
      return <_Candidate>[inPlot(around((p.x + b.x) / 2, (p.y + b.y) / 2))];
    default:
      return const <_Candidate>[];
  }
}

/// The part of [bar] inside [plot]; where they share nothing, a rectangle
/// with no area on [bar]'s nearest edge (which no label fits in).
ChartRect _visible(ChartRect bar, ChartRect plot) {
  final double left = math.min(math.max(bar.left, plot.left), plot.right);
  final double top = math.min(math.max(bar.top, plot.top), plot.bottom);
  final double right = math.max(math.min(bar.right, plot.right), left);
  final double bottom = math.max(math.min(bar.bottom, plot.bottom), top);
  return ChartRect(left, top, right - left, bottom - top);
}
