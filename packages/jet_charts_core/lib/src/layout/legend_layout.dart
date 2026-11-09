/// The title and the legend, which take their space from the chart before the
/// axes and the plot do.
library;

import 'dart:math' as math;

import '../model/chart_kind.dart';
import '../theme/chart_color.dart';
import '../theme/chart_spacing.dart';
import 'chart_ids.dart' as ids;
import 'geometry.dart';
import 'marks.dart' show markerOutlineWidth;
import 'primitives.dart';
import 'text_measurer.dart';

/// A part of the frame placed in an area, and the area left for the rest.
final class Placed {
  /// Creates a placement of [primitives] that leaves [rest].
  const Placed(this.primitives, this.rest);

  /// What the part draws, in paint order.
  final List<ChartPrimitive> primitives;

  /// The area left once the part, and its gap, are taken out.
  final ChartRect rest;
}

/// Places the title [text] at the top of [area], centred.
///
/// Returns `null` when it does not fit: wider than [area], or taller than it
/// with the `titleGap` under it.
Placed? placeTitle(
  String text,
  ChartRect area,
  ChartTextStyle style,
  TextMeasurer measurer,
  ChartSpacing spacing,
) {
  final ChartSize size = measurer.measure(text, style);
  if (size.width > area.width || size.height + spacing.titleGap > area.height) {
    return null;
  }
  final ChartRect rect = ChartRect(
    area.left + (area.width - size.width) / 2,
    area.top,
    size.width,
    size.height,
  );
  final double taken = size.height + spacing.titleGap;
  return Placed(<ChartPrimitive>[
    TextPrimitive(ids.title, text, rect, style),
  ], ChartRect(area.left, area.top + taken, area.width, area.height - taken));
}

/// How the legend draws the symbol of a line series: a line of
/// `legendLineSymbol` long and `lineWidth` wide, with a marker of
/// `markerSize` in its middle when `markers` is on.
typedef LegendLineLook = ({double lineWidth, double markerSize, bool markers});

/// Places a legend of [names] in [colors] on the [position] side of [area].
///
/// An entry is a symbol, `labelGap`, then the name. The symbol is a
/// `legendSymbol` square, or for an entry [lines] marks (a line series) a
/// horizontal line `legendLineSymbol` long at the entry's vertical middle,
/// drawn as [lineLook] says, with its marker (`legend/<s>/marker`) over it.
/// On the top or bottom, entries run in rows `legendItemGap` apart that wrap
/// at the width of [area], each row centred, rows `minTextGap` apart, at most
/// a third of [limit]'s height in all. On the left or right, entries make one column,
/// at most a third of [limit]'s width wide and no taller than [area], centred
/// on [area]'s height. The legend keeps `legendGap` from what is left.
///
/// Returns `null` when it does not fit. The `legend` rectangle holds the
/// entries exactly and has no fill.
Placed? placeLegend(
  List<String> names,
  List<ChartColor> colors,
  ChartLegendPosition position,
  ChartRect area,
  ChartRect limit,
  ChartTextStyle style,
  TextMeasurer measurer,
  ChartSpacing spacing, {
  List<bool> lines = const <bool>[],
  LegendLineLook lineLook = (lineWidth: 1, markerSize: 0, markers: false),
}) {
  if (names.isEmpty) {
    return Placed(const <ChartPrimitive>[], area);
  }
  bool isLine(int i) => i < lines.length && lines[i];
  double symbolWidth(int i) =>
      isLine(i) ? spacing.legendLineSymbol : spacing.legendSymbol;
  final List<ChartSize> sizes = <ChartSize>[
    for (final String name in names) measurer.measure(name, style),
  ];
  double rowHeight = spacing.legendSymbol;
  if (lineLook.markers && lines.contains(true)) {
    rowHeight = math.max(rowHeight, lineLook.markerSize);
  }
  for (final ChartSize size in sizes) {
    rowHeight = math.max(rowHeight, size.height);
  }
  double entryWidth(int i) =>
      symbolWidth(i) + spacing.labelGap + sizes[i].width;

  // Each row is a list of entry indexes.
  final List<List<int>> rows = <List<int>>[];
  final bool sideways =
      position == ChartLegendPosition.left ||
      position == ChartLegendPosition.right;
  double width = 0;
  if (sideways) {
    for (int i = 0; i < names.length; i++) {
      rows.add(<int>[i]);
      width = math.max(width, entryWidth(i));
    }
    if (width > limit.width / 3 || width > area.width) {
      return null;
    }
  } else {
    List<int> row = <int>[];
    double used = 0;
    for (int i = 0; i < names.length; i++) {
      final double w = entryWidth(i);
      if (w > area.width) {
        return null;
      }
      final double next = row.isEmpty ? w : used + spacing.legendItemGap + w;
      if (next > area.width) {
        rows.add(row);
        row = <int>[i];
        used = w;
      } else {
        row.add(i);
        used = next;
      }
      width = math.max(width, used);
    }
    rows.add(row);
  }
  final double height =
      rows.length * rowHeight + (rows.length - 1) * spacing.minTextGap;
  final bool fits = sideways
      ? height <= area.height && width + spacing.legendGap <= area.width
      : height <= limit.height / 3 && height + spacing.legendGap <= area.height;
  if (!fits) {
    return null;
  }

  final double top = switch (position) {
    ChartLegendPosition.top => area.top,
    ChartLegendPosition.bottom => area.bottom - height,
    _ => area.top + (area.height - height) / 2,
  };
  final double left = switch (position) {
    ChartLegendPosition.left => area.left,
    ChartLegendPosition.right => area.right - width,
    _ => area.left + (area.width - width) / 2,
  };
  final List<ChartPrimitive> entries = <ChartPrimitive>[];
  for (int r = 0; r < rows.length; r++) {
    final List<int> row = rows[r];
    double rowWidth = 0;
    for (final int i in row) {
      rowWidth += entryWidth(i);
    }
    rowWidth += (row.length - 1) * spacing.legendItemGap;
    double x = sideways ? left : left + (width - rowWidth) / 2;
    final double y = top + r * (rowHeight + spacing.minTextGap);
    for (final int i in row) {
      if (isLine(i)) {
        final double middle = y + rowHeight / 2;
        final double length = spacing.legendLineSymbol;
        entries.add(
          PathPrimitive(
            ids.legendSymbolId(i),
            <ChartPoint>[ChartPoint(x, middle), ChartPoint(x + length, middle)],
            stroke: colors[i],
            strokeWidth: lineLook.lineWidth,
          ),
        );
        if (lineLook.markers) {
          entries.add(
            ArcPrimitive(
              ids.legendMarkerId(i),
              ChartPoint(x + length / 2, middle),
              lineLook.markerSize / 2,
              0,
              0,
              360,
              fill: colors[i],
              stroke: colors[i],
              strokeWidth: markerOutlineWidth,
            ),
          );
        }
      } else {
        entries.add(
          RectPrimitive(
            ids.legendSymbolId(i),
            ChartRect(
              x,
              y + (rowHeight - spacing.legendSymbol) / 2,
              spacing.legendSymbol,
              spacing.legendSymbol,
            ),
            fill: colors[i],
          ),
        );
      }
      entries.add(
        TextPrimitive(
          ids.legendTextId(i),
          names[i],
          ChartRect(
            x + symbolWidth(i) + spacing.labelGap,
            y + (rowHeight - sizes[i].height) / 2,
            sizes[i].width,
            sizes[i].height,
          ),
          style,
        ),
      );
      x += entryWidth(i) + spacing.legendItemGap;
    }
  }
  final ChartRect legendRect = ChartRect(left, top, width, height);
  final double gapped = sideways
      ? width + spacing.legendGap
      : height + spacing.legendGap;
  final ChartRect rest = switch (position) {
    ChartLegendPosition.top => ChartRect(
      area.left,
      area.top + gapped,
      area.width,
      area.height - gapped,
    ),
    ChartLegendPosition.bottom => ChartRect(
      area.left,
      area.top,
      area.width,
      area.height - gapped,
    ),
    ChartLegendPosition.left => ChartRect(
      area.left + gapped,
      area.top,
      area.width - gapped,
      area.height,
    ),
    ChartLegendPosition.right => ChartRect(
      area.left,
      area.top,
      area.width - gapped,
      area.height,
    ),
  };
  return Placed(<ChartPrimitive>[
    RectPrimitive(ids.legend, legendRect),
    ...entries,
  ], rest);
}
