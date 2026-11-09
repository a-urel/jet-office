import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

const ChartSize _size = ChartSize(120, 30);
final ChartTheme _office = ChartTheme.office;
final double _w = _office.sparklineWidth;

ChartSeries _series(
  List<double?> values, {
  ChartKind? kind,
  bool smooth = false,
  List<Object?>? categories,
}) => ChartSeries(
  name: ChartData<String>(values: <String?>['Refunds']),
  categories: ChartData<Object>(values: categories ?? <Object?>[]),
  values: ChartData<double>(values: values),
  kind: kind,
  smooth: smooth,
);

Chart _chart(List<ChartSeries> series, {ChartAxis? valueAxis}) => Chart(
  kind: ChartKind.sparkline,
  series: series,
  valueAxis: valueAxis ?? const ChartAxis(),
  title: const ChartTitle(text: 'Hidden title'),
);

ChartLayout _lay(Chart chart, {ChartSize size = _size, ChartTheme? theme}) =>
    layoutChart(
      chart,
      theme: theme ?? _office,
      size: size,
      measurer: const FixedWidthTextMeasurer(),
    );

List<PathPrimitive> _paths(ChartLayout layout, String prefix) =>
    <PathPrimitive>[
      for (final ChartPrimitive p in layout.primitives)
        if (p is PathPrimitive && p.id.startsWith(prefix)) p,
    ];

void main() {
  test('[1, 3, 2] is one open path across the plot, low to high', () {
    final ChartLayout layout = _lay(
      _chart(<ChartSeries>[
        _series(<double?>[1, 3, 2]),
      ]),
    );
    final ChartRect plot = layout.plotArea!;
    expect(plot, ChartRect(_w, _w, 120 - 2 * _w, 30 - 2 * _w));
    final List<PathPrimitive> lines = _paths(layout, 'series/0/line/');
    expect(lines, hasLength(1));
    final PathPrimitive line = lines.single;
    expect(line.id, 'series/0/line/0');
    expect(line.closed, isFalse);
    expect(line.strokeWidth, _w);
    expect(line.points, hasLength(3));
    expect(line.points.first.x, closeTo(plot.left, 1e-9));
    expect(line.points.last.x, closeTo(plot.right, 1e-9));
    expect(line.points[0].y, closeTo(plot.bottom, 1e-9));
    expect(line.points[1].y, closeTo(plot.top, 1e-9));
    expect(line.points[2].y, closeTo(plot.top + plot.height / 2, 1e-9));
    expect(layout.primitives.whereType<TextPrimitive>(), isEmpty);
    expect(layout.primitives.map((ChartPrimitive p) => p.id), <String>[
      'background',
      'series/0/line/0',
    ]);
    expect(layout.valueScale, isNull);
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('the background has no border even when the theme has one', () {
    final ChartTheme bordered = _office.copyWith(
      border: ChartColor.rgb(0xFF0000),
      borderWidth: 2,
    );
    final ChartLayout layout = _lay(
      _chart(<ChartSeries>[
        _series(<double?>[1, 2]),
      ]),
      theme: bordered,
    );
    final RectPrimitive background = layout.primitives.first as RectPrimitive;
    expect(background.rect, const ChartRect(0, 0, 120, 30));
    expect(background.stroke, isNull);
  });

  test('equal values are a flat path at the vertical centre', () {
    final ChartLayout layout = _lay(
      _chart(<ChartSeries>[
        _series(<double?>[2, 2, 2]),
      ]),
    );
    final ChartRect plot = layout.plotArea!;
    for (final ChartPoint p in _paths(layout, 'series/0/line/').single.points) {
      expect(p.y, closeTo(plot.top + plot.height / 2, 1e-9));
    }
  });

  test('one value is a square dot and no line', () {
    final ChartLayout layout = _lay(
      _chart(<ChartSeries>[
        _series(<double?>[5]),
      ]),
    );
    expect(_paths(layout, 'series/0/line/'), isEmpty);
    final PathPrimitive dot = _paths(layout, 'series/0/marker/').single;
    expect(dot.id, 'series/0/marker/0');
    expect(dot.closed, isTrue);
    expect(dot.fill, isNotNull);
    final List<double> xs = <double>[for (final p in dot.points) p.x];
    final List<double> ys = <double>[for (final p in dot.points) p.y];
    expect(
      xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b),
      closeTo(2 * _w, 1e-9),
    );
    expect(
      ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b),
      closeTo(2 * _w, 1e-9),
    );
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('a lone value among gaps is a dot, a run after a gap a new line', () {
    final ChartLayout layout = _lay(
      _chart(<ChartSeries>[
        _series(<double?>[1, null, 2, 3]),
      ]),
    );
    expect(_paths(layout, 'series/0/marker/').single.id, 'series/0/marker/0');
    expect(_paths(layout, 'series/0/line/').single.id, 'series/0/line/0');
  });

  test('no finite value draws only the background', () {
    for (final List<double?> values in <List<double?>>[
      <double?>[],
      <double?>[null, double.nan],
    ]) {
      final ChartLayout layout = _lay(_chart(<ChartSeries>[_series(values)]));
      expect(layout.primitives.map((ChartPrimitive p) => p.id), <String>[
        'background',
      ]);
    }
    final ChartLayout none = _lay(_chart(const <ChartSeries>[]));
    expect(none.primitives, hasLength(1));
  });

  test('a series of kind area fills down to the plot bottom', () {
    final ChartTheme faint = _office.copyWith(areaOpacity: 0.1);
    final ChartLayout layout = _lay(
      _chart(<ChartSeries>[
        _series(<double?>[1, 3, 2], kind: ChartKind.area),
      ]),
      theme: faint,
    );
    final ChartRect plot = layout.plotArea!;
    final PathPrimitive area = _paths(layout, 'series/0/area').single;
    expect(area.closed, isTrue);
    expect(area.fillOpacity, 0.1);
    expect(area.points, hasLength(5));
    expect(area.points[3], ChartPoint(plot.right, plot.bottom));
    expect(area.points[4], ChartPoint(plot.left, plot.bottom));
    expect(layout.primitives.map((ChartPrimitive p) => p.id).toList(), <String>[
      'background',
      'series/0/area',
      'series/0/line/0',
    ]);
  });

  test('the area closes on the zero line when 0 is inside the range', () {
    final ChartLayout layout = _lay(
      _chart(<ChartSeries>[
        _series(<double?>[-1, 3], kind: ChartKind.area),
      ]),
    );
    final ChartRect plot = layout.plotArea!;
    final PathPrimitive area = _paths(layout, 'series/0/area').single;
    expect(area.points.last.y, closeTo(plot.bottom - plot.height / 4, 1e-9));
  });

  test('a series of another kind has no area', () {
    final ChartLayout layout = _lay(
      _chart(<ChartSeries>[
        _series(<double?>[1, 3, 2]),
      ]),
    );
    expect(_paths(layout, 'series/0/area'), isEmpty);
  });

  test('a fixed minimum of 0 puts [0, 0] on the bottom', () {
    final ChartLayout layout = _lay(
      _chart(<ChartSeries>[
        _series(<double?>[0, 0]),
      ], valueAxis: const ChartAxis(min: 0)),
    );
    final ChartRect plot = layout.plotArea!;
    for (final ChartPoint p in _paths(layout, 'series/0/line/').single.points) {
      expect(p.y, closeTo(plot.bottom, 1e-9));
    }
  });

  test('a fixed range sets the scale and clamps what lies outside', () {
    final ChartLayout layout = _lay(
      _chart(<ChartSeries>[
        _series(<double?>[5, 10, 20]),
      ], valueAxis: const ChartAxis(min: 0, max: 10)),
    );
    final ChartRect plot = layout.plotArea!;
    final List<ChartPoint> p = _paths(layout, 'series/0/line/').single.points;
    expect(p[0].y, closeTo(plot.bottom - plot.height / 2, 1e-9));
    expect(p[1].y, closeTo(plot.top, 1e-9));
    expect(p[2].y, closeTo(plot.top, 1e-9));
  });

  test('smooth gives more points than values, inside the plot', () {
    final ChartLayout layout = _lay(
      _chart(<ChartSeries>[
        _series(<double?>[1, 9, 1, 9, 1], smooth: true),
      ]),
    );
    final ChartRect plot = layout.plotArea!;
    final List<ChartPoint> p = _paths(layout, 'series/0/line/').single.points;
    expect(p.length, greaterThan(5));
    for (final ChartPoint q in p) {
      expect(q.y, inInclusiveRange(plot.top, plot.bottom));
    }
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('every series is a line; points spread by index, not category', () {
    final ChartLayout layout = _lay(
      _chart(<ChartSeries>[
        _series(<double?>[1, 2, 3], categories: <Object?>[10, 20, 90]),
        _series(<double?>[3, 2, 1]),
      ]),
    );
    expect(_paths(layout, 'series/0/line/'), hasLength(1));
    expect(_paths(layout, 'series/1/line/'), hasLength(1));
    final List<ChartPoint> p = _paths(layout, 'series/0/line/').single.points;
    expect(p[1].x, closeTo(60, 1e-9));
  });

  test('one band per index tiles the plot', () {
    final ChartLayout layout = _lay(
      _chart(<ChartSeries>[
        _series(<double?>[1, 3, 2]),
      ]),
    );
    final ChartRect plot = layout.plotArea!;
    expect(layout.categoryBands, hasLength(3));
    expect(layout.categoryBands.first.left, plot.left);
    expect(layout.categoryBands.last.right, closeTo(plot.right, 1e-9));
    expect(
      layout.categoryBands[0].right,
      closeTo(layout.categoryBands[1].left, 1e-9),
    );
  });

  test('a tiny size is background only, and nothing leaves the size', () {
    final ChartLayout flat = _lay(
      _chart(<ChartSeries>[
        _series(<double?>[1, 2]),
      ]),
      size: const ChartSize(1, 1),
    );
    expect(flat.primitives, hasLength(1));
    expect(flat.plotArea, isNull);
    final ChartLayout small = _lay(
      _chart(<ChartSeries>[
        _series(<double?>[1, 3, 2, 5], kind: ChartKind.area),
        _series(<double?>[4]),
      ]),
      size: const ChartSize(40, 12),
    );
    expect(findOverlaps(small.primitives, small.size), isEmpty);
  });
}
