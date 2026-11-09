// JetChart's hover, touch and tooltip box.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';
import 'package:jet_charts_flutter/src/interaction.dart'
    show mouseTolerance, touchTolerance;
import 'package:jet_charts_flutter/src/jet_chart.dart' show JetChartState;
import 'package:jet_charts_flutter/src/tooltip_view.dart'
    show TooltipView, tooltipOrigin;

import 'support/charts.dart';

Chart _chart(String name) => goldenCharts()
    .firstWhere(((String, Chart, ChartSize) g) => g.$1 == name)
    .$2;

/// Where the chart's top left corner sits on the test surface.
const Offset _origin = Offset(100, 100);

/// [chart] at [_origin] in a box of [size], under a tap region surface, and
/// under an [Overlay] when [overlay].
Widget _app(
  Widget chart, {
  Size size = const Size(360, 240),
  bool overlay = false,
}) {
  // The page behind the chart takes taps, as an app's page does, so a tap
  // beside the chart reaches the tap region surface.
  final Widget placed = ColoredBox(
    color: const Color(0xFFFFFFFF),
    child: Padding(
      padding: EdgeInsets.only(left: _origin.dx, top: _origin.dy),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: size.width, height: size.height, child: chart),
      ),
    ),
  );
  return MediaQuery(
    data: const MediaQueryData(),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: TapRegionSurface(
        child: overlay
            ? Overlay(
                initialEntries: <OverlayEntry>[
                  OverlayEntry(builder: (BuildContext context) => placed),
                ],
              )
            : placed,
      ),
    ),
  );
}

JetChartState _state(WidgetTester tester) =>
    tester.state<JetChartState>(find.byType(JetChart));

/// Every primitive of [primitives], clips' children included.
Iterable<ChartPrimitive> _flat(List<ChartPrimitive> primitives) sync* {
  for (final ChartPrimitive p in primitives) {
    yield p;
    if (p is ClipPrimitive) {
      yield* _flat(p.children);
    }
  }
}

/// The centre of the primitive [id] of the current layout, on the surface.
Offset _centreOf(WidgetTester tester, String id) {
  final ChartRect rect =
      (_flat(
                _state(tester).currentLayout!.primitives,
              ).firstWhere((ChartPrimitive p) => p.id == id)
              as RectPrimitive)
          .rect;
  return _origin +
      Offset(rect.left + rect.width / 2, rect.top + rect.height / 2);
}

Finder _inBox(String text) =>
    find.descendant(of: find.byType(TooltipView), matching: find.text(text));

Future<TestGesture> _mouse(WidgetTester tester) async {
  final TestGesture gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
  );
  await gesture.addPointer(location: const Offset(1, 1));
  addTearDown(gesture.removePointer);
  return gesture;
}

/// The tooltip [chart]'s current layout has at the surface point [pointer].
ChartTooltip? _expectedAt(
  WidgetTester tester,
  Chart chart,
  Offset pointer, {
  required double tolerance,
  ChartTheme? theme,
}) {
  final Offset local = pointer - _origin;
  return chartTooltipAt(
    chart,
    _state(tester).currentLayout!,
    ChartPoint(local.dx, local.dy),
    theme: theme ?? ChartTheme.office,
    tolerance: tolerance,
  );
}

/// Expects no box when [expected] is `null`, else a box of its title and
/// rows.
void _expectBox(WidgetTester tester, ChartTooltip? expected) {
  if (expected == null) {
    expect(find.byType(TooltipView), findsNothing);
    return;
  }
  expect(
    tester.widget<TooltipView>(find.byType(TooltipView)).tooltip,
    expected,
  );
  if (expected.title case final String title) {
    expect(_inBox(title), findsOneWidget);
  }
  for (final ChartTooltipRow row in expected.rows) {
    expect(_inBox(row.label), findsOneWidget);
    expect(_inBox(row.value), findsOneWidget);
  }
}

void main() {
  group('JetChartHit', () {
    test('is a value', () {
      final ChartElementId element = ChartElementId.parse('series/1/bar/2')!;
      expect(
        JetChartHit(
          id: 'series/1/bar/2',
          element: element,
          position: const Offset(1, 2),
        ),
        JetChartHit(
          id: 'series/1/bar/2',
          element: ChartElementId.parse('series/1/bar/2'),
          position: const Offset(1, 2),
        ),
      );
      expect(
        const JetChartHit(id: 'plot', position: Offset(1, 2)),
        isNot(const JetChartHit(id: 'plot', position: Offset(1, 3))),
      );
      expect(
        const JetChartHit(id: 'plot', position: Offset(1, 2)).hashCode,
        const JetChartHit(id: 'plot', position: Offset(1, 2)).hashCode,
      );
    });
  });

  group('hover', () {
    testWidgets('over a bar shows its point and reports the hit', (
      WidgetTester tester,
    ) async {
      final List<JetChartHit?> hovers = <JetChartHit?>[];
      await tester.pumpWidget(
        _app(JetChart(chart: _chart('column_clustered'), onHover: hovers.add)),
      );
      final TestGesture mouse = await _mouse(tester);
      await mouse.moveTo(_centreOf(tester, 'series/1/bar/2'));
      await tester.pump();

      expect(find.byType(TooltipView), findsOneWidget);
      expect(_inBox('Q3'), findsOneWidget);
      expect(_inBox('South'), findsOneWidget);
      expect(_inBox('14'), findsOneWidget);
      final JetChartHit hit = hovers.last!;
      expect(hit.id, 'series/1/bar/2');
      expect(hit.element!.kind, ChartElementKind.bar);
      expect(hit.element!.series, 1);
      expect(hit.element!.category, 2);
      expect(hit.tooltip!.title, 'Q3');
      expect(hit.position, _centreOf(tester, 'series/1/bar/2') - _origin);

      await mouse.moveTo(const Offset(700, 560));
      await tester.pump();
      expect(hovers.last, isNull);
      expect(find.byType(TooltipView), findsNothing);
    });

    testWidgets('the box carries its text in a live region', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(JetChart(chart: _chart('column_clustered'))),
      );
      final TestGesture mouse = await _mouse(tester);
      await mouse.moveTo(_centreOf(tester, 'series/1/bar/2'));
      await tester.pump();
      final SemanticsNode node = tester.getSemantics(find.byType(TooltipView));
      expect(node.flagsCollection.isLiveRegion, isTrue);
      expect(node.label, contains('Q3'));
      expect(node.label, contains('South'));
      expect(node.label, contains('14'));
      handle.dispose();
    });

    testWidgets('tooltips: false keeps the callback and shows no box', (
      WidgetTester tester,
    ) async {
      final List<JetChartHit?> hovers = <JetChartHit?>[];
      await tester.pumpWidget(
        _app(
          JetChart(
            chart: _chart('column_clustered'),
            tooltips: false,
            onHover: hovers.add,
          ),
        ),
      );
      final TestGesture mouse = await _mouse(tester);
      await mouse.moveTo(_centreOf(tester, 'series/1/bar/2'));
      await tester.pump();
      expect(find.byType(TooltipView), findsNothing);
      expect(hovers.last!.id, 'series/1/bar/2');
      expect(hovers.last!.tooltip!.title, 'Q3');
    });

    testWidgets('near the right edge the box is left of the pointer', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(JetChart(chart: _chart('column_clustered'))),
      );
      final TestGesture mouse = await _mouse(tester);
      final Offset right = _centreOf(tester, 'series/2/bar/3');
      await mouse.moveTo(right);
      await tester.pump();
      expect(_inBox('West'), findsOneWidget);
      expect(
        tester.getRect(find.byType(TooltipView)).right,
        lessThan(right.dx),
      );

      final Offset left = _centreOf(tester, 'series/0/bar/0');
      await mouse.moveTo(left);
      await tester.pump();
      expect(_inBox('North'), findsOneWidget);
      final Rect box = tester.getRect(find.byType(TooltipView));
      expect(box.left, moreOrLessEquals(left.dx + 12));
      expect(box.top, moreOrLessEquals(left.dy + 12));
    });
  });

  group('touch', () {
    testWidgets('a tap shows the box; a tap on empty space or outside '
        'closes it', (WidgetTester tester) async {
      final List<JetChartHit> taps = <JetChartHit>[];
      await tester.pumpWidget(
        _app(JetChart(chart: _chart('column_clustered'), onTap: taps.add)),
      );
      final Offset bar = _centreOf(tester, 'series/1/bar/2');
      await tester.tapAt(bar);
      await tester.pump();
      expect(_inBox('South'), findsOneWidget);
      expect(taps.last.id, 'series/1/bar/2');
      expect(taps.last.element!.series, 1);

      // The background's corner: nothing there has a tooltip.
      await tester.tapAt(_origin + const Offset(2, 2));
      await tester.pump();
      expect(find.byType(TooltipView), findsNothing);
      expect(taps.last.id, 'background');

      await tester.tapAt(bar);
      await tester.pump();
      expect(_inBox('South'), findsOneWidget);
      await tester.tapAt(const Offset(760, 580));
      await tester.pump();
      expect(find.byType(TooltipView), findsNothing);
    });

    testWidgets('a tappable parent keeps its taps', (
      WidgetTester tester,
    ) async {
      int parentTaps = 0;
      await tester.pumpWidget(
        _app(
          GestureDetector(
            onTap: () => parentTaps++,
            child: JetChart(chart: _chart('column_clustered')),
          ),
        ),
      );
      await tester.tapAt(_centreOf(tester, 'series/1/bar/2'));
      await tester.pump();
      expect(_inBox('South'), findsOneWidget);
      expect(parentTaps, 1);
    });

    testWidgets('a drag past the touch slop does not toggle the box', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(JetChart(chart: _chart('column_clustered'))),
      );
      final Offset bar = _centreOf(tester, 'series/1/bar/2');
      final TestGesture finger = await tester.startGesture(bar);
      await finger.moveBy(const Offset(0, 40));
      await finger.up();
      await tester.pump();
      expect(find.byType(TooltipView), findsNothing);
    });

    testWidgets('tooltips: false keeps onTap and shows no box', (
      WidgetTester tester,
    ) async {
      final List<JetChartHit> taps = <JetChartHit>[];
      await tester.pumpWidget(
        _app(
          JetChart(
            chart: _chart('column_clustered'),
            tooltips: false,
            onTap: taps.add,
          ),
        ),
      );
      await tester.tapAt(_centreOf(tester, 'series/1/bar/2'));
      await tester.pump();
      expect(find.byType(TooltipView), findsNothing);
      expect(taps.single.tooltip!.rows.single.label, 'South');
    });
  });

  group('placement', () {
    const Size tile = Size(160, 100);

    Future<Rect> boxAtPlotCentre(
      WidgetTester tester, {
      required bool overlay,
    }) async {
      await tester.pumpWidget(
        _app(
          JetChart(chart: _chart('column_clustered')),
          size: tile,
          overlay: overlay,
        ),
      );
      final ChartRect plot = _state(tester).currentLayout!.plotArea!;
      final TestGesture mouse = await _mouse(tester);
      await mouse.moveTo(
        _origin +
            Offset(plot.left + plot.width / 2, plot.top + plot.height / 2),
      );
      await tester.pump();
      expect(find.byType(TooltipView), findsOneWidget);
      return tester.getRect(find.byType(TooltipView));
    }

    testWidgets('under an Overlay the box may leave a small tile', (
      WidgetTester tester,
    ) async {
      final Rect box = await boxAtPlotCentre(tester, overlay: true);
      final Rect chart = _origin & tile;
      expect(
        box.left < chart.left - 0.5 || box.top < chart.top - 0.5,
        isTrue,
        reason: '$box inside $chart',
      );
    });

    testWidgets('without an Overlay the box stays inside the tile', (
      WidgetTester tester,
    ) async {
      final Rect box = await boxAtPlotCentre(tester, overlay: false);
      final Rect chart = (_origin & tile).inflate(0.01);
      expect(chart.contains(box.topLeft), isTrue, reason: '$box');
      expect(chart.contains(box.bottomRight), isTrue, reason: '$box');
    });

    test('tooltipOrigin flips and clamps', () {
      const Rect chart = Rect.fromLTWH(0, 0, 200, 100);
      expect(
        tooltipOrigin(
          pointer: const Offset(10, 10),
          box: const Size(50, 30),
          chart: chart,
          bounds: chart,
        ),
        const Offset(22, 22),
      );
      expect(
        tooltipOrigin(
          pointer: const Offset(190, 90),
          box: const Size(50, 30),
          chart: chart,
          bounds: chart,
        ),
        const Offset(128, 48),
      );
      // Flipped past the chart's left edge: clamped into the bounds.
      expect(
        tooltipOrigin(
          pointer: const Offset(60, 80),
          box: const Size(150, 30),
          chart: chart,
          bounds: chart,
        ),
        const Offset(0, 38),
      );
      expect(
        tooltipOrigin(
          pointer: const Offset(100, 50),
          box: const Size(150, 60),
          chart: chart,
          bounds: const Rect.fromLTWH(-500, -500, 1000, 1000),
        ),
        const Offset(-62, -22),
      );
      // A box larger than the bounds starts at their top left corner.
      expect(
        tooltipOrigin(
          pointer: const Offset(100, 50),
          box: const Size(300, 200),
          chart: chart,
          bounds: chart,
        ),
        Offset.zero,
      );
    });
  });

  group('changes while the box shows', () {
    testWidgets('a chart of one series shows what the new layout has at '
        'the pointer', (WidgetTester tester) async {
      final Chart chart = _chart('column_clustered');
      await tester.pumpWidget(_app(JetChart(chart: chart)));
      final TestGesture mouse = await _mouse(tester);
      final Offset pointer = _centreOf(tester, 'series/1/bar/2');
      await mouse.moveTo(pointer);
      await tester.pump();
      expect(_inBox('South'), findsOneWidget);

      final Chart one = Chart(
        kind: ChartKind.column,
        series: <ChartSeries>[chart.series.first],
      );
      await tester.pumpWidget(_app(JetChart(chart: one)));
      expect(tester.takeException(), isNull);
      // No new hover: the box is what the new layout has at the pointer.
      _expectBox(
        tester,
        _expectedAt(tester, one, pointer, tolerance: mouseTolerance),
      );
      expect(_inBox('South'), findsNothing);

      // The pointer moves on: the box follows the new layout.
      await mouse.moveTo(_centreOf(tester, 'series/0/bar/2'));
      await tester.pump();
      expect(_inBox('North'), findsOneWidget);
    });

    testWidgets('a tapped box is recomputed for the new chart', (
      WidgetTester tester,
    ) async {
      final Chart chart = _chart('column_clustered');
      await tester.pumpWidget(_app(JetChart(chart: chart)));
      final Offset pointer = _centreOf(tester, 'series/1/bar/2');
      await tester.tapAt(pointer);
      await tester.pump();
      expect(_inBox('South'), findsOneWidget);
      expect(_inBox('14'), findsOneWidget);

      // Same chart, new values: the same pointer gives the new value.
      final Chart changed = Chart(
        kind: ChartKind.column,
        title: chart.title,
        series: <ChartSeries>[
          for (final ChartSeries s in chart.series)
            ChartSeries(
              name: s.name,
              categories: s.categories,
              values: ChartData<double>(
                values: <double?>[
                  for (final double? v in s.values.values)
                    v == null ? null : v + 0.5,
                ],
              ),
            ),
        ],
      );
      await tester.pumpWidget(_app(JetChart(chart: changed)));
      expect(tester.takeException(), isNull);
      final ChartTooltip? expected = _expectedAt(
        tester,
        changed,
        pointer,
        tolerance: touchTolerance,
      );
      expect(expected, isNotNull);
      expect(expected!.rows.single.value, '14.5');
      _expectBox(tester, expected);

      await tester.pumpWidget(_app(const JetChart()));
      expect(tester.takeException(), isNull);
      expect(find.byType(TooltipView), findsNothing);
    });

    testWidgets('a new theme refreshes the open box', (
      WidgetTester tester,
    ) async {
      final Chart chart = _chart('column_clustered');
      await tester.pumpWidget(_app(JetChart(chart: chart)));
      final TestGesture mouse = await _mouse(tester);
      final Offset pointer = _centreOf(tester, 'series/1/bar/2');
      await mouse.moveTo(pointer);
      await tester.pump();
      expect(_inBox('South'), findsOneWidget);
      final ChartLayout before = _state(tester).currentLayout!;

      final ChartTheme theme = ChartTheme.office.copyWith(
        spacing: ChartSpacing(padding: 30),
        tooltip: ChartTheme.office.tooltip.copyWith(padding: 10),
      );
      await tester.pumpWidget(_app(JetChart(chart: chart, theme: theme)));
      expect(tester.takeException(), isNull);
      expect(_state(tester).currentLayout, isNot(before));
      _expectBox(
        tester,
        _expectedAt(
          tester,
          chart,
          pointer,
          tolerance: mouseTolerance,
          theme: theme,
        ),
      );
      if (find.byType(TooltipView).evaluate().isNotEmpty) {
        expect(
          tester.widget<TooltipView>(find.byType(TooltipView)).style,
          theme.tooltip,
        );
      }
    });
  });
}
