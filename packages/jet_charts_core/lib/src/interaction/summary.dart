/// A chart's data as text, for a screen reader or a data table.
library;

import 'package:jet_core/jet_core.dart';

import '../layout/resolve.dart';
import '../model/chart.dart';
import '../model/chart_kind.dart';
import '../model/equality.dart';
import '../theme/chart_theme.dart';
import 'tooltip.dart' show formatSeriesValue;

/// A chart's data as the texts a layout and its tooltips show, for a screen
/// reader's description or a data table beside the chart.
final class ChartSummary {
  /// Creates a summary; the lists are copied into unmodifiable ones.
  ChartSummary({
    required this.kind,
    this.title,
    required List<String> seriesNames,
    required List<String> categories,
    required List<List<String>> values,
    this.minimum,
    this.maximum,
    required this.isEmpty,
  }) : seriesNames = List<String>.unmodifiable(seriesNames),
       categories = List<String>.unmodifiable(categories),
       values = List<List<String>>.unmodifiable(<List<String>>[
         for (final List<String> v in values) List<String>.unmodifiable(v),
       ]);

  /// The chart's kind.
  final ChartKind kind;

  /// The chart's title, or `null` when it has none.
  final String? title;

  /// The name of each series, as the legend shows it in full.
  final List<String> seriesNames;

  /// The text of each category, as the category axis shows it in full.
  final List<String> categories;

  /// The values of each series, one text per category, formatted as tooltips
  /// format them; an empty text where there is no value.
  final List<List<String>> values;

  /// The least finite value, formatted in its series' code; `null` when there
  /// is none.
  final String? minimum;

  /// The greatest finite value, formatted in its series' code; `null` when
  /// there is none.
  final String? maximum;

  /// Whether no series has a finite value.
  final bool isEmpty;

  @override
  bool operator ==(Object other) {
    if (other is! ChartSummary ||
        kind != other.kind ||
        title != other.title ||
        minimum != other.minimum ||
        maximum != other.maximum ||
        isEmpty != other.isEmpty ||
        !listValueEquals(seriesNames, other.seriesNames) ||
        !listValueEquals(categories, other.categories) ||
        values.length != other.values.length) {
      return false;
    }
    for (int i = 0; i < values.length; i++) {
      if (!listValueEquals(values[i], other.values[i])) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    kind,
    title,
    listValueHash(seriesNames),
    listValueHash(categories),
    Object.hashAll(values.map(listValueHash)),
    minimum,
    maximum,
    isEmpty,
  );

  @override
  String toString() =>
      'ChartSummary($kind, ${seriesNames.length} series, '
      '${categories.length} categories)';
}

/// The summary of [chart], its texts formatted for [locale].
///
/// Series names and categories are the texts the layout shows, in full, never
/// cut. Each value is formatted as `chartTooltipAt` formats it (the series'
/// format code, else the value axis' code, else `General`; no share), and a
/// missing or non-finite value is an empty text. The minimum and maximum are
/// those of the finite values, each formatted in the code of the first series
/// that holds it.
ChartSummary summarizeChart(
  Chart chart, {
  FormatLocale locale = FormatLocale.enUS,
}) {
  final NumberFormatter formatter = NumberFormatter(locale: locale);
  // Colours do not matter here; any theme resolves the same texts.
  final ResolvedChart resolved = resolveChart(
    chart,
    ChartTheme.office,
    formatter,
  );
  (int, double)? low;
  (int, double)? high;
  final List<List<String>> values = <List<String>>[];
  for (int s = 0; s < resolved.values.length; s++) {
    final List<String> texts = <String>[];
    for (final double? value in resolved.values[s]) {
      if (value == null) {
        texts.add('');
        continue;
      }
      texts.add(formatSeriesValue(chart, s, value, formatter));
      if (low == null || value < low.$2) {
        low = (s, value);
      }
      if (high == null || value > high.$2) {
        high = (s, value);
      }
    }
    values.add(texts);
  }
  final String? title = chart.title?.text;
  return ChartSummary(
    kind: chart.kind,
    title: title == null || title.isEmpty ? null : title,
    seriesNames: resolved.seriesNames,
    categories: resolved.categoryLabels,
    values: values,
    minimum: low == null
        ? null
        : formatSeriesValue(chart, low.$1, low.$2, formatter),
    maximum: high == null
        ? null
        : formatSeriesValue(chart, high.$1, high.$2, formatter),
    isEmpty: low == null,
  );
}
