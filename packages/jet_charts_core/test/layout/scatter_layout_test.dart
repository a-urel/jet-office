import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_core/src/layout/scatter_layout.dart'
    show excelSerialOf;
import 'package:jet_charts_core/src/scale/value_scale.dart'
    show excelMaxIntervals;
import 'package:test/test.dart';

const ChartSize _size = ChartSize(360, 240);
final ChartTheme _office = ChartTheme.office;

ChartSeries _series(
  String name,
  List<Object?> x,
  List<double?> y, {
  List<ChartColor?> pointColors = const <ChartColor?>[],
}) => ChartSeries(
  name: ChartData<String>(values: <String?>[name]),
  categories: ChartData<Object>(values: x),
  values: ChartData<double>(values: y),
  pointColors: pointColors,
);

Chart _scatter(
  List<ChartSeries> series, {
  ChartAxis categoryAxis = const ChartAxis(),
  ChartAxis valueAxis = const ChartAxis(gridLines: true),
  ChartDataLabels dataLabels = const ChartDataLabels(),
}) => Chart(
  kind: ChartKind.scatter,
  series: series,
  categoryAxis: categoryAxis,
  valueAxis: valueAxis,
  dataLabels: dataLabels,
);

ChartLayout _lay(Chart chart, {ChartSize size = _size, ChartTheme? theme}) =>
    layoutChart(
      chart,
      theme: theme ?? _office,
      size: size,
      measurer: const FixedWidthTextMeasurer(),
    );

Iterable<ChartPrimitive> _flat(List<ChartPrimitive> list) sync* {
  for (final ChartPrimitive p in list) {
    yield p;
    if (p is ClipPrimitive) {
      yield* _flat(p.children);
    }
  }
}

List<T> _starting<T extends ChartPrimitive>(
  ChartLayout layout,
  String prefix,
) => <T>[
  for (final ChartPrimitive p in _flat(layout.primitives))
    if (p is T && p.id.startsWith(prefix)) p,
];

ChartPoint _centre(ChartRect r) =>
    ChartPoint(r.left + r.width / 2, r.top + r.height / 2);

/// The value at the x of [x] on the horizontal axis whose tick labels are
/// [labels] (their centres are the ticks, each label's text its value).
double _xValue(List<TextPrimitive> labels, double x) {
  final double a = _centre(labels.first.rect).x;
  final double b = _centre(labels.last.rect).x;
  final double va = double.parse(labels.first.text);
  final double vb = double.parse(labels.last.text);
  return va + (x - a) / (b - a) * (vb - va);
}

void main() {
  final Chart basic = _scatter(<ChartSeries>[
    _series('Points', <Object?>[1, 2, 4], <double?>[10, 20, 15]),
  ]);

  PathPrimitive? line(ChartLayout layout, String axis) {
    for (final ChartPrimitive p in _flat(layout.primitives)) {
      if (p is PathPrimitive && p.id == 'axis/$axis/line') {
        return p;
      }
    }
    return null;
  }

  test('the Office theme draws both scatter axis lines in BFBFBF', () {
    final ChartLayout layout = _lay(
      _scatter(<ChartSeries>[
        _series('Points', <Object?>[1, 2, 4], <double?>[10, 20, 15]),
      ], categoryAxis: const ChartAxis(gridLines: true)),
    );
    final ChartColor expected = _office.scatterAxisLine!;
    expect(expected.rgb, 0xBFBFBF);
    expect(line(layout, 'value')!.stroke, expected);
    expect(line(layout, 'category')!.stroke, expected);
    expect(line(layout, 'value')!.strokeWidth, 0.75);
    expect(line(layout, 'category')!.strokeWidth, 0.75);
    // Excel's default scatter: grid lines on both axes (E1, chart 4).
    expect(_starting<PathPrimitive>(layout, 'grid/category/'), isNotEmpty);
    expect(_starting<PathPrimitive>(layout, 'grid/value/'), isNotEmpty);
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('without scatterAxisLine a scatter draws its axes as before', () {
    final ChartTheme plain = ChartTheme.fromColors(
      palette: <ChartColor>[ChartColor.rgb(0x2563EB)],
      fontFamily: 'Test',
      text: ChartColor.rgb(0x333333),
      background: ChartColor.rgb(0xFFFFFF),
    );
    final ChartLayout layout = _lay(basic, theme: plain);
    expect(line(layout, 'value'), isNull);
    expect(line(layout, 'category')!.stroke, plain.axisLine);
  });

  test('a column chart keeps the Office theme without a value axis line', () {
    final ChartLayout layout = layoutChart(
      Chart(
        kind: ChartKind.column,
        series: <ChartSeries>[
          _series('Points', <Object?>['a', 'b'], <double?>[1, 2]),
        ],
      ),
      theme: _office,
      size: _size,
      measurer: const FixedWidthTextMeasurer(),
    );
    expect(line(layout, 'value'), isNull);
    expect(line(layout, 'category')!.stroke, _office.axisLine);
  });

  test('three points draw three markers on two value axes', () {
    final ChartLayout layout = _lay(basic);
    final ChartRect plot = layout.plotArea!;
    final List<ArcPrimitive> markers = _starting<ArcPrimitive>(
      layout,
      'series/0/marker/',
    );
    expect(markers.map((ArcPrimitive m) => m.id), <String>[
      'series/0/marker/0',
      'series/0/marker/1',
      'series/0/marker/2',
    ]);
    // The horizontal scale: autoValueScale of 1..4 at the plot's width.
    final ValueScale x = autoValueScale(
      dataMin: 1,
      dataMax: 4,
      maxIntervals: excelMaxIntervals(
        plot.width,
        horizontal: true,
        fontSize: _office.axisLabels.size,
      ),
    );
    final List<TextPrimitive> xLabels = _starting<TextPrimitive>(
      layout,
      'axis/category/label/',
    );
    expect(xLabels.map((TextPrimitive t) => t.text), <String>[
      for (final double t in x.ticks) t.toStringAsFixed(t % 1 == 0 ? 0 : 1),
    ]);
    expect(_centre(xLabels.first.rect).x, closeTo(plot.left, 1e-9));
    expect(_centre(xLabels.last.rect).x, closeTo(plot.right, 1e-9));
    // The vertical scale: autoValueScale of 10..20 at the plot's height.
    final ValueScale y = autoValueScale(
      dataMin: 10,
      dataMax: 20,
      maxIntervals: excelMaxIntervals(
        plot.height,
        horizontal: false,
        fontSize: _office.axisLabels.size,
      ),
    );
    expect(layout.valueScale, y);
    const List<(double, double)> points = <(double, double)>[
      (1, 10),
      (2, 20),
      (4, 15),
    ];
    for (int i = 0; i < 3; i++) {
      final ArcPrimitive m = markers[i];
      expect(
        m.center.x,
        closeTo(
          plot.left + (points[i].$1 - x.min) / (x.max - x.min) * plot.width,
          1e-9,
        ),
      );
      expect(_xValue(xLabels, m.center.x), closeTo(points[i].$1, 1e-9));
      expect(
        m.center.y,
        closeTo(
          plot.bottom - (points[i].$2 - y.min) / (y.max - y.min) * plot.height,
          1e-9,
        ),
      );
      expect(m.radius, _office.markerSize / 2);
      expect(m.fill, _office.seriesColor(0));
    }
    expect(layout.categoryBands, isEmpty);
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('horizontal grid lines only with the Office defaults', () {
    final ChartLayout layout = _lay(basic);
    expect(_starting<PathPrimitive>(layout, 'grid/value/'), isNotEmpty);
    expect(_starting<PathPrimitive>(layout, 'grid/category/'), isEmpty);
    for (final PathPrimitive g in _starting<PathPrimitive>(
      layout,
      'grid/value/',
    )) {
      expect(g.points.first.y, g.points.last.y);
    }
  });

  test('a category axis with grid lines adds vertical ones at its ticks', () {
    final ChartLayout layout = _lay(
      _scatter(basic.series, categoryAxis: const ChartAxis(gridLines: true)),
    );
    final List<PathPrimitive> grid = _starting<PathPrimitive>(
      layout,
      'grid/category/',
    );
    final List<TextPrimitive> labels = _starting<TextPrimitive>(
      layout,
      'axis/category/label/',
    );
    expect(grid, hasLength(labels.length));
    for (int i = 0; i < grid.length; i++) {
      expect(grid[i].id, 'grid/category/$i');
      expect(grid[i].points.first.x, grid[i].points.last.x);
      expect(grid[i].points.first.x, closeTo(_centre(labels[i].rect).x, 1e-9));
    }
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('text x values number the points 1, 2, 3', () {
    final ChartLayout text = _lay(
      _scatter(<ChartSeries>[
        _series('Points', <Object?>['a', 'b', 'c'], <double?>[10, 20, 15]),
      ]),
    );
    final ChartLayout numbered = _lay(
      _scatter(<ChartSeries>[
        _series('Points', <Object?>[1, 2, 3], <double?>[10, 20, 15]),
      ]),
    );
    expect(
      _starting<ArcPrimitive>(text, 'series/'),
      _starting<ArcPrimitive>(numbered, 'series/'),
    );
  });

  test('a DateTime x is its Excel serial', () {
    final ChartLayout dated = _lay(
      _scatter(<ChartSeries>[
        _series(
          'Points',
          <Object?>[DateTime(2026, 1, 1), DateTime(2026, 1, 3)],
          <double?>[10, 20],
        ),
      ], categoryAxis: const ChartAxis(formatCode: 'd mmm')),
    );
    final ChartLayout serial = _lay(
      _scatter(<ChartSeries>[
        _series('Points', <Object?>[46023, 46025], <double?>[10, 20]),
      ], categoryAxis: const ChartAxis(formatCode: 'd mmm')),
    );
    expect(
      _starting<ArcPrimitive>(dated, 'series/'),
      _starting<ArcPrimitive>(serial, 'series/'),
    );
    expect(
      _starting<TextPrimitive>(
        dated,
        'axis/category/label/',
      ).map((TextPrimitive t) => t.text),
      contains('1 Jan'),
    );
  });

  test("a date's serial keeps the time of day and Excel's phantom day", () {
    expect(excelSerialOf(DateTime(2026, 1, 1)), 46023);
    expect(excelSerialOf(DateTime(2026, 1, 1, 12)), 46023.5);
    expect(excelSerialOf(DateTime(1900, 2, 28)), 59);
    expect(excelSerialOf(DateTime(1900, 3, 1)), 61);
  });

  test('the legend shows each series as its marker alone', () {
    final ChartLayout layout = _lay(
      _scatter(<ChartSeries>[
        ...basic.series,
        _series('More', <Object?>[3], <double?>[12]),
      ]),
    );
    for (int s = 0; s < 2; s++) {
      expect(_starting<ChartPrimitive>(layout, 'legend/$s/symbol'), isEmpty);
      final ArcPrimitive marker = _starting<ArcPrimitive>(
        layout,
        'legend/$s/marker',
      ).single;
      expect(marker.radius, _office.markerSize / 2);
      expect(marker.fill, _office.seriesColor(s));
      expect(marker.stroke, _office.seriesColor(s));
      final TextPrimitive text = _starting<TextPrimitive>(
        layout,
        'legend/$s/text',
      ).single;
      expect(marker.center.x + marker.radius, lessThan(text.rect.left));
      expect(marker.center.y, closeTo(_centre(text.rect).y, 1e-9));
    }
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('a null y draws no marker', () {
    final ChartLayout layout = _lay(
      _scatter(<ChartSeries>[
        _series('Points', <Object?>[1, 2, 4], <double?>[10, null, 15]),
      ]),
    );
    expect(
      _starting<ArcPrimitive>(
        layout,
        'series/0/marker/',
      ).map((ArcPrimitive m) => m.id),
      <String>['series/0/marker/0', 'series/0/marker/2'],
    );
  });

  test('a series of only NaN draws nothing and does not throw', () {
    final ChartLayout layout = _lay(
      _scatter(<ChartSeries>[
        _series(
          'Nothing',
          <Object?>[double.nan, 2],
          <double?>[double.nan, double.nan],
        ),
      ]),
    );
    expect(_starting<ArcPrimitive>(layout, 'series/'), isEmpty);
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('a point colour paints its marker', () {
    final ChartColor red = ChartColor.rgb(0xFF0000);
    final ChartLayout layout = _lay(
      _scatter(<ChartSeries>[
        _series(
          'Points',
          <Object?>[1, 2, 4],
          <double?>[10, 20, 15],
          pointColors: <ChartColor?>[null, red],
        ),
      ]),
    );
    final List<ArcPrimitive> markers = _starting<ArcPrimitive>(
      layout,
      'series/0/marker/',
    );
    expect(markers.map((ArcPrimitive m) => m.fill), <ChartColor>[
      _office.seriesColor(0),
      red,
      _office.seriesColor(0),
    ]);
  });

  test('data labels show the y value beside its marker', () {
    final ChartLayout layout = _lay(
      _scatter(basic.series, dataLabels: const ChartDataLabels(visible: true)),
    );
    final List<TextPrimitive> labels = _starting<TextPrimitive>(
      layout,
      'label/',
    );
    expect(labels.map((TextPrimitive t) => t.text), <String>['10', '20', '15']);
    final ArcPrimitive marker = _starting<ArcPrimitive>(
      layout,
      'series/0/marker/1',
    ).single;
    final TextPrimitive label = labels[1];
    expect(_centre(label.rect).x, closeTo(marker.center.x, 1e-9));
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('a small scatter lays out without overlap', () {
    for (final ChartSize size in const <ChartSize>[
      ChartSize(160, 100),
      ChartSize(60, 40),
      ChartSize(20, 10),
    ]) {
      final ChartLayout layout = _lay(basic, size: size);
      expect(findOverlaps(layout.primitives, layout.size), isEmpty);
    }
  });

  test('a marker takes a point colour key from the theme', () {
    final ChartColor paid = ChartColor.rgb(0x16A34A);
    final ChartLayout layout = layoutChart(
      _scatter(<ChartSeries>[
        _series(
          'P',
          <Object?>[1, 2],
          <double?>[3, 4],
        ).copyWith(pointColorKeys: <String?>['paid']),
      ]),
      theme: _office.copyWith(semantic: <String, ChartColor>{'paid': paid}),
      size: _size,
      measurer: const FixedWidthTextMeasurer(),
    );
    ChartColor? fill(int i) => _flat(layout.primitives)
        .whereType<ArcPrimitive>()
        .firstWhere((ArcPrimitive a) => a.id == 'series/0/marker/$i')
        .fill;
    expect(fill(0), paid);
    expect(fill(1), _office.seriesColor(0));
  });
}
