import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_core/jet_core.dart';
import 'package:test/test.dart';

import '../support/gallery.dart';

final ChartTheme _office = ChartTheme.office;

Chart _chart(String name) =>
    galleryCharts().firstWhere((GalleryChart g) => g.name == name).chart;

ChartLayout _layout(
  Chart chart, {
  ChartSize size = goldenSize,
  FormatLocale locale = FormatLocale.enUS,
}) => layoutChart(
  chart,
  theme: _office,
  size: size,
  measurer: const FixedWidthTextMeasurer(),
  locale: locale,
);

Iterable<ChartPrimitive> _flat(List<ChartPrimitive> list) sync* {
  for (final ChartPrimitive p in list) {
    yield p;
    if (p is ClipPrimitive) {
      yield* _flat(p.children);
    }
  }
}

T _byId<T extends ChartPrimitive>(ChartLayout layout, String id) =>
    _flat(layout.primitives).firstWhere((ChartPrimitive p) => p.id == id) as T;

ChartPoint _centre(ChartRect r) =>
    ChartPoint(r.left + r.width / 2, r.top + r.height / 2);

ChartPoint _along(ChartPoint a, ChartPoint b, double t) =>
    ChartPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);

ChartSeries _series(String name, List<Object> categories, List<double?> v) =>
    ChartSeries(
      name: ChartData<String>(values: <String?>[name]),
      categories: ChartData<Object>(values: categories),
      values: ChartData<double>(values: v),
    );

void main() {
  group('column_clustered', () {
    final Chart chart = _chart('column_clustered');
    final ChartLayout layout = _layout(chart);

    test('a bar gives its point', () {
      final ChartPoint p = _centre(
        _byId<RectPrimitive>(layout, 'series/1/bar/2').rect,
      );
      final ChartTooltip? tip = chartTooltipAt(
        chart,
        layout,
        p,
        theme: _office,
      );
      expect(
        tip,
        ChartTooltip(
          title: 'Q3',
          rows: <ChartTooltipRow>[
            ChartTooltipRow(
              color: _office.seriesColor(1),
              label: 'South',
              value: '14',
            ),
          ],
          sourceId: 'series/1/bar/2',
        ),
      );
      expect(
        chartTooltipFor(chart, layout, 'series/1/bar/2', theme: _office),
        tip,
      );
    });

    test('a legend entry gives the series name and no rows', () {
      for (final String id in <String>['legend/1/text', 'legend/1/symbol']) {
        final ChartPrimitive entry = _byId<ChartPrimitive>(layout, id);
        final ChartPoint p = _centre(switch (entry) {
          RectPrimitive(:final ChartRect rect) => rect,
          TextPrimitive(:final ChartRect rect) => rect,
          _ => throw StateError('unexpected $entry'),
        });
        final ChartTooltip tip = chartTooltipAt(
          chart,
          layout,
          p,
          theme: _office,
        )!;
        expect(tip.title, 'South');
        expect(tip.rows, isEmpty);
        expect(tip.sourceId, id);
      }
    });

    test('empty plot gives the category of the band under it', () {
      final ChartRect band = layout.categoryBands[3];
      // Just under the plot's top, at the band's left quarter: no bar.
      final ChartPoint p = ChartPoint(
        band.left + band.width * 0.1,
        band.top + 1,
      );
      final ChartTooltip tip = chartTooltipAt(
        chart,
        layout,
        p,
        theme: _office,
      )!;
      expect(tip.title, 'Q4');
      expect(tip.sourceId, 'plot/clip');
      expect(tip.rows, <ChartTooltipRow>[
        ChartTooltipRow(
          color: _office.seriesColor(0),
          label: 'North',
          value: '15',
        ),
        ChartTooltipRow(
          color: _office.seriesColor(1),
          label: 'South',
          value: '10',
        ),
        ChartTooltipRow(
          color: _office.seriesColor(2),
          label: 'West',
          value: '13',
        ),
      ]);
    });

    test('a category label gives every series at it', () {
      final ChartTooltip tip = chartTooltipAt(
        chart,
        layout,
        _centre(_byId<TextPrimitive>(layout, 'axis/category/label/0').rect),
        theme: _office,
      )!;
      expect(tip.title, 'Q1');
      expect(tip.rows.map((ChartTooltipRow r) => r.value), <String>[
        '12',
        '8',
        '5',
      ]);
      expect(tip.sourceId, 'axis/category/label/0');
    });

    test('a value tick label is an axis tick, not data', () {
      expect(
        chartTooltipFor(chart, layout, 'axis/value/label/1', theme: _office),
        isNull,
      );
    });

    test('an unknown id gives null', () {
      for (final String id in <String>[
        'nope',
        'series/9/bar/0',
        'series/0/bar/99',
        'legend/7/text',
        'axis/category/label/40',
        '',
      ]) {
        expect(chartTooltipFor(chart, layout, id, theme: _office), isNull);
      }
    });

    test('rows and the tooltip are values', () {
      final ChartTooltip tip = chartTooltipFor(
        chart,
        layout,
        'series/0/bar/0',
        theme: _office,
      )!;
      expect(
        () => tip.rows.add(const ChartTooltipRow(label: 'x', value: 'y')),
        throwsUnsupportedError,
      );
      final ChartTooltip same = chartTooltipFor(
        chart,
        layout,
        'series/0/bar/0',
        theme: _office,
      )!;
      expect(same, tip);
      expect(same.hashCode, tip.hashCode);
    });
  });

  test('a line between markers gives the band under it', () {
    final Chart chart = _chart('line_gap');
    final ChartLayout layout = _layout(chart);
    final PathPrimitive first = _byId<PathPrimitive>(layout, 'series/0/line/0');
    final ChartTooltip mon = chartTooltipAt(
      chart,
      layout,
      _along(first.points[0], first.points[1], 0.25),
      theme: _office,
    )!;
    expect(mon.title, 'Mon');
    expect(mon.sourceId, 'series/0/line/0');
    expect(mon.rows, <ChartTooltipRow>[
      ChartTooltipRow(
        color: _office.seriesColor(0),
        label: 'Visits',
        value: '4',
      ),
      ChartTooltipRow(
        color: _office.seriesColor(1),
        label: 'Orders',
        value: '2',
      ),
    ]);
    // Thursday has no Orders value: one row.
    final PathPrimitive second = _byId<PathPrimitive>(
      layout,
      'series/0/line/1',
    );
    final ChartTooltip thu = chartTooltipAt(
      chart,
      layout,
      _along(second.points[0], second.points[1], 0.25),
      theme: _office,
    )!;
    expect(thu.title, 'Thu');
    expect(thu.rows, <ChartTooltipRow>[
      ChartTooltipRow(
        color: _office.seriesColor(0),
        label: 'Visits',
        value: '9',
      ),
    ]);
    // The line has no category of its own without a point.
    expect(
      chartTooltipFor(chart, layout, 'series/0/line/0', theme: _office),
      isNull,
    );
  });

  test('a cut category label gives its full text', () {
    final Chart chart = _chart('column_long_labels');
    final ChartLayout layout = _layout(chart);
    final TextPrimitive label = _byId<TextPrimitive>(
      layout,
      'axis/category/label/1',
    );
    expect(label.text, endsWith('…'));
    final ChartTooltip tip = chartTooltipAt(
      chart,
      layout,
      _centre(label.rect),
      theme: _office,
    )!;
    expect(tip.title, 'Southern region, first half');
    expect(tip.rows.single.label, 'Revenue');
    expect(tip.rows.single.value, '95');
  });

  test('a percent stacked chart adds the share', () {
    final Chart chart = _chart('column_percent');
    final ChartLayout layout = _layout(chart);
    final ChartTooltip tip = chartTooltipFor(
      chart,
      layout,
      'series/0/bar/1',
      theme: _office,
    )!;
    // Q2: North 18, South 11, West 7.
    final int share = (18 / (18 + 11 + 7) * 100).round();
    expect(tip.rows.single.value, '18 ($share%)');
  });

  test("the series' format code wins, in the locale", () {
    final Chart chart = Chart(
      kind: ChartKind.column,
      valueAxis: const ChartAxis(gridLines: true, formatCode: '0.0'),
      series: <ChartSeries>[
        _series(
          'Lira',
          <Object>['A'],
          <double?>[1234.5],
        ).copyWith(formatCode: '#,##0.00 "₺"'),
        _series('Plain', <Object>['A'], <double?>[2.25]),
      ],
    );
    final ChartLayout layout = _layout(chart, locale: FormatLocale.trTR);
    final ChartTooltip tip = chartTooltipFor(
      chart,
      layout,
      'axis/category/label/0',
      theme: _office,
      locale: FormatLocale.trTR,
    )!;
    expect(tip.rows.map((ChartTooltipRow r) => r.value), <String>[
      '1.234,50 ₺',
      // Falls back to the value axis' code.
      '2,3',
    ]);
  });

  test('null and non-finite values make no row; no row left is null', () {
    final Chart chart = Chart(
      kind: ChartKind.column,
      series: <ChartSeries>[
        _series('One', <Object>['A', 'B'], <double?>[1, null]),
        _series('Two', <Object>['A', 'B'], <double?>[double.nan, null]),
      ],
    );
    final ChartLayout layout = _layout(chart);
    final ChartTooltip a = chartTooltipFor(
      chart,
      layout,
      'axis/category/label/0',
      theme: _office,
    )!;
    expect(a.rows.single.label, 'One');
    expect(
      chartTooltipFor(chart, layout, 'axis/category/label/1', theme: _office),
      isNull,
    );
  });

  test('a hidden title shows in the background tooltip', () {
    final Chart chart = _chart('column_clustered');
    final ChartLayout layout = _layout(chart, size: const ChartSize(60, 40));
    expect(layout.hidden.map((ChartHiddenLabel h) => h.id), contains('title'));
    final ChartTooltip tip = chartTooltipAt(
      chart,
      layout,
      const ChartPoint(2, 2),
      theme: _office,
    )!;
    expect(tip.title, 'Sales by quarter');
    expect(tip.sourceId, 'background');
    // The background of a chart that shows its title has no tooltip.
    final ChartLayout full = _layout(chart);
    expect(
      chartTooltipAt(chart, full, const ChartPoint(2, 2), theme: _office),
      isNull,
    );
  });

  test('hidden axis titles show as rows of the background tooltip', () {
    final Chart chart = _chart('column_clustered').copyWith(
      title: const ChartTitle(text: 'T'),
      valueAxis: const ChartAxis(gridLines: true, title: 'Amount'),
      categoryAxis: const ChartAxis(title: 'Quarter'),
    );
    final ChartLayout layout = _layout(chart, size: const ChartSize(60, 40));
    final ChartTooltip tip = chartTooltipFor(
      chart,
      layout,
      'background',
      theme: _office,
    )!;
    final Set<String> hidden = <String>{
      for (final ChartHiddenLabel h in layout.hidden) h.id,
    };
    expect(tip.title, hidden.contains('title') ? 'T' : null);
    expect(tip.rows.map((ChartTooltipRow r) => r.label), <String>[
      if (hidden.contains('axis/value/title')) 'Amount',
      if (hidden.contains('axis/category/title')) 'Quarter',
    ]);
    expect(tip.rows, isNotEmpty);
  });

  test('a point outside the chart gives null', () {
    final Chart chart = _chart('column_clustered');
    final ChartLayout layout = _layout(chart);
    expect(
      chartTooltipAt(chart, layout, const ChartPoint(-50, -50), theme: _office),
      isNull,
    );
    expect(
      chartTooltipAt(
        chart,
        layout,
        const ChartPoint(double.nan, 3),
        theme: _office,
      ),
      isNull,
    );
  });
}
