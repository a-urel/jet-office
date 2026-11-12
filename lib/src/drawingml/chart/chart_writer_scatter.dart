/// The scatter group of a chart part and its two value axes, as Excel for
/// Mac writes them.
///
/// Not ported from Quds; written for jet_office.
///
/// A part of `chart_writer.dart`, kept apart only to keep that file readable:
/// these are members of its writer, through a private extension.
///
/// The template is the owner's `chart_reference_j4.xlsx` (Excel for Mac
/// 16.114.4, `packages/jet_charts_core/docs/excel-checks.md`, "J4 values"),
/// chart 4: Excel's scatter chart of markers only, whose x values were text
/// (`c:xVal/c:strRef`). Numeric x values (`c:xVal/c:numRef`, as the gallery
/// workbook writes them) are an estimate, not checked in Excel: E3 decides.
/// So are a scatter chart's data labels (written as a line chart's without
/// the leader line extension), its point colours (as a line's markers), an x
/// axis' number format (written only when the category axis has one) and
/// axis lines in a theme without a `scatterAxisLine` (drawn as any chart's).
part of 'chart_writer.dart';

/// The width of a scatter series' line Excel writes, though it has no fill,
/// in EMU (3 pt; `chart_reference_j4.xlsx`, chart 4).
const String _scatterLineWidth = '38100';

extension _ScatterWriting on _ChartWriter {
  /// The `c:scatterChart`: Excel's `lineMarker` style without varied
  /// colours, the series, the group's labels (every flag off) and the two
  /// axis ids.
  void _writeScatterGroup() {
    w.start('c:scatterChart');
    _value('c:scatterStyle', 'lineMarker');
    _value('c:varyColors', '0');
    for (int i = 0; i < chart.series.length; i++) {
      _writeScatterSeries(chart.series[i], i);
    }
    _writeGroupDataLabels();
    _value('c:axId', space.ids.categoryAxis.toString());
    _value('c:axId', space.ids.valueAxis.toString());
    w.end();
  }

  /// A scatter series: its name, a line without fill, a circle marker in its
  /// colour, its point colours and labels, its categories as x values, its
  /// values as y values, `c:smooth 0` and its id.
  void _writeScatterSeries(ChartSeries series, int index) {
    w.start('c:ser');
    _value('c:idx', index.toString());
    _value('c:order', index.toString());
    _writeSeriesName(series.name);
    final ChartColor color = theme.colorOf(series, index);
    w.start('c:spPr');
    _scatterSeriesLine();
    w.empty('a:effectLst');
    w.end();
    w.start('c:marker');
    _value('c:symbol', 'circle');
    _value('c:size', theme.markerSize.clamp(2, 72).round().toString());
    _markerShape(color);
    w.end();
    _writePointColors(series, color);
    if (chart.dataLabels.visible) {
      // A line's labels without Excel's leader lines: the Open XML SDK
      // refuses their `c15` extension, and `tool/ooxml_validate` ignores
      // that only in a bar, line or area group.
      _writeSeriesDataLabels(leaderLines: false);
    }
    _writeCategories(series.categories, name: 'c:xVal');
    _writeValues(series, name: 'c:yVal');
    // Excel writes `c:smooth 0` in a scatter chart of markers only; the
    // series' smoothing draws nothing there.
    _value('c:smooth', '0');
    _writeSeriesId(index);
    w.end();
  }

  /// A scatter series' `a:ln`: 3 pt, a round cap, no fill and a round join.
  void _scatterSeriesLine() {
    w.start('a:ln');
    w.attribute('w', _scatterLineWidth);
    w.attribute('cap', 'rnd');
    w.empty('a:noFill');
    w.empty('a:round');
    w.end();
  }

  /// The `c:valAx` of the x values ([x], at the bottom, of the category axis'
  /// options and the ids' `categoryAxis`) or of the y values (at the left, of
  /// the value axis' options and `valueAxis`): the scaling, grid lines, the
  /// title, a number format (the x axis' only when the category axis has
  /// one), no tick marks, labels next to the axis, the axis line, crossing
  /// the other axis at zero, `midCat`, and the major unit.
  void _writeScatterAxis({required bool x}) {
    final ChartAxis axis = x ? chart.categoryAxis : chart.valueAxis;
    final int id = x ? space.ids.categoryAxis : space.ids.valueAxis;
    final int crossId = x ? space.ids.valueAxis : space.ids.categoryAxis;
    w.start('c:valAx');
    _value('c:axId', id.toString());
    w.start('c:scaling');
    _value('c:orientation', 'minMax');
    final double? max = axis.max;
    final double? min = axis.min;
    if (max != null) {
      _writeNumberValue('c:max', max);
    }
    if (min != null) {
      _writeNumberValue('c:min', min);
    }
    w.end();
    _value('c:delete', axis.visible ? '0' : '1');
    _value('c:axPos', x ? 'b' : 'l');
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
        vertical: !x,
      );
    }
    final String? formatCode = axis.formatCode;
    if (formatCode != null || !x) {
      w.empty('c:numFmt', <String, String>{
        'formatCode': formatCode != null ? _scrub(formatCode) : 'General',
        'sourceLinked': formatCode == null ? '1' : '0',
      });
    }
    _value('c:majorTickMark', 'none');
    _value('c:minorTickMark', 'none');
    // Excel keeps the labels next to the axis though a value is negative
    // (chart 4).
    _value('c:tickLblPos', 'nextTo');
    if (axis.visible) {
      final ChartColor? line = theme.scatterAxisLine;
      if (line != null) {
        w.start('c:spPr');
        w.empty('a:noFill');
        _line(line, theme.spacing.axisLineWidth);
        w.empty('a:effectLst');
        w.end();
      } else if (x) {
        // As a category axis' line.
        w.start('c:spPr');
        w.empty('a:noFill');
        _line(theme.axisLine, theme.spacing.axisLineWidth);
        w.empty('a:effectLst');
        w.end();
      } else {
        // As a value axis', which has none.
        _noFillShape();
      }
      _writeAxisLabels();
    }
    _value('c:crossAx', crossId.toString());
    _value('c:crosses', 'autoZero');
    _value('c:crossBetween', 'midCat');
    final double? majorUnit = axis.majorUnit;
    if (majorUnit != null) {
      _writeNumberValue('c:majorUnit', majorUnit);
    }
    w.end();
  }
}
