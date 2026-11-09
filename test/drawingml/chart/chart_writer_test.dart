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

    test('series 7 of the Office theme writes accent 1 at lumMod 0.6', () {
      final List<ChartSeries> series = <ChartSeries>[
        for (int i = 0; i < 7; i++) _excelSeries(),
      ];
      final String xml = _xml(_write(_chart(ChartKind.column, series: series)));
      final ChartColor seventh = _office.colorOf(series[6], 6);
      expect(seventh.slot, ChartSchemeColor.accent1);
      expect(
        xml,
        contains(
          '<c:idx val="6"/><c:order val="6"/><c:spPr><a:solidFill>'
          '<a:schemeClr val="accent1"><a:lumMod val="60000"/>'
          '</a:schemeClr></a:solidFill>',
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

  group('markers', () {
    const String circle =
        '<c:marker><c:symbol val="circle"/><c:size val="5"/><c:spPr>';
    const String none = '<c:marker><c:symbol val="none"/></c:marker>';

    test('a line series has a circle marker when the theme has markers', () {
      final String xml = _xml(_write(_chart(ChartKind.line)));
      expect(_count(xml, circle), 1);
      expect(xml, isNot(contains(none)));
    });

    test('a line series has no marker when the theme has none', () {
      final String xml = _xml(
        _write(
          _chart(
            ChartKind.line,
            series: <ChartSeries>[_excelSeries(), _excelSeries()],
          ),
          theme: _office.copyWith(lineMarkers: false),
        ),
      );
      _expectWellFormed(xml);
      // Excel's "Line" without markers: the symbol none, and no size or
      // shape properties. A lone point gets no marker either (Excel cannot
      // mark single points of a series).
      expect(_count(xml, none), 2);
      expect(xml, isNot(contains('<c:symbol val="circle"/>')));
      expect(xml, isNot(contains('<c:size ')));
      expect(xml, contains('<c:marker val="1"/>'));
    });

    test('other kinds have no series marker either way', () {
      for (final ChartKind kind in <ChartKind>[
        ChartKind.column,
        ChartKind.bar,
        ChartKind.area,
      ]) {
        final String xml = _xml(
          _write(_chart(kind), theme: _office.copyWith(lineMarkers: false)),
        );
        expect(xml, isNot(contains('<c:marker>')), reason: kind.name);
      }
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

    test('invalid characters in format codes are dropped and reported', () {
      final DrawingChartWritten written = _write(
        _chart(
          ChartKind.column,
          categoryAxis: const ChartAxis(formatCode: 'dd\u0001.mm.yyyy'),
          valueAxis: const ChartAxis(formatCode: '0\u0002%'),
          dataLabels: const ChartDataLabels(
            visible: true,
            formatCode: '#\u0003,##0',
          ),
          series: <ChartSeries>[
            _excelSeries().copyWith(
              formatCode: '0.0\u0004',
              categories: ChartData<Object>(
                values: <Object?>[DateTime(2026, 1, 1)],
              ),
            ),
          ],
        ),
      );
      final String xml = _xml(written);
      _expectWellFormed(xml);
      expect(xml, contains('<c:formatCode>dd.mm.yyyy</c:formatCode>'));
      expect(xml, contains('<c:formatCode>0.0</c:formatCode>'));
      expect(xml, contains('formatCode="dd.mm.yyyy"'));
      expect(xml, contains('formatCode="0%"'));
      expect(xml, contains('formatCode="#,##0"'));
      expect(xml, isNot(matches(RegExp('[\u0001-\u0004]'))));
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
          ids: const DrawingChartIds(
            series: <String>['{00000000-0000-0000-0000-00000000000A}'],
          ),
        ),
        _office,
      );
      final String xml = _xml(written);
      expect(_count(xml, '<c16:uniqueId '), 1);
      expect(
        xml,
        contains(
          '<c16:uniqueId val="{00000000-0000-0000-0000-00000000000A}"/>',
        ),
      );
      expect(xml, contains('<c:axId val="500000001"/>'));
      expect(xml, contains('<c:axId val="500000002"/>'));
    });

    test('writes 10,000 points', () {
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

  group('clamping', () {
    test('gap width and overlap are clamped to Excel ranges', () {
      ChartTheme theme(double gap, double overlap) => _office.copyWith(
        gapWidthPercent: gap,
        spacing: _office.spacing.copyWith(overlapPercent: overlap),
      );
      String xml(ChartTheme t) =>
          _xml(_write(_chart(ChartKind.column), theme: t));
      final String high = xml(theme(600, 150));
      expect(high, contains('<c:gapWidth val="500"/>'));
      expect(high, contains('<c:overlap val="100"/>'));
      final String low = xml(theme(-5, -150.4));
      expect(low, contains('<c:gapWidth val="0"/>'));
      expect(low, contains('<c:overlap val="-100"/>'));
      final String fraction = xml(theme(150.6, -27.4));
      expect(fraction, contains('<c:gapWidth val="151"/>'));
      expect(fraction, contains('<c:overlap val="-27"/>'));
      expect(xml(theme(double.nan, 0)), contains('<c:gapWidth val="0"/>'));
    });
  });

  group('vertical axis titles', () {
    String axisTitleBodies(ChartKind kind, {required bool value}) {
      final String xml = _xml(
        _write(
          _chart(
            kind,
            categoryAxis: const ChartAxis(title: 'Ay'),
            valueAxis: const ChartAxis(title: 'Tutar'),
          ),
        ),
      );
      _expectWellFormed(xml);
      return RegExp(
        value ? '<c:valAx>.*</c:valAx>' : '<c:catAx>.*</c:catAx>',
      ).firstMatch(xml)![0]!;
    }

    test('the vertical axis title is turned as Excel does', () {
      for (final ChartKind kind in <ChartKind>[
        ChartKind.column,
        ChartKind.line,
        ChartKind.area,
        ChartKind.bar,
      ]) {
        final bool barChart = kind == ChartKind.bar;
        final String vertical = axisTitleBodies(kind, value: !barChart);
        final String horizontal = axisTitleBodies(kind, value: barChart);
        final String title = RegExp(
          '<c:title>.*?</c:title>',
        ).firstMatch(vertical)![0]!;
        expect(
          _count(
            title,
            '<a:bodyPr rot="-5400000" spcFirstLastPara="1" '
            'vertOverflow="ellipsis" vert="horz" ',
          ),
          2,
          reason: '${kind.name}: c:rich and c:txPr',
        );
        final String flat = RegExp(
          '<c:title>.*?</c:title>',
        ).firstMatch(horizontal)![0]!;
        expect(_count(flat, '<a:bodyPr rot="0" '), 2, reason: kind.name);
        expect(flat, isNot(contains('-5400000')));
      }
    });

    test('the chart title stays flat', () {
      final String xml = _xml(
        _write(_chart(ChartKind.column, title: const ChartTitle(text: 'T'))),
      );
      expect(xml, isNot(contains('-5400000')));
    });
  });

  group('ids', () {
    test('axis ids must be unsigned 32-bit and distinct', () {
      for (final DrawingChartIds ids in <DrawingChartIds>[
        const DrawingChartIds(categoryAxis: -1),
        const DrawingChartIds(valueAxis: 4294967296),
        const DrawingChartIds(categoryAxis: 7, valueAxis: 7),
      ]) {
        expect(
          () => writeDrawingChartSpace(
            DrawingChartSpace(chart: _chart(ChartKind.column), ids: ids),
            _office,
          ),
          throwsArgumentError,
          reason: '$ids',
        );
      }
      expect(
        writeDrawingChartSpace(
          DrawingChartSpace(
            chart: _chart(ChartKind.column),
            ids: const DrawingChartIds(categoryAxis: 0, valueAxis: 4294967295),
          ),
          _office,
        ).issues,
        isEmpty,
      );
    });

    test('series unique ids must be braced GUIDs', () {
      for (final String id in <String>[
        '00000000-8918-7940-9A01-4B67489FEBC8',
        '{00000000-8918-7940-9A01-4B67489FEBC}',
        '{G0000000-8918-7940-9A01-4B67489FEBC8}',
        '{00000000-8918-7940-9A01-4B67489FEBC8}x',
        '',
      ]) {
        expect(
          () => writeDrawingChartSpace(
            DrawingChartSpace(
              chart: _chart(ChartKind.column),
              ids: DrawingChartIds(series: <String>[id]),
            ),
            _office,
          ),
          throwsArgumentError,
          reason: id,
        );
      }
      // An id for a series the chart lacks is still checked.
      expect(
        () => writeDrawingChartSpace(
          DrawingChartSpace(
            chart: _chart(ChartKind.column),
            ids: const DrawingChartIds(
              series: <String>['{00000000-8918-7940-9a01-4b67489febc8}', 'x'],
            ),
          ),
          _office,
        ),
        throwsArgumentError,
      );
    });
  });

  group('xstring escaping', () {
    test('Xstring look-alikes are escaped in c:v, c:f and c:formatCode, not '
        'in a:t', () {
      final String xml = _xml(
        _write(
          _chart(
            ChartKind.column,
            title: const ChartTitle(text: 'T_x0041_'),
            series: <ChartSeries>[
              ChartSeries(
                name: ChartData<String>(
                  values: const <String?>['n_x0041_'],
                  reference: r"'_x0042_'!$B$1",
                ),
                categories: ChartData<Object>(
                  values: const <Object?>['_x0043_'],
                ),
                values: ChartData<double>(
                  values: const <double?>[1],
                  reference: r"'_x0042_'!$B$2",
                ),
                formatCode: '0_x0044_',
              ),
            ],
          ),
        ),
      );
      expect(xml, contains('<c:v>n_x005F_x0041_</c:v>'));
      expect(xml, contains(r"<c:f>'_x005F_x0042_'!$B$1</c:f>"));
      expect(xml, contains(r"<c:f>'_x005F_x0042_'!$B$2</c:f>"));
      expect(xml, contains('<c:v>_x005F_x0043_</c:v>'));
      expect(xml, contains('<c:formatCode>0_x005F_x0044_</c:formatCode>'));
      expect(xml, contains('<a:t>T_x0041_</a:t>'));
    });
  });

  group('ArgumentError', () {
    test('for a theme value the part cannot hold, naming the field', () {
      final ChartTextStyle text = _office.axisLabels.copyWith(size: 9);
      final Map<String, ChartTheme> themes = <String, ChartTheme>{
        for (final double v in <double>[double.nan, double.infinity, -1, 1585])
          'lineWidth $v': _office.copyWith(lineWidth: v),
        for (final double v in <double>[double.nan, double.infinity, -1])
          'markerSize $v': _office.copyWith(markerSize: v),
        'spacing.gridLineWidth 1585': _office.copyWith(
          spacing: _office.spacing.copyWith(gridLineWidth: 1585),
        ),
        'spacing.axisLineWidth 1585': _office.copyWith(
          spacing: _office.spacing.copyWith(axisLineWidth: 1585),
        ),
        for (final double v in <double>[
          double.nan,
          double.infinity,
          0.5,
          -9,
          4001,
        ]) ...<String, ChartTheme>{
          'titleText.size $v': _office.copyWith(
            titleText: text.copyWith(size: v),
          ),
          'axisLabels.size $v': _office.copyWith(
            axisLabels: text.copyWith(size: v),
          ),
          'legendText.size $v': _office.copyWith(
            legendText: text.copyWith(size: v),
          ),
          'dataLabels.size $v': _office.copyWith(
            dataLabels: text.copyWith(size: v),
          ),
        },
      };
      themes.forEach((String label, ChartTheme theme) {
        final String field = label.substring(0, label.indexOf(' '));
        for (final ChartKind kind in <ChartKind>[
          ChartKind.column,
          ChartKind.line,
        ]) {
          expect(
            () => _write(_chart(kind), theme: theme),
            throwsA(
              isA<ArgumentError>().having(
                (ArgumentError e) => e.name,
                'name',
                'theme.$field',
              ),
            ),
            reason: '$label, ${kind.name}',
          );
        }
      });
    });

    test('not for theme values at the bounds the part can hold', () {
      final ChartTextStyle text = _office.axisLabels.copyWith(size: 1);
      for (final ChartTheme theme in <ChartTheme>[
        _office.copyWith(
          lineWidth: 0,
          markerSize: 0,
          titleText: text,
          axisLabels: text,
          legendText: text,
          dataLabels: text,
        ),
        _office.copyWith(
          lineWidth: 1584,
          markerSize: 1e300,
          spacing: _office.spacing.copyWith(
            gridLineWidth: 1584,
            axisLineWidth: 1584,
          ),
          titleText: text.copyWith(size: 4000),
          axisLabels: text.copyWith(size: 4000),
          legendText: text.copyWith(size: 4000),
          dataLabels: text.copyWith(size: 4000),
        ),
      ]) {
        final String xml = _xml(
          _write(
            _chart(
              ChartKind.line,
              title: const ChartTitle(text: 'T'),
              legend: const ChartLegend(),
              dataLabels: const ChartDataLabels(visible: true),
            ),
            theme: theme,
          ),
        );
        _expectWellFormed(xml);
      }
    });

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
