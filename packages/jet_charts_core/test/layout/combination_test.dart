import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

const ChartSize _size = ChartSize(360, 240);
final ChartTheme _office = ChartTheme.office;
const List<String> _quarters = <String>['Q1', 'Q2', 'Q3', 'Q4'];

ChartSeries _series(String name, List<double?> values, {ChartKind? kind}) =>
    ChartSeries(
      name: ChartData<String>(values: <String?>[name]),
      categories: ChartData<Object>(values: _quarters),
      values: ChartData<double>(values: values),
      kind: kind,
    );

Chart _combo(
  List<ChartSeries> series, {
  ChartGrouping grouping = ChartGrouping.clustered,
  ChartDataLabels dataLabels = const ChartDataLabels(),
}) => Chart(
  kind: ChartKind.combination,
  grouping: grouping,
  series: series,
  dataLabels: dataLabels,
);

ChartLayout _lay(Chart chart, {ChartSize size = _size}) => layoutChart(
  chart,
  theme: _office,
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

List<String> _ids(ChartLayout layout) => <String>[
  for (final ChartPrimitive p in _flat(layout.primitives)) p.id,
];

List<T> _starting<T extends ChartPrimitive>(
  ChartLayout layout,
  String prefix,
) => <T>[
  for (final ChartPrimitive p in _flat(layout.primitives))
    if (p is T && p.id.startsWith(prefix)) p,
];

double _centreX(ChartRect r) => r.left + r.width / 2;

void main() {
  final Chart columnLine = _combo(<ChartSeries>[
    _series('Sales', <double?>[12, 18, 9, 15]),
    _series('Trend', <double?>[10, 14, 12, 16], kind: ChartKind.line),
  ]);

  test('a column and a line series draw bars, then a line with markers', () {
    final ChartLayout layout = _lay(columnLine);
    final ChartRect plot = layout.plotArea!;
    final List<String> ids = _ids(layout);
    final List<RectPrimitive> bars = _starting<RectPrimitive>(
      layout,
      'series/0/bar/',
    );
    expect(bars.map((RectPrimitive b) => b.id), <String>[
      for (int c = 0; c < 4; c++) 'series/0/bar/$c',
    ]);
    expect(ids, contains('series/1/line/0'));
    final List<ArcPrimitive> markers = _starting<ArcPrimitive>(
      layout,
      'series/1/marker/',
    );
    expect(markers, hasLength(4));
    expect(_starting<RectPrimitive>(layout, 'series/1/bar/'), isEmpty);
    // The line is painted after every bar.
    expect(
      ids.indexOf('series/1/line/0'),
      greaterThan(ids.indexOf('series/0/bar/3')),
    );
    // Each point sits at its category's centre.
    final double band = plot.width / 4;
    for (int c = 0; c < 4; c++) {
      expect(markers[c].center.x, closeTo(plot.left + (c + 0.5) * band, 1e-9));
    }
    // A column chart of the column series alone: its one bar per category is
    // centred in its band.
    for (int c = 0; c < 4; c++) {
      expect(
        _centreX(bars[c].rect),
        closeTo(plot.left + (c + 0.5) * band, 1e-9),
      );
    }
    // The category labels sit between tick marks, as a column chart's.
    expect(layout.categoryBands, hasLength(4));
    expect(layout.categoryBands.first.left, closeTo(plot.left, 1e-9));
    expect(layout.categoryBands.first.width, closeTo(band, 1e-9));
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('the bars match a column chart of the column series alone', () {
    final ChartLayout combo = _lay(
      _combo(<ChartSeries>[
        _series('A', <double?>[12, 18, 9, 15]),
        _series('Trend', <double?>[10, 14, 12, 16], kind: ChartKind.line),
        _series('B', <double?>[8, 11, 14, 10], kind: ChartKind.column),
      ]),
    );
    final ChartRect plot = combo.plotArea!;
    final List<RectPrimitive> a = _starting<RectPrimitive>(combo, 'series/0/');
    final List<RectPrimitive> b = _starting<RectPrimitive>(combo, 'series/2/');
    expect(a, hasLength(4));
    expect(b, hasLength(4));
    // Two series side by side: the same width, B right of A in each band.
    for (int c = 0; c < 4; c++) {
      expect(a[c].rect.width, closeTo(b[c].rect.width, 1e-9));
      expect(b[c].rect.left, greaterThan(a[c].rect.left));
      final double band = plot.width / 4;
      final double mid = (_centreX(a[c].rect) + _centreX(b[c].rect)) / 2;
      expect(mid, closeTo(plot.left + (c + 0.5) * band, 1e-9));
    }
  });

  test('an area series is painted before the columns', () {
    final ChartLayout layout = _lay(
      _combo(<ChartSeries>[
        _series('Sales', <double?>[12, 18, 9, 15]),
        _series('Base', <double?>[6, 8, 7, 9], kind: ChartKind.area),
        _series('Trend', <double?>[10, 14, 12, 16], kind: ChartKind.line),
      ]),
    );
    final List<String> ids = _ids(layout);
    expect(ids, contains('series/1/area'));
    expect(
      ids.indexOf('series/1/area'),
      lessThan(ids.indexOf('series/0/bar/0')),
    );
    expect(
      ids.indexOf('series/2/line/0'),
      greaterThan(ids.indexOf('series/0/bar/3')),
    );
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('an area and a line without columns sit on tick marks', () {
    final ChartLayout layout = _lay(
      _combo(<ChartSeries>[
        _series('Base', <double?>[6, 8, 7, 9], kind: ChartKind.area),
        _series('Trend', <double?>[10, 14, 12, 16], kind: ChartKind.line),
      ]),
    );
    final ChartRect plot = layout.plotArea!;
    final List<ArcPrimitive> markers = _starting<ArcPrimitive>(
      layout,
      'series/1/marker/',
    );
    expect(markers.first.center.x, closeTo(plot.left, 1e-9));
    expect(markers.last.center.x, closeTo(plot.right, 1e-9));
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('a series of another kind, or none, is drawn as columns', () {
    final ChartLayout layout = _lay(
      _combo(<ChartSeries>[
        _series('Pie', <double?>[12, 18, 9, 15], kind: ChartKind.pie),
        _series('None', <double?>[8, 11, 14, 10]),
      ]),
    );
    expect(_starting<RectPrimitive>(layout, 'series/0/bar/'), hasLength(4));
    expect(_starting<RectPrimitive>(layout, 'series/1/bar/'), hasLength(4));
    expect(_starting<ChartPrimitive>(layout, 'series/0/slice/'), isEmpty);
  });

  test('stacked grouping stacks the column series but not the line', () {
    final ChartLayout layout = _lay(
      _combo(<ChartSeries>[
        _series('A', <double?>[12, 18, 9, 15]),
        _series('B', <double?>[8, 11, 14, 10]),
        _series('Trend', <double?>[10, 14, 12, 16], kind: ChartKind.line),
      ], grouping: ChartGrouping.stacked),
    );
    final ValueScale scale = layout.valueScale!;
    // The extent: the stacked columns reach 29; the line alone is 16.
    expect(scale.max, greaterThanOrEqualTo(29));
    final List<RectPrimitive> a = _starting<RectPrimitive>(layout, 'series/0/');
    final List<RectPrimitive> b = _starting<RectPrimitive>(layout, 'series/1/');
    for (int c = 0; c < 4; c++) {
      // B sits on A.
      expect(b[c].rect.bottom, closeTo(a[c].rect.top, 1e-9));
      expect(b[c].rect.left, closeTo(a[c].rect.left, 1e-9));
    }
    final ChartRect plot = layout.plotArea!;
    final List<ArcPrimitive> markers = _starting<ArcPrimitive>(
      layout,
      'series/2/marker/',
    );
    double y(double v) =>
        plot.bottom - (v - scale.min) / (scale.max - scale.min) * plot.height;
    // The line is not added onto the columns.
    expect(markers[0].center.y, closeTo(y(10), 1e-9));
    expect(markers[3].center.y, closeTo(y(16), 1e-9));
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('the legend draws a line series as a line, columns as squares', () {
    final ChartLayout layout = _lay(columnLine);
    final List<String> ids = _ids(layout);
    expect(ids, contains('legend/1/marker'));
    expect(ids, isNot(contains('legend/0/marker')));
  });

  test('data labels follow each series\' kind', () {
    final ChartLayout layout = _lay(
      _combo(<ChartSeries>[
        _series('Sales', <double?>[12, 18, 9, 15]),
        _series('Trend', <double?>[3, 4, 3, 5], kind: ChartKind.line),
      ], dataLabels: const ChartDataLabels(visible: true)),
      size: const ChartSize(480, 320),
    );
    final List<TextPrimitive> labels = _starting<TextPrimitive>(
      layout,
      'label/',
    );
    expect(labels, isNotEmpty);
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
    final RectPrimitive bar = _starting<RectPrimitive>(
      layout,
      'series/0/bar/1',
    ).single;
    final TextPrimitive barLabel = labels.firstWhere(
      (TextPrimitive t) => t.id == 'label/0/1',
    );
    // Outside the column's end, above it.
    expect(barLabel.rect.bottom, lessThanOrEqualTo(bar.rect.top));
  });

  test('small sizes lay out without an overlap', () {
    for (final ChartSize size in <ChartSize>[
      const ChartSize(200, 120),
      const ChartSize(120, 80),
      const ChartSize(40, 30),
    ]) {
      final ChartLayout layout = _lay(columnLine, size: size);
      expect(findOverlaps(layout.primitives, layout.size), isEmpty);
    }
  });
  test('point colours fill a column and mark a line point', () {
    final ChartColor gold = ChartColor.rgb(0xFBBF24);
    final ChartColor navy = ChartColor.rgb(0x1E3A8A);
    final ChartLayout layout = _lay(
      _combo(<ChartSeries>[
        _series('Sales', <double?>[
          12,
          18,
          9,
          15,
        ]).copyWith(pointColors: <ChartColor?>[null, gold]),
        _series(
          'Trend',
          <double?>[10, 14, 12, 16],
          kind: ChartKind.line,
        ).copyWith(pointColors: <ChartColor?>[null, null, navy]),
      ]),
    );
    final Map<String, ChartPrimitive> byId = <String, ChartPrimitive>{
      for (final ChartPrimitive p in _flat(layout.primitives)) p.id: p,
    };
    expect(
      (byId['series/0/bar/0']! as RectPrimitive).fill,
      _office.seriesColor(0),
    );
    expect((byId['series/0/bar/1']! as RectPrimitive).fill, gold);
    expect(
      (byId['series/1/marker/0']! as ArcPrimitive).fill,
      _office.seriesColor(1),
    );
    expect((byId['series/1/marker/2']! as ArcPrimitive).fill, navy);
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });
}
