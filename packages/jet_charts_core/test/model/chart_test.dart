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

  group('holeSizePercent and centerText', () {
    Chart donut({double? hole, String? text}) => hole == null
        ? Chart(kind: ChartKind.line, series: <ChartSeries>[])
        : Chart(
            kind: ChartKind.line,
            series: <ChartSeries>[],
            holeSizePercent: hole,
            centerText: text,
          );

    test('defaults', () {
      final Chart c = donut();
      expect(c.holeSizePercent, 75);
      expect(c.centerText, isNull);
    });

    test('copyWith sets and keeps them', () {
      final Chart c = donut().copyWith(holeSizePercent: 50, centerText: 'T');
      expect(c.holeSizePercent, 50);
      expect(c.centerText, 'T');
      final Chart kept = c.copyWith(kind: ChartKind.bar);
      expect(kept.holeSizePercent, 50);
      expect(kept.centerText, 'T');
    });

    test('they change == and hashCode', () {
      final Chart a = donut();
      final Chart b = a.copyWith(holeSizePercent: 50);
      final Chart c = a.copyWith(centerText: 'T');
      expect(a, isNot(b));
      expect(a, isNot(c));
      expect(a.hashCode, isNot(b.hashCode));
      expect(a.hashCode, isNot(c.hashCode));
    });

    test('the hole size must be finite and within 10 to 90', () {
      for (final double bad in <double>[9, 90.5, double.nan, double.infinity]) {
        expect(() => donut(hole: bad), throwsArgumentError, reason: '$bad');
      }
      expect(donut(hole: 10).holeSizePercent, 10);
      expect(donut(hole: 90).holeSizePercent, 90);
      expect(() => donut().copyWith(holeSizePercent: 95), throwsArgumentError);
    });
  });
}
