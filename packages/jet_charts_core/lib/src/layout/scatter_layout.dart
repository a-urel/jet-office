/// A scatter chart's data on two value axes: each point's x, the horizontal
/// axis' extent and text, and the markers.
///
/// The frame (`frame.dart`) lays a scatter chart out as a column chart whose
/// category axis is a second value axis: its scale comes from
/// `autoValueScale` on the extent of the x values and the plot's width, and
/// its tick labels are the value axis' labels laid horizontally
/// (`valueLabelPrimitives`), with the category axis' ids. Both axes being
/// automatic, and only horizontal grid lines by default, is an estimate of
/// Excel's scatter chart, not checked in Excel.
///
/// The x values are each series' categories; nothing else of the model
/// carries a meaning here, so a later kind (a bubble chart's sizes) adds its
/// own field and reuses the horizontal value axis as it is.
library;

import 'package:jet_core/jet_core.dart';

import '../model/chart.dart';
import '../model/chart_kind.dart';
import '../model/chart_series.dart';
import '../scale/value_scale.dart';
import '../theme/chart_color.dart';
import '../theme/chart_theme.dart';
import 'chart_ids.dart' as ids;
import 'geometry.dart';
import 'marks.dart';
import 'primitives.dart';
import 'resolve.dart';

/// A scatter chart's horizontal axis as its marks need it: the axis'
/// [ValueScale] and each point's x ([scatterXValues]), found once per
/// layout.
typedef ScatterAxis = ({ValueScale scale, List<List<double>> values});

/// The x value of each point of each of [chart]'s series, [count] per
/// series (the resolved category count).
///
/// The categories at the indexes of the series' values decide: when each of
/// them is a finite number or a `DateTime`, the series takes them as they
/// are, a `DateTime` as its serial in Excel's 1900 date system
/// ([excelSerialOf]). When any of them is something else (a `String`, a
/// `null`, a non-finite number, or missing because the categories are
/// fewer than the values), the series numbers its points `1, 2, 3, …` by
/// index, whether or not that index has a value (Excel's handling of text x
/// values: an estimate, not checked in Excel, pending E1). A
/// series with no values takes index numbers. An index past the series'
/// values gets its index number too; it has no value, so it draws nothing.
List<List<double>> scatterXValues(Chart chart, int count) {
  final List<List<double>> out = <List<double>>[];
  for (final ChartSeries s in chart.series) {
    final List<Object?> categories = s.categories.values;
    final List<double?> numbers = <double?>[
      for (int i = 0; i < s.values.values.length; i++)
        _number(i < categories.length ? categories[i] : null),
    ];
    final bool numbered = numbers.any((double? x) => x == null);
    out.add(<double>[
      for (int i = 0; i < count; i++)
        !numbered && i < numbers.length ? numbers[i]! : i + 1.0,
    ]);
  }
  return out;
}

/// Whether [series]' x values are dates: every category where it has a
/// value is a `DateTime`, and it has one.
bool _datedSeries(ChartSeries series) {
  final List<Object?> categories = series.categories.values;
  final int n = series.values.values.length;
  if (n == 0) {
    return false;
  }
  for (int i = 0; i < n; i++) {
    if (i >= categories.length || categories[i] is! DateTime) {
      return false;
    }
  }
  return true;
}

double? _number(Object? category) => switch (category) {
  final num n when n.isFinite => n.toDouble(),
  final DateTime d => excelSerialOf(d),
  _ => null,
};

/// The formatter whose `General` text gives a date's serial: en-US, whose
/// decimal separator is a point.
final NumberFormatter _serialFormatter = NumberFormatter();

/// The serial number of [date] in Excel's 1900 date system, with the time of
/// day as the fraction, as `jet_core`'s number formatter computes it (the
/// formatter shows a `DateTime` as its serial; its `General` text, at a width
/// that keeps every digit, is read back). `DateTime(2026, 1, 1)` is 46023.
double excelSerialOf(DateTime date) =>
    double.tryParse(_serialFormatter.format(date, generalWidth: 40).text) ?? 0;

/// The extent of the x values [xs] of the points that have a value in
/// [values]: the horizontal axis' data extent (`dataExtent`, clustered).
({double min, double max}) scatterXExtent(
  List<List<double>> xs,
  List<List<double?>> values,
) => dataExtent(<List<double?>>[
  for (int s = 0; s < xs.length && s < values.length; s++)
    <double?>[
      for (int i = 0; i < xs[s].length && i < values[s].length; i++)
        values[s][i] == null ? null : xs[s][i],
    ],
], ChartGrouping.clustered);

/// [x] as the horizontal axis of [chart] shows it: in the category axis'
/// format code, else as the locale's short date (built-in format 14) when
/// every series with a value has dates for x, else in `General`.
String scatterXText(double x, Chart chart, NumberFormatter formatter) {
  final String? code = chart.categoryAxis.formatCode;
  if (code != null) {
    return formatter.format(x, numberFormat: code).text;
  }
  final Iterable<ChartSeries> withValues = chart.series.where(
    (ChartSeries s) => s.values.values.isNotEmpty,
  );
  if (withValues.isNotEmpty && withValues.every(_datedSeries)) {
    return formatter.format(x, numberFormatId: 14).text;
  }
  return formatter.format(x).text;
}

/// The point of each value of [resolved] at its x of [xs], on [plot] with
/// the vertical [scale] and the horizontal [xScale]; `null` where there is no
/// value. Coordinates stay within one plot length of the plot's edges
/// (`MarkAxes.position`).
List<List<ChartPoint?>> scatterPoints(
  ResolvedChart resolved,
  List<List<double>> xs,
  ChartRect plot,
  ValueScale scale,
  ValueScale xScale,
) {
  final MarkAxes vertical = MarkAxes(plot, scale, horizontal: false);
  final MarkAxes horizontal = MarkAxes(plot, xScale, horizontal: true);
  return <List<ChartPoint?>>[
    for (int s = 0; s < resolved.values.length; s++)
      <ChartPoint?>[
        for (int i = 0; i < resolved.values[s].length; i++)
          resolved.values[s][i] == null || i >= xs[s].length
              ? null
              : ChartPoint(
                  horizontal.position(xs[s][i]),
                  vertical.position(resolved.values[s][i]!),
                ),
      ],
  ];
}

/// The colour of [chart]'s series [series] at point [index]: its point
/// colour, else [seriesColor].
ChartColor scatterPointColor(
  Chart chart,
  int series,
  int index,
  ChartColor seriesColor,
) {
  final List<ChartColor?> points = chart.series[series].pointColors;
  return (index < points.length ? points[index] : null) ?? seriesColor;
}

/// The markers of a scatter chart, one per point with a value: a line
/// chart's marker (`lineMarker`) `series/<s>/marker/<i>` in the point's
/// colour ([scatterPointColor]), in series then point order. No lines are
/// drawn.
List<ChartPrimitive> scatterMarks(
  Chart chart,
  ResolvedChart resolved,
  ChartTheme theme,
  ChartRect plot,
  ValueScale scale,
  ScatterAxis x,
) {
  final List<List<ChartPoint?>> points = scatterPoints(
    resolved,
    x.values,
    plot,
    scale,
    x.scale,
  );
  return <ChartPrimitive>[
    for (int s = 0; s < points.length; s++)
      for (int i = 0; i < points[s].length; i++)
        if (points[s][i] != null)
          lineMarker(
            ids.seriesMarkerId(s, i),
            points[s][i]!,
            scatterPointColor(chart, s, i, resolved.colors[s]),
            theme,
          ),
  ];
}

/// The anchors of a scatter chart's data labels: each marker's centre.
List<MarkAnchor> scatterAnchors(
  Chart chart,
  ResolvedChart resolved,
  ChartRect plot,
  ValueScale scale,
  ScatterAxis x,
) {
  final List<List<ChartPoint?>> points = scatterPoints(
    resolved,
    x.values,
    plot,
    scale,
    x.scale,
  );
  return <MarkAnchor>[
    for (int s = 0; s < points.length; s++)
      for (int i = 0; i < points[s].length; i++)
        if (points[s][i] != null) MarkAnchor(s, i, point: points[s][i]),
  ];
}
