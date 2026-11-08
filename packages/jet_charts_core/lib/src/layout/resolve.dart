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
  }) : values = List<List<double?>>.unmodifiable(<List<double?>>[
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
  );
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
