/// The look of a chart: colours, fonts, lines and spacing.
library;

import 'dart:math' as math;

import '../model/chart_series.dart';
import '../model/equality.dart';
import 'chart_color.dart';
import 'chart_spacing.dart';
import 'chart_tooltip_style.dart';
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
  /// point with no neighbour to join gets a marker, so it still shows.
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
  /// The first pass through [palette] gives its colours unchanged, scheme
  /// slots included. The second pass (series 7 to 12 of a six-colour palette)
  /// is Office's "lighter 40%" of each colour, as the owner's check of Excel
  /// shows: a scheme-bound colour keeps its slot with `lumMod` 0.6 and `lumOff`
  /// 0.4, so it exports as a scheme colour, and any other colour is the fixed
  /// colour whose channels are `round(v * 0.6 + 255 * 0.4)`. Accent 1
  /// (`156082`) gives `73A0B4`, accent 2 (`E97132`) `F2AA84`. A later pass `p`
  /// (`index ~/ palette.length`) gives each colour of the palette, as a fixed
  /// colour, derived by a rule that is this library's own and unconfirmed: for
  /// `p` of 2 or more, an odd `p` multiplies each channel by
  /// `0.6^((p + 1) / 2)` and an even `p` moves each channel toward 255 by
  /// `1 - 0.6^(p / 2)`, with the passes 1 and 2 of that rule swapped (pass 2
  /// is the darker 0.6, as pass 1 is the lighter). No repeat within the first
  /// 24 series is checked for the office theme and for the five-colour palette
  /// of the tests. Other palettes, greys, and palettes with black or white can
  /// repeat derived colours, as scaling black or moving white toward 255
  /// changes nothing. Any index is valid.
  ///
  /// Throws a [RangeError] when [index] is negative.
  ChartColor seriesColor(int index) {
    RangeError.checkNotNegative(index, 'index');
    final int pass = index ~/ palette.length;
    final ChartColor base = palette[index % palette.length];
    if (pass == 0) {
      return base;
    }
    if (pass == 1) {
      int lighter(int shift) {
        final int value = (base.rgb >> shift) & 0xFF;
        return (value * 0.6 + 255 * 0.4).round().clamp(0, 255);
      }

      final int rgb = lighter(16) << 16 | lighter(8) << 8 | lighter(0);
      final ChartSchemeColor? slot = base.slot;
      return slot == null
          ? ChartColor.rgb(rgb)
          : ChartColor.scheme(slot, rgb: rgb, lumMod: 0.6, lumOff: 0.4);
    }
    final int rule = pass == 2 ? 1 : pass;
    final bool odd = rule.isOdd;
    final double factor =
        math.pow(0.6, odd ? (rule + 1) ~/ 2 : rule ~/ 2) as double;
    int channel(int shift) {
      final int value = (base.rgb >> shift) & 0xFF;
      final double derived = odd
          ? value * factor
          : value + (255 - value) * (1 - factor);
      return derived.round().clamp(0, 255);
    }

    return ChartColor.rgb(channel(16) << 16 | channel(8) << 8 | channel(0));
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
