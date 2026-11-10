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
import '../scale/value_scale.dart';
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
    required List<ChartKind> seriesKinds,
    required List<bool> secondary,
    required List<ChartGrouping> seriesGroupings,
    required this.secondaryTickFormatCode,
    required this.percent,
    required this.secondaryPercent,
    List<List<ChartColor?>> pointColors = const <List<ChartColor?>>[],
  }) : pointColors = List<List<ChartColor?>>.unmodifiable(<List<ChartColor?>>[
         for (final List<ChartColor?> p in pointColors)
           List<ChartColor?>.unmodifiable(p),
       ]),
       seriesKinds = List<ChartKind>.unmodifiable(seriesKinds),
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

  /// The point colours of each series (`ChartTheme.pointColorOf`: its
  /// `ChartSeries.pointColors`, else its `ChartSeries.pointColorKeys` in the
  /// theme), shorter or longer than the data, with `null` entries; a series
  /// past the list's end has none.
  final List<List<ChartColor?>> pointColors;

  /// The point colour of series [s] at category [c], or `null` when it has
  /// none.
  ChartColor? pointColorAt(int s, int c) {
    if (s >= pointColors.length) {
      return null;
    }
    final List<ChartColor?> points = pointColors[s];
    return c < points.length ? points[c] : null;
  }

  /// The colour series [s] is drawn in at category [c]: its point colour
  /// there, else the series colour.
  ChartColor colorAt(int s, int c) => pointColorAt(s, c) ?? colors[s];

  /// The number format code of the value axis' tick labels.
  final String tickFormatCode;

  /// How the series share a category.
  final ChartGrouping grouping;

  /// The kind each series is drawn as (`drawnKinds`): the chart's kind,
  /// or in a combination chart the series' own column, line or area. One
  /// per series.
  final List<ChartKind> seriesKinds;

  /// Whether each series is measured on the secondary value axis
  /// (`onSecondaryAxis`). One per series.
  final List<bool> secondary;

  /// How each series shares a category with the others of its kind on its
  /// axis: the chart's grouping, except a line series of a combination
  /// chart, which is never stacked.
  final List<ChartGrouping> seriesGroupings;

  /// The number format code of the secondary value axis' tick labels: its
  /// own code, else on a percent axis ([secondaryPercent]) `0%`, else the
  /// first secondary series' code, else `General`.
  final String secondaryTickFormatCode;

  /// Whether the primary value axis is a percent one, from 0 to 100
  /// percent: a percent stacked group is measured on it, or, with no series
  /// on it, the chart is percent stacked. A combination's lines alone are
  /// not.
  final bool percent;

  /// Whether the secondary value axis is a percent one: a percent stacked
  /// group is measured on it.
  final bool secondaryPercent;

  /// Whether some series is measured on the secondary value axis.
  bool get hasSecondary => secondary.contains(true);

  /// Whether series [s] is measured on the secondary value axis.
  bool isSecondary(int s) => secondary[s];

  /// The grouping of series [s] (`seriesGroupings`).
  ChartGrouping groupingOf(int s) => seriesGroupings[s];

  /// The kind series [s] is drawn as (`seriesKinds`).
  ChartKind kindOf(int s) => seriesKinds[s];

  /// The groups of the series, in paint order (`markGroups`), found once.
  late final List<MarkGroup> groups = markGroups(this);

  /// The extent of the values measured on the primary value axis
  /// (`axisExtent`), found once.
  late final ({double min, double max}) primaryExtent = axisExtent(
    this,
    secondary: false,
  );

  /// The extent of the values measured on the secondary value axis
  /// (`axisExtent`), found once.
  late final ({double min, double max}) secondaryExtent = axisExtent(
    this,
    secondary: true,
  );

  /// Whether there is a secondary value axis to draw: some series is
  /// measured on it and has a finite value.
  bool get drawsSecondaryAxis => hasSecondary && !secondaryExtent.min.isNaN;

  /// The values the marks and tooltips use (`shapedValues`), found once.
  late final List<List<double?>> shaped = shapedValues(this);

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
/// axis (`ResolvedChart.percent`), `0%`, else the code of the first series
/// measured on that axis, else `General`. The secondary axis' code is found
/// the same way (`ResolvedChart.secondaryTickFormatCode`).
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
  final List<ChartKind> kinds = drawnKinds(chart);
  final List<bool> secondary = onSecondaryAxis(chart);
  final List<ChartGrouping> groupings = <ChartGrouping>[
    for (final ChartKind kind in kinds)
      chart.kind == ChartKind.combination && kind == ChartKind.line
          ? ChartGrouping.clustered
          : chart.grouping,
  ];
  bool percentOn({required bool onSecondary}) {
    for (int s = 0; s < groupings.length; s++) {
      if (secondary[s] == onSecondary &&
          groupings[s] == ChartGrouping.percentStacked) {
        return true;
      }
    }
    return false;
  }

  final bool percent =
      percentOn(onSecondary: false) ||
      (!secondary.contains(false) &&
          chart.grouping == ChartGrouping.percentStacked);
  final bool secondaryPercent = percentOn(onSecondary: true);
  String? secondaryCode;
  String? primaryCode;
  for (int s = series.length - 1; s >= 0; s--) {
    if (secondary[s]) {
      secondaryCode = series[s].formatCode;
    } else {
      primaryCode = series[s].formatCode;
    }
  }
  final String tickCode =
      chart.valueAxis.formatCode ??
      (percent ? '0%' : null) ??
      primaryCode ??
      'General';
  return ResolvedChart(
    values: values,
    categoryLabels: labels,
    seriesNames: names,
    colors: <ChartColor>[
      for (int s = 0; s < series.length; s++) theme.colorOf(series[s], s),
    ],
    pointColors: <List<ChartColor?>>[
      for (final ChartSeries one in series)
        <ChartColor?>[
          for (int i = 0; i < theme.pointColorCount(one); i++)
            theme.pointColorOf(one, i),
        ],
    ],
    tickFormatCode: tickCode,
    grouping: chart.grouping,
    seriesKinds: kinds,
    secondary: secondary,
    seriesGroupings: groupings,
    percent: percent,
    secondaryPercent: secondaryPercent,
    secondaryTickFormatCode:
        chart.secondaryValueAxis?.formatCode ??
        (secondaryPercent ? '0%' : null) ??
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

/// The series of one drawn kind on one value axis, drawn together: columns
/// of a group share the category's slot, and a stacked group's values add
/// up.
final class MarkGroup {
  /// Creates the group of the series [members] (indexes, in series order)
  /// drawn as [kind].
  const MarkGroup(
    this.kind,
    this.members, {
    required this.secondary,
    required this.grouping,
  });

  /// The kind the group is drawn as.
  final ChartKind kind;

  /// The indexes of the group's series, in series order.
  final List<int> members;

  /// Whether the group is measured on the secondary value axis.
  final bool secondary;

  /// How the group's series share a category.
  final ChartGrouping grouping;

  /// Whether the group's values add up.
  bool get stacked => grouping != ChartGrouping.clustered;
}

/// The order kinds are drawn in: areas under columns and bars, lines on
/// top. A kind not listed (a later one) is drawn after these, in the order
/// its series first appear.
const List<ChartKind> _drawOrder = <ChartKind>[
  ChartKind.area,
  ChartKind.column,
  ChartKind.bar,
  ChartKind.line,
];

/// The groups of [resolved]'s series, in paint order: per kind (areas,
/// columns, bars, lines, then any other), the primary axis' group, then the
/// secondary axis' one; each group's series in series order. A group's
/// grouping is its series' (`ResolvedChart.seriesGroupings`). An empty
/// group is left out.
List<MarkGroup> markGroups(ResolvedChart resolved) {
  final int n = resolved.values.length;
  final List<ChartKind> kinds = <ChartKind>[..._drawOrder];
  for (int s = 0; s < n; s++) {
    if (!kinds.contains(resolved.kindOf(s))) {
      kinds.add(resolved.kindOf(s));
    }
  }
  return <MarkGroup>[
    for (final ChartKind kind in kinds)
      for (final bool secondary in <bool>[false, true])
        if (<int>[
              for (int s = 0; s < n; s++)
                if (resolved.kindOf(s) == kind &&
                    resolved.isSecondary(s) == secondary)
                  s,
            ]
            case final List<int> members when members.isNotEmpty)
          MarkGroup(
            kind,
            members,
            secondary: secondary,
            grouping: resolved.groupingOf(members.first),
          ),
  ];
}

/// The extent of the values measured on the primary value axis, or on the
/// [secondary] one: of each group on it (`dataExtent` of the group's values
/// under its grouping), joined. With no finite value both ends are `NaN`.
({double min, double max}) axisExtent(
  ResolvedChart resolved, {
  required bool secondary,
}) {
  double min = double.nan;
  double max = double.nan;
  for (final MarkGroup group in resolved.groups) {
    if (group.secondary != secondary) {
      continue;
    }
    final ({double min, double max}) e = dataExtent(<List<double?>>[
      for (final int s in group.members) resolved.values[s],
    ], group.grouping);
    if (e.min.isNaN) {
      continue;
    }
    min = min.isNaN ? e.min : math.min(min, e.min);
    max = max.isNaN ? e.max : math.max(max, e.max);
  }
  return (min: min, max: max);
}

/// The values the marks use: the resolved ones, or in a percent stacked
/// group (`markGroups`) each as its share of the category's absolute sum
/// over the group's series (a category of sum 0 has no value). Tooltips read
/// the share from here too.
List<List<double?>> shapedValues(ResolvedChart resolved) {
  if (!resolved.seriesGroupings.contains(ChartGrouping.percentStacked)) {
    return resolved.values;
  }
  final List<List<double?>> out = <List<double?>>[...resolved.values];
  for (final MarkGroup group in resolved.groups) {
    if (group.grouping != ChartGrouping.percentStacked) {
      continue;
    }
    final List<double> sums = <double>[
      for (int c = 0; c < resolved.categoryCount; c++)
        group.members.fold<double>(
          0,
          (double sum, int s) => sum + (resolved.values[s][c] ?? 0).abs(),
        ),
    ];
    for (final int s in group.members) {
      final List<double?> series = resolved.values[s];
      out[s] = <double?>[
        for (int c = 0; c < series.length; c++)
          series[c] == null || !(sums[c] > 0) ? null : series[c]! / sums[c],
      ];
    }
  }
  return out;
}
