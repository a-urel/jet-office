// JetChart: its size, its layout cache, its states and its semantics.
library;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';
import 'package:jet_charts_flutter/src/jet_chart.dart' show JetChartState;
import 'package:jet_core/jet_core.dart';

import 'support/charts.dart';

Chart _chart(String name) => goldenCharts()
    .firstWhere(((String, Chart, ChartSize) g) => g.$1 == name)
    .$2;

Widget _app(Widget child, {TextScaler textScaler = TextScaler.noScaling}) =>
    MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    );

JetChartState _state(WidgetTester tester) =>
    tester.state<JetChartState>(find.byType(JetChart));

Chart _nullChart() => Chart(
  kind: ChartKind.column,
  title: const ChartTitle(text: 'Nothing yet'),
  series: <ChartSeries>[
    ChartSeries(
      name: ChartData<String>(values: <String?>['North']),
      categories: ChartData<Object>(values: <Object?>['Q1', 'Q2']),
      values: ChartData<double>(values: <double?>[null, null]),
    ),
  ],
);

void main() {
  group('size', () {
    testWidgets('a bounded width with an unbounded height keeps 0.6', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Center(
            child: SizedBox(
              width: 400,
              child: Column(
                children: <Widget>[JetChart(chart: _chart('column_clustered'))],
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(JetChart)), const Size(400, 240));
      expect(tester.takeException(), isNull);
    });

    testWidgets('both sides unbounded, in a Row in a Column, is 360 by 216', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Column(
            children: <Widget>[
              Row(
                children: <Widget>[JetChart(chart: _chart('column_clustered'))],
              ),
            ],
          ),
        ),
      );
      expect(tester.getSize(find.byType(JetChart)), const Size(360, 216));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unbounded width beside a bounded height keeps 0.6', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 216,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[JetChart(chart: _chart('column_clustered'))],
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(JetChart)), const Size(360, 216));
      await tester.pumpWidget(
        _app(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 216,
              child: Row(
                children: <Widget>[JetChart(chart: _chart('column_clustered'))],
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(JetChart)), const Size(360, 216));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a zero size paints and throws nothing', (
      WidgetTester tester,
    ) async {
      for (final Widget chart in <Widget>[
        JetChart(chart: _chart('column_clustered')),
        const JetChart(loading: true),
        const JetChart(),
        JetChart(error: StateError('x')),
      ]) {
        await tester.pumpWidget(
          _app(Center(child: SizedBox(width: 0, height: 0, child: chart))),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.getSize(find.byType(JetChart)), Size.zero);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('layout cache', () {
    testWidgets('a new width relayouts once', (WidgetTester tester) async {
      Widget sized(double width) => _app(
        Center(
          child: SizedBox(
            width: width,
            height: 200,
            child: JetChart(chart: _chart('column_clustered')),
          ),
        ),
      );
      await tester.pumpWidget(sized(300));
      final JetChartState state = _state(tester);
      expect(state.layoutCount, 1);
      expect(state.currentLayout!.size, const ChartSize(300, 200));
      await tester.pumpWidget(sized(600));
      expect(state.layoutCount, 2);
      expect(state.currentLayout!.size, const ChartSize(600, 200));
      await tester.pump();
      expect(state.layoutCount, 2);
    });

    testWidgets('an equal chart, theme and size reuse the layout', (
      WidgetTester tester,
    ) async {
      Widget build() => _app(
        Center(
          child: SizedBox(
            width: 360,
            height: 240,
            child: JetChart(
              chart: _chart('column_clustered'),
              theme: robotoTheme(ChartTheme.office),
            ),
          ),
        ),
      );
      await tester.pumpWidget(build());
      final JetChartState state = _state(tester);
      final ChartLayout first = state.currentLayout!;
      await tester.pumpWidget(build());
      expect(state.layoutCount, 1);
      expect(identical(state.currentLayout, first), isTrue);
    });

    testWidgets('a larger text scale gives larger text without overlap', (
      WidgetTester tester,
    ) async {
      Widget build(double scale) => _app(
        Center(
          child: SizedBox(
            width: 360,
            height: 240,
            child: JetChart(chart: _chart('column_clustered')),
          ),
        ),
        textScaler: TextScaler.linear(scale),
      );
      double labelHeight(ChartLayout layout) => layout.primitives
          .whereType<TextPrimitive>()
          .firstWhere((TextPrimitive t) => t.text == 'Q1')
          .rect
          .height;

      await tester.pumpWidget(build(1));
      final JetChartState state = _state(tester);
      final double normal = labelHeight(state.currentLayout!);
      await tester.pumpWidget(build(2));
      expect(state.layoutCount, 2);
      final ChartLayout large = state.currentLayout!;
      expect(labelHeight(large), greaterThan(normal * 1.8));
      expect(findOverlaps(large.primitives, large.size), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('states', () {
    testWidgets('loading shows the loading text to a screen reader', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_app(const JetChart(loading: true)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.bySemanticsLabel('Loading chart…'), findsOneWidget);
      expect(_state(tester).currentLayout, isNull);
    });

    testWidgets('loading does not animate when animations are disabled', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: JetChart(loading: true),
        ),
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('an error shows the error text and never the error', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          JetChart(
            chart: _chart('column_clustered'),
            loading: true,
            error: StateError('x'),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('The chart could not be shown'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('x')), findsNothing);
      expect(find.bySemanticsLabel(RegExp('StateError')), findsNothing);
    });

    testWidgets('a chart of only null values is empty, with its title', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_app(JetChart(chart: _nullChart())));
      expect(find.bySemanticsLabel(RegExp('No data')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Nothing yet')), findsOneWidget);
      expect(_state(tester).currentLayout, isNull);
    });

    testWidgets('no chart is empty, in the strings given', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(const JetChart(strings: JetChartStrings.tr)),
      );
      expect(find.bySemanticsLabel('Veri yok'), findsOneWidget);
    });

    testWidgets('a pie chart shows the placeholder, not empty', (
      WidgetTester tester,
    ) async {
      final Chart pie = Chart(
        kind: ChartKind.pie,
        series: _chart('column_clustered').series.take(1).toList(),
      );
      await tester.pumpWidget(_app(JetChart(chart: pie)));
      expect(find.bySemanticsLabel(RegExp('No data')), findsNothing);
      expect(find.bySemanticsLabel(RegExp('^Pie chart')), findsOneWidget);
      final ChartLayout layout = _state(tester).currentLayout!;
      expect(
        layout.primitives.whereType<TextPrimitive>().map(
          (TextPrimitive t) => t.text,
        ),
        contains('pie'),
      );
    });

    testWidgets('custom builders replace each look', (
      WidgetTester tester,
    ) async {
      final List<Object> errors = <Object>[];
      Widget build({bool loading = false, Object? error, Chart? chart}) => _app(
        JetChart(
          chart: chart,
          loading: loading,
          error: error,
          loadingBuilder: (BuildContext context, ChartTheme theme) =>
              const SizedBox(key: Key('loading')),
          emptyBuilder: (BuildContext context, ChartTheme theme) =>
              const SizedBox(key: Key('empty')),
          errorBuilder: (BuildContext context, ChartTheme theme, Object error) {
            errors.add(error);
            return const SizedBox(key: Key('error'));
          },
        ),
      );
      await tester.pumpWidget(build(loading: true));
      expect(find.byKey(const Key('loading')), findsOneWidget);
      expect(find.bySemanticsLabel('Loading chart…'), findsNothing);
      await tester.pumpWidget(build());
      expect(find.byKey(const Key('empty')), findsOneWidget);
      await tester.pumpWidget(build(chart: _nullChart()));
      expect(find.byKey(const Key('empty')), findsOneWidget);
      final StateError error = StateError('x');
      await tester.pumpWidget(build(error: error));
      expect(find.byKey(const Key('error')), findsOneWidget);
      expect(errors.last, same(error));
      await tester.pumpWidget(build(chart: _chart('column_clustered')));
      expect(find.byKey(const Key('error')), findsNothing);
      expect(_state(tester).currentLayout, isNotNull);
    });

    testWidgets('the theme is ChartTheme.office when none is given', (
      WidgetTester tester,
    ) async {
      ChartTheme? seen;
      await tester.pumpWidget(
        _app(
          JetChart(
            emptyBuilder: (BuildContext context, ChartTheme theme) {
              seen = theme;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, ChartTheme.office);
    });
  });

  group('semantics', () {
    testWidgets('the chart describes its series and categories', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(JetChart(chart: _chart('column_clustered'))),
      );
      final SemanticsNode node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('North')),
      );
      expect(node.label, contains('South'));
      expect(node.label, contains('West'));
      expect(node.label, contains('Q1'));
      expect(
        node.label,
        JetChartStrings.en.describe(summarizeChart(_chart('column_clustered'))),
      );
    });

    testWidgets('semanticsLabel replaces the first sentence', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          JetChart(
            chart: _chart('column_clustered'),
            semanticsLabel: 'Quarterly sales.',
          ),
        ),
      );
      final SemanticsNode node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('North')),
      );
      expect(node.label, startsWith('Quarterly sales. Series (3): North'));
      expect(node.label, isNot(contains('Column chart')));
    });

    testWidgets('the locale formats the described numbers', (
      WidgetTester tester,
    ) async {
      final Chart chart = Chart(
        kind: ChartKind.line,
        series: <ChartSeries>[
          ChartSeries(
            name: ChartData<String>(values: <String?>['Rate']),
            categories: ChartData<Object>(values: <Object?>['a']),
            values: ChartData<double>(values: <double?>[1.5]),
          ),
        ],
      );
      await tester.pumpWidget(
        _app(
          JetChart(
            chart: chart,
            locale: FormatLocale.trTR,
            strings: JetChartStrings.tr,
          ),
        ),
      );
      expect(find.bySemanticsLabel(RegExp('Rate: a 1,5')), findsOneWidget);
    });
  });
}
