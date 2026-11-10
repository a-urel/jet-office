import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

ChartTextStyle style() =>
    ChartTextStyle(fontFamily: 'Test', size: 10, color: ChartColor.rgb(0));

/// Exhaustive on purpose: adding a primitive without handling it here breaks
/// compilation, because there is no default.
String kindOf(ChartPrimitive primitive) {
  return switch (primitive) {
    RectPrimitive() => 'rect',
    PathPrimitive() => 'path',
    ArcPrimitive() => 'arc',
    TextPrimitive() => 'text',
    ClipPrimitive() => 'clip',
  };
}

void main() {
  const ChartRect a = ChartRect(0, 0, 10, 10);

  test('touching rects do not intersect', () {
    expect(a.intersects(const ChartRect(10, 0, 10, 10)), isFalse);
    expect(a.intersects(const ChartRect(0, 10, 10, 10)), isFalse);
  });

  test('overlapping rects do', () {
    expect(a.intersects(const ChartRect(5, 5, 10, 10)), isTrue);
    expect(const ChartRect(5, 5, 10, 10).intersects(a), isTrue);
  });

  test('a rect contains itself', () {
    expect(a.contains(a), isTrue);
    expect(a.contains(const ChartRect(2, 2, 3, 3)), isTrue);
    expect(a.contains(const ChartRect(5, 5, 10, 10)), isFalse);
  });

  test('right and bottom', () {
    expect(const ChartRect(1, 2, 3, 4).right, 4);
    expect(const ChartRect(1, 2, 3, 4).bottom, 6);
  });

  test('zero-size rects intersect nothing', () {
    const ChartRect zero = ChartRect(5, 5, 0, 0);
    const ChartRect flat = ChartRect(0, 5, 10, 0);
    expect(zero.intersects(a), isFalse);
    expect(a.intersects(zero), isFalse);
    expect(zero.intersects(zero), isFalse);
    expect(flat.intersects(a), isFalse);
  });

  test(
    'rects with NaN or negative size intersect nothing and do not throw',
    () {
      const ChartRect nan = ChartRect(0, 0, double.nan, 10);
      const ChartRect negative = ChartRect(0, 0, -10, 10);
      expect(nan.intersects(a), isFalse);
      expect(a.intersects(nan), isFalse);
      expect(negative.intersects(a), isFalse);
      expect(a.intersects(negative), isFalse);
      expect(nan.intersects(nan), isFalse);
      expect(a.contains(nan), isFalse);
    },
  );

  test('points, sizes and rects are values', () {
    expect(const ChartPoint(1, 2), const ChartPoint(1, 2));
    expect(const ChartPoint(1, 2).hashCode, const ChartPoint(1, 2).hashCode);
    expect(const ChartSize(1, 2), isNot(const ChartSize(2, 1)));
    expect(const ChartRect(1, 2, 3, 4), const ChartRect(1, 2, 3, 4));
    expect(const ChartRect(1, 2, 3, 4), isNot(const ChartRect(1, 2, 3, 5)));
  });

  test('primitives are values', () {
    TextPrimitive make() =>
        TextPrimitive('t', 'Sales', a, style(), rotationDegrees: 90);
    expect(make(), make());
    expect(make().hashCode, make().hashCode);
    expect(make(), isNot(TextPrimitive('t', 'Sales', a, style())));
    expect(
      RectPrimitive('r', a, fill: ChartColor.rgb(1)),
      RectPrimitive('r', a, fill: ChartColor.rgb(1)),
    );
    expect(
      RectPrimitive('r', a, fill: ChartColor.rgb(1)),
      isNot(RectPrimitive('r', a, fill: ChartColor.rgb(2))),
    );
    expect(const RectPrimitive('r', a).strokeWidth, 1);
  });

  test('path and clip copy their lists', () {
    final List<ChartPoint> points = <ChartPoint>[
      const ChartPoint(0, 0),
      const ChartPoint(1, 1),
    ];
    final List<double> dash = <double>[2, 2];
    final PathPrimitive path = PathPrimitive('p', points, dash: dash);
    final PathPrimitive same = PathPrimitive(
      'p',
      <ChartPoint>[const ChartPoint(0, 0), const ChartPoint(1, 1)],
      dash: <double>[2, 2],
    );
    points.add(const ChartPoint(2, 2));
    dash.add(9);
    expect(path.points, hasLength(2));
    expect(path.dash, <double>[2, 2]);
    expect(path, same);
    expect(path.hashCode, same.hashCode);
    expect(path.closed, isFalse);
    expect(
      () => path.points.add(const ChartPoint(3, 3)),
      throwsUnsupportedError,
    );
    expect(() => path.dash!.add(1), throwsUnsupportedError);
    expect(PathPrimitive('p', points).dash, isNull);

    final List<ChartPrimitive> children = <ChartPrimitive>[path];
    final ClipPrimitive clip = ClipPrimitive('c', a, children);
    children.clear();
    expect(clip.children, hasLength(1));
    expect(() => clip.children.add(path), throwsUnsupportedError);
    expect(clip, ClipPrimitive('c', a, <ChartPrimitive>[same]));
  });

  test('arcs are values', () {
    ArcPrimitive make({double inner = 0}) =>
        ArcPrimitive('a', const ChartPoint(5, 5), 5, inner, 0, 90);
    expect(make(), make());
    expect(make(), isNot(make(inner: 2)));
  });

  test('an arc has a stroke width, 1 by default, part of its value', () {
    const ArcPrimitive plain = ArcPrimitive('a', ChartPoint(5, 5), 5, 0, 0, 90);
    expect(plain.strokeWidth, 1);
    const ArcPrimitive thick = ArcPrimitive(
      'a',
      ChartPoint(5, 5),
      5,
      0,
      0,
      90,
      strokeWidth: 3,
    );
    expect(thick.strokeWidth, 3);
    expect(thick, isNot(plain));
    expect(thick.hashCode, isNot(plain.hashCode));
    expect(
      thick,
      const ArcPrimitive('a', ChartPoint(5, 5), 5, 0, 0, 90, strokeWidth: 3),
    );
    expect(
      thick.hashCode,
      const ArcPrimitive(
        'a',
        ChartPoint(5, 5),
        5,
        0,
        0,
        90,
        strokeWidth: 3,
      ).hashCode,
    );
  });

  test('an exhaustive switch over ChartPrimitive compiles', () {
    expect(kindOf(const RectPrimitive('r', a)), 'rect');
    expect(kindOf(PathPrimitive('p', const <ChartPoint>[])), 'path');
    expect(
      kindOf(const ArcPrimitive('a', ChartPoint(0, 0), 1, 0, 0, 360)),
      'arc',
    );
    expect(kindOf(TextPrimitive('t', '', a, style())), 'text');
    expect(kindOf(ClipPrimitive('c', a, const <ChartPrimitive>[])), 'clip');
  });

  test('text corners turn about the centre', () {
    final TextPrimitive turned = TextPrimitive(
      't',
      'x',
      const ChartRect(0, 0, 20, 10),
      style(),
      rotationDegrees: 90,
    );
    final ChartRect b = turned.bounds;
    expect(b.left, closeTo(5, 1e-9));
    expect(b.top, closeTo(-5, 1e-9));
    expect(b.width, closeTo(10, 1e-9));
    expect(b.height, closeTo(20, 1e-9));
    expect(turned.corners.length, 4);
    // Top left of the box goes to the top right after a quarter turn.
    expect(turned.corners[0].x, closeTo(15, 1e-9));
    expect(turned.corners[0].y, closeTo(-5, 1e-9));
  });

  test('text bounds at 0 degrees are the rect', () {
    final TextPrimitive t = TextPrimitive(
      't',
      'x',
      const ChartRect(3, 4, 20, 10),
      style(),
    );
    expect(t.bounds, const ChartRect(3, 4, 20, 10));
    expect(t.corners, const <ChartPoint>[
      ChartPoint(3, 4),
      ChartPoint(23, 4),
      ChartPoint(23, 14),
      ChartPoint(3, 14),
    ]);
  });

  group('PathPrimitive.fillOpacity', () {
    const List<ChartPoint> points = <ChartPoint>[ChartPoint(0, 0)];

    test('defaults to 1', () {
      expect(PathPrimitive('p', points).fillOpacity, 1);
    });

    test('changes == and hashCode', () {
      final PathPrimitive a = PathPrimitive('p', points);
      final PathPrimitive b = PathPrimitive('p', points, fillOpacity: 0.5);
      expect(a, isNot(b));
      expect(a.hashCode, isNot(b.hashCode));
      expect(b, PathPrimitive('p', points, fillOpacity: 0.5));
    });

    test('must be above 0, at most 1 and finite', () {
      for (final double bad in <double>[
        0,
        1.5,
        -0.1,
        double.nan,
        double.infinity,
      ]) {
        expect(
          () => PathPrimitive('p', points, fillOpacity: bad),
          throwsArgumentError,
          reason: '$bad',
        );
      }
      expect(PathPrimitive('p', points, fillOpacity: 0.1).fillOpacity, 0.1);
      expect(PathPrimitive('p', points, fillOpacity: 1).fillOpacity, 1);
    });
  });
}
