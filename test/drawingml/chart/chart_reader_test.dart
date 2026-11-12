import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_office/src/common/theme_colors.dart';
import 'package:jet_office/src/drawingml/chart/chart_reader.dart';
import 'package:jet_office/src/drawingml/chart/chart_space.dart';
import 'package:jet_office/src/drawingml/chart/chart_writer.dart';
import 'package:jet_office/src/drawingml/color.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

import 'support/excel_charts.dart';

final ChartTheme _office = ChartTheme.office;

/// The digits of the long number test: a megabyte.
const int _longDigits = 1 << 20;

Uint8List _bytes(String xml) => utf8.encode(xml);

DrawingChartRead _read(String xml, {ChartTheme? theme}) =>
    readDrawingChartSpace(_bytes(xml), theme: theme);

/// A series of [values] with text categories, both by reference.
ChartSeries _series({
  String? name,
  String? nameReference,
  List<Object?> categories = const <Object?>['A', 'B', 'C'],
  String? categoryReference = r'Sheet1!$A$2:$A$4',
  List<double?> values = const <double?>[1, 2, 3],
  String? valueReference = r'Sheet1!$B$2:$B$4',
  String? formatCode,
  ChartColor? color,
}) => ChartSeries(
  name: ChartData<String>(
    values: name == null ? const <String?>[] : <String?>[name],
    reference: nameReference,
  ),
  categories: ChartData<Object>(
    values: categories,
    reference: categoryReference,
  ),
  values: ChartData<double>(values: values, reference: valueReference),
  formatCode: formatCode,
  color: color,
);

Chart _chart(
  ChartKind kind, {
  ChartGrouping grouping = ChartGrouping.clustered,
  List<ChartSeries>? series,
  ChartLegend legend = const ChartLegend(visible: false),
  ChartTitle? title,
  ChartAxis categoryAxis = const ChartAxis(),
  ChartAxis valueAxis = const ChartAxis(gridLines: true),
  ChartDataLabels dataLabels = const ChartDataLabels(),
}) => Chart(
  kind: kind,
  grouping: grouping,
  series: series ?? <ChartSeries>[_series()],
  legend: legend,
  title: title,
  categoryAxis: categoryAxis,
  valueAxis: valueAxis,
  dataLabels: dataLabels,
);

/// Writes [space] in [theme] and reads it back in the same theme.
DrawingChartRead _roundTrip(DrawingChartSpace space, {ChartTheme? theme}) {
  final DrawingChartWritten written = writeDrawingChartSpace(
    space,
    theme ?? _office,
  );
  return readDrawingChartSpace(written.bytes, theme: theme ?? _office);
}

/// Expects [space] to read back typed and equal after a write.
void _expectRoundTrip(DrawingChartSpace space, {ChartTheme? theme}) {
  final DrawingChartRead read = _roundTrip(space, theme: theme);
  expect(read.chart, space.chart);
  expect(read.typed, space);
  expect(read.issues, isEmpty);
}

String _guid(int i) =>
    '{00000000-0000-0000-0000-${i.toRadixString(16).padLeft(12, '0')}}';

void main() {
  group("Excel's default charts", () {
    for (final (String name, String xml, ChartKind kind)
        in <(String, String, ChartKind)>[
          ('column', excelColumnChart, ChartKind.column),
          ('line', excelLineChart, ChartKind.line),
        ]) {
      test('the $name chart reads typed', () {
        final DrawingChartRead read = _read(xml);
        expect(read.issues, isEmpty);
        final Chart chart = read.chart!;
        expect(chart.kind, kind);
        expect(chart.grouping, ChartGrouping.clustered);
        expect(chart.title, isNull);
        expect(chart.legend.visible, isFalse);
        expect(chart.valueAxis.gridLines, isTrue);
        expect(chart.categoryAxis.gridLines, isFalse);
        expect(chart.series, hasLength(1));
        final ChartSeries series = chart.series.single;
        expect(series.name.values, isEmpty);
        expect(series.name.reference, isNull);
        expect(series.categories.values, <Object?>['A', 'B', 'C']);
        expect(series.categories.reference, r'Sayfa1!$A$1:$A$3');
        expect(series.values.values, <double?>[1, 2, 3]);
        expect(series.values.reference, r'Sayfa1!$B$1:$B$3');
        expect(series.formatCode, isNull);
        expect(series.color, isNull);
        final DrawingChartSpace typed = read.typed!;
        expect(typed.chart, chart);
        expect(typed.autoTitle, isTrue);
        expect(typed.language, 'tr-TR');
        expect(typed.ids.series, hasLength(1));
        expect(utf8.decode(writeDrawingChartSpace(typed, _office).bytes), xml);
      });
    }

    test('the column chart keeps its ids', () {
      final DrawingChartRead read = _read(excelColumnChart);
      expect(
        read.typed!.ids,
        const DrawingChartIds(
          categoryAxis: 1690013631,
          valueAxis: 1469245055,
          series: <String>['{00000000-8918-7940-9A01-4B67489FEBC8}'],
        ),
      );
    });
  });

  group('J4 fields', () {
    final ChartColor red = ChartColor.rgb(0xFF0000);

    test('a smooth line reads typed', () {
      _expectRoundTrip(
        DrawingChartSpace(
          chart: _chart(
            ChartKind.line,
            series: <ChartSeries>[_series().copyWith(smooth: true)],
          ),
        ),
      );
    });

    test('point colours of a column, a bar and a line read typed', () {
      for (final ChartKind kind in <ChartKind>[
        ChartKind.column,
        ChartKind.bar,
        ChartKind.line,
      ]) {
        final DrawingChartSpace space = DrawingChartSpace(
          chart: _chart(
            kind,
            series: <ChartSeries>[
              _series().copyWith(pointColors: <ChartColor?>[null, red]),
            ],
          ),
        );
        _expectRoundTrip(space);
        expect(
          _roundTrip(space).chart!.series.single.pointColors,
          <ChartColor?>[null, red],
          reason: kind.name,
        );
      }
    });

    test('area opacity and line read typed in their theme', () {
      final ChartTheme theme = _office.copyWith(
        areaOpacity: 0.25,
        areaLine: true,
      );
      _expectRoundTrip(
        DrawingChartSpace(
          chart: _chart(
            ChartKind.area,
            series: <ChartSeries>[_series(color: red)],
          ),
        ),
        theme: theme,
      );
      _expectRoundTrip(
        DrawingChartSpace(chart: _chart(ChartKind.area)),
        theme: theme,
      );
    });

    test('a translucent colour outside a series fill reads as before', () {
      final DrawingChartWritten written = writeDrawingChartSpace(
        DrawingChartSpace(chart: _chart(ChartKind.column)),
        _office,
      );
      final String xml = utf8
          .decode(written.bytes)
          .replaceFirst(
            '<c:majorGridlines><c:spPr><a:ln w="9525" cap="flat" cmpd="sng" '
                'algn="ctr"><a:solidFill><a:schemeClr val="tx1">',
            '<c:majorGridlines><c:spPr><a:ln w="9525" cap="flat" cmpd="sng" '
                'algn="ctr"><a:solidFill><a:schemeClr val="tx1"><a:alpha '
                'val="50000"/>',
          );
      expect(xml, contains('<a:alpha val="50000"/>'));
      final DrawingChartRead read = _read(xml);
      expect(read.chart!.valueAxis.gridLines, isTrue);
      // Not read as a colour, so the writer cannot reproduce the part.
      expect(read.typed, isNull);
    });

    test('an alpha the theme does not write leaves the part untyped', () {
      final ChartTheme alpha = _office.copyWith(areaOpacity: 0.25);
      final DrawingChartWritten written = writeDrawingChartSpace(
        DrawingChartSpace(chart: _chart(ChartKind.area)),
        alpha,
      );
      expect(
        readDrawingChartSpace(written.bytes, theme: _office).typed,
        isNull,
      );
    });
  });

  group('round trip', () {
    for (final ChartKind kind in <ChartKind>[
      ChartKind.column,
      ChartKind.bar,
      ChartKind.line,
      ChartKind.area,
    ]) {
      for (final ChartGrouping grouping in ChartGrouping.values) {
        test('${kind.name} ${grouping.name}', () {
          _expectRoundTrip(
            DrawingChartSpace(chart: _chart(kind, grouping: grouping)),
          );
        });
      }
    }

    test('a title of two lines with markup', () {
      _expectRoundTrip(
        DrawingChartSpace(
          chart: _chart(
            ChartKind.column,
            title: const ChartTitle(text: 'Gelir & <gider>\n"2026" 😀'),
          ),
          language: 'tr-TR',
        ),
      );
    });

    test('an automatic title', () {
      _expectRoundTrip(
        DrawingChartSpace(chart: _chart(ChartKind.line), autoTitle: true),
      );
    });

    for (final ChartLegendPosition position in ChartLegendPosition.values) {
      test('a legend at ${position.name}', () {
        _expectRoundTrip(
          DrawingChartSpace(
            chart: _chart(
              ChartKind.column,
              legend: ChartLegend(position: position),
            ),
          ),
        );
      });
    }

    test('axis titles, scaling and format codes', () {
      for (final ChartKind kind in <ChartKind>[
        ChartKind.column,
        ChartKind.bar,
      ]) {
        _expectRoundTrip(
          DrawingChartSpace(
            chart: _chart(
              kind,
              categoryAxis: const ChartAxis(title: 'Ay', formatCode: '@'),
              valueAxis: const ChartAxis(
                title: 'Tutar\nTL',
                min: -10.5,
                max: 1e21,
                majorUnit: 0.25,
                formatCode: '#,##0.00 "TL"',
                gridLines: true,
              ),
            ),
          ),
        );
      }
    });

    test('hidden axes without grid lines', () {
      _expectRoundTrip(
        DrawingChartSpace(
          chart: _chart(
            ChartKind.area,
            categoryAxis: const ChartAxis(visible: false),
            valueAxis: const ChartAxis(visible: false),
          ),
        ),
      );
    });

    test('data labels with a format code', () {
      for (final ChartKind kind in <ChartKind>[
        ChartKind.column,
        ChartKind.line,
        ChartKind.area,
      ]) {
        for (final ChartGrouping grouping in ChartGrouping.values) {
          _expectRoundTrip(
            DrawingChartSpace(
              chart: _chart(
                kind,
                grouping: grouping,
                dataLabels: const ChartDataLabels(
                  visible: true,
                  formatCode: '0.0%',
                ),
              ),
            ),
          );
        }
      }
      _expectRoundTrip(
        DrawingChartSpace(
          chart: _chart(
            ChartKind.bar,
            dataLabels: const ChartDataLabels(visible: true),
          ),
        ),
      );
    });

    test('literal data, names and gaps', () {
      _expectRoundTrip(
        DrawingChartSpace(
          chart: _chart(
            ChartKind.column,
            series: <ChartSeries>[
              _series(
                name: 'Gelir',
                categories: const <Object?>['a', null, 'c'],
                categoryReference: null,
                values: const <double?>[1.5, null, -3e-7],
                valueReference: null,
                formatCode: '#,##0.00',
              ),
              _series(
                name: 'Gider',
                nameReference: r"'O''Brien'!$C$1",
                categoryReference: '[0]!Tutarlar',
                valueReference: r'Sheet1!$B$2:$B$5,Sheet1!$D$2',
              ),
              _series(nameReference: r'Sheet1!$D$1'),
              _series(categories: const <Object?>[], categoryReference: null),
            ],
          ),
        ),
      );
    });

    test('Xstring look-alikes in names, references and format codes', () {
      _expectRoundTrip(
        DrawingChartSpace(
          chart: _chart(
            ChartKind.column,
            series: <ChartSeries>[
              _series(
                name: 'n_x0041_',
                nameReference: r'S_x0042_!$A$1',
                categories: const <Object?>['c_x0043_'],
                values: const <double?>[1],
                formatCode: '0_x0044_',
              ),
            ],
          ),
        ),
      );
    });

    test('number and date categories', () {
      _expectRoundTrip(
        DrawingChartSpace(
          chart: _chart(
            ChartKind.line,
            series: <ChartSeries>[
              _series(categories: const <Object?>[2024.0, 2025.0, 2026.5]),
            ],
          ),
        ),
      );
      _expectRoundTrip(
        DrawingChartSpace(
          chart: _chart(
            ChartKind.column,
            series: <ChartSeries>[
              _series(
                categories: <Object?>[
                  DateTime(2026, 1, 1),
                  null,
                  DateTime(2026, 3, 1, 12, 30),
                ],
              ),
            ],
          ),
        ),
      );
      _expectRoundTrip(
        DrawingChartSpace(
          chart: _chart(
            ChartKind.column,
            categoryAxis: const ChartAxis(formatCode: 'dd.mm.yyyy'),
            series: <ChartSeries>[
              _series(categories: <Object?>[DateTime(2026, 1, 31)]),
            ],
          ),
        ),
      );
    });

    test('date categories round trip in the 1904 system', () {
      final DrawingChartSpace space = DrawingChartSpace(
        chart: _chart(
          ChartKind.column,
          series: <ChartSeries>[
            _series(
              categories: <Object?>[
                DateTime(2026, 1, 1),
                DateTime(2026, 3, 1, 12, 30),
              ],
            ),
          ],
        ),
      );
      final DrawingChartWritten w1904 = writeDrawingChartSpace(
        space,
        _office,
        date1904: true,
      );
      final DrawingChartWritten w1900 = writeDrawingChartSpace(space, _office);
      expect(utf8.decode(w1904.bytes), contains('<c:v>44561</c:v>'));
      expect(utf8.decode(w1900.bytes), contains('<c:v>46023</c:v>'));
      final DrawingChartRead read = readDrawingChartSpace(
        w1904.bytes,
        date1904: true,
      );
      expect(read.typed, space);
      expect(read.chart!.series.single.categories.values, <Object?>[
        DateTime(2026, 1, 1),
        DateTime(2026, 3, 1, 12, 30),
      ]);
      final DrawingChartRead wrong = readDrawingChartSpace(w1904.bytes);
      // 44561 read as a 1900 serial: 1,462 days earlier than the real date.
      expect(
        wrong.chart!.series.single.categories.values.first,
        DateTime(2021, 12, 31),
      );
      // The part declares 1904, the reader was told 1900: not typed.
      expect(wrong.typed, isNull);
      expect(utf8.decode(w1904.bytes), contains('<c:date1904 val="1"/>'));
      expect(utf8.decode(w1900.bytes), contains('<c:date1904 val="0"/>'));
      // And the other way round.
      expect(readDrawingChartSpace(w1900.bytes, date1904: true).typed, isNull);
    });

    test('an app theme with fixed colours and an explicit colour', () {
      final ChartTheme app = _office.copyWith(
        exportColors: ChartExportColors.fixed,
      );
      _expectRoundTrip(
        DrawingChartSpace(
          chart: _chart(
            ChartKind.line,
            title: const ChartTitle(text: 'App'),
            legend: const ChartLegend(),
            series: <ChartSeries>[
              _series(),
              _series(color: ChartColor.rgb(0x123456)),
            ],
          ),
        ),
        theme: app,
      );
    });

    test('a theme without line markers', () {
      final ChartTheme plain = _office.copyWith(lineMarkers: false);
      final DrawingChartSpace space = DrawingChartSpace(
        chart: _chart(ChartKind.line),
      );
      _expectRoundTrip(space, theme: plain);
      // The part is the theme's: read in the Office theme, whose lines have
      // markers, it has no typed form.
      final DrawingChartWritten written = writeDrawingChartSpace(space, plain);
      expect(
        readDrawingChartSpace(written.bytes, theme: _office).typed,
        isNull,
      );
    });

    test('a series colour bound to another slot', () {
      _expectRoundTrip(
        DrawingChartSpace(
          chart: _chart(
            ChartKind.column,
            series: <ChartSeries>[
              _series(
                color: ChartColor.scheme(
                  ChartSchemeColor.accent3,
                  // The colour drawn: the slot's with the luminance applied.
                  rgb: applyDrawingLuminance(0x196B24, 0.75, 0),
                  lumMod: 0.75,
                ),
              ),
            ],
          ),
        ),
      );
    });

    test('ten series with ids', () {
      _expectRoundTrip(
        DrawingChartSpace(
          chart: _chart(
            ChartKind.column,
            legend: const ChartLegend(),
            series: <ChartSeries>[
              for (int i = 0; i < 10; i++)
                _series(name: 'S$i', values: <double?>[i.toDouble(), 1, 2]),
            ],
          ),
          ids: DrawingChartIds(
            categoryAxis: 0,
            valueAxis: 4294967295,
            series: <String>[for (int i = 0; i < 10; i++) _guid(i)],
          ),
        ),
      );
    });

    test('10,000 points', () {
      final List<double?> values = <double?>[
        for (int i = 0; i < 10000; i++) i * 0.5,
      ];
      final List<Object?> categories = <Object?>[
        for (int i = 0; i < 10000; i++) 'C$i',
      ];
      _expectRoundTrip(
        DrawingChartSpace(
          chart: _chart(
            ChartKind.line,
            series: <ChartSeries>[
              _series(categories: categories, values: values),
              _series(categories: categories, values: values),
            ],
          ),
        ),
      );
    });

    test('a chart without series', () {
      _expectRoundTrip(
        DrawingChartSpace(
          chart: _chart(ChartKind.column, series: const <ChartSeries>[]),
        ),
      );
    });
  });

  group('parts that are not typed', () {
    test('a theme the writer refuses gives a view only, never a throw', () {
      final ChartTextStyle text = _office.titleText;
      for (final ChartTheme theme in <ChartTheme>[
        _office.copyWith(lineWidth: double.nan),
        _office.copyWith(markerSize: double.infinity),
        _office.copyWith(markerSize: -1),
        _office.copyWith(titleText: text.copyWith(size: double.nan)),
        _office.copyWith(axisLabels: text.copyWith(size: 0.5)),
        _office.copyWith(legendText: text.copyWith(size: 4001)),
      ]) {
        for (final String xml in <String>[excelColumnChart, excelLineChart]) {
          final DrawingChartRead read = readDrawingChartSpace(
            _bytes(xml),
            theme: theme,
          );
          expect(read.chart, _read(xml).chart);
          expect(read.typed, isNull);
          expect(read.issues, isEmpty);
        }
      }
    });

    test('dk1 in place of tx1 gives a view only', () {
      final DrawingChartRead read = _read(
        excelColumnChart.replaceAll('"tx1"', '"dk1"'),
      );
      expect(read.chart, _read(excelColumnChart).chart);
      expect(read.typed, isNull);
      expect(read.issues, isEmpty);
    });

    test('an extra c:dispUnits gives a view only', () {
      final DrawingChartRead read = _read(
        excelColumnChart.replaceFirst(
          '<c:crossBetween val="between"/>',
          '<c:crossBetween val="between"/>'
              '<c:dispUnits><c:builtInUnit val="thousands"/></c:dispUnits>',
        ),
      );
      expect(read.chart!.kind, ChartKind.column);
      expect(read.typed, isNull);
    });

    test('a part without c16 ids is read and typed, with no series ids', () {
      final String xml = excelColumnChart.replaceFirst(
        RegExp('<c:extLst><c:ext uri="{C3380CC4.*?</c:extLst>'),
        '',
      );
      final DrawingChartRead read = _read(xml);
      expect(read.chart, _read(excelColumnChart).chart);
      // The writer writes such a series without ids, so it is typed.
      expect(read.typed!.ids.series, isEmpty);
    });

    test('a pie chart beside two axes is unsupported', () {
      final DrawingChartRead read = _read(
        excelColumnChart
            .replaceFirst('<c:barChart><c:barDir val="col"/>', '<c:pieChart>')
            .replaceFirst('</c:barChart>', '</c:pieChart>'),
      );
      final Chart chart = read.chart!;
      expect(chart.kind, ChartKind.unsupported);
      expect(chart.unsupportedName, 'pieChart');
      expect(chart.series.single.values.values, <double?>[1, 2, 3]);
      expect(read.typed, isNull);
      expect(read.issues, <DrawingChartIssue>[
        DrawingChartIssue.unsupportedKind,
      ]);
    });

    group('pies and doughnuts', () {
      test('a pie reads back typed', () {
        _expectRoundTrip(
          DrawingChartSpace(
            chart: _chart(ChartKind.pie, legend: const ChartLegend()),
            language: 'tr-TR',
            ids: DrawingChartIds(series: <String>[_guid(1)]),
            autoTitle: true,
          ),
        );
      });

      test('a doughnut of two series and a hole of 40 reads back typed', () {
        _expectRoundTrip(
          DrawingChartSpace(
            chart: Chart(
              kind: ChartKind.donut,
              series: <ChartSeries>[
                _series(name: 'a'),
                _series(name: 'b'),
              ],
              holeSizePercent: 40,
              title: const ChartTitle(text: 'Halka'),
            ),
          ),
        );
      });

      test('labels with values and percents read back typed', () {
        for (final ChartKind kind in <ChartKind>[
          ChartKind.pie,
          ChartKind.donut,
        ]) {
          _expectRoundTrip(
            DrawingChartSpace(
              chart: _chart(
                kind,
                dataLabels: const ChartDataLabels(
                  visible: true,
                  showValue: false,
                  showPercent: true,
                  formatCode: '0.0%',
                ),
              ),
            ),
          );
        }
      });

      test('a point colour of its own reads back; an accent of its index '
          'reads as automatic', () {
        final ChartSeries series = _series().copyWith(
          pointColors: <ChartColor?>[null, ChartColor.rgb(0x123456)],
        );
        _expectRoundTrip(
          DrawingChartSpace(chart: _chart(ChartKind.pie, series: [series])),
        );
        final DrawingChartRead read = _roundTrip(
          DrawingChartSpace(
            chart: _chart(
              ChartKind.pie,
              series: <ChartSeries>[
                _series().copyWith(
                  pointColors: <ChartColor?>[_office.seriesColor(0)],
                ),
              ],
            ),
          ),
        );
        expect(read.chart!.series.single.pointColors, isEmpty);
        expect(read.typed, isNotNull);
      });

      test('an app theme with fixed colours reads back equal', () {
        final ChartTheme app = _office.copyWith(
          exportColors: ChartExportColors.fixed,
        );
        _expectRoundTrip(
          DrawingChartSpace(
            chart: _chart(
              ChartKind.pie,
              legend: const ChartLegend(),
              dataLabels: const ChartDataLabels(visible: true),
            ),
          ),
          theme: app,
        );
      });

      test('a hole size that cannot be read is a bad number, untyped', () {
        final String xml = utf8
            .decode(
              writeDrawingChartSpace(
                DrawingChartSpace(chart: _chart(ChartKind.donut)),
                _office,
              ).bytes,
            )
            .replaceFirst('<c:holeSize val="75"/>', '<c:holeSize val="x"/>');
        final DrawingChartRead read = _read(xml);
        expect(read.chart!.kind, ChartKind.donut);
        expect(read.chart!.holeSizePercent, 75);
        expect(read.typed, isNull);
        expect(read.issues, <DrawingChartIssue>[DrawingChartIssue.badNumber]);
      });

      test('a hole size outside 10 to 90 reads as 75, untyped', () {
        for (final String size in <String>['5', '95']) {
          final String xml = utf8
              .decode(
                writeDrawingChartSpace(
                  DrawingChartSpace(chart: _chart(ChartKind.donut)),
                  _office,
                ).bytes,
              )
              .replaceFirst(
                '<c:holeSize val="75"/>',
                '<c:holeSize val="$size"/>',
              );
          final DrawingChartRead read = _read(xml);
          expect(read.chart!.holeSizePercent, 75, reason: size);
          expect(read.typed, isNull, reason: size);
        }
      });
    });

    group('scatter charts', () {
      Chart scatter({
        List<ChartSeries>? series,
        ChartAxis categoryAxis = const ChartAxis(gridLines: true),
        ChartAxis valueAxis = const ChartAxis(gridLines: true),
        ChartDataLabels dataLabels = const ChartDataLabels(),
      }) => Chart(
        kind: ChartKind.scatter,
        series:
            series ??
            <ChartSeries>[
              _series(
                name: 'Satış',
                nameReference: r'Sheet1!$B$1',
                categories: const <Object?>[1.5, 2, 4],
              ),
            ],
        categoryAxis: categoryAxis,
        valueAxis: valueAxis,
        dataLabels: dataLabels,
        legend: const ChartLegend(),
      );

      test('numeric x values read back typed', () {
        _expectRoundTrip(
          DrawingChartSpace(
            chart: scatter(),
            ids: DrawingChartIds(series: <String>[_guid(1)]),
            autoTitle: true,
          ),
        );
      });

      test('text x values of two series read back typed', () {
        _expectRoundTrip(
          DrawingChartSpace(
            chart: scatter(
              series: <ChartSeries>[
                _series(name: 'a'),
                _series(name: 'b', values: const <double?>[-4, null, 9]),
              ],
            ),
            language: 'tr-TR',
          ),
        );
      });

      test('date x values read back typed, in both date systems', () {
        final DrawingChartSpace space = DrawingChartSpace(
          chart: scatter(
            series: <ChartSeries>[
              _series(
                categories: <Object?>[
                  DateTime(2026, 1, 1),
                  DateTime(2026, 2, 1),
                  DateTime(2026, 3, 1),
                ],
              ),
            ],
          ),
        );
        _expectRoundTrip(space);
        for (final bool date1904 in <bool>[false, true]) {
          final DrawingChartRead read = readDrawingChartSpace(
            writeDrawingChartSpace(space, _office, date1904: date1904).bytes,
            date1904: date1904,
          );
          expect(read.typed, space, reason: '$date1904');
        }
      });

      test('the axes\' options read back typed: no x grid lines, titles, '
          'a fixed range, formats, a hidden axis', () {
        _expectRoundTrip(
          DrawingChartSpace(
            chart: scatter(
              categoryAxis: const ChartAxis(
                title: 'X',
                min: 0,
                max: 10,
                majorUnit: 2,
                formatCode: '0.0',
              ),
              valueAxis: const ChartAxis(
                title: 'Y',
                formatCode: '#,##0',
                gridLines: false,
              ),
            ),
          ),
        );
        _expectRoundTrip(
          DrawingChartSpace(
            chart: scatter(
              valueAxis: const ChartAxis(visible: false, gridLines: true),
            ),
          ),
        );
      });

      test('a series and point colour of its own read back typed', () {
        final ChartColor red = ChartColor.rgb(0xFF0000);
        final DrawingChartSpace space = DrawingChartSpace(
          chart: scatter(
            series: <ChartSeries>[
              _series(
                color: ChartColor.rgb(0x123456),
              ).copyWith(pointColors: <ChartColor?>[null, red]),
            ],
          ),
        );
        _expectRoundTrip(space);
        final ChartSeries read = _roundTrip(space).chart!.series.single;
        expect(read.color, ChartColor.rgb(0x123456));
        expect(read.pointColors, <ChartColor?>[null, red]);
      });

      test('data labels and an app theme with fixed colours read back '
          'typed', () {
        _expectRoundTrip(
          DrawingChartSpace(
            chart: scatter(dataLabels: const ChartDataLabels(visible: true)),
          ),
          theme: _office.copyWith(exportColors: ChartExportColors.fixed),
        );
      });

      test('a scatter group beside a category axis is unsupported', () {
        final String xml = utf8
            .decode(
              writeDrawingChartSpace(
                DrawingChartSpace(chart: scatter()),
                _office,
              ).bytes,
            )
            .replaceFirst('<c:valAx>', '<c:catAx>')
            .replaceFirst('</c:valAx>', '</c:catAx>');
        final DrawingChartRead read = _read(xml);
        expect(read.chart!.kind, ChartKind.unsupported);
        expect(read.chart!.unsupportedName, 'scatterChart');
        expect(read.typed, isNull);
      });
    });

    test('a bar and line combination is unsupported', () {
      final String line = RegExp(
        '<c:lineChart>.*</c:lineChart>',
      ).firstMatch(excelLineChart)![0]!;
      final DrawingChartRead read = _read(
        excelColumnChart.replaceFirst('</c:barChart>', '</c:barChart>$line'),
      );
      expect(read.chart!.kind, ChartKind.unsupported);
      expect(read.chart!.unsupportedName, 'barChart+lineChart');
      expect(read.chart!.series, hasLength(1));
      expect(read.typed, isNull);
      expect(read.issues, <DrawingChartIssue>[
        DrawingChartIssue.unsupportedKind,
      ]);
    });

    test('a third axis is unsupported', () {
      final DrawingChartRead read = _read(
        excelColumnChart.replaceFirst(
          '</c:valAx>',
          '</c:valAx><c:serAx><c:axId val="7"/></c:serAx>',
        ),
      );
      expect(read.chart!.kind, ChartKind.unsupported);
      expect(read.chart!.unsupportedName, 'barChart');
      expect(read.typed, isNull);
    });

    test('a number that does not parse is an empty point', () {
      final DrawingChartRead read = _read(
        excelColumnChart.replaceFirst('<c:v>2</c:v>', '<c:v>x</c:v>'),
      );
      expect(read.chart!.series.single.values.values, <double?>[1, null, 3]);
      expect(read.typed, isNull);
      expect(read.issues, <DrawingChartIssue>[DrawingChartIssue.badNumber]);
    });

    test('NaN and infinite numbers are empty points', () {
      for (final String text in <String>['NaN', 'Infinity', '1e999', '']) {
        final DrawingChartRead read = _read(
          excelColumnChart.replaceFirst('<c:v>2</c:v>', '<c:v>$text</c:v>'),
        );
        expect(read.chart!.series.single.values.values, <double?>[
          1,
          null,
          3,
        ], reason: text);
        expect(read.issues, <DrawingChartIssue>[DrawingChartIssue.badNumber]);
      }
    });

    test('a point count beyond the limit is capped', () {
      final DrawingChartRead read = _read(
        excelColumnChart
            .replaceFirst(
              '<c:ptCount val="3"/><c:pt idx="0"><c:v>1',
              '<c:ptCount val="99999999999999999999"/><c:pt idx="0"><c:v>1',
            )
            .replaceFirst('<c:pt idx="2"><c:v>3', '<c:pt idx="-1"><c:v>3'),
      );
      final List<double?> values = read.chart!.series.single.values.values;
      expect(values.length, lessThanOrEqualTo(1 << 20));
      expect(values.take(3), <double?>[1, 2, null]);
      expect(read.issues, contains(DrawingChartIssue.badNumber));
    });

    test('unreadable input gives no chart and never throws', () {
      for (final String xml in <String>[
        '',
        '<a/>',
        excelColumnChart.substring(0, excelColumnChart.length ~/ 2),
        '<c:chartSpace xmlns:c="$drawingChartNamespace"/>',
        '<!DOCTYPE x><x/>',
      ]) {
        final DrawingChartRead read = _read(xml);
        expect(read.chart, isNull, reason: xml);
        expect(read.typed, isNull);
        expect(read.issues, <DrawingChartIssue>[DrawingChartIssue.unreadable]);
      }
      final DrawingChartRead binary = readDrawingChartSpace(
        Uint8List.fromList(<int>[0xFF, 0xFE, 0, 1, 2]),
      );
      expect(binary.chart, isNull);
      expect(binary.issues, <DrawingChartIssue>[DrawingChartIssue.unreadable]);
    });

    test('a long run of digits is read promptly as a bad number', () {
      final String digits = '1' * _longDigits;
      final Stopwatch watch = Stopwatch()..start();
      final DrawingChartRead read = _read(
        excelColumnChart.replaceFirst('<c:v>2</c:v>', '<c:v>${digits}x</c:v>'),
      );
      watch.stop();
      expect(read.chart!.series.single.values.values, <double?>[1, null, 3]);
      expect(read.issues, <DrawingChartIssue>[DrawingChartIssue.badNumber]);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('declared point counts share one budget per part', () {
      const String count = '<c:ptCount val="1048576"/>';
      final String series = List<String>.generate(
        100,
        (int i) =>
            '<c:ser><c:idx val="$i"/><c:order val="$i"/>'
            '<c:cat><c:strLit>$count<c:pt idx="0"><c:v>A</c:v></c:pt>'
            '</c:strLit></c:cat>'
            '<c:val><c:numLit>$count<c:pt idx="1"><c:v>1</c:v></c:pt>'
            '</c:numLit></c:val></c:ser>',
      ).join();
      final String xml =
          '<c:chartSpace xmlns:c="$drawingChartNamespace"><c:chart>'
          '<c:plotArea><c:barChart>$series</c:barChart>'
          '<c:catAx><c:axId val="1"/></c:catAx>'
          '<c:valAx><c:axId val="2"/></c:valAx></c:plotArea></c:chart>'
          '</c:chartSpace>';
      final Uint8List bytes = _bytes(xml);
      final Stopwatch watch = Stopwatch()..start();
      final DrawingChartRead read = readDrawingChartSpace(bytes);
      watch.stop();
      final Chart chart = read.chart!;
      expect(chart.series, hasLength(100));
      int entries = 0;
      for (final ChartSeries s in chart.series) {
        entries += s.categories.values.length + s.values.values.length;
      }
      expect(entries, lessThanOrEqualTo((1 << 20) + bytes.length));
      // The first caches keep their count; the later ones are cut to their
      // points.
      expect(chart.series.first.categories.values, hasLength(1 << 20));
      expect(chart.series.last.categories.values, <Object?>['A']);
      expect(chart.series.last.values.values, <double?>[null, 1]);
      expect(read.issues, <DrawingChartIssue>[DrawingChartIssue.badNumber]);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('a plot area without groups is unsupported', () {
      final DrawingChartRead read = _read(
        '<c:chartSpace xmlns:c="$drawingChartNamespace"><c:chart>'
        '<c:plotArea><c:layout/></c:plotArea></c:chart></c:chartSpace>',
      );
      expect(read.chart!.kind, ChartKind.unsupported);
      expect(read.chart!.series, isEmpty);
      expect(read.chart!.unsupportedName, isNull);
      expect(read.issues, <DrawingChartIssue>[
        DrawingChartIssue.unsupportedKind,
      ]);
    });
  });

  group('variants of other producers', () {
    const String c = drawingChartNamespace;
    const String a = 'http://schemas.openxmlformats.org/drawingml/2006/main';

    String part(String plot, {String chartExtra = ''}) =>
        '<c:chartSpace xmlns:c="$c" xmlns:a="$a"><c:lang val="en-US"/>'
        '<c:chart>$chartExtra<c:plotArea>$plot</c:plotArea></c:chart>'
        '</c:chartSpace>';

    const String axes =
        '<c:catAx><c:axId val="1"/><c:delete val="1"/>'
        '<c:numFmt formatCode="0.0" sourceLinked="0"/></c:catAx>'
        '<c:valAx><c:axId val="2"/><c:scaling><c:orientation val="minMax"/>'
        '<c:max val="10"/><c:min val="abc"/></c:scaling><c:delete/>'
        '<c:majorGridlines/><c:numFmt formatCode="0%" sourceLinked="1"/>'
        '<c:majorUnit val="2"/></c:valAx>';

    test('reads a stacked bar chart of another producer', () {
      final DrawingChartRead read = _read(
        part(
          '<c:barChart><c:barDir val="bar"/><c:grouping val="stacked"/>'
          '<c:ser><c:idx val="0"/><c:order val="0"/>'
          '<c:tx><c:strRef><c:f>Sheet1!B1</c:f><c:strCache><c:ptCount val="1"/>'
          '<c:pt idx="0"><c:v>Sales</c:v></c:pt></c:strCache></c:strRef></c:tx>'
          '<c:spPr><a:solidFill><a:srgbClr val="FF0000"/></a:solidFill></c:spPr>'
          '<c:cat><c:numRef><c:f>Sheet1!A2:A3</c:f><c:numCache>'
          '<c:formatCode>yyyy-mm-dd</c:formatCode><c:ptCount val="2"/>'
          '<c:pt idx="0"><c:v>46023</c:v></c:pt><c:pt idx="1"><c:v>46024.5</c:v></c:pt>'
          '</c:numCache></c:numRef></c:cat>'
          '<c:val><c:numLit><c:ptCount val="2"/><c:pt idx="1"><c:v>4</c:v></c:pt>'
          '</c:numLit></c:val></c:ser>'
          '<c:dLbls><c:numFmt formatCode="0.00" sourceLinked="0"/>'
          '<c:showVal val="1"/></c:dLbls>'
          '<c:axId val="1"/><c:axId val="2"/></c:barChart>$axes',
          chartExtra:
              '<c:title><c:tx><c:rich><a:p><a:r><a:t>Q</a:t></a:r>'
              '<a:r><a:t>1</a:t></a:r></a:p><a:p/></c:rich></c:tx></c:title>',
        ).replaceFirst(
          '</c:plotArea>',
          '</c:plotArea><c:legend><c:legendPos val="tr"/></c:legend>',
        ),
      );
      final Chart chart = read.chart!;
      expect(chart.kind, ChartKind.bar);
      expect(chart.grouping, ChartGrouping.stacked);
      expect(chart.title, const ChartTitle(text: 'Q1\n'));
      expect(
        chart.legend,
        const ChartLegend(position: ChartLegendPosition.right),
      );
      expect(
        chart.dataLabels,
        const ChartDataLabels(visible: true, formatCode: '0.00'),
      );
      expect(
        chart.categoryAxis,
        const ChartAxis(visible: false, formatCode: '0.0'),
      );
      expect(
        chart.valueAxis,
        const ChartAxis(max: 10, majorUnit: 2, visible: false, gridLines: true),
      );
      final ChartSeries series = chart.series.single;
      expect(series.name.values, <String?>['Sales']);
      expect(series.name.reference, 'Sheet1!B1');
      expect(series.color, ChartColor.rgb(0xFF0000));
      expect(series.categories.values, <Object?>[
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 2, 12),
      ]);
      expect(series.values.values, <double?>[null, 4]);
      expect(series.values.reference, isNull);
      expect(series.formatCode, isNull);
      expect(read.typed, isNull);
      expect(read.issues, <DrawingChartIssue>[DrawingChartIssue.badNumber]);
    });

    test('a hidden legend and data labels deleted', () {
      final DrawingChartRead read = _read(
        part(
          '<c:lineChart><c:grouping val="percentStacked"/>'
          '<c:dLbls><c:delete val="1"/></c:dLbls></c:lineChart>$axes',
        ).replaceFirst(
          '</c:plotArea>',
          '</c:plotArea><c:legend><c:legendPos val="t"/><c:delete val="1"/>'
              '</c:legend>',
        ),
      );
      expect(read.chart!.kind, ChartKind.line);
      expect(read.chart!.grouping, ChartGrouping.percentStacked);
      expect(read.chart!.legend.visible, isFalse);
      expect(read.chart!.dataLabels.visible, isFalse);
    });

    String labelled(String seriesLabels, String groupLabels) => part(
      '<c:barChart><c:barDir val="col"/><c:grouping val="clustered"/>'
      '<c:ser><c:idx val="0"/><c:order val="0"/>$seriesLabels'
      '<c:val><c:numLit><c:ptCount val="1"/><c:pt idx="0"><c:v>1</c:v></c:pt>'
      '</c:numLit></c:val></c:ser>$groupLabels'
      '<c:axId val="1"/><c:axId val="2"/></c:barChart>$axes',
    );

    group('data labels of a series and of the group', () {
      const String shown = '<c:dLbls><c:showVal val="1"/></c:dLbls>';
      const String off = '<c:dLbls><c:showVal val="0"/></c:dLbls>';
      const String deleted = '<c:dLbls><c:delete val="1"/></c:dLbls>';

      test('a series with showVal 0 hides what the group shows', () {
        final DrawingChartRead read = _read(labelled(off, shown));
        expect(read.chart!.dataLabels.visible, isFalse);
      });

      test('a series with delete 1 hides what the group shows', () {
        final DrawingChartRead read = _read(labelled(deleted, shown));
        expect(read.chart!.dataLabels.visible, isFalse);
      });

      test('a series with showVal 1 shows what the group hides', () {
        final DrawingChartRead read = _read(labelled(shown, off));
        expect(read.chart!.dataLabels.visible, isTrue);
      });

      test('a series without its own labels takes the group\'s', () {
        expect(_read(labelled('', shown)).chart!.dataLabels.visible, isTrue);
        expect(_read(labelled('', off)).chart!.dataLabels.visible, isFalse);
      });
    });

    test(
      'a scheme colour of the file theme equal to the derived one is null',
      () {
        final ThemeColors theme = ThemeColors.read(
          XmlPullReader(
            '<a:theme xmlns:a="$a"><a:themeElements><a:clrScheme name="x">'
            '<a:accent1><a:srgbClr val="FF0000"/></a:accent1>'
            '</a:clrScheme></a:themeElements></a:theme>',
          ),
        )!;
        final DrawingChartRead read = readDrawingChartSpace(
          _bytes(excelColumnChart),
          themeColors: theme,
        );
        expect(read.chart!.series.single.color, isNull);
        expect(read.typed, isNotNull);
      },
    );
  });
}
