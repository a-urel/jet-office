/// The chart writer: [writeDrawingChartSpace] turns a [DrawingChartSpace]
/// into a `c:chartSpace` part as Excel for Mac writes it.
///
/// Not ported from Quds; written for jet_office.
///
/// The template is Excel's own output, the two charts of the owner's
/// `chart_defaults.xlsx`: a part written from the typed form of either is
/// equal to it by `xmlDifference` (and byte for byte). The elements are in the
/// schema's order, and everything the typed form does not carry is fixed as
/// Excel writes it. What those two charts do not show (other kinds and
/// groupings, a legend, data labels, axis titles and scaling) follows
/// ECMA-376 and Excel's known habits until the owner's reference workbook
/// shows it (ruling R7 of C1).
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
///
/// Throws an [ArgumentError] when the chart's kind is not column, bar, line
/// or area, when it has a secondary value axis, or when a series is bound to
/// the secondary axis or has a kind other than `null` or the chart's.
DrawingChartWritten writeDrawingChartSpace(
  DrawingChartSpace space,
  ChartTheme theme,
) {
  _checkExpressible(space.chart);
  final StringBuffer out = StringBuffer();
  final _ChartWriter writer = _ChartWriter(XmlWriter(out), space, theme);
  writer.write();
  return DrawingChartWritten(
    utf8.encode(out.toString()),
    List<DrawingChartIssue>.unmodifiable(writer.issues),
  );
}

void _checkExpressible(Chart chart) {
  switch (chart.kind) {
    case ChartKind.column || ChartKind.bar || ChartKind.line || ChartKind.area:
      break;
    default:
      throw ArgumentError.value(
        chart.kind,
        'chart.kind',
        'must be column, bar, line or area',
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

/// The size of an axis title's text Excel gives it, in points.
const double _axisTitleSize = 10;

final class _ChartWriter {
  _ChartWriter(this.w, this.space, this.theme)
    : chart = space.chart,
      mode = theme.exportColors;

  final XmlWriter w;
  final DrawingChartSpace space;
  final Chart chart;
  final ChartTheme theme;
  final ChartExportColors mode;
  final List<DrawingChartIssue> issues = <DrawingChartIssue>[];
  late final String language = _scrub(space.language);

  bool get _bars =>
      chart.kind == ChartKind.column || chart.kind == ChartKind.bar;

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
    _value('c:date1904', '0');
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
    _writeGroup();
    _writeCategoryAxis();
    _writeValueAxis();
    _noFillShape();
    w.end();
    if (chart.legend.visible) {
      _writeLegend();
    }
    _value('c:plotVisOnly', '1');
    _value('c:dispBlanksAs', 'gap');
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
  /// `c:tx`) when [text] is `null`.
  void _writeTitle(String? text, ChartTextStyle style) {
    w.start('c:title');
    if (text != null) {
      w.start('c:tx');
      writeDrawingRichText(
        w,
        _scrub(text),
        style,
        mode: mode,
        language: language,
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
      use: DrawingTextUse.title,
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
      _value('c:gapWidth', theme.gapWidthPercent.round().toString());
      _value(
        'c:overlap',
        chart.grouping == ChartGrouping.clustered
            ? theme.spacing.overlapPercent.round().toString()
            : '100',
      );
    } else if (chart.kind == ChartKind.line) {
      _value('c:marker', '1');
      _value('c:smooth', '0');
    }
    _value('c:axId', space.ids.categoryAxis.toString());
    _value('c:axId', space.ids.valueAxis.toString());
    w.end();
  }

  /// The group's `c:dLbls`: all flags off when the labels are hidden, as in
  /// Excel's default charts; when they are visible, the format, a bare shape,
  /// the data label text, the position and `showVal 1`.
  ///
  /// The visible form is Excel's best known habit, not yet seen in an Excel
  /// file; the owner's reference workbook corrects it (ruling R7 of C1).
  void _writeGroupDataLabels() {
    final ChartDataLabels labels = chart.dataLabels;
    w.start('c:dLbls');
    if (labels.visible) {
      final String? formatCode = labels.formatCode;
      if (formatCode != null) {
        w.empty('c:numFmt', <String, String>{
          'formatCode': _scrub(formatCode),
          'sourceLinked': '0',
        });
      }
      _noFillShape();
      writeDrawingTextBody(
        w,
        theme.dataLabels,
        mode: mode,
        language: language,
        use: DrawingTextUse.dataLabel,
      );
      final String? position = switch (chart.kind) {
        ChartKind.line => 'r',
        ChartKind.area => null,
        _ => chart.grouping == ChartGrouping.clustered ? 'outEnd' : 'ctr',
      };
      if (position != null) {
        _value('c:dLblPos', position);
      }
    }
    _value('c:showLegendKey', '0');
    _value('c:showVal', labels.visible ? '1' : '0');
    _value('c:showCatName', '0');
    _value('c:showSerName', '0');
    _value('c:showPercent', '0');
    _value('c:showBubbleSize', '0');
    w.end();
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
    w.start('c:spPr');
    w.empty('a:noFill');
    _line(theme.axisLine, theme.spacing.axisLineWidth);
    w.empty('a:effectLst');
    w.end();
    _writeAxisLabels();
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
    _noFillShape();
    _writeAxisLabels();
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
  /// grid lines, the title, the number format and Excel's tick settings.
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
      _writeTitle(title, theme.axisLabels.copyWith(size: _axisTitleSize));
    }
    final String? formatCode = axis.formatCode;
    w.empty('c:numFmt', <String, String>{
      'formatCode': formatCode == null ? 'General' : _scrub(formatCode),
      'sourceLinked': formatCode == null ? '1' : '0',
    });
    _value('c:majorTickMark', 'none');
    _value('c:minorTickMark', 'none');
    _value('c:tickLblPos', 'nextTo');
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

  void _solidFill(ChartColor color) {
    w.start('a:solidFill');
    writeDrawingColor(w, color, mode);
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
