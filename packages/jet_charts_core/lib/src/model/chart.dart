/// The chart: [Chart].
library;

import 'chart_axis.dart';
import 'chart_kind.dart';
import 'chart_parts.dart';
import 'chart_series.dart';
import 'equality.dart';

/// An immutable description of one chart.
final class Chart {
  /// Creates a chart from a copy of [series].
  ///
  /// [unsupportedName] is the name of a kind read from a file that the model
  /// does not draw; it goes with [ChartKind.unsupported].
  Chart({
    required this.kind,
    required List<ChartSeries> series,
    this.grouping = ChartGrouping.clustered,
    this.categoryAxis = const ChartAxis(),
    this.valueAxis = const ChartAxis(gridLines: true),
    this.secondaryValueAxis,
    this.title,
    this.legend = const ChartLegend(),
    this.dataLabels = const ChartDataLabels(),
    this.unsupportedName,
  }) : series = List<ChartSeries>.unmodifiable(series);

  /// What the chart draws.
  final ChartKind kind;

  /// The series, in drawing order. The list cannot be modified.
  final List<ChartSeries> series;

  /// How the series share a category's space.
  final ChartGrouping grouping;

  /// The category axis (the horizontal one, except in a bar chart).
  final ChartAxis categoryAxis;

  /// The value axis.
  final ChartAxis valueAxis;

  /// The second value axis, or `null` when no series is bound to it.
  final ChartAxis? secondaryValueAxis;

  /// The title, or `null` for none.
  final ChartTitle? title;

  /// The legend.
  final ChartLegend legend;

  /// The data labels.
  final ChartDataLabels dataLabels;

  /// The name of the kind in the file when [kind] is
  /// [ChartKind.unsupported], else `null`.
  final String? unsupportedName;

  /// A copy with the given fields replaced.
  ///
  /// A field cannot be set to `null` this way: passing `null` keeps the
  /// current value.
  Chart copyWith({
    ChartKind? kind,
    List<ChartSeries>? series,
    ChartGrouping? grouping,
    ChartAxis? categoryAxis,
    ChartAxis? valueAxis,
    ChartAxis? secondaryValueAxis,
    ChartTitle? title,
    ChartLegend? legend,
    ChartDataLabels? dataLabels,
    String? unsupportedName,
  }) {
    return Chart(
      kind: kind ?? this.kind,
      series: series ?? this.series,
      grouping: grouping ?? this.grouping,
      categoryAxis: categoryAxis ?? this.categoryAxis,
      valueAxis: valueAxis ?? this.valueAxis,
      secondaryValueAxis: secondaryValueAxis ?? this.secondaryValueAxis,
      title: title ?? this.title,
      legend: legend ?? this.legend,
      dataLabels: dataLabels ?? this.dataLabels,
      unsupportedName: unsupportedName ?? this.unsupportedName,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is Chart &&
        kind == other.kind &&
        listValueEquals(series, other.series) &&
        grouping == other.grouping &&
        categoryAxis == other.categoryAxis &&
        valueAxis == other.valueAxis &&
        secondaryValueAxis == other.secondaryValueAxis &&
        title == other.title &&
        legend == other.legend &&
        dataLabels == other.dataLabels &&
        unsupportedName == other.unsupportedName;
  }

  @override
  int get hashCode => Object.hash(
    kind,
    listValueHash(series),
    grouping,
    categoryAxis,
    valueAxis,
    secondaryValueAxis,
    title,
    legend,
    dataLabels,
    unsupportedName,
  );

  @override
  String toString() => 'Chart($kind, ${series.length} series)';
}
