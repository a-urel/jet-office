import 'dart:convert';

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_office/src/drawingml/chart/chart_space.dart';
import 'package:jet_office/src/drawingml/chart/chart_writer.dart';
import 'package:jet_office/src/xml/xml_equivalence.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:test/test.dart';

import 'support/excel_charts.dart';

final ChartTheme _office = ChartTheme.office;

/// The one series of the owner's `chart_defaults.xlsx`.
ChartSeries _excelSeries() => ChartSeries(
  name: ChartData<String>(values: const <String?>[]),
  categories: ChartData<Object>(
    values: const <Object?>['A', 'B', 'C'],
    reference: r'Sayfa1!$A$1:$A$3',
  ),
  values: ChartData<double>(
    values: const <double?>[1, 2, 3],
    reference: r'Sayfa1!$B$1:$B$3',
  ),
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
  series: series ?? <ChartSeries>[_excelSeries()],
  legend: legend,
  title: title,
  categoryAxis: categoryAxis,
  valueAxis: valueAxis,
  dataLabels: dataLabels,
);

DrawingChartWritten _write(Chart chart, {ChartTheme? theme}) =>
    writeDrawingChartSpace(DrawingChartSpace(chart: chart), theme ?? _office);

String _xml(DrawingChartWritten written) => utf8.decode(written.bytes);

/// Reads [xml] through and fails when it is not well formed.
void _expectWellFormed(String xml) {
  final XmlPullReader r = XmlPullReader(xml);
  while (r.next()) {}
}

int _count(String xml, String pattern) => pattern.allMatches(xml).length;

void main() {
  group("Excel's default charts", () {
    test("writes Excel's default column chart", () {
      final DrawingChartWritten written = writeDrawingChartSpace(
        DrawingChartSpace(
          chart: _chart(ChartKind.column),
          language: 'tr-TR',
          ids: const DrawingChartIds(
            categoryAxis: 1690013631,
            valueAxis: 1469245055,
            series: <String>['{00000000-8918-7940-9A01-4B67489FEBC8}'],
          ),
          autoTitle: true,
        ),
        _office,
      );
      expect(
        xmlDifference(written.bytes, utf8.encode(excelColumnChart)),
        isNull,
      );
      expect(written.issues, isEmpty);
      // Byte for byte, too: the writer spells the part as Excel does.
      expect(_xml(written), excelColumnChart);
    });

    test("writes Excel's default line chart", () {
      final DrawingChartWritten written = writeDrawingChartSpace(
        DrawingChartSpace(
          chart: _chart(ChartKind.line),
          language: 'tr-TR',
          ids: const DrawingChartIds(
            categoryAxis: 1689503039,
            valueAxis: 1689506623,
            series: <String>['{00000000-EC46-334E-9FAA-C735C7AD2695}'],
          ),
          autoTitle: true,
        ),
        _office,
      );
      expect(xmlDifference(written.bytes, utf8.encode(excelLineChart)), isNull);
      expect(written.issues, isEmpty);
      expect(_xml(written), excelLineChart);
    });
  });

  group('kinds and groupings', () {
    for (final ChartKind kind in <ChartKind>[
      ChartKind.column,
      ChartKind.bar,
      ChartKind.line,
      ChartKind.area,
    ]) {
      for (final ChartGrouping grouping in ChartGrouping.values) {
        test('${kind.name} ${grouping.name}', () {
          final String xml = _xml(_write(_chart(kind, grouping: grouping)));
          _expectWellFormed(xml);
          final bool bars = kind == ChartKind.column || kind == ChartKind.bar;
          final String group = switch (kind) {
            ChartKind.line => 'lineChart',
            ChartKind.area => 'areaChart',
            _ => 'barChart',
          };
          expect(xml, contains('<c:plotArea><c:layout/><c:$group>'));
          final String groupingName = switch (grouping) {
            ChartGrouping.clustered => bars ? 'clustered' : 'standard',
            ChartGrouping.stacked => 'stacked',
            ChartGrouping.percentStacked => 'percentStacked',
          };
          expect(xml, contains('<c:grouping val="$groupingName"/>'));
          if (bars) {
            final String dir = kind == ChartKind.bar ? 'bar' : 'col';
            expect(xml, contains('<c:barDir val="$dir"/>'));
            final String overlap = grouping == ChartGrouping.clustered
                ? '-27'
                : '100';
            expect(xml, contains('<c:overlap val="$overlap"/>'));
            expect(xml, contains('<c:gapWidth val="219"/>'));
            expect(xml, contains('<c:invertIfNegative val="0"/>'));
          } else {
            expect(xml, isNot(contains('barDir')));
            expect(xml, isNot(contains('overlap')));
          }
          final (String cat, String val) = kind == ChartKind.bar
              ? ('l', 'b')
              : ('b', 'l');
          expect(
            RegExp(
              '<c:catAx>.*<c:axPos val="$cat"/>.*</c:catAx>'
              '<c:valAx>.*<c:axPos val="$val"/>.*</c:valAx>',
            ).hasMatch(xml),
            isTrue,
          );
          expect(xml.contains('<c:marker val="1"/>'), kind == ChartKind.line);
          expect(
            xml.contains('<c:crossBetween val="midCat"/>'),
            kind == ChartKind.area,
          );
        });
      }
    }
  });

  group('colours', () {
    test('an app theme writes no schemeClr and no theme font', () {
      final ChartTheme app = _office.copyWith(
        exportColors: ChartExportColors.fixed,
      );
      final String xml = _xml(
        _write(
          _chart(
            ChartKind.column,
            title: const ChartTitle(text: 'Satışlar'),
            legend: const ChartLegend(),
            dataLabels: const ChartDataLabels(visible: true),
          ),
          theme: app,
        ),
      );
      _expectWellFormed(xml);
      expect(xml, isNot(contains('schemeClr')));
      expect(xml, isNot(contains('+mn-')));
      expect(xml, contains('<a:srgbClr val="156082"/>'));
      expect(xml, contains('<a:latin typeface="Aptos Narrow"/>'));
    });

    test('series 7 of the Office theme writes the derived fixed colour', () {
      final List<ChartSeries> series = <ChartSeries>[
        for (int i = 0; i < 7; i++) _excelSeries(),
      ];
      final String xml = _xml(_write(_chart(ChartKind.column, series: series)));
      final ChartColor seventh = _office.colorOf(series[6], 6);
      expect(seventh.slot, isNull);
      final String hex = seventh.rgb
          .toRadixString(16)
          .padLeft(6, '0')
          .toUpperCase();
      expect(
        xml,
        contains(
          '<c:idx val="6"/><c:order val="6"/><c:spPr><a:solidFill>'
          '<a:srgbClr val="$hex"/></a:solidFill>',
        ),
      );
      expect(xml, contains('<a:schemeClr val="accent6"/>'));
    });

    test('a series colour and a semantic key win over the palette', () {
      final ChartTheme theme = _office.copyWith(
        semantic: <String, ChartColor>{'income': ChartColor.rgb(0x00FF00)},
      );
      final String xml = _xml(
        _write(
          _chart(
            ChartKind.column,
            series: <ChartSeries>[
              _excelSeries().copyWith(color: ChartColor.rgb(0xFF0000)),
              _excelSeries().copyWith(colorKey: 'income'),
            ],
          ),
          theme: theme,
        ),
      );
      expect(xml, contains('<a:srgbClr val="FF0000"/>'));
      expect(xml, contains('<a:srgbClr val="00FF00"/>'));
      expect(xml, isNot(contains('accent1')));
    });
  });

  group('data', () {
    test('literal data writes strLit and numLit', () {
      final String xml = _xml(
        _write(
          _chart(
            ChartKind.column,
            series: <ChartSeries>[
              ChartSeries(
                name: ChartData<String>(values: const <String?>['Gelir']),
                categories: ChartData<Object>(
                  values: const <Object?>['x', 'y'],
                ),
                values: ChartData<double>(values: const <double?>[1.5, 2]),
                formatCode: '#,##0.00',
              ),
            ],
          ),
        ),
      );
      _expectWellFormed(xml);
      expect(xml, contains('<c:tx><c:v>Gelir</c:v></c:tx>'));
      expect(
        xml,
        contains(
          '<c:cat><c:strLit><c:ptCount val="2"/><c:pt idx="0"><c:v>x</c:v>'
          '</c:pt><c:pt idx="1"><c:v>y</c:v></c:pt></c:strLit></c:cat>',
        ),
      );
      expect(
        xml,
        contains(
          '<c:val><c:numLit><c:formatCode>#,##0.00</c:formatCode>'
          '<c:ptCount val="2"/><c:pt idx="0"><c:v>1.5</c:v></c:pt>'
          '<c:pt idx="1"><c:v>2</c:v></c:pt></c:numLit></c:val>',
        ),
      );
    });

    test('a referenced name writes strRef with a one-point cache', () {
      final String xml = _xml(
        _write(
          _chart(
            ChartKind.column,
            series: <ChartSeries>[
              _excelSeries().copyWith(
                name: ChartData<String>(
                  values: const <String?>['Gelir'],
                  reference: r'Sayfa1!$B$1',
                ),
              ),
            ],
          ),
        ),
      );
      expect(
        xml,
        contains(
          r'<c:tx><c:strRef><c:f>Sayfa1!$B$1</c:f><c:strCache>'
          '<c:ptCount val="1"/><c:pt idx="0"><c:v>Gelir</c:v></c:pt>'
          '</c:strCache></c:strRef></c:tx>',
        ),
      );
    });

    test('date categories write serials in m/d/yyyy', () {
      final String xml = _xml(
        _write(
          _chart(
            ChartKind.line,
            series: <ChartSeries>[
              ChartSeries(
                name: ChartData<String>(values: const <String?>[]),
                categories: ChartData<Object>(
                  values: <Object?>[DateTime(2026, 1, 1), DateTime(2026, 1, 2)],
                ),
                values: ChartData<double>(values: const <double?>[1, 2]),
              ),
            ],
          ),
        ),
      );
      expect(
        xml,
        contains(
          '<c:cat><c:numLit><c:formatCode>m/d/yyyy</c:formatCode>'
          '<c:ptCount val="2"/><c:pt idx="0"><c:v>46023</c:v></c:pt>'
          '<c:pt idx="1"><c:v>46024</c:v></c:pt></c:numLit></c:cat>',
        ),
      );
    });

    test("date categories take the category axis' format", () {
      final String xml = _xml(
        _write(
          _chart(
            ChartKind.line,
            categoryAxis: const ChartAxis(formatCode: 'dd.mm.yyyy'),
            series: <ChartSeries>[
              ChartSeries(
                name: ChartData<String>(values: const <String?>[]),
                categories: ChartData<Object>(
                  values: <Object?>[DateTime(2026, 1, 1)],
                  reference: r'Sayfa1!$A$2',
                ),
                values: ChartData<double>(values: const <double?>[1]),
              ),
            ],
          ),
        ),
      );
      expect(
        xml,
        contains(
          r'<c:cat><c:numRef><c:f>Sayfa1!$A$2</c:f><c:numCache>'
          '<c:formatCode>dd.mm.yyyy</c:formatCode>',
        ),
      );
      expect(
        xml,
        contains('<c:numFmt formatCode="dd.mm.yyyy" sourceLinked="0"/>'),
      );
    });

    test('number categories write num, mixed ones str', () {
      ChartSeries series(List<Object?> categories) => ChartSeries(
        name: ChartData<String>(values: const <String?>[]),
        categories: ChartData<Object>(values: categories),
        values: ChartData<double>(values: const <double?>[1, 2]),
      );
      final String numbers = _xml(
        _write(
          _chart(
            ChartKind.column,
            series: <ChartSeries>[
              series(<Object?>[2025, 2026.5]),
            ],
          ),
        ),
      );
      expect(
        numbers,
        contains(
          '<c:cat><c:numLit><c:formatCode>General</c:formatCode>'
          '<c:ptCount val="2"/><c:pt idx="0"><c:v>2025</c:v></c:pt>'
          '<c:pt idx="1"><c:v>2026.5</c:v></c:pt></c:numLit></c:cat>',
        ),
      );
      final String mixed = _xml(
        _write(
          _chart(
            ChartKind.column,
            series: <ChartSeries>[
              series(<Object?>[2025, 'b']),
            ],
          ),
        ),
      );
      expect(mixed, contains('<c:pt idx="0"><c:v>2025</c:v></c:pt>'));
      expect(mixed, contains('<c:strLit>'));
    });
  });

  group('titles, axes, legend and labels', () {
    test('no title writes autoTitleDeleted 1 and no c:title', () {
      final String xml = _xml(_write(_chart(ChartKind.column)));
      expect(xml, contains('<c:chart><c:autoTitleDeleted val="1"/>'));
      expect(xml, isNot(contains('<c:title>')));
    });

    test('a title writes c:tx rich and ignores autoTitle', () {
      final DrawingChartWritten written = writeDrawingChartSpace(
        DrawingChartSpace(
          chart: _chart(
            ChartKind.column,
            title: const ChartTitle(text: 'Satışlar'),
          ),
          autoTitle: true,
        ),
        _office,
      );
      final String xml = _xml(written);
      expect(
        xml,
        contains(
          '<c:chart><c:title><c:tx><c:rich><a:bodyPr rot="0" '
          'spcFirstLastPara="1"',
        ),
      );
      expect(xml, contains('<a:t>Satışlar</a:t>'));
      expect(
        xml,
        contains(
          '</c:rich></c:tx><c:overlay val="0"/><c:spPr><a:noFill/>'
          '<a:ln><a:noFill/></a:ln><a:effectLst/></c:spPr><c:txPr>',
        ),
      );
      expect(xml, contains('</c:title><c:autoTitleDeleted val="0"/>'));
    });

    test('axis values write delete, grid lines, format and scaling', () {
      final String xml = _xml(
        _write(
          _chart(
            ChartKind.column,
            categoryAxis: const ChartAxis(
              visible: false,
              gridLines: true,
              title: 'Ay',
            ),
            valueAxis: const ChartAxis(
              min: 0,
              max: 100,
              majorUnit: 25,
              formatCode: '0%',
            ),
          ),
        ),
      );
      _expectWellFormed(xml);
      final String cat = RegExp('<c:catAx>.*</c:catAx>').firstMatch(xml)![0]!;
      final String val = RegExp('<c:valAx>.*</c:valAx>').firstMatch(xml)![0]!;
      expect(cat, contains('<c:delete val="1"/>'));
      expect(cat, contains('<c:majorGridlines>'));
      expect(cat, contains('<a:t>Ay</a:t>'));
      expect(cat, contains('</c:majorGridlines><c:title><c:tx><c:rich>'));
      expect(
        cat,
        contains('<c:numFmt formatCode="General" sourceLinked="1"/>'),
      );
      expect(val, isNot(contains('<c:majorGridlines>')));
      expect(val, contains('<c:delete val="0"/>'));
      expect(
        val,
        contains(
          '<c:scaling><c:orientation val="minMax"/><c:max val="100"/>'
          '<c:min val="0"/></c:scaling>',
        ),
      );
      expect(val, contains('<c:numFmt formatCode="0%" sourceLinked="0"/>'));
      expect(
        val,
        contains('<c:crossBetween val="between"/><c:majorUnit val="25"/>'),
      );
    });

    test('a visible legend writes legendPos and Excel blocks', () {
      for (final (ChartLegendPosition position, String code)
          in <(ChartLegendPosition, String)>[
            (ChartLegendPosition.bottom, 'b'),
            (ChartLegendPosition.top, 't'),
            (ChartLegendPosition.left, 'l'),
            (ChartLegendPosition.right, 'r'),
          ]) {
        final String xml = _xml(
          _write(
            _chart(ChartKind.column, legend: ChartLegend(position: position)),
          ),
        );
        expect(
          xml,
          contains(
            '</c:plotArea><c:legend><c:legendPos val="$code"/>'
            '<c:overlay val="0"/><c:spPr><a:noFill/><a:ln><a:noFill/></a:ln>'
            '<a:effectLst/></c:spPr><c:txPr><a:bodyPr rot="0" ',
          ),
        );
        expect(xml, contains('</c:legend><c:plotVisOnly val="1"/>'));
      }
    });

    test('a hidden legend writes no element', () {
      final String xml = _xml(_write(_chart(ChartKind.column)));
      expect(xml, isNot(contains('<c:legend>')));
    });

    test('visible data labels write the group dLbls', () {
      for (final (ChartKind kind, ChartGrouping grouping, String? position)
          in <(ChartKind, ChartGrouping, String?)>[
            (ChartKind.column, ChartGrouping.clustered, 'outEnd'),
            (ChartKind.bar, ChartGrouping.stacked, 'ctr'),
            (ChartKind.column, ChartGrouping.percentStacked, 'ctr'),
            (ChartKind.line, ChartGrouping.clustered, 'r'),
            (ChartKind.area, ChartGrouping.stacked, null),
          ]) {
        final String xml = _xml(
          _write(
            _chart(
              kind,
              grouping: grouping,
              dataLabels: const ChartDataLabels(
                visible: true,
                formatCode: '#,##0',
              ),
            ),
          ),
        );
        _expectWellFormed(xml);
        final String labels = RegExp(
          '</c:ser><c:dLbls>.*?</c:dLbls>',
        ).firstMatch(xml)![0]!;
        expect(
          labels,
          contains(
            '<c:dLbls><c:numFmt formatCode="#,##0" sourceLinked="0"/>'
            '<c:spPr><a:noFill/><a:ln><a:noFill/></a:ln><a:effectLst/>'
            '</c:spPr><c:txPr><a:bodyPr rot="0" spcFirstLastPara="1" '
            'vertOverflow="ellipsis" vert="horz" wrap="square" lIns="38100"',
          ),
        );
        expect(
          labels,
          endsWith(
            '${position == null ? '' : '<c:dLblPos val="$position"/>'}'
            '<c:showLegendKey val="0"/><c:showVal val="1"/>'
            '<c:showCatName val="0"/><c:showSerName val="0"/>'
            '<c:showPercent val="0"/><c:showBubbleSize val="0"/></c:dLbls>',
          ),
          reason: '$kind $grouping',
        );
      }
    });

    test('data labels without a format write no numFmt', () {
      final String xml = _xml(
        _write(
          _chart(
            ChartKind.column,
            dataLabels: const ChartDataLabels(visible: true),
          ),
        ),
      );
      expect(xml, contains('<c:dLbls><c:spPr>'));
    });
  });

  group('Review Focus', () {
    test('no series writes a well-formed part', () {
      final DrawingChartWritten written = _write(
        _chart(ChartKind.column, series: const <ChartSeries>[]),
      );
      final String xml = _xml(written);
      _expectWellFormed(xml);
      expect(xml, isNot(contains('<c:ser>')));
      expect(xml, contains('<c:varyColors val="0"/><c:dLbls>'));
      expect(written.issues, isEmpty);
    });

    test('empty values write ptCount 0', () {
      final DrawingChartWritten written = _write(
        _chart(
          ChartKind.line,
          series: <ChartSeries>[
            ChartSeries(
              name: ChartData<String>(values: const <String?>[]),
              categories: ChartData<Object>(values: const <Object?>[]),
              values: ChartData<double>(values: const <double?>[]),
            ),
          ],
        ),
      );
      final String xml = _xml(written);
      _expectWellFormed(xml);
      expect(
        xml,
        contains(
          '<c:val><c:numLit><c:formatCode>General</c:formatCode>'
          '<c:ptCount val="0"/></c:numLit></c:val>',
        ),
      );
      expect(xml, isNot(contains('<c:cat>')));
      expect(written.issues, isEmpty);
    });

    test('null, NaN and infinite values have no point', () {
      final DrawingChartWritten written = _write(
        _chart(
          ChartKind.column,
          series: <ChartSeries>[
            ChartSeries(
              name: ChartData<String>(values: const <String?>[]),
              categories: ChartData<Object>(values: const <Object?>[]),
              values: ChartData<double>(
                values: const <double?>[null, double.nan, 1, double.infinity],
              ),
            ),
          ],
        ),
      );
      final String xml = _xml(written);
      expect(
        xml,
        contains(
          '<c:ptCount val="4"/><c:pt idx="2"><c:v>1</c:v></c:pt></c:numLit>',
        ),
      );
      expect(_count(xml, '<c:pt '), 1);
      expect(written.issues, <DrawingChartIssue>[
        DrawingChartIssue.nonFiniteValue,
      ]);
    });

    test('references pass through unchanged', () {
      const List<String> references = <String>[
        r"'O''Brien'!$A$1:$A$3",
        '[0]!Tutarlar',
        r'Sheet1!$B$2:$B$5,Sheet1!$D$2',
      ];
      final String xml = _xml(
        _write(
          _chart(
            ChartKind.column,
            series: <ChartSeries>[
              ChartSeries(
                name: ChartData<String>(
                  values: const <String?>['n'],
                  reference: references[0],
                ),
                categories: ChartData<Object>(
                  values: const <Object?>['a'],
                  reference: references[1],
                ),
                values: ChartData<double>(
                  values: const <double?>[1],
                  reference: references[2],
                ),
              ),
            ],
          ),
        ),
      );
      final XmlPullReader r = XmlPullReader(xml);
      final List<String> read = <String>[];
      while (r.next()) {
        if (r.eventType == XmlEventType.startElement && r.localName == 'f') {
          r.next();
          read.add(r.text);
        }
      }
      expect(read, references);
    });

    test('a title with markup, a line break, an emoji and a control '
        'character', () {
      final DrawingChartWritten written = _write(
        _chart(
          ChartKind.column,
          title: const ChartTitle(text: 'a<b & "c"\n😀\u0001'),
        ),
      );
      final String xml = _xml(written);
      _expectWellFormed(xml);
      final String title = RegExp(
        '<c:title>.*?</c:title>',
      ).firstMatch(xml)![0]!;
      expect(_count(title, '<a:p>'), 3); // two in c:rich, one in c:txPr
      expect(title, contains('<a:t>a&lt;b &amp; "c"</a:t>'));
      expect(title, contains('<a:t>😀</a:t>'));
      expect(xml, isNot(contains('\u0001')));
      expect(written.issues, <DrawingChartIssue>[
        DrawingChartIssue.invalidCharacter,
      ]);
    });

    test('invalid characters in data are dropped and reported once', () {
      final DrawingChartWritten written = _write(
        _chart(
          ChartKind.column,
          series: <ChartSeries>[
            ChartSeries(
              name: ChartData<String>(values: const <String?>['n\u0002']),
              categories: ChartData<Object>(
                values: const <Object?>['a\u0000', 'b￿'],
              ),
              values: ChartData<double>(values: const <double?>[1, 2]),
            ),
          ],
        ),
      );
      final String xml = _xml(written);
      _expectWellFormed(xml);
      expect(xml, contains('<c:v>a</c:v>'));
      expect(xml, contains('<c:v>b</c:v>'));
      expect(xml, contains('<c:tx><c:v>n</c:v></c:tx>'));
      expect(written.issues, <DrawingChartIssue>[
        DrawingChartIssue.invalidCharacter,
      ]);
    });

    test('a series past the ids has no c:extLst', () {
      final DrawingChartWritten written = writeDrawingChartSpace(
        DrawingChartSpace(
          chart: _chart(
            ChartKind.column,
            series: <ChartSeries>[_excelSeries(), _excelSeries()],
          ),
          ids: const DrawingChartIds(series: <String>['{A}']),
        ),
        _office,
      );
      final String xml = _xml(written);
      expect(_count(xml, '<c16:uniqueId '), 1);
      expect(xml, contains('<c16:uniqueId val="{A}"/>'));
      expect(xml, contains('<c:axId val="500000001"/>'));
      expect(xml, contains('<c:axId val="500000002"/>'));
    });

    test('10,000 points write in linear time', () {
      ChartSeries long(int n) => ChartSeries(
        name: ChartData<String>(values: const <String?>[]),
        categories: ChartData<Object>(
          values: <Object?>[for (int i = 0; i < n; i++) 'c$i'],
        ),
        values: ChartData<double>(
          values: <double?>[for (int i = 0; i < n; i++) i * 0.5],
        ),
      );
      final DrawingChartWritten written = _write(
        _chart(ChartKind.line, series: <ChartSeries>[long(10000)]),
      );
      final String xml = _xml(written);
      _expectWellFormed(xml);
      expect(_count(xml, '<c:pt '), 20000);
    });
  });

  group('ArgumentError', () {
    test('for a kind the writer cannot express', () {
      for (final ChartKind kind in <ChartKind>[
        ChartKind.pie,
        ChartKind.donut,
        ChartKind.scatter,
        ChartKind.sparkline,
        ChartKind.combination,
        ChartKind.unsupported,
      ]) {
        expect(
          () => _write(_chart(kind)),
          throwsArgumentError,
          reason: kind.name,
        );
      }
    });

    test('for a secondary value axis', () {
      expect(
        () => _write(
          _chart(
            ChartKind.column,
          ).copyWith(secondaryValueAxis: const ChartAxis()),
        ),
        throwsArgumentError,
      );
      expect(
        () => _write(
          _chart(
            ChartKind.column,
            series: <ChartSeries>[
              _excelSeries().copyWith(axis: ChartAxisBinding.secondary),
            ],
          ),
        ),
        throwsArgumentError,
      );
    });

    test('for a series of another kind', () {
      expect(
        () => _write(
          _chart(
            ChartKind.column,
            series: <ChartSeries>[
              _excelSeries().copyWith(kind: ChartKind.line),
            ],
          ),
        ),
        throwsArgumentError,
      );
      // The chart's own kind is allowed.
      expect(
        _write(
          _chart(
            ChartKind.column,
            series: <ChartSeries>[
              _excelSeries().copyWith(kind: ChartKind.column),
            ],
          ),
        ).issues,
        isEmpty,
      );
    });
  });

  test('DrawingChartSpace and DrawingChartIds have value equality', () {
    DrawingChartSpace space() => DrawingChartSpace(
      chart: _chart(ChartKind.column),
      language: 'tr-TR',
      ids: DrawingChartIds(series: <String>['{', 'A}'.substring(0, 2)]),
    );
    expect(space(), space());
    expect(space().hashCode, space().hashCode);
    expect(space(), isNot(DrawingChartSpace(chart: _chart(ChartKind.column))));
    expect(
      const DrawingChartIds(categoryAxis: 1),
      isNot(const DrawingChartIds()),
    );
  });

  test('the part names', () {
    expect(
      drawingChartNamespace,
      'http://schemas.openxmlformats.org/drawingml/2006/chart',
    );
    expect(
      drawingChartContentType,
      'application/vnd.openxmlformats-officedocument.drawingml.chart+xml',
    );
    expect(
      drawingChartRelationshipType,
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
      'chart',
    );
  });
}
