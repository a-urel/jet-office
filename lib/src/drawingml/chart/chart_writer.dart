/// The chart writer: [writeDrawingChartSpace] turns a [DrawingChartSpace]
/// into a `c:chartSpace` part as Excel for Mac writes it.
///
/// Not ported from Quds; written for jet_office.
///
/// The template is Excel's own output: the two charts of the owner's
/// `chart_defaults.xlsx`, whose typed forms write parts equal to them by
/// `xmlDifference` (and byte for byte), and the 23 of
/// `chart_reference.xlsx` (every kind and grouping, titles, legends, axis
/// titles, scaling, formats, data labels, a hidden axis), all but one of
/// which read typed (`docs/drawingml-charts.md`, "Excel's reference
/// workbook"), and the pies and doughnuts of `chart_reference_j4.xlsx`
/// (charts 1, 2, 3 and 7, `chart_writer_pie.dart`). The elements are in the schema's order, and everything the
/// typed form does not carry is fixed as Excel writes it.
///
/// Data problems never throw: a value that is `NaN` or infinite is left out
/// and text loses the characters XML 1.0 forbids, each reported once as a
/// [DrawingChartIssue]. A chart the writer cannot express is a programmer
/// error and throws an [ArgumentError]. The writer is linear in the number of
/// points.
///
/// This layer imports `opc`, `xml`, `common`, `jet_charts_core` and `jet_core`
/// only, never `xlsx` or `docx` (decisions 0014 and 0015).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_charts_core/jet_charts_core.dart';

import '../../xml/xml_escape.dart';
import '../../xml/xml_writer.dart';
import '../color.dart';
import '../text.dart';
import 'chart_space.dart';
import 'chart_values.dart';

part 'chart_writer_pie.dart';
part 'chart_writer_series.dart';

/// A written chart part: its bytes and the data problems the writer got past.
final class DrawingChartWritten {
  /// Creates a written part of [bytes] with [issues].
  const DrawingChartWritten(this.bytes, this.issues);

  /// The part, UTF-8 encoded: an XML declaration, a carriage return and line
  /// feed, and the `c:chartSpace` element, as Excel writes it.
  final Uint8List bytes;

  /// Each kind of data problem met, once, in the order first met.
  final List<DrawingChartIssue> issues;
}

/// Writes [space] as a `c:chartSpace` part drawn in [theme].
///
/// The theme gives the series colours (`ChartTheme.colorOf`), the text
/// styles, the grid, axis and background colours, the line widths, the
/// marker size, the gap width and the overlap, and with its `exportColors`
/// whether colours and fonts are written bound to the file's theme or fixed.
/// A line series has a circle marker when the theme's `lineMarkers` is on,
/// else the symbol `none` (Excel's line without markers): the layout's
/// marker on a lone point is not written, as a series' marker in the part is
/// all or nothing.
///
/// The gap width is kept within 0 and 500 and a clustered chart's overlap
/// within -100 and 100, Excel's ranges (as the layout keeps them), rounded to
/// whole numbers; a `NaN` gap width is 0.
///
/// A date category is written as a serial of the 1904 date system when
/// [date1904] is set (a workbook's `date1904`), of the 1900 one otherwise.
///
/// A pie or donut is written as Excel's `c:pieChart` or `c:doughnutChart`
/// (`chart_reference_j4.xlsx`, charts 1, 2, 3 and 7): no axes (the axis ids
/// of `space.ids` are checked but not written), colours varied by slice, a
/// `c:dPt` per slice in its colour (`ChartTheme.pointColorOf`, else the
/// theme's colour of the slice's index) outlined in the theme's background,
/// `sliceBorderWidth` wide, the first slice at 0 and, for a donut, the
/// `holeSizePercent` rounded. What a pie does not draw is not written: the
/// axes, the grouping, a series' own colour and its smoothing.
///
/// Throws an [ArgumentError] when the chart's kind is not column, bar, line,
/// area, pie or donut, when it has centre text (a part cannot carry it; a
/// hole size is ignored but by a donut), when it has a secondary value axis, when a series is bound to
/// the secondary axis or has a kind other than `null` or the chart's, when an
/// axis id of `space.ids` (the four, secondary ones too) is outside 0 to
/// 4294967295 or two of them are equal, or
/// when one of its series ids is not a GUID in braces.
///
/// Also throws an [ArgumentError], naming the field (`theme.lineWidth`,
/// `theme.spacing.gridLineWidth`, `theme.titleText.size` and the like), when
/// a value of [theme] the part cannot hold is not finite or outside its
/// range: the line widths ([ChartTheme.lineWidth],
/// [ChartTheme.sliceBorderWidth] and the spacing's grid and axis line widths)
/// within 0 and 1584 points (`ST_LineWidth`, 0 to 20116800
/// EMU), [ChartTheme.markerSize] not negative (it is then kept within 2 and
/// 72, Excel's range), and the size of each of the four text styles within 1
/// and 4000 points (`ST_TextFontSize`, 100 to 400000 hundredths). The theme is
/// checked whatever the chart uses of it.
DrawingChartWritten writeDrawingChartSpace(
  DrawingChartSpace space,
  ChartTheme theme, {
  bool date1904 = false,
}) {
  _checkExpressible(space.chart);
  _checkIds(space.ids);
  _checkTheme(theme);
  final StringBuffer out = StringBuffer();
  final _ChartWriter writer = _ChartWriter(
    XmlWriter(out),
    space,
    theme,
    date1904,
  );
  writer.write();
  return DrawingChartWritten(
    utf8.encode(out.toString()),
    List<DrawingChartIssue>.unmodifiable(writer.issues),
  );
}

void _checkExpressible(Chart chart) {
  switch (chart.kind) {
    case ChartKind.column ||
        ChartKind.bar ||
        ChartKind.line ||
        ChartKind.area ||
        ChartKind.pie ||
        ChartKind.donut:
      break;
    default:
      throw ArgumentError.value(
        chart.kind,
        'chart.kind',
        'must be column, bar, line, area, pie or donut',
      );
  }
  if (chart.centerText != null) {
    throw ArgumentError.value(
      chart.centerText,
      'chart.centerText',
      'must be null: a chart part cannot carry centre text',
    );
  }
  if (chart.secondaryValueAxis != null) {
    throw ArgumentError.value(
      chart.secondaryValueAxis,
      'chart.secondaryValueAxis',
      'must be null',
    );
  }
  for (int i = 0; i < chart.series.length; i++) {
    final ChartSeries series = chart.series[i];
    if (series.axis != ChartAxisBinding.primary) {
      throw ArgumentError.value(
        series.axis,
        'chart.series[$i].axis',
        'must be primary',
      );
    }
    if (series.kind != null && series.kind != chart.kind) {
      throw ArgumentError.value(
        series.kind,
        'chart.series[$i].kind',
        'must be null or ${chart.kind.name}',
      );
    }
  }
}

/// The widest line `ST_LineWidth` holds, 20116800 EMU, in points.
const double _maxLineWidth = 1584;

/// The smallest and largest text size `ST_TextFontSize` holds (100 and
/// 400000 hundredths of a point), in points.
const double _minTextSize = 1;
const double _maxTextSize = 4000;

void _checkTheme(ChartTheme theme) {
  void within(double value, String name, double low, double high) {
    if (!value.isFinite || value < low || value > high) {
      throw ArgumentError.value(
        value,
        'theme.$name',
        'must be finite, within $low and $high',
      );
    }
  }

  within(theme.lineWidth, 'lineWidth', 0, _maxLineWidth);
  within(theme.markerSize, 'markerSize', 0, double.maxFinite);
  within(theme.sliceBorderWidth, 'sliceBorderWidth', 0, _maxLineWidth);
  within(
    theme.spacing.gridLineWidth,
    'spacing.gridLineWidth',
    0,
    _maxLineWidth,
  );
  within(
    theme.spacing.axisLineWidth,
    'spacing.axisLineWidth',
    0,
    _maxLineWidth,
  );
  for (final (String name, ChartTextStyle style) in <(String, ChartTextStyle)>[
    ('titleText', theme.titleText),
    ('axisLabels', theme.axisLabels),
    ('legendText', theme.legendText),
    ('dataLabels', theme.dataLabels),
  ]) {
    within(style.size, '$name.size', _minTextSize, _maxTextSize);
  }
}

/// The largest `c:axId`, that of `xsd:unsignedInt`.
const int _maxAxisId = 4294967295;

void _checkIds(DrawingChartIds ids) {
  final List<(String, int)> axes = <(String, int)>[
    ('ids.categoryAxis', ids.categoryAxis),
    ('ids.valueAxis', ids.valueAxis),
    ('ids.secondaryCategoryAxis', ids.secondaryCategoryAxis),
    ('ids.secondaryValueAxis', ids.secondaryValueAxis),
  ];
  for (final (String name, int id) in axes) {
    if (id < 0 || id > _maxAxisId) {
      throw ArgumentError.value(id, name, 'must be within 0 and $_maxAxisId');
    }
  }
  for (int i = 1; i < axes.length; i++) {
    for (int j = 0; j < i; j++) {
      if (axes[i].$2 == axes[j].$2) {
        throw ArgumentError.value(
          axes[i].$2,
          axes[i].$1,
          'must differ from ${axes[j].$1}',
        );
      }
    }
  }
  for (int i = 0; i < ids.series.length; i++) {
    if (!isDrawingChartSeriesId(ids.series[i])) {
      throw ArgumentError.value(
        ids.series[i],
        'ids.series[$i]',
        'must be a GUID in braces',
      );
    }
  }
}

const String _relationshipsNamespace =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _c16r2Namespace =
    'http://schemas.microsoft.com/office/drawing/2015/06/chart';
const String _c14Namespace =
    'http://schemas.microsoft.com/office/drawing/2007/8/2/chart';
const String _c16Namespace =
    'http://schemas.microsoft.com/office/drawing/2014/chart';
const String _c16r3Namespace =
    'http://schemas.microsoft.com/office/drawing/2017/03/chart';
const String _markupCompatibilityNamespace =
    'http://schemas.openxmlformats.org/markup-compatibility/2006';

/// The `uri` of the `c:ext` that holds a series' `c16:uniqueId`.
const String _uniqueIdExtension = '{C3380CC4-5D6E-409C-BE32-E72D297353CC}';

/// The `uri` of the `c:ext` that holds Excel's data display options.
const String _dataDisplayExtension = '{56B9EC1D-385E-4148-901F-78D8002777C0}';

/// English Metric Units per point, the unit of a DrawingML line width.
const int _emuPerPoint = 12700;

/// The width of a marker's outline Excel writes, in EMU (0.75 pt).
const String _markerLineWidth = '9525';

/// The `uri` of the `c:ext` that holds a `c:dLbls`' `c15:leaderLines`.
const String _leaderLinesExtension = '{CE6537A1-D6FC-4f65-9D91-7224C49458BB}';

const String _c15Namespace =
    'http://schemas.microsoft.com/office/drawing/2012/chart';

/// The colour of Excel's data label leader lines, `A6A6A6`: `tx1` with
/// `lumMod` 0.35 and `lumOff` 0.65 (`chart_reference.xlsx`, charts 20 and
/// 21). No theme value: the layout draws no leader lines.
final ChartColor _leaderLineColor = ChartColor.scheme(
  ChartSchemeColor.dark1,
  rgb: 0xA6A6A6,
  lumMod: 0.35,
  lumOff: 0.65,
);

/// The width of Excel's leader lines, in points (9525 EMU).
const double _leaderLineWidth = 0.75;

/// The size of an axis title's text Excel gives it, in points.
const double _axisTitleSize = 10;

final class _ChartWriter {
  _ChartWriter(this.w, this.space, this.theme, this.date1904)
    : chart = space.chart,
      mode = theme.exportColors;

  final XmlWriter w;
  final DrawingChartSpace space;
  final Chart chart;
  final ChartTheme theme;
  final bool date1904;
  final ChartExportColors mode;
  final List<DrawingChartIssue> issues = <DrawingChartIssue>[];
  late final String language = _scrub(space.language);

  bool get _bars =>
      chart.kind == ChartKind.column || chart.kind == ChartKind.bar;

  /// Whether the chart is a pie or a donut.
  bool get _round =>
      chart.kind == ChartKind.pie || chart.kind == ChartKind.donut;

  void _report(DrawingChartIssue issue) {
    if (!issues.contains(issue)) {
      issues.add(issue);
    }
  }

  /// [text] without the characters XML 1.0 forbids, reporting
  /// [DrawingChartIssue.invalidCharacter] when any were dropped.
  String _scrub(String text) {
    final ScrubResult result = scrubXmlText(text);
    if (result.removed > 0) {
      _report(DrawingChartIssue.invalidCharacter);
    }
    return result.text;
  }

  /// [text] scrubbed ([_scrub]) and protected from ST_Xstring decoding
  /// ([drawingEscapeXstring]), for a `c:v` of text and a `c:f`.
  String _xstring(String text) => drawingEscapeXstring(_scrub(text));

  void _value(String name, String value) {
    w.empty(name, <String, String>{'val': value});
  }

  void _element(String name, String text) {
    w.start(name);
    w.text(text);
    w.end();
  }

  void write() {
    w.declaration();
    w.raw('\r\n');
    w.start('c:chartSpace');
    w.attribute('xmlns:c', drawingChartNamespace);
    w.attribute('xmlns:a', drawingMainNamespace);
    w.attribute('xmlns:r', _relationshipsNamespace);
    w.attribute('xmlns:c16r2', _c16r2Namespace);
    _value('c:date1904', date1904 ? '1' : '0');
    _value('c:lang', language);
    _value('c:roundedCorners', '0');
    _writeStyle();
    _writeChart();
    w.start('c:spPr');
    _solidFill(theme.background);
    _line(theme.gridLine, theme.spacing.gridLineWidth);
    w.empty('a:effectLst');
    w.end();
    writeDrawingTextBody(
      w,
      theme.axisLabels,
      mode: mode,
      language: language,
      use: DrawingTextUse.chartSpace,
    );
    w.start('c:printSettings');
    w.empty('c:headerFooter');
    w.empty('c:pageMargins', <String, String>{
      'b': '0.75',
      'l': '0.7',
      'r': '0.7',
      't': '0.75',
      'header': '0.3',
      'footer': '0.3',
    });
    w.empty('c:pageSetup');
    w.end();
    w.end();
  }

  /// The `mc:AlternateContent` of `c14:style 102` and `c:style 2`.
  void _writeStyle() {
    w.start('mc:AlternateContent');
    w.attribute('xmlns:mc', _markupCompatibilityNamespace);
    w.start('mc:Choice');
    w.attribute('Requires', 'c14');
    w.attribute('xmlns:c14', _c14Namespace);
    _value('c14:style', '102');
    w.end();
    w.start('mc:Fallback');
    _value('c:style', '2');
    w.end();
    w.end();
  }

  void _writeChart() {
    w.start('c:chart');
    final ChartTitle? title = chart.title;
    if (title != null) {
      _writeTitle(title.text, theme.titleText);
      _value('c:autoTitleDeleted', '0');
    } else if (space.autoTitle) {
      _writeTitle(null, theme.titleText);
      _value('c:autoTitleDeleted', '0');
    } else {
      _value('c:autoTitleDeleted', '1');
    }
    w.start('c:plotArea');
    w.empty('c:layout');
    if (_round) {
      _writePieGroup();
    } else {
      _writeGroup();
      _writeCategoryAxis();
      _writeValueAxis();
    }
    _noFillShape();
    w.end();
    if (chart.legend.visible) {
      _writeLegend();
    }
    _value('c:plotVisOnly', '1');
    // Excel shows a blank as zero where a gap would break a stack or an
    // area: every area chart and the stacked line charts
    // (`chart_reference.xlsx`, charts 8 to 12).
    _value(
      'c:dispBlanksAs',
      chart.kind == ChartKind.area ||
              (chart.kind == ChartKind.line &&
                  chart.grouping != ChartGrouping.clustered)
          ? 'zero'
          : 'gap',
    );
    _value('c:showDLblsOverMax', '0');
    w.start('c:extLst');
    w.start('c:ext');
    w.attribute('uri', _dataDisplayExtension);
    w.attribute('xmlns:c16r3', _c16r3Namespace);
    w.start('c16r3:dataDisplayOptions16');
    _value('c16r3:dispNaAsBlank', '1');
    w.end();
    w.end();
    w.end();
    w.end();
  }

  /// A `c:title` of [text] in [style], or Excel's automatic title (no
  /// `c:tx`) when [text] is `null`; an [axis] title has no `spc`, and
  /// [vertical] turns it a quarter to the left, as Excel writes a vertical
  /// axis' title.
  void _writeTitle(
    String? text,
    ChartTextStyle style, {
    bool axis = false,
    bool vertical = false,
  }) {
    final DrawingTextUse use = axis
        ? DrawingTextUse.axisTitle
        : DrawingTextUse.title;
    w.start('c:title');
    if (text != null) {
      w.start('c:tx');
      writeDrawingRichText(
        w,
        _scrub(text),
        style,
        mode: mode,
        language: language,
        use: use,
        vertical: vertical,
      );
      w.end();
    }
    _value('c:overlay', '0');
    _noFillShape();
    writeDrawingTextBody(
      w,
      style,
      mode: mode,
      language: language,
      use: use,
      vertical: vertical,
    );
    w.end();
  }

  void _writeGroup() {
    final String groupName = switch (chart.kind) {
      ChartKind.line => 'c:lineChart',
      ChartKind.area => 'c:areaChart',
      _ => 'c:barChart',
    };
    w.start(groupName);
    if (_bars) {
      _value('c:barDir', chart.kind == ChartKind.bar ? 'bar' : 'col');
    }
    _value('c:grouping', switch (chart.grouping) {
      ChartGrouping.clustered => _bars ? 'clustered' : 'standard',
      ChartGrouping.stacked => 'stacked',
      ChartGrouping.percentStacked => 'percentStacked',
    });
    _value('c:varyColors', '0');
    for (int i = 0; i < chart.series.length; i++) {
      _writeSeries(chart.series[i], i);
    }
    _writeGroupDataLabels();
    if (_bars) {
      _value(
        'c:gapWidth',
        _percent(theme.gapWidthPercentOf(chart.kind, chart.grouping), 0, 500),
      );
      final String overlap = _percent(
        theme.overlapPercentOf(chart.kind, chart.grouping),
        -100,
        100,
      );
      // Excel writes no overlap of 0, the schema's default (its clustered bar
      // chart, `chart_reference.xlsx` chart 4).
      if (overlap != '0') {
        _value('c:overlap', overlap);
      }
    } else if (chart.kind == ChartKind.line) {
      _value('c:marker', '1');
      _value('c:smooth', '0');
    }
    _value('c:axId', space.ids.categoryAxis.toString());
    _value('c:axId', space.ids.valueAxis.toString());
    w.end();
  }

  /// The group's `c:dLbls`: every flag off, as Excel writes it whether the
  /// labels are shown or not; shown labels are each series' own `c:dLbls`
  /// (`chart_reference.xlsx`, charts 20 and 21).
  void _writeGroupDataLabels() {
    w.start('c:dLbls');
    _writeLabelFlags(showValue: false);
    w.end();
  }

  /// The six `c:show*` flags of a `c:dLbls`, all off but `c:showVal` when
  /// [showValue] and `c:showPercent` when [showPercent].
  void _writeLabelFlags({required bool showValue, bool showPercent = false}) {
    _value('c:showLegendKey', '0');
    _value('c:showVal', showValue ? '1' : '0');
    _value('c:showCatName', '0');
    _value('c:showSerName', '0');
    _value('c:showPercent', showPercent ? '1' : '0');
    _value('c:showBubbleSize', '0');
  }

  void _writeCategoryAxis() {
    final ChartAxis axis = chart.categoryAxis;
    w.start('c:catAx');
    _writeAxisStart(
      axis,
      space.ids.categoryAxis,
      chart.kind == ChartKind.bar ? 'l' : 'b',
      value: false,
    );
    if (axis.visible) {
      w.start('c:spPr');
      w.empty('a:noFill');
      _line(theme.axisLine, theme.spacing.axisLineWidth);
      w.empty('a:effectLst');
      w.end();
      _writeAxisLabels();
    }
    _value('c:crossAx', space.ids.valueAxis.toString());
    _value('c:crosses', 'autoZero');
    _value('c:auto', '1');
    _value('c:lblAlgn', 'ctr');
    _value('c:lblOffset', '100');
    _value('c:noMultiLvlLbl', '0');
    w.end();
  }

  void _writeValueAxis() {
    final ChartAxis axis = chart.valueAxis;
    w.start('c:valAx');
    _writeAxisStart(
      axis,
      space.ids.valueAxis,
      chart.kind == ChartKind.bar ? 'b' : 'l',
      value: true,
    );
    if (axis.visible) {
      _noFillShape();
      _writeAxisLabels();
    }
    _value('c:crossAx', space.ids.categoryAxis.toString());
    _value('c:crosses', 'autoZero');
    _value(
      'c:crossBetween',
      chart.kind == ChartKind.area ? 'midCat' : 'between',
    );
    final double? majorUnit = axis.majorUnit;
    if (majorUnit != null) {
      _writeNumberValue('c:majorUnit', majorUnit);
    }
    w.end();
  }

  /// An axis from `c:axId` through `c:tickLblPos`: the scaling (with the
  /// minimum and maximum of a [value] axis), `c:delete`, the position, the
  /// grid lines, the title, the number format and Excel's tick settings
  /// (`low` labels on a category axis that crosses inside the plot,
  /// [_crossesInside]).
  void _writeAxisStart(
    ChartAxis axis,
    int id,
    String position, {
    required bool value,
  }) {
    _value('c:axId', id.toString());
    w.start('c:scaling');
    _value('c:orientation', 'minMax');
    if (value) {
      final double? max = axis.max;
      final double? min = axis.min;
      if (max != null) {
        _writeNumberValue('c:max', max);
      }
      if (min != null) {
        _writeNumberValue('c:min', min);
      }
    }
    w.end();
    _value('c:delete', axis.visible ? '0' : '1');
    _value('c:axPos', position);
    if (axis.gridLines) {
      w.start('c:majorGridlines');
      w.start('c:spPr');
      _line(theme.gridLine, theme.spacing.gridLineWidth);
      w.empty('a:effectLst');
      w.end();
      w.end();
    }
    final String? title = axis.title;
    if (title != null) {
      _writeTitle(
        title,
        theme.axisLabels.copyWith(size: _axisTitleSize),
        axis: true,
        // The value axis is vertical except in a bar chart, where the
        // category axis is.
        vertical: value != (chart.kind == ChartKind.bar),
      );
    }
    final String? formatCode = axis.formatCode;
    w.empty('c:numFmt', <String, String>{
      'formatCode': formatCode != null
          ? _scrub(formatCode)
          // A percent stacked value axis is linked to the source but shows
          // `0%` (`chart_reference.xlsx`, charts 3, 6, 9 and 12).
          : (value && chart.grouping == ChartGrouping.percentStacked
                ? '0%'
                : 'General'),
      'sourceLinked': formatCode == null ? '1' : '0',
    });
    // Excel ticks an area chart's category axis outside
    // (`chart_reference.xlsx`, charts 10 to 12).
    _value(
      'c:majorTickMark',
      !value && chart.kind == ChartKind.area ? 'out' : 'none',
    );
    _value('c:minorTickMark', 'none');
    _value('c:tickLblPos', !value && _crossesInside ? 'low' : 'nextTo');
  }

  /// Whether the category axis crosses the value axis inside the plot: a
  /// series has a negative value or the value axis starts below zero. Its
  /// labels then go `low`, under the plot (left of a bar chart's), as the
  /// layout draws them, where Excel's `nextTo` would put them at the zero
  /// line under the negative bars (the owner's choice, J3 and J4 gallery
  /// checks).
  bool get _crossesInside {
    final double? min = chart.valueAxis.min;
    if (min != null && min < 0) {
      return true;
    }
    return chart.series.any(
      (ChartSeries s) => s.values.values.any((double? v) => v != null && v < 0),
    );
  }

  void _writeAxisLabels() {
    writeDrawingTextBody(
      w,
      theme.axisLabels,
      mode: mode,
      language: language,
      use: DrawingTextUse.axis,
    );
  }

  /// An element of `val` [v], left out with a
  /// [DrawingChartIssue.nonFiniteValue] when [v] is `NaN` or infinite.
  void _writeNumberValue(String name, double v) {
    if (!v.isFinite) {
      _report(DrawingChartIssue.nonFiniteValue);
      return;
    }
    _value(name, drawingNumberText(v));
  }

  void _writeLegend() {
    w.start('c:legend');
    _value('c:legendPos', switch (chart.legend.position) {
      ChartLegendPosition.bottom => 'b',
      ChartLegendPosition.top => 't',
      ChartLegendPosition.left => 'l',
      ChartLegendPosition.right => 'r',
    });
    _value('c:overlay', '0');
    _noFillShape();
    writeDrawingTextBody(
      w,
      theme.legendText,
      mode: mode,
      language: language,
      use: DrawingTextUse.legend,
    );
    w.end();
  }

  /// [value] kept within [low] and [high] (`NaN` as [low]) and rounded, as
  /// text: jet_charts_core's layout keeps the gap width and overlap so.
  static String _percent(double value, double low, double high) =>
      (value.isNaN ? low : value.clamp(low, high)).round().toString();

  void _solidFill(ChartColor color, {double? alpha}) {
    w.start('a:solidFill');
    writeDrawingColor(w, color, mode, alpha: alpha);
    w.end();
  }

  /// An `a:ln` of [color] and [widthPoints], with Excel's flat cap, single
  /// compound, centred alignment and round join.
  void _line(ChartColor color, double widthPoints) {
    w.start('a:ln');
    w.attribute('w', (widthPoints * _emuPerPoint).round().toString());
    w.attribute('cap', 'flat');
    w.attribute('cmpd', 'sng');
    w.attribute('algn', 'ctr');
    _solidFill(color);
    w.empty('a:round');
    w.end();
  }

  /// A `c:spPr` of no fill, no line and an empty effect list.
  void _noFillShape() {
    w.start('c:spPr');
    w.empty('a:noFill');
    w.start('a:ln');
    w.empty('a:noFill');
    w.end();
    w.empty('a:effectLst');
    w.end();
  }
}
