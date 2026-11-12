/// The pie and doughnut groups of a chart part, as Excel for Mac writes them.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `chart_writer.dart`, kept apart only to keep that file readable:
/// these are members of its writer, through a private extension.
///
/// The template is the owner's `chart_reference_j4.xlsx` (Excel for Mac
/// 16.114.4, `packages/jet_charts_core/docs/excel-checks.md`, "J4 values"):
/// a pie (chart 1), doughnuts of one and two series (charts 2 and 3) and a
/// pie with value labels (chart 7). A doughnut's data labels are not in it:
/// they are written as a pie's without the position, which `c:doughnutChart`
/// does not take for best fit (an estimate, not checked in Excel).
part of 'chart_writer.dart';

/// The width of a pie's leader lines Excel writes, in points (9525 EMU;
/// `chart_reference_j4.xlsx`, chart 7).
const double _pieLeaderLineWidth = 0.75;

extension _PieWriting on _ChartWriter {
  /// The `c:pieChart` or `c:doughnutChart`: colours varied by slice, the
  /// series, the group's labels, the first slice at 0 and a doughnut's hole
  /// size. No `c:axId`: a pie has no axes.
  void _writePieGroup() {
    final bool donut = chart.kind == ChartKind.donut;
    w.start(donut ? 'c:doughnutChart' : 'c:pieChart');
    _value('c:varyColors', '1');
    for (int i = 0; i < chart.series.length; i++) {
      _writePieSeries(chart.series[i], i);
    }
    // Excel's group labels repeat the shown labels' position and flags
    // (chart 7), and are off otherwise (chart 1); leader lines are on in
    // both.
    final ChartDataLabels labels = chart.dataLabels;
    w.start('c:dLbls');
    if (labels.visible) {
      _writePieLabelPosition();
      _writeLabelFlags(
        showValue: labels.showValue,
        showPercent: labels.showPercent,
      );
    } else {
      _writeLabelFlags(showValue: false);
    }
    _value('c:showLeaderLines', '1');
    w.end();
    _value('c:firstSliceAng', '0');
    if (donut) {
      // `Chart` keeps the hole within 10 and 90.
      _value('c:holeSize', chart.holeSizePercent.round().toString());
    }
    w.end();
  }

  /// A series of a pie or doughnut: its name, a `c:dPt` per slice, its
  /// labels, categories, values and id. Excel writes no `c:spPr` for the
  /// series itself: each slice has its own.
  void _writePieSeries(ChartSeries series, int index) {
    w.start('c:ser');
    _value('c:idx', index.toString());
    _value('c:order', index.toString());
    _writeSeriesName(series.name);
    final int pointColors = theme.pointColorCount(series);
    final int values = series.values.values.length;
    final int slices = values > pointColors ? values : pointColors;
    for (int i = 0; i < slices; i++) {
      _writeSlice(theme.pointColorOf(series, i) ?? theme.seriesColor(i), i);
    }
    if (chart.dataLabels.visible) {
      _writePieSeriesLabels();
    }
    _writeCategories(series.categories);
    _writeValues(series);
    _writeSeriesId(index);
    w.end();
  }

  /// The `c:dPt` of slice [index] in [color], outlined in the theme's
  /// background `sliceBorderWidth` wide (no line at 0).
  void _writeSlice(ChartColor color, int index) {
    w.start('c:dPt');
    _value('c:idx', index.toString());
    _value('c:bubble3D', '0');
    w.start('c:spPr');
    _solidFill(color);
    w.start('a:ln');
    if (theme.sliceBorderWidth == 0) {
      w.empty('a:noFill');
    } else {
      w.attribute(
        'w',
        (theme.sliceBorderWidth * _emuPerPoint).round().toString(),
      );
      w.start('a:solidFill');
      _writeSliceBorderColor(theme.background);
      w.end();
    }
    w.end();
    w.empty('a:effectLst');
    w.end();
    w.end();
  }

  /// [color] as a slice's outline: Excel names the first light slot `lt1`
  /// there (its chart style 251), where the chart's background is `bg1`.
  void _writeSliceBorderColor(ChartColor color) {
    if (mode == ChartExportColors.fileTheme &&
        color.slot == ChartSchemeColor.light1 &&
        color.lumMod == 1 &&
        color.lumOff == 0) {
      _value('a:schemeClr', 'lt1');
    } else {
      writeDrawingColor(w, color, mode);
    }
  }

  /// A pie's `c:dLblPos` of best fit; a doughnut takes none.
  void _writePieLabelPosition() {
    if (chart.kind == ChartKind.pie) {
      _value('c:dLblPos', 'bestFit');
    }
  }

  /// The series' `c:dLbls` of shown labels, as Excel writes a pie's (chart
  /// 7): the format when the labels have one, a bare shape, the data label
  /// text, the position, the flags, leader lines on in the theme's
  /// `leaderLine` colour, and Excel's empty `c15` extension.
  void _writePieSeriesLabels() {
    final ChartDataLabels labels = chart.dataLabels;
    w.start('c:dLbls');
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
    _writePieLabelPosition();
    _writeLabelFlags(
      showValue: labels.showValue,
      showPercent: labels.showPercent,
    );
    _value('c:showLeaderLines', '1');
    w.start('c:leaderLines');
    w.start('c:spPr');
    _line(theme.leaderLine, _pieLeaderLineWidth);
    w.empty('a:effectLst');
    w.end();
    w.end();
    w.start('c:extLst');
    w.start('c:ext');
    w.attribute('uri', _leaderLinesExtension);
    w.attribute('xmlns:c15', _c15Namespace);
    w.end();
    w.end();
    w.end();
  }
}
