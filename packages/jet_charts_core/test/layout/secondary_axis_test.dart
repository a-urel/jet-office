import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_core/src/scale/value_scale.dart'
    show dataExtent, excelMaxIntervals;
import 'package:jet_core/jet_core.dart';
import 'package:test/test.dart';

const ChartSize _size = ChartSize(360, 216);
// Markers on a combination's lines, as the tests of mark positions need
// them; the Office theme's combination lines have none.
final ChartTheme _office = ChartTheme.office.copyWith(
  combinationLineMarkers: true,
);
const List<String> _quarters = <String>['Q1', 'Q2', 'Q3', 'Q4'];

ChartSeries _series(
  String name,
  List<double?> values, {
  ChartKind? kind,
  ChartAxisBinding axis = ChartAxisBinding.primary,
}) => ChartSeries(
  name: ChartData<String>(values: <String?>[name]),
  categories: ChartData<Object>(values: _quarters),
  values: ChartData<double>(values: values),
  kind: kind,
  axis: axis,
);

const List<double> _column = <double>[12, 18, 9, 15];
const List<double> _line = <double>[1200, 950, 1400, 800];

Chart _chart({
  ChartKind kind = ChartKind.combination,
  bool columnSecondary = false,
  List<double?> line = _line,
  ChartAxis? secondaryValueAxis,
}) => Chart(
  kind: kind,
  series: <ChartSeries>[
    _series(
      'Sales',
      _column,
      axis: columnSecondary
          ? ChartAxisBinding.secondary
          : ChartAxisBinding.primary,
    ),
    _series(
      'Revenue',
      line,
      kind: ChartKind.line,
      axis: ChartAxisBinding.secondary,
    ),
  ],
  secondaryValueAxis: secondaryValueAxis,
);

ChartLayout _lay(
  Chart chart, {
  ChartSize size = _size,
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

List<T> _starting<T extends ChartPrimitive>(
  ChartLayout layout,
  String prefix,
) => <T>[
  for (final ChartPrimitive p in _flat(layout.primitives))
    if (p is T && p.id.startsWith(prefix)) p,
];

void main() {
  test('the secondary series is measured on its own scale, on the right', () {
    final ChartLayout layout = _lay(_chart());
    final ChartRect plot = layout.plotArea!;
    final ({double min, double max}) extent = dataExtent(<List<double?>>[
      _line,
    ], ChartGrouping.clustered);
    final ValueScale expected = autoValueScale(
      dataMin: extent.min,
      dataMax: extent.max,
      maxIntervals: excelMaxIntervals(
        plot.height,
        horizontal: false,
        fontSize: _office.axisLabels.size,
      ),
    );
    expect(layout.secondaryValueScale, expected);
    // The primary scale follows the column alone.
    expect(layout.valueScale!.max, lessThan(100));
    final List<TextPrimitive> secondary = _starting<TextPrimitive>(
      layout,
      'axis/secondary/label/',
    );
    expect(secondary, hasLength(expected.ticks.length));
    for (final TextPrimitive t in secondary) {
      expect(t.rect.left, greaterThan(plot.right));
      expect(t.rect.right, lessThanOrEqualTo(_size.width));
    }
    for (final TextPrimitive t in _starting<TextPrimitive>(
      layout,
      'axis/value/label/',
    )) {
      expect(t.rect.right, lessThan(plot.left));
    }
    // The line's highest point, 1400, at its fraction of the secondary scale.
    final ArcPrimitive top = _starting<ArcPrimitive>(
      layout,
      'series/1/marker/2',
    ).single;
    final double t = (1400 - expected.min) / (expected.max - expected.min);
    expect(top.center.y, closeTo(plot.bottom - t * plot.height, 1e-9));
    // No grid lines unless asked for; the axis line as the theme says.
    expect(_starting<ChartPrimitive>(layout, 'grid/secondary/'), isEmpty);
    expect(
      _starting<ChartPrimitive>(layout, 'axis/secondary/line'),
      _office.valueAxisLine ? hasLength(1) : isEmpty,
    );
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('gridlines, a title and an axis line when asked for', () {
    final ChartLayout layout = _lay(
      _chart(
        secondaryValueAxis: const ChartAxis(
          gridLines: true,
          title: 'Revenue (TL)',
        ),
      ),
      size: const ChartSize(480, 320),
    );
    final ValueScale scale = layout.secondaryValueScale!;
    expect(
      _starting<PathPrimitive>(layout, 'grid/secondary/'),
      hasLength(scale.ticks.length),
    );
    final TextPrimitive title = _starting<TextPrimitive>(
      layout,
      'axis/secondary/title',
    ).single;
    expect(title.rect.left, greaterThan(layout.plotArea!.right));
    expect(title.rotationDegrees, -90);
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
    final ChartLayout lined = layoutChart(
      _chart(),
      theme: _office.copyWith(valueAxisLine: true),
      size: _size,
      measurer: const FixedWidthTextMeasurer(),
    );
    final PathPrimitive line = _starting<PathPrimitive>(
      lined,
      'axis/secondary/line',
    ).single;
    expect(line.points.first.x, closeTo(lined.plotArea!.right, 1e-9));
  });

  test('with every series secondary there is no secondary axis', () {
    final ChartLayout layout = _lay(_chart(columnSecondary: true));
    expect(_starting<ChartPrimitive>(layout, 'axis/secondary/'), isEmpty);
    expect(layout.secondaryValueScale, isNull);
    expect(layout.valueScale!.max, greaterThanOrEqualTo(1400));
  });

  test('a secondary axis with no finite value is not drawn', () {
    final ChartLayout layout = _lay(
      _chart(line: const <double?>[null, null, null, null]),
    );
    expect(_starting<ChartPrimitive>(layout, 'axis/secondary/'), isEmpty);
    expect(layout.secondaryValueScale, isNull);
  });

  test('a bar chart measures every series on the primary axis', () {
    final ChartLayout layout = _lay(_chart(kind: ChartKind.bar));
    expect(_starting<ChartPrimitive>(layout, 'axis/secondary/'), isEmpty);
    expect(layout.secondaryValueScale, isNull);
    expect(layout.valueScale!.max, greaterThanOrEqualTo(1400));
  });

  test('a line chart with a secondary series has a secondary axis', () {
    final ChartLayout layout = _lay(_chart(kind: ChartKind.line));
    expect(layout.secondaryValueScale, isNotNull);
    expect(
      _starting<TextPrimitive>(layout, 'axis/secondary/label/'),
      isNotEmpty,
    );
  });

  test('primary and secondary columns each take the full slot', () {
    final Chart chart = Chart(
      kind: ChartKind.column,
      series: <ChartSeries>[
        _series('A', _column),
        _series('B', _line, axis: ChartAxisBinding.secondary),
      ],
    );
    final ChartLayout layout = _lay(chart);
    final List<RectPrimitive> a = _starting<RectPrimitive>(layout, 'series/0/');
    final List<RectPrimitive> b = _starting<RectPrimitive>(layout, 'series/1/');
    for (int c = 0; c < 4; c++) {
      expect(b[c].rect.left, closeTo(a[c].rect.left, 1e-9));
      expect(b[c].rect.width, closeTo(a[c].rect.width, 1e-9));
    }
    final List<String> ids = <String>[
      for (final ChartPrimitive p in _flat(layout.primitives)) p.id,
    ];
    expect(
      ids.indexOf('series/1/bar/0'),
      greaterThan(ids.indexOf('series/0/bar/3')),
    );
  });

  test('a secondary marker\'s tooltip takes the secondary axis\' code', () {
    final Chart chart = _chart(
      secondaryValueAxis: const ChartAxis(formatCode: '#,##0 "₺"'),
    );
    final ChartLayout layout = _lay(chart, locale: FormatLocale.trTR);
    final ChartTooltip tip = chartTooltipFor(
      chart,
      layout,
      'series/1/marker/0',
      theme: _office,
      locale: FormatLocale.trTR,
    )!;
    expect(tip.rows.single.value, '1.200 ₺');
    expect(
      _starting<TextPrimitive>(
        layout,
        'axis/secondary/label/',
      ).map((TextPrimitive t) => t.text),
      everyElement(endsWith('₺')),
    );
  });

  group('a percent stacked combination', () {
    test('a secondary axis of lines alone is not a percent axis', () {
      final Chart chart = Chart(
        kind: ChartKind.combination,
        grouping: ChartGrouping.percentStacked,
        series: <ChartSeries>[
          _series('A', _column),
          _series('B', const <double>[8, 11, 14, 10]),
          _series(
            'Revenue',
            _line,
            kind: ChartKind.line,
            axis: ChartAxisBinding.secondary,
          ),
        ],
      );
      final ChartLayout layout = _lay(chart);
      final ChartRect plot = layout.plotArea!;
      // The columns' axis is a percent one; the line's is not.
      expect(layout.valueScale!.max, 1);
      expect(
        _starting<TextPrimitive>(layout, 'axis/value/label/').last.text,
        '100%',
      );
      final ValueScale secondary = layout.secondaryValueScale!;
      expect(secondary.max, greaterThanOrEqualTo(1400));
      expect(
        _starting<TextPrimitive>(
          layout,
          'axis/secondary/label/',
        ).map((TextPrimitive t) => t.text),
        everyElement(isNot(endsWith('%'))),
      );
      for (final ArcPrimitive m in _starting<ArcPrimitive>(
        layout,
        'series/2/marker/',
      )) {
        expect(m.center.y, inInclusiveRange(plot.top, plot.bottom));
      }
      expect(findOverlaps(layout.primitives, layout.size), isEmpty);
    });

    test('a primary axis of lines alone is not a percent axis', () {
      final Chart chart = Chart(
        kind: ChartKind.combination,
        grouping: ChartGrouping.percentStacked,
        series: <ChartSeries>[
          _series('Revenue', _line, kind: ChartKind.line),
          _series('A', _column, axis: ChartAxisBinding.secondary),
          _series('B', const <double>[
            8,
            11,
            14,
            10,
          ], axis: ChartAxisBinding.secondary),
        ],
      );
      final ChartLayout layout = _lay(chart);
      final ChartRect plot = layout.plotArea!;
      expect(layout.valueScale!.max, greaterThanOrEqualTo(1400));
      expect(
        _starting<TextPrimitive>(
          layout,
          'axis/value/label/',
        ).map((TextPrimitive t) => t.text),
        everyElement(isNot(endsWith('%'))),
      );
      expect(layout.secondaryValueScale!.max, 1);
      expect(
        _starting<TextPrimitive>(layout, 'axis/secondary/label/').last.text,
        '100%',
      );
      for (final ArcPrimitive m in _starting<ArcPrimitive>(
        layout,
        'series/0/marker/',
      )) {
        expect(m.center.y, inInclusiveRange(plot.top, plot.bottom));
      }
      expect(findOverlaps(layout.primitives, layout.size), isEmpty);
    });
  });

  test('every id parses', () {
    final ChartLayout layout = _lay(
      _chart(secondaryValueAxis: const ChartAxis(gridLines: true, title: 'T')),
      size: const ChartSize(480, 320),
    );
    for (final ChartPrimitive p in _flat(layout.primitives)) {
      expect(ChartElementId.parse(p.id), isNotNull, reason: p.id);
    }
    expect(
      ChartElementId.parse('axis/secondary/label/0')!.axis,
      ChartAxisRole.secondaryValue,
    );
  });

  test('no overlap at 360 by 216 and 200 by 120', () {
    for (final ChartSize size in <ChartSize>[
      const ChartSize(360, 216),
      const ChartSize(200, 120),
      const ChartSize(120, 70),
    ]) {
      for (final Chart chart in <Chart>[
        _chart(),
        _chart(
          secondaryValueAxis: const ChartAxis(
            title: 'Revenue',
            gridLines: true,
          ),
        ),
      ]) {
        final ChartLayout layout = _lay(chart, size: size);
        expect(findOverlaps(layout.primitives, layout.size), isEmpty);
        for (final ChartPrimitive p in layout.primitives) {
          if (p is TextPrimitive) {
            expect(p.bounds.left, greaterThanOrEqualTo(-1e-9));
            expect(p.bounds.right, lessThanOrEqualTo(size.width + 1e-9));
          }
        }
      }
    }
  });
}
