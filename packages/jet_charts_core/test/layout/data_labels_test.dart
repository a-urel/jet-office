import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_core/src/layout/chart_ids.dart' as ids;
import 'package:test/test.dart';

const FixedWidthTextMeasurer measurer = FixedWidthTextMeasurer();

final ChartTheme theme = ChartTheme.office.copyWith(
  gapWidthPercent: 100,
  spacing: ChartTheme.office.spacing.copyWith(overlapPercent: 0),
);

const List<Object?> cats = <Object?>['A', 'B', 'C', 'D', 'E'];
final double gap = theme.spacing.labelGap;

ChartSeries series(String name, List<double?> values, {String? formatCode}) {
  return ChartSeries(
    name: ChartData<String>(values: <String?>[name]),
    categories: ChartData<Object>(values: cats.sublist(0, values.length)),
    values: ChartData<double>(values: values),
    formatCode: formatCode,
  );
}

ChartLayout lay(
  List<List<double?>> data, {
  ChartKind kind = ChartKind.column,
  ChartGrouping grouping = ChartGrouping.clustered,
  ChartAxis valueAxis = const ChartAxis(),
  ChartDataLabels labels = const ChartDataLabels(visible: true),
  List<String?>? codes,
  ChartSize size = const ChartSize(400, 300),
}) {
  return layoutChart(
    Chart(
      kind: kind,
      grouping: grouping,
      valueAxis: valueAxis,
      dataLabels: labels,
      legend: const ChartLegend(visible: false),
      series: <ChartSeries>[
        for (int s = 0; s < data.length; s++)
          series('S$s', data[s], formatCode: codes?[s]),
      ],
    ),
    theme: theme,
    size: size,
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

TextPrimitive label(ChartLayout l, int s, int c) =>
    byId<TextPrimitive>(l, ids.dataLabelId(s, c));

const double tol = 1e-9;

void main() {
  const ChartAxis fixed = ChartAxis(min: 0, max: 100);

  test('a column label sits above its bar', () {
    final ChartLayout l = lay(<List<double?>>[
      <double?>[10, 20, 30, 40, 50],
    ], valueAxis: fixed);
    final ChartRect bar = byId<RectPrimitive>(l, ids.seriesBarId(0, 2)).rect;
    final TextPrimitive t = label(l, 0, 2);
    expect(t.text, '30');
    expect(t.rect.bottom, closeTo(bar.top - gap, tol));
    expect(
      t.rect.left + t.rect.width / 2,
      closeTo(bar.left + bar.width / 2, tol),
    );
    expect(t.style, theme.dataLabels);
  });

  test('data labels are drawn after the axis labels and outside the clip', () {
    final ChartLayout l = lay(<List<double?>>[
      <double?>[10, 20],
    ], valueAxis: fixed);
    final List<String> order = <String>[
      for (final ChartPrimitive p in l.primitives) p.id,
    ];
    expect(
      order.indexOf(ids.dataLabelId(0, 0)),
      greaterThan(order.indexOf(ids.axisLabelId(ids.categoryAxis, 1))),
    );
    expect(
      byId<ClipPrimitive>(
        l,
        ids.plotClip,
      ).children.any((ChartPrimitive p) => p.id.startsWith('label/')),
      isFalse,
    );
  });

  test('a label too tall for outside goes inside', () {
    final ChartLayout l = lay(<List<double?>>[
      <double?>[100, 50],
    ], valueAxis: fixed);
    final ChartRect bar = byId<RectPrimitive>(l, ids.seriesBarId(0, 0)).rect;
    final TextPrimitive t = label(l, 0, 0);
    expect(t.rect.top, closeTo(bar.top + gap, tol));
    expect(t.rect.bottom, lessThan(bar.bottom));
    // The other label still fits outside.
    final ChartRect bar1 = byId<RectPrimitive>(l, ids.seriesBarId(0, 1)).rect;
    expect(label(l, 0, 1).rect.bottom, closeTo(bar1.top - gap, tol));
  });

  test('a negative column label sits below its bar', () {
    final ChartLayout l = lay(<List<double?>>[
      <double?>[-20, 20],
    ], valueAxis: const ChartAxis(min: -100, max: 100));
    final ChartRect bar = byId<RectPrimitive>(l, ids.seriesBarId(0, 0)).rect;
    expect(label(l, 0, 0).rect.top, closeTo(bar.bottom + gap, tol));
  });

  test('a bar chart label sits right of its bar', () {
    final ChartLayout l = lay(
      <List<double?>>[
        <double?>[10, 20, 30],
      ],
      kind: ChartKind.bar,
      valueAxis: fixed,
    );
    final ChartRect bar = byId<RectPrimitive>(l, ids.seriesBarId(0, 1)).rect;
    final TextPrimitive t = label(l, 0, 1);
    expect(t.rect.left, closeTo(bar.right + gap, tol));
    expect(
      t.rect.top + t.rect.height / 2,
      closeTo(bar.top + bar.height / 2, tol),
    );
  });

  test('a stacked label is centred', () {
    final ChartLayout l = lay(
      <List<double?>>[
        <double?>[10, 20],
        <double?>[30, 40],
      ],
      grouping: ChartGrouping.stacked,
      valueAxis: fixed,
    );
    for (int s = 0; s < 2; s++) {
      final ChartRect bar = byId<RectPrimitive>(l, ids.seriesBarId(s, 1)).rect;
      final TextPrimitive t = label(l, s, 1);
      expect(
        t.rect.left + t.rect.width / 2,
        closeTo(bar.left + bar.width / 2, tol),
      );
      expect(
        t.rect.top + t.rect.height / 2,
        closeTo(bar.top + bar.height / 2, tol),
      );
    }
  });

  test('a line label sits above its point', () {
    final ChartLayout l = lay(
      <List<double?>>[
        <double?>[10, 20, 30, 40, 50],
      ],
      kind: ChartKind.line,
      valueAxis: fixed,
    );
    final PathPrimitive line = byId<PathPrimitive>(l, ids.seriesLineId(0, 0));
    final ChartPoint p = line.points[2];
    final TextPrimitive t = label(l, 0, 2);
    expect(t.rect.bottom, lessThan(p.y));
    expect(t.rect.left + t.rect.width / 2, closeTo(p.x, tol));
  });

  test('crowded line labels move below', () {
    final ChartLayout l = lay(
      <List<double?>>[
        <double?>[50, 50, 50],
        <double?>[51, 51, 51],
      ],
      kind: ChartKind.line,
      valueAxis: fixed,
    );
    final ChartPoint p0 = byId<PathPrimitive>(
      l,
      ids.seriesLineId(0, 0),
    ).points[1];
    final ChartPoint p1 = byId<PathPrimitive>(
      l,
      ids.seriesLineId(1, 0),
    ).points[1];
    expect(label(l, 0, 1).rect.bottom, lessThan(p0.y));
    expect(label(l, 1, 1).rect.top, greaterThan(p1.y));
    expect(findOverlaps(l.primitives, const ChartSize(400, 300)), isEmpty);
  });

  test('an area label sits halfway between the point and its base', () {
    final ChartLayout l = lay(
      <List<double?>>[
        <double?>[10, 20, 30],
        <double?>[10, 20, 30],
      ],
      kind: ChartKind.area,
      grouping: ChartGrouping.stacked,
      valueAxis: fixed,
    );
    final PathPrimitive a0 = byId<PathPrimitive>(l, ids.seriesAreaId(0));
    final PathPrimitive a1 = byId<PathPrimitive>(l, ids.seriesAreaId(1));
    // Area points: tops for 0..2, then bases for 2..0.
    final ChartPoint top1 = a1.points[1];
    final ChartPoint base1 = a1.points[4];
    final TextPrimitive t = label(l, 1, 1);
    expect(
      t.rect.top + t.rect.height / 2,
      closeTo((top1.y + base1.y) / 2, tol),
    );
    expect(t.rect.left + t.rect.width / 2, closeTo(top1.x, tol));
    final ChartPoint top0 = a0.points[1];
    final ChartPoint base0 = a0.points[4];
    expect(
      label(l, 0, 1).rect.top + label(l, 0, 1).rect.height / 2,
      closeTo((top0.y + base0.y) / 2, tol),
    );
  });

  test('labels that cannot fit are hidden and listed', () {
    final ChartLayout l = lay(
      <List<double?>>[
        for (int s = 0; s < 5; s++) <double?>[50, 50, 50, 50, 50],
      ],
      kind: ChartKind.line,
      valueAxis: fixed,
    );
    for (int c = 0; c < 5; c++) {
      expect(has(l, ids.dataLabelId(4, c)), isFalse);
      expect(l.hidden, contains(ChartHiddenLabel(ids.dataLabelId(4, c), '50')));
      for (int s = 0; s < 4; s++) {
        expect(has(l, ids.dataLabelId(s, c)), isTrue);
      }
    }
    expect(findOverlaps(l.primitives, const ChartSize(400, 300)), isEmpty);
  });

  test('a label outside the plot is hidden', () {
    final ChartLayout l = lay(
      <List<double?>>[
        <double?>[10, 20, 30],
      ],
      valueAxis: fixed,
      size: const ChartSize(400, 40),
    );
    for (int c = 0; c < 3; c++) {
      final bool drawn = has(l, ids.dataLabelId(0, c));
      expect(
        drawn ||
            l.hidden.any((ChartHiddenLabel h) => h.id == ids.dataLabelId(0, c)),
        isTrue,
      );
      if (drawn) {
        expect(l.plotArea!.contains(label(l, 0, c).rect), isTrue);
      }
    }
  });

  test('a null value has no label', () {
    final ChartLayout l = lay(<List<double?>>[
      <double?>[10, null, 30],
    ], valueAxis: fixed);
    expect(has(l, ids.dataLabelId(0, 1)), isFalse);
    expect(
      l.hidden.any((ChartHiddenLabel h) => h.id == ids.dataLabelId(0, 1)),
      isFalse,
    );
  });

  test('a data label format code wins over the series\'', () {
    final List<List<double?>> data = <List<double?>>[
      <double?>[10, 20],
    ];
    ChartLayout l = lay(
      data,
      valueAxis: fixed,
      labels: const ChartDataLabels(visible: true, formatCode: '0.0'),
      codes: <String?>['0.00'],
    );
    expect(label(l, 0, 0).text, '10.0');
    l = lay(data, valueAxis: fixed, codes: <String?>['0.00']);
    expect(label(l, 0, 0).text, '10.00');
    l = lay(data, valueAxis: fixed);
    expect(label(l, 0, 0).text, '10');
  });

  test(
    'hidden data labels are not drawn when the chart has no data labels',
    () {
      final ChartLayout l = lay(
        <List<double?>>[
          <double?>[10, 20],
        ],
        valueAxis: fixed,
        labels: const ChartDataLabels(),
      );
      expect(has(l, ids.dataLabelId(0, 0)), isFalse);
      expect(l.hidden, isEmpty);
    },
  );

  test('data labels are dropped first when the frame has no room', () {
    final ChartLayout l = lay(
      <List<double?>>[
        <double?>[10, 20],
      ],
      valueAxis: fixed,
      size: const ChartSize(10, 10),
    );
    expect(l.plotArea, isNull);
    expect(has(l, ids.dataLabelId(0, 0)), isFalse);
    expect(l.hidden.first, ChartHiddenLabel(ids.dataLabelId(0, 0), '10'));
    expect(l.hidden[1], ChartHiddenLabel(ids.dataLabelId(0, 1), '20'));
  });

  test('every label of a sweep lies inside the plot and apart', () {
    for (final ChartKind kind in <ChartKind>[
      ChartKind.column,
      ChartKind.bar,
      ChartKind.line,
      ChartKind.area,
    ]) {
      for (final ChartGrouping g in ChartGrouping.values) {
        for (double w = 120; w <= 600; w += 120) {
          final ChartLayout l = lay(
            <List<double?>>[
              <double?>[10, 55, -20, 80, 33],
              <double?>[12, 50, 25, 70, 33],
              <double?>[11, 52, 5, 71, 34],
            ],
            kind: kind,
            grouping: g,
            size: ChartSize(w, w * 0.7),
          );
          expect(
            findOverlaps(l.primitives, ChartSize(w, w * 0.7)),
            isEmpty,
            reason: '$kind $g $w',
          );
          for (final ChartPrimitive p in flat(l.primitives)) {
            if (p is TextPrimitive && p.id.startsWith('label/')) {
              expect(l.plotArea!.contains(p.rect), isTrue, reason: p.id);
            }
          }
        }
      }
    }
  });
}
