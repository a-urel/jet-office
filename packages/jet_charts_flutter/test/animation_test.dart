// The light animation of marks on data change: lerpChartPrimitives and the
// JetChart widget's animation.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';
import 'package:jet_charts_flutter/src/animation.dart';
import 'package:jet_charts_flutter/src/jet_chart.dart' show JetChartState;
import 'package:jet_charts_flutter/src/tooltip_view.dart' show TooltipView;
import 'package:jet_core/jet_core.dart';

const List<String> _quarters = <String>['Q1', 'Q2', 'Q3', 'Q4', 'Q5'];

/// A one-series chart of [kind] over the first `values.length` quarters,
/// with data labels when [labels].
Chart _chart(
  List<double> values, {
  ChartKind kind = ChartKind.column,
  bool labels = false,
}) => Chart(
  kind: kind,
  title: const ChartTitle(text: 'Sales'),
  series: <ChartSeries>[
    ChartSeries(
      name: ChartData<String>(values: <String?>['North']),
      categories: ChartData<Object>(
        values: _quarters.take(values.length).toList(),
      ),
      values: ChartData<double>(values: values),
    ),
  ],
  dataLabels: ChartDataLabels(visible: labels),
);

ChartLayout _layout(
  Chart chart, {
  ChartSize size = const ChartSize(360, 240),
}) => layoutChart(
  chart,
  theme: ChartTheme.office,
  size: size,
  measurer: FlutterTextMeasurer(),
);

/// Every primitive of [primitives], clips' children included.
Iterable<ChartPrimitive> _flat(List<ChartPrimitive> primitives) sync* {
  for (final ChartPrimitive p in primitives) {
    yield p;
    if (p is ClipPrimitive) {
      yield* _flat(p.children);
    }
  }
}

ChartPrimitive? _find(List<ChartPrimitive> primitives, String id) {
  for (final ChartPrimitive p in _flat(primitives)) {
    if (p.id == id) {
      return p;
    }
  }
  return null;
}

ChartRect _bar(
  List<ChartPrimitive> primitives, [
  String id = 'series/0/bar/0',
]) => (_find(primitives, id)! as RectPrimitive).rect;

Widget _app(
  Widget child, {
  bool disableAnimations = false,
  TextScaler textScaler = TextScaler.noScaling,
}) => MediaQuery(
  data: MediaQueryData(
    disableAnimations: disableAnimations,
    textScaler: textScaler,
  ),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  ),
);

Widget _sized(
  Chart chart, {
  double width = 360,
  FormatLocale locale = FormatLocale.enUS,
}) => SizedBox(
  width: width,
  height: 240,
  child: JetChart(chart: chart, locale: locale),
);

/// A column chart of [count] series over four quarters.
Chart _series(int count, {double scale = 1}) => Chart(
  kind: ChartKind.column,
  title: const ChartTitle(text: 'Sales'),
  series: <ChartSeries>[
    for (int s = 0; s < count; s++)
      ChartSeries(
        name: ChartData<String>(values: <String?>['Series $s']),
        categories: ChartData<Object>(values: _quarters.take(4).toList()),
        values: ChartData<double>(
          values: <double?>[
            for (int c = 0; c < 4; c++) (10 + 7 * s + 3 * c) * scale,
          ],
        ),
      ),
  ],
);

JetChartState _state(WidgetTester tester) =>
    tester.state<JetChartState>(find.byType(JetChart));

/// The painted primitives equal the target layout's.
void _showsTarget(WidgetTester tester) {
  expect(_painted(tester), _state(tester).currentLayout!.primitives);
}

/// The primitives the chart paints now.
List<ChartPrimitive> _painted(WidgetTester tester) {
  final CustomPaint paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(JetChart),
      matching: find.byWidgetPredicate(
        (Widget w) => w is CustomPaint && w.painter is ChartLayoutPainter,
      ),
    ),
  );
  return (paint.painter! as ChartLayoutPainter).primitives;
}

void main() {
  group('lerpChartPrimitives', () {
    test('puts a bar halfway at 0.5', () {
      final ChartLayout from = _layout(_chart(<double>[10, 20, 30, 40]));
      final ChartLayout to = _layout(_chart(<double>[30, 20, 10, 5]));
      final List<ChartPrimitive> half = lerpChartPrimitives(
        from.primitives,
        to.primitives,
        0.5,
      );
      final ChartRect a = _bar(from.primitives);
      final ChartRect b = _bar(to.primitives);
      final ChartRect m = _bar(half);
      expect(a.top, isNot(closeTo(b.top, 1)));
      expect(m.top, closeTo((a.top + b.top) / 2, 1e-9));
      expect(m.height, closeTo((a.height + b.height) / 2, 1e-9));
      expect(m.left, closeTo((a.left + b.left) / 2, 1e-9));
      expect(m.width, closeTo((a.width + b.width) / 2, 1e-9));
    });

    test('a line whose point count changed takes the new line', () {
      final ChartLayout from = _layout(
        _chart(<double>[1, 2, 3, 4], kind: ChartKind.line),
      );
      final ChartLayout to = _layout(
        _chart(<double>[4, 3, 2, 1, 5], kind: ChartKind.line),
      );
      final List<ChartPrimitive> half = lerpChartPrimitives(
        from.primitives,
        to.primitives,
        0.5,
      );
      expect(
        _find(half, 'series/0/line/0'),
        _find(to.primitives, 'series/0/line/0'),
      );
    });

    test('a line with the same point count moves point by point', () {
      final ChartLayout from = _layout(
        _chart(<double>[1, 2, 3, 4], kind: ChartKind.line),
      );
      final ChartLayout to = _layout(
        _chart(<double>[4, 3, 2, 1], kind: ChartKind.line),
      );
      final PathPrimitive a =
          _find(from.primitives, 'series/0/line/0')! as PathPrimitive;
      final PathPrimitive b =
          _find(to.primitives, 'series/0/line/0')! as PathPrimitive;
      final PathPrimitive m =
          _find(
                lerpChartPrimitives(from.primitives, to.primitives, 0.25),
                'series/0/line/0',
              )!
              as PathPrimitive;
      for (int i = 0; i < m.points.length; i++) {
        expect(
          m.points[i].y,
          closeTo(a.points[i].y + (b.points[i].y - a.points[i].y) * 0.25, 1e-9),
        );
      }
      expect(m.stroke, b.stroke);
    });

    test('a data label is absent at 0.5 and present at 1', () {
      final ChartLayout from = _layout(
        _chart(<double>[10, 20, 30, 40], labels: true),
      );
      final ChartLayout to = _layout(
        _chart(<double>[30, 20, 10, 5], labels: true),
      );
      expect(_find(to.primitives, 'label/0/0'), isNotNull);
      final List<ChartPrimitive> half = lerpChartPrimitives(
        from.primitives,
        to.primitives,
        0.5,
      );
      expect(
        _flat(half).where(
          (ChartPrimitive p) =>
              ChartElementId.parse(p.id)?.kind == ChartElementKind.dataLabel,
        ),
        isEmpty,
      );
      expect(
        _find(
          lerpChartPrimitives(from.primitives, to.primitives, 1),
          'label/0/0',
        ),
        _find(to.primitives, 'label/0/0'),
      );
    });

    test('text and grid lines come from to at 0.5', () {
      final ChartLayout from = _layout(_chart(<double>[10, 20, 30, 40]));
      final ChartLayout to = _layout(_chart(<double>[300, 200, 100, 50]));
      final List<ChartPrimitive> half = lerpChartPrimitives(
        from.primitives,
        to.primitives,
        0.5,
      );
      for (final ChartPrimitive p in _flat(to.primitives)) {
        final ChartElementKind? kind = ChartElementId.parse(p.id)?.kind;
        if (p is TextPrimitive || kind == ChartElementKind.gridLine) {
          expect(_find(half, p.id), p, reason: p.id);
        }
      }
    });

    test('t = 1 returns to, and t is clamped', () {
      final ChartLayout from = _layout(_chart(<double>[10, 20, 30, 40]));
      final ChartLayout to = _layout(
        _chart(<double>[30, 20, 10, 5], labels: true),
      );
      expect(lerpChartPrimitives(from.primitives, to.primitives, 1), <Object>[
        ...to.primitives,
      ]);
      expect(lerpChartPrimitives(from.primitives, to.primitives, 3), <Object>[
        ...to.primitives,
      ]);
      expect(
        _bar(lerpChartPrimitives(from.primitives, to.primitives, -1)),
        _bar(from.primitives),
      );
    });

    test('clips recurse by id', () {
      const ChartRect clipA = ChartRect(0, 0, 100, 100);
      const ChartRect clipB = ChartRect(0, 0, 120, 100);
      const ChartRect a = ChartRect(10, 50, 20, 50);
      const ChartRect b = ChartRect(10, 20, 20, 80);
      final List<ChartPrimitive> from = <ChartPrimitive>[
        ClipPrimitive('plot/clip', clipA, <ChartPrimitive>[
          const RectPrimitive('series/0/bar/0', a),
          const RectPrimitive('label/0/0', a),
        ]),
      ];
      final List<ChartPrimitive> to = <ChartPrimitive>[
        ClipPrimitive('plot/clip', clipB, <ChartPrimitive>[
          const RectPrimitive('series/0/bar/0', b),
          const RectPrimitive('series/0/bar/1', b),
          const RectPrimitive('label/0/0', b),
        ]),
        ClipPrimitive('other/clip', clipB, <ChartPrimitive>[
          const RectPrimitive('series/1/bar/0', a),
          const RectPrimitive('label/1/0', a),
        ]),
      ];
      final List<ChartPrimitive> half = lerpChartPrimitives(from, to, 0.5);
      expect(half, <ChartPrimitive>[
        ClipPrimitive('plot/clip', clipB, <ChartPrimitive>[
          const RectPrimitive('series/0/bar/0', ChartRect(10, 35, 20, 65)),
          const RectPrimitive('series/0/bar/1', b),
        ]),
        ClipPrimitive('other/clip', clipB, <ChartPrimitive>[
          const RectPrimitive('series/1/bar/0', a),
        ]),
      ]);
    });

    test('a mark only in to shows; one only in from is dropped', () {
      final ChartLayout from = _layout(_chart(<double>[10, 20, 30]));
      final ChartLayout to = _layout(_chart(<double>[10, 20, 30, 40]));
      final List<ChartPrimitive> half = lerpChartPrimitives(
        from.primitives,
        to.primitives,
        0.5,
      );
      expect(
        _find(half, 'series/0/bar/3'),
        _find(to.primitives, 'series/0/bar/3'),
      );
      final List<ChartPrimitive> back = lerpChartPrimitives(
        to.primitives,
        from.primitives,
        0.5,
      );
      expect(_find(back, 'series/0/bar/3'), isNull);
    });
  });

  group('JetChart', () {
    final Chart before = _chart(<double>[10, 20, 30, 40]);
    final Chart after = _chart(<double>[30, 20, 10, 5]);

    testWidgets('a data change animates over animationDuration', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_app(_sized(before)));
      final ChartRect start = _bar(_painted(tester));
      await tester.pumpWidget(_app(_sized(after)));
      expect(_bar(_painted(tester)), start);
      await tester.pump(const Duration(milliseconds: 150));
      final ChartRect middle = _bar(_painted(tester));
      final ChartRect end = _bar(_layout(after).primitives);
      expect(middle.top, lessThan(start.top));
      expect(middle.top, greaterThan(end.top));
      await tester.pump(const Duration(milliseconds: 150));
      expect(_bar(_painted(tester)), end);
      // The controller finishes on the frame after it reaches 1.
      await tester.pump(const Duration(milliseconds: 16));
      expect(_bar(_painted(tester)), end);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('disabled animations show the new layout at once', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_app(_sized(before), disableAnimations: true));
      await tester.pumpWidget(_app(_sized(after), disableAnimations: true));
      expect(_bar(_painted(tester)), _bar(_layout(after).primitives));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a zero animationDuration shows the new layout at once', (
      WidgetTester tester,
    ) async {
      Widget chart(Chart c) => _app(
        SizedBox(
          width: 360,
          height: 240,
          child: JetChart(chart: c, animationDuration: Duration.zero),
        ),
      );
      await tester.pumpWidget(chart(before));
      await tester.pumpWidget(chart(after));
      expect(_bar(_painted(tester)), _bar(_layout(after).primitives));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a change during an animation starts from the screen', (
      WidgetTester tester,
    ) async {
      final Chart third = _chart(<double>[5, 20, 30, 40]);
      await tester.pumpWidget(_app(_sized(before)));
      await tester.pumpWidget(_app(_sized(after)));
      await tester.pump(const Duration(milliseconds: 150));
      final ChartRect onScreen = _bar(_painted(tester));
      await tester.pumpWidget(_app(_sized(third)));
      expect(_bar(_painted(tester)), onScreen);
      final ChartRect target = _bar(_layout(third).primitives);
      await tester.pump(const Duration(milliseconds: 16));
      final ChartRect next = _bar(_painted(tester));
      // A frame later it has moved a little from there towards the target.
      expect(next.top, greaterThan(onScreen.top));
      expect(next.top, lessThan(target.top));
      expect(
        next.top - onScreen.top,
        lessThan((target.top - onScreen.top) * 0.2),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(_bar(_painted(tester)), _bar(_layout(third).primitives));
    });

    testWidgets('the first build does not animate', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_app(_sized(after)));
      expect(_bar(_painted(tester)), _bar(_layout(after).primitives));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a resize does not animate', (WidgetTester tester) async {
      await tester.pumpWidget(_app(_sized(before)));
      await tester.pumpWidget(_app(_sized(before, width: 300)));
      expect(
        _bar(_painted(tester)),
        _bar(_layout(before, size: const ChartSize(300, 240)).primitives),
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a data change with a resize does not animate', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_app(_sized(before)));
      await tester.pumpWidget(_app(_sized(after, width: 300)));
      expect(
        _bar(_painted(tester)),
        _bar(_layout(after, size: const ChartSize(300, 240)).primitives),
      );
    });

    testWidgets('hit testing uses the new layout during an animation', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_app(_sized(before)));
      await tester.pumpWidget(_app(_sized(after)));
      await tester.pump(const Duration(milliseconds: 150));
      final JetChartState state = tester.state(find.byType(JetChart));
      expect(state.currentLayout, _layout(after));
      await tester.pumpAndSettle();
    });

    testWidgets('a swap to fewer series mid-animation ends on that chart', (
      WidgetTester tester,
    ) async {
      final Chart three = _series(3);
      final Chart one = _series(1, scale: 2);
      await tester.pumpWidget(_app(_sized(three)));
      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      final ChartRect bar = _bar(
        _state(tester).currentLayout!.primitives,
        'series/2/bar/1',
      );
      final Offset origin = tester.getTopLeft(find.byType(JetChart));
      final Offset local = Offset(
        bar.left + bar.width / 2,
        bar.top + bar.height / 2,
      );
      await mouse.moveTo(origin + local);
      await tester.pump();
      expect(find.byType(TooltipView), findsOneWidget);
      await tester.pumpWidget(_app(_sized(_series(3, scale: 3))));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpWidget(_app(_sized(one)));
      expect(tester.takeException(), isNull);
      final ChartLayout target = _state(tester).currentLayout!;
      expect(target, _layout(one));
      expect(_find(_painted(tester), 'series/2/bar/1'), isNull);
      final ChartTooltip? expected = chartTooltipAt(
        one,
        target,
        ChartPoint(local.dx, local.dy),
        theme: ChartTheme.office,
        tolerance: 2,
      );
      if (expected == null) {
        expect(find.byType(TooltipView), findsNothing);
      } else {
        expect(
          tester.widget<TooltipView>(find.byType(TooltipView)).tooltip,
          expected,
        );
      }
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 150));
      _showsTarget(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
    });

    testWidgets('a swap to an empty chart mid-animation stops it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_app(_sized(before)));
      await tester.pumpWidget(_app(_sized(after)));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpWidget(
        _app(const SizedBox(width: 360, height: 240, child: JetChart())),
      );
      expect(find.bySemanticsLabel(JetChartStrings.en.empty), findsOneWidget);
      expect(_state(tester).currentLayout, isNull);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an error mid-animation stops it', (WidgetTester tester) async {
      await tester.pumpWidget(_app(_sized(before)));
      await tester.pumpWidget(_app(_sized(after)));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 360,
            height: 240,
            child: JetChart(chart: after, error: StateError('x')),
          ),
        ),
      );
      expect(_state(tester).currentLayout, isNull);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('reduced motion turned on mid-animation shows the target', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_app(_sized(before)));
      await tester.pumpWidget(_app(_sized(after)));
      await tester.pump(const Duration(milliseconds: 150));
      expect(_painted(tester), isNot(_layout(after).primitives));
      await tester.pumpWidget(_app(_sized(after), disableAnimations: true));
      _showsTarget(tester);
      expect(_state(tester).currentLayout, _layout(after));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('a text scale change mid-animation shows the new target', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_app(_sized(before)));
      await tester.pumpWidget(_app(_sized(after)));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpWidget(
        _app(_sized(after), textScaler: const TextScaler.linear(1.5)),
      );
      _showsTarget(tester);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('a locale change mid-animation shows the new target', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_app(_sized(before)));
      await tester.pumpWidget(_app(_sized(after)));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpWidget(_app(_sized(after, locale: FormatLocale.deDE)));
      _showsTarget(tester);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('a theme change mid-animation shows the new target', (
      WidgetTester tester,
    ) async {
      Widget themed(Chart c, ChartTheme theme) => _app(
        SizedBox(
          width: 360,
          height: 240,
          child: JetChart(chart: c, theme: theme),
        ),
      );
      await tester.pumpWidget(themed(before, ChartTheme.office));
      await tester.pumpWidget(themed(after, ChartTheme.office));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpWidget(
        themed(
          after,
          ChartTheme.office.copyWith(
            axisLabels: ChartTheme.office.axisLabels.copyWith(
              fontFamily: 'Roboto',
            ),
          ),
        ),
      );
      _showsTarget(tester);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
