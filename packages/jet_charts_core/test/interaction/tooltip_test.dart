import 'dart:math' as math;

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
  group('scatter', () {
    final Chart chart = Chart(
      kind: ChartKind.scatter,
      series: <ChartSeries>[
        ChartSeries(
          name: ChartData<String>(values: <String?>['Points']),
          categories: ChartData<Object>(values: <Object?>[1, 2, 4]),
          values: ChartData<double>(values: <double?>[10, 20, 15]),
        ),
      ],
      dataLabels: const ChartDataLabels(visible: true),
    );
    final ChartLayout layout = _layout(chart);

    test('a marker gives its series, X and Y', () {
      final ArcPrimitive marker = _byId<ArcPrimitive>(
        layout,
        'series/0/marker/2',
      );
      final ChartTooltip tip = chartTooltipAt(
        chart,
        layout,
        marker.center,
        theme: _office,
      )!;
      expect(tip.title, 'Points');
      expect(tip.rows, const <ChartTooltipRow>[
        ChartTooltipRow(label: 'X', value: '4'),
        ChartTooltipRow(label: 'Y', value: '15'),
      ]);
      expect(tip.sourceId, 'series/0/marker/2');
    });

    test('a data label gives its point', () {
      final ChartTooltip tip = chartTooltipFor(
        chart,
        layout,
        'label/0/1',
        theme: _office,
      )!;
      expect(tip.title, 'Points');
      expect(tip.rows.map((ChartTooltipRow r) => r.value), <String>['2', '20']);
    });

    test('the plot and an x tick label have no tooltip', () {
      final ChartRect plot = layout.plotArea!;
      expect(
        chartTooltipAt(
          chart,
          layout,
          ChartPoint(plot.left + 1, plot.top + 1),
          theme: _office,
        ),
        isNull,
      );
      expect(
        chartTooltipFor(chart, layout, 'axis/category/label/0', theme: _office),
        isNull,
      );
    });
  });

  group('donut_center', () {
    final Chart chart = _chart('donut_center');
    final ChartLayout layout = _layout(chart);

    // A point of the slice off its label, which sits in the ring's middle.
    ChartPoint middle(ArcPrimitive a) {
      final double angle = (a.startAngle + a.sweepAngle / 2) * math.pi / 180;
      final double r = a.innerRadius + 0.15 * (a.radius - a.innerRadius);
      return ChartPoint(
        a.center.x + r * math.cos(angle),
        a.center.y + r * math.sin(angle),
      );
    }

    test('a slice gives its category, value and share', () {
      final ArcPrimitive slice = _byId<ArcPrimitive>(
        layout,
        'series/0/slice/1',
      );
      final List<double> values = <double>[
        for (final double? v in chart.series.first.values.values) v!.abs(),
      ];
      final double sum = values.fold(0, (double a, double b) => a + b);
      final String share = '${(18 / sum * 100).round()}%';
      final ChartTooltip expected = ChartTooltip(
        title: 'Güney',
        rows: <ChartTooltipRow>[
          ChartTooltipRow(
            color: slice.fill,
            label: 'Satış',
            value: '18 ($share)',
          ),
        ],
        sourceId: 'series/0/slice/1',
      );
      expect(share, '40%');
      expect(
        chartTooltipAt(chart, layout, middle(slice), theme: _office),
        expected,
      );
      expect(
        chartTooltipFor(chart, layout, 'series/0/slice/1', theme: _office),
        expected,
      );
      expect(
        chartTooltipFor(chart, layout, 'label/0/1', theme: _office)!.rows,
        expected.rows,
      );
    });

    test('a legend entry gives its category', () {
      final TextPrimitive text = _byId<TextPrimitive>(layout, 'legend/2/text');
      expect(text.text, 'Doğu');
      expect(
        chartTooltipAt(chart, layout, _centre(text.rect), theme: _office),
        ChartTooltip(
          title: 'Doğu',
          rows: const <ChartTooltipRow>[],
          sourceId: 'legend/2/text',
        ),
      );
    });

    test('a hidden centre text shows in the background tooltip', () {
      final ChartLayout small = _layout(chart, size: const ChartSize(120, 80));
      expect(
        small.hidden.map((ChartHiddenLabel h) => h.id),
        contains('center'),
      );
      expect(
        chartTooltipFor(chart, small, 'background', theme: _office)!.title,
        chart.centerText,
      );
    });
  });

  test('a leader line gives its slice', () {
    final Chart chart = _chart('pie_small_slices');
    final ChartLayout layout = _layout(chart);
    final PathPrimitive leader = _flat(layout.primitives)
        .whereType<PathPrimitive>()
        .firstWhere((PathPrimitive p) => p.id.endsWith('/leader'));
    final ChartTooltip? tip = chartTooltipAt(
      chart,
      layout,
      _longestMiddle(leader.points),
      theme: _office,
    );
    expect(tip, isNotNull);
    expect(tip!.sourceId, leader.id);
    expect(tip.rows, hasLength(1));
  });

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
    // At 240 wide a word of these labels is wider than its slot, so they
    // cannot wrap: they turn and are cut.
    final Chart chart = _chart('column_long_labels');
    final ChartLayout layout = _layout(chart, size: const ChartSize(240, 240));
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

  test('a percent stacked combination shares columns, not the line', () {
    final Chart chart = Chart(
      kind: ChartKind.combination,
      grouping: ChartGrouping.percentStacked,
      series: <ChartSeries>[
        _series('A', <Object>['Q1'], <double?>[1]),
        _series('B', <Object>['Q1'], <double?>[3]),
        _series(
          'Line',
          <Object>['Q1'],
          <double?>[0.5],
        ).copyWith(kind: ChartKind.line),
      ],
    );
    final ChartLayout layout = _layout(chart);
    final ChartTooltip tip = chartTooltipFor(
      chart,
      layout,
      'axis/category/label/0',
      theme: _office,
    )!;
    expect(tip.rows.map((ChartTooltipRow r) => r.value), <String>[
      '1 (25%)',
      '3 (75%)',
      '0.5',
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

  test('a marker gives its point', () {
    // A point with no neighbour is drawn as a marker.
    final Chart chart = Chart(
      kind: ChartKind.line,
      series: <ChartSeries>[
        _series('Visits', <Object>['Mon', 'Tue', 'Wed'], <double?>[4, null, 6]),
        _series('Orders', <Object>['Mon', 'Tue', 'Wed'], <double?>[2, 3, 5]),
      ],
    );
    final ChartLayout layout = _layout(chart);
    final ArcPrimitive marker = _byId<ArcPrimitive>(
      layout,
      'series/0/marker/2',
    );
    final ChartTooltip expected = ChartTooltip(
      title: 'Wed',
      rows: <ChartTooltipRow>[
        ChartTooltipRow(
          color: _office.seriesColor(0),
          label: 'Visits',
          value: '6',
        ),
      ],
      sourceId: 'series/0/marker/2',
    );
    expect(
      chartTooltipAt(chart, layout, marker.center, theme: _office),
      expected,
    );
    expect(
      chartTooltipFor(chart, layout, 'series/0/marker/2', theme: _office),
      expected,
    );
    // A marker of a category out of range has none.
    expect(
      chartTooltipFor(chart, layout, 'series/0/marker/3', theme: _office),
      isNull,
    );
  });

  test('a data label gives its point', () {
    final Chart chart = _chart('column_data_labels');
    final ChartLayout layout = _layout(chart);
    final TextPrimitive label = _byId<TextPrimitive>(layout, 'label/1/2');
    final ChartTooltip expected = ChartTooltip(
      title: 'Q3',
      rows: <ChartTooltipRow>[
        ChartTooltipRow(
          color: _office.seriesColor(1),
          label: 'South',
          value: '14',
        ),
      ],
      sourceId: 'label/1/2',
    );
    expect(
      chartTooltipAt(chart, layout, _centre(label.rect), theme: _office),
      expected,
    );
    expect(
      chartTooltipFor(chart, layout, 'label/1/2', theme: _office),
      expected,
    );
  });

  test('a hidden placeholder shows in the background tooltip', () {
    final Chart chart = Chart(
      kind: ChartKind.unsupported,
      unsupportedName: 'bubble',
      series: <ChartSeries>[
        _series('Share', <Object>['A', 'B'], <double?>[1, 2]),
      ],
    );
    // Shown, the placeholder text has no tooltip, nor has the background.
    final ChartLayout shown = _layout(chart);
    final TextPrimitive text = _byId<TextPrimitive>(shown, 'placeholder');
    expect(text.text, 'bubble');
    expect(
      chartTooltipAt(chart, shown, _centre(text.rect), theme: _office),
      isNull,
    );
    expect(
      chartTooltipFor(chart, shown, 'placeholder', theme: _office),
      isNull,
    );
    // Hidden, it is a row of the background tooltip.
    final ChartLayout small = _layout(chart, size: const ChartSize(20, 20));
    expect(
      small.hidden,
      contains(const ChartHiddenLabel('placeholder', 'bubble')),
    );
    final ChartTooltip expected = ChartTooltip(
      rows: <ChartTooltipRow>[
        const ChartTooltipRow(label: 'bubble', value: ''),
      ],
      sourceId: 'background',
    );
    expect(
      chartTooltipAt(chart, small, const ChartPoint(10, 10), theme: _office),
      expected,
    );
    expect(
      chartTooltipFor(chart, small, 'background', theme: _office),
      expected,
    );
  });

  test('given hits give the tooltip of a hit test of their own', () {
    final Chart chart = _chart('line_gap');
    final ChartLayout layout = _layout(chart);
    final PathPrimitive line = _byId<PathPrimitive>(layout, 'series/0/line/0');
    for (final ChartPoint p in <ChartPoint>[
      _along(line.points[0], line.points[1], 0.25),
      line.points[1],
      const ChartPoint(2, 2),
      const ChartPoint(-50, -50),
    ]) {
      final List<ChartPrimitive> hits = hitTestLayout(layout, p, tolerance: 2);
      expect(
        chartTooltipAt(
          chart,
          layout,
          p,
          theme: _office,
          tolerance: 2,
          hits: hits,
        ),
        chartTooltipAt(chart, layout, p, theme: _office, tolerance: 2),
        reason: '$p',
      );
    }
    // The hits are used as given: none gives no tooltip.
    expect(
      chartTooltipAt(
        chart,
        layout,
        _along(line.points[0], line.points[1], 0.25),
        theme: _office,
        hits: const <ChartPrimitive>[],
      ),
      isNull,
    );
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
  group('a sparkline', () {
    Chart spark({bool categories = true}) => Chart(
      kind: ChartKind.sparkline,
      series: <ChartSeries>[
        _series(
          'Refunds',
          categories ? <Object>['Mon', 'Tue', 'Wed'] : <Object>[],
          <double?>[1, 3, 2],
        ),
        _series(
          'Sales',
          categories ? <Object>['Mon', 'Tue', 'Wed'] : <Object>[],
          <double?>[4, null, 6],
        ),
      ],
    );

    test('over a band shows the category and each series value', () {
      final Chart chart = spark();
      final ChartLayout layout = _layout(chart, size: const ChartSize(120, 30));
      final ChartRect band = layout.categoryBands[1];
      final ChartTooltip? tip = chartTooltipAt(
        chart,
        layout,
        _centre(band),
        theme: _office,
      );
      expect(tip!.title, 'Tue');
      expect(tip.rows.map((ChartTooltipRow r) => r.label), <String>['Refunds']);
      expect(tip.rows.single.value, '3');
      final ChartTooltip? first = chartTooltipAt(
        chart,
        layout,
        _centre(layout.categoryBands[0]),
        theme: _office,
      );
      expect(first!.title, 'Mon');
      expect(first.rows, hasLength(2));
      expect(first.rows.last.value, '4');
    });

    test('has no title when the series has no categories', () {
      final Chart chart = spark(categories: false);
      final ChartLayout layout = _layout(chart, size: const ChartSize(120, 30));
      final ChartTooltip? tip = chartTooltipAt(
        chart,
        layout,
        _centre(layout.categoryBands[2]),
        theme: _office,
      );
      expect(tip!.title, isNull);
      expect(tip.rows.map((ChartTooltipRow r) => r.value), <String>['2', '6']);
    });

    test('over its own line and area gives the band tooltip', () {
      final Chart chart = Chart(
        kind: ChartKind.sparkline,
        series: <ChartSeries>[
          _series(
            'Refunds',
            <Object>['Mon', 'Tue', 'Wed'],
            <double?>[1, 3, 2],
          ).copyWith(kind: ChartKind.area),
        ],
      );
      final ChartLayout layout = _layout(chart, size: const ChartSize(120, 30));
      final PathPrimitive line = _byId(layout, 'series/0/line/0');
      final ChartPoint onLine = line.points[1];
      final ChartTooltip? atLine = chartTooltipAt(
        chart,
        layout,
        onLine,
        theme: _office,
      );
      expect(atLine!.sourceId, 'series/0/line/0');
      expect(atLine.title, 'Tue');
      final ChartPoint inArea = ChartPoint(
        onLine.x,
        layout.plotArea!.bottom - 0.5,
      );
      final ChartTooltip? atArea = chartTooltipAt(
        chart,
        layout,
        inArea,
        theme: _office,
      );
      expect(atArea!.sourceId, 'series/0/area');
      expect(atArea.title, 'Tue');
    });

    test('takes its title from the first series, as resolveChart does', () {
      Chart two(List<Object> a, List<Object> b) => Chart(
        kind: ChartKind.sparkline,
        series: <ChartSeries>[
          _series('A', a, <double?>[1, 2]),
          _series('B', b, <double?>[3, 4]),
        ],
      );
      for (final (List<Object> a, List<Object> b, String? title)
          in <(List<Object>, List<Object>, String?)>[
            (<Object>[], <Object>['x', 'y'], null),
            (<Object>['p', 'q'], <Object>[], 'p'),
          ]) {
        final Chart chart = two(a, b);
        final ChartLayout layout = _layout(
          chart,
          size: const ChartSize(120, 30),
        );
        final ChartTooltip? tip = chartTooltipAt(
          chart,
          layout,
          _centre(layout.categoryBands[0]),
          theme: _office,
        );
        expect(tip!.title, title);
      }
    });

    test('off the bands has none', () {
      final Chart chart = spark();
      final ChartLayout layout = _layout(chart, size: const ChartSize(120, 30));
      expect(
        chartTooltipAt(
          chart,
          layout,
          const ChartPoint(0.1, 0.1),
          theme: _office,
        ),
        isNull,
      );
    });
  });

  test('a bar\'s and a marker\'s row take the point colour', () {
    final ChartColor gold = ChartColor.rgb(0xFBBF24);
    for (final ChartKind kind in <ChartKind>[
      ChartKind.column,
      ChartKind.line,
    ]) {
      final Chart chart = Chart(
        kind: kind,
        series: <ChartSeries>[
          _series(
            'Sales',
            <Object>['A', 'B', 'C'],
            <double?>[1, 2, 3],
          ).copyWith(pointColors: <ChartColor?>[null, gold]),
        ],
      );
      final ChartLayout layout = _layout(chart);
      final String id = kind == ChartKind.column
          ? 'series/0/bar/1'
          : 'series/0/marker/1';
      expect(
        chartTooltipFor(chart, layout, id, theme: _office)!.rows.single.color,
        gold,
        reason: kind.name,
      );
      expect(
        chartTooltipFor(
          chart,
          layout,
          id.replaceFirst('/1', '/0'),
          theme: _office,
        )!.rows.single.color,
        _office.seriesColor(0),
      );
    }
  });
}

/// The middle of the longest segment of the path through [points].
ChartPoint _longestMiddle(List<ChartPoint> points) {
  ChartPoint best = points.first;
  double longest = -1;
  for (int i = 0; i + 1 < points.length; i++) {
    final double dx = points[i + 1].x - points[i].x;
    final double dy = points[i + 1].y - points[i].y;
    final double length = dx * dx + dy * dy;
    if (length > longest) {
      longest = length;
      best = _along(points[i], points[i + 1], 0.5);
    }
  }
  return best;
}
