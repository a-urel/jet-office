/// Tooltip content: what a backend shows for a point or a primitive of a
/// layout.
library;

import 'package:jet_core/jet_core.dart';

import '../layout/chart_ids.dart' as ids;
import '../layout/chart_layout.dart';
import '../layout/geometry.dart';
import '../layout/marks.dart' show shapedValues;
import '../layout/primitives.dart';
import '../layout/resolve.dart';
import '../model/chart.dart';
import '../model/equality.dart';
import '../theme/chart_color.dart';
import '../theme/chart_theme.dart';
import 'element_id.dart';
import 'hit_test.dart';

/// One line of a tooltip: a series' colour, a label and a value.
final class ChartTooltipRow {
  /// Creates a row of [label] and [value], with the swatch [color] if any.
  const ChartTooltipRow({this.color, required this.label, required this.value});

  /// The colour of the row's swatch: the series' colour, or `null` for a row
  /// that names no series (a hidden axis title).
  final ChartColor? color;

  /// The row's label: a series name, or a hidden text.
  final String label;

  /// The row's value, formatted; empty when the row has none.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is ChartTooltipRow &&
      color == other.color &&
      label == other.label &&
      value == other.value;

  @override
  int get hashCode => Object.hash(color, label, value);

  @override
  String toString() => 'ChartTooltipRow($label, $value, $color)';
}

/// What a tooltip shows: a title, rows, and the primitive it was found from.
final class ChartTooltip {
  /// Creates a tooltip; [rows] is copied into an unmodifiable list.
  ChartTooltip({
    this.title,
    required List<ChartTooltipRow> rows,
    required this.sourceId,
  }) : rows = List<ChartTooltipRow>.unmodifiable(rows);

  /// The title: a category's full text, a series name or a hidden title; or
  /// `null` for none.
  final String? title;

  /// The rows, in series order. Empty for a legend entry's tooltip.
  final List<ChartTooltipRow> rows;

  /// The id of the primitive the tooltip was found from, in the scheme that
  /// `ChartLayout.primitives` describes.
  final String sourceId;

  @override
  bool operator ==(Object other) =>
      other is ChartTooltip &&
      title == other.title &&
      sourceId == other.sourceId &&
      listValueEquals(rows, other.rows);

  @override
  int get hashCode => Object.hash(title, sourceId, listValueHash(rows));

  @override
  String toString() => 'ChartTooltip($title, $rows, from $sourceId)';
}

/// The tooltip at [point] of [layout], the layout of [chart] with [theme] in
/// [locale], or `null` when nothing there has one.
///
/// The primitives under [point] are taken topmost first (`hitTestLayout`,
/// with [tolerance]) and the first that has a tooltip wins:
///
/// * a bar, a marker or a data label: that point, its category's full text
///   as the title and one row of the series' colour, name and value;
/// * a line, an area, a grid line or the plot (`plot/clip`, `plot/markers`,
///   `plot`): the
///   category whose `ChartLayout.categoryBands` band holds [point], every
///   series at it as a row;
/// * a category label: that category, as above;
/// * a legend entry: the series name as the title, and no row;
/// * the background: the texts the layout hid of the title (as the title),
///   the axis titles and a placeholder (as rows without a value), or nothing
///   when none was hidden.
///
/// A value is formatted with `NumberFormatter` of [locale] in the series'
/// format code, else the value axis' code, else `General`; in a percent
/// stacked chart it is followed by its share of the category, in `0%`, in
/// brackets. A `null` or non-finite value makes no row, and a category with no
/// row left has no tooltip.
///
/// Every kind of `ChartLayout.hidden` stays within reach:
///
/// * data labels: their point's value is in the point and category tooltips;
/// * legend entries: the series names are the labels of the rows;
/// * category labels: the category tooltip's title is the full text, never
///   cut, even when the label was cut or skipped;
/// * the title and the axis titles: in the background tooltip;
/// * a placeholder: in the background tooltip;
/// * value tick labels: they are axis ticks, not data, and have no tooltip;
///   the exact values they would mark are in the data tooltips.
///
/// A [point] with a coordinate that is not finite has no tooltip. Throws an
/// [ArgumentError] when [hits] is `null` and [tolerance] is negative or not
/// finite.
///
/// A caller that has already hit tested [point] (to report the topmost
/// primitive, say) passes that list as [hits], topmost first, so the layout is
/// not hit tested twice; it is then used as given, and [tolerance] is not
/// read. When [hits] is `null`, `hitTestLayout(layout, point, tolerance:
/// tolerance)` gives them.
ChartTooltip? chartTooltipAt(
  Chart chart,
  ChartLayout layout,
  ChartPoint point, {
  required ChartTheme theme,
  FormatLocale locale = FormatLocale.enUS,
  double tolerance = 0,
  List<ChartPrimitive>? hits,
}) {
  hits ??= hitTestLayout(layout, point, tolerance: tolerance);
  if (hits.isEmpty) {
    return null;
  }
  final _Source source = _Source(chart, layout, theme, locale);
  for (final ChartPrimitive hit in hits) {
    final ChartTooltip? tooltip = source.tooltip(hit.id, point);
    if (tooltip != null) {
      return tooltip;
    }
  }
  return null;
}

/// The tooltip of the primitive [id] of [layout], the layout of [chart] with
/// [theme] in [locale], or `null` when it has none.
///
/// It is what [chartTooltipAt] gives over that primitive, for the kinds whose
/// tooltip does not depend on the point: a bar, a marker, a data label, a
/// category label, a legend entry and the background. A line, an area, a grid
/// line and the plot have a tooltip only at a point, and give `null` here; so
/// does an id the layout's chart does not have (a series or category out of
/// range) or one that is not of the scheme.
ChartTooltip? chartTooltipFor(
  Chart chart,
  ChartLayout layout,
  String id, {
  required ChartTheme theme,
  FormatLocale locale = FormatLocale.enUS,
}) => _Source(chart, layout, theme, locale).tooltip(id, null);

/// [value] of [chart]'s series [series] formatted as a tooltip shows it: in
/// the series' format code, else the value axis' code, else `General`.
String formatSeriesValue(
  Chart chart,
  int series,
  double value,
  NumberFormatter formatter,
) => formatter
    .format(
      value,
      numberFormat:
          chart.series[series].formatCode ??
          chart.valueAxis.formatCode ??
          'General',
    )
    .text;

/// A chart resolved once for the tooltips of one call.
final class _Source {
  _Source(this.chart, this.layout, ChartTheme theme, FormatLocale locale)
    : formatter = NumberFormatter(locale: locale),
      _theme = theme;

  final Chart chart;
  final ChartLayout layout;
  final NumberFormatter formatter;
  final ChartTheme _theme;

  late final ResolvedChart resolved = resolveChart(chart, _theme, formatter);
  late final List<List<double?>> shares = shapedValues(resolved);

  /// The tooltip of the primitive [id], found at [point] when one is given.
  ChartTooltip? tooltip(String id, ChartPoint? point) {
    final ChartElementId? element = ChartElementId.parse(id);
    if (element == null) {
      return null;
    }
    switch (element.kind) {
      case ChartElementKind.bar:
      case ChartElementKind.marker:
      case ChartElementKind.dataLabel:
        return _point(id, element.series!, element.category!);
      case ChartElementKind.axisLabel:
        return element.axis == ChartAxisRole.category
            ? _category(id, element.category!)
            : null;
      case ChartElementKind.line:
      case ChartElementKind.area:
      case ChartElementKind.gridLine:
      case ChartElementKind.plot:
      case ChartElementKind.plotClip:
      case ChartElementKind.markerClip:
        final int? category = point == null ? null : _band(point);
        return category == null ? null : _category(id, category);
      case ChartElementKind.legendSymbol:
      case ChartElementKind.legendText:
        final int s = element.series!;
        return s < resolved.seriesNames.length
            ? ChartTooltip(
                title: resolved.seriesNames[s],
                rows: const <ChartTooltipRow>[],
                sourceId: id,
              )
            : null;
      case ChartElementKind.background:
        return _background(id);
      case ChartElementKind.title:
      case ChartElementKind.legend:
      case ChartElementKind.placeholder:
      case ChartElementKind.axisLine:
      case ChartElementKind.axisTitle:
        return null;
    }
  }

  ChartTooltip? _point(String id, int series, int category) {
    if (series >= resolved.values.length ||
        category >= resolved.categoryCount) {
      return null;
    }
    final ChartTooltipRow? row = _row(series, category);
    return row == null
        ? null
        : ChartTooltip(
            title: _title(category),
            rows: <ChartTooltipRow>[row],
            sourceId: id,
          );
  }

  ChartTooltip? _category(String id, int category) {
    if (category >= resolved.categoryCount) {
      return null;
    }
    final List<ChartTooltipRow> rows = <ChartTooltipRow>[
      for (int s = 0; s < resolved.values.length; s++) ?_row(s, category),
    ];
    return rows.isEmpty
        ? null
        : ChartTooltip(title: _title(category), rows: rows, sourceId: id);
  }

  ChartTooltipRow? _row(int series, int category) {
    final double? value = resolved.values[series][category];
    if (value == null) {
      return null;
    }
    String text = formatSeriesValue(chart, series, value, formatter);
    if (resolved.percent) {
      final double? share = shares[series][category];
      if (share != null) {
        text += ' (${formatter.format(share, numberFormat: '0%').text})';
      }
    }
    return ChartTooltipRow(
      color: resolved.colors[series],
      label: resolved.seriesNames[series],
      value: text,
    );
  }

  /// The full text of [category], or `null` when it is empty.
  String? _title(int category) {
    final String text = resolved.categoryLabels[category];
    return text.isEmpty ? null : text;
  }

  /// The category whose band holds [point], or `null`.
  int? _band(ChartPoint point) {
    final List<ChartRect> bands = layout.categoryBands;
    for (int i = 0; i < bands.length; i++) {
      final ChartRect b = bands[i];
      if (point.x >= b.left &&
          point.x <= b.right &&
          point.y >= b.top &&
          point.y <= b.bottom) {
        return i;
      }
    }
    return null;
  }

  ChartTooltip? _background(String id) {
    String? title;
    final List<ChartTooltipRow> rows = <ChartTooltipRow>[];
    for (final String part in <String>[
      ids.title,
      ids.axisTitleId(ids.valueAxis),
      ids.axisTitleId(ids.categoryAxis),
      ids.placeholder,
    ]) {
      for (final ChartHiddenLabel hidden in layout.hidden) {
        if (hidden.id != part || hidden.text.isEmpty) {
          continue;
        }
        if (part == ids.title) {
          title = hidden.text;
        } else {
          rows.add(ChartTooltipRow(label: hidden.text, value: ''));
        }
      }
    }
    return title == null && rows.isEmpty
        ? null
        : ChartTooltip(title: title, rows: rows, sourceId: id);
  }
}
