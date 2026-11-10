import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_gallery/gallery.dart';
import 'package:jet_charts_gallery/src/excel_chart_style.dart';
import 'package:jet_charts_gallery/src/excel_gallery.dart';
import 'package:xml/xml.dart';

void main() {
  final List<GalleryEntry> entries = galleryEntries();
  final Uint8List bytes = buildExcelGallery(entries);
  final Archive archive = ZipDecoder().decodeBytes(bytes);

  String part(String name) {
    final ArchiveFile? file = archive.findFile(name);
    expect(file, isNotNull, reason: name);
    return utf8.decode(file!.content);
  }

  XmlDocument xml(String name) => XmlDocument.parse(part(name));

  Iterable<XmlElement> all(XmlNode node, String name) => node.descendants
      .whereType<XmlElement>()
      .where((XmlElement e) => e.name.qualified == name);

  String? val(XmlNode node, String name) =>
      all(node, name).firstOrNull?.getAttribute('val');

  bool sparkline(GalleryEntry e) => e.chart.kind == ChartKind.sparkline;

  /// The 1-based indexes of the entries that get a chart part.
  final List<int> charted = <int>[
    for (int i = 1; i <= entries.length; i++)
      if (!sparkline(entries[i - 1])) i,
  ];

  int indexOf(String name) =>
      entries.indexWhere((GalleryEntry e) => e.name == name) + 1;

  XmlDocument chartOf(String name) =>
      xml('xl/charts/chart${indexOf(name)}.xml');

  test('every part is well-formed XML', () {
    for (final ArchiveFile file in archive.files) {
      if (!file.isFile) continue;
      expect(
        () => XmlDocument.parse(utf8.decode(file.content)),
        returnsNormally,
        reason: file.name,
      );
    }
  });

  test('one sheet per entry, named by the entry, and one chart part per '
      'entry but a sparkline', () {
    final XmlDocument workbook = xml('xl/workbook.xml');
    final List<String> names = <String>[
      for (final XmlElement sheet in all(workbook, 'sheet'))
        sheet.getAttribute('name')!,
    ];
    expect(names, <String>[
      for (final GalleryEntry e in entries)
        e.name.length > 31 ? e.name.substring(0, 31) : e.name,
    ]);
    for (int i = 1; i <= entries.length; i++) {
      expect(archive.findFile('xl/worksheets/sheet$i.xml'), isNotNull);
      expect(
        archive.findFile('xl/charts/chart$i.xml'),
        sparkline(entries[i - 1]) ? isNull : isNotNull,
        reason: entries[i - 1].name,
      );
    }
    expect(charted, hasLength(entries.length - 2));
    expect(
      archive.findFile('xl/charts/chart${entries.length + 1}.xml'),
      isNull,
    );
  });

  test('each chart is anchored at 360 by 216 points', () {
    for (final int i in charted) {
      final XmlElement ext = all(
        xml('xl/drawings/drawing$i.xml'),
        'xdr:ext',
      ).single;
      expect(ext.getAttribute('cx'), '${360 * 12700}');
      expect(ext.getAttribute('cy'), '${216 * 12700}');
    }
  });

  test('each chart has its entry\'s kind, grouping, title, legend and '
      'labels', () {
    for (final int i in charted) {
      final GalleryEntry entry = entries[i - 1];
      final Chart chart = entry.chart;
      final XmlDocument doc = xml('xl/charts/chart$i.xml');
      final String reason = entry.name;
      switch (chart.kind) {
        case ChartKind.column || ChartKind.bar:
          expect(
            val(doc, 'c:barDir'),
            chart.kind == ChartKind.bar ? 'bar' : 'col',
            reason: reason,
          );
          expect(val(doc, 'c:grouping'), chart.grouping.name, reason: reason);
        case ChartKind.line:
          // One line group per value axis.
          final bool secondary = chart.series.any(
            (ChartSeries s) => s.axis == ChartAxisBinding.secondary,
          );
          expect(
            all(doc, 'c:lineChart'),
            hasLength(secondary ? 2 : 1),
            reason: reason,
          );
          expect(val(doc, 'c:grouping'), switch (chart.grouping) {
            ChartGrouping.clustered => 'standard',
            ChartGrouping.stacked => 'stacked',
            ChartGrouping.percentStacked => 'percentStacked',
          }, reason: reason);
        case ChartKind.area:
          expect(all(doc, 'c:areaChart'), hasLength(1), reason: reason);
          expect(val(doc, 'c:grouping'), chart.grouping.name, reason: reason);
        case ChartKind.pie:
          expect(all(doc, 'c:pieChart'), hasLength(1), reason: reason);
        case ChartKind.donut:
          expect(all(doc, 'c:doughnutChart'), hasLength(1), reason: reason);
        case ChartKind.scatter:
          expect(all(doc, 'c:scatterChart'), hasLength(1), reason: reason);
        case ChartKind.combination:
          expect(all(doc, 'c:barChart'), hasLength(1), reason: reason);
          expect(all(doc, 'c:lineChart'), hasLength(1), reason: reason);
        default:
          fail('$reason: unexpected kind ${chart.kind}');
      }
      final String title = <String>[
        // The chart's own title, not an axis title.
        for (final XmlElement t in all(doc, 'c:chart').single.childElements)
          if (t.name.qualified == 'c:title')
            for (final XmlElement r in all(t, 'a:t')) r.innerText,
      ].join();
      expect(title, entry.excelTitle, reason: reason);
      expect(
        val(doc, 'c:autoTitleDeleted'),
        entry.excelTitle.isEmpty ? '1' : '0',
        reason: reason,
      );
      if (chart.legend.visible) {
        expect(val(doc, 'c:legendPos'), switch (chart.legend.position) {
          ChartLegendPosition.top => 't',
          ChartLegendPosition.bottom => 'b',
          ChartLegendPosition.left => 'l',
          ChartLegendPosition.right => 'r',
        }, reason: reason);
      } else {
        expect(all(doc, 'c:legend'), isEmpty, reason: reason);
      }
      final XmlElement? labels = all(doc, 'c:dLbls').firstOrNull;
      expect(
        labels == null ? '0' : val(labels, 'c:showVal'),
        chart.dataLabels.visible && chart.dataLabels.showValue ? '1' : '0',
        reason: reason,
      );
      expect(
        labels == null ? '0' : val(labels, 'c:showPercent'),
        chart.dataLabels.visible && chart.dataLabels.showPercent ? '1' : '0',
        reason: reason,
      );
      // Only a point colour the chart itself sets is written as an RGB.
      final int ownColours = <ChartColor?>[
        for (final ChartSeries series in chart.series) ...series.pointColors,
      ].nonNulls.length;
      expect(
        all(doc, 'a:srgbClr'),
        hasLength(ownColours),
        reason: '$reason: own colours',
      );
      expect(all(doc, 'c:manualLayout'), isEmpty, reason: '$reason: layout');
      for (final XmlElement latin in all(doc, 'a:latin')) {
        expect(
          latin.getAttribute('typeface'),
          startsWith('+'),
          reason: '$reason: own font',
        );
      }
    }
  });

  test('series refer to their sheet\'s cells and cache the values', () {
    for (final int i in charted) {
      final GalleryEntry entry = entries[i - 1];
      final XmlDocument doc = xml('xl/charts/chart$i.xml');
      final List<XmlElement> sers = all(doc, 'c:ser').toList();
      expect(sers, hasLength(entry.chart.series.length), reason: entry.name);
      for (int s = 0; s < sers.length; s++) {
        final ChartSeries series = entry.chart.series[s];
        // A scatter series has its own x column before its values.
        final bool scatter = entry.chart.kind == ChartKind.scatter;
        final String column = String.fromCharCode(
          scatter ? 66 + 2 * s : 66 + s,
        );
        final String x = scatter ? String.fromCharCode(65 + 2 * s) : 'A';
        final int last = series.values.values.length + 1;
        final List<String> refs = <String>[
          for (final XmlElement f in all(sers[s], 'c:f')) f.innerText,
        ];
        expect(refs, <String>[
          "'${entry.name}'!\$$column\$1",
          "'${entry.name}'!\$$x\$2:\$$x\$$last",
          "'${entry.name}'!\$$column\$2:\$$column\$$last",
        ], reason: entry.name);
        // A scatter series caches its x values first, its values last.
        final XmlElement cache = all(sers[s], 'c:numCache').last;
        final List<double?> cached = List<double?>.filled(
          series.values.values.length,
          null,
        );
        for (final XmlElement pt in all(cache, 'c:pt')) {
          cached[int.parse(pt.getAttribute('idx')!)] = double.parse(
            all(pt, 'c:v').single.innerText,
          );
        }
        expect(cached, series.values.values, reason: entry.name);
        expect(
          all(cache, 'c:formatCode').single.innerText,
          series.formatCode ?? 'General',
          reason: entry.name,
        );
      }
    }
  });

  // Excel reads rot="-60000000" (its "automatic" angle) as vertical text
  // outside an axis, so the legend and data labels take rot="0", as Excel
  // writes them.
  test('only axis labels take the automatic text angle', () {
    for (final int i in charted) {
      final XmlDocument doc = xml('xl/charts/chart$i.xml');
      for (final String owner in <String>['c:legend', 'c:dLbls']) {
        for (final XmlElement e in all(doc, owner)) {
          for (final XmlElement body in all(e, 'a:bodyPr')) {
            expect(
              body.getAttribute('rot'),
              '0',
              reason: '${entries[i - 1].name}: $owner',
            );
          }
        }
      }
      for (final String axis in <String>['c:catAx', 'c:valAx']) {
        for (final XmlElement e in all(doc, axis)) {
          final XmlElement txPr = e.childElements.firstWhere(
            (XmlElement c) => c.name.qualified == 'c:txPr',
          );
          expect(
            all(txPr, 'a:bodyPr').single.getAttribute('rot'),
            '-60000000',
            reason: '${entries[i - 1].name}: $axis',
          );
        }
      }
    }
  });

  // Excel draws a series without c:spPr from its legacy colours, not from
  // the colour cycle it gives a new chart (the owner's check, 2026-11-09), so
  // series 7 and 8 name the cycle's colour as Excel writes it in a new chart.
  test('series 7 and 8 of column_eight_series carry the cycle\'s colour', () {
    final int index =
        entries.indexWhere(
          (GalleryEntry e) => e.name == 'column_eight_series',
        ) +
        1;
    final List<XmlElement> sers = all(
      xml('xl/charts/chart$index.xml'),
      'c:ser',
    ).toList();
    expect(sers, hasLength(8));
    for (int s = 0; s < 8; s++) {
      final XmlElement fill = all(
        all(sers[s], 'c:spPr').single,
        'a:schemeClr',
      ).first;
      expect(fill.getAttribute('val'), 'accent${s % 6 + 1}', reason: '$s');
      expect(val(fill, 'a:lumMod'), s < 6 ? isNull : '60000', reason: '$s');
      expect(val(fill, 'a:lumOff'), isNull, reason: '$s');
    }
  });

  test("each chart has Excel's colour and style parts", () {
    // The owner's Excel-saved default chart, whose parts these are.
    final Archive defaults = ZipDecoder().decodeBytes(
      File(
        '../../jet_charts_core/test/fixtures/owner/axis_full/'
        'chart_defaults.xlsx',
      ).readAsBytesSync(),
    );
    String owner(String name) => utf8.decode(defaults.findFile(name)!.content);
    expect(excelChartColorsXml, owner('xl/charts/colors1.xml'));
    expect(excelChartStyleXml, owner('xl/charts/style1.xml'));
    expect(excelLineChartStyleXml, owner('xl/charts/style2.xml'));
    const String office = 'http://schemas.microsoft.com/office/2011/';
    final String types = part('[Content_Types].xml');
    for (final int i in charted) {
      expect(part('xl/charts/colors$i.xml'), excelChartColorsXml);
      // A line chart has the style of Excel's default line chart (332);
      // the owner's file has no sample of the other kinds, so they keep 201.
      expect(
        part('xl/charts/style$i.xml'),
        entries[i - 1].chart.kind == ChartKind.line
            ? excelLineChartStyleXml
            : excelChartStyleXml,
        reason: entries[i - 1].name,
      );
      final Map<String, String> targets = <String, String>{
        for (final XmlElement r in all(
          xml('xl/charts/_rels/chart$i.xml.rels'),
          'Relationship',
        ))
          r.getAttribute('Type')!: r.getAttribute('Target')!,
      };
      expect(targets, <String, String>{
        '${office}relationships/chartColorStyle': 'colors$i.xml',
        '${office}relationships/chartStyle': 'style$i.xml',
      });
      expect(
        types,
        contains(
          '<Override PartName="/xl/charts/style$i.xml" '
          'ContentType="application/vnd.ms-office.chartstyle+xml"/>',
        ),
      );
      expect(
        types,
        contains(
          '<Override PartName="/xl/charts/colors$i.xml" '
          'ContentType="application/vnd.ms-office.chartcolorstyle+xml"/>',
        ),
      );
    }
  });

  test('format codes go on the cells and on the value axis', () {
    final int index =
        entries.indexWhere((GalleryEntry e) => e.name == 'turkish_amounts') + 1;
    final XmlDocument styles = xml('xl/styles.xml');
    final XmlElement numFmt = all(styles, 'numFmt').firstWhere(
      (XmlElement e) => e.getAttribute('formatCode') == turkishAmountFormat,
    );
    expect(numFmt.getAttribute('formatCode'), turkishAmountFormat);
    final String id = numFmt.getAttribute('numFmtId')!;
    final List<XmlElement> xfs = all(
      all(styles, 'cellXfs').single,
      'xf',
    ).toList();
    final int xf = xfs.indexWhere(
      (XmlElement e) => e.getAttribute('numFmtId') == id,
    );
    expect(xf, greaterThan(0));
    final XmlDocument sheet = xml('xl/worksheets/sheet$index.xml');
    final XmlElement b2 = all(
      sheet,
      'c',
    ).firstWhere((XmlElement c) => c.getAttribute('r') == 'B2');
    expect(b2.getAttribute('s'), '$xf');
    final XmlDocument chart = xml('xl/charts/chart$index.xml');
    final XmlElement axisFormat = all(
      all(chart, 'c:valAx').single,
      'c:numFmt',
    ).single;
    expect(axisFormat.getAttribute('formatCode'), turkishAmountFormat);
    expect(axisFormat.getAttribute('sourceLinked'), '1');
  });

  test('a pie varies its colours, starts at 0 degrees and names each '
      "slice's accent", () {
    final String text = part('xl/charts/chart${indexOf('pie_basic')}.xml');
    expect(text, contains('<c:pieChart>'));
    expect(text, contains('<c:varyColors val="1"/>'));
    final XmlDocument doc = XmlDocument.parse(text);
    expect(val(doc, 'c:firstSliceAng'), '0');
    expect(all(doc, 'c:catAx'), isEmpty);
    expect(all(doc, 'c:valAx'), isEmpty);
    final List<XmlElement> points = all(doc, 'c:dPt').toList();
    expect(points, hasLength(4));
    for (int p = 0; p < 4; p++) {
      expect(val(points[p], 'c:idx'), '$p');
      expect(
        all(points[p], 'a:schemeClr').first.getAttribute('val'),
        'accent${p + 1}',
      );
    }
    expect(val(doc, 'c:dLblPos'), 'bestFit');
    expect(val(doc, 'c:showLeaderLines'), '1');
  });

  test('a donut has a hole of the chart\'s size and no label position', () {
    expect(val(chartOf('donut_center'), 'c:holeSize'), '55');
    expect(val(chartOf('donut_two_series'), 'c:holeSize'), '75');
    for (final String name in <String>['donut_center', 'donut_two_series']) {
      final XmlDocument doc = chartOf(name);
      expect(val(doc, 'c:varyColors'), '1', reason: name);
      expect(val(doc, 'c:firstSliceAng'), '0', reason: name);
      expect(all(doc, 'c:dLblPos'), isEmpty, reason: name);
    }
    expect(all(chartOf('donut_two_series'), 'c:ser'), hasLength(2));
    // The slice donut_center colours itself.
    final XmlElement third = all(chartOf('donut_center'), 'c:dPt').elementAt(2);
    expect(all(third, 'a:srgbClr').single.getAttribute('val'), 'C0392B');
  });

  test('a scatter chart has markers only and two value axes', () {
    for (final String name in <String>['scatter_basic', 'scatter_dates']) {
      final XmlDocument doc = chartOf(name);
      expect(val(doc, 'c:scatterStyle'), 'lineMarker', reason: name);
      expect(all(doc, 'c:valAx'), hasLength(2), reason: name);
      expect(all(doc, 'c:catAx'), isEmpty, reason: name);
      for (final XmlElement ser in all(doc, 'c:ser')) {
        final XmlElement ln = all(ser.getElement('c:spPr')!, 'a:ln').single;
        expect(ln.getElement('a:noFill'), isNotNull, reason: name);
        expect(all(ser, 'c:xVal'), hasLength(1), reason: name);
        expect(all(ser, 'c:yVal'), hasLength(1), reason: name);
      }
      // Gridlines on the vertical axis only.
      final List<XmlElement> axes = all(doc, 'c:valAx').toList();
      expect(val(axes[0], 'c:axPos'), 'b', reason: name);
      expect(all(axes[0], 'c:majorGridlines'), isEmpty, reason: name);
      expect(all(axes[1], 'c:majorGridlines'), hasLength(1), reason: name);
    }
    final XmlElement xAxis = all(chartOf('scatter_dates'), 'c:valAx').first;
    expect(xAxis.getElement('c:numFmt')!.getAttribute('formatCode'), 'd mmm');
  });

  test('the x values of scatter_dates are date serials in their format', () {
    final int index = indexOf('scatter_dates');
    final XmlDocument sheet = xml('xl/worksheets/sheet$index.xml');
    final XmlElement a2 = all(
      sheet,
      'c',
    ).firstWhere((XmlElement c) => c.getAttribute('r') == 'A2');
    expect(a2.getAttribute('t'), isNull);
    expect(all(a2, 'v').single.innerText, '46023');
    final XmlDocument styles = xml('xl/styles.xml');
    final XmlElement numFmt = all(
      styles,
      'numFmt',
    ).firstWhere((XmlElement e) => e.getAttribute('formatCode') == 'd mmm');
    final List<XmlElement> xfs = all(
      all(styles, 'cellXfs').single,
      'xf',
    ).toList();
    expect(
      xfs[int.parse(a2.getAttribute('s')!)].getAttribute('numFmtId'),
      numFmt.getAttribute('numFmtId'),
    );
  });

  test('each scatter series\' x and y caches equal the cells they name', () {
    for (final String name in <String>['scatter_basic', 'scatter_dates']) {
      final int index = indexOf(name);
      final Map<String, double> cells = <String, double>{
        for (final XmlElement c in all(
          xml('xl/worksheets/sheet$index.xml'),
          'c',
        ))
          if (c.getAttribute('t') == null)
            c.getAttribute('r')!: double.parse(all(c, 'v').single.innerText),
      };
      final List<XmlElement> sers = all(chartOf(name), 'c:ser').toList();
      expect(sers, hasLength(entries[index - 1].chart.series.length));
      for (final XmlElement ser in sers) {
        for (final String tag in <String>['c:xVal', 'c:yVal']) {
          final XmlElement ref = all(ser, tag).single;
          final RegExpMatch m = RegExp(
            r'!\$([A-Z])\$(\d+):\$([A-Z])\$(\d+)$',
          ).firstMatch(all(ref, 'c:f').single.innerText)!;
          expect(m[1], m[3], reason: '$name $tag');
          final int first = int.parse(m[2]!);
          final int last = int.parse(m[4]!);
          final Map<int, double> cached = <int, double>{
            for (final XmlElement pt in all(ref, 'c:pt'))
              int.parse(pt.getAttribute('idx')!): double.parse(
                all(pt, 'c:v').single.innerText,
              ),
          };
          expect(cached, <int, double>{
            for (int r = first; r <= last; r++)
              if (cells['${m[1]}$r'] case final double v) r - first: v,
          }, reason: '$name $tag');
          expect(cached, isNotEmpty, reason: '$name $tag');
        }
      }
      // The x columns of two series differ.
      if (sers.length > 1) {
        expect(
          all(all(sers[0], 'c:xVal').single, 'c:f').single.innerText,
          isNot(all(all(sers[1], 'c:xVal').single, 'c:f').single.innerText),
        );
      }
    }
  });

  test('a series on the secondary axis gets a value axis on the right that '
      'crosses at the maximum, and a deleted category axis', () {
    for (final String name in <String>['combo_column_line', 'line_secondary']) {
      final XmlDocument doc = chartOf(name);
      final List<XmlElement> values = all(doc, 'c:valAx').toList();
      expect(values, hasLength(2), reason: name);
      expect(val(values[1], 'c:axPos'), 'r', reason: name);
      expect(val(values[1], 'c:crosses'), 'max', reason: name);
      expect(all(values[1], 'c:majorGridlines'), isEmpty, reason: name);
      final List<XmlElement> categories = all(doc, 'c:catAx').toList();
      expect(categories, hasLength(2), reason: name);
      expect(val(categories[0], 'c:delete'), '0', reason: name);
      expect(val(categories[1], 'c:delete'), '1', reason: name);
      expect(
        val(categories[1], 'c:crossAx'),
        val(values[1], 'c:axId'),
        reason: name,
      );
    }
    final XmlElement secondary = all(chartOf('line_secondary'), 'c:valAx').last;
    expect(
      all(secondary.getElement('c:title')!, 'a:t').single.innerText,
      'Units',
    );
    expect(all(chartOf('line_secondary'), 'c:lineChart'), hasLength(2));
    // A combination with every series on the primary axis has one.
    final XmlDocument plan = chartOf('combo_area_column_line');
    expect(all(plan, 'c:valAx'), hasLength(1));
    expect(all(plan, 'c:areaChart'), hasLength(1));
  });

  test('the smooth series of line_smooth is smooth, the other is not', () {
    final List<XmlElement> sers = all(chartOf('line_smooth'), 'c:ser').toList();
    expect(
      part('xl/charts/chart${indexOf('line_smooth')}.xml'),
      contains('<c:smooth val="1"/>'),
    );
    expect(val(sers[0], 'c:smooth'), '1');
    expect(val(sers[1], 'c:smooth'), '0');
  });

  test('a sparkline is an Excel sparkline of its values beside them', () {
    for (final String name in <String>['sparkline_line', 'sparkline_area']) {
      final int index = indexOf(name);
      final XmlDocument sheet = xml('xl/worksheets/sheet$index.xml');
      expect(all(sheet, 'drawing'), isEmpty, reason: name);
      final XmlElement group = all(sheet, 'x14:sparklineGroup').single;
      expect(group.getAttribute('type'), isNull, reason: '$name: a line');
      expect(group.getAttribute('minAxisType'), 'custom', reason: name);
      expect(group.getAttribute('manualMin'), '0', reason: name);
      expect(
        all(group, 'xm:f').single.innerText,
        "'$name'!B2:B8",
        reason: name,
      );
      expect(all(group, 'xm:sqref').single.innerText, 'D2', reason: name);
    }
  });

  test('the same entries give the same bytes', () {
    expect(buildExcelGallery(entries), bytes);
  });
}
