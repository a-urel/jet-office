import 'dart:math' as math;

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_core/src/layout/curve.dart';
import 'package:test/test.dart';

double _distance(ChartPoint a, ChartPoint b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

void main() {
  test('fewer than three points come back unchanged', () {
    const List<ChartPoint> two = <ChartPoint>[
      ChartPoint(0, 0),
      ChartPoint(10, 5),
    ];
    expect(smoothPolyline(two), two);
    expect(smoothPolyline(const <ChartPoint>[]), isEmpty);
    expect(smoothPolyline(const <ChartPoint>[ChartPoint(1, 1)]), hasLength(1));
  });

  test('three collinear points give points on the line', () {
    final List<ChartPoint> r = smoothPolyline(const <ChartPoint>[
      ChartPoint(0, 0),
      ChartPoint(10, 10),
      ChartPoint(20, 20),
    ]);
    for (final ChartPoint p in r) {
      expect((p.x - p.y).abs(), lessThan(1e-9));
    }
  });

  test('a curve through three points stays within tolerance of the Bezier', () {
    const List<ChartPoint> input = <ChartPoint>[
      ChartPoint(0, 0),
      ChartPoint(10, 10),
      ChartPoint(20, 0),
    ];
    final List<ChartPoint> r = smoothPolyline(input);
    expect(r.first, input.first);
    expect(r.last, input.last);
    for (final ChartPoint p in input) {
      expect(r, contains(p));
    }
    ChartPoint at(
      ChartPoint p0,
      ChartPoint p1,
      ChartPoint p2,
      ChartPoint p3,
      double t,
    ) {
      final ChartPoint c1 = ChartPoint(
        p1.x + (p2.x - p0.x) / 6,
        p1.y + (p2.y - p0.y) / 6,
      );
      final ChartPoint c2 = ChartPoint(
        p2.x - (p3.x - p1.x) / 6,
        p2.y - (p3.y - p1.y) / 6,
      );
      final double u = 1 - t;
      double f(double a, double b, double c, double d) =>
          u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d;
      return ChartPoint(f(p1.x, c1.x, c2.x, p2.x), f(p1.y, c1.y, c2.y, p2.y));
    }

    final List<ChartPoint> exact = <ChartPoint>[
      for (int i = 0; i <= 100; i++) ...<ChartPoint>[
        at(input[0], input[0], input[1], input[2], i / 100),
        at(input[0], input[1], input[2], input[2], i / 100),
      ],
    ];
    for (final ChartPoint p in r) {
      final double nearest = exact
          .map((ChartPoint e) => _distance(p, e))
          .reduce(math.min);
      expect(nearest, lessThan(0.5), reason: '$p');
    }
    expect(r.length, greaterThan(3));
  });

  test('1000 random points stay finite and within the piece limit', () {
    final math.Random random = math.Random(7);
    final List<ChartPoint> input = <ChartPoint>[
      for (int i = 0; i < 1000; i++)
        ChartPoint(i * 3.0, random.nextDouble() * 400),
    ];
    final List<ChartPoint> r = smoothPolyline(input);
    for (final ChartPoint p in r) {
      expect(p.x.isFinite && p.y.isFinite, isTrue);
    }
    expect(r.length, lessThanOrEqualTo(64 * 999 + 1));
    expect(r.length, greaterThan(input.length));
  });
}
