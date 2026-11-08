import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_core/src/layout/chart_ids.dart' as ids;
import 'package:jet_charts_core/src/layout/resolve.dart';
import 'package:jet_core/jet_core.dart';
import 'package:test/test.dart';

ChartSeries series(
  List<double?> values, {
  List<Object?> categories = const <Object?>[],
  String? name,
  String? formatCode,
}) {
  return ChartSeries(
    name: ChartData<String>(values: <String?>[?name]),
    categories: ChartData<Object>(values: categories),
    values: ChartData<double>(values: values),
    formatCode: formatCode,
  );
}

ResolvedChart resolve(Chart chart, {FormatLocale locale = FormatLocale.enUS}) {
  return resolveChart(
    chart,
    ChartTheme.office,
    NumberFormatter(locale: locale),
  );
}

void main() {
  test('NaN and infinity resolve to null', () {
    final ResolvedChart resolved = resolve(
      Chart(
        kind: ChartKind.column,
        series: <ChartSeries>[
          series(<double?>[
            1,
            double.nan,
            double.infinity,
            double.negativeInfinity,
            null,
            2,
          ]),
        ],
      ),
    );
    expect(resolved.values, <List<double?>>[
      <double?>[1, null, null, null, null, 2],
    ]);
  });

  test('a short series is padded with null to the category count', () {
    final ResolvedChart resolved = resolve(
      Chart(
        kind: ChartKind.column,
        series: <ChartSeries>[
          series(<double?>[1, 2, 3], categories: <Object?>['a', 'b', 'c']),
          series(<double?>[4]),
        ],
      ),
    );
    expect(resolved.categoryCount, 3);
    expect(resolved.values[1], <double?>[4, null, null]);
  });

  test('dates use the locale\'s short date', () {
    final DateTime day = DateTime(2026, 3, 5);
    final Chart chart = Chart(
      kind: ChartKind.column,
      series: <ChartSeries>[
        series(<double?>[1], categories: <Object?>[day]),
      ],
    );
    expect(resolve(chart).categoryLabels, <String>['3/5/26']);
    expect(resolve(chart, locale: FormatLocale.trTR).categoryLabels, <String>[
      '05.03.2026',
    ]);
  });

  test('a date takes the axis code, then the series code', () {
    final DateTime day = DateTime(2026, 3, 5);
    final Chart bySeries = Chart(
      kind: ChartKind.column,
      series: <ChartSeries>[
        series(
          <double?>[1],
          categories: <Object?>[day],
          formatCode: 'yyyy-mm-dd',
        ),
      ],
    );
    expect(resolve(bySeries).categoryLabels, <String>['2026-03-05']);
    final Chart byAxis = bySeries.copyWith(
      categoryAxis: const ChartAxis(formatCode: 'mmm d'),
    );
    expect(resolve(byAxis).categoryLabels, <String>['Mar 5']);
  });

  test('a date ignores a series code that is not a date or time', () {
    final DateTime day = DateTime(2026, 3, 5);
    final Chart currency = Chart(
      kind: ChartKind.column,
      series: <ChartSeries>[
        series(
          <double?>[1],
          categories: <Object?>[day],
          formatCode: '"\$"#,##0.00',
        ),
      ],
    );
    expect(resolve(currency).categoryLabels, <String>['3/5/26']);
    expect(
      resolve(currency, locale: FormatLocale.trTR).categoryLabels,
      <String>['05.03.2026'],
    );
    final Chart time = Chart(
      kind: ChartKind.column,
      series: <ChartSeries>[
        series(
          <double?>[1],
          categories: <Object?>[DateTime(2026, 3, 5, 14, 30)],
          formatCode: 'h:mm',
        ),
      ],
    );
    expect(resolve(time).categoryLabels, <String>['14:30']);
  });

  test('numbers show as General and text as it is', () {
    final ResolvedChart resolved = resolve(
      Chart(
        kind: ChartKind.column,
        series: <ChartSeries>[
          series(
            <double?>[1, 2, 3],
            categories: <Object?>[1.5, 'İstanbul', null],
          ),
        ],
      ),
    );
    expect(resolved.categoryLabels, <String>['1.5', 'İstanbul', '']);
  });

  test('a chart without category values numbers its categories', () {
    final ResolvedChart resolved = resolve(
      Chart(
        kind: ChartKind.column,
        series: <ChartSeries>[
          series(<double?>[1, 2, 3]),
        ],
      ),
    );
    expect(resolved.categoryLabels, <String>['1', '2', '3']);
  });

  test('a series without a name is named by its number', () {
    final ResolvedChart resolved = resolve(
      Chart(
        kind: ChartKind.column,
        series: <ChartSeries>[
          series(<double?>[1], name: 'Sales'),
          series(<double?>[1]),
        ],
      ),
    );
    expect(resolved.seriesNames, <String>['Sales', 'Series 2']);
  });

  test('tick labels take the axis code, then the series code', () {
    final Chart chart = Chart(
      kind: ChartKind.column,
      series: <ChartSeries>[
        series(<double?>[1], formatCode: '0.0'),
      ],
    );
    expect(resolve(chart).tickFormatCode, '0.0');
    expect(
      resolve(
        chart.copyWith(valueAxis: const ChartAxis(formatCode: '#,##0')),
      ).tickFormatCode,
      '#,##0',
    );
    expect(
      resolve(
        Chart(
          kind: ChartKind.column,
          series: <ChartSeries>[
            series(<double?>[1]),
          ],
        ),
      ).tickFormatCode,
      'General',
    );
  });

  test('a percent axis shows 0%', () {
    final Chart chart = Chart(
      kind: ChartKind.column,
      grouping: ChartGrouping.percentStacked,
      series: <ChartSeries>[
        series(<double?>[1, 3], formatCode: '0.0'),
        series(<double?>[2, 1]),
      ],
    );
    expect(resolve(chart).tickFormatCode, '0%');
    final ChartLayout layout = layoutChart(
      chart,
      theme: ChartTheme.office,
      size: const ChartSize(400, 300),
      measurer: const FixedWidthTextMeasurer(),
    );
    final List<String> labels = layout.primitives
        .whereType<TextPrimitive>()
        .where((TextPrimitive t) => t.id.startsWith('axis/value/label/'))
        .map((TextPrimitive t) => t.text)
        .toList();
    expect(labels.first, '0%');
    expect(labels.last, '100%');
    expect(
      layout.primitives.any(
        (ChartPrimitive p) => p.id == ids.axisLabelId(ids.valueAxis, 0),
      ),
      isTrue,
    );
  });
}
