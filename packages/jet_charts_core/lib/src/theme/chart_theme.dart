/// The look of a chart: colours, fonts, lines and spacing.
library;

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
  /// to the Office theme's `ChartSpacing()` and [tooltip] to the Office
  /// theme's tooltip look. Throws an [ArgumentError] when
  /// [palette] is empty.
  ChartTheme({
    required List<ChartColor> palette,
    Map<String, ChartColor> semantic = const <String, ChartColor>{},
    required this.axisLabels,
    required this.titleText,
    required this.legendText,
    required this.dataLabels,
    required this.gridLine,
    required this.axisLine,
    required this.background,
    this.border,
    this.borderWidth = 0.75,
    this.valueAxisLine = true,
    this.gapWidthPercent = 219,
    this.lineWidth = 2.25,
    this.markerSize = 5,
    this.lineMarkers = true,
    ChartSpacing? spacing,
    ChartTooltipStyle? tooltip,
    this.exportColors = ChartExportColors.fixed,
  }) : palette = List<ChartColor>.unmodifiable(palette),
       semantic = Map<String, ChartColor>.unmodifiable(semantic),
       spacing = spacing ?? ChartSpacing(),
       tooltip = tooltip ?? buildOfficeTooltipStyle() {
    if (palette.isEmpty) {
      throw ArgumentError.value(palette, 'palette', 'must not be empty');
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
  /// the overlap and the tick length. Still unconfirmed: 9 pt for the legend
  /// and data labels, and the other gaps of [spacing].
  ///
  /// Its [tooltip] is this library's own look, not an Excel value.
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

  /// The gap between the bars or columns of a category, as a percentage of a
  /// bar's width. Excel's default, 219, is verified; see
  /// `docs/excel-checks.md`.
  final double gapWidthPercent;

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
    ChartColor? background,
    ChartColor? border,
    double? borderWidth,
    bool? valueAxisLine,
    double? gapWidthPercent,
    double? lineWidth,
    double? markerSize,
    bool? lineMarkers,
    ChartSpacing? spacing,
    ChartTooltipStyle? tooltip,
    ChartExportColors? exportColors,
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
      background: background ?? this.background,
      border: border ?? this.border,
      borderWidth: borderWidth ?? this.borderWidth,
      valueAxisLine: valueAxisLine ?? this.valueAxisLine,
      gapWidthPercent: gapWidthPercent ?? this.gapWidthPercent,
      lineWidth: lineWidth ?? this.lineWidth,
      markerSize: markerSize ?? this.markerSize,
      lineMarkers: lineMarkers ?? this.lineMarkers,
      spacing: spacing ?? this.spacing,
      tooltip: tooltip ?? this.tooltip,
      exportColors: exportColors ?? this.exportColors,
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
        background == other.background &&
        border == other.border &&
        borderWidth == other.borderWidth &&
        valueAxisLine == other.valueAxisLine &&
        gapWidthPercent == other.gapWidthPercent &&
        lineWidth == other.lineWidth &&
        markerSize == other.markerSize &&
        lineMarkers == other.lineMarkers &&
        spacing == other.spacing &&
        tooltip == other.tooltip &&
        exportColors == other.exportColors;
  }

  @override
  int get hashCode => Object.hash(
    listValueHash(palette),
    mapValueHash(semantic),
    axisLabels,
    titleText,
    legendText,
    dataLabels,
    gridLine,
    axisLine,
    background,
    border,
    borderWidth,
    valueAxisLine,
    gapWidthPercent,
    lineWidth,
    markerSize,
    lineMarkers,
    spacing,
    tooltip,
    exportColors,
  );

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
