/// The look of a chart: colours, fonts, lines and spacing.
library;

import '../model/chart_kind.dart';
import '../model/chart_series.dart';
import '../model/equality.dart';
import 'chart_color.dart';
import 'chart_spacing.dart';
import 'chart_tooltip_style.dart';
import 'luminance.dart';
import 'office_theme.dart';

/// The look of a chart, one object that travels to every output so a chart
/// looks the same on screen, in a PDF and in a file.
final class ChartTheme {
  /// Creates a theme.
  ///
  /// [palette] and [semantic] are copied and unmodifiable. [spacing] defaults
  /// to the Office theme's `ChartSpacing()`, [tooltip] to the Office theme's
  /// tooltip look and [leaderLine] to [axisLine]. Throws an [ArgumentError]
  /// when [palette] is empty.
  ChartTheme({
    required List<ChartColor> palette,
    Map<String, ChartColor> semantic = const <String, ChartColor>{},
    required this.axisLabels,
    required this.titleText,
    required this.legendText,
    required this.dataLabels,
    required this.gridLine,
    required this.axisLine,
    ChartColor? leaderLine,
    required this.background,
    this.border,
    this.borderWidth = 0.75,
    this.valueAxisLine = true,
    this.gapWidthPercent = 219,
    this.stackedGapWidthPercent = 150,
    this.barGapWidthPercent = 182,
    this.lineWidth = 2.25,
    this.markerSize = 5,
    this.lineMarkers = true,
    ChartSpacing? spacing,
    ChartTooltipStyle? tooltip,
    this.exportColors = ChartExportColors.fixed,
    this.areaOpacity = 1,
    this.areaLine = false,
    this.sliceBorderWidth = 1.5,
    this.centerText,
    this.sparklineWidth = 0.75,
    this.combinationLineMarkers = false,
    this.combinationGapWidthPercent = 150,
    this.scatterAxisLine,
    this.sliceLabelContrast = true,
  }) : palette = List<ChartColor>.unmodifiable(palette),
       semantic = Map<String, ChartColor>.unmodifiable(semantic),
       leaderLine = leaderLine ?? axisLine,
       spacing = spacing ?? ChartSpacing(),
       tooltip = tooltip ?? buildOfficeTooltipStyle() {
    if (palette.isEmpty) {
      throw ArgumentError.value(palette, 'palette', 'must not be empty');
    }
    if (!(areaOpacity > 0 && areaOpacity <= 1)) {
      throw ArgumentError.value(
        areaOpacity,
        'areaOpacity',
        'must be above 0 and at most 1',
      );
    }
    _checkWidth(sliceBorderWidth, 'sliceBorderWidth');
    _checkWidth(sparklineWidth, 'sparklineWidth');
  }

  /// An app's theme in one call, from its own colours and font.
  ///
  /// [palette] is the series colours and [semantic] the named ones. Axis
  /// labels, legend and data labels are [fontSize] points (9 by default) in
  /// [fontFamily] and [text]; the title is `fontSize * 14 / 9`, 14 pt for the
  /// default. [gridLine] defaults to [text] blended 15 % over [background]
  /// (per channel, rounded), and is also the axis line colour and the
  /// tooltip's border, and the leader line colour. The tooltip's background is [background] and its text
  /// is [fontFamily] at `fontSize + 1` in [text]. There is no [border] and no
  /// [valueAxisLine] and no [scatterAxisLine], and [exportColors] is
  /// [ChartExportColors.fixed]. Every other value is the Office theme's. Dark mode is the same call with dark
  /// colours.
  ///
  /// Throws an [ArgumentError] when [palette] is empty or [fontSize] is not
  /// finite and positive.
  static ChartTheme fromColors({
    required List<ChartColor> palette,
    required String fontFamily,
    required ChartColor text,
    required ChartColor background,
    ChartColor? gridLine,
    Map<String, ChartColor> semantic = const <String, ChartColor>{},
    double fontSize = 9,
  }) {
    if (!fontSize.isFinite || fontSize <= 0) {
      throw ArgumentError.value(
        fontSize,
        'fontSize',
        'must be finite and positive',
      );
    }
    ChartTextStyle style(double size) =>
        ChartTextStyle(fontFamily: fontFamily, size: size, color: text);
    final ChartColor grid =
        gridLine ?? blendChartColors(text, background, 0.15);
    return ChartTheme(
      palette: palette,
      semantic: semantic,
      axisLabels: style(fontSize),
      titleText: style(fontSize * 14 / 9),
      legendText: style(fontSize),
      dataLabels: style(fontSize),
      gridLine: grid,
      axisLine: grid,
      background: background,
      valueAxisLine: false,
      tooltip: ChartTooltipStyle(
        background: background,
        border: grid,
        text: style(fontSize + 1),
        padding: office.tooltip.padding,
      ),
      exportColors: ChartExportColors.fixed,
    );
  }

  static void _checkWidth(double value, String name) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(value, name, 'must be finite, not negative');
    }
  }

  /// A theme matching Excel's defaults, bound to the file's theme.
  ///
  /// The six accents are `scheme` colours of `accent1` to `accent6`, with the
  /// values of `Office Theme.thmx` of Excel for Mac 16.114.4, verified on
  /// 2026-11-06 (dark 1 `000000`, light 1 `FFFFFF`, dark 2 `0E2841`, light 2
  /// `E8E8E8`). Its [exportColors] is [ChartExportColors.fileTheme].
  ///
  /// Verified on Excel's default column and line charts
  /// (`chart_defaults.xlsx`, 2026-11-08; `docs/excel-checks.md` gives each
  /// value's source): the font family `Aptos Narrow` (the theme's minor
  /// font), 9 pt axis labels and a 14 pt title, the text colour `595959`
  /// (`tx1` with `lumMod` 0.65 and `lumOff` 0.35), the grid and axis line
  /// colour `D9D9D9` (`tx1`, 0.15 and 0.85), a 0.75 pt [border] of the same
  /// colour, no [valueAxisLine] and the background `FFFFFF` (`bg1`), each
  /// colour bound to the file theme; also [gapWidthPercent] 219, [lineWidth]
  /// 2.25, [markerSize] 5, [lineMarkers] on, and of [spacing] the line widths,
  /// the overlap and the tick length. The owner's `chart_reference.xlsx`
  /// (2026-11-09) verifies [stackedGapWidthPercent] 150, [barGapWidthPercent]
  /// 182 and the spacing's `barOverlapPercent` 0, 9 pt legend and data label
  /// text, and the data label colour `404040` (`tx1` with `lumMod` 0.75 and
  /// `lumOff` 0.25). Still unconfirmed: the other gaps of [spacing].
  ///
  /// Its [tooltip] is this library's own look, not an Excel value.
  ///
  /// The J4 values are [areaOpacity] 1, [areaLine] off, [centerText] null
  /// and [sparklineWidth] 0.75 (an estimate, not checked in Excel). The
  /// owner's E1 file (`chart_reference_j4.xlsx`, Excel for Mac 16.114.4,
  /// 2026-11-10) verifies [sliceBorderWidth] 1.5 in the [background] (`lt1`),
  /// the [leaderLine] `A6A6A6` (`tx1` with `lumMod` 0.35 and `lumOff` 0.65),
  /// a combination's lines without markers ([combinationLineMarkers] off)
  /// and its columns' gap of 150 with no overlap
  /// ([combinationGapWidthPercent]), a scatter chart's two axis lines in
  /// `BFBFBF` ([scatterAxisLine], `tx1` with `lumMod` 0.25 and `lumOff`
  /// 0.75), and pie labels in the data label colour on every slice
  /// ([sliceLabelContrast] off).
  static final ChartTheme office = buildOfficeTheme();

  /// The series colours, in order. Never empty.
  final List<ChartColor> palette;

  /// Named colours with a meaning in an app, such as `income` or `expense`.
  final Map<String, ChartColor> semantic;

  /// The text of the axes' tick labels.
  final ChartTextStyle axisLabels;

  /// The text of the title.
  final ChartTextStyle titleText;

  /// The text of the legend.
  final ChartTextStyle legendText;

  /// The text of data labels.
  final ChartTextStyle dataLabels;

  /// The colour of grid lines.
  final ChartColor gridLine;

  /// The colour of axis lines.
  final ChartColor axisLine;

  /// The colour of a pie label's leader line, drawn the spacing's
  /// `axisLineWidth` wide. A theme that names none takes [axisLine]; the
  /// Office theme's is Excel's `A6A6A6` (`tx1` with `lumMod` 0.35 and
  /// `lumOff` 0.65), verified by E1 (chart 7).
  final ChartColor leaderLine;

  /// The colour behind the chart.
  final ChartColor background;

  /// The colour of the chart area's border, or null for none.
  ///
  /// The border is drawn inside the chart's size. The Office theme has the
  /// colour of Excel's default, `D9D9D9`; see `docs/excel-checks.md`.
  ///
  /// To drop the Office border, use `ChartTheme.office.copyWith(borderWidth:
  /// 0)`, as [copyWith] cannot set this field to `null`, or build a theme
  /// whose [border] is `null` (the constructor's default).
  final ChartColor? border;

  /// The width of the border, in points. Excel's default, 0.75, is verified;
  /// it is drawn only when [border] is set.
  final double borderWidth;

  /// Whether the value axis has a line. Excel's default chart has none, so
  /// the Office theme does not; other themes draw one unless they say not to.
  final bool valueAxisLine;

  /// The gap between the columns of two categories in a clustered column
  /// chart, as a percentage of a bar's width. Excel's default, 219, is
  /// verified; see `docs/excel-checks.md`. [gapWidthPercentOf] gives the gap
  /// of each kind and grouping.
  final double gapWidthPercent;

  /// The gap of a stacked or percent stacked column or bar chart, as
  /// [gapWidthPercent] is for clustered columns. Excel's default, 150, is
  /// verified (`chart_reference.xlsx`).
  final double stackedGapWidthPercent;

  /// The gap of a clustered bar chart (bars along the horizontal axis), as
  /// [gapWidthPercent] is for clustered columns. Excel's default, 182, is
  /// verified (`chart_reference.xlsx`).
  final double barGapWidthPercent;

  /// The width of a line series, in points. Excel's default, 2.25, is
  /// verified; see `docs/excel-checks.md`.
  final double lineWidth;

  /// The size of a marker, in points. Excel's default, 5, is verified; see
  /// `docs/excel-checks.md`.
  final double markerSize;

  /// Whether every point of a line series has a marker, a filled circle of
  /// [markerSize] in the series' colour, also shown in the middle of the
  /// series' legend line.
  ///
  /// Excel's default line chart has one (`c:marker`, a circle of size 5, in
  /// `chart_defaults.xlsx`), so the default is `true`. When `false`, only a
  /// point with no neighbour to join gets a marker, so it still shows. When
  /// `true`, the layout still leaves out the markers of a line whose category
  /// step is under [markerSize] plus 2 pt, where they would touch, but those
  /// of a point with no neighbour (this library's choice; Excel's behaviour
  /// on dense lines was not checked, `docs/parity.md`).
  final bool lineMarkers;

  /// The gaps, symbol sizes and line widths of the layout.
  final ChartSpacing spacing;

  /// The look of the tooltip a backend shows.
  ///
  /// The Office theme's values are this library's own, not Excel's (Excel's
  /// hover box is a system tooltip, so it is not a parity item): a background
  /// of `FFFFFF`, a border of `D9D9D9`, Aptos Narrow 10 pt text of `404040`
  /// and a padding of 6. A theme that names no tooltip gets the same.
  final ChartTooltipStyle tooltip;

  /// How the theme's colours are exported to a file.
  final ChartExportColors exportColors;

  /// The opacity of an area's fill, above 0 and at most 1; 1 is opaque, as
  /// Excel's default area.
  final double areaOpacity;

  /// Whether an area also draws its top edge as a line of [lineWidth] in the
  /// series colour, a line over a light fill. Excel's area has none, so the
  /// Office theme does not.
  final bool areaLine;

  /// The width of the outline of each pie or donut slice, in points, drawn in
  /// [background]; 0 draws none. Excel's 1.5 in `lt1` (white), the default,
  /// is verified by E1 (`a:ln w="19050"` on every slice).
  final double sliceBorderWidth;

  /// The style of `Chart.centerText`, or null for [titleText]. Read
  /// [centerTextStyle] for the effective style.
  ///
  /// [copyWith] cannot set this field back to null.
  final ChartTextStyle? centerText;

  /// The width of a sparkline's line, in points. The Office theme's 0.75 is
  /// an estimate, not checked in Excel.
  final double sparklineWidth;

  /// Whether the line series of a combination chart mark every point, when
  /// [lineMarkers] is on too ([lineMarkersOf]).
  ///
  /// Excel's "Clustered Column - Line" draws its line without markers
  /// (`c:symbol none`, E1 chart 5), so the default is `false`. A plain line
  /// chart, with a secondary axis or not, keeps [lineMarkers] alone. A
  /// point with no neighbour keeps its marker either way, so it shows.
  final bool combinationLineMarkers;

  /// The gap of the clustered columns of a combination chart, as
  /// [gapWidthPercent] is for a clustered column chart; their overlap is 0.
  /// Excel's default, 150 with no `c:overlap`, is verified by E1 (chart 5).
  /// A stacked combination takes [stackedGapWidthPercent].
  final double combinationGapWidthPercent;

  /// The colour of a scatter chart's two axis lines, or null to draw them as
  /// any chart's (in [axisLine], the vertical one only with [valueAxisLine]).
  ///
  /// When set, a scatter chart draws both its axis lines in it, the vertical
  /// one even when [valueAxisLine] is off. Excel's default scatter chart has
  /// both, `BFBFBF` (`tx1` with `lumMod` 0.25 and `lumOff` 0.75), and grid
  /// lines on both axes (E1 chart 4); the vertical grid lines are the model's
  /// `Chart.categoryAxis.gridLines`. [copyWith] cannot set this field back
  /// to null.
  final ChartColor? scatterAxisLine;

  /// Whether a data label inside a pie or donut slice reads against the
  /// slice: the lighter or darker of [dataLabels]' colour and [background],
  /// whichever contrasts more with the fill, as a label inside a bar does.
  ///
  /// When `false`, a label inside a slice takes [dataLabels] as it is.
  /// Excel writes a pie's labels in its data label colour whatever the
  /// slice (`404040`, E1 chart 7), so the Office theme sets `false`; the
  /// default, `true`, keeps the readable rule for an app's themes (and
  /// [fromColors]). A label outside a pie takes [dataLabels] either way.
  final bool sliceLabelContrast;

  /// Whether the line series of a chart of [kind] mark every point:
  /// [lineMarkers], and in a combination chart [combinationLineMarkers] too.
  bool lineMarkersOf(ChartKind kind) =>
      lineMarkers && (kind != ChartKind.combination || combinationLineMarkers);

  /// The style of `Chart.centerText`: [centerText], else [titleText].
  ChartTextStyle get centerTextStyle => centerText ?? titleText;

  /// The gap width of a chart of [kind] and [grouping], as a percentage of a
  /// bar's width: [stackedGapWidthPercent] when it is stacked or percent
  /// stacked, [barGapWidthPercent] for a clustered bar chart,
  /// [combinationGapWidthPercent] for the columns of a clustered combination
  /// chart, and [gapWidthPercent] otherwise (a clustered column chart; other
  /// kinds have no bars).
  double gapWidthPercentOf(ChartKind kind, ChartGrouping grouping) {
    if (grouping != ChartGrouping.clustered) {
      return stackedGapWidthPercent;
    }
    return switch (kind) {
      ChartKind.bar => barGapWidthPercent,
      ChartKind.combination => combinationGapWidthPercent,
      _ => gapWidthPercent,
    };
  }

  /// The overlap of the bars of one category in a chart of [kind] and
  /// [grouping], as a percentage of a bar's width: 100 when it is stacked or
  /// percent stacked (the bars of a category are one stack), the spacing's
  /// `barOverlapPercent` for a clustered bar chart, 0 for the columns of a
  /// clustered combination chart (Excel's, E1 chart 5), and the spacing's
  /// `overlapPercent` otherwise.
  double overlapPercentOf(ChartKind kind, ChartGrouping grouping) {
    if (grouping != ChartGrouping.clustered) {
      return 100;
    }
    return switch (kind) {
      ChartKind.bar => spacing.barOverlapPercent,
      ChartKind.combination => 0,
      _ => spacing.overlapPercent,
    };
  }

  /// The colour of the series at [index], counting from 0.
  ///
  /// It is Excel's colour cycle, `xl/charts/colors1.xml` of the owner's
  /// `chart_defaults.xlsx` (`cs:colorStyle` of `meth="cycle"`, `id="10"`):
  /// the series takes the colour `index % palette.length` of [palette],
  /// varied by the pass `index ~/ palette.length` through it. Pass 0 gives
  /// the palette's colours unchanged; the passes 1 to 8 vary the colour's
  /// luminance, as DrawingML's `lumMod` and `lumOff`, by `lumMod` 0.6;
  /// `lumMod` 0.8 and `lumOff` 0.2; `lumMod` 0.8; `lumMod` 0.6 and `lumOff`
  /// 0.4; `lumMod` 0.5; `lumMod` 0.7 and `lumOff` 0.3; `lumMod` 0.7; and
  /// `lumMod` 0.5 and `lumOff` 0.5. The file lists these nine variations and
  /// says nothing of what comes after them, so pass 9 starts the cycle again
  /// (pass `p` varies as pass `p % 9`), as `colorStyle`'s `cycle` method
  /// suggests: the Office theme's series 55 has series 1's colour.
  ///
  /// A scheme-bound colour keeps its slot and carries the variation's
  /// `lumMod` and `lumOff`, so it exports as a scheme colour; its RGB value is
  /// the variation applied to the colour's own RGB value in hue, saturation
  /// and luminance (HSL). Accent 1 (`156082`) at `lumMod` 0.6 is `0D3A4E`,
  /// accent 2 (`E97132`) `994010`. A fixed colour gives the fixed colour of
  /// that RGB value. A scheme-bound colour that has a `lumMod` or `lumOff` of
  /// its own composes with the variation when the two can be one: when its
  /// `lumMod` plus `lumOff` is at most 1 (so its luminance is never clamped),
  /// the result carries `lumMod` `m1 * m2` and `lumOff` `o1 * m2 + o2`; else
  /// it is the fixed colour of the variation applied to its RGB value.
  ///
  /// A palette with black, white or greys can repeat a varied colour; the
  /// Office theme repeats none in its 54 series of a cycle. Any index is
  /// valid.
  ///
  /// Throws a [RangeError] when [index] is negative.
  ChartColor seriesColor(int index) {
    RangeError.checkNotNegative(index, 'index');
    final ChartColor base = palette[index % palette.length];
    final (double mod, double off) =
        _colorCycle[(index ~/ palette.length) % _colorCycle.length];
    if (mod == 1 && off == 0) {
      return base;
    }
    final int rgb = applyLuminance(base.rgb, mod, off);
    final ChartSchemeColor? slot = base.slot;
    if (slot == null) {
      return ChartColor.rgb(rgb);
    }
    if (base.lumMod == 1 && base.lumOff == 0) {
      return ChartColor.scheme(slot, rgb: rgb, lumMod: mod, lumOff: off);
    }
    if (base.lumMod + base.lumOff <= 1) {
      return ChartColor.scheme(
        slot,
        rgb: rgb,
        lumMod: base.lumMod * mod,
        lumOff: base.lumOff * mod + off,
      );
    }
    return ChartColor.rgb(rgb);
  }

  /// The colour of [series], which is the series at [index].
  ///
  /// It is the series' own [ChartSeries.color], else the [semantic] colour
  /// named by its [ChartSeries.colorKey], else [seriesColor] of [index]. A key
  /// [semantic] does not hold falls to the palette. Throws a [RangeError] when
  /// [index] is negative and the series has neither colour nor known key.
  ChartColor colorOf(ChartSeries series, int index) {
    return series.color ?? semantic[series.colorKey] ?? seriesColor(index);
  }

  /// The colour of point [index] of [series], or `null` when it is
  /// automatic.
  ///
  /// It is the series' [ChartSeries.pointColors] entry, else the [semantic]
  /// colour named by its [ChartSeries.pointColorKeys] entry. A key
  /// [semantic] does not hold, a negative index and one past both lists are
  /// `null`.
  ChartColor? pointColorOf(ChartSeries series, int index) {
    if (index < 0) {
      return null;
    }
    final List<ChartColor?> colors = series.pointColors;
    final List<String?> keys = series.pointColorKeys;
    return (index < colors.length ? colors[index] : null) ??
        (index < keys.length ? semantic[keys[index]] : null);
  }

  /// How many points of [series] may have a colour of their own
  /// ([pointColorOf]): the longer of its point colours and point colour
  /// keys.
  int pointColorCount(ChartSeries series) =>
      series.pointColors.length > series.pointColorKeys.length
      ? series.pointColors.length
      : series.pointColorKeys.length;

  /// A copy with the given fields replaced.
  ///
  /// A field cannot be set to `null` this way: passing `null` keeps the
  /// current value.
  ChartTheme copyWith({
    List<ChartColor>? palette,
    Map<String, ChartColor>? semantic,
    ChartTextStyle? axisLabels,
    ChartTextStyle? titleText,
    ChartTextStyle? legendText,
    ChartTextStyle? dataLabels,
    ChartColor? gridLine,
    ChartColor? axisLine,
    ChartColor? leaderLine,
    ChartColor? background,
    ChartColor? border,
    double? borderWidth,
    bool? valueAxisLine,
    double? gapWidthPercent,
    double? stackedGapWidthPercent,
    double? barGapWidthPercent,
    double? lineWidth,
    double? markerSize,
    bool? lineMarkers,
    ChartSpacing? spacing,
    ChartTooltipStyle? tooltip,
    ChartExportColors? exportColors,
    double? areaOpacity,
    bool? areaLine,
    double? sliceBorderWidth,
    ChartTextStyle? centerText,
    double? sparklineWidth,
    bool? combinationLineMarkers,
    double? combinationGapWidthPercent,
    ChartColor? scatterAxisLine,
    bool? sliceLabelContrast,
  }) {
    return ChartTheme(
      palette: palette ?? this.palette,
      semantic: semantic ?? this.semantic,
      axisLabels: axisLabels ?? this.axisLabels,
      titleText: titleText ?? this.titleText,
      legendText: legendText ?? this.legendText,
      dataLabels: dataLabels ?? this.dataLabels,
      gridLine: gridLine ?? this.gridLine,
      axisLine: axisLine ?? this.axisLine,
      leaderLine: leaderLine ?? this.leaderLine,
      background: background ?? this.background,
      border: border ?? this.border,
      borderWidth: borderWidth ?? this.borderWidth,
      valueAxisLine: valueAxisLine ?? this.valueAxisLine,
      gapWidthPercent: gapWidthPercent ?? this.gapWidthPercent,
      stackedGapWidthPercent:
          stackedGapWidthPercent ?? this.stackedGapWidthPercent,
      barGapWidthPercent: barGapWidthPercent ?? this.barGapWidthPercent,
      lineWidth: lineWidth ?? this.lineWidth,
      markerSize: markerSize ?? this.markerSize,
      lineMarkers: lineMarkers ?? this.lineMarkers,
      spacing: spacing ?? this.spacing,
      tooltip: tooltip ?? this.tooltip,
      exportColors: exportColors ?? this.exportColors,
      areaOpacity: areaOpacity ?? this.areaOpacity,
      areaLine: areaLine ?? this.areaLine,
      sliceBorderWidth: sliceBorderWidth ?? this.sliceBorderWidth,
      centerText: centerText ?? this.centerText,
      sparklineWidth: sparklineWidth ?? this.sparklineWidth,
      combinationLineMarkers:
          combinationLineMarkers ?? this.combinationLineMarkers,
      combinationGapWidthPercent:
          combinationGapWidthPercent ?? this.combinationGapWidthPercent,
      scatterAxisLine: scatterAxisLine ?? this.scatterAxisLine,
      sliceLabelContrast: sliceLabelContrast ?? this.sliceLabelContrast,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChartTheme &&
        listValueEquals(palette, other.palette) &&
        mapValueEquals(semantic, other.semantic) &&
        axisLabels == other.axisLabels &&
        titleText == other.titleText &&
        legendText == other.legendText &&
        dataLabels == other.dataLabels &&
        gridLine == other.gridLine &&
        axisLine == other.axisLine &&
        leaderLine == other.leaderLine &&
        background == other.background &&
        border == other.border &&
        borderWidth == other.borderWidth &&
        valueAxisLine == other.valueAxisLine &&
        gapWidthPercent == other.gapWidthPercent &&
        stackedGapWidthPercent == other.stackedGapWidthPercent &&
        barGapWidthPercent == other.barGapWidthPercent &&
        lineWidth == other.lineWidth &&
        markerSize == other.markerSize &&
        lineMarkers == other.lineMarkers &&
        spacing == other.spacing &&
        tooltip == other.tooltip &&
        exportColors == other.exportColors &&
        areaOpacity == other.areaOpacity &&
        areaLine == other.areaLine &&
        sliceBorderWidth == other.sliceBorderWidth &&
        centerText == other.centerText &&
        sparklineWidth == other.sparklineWidth &&
        combinationLineMarkers == other.combinationLineMarkers &&
        combinationGapWidthPercent == other.combinationGapWidthPercent &&
        scatterAxisLine == other.scatterAxisLine &&
        sliceLabelContrast == other.sliceLabelContrast;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    listValueHash(palette),
    mapValueHash(semantic),
    axisLabels,
    titleText,
    legendText,
    dataLabels,
    gridLine,
    axisLine,
    leaderLine,
    background,
    border,
    borderWidth,
    valueAxisLine,
    gapWidthPercent,
    stackedGapWidthPercent,
    barGapWidthPercent,
    lineWidth,
    markerSize,
    lineMarkers,
    spacing,
    tooltip,
    exportColors,
    areaOpacity,
    areaLine,
    sliceBorderWidth,
    centerText,
    sparklineWidth,
    combinationLineMarkers,
    combinationGapWidthPercent,
    scatterAxisLine,
    sliceLabelContrast,
  ]);

  @override
  String toString() => 'ChartTheme(${palette.length} colours, $exportColors)';
}

/// The variations of Excel's colour cycle as `lumMod` and `lumOff`, one per
/// pass through the palette: `xl/charts/colors1.xml` of the owner's
/// `chart_defaults.xlsx`.
const List<(double, double)> _colorCycle = <(double, double)>[
  (1, 0),
  (0.6, 0),
  (0.8, 0.2),
  (0.8, 0),
  (0.6, 0.4),
  (0.5, 0),
  (0.7, 0.3),
  (0.7, 0),
  (0.5, 0.5),
];
