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
/// written as such. Series past the sixth carry no `c:spPr`, so Excel chooses
/// their colours itself: that is the open question of Excel's palette past six
/// colours.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_charts_core/jet_charts_core.dart';

import '../gallery.dart';
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
/// cut to 31 characters, with the categories in column A from row 2, a column
/// per series from column B with the series' name in row 1, and below them one
/// chart of [gallerySize] (Excel's default 360 by 216 points). The same
/// [entries] give the same bytes.
///
/// Throws an [ArgumentError] for an entry whose kind is not column, bar, line
/// or area, or with more than 25 series.
Uint8List buildExcelGallery(List<GalleryEntry> entries) {
  for (final GalleryEntry entry in entries) {
    if (!const <ChartKind>[
      ChartKind.column,
      ChartKind.bar,
      ChartKind.line,
      ChartKind.area,
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
  }.toList();
  final Archive archive = Archive();
  void add(String name, String text) =>
      archive.add(ArchiveFile.bytes(name, utf8.encode(text)));

  final int n = entries.length;
  add('[Content_Types].xml', _contentTypes(n));
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

int _rowCount(Chart chart) => <int>[
  for (final ChartSeries s in chart.series) s.values.values.length,
  if (chart.series.isNotEmpty) chart.series.first.categories.values.length,
].fold(0, (int a, int b) => a > b ? a : b);

String _contentTypes(int sheets) {
  const String office = 'application/vnd.openxmlformats-officedocument';
  return '$_xmlDecl<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="$office.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="$office.spreadsheetml.styles+xml"/>'
      '<Override PartName="/xl/theme/theme1.xml" ContentType="$office.theme+xml"/>'
      '${<String>[
        for (int i = 1; i <= sheets; i++) ...<String>['<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="$office.spreadsheetml.worksheet+xml"/>', '<Override PartName="/xl/drawings/drawing$i.xml" ContentType="$office.drawing+xml"/>', '<Override PartName="/xl/charts/chart$i.xml" ContentType="$office.drawingml.chart+xml"/>'],
      ].join()}'
      '</Types>';
}

String _rels(List<String> relationships) =>
    '$_xmlDecl<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '${relationships.join()}</Relationships>';

String _rel(int id, String type, String target) =>
    '<Relationship Id="rId$id" Type="$_relNs/$type" Target="$target"/>';

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
      '<c r="${_column(s + 1)}1" t="inlineStr"><is><t>'
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
    if (category != null) {
      out.write(
        '<c r="A$r" t="inlineStr"><is><t>${_escape('$category')}</t></is></c>',
      );
    }
    for (int s = 0; s < chart.series.length; s++) {
      final ChartSeries series = chart.series[s];
      final List<double?> values = series.values.values;
      final double? value = i < values.length ? values[i] : null;
      if (value == null || !value.isFinite) continue;
      final String style = series.formatCode == null
          ? ''
          : ' s="${codes.indexOf(series.formatCode!) + 1}"';
      out.write(
        '<c r="${_column(s + 1)}$r"$style><v>${_numText(value)}</v></c>',
      );
    }
    out.write('</row>');
  }
  out.write('</sheetData><drawing r:id="rId1"/></worksheet>');
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

String _showFlags(bool value) =>
    '<c:showLegendKey val="0"/><c:showVal val="${value ? 1 : 0}"/>'
    '<c:showCatName val="0"/><c:showSerName val="0"/>'
    '<c:showPercent val="0"/><c:showBubbleSize val="0"/>';

/// A series' data labels, shown: Excel places them by the chart's kind.
String get _seriesLabels =>
    '<c:dLbls>$_noShape${_txPr(75000, 25000, _labelBodyPr)}${_showFlags(true)}</c:dLbls>';

String _seriesShape(ChartKind kind, int index) {
  // Past the sixth series Excel chooses the colour (see the library comment).
  if (index >= 6) return '';
  final String accent = '<a:schemeClr val="accent${index + 1}"/>';
  if (kind == ChartKind.line) {
    return '<c:spPr><a:ln w="28575" cap="rnd"><a:solidFill>$accent'
        '</a:solidFill><a:round/></a:ln><a:effectLst/></c:spPr>'
        '<c:marker><c:symbol val="circle"/><c:size val="5"/><c:spPr>'
        '<a:solidFill>$accent</a:solidFill><a:ln w="9525"><a:solidFill>'
        '$accent</a:solidFill></a:ln><a:effectLst/></c:spPr></c:marker>';
  }
  return '<c:spPr><a:solidFill>$accent</a:solidFill><a:ln><a:noFill/></a:ln>'
      '<a:effectLst/></c:spPr>';
}

String _chartXml(GalleryEntry entry) {
  final Chart chart = entry.chart;
  final String sheet = "'${_sheetName(entry).replaceAll("'", "''")}'";
  final int count = _rowCount(chart);
  final int last = count + 1;
  final bool labels = chart.dataLabels.visible;
  final List<Object?> categories = chart.series.isEmpty
      ? const <Object?>[]
      : chart.series.first.categories.values;
  final StringBuffer sers = StringBuffer();
  for (int s = 0; s < chart.series.length; s++) {
    final ChartSeries series = chart.series[s];
    final String column = _column(s + 1);
    final List<double?> values = series.values.values;
    final String name = _escape(_seriesName(series, s));
    final String cat =
        '<c:cat><c:strRef><c:f>$sheet!\$A\$2:\$A\$$last</c:f><c:strCache>'
        '<c:ptCount val="$count"/>${<String>[for (int i = 0; i < categories.length; i++)
          if (categories[i] != null) '<c:pt idx="$i"><c:v>${_escape('${categories[i]}')}</c:v></c:pt>'].join()}</c:strCache></c:strRef></c:cat>';
    final String val =
        '<c:val><c:numRef><c:f>$sheet!\$$column\$2:\$$column\$$last</c:f>'
        '<c:numCache><c:formatCode>${_escape(series.formatCode ?? 'General')}'
        '</c:formatCode><c:ptCount val="$count"/>${<String>[for (int i = 0; i < values.length; i++)
          if (values[i] case final double v when v.isFinite) '<c:pt idx="$i"><c:v>${_numText(v)}</c:v></c:pt>'].join()}</c:numCache></c:numRef></c:val>';
    sers
      ..write('<c:ser><c:idx val="$s"/><c:order val="$s"/>')
      ..write(
        '<c:tx><c:strRef><c:f>$sheet!\$$column\$1</c:f><c:strCache>'
        '<c:ptCount val="1"/><c:pt idx="0"><c:v>$name</c:v></c:pt>'
        '</c:strCache></c:strRef></c:tx>',
      )
      ..write(_seriesShape(chart.kind, s))
      ..write(switch (chart.kind) {
        ChartKind.line =>
          '${labels ? _seriesLabels : ''}$cat$val<c:smooth val="0"/>',
        ChartKind.area => '${labels ? _seriesLabels : ''}$cat$val',
        _ =>
          '<c:invertIfNegative val="0"/>${labels ? _seriesLabels : ''}$cat$val',
      })
      ..write('</c:ser>');
  }
  final bool horizontal = chart.kind == ChartKind.bar;
  final bool clustered = chart.grouping == ChartGrouping.clustered;
  final String groupLabels = '<c:dLbls>${_showFlags(false)}</c:dLbls>';
  const String axIds = '<c:axId val="111111111"/><c:axId val="222222222"/>';
  final String plot = switch (chart.kind) {
    ChartKind.line =>
      '<c:lineChart><c:grouping val="${clustered ? 'standard' : chart.grouping.name}"/>'
          '<c:varyColors val="0"/>$sers$groupLabels<c:marker val="1"/>'
          '<c:smooth val="0"/>$axIds</c:lineChart>',
    ChartKind.area =>
      '<c:areaChart><c:grouping val="${chart.grouping.name}"/>'
          '<c:varyColors val="0"/>$sers$groupLabels$axIds</c:areaChart>',
    _ =>
      '<c:barChart><c:barDir val="${horizontal ? 'bar' : 'col'}"/>'
          '<c:grouping val="${chart.grouping.name}"/><c:varyColors val="0"/>'
          '$sers$groupLabels${_gapAndOverlap(horizontal, clustered)}'
          '$axIds</c:barChart>',
  };
  // The value axis number format follows the first series.
  final String valueFormat = chart.grouping == ChartGrouping.percentStacked
      ? '<c:numFmt formatCode="0%" sourceLinked="0"/>'
      : '<c:numFmt formatCode="${_escape(chart.series.firstOrNull?.formatCode ?? 'General')}" '
            'sourceLinked="1"/>';
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
      '<c:chart>$title<c:plotArea><c:layout/>$plot'
      '<c:catAx><c:axId val="111111111"/>'
      '<c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/>'
      '<c:axPos val="${horizontal ? 'l' : 'b'}"/>'
      '<c:numFmt formatCode="General" sourceLinked="1"/>'
      '<c:majorTickMark val="none"/><c:minorTickMark val="none"/>'
      '<c:tickLblPos val="nextTo"/><c:spPr><a:noFill/>$_greyLine'
      '<a:effectLst/></c:spPr>${_txPr(65000, 35000, _axisBodyPr)}'
      '<c:crossAx val="222222222"/><c:crosses val="autoZero"/><c:auto val="1"/>'
      '<c:lblAlgn val="ctr"/><c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/>'
      '</c:catAx>'
      '<c:valAx><c:axId val="222222222"/>'
      '<c:scaling><c:orientation val="minMax"/></c:scaling><c:delete val="0"/>'
      '<c:axPos val="${horizontal ? 'b' : 'l'}"/>'
      '<c:majorGridlines><c:spPr>$_greyLine<a:effectLst/></c:spPr>'
      '</c:majorGridlines>$valueFormat'
      '<c:majorTickMark val="none"/><c:minorTickMark val="none"/>'
      '<c:tickLblPos val="nextTo"/>$_noShape${_txPr(65000, 35000, _axisBodyPr)}'
      '<c:crossAx val="111111111"/><c:crosses val="autoZero"/>'
      '<c:crossBetween val="${chart.kind == ChartKind.area ? 'midCat' : 'between'}"/>'
      '</c:valAx>$_noShape</c:plotArea>$legend'
      '<c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/></c:chart>'
      '<c:spPr><a:solidFill><a:schemeClr val="bg1"/></a:solidFill>$_greyLine'
      '<a:effectLst/></c:spPr>'
      '<c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr/></a:pPr>'
      '<a:endParaRPr lang="en-US"/></a:p></c:txPr>'
      '</c:chartSpace>';
}

/// The gap and overlap Excel gives a new chart: 219 and -27 for clustered
/// columns (`chart_defaults.xlsx`), 182 and none for clustered bars, 150 and
/// 100 for stacked ones, each confirmed by the owner's `chart_reference.xlsx`
/// (`ChartTheme.gapWidthPercentOf` and `overlapPercentOf` hold them).
String _gapAndOverlap(bool horizontal, bool clustered) {
  if (!clustered) return '<c:gapWidth val="150"/><c:overlap val="100"/>';
  if (horizontal) return '<c:gapWidth val="182"/>';
  return '<c:gapWidth val="219"/><c:overlap val="-27"/>';
}
