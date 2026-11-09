import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_office/src/drawingml/chart/chart_part.dart';
import 'package:jet_office/src/drawingml/chart/chart_reader.dart';
import 'package:jet_office/src/drawingml/chart/chart_space.dart';
import 'package:jet_office/src/drawingml/chart/chart_writer.dart';
import 'package:jet_office/src/opc/package.dart';
import 'package:test/test.dart';

import 'support/excel_charts.dart';

final ChartTheme _office = ChartTheme.office;

DrawingChartSpace _space(ChartKind kind) => DrawingChartSpace(
  chart: Chart(
    kind: kind,
    series: <ChartSeries>[
      ChartSeries(
        name: ChartData<String>(values: const <String?>[]),
        categories: ChartData<Object>(
          values: const <Object?>['A', 'B'],
          reference: r'S!$A$1:$A$2',
        ),
        values: ChartData<double>(
          values: const <double?>[1, 2],
          reference: r'S!$B$1:$B$2',
        ),
      ),
    ],
  ),
);

Uint8List _joined(PartContent c) =>
    Uint8List.fromList(c.encode().expand((Uint8List b) => b).toList());

void main() {
  group('opened', () {
    test("an Excel chart encodes to the file's bytes", () {
      final Uint8List bytes = Uint8List.fromList(utf8.encode(excelColumnChart));
      final DrawingChart part = DrawingChart.opened(bytes);
      expect(part.changed, isFalse);
      expect(_joined(part), bytes);
      expect(part.chart, isNotNull);
      expect(part.typed, isNotNull);
      expect(part.issues, isEmpty);
      expect(_joined(part), bytes);
      expect(part.changed, isFalse);
    });

    test('the opened bytes are held, not copied', () {
      final Uint8List bytes = Uint8List.fromList(utf8.encode(excelColumnChart));
      expect(
        identical(DrawingChart.opened(bytes).encode().single, bytes),
        isTrue,
      );
    });

    test('an untyped chart keeps its bytes', () {
      const String xml =
          '<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"/>';
      final Uint8List bytes = Uint8List.fromList(utf8.encode(xml));
      final DrawingChart part = DrawingChart.opened(bytes);
      expect(part.typed, isNull);
      expect(_joined(part), bytes);
      expect(part.changed, isFalse);
    });

    test('unreadable bytes keep their bytes and report on request', () {
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final DrawingChart part = DrawingChart.opened(bytes);
      expect(_joined(part), bytes);
      expect(part.chart, isNull);
      expect(part.typed, isNull);
      expect(part.issues, contains(DrawingChartIssue.unreadable));
      expect(part.changed, isFalse);
    });

    test('reads once: issues is the same list each time', () {
      final DrawingChart part = DrawingChart.opened(
        Uint8List.fromList(<int>[0xff, 0xfe]),
      );
      expect(part.changed, isFalse);
      expect(identical(part.issues, part.issues), isTrue);
    });

    test('issues are the reader issues', () {
      final Uint8List bytes = Uint8List.fromList(utf8.encode(excelLineChart));
      expect(
        DrawingChart.opened(bytes).issues,
        readDrawingChartSpace(bytes).issues,
      );
    });
  });

  group('replace and created', () {
    test('replace encodes the written bytes and marks changed', () {
      final DrawingChart part = DrawingChart.opened(
        Uint8List.fromList(utf8.encode(excelColumnChart)),
      );
      final DrawingChartSpace space = _space(ChartKind.line);
      part.replace(space, _office);
      final DrawingChartWritten written = writeDrawingChartSpace(
        space,
        _office,
      );
      expect(part.changed, isTrue);
      expect(_joined(part), written.bytes);
      expect(part.issues, written.issues);
      expect(part.typed, same(space));
      expect(part.chart, same(space.chart));
      expect(identical(part.encode().first, part.encode().first), isTrue);
    });

    test('created encodes the written bytes', () {
      final DrawingChartSpace space = _space(ChartKind.column);
      final DrawingChart part = DrawingChart.created(space, _office);
      expect(part.changed, isTrue);
      expect(_joined(part), writeDrawingChartSpace(space, _office).bytes);
    });

    test('a chart the writer cannot express throws from created', () {
      expect(
        () => DrawingChart.created(_space(ChartKind.pie), _office),
        throwsArgumentError,
      );
    });

    test('a failed replace leaves the part as it was', () {
      final Uint8List bytes = Uint8List.fromList(utf8.encode(excelColumnChart));
      final DrawingChart part = DrawingChart.opened(bytes);
      expect(
        () => part.replace(_space(ChartKind.pie), _office),
        throwsArgumentError,
      );
      expect(part.changed, isFalse);
      expect(_joined(part), bytes);
    });
  });
}
