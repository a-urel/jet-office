/// The owner's two Excel workbooks with charts: every chart part reads typed,
/// and what it shows is what the owner's instructions made it show.
///
/// `chart_defaults.xlsx` (two charts of one series) and `chart_reference.xlsx`
/// (23 charts of `Veri!A1:C5`, built by the steps in
/// `test/fixtures/owner/charts/TALIMATLAR.md` through Office.js in Excel for
/// Mac 16.0300) are committed. The reference group fails on any chart that
/// does not read as [_expectations] says: typed (or, for the one chart the
/// typed form cannot express, untyped with its reason) and showing what the
/// owner's steps made it show.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_office/src/drawingml/chart/chart_reader.dart';
import 'package:test/test.dart';

import '../../support/read_xlsx.dart';

const String _referencePath = 'test/fixtures/owner/charts/chart_reference.xlsx';

/// What one chart of the reference workbook must show; a `null` field is not
/// checked, so a default stays whatever Excel gives it.
class _Expect {
  const _Expect(
    this.name,
    this.kind,
    this.grouping, {
    this.title,
    this.legend = const ChartLegend(),
    this.categoryTitle,
    this.valueTitle,
    this.min,
    this.max,
    this.majorUnit,
    this.valueFormat,
    this.labels = false,
    this.labelFormat,
    this.valueAxisVisible = true,
    this.gridLines = true,
    this.autoTitle = true,
    this.untypedReason,
  });

  final String name;
  final ChartKind kind;
  final ChartGrouping grouping;
  final String? title;
  final ChartLegend legend;
  final String? categoryTitle;
  final String? valueTitle;
  final double? min;
  final double? max;
  final double? majorUnit;
  final String? valueFormat;
  final bool labels;
  final String? labelFormat;
  final bool valueAxisVisible;
  final bool gridLines;

  /// Whether the typed form has Excel's automatic title: every chart of two
  /// series made through Office.js has one (a `c:title` without text and
  /// `c:autoTitleDeleted` 0), except the one given a title.
  final bool autoTitle;

  /// Why the chart is not typed, or `null` when it must read typed.
  final String? untypedReason;
}

const ChartLegend _hidden = ChartLegend(visible: false);

/// One entry per chart, in TALIMATLAR's order (1 to 23).
const List<_Expect> _expectations = <_Expect>[
  _Expect('1 clustered column', ChartKind.column, ChartGrouping.clustered),
  _Expect('2 stacked column', ChartKind.column, ChartGrouping.stacked),
  _Expect('3 100% column', ChartKind.column, ChartGrouping.percentStacked),
  _Expect('4 clustered bar', ChartKind.bar, ChartGrouping.clustered),
  _Expect('5 stacked bar', ChartKind.bar, ChartGrouping.stacked),
  _Expect('6 100% bar', ChartKind.bar, ChartGrouping.percentStacked),
  _Expect('7 line', ChartKind.line, ChartGrouping.clustered),
  _Expect('8 stacked line', ChartKind.line, ChartGrouping.stacked),
  _Expect('9 100% line', ChartKind.line, ChartGrouping.percentStacked),
  _Expect('10 area', ChartKind.area, ChartGrouping.clustered),
  _Expect('11 stacked area', ChartKind.area, ChartGrouping.stacked),
  _Expect('12 100% area', ChartKind.area, ChartGrouping.percentStacked),
  _Expect(
    '13 title',
    ChartKind.column,
    ChartGrouping.clustered,
    title: 'Satışlar',
    autoTitle: false,
    untypedReason:
        "the title's run is `lang=\"en-US\"` while the part's `c:lang` and "
        'every other text are `tr-TR` (Office.js set the text); the typed '
        'form carries one language (ruling R3 of C1)',
  ),
  _Expect(
    '14 legend top',
    ChartKind.column,
    ChartGrouping.clustered,
    legend: ChartLegend(position: ChartLegendPosition.top),
  ),
  _Expect(
    '15 legend right',
    ChartKind.column,
    ChartGrouping.clustered,
    legend: ChartLegend(position: ChartLegendPosition.right),
  ),
  _Expect(
    '16 no legend',
    ChartKind.column,
    ChartGrouping.clustered,
    legend: _hidden,
  ),
  _Expect(
    '17 axis titles',
    ChartKind.column,
    ChartGrouping.clustered,
    categoryTitle: 'Çeyrek',
    valueTitle: 'Tutar',
  ),
  _Expect(
    '18 axis scale',
    ChartKind.column,
    ChartGrouping.clustered,
    min: 0,
    max: 50,
    majorUnit: 10,
  ),
  _Expect(
    '19 axis format',
    ChartKind.column,
    ChartGrouping.clustered,
    valueFormat: '#,##0.00',
  ),
  _Expect('20 labels', ChartKind.column, ChartGrouping.clustered, labels: true),
  _Expect(
    '21 label format',
    ChartKind.column,
    ChartGrouping.clustered,
    labels: true,
    labelFormat: '0.0',
  ),
  _Expect(
    '22 no value axis',
    ChartKind.column,
    ChartGrouping.clustered,
    valueAxisVisible: false,
    gridLines: false,
  ),
  _Expect('23 name', ChartKind.column, ChartGrouping.clustered),
];

/// The chart part names of [parts] in the order of their anchors: each
/// worksheet's drawing, its `c:chart` frames in document order, each
/// resolved through the drawing's relationships.
///
/// It assumes that the anchors' document order is the order the owner made
/// the charts in (`TALIMATLAR.md`: "Sırayı koru", keep the order), which is
/// what Excel writes, and that the sheet and the drawing name their parts
/// with the prefixes Excel writes (`r:id` on `drawing`, `c:chart` with
/// `r:id`). A relationship target is resolved relative to the part's folder,
/// or from the package root when it starts with `/` (`/xl/charts/...`).
List<String> _chartsInAnchorOrder(Map<String, Uint8List> parts) {
  String text(String name) => utf8.decode(parts[name]!);
  String? target(String relsName, String id, String base) {
    final String? rels = parts[relsName] == null ? null : text(relsName);
    if (rels == null) return null;
    for (final RegExpMatch m in RegExp(
      r'<Relationship\b[^>]*>',
    ).allMatches(rels)) {
      final String tag = m.group(0)!;
      if (RegExp('\\bId="$id"').hasMatch(tag)) {
        final String? t = RegExp(
          r'\bTarget="([^"]*)"',
        ).firstMatch(tag)?.group(1);
        if (t == null) return null;
        return t.startsWith('/')
            ? Uri.parse(t).normalizePath().path.substring(1)
            : Uri.parse('$base/$t').normalizePath().path;
      }
    }
    return null;
  }

  final List<String> sheets =
      parts.keys
          .where(
            (String k) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(k),
          )
          .toList()
        ..sort(_byNumber);
  final List<String> result = <String>[];
  for (final String sheet in sheets) {
    final String sheetRels =
        'xl/worksheets/_rels/${sheet.split('/').last}.rels';
    final String? drawingId = RegExp(
      r'<drawing\b[^>]*\br:id="([^"]*)"',
    ).firstMatch(text(sheet))?.group(1);
    if (drawingId == null) continue;
    final String? drawing = target(sheetRels, drawingId, 'xl/worksheets');
    if (drawing == null || parts[drawing] == null) continue;
    final String drawingRels =
        '${drawing.substring(0, drawing.lastIndexOf('/'))}/_rels/'
        '${drawing.split('/').last}.rels';
    final String dir = drawing.substring(0, drawing.lastIndexOf('/'));
    for (final RegExpMatch m in RegExp(
      r'<c:chart\b[^>]*\br:id="([^"]*)"',
    ).allMatches(text(drawing))) {
      final String? chart = target(drawingRels, m.group(1)!, dir);
      if (chart != null) result.add(chart);
    }
  }
  return result;
}

int _byNumber(String a, String b) => int.parse(
  RegExp(r'(\d+)\.xml$').firstMatch(a)!.group(1)!,
).compareTo(int.parse(RegExp(r'(\d+)\.xml$').firstMatch(b)!.group(1)!));

void _expectSeries(Chart chart, String name) {
  expect(chart.series, hasLength(2), reason: name);
  const List<String> names = <String>['Kuzey', 'Güney'];
  const List<String> columns = <String>['B', 'C'];
  for (int i = 0; i < 2; i++) {
    final ChartSeries s = chart.series[i];
    expect(s.name.values, <String?>[names[i]], reason: '$name series $i');
    expect(s.name.reference, 'Veri!\$${columns[i]}\$1', reason: name);
    expect(s.categories.reference, 'Veri!\$A\$2:\$A\$5', reason: name);
    expect(
      s.values.reference,
      'Veri!\$${columns[i]}\$2:\$${columns[i]}\$5',
      reason: name,
    );
  }
}

void main() {
  group('chart_defaults.xlsx', () {
    final Map<String, Uint8List> parts = readXlsxBytes(
      File(
        'packages/jet_charts_core/test/fixtures/owner/axis_full/'
        'chart_defaults.xlsx',
      ).readAsBytesSync(),
    );
    final List<String> charts =
        parts.keys
            .where(
              (String k) => RegExp(r'^xl/charts/chart\d+\.xml$').hasMatch(k),
            )
            .toList()
          ..sort(_byNumber);

    test('holds two chart parts', () => expect(charts, hasLength(2)));

    test('the anchor order finds both parts through the drawing', () {
      expect(_chartsInAnchorOrder(parts), <String>[
        'xl/charts/chart1.xml',
        'xl/charts/chart2.xml',
      ]);
    });

    test('the anchor order resolves absolute targets too', () {
      final Map<String, Uint8List> absolute = <String, Uint8List>{
        for (final MapEntry<String, Uint8List> e in parts.entries)
          e.key: e.key.endsWith('.xml.rels')
              ? utf8.encode(
                  utf8
                      .decode(e.value)
                      .replaceAll('Target="../charts/', 'Target="/xl/charts/')
                      .replaceAll(
                        'Target="../drawings/',
                        'Target="/xl/drawings/',
                      ),
                )
              : e.value,
      };
      expect(
        absolute.values.any(
          (Uint8List b) => utf8.decode(b).contains('Target="/xl/charts/'),
        ),
        isTrue,
      );
      expect(_chartsInAnchorOrder(absolute), <String>[
        'xl/charts/chart1.xml',
        'xl/charts/chart2.xml',
      ]);
    });

    for (final String name in charts) {
      test('$name reads typed as Excel wrote it', () {
        final DrawingChartRead read = readDrawingChartSpace(parts[name]!);
        expect(read.issues, isEmpty);
        expect(read.typed, isNotNull);
        final Chart chart = read.chart!;
        expect(
          chart.kind,
          name.endsWith('chart1.xml') ? ChartKind.column : ChartKind.line,
        );
        expect(chart.grouping, ChartGrouping.clustered);
        expect(chart.title, isNull);
        expect(chart.legend.visible, isFalse);
        expect(chart.series, hasLength(1));
        expect(chart.series.single.values.reference, r'Sayfa1!$B$1:$B$3');
        expect(chart.series.single.categories.reference, r'Sayfa1!$A$1:$A$3');
      });
    }
  });

  final File reference = File(_referencePath);
  group('chart_reference.xlsx', () {
    late final Map<String, Uint8List> parts;
    late final List<String> charts;
    setUpAll(() {
      if (!reference.existsSync()) {
        fail(
          "the owner's chart_reference.xlsx is missing; see "
          'test/fixtures/owner/charts/TALIMATLAR.md',
        );
      }
      parts = readXlsxBytes(reference.readAsBytesSync());
      charts = _chartsInAnchorOrder(parts);
    });

    test('has 23 charts in the anchors', () {
      expect(charts, hasLength(_expectations.length));
      expect(charts.toSet(), hasLength(charts.length));
    });

    for (int i = 0; i < _expectations.length; i++) {
      final _Expect e = _expectations[i];
      test('chart ${e.name}', () {
        final DrawingChartRead read = readDrawingChartSpace(parts[charts[i]]!);
        expect(read.issues, isEmpty, reason: charts[i]);
        if (e.untypedReason == null) {
          expect(read.typed, isNotNull, reason: charts[i]);
          expect(read.typed!.autoTitle, e.autoTitle, reason: e.name);
          expect(read.typed!.language, 'tr-TR', reason: e.name);
        } else {
          expect(read.typed, isNull, reason: e.untypedReason);
        }
        final Chart chart = read.chart!;
        expect(chart.kind, e.kind, reason: e.name);
        expect(chart.grouping, e.grouping, reason: e.name);
        _expectSeries(chart, e.name);
        expect(chart.title?.text, e.title, reason: e.name);
        expect(chart.legend.visible, e.legend.visible, reason: e.name);
        if (e.legend.visible) {
          expect(chart.legend.position, e.legend.position, reason: e.name);
        }
        expect(chart.categoryAxis.title, e.categoryTitle, reason: e.name);
        expect(chart.valueAxis.title, e.valueTitle, reason: e.name);
        expect(chart.valueAxis.min, e.min, reason: e.name);
        expect(chart.valueAxis.max, e.max, reason: e.name);
        expect(chart.valueAxis.majorUnit, e.majorUnit, reason: e.name);
        if (e.valueFormat != null) {
          expect(chart.valueAxis.formatCode, e.valueFormat, reason: e.name);
        }
        expect(chart.dataLabels.visible, e.labels, reason: e.name);
        if (e.labelFormat != null) {
          expect(chart.dataLabels.formatCode, e.labelFormat, reason: e.name);
        }
        expect(chart.valueAxis.visible, e.valueAxisVisible, reason: e.name);
        expect(chart.valueAxis.gridLines, e.gridLines, reason: e.name);
        if (e.name.startsWith('23')) {
          // Office.js resolved the name `Tutarlar` to its range, so this
          // chart does not answer whether Excel writes `[0]!Tutarlar`
          // (docs/drawingml-charts.md, "Open for C2").
          expect(
            chart.series.first.values.reference,
            r'Veri!$B$2:$B$5',
            reason: e.name,
          );
        }
      });
    }
  });
}
