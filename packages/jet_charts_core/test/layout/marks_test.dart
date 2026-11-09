import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_core/src/layout/chart_ids.dart' as ids;
import 'package:test/test.dart';

import '../support/gallery.dart';

const FixedWidthTextMeasurer measurer = FixedWidthTextMeasurer();

final ChartTheme theme = ChartTheme.office.copyWith(
  gapWidthPercent: 100,
  stackedGapWidthPercent: 100,
  barGapWidthPercent: 100,
  spacing: ChartTheme.office.spacing.copyWith(overlapPercent: 0),
);

const List<Object?> cats = <Object?>['A', 'B', 'C', 'D', 'E'];

ChartSeries series(String name, List<double?> values) {
  return ChartSeries(
    name: ChartData<String>(values: <String?>[name]),
    categories: ChartData<Object>(values: cats.sublist(0, values.length)),
    values: ChartData<double>(values: values),
  );
}

ChartLayout lay(
  List<List<double?>> data, {
  ChartKind kind = ChartKind.column,
  ChartGrouping grouping = ChartGrouping.clustered,
  ChartAxis valueAxis = const ChartAxis(),
  ChartTheme? withTheme,
}) {
  return layoutChart(
    Chart(
      kind: kind,
      grouping: grouping,
      valueAxis: valueAxis,
      legend: const ChartLegend(visible: false),
      series: <ChartSeries>[
        for (int s = 0; s < data.length; s++) series('S$s', data[s]),
      ],
    ),
    theme: withTheme ?? theme,
    size: const ChartSize(400, 300),
    measurer: measurer,
  );
}

Iterable<ChartPrimitive> flat(List<ChartPrimitive> list) sync* {
  for (final ChartPrimitive p in list) {
    yield p;
    if (p is ClipPrimitive) {
      yield* flat(p.children);
    }
  }
}

T byId<T extends ChartPrimitive>(ChartLayout l, String id) =>
    flat(l.primitives).firstWhere((ChartPrimitive p) => p.id == id) as T;

bool has(ChartLayout l, String id) =>
    flat(l.primitives).any((ChartPrimitive p) => p.id == id);

ChartRect bar(ChartLayout l, int s, int c) =>
    byId<RectPrimitive>(l, ids.seriesBarId(s, c)).rect;

/// The y of [v], vertical axis, from the layout's own plot and scale.
double yOf(ChartLayout l, double v) {
  final ChartRect p = l.plotArea!;
  final ValueScale s = l.valueScale!;
  return p.bottom - (v - s.min) / (s.max - s.min) * p.height;
}

double xOf(ChartLayout l, double v) {
  final ChartRect p = l.plotArea!;
  final ValueScale s = l.valueScale!;
  return p.left + (v - s.min) / (s.max - s.min) * p.width;
}

Matcher near(double v) => closeTo(v, 1e-9);

void main() {
  test('two clustered series in a band', () {
    final ChartLayout l = lay(<List<double?>>[
      <double?>[1, 2, 3, 4],
      <double?>[2, 3, 4, 5],
    ]);
    final ChartRect p = l.plotArea!;
    final double band = p.width / 4;
    // w = band / (g + n - (n - 1) * o) = band / 3.
    final double w = band / 3;
    for (int c = 0; c < 4; c++) {
      final ChartRect a = bar(l, 0, c);
      final ChartRect b = bar(l, 1, c);
      expect(a.width, near(w));
      expect(b.width, near(w));
      expect(a.left, near(p.left + c * band + w / 2));
      expect(b.left, near(p.left + c * band + w / 2 + w));
      expect(a.bottom, near(yOf(l, 0)));
      expect(a.top, near(yOf(l, 1.0 + c)));
      expect(b.top, near(yOf(l, 2.0 + c)));
    }
    expect(
      byId<RectPrimitive>(l, ids.seriesBarId(0, 0)).fill,
      theme.colorOf(series('S0', <double?>[1]), 0),
    );
  });

  test('clustered bars overlap by the theme\'s percentage', () {
    final ChartLayout l = layoutChart(
      Chart(
        kind: ChartKind.column,
        legend: const ChartLegend(visible: false),
        series: <ChartSeries>[
          series('S0', <double?>[1, 2, 3, 4]),
          series('S1', <double?>[2, 3, 4, 5]),
          series('S2', <double?>[3, 4, 5, 6]),
        ],
      ),
      theme: theme.copyWith(
        gapWidthPercent: 150,
        spacing: theme.spacing.copyWith(overlapPercent: 50),
      ),
      size: const ChartSize(400, 300),
      measurer: measurer,
    );
    final ChartRect p = l.plotArea!;
    final double band = p.width / 4;
    // w = band / (g + n - (n - 1) * o) = band / (1.5 + 3 - 2 * 0.5).
    final double w = band / 3.5;
    for (int c = 0; c < 4; c++) {
      for (int s = 0; s < 3; s++) {
        final ChartRect r = bar(l, s, c);
        expect(r.width, near(w));
        // Series s starts s * w * (1 - o) after the half gap.
        expect(r.left, near(p.left + c * band + 1.5 * w / 2 + s * w * 0.5));
      }
    }
  });

  test('each kind and grouping takes its own gap and overlap', () {
    // Office: clustered column 219 and -27, clustered bar 182 and 0, stacked
    // 150 and 100 (chart_reference.xlsx).
    for (final (ChartKind kind, ChartGrouping grouping, double g, double o)
        in <(ChartKind, ChartGrouping, double, double)>[
          (ChartKind.column, ChartGrouping.clustered, 2.19, -0.27),
          (ChartKind.bar, ChartGrouping.clustered, 1.82, 0),
          (ChartKind.column, ChartGrouping.stacked, 1.5, 1),
          (ChartKind.bar, ChartGrouping.percentStacked, 1.5, 1),
        ]) {
      final ChartLayout l = layoutChart(
        Chart(
          kind: kind,
          grouping: grouping,
          legend: const ChartLegend(visible: false),
          series: <ChartSeries>[
            series('S0', <double?>[1, 2, 3]),
            series('S1', <double?>[2, 3, 4]),
          ],
        ),
        theme: ChartTheme.office,
        size: const ChartSize(400, 300),
        measurer: measurer,
      );
      final ChartRect p = l.plotArea!;
      final double length = kind == ChartKind.bar ? p.height : p.width;
      final double w = length / 3 / (g + 2 - o);
      final ChartRect r = bar(l, 0, 0);
      expect(
        kind == ChartKind.bar ? r.height : r.width,
        near(w),
        reason: '$kind $grouping',
      );
    }
  });

  test('gap and overlap are kept to Excel\'s ranges', () {
    for (final (double gap, double overlap) in <(double, double)>[
      (-50, 0),
      (100, 150),
      (-50, 150),
      (900, -300),
    ]) {
      final ChartLayout l = layoutChart(
        Chart(
          kind: ChartKind.column,
          legend: const ChartLegend(visible: false),
          series: <ChartSeries>[
            series('S0', <double?>[1, 2, 3]),
            series('S1', <double?>[2, 3, 4]),
          ],
        ),
        theme: theme.copyWith(
          gapWidthPercent: gap,
          spacing: theme.spacing.copyWith(overlapPercent: overlap),
        ),
        size: const ChartSize(400, 300),
        measurer: measurer,
      );
      final ChartRect p = l.plotArea!;
      final double band = p.width / 3;
      // Gap 0..500 and overlap -100..100, as Excel allows.
      final double g = gap.clamp(0, 500) / 100;
      final double o = overlap.clamp(-100, 100) / 100;
      final double w = band / (g + 2 - o);
      for (int s = 0; s < 2; s++) {
        for (int c = 0; c < 3; c++) {
          final ChartRect r = bar(l, s, c);
          expect(
            r.width.isFinite && r.width > 0,
            isTrue,
            reason: '$gap $overlap',
          );
          expect(r.width, near(w), reason: '$gap $overlap');
          expect(
            r.left,
            near(p.left + c * band + g * w / 2 + s * w * (1 - o)),
            reason: '$gap $overlap',
          );
        }
      }
    }
  });

  test('stacked bars build up and down apart', () {
    final ChartLayout l = lay(<List<double?>>[
      <double?>[3, -1],
      <double?>[-2, 4],
    ], grouping: ChartGrouping.stacked);
    final ChartRect p = l.plotArea!;
    final double band = p.width / 2;
    final double w = band / 2; // g = 1, one bar per category.
    final ChartRect a0 = bar(l, 0, 0);
    expect(a0.left, near(p.left + w / 2));
    expect(a0.width, near(w));
    expect(a0.top, near(yOf(l, 3)));
    expect(a0.bottom, near(yOf(l, 0)));
    final ChartRect b0 = bar(l, 1, 0);
    expect(b0.left, near(a0.left));
    expect(b0.top, near(yOf(l, 0)));
    expect(b0.bottom, near(yOf(l, -2)));
    final ChartRect a1 = bar(l, 0, 1);
    expect(a1.top, near(yOf(l, 0)));
    expect(a1.bottom, near(yOf(l, -1)));
    final ChartRect b1 = bar(l, 1, 1);
    expect(b1.top, near(yOf(l, 4)));
    expect(b1.bottom, near(yOf(l, 0)));
  });

  test('percent stacked fills to the top', () {
    final ChartLayout l = lay(<List<double?>>[
      <double?>[1, 2],
      <double?>[3, 2],
      <double?>[0, 0],
    ], grouping: ChartGrouping.percentStacked);
    expect(l.valueScale!.max, 1);
    expect(bar(l, 0, 0).top, near(yOf(l, 0.25)));
    expect(bar(l, 0, 0).bottom, near(yOf(l, 0)));
    expect(bar(l, 1, 0).top, near(yOf(l, 1)));
    expect(bar(l, 1, 0).bottom, near(yOf(l, 0.25)));
    expect(bar(l, 1, 1).top, near(yOf(l, 1)));
    expect(bar(l, 1, 1).bottom, near(yOf(l, 0.5)));
  });

  test('a percent stacked category that sums to zero draws nothing', () {
    final ChartLayout l = lay(<List<double?>>[
      <double?>[0, 2],
      <double?>[0, 2],
    ], grouping: ChartGrouping.percentStacked);
    expect(has(l, ids.seriesBarId(0, 0)), isFalse);
    expect(has(l, ids.seriesBarId(1, 0)), isFalse);
    expect(has(l, ids.seriesBarId(0, 1)), isTrue);
  });

  test(
    'a bar chart runs left to right with the first category at the bottom',
    () {
      final ChartLayout l = lay(<List<double?>>[
        <double?>[1, 2, 3, 4],
        <double?>[2, 3, 4, 5],
      ], kind: ChartKind.bar);
      final ChartRect p = l.plotArea!;
      final double band = p.height / 4;
      final double w = band / 3;
      for (int c = 0; c < 4; c++) {
        final ChartRect a = bar(l, 0, c);
        final ChartRect b = bar(l, 1, c);
        final double bandBottom = p.bottom - c * band;
        expect(a.height, near(w));
        expect(b.height, near(w));
        expect(a.bottom, near(bandBottom - w / 2));
        expect(b.bottom, near(bandBottom - w / 2 - w));
        expect(a.left, near(xOf(l, 0)));
        expect(a.right, near(xOf(l, 1.0 + c)));
        expect(b.right, near(xOf(l, 2.0 + c)));
      }
    },
  );

  test('a null value draws no bar', () {
    final ChartLayout l = lay(<List<double?>>[
      <double?>[1, null, 3, 4],
    ]);
    expect(has(l, ids.seriesBarId(0, 0)), isTrue);
    expect(has(l, ids.seriesBarId(0, 1)), isFalse);
    expect(has(l, ids.seriesBarId(0, 2)), isTrue);
  });

  test('a line breaks at null', () {
    final ChartLayout l = lay(
      <List<double?>>[
        <double?>[1, 2, null, 4, 5],
      ],
      kind: ChartKind.line,
      withTheme: theme.copyWith(lineMarkers: false),
    );
    final ChartRect p = l.plotArea!;
    final double band = p.width / 5;
    final PathPrimitive r0 = byId<PathPrimitive>(l, ids.seriesLineId(0, 0));
    final PathPrimitive r1 = byId<PathPrimitive>(l, ids.seriesLineId(0, 1));
    expect(r0.points, hasLength(2));
    expect(r1.points, hasLength(2));
    expect(r0.closed, isFalse);
    expect(r0.fill, isNull);
    expect(r0.strokeWidth, theme.lineWidth);
    expect(r0.points[0].x, near(p.left + band / 2));
    expect(r0.points[0].y, near(yOf(l, 1)));
    expect(r0.points[1].x, near(p.left + band * 1.5));
    expect(r1.points[0].x, near(p.left + band * 3.5));
    expect(r1.points[0].y, near(yOf(l, 4)));
    expect(r1.points[1].x, near(p.left + band * 4.5));
    expect(has(l, ids.seriesLineId(0, 2)), isFalse);
    expect(
      flat(l.primitives).where((ChartPrimitive q) => q.id.contains('marker')),
      isEmpty,
    );
  });

  test('every point of a line gets a circle marker after its runs', () {
    final GalleryChart g = galleryCharts().firstWhere(
      (GalleryChart g) => g.name == 'line_gap',
    );
    final ChartLayout l = g.layout(goldenSize);
    final ChartTheme office = ChartTheme.office;
    final List<ChartPrimitive> marks = flat(
      l.primitives,
    ).where((ChartPrimitive q) => q.id.startsWith('series/')).toList();
    int count = 0;
    final ChartRect plot = l.plotArea!;
    final double band = plot.width / 6;
    for (int s = 0; s < g.chart.series.length; s++) {
      final List<double?> values = g.chart.series[s].values.values;
      final ChartColor color = office.seriesColor(s);
      int lastRun = -1;
      for (int i = 0; i < marks.length; i++) {
        if (marks[i].id.startsWith('series/$s/line/')) {
          lastRun = i;
        }
      }
      for (int c = 0; c < values.length; c++) {
        final String id = ids.seriesMarkerId(s, c);
        if (values[c] == null) {
          expect(has(l, id), isFalse, reason: id);
          continue;
        }
        final int at = marks.indexWhere((ChartPrimitive q) => q.id == id);
        expect(at, greaterThan(lastRun), reason: '$id after the runs');
        final ArcPrimitive m = marks[at] as ArcPrimitive;
        expect(m.radius, office.markerSize / 2);
        expect(m.innerRadius, 0);
        expect(m.startAngle, 0);
        expect(m.sweepAngle, 360);
        expect(m.fill, color);
        expect(m.stroke, color);
        expect(m.strokeWidth, 0.75);
        expect(m.center.x, near(plot.left + band * (c + 0.5)));
        expect(m.center.y, near(yOf(l, values[c]!)));
        count++;
      }
    }
    expect(count, 10);
    // Markers sit in their own clip, after the plot's clip, in series then
    // category order.
    final List<ClipPrimitive> clips = l.primitives
        .whereType<ClipPrimitive>()
        .toList();
    expect(clips.map((ClipPrimitive c) => c.id), <String>[
      ids.plotClip,
      ids.markerClip,
    ]);
    expect(clips[0].children.whereType<ArcPrimitive>(), isEmpty);
    final List<String> markers = <String>[
      for (final ChartPrimitive m in clips[1].children) m.id,
    ];
    expect(markers, hasLength(10));
    expect(markers, <String>[
      for (int s = 0; s < g.chart.series.length; s++)
        for (int c = 0; c < g.chart.series[s].values.values.length; c++)
          if (g.chart.series[s].values.values[c] != null)
            ids.seriesMarkerId(s, c),
    ]);
  });

  test('a marker on the plot\'s edge is drawn whole', () {
    // A 0 on an axis from 0: the marker's centre is on the plot's bottom.
    final ChartLayout l = lay(
      <List<double?>>[
        <double?>[0, 50, 100],
      ],
      kind: ChartKind.line,
      valueAxis: const ChartAxis(min: 0, max: 100),
    );
    final ChartRect plot = l.plotArea!;
    final ArcPrimitive low = byId<ArcPrimitive>(l, ids.seriesMarkerId(0, 0));
    final ArcPrimitive high = byId<ArcPrimitive>(l, ids.seriesMarkerId(0, 2));
    expect(low.center.y, near(plot.bottom));
    expect(high.center.y, near(plot.top));
    final ClipPrimitive clip = byId<ClipPrimitive>(l, ids.markerClip);
    final double reach = theme.markerSize / 2 + 0.75 / 2;
    expect(
      clip.rect,
      ChartRect(
        plot.left - reach,
        plot.top - reach,
        plot.width + 2 * reach,
        plot.height + 2 * reach,
      ),
    );
    for (final ArcPrimitive m in <ArcPrimitive>[low, high]) {
      expect(m.center.y + reach, lessThanOrEqualTo(clip.rect.bottom + 1e-9));
      expect(m.center.y - reach, greaterThanOrEqualTo(clip.rect.top - 1e-9));
    }
    // The line itself stays in the plot's clip.
    expect(
      byId<ClipPrimitive>(
        l,
        ids.plotClip,
      ).children.map((ChartPrimitive c) => c.id),
      <String>[ids.seriesLineId(0, 0)],
    );
    expect(findOverlaps(l.primitives, l.size), isEmpty);
  });

  test('the marker clip stays inside the chart', () {
    final ChartLayout l = layoutChart(
      Chart(
        kind: ChartKind.line,
        valueAxis: const ChartAxis(min: 0, max: 100),
        legend: const ChartLegend(visible: false),
        series: <ChartSeries>[
          series('S0', <double?>[0, 100]),
        ],
      ),
      theme: theme.copyWith(
        spacing: theme.spacing.copyWith(padding: 1),
        markerSize: 20,
      ),
      size: const ChartSize(400, 300),
      measurer: measurer,
    );
    final ChartRect clip = byId<ClipPrimitive>(l, ids.markerClip).rect;
    // The plot grown by the reach (10 + 0.375) would leave the chart.
    expect(l.plotArea!.right + 10.375, greaterThan(400));
    expect(clip.right, 400);
    expect(clip.left, greaterThanOrEqualTo(0));
    expect(clip.top, greaterThanOrEqualTo(0));
    expect(clip.right, lessThanOrEqualTo(400));
    expect(clip.bottom, lessThanOrEqualTo(300));
  });

  test('without line markers only a lone point gets a marker', () {
    final ChartLayout l = lay(
      <List<double?>>[
        <double?>[1, null, 3, 4],
      ],
      kind: ChartKind.line,
      withTheme: theme.copyWith(lineMarkers: false),
    );
    final ChartRect p = l.plotArea!;
    final double band = p.width / 4;
    final ArcPrimitive m = byId<ArcPrimitive>(l, ids.seriesMarkerId(0, 0));
    expect(m.center.x, near(p.left + band / 2));
    expect(m.center.y, near(yOf(l, 1)));
    expect(m.radius, theme.markerSize / 2);
    expect(m.sweepAngle, 360);
    expect(m.fill, theme.seriesColor(0));
    expect(m.stroke, theme.seriesColor(0));
    expect(m.strokeWidth, 0.75);
    expect(has(l, ids.seriesMarkerId(0, 2)), isFalse);
    expect(has(l, ids.seriesMarkerId(0, 3)), isFalse);
    expect(has(l, ids.seriesLineId(0, 0)), isTrue);
  });

  group('markers only where they fit', () {
    // The plot of 400 by 300 with no legend is about 380 wide: a step of
    // markerSize + 2 (7 pt) fits about 54 categories.
    ChartLayout dense(int count, List<double?> Function(int c) value) {
      return layoutChart(
        Chart(
          kind: ChartKind.line,
          legend: const ChartLegend(visible: false),
          series: <ChartSeries>[
            ChartSeries(
              name: ChartData<String>(values: <String?>['S']),
              categories: ChartData<Object>(
                values: <Object?>[for (int c = 0; c < count; c++) 'C$c'],
              ),
              values: ChartData<double>(
                values: <double?>[for (int c = 0; c < count; c++) ...value(c)],
              ),
            ),
          ],
        ),
        theme: ChartTheme.office,
        size: const ChartSize(400, 300),
        measurer: measurer,
      );
    }

    int markers(ChartLayout l) => flat(
      l.primitives,
    ).where((ChartPrimitive p) => p.id.contains('/marker/')).length;

    double step(ChartLayout l, int count) => l.plotArea!.width / count;

    test('a line whose step fits a marker and a gap marks every point', () {
      final ChartLayout l = dense(20, (int c) => <double?>[c.toDouble()]);
      expect(step(l, 20), greaterThanOrEqualTo(7));
      expect(markers(l), 20);
    });

    test('a line whose step is under markerSize + 2 has no markers', () {
      final ChartLayout l = dense(80, (int c) => <double?>[c.toDouble()]);
      expect(step(l, 80), lessThan(ChartTheme.office.markerSize + 2));
      expect(markers(l), 0);
      expect(has(l, ids.markerClip), isFalse);
      expect(has(l, ids.seriesLineId(0, 0)), isTrue);
    });

    test('a dense line keeps the markers of its lone points', () {
      // Every third value stands alone between two gaps.
      final ChartLayout l = dense(
        90,
        (int c) => <double?>[c % 6 == 0 || c % 6 == 3 ? 1 : null],
      );
      expect(markers(l), 30);
      expect(has(l, ids.seriesMarkerId(0, 3)), isTrue);
    });

    test('a 10,000-point line has no markers', () {
      final ChartLayout l = dense(10000, (int c) => <double?>[c % 7.0]);
      expect(markers(l), 0);
    });
  });

  test('a lone point gets a marker and no line', () {
    final ChartLayout l = lay(<List<double?>>[
      <double?>[1, null, 3, null],
    ], kind: ChartKind.line);
    expect(byId<ArcPrimitive>(l, ids.seriesMarkerId(0, 0)).sweepAngle, 360);
    expect(has(l, ids.seriesMarkerId(0, 2)), isTrue);
    expect(has(l, ids.seriesLineId(0, 0)), isFalse);
  });

  test('an area treats null as zero', () {
    final ChartLayout l = lay(<List<double?>>[
      <double?>[2, null, 4],
    ], kind: ChartKind.area);
    final ChartRect p = l.plotArea!;
    final PathPrimitive a = byId<PathPrimitive>(l, ids.seriesAreaId(0));
    expect(a.closed, isTrue);
    expect(a.points, hasLength(6));
    // On tick marks: the first value at the plot's left, the last at its
    // right.
    final List<double> xs = <double>[p.left, p.left + p.width / 2, p.right];
    final List<double> ys = <double>[yOf(l, 2), yOf(l, 0), yOf(l, 4)];
    for (int i = 0; i < 3; i++) {
      expect(a.points[i].x, near(xs[i]));
      expect(a.points[i].y, near(ys[i]));
      expect(a.points[5 - i].x, near(xs[i]));
      expect(a.points[5 - i].y, near(yOf(l, 0)));
    }
  });

  test('a stacked area runs down to the series below', () {
    final ChartLayout l = lay(
      <List<double?>>[
        <double?>[1, 2],
        <double?>[3, 4],
      ],
      kind: ChartKind.area,
      grouping: ChartGrouping.stacked,
    );
    final PathPrimitive b = byId<PathPrimitive>(l, ids.seriesAreaId(1));
    expect(b.points[0].y, near(yOf(l, 4)));
    expect(b.points[1].y, near(yOf(l, 6)));
    expect(b.points[2].y, near(yOf(l, 2)));
    expect(b.points[3].y, near(yOf(l, 1)));
  });

  test('marks are clipped to the plot', () {
    final ChartLayout l = lay(<List<double?>>[
      <double?>[1, 2, 3, 4],
    ]);
    final ClipPrimitive clip = byId<ClipPrimitive>(l, ids.plotClip);
    expect(clip.rect, l.plotArea);
    expect(clip.children.map((ChartPrimitive c) => c.id), <String>[
      for (int c = 0; c < 4; c++) ids.seriesBarId(0, c),
    ]);
    final List<String> order = <String>[
      for (final ChartPrimitive p in l.primitives) p.id,
    ];
    expect(
      order.indexOf(ids.plotClip),
      greaterThan(order.indexOf(ids.gridId(ids.valueAxis, 0))),
    );
    expect(
      order.indexOf(ids.plotClip),
      lessThan(order.indexOf(ids.axisLineId(ids.categoryAxis))),
    );
  });

  test('a value beyond a fixed axis maximum is drawn to a finite extent', () {
    final ChartLayout l = lay(<List<double?>>[
      <double?>[1, 2, 3, 100],
    ], valueAxis: const ChartAxis(min: 0, max: 5));
    final ChartRect r = bar(l, 0, 3);
    final ChartRect p = l.plotArea!;
    expect(r.top, near(p.top - p.height));
    expect(r.bottom, near(yOf(l, 0)));
  });

  for (final ChartKind kind in <ChartKind>[
    ChartKind.column,
    ChartKind.bar,
    ChartKind.line,
    ChartKind.area,
  ]) {
    for (final ChartGrouping g in ChartGrouping.values) {
      test('all coordinates are finite for 1e300 and -1e300: $kind $g', () {
        final ChartLayout l = lay(
          <List<double?>>[
            <double?>[1e300, -1e300, 5, null],
            <double?>[-1e300, 1e300, 1e300, 1e300],
          ],
          kind: kind,
          grouping: g,
        );
        for (final ChartPrimitive p in flat(l.primitives)) {
          final List<double> numbers = switch (p) {
            RectPrimitive() => <double>[
              p.rect.left,
              p.rect.top,
              p.rect.width,
              p.rect.height,
            ],
            PathPrimitive() => <double>[
              for (final ChartPoint q in p.points) ...<double>[q.x, q.y],
            ],
            _ => const <double>[],
          };
          for (final double n in numbers) {
            expect(n.isFinite, isTrue, reason: '${p.id}: $n');
          }
        }
      });
    }
  }
}
