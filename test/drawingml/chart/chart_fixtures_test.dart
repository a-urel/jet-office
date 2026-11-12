import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/drawingml/chart/chart_space.dart';
import 'package:jet_office/src/drawingml/chart/chart_writer.dart';
import 'package:jet_office/src/xlsx/chart.dart'
    show xlsxChartIds, xlsxChartPartIds;
import 'package:jet_office/src/xml/xml_equivalence.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../../fixtures/c1_fixtures.dart';
import '../../fixtures/c2_fixtures.dart';
import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';

/// The charts of every chart fixture, in part order.
List<C1Chart> _charts(String name) =>
    name.startsWith('c1_') ? c1Charts(name) : c2Charts(name);

/// Every chart the sheets of [book] list, in sheet order.
List<XlsxSheetChart> _listed(XlsxWorkbook book) => <XlsxSheetChart>[
  for (final XlsxSheet sheet in book.sheets) ...sheet.charts,
];

/// Whether [chart] has no axes, so its typed ids carry the default axis ids.
bool _axisless(Chart chart) =>
    chart.kind == ChartKind.pie || chart.kind == ChartKind.donut;

/// [chart] with each series in the colour [theme] gives it, as a part
/// written with fixed colours holds them: plain RGB, bound to no slot.
Chart _fixedColours(Chart chart, ChartTheme theme) => chart.copyWith(
  series: <ChartSeries>[
    for (final (int i, ChartSeries s) in chart.series.indexed)
      s.copyWith(color: ChartColor.rgb(theme.colorOf(s, i).rgb)),
  ],
);

/// Whether [chart]'s part holds a secondary axis pair: a series is bound to
/// it. A part without one does not hold the secondary ids.
bool _secondary(Chart chart) =>
    chart.series.any((ChartSeries s) => s.axis == ChartAxisBinding.secondary);

void main() {
  test('the C1 fixtures are c1_kinds and c1_options', () {
    expect(
      <String>[for (final Fixture f in c1Fixtures()) f.name],
      <String>['c1_kinds', 'c1_options'],
    );
    expect(c1Charts('c1_kinds'), hasLength(12));
    expect(c1Charts('c1_options'), hasLength(6));
  });

  test('the C2 fixtures are c2_kinds and c2_data', () {
    expect(
      <String>[for (final Fixture f in c2Fixtures()) f.name],
      <String>['c2_kinds', 'c2_data'],
    );
    expect(
      <ChartKind>[
        for (final C1Chart c in c2Charts('c2_kinds')) c.space.chart.kind,
      ],
      <ChartKind>[
        ChartKind.pie,
        ChartKind.donut,
        ChartKind.scatter,
        ChartKind.combination,
        ChartKind.combination,
        ChartKind.combination,
        ChartKind.line,
      ],
    );
    expect(() => c2Charts('c1_kinds'), throwsArgumentError);
  });

  test('each C1 part is the one the C1 host wrote', () {
    // The ids C1 gave chart i (0-based, part i + 1): the axes 100000 + 2i
    // and 100001 + 2i, series s {00000000-00C1-0000-<i>-<s>}.
    for (final Fixture fixture in c1Fixtures()) {
      final List<C1Chart> charts = c1Charts(fixture.name);
      final Map<String, Uint8List> parts = readXlsxBytes(fixture.build());
      for (int i = 0; i < charts.length; i++) {
        final DrawingChartIds ids = charts[i].space.ids;
        expect(ids.categoryAxis, 100000 + 2 * i);
        expect(ids.valueAxis, 100001 + 2 * i);
        expect(ids.series, <String>[
          for (int s = 0; s < ids.series.length; s++)
            '{00000000-00C1-0000-${i.toString().padLeft(4, '0')}-'
                '${s.toString().padLeft(12, '0')}}',
        ]);
        expect(
          parts['xl/charts/chart${i + 1}.xml'],
          writeDrawingChartSpace(charts[i].space, charts[i].theme).bytes,
          reason: '${fixture.name} chart ${i + 1}',
        );
      }
    }
  });

  test('each C2 part has the ids its part number gives', () {
    for (final Fixture fixture in c2Fixtures()) {
      final List<C1Chart> charts = c2Charts(fixture.name);
      for (int i = 0; i < charts.length; i++) {
        final Chart chart = charts[i].space.chart;
        expect(
          charts[i].space.ids,
          xlsxChartPartIds(i + 1, chart.series.length),
          reason: '${fixture.name} chart ${i + 1}',
        );
      }
    }
  });

  for (final Fixture fixture in <Fixture>[...c1Fixtures(), ...c2Fixtures()]) {
    group(fixture.name, () {
      final List<C1Chart> charts = _charts(fixture.name);

      test('builds without a warning', () {
        expect(fixture.warnings(), isEmpty);
      });

      test('every chart writes without an issue', () {
        for (final C1Chart chart in charts) {
          expect(
            writeDrawingChartSpace(chart.space, chart.theme).issues,
            isEmpty,
          );
        }
      });

      test('its chart parts are the charts written', () {
        final Map<String, Uint8List> parts = readXlsxBytes(fixture.build());
        for (int i = 0; i < charts.length; i++) {
          final Uint8List? part = parts['xl/charts/chart${i + 1}.xml'];
          expect(part, isNotNull, reason: 'chart ${i + 1}');
          expect(
            xmlDifference(
              part!,
              writeDrawingChartSpace(charts[i].space, charts[i].theme).bytes,
            ),
            isNull,
            reason: 'chart ${i + 1}',
          );
        }
        expect(parts['xl/charts/chart${charts.length + 1}.xml'], isNull);
      });

      test('its charts list typed, with their ids', () {
        final XlsxWorkbook book = XlsxWorkbook.open(fixture.build());
        final List<XlsxSheetChart> listed = _listed(book);
        expect(listed, hasLength(charts.length));
        for (int i = 0; i < charts.length; i++) {
          final DrawingChartSpace space = charts[i].space;
          final String reason = 'chart ${i + 1}';
          final XlsxChart? typed = listed[i].typed;
          if (charts[i].theme != ChartTheme.office) {
            // An app theme's fixed colours read back as the series' own, and
            // read in the Office theme they may not give the part again: the
            // view is what counts.
            expect(
              listed[i].view,
              _fixedColours(space.chart, charts[i].theme),
              reason: reason,
            );
            continue;
          }
          expect(listed[i].view, space.chart, reason: reason);
          expect(typed, isNotNull, reason: reason);
          expect(typed!.chart, space.chart, reason: reason);
          expect(typed.language, space.language, reason: reason);
          expect(typed.autoTitle, space.autoTitle, reason: reason);
          final DrawingChartIds ids = xlsxChartIds(typed)!;
          expect(ids.series, space.ids.series, reason: reason);
          if (!_axisless(space.chart)) {
            expect(ids.categoryAxis, space.ids.categoryAxis, reason: reason);
            expect(ids.valueAxis, space.ids.valueAxis, reason: reason);
          }
          if (_secondary(space.chart)) {
            expect(
              ids.secondaryCategoryAxis,
              space.ids.secondaryCategoryAxis,
              reason: reason,
            );
            expect(
              ids.secondaryValueAxis,
              space.ids.secondaryValueAxis,
              reason: reason,
            );
          }
        }
        expect(book.warnings, isEmpty);
      });

      test('the drawing holds one graphic frame per chart', () {
        final Map<String, String> parts = readXlsx(fixture.build());
        int frames = 0;
        for (final MapEntry<String, String> p in parts.entries) {
          if (!RegExp(r'^xl/drawings/drawing\d+\.xml$').hasMatch(p.key)) {
            continue;
          }
          frames += XmlDocument.parse(
            p.value,
          ).findAllElements('xdr:graphicFrame').length;
        }
        expect(frames, charts.length);
        expect(
          parts['[Content_Types].xml'],
          contains(
            '<Override PartName="/xl/charts/chart1.xml" '
            'ContentType="$drawingChartContentType"/>',
          ),
        );
      });
    });
  }
}
