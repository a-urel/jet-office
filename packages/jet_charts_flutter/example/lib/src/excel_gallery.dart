/// The workbook of the owner's check: the gallery's charts as Excel's own
/// default charts, to open in Excel for Mac beside the app.
///
/// Adapted from the small chart-workbook writer of
/// `packages/jet_charts_core/tool/src/axis_oracle.dart` and
/// `axis_oracle_full.dart` (nothing is imported across packages). It uses
/// `archive` and knows one chart shape; no `dart:io`, so its tests run
/// anywhere.
///
/// Each chart is written as Excel for Mac writes its default chart in
/// `packages/jet_charts_core/test/fixtures/owner/axis_full/chart_defaults.xlsx`:
/// scheme colours (`accent1` and on, `tx1` with `lumMod` and `lumOff`), the
/// theme's minor font (`+mn-lt`), Excel's text sizes and an empty
/// `c:layout`, with that file's theme part. Nothing names a colour, a font or
/// a position of its own. What a chart of the gallery sets (kind, grouping,
/// title, legend position, data labels, the data and its format codes) is
/// written as such. Beside each chart go Excel's colour-style and style parts
/// of that file (`colorsN.xml`, `styleN.xml`, `excel_chart_style.dart`), as
/// Excel writes them beside every chart it makes: the style part of its
/// clustered column chart (201) for column charts and that of its line chart
/// (332) for line charts, smoothed or not; the owner's E1 file
/// (`chart_reference_j4.xlsx`) gives a pie or doughnut 251, a scatter chart
/// 240 and the combination 322. The owner's files have no Excel-saved bar or
/// area chart, so those two kinds keep the column style. Every series names its
/// colour of Excel's colour cycle (`colorsN.xml`), as Excel writes it in a new
/// chart: series 7 is `accent1` with `lumMod` 60000. A series without
/// `c:spPr` would not do: Excel drew series 7 and 8 of such a chart light
/// even with the colour-style part beside it, while a chart the owner made
/// new in Excel from the same cells drew them `0D3A4E` and `994010` (the
/// owner's check, 2026-11-09, `docs/excel-checks.md` of `jet_charts_core`).
///
/// The J4 kinds (pie, doughnut, scatter, a combination of column, line and
/// area groups, a secondary value axis, a smooth line and the sparkline) are
/// written as the owner's E1 file (`chart_reference_j4.xlsx`,
/// `test/fixtures/owner/charts/TALIMATLAR_J4.md` of the repository, read
/// 2026-11-10) shows Excel's Insert menu writes them. What that file does not
/// hold (a secondary axis, an area group in a combination, a numeric scatter)
/// stays an estimate, marked so in a comment.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_charts_core/jet_charts_core.dart';

import '../gallery.dart';
import 'excel_chart_style.dart';
import 'office_theme.dart';

/// EMU per point.
const int _emu = 12700;

/// The left edge of every chart, in points.
const int _chartLeft = 20;

/// The height of a row the chart is placed below, in points: more than a
/// default row, so the chart never covers the data.
const int _rowPoints = 20;

/// The first number format id a workbook may define.
const int _firstCustomFormat = 164;

/// Writes `gallery.xlsx` for [entries]: a sheet per entry, named by its name
/// cut to 31 characters, with the categories in column A from row 2 (a
/// scatter series' x values in a column of its own, left of its values), a column
/// per series from column B with the series' name in row 1, and below them one
/// chart of [gallerySize] (Excel's default 360 by 216 points). The same
/// [entries] give the same bytes.
///
/// A sparkline gets no chart: its sheet holds Excel's own sparkline of the
/// values in cell D2, about [sparklineSize] (`_sparklineSheetXml`).
///
/// Throws an [ArgumentError] for an entry whose kind is not column, bar,
/// line, area, pie, donut, scatter, combination or sparkline, or with more
/// than 25 series.
Uint8List buildExcelGallery(List<GalleryEntry> entries) {
  for (final GalleryEntry entry in entries) {
    if (!const <ChartKind>[
      ChartKind.column,
      ChartKind.bar,
      ChartKind.line,
      ChartKind.area,
      ChartKind.pie,
      ChartKind.donut,
      ChartKind.scatter,
      ChartKind.combination,
      ChartKind.sparkline,
    ].contains(entry.chart.kind)) {
      throw ArgumentError.value(entry.name, 'entries', 'unsupported kind');
    }
    if (entry.chart.series.length > 25) {
      throw ArgumentError.value(entry.name, 'entries', 'too many series');
    }
  }
  final List<String> codes = <String>{
    for (final GalleryEntry entry in entries)
      for (final ChartSeries series in entry.chart.series)
        if (series.formatCode case final String code) code,
    for (final GalleryEntry entry in entries)
      if (entry.chart.kind == ChartKind.scatter)
        if (entry.chart.categoryAxis.formatCode case final String code) code,
  }.toList();
  final Archive archive = Archive();
  void add(String name, String text) =>
      archive.add(ArchiveFile.bytes(name, utf8.encode(text)));

  final int n = entries.length;
  add('[Content_Types].xml', _contentTypes(entries));
  add(
    '_rels/.rels',
    _rels(<String>[_rel(1, 'officeDocument', 'xl/workbook.xml')]),
  );
  add('xl/workbook.xml', _workbookXml(entries));
  add(
    'xl/_rels/workbook.xml.rels',
    _rels(<String>[
      for (int i = 1; i <= n; i++)
        _rel(i, 'worksheet', 'worksheets/sheet$i.xml'),
      _rel(n + 1, 'styles', 'styles.xml'),
      _rel(n + 2, 'theme', 'theme/theme1.xml'),
    ]),
  );
  add('xl/styles.xml', _stylesXml(codes));
  add('xl/theme/theme1.xml', '$_xmlDecl$officeThemeXml');
  for (int i = 1; i <= n; i++) {
    final GalleryEntry entry = entries[i - 1];
    if (entry.chart.kind == ChartKind.sparkline) {
      add('xl/worksheets/sheet$i.xml', _sparklineSheetXml(entry));
      continue;
    }
    add('xl/worksheets/sheet$i.xml', _sheetXml(entry.chart, codes));
    add(
      'xl/worksheets/_rels/sheet$i.xml.rels',
      _rels(<String>[_rel(1, 'drawing', '../drawings/drawing$i.xml')]),
    );
    add('xl/drawings/drawing$i.xml', _drawingXml(entry));
    add(
      'xl/drawings/_rels/drawing$i.xml.rels',
      _rels(<String>[_rel(1, 'chart', '../charts/chart$i.xml')]),
    );
    add('xl/charts/chart$i.xml', _chartXml(entry));
    add(
      'xl/charts/_rels/chart$i.xml.rels',
      _rels(<String>[
        _officeRel(2, 'chartColorStyle', 'colors$i.xml'),
        _officeRel(1, 'chartStyle', 'style$i.xml'),
      ]),
    );
    add('xl/charts/style$i.xml', switch (entry.chart.kind) {
      ChartKind.line => excelLineChartStyleXml,
      ChartKind.pie || ChartKind.donut => excelPieChartStyleXml,
      ChartKind.scatter => excelScatterChartStyleXml,
      ChartKind.combination => excelComboChartStyleXml,
      _ => excelChartStyleXml,
    });
    add('xl/charts/colors$i.xml', excelChartColorsXml);
  }
  return Uint8List.fromList(
    ZipEncoder().encodeBytes(archive, modified: DateTime.utc(2020)),
  );
}

const String _xmlDecl =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const String _relNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _mainNs =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const String _chartNs =
    'http://schemas.openxmlformats.org/drawingml/2006/chart';
const String _drawingNs =
    'http://schemas.openxmlformats.org/drawingml/2006/main';

String _sheetName(GalleryEntry entry) =>
    entry.name.length > 31 ? entry.name.substring(0, 31) : entry.name;

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// [value] as the shortest text: whole numbers without a decimal point.
String _numText(double value) =>
    value == value.roundToDouble() && value.abs() < 1e15
    ? '${value.toInt()}'
    : '$value';

String _column(int index) => String.fromCharCode('A'.codeUnitAt(0) + index);

/// The column index of series [s]'s values: B on for most charts; a
/// scatter series has its own x column, so its values are in B, D, F and on.
int _valueColumn(Chart chart, int s) =>
    chart.kind == ChartKind.scatter ? 2 * s + 1 : s + 1;

/// The column index of series [s]'s categories or x values: A, or a
/// scatter series' own column left of its values (A, C, E and on).
int _xColumn(Chart chart, int s) => chart.kind == ChartKind.scatter ? 2 * s : 0;

int _rowCount(Chart chart) => <int>[
  for (final ChartSeries s in chart.series) s.values.values.length,
  if (chart.kind == ChartKind.scatter)
    for (final ChartSeries s in chart.series) s.categories.values.length
  else if (chart.series.isNotEmpty)
    chart.series.first.categories.values.length,
].fold(0, (int a, int b) => a > b ? a : b);

String _contentTypes(List<GalleryEntry> entries) {
  const String office = 'application/vnd.openxmlformats-officedocument';
  return '$_xmlDecl<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="$office.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="$office.spreadsheetml.styles+xml"/>'
      '<Override PartName="/xl/theme/theme1.xml" ContentType="$office.theme+xml"/>'
      '${<String>[
        for (int i = 1; i <= entries.length; i++) ...<String>[
          '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="$office.spreadsheetml.worksheet+xml"/>',
          if (entries[i - 1].chart.kind != ChartKind.sparkline) ...<String>['<Override PartName="/xl/drawings/drawing$i.xml" ContentType="$office.drawing+xml"/>', '<Override PartName="/xl/charts/chart$i.xml" ContentType="$office.drawingml.chart+xml"/>', '<Override PartName="/xl/charts/style$i.xml" ContentType="application/vnd.ms-office.chartstyle+xml"/>', '<Override PartName="/xl/charts/colors$i.xml" ContentType="application/vnd.ms-office.chartcolorstyle+xml"/>'],
        ],
      ].join()}'
      '</Types>';
}

String _rels(List<String> relationships) =>
    '$_xmlDecl<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '${relationships.join()}</Relationships>';

String _rel(int id, String type, String target) =>
    '<Relationship Id="rId$id" Type="$_relNs/$type" Target="$target"/>';

/// A relationship of Office 2011's types, as a chart's to its style parts.
String _officeRel(int id, String type, String target) =>
    '<Relationship Id="rId$id" '
    'Type="http://schemas.microsoft.com/office/2011/relationships/$type" '
    'Target="$target"/>';

String _workbookXml(List<GalleryEntry> entries) =>
    '$_xmlDecl<workbook xmlns="$_mainNs" xmlns:r="$_relNs"><sheets>'
    '${<String>[for (int i = 1; i <= entries.length; i++) '<sheet name="${_escape(_sheetName(entries[i - 1]))}" sheetId="$i" r:id="rId$i"/>'].join()}'
    '</sheets></workbook>';

/// Excel for Mac's own cell style: Aptos Narrow 12 of the theme, and one cell
/// format per code of [codes] after the default one.
String _stylesXml(List<String> codes) {
  final StringBuffer out = StringBuffer(
    '$_xmlDecl<styleSheet xmlns="$_mainNs">',
  );
  if (codes.isNotEmpty) {
    out.write('<numFmts count="${codes.length}">');
    for (int i = 0; i < codes.length; i++) {
      out.write(
        '<numFmt numFmtId="${_firstCustomFormat + i}" '
        'formatCode="${_escape(codes[i])}"/>',
      );
    }
    out.write('</numFmts>');
  }
  out.write(
    '<fonts count="1"><font><sz val="12"/><color theme="1"/>'
    '<name val="Aptos Narrow"/><family val="2"/><scheme val="minor"/></font>'
    '</fonts><fills count="2"><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/>'
    '</border></borders><cellStyleXfs count="1">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="${codes.length + 1}">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>',
  );
  for (int i = 0; i < codes.length; i++) {
    out.write(
      '<xf numFmtId="${_firstCustomFormat + i}" fontId="0" fillId="0" '
      'borderId="0" xfId="0" applyNumberFormat="1"/>',
    );
  }
  out.write(
    '</cellXfs><cellStyles count="1">'
    '<cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>',
  );
  return out.toString();
}

String _sheetXml(Chart chart, List<String> codes) {
  final StringBuffer out = StringBuffer(
    '$_xmlDecl<worksheet xmlns="$_mainNs" xmlns:r="$_relNs"><sheetData>',
  );
  out.write('<row r="1">');
  for (int s = 0; s < chart.series.length; s++) {
    out.write(
      '<c r="${_column(_valueColumn(chart, s))}1" t="inlineStr"><is><t>'
      '${_escape(_seriesName(chart.series[s], s))}</t></is></c>',
    );
  }
  out.write('</row>');
  final List<Object?> categories = chart.series.isEmpty
      ? const <Object?>[]
      : chart.series.first.categories.values;
  for (int i = 0; i < _rowCount(chart); i++) {
    final int r = i + 2;
    out.write('<row r="$r">');
    final Object? category = i < categories.length ? categories[i] : null;
    if (chart.kind != ChartKind.scatter && category != null) {
      out.write(
        '<c r="A$r" t="inlineStr"><is><t>${_escape('$category')}</t></is></c>',
      );
    }
    for (int s = 0; s < chart.series.length; s++) {
      final ChartSeries series = chart.series[s];
      if (chart.kind == ChartKind.scatter) {
        // A scatter series' x values are numbers in its own column, a date
        // as its serial in the category axis' format.
        final List<Object?> xs = series.categories.values;
        if (_xNumber(i < xs.length ? xs[i] : null) case final double x) {
          final String? code = chart.categoryAxis.formatCode;
          final String style = code == null
              ? ''
              : ' s="${codes.indexOf(code) + 1}"';
          out.write(
            '<c r="${_column(_xColumn(chart, s))}$r"$style>'
            '<v>${_numText(x)}</v></c>',
          );
        }
      }
      final List<double?> values = series.values.values;
      final double? value = i < values.length ? values[i] : null;
      if (value == null || !value.isFinite) continue;
      final String style = series.formatCode == null
          ? ''
          : ' s="${codes.indexOf(series.formatCode!) + 1}"';
      out.write(
        '<c r="${_column(_valueColumn(chart, s))}$r"$style>'
        '<v>${_numText(value)}</v></c>',
      );
    }
    out.write('</row>');
  }
  out.write('</sheetData><drawing r:id="rId1"/></worksheet>');
  return out.toString();
}

/// The cell of a sparkline's Excel sparkline.
const String _sparklineCell = 'D2';

/// The sheet of a sparkline [entry]: the values in column B from row 2 under
/// the series' name, and Excel's own sparkline of them in [_sparklineCell],
/// whose column and row are about [sparklineSize] (the column width in
/// characters is approximate: Excel measures it in the default font's digit
/// width).
///
/// The sparkline group is Excel's default one (Insert > Sparklines > Line):
/// its colours are those Excel writes for a new sparkline group, `accent1`
/// darker 50 % for the line and markers (an estimate, not checked in Excel,
/// pending E1). Excel has no area sparkline, so `sparkline_area` is a line
/// there. A minimum the chart sets is written as Excel's custom minimum.
String _sparklineSheetXml(GalleryEntry entry) {
  final Chart chart = entry.chart;
  final ChartSeries? series = chart.series.firstOrNull;
  final List<double?> values = series?.values.values ?? const <double?>[];
  final StringBuffer out = StringBuffer(
    '$_xmlDecl<worksheet xmlns="$_mainNs" xmlns:r="$_relNs">'
    '<cols><col min="4" max="4" width="22.83" customWidth="1"/></cols>'
    '<sheetData>',
  );
  if (series != null) {
    out.write(
      '<row r="1"><c r="B1" t="inlineStr"><is><t>'
      '${_escape(_seriesName(series, 0))}</t></is></c></row>',
    );
  }
  final int rows = values.isEmpty ? 1 : values.length;
  for (int i = 0; i < rows; i++) {
    final int r = i + 2;
    final double? value = i < values.length ? values[i] : null;
    out
      ..write(
        '<row r="$r"${r == 2 ? ' ht="${sparklineSize.height.round()}" customHeight="1"' : ''}>',
      )
      ..write(
        value == null || !value.isFinite
            ? ''
            : '<c r="B$r"><v>${_numText(value)}</v></c>',
      )
      ..write('</row>');
  }
  final double? min = chart.valueAxis.min;
  final double? max = chart.valueAxis.max;
  final String sheet = "'${_sheetName(entry).replaceAll("'", "''")}'";
  out
    ..write('</sheetData><extLst>')
    ..write(
      '<ext uri="{05C60535-1F16-4fd2-B633-F4F36F0B64E0}" '
      'xmlns:x14="http://schemas.microsoft.com/office/spreadsheetml/2009/9/main">'
      '<x14:sparklineGroups '
      'xmlns:xm="http://schemas.microsoft.com/office/excel/2006/main">'
      '<x14:sparklineGroup'
      '${max == null ? '' : ' manualMax="${_numText(max)}"'}'
      '${min == null ? '' : ' manualMin="${_numText(min)}"'}'
      ' displayEmptyCellsAs="gap"'
      '${min == null ? '' : ' minAxisType="custom"'}'
      '${max == null ? '' : ' maxAxisType="custom"'}>'
      '<x14:colorSeries theme="4" tint="-0.499984740745262"/>'
      '<x14:colorNegative theme="5"/><x14:colorAxis rgb="FF000000"/>'
      '<x14:colorMarkers theme="4" tint="-0.499984740745262"/>'
      '<x14:colorFirst theme="4" tint="0.39997558519241921"/>'
      '<x14:colorLast theme="4" tint="0.39997558519241921"/>'
      '<x14:colorHigh theme="4"/><x14:colorLow theme="4"/>'
      '<x14:sparklines><x14:sparkline>'
      '<xm:f>$sheet!B2:B${rows + 1}</xm:f><xm:sqref>$_sparklineCell</xm:sqref>'
      '</x14:sparkline></x14:sparklines></x14:sparklineGroup>'
      '</x14:sparklineGroups></ext></extLst></worksheet>',
    );
  return out.toString();
}

String _seriesName(ChartSeries series, int index) =>
    series.name.values.firstOrNull ?? 'Series ${index + 1}';

String _drawingXml(GalleryEntry entry) {
  final int top = (_rowCount(entry.chart) + 2) * _rowPoints;
  final int width = gallerySize.width.round();
  final int height = gallerySize.height.round();
  return '$_xmlDecl<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
      'xmlns:a="$_drawingNs">'
      '<xdr:absoluteAnchor>'
      '<xdr:pos x="${_chartLeft * _emu}" y="${top * _emu}"/>'
      '<xdr:ext cx="${width * _emu}" cy="${height * _emu}"/>'
      '<xdr:graphicFrame macro=""><xdr:nvGraphicFramePr>'
      '<xdr:cNvPr id="2" name="${_escape(entry.name)}"/><xdr:cNvGraphicFramePr/>'
      '</xdr:nvGraphicFramePr>'
      '<xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm>'
      '<a:graphic><a:graphicData uri="$_chartNs">'
      '<c:chart xmlns:c="$_chartNs" xmlns:r="$_relNs" r:id="rId1"/>'
      '</a:graphicData></a:graphic></xdr:graphicFrame><xdr:clientData/>'
      '</xdr:absoluteAnchor></xdr:wsDr>';
}

// What follows is Excel's default chart as chart_defaults.xlsx holds it.

const String _fonts =
    '<a:latin typeface="+mn-lt"/><a:ea typeface="+mn-ea"/>'
    '<a:cs typeface="+mn-cs"/>';

/// Text in `tx1` at [mod] and [off] (`lumMod`, `lumOff`, in thousandths).
String _textFill(int mod, int off) =>
    '<a:solidFill><a:schemeClr val="tx1"><a:lumMod val="$mod"/>'
    '<a:lumOff val="$off"/></a:schemeClr></a:solidFill>';

/// The light grey line of gridlines, the category axis and the border.
const String _greyLine =
    '<a:ln w="9525" cap="flat" cmpd="sng" algn="ctr"><a:solidFill>'
    '<a:schemeClr val="tx1"><a:lumMod val="15000"/><a:lumOff val="85000"/>'
    '</a:schemeClr></a:solidFill><a:round/></a:ln>';

/// The darker grey line of a scatter chart's two axes, `tx1` at 25 and 75
/// (`BFBFBF`), as Excel writes them (E1, chart 4).
const String _scatterAxisLine =
    '<c:spPr><a:noFill/><a:ln w="9525" cap="flat" cmpd="sng" algn="ctr">'
    '<a:solidFill><a:schemeClr val="tx1"><a:lumMod val="25000"/>'
    '<a:lumOff val="75000"/></a:schemeClr></a:solidFill><a:round/></a:ln>'
    '<a:effectLst/></c:spPr>';

/// A pie's leader lines, `tx1` at 35 and 65 (`A6A6A6`), 0.75 pt, as Excel
/// writes them in a series' data labels (E1, chart 7).
const String _leaderLines =
    '<c:leaderLines><c:spPr><a:ln w="9525" cap="flat" cmpd="sng" algn="ctr">'
    '<a:solidFill><a:schemeClr val="tx1"><a:lumMod val="35000"/>'
    '<a:lumOff val="65000"/></a:schemeClr></a:solidFill><a:round/></a:ln>'
    '<a:effectLst/></c:spPr></c:leaderLines>';

const String _noShape =
    '<c:spPr><a:noFill/><a:ln><a:noFill/></a:ln><a:effectLst/></c:spPr>';

/// The text body of axis labels: `rot="-60000000"` is Excel's automatic
/// angle, which it honours on an axis only.
const String _axisBodyPr =
    '<a:bodyPr rot="-60000000" spcFirstLastPara="1" vertOverflow="ellipsis" '
    'vert="horz" wrap="square" anchor="ctr" anchorCtr="1"/>';

/// The text body of the legend, level as Excel writes it; Excel turns
/// legend text written with the automatic angle on its side.
const String _legendBodyPr =
    '<a:bodyPr rot="0" spcFirstLastPara="1" vertOverflow="ellipsis" '
    'vert="horz" wrap="square" anchor="ctr" anchorCtr="1"/>';

/// The text body of data labels, as Excel writes it.
const String _labelBodyPr =
    '<a:bodyPr rot="0" spcFirstLastPara="1" vertOverflow="ellipsis" '
    'vert="horz" wrap="square" lIns="38100" tIns="19050" rIns="38100" '
    'bIns="19050" anchor="ctr" anchorCtr="1"><a:spAutoFit/></a:bodyPr>';

/// The text properties of axis labels and the legend (9 pt, 65 and 35) and of
/// data labels (9 pt, 75 and 25), with the text body [bodyPr].
String _txPr(int mod, int off, String bodyPr) =>
    '<c:txPr>$bodyPr<a:lstStyle/><a:p><a:pPr><a:defRPr sz="900" b="0" i="0" '
    'u="none" strike="noStrike" kern="1200" baseline="0">'
    '${_textFill(mod, off)}$_fonts</a:defRPr></a:pPr>'
    '<a:endParaRPr lang="en-US"/></a:p></c:txPr>';

String _title(String text) =>
    '<c:title><c:tx><c:rich><a:bodyPr rot="0" spcFirstLastPara="1" '
    'vertOverflow="ellipsis" vert="horz" wrap="square" anchor="ctr" '
    'anchorCtr="1"/><a:lstStyle/><a:p><a:pPr><a:defRPr sz="1400" b="0" i="0" '
    'u="none" strike="noStrike" kern="1200" spc="0" baseline="0">'
    '${_textFill(65000, 35000)}$_fonts</a:defRPr></a:pPr>'
    '<a:r><a:rPr lang="en-US"/><a:t>${_escape(text)}</a:t></a:r></a:p>'
    '</c:rich></c:tx><c:overlay val="0"/>$_noShape</c:title>';

/// [color] as DrawingML: a scheme colour with its `lumMod` and `lumOff`, or
/// an RGB colour the chart itself names.
String _colorXml(ChartColor color) {
  String percent(double value) => '${(value * 100000).round()}';
  if (color.slot case final ChartSchemeColor slot) {
    return '<a:schemeClr val="${slot.name}">'
        '${color.lumMod == 1 ? '' : '<a:lumMod val="${percent(color.lumMod)}"/>'}'
        '${color.lumOff == 0 ? '' : '<a:lumOff val="${percent(color.lumOff)}"/>'}'
        '</a:schemeClr>';
  }
  return '<a:srgbClr val="${color.rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}"/>';
}

/// The colour of Excel's cycle at [index] (see the library comment).
String _accent(int index) => _colorXml(ChartTheme.office.seriesColor(index));

/// A marker as Excel's line chart with markers writes it: a 5 pt circle
/// filled and outlined in [accent].
String _circleMarker(String accent) =>
    '<c:marker><c:symbol val="circle"/><c:size val="5"/><c:spPr>'
    '<a:solidFill>$accent</a:solidFill><a:ln w="9525"><a:solidFill>'
    '$accent</a:solidFill></a:ln><a:effectLst/></c:spPr></c:marker>';

/// The shape of a series drawn as [kind] (column, line or area) at [index].
/// A line of a combination chart has no marker, as Excel's combination
/// "Clustered Column - Line" draws it ([combination]; `c:symbol none`, E1
/// chart 5).
String _seriesShape(ChartKind kind, int index, {bool combination = false}) {
  final String accent = _accent(index);
  if (kind == ChartKind.line) {
    return '<c:spPr><a:ln w="28575" cap="rnd"><a:solidFill>$accent'
        '</a:solidFill><a:round/></a:ln><a:effectLst/></c:spPr>'
        '${combination ? '<c:marker><c:symbol val="none"/></c:marker>' : _circleMarker(accent)}';
  }
  return '<c:spPr><a:solidFill>$accent</a:solidFill><a:ln><a:noFill/></a:ln>'
      '<a:effectLst/></c:spPr>';
}

/// A slice of a pie or donut at [index]: its colour of the cycle, or the one
/// the series names in its `pointColors`, outlined in `lt1` at 1.5 pt.
///
/// Excel's pie and doughnut style (251) outlines a slice in `lt1` at 19050
/// EMU, as the owner's E1 file shows on every `c:dPt`; the Office theme's
/// `sliceBorderWidth` is the same 1.5 pt in its background, white.
String _slicePoint(ChartSeries series, int index) {
  final ChartColor? own = index < series.pointColors.length
      ? series.pointColors[index]
      : null;
  final String fill = own == null ? _accent(index) : _colorXml(own);
  return '<c:dPt><c:idx val="$index"/><c:bubble3D val="0"/><c:spPr>'
      '<a:solidFill>$fill</a:solidFill><a:ln w="19050"><a:solidFill>'
      '<a:schemeClr val="lt1"/></a:solidFill></a:ln><a:effectLst/></c:spPr>'
      '</c:dPt>';
}

/// The kind a series of [chart] is drawn as: its own in a combination chart
/// (column, line or area; any other is a column), else the chart's.
ChartKind _drawnKind(Chart chart, ChartSeries series) {
  if (chart.kind != ChartKind.combination) return chart.kind;
  return switch (series.kind) {
    ChartKind.line => ChartKind.line,
    ChartKind.area => ChartKind.area,
    _ => ChartKind.column,
  };
}

/// Whether [series] goes on the secondary value axis: when it is bound to it
/// and some series of [chart] is not, and the chart is not a bar chart (the
/// rule `ChartSeries.axis` states).
bool _onSecondary(Chart chart, ChartSeries series) =>
    chart.kind != ChartKind.bar &&
    series.axis == ChartAxisBinding.secondary &&
    chart.series.any((ChartSeries s) => s.axis != ChartAxisBinding.secondary);

/// [value] (a number or a `DateTime`) as the number a cell holds: a date as
/// Excel's serial of the 1900 system, the days since 1899-12-30.
double? _xNumber(Object? value) => switch (value) {
  final num n => n.toDouble(),
  final DateTime d =>
    DateTime.utc(
          d.year,
          d.month,
          d.day,
        ).difference(DateTime.utc(1899, 12, 30)).inDays +
        (d.hour * 3600 + d.minute * 60 + d.second) / 86400,
  _ => null,
};

/// The title of an axis, as Excel writes a new axis title: 10 pt in `tx1` at
/// 65 and 35, turned up on a vertical axis ([vertical]).
String _axisTitle(String text, {required bool vertical}) =>
    '<c:title><c:tx><c:rich><a:bodyPr rot="${vertical ? -5400000 : 0}" '
    'spcFirstLastPara="1" vertOverflow="ellipsis" vert="horz" wrap="square" '
    'anchor="ctr" anchorCtr="1"/><a:lstStyle/><a:p><a:pPr><a:defRPr sz="1000" '
    'b="0" i="0" u="none" strike="noStrike" kern="1200" baseline="0">'
    '${_textFill(65000, 35000)}$_fonts</a:defRPr></a:pPr>'
    '<a:r><a:rPr lang="en-US"/><a:t>${_escape(text)}</a:t></a:r></a:p>'
    '</c:rich></c:tx><c:overlay val="0"/>$_noShape</c:title>';

/// The ids of the primary category and value axes, and of the secondary
/// ones (Excel writes random ids; any distinct numbers do).
const int _catId = 111111111;
const int _valId = 222222222;
const int _secondaryCatId = 333333333;
const int _secondaryValId = 444444444;

/// A category axis as Excel writes it; a secondary one is deleted (an
/// estimate, not checked in Excel: the E1 file has no secondary axis). Its labels are [low], under
/// the plot, when a value is negative, as the app draws them, not at the zero
/// line under the negative bars (the owner's choice, J3 and J4 checks; the
/// library's writer does the same).
String _catAx(
  int id,
  int cross, {
  required String pos,
  bool deleted = false,
  bool low = false,
}) =>
    '<c:catAx><c:axId val="$id"/>'
    '<c:scaling><c:orientation val="minMax"/></c:scaling>'
    '<c:delete val="${deleted ? 1 : 0}"/><c:axPos val="$pos"/>'
    '<c:numFmt formatCode="General" sourceLinked="1"/>'
    '<c:majorTickMark val="${deleted ? 'out' : 'none'}"/>'
    '<c:minorTickMark val="none"/>'
    '<c:tickLblPos val="${low ? 'low' : 'nextTo'}"/>'
    '${deleted ? '' : '<c:spPr><a:noFill/>$_greyLine<a:effectLst/></c:spPr>'}'
    '${_txPr(65000, 35000, _axisBodyPr)}'
    '<c:crossAx val="$cross"/><c:crosses val="autoZero"/><c:auto val="1"/>'
    '<c:lblAlgn val="ctr"/><c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/>'
    '</c:catAx>';

/// A value axis as Excel writes it: at [pos], with gridlines when
/// [gridlines], the number format [format], the title [title] (none when
/// null), crossing its [cross] axis at [crosses] and with the shape
/// [shape] (none by default; a scatter chart's axes have Excel's line). A
/// secondary axis is an estimate, not checked in Excel (the E1 file has
/// none); a scatter chart's axes are Excel's (E1, chart 4).
String _valAx(
  int id,
  int cross, {
  required String pos,
  required bool gridlines,
  required String format,
  required String crosses,
  required String crossBetween,
  String? title,
  String shape = _noShape,
}) =>
    '<c:valAx><c:axId val="$id"/>'
    '<c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/>'
    '<c:axPos val="$pos"/>'
    '${gridlines ? '<c:majorGridlines><c:spPr>$_greyLine<a:effectLst/></c:spPr></c:majorGridlines>' : ''}'
    '${title == null ? '' : _axisTitle(title, vertical: pos == 'l' || pos == 'r')}'
    '$format<c:majorTickMark val="none"/><c:minorTickMark val="none"/>'
    '<c:tickLblPos val="nextTo"/>'
    '$shape'
    '${_txPr(65000, 35000, _axisBodyPr)}'
    '<c:crossAx val="$cross"/><c:crosses val="$crosses"/>'
    '<c:crossBetween val="$crossBetween"/></c:valAx>';

String _numFmt(String? code) =>
    '<c:numFmt formatCode="${_escape(code ?? 'General')}" sourceLinked="1"/>';

String _chartXml(GalleryEntry entry) {
  final Chart chart = entry.chart;
  final String sheet = "'${_sheetName(entry).replaceAll("'", "''")}'";
  final int count = _rowCount(chart);
  final int last = count + 1;
  final ChartDataLabels dataLabels = chart.dataLabels;
  final bool labels = dataLabels.visible;
  final bool pie = chart.kind == ChartKind.pie;
  final bool round = pie || chart.kind == ChartKind.donut;
  final bool scatter = chart.kind == ChartKind.scatter;
  final List<Object?> categories = chart.series.isEmpty
      ? const <Object?>[]
      : chart.series.first.categories.values;
  String flags({required bool shown}) =>
      '<c:showLegendKey val="0"/>'
      '<c:showVal val="${shown && dataLabels.showValue ? 1 : 0}"/>'
      '<c:showCatName val="0"/><c:showSerName val="0"/>'
      '<c:showPercent val="${shown && dataLabels.showPercent ? 1 : 0}"/>'
      '<c:showBubbleSize val="0"/>'
      // A pie's and a donut's labels have leader lines, as Excel writes
      // them, and the series' shown labels Excel's line (E1, chart 7).
      '${round ? '<c:showLeaderLines val="1"/>' : ''}'
      '${round && shown ? _leaderLines : ''}';
  // A pie's labels go where Excel finds best ("Best Fit", E1 chart 7); a
  // doughnut takes no label position.
  final String seriesLabels = !labels
      ? ''
      : '<c:dLbls>$_noShape${_txPr(75000, 25000, _labelBodyPr)}'
            '${pie ? '<c:dLblPos val="bestFit"/>' : ''}'
            '${flags(shown: true)}</c:dLbls>';
  final String groupLabels = '<c:dLbls>${flags(shown: false)}</c:dLbls>';

  final List<String> sers = <String>[];
  for (int s = 0; s < chart.series.length; s++) {
    final ChartSeries series = chart.series[s];
    final ChartKind kind = _drawnKind(chart, series);
    final String column = _column(_valueColumn(chart, s));
    final String xColumn = _column(_xColumn(chart, s));
    final List<double?> values = series.values.values;
    final String name = _escape(_seriesName(series, s));
    final String tx =
        '<c:tx><c:strRef><c:f>$sheet!\$$column\$1</c:f><c:strCache>'
        '<c:ptCount val="1"/><c:pt idx="0"><c:v>$name</c:v></c:pt>'
        '</c:strCache></c:strRef></c:tx>';
    final String range = '$sheet!\$$xColumn\$2:\$$xColumn\$$last';
    final String cat = scatter
        ? '<c:xVal><c:numRef><c:f>$range</c:f><c:numCache><c:formatCode>'
              '${_escape(chart.categoryAxis.formatCode ?? 'General')}'
              '</c:formatCode><c:ptCount val="$count"/>${<String>[for (int i = 0; i < series.categories.values.length; i++)
                if (_xNumber(series.categories.values[i]) case final double x) '<c:pt idx="$i"><c:v>${_numText(x)}</c:v></c:pt>'].join()}</c:numCache></c:numRef></c:xVal>'
        : '<c:cat><c:strRef><c:f>$range</c:f><c:strCache>'
              '<c:ptCount val="$count"/>${<String>[for (int i = 0; i < categories.length; i++)
                if (categories[i] != null) '<c:pt idx="$i"><c:v>${_escape('${categories[i]}')}</c:v></c:pt>'].join()}</c:strCache></c:strRef></c:cat>';
    final String valTag = scatter ? 'c:yVal' : 'c:val';
    final String val =
        '<$valTag><c:numRef><c:f>$sheet!\$$column\$2:\$$column\$$last</c:f>'
        '<c:numCache><c:formatCode>${_escape(series.formatCode ?? 'General')}'
        '</c:formatCode><c:ptCount val="$count"/>${<String>[for (int i = 0; i < values.length; i++)
          if (values[i] case final double v when v.isFinite) '<c:pt idx="$i"><c:v>${_numText(v)}</c:v></c:pt>'].join()}</c:numCache></c:numRef></$valTag>';
    final String smooth = '<c:smooth val="${series.smooth ? 1 : 0}"/>';
    final String body = switch (chart.kind) {
      ChartKind.pie || ChartKind.donut =>
        '${<String>[for (int i = 0; i < count; i++) _slicePoint(series, i)].join()}'
            '$seriesLabels$cat$val',
      // Excel's scatter chart with markers only: the series line has no
      // fill (E1, chart 4).
      ChartKind.scatter =>
        '<c:spPr><a:ln w="25400" cap="rnd"><a:noFill/><a:round/></a:ln>'
            '<a:effectLst/></c:spPr>${_circleMarker(_accent(s))}'
            '$seriesLabels$cat$val$smooth',
      _ => switch (kind) {
        ChartKind.line =>
          '${_seriesShape(kind, s, combination: chart.kind == ChartKind.combination)}'
              '$seriesLabels$cat$val$smooth',
        ChartKind.area => '${_seriesShape(kind, s)}$seriesLabels$cat$val',
        _ =>
          '${_seriesShape(kind, s)}<c:invertIfNegative val="0"/>'
              '$seriesLabels$cat$val',
      },
    };
    sers.add('<c:ser><c:idx val="$s"/><c:order val="$s"/>$tx$body</c:ser>');
  }

  final String plot;
  final String axes;
  if (round) {
    // Excel's pie and doughnut: colours vary by slice, the first slice
    // starts at 12 o'clock (E1, charts 1, 2, 3 and 7).
    plot = pie
        ? '<c:pieChart><c:varyColors val="1"/>${sers.join()}$groupLabels'
              '<c:firstSliceAng val="0"/></c:pieChart>'
        : '<c:doughnutChart><c:varyColors val="1"/>${sers.join()}'
              '$groupLabels<c:firstSliceAng val="0"/>'
              '<c:holeSize val="${chart.holeSizePercent.round()}"/>'
              '</c:doughnutChart>';
    axes = '';
  } else if (scatter) {
    plot =
        '<c:scatterChart><c:scatterStyle val="lineMarker"/>'
        '<c:varyColors val="0"/>${sers.join()}$groupLabels'
        '<c:axId val="$_catId"/><c:axId val="$_valId"/></c:scatterChart>';
    // Excel's scatter chart (E1, chart 4): gridlines and a BFBFBF line on
    // both axes, the x axis without a number format unless its values are
    // dates. The x axis' gridlines follow the chart's category axis, which
    // the gallery's scatter charts turn on, as Excel's default has them.
    final String? xFormat = chart.categoryAxis.formatCode;
    axes =
        _valAx(
          _catId,
          _valId,
          pos: 'b',
          gridlines: chart.categoryAxis.gridLines,
          format: xFormat == null ? '' : _numFmt(xFormat),
          crosses: 'autoZero',
          crossBetween: 'midCat',
          title: chart.categoryAxis.title,
          shape: _scatterAxisLine,
        ) +
        _valAx(
          _valId,
          _catId,
          pos: 'l',
          gridlines: true,
          format: _numFmt(chart.series.firstOrNull?.formatCode),
          crosses: 'autoZero',
          crossBetween: 'midCat',
          title: chart.valueAxis.title,
          shape: _scatterAxisLine,
        );
  } else {
    final bool horizontal = chart.kind == ChartKind.bar;
    final bool clustered = chart.grouping == ChartGrouping.clustered;
    // One group per drawn kind and axis, primary first, each in Excel's
    // order of area, bar and line, its series keeping their indexes.
    final StringBuffer groups = StringBuffer();
    bool anySecondary = false;
    for (final bool secondary in <bool>[false, true]) {
      for (final ChartKind kind in <ChartKind>[
        ChartKind.area,
        ChartKind.column,
        ChartKind.line,
      ]) {
        final List<int> members = <int>[
          for (int s = 0; s < chart.series.length; s++)
            if (_onSecondary(chart, chart.series[s]) == secondary &&
                switch (_drawnKind(chart, chart.series[s])) {
                      ChartKind.bar => ChartKind.column,
                      final ChartKind k => k,
                    } ==
                    kind)
              s,
        ];
        if (members.isEmpty) continue;
        anySecondary = anySecondary || secondary;
        final String own = members.map((int s) => sers[s]).join();
        final String axIds = secondary
            ? '<c:axId val="$_secondaryCatId"/><c:axId val="$_secondaryValId"/>'
            : '<c:axId val="$_catId"/><c:axId val="$_valId"/>';
        groups.write(switch (kind) {
          ChartKind.line =>
            '<c:lineChart><c:grouping val="${clustered ? 'standard' : chart.grouping.name}"/>'
                '<c:varyColors val="0"/>$own$groupLabels<c:marker val="1"/>'
                '<c:smooth val="0"/>$axIds</c:lineChart>',
          ChartKind.area =>
            '<c:areaChart><c:grouping val="${clustered ? 'standard' : chart.grouping.name}"/>'
                '<c:varyColors val="0"/>$own$groupLabels$axIds</c:areaChart>',
          _ =>
            '<c:barChart><c:barDir val="${horizontal ? 'bar' : 'col'}"/>'
                '<c:grouping val="${chart.grouping.name}"/><c:varyColors val="0"/>'
                '$own$groupLabels'
                '${_gapAndOverlap(horizontal, clustered, combination: chart.kind == ChartKind.combination)}'
                '$axIds</c:barChart>',
        });
      }
    }
    plot = groups.toString();
    // The value axis number format follows the first series on it.
    String formatOf({required bool secondary}) =>
        chart.grouping == ChartGrouping.percentStacked
        ? '<c:numFmt formatCode="0%" sourceLinked="0"/>'
        : _numFmt(
            chart.series
                .where((ChartSeries s) => _onSecondary(chart, s) == secondary)
                .firstOrNull
                ?.formatCode,
          );
    final String crossBetween = chart.kind == ChartKind.area
        ? 'midCat'
        : 'between';
    axes =
        _catAx(
          _catId,
          _valId,
          pos: horizontal ? 'l' : 'b',
          low: chart.series.any(
            (ChartSeries s) =>
                s.values.values.any((double? v) => v != null && v < 0),
          ),
        ) +
        _valAx(
          _valId,
          _catId,
          pos: horizontal ? 'b' : 'l',
          gridlines: true,
          format: formatOf(secondary: false),
          crosses: 'autoZero',
          crossBetween: crossBetween,
          title: chart.valueAxis.title,
        ) +
        // Excel's secondary axis: a value axis on the right without
        // gridlines that crosses its own deleted category axis at the
        // maximum (an estimate, not checked in Excel: the E1 file has no
        // secondary axis).
        (anySecondary
            ? _valAx(
                    _secondaryValId,
                    _secondaryCatId,
                    pos: 'r',
                    gridlines: false,
                    format: formatOf(secondary: true),
                    crosses: 'max',
                    crossBetween: crossBetween,
                    title: chart.secondaryValueAxis?.title,
                  ) +
                  _catAx(
                    _secondaryCatId,
                    _secondaryValId,
                    pos: 'b',
                    deleted: true,
                  )
            : '');
  }
  final String legend = !chart.legend.visible
      ? ''
      : '<c:legend><c:legendPos val="${switch (chart.legend.position) {
          ChartLegendPosition.top => 't',
          ChartLegendPosition.bottom => 'b',
          ChartLegendPosition.left => 'l',
          ChartLegendPosition.right => 'r',
        }}"/><c:overlay val="0"/>$_noShape${_txPr(65000, 35000, _legendBodyPr)}</c:legend>';
  final String title = entry.excelTitle.isEmpty
      ? '<c:autoTitleDeleted val="1"/>'
      : '${_title(entry.excelTitle)}<c:autoTitleDeleted val="0"/>';
  return '$_xmlDecl<c:chartSpace xmlns:c="$_chartNs" xmlns:a="$_drawingNs" xmlns:r="$_relNs">'
      '<c:date1904 val="0"/><c:roundedCorners val="0"/>'
      '<mc:AlternateContent xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">'
      '<mc:Choice Requires="c14" xmlns:c14="http://schemas.microsoft.com/office/drawing/2007/8/2/chart">'
      '<c14:style val="102"/></mc:Choice><mc:Fallback><c:style val="2"/>'
      '</mc:Fallback></mc:AlternateContent>'
      '<c:chart>$title<c:plotArea><c:layout/>$plot$axes$_noShape</c:plotArea>'
      '$legend<c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart>'
      '<c:spPr><a:solidFill><a:schemeClr val="bg1"/></a:solidFill>$_greyLine'
      '<a:effectLst/></c:spPr>'
      '<c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr/></a:pPr>'
      '<a:endParaRPr lang="en-US"/></a:p></c:txPr>'
      '</c:chartSpace>';
}

/// The gap and overlap Excel gives a new chart: 219 and -27 for clustered
/// columns (`chart_defaults.xlsx`), 182 and none for clustered bars, 150 and
/// 100 for stacked ones, each confirmed by the owner's `chart_reference.xlsx`,
/// and 150 and none for the clustered columns of a [combination] (E1, chart
/// 5) (`ChartTheme.gapWidthPercentOf` and `overlapPercentOf` hold them).
String _gapAndOverlap(
  bool horizontal,
  bool clustered, {
  bool combination = false,
}) {
  if (!clustered) return '<c:gapWidth val="150"/><c:overlap val="100"/>';
  if (horizontal) return '<c:gapWidth val="182"/>';
  if (combination) return '<c:gapWidth val="150"/>';
  return '<c:gapWidth val="219"/><c:overlap val="-27"/>';
}
