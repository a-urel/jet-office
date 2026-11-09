/// The first step of layout: a chart's data made ready to place.
///
/// Values are checked (a non-finite value is `null`), the series are padded to
/// one category count, and every text the frame shows is formatted once:
/// category labels, series names and the value axis' format code.
library;

import 'dart:math' as math;

import 'package:jet_core/jet_core.dart';

import '../model/chart.dart';
import '../model/chart_kind.dart';
import '../model/chart_series.dart';
import '../theme/chart_color.dart';
import '../theme/chart_theme.dart';

/// A chart's data, checked and formatted for layout.
final class ResolvedChart {
  /// Creates resolved data; the lists are copied into unmodifiable ones.
  ResolvedChart({
    required List<List<double?>> values,
    required List<String> categoryLabels,
    required List<String> seriesNames,
    required List<ChartColor> colors,
    required this.tickFormatCode,
    required this.grouping,
    List<ChartKind> seriesKinds = const <ChartKind>[],
    List<bool> secondary = const <bool>[],
    List<ChartGrouping> seriesGroupings = const <ChartGrouping>[],
    this.secondaryTickFormatCode = 'General',
  }) : seriesKinds = List<ChartKind>.unmodifiable(seriesKinds),
       secondary = List<bool>.unmodifiable(secondary),
       seriesGroupings = List<ChartGrouping>.unmodifiable(seriesGroupings),
       values = List<List<double?>>.unmodifiable(<List<double?>>[
         for (final List<double?> v in values) List<double?>.unmodifiable(v),
       ]),
       categoryLabels = List<String>.unmodifiable(categoryLabels),
       seriesNames = List<String>.unmodifiable(seriesNames),
       colors = List<ChartColor>.unmodifiable(colors);

  /// The values of each series, one per category; a missing or non-finite
  /// value is `null`.
  final List<List<double?>> values;

  /// The text of each category's label.
  final List<String> categoryLabels;

  /// The legend text of each series.
  final List<String> seriesNames;

  /// The colour of each series (`ChartTheme.colorOf`).
  final List<ChartColor> colors;

  /// The number format code of the value axis' tick labels.
  final String tickFormatCode;

  /// How the series share a category.
  final ChartGrouping grouping;

  /// The kind each series is drawn as (`drawnKinds`): the chart's kind,
  /// or in a combination chart the series' own column, line or area.
  final List<ChartKind> seriesKinds;

  /// Whether each series is measured on the secondary value axis
  /// (`onSecondaryAxis`).
  final List<bool> secondary;

  /// How each series shares a category with the others of its kind on its
  /// axis: the chart's grouping, except a line series of a combination
  /// chart, which is never stacked.
  final List<ChartGrouping> seriesGroupings;

  /// The number format code of the secondary value axis' tick labels: its
  /// own code, else on a percent stacked axis `0%`, else the first
  /// secondary series' code, else `General`.
  final String secondaryTickFormatCode;

  /// Whether some series is measured on the secondary value axis.
  bool get hasSecondary => secondary.contains(true);

  /// Whether series [s] is measured on the secondary value axis.
  bool isSecondary(int s) => s < secondary.length && secondary[s];

  /// The grouping of series [s] (`seriesGroupings`), or the chart's.
  ChartGrouping groupingOf(int s) =>
      s < seriesGroupings.length ? seriesGroupings[s] : grouping;

  /// The kind series [s] is drawn as (`seriesKinds`).
  /// A series beyond the list (none) counts as a column.
  ChartKind kindOf(int s) =>
      s < seriesKinds.length ? seriesKinds[s] : ChartKind.column;

  /// Whether the value axis is a percent stacked one, from 0 to 100 percent.
  bool get percent => grouping == ChartGrouping.percentStacked;

  /// The number of categories.
  int get categoryCount => categoryLabels.length;
}

/// Resolves [chart] with [theme]'s colours, formatting with [formatter].
///
/// The category count is the longest of the series' values and the first
/// series' categories. Category labels come from the first series, as Excel
/// takes them: a `String` as it is, a `num` in `General`, a `DateTime` in the
/// category axis' format code, else the first series' when it shows a date or
/// a time (`classifyFormatCode`), else the locale's short date (built-in
/// format 14), a `null` as an empty text, anything else by its
/// `toString`. A chart whose first series has no category value at all numbers
/// its categories from 1, as Excel does.
///
/// A series name is its name's texts joined by a space, or `Series <n>` when it
/// has none. The tick format code is the value axis' code, else, on a percent
/// stacked axis, `0%`, else the first series' code, else `General`.
ResolvedChart resolveChart(
  Chart chart,
  ChartTheme theme,
  NumberFormatter formatter,
) {
  final List<ChartSeries> series = chart.series;
  final List<Object?> categories = series.isEmpty
      ? const <Object?>[]
      : series.first.categories.values;
  int count = categories.length;
  for (final ChartSeries s in series) {
    count = math.max(count, s.values.values.length);
  }
  final String? seriesCode = series.isEmpty ? null : series.first.formatCode;
  final bool numbered = categories.every((Object? c) => c == null);
  final List<String> labels = <String>[
    for (int i = 0; i < count; i++)
      numbered
          ? '${i + 1}'
          : categoryLabelText(
              i < categories.length ? categories[i] : null,
              axisCode: chart.categoryAxis.formatCode,
              seriesCode: seriesCode,
              formatter: formatter,
            ),
  ];
  final List<List<double?>> values = <List<double?>>[
    for (final ChartSeries s in series)
      <double?>[for (int i = 0; i < count; i++) _finite(s.values.values, i)],
  ];
  final List<String> names = <String>[
    for (int s = 0; s < series.length; s++) _name(series[s], s),
  ];
  final bool percent = chart.grouping == ChartGrouping.percentStacked;
  final List<ChartKind> kinds = drawnKinds(chart);
  final List<bool> secondary = onSecondaryAxis(chart);
  String? secondaryCode;
  for (int s = 0; s < series.length; s++) {
    if (secondary[s]) {
      secondaryCode = series[s].formatCode;
      break;
    }
  }
  final String tickCode =
      chart.valueAxis.formatCode ??
      (percent ? '0%' : null) ??
      seriesCode ??
      'General';
  return ResolvedChart(
    values: values,
    categoryLabels: labels,
    seriesNames: names,
    colors: <ChartColor>[
      for (int s = 0; s < series.length; s++) theme.colorOf(series[s], s),
    ],
    tickFormatCode: tickCode,
    grouping: chart.grouping,
    seriesKinds: kinds,
    secondary: secondary,
    seriesGroupings: <ChartGrouping>[
      for (final ChartKind kind in kinds)
        chart.kind == ChartKind.combination && kind == ChartKind.line
            ? ChartGrouping.clustered
            : chart.grouping,
    ],
    secondaryTickFormatCode:
        chart.secondaryValueAxis?.formatCode ??
        (percent ? '0%' : null) ??
        secondaryCode ??
        'General',
  );
}

/// The kind each series of [chart] is drawn as.
///
/// In a combination chart each series is drawn as its own `kind` when that
/// is [ChartKind.column], [ChartKind.line] or [ChartKind.area]; a `null`
/// kind, or any other, draws as [ChartKind.column]. In any other chart each
/// series is drawn as the chart's kind.
List<ChartKind> drawnKinds(Chart chart) => <ChartKind>[
  for (final ChartSeries s in chart.series)
    chart.kind != ChartKind.combination
        ? chart.kind
        : switch (s.kind) {
            ChartKind.line => ChartKind.line,
            ChartKind.area => ChartKind.area,
            _ => ChartKind.column,
          },
];

/// Whether each series of [chart] is measured on the secondary value axis.
///
/// Only column, line, area and combination charts have one; a bar chart, as
/// any other kind, measures every series on the primary axis. A series bound
/// to the secondary axis is measured on it only when some series is bound to
/// the primary axis: with none, every series is measured on the primary
/// axis and no secondary axis shows.
List<bool> onSecondaryAxis(Chart chart) {
  final bool axes = switch (chart.kind) {
    ChartKind.column ||
    ChartKind.line ||
    ChartKind.area ||
    ChartKind.combination => true,
    _ => false,
  };
  final bool anyPrimary = chart.series.any(
    (ChartSeries s) => s.axis == ChartAxisBinding.primary,
  );
  return <bool>[
    for (final ChartSeries s in chart.series)
      axes && anyPrimary && s.axis == ChartAxisBinding.secondary,
  ];
}

/// The label text of the category [value] (see [resolveChart]).
String categoryLabelText(
  Object? value, {
  required String? axisCode,
  required String? seriesCode,
  required NumberFormatter formatter,
}) {
  return switch (value) {
    null => '',
    final String text => text,
    final num number => formatter.format(number).text,
    final DateTime date => _dateText(date, axisCode, seriesCode, formatter),
    _ => value.toString(),
  };
}

/// The label of the category [date]: the category axis' code, else the
/// series' code when it shows a date or a time, else the locale's short date
/// (built-in format 14). A series code for its values, such as a currency,
/// would show the date's serial number.
String _dateText(
  DateTime date,
  String? axisCode,
  String? seriesCode,
  NumberFormatter formatter,
) {
  final String? code =
      axisCode ??
      (seriesCode != null && classifyFormatCode(seriesCode) != FormatKind.number
          ? seriesCode
          : null);
  return code != null
      ? formatter.format(date, numberFormat: code).text
      : formatter.format(date, numberFormatId: 14).text;
}

/// [value] formatted with the number format [code].
String formatTick(double value, String code, NumberFormatter formatter) =>
    formatter.format(value, numberFormat: code).text;

double? _finite(List<double?> values, int index) {
  if (index >= values.length) {
    return null;
  }
  final double? value = values[index];
  return value != null && value.isFinite ? value : null;
}

String _name(ChartSeries series, int index) {
  final String text = series.name.values.whereType<String>().join(' ');
  return text.isEmpty ? 'Series ${index + 1}' : text;
}
