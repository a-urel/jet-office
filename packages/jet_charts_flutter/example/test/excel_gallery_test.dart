import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_gallery/gallery.dart';
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

  test('one sheet and one chart part per entry, named by the entry', () {
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
      expect(archive.findFile('xl/charts/chart$i.xml'), isNotNull);
    }
    expect(
      archive.findFile('xl/charts/chart${entries.length + 1}.xml'),
      isNull,
    );
  });

  test('each chart is anchored at 360 by 216 points', () {
    for (int i = 1; i <= entries.length; i++) {
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
    for (int i = 1; i <= entries.length; i++) {
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
          expect(all(doc, 'c:lineChart'), hasLength(1), reason: reason);
          expect(val(doc, 'c:grouping'), switch (chart.grouping) {
            ChartGrouping.clustered => 'standard',
            ChartGrouping.stacked => 'stacked',
            ChartGrouping.percentStacked => 'percentStacked',
          }, reason: reason);
        case ChartKind.area:
          expect(all(doc, 'c:areaChart'), hasLength(1), reason: reason);
          expect(val(doc, 'c:grouping'), chart.grouping.name, reason: reason);
        default:
          fail('$reason: unexpected kind ${chart.kind}');
      }
      final String title = <String>[
        for (final XmlElement t in all(doc, 'c:title'))
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
        chart.dataLabels.visible ? '1' : '0',
        reason: reason,
      );
      expect(all(doc, 'a:srgbClr'), isEmpty, reason: '$reason: own colours');
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
    for (int i = 1; i <= entries.length; i++) {
      final GalleryEntry entry = entries[i - 1];
      final XmlDocument doc = xml('xl/charts/chart$i.xml');
      final List<XmlElement> sers = all(doc, 'c:ser').toList();
      expect(sers, hasLength(entry.chart.series.length), reason: entry.name);
      for (int s = 0; s < sers.length; s++) {
        final ChartSeries series = entry.chart.series[s];
        final String column = String.fromCharCode(66 + s);
        final int last = series.values.values.length + 1;
        final List<String> refs = <String>[
          for (final XmlElement f in all(sers[s], 'c:f')) f.innerText,
        ];
        expect(refs, <String>[
          "'${entry.name}'!\$$column\$1",
          "'${entry.name}'!\$A\$2:\$A\$$last",
          "'${entry.name}'!\$$column\$2:\$$column\$$last",
        ], reason: entry.name);
        final XmlElement cache = all(sers[s], 'c:numCache').single;
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

  test('series 7 and 8 of column_eight_series carry no colour', () {
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
      expect(
        all(sers[s], 'c:spPr'),
        s < 6 ? isNotEmpty : isEmpty,
        reason: '$s',
      );
    }
  });

  test('format codes go on the cells and on the value axis', () {
    final int index =
        entries.indexWhere((GalleryEntry e) => e.name == 'turkish_amounts') + 1;
    final XmlDocument styles = xml('xl/styles.xml');
    final XmlElement numFmt = all(styles, 'numFmt').single;
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

  test('the same entries give the same bytes', () {
    expect(buildExcelGallery(entries), bytes);
  });
}
