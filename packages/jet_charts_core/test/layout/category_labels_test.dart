import 'dart:math' as math;

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_core/src/layout/axis_layout.dart' show isWrappingOf;
import 'package:jet_charts_core/src/layout/chart_ids.dart' as ids;
import 'package:test/test.dart';

import '../support/gallery.dart';

const FixedWidthTextMeasurer measurer = FixedWidthTextMeasurer();

/// The axis labels' height under the fixed measurer: 9 pt times 1.2.
const double labelHeight = 10.8;

/// The Office theme's gaps.
const double labelGap = 4;
const double minTextGap = 2;

/// [count] labels of exactly [length] characters, each distinct.
List<String> labelsOf(int count, int length) => <String>[
  for (int i = 0; i < count; i++)
    'L${i.toString().padLeft(3, '0')}'.padRight(length, 'x'),
];

ChartLayout lay(
  List<String> categories,
  ChartSize size, {
  ChartKind kind = ChartKind.column,
  String? title,
  ChartLegend legend = const ChartLegend(visible: false),
  ChartAxis valueAxis = const ChartAxis(),
}) {
  return layoutChart(
    Chart(
      kind: kind,
      title: title == null ? null : ChartTitle(text: title),
      legend: legend,
      valueAxis: valueAxis,
      series: <ChartSeries>[
        ChartSeries(
          name: ChartData<String>(values: <String?>['Sales']),
          categories: ChartData<Object>(values: categories),
          values: ChartData<double>(
            values: <double?>[
              for (int c = 0; c < categories.length; c++) 3 + c % 7 * 2.5,
            ],
          ),
        ),
      ],
    ),
    theme: ChartTheme.office,
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

/// The category labels drawn, by their index.
Map<int, TextPrimitive> categoryLabels(ChartLayout layout) {
  const String prefix = 'axis/category/label/';
  return <int, TextPrimitive>{
    for (final TextPrimitive t
        in flat(layout.primitives).whereType<TextPrimitive>().where(
          (TextPrimitive t) => t.id.startsWith(prefix),
        ))
      int.parse(t.id.substring(prefix.length)): t,
  };
}

bool drawn(ChartLayout layout, String id) =>
    flat(layout.primitives).any((ChartPrimitive p) => p.id == id);

/// The middle of a label's end edge: the right edge of its unturned box.
ChartPoint endOf(TextPrimitive t) {
  final List<ChartPoint> c = t.corners;
  return ChartPoint((c[1].x + c[2].x) / 2, (c[1].y + c[2].y) / 2);
}

/// The x of category [i]'s tick, the middle of its band.
double tickX(ChartLayout layout, int i, int n) {
  final ChartRect plot = layout.plotArea!;
  return plot.left + (i + 0.5) * plot.width / n;
}

void main() {
  group('isWrappingOf', () {
    test('a text is a wrapping of itself', () {
      expect(isWrappingOf('North region', 'North region'), isTrue);
      expect(isWrappingOf('', ''), isTrue);
    });

    test('spaces turned into line breaks are a wrapping', () {
      expect(isWrappingOf('North\nregion', 'North region'), isTrue);
      expect(isWrappingOf('a\nb c\nd', 'a b c d'), isTrue);
    });

    test('any other change is not', () {
      // A cut text, a line break where the text has none, a space where it
      // has a break, another letter and a longer text.
      expect(isWrappingOf('North…', 'North region'), isFalse);
      expect(isWrappingOf('Nor\nh', 'North'), isFalse);
      expect(isWrappingOf('a b', 'a\nb'), isFalse);
      expect(isWrappingOf('North regiom', 'North region'), isFalse);
      expect(isWrappingOf('North region ', 'North region'), isFalse);
    });
  });

  test('short labels stay horizontal', () {
    final List<String> cats = <String>['Q1', 'Q2', 'Q3', 'Q4'];
    final ChartLayout layout = lay(cats, const ChartSize(400, 300));
    final Map<int, TextPrimitive> labels = categoryLabels(layout);
    expect(labels.keys, <int>[0, 1, 2, 3]);
    final ChartRect plot = layout.plotArea!;
    for (int i = 0; i < 4; i++) {
      final TextPrimitive t = labels[i]!;
      expect(t.text, cats[i]);
      expect(t.rotationDegrees, 0);
      expect(
        t.rect.left + t.rect.width / 2,
        closeTo(tickX(layout, i, 4), 1e-9),
      );
      expect(t.rect.top, closeTo(plot.bottom + labelGap, 1e-9));
    }
    expect(layout.hidden, isEmpty);
  });

  test('crowded labels skip every second', () {
    // Twelve labels 16.2 wide on a plot about 170 wide: a band of about 14
    // holds no label and a neighbour, two bands hold one.
    final List<String> cats = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final ChartLayout layout = lay(cats, const ChartSize(200, 200));
    final double band = layout.plotArea!.width / 12;
    expect(band, lessThan(16.2 + minTextGap));
    expect(2 * band, greaterThanOrEqualTo(16.2 + minTextGap));
    final Map<int, TextPrimitive> labels = categoryLabels(layout);
    expect(labels.keys, <int>[0, 2, 4, 6, 8, 10]);
    for (final MapEntry<int, TextPrimitive> e in labels.entries) {
      expect(e.value.rotationDegrees, 0);
      expect(e.value.text, cats[e.key]);
      expect(
        e.value.rect.left + e.value.rect.width / 2,
        closeTo(tickX(layout, e.key, 12), 1e-9),
      );
    }
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('level labels skip at most every second, then turn', () {
    // Excel's label spacing never exceeded 2 in the owner's full run (C
    // group), so where every third level label would fit but not every
    // second, they turn instead. 18 labels 48.6 wide on a plot about 360
    // wide: two bands are too few, three would do at 0 degrees.
    final List<String> cats = labelsOf(18, 9);
    final ChartLayout layout = lay(cats, const ChartSize(400, 300));
    final double band = layout.plotArea!.width / 18;
    expect(2 * band, lessThan(48.6 + minTextGap));
    expect(3 * band, greaterThanOrEqualTo(48.6 + minTextGap));
    final Map<int, TextPrimitive> labels = categoryLabels(layout);
    expect(labels.keys, List<int>.generate(18, (int i) => i));
    for (final TextPrimitive t in labels.values) {
      expect(t.rotationDegrees, -45);
    }
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('long labels turn to 45 degrees', () {
    // 18 labels 64.8 wide: three bands are too few at 0 degrees, one band
    // holds a turned label and its neighbour.
    final List<String> cats = labelsOf(18, 12);
    final ChartLayout layout = lay(cats, const ChartSize(400, 300));
    final Map<int, TextPrimitive> labels = categoryLabels(layout);
    expect(labels.keys, List<int>.generate(18, (int i) => i));
    for (final MapEntry<int, TextPrimitive> e in labels.entries) {
      expect(e.value.rotationDegrees, -45);
      expect(e.value.text, cats[e.key]);
    }
    final double band = layout.plotArea!.width / 18;
    expect(3 * band, lessThan(64.8 + minTextGap));
    expect(
      band * math.sin(math.pi / 4),
      greaterThanOrEqualTo(labelHeight + minTextGap),
    );
    expect(layout.hidden, isEmpty);
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('very long labels turn to 90 and are cut with an ellipsis', () {
    // 100 labels on a plot about 360 wide: a band of about 3.6 is too narrow
    // even for every third label at 45 degrees.
    final List<String> cats = labelsOf(100, 60);
    final ChartLayout layout = lay(cats, const ChartSize(400, 300));
    final Map<int, TextPrimitive> labels = categoryLabels(layout);
    expect(labels, isNotEmpty);
    final ChartRect plot = layout.plotArea!;
    final int step = labels.keys.elementAt(1) - labels.keys.first;
    expect(labels.keys, <int>[for (int i = 0; i < 100; i += step) i]);
    final double band = plot.width / 100;
    expect(
      3 * band * math.sin(math.pi / 4),
      lessThan(labelHeight + minTextGap),
    );
    expect(step * band, greaterThanOrEqualTo(labelHeight + minTextGap));
    expect((step - 1) * band, lessThan(labelHeight + minTextGap));
    for (final MapEntry<int, TextPrimitive> e in labels.entries) {
      final TextPrimitive t = e.value;
      expect(t.rotationDegrees, -90);
      expect(t.text, endsWith('…'));
      final String kept = t.text.substring(0, t.text.length - 1);
      expect(cats[e.key], startsWith(kept));
      expect(kept.length, greaterThan(0));
      // The band (label gap and depth) stays within 40% of the plot and
      // band.
      final double depth = t.bounds.bottom - plot.bottom;
      expect(depth, lessThanOrEqualTo(0.4 * (plot.height + depth) + 1e-9));
    }
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('hidden labels are listed', () {
    final List<String> cats = labelsOf(100, 60);
    final ChartLayout layout = lay(cats, const ChartSize(400, 300));
    final Map<int, TextPrimitive> labels = categoryLabels(layout);
    // Every label not shown, and every cut one, with its full text, in
    // index order.
    expect(layout.hidden, <ChartHiddenLabel>[
      for (int i = 0; i < 100; i++)
        if (labels[i] == null || labels[i]!.text != cats[i])
          ChartHiddenLabel(ids.axisLabelId(ids.categoryAxis, i), cats[i]),
    ]);
    expect(layout.hidden, hasLength(100));

    final ChartLayout skipped = lay(<String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ], const ChartSize(200, 200));
    expect(skipped.hidden, <ChartHiddenLabel>[
      for (final (int i, String m) in <(int, String)>[
        (1, 'Feb'),
        (3, 'Apr'),
        (5, 'Jun'),
        (7, 'Aug'),
        (9, 'Oct'),
        (11, 'Dec'),
      ])
        ChartHiddenLabel(ids.axisLabelId(ids.categoryAxis, i), m),
    ]);
  });

  test('the end of a turned label sits at its tick', () {
    for (final (List<String> cats, double rotation) in <(List<String>, double)>[
      (labelsOf(18, 12), -45),
      (labelsOf(100, 60), -90),
    ]) {
      final ChartLayout layout = lay(cats, const ChartSize(400, 300));
      final ChartRect plot = layout.plotArea!;
      expect(categoryLabels(layout), isNotEmpty);
      for (final MapEntry<int, TextPrimitive> e in categoryLabels(
        layout,
      ).entries) {
        final TextPrimitive t = e.value;
        expect(t.rotationDegrees, rotation);
        final ChartPoint end = endOf(t);
        expect(end.x, closeTo(tickX(layout, e.key, cats.length), 1e-9));
        // The end is the label's highest edge: the label hangs from the
        // axis, labelGap or more below the plot.
        expect(
          t.bounds.top,
          greaterThanOrEqualTo(plot.bottom + labelGap - 1e-9),
        );
        expect(end.y, lessThan(t.bounds.top + labelHeight));
      }
    }
  });

  test('bar labels stay level, skip and are cut', () {
    final List<String> cats = labelsOf(60, 40);
    final ChartLayout layout = lay(
      cats,
      const ChartSize(300, 200),
      kind: ChartKind.bar,
    );
    final ChartRect plot = layout.plotArea!;
    final Map<int, TextPrimitive> labels = categoryLabels(layout);
    final int step = labels.keys.elementAt(1) - labels.keys.first;
    expect(step, greaterThan(1));
    expect(labels.keys, <int>[for (int i = 0; i < 60; i += step) i]);
    final double band = plot.height / 60;
    expect(step * band, greaterThanOrEqualTo(labelHeight + minTextGap));
    expect((step - 1) * band, lessThan(labelHeight + minTextGap));
    for (final MapEntry<int, TextPrimitive> e in labels.entries) {
      final TextPrimitive t = e.value;
      expect(t.rotationDegrees, 0);
      expect(t.text, endsWith('…'));
      expect(t.rect.right, closeTo(plot.left - labelGap, 1e-9));
      expect(
        t.rect.top + t.rect.height / 2,
        closeTo(plot.bottom - (e.key + 0.5) * band, 1e-9),
      );
      // Within 40% of the width left for the plot and the band.
      final double depth = plot.left - t.rect.left;
      expect(depth, lessThanOrEqualTo(0.4 * (plot.width + depth) + 1e-9));
    }
    expect(layout.hidden, hasLength(60));
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('no overlap at widths 80 to 800 step 40 for 30 labels of 25 '
      'characters', () {
    final List<String> cats = labelsOf(30, 25);
    for (final ChartKind kind in <ChartKind>[
      ChartKind.column,
      ChartKind.line,
      ChartKind.bar,
    ]) {
      for (double w = 80; w <= 800; w += 40) {
        for (final double h in <double>[120, 300, 600]) {
          final ChartLayout layout = lay(
            cats,
            ChartSize(w, h),
            kind: kind,
            title: 'Revenue',
            legend: const ChartLegend(),
          );
          expect(
            findOverlaps(layout.primitives, layout.size),
            isEmpty,
            reason: '$kind $w x $h',
          );
          if (w >= 400) {
            expect(categoryLabels(layout), isNotEmpty, reason: '$kind $w x $h');
          }
        }
      }
    }
  });

  test('200 crowded categories keep the title and the legend', () {
    final ChartLayout layout = lay(
      labelsOf(200, 20),
      const ChartSize(400, 300),
      title: 'Revenue',
      legend: const ChartLegend(),
    );
    expect(drawn(layout, ids.title), isTrue);
    expect(drawn(layout, ids.legend), isTrue);
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('a hidden value axis leaves room for the first and last label', () {
    for (final ChartKind kind in <ChartKind>[ChartKind.column, ChartKind.bar]) {
      for (final ChartLegendPosition position in ChartLegendPosition.values) {
        for (final List<String> cats in <List<String>>[
          labelsOf(60, 3),
          labelsOf(200, 20),
        ]) {
          final ChartLayout layout = lay(
            cats,
            const ChartSize(400, 300),
            kind: kind,
            title: 'Revenue',
            legend: ChartLegend(position: position),
            valueAxis: const ChartAxis(visible: false),
          );
          final String reason = '$kind $position ${cats.length}';
          expect(drawn(layout, ids.title), isTrue, reason: reason);
          expect(drawn(layout, ids.legend), isTrue, reason: reason);
          expect(categoryLabels(layout), isNotEmpty, reason: reason);
          expect(
            findOverlaps(layout.primitives, layout.size),
            isEmpty,
            reason: reason,
          );
        }
      }
    }
  });

  test('a last label a little wider than its band stays level', () {
    // A last label 54 wide in a band of about 40: it reaches 7 past the
    // plot's right, into the chart's padding, and no label is skipped.
    final ChartLayout layout = lay(
      <String>['Q1', 'Q2', 'Q3', 'Last label'],
      const ChartSize(176, 200),
      valueAxis: const ChartAxis(visible: false),
    );
    final double band = layout.plotArea!.width / 4;
    expect(band, lessThan(54));
    expect(band, greaterThanOrEqualTo((10.8 + 54) / 2 + minTextGap));
    final Map<int, TextPrimitive> labels = categoryLabels(layout);
    expect(labels.keys, <int>[0, 1, 2, 3]);
    expect(
      labels.values.every((TextPrimitive t) => t.rotationDegrees == 0),
      isTrue,
    );
    expect(labels[3]!.rect.right, greaterThan(layout.plotArea!.right));
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  group('wrapped level labels', () {
    // A measurer about as narrow as Aptos Narrow at 9 pt (3.6 per
    // character); the default 0.6 is wider than any real font.
    const FixedWidthTextMeasurer narrow = FixedWidthTextMeasurer(
      charWidthFactor: 0.4,
    );
    const List<List<String>> lines = <List<String>>[
      <String>['Northern region,', 'first half'],
      <String>['Southern region,', 'first half'],
      <String>['Western region,', 'second half'],
      <String>['Eastern region,', 'second half'],
      <String>['Central region,', 'whole year'],
    ];

    Chart longLabels({ChartKind kind = ChartKind.column}) {
      final Chart chart = galleryCharts()
          .firstWhere((GalleryChart g) => g.name == 'column_long_labels')
          .chart;
      return Chart(
        kind: kind,
        series: chart.series,
        title: chart.title,
        legend: chart.legend,
      );
    }

    for (final ChartKind kind in <ChartKind>[
      ChartKind.column,
      ChartKind.line,
      ChartKind.area,
    ]) {
      test('column_long_labels at 360 by 216 wraps onto two lines ($kind)', () {
        // Excel for Mac keeps these five labels level, each on two lines
        // (the owner's J3 gallery check).
        final ChartLayout layout = layoutChart(
          longLabels(kind: kind),
          theme: ChartTheme.office,
          size: const ChartSize(360, 216),
          measurer: narrow,
        );
        final Map<int, TextPrimitive> labels = categoryLabels(layout);
        expect(labels.keys, <int>[0, 1, 2, 3, 4]);
        for (int i = 0; i < 5; i++) {
          final TextPrimitive t = labels[i]!;
          expect(t.rotationDegrees, 0);
          expect(t.text.split('\n'), lines[i]);
          expect(t.text, isNot(contains('…')));
          expect(t.rect.height, closeTo(2 * 9 * 1.2, 1e-9));
        }
        expect(layout.hidden, isEmpty);
        expect(findOverlaps(layout.primitives, layout.size), isEmpty);
        for (final ChartPrimitive p in flat(layout.primitives)) {
          if (p is TextPrimitive) {
            expect(p.bounds.left, greaterThanOrEqualTo(-1e-9), reason: p.id);
            expect(p.bounds.right, lessThanOrEqualTo(360 + 1e-9), reason: p.id);
          }
        }
      });
    }

    test('wrapped labels take their height from the plot', () {
      final ChartLayout layout = layoutChart(
        longLabels(),
        theme: ChartTheme.office,
        size: const ChartSize(360, 216),
        measurer: narrow,
      );
      final ChartRect plot = layout.plotArea!;
      for (final TextPrimitive t in categoryLabels(layout).values) {
        expect(t.rect.top, closeTo(plot.bottom + labelGap, 1e-9));
      }
    });

    test('a label of one word wider than its slot falls through to the '
        'turned option', () {
      // At 600 wide each band is about 108: the spaced labels wrap onto two
      // lines, but the single word of 60 characters (216 wide here) cannot
      // wrap, and every second level label does not fit either.
      final String word = 'W' * 60;
      final List<String> spaced = <String>[
        'Northern region, first half',
        'Southern region, first half',
        'Western region, second half',
        'Eastern region, second half',
      ];
      final ChartLayout wrapped = layoutChart(
        _single(<String>[...spaced, 'Central region, whole year']),
        theme: ChartTheme.office,
        size: const ChartSize(600, 300),
        measurer: measurer,
      );
      expect(
        categoryLabels(
          wrapped,
        ).values.every((TextPrimitive t) => t.rotationDegrees == 0),
        isTrue,
      );
      expect(categoryLabels(wrapped)[0]!.text, 'Northern region,\nfirst half');
      expect(wrapped.hidden, isEmpty);

      final ChartLayout turned = layoutChart(
        _single(<String>[...spaced, word]),
        theme: ChartTheme.office,
        size: const ChartSize(600, 300),
        measurer: measurer,
      );
      final Map<int, TextPrimitive> labels = categoryLabels(turned);
      expect(labels, isNotEmpty);
      for (final TextPrimitive t in labels.values) {
        expect(t.rotationDegrees, isNot(0));
        expect(t.text, isNot(contains('\n')));
      }
      expect(findOverlaps(turned.primitives, turned.size), isEmpty);
    });

    test('the default measurer wraps column_long_labels onto three lines', () {
      // The default measurer (5.4 per character) is wider than Aptos Narrow,
      // so "Western region," does not fit its slot of about 62.8 and each
      // label takes three lines; the labels stay level and whole, and the
      // value axis is scaled on the taller plot: 0 to 160 by 20, as Excel
      // shows it.
      final ChartLayout layout = layoutChart(
        longLabels(),
        theme: ChartTheme.office,
        size: const ChartSize(360, 216),
        measurer: measurer,
      );
      final Map<int, TextPrimitive> labels = categoryLabels(layout);
      expect(labels.keys, <int>[0, 1, 2, 3, 4]);
      expect(labels[2]!.text, 'Western\nregion,\nsecond half');
      for (final TextPrimitive t in labels.values) {
        expect(t.rotationDegrees, 0);
        expect(t.text.split('\n'), hasLength(3));
      }
      expect(layout.hidden, isEmpty);
      const String prefix = 'axis/value/label/';
      expect(
        <String>[
          for (final TextPrimitive t in flat(
            layout.primitives,
          ).whereType<TextPrimitive>())
            if (t.id.startsWith(prefix)) t.text,
        ],
        <String>['0', '20', '40', '60', '80', '100', '120', '140', '160'],
      );
      expect(findOverlaps(layout.primitives, layout.size), isEmpty);
    });

    test('a label wrapped onto more than three lines is not wrapped', () {
      // Four short words, each on its own line in a narrow slot: four lines
      // are too many, so the labels turn.
      final ChartLayout layout = lay(<String>[
        for (int i = 0; i < 6; i++) 'Aaaaaa$i Bbbbbbb Ccccccc Ddddddd',
      ], const ChartSize(400, 300));
      for (final TextPrimitive t in categoryLabels(layout).values) {
        expect(t.rotationDegrees, isNot(0));
        expect(t.text, isNot(contains('\n')));
      }
      expect(findOverlaps(layout.primitives, layout.size), isEmpty);
    });
  });
  group('labels at the chart edge', () {
    // The Office theme's padding: every text keeps it from the chart's edge,
    // where the Office theme draws its border.
    const double padding = 8;
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
    ];

    for (final ChartSize size in const <ChartSize>[
      ChartSize(240, 160),
      ChartSize(360, 216),
      ChartSize(480, 200),
      ChartSize(600, 300),
    ]) {
      for (final bool legend in <bool>[false, true]) {
        test('an area chart\'s first and last labels keep the padding at '
            '${size.width} by ${size.height}${legend ? ', legend' : ''}', () {
          // On tick marks the last label is centred on the plot's right
          // edge, so the plot must leave it half its width and the padding.
          final ChartLayout layout = lay(
            months,
            size,
            kind: ChartKind.area,
            title: 'Monthly sales',
            legend: ChartLegend(visible: legend),
          );
          final Map<int, TextPrimitive> labels = categoryLabels(layout);
          expect(labels.keys, <int>[0, 1, 2, 3, 4, 5]);
          final ChartRect plot = layout.plotArea!;
          final ChartRect last = labels[5]!.bounds;
          expect(
            (last.left + last.right) / 2,
            closeTo(plot.right, 1e-9),
            reason: 'the last label is centred on the plot\'s right edge',
          );
          expect(last.right, lessThanOrEqualTo(size.width - padding + 1e-9));
          expect(labels[0]!.bounds.left, greaterThanOrEqualTo(padding - 1e-9));
          expect(findOverlaps(layout.primitives, layout.size), isEmpty);
        });
      }
    }

    test('an area chart\'s last label keeps minTextGap from a legend on the '
        'right', () {
      final ChartLayout layout = lay(
        months,
        const ChartSize(400, 200),
        kind: ChartKind.area,
        legend: const ChartLegend(position: ChartLegendPosition.right),
      );
      final TextPrimitive last = categoryLabels(layout)[5]!;
      final double legendLeft = flat(layout.primitives)
          .whereType<TextPrimitive>()
          .where((TextPrimitive p) => p.id.startsWith('legend/'))
          .map((TextPrimitive p) => p.bounds.left)
          .reduce(math.min);
      expect(
        last.bounds.right,
        lessThanOrEqualTo(legendLeft - minTextGap + 1e-9),
      );
      expect(findOverlaps(layout.primitives, layout.size), isEmpty);
    });

    test('a turned first label keeps the padding with no value labels', () {
      // A hidden value axis leaves the first label turned at -45 degrees no
      // band of tick labels to reach into: the frame keeps room for it.
      final ChartLayout layout = lay(
        labelsOf(12, 14),
        const ChartSize(300, 200),
        valueAxis: const ChartAxis(visible: false),
      );
      final Map<int, TextPrimitive> labels = categoryLabels(layout);
      expect(labels, isNotEmpty);
      final TextPrimitive first = labels[labels.keys.reduce(math.min)]!;
      expect(first.rotationDegrees, isNot(0));
      expect(first.bounds.left, greaterThanOrEqualTo(padding - 1e-9));
      expect(findOverlaps(layout.primitives, layout.size), isEmpty);
    });
  });
}

Chart _single(List<String> categories) => Chart(
  kind: ChartKind.column,
  legend: const ChartLegend(visible: false),
  series: <ChartSeries>[
    ChartSeries(
      name: ChartData<String>(values: <String?>['Sales']),
      categories: ChartData<Object>(values: categories),
      values: ChartData<double>(
        values: <double?>[
          for (int c = 0; c < categories.length; c++) 3 + c * 2.5,
        ],
      ),
    ),
  ],
);
