import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_core/src/layout/chart_ids.dart' as ids;
import 'package:test/test.dart';

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
      maxIntervals: provisionalMaxIntervals(plot.height),
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
    // horizontal value axis, so both stay.
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
    expect(kept, isNot(contains(ids.axisLabelId(ids.valueAxis, 0))));
    expect(
      layout.hidden.map((ChartHiddenLabel h) => h.id),
      isNot(contains(ids.title)),
    );
    expect(problems(layout), isEmpty);
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
      expect(back.rect, ChartRect(0, 0, size.width, size.height));
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

  test('pie, scatter, combination and unsupported draw a placeholder', () {
    const ChartSize size = ChartSize(300, 200);
    for (final ChartKind kind in <ChartKind>[
      ChartKind.pie,
      ChartKind.donut,
      ChartKind.scatter,
      ChartKind.sparkline,
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
      chart(kind: ChartKind.pie, title: 'Share'),
      size,
    );
    expect(titled.primitives.map((ChartPrimitive p) => p.id), <String>[
      ids.background,
      ids.title,
      ids.placeholder,
    ]);
    final ChartLayout tiny = lay(
      chart(kind: ChartKind.pie),
      const ChartSize(20, 10),
    );
    expect(tiny.primitives.map((ChartPrimitive p) => p.id), <String>[
      ids.background,
    ]);
    expect(tiny.hidden, <ChartHiddenLabel>[
      const ChartHiddenLabel(ids.placeholder, 'pie'),
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
}
