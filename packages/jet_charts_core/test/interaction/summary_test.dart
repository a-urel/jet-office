import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

import '../support/gallery.dart';

Chart _chart(String name) =>
    galleryCharts().firstWhere((GalleryChart g) => g.name == name).chart;

void main() {
  test('a pie gives the share of each value', () {
    final ChartSummary summary = summarizeChart(
      Chart(
        kind: ChartKind.pie,
        series: <ChartSeries>[
          ChartSeries(
            name: ChartData<String>(values: <String?>['Share']),
            categories: ChartData<Object>(
              values: <Object?>['a', 'b', 'c', 'd'],
            ),
            values: ChartData<double>(values: <double?>[1, 1, 2, null]),
          ),
        ],
      ),
    );
    expect(summary.shares, <List<String>>[
      <String>['25%', '25%', '50%', ''],
    ]);
    expect(summary.centerText, isNull);
  });

  test('a pie gives no shares for the series it does not draw', () {
    ChartSeries series(List<double?> v) => ChartSeries(
      name: ChartData<String>(values: <String?>['S']),
      categories: ChartData<Object>(values: <Object?>['a', 'b']),
      values: ChartData<double>(values: v),
    );
    final Chart pie = Chart(
      kind: ChartKind.pie,
      series: <ChartSeries>[
        series(<double?>[1, 3]),
        series(<double?>[2, 2]),
      ],
    );
    expect(summarizeChart(pie).shares, <List<String>>[
      <String>['25%', '75%'],
      <String>['', ''],
    ]);
    expect(
      summarizeChart(pie.copyWith(kind: ChartKind.donut)).shares,
      <List<String>>[
        <String>['25%', '75%'],
        <String>['50%', '50%'],
      ],
    );
  });

  test('a donut gives its centre text', () {
    final ChartSummary summary = summarizeChart(_chart('donut_center'));
    expect(summary.centerText, _chart('donut_center').centerText);
    expect(summary.shares.first[1], '40%');
    expect(
      summary,
      isNot(
        summarizeChart(_chart('donut_center').copyWith(centerText: 'Other')),
      ),
    );
  });

  test('other kinds have no shares', () {
    final ChartSummary summary = summarizeChart(_chart('column_clustered'));
    expect(summary.shares, <List<String>>[<String>[], <String>[], <String>[]]);
    expect(summary.centerText, isNull);
  });

  test('column_clustered', () {
    final ChartSummary summary = summarizeChart(_chart('column_clustered'));
    expect(summary.kind, ChartKind.column);
    expect(summary.title, 'Sales by quarter');
    expect(summary.seriesNames, <String>['North', 'South', 'West']);
    expect(summary.categories, <String>['Q1', 'Q2', 'Q3', 'Q4']);
    expect(summary.values, hasLength(3));
    expect(summary.values[0], <String>['12', '18', '9', '15']);
    expect(summary.minimum, '5');
    expect(summary.maximum, '18');
    expect(summary.isEmpty, isFalse);
    expect(summarizeChart(_chart('column_clustered')), summary);
    expect(
      summarizeChart(_chart('column_clustered')).hashCode,
      summary.hashCode,
    );
    expect(() => summary.values[0].add('x'), throwsUnsupportedError);
    expect(() => summary.values.add(<String>[]), throwsUnsupportedError);
  });

  test('missing values are empty texts', () {
    final ChartSummary summary = summarizeChart(_chart('line_gap'));
    expect(summary.values[0], <String>['4', '7', '', '9', '6', '11']);
    expect(summary.minimum, '2');
    expect(summary.maximum, '11');
  });

  test('only null and NaN values is empty', () {
    final Chart chart = Chart(
      kind: ChartKind.line,
      series: <ChartSeries>[
        ChartSeries(
          name: ChartData<String>(values: <String?>[]),
          categories: ChartData<Object>(values: <Object?>['a', 'b']),
          values: ChartData<double>(values: <double?>[null, double.nan]),
        ),
      ],
    );
    final ChartSummary summary = summarizeChart(chart);
    expect(summary.isEmpty, isTrue);
    expect(summary.minimum, isNull);
    expect(summary.maximum, isNull);
    expect(summary.title, isNull);
    expect(summary.seriesNames, <String>['Series 1']);
    expect(summary.values, <List<String>>[
      <String>['', ''],
    ]);
    expect(
      summarizeChart(
        Chart(kind: ChartKind.bar, series: <ChartSeries>[]),
      ).isEmpty,
      isTrue,
    );
  });

  test('a date category shows as the layout shows it', () {
    final Chart chart = Chart(
      kind: ChartKind.column,
      series: <ChartSeries>[
        ChartSeries(
          name: ChartData<String>(values: <String?>['Sales']),
          categories: ChartData<Object>(
            values: <Object?>[DateTime(2026, 3, 14), DateTime(2026, 3, 15)],
          ),
          values: ChartData<double>(values: <double?>[1, 2]),
        ),
      ],
    );
    final ChartLayout layout = layoutChart(
      chart,
      theme: ChartTheme.office,
      size: goldenSize,
      measurer: const FixedWidthTextMeasurer(),
    );
    final TextPrimitive label =
        layout.primitives.firstWhere(
              (ChartPrimitive p) => p.id == 'axis/category/label/0',
            )
            as TextPrimitive;
    final ChartSummary summary = summarizeChart(chart);
    expect(summary.categories.first, label.text);
    expect(summary.categories.first, '3/14/26');
  });

  test("each value takes its series' format code", () {
    final Chart chart = Chart(
      kind: ChartKind.column,
      series: <ChartSeries>[
        ChartSeries(
          name: ChartData<String>(values: <String?>['A']),
          categories: ChartData<Object>(values: <Object?>['x']),
          values: ChartData<double>(values: <double?>[0.25]),
          formatCode: '0%',
        ),
        ChartSeries(
          name: ChartData<String>(values: <String?>['B']),
          categories: ChartData<Object>(values: <Object?>['x']),
          values: ChartData<double>(values: <double?>[3]),
        ),
      ],
    );
    final ChartSummary summary = summarizeChart(chart);
    expect(summary.values, <List<String>>[
      <String>['25%'],
      <String>['3'],
    ]);
    expect(summary.minimum, '25%');
    expect(summary.maximum, '3');
  });

  test('a sparkline is summarized as a line chart is', () {
    ChartSeries series(ChartKind kind) => ChartSeries(
      name: ChartData<String>(values: <String?>['Refunds']),
      categories: ChartData<Object>(values: <Object?>['a', 'b', 'c']),
      values: ChartData<double>(values: <double?>[2, 7, null]),
    );
    final ChartSummary spark = summarizeChart(
      Chart(
        kind: ChartKind.sparkline,
        series: <ChartSeries>[series(ChartKind.line)],
      ),
    );
    final ChartSummary line = summarizeChart(
      Chart(
        kind: ChartKind.line,
        series: <ChartSeries>[series(ChartKind.line)],
      ),
    );
    expect(spark.kind, ChartKind.sparkline);
    expect(spark.values, line.values);
    expect(spark.categories, line.categories);
    expect(spark.minimum, '2');
    expect(spark.maximum, '7');
    expect(spark.shares, line.shares);
    expect(spark.isEmpty, isFalse);
  });
}
