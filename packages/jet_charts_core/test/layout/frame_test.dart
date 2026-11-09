import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_core/src/layout/chart_ids.dart' as ids;
import 'package:jet_charts_core/src/layout/degradation.dart';
import 'package:jet_charts_core/src/layout/resolve.dart';
import 'package:jet_charts_core/src/scale/value_scale.dart'
    show excelMaxIntervals;
import 'package:jet_core/jet_core.dart';
import 'package:test/test.dart';

import '../support/gallery.dart';

const FixedWidthTextMeasurer measurer = FixedWidthTextMeasurer();

ChartSeries series(String name, List<double?> values, List<Object?> cats) {
  return ChartSeries(
    name: ChartData<String>(values: <String?>[name]),
    categories: ChartData<Object>(values: cats),
    values: ChartData<double>(values: values),
  );
}

Chart chart({
  ChartKind kind = ChartKind.column,
  int seriesCount = 2,
  List<String> names = const <String>[],
  String? title,
  ChartLegend legend = const ChartLegend(),
  ChartAxis categoryAxis = const ChartAxis(),
  ChartAxis valueAxis = const ChartAxis(gridLines: true),
  List<Object?> categories = const <Object?>['Q1', 'Q2', 'Q3', 'Q4'],
  String? unsupportedName,
}) {
  return Chart(
    kind: kind,
    series: <ChartSeries>[
      for (int s = 0; s < seriesCount; s++)
        series(s < names.length ? names[s] : 'S${s + 1}', <double?>[
          for (int c = 0; c < categories.length; c++) (3 + s + c * 2.5),
        ], categories),
    ],
    title: title == null ? null : ChartTitle(text: title),
    legend: legend,
    categoryAxis: categoryAxis,
    valueAxis: valueAxis,
    unsupportedName: unsupportedName,
  );
}

ChartLayout lay(Chart chart, ChartSize size) => layoutChart(
  chart,
  theme: ChartTheme.office,
  size: size,
  measurer: measurer,
);

Iterable<ChartPrimitive> flat(List<ChartPrimitive> list) sync* {
  for (final ChartPrimitive p in list) {
    yield p;
    if (p is ClipPrimitive) {
      yield* flat(p.children);
    }
  }
}

T byId<T extends ChartPrimitive>(ChartLayout layout, String id) =>
    flat(layout.primitives).firstWhere((ChartPrimitive p) => p.id == id) as T;

double midX(ChartRect r) => r.left + r.width / 2;

List<TextPrimitive> textsStarting(ChartLayout layout, String prefix) =>
    flat(layout.primitives)
        .whereType<TextPrimitive>()
        .where((TextPrimitive t) => t.id.startsWith(prefix))
        .toList();

/// Every problem of [layout]: a non-finite number, something outside the
/// size, or an overlap.
List<String> problems(ChartLayout layout) {
  final ChartSize size = layout.size;
  final List<String> found = <String>[];
  bool inside(ChartRect r) =>
      r.left >= -1e-6 &&
      r.top >= -1e-6 &&
      r.right <= size.width + 1e-6 &&
      r.bottom <= size.height + 1e-6;
  bool finite(ChartRect r) =>
      r.left.isFinite &&
      r.top.isFinite &&
      r.width.isFinite &&
      r.height.isFinite;
  for (final ChartPrimitive p in flat(layout.primitives)) {
    final ChartRect? r = switch (p) {
      RectPrimitive(:final ChartRect rect) => rect,
      TextPrimitive() => p.bounds,
      ClipPrimitive(:final ChartRect rect) => rect,
      _ => null,
    };
    if (r != null && (!finite(r) || !inside(r))) {
      found.add('${p.id} at $r');
    }
    if (p is PathPrimitive) {
      for (final ChartPoint q in p.points) {
        if (!q.x.isFinite ||
            !q.y.isFinite ||
            q.x < -1e-6 ||
            q.y < -1e-6 ||
            q.x > size.width + 1e-6 ||
            q.y > size.height + 1e-6) {
          found.add('${p.id} point $q');
        }
      }
    }
  }
  for (final ChartOverlap o in findOverlaps(layout.primitives, size)) {
    found.add('$o');
  }
  return found;
}

void main() {
  test('the title shrinks the plot', () {
    const ChartSize size = ChartSize(400, 300);
    final ChartLayout without = lay(chart(), size);
    final ChartLayout titled = lay(chart(title: 'Sales'), size);
    // 14 pt title: 16.8 high, then the 6 pt title gap.
    expect(titled.plotArea!.top, closeTo(without.plotArea!.top + 22.8, 1e-9));
    expect(titled.plotArea!.bottom, closeTo(without.plotArea!.bottom, 1e-9));
    final TextPrimitive t = byId<TextPrimitive>(titled, ids.title);
    expect(t.text, 'Sales');
    expect(t.rect.top, 8);
    expect(t.rect.left + t.rect.width / 2, closeTo(200, 1e-9));
    expect(problems(titled), isEmpty);
  });

  test('a bottom legend wraps and sits below the plot', () {
    const ChartSize size = ChartSize(360, 240);
    final ChartLayout layout = lay(
      chart(
        seriesCount: 8,
        names: <String>[for (int i = 1; i <= 8; i++) 'Series name $i'],
      ),
      size,
    );
    final RectPrimitive legend = byId<RectPrimitive>(layout, ids.legend);
    final List<TextPrimitive> entries = textsStarting(layout, ids.legendPrefix);
    expect(entries, hasLength(8));
    // 81.2 per entry and a 12 gap: three fit in 344.
    expect(entries.map((TextPrimitive t) => t.rect.top).toSet(), hasLength(3));
    expect(legend.rect.top, greaterThanOrEqualTo(layout.plotArea!.bottom));
    for (final TextPrimitive label in textsStarting(layout, 'axis/')) {
      expect(label.bounds.bottom, lessThanOrEqualTo(legend.rect.top));
    }
    expect(legend.rect.bottom, closeTo(232, 1e-9));
    expect(problems(layout), isEmpty);
  });

  test('a right legend is a column', () {
    const ChartSize size = ChartSize(360, 240);
    final ChartLayout layout = lay(
      chart(
        seriesCount: 4,
        legend: const ChartLegend(position: ChartLegendPosition.right),
      ),
      size,
    );
    final RectPrimitive legend = byId<RectPrimitive>(layout, ids.legend);
    final List<TextPrimitive> entries = textsStarting(layout, ids.legendPrefix);
    expect(entries, hasLength(4));
    expect(entries.map((TextPrimitive t) => t.rect.left).toSet(), hasLength(1));
    for (int i = 1; i < entries.length; i++) {
      expect(entries[i].rect.top, greaterThan(entries[i - 1].rect.top));
    }
    expect(
      legend.rect.left,
      greaterThanOrEqualTo(layout.plotArea!.right + 6 - 1e-9),
    );
    expect(legend.rect.right, closeTo(352, 1e-9));
    expect(problems(layout), isEmpty);
  });

  test('the legend never covers the plot', () {
    const ChartSize size = ChartSize(360, 240);
    int checked = 0;
    for (final (List<String> names, Set<ChartLegendPosition> fit)
        in <(List<String>, Set<ChartLegendPosition>)>[
          // Long names fit only in rows; a column of them would take more
          // than a third of the width, so the legend is hidden there.
          (
            <String>[
              for (int i = 1; i <= 8; i++) 'A rather long series name $i',
            ],
            <ChartLegendPosition>{
              ChartLegendPosition.top,
              ChartLegendPosition.bottom,
            },
          ),
          // Short names fit on every side.
          (
            <String>[for (int i = 1; i <= 3; i++) 'Series $i'],
            ChartLegendPosition.values.toSet(),
          ),
        ]) {
      for (final ChartLegendPosition position in ChartLegendPosition.values) {
        final ChartLayout layout = lay(
          chart(
            seriesCount: names.length,
            names: names,
            legend: ChartLegend(position: position),
          ),
          size,
        );
        final String reason = '${names.first} $position';
        expect(problems(layout), isEmpty, reason: reason);
        final List<RectPrimitive> legends = flat(layout.primitives)
            .whereType<RectPrimitive>()
            .where((RectPrimitive p) => p.id == ids.legend)
            .toList();
        expect(
          legends,
          hasLength(fit.contains(position) ? 1 : 0),
          reason: reason,
        );
        for (final RectPrimitive legend in legends) {
          expect(
            legend.rect.intersects(layout.plotArea!),
            isFalse,
            reason: reason,
          );
          checked++;
        }
      }
    }
    // Two long-name rows and four short-name sides.
    expect(checked, 6);
  });

  test('value tick labels follow the scale', () {
    final ChartLayout layout = lay(
      Chart(
        kind: ChartKind.column,
        series: <ChartSeries>[
          series('A', <double?>[3, 7, 12], <Object?>['a', 'b', 'c']),
        ],
      ),
      const ChartSize(400, 300),
    );
    final ChartRect plot = layout.plotArea!;
    final ValueScale expected = autoValueScale(
      dataMin: 3,
      dataMax: 12,
      maxIntervals: excelMaxIntervals(
        plot.height,
        horizontal: false,
        fontSize: ChartTheme.office.axisLabels.size,
      ),
    );
    expect(layout.valueScale, expected);
    final List<TextPrimitive> labels = textsStarting(
      layout,
      'axis/value/label/',
    );
    expect(labels, hasLength(expected.ticks.length));
    for (int i = 0; i < labels.length; i++) {
      final double tick = expected.ticks[i];
      expect(labels[i].id, ids.axisLabelId(ids.valueAxis, i));
      expect(labels[i].text, tick.toInt().toString());
      final double y =
          plot.bottom -
          (tick - expected.min) / (expected.max - expected.min) * plot.height;
      expect(labels[i].rect.top + labels[i].rect.height / 2, closeTo(y, 1e-9));
      expect(labels[i].rect.right, closeTo(plot.left - 4, 1e-9));
    }
    expect(
      textsStarting(
        layout,
        'axis/category/label/',
      ).map((TextPrimitive t) => t.text),
      <String>['a', 'b', 'c'],
    );
    expect(problems(layout), isEmpty);
  });

  test('a bar chart has its value axis at the bottom and the first '
      'category at the bottom', () {
    final ChartLayout layout = lay(
      chart(kind: ChartKind.bar),
      const ChartSize(400, 300),
    );
    final ChartRect plot = layout.plotArea!;
    final List<TextPrimitive> values = textsStarting(
      layout,
      'axis/value/label/',
    );
    expect(values.first.rect.top, closeTo(plot.bottom + 4, 1e-9));
    expect(
      values.first.rect.left + values.first.rect.width / 2,
      closeTo(plot.left, 1e-9),
    );
    final List<TextPrimitive> cats = textsStarting(
      layout,
      'axis/category/label/',
    );
    expect(cats.first.text, 'Q1');
    expect(cats.first.rect.right, closeTo(plot.left - 4, 1e-9));
    final double band = plot.height / 4;
    expect(
      cats.first.rect.top + cats.first.rect.height / 2,
      closeTo(plot.bottom - band / 2, 1e-9),
    );
    expect(
      cats.last.rect.top + cats.last.rect.height / 2,
      closeTo(plot.top + band / 2, 1e-9),
    );
    expect(problems(layout), isEmpty);
  });

  test('axis titles sit outside the labels', () {
    final ChartLayout layout = lay(
      chart(
        categoryAxis: const ChartAxis(title: 'Quarter'),
        valueAxis: const ChartAxis(title: 'Revenue', gridLines: true),
      ),
      const ChartSize(400, 300),
    );
    final TextPrimitive value = byId<TextPrimitive>(
      layout,
      ids.axisTitleId(ids.valueAxis),
    );
    final TextPrimitive category = byId<TextPrimitive>(
      layout,
      ids.axisTitleId(ids.categoryAxis),
    );
    expect(value.rotationDegrees, -90);
    expect(value.bounds.left, closeTo(8, 1e-9));
    expect(category.rect.bottom, closeTo(300 - 8 - 10.8 - 6, 1e-9));
    expect(problems(layout), isEmpty);
  });

  test('a 60 by 40 chart hides in order', () {
    const ChartSize size = ChartSize(60, 40);
    final ChartLayout layout = lay(
      chart(
        title: 'Sales',
        categoryAxis: const ChartAxis(title: 'Quarter'),
        valueAxis: const ChartAxis(title: 'Revenue', gridLines: true),
      ),
      size,
    );
    final Set<String> kept = flat(
      layout.primitives,
    ).map((ChartPrimitive p) => p.id).toSet();
    // Legend, axis titles, title and category labels go, in that order; the
    // value labels and the plot stay.
    expect(kept, contains(ids.background));
    expect(kept, contains(ids.plot));
    expect(kept, contains(ids.axisLabelId(ids.valueAxis, 0)));
    expect(kept, isNot(contains(ids.legend)));
    expect(kept, isNot(contains(ids.title)));
    expect(kept, isNot(contains(ids.axisTitleId(ids.valueAxis))));
    expect(kept, isNot(contains(ids.axisTitleId(ids.categoryAxis))));
    expect(kept, isNot(contains(ids.axisLabelId(ids.categoryAxis, 0))));
    expect(layout.hidden.map((ChartHiddenLabel h) => h.id), <String>[
      ids.legendTextId(0),
      ids.legendTextId(1),
      ids.axisTitleId(ids.valueAxis),
      ids.axisTitleId(ids.categoryAxis),
      ids.title,
      for (int i = 0; i < 4; i++) ids.axisLabelId(ids.categoryAxis, i),
    ]);
    expect(layout.hidden.first.text, 'S1');
    expect(problems(layout), isEmpty);
  });

  test('a step that cannot relieve the misfit is passed over', () {
    // A bar chart's tick labels at a fixed unit of 0.5 collide on any
    // width: neither the title nor a bottom legend lengthens its
    // horizontal value axis, so both stay, and the labels are thinned.
    const ChartSize size = ChartSize(400, 300);
    final ChartLayout layout = lay(
      chart(
        kind: ChartKind.bar,
        title: 'Sales',
        valueAxis: const ChartAxis(majorUnit: 0.5),
      ),
      size,
    );
    final Set<String> kept = flat(
      layout.primitives,
    ).map((ChartPrimitive p) => p.id).toSet();
    expect(kept, contains(ids.title));
    expect(kept, contains(ids.legend));
    expect(kept, contains(ids.axisLabelId(ids.valueAxis, 0)));
    expect(kept, isNot(contains(ids.axisLabelId(ids.valueAxis, 1))));
    expect(
      layout.hidden.map((ChartHiddenLabel h) => h.id),
      isNot(contains(ids.title)),
    );
    expect(problems(layout), isEmpty);
  });

  test('a fixed unit whose labels crowd thins them and keeps the rest', () {
    const ChartSize size = ChartSize(360, 240);
    final ChartLayout layout = lay(
      Chart(
        kind: ChartKind.column,
        title: const ChartTitle(text: 'Sales'),
        valueAxis: const ChartAxis(gridLines: true, majorUnit: 2500),
        series: <ChartSeries>[
          series(
            'Revenue',
            <double?>[12000, 35000, 50000],
            <Object?>['North', 'South', 'East'],
          ),
        ],
      ),
      size,
    );
    final Set<String> kept = flat(
      layout.primitives,
    ).map((ChartPrimitive p) => p.id).toSet();
    expect(kept, contains(ids.title));
    expect(kept, contains(ids.legend));
    expect(kept, contains(ids.axisLabelId(ids.categoryAxis, 0)));
    // The first tick's label is always drawn; not every one is.
    expect(kept, contains(ids.axisLabelId(ids.valueAxis, 0)));
    final int ticks = layout.valueScale!.ticks.length;
    final List<TextPrimitive> drawn = textsStarting(
      layout,
      'axis/value/label/',
    );
    expect(drawn.length, greaterThan(1));
    expect(drawn.length, lessThan(ticks));
    // Every grid line stays.
    for (int i = 0; i < ticks; i++) {
      expect(kept, contains(ids.gridId(ids.valueAxis, i)), reason: '$i');
    }
    // The undrawn labels are listed, and nothing else is.
    final List<String> hiddenIds = <String>[
      for (final ChartHiddenLabel h in layout.hidden) h.id,
    ];
    expect(hiddenIds, hasLength(ticks - drawn.length));
    expect(hiddenIds, everyElement(startsWith('axis/value/label/')));
    expect(problems(layout), isEmpty);
  });

  test('a thinned tick label never leaves the chart', () {
    // Fuzz seeds 1 case 684 and 6 case 13, minimized. A bar chart's last
    // tick label is the narrow `0`, so the band past the axis' end is
    // narrow: a wider label that thinning keeps near the end, or a lone
    // first label wider than the plot, would reach past the size.
    final List<(ChartAxis, List<double?>, double)> cases =
        <(ChartAxis, List<double?>, double)>[
          (const ChartAxis(majorUnit: 1e-300), <double?>[-1e300, -1], 100),
          (const ChartAxis(majorUnit: 1e-300), <double?>[-1e300, -1], 480),
          (
            const ChartAxis(
              min: -1e100,
              max: 1,
              majorUnit: 1e-300,
              formatCode: '0',
            ),
            <double?>[1, 0.5],
            400,
          ),
        ];
    for (final (ChartAxis axis, List<double?> values, double width) in cases) {
      final ChartLayout layout = lay(
        Chart(
          kind: ChartKind.bar,
          legend: const ChartLegend(visible: false),
          valueAxis: axis,
          series: <ChartSeries>[
            series('S', values, <Object?>['A', 'B']),
          ],
        ),
        ChartSize(width, 200),
      );
      expect(problems(layout), isEmpty, reason: '$axis $width');
    }
  });

  test('a valueLabels misfit is relieved only by the value labels', () {
    final FrameShown shown = FrameShown.wanted(
      chart(
        title: 'Sales',
        categoryAxis: const ChartAxis(title: 'Quarter'),
        valueAxis: const ChartAxis(title: 'Revenue'),
      ),
      resolveChart(
        chart(),
        ChartTheme.office,
        NumberFormatter(locale: FormatLocale.enUS),
      ),
    );
    for (final bool bar in <bool>[false, true]) {
      for (final ChartLegendPosition position in ChartLegendPosition.values) {
        final List<DegradeStep> relieving = <DegradeStep>[
          for (final DegradeStep step in DegradeStep.values)
            if (shown.relieves(
              step,
              const <FrameMisfit>{FrameMisfit.valueLabels},
              bar: bar,
              legendPosition: position,
            ))
              step,
        ];
        expect(relieving, <DegradeStep>[
          DegradeStep.valueLabels,
        ], reason: 'bar: $bar, $position');
      }
    }
  });

  test("the Office theme draws Excel's border and no value axis line", () {
    final ChartLayout layout = lay(chart(), const ChartSize(480, 288));
    final RectPrimitive back = layout.primitives.first as RectPrimitive;
    expect(back.id, ids.background);
    expect(back.fill, ChartTheme.office.background);
    expect(back.stroke!.rgb, 0xD9D9D9);
    expect(back.strokeWidth, 0.75);
    expect(back.rect, const ChartRect(0.375, 0.375, 479.25, 287.25));
    expect(
      flat(layout.primitives).map((ChartPrimitive p) => p.id),
      isNot(contains('axis/value/line')),
    );
    expect(problems(layout), isEmpty);
  });

  test('a theme without border and with a value axis line draws both ways', () {
    final ChartTheme old = ChartTheme.office.copyWith(valueAxisLine: true);
    final ChartTheme plain = ChartTheme(
      palette: old.palette,
      axisLabels: old.axisLabels,
      titleText: old.titleText,
      legendText: old.legendText,
      dataLabels: old.dataLabels,
      gridLine: old.gridLine,
      axisLine: old.axisLine,
      background: old.background,
    );
    final ChartLayout layout = layoutChart(
      chart(),
      theme: plain,
      size: const ChartSize(480, 288),
      measurer: measurer,
    );
    final RectPrimitive back = layout.primitives.first as RectPrimitive;
    expect(back.stroke, isNull);
    expect(back.rect, const ChartRect(0, 0, 480, 288));
    expect(
      flat(layout.primitives).map((ChartPrimitive p) => p.id),
      contains('axis/value/line'),
    );
  });

  test('a tiny chart draws only its background', () {
    for (final ChartSize size in const <ChartSize>[
      ChartSize(0, 0),
      ChartSize(10, 10),
      ChartSize(16.5, 300),
    ]) {
      final ChartLayout layout = lay(chart(title: 'Sales'), size);
      expect(layout.primitives, hasLength(1), reason: '$size');
      final RectPrimitive back = layout.primitives.single as RectPrimitive;
      expect(back.id, ids.background);
      expect(back.fill, ChartTheme.office.background);
      // The border's stroke stays inside the size, so a size no larger than
      // its width has none.
      if (size.width <= 0.75 || size.height <= 0.75) {
        expect(back.rect, ChartRect(0, 0, size.width, size.height));
        expect(back.stroke, isNull);
      } else {
        expect(
          back.rect,
          ChartRect(0.375, 0.375, size.width - 0.75, size.height - 0.75),
        );
      }
      expect(layout.plotArea, isNull);
      expect(
        layout.hidden.map((ChartHiddenLabel h) => h.id),
        contains(ids.title),
      );
      // The value tick labels are listed too, even with no room at all.
      expect(
        layout.hidden.map((ChartHiddenLabel h) => h.id),
        containsAll(<String>[
          ids.axisLabelId(ids.valueAxis, 0),
          ids.axisLabelId(ids.valueAxis, 1),
        ]),
        reason: '$size',
      );
      expect(
        layout.hidden.map((ChartHiddenLabel h) => h.id).last,
        startsWith('axis/value/label/'),
      );
    }
  });

  test('a 2,000-character title is hidden, not overlapping', () {
    const ChartSize size = ChartSize(360, 240);
    final String long = 'T' * 2000;
    final ChartLayout layout = lay(chart(title: long), size);
    expect(
      flat(layout.primitives).any((ChartPrimitive p) => p.id == ids.title),
      isFalse,
    );
    expect(layout.hidden, contains(ChartHiddenLabel(ids.title, long)));
    // Only the title goes: the legend stays.
    expect(
      flat(layout.primitives).any((ChartPrimitive p) => p.id == ids.legend),
      isTrue,
    );
    expect(problems(layout), isEmpty);
  });

  test('an empty series list gives axes 0 to 1', () {
    final ChartLayout layout = lay(
      Chart(kind: ChartKind.column, series: <ChartSeries>[]),
      const ChartSize(360, 240),
    );
    expect(layout.valueScale!.min, 0);
    expect(layout.valueScale!.max, 1);
    expect(textsStarting(layout, 'axis/value/label/').first.text, '0');
    expect(textsStarting(layout, 'axis/value/label/').last.text, '1');
    expect(
      flat(layout.primitives).any((ChartPrimitive p) => p.id == ids.legend),
      isFalse,
    );
    expect(problems(layout), isEmpty);
  });

  test('scatter, combination and unsupported draw a placeholder', () {
    const ChartSize size = ChartSize(300, 200);
    for (final ChartKind kind in <ChartKind>[
      ChartKind.scatter,
      ChartKind.combination,
      ChartKind.unsupported,
    ]) {
      final ChartLayout layout = lay(
        chart(
          kind: kind,
          unsupportedName: kind == ChartKind.unsupported ? 'bubbleChart' : null,
        ),
        size,
      );
      expect(layout.primitives.map((ChartPrimitive p) => p.id), <String>[
        ids.background,
        ids.placeholder,
      ], reason: '$kind');
      final TextPrimitive text = layout.primitives.last as TextPrimitive;
      expect(
        text.text,
        kind == ChartKind.unsupported ? 'bubbleChart' : kind.name,
      );
      expect(text.rect.left + text.rect.width / 2, closeTo(150, 1e-9));
      expect(text.rect.top + text.rect.height / 2, closeTo(100, 1e-9));
      expect(layout.plotArea, isNull);
      expect(layout.valueScale, isNull);
    }
    final ChartLayout titled = lay(
      chart(
        kind: ChartKind.unsupported,
        unsupportedName: 'bubbleChart',
        title: 'Share',
      ),
      size,
    );
    expect(titled.primitives.map((ChartPrimitive p) => p.id), <String>[
      ids.background,
      ids.title,
      ids.placeholder,
    ]);
    final ChartLayout tiny = lay(
      chart(kind: ChartKind.unsupported, unsupportedName: 'bubbleChart'),
      const ChartSize(20, 10),
    );
    expect(tiny.primitives.map((ChartPrimitive p) => p.id), <String>[
      ids.background,
    ]);
    expect(tiny.hidden, <ChartHiddenLabel>[
      const ChartHiddenLabel(ids.placeholder, 'bubbleChart'),
    ]);
  });

  test('negative size throws', () {
    for (final ChartSize size in const <ChartSize>[
      ChartSize(-1, 10),
      ChartSize(10, -1),
      ChartSize(double.nan, 10),
      ChartSize(10, double.infinity),
    ]) {
      expect(() => lay(chart(), size), throwsArgumentError, reason: '$size');
    }
  });

  test('every size from tiny to large lays out inside and without overlap', () {
    final List<Chart> charts = <Chart>[
      for (final ChartKind kind in <ChartKind>[
        ChartKind.column,
        ChartKind.bar,
        ChartKind.line,
        ChartKind.area,
      ])
        for (final ChartLegendPosition position in ChartLegendPosition.values)
          chart(
            kind: kind,
            seriesCount: 3,
            title: 'Revenue by quarter',
            legend: ChartLegend(position: position),
            categoryAxis: const ChartAxis(title: 'Quarter', gridLines: true),
            valueAxis: const ChartAxis(title: 'Revenue', gridLines: true),
          ),
    ];
    for (final Chart c in charts) {
      for (double w = 0; w <= 800; w += 37) {
        for (double h = 0; h <= 600; h += 43) {
          final ChartLayout layout = lay(c, ChartSize(w, h));
          expect(problems(layout), isEmpty, reason: '${c.kind} $w x $h');
        }
      }
    }
  });

  group('category bands', () {
    ChartLayout galleryLayout(String name) => galleryCharts()
        .firstWhere((GalleryChart g) => g.name == name)
        .layout(goldenSize);

    test('column_clustered has 4 bands tiling the plot\'s width', () {
      final ChartLayout layout = galleryLayout('column_clustered');
      final ChartRect plot = layout.plotArea!;
      final List<ChartRect> bands = layout.categoryBands;
      expect(bands, hasLength(4));
      expect(bands.first.left, closeTo(plot.left, 1e-9));
      expect(bands.last.right, closeTo(plot.right, 1e-9));
      for (int i = 0; i < bands.length; i++) {
        expect(bands[i].top, plot.top);
        expect(bands[i].height, plot.height);
        expect(bands[i].width, closeTo(plot.width / 4, 1e-9));
        if (i > 0) {
          expect(bands[i].left, closeTo(bands[i - 1].right, 1e-9));
        }
      }
      // Each bar lies in its category's band.
      for (int s = 0; s < 3; s++) {
        for (int c = 0; c < 4; c++) {
          final RectPrimitive bar = byId<RectPrimitive>(
            layout,
            ids.seriesBarId(s, c),
          );
          expect(bands[c].contains(bar.rect), isTrue, reason: '$s/$c');
        }
      }
      // The category grid lines run along the bands' edges.
      final ChartLayout gridded = lay(
        chart(categoryAxis: const ChartAxis(gridLines: true)),
        goldenSize,
      );
      for (int i = 0; i <= 4; i++) {
        final PathPrimitive line = byId<PathPrimitive>(
          gridded,
          ids.gridId(ids.categoryAxis, i),
        );
        expect(
          line.points.first.x,
          i < 4
              ? gridded.categoryBands[i].left
              : gridded.categoryBands[3].right,
        );
      }
    });

    test('bar_clustered has 4 bands tiling the plot\'s height, from the '
        'bottom', () {
      final ChartLayout layout = galleryLayout('bar_clustered');
      final ChartRect plot = layout.plotArea!;
      final List<ChartRect> bands = layout.categoryBands;
      expect(bands, hasLength(4));
      expect(bands.first.bottom, closeTo(plot.bottom, 1e-9));
      expect(bands.last.top, closeTo(plot.top, 1e-9));
      for (int i = 0; i < bands.length; i++) {
        expect(bands[i].left, plot.left);
        expect(bands[i].width, plot.width);
        expect(bands[i].height, closeTo(plot.height / 4, 1e-9));
        if (i > 0) {
          expect(bands[i].bottom, closeTo(bands[i - 1].top, 1e-9));
        }
        final RectPrimitive bar = byId<RectPrimitive>(
          layout,
          ids.seriesBarId(0, i),
        );
        expect(bands[i].contains(bar.rect), isTrue, reason: '$i');
      }
    });

    test('line and area charts have a band per category', () {
      expect(galleryLayout('line_gap').categoryBands, hasLength(6));
      expect(galleryLayout('area_stacked').categoryBands, hasLength(4));
    });

    group('an area chart lies on tick marks', () {
      test('area_stacked runs from the plot\'s left to its right', () {
        final ChartLayout layout = galleryLayout('area_stacked');
        final ChartRect plot = layout.plotArea!;
        for (int s = 0; s < 3; s++) {
          final PathPrimitive area = byId<PathPrimitive>(
            layout,
            ids.seriesAreaId(s),
          );
          for (int c = 0; c < 4; c++) {
            final double x = plot.left + c * plot.width / 3;
            expect(area.points[c].x, closeTo(x, 1e-9), reason: '$s/$c');
            expect(area.points[7 - c].x, closeTo(x, 1e-9), reason: '$s/$c');
          }
          expect(area.points.first.x, closeTo(plot.left, 1e-9));
          expect(area.points[3].x, closeTo(plot.right, 1e-9));
        }
      });

      test('its labels are centred on the categories, inside the chart', () {
        final ChartLayout layout = galleryLayout('area_stacked');
        final ChartRect plot = layout.plotArea!;
        final TextPrimitive q1 = byId<TextPrimitive>(
          layout,
          ids.axisLabelId(ids.categoryAxis, 0),
        );
        final TextPrimitive q4 = byId<TextPrimitive>(
          layout,
          ids.axisLabelId(ids.categoryAxis, 3),
        );
        expect(q1.text, 'Q1');
        expect(q4.text, 'Q4');
        expect(midX(q1.rect), closeTo(plot.left, 1e-9));
        expect(midX(q4.rect), closeTo(plot.right, 1e-9));
        expect(q1.bounds.left, greaterThanOrEqualTo(0));
        expect(q4.bounds.right, lessThanOrEqualTo(goldenSize.width));
        expect(problems(layout), isEmpty);
      });

      test('its bands tile the plot with edges halfway between categories', () {
        final ChartLayout layout = galleryLayout('area_stacked');
        final ChartRect plot = layout.plotArea!;
        final List<ChartRect> bands = layout.categoryBands;
        final double step = plot.width / 3;
        expect(bands, hasLength(4));
        expect(bands.first.left, closeTo(plot.left, 1e-9));
        expect(bands.last.right, closeTo(plot.right, 1e-9));
        for (int i = 0; i < 4; i++) {
          expect(bands[i].top, plot.top);
          expect(bands[i].height, plot.height);
          if (i > 0) {
            expect(bands[i].left, closeTo(plot.left + (i - 0.5) * step, 1e-9));
            expect(bands[i].left, closeTo(bands[i - 1].right, 1e-9));
          }
        }
        expect(bands.first.width, closeTo(step / 2, 1e-9));
        expect(bands[1].width, closeTo(step, 1e-9));
      });

      test('its category grid lines run through the categories', () {
        final ChartLayout layout = lay(
          chart(
            kind: ChartKind.area,
            categoryAxis: const ChartAxis(gridLines: true),
          ),
          goldenSize,
        );
        final ChartRect plot = layout.plotArea!;
        for (int i = 0; i < 4; i++) {
          final PathPrimitive line = byId<PathPrimitive>(
            layout,
            ids.gridId(ids.categoryAxis, i),
          );
          expect(
            line.points.first.x,
            closeTo(plot.left + i * plot.width / 3, 1e-9),
          );
        }
        expect(
          flat(
            layout.primitives,
          ).any((ChartPrimitive p) => p.id == ids.gridId(ids.categoryAxis, 4)),
          isFalse,
        );
      });

      test('a one-category area is centred, its band the whole plot', () {
        final ChartLayout layout = lay(
          chart(kind: ChartKind.area, categories: const <Object?>['Q1']),
          goldenSize,
        );
        final ChartRect plot = layout.plotArea!;
        final PathPrimitive area = byId<PathPrimitive>(
          layout,
          ids.seriesAreaId(0),
        );
        for (final ChartPoint p in area.points) {
          expect(p.x, closeTo(midX(plot), 1e-9));
        }
        final TextPrimitive q1 = byId<TextPrimitive>(
          layout,
          ids.axisLabelId(ids.categoryAxis, 0),
        );
        expect(midX(q1.rect), closeTo(midX(plot), 1e-9));
        expect(layout.categoryBands, <ChartRect>[plot]);
      });

      test('a column, bar or line chart keeps band middles', () {
        final ChartLayout layout = galleryLayout('line_gap');
        final ChartRect plot = layout.plotArea!;
        final TextPrimitive first = byId<TextPrimitive>(
          layout,
          ids.axisLabelId(ids.categoryAxis, 0),
        );
        expect(midX(first.rect), closeTo(plot.left + plot.width / 12, 1e-9));
      });
    });

    test('a placeholder kind, or a chart without a plot, has none', () {
      expect(
        lay(
          chart(kind: ChartKind.unsupported, unsupportedName: 'bubbleChart'),
          goldenSize,
        ).categoryBands,
        isEmpty,
      );
      expect(lay(chart(), const ChartSize(8, 8)).categoryBands, isEmpty);
    });

    test('the bands are unmodifiable and part of the layout\'s value', () {
      final ChartLayout layout = galleryLayout('column_clustered');
      expect(
        () => layout.categoryBands.add(const ChartRect(0, 0, 1, 1)),
        throwsUnsupportedError,
      );
      final ChartLayout copy = ChartLayout(
        size: layout.size,
        primitives: layout.primitives,
        plotArea: layout.plotArea,
        valueScale: layout.valueScale,
        hidden: layout.hidden,
        categoryBands: layout.categoryBands,
      );
      expect(copy, layout);
      expect(copy.hashCode, layout.hashCode);
      final ChartLayout without = ChartLayout(
        size: layout.size,
        primitives: layout.primitives,
        plotArea: layout.plotArea,
        valueScale: layout.valueScale,
        hidden: layout.hidden,
      );
      expect(without.categoryBands, isEmpty);
      expect(without, isNot(layout));
    });
  });
}
