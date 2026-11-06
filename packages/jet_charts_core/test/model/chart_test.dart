import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

ChartSeries series(List<double?> values) {
  return ChartSeries(
    name: ChartData<String>(values: <String?>['Sales']),
    categories: ChartData<Object>(values: <Object?>['a', 'b']),
    values: ChartData<double>(values: values),
  );
}

void main() {
  test('equal charts are equal and hash equal', () {
    final Chart a = Chart(
      kind: ChartKind.column,
      series: <ChartSeries>[
        series(<double?>[1, double.nan]),
      ],
      title: const ChartTitle(text: 'T'),
    );
    final Chart b = Chart(
      kind: ChartKind.column,
      series: <ChartSeries>[
        series(<double?>[1, double.nan]),
      ],
      title: const ChartTitle(text: 'T'),
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(a.copyWith(kind: ChartKind.bar)));
  });

  test('defaults', () {
    final Chart c = Chart(kind: ChartKind.line, series: <ChartSeries>[]);
    expect(c.grouping, ChartGrouping.clustered);
    expect(c.categoryAxis.gridLines, isFalse);
    expect(c.valueAxis.gridLines, isTrue);
    expect(c.valueAxis.visible, isTrue);
    expect(c.legend.position, ChartLegendPosition.bottom);
    expect(c.legend.visible, isTrue);
    expect(c.dataLabels.visible, isFalse);
    expect(c.secondaryValueAxis, isNull);
    expect(c.unsupportedName, isNull);
  });

  test('series list is copied and unmodifiable', () {
    final List<ChartSeries> source = <ChartSeries>[
      series(<double?>[1]),
    ];
    final Chart c = Chart(kind: ChartKind.column, series: source);
    source.add(series(<double?>[2]));
    expect(c.series.length, 1);
    expect(() => c.series.add(series(<double?>[3])), throwsUnsupportedError);
  });

  test('copyWith changes one field', () {
    final Chart c = Chart(
      kind: ChartKind.column,
      series: <ChartSeries>[
        series(<double?>[1]),
      ],
    );
    final Chart d = c.copyWith(grouping: ChartGrouping.stacked);
    expect(d.grouping, ChartGrouping.stacked);
    expect(d.kind, c.kind);
    expect(d.series, c.series);
    expect(c.copyWith(), c);
    expect(c.copyWith(unsupportedName: 'radar').unsupportedName, 'radar');
  });

  test('parts compare by value', () {
    expect(const ChartAxis(min: 1), const ChartAxis(min: 1));
    expect(const ChartAxis(min: 1), isNot(const ChartAxis(min: 2)));
    expect(const ChartAxis().copyWith(max: 5).max, 5);
    expect(const ChartLegend().copyWith(visible: false).visible, isFalse);
    expect(
      const ChartDataLabels(formatCode: '0'),
      const ChartDataLabels(formatCode: '0'),
    );
    expect(const ChartTitle(text: 'a').copyWith(text: 'b').text, 'b');
    expect(const ChartAxis(min: double.nan), const ChartAxis(min: double.nan));
  });
}
