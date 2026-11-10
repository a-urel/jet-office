import 'dart:math' as math;

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_core/src/layout/chart_ids.dart' as ids;
import 'package:test/test.dart';

import '../support/gallery.dart';

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

  test('column_data_labels at 360 by 216 puts 18 above its bar', () {
    // The owner's gallery check: North, Q2 = 18 on an axis to 20. The bar
    // ends 14 points below the plot's top, less than the label and its gap
    // need, so the label sits above the plot's top edge, clear of the title.
    const ChartSize size = ChartSize(360, 216);
    final ChartLayout l = galleryCharts()
        .firstWhere((GalleryChart g) => g.name == 'column_data_labels')
        .layout(size);
    final ChartRect bar = byId<RectPrimitive>(l, ids.seriesBarId(0, 1)).rect;
    final TextPrimitive t = label(l, 0, 1);
    expect(t.text, '18');
    expect(t.rect.bottom, closeTo(bar.top - gap, tol));
    expect(t.rect.top, lessThan(l.plotArea!.top));
    expect(t.style, ChartTheme.office.dataLabels);
    expect(findOverlaps(l.primitives, size), isEmpty);
  });

  test(
    'a label inside a dark bar is white, inside a light one the theme\'s',
    () {
      for (final (int rgb, ChartColor expected) in <(int, ChartColor)>[
        (0x156082, ChartColor.rgb(0xFFFFFF)),
        (0xF2F2F2, theme.dataLabels.color),
      ]) {
        final ChartLayout l = layoutChart(
          Chart(
            kind: ChartKind.column,
            dataLabels: const ChartDataLabels(visible: true),
            legend: const ChartLegend(visible: false),
            valueAxis: fixed,
            series: <ChartSeries>[
              series('S0', <double?>[100, 50]),
            ],
          ),
          theme: theme.copyWith(palette: <ChartColor>[ChartColor.rgb(rgb)]),
          size: const ChartSize(400, 300),
          measurer: measurer,
        );
        final ChartRect bar = byId<RectPrimitive>(
          l,
          ids.seriesBarId(0, 0),
        ).rect;
        final TextPrimitive inside = label(l, 0, 0);
        expect(bar.contains(inside.rect), isTrue);
        expect(inside.style, theme.dataLabels.copyWith(color: expected));
        // A label outside its bar keeps the theme's colour.
        expect(label(l, 0, 1).style, theme.dataLabels);
      }
    },
  );

  test('in a dark theme a label inside a light bar takes the background, '
      'inside a dark one the theme\'s light text', () {
    // The dark theme of docs/app-themes.md (jet_charts_flutter).
    final ChartTheme dark = ChartTheme.fromColors(
      palette: <ChartColor>[ChartColor.rgb(0xFBBF24)],
      fontFamily: 'Inter',
      text: ChartColor.rgb(0xE5E7EB),
      background: ChartColor.rgb(0x111827),
    );
    for (final (int rgb, int expected) in <(int, int)>[
      (0xFBBF24, 0x111827),
      (0x1E3A8A, 0xE5E7EB),
    ]) {
      final ChartLayout l = layoutChart(
        Chart(
          kind: ChartKind.column,
          dataLabels: const ChartDataLabels(visible: true),
          legend: const ChartLegend(visible: false),
          valueAxis: fixed,
          series: <ChartSeries>[
            series('S0', <double?>[100, 50]),
          ],
        ),
        theme: dark.copyWith(palette: <ChartColor>[ChartColor.rgb(rgb)]),
        size: const ChartSize(400, 300),
        measurer: measurer,
      );
      final ChartRect bar = byId<RectPrimitive>(l, ids.seriesBarId(0, 0)).rect;
      final TextPrimitive inside = label(l, 0, 0);
      expect(bar.contains(inside.rect), isTrue);
      expect(inside.style.color.rgb, expected, reason: rgb.toRadixString(16));
      expect(label(l, 0, 1).style, dark.dataLabels);
    }
  });

  test('a label inside a bar reads against the bar\'s point colour', () {
    final ChartLayout l = layoutChart(
      Chart(
        kind: ChartKind.column,
        dataLabels: const ChartDataLabels(visible: true),
        legend: const ChartLegend(visible: false),
        valueAxis: fixed,
        series: <ChartSeries>[
          series('S0', <double?>[
            100,
            100,
          ]).copyWith(pointColors: <ChartColor?>[ChartColor.rgb(0xF2F2F2)]),
        ],
      ),
      theme: theme,
      size: const ChartSize(400, 300),
      measurer: measurer,
    );
    // Bar 0 is light by its point colour, bar 1 the dark accent 1.
    expect(label(l, 0, 0).style, theme.dataLabels);
    expect(label(l, 0, 1).style.color, ChartColor.rgb(0xFFFFFF));
  });

  test('a label never lies on another series\' bar', () {
    // Five categories of two series: bars about 25 wide, a label 48.6 wide.
    // Above its bar the label of S0 would cover S1's taller bar, and it is
    // wider than its own bar, so it is hidden.
    final ChartLayout l = lay(
      <List<double?>>[
        <double?>[50, 50, 50, 50, 50],
        <double?>[90, 90, 90, 90, 90],
      ],
      valueAxis: fixed,
      codes: <String?>['0.000000', null],
    );
    for (int c = 0; c < 5; c++) {
      expect(has(l, ids.dataLabelId(0, c)), isFalse);
      expect(
        l.hidden,
        contains(ChartHiddenLabel(ids.dataLabelId(0, c), '50.000000')),
      );
      expect(has(l, ids.dataLabelId(1, c)), isTrue);
    }
    expect(findOverlaps(l.primitives, const ChartSize(400, 300)), isEmpty);
  });

  test('a label that fits neither outside nor inside its bar is hidden', () {
    // The bar is too short for its label inside, and outside the label
    // would cover the taller bar beside it.
    final ChartLayout l = lay(
      <List<double?>>[
        <double?>[3, 3, 3, 3, 3],
        <double?>[90, 90, 90, 90, 90],
      ],
      valueAxis: fixed,
      codes: <String?>['0.000000', null],
    );
    expect(has(l, ids.dataLabelId(0, 0)), isFalse);
    expect(findOverlaps(l.primitives, const ChartSize(400, 300)), isEmpty);
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

  test('an overlapping area chart keeps its labels over other areas', () {
    // Standard grouping: S1's area lies wholly over S0's, and S0's labels
    // lie inside S1's area. Labels are painted over area fills.
    final ChartLayout l = lay(
      <List<double?>>[
        <double?>[80, 80, 80],
        <double?>[60, 60, 60],
      ],
      kind: ChartKind.area,
      valueAxis: fixed,
    );
    // Every label: those at the ends, whose points sit on the plot's edges
    // (an area's points are on tick marks), are moved inward.
    for (int s = 0; s < 2; s++) {
      for (int c = 0; c < 3; c++) {
        expect(has(l, ids.dataLabelId(s, c)), isTrue, reason: 'label/$s/$c');
      }
    }
    expect(findOverlaps(l.primitives, const ChartSize(400, 300)), isEmpty);
  });

  test('an area label at the plot\'s edge moves inward until it fits', () {
    final ChartLayout l = lay(
      <List<double?>>[
        <double?>[10, 20, 30],
      ],
      kind: ChartKind.area,
      valueAxis: fixed,
    );
    final ChartRect plot = l.plotArea!;
    final PathPrimitive a = byId<PathPrimitive>(l, ids.seriesAreaId(0));
    // Area points: tops for 0..2, then bases for 2..0.
    final TextPrimitive first = label(l, 0, 0);
    final TextPrimitive last = label(l, 0, 2);
    expect(a.points[0].x, closeTo(plot.left, tol));
    expect(a.points[2].x, closeTo(plot.right, tol));
    expect(first.rect.left, closeTo(plot.left, tol));
    expect(last.rect.right, closeTo(plot.right, tol));
    // Still halfway between the point and the base, up and down.
    expect(
      first.rect.top + first.rect.height / 2,
      closeTo((a.points[0].y + a.points[5].y) / 2, tol),
    );
    expect(
      last.rect.top + last.rect.height / 2,
      closeTo((a.points[2].y + a.points[3].y) / 2, tol),
    );
    expect(findOverlaps(l.primitives, l.size), isEmpty);
  });

  group('an area label reads on the fill under it', () {
    final ChartColor light = ChartColor.rgb(0xFFFF99);
    final ChartColor dark = ChartColor.rgb(0x000080);
    ChartLayout areas(List<ChartColor> palette, ChartGrouping grouping) {
      // Stacked, the two must fit the axis to 100 together.
      final bool standard = grouping == ChartGrouping.clustered;
      final double a = standard ? 80 : 40;
      final double b = standard ? 60 : 30;
      return layoutChart(
        Chart(
          kind: ChartKind.area,
          grouping: grouping,
          valueAxis: fixed,
          dataLabels: const ChartDataLabels(visible: true),
          legend: const ChartLegend(visible: false),
          series: <ChartSeries>[
            series('S0', <double?>[a, a, a]),
            series('S1', <double?>[b, b, b]),
          ],
        ),
        theme: theme.copyWith(palette: palette),
        size: const ChartSize(400, 300),
        measurer: measurer,
      );
    }

    final ChartColor white = ChartColor.rgb(0xFFFFFF);

    test('standard (clustered): the topmost area painted there', () {
      // S1 is painted over S0, and S0's label (at 40) lies on S1's fill.
      final ChartLayout overDark = areas(<ChartColor>[
        light,
        dark,
      ], ChartGrouping.clustered);
      expect(label(overDark, 0, 1).style.color, white);
      expect(label(overDark, 1, 1).style.color, white);
      final ChartLayout overLight = areas(<ChartColor>[
        dark,
        light,
      ], ChartGrouping.clustered);
      expect(label(overLight, 0, 1).style.color, theme.dataLabels.color);
      expect(label(overLight, 1, 1).style.color, theme.dataLabels.color);
    });

    test('stacked: its own series', () {
      final ChartLayout l = areas(<ChartColor>[
        light,
        dark,
      ], ChartGrouping.stacked);
      expect(label(l, 0, 1).style.color, theme.dataLabels.color);
      expect(label(l, 1, 1).style.color, white);
      final ChartLayout swapped = areas(<ChartColor>[
        dark,
        light,
      ], ChartGrouping.stacked);
      expect(label(swapped, 0, 1).style.color, white);
      expect(label(swapped, 1, 1).style.color, theme.dataLabels.color);
    });
  });

  test('a line of 10,000 points with data labels lays out in reasonable '
      'time', () {
    // A guard against checking every label against every mark, segment or
    // placed label, not a benchmark. On the VM it takes about 255 ms (it took
    // about 2.85 s when every label went through every marker, about 8 s when
    // also through every segment); 1.5 s keeps a margin of about 6. VM only:
    // Chrome is slower and the guard is about the algorithm, not a platform.
    final List<double?> values = <double?>[
      for (int i = 0; i < 10000; i++) 50 + 40 * math.sin(i / 50),
    ];
    final Stopwatch watch = Stopwatch()..start();
    final ChartLayout l = layoutChart(
      Chart(
        kind: ChartKind.line,
        dataLabels: const ChartDataLabels(visible: true),
        legend: const ChartLegend(visible: false),
        valueAxis: fixed,
        series: <ChartSeries>[
          ChartSeries(
            name: ChartData<String>(values: <String?>['S0']),
            categories: ChartData<Object>(
              values: <Object>[for (int i = 0; i < 10000; i++) i],
            ),
            values: ChartData<double>(values: values),
          ),
        ],
      ),
      theme: theme,
      size: const ChartSize(800, 400),
      measurer: measurer,
    );
    watch.stop();
    expect(watch.elapsed, lessThan(const Duration(milliseconds: 1500)));
    expect(
      flat(
        l.primitives,
      ).where((ChartPrimitive p) => p.id.startsWith(ids.dataLabelPrefix)),
      isNotEmpty,
    );
  }, testOn: 'vm');

  test('labels that cannot fit are hidden and listed', () {
    final ChartLayout l = lay(
      <List<double?>>[
        for (int s = 0; s < 5; s++) <double?>[50, 50, 50, 50, 50],
      ],
      kind: ChartKind.line,
      valueAxis: fixed,
    );
    // Above and below the five lines are free; beside a point lie the
    // other lines, so beside labels go, but at the ends, where no line is
    // on the outer side.
    for (int c = 0; c < 5; c++) {
      expect(has(l, ids.dataLabelId(4, c)), isFalse);
      expect(l.hidden, contains(ChartHiddenLabel(ids.dataLabelId(4, c), '50')));
      for (int s = 0; s < 2; s++) {
        expect(has(l, ids.dataLabelId(s, c)), isTrue);
      }
      expect(has(l, ids.dataLabelId(2, c)), c == 0 || c == 4);
    }
    expect(findOverlaps(l.primitives, const ChartSize(400, 300)), isEmpty);
  });

  test('a label that does not fit the chart is hidden', () {
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
        expect(
          const ChartRect(0, 0, 400, 40).contains(label(l, 0, c).rect),
          isTrue,
        );
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

  test('a small tile keeps its data labels when the legend and title free '
      'space', () {
    // At 68 by 62 a top legend and a title leave too little room for the
    // plot; they go, and the data labels, which take no room, stay.
    final ChartLayout l = layoutChart(
      Chart(
        kind: ChartKind.column,
        title: const ChartTitle(text: 'Sales'),
        dataLabels: const ChartDataLabels(visible: true),
        legend: const ChartLegend(position: ChartLegendPosition.top),
        valueAxis: fixed,
        series: <ChartSeries>[
          series('Revenue', <double?>[10, 60]),
        ],
      ),
      theme: ChartTheme.office,
      size: const ChartSize(68, 62),
      measurer: measurer,
    );
    expect(l.plotArea, isNotNull);
    expect(l.hidden, <ChartHiddenLabel>[
      ChartHiddenLabel(ids.legendTextId(0), 'Revenue'),
      const ChartHiddenLabel(ids.title, 'Sales'),
    ]);
    expect(has(l, ids.dataLabelId(0, 0)), isTrue);
    expect(has(l, ids.dataLabelId(0, 1)), isTrue);
    expect(findOverlaps(l.primitives, l.size), isEmpty);
  });

  test('every label of a sweep lies apart, and inside the plot but for a '
      'column or bar label beyond its bar\'s end', () {
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
          final bool bars = kind == ChartKind.column || kind == ChartKind.bar;
          for (final ChartPrimitive p in flat(l.primitives)) {
            if (p is TextPrimitive && p.id.startsWith('label/')) {
              expect(
                (bars ? ChartRect(0, 0, w, w * 0.7) : l.plotArea!).contains(
                  p.rect,
                ),
                isTrue,
                reason: p.id,
              );
            }
          }
        }
      }
    }
  });
}
