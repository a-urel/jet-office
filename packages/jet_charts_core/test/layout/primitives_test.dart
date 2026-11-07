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
}
