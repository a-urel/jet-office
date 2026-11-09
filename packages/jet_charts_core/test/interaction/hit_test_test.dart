import 'dart:math' as math;

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

import '../support/gallery.dart';

ChartLayout _gallery(String name) => galleryCharts()
    .firstWhere((GalleryChart g) => g.name == name)
    .layout(goldenSize);

Iterable<ChartPrimitive> _flat(List<ChartPrimitive> list) sync* {
  for (final ChartPrimitive p in list) {
    yield p;
    if (p is ClipPrimitive) {
      yield* _flat(p.children);
    }
  }
}

T _byId<T extends ChartPrimitive>(ChartLayout layout, String id) =>
    _flat(layout.primitives).firstWhere((ChartPrimitive p) => p.id == id) as T;

List<String> _hitIds(
  ChartLayout layout,
  ChartPoint point, {
  double tolerance = 0,
}) => <String>[
  for (final ChartPrimitive p in hitTestLayout(
    layout,
    point,
    tolerance: tolerance,
  ))
    p.id,
];

bool _isMark(String id) => id.startsWith('series/') || id.startsWith('label/');

/// The point [distance] off the middle of the segment [a] to [b], along its
/// normal.
ChartPoint _offMiddle(ChartPoint a, ChartPoint b, double distance) {
  final double dx = b.x - a.x;
  final double dy = b.y - a.y;
  final double length = math.sqrt(dx * dx + dy * dy);
  return ChartPoint(
    (a.x + b.x) / 2 - dy / length * distance,
    (a.y + b.y) / 2 + dx / length * distance,
  );
}

void main() {
  group('on column_clustered', () {
    final ChartLayout layout = _gallery('column_clustered');

    test('the centre of a bar hits it first and the background last', () {
      final ChartRect r = _byId<RectPrimitive>(layout, 'series/1/bar/2').rect;
      final List<String> hits = _hitIds(
        layout,
        ChartPoint(r.left + r.width / 2, r.top + r.height / 2),
      );
      expect(hits.first, 'series/1/bar/2');
      expect(hits.last, 'background');
      // The clip comes after its children, the plot after the clip.
      expect(hits.indexOf('plot/clip'), greaterThan(0));
      expect(hits.indexOf('plot'), greaterThan(hits.indexOf('plot/clip')));
    });

    test('a point between bars hits no mark; plot, then background', () {
      final ChartRect a = _byId<RectPrimitive>(layout, 'series/2/bar/0').rect;
      final ChartRect b = _byId<RectPrimitive>(layout, 'series/0/bar/1').rect;
      final ChartRect plot = layout.plotArea!;
      final ChartPoint p = ChartPoint((a.right + b.left) / 2, plot.top + 5);
      final List<String> hits = _hitIds(layout, p);
      expect(hits.where(_isMark), isEmpty);
      expect(hits.sublist(hits.length - 2), <String>['plot', 'background']);
      expect(hits, contains('plot/clip'));
    });

    test('a NaN or infinite point hits nothing', () {
      expect(hitTestLayout(layout, const ChartPoint(double.nan, 10)), isEmpty);
      expect(hitTestLayout(layout, const ChartPoint(10, double.nan)), isEmpty);
      expect(
        hitTestLayout(layout, const ChartPoint(double.infinity, 10)),
        isEmpty,
      );
    });

    test('a negative or non-finite tolerance throws', () {
      for (final double t in <double>[-1, double.nan, double.infinity]) {
        expect(
          () => hitTestLayout(layout, const ChartPoint(10, 10), tolerance: t),
          throwsArgumentError,
          reason: '$t',
        );
      }
    });

    test('a point outside the size hits nothing; tolerance reaches it', () {
      expect(hitTestLayout(layout, const ChartPoint(-3, -3)), isEmpty);
      expect(_hitIds(layout, const ChartPoint(-3, -3), tolerance: 4), <String>[
        'background',
      ]);
    });
  });

  test('a line is hit within half its width, or with a tolerance', () {
    final ChartLayout layout = _gallery('line_gap');
    final PathPrimitive line = _byId<PathPrimitive>(layout, 'series/0/line/0');
    expect(line.strokeWidth / 2, greaterThan(1));
    expect(line.strokeWidth / 2, lessThan(5));
    final ChartPoint a = line.points[0];
    final ChartPoint b = line.points[1];
    expect(_hitIds(layout, _offMiddle(a, b, 1)).first, 'series/0/line/0');
    expect(_hitIds(layout, _offMiddle(a, b, 5)), isNot(contains(line.id)));
    expect(
      _hitIds(layout, _offMiddle(a, b, 5), tolerance: 4).first,
      'series/0/line/0',
    );
    expect(_hitIds(layout, _offMiddle(a, b, -1)).first, 'series/0/line/0');
    // Past the end of the run, beyond half the width: no hit.
    expect(_hitIds(layout, ChartPoint(a.x - 3, a.y)), isNot(contains(line.id)));
  });

  test('a turned label is hit inside its corners only', () {
    final ChartLayout layout = _gallery('column_long_labels');
    final TextPrimitive label = _byId<TextPrimitive>(
      layout,
      'axis/category/label/0',
    );
    expect(label.rotationDegrees, isNot(0));
    final ChartRect r = label.rect;
    final ChartPoint centre = ChartPoint(
      r.left + r.width / 2,
      r.top + r.height / 2,
    );
    expect(_hitIds(layout, centre), contains(label.id));
    // Near a turned corner, inside it.
    final ChartPoint corner = label.corners[0];
    final ChartPoint nearCorner = ChartPoint(
      corner.x + (centre.x - corner.x) * 0.05,
      corner.y + (centre.y - corner.y) * 0.05,
    );
    expect(_hitIds(layout, nearCorner), contains(label.id));
    // Inside the unrotated rectangle's corner, but outside the turned text.
    final ChartPoint unrotated = ChartPoint(r.left + 1, r.top + 1);
    expect(_hitIds(layout, unrotated), isNot(contains(label.id)));
  });

  test('a mark that overflows the clip is not hit outside it', () {
    final Chart chart = Chart(
      kind: ChartKind.column,
      series: <ChartSeries>[
        ChartSeries(
          name: ChartData<String>(values: <String?>['Over']),
          categories: ChartData<Object>(values: <Object?>['A', 'B']),
          values: ChartData<double>(values: <double?>[18, 4]),
        ),
      ],
      valueAxis: const ChartAxis(min: 0, max: 10, majorUnit: 2),
    );
    final ChartLayout layout = layoutChart(
      chart,
      theme: ChartTheme.office,
      size: goldenSize,
      measurer: const FixedWidthTextMeasurer(),
    );
    final ChartRect plot = layout.plotArea!;
    final ChartRect bar = _byId<RectPrimitive>(layout, 'series/0/bar/0').rect;
    expect(bar.top, lessThan(plot.top - 2));
    final double x = bar.left + bar.width / 2;
    final ChartPoint above = ChartPoint(x, plot.top - 1);
    final List<String> hits = _hitIds(layout, above);
    expect(hits, isNot(contains('series/0/bar/0')));
    expect(hits, isNot(contains('plot/clip')));
    expect(
      _hitIds(layout, ChartPoint(x, plot.top + 1)).first,
      'series/0/bar/0',
    );
  });

  group('primitives by kind', () {
    ChartLayout of(List<ChartPrimitive> primitives) =>
        ChartLayout(size: const ChartSize(100, 100), primitives: primitives);

    test('a rectangle, edges included, grown by the tolerance', () {
      final ChartLayout layout = of(<ChartPrimitive>[
        const RectPrimitive('r', ChartRect(10, 10, 20, 20)),
      ]);
      expect(_hitIds(layout, const ChartPoint(10, 30)), <String>['r']);
      expect(_hitIds(layout, const ChartPoint(9, 20)), isEmpty);
      expect(_hitIds(layout, const ChartPoint(9, 20), tolerance: 1), <String>[
        'r',
      ]);
    });

    test('a closed filled path: inside (even-odd) or near an edge', () {
      final ChartLayout layout = of(<ChartPrimitive>[
        PathPrimitive(
          'p',
          const <ChartPoint>[
            ChartPoint(0, 0),
            ChartPoint(40, 0),
            ChartPoint(40, 40),
            ChartPoint(0, 40),
          ],
          closed: true,
          fill: ChartColor.rgb(0x112233),
        ),
      ]);
      expect(_hitIds(layout, const ChartPoint(20, 20)), <String>['p']);
      expect(_hitIds(layout, const ChartPoint(42, 20)), isEmpty);
      expect(_hitIds(layout, const ChartPoint(42, 20), tolerance: 2), <String>[
        'p',
      ]);
    });

    test('a closed path without a fill is hit along its outline only', () {
      final ChartLayout layout = of(<ChartPrimitive>[
        PathPrimitive(
          'p',
          const <ChartPoint>[
            ChartPoint(0, 0),
            ChartPoint(40, 0),
            ChartPoint(40, 40),
            ChartPoint(0, 40),
          ],
          closed: true,
          stroke: ChartColor.rgb(0x112233),
          strokeWidth: 2,
        ),
      ]);
      expect(_hitIds(layout, const ChartPoint(20, 20)), isEmpty);
      // The closing edge, from the last point back to the first.
      expect(_hitIds(layout, const ChartPoint(0.5, 20)), <String>['p']);
    });

    test('an arc: between its radii and inside its sweep', () {
      final ChartLayout layout = of(<ChartPrimitive>[
        const ArcPrimitive('a', ChartPoint(50, 50), 40, 20, 0, 90),
        const ArcPrimitive('b', ChartPoint(50, 50), 40, 20, 0, -90),
      ]);
      // 0 degrees is three o'clock; positive sweeps clockwise (y down).
      expect(_hitIds(layout, const ChartPoint(50, 80)), <String>['a']);
      expect(_hitIds(layout, const ChartPoint(50, 20)), <String>['b']);
      expect(_hitIds(layout, const ChartPoint(20, 50)), isEmpty);
      expect(_hitIds(layout, const ChartPoint(50, 60)), isEmpty);
      expect(_hitIds(layout, const ChartPoint(50, 60), tolerance: 10), <String>[
        'a',
      ]);
      expect(_hitIds(layout, const ChartPoint(50, 91)), isEmpty);
    });

    test('a stroked arc is hit on half its stroke width too', () {
      final ChartLayout layout = of(<ChartPrimitive>[
        ArcPrimitive(
          'a',
          const ChartPoint(50, 50),
          10,
          0,
          0,
          360,
          stroke: ChartColor.rgb(0x112233),
          strokeWidth: 4,
        ),
        const ArcPrimitive(
          'b',
          ChartPoint(50, 20),
          10,
          0,
          0,
          360,
          strokeWidth: 4,
        ),
      ]);
      expect(_hitIds(layout, const ChartPoint(61.5, 50)), <String>['a']);
      expect(_hitIds(layout, const ChartPoint(62.5, 50)), isEmpty);
      // Without a stroke colour the width adds nothing.
      expect(_hitIds(layout, const ChartPoint(61.5, 20)), isEmpty);
    });

    test('topmost first: later primitives come before earlier ones', () {
      final ChartLayout layout = of(<ChartPrimitive>[
        const RectPrimitive('under', ChartRect(0, 0, 50, 50)),
        const RectPrimitive('over', ChartRect(10, 10, 20, 20)),
      ]);
      expect(_hitIds(layout, const ChartPoint(15, 15)), <String>[
        'over',
        'under',
      ]);
    });
  });
}
