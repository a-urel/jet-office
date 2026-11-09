// JetChartStrings: the state texts and the screen reader's description.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';
import 'package:jet_core/jet_core.dart';

import 'support/charts.dart';

Chart _chart(String name) => goldenCharts()
    .firstWhere(((String, Chart, ChartSize) g) => g.$1 == name)
    .$2;

ChartSeries _series(String name, List<Object> categories, List<double?> v) =>
    ChartSeries(
      name: ChartData<String>(values: <String?>[name]),
      categories: ChartData<Object>(values: categories),
      values: ChartData<double>(values: v),
    );

void main() {
  test('English describes column_clustered', () {
    expect(
      JetChartStrings.en.describe(summarizeChart(_chart('column_clustered'))),
      'Column chart: Sales by quarter. '
      'Series (3): North, South, West. '
      'Categories (4): Q1 to Q4. '
      'Values from 5 to 18. '
      'North: Q1 12, Q2 18, Q3 9, Q4 15. '
      'South: Q1 8, Q2 11, Q3 14, Q4 10. '
      'West: Q1 5, Q2 7, Q3 6, Q4 13.',
    );
  });

  test('Turkish describes column_clustered', () {
    expect(
      JetChartStrings.tr.describe(
        summarizeChart(_chart('column_clustered'), locale: FormatLocale.trTR),
      ),
      'Sütun grafik: Sales by quarter. '
      'Seriler (3): North, South, West. '
      'Kategoriler (4): Q1 ile Q4 arası. '
      'Değerler 5 ile 18 arasında. '
      'North: Q1 12, Q2 18, Q3 9, Q4 15. '
      'South: Q1 8, Q2 11, Q3 14, Q4 10. '
      'West: Q1 5, Q2 7, Q3 6, Q4 13.',
    );
  });

  test('German describes column_clustered', () {
    expect(
      JetChartStrings.de.describe(
        summarizeChart(_chart('column_clustered'), locale: FormatLocale.deDE),
      ),
      'Säulendiagramm: Sales by quarter. '
      'Datenreihen (3): North, South, West. '
      'Kategorien (4): Q1 bis Q4. '
      'Werte von 5 bis 18. '
      'North: Q1 12, Q2 18, Q3 9, Q4 15. '
      'South: Q1 8, Q2 11, Q3 14, Q4 10. '
      'West: Q1 5, Q2 7, Q3 6, Q4 13.',
    );
  });

  test('numbers come formatted for the locale of the summary', () {
    final Chart chart = Chart(
      kind: ChartKind.line,
      series: <ChartSeries>[
        _series('Rate', <Object>['a', 'b'], <double?>[1.5, 2.25]),
      ],
    );
    expect(
      JetChartStrings.tr.describe(
        summarizeChart(chart, locale: FormatLocale.trTR),
      ),
      'Çizgi grafik. '
      'Seriler (1): Rate. '
      'Kategoriler (2): a ile b arası. '
      'Değerler 1,5 ile 2,25 arasında. '
      'Rate: a 1,5, b 2,25.',
    );
  });

  test('more than 12 values end with the moreValues text', () {
    final List<Object> months = <Object>[for (int i = 1; i <= 15; i++) 'M$i'];
    final Chart chart = Chart(
      kind: ChartKind.column,
      series: <ChartSeries>[
        _series('Sales', months, <double?>[
          for (int i = 1; i <= 15; i++) i * 1,
        ]),
      ],
    );
    final String text = JetChartStrings.en.describe(summarizeChart(chart));
    expect(
      text,
      endsWith(
        'Sales: M1 1, M2 2, M3 3, M4 4, M5 5, M6 6, M7 7, M8 8, M9 9, '
        'M10 10, M11 11, M12 12 and 3 more.',
      ),
    );
    expect(
      JetChartStrings.tr.describe(summarizeChart(chart)),
      endsWith('M12 12 ve 3 değer daha.'),
    );
    expect(
      JetChartStrings.de.describe(summarizeChart(chart)),
      endsWith('M12 12 und 3 weitere.'),
    );
  });

  test('missing values are left out of the pairs', () {
    final String text = JetChartStrings.en.describe(
      summarizeChart(_chart('line_gap')),
    );
    expect(text, contains('Visits: Mon 4, Tue 7, Thu 9, Fri 6, Sat 11.'));
  });

  test('a placeholder in a category name is not replaced again', () {
    final Chart chart = Chart(
      kind: ChartKind.bar,
      series: <ChartSeries>[
        _series('S', <Object>['{last}', 'z'], <double?>[1, 2]),
      ],
    );
    expect(
      JetChartStrings.en.describe(summarizeChart(chart)),
      contains('Categories (2): {last} to z.'),
    );
  });

  test('an empty summary names only the kind and title', () {
    final Chart chart = Chart(
      kind: ChartKind.bar,
      title: const ChartTitle(text: 'Nothing'),
      series: <ChartSeries>[],
    );
    expect(
      JetChartStrings.en.describe(summarizeChart(chart)),
      'Bar chart: Nothing.',
    );
  });

  test('every built-in names every kind', () {
    for (final JetChartStrings strings in <JetChartStrings>[
      JetChartStrings.en,
      JetChartStrings.tr,
      JetChartStrings.de,
    ]) {
      expect(strings.kindNames.keys.toSet(), ChartKind.values.toSet());
    }
    expect(JetChartStrings.tr.kindNames[ChartKind.pie], 'Pasta grafik');
    expect(JetChartStrings.tr.loading, 'Grafik yükleniyor…');
    expect(JetChartStrings.de.empty, 'Keine Daten');
    expect(JetChartStrings.en.error, 'The chart could not be shown');
  });

  test('Turkish describes a donut with its centre text and shares', () {
    final Chart chart = Chart(
      kind: ChartKind.donut,
      centerText: 'Toplam 12.450 ₺',
      series: <ChartSeries>[
        _series(
          'Satış',
          <Object>['Kuzey', 'Güney', 'Doğu'],
          <double?>[12, 18, 15],
        ),
      ],
    );
    final String text = JetChartStrings.tr.describe(
      summarizeChart(chart, locale: FormatLocale.trTR),
    );
    expect(text, startsWith('Halka grafik. Orta: Toplam 12.450 ₺.'));
    expect(text, contains('Güney 18 (40%)'));
    expect(
      text,
      endsWith('Satış: Kuzey 12 (27%), Güney 18 (40%), Doğu 15 (33%).'),
    );
    expect(
      JetChartStrings.en.describe(summarizeChart(chart)),
      contains('Center: Toplam 12.450 ₺.'),
    );
    expect(
      JetChartStrings.de.describe(
        summarizeChart(chart, locale: FormatLocale.deDE),
      ),
      contains('Mitte: Toplam 12.450 ₺.'),
    );
  });

  test('a pie reads each share after its value', () {
    final Chart chart = Chart(
      kind: ChartKind.pie,
      series: <ChartSeries>[
        _series('Sales', <Object>['a', 'b'], <double?>[1, 3]),
      ],
    );
    expect(
      JetChartStrings.en.describe(summarizeChart(chart)),
      endsWith('Sales: a 1 (25%), b 3 (75%).'),
    );
  });

  test('a scatter chart reads (x, y) pairs and no category range', () {
    final Chart chart = Chart(
      kind: ChartKind.scatter,
      series: <ChartSeries>[
        _series('Trial', <Object>[1.5, 2, 4], <double?>[10, null, 30]),
      ],
    );
    final String text = JetChartStrings.en.describe(summarizeChart(chart));
    expect(text, endsWith('Trial: (1.5, 10), (4, 30).'));
    expect(text, isNot(contains('Categories')));
  });

  test('the built-ins name the J4 kinds', () {
    expect(
      JetChartStrings.tr.kindNames,
      containsPair(ChartKind.sparkline, 'Mini grafik'),
    );
    expect(JetChartStrings.tr.kindNames[ChartKind.scatter], 'Dağılım grafiği');
    expect(
      JetChartStrings.de.kindNames[ChartKind.combination],
      'Kombinationsdiagramm',
    );
    for (final JetChartStrings strings in <JetChartStrings>[
      JetChartStrings.en,
      JetChartStrings.tr,
      JetChartStrings.de,
    ]) {
      expect(strings.share, '{value} ({percent})');
    }
    expect(JetChartStrings.tr.centerText, 'Orta: {text}');
    expect(JetChartStrings.de.centerText, 'Mitte: {text}');
    expect(JetChartStrings.en.centerText, 'Center: {text}');
  });

  test('value equality', () {
    const JetChartStrings copy = JetChartStrings(
      loading: 'Loading chart…',
      empty: 'No data',
      error: 'The chart could not be shown',
      kindNames: <ChartKind, String>{ChartKind.column: 'Column chart'},
      seriesCount: 'Series ({n})',
      categoryRange: 'Categories ({n}): {first} to {last}',
      valueRange: 'Values from {min} to {max}',
      moreValues: 'and {n} more',
      share: '{value} ({percent})',
      centerText: 'Center: {text}',
    );
    const JetChartStrings same = JetChartStrings(
      loading: 'Loading chart…',
      empty: 'No data',
      error: 'The chart could not be shown',
      kindNames: <ChartKind, String>{ChartKind.column: 'Column chart'},
      seriesCount: 'Series ({n})',
      categoryRange: 'Categories ({n}): {first} to {last}',
      valueRange: 'Values from {min} to {max}',
      moreValues: 'and {n} more',
      share: '{value} ({percent})',
      centerText: 'Center: {text}',
    );
    expect(copy, same);
    expect(copy.hashCode, same.hashCode);
    expect(copy, isNot(JetChartStrings.en));
    expect(JetChartStrings.en, JetChartStrings.en);
  });
}
