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
/// (`c:xVal/c:strRef`), and the owner's `chart_reference_e3.xlsx` (E3),
/// chart 2: numeric x values (`c:xVal/c:numRef`), whose x axis Excel gives
/// a linked `General` format (an x axis of text has none unless the
/// category axis has a format code). A scatter chart's data labels (written
/// as a line chart's without the leader line extension), its point colours
/// (as a line's markers) and axis lines in a theme without a
/// `scatterAxisLine` (drawn as any chart's) are estimates, not checked in
/// Excel.
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
    _writePointColors(series, color, ChartKind.scatter);
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

  /// Whether a series' x values are numbers or dates, not text: Excel
  /// then writes `c:xVal/c:numRef` and a linked format on the x axis.
  bool get _numericX => chart.series.any(
    (ChartSeries s) =>
        _SeriesWriting._categoryType(s.categories.values) != _CategoryType.text,
  );

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
    // A value axis' start, whose labels Excel keeps next to the axis though
    // a value is negative (chart 4).
    _writeAxisStart(
      axis,
      id,
      x ? 'b' : 'l',
      value: true,
      vertical: !x,
      // Excel gives an x axis of numbers a linked format and one of text
      // none (`chart_reference_e3.xlsx`, chart 2; `chart_reference_j4.xlsx`,
      // chart 4).
      numberFormat: !x || _numericX,
    );
    if (axis.visible) {
      final ChartColor? line = theme.scatterAxisLine;
      if (line != null) {
        _axisLineShape(line);
      } else if (x) {
        // As a category axis' line.
        _axisLineShape(theme.axisLine);
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
