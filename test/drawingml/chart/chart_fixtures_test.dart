import 'dart:typed_data';

import 'package:jet_office/src/drawingml/chart/chart_reader.dart';
import 'package:jet_office/src/drawingml/chart/chart_space.dart';
import 'package:jet_office/src/drawingml/chart/chart_writer.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import '../../fixtures/c1_fixtures.dart';
import '../../fixtures/fixtures.dart';
import '../../support/read_xlsx.dart';
import '../../support/xlsx_checker.dart';
import 'support/chart_host.dart';

void main() {
  test('the C1 fixtures are c1_kinds and c1_options', () {
    expect(
      <String>[for (final Fixture f in c1Fixtures()) f.name],
      <String>['c1_kinds', 'c1_options'],
    );
    expect(c1Charts('c1_kinds'), hasLength(12));
  });

  for (final Fixture fixture in c1Fixtures()) {
    group(fixture.name, () {
      final List<C1Chart> charts = c1Charts(fixture.name);

      test('every chart writes without an issue', () {
        for (final C1Chart chart in charts) {
          expect(
            writeDrawingChartSpace(chart.space, chart.theme).issues,
            isEmpty,
          );
        }
      });

      test('its chart parts read back typed and equal what was written', () {
        final Map<String, Uint8List> parts = readXlsxBytes(fixture.build());
        for (int i = 0; i < charts.length; i++) {
          final Uint8List? part = parts['xl/charts/chart${i + 1}.xml'];
          expect(part, isNotNull, reason: 'chart ${i + 1}');
          expect(
            part,
            writeDrawingChartSpace(charts[i].space, charts[i].theme).bytes,
          );
          final DrawingChartRead read = readDrawingChartSpace(
            part!,
            theme: charts[i].theme,
          );
          expect(read.issues, isEmpty, reason: 'chart ${i + 1}');
          expect(read.chart, charts[i].space.chart, reason: 'chart ${i + 1}');
          expect(read.typed, charts[i].space, reason: 'chart ${i + 1}');
        }
        expect(parts['xl/charts/chart${charts.length + 1}.xml'], isNull);
      });

      test('the drawing holds one graphic frame per chart', () {
        final Map<String, String> parts = readXlsx(fixture.build());
        final XmlDocument drawing = XmlDocument.parse(
          parts['xl/drawings/drawing1.xml']!,
        );
        expect(
          drawing.findAllElements('xdr:graphicFrame'),
          hasLength(charts.length),
        );
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

  group('withCharts', () {
    test('puts the drawing before the parts that follow it', () {
      final Fixture tables = allFixtures().firstWhere(
        (Fixture f) => f.name == 'm4_tables',
      );
      final C1Chart chart = c1Charts('c1_kinds').first;
      final Uint8List bytes = withCharts(tables.build(), 'Sales', <Uint8List>[
        writeDrawingChartSpace(chart.space, chart.theme).bytes,
      ]);
      expect(checkXlsx(bytes), isEmpty);
      final String sheet = readXlsx(bytes)['xl/worksheets/sheet1.xml']!;
      expect(sheet, contains(RegExp(r'<drawing r:id="rId\d+"/><tableParts')));
    });

    test('refuses a sheet it does not know', () {
      expect(
        () => withCharts(c1Fixtures().first.build(), 'Nope', <Uint8List>[]),
        throwsArgumentError,
      );
    });
  });
}
