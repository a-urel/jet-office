// JetChart's keyboard navigation, focus ring and per-point screen reader
// nodes.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart'
    show DebugSemanticsDumpOrder, SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';
import 'package:jet_charts_flutter/src/chart_semantics.dart'
    show FocusRingPainter;
import 'package:jet_charts_flutter/src/jet_chart.dart' show JetChartState;
import 'package:jet_charts_flutter/src/tooltip_view.dart' show TooltipView;

import 'support/charts.dart';

Chart _golden(String name) => goldenCharts()
    .firstWhere(((String, Chart, ChartSize) g) => g.$1 == name)
    .$2;

ChartSeries _series(String name, List<Object> categories, List<double?> v) =>
    ChartSeries(
      name: ChartData<String>(values: <String?>[name]),
      categories: ChartData<Object>(values: categories),
      values: ChartData<double>(values: v),
    );

/// A column chart of 2 series by 3 categories.
Chart _columns() => Chart(
  kind: ChartKind.column,
  series: <ChartSeries>[
    _series('North', <Object>['Q1', 'Q2', 'Q3'], <double?>[12, 18, 7]),
    _series('South', <Object>['Q1', 'Q2', 'Q3'], <double?>[9, 11, 14]),
  ],
);

/// [children] in a `WidgetsApp` (no `MaterialApp`), each in a 360 by 240
/// box, one under the other.
Widget _app(List<Widget> children) => WidgetsApp(
  color: const Color(0xFF000000),
  debugShowCheckedModeBanner: false,
  // With no navigator, nothing holds the focus at first: an autofocused
  // scope does, as a page route's does in an app.
  builder: (BuildContext context, Widget? child) => FocusScope(
    autofocus: true,
    child: Align(
      alignment: Alignment.topLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final Widget c in children)
            SizedBox(width: 360, height: 240, child: c),
        ],
      ),
    ),
  ),
);

JetChartState _state(WidgetTester tester) =>
    tester.state<JetChartState>(find.byType(JetChart).first);

ChartTooltip? _shown(WidgetTester tester) {
  final Finder box = find.byType(TooltipView);
  return box.evaluate().isEmpty
      ? null
      : tester.widget<TooltipView>(box).tooltip;
}

ChartTooltip _expectedFor(WidgetTester tester, Chart chart, String id) =>
    chartTooltipFor(
      chart,
      _state(tester).currentLayout!,
      id,
      theme: ChartTheme.office,
    )!;

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

/// The children of [node], in order.
List<SemanticsNode> _children(SemanticsNode node) =>
    node.debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder);

SemanticsNode _chartNode(WidgetTester tester, String start) =>
    tester.getSemantics(find.bySemanticsLabel(RegExp('^$start')));

void main() {
  group('keyboard', () {
    testWidgets('tab focuses the chart and the arrows walk its points', (
      WidgetTester tester,
    ) async {
      final Chart chart = _columns();
      await tester.pumpWidget(_app(<Widget>[JetChart(chart: chart)]));
      expect(_shown(tester), isNull);
      await _key(tester, LogicalKeyboardKey.tab);
      expect(_state(tester).hasFocus, isTrue);
      expect(_shown(tester), isNull);

      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(_shown(tester), _expectedFor(tester, chart, 'series/0/bar/0'));
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(_shown(tester), _expectedFor(tester, chart, 'series/0/bar/1'));
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(_shown(tester), _expectedFor(tester, chart, 'series/0/bar/2'));
      // Series-major: series 0's last point is followed by series 1's first.
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(_shown(tester), _expectedFor(tester, chart, 'series/1/bar/0'));
      await _key(tester, LogicalKeyboardKey.arrowLeft);
      expect(_shown(tester), _expectedFor(tester, chart, 'series/0/bar/2'));
      await _key(tester, LogicalKeyboardKey.arrowUp);
      expect(_shown(tester), _expectedFor(tester, chart, 'series/0/bar/1'));

      await _key(tester, LogicalKeyboardKey.end);
      expect(_shown(tester), _expectedFor(tester, chart, 'series/1/bar/2'));
      // The last point stays the last.
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(_shown(tester), _expectedFor(tester, chart, 'series/1/bar/2'));
      await _key(tester, LogicalKeyboardKey.home);
      expect(_shown(tester), _expectedFor(tester, chart, 'series/0/bar/0'));

      await _key(tester, LogicalKeyboardKey.escape);
      expect(_shown(tester), isNull);
      expect(find.byType(CustomPaint).evaluate().where(_isRing), isEmpty);
    });

    testWidgets('left from no point goes to the last one', (
      WidgetTester tester,
    ) async {
      final Chart chart = _columns();
      await tester.pumpWidget(_app(<Widget>[JetChart(chart: chart)]));
      await _key(tester, LogicalKeyboardKey.tab);
      await _key(tester, LogicalKeyboardKey.arrowLeft);
      expect(_shown(tester), _expectedFor(tester, chart, 'series/1/bar/2'));
    });

    testWidgets('a ring in the axis label colour marks the focused point', (
      WidgetTester tester,
    ) async {
      final Chart chart = _columns();
      await tester.pumpWidget(_app(<Widget>[JetChart(chart: chart)]));
      await _key(tester, LogicalKeyboardKey.tab);
      expect(find.byType(CustomPaint).evaluate().where(_isRing), isEmpty);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      final FocusRingPainter ring = _ring(tester);
      final RectPrimitive bar = _state(tester).currentLayout!.primitives
          .expand(_flat)
          .whereType<RectPrimitive>()
          .firstWhere((RectPrimitive p) => p.id == 'series/0/bar/0');
      final Rect bounds = Rect.fromLTWH(
        bar.rect.left,
        bar.rect.top,
        bar.rect.width,
        bar.rect.height,
      );
      expect(ring.rect.contains(bounds.topLeft), isTrue);
      expect(
        ring.rect.contains(bounds.bottomRight - const Offset(1, 1)),
        isTrue,
      );
      expect(ring.rect.center.dx, closeTo(bounds.center.dx, 0.01));
      expect(
        ring.color,
        Color(0xFF000000 | ChartTheme.office.axisLabels.color.rgb),
      );
      expect(ring.strokeWidth, 1.5);
    });

    testWidgets('the box sits by the focused point centre', (
      WidgetTester tester,
    ) async {
      final Chart chart = _columns();
      await tester.pumpWidget(_app(<Widget>[JetChart(chart: chart)]));
      await _key(tester, LogicalKeyboardKey.tab);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      final Rect ring = _ring(tester).rect;
      final Offset box = tester.getTopLeft(find.byType(TooltipView));
      expect(box.dx, closeTo(ring.center.dx + 12, 0.5));
    });

    testWidgets('focus leaving closes the box', (WidgetTester tester) async {
      final FocusNode other = FocusNode();
      addTearDown(other.dispose);
      await tester.pumpWidget(
        _app(<Widget>[
          JetChart(chart: _columns()),
          Focus(focusNode: other, child: const SizedBox()),
        ]),
      );
      await _key(tester, LogicalKeyboardKey.tab);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(_shown(tester), isNotNull);
      other.requestFocus();
      // The focus moves in a microtask after this frame; the next one shows
      // its result.
      await tester.pump();
      await tester.pump();
      expect(other.hasFocus, isTrue);
      expect(_shown(tester), isNull);
      expect(find.byType(CustomPaint).evaluate().where(_isRing), isEmpty);
    });

    testWidgets('focusable false is skipped by tab', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(<Widget>[
          JetChart(chart: _columns(), focusable: false),
          JetChart(chart: _columns()),
        ]),
      );
      await _key(tester, LogicalKeyboardKey.tab);
      final List<JetChartState> states = tester
          .stateList<JetChartState>(find.byType(JetChart))
          .toList();
      expect(states[0].hasFocus, isFalse);
      expect(states[1].hasFocus, isTrue);
    });

    testWidgets('a given focus node is used', (WidgetTester tester) async {
      final FocusNode node = FocusNode();
      addTearDown(node.dispose);
      final Chart chart = _columns();
      await tester.pumpWidget(
        _app(<Widget>[JetChart(chart: chart, focusNode: node)]),
      );
      node.requestFocus();
      await tester.pump();
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(_shown(tester), _expectedFor(tester, chart, 'series/0/bar/0'));
    });

    testWidgets('a new layout keeps the focused point by its id', (
      WidgetTester tester,
    ) async {
      final Chart chart = _columns();
      await tester.pumpWidget(_app(<Widget>[JetChart(chart: chart)]));
      await _key(tester, LogicalKeyboardKey.tab);
      await _key(tester, LogicalKeyboardKey.end);
      final Chart changed = Chart(
        kind: ChartKind.column,
        series: <ChartSeries>[
          ...chart.series.take(1),
          _series('South', <Object>['Q1', 'Q2', 'Q3'], <double?>[9, 11, 20]),
        ],
      );
      await tester.pumpWidget(_app(<Widget>[JetChart(chart: changed)]));
      expect(_shown(tester), _expectedFor(tester, changed, 'series/1/bar/2'));
      expect(_shown(tester)!.rows.single.value, '20');
      // The point is gone: the focus on a point ends.
      await tester.pumpWidget(
        _app(<Widget>[
          JetChart(
            chart: Chart(
              kind: ChartKind.column,
              series: chart.series.take(1).toList(),
            ),
          ),
        ]),
      );
      expect(_shown(tester), isNull);
      expect(find.byType(CustomPaint).evaluate().where(_isRing), isEmpty);
      await tester.pumpAndSettle();
    });

    testWidgets('with tooltips off only the ring shows', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(<Widget>[JetChart(chart: _columns(), tooltips: false)]),
      );
      await _key(tester, LogicalKeyboardKey.tab);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(_shown(tester), isNull);
      expect(find.byType(CustomPaint).evaluate().where(_isRing), hasLength(1));
    });

    /// Walks [chart] in [theme] from Home to End and expects each step to
    /// show its category band's tooltip, every series in it.
    Future<void> expectBands(
      WidgetTester tester,
      Chart chart, {
      ChartTheme? theme,
    }) async {
      await tester.pumpWidget(
        _app(<Widget>[JetChart(chart: chart, theme: theme)]),
      );
      await _key(tester, LogicalKeyboardKey.tab);
      final ChartLayout layout = _state(tester).currentLayout!;
      final int count = layout.categoryBands.length;
      expect(count, greaterThan(1));
      for (int i = 0; i < count; i++) {
        await _key(
          tester,
          i == 0 ? LogicalKeyboardKey.home : LogicalKeyboardKey.arrowRight,
        );
        final ChartTooltip expected = chartTooltipFor(
          chart,
          layout,
          'axis/category/label/$i',
          theme: theme ?? ChartTheme.office,
        )!;
        final ChartTooltip shown = _shown(tester)!;
        expect(shown.title, expected.title);
        expect(shown.rows, expected.rows);
        final ChartRect band = layout.categoryBands[i];
        expect(
          _ring(tester).rect.center.dx,
          closeTo(band.left + band.width / 2, 0.01),
        );
      }
      // The last band stays the last.
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(
        _shown(tester)!.title,
        chartTooltipFor(
          chart,
          layout,
          'axis/category/label/${count - 1}',
          theme: theme ?? ChartTheme.office,
        )!.title,
      );
    }

    testWidgets('an area chart walks its bands', (WidgetTester tester) async {
      await expectBands(tester, _golden('area_stacked'));
    });

    testWidgets('a line with markers walks its bands', (
      WidgetTester tester,
    ) async {
      final Chart chart = _golden('line_smooth');
      await expectBands(tester, chart);
      expect(
        _state(tester).currentLayout!.primitives
            .expand(_flat)
            .any((ChartPrimitive p) => p.id.contains('/marker/')),
        isTrue,
      );
    });

    testWidgets('a line with lineMarkers off walks its bands', (
      WidgetTester tester,
    ) async {
      await expectBands(
        tester,
        _golden('line_smooth'),
        theme: ChartTheme.office.copyWith(lineMarkers: false),
      );
    });

    testWidgets('a combination chart walks its bands, columns included', (
      WidgetTester tester,
    ) async {
      final Chart chart = _golden('combo_column_line');
      await expectBands(tester, chart);
      expect(_shown(tester)!.rows, hasLength(chart.series.length));
    });

    testWidgets('a donut walks the slices of its first series', (
      WidgetTester tester,
    ) async {
      final Chart chart = Chart(
        kind: ChartKind.donut,
        series: <ChartSeries>[
          _series('Inner', <Object>['a', 'b'], <double?>[1, 3]),
          _series('Outer', <Object>['a', 'b'], <double?>[2, 2]),
        ],
      );
      await tester.pumpWidget(_app(<Widget>[JetChart(chart: chart)]));
      await _key(tester, LogicalKeyboardKey.tab);
      await _key(tester, LogicalKeyboardKey.end);
      expect(_shown(tester), _expectedFor(tester, chart, 'series/0/slice/1'));
    });

    testWidgets('the ring holds a pie slice', (WidgetTester tester) async {
      final Chart chart = _golden('pie_basic');
      await tester.pumpWidget(_app(<Widget>[JetChart(chart: chart)]));
      await _key(tester, LogicalKeyboardKey.tab);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      final ArcPrimitive slice = _state(tester).currentLayout!.primitives
          .expand(_flat)
          .whereType<ArcPrimitive>()
          .firstWhere((ArcPrimitive p) => p.id == 'series/0/slice/0');
      final Rect ring = _ring(tester).rect;
      // Points along the slice's outline, at every degree of its sweep and
      // its centre side, all lie inside the ring.
      final int steps = slice.sweepAngle.abs().ceil();
      for (int i = 0; i <= steps; i++) {
        final double a =
            (slice.startAngle + slice.sweepAngle * i / steps) * math.pi / 180;
        for (final double r in <double>[slice.innerRadius, slice.radius]) {
          final Offset p = Offset(
            slice.center.x + r * math.cos(a),
            slice.center.y + r * math.sin(a),
          );
          expect(ring.inflate(0.01).contains(p), isTrue, reason: '$p');
        }
      }
      // And the ring is tight: within its margin of the outline's extremes.
      double top = double.infinity;
      for (int i = 0; i <= steps; i++) {
        final double a =
            (slice.startAngle + slice.sweepAngle * i / steps) * math.pi / 180;
        top = math.min(top, slice.center.y + slice.radius * math.sin(a));
        top = math.min(top, slice.center.y);
      }
      expect(ring.top, closeTo(math.max(top - 1.75, 0.75), 0.05));
    });

    testWidgets('a pie walks its slices', (WidgetTester tester) async {
      final Chart chart = _golden('pie_basic');
      await tester.pumpWidget(_app(<Widget>[JetChart(chart: chart)]));
      await _key(tester, LogicalKeyboardKey.tab);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(_shown(tester), _expectedFor(tester, chart, 'series/0/slice/0'));
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(_shown(tester), _expectedFor(tester, chart, 'series/0/slice/1'));
    });

    testWidgets('a sparkline walks its bands', (WidgetTester tester) async {
      final Chart chart = _golden('sparkline_area');
      await tester.pumpWidget(_app(<Widget>[JetChart(chart: chart)]));
      await _key(tester, LogicalKeyboardKey.tab);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      final ChartTooltip? tip = _shown(tester);
      expect(tip, isNotNull);
      final ChartSummary summary = summarizeChart(chart);
      expect(tip!.rows, hasLength(chart.series.length));
      expect(tip.rows.single.value, summary.values.first.first);
      await _key(tester, LogicalKeyboardKey.end);
      expect(_shown(tester)!.rows.single.value, summary.values.first.last);
    });
  });

  group('screen reader nodes', () {
    testWidgets('a column chart has a node per category', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final Chart chart = _columns();
      await tester.pumpWidget(_app(<Widget>[JetChart(chart: chart)]));
      final SemanticsNode node = _chartNode(tester, 'Column chart');
      expect(node.label, JetChartStrings.en.describe(summarizeChart(chart)));
      final List<SemanticsNode> children = _children(node);
      expect(children.map((SemanticsNode n) => n.label), <String>[
        'Q1: North 12, South 9',
        'Q2: North 18, South 11',
        'Q3: North 7, South 14',
      ]);
      final List<ChartRect> bands = _state(tester).currentLayout!.categoryBands;
      for (int i = 0; i < 3; i++) {
        final SemanticsNode child = children[i];
        final Offset at = MatrixUtils.transformPoint(
          child.transform ?? Matrix4.identity(),
          child.rect.topLeft,
        );
        expect(at.dx, closeTo(bands[i].left, 0.01));
        expect(child.rect.width, closeTo(bands[i].width, 0.01));
      }
      handle.dispose();
    });

    testWidgets('a donut has a node per slice with its share', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final Chart chart = _golden('donut_center');
      await tester.pumpWidget(_app(<Widget>[JetChart(chart: chart)]));
      final List<SemanticsNode> children = _children(
        _chartNode(tester, 'Donut chart'),
      );
      expect(children, hasLength(5));
      expect(children[1].label, 'Güney: Satış 18 (40%)');
      handle.dispose();
    });

    testWidgets('a scatter chart has a node per marker', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final Chart chart = _golden('scatter_basic');
      await tester.pumpWidget(_app(<Widget>[JetChart(chart: chart)]));
      final List<SemanticsNode> children = _children(
        _chartNode(tester, 'Scatter chart'),
      );
      final int points = chart.series.fold<int>(
        0,
        (int n, ChartSeries s) =>
            n + s.values.values.where((double? v) => v != null).length,
      );
      expect(children, hasLength(points));
      expect(
        children.first.label,
        startsWith('${summarizeChart(chart).seriesNames.first}: X '),
      );
      handle.dispose();
    });

    testWidgets('no node while loading', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(<Widget>[JetChart(chart: _columns(), loading: true)]),
      );
      expect(find.bySemanticsLabel(RegExp('^Q1')), findsNothing);
      handle.dispose();
    });

    testWidgets('a line of 300 categories has no point node', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final List<Object> days = <Object>[for (int i = 1; i <= 300; i++) 'D$i'];
      final Chart chart = Chart(
        kind: ChartKind.line,
        series: <ChartSeries>[
          _series('Visits', days, <double?>[
            for (int i = 0; i < 300; i++) i * 1,
          ]),
        ],
      );
      await tester.pumpWidget(_app(<Widget>[JetChart(chart: chart)]));
      expect(_children(_chartNode(tester, 'Line chart')), isEmpty);
      expect(JetChartStrings.maxPointNodes, 200);
      handle.dispose();
    });
  });
}

/// Every primitive of [p], a clip's children included.
Iterable<ChartPrimitive> _flat(ChartPrimitive p) sync* {
  yield p;
  if (p is ClipPrimitive) {
    yield* p.children.expand(_flat);
  }
}

bool _isRing(Element e) =>
    (e.widget as CustomPaint).painter is FocusRingPainter;

FocusRingPainter _ring(WidgetTester tester) =>
    (find.byType(CustomPaint).evaluate().firstWhere(_isRing).widget
                as CustomPaint)
            .painter!
        as FocusRingPainter;
