/// The owner's E1 workbook, `chart_reference_j4.xlsx`: what Excel for Mac
/// 16.114.4 wrote for the J4 kinds, the source of the values
/// `packages/jet_charts_core/docs/excel-checks.md` ("J4 values") marks E1.
///
/// The sheet `Veri` and its seven charts follow
/// `test/fixtures/owner/charts/TALIMATLAR_J4.md`, but for two charts the
/// README there names (chart 4 took text x values, chart 5 has no secondary
/// axis). The reader does not type pies, doughnuts, scatter or combination
/// charts yet (C2 and C3), so this test pins Excel's values in the XML, and
/// how the reader reads each part today.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_office/src/drawingml/chart/chart_reader.dart';
import 'package:jet_office/src/drawingml/chart/chart_space.dart';
import 'package:test/test.dart';

import '../../support/read_xlsx.dart';

const String _path = 'test/fixtures/owner/charts/chart_reference_j4.xlsx';

void main() {
  late final Map<String, Uint8List> parts;
  setUpAll(() {
    final File file = File(_path);
    if (!file.existsSync()) {
      fail(
        "the owner's chart_reference_j4.xlsx is missing; see "
        'test/fixtures/owner/charts/TALIMATLAR_J4.md',
      );
    }
    parts = readXlsxBytes(file.readAsBytesSync());
  });

  String chart(int n) => utf8.decode(parts['xl/charts/chart$n.xml']!);
  String style(int n) => utf8.decode(parts['xl/charts/style$n.xml']!);
  String colors(int n) => utf8.decode(parts['xl/charts/colors$n.xml']!);

  test('holds seven charts, anchored in the steps\' order', () {
    final String drawing = utf8.decode(parts['xl/drawings/drawing1.xml']!);
    final List<String> ids = RegExp(
      r'<c:chart [^>]*r:id="(rId\d+)"',
    ).allMatches(drawing).map((RegExpMatch m) => m[1]!).toList();
    expect(ids, <String>[for (int i = 1; i <= 7; i++) 'rId$i']);
    final String rels = utf8.decode(
      parts['xl/drawings/_rels/drawing1.xml.rels']!,
    );
    for (int i = 1; i <= 7; i++) {
      expect(rels, contains('Id="rId$i"'));
      expect(rels, matches(RegExp('Id="rId$i"[^>]*chart$i.xml')));
    }
  });

  test('pies and doughnuts: first slice at 0, white 1.5 pt slice edges, '
      'varied accent colours, the legend at the bottom', () {
    for (final int n in <int>[1, 2, 3, 7]) {
      final String xml = chart(n);
      expect(xml, contains('<c:varyColors val="1"/>'), reason: '$n');
      expect(xml, contains('<c:firstSliceAng val="0"/>'), reason: '$n');
      expect(xml, contains('<c:legendPos val="b"/>'), reason: '$n');
      final Iterable<RegExpMatch> points = RegExp(
        '<c:dPt><c:idx val="(\\d)"/><c:bubble3D val="0"/><c:spPr>'
        '<a:solidFill><a:schemeClr val="(accent\\d)"/></a:solidFill>'
        '<a:ln w="19050"><a:solidFill><a:schemeClr val="lt1"/>',
      ).allMatches(xml);
      final int series = n == 3 ? 2 : 1;
      expect(points, hasLength(4 * series), reason: '$n');
      for (final RegExpMatch m in points) {
        expect(m[2], 'accent${int.parse(m[1]!) + 1}', reason: '$n');
      }
    }
    expect(chart(2), contains('<c:holeSize val="75"/>'));
    expect(chart(3), contains('<c:holeSize val="75"/>'));
    expect(chart(1), isNot(contains('c:holeSize')));
  });

  test("a pie's best fit labels are dark, 9 pt, with A6A6A6 leader lines", () {
    final String xml = chart(7);
    expect(xml, contains('<c:dLblPos val="bestFit"/>'));
    expect(xml, contains('<c:showVal val="1"/>'));
    expect(
      xml,
      contains(
        '<a:defRPr sz="900" b="0" i="0" u="none" strike="noStrike" '
        'kern="1200" baseline="0"><a:solidFill><a:schemeClr val="tx1">'
        '<a:lumMod val="75000"/><a:lumOff val="25000"/>',
      ),
    );
    expect(
      xml,
      contains(
        '<c:leaderLines><c:spPr><a:ln w="9525" cap="flat" cmpd="sng" '
        'algn="ctr"><a:solidFill><a:schemeClr val="tx1">'
        '<a:lumMod val="35000"/><a:lumOff val="65000"/>',
      ),
    );
  });

  test('a scatter chart: markers only, grid lines and axis lines on both '
      'axes', () {
    final String xml = chart(4);
    expect(xml, contains('<c:scatterStyle val="lineMarker"/>'));
    expect(
      RegExp(
        '<c:spPr><a:ln w="38100" cap="rnd"><a:noFill/><a:round/></a:ln>',
      ).allMatches(xml),
      hasLength(2),
    );
    expect(
      RegExp(
        '<c:marker><c:symbol val="circle"/><c:size val="5"/>',
      ).allMatches(xml),
      hasLength(2),
    );
    final List<String> axes = RegExp(
      '<c:valAx>.*?</c:valAx>',
    ).allMatches(xml).map((RegExpMatch m) => m[0]!).toList();
    expect(axes, hasLength(2));
    for (final String axis in axes) {
      expect(axis, contains('<c:majorGridlines>'));
      expect(axis, contains('<c:crossBetween val="midCat"/>'));
      expect(
        axis,
        contains(
          '<c:tickLblPos val="nextTo"/><c:spPr><a:noFill/><a:ln w="9525" '
          'cap="flat" cmpd="sng" algn="ctr"><a:solidFill>'
          '<a:schemeClr val="tx1"><a:lumMod val="25000"/>'
          '<a:lumOff val="75000"/>',
        ),
      );
    }
    expect(axes.first, isNot(contains('c:numFmt')));
    // The owner's selection took the text A2:A5 as x values.
    expect(xml, contains(r'<c:xVal><c:strRef><c:f>Veri!$A$2:$A$5</c:f>'));
  });

  test('a combination: columns gap 150 without overlap, then a 2.25 pt '
      'line without markers, on one value axis', () {
    final String xml = chart(5);
    expect(xml.indexOf('<c:barChart>'), lessThan(xml.indexOf('<c:lineChart>')));
    expect(xml, contains('<c:gapWidth val="150"/>'));
    expect(xml, isNot(contains('c:overlap')));
    expect(
      xml,
      contains(
        '<c:spPr><a:ln w="28575" cap="rnd"><a:solidFill>'
        '<a:schemeClr val="accent2"/></a:solidFill><a:round/></a:ln>'
        '<a:effectLst/></c:spPr><c:marker><c:symbol val="none"/></c:marker>',
      ),
    );
    expect(RegExp('<c:valAx>').allMatches(xml), hasLength(1));
  });

  test('a smoothed line keeps its markers and writes c:smooth 1', () {
    final String xml = chart(6);
    expect(xml, contains('</c:val><c:smooth val="1"/>'));
    expect(
      xml,
      contains('<c:marker><c:symbol val="circle"/><c:size val="5"/>'),
    );
    expect(xml, isNot(contains('<c:legend>')));
  });

  test('chart styles 251, 240, 322 and 332; colour style 10', () {
    const List<String> ids = <String>[
      '251', '251', '251', '240', '322', '332', '251', //
    ];
    for (int n = 1; n <= 7; n++) {
      expect(style(n), contains('id="${ids[n - 1]}"'), reason: '$n');
      expect(colors(n), contains('id="10"'), reason: '$n');
    }
  });

  test('the reader types the smooth line and leaves the other kinds to C2 '
      'and C3', () {
    for (int n = 1; n <= 7; n++) {
      final DrawingChartRead read = readDrawingChartSpace(
        parts['xl/charts/chart$n.xml']!,
      );
      if (n == 6) {
        expect(read.issues, isEmpty);
        expect(read.typed, isNotNull);
        expect(read.chart!.kind, ChartKind.line);
        expect(read.chart!.series.single.smooth, isTrue);
      } else {
        expect(read.typed, isNull, reason: '$n');
        expect(read.issues, <DrawingChartIssue>[
          DrawingChartIssue.unsupportedKind,
        ], reason: '$n');
      }
    }
  });
}
