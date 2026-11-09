/// The look of a chart: colours, fonts, lines and spacing.
library;

import 'dart:math' as math;

import '../model/chart_series.dart';
import '../model/equality.dart';
import 'chart_color.dart';
import 'chart_spacing.dart';
import 'office_theme.dart';

/// The look of a chart, one object that travels to every output so a chart
/// looks the same on screen, in a PDF and in a file.
final class ChartTheme {
  /// Creates a theme.
  ///
  /// [palette] and [semantic] are copied and unmodifiable. [spacing] defaults
  /// to the Office theme's `ChartSpacing()`. Throws an [ArgumentError] when
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
    this.gapWidthPercent = 219,
    this.lineWidth = 2.25,
    this.markerSize = 5,
    ChartSpacing? spacing,
    this.exportColors = ChartExportColors.fixed,
  }) : palette = List<ChartColor>.unmodifiable(palette),
       semantic = Map<String, ChartColor>.unmodifiable(semantic),
       spacing = spacing ?? ChartSpacing() {
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
  /// colour `D9D9D9` (`tx1`, 0.15 and 0.85), the background `FFFFFF` (`bg1`),
  /// each bound to the file theme,
  /// [gapWidthPercent] 219, [lineWidth] 2.25, [markerSize] 5, and of
  /// [spacing] the line widths, the overlap and the tick length. Still
  /// unconfirmed: 9 pt for the legend and data labels, and the other gaps of
  /// [spacing].
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

  /// The gaps, symbol sizes and line widths of the layout.
  final ChartSpacing spacing;

  /// How the theme's colours are exported to a file.
  final ChartExportColors exportColors;

  /// The colour of the series at [index], counting from 0.
  ///
  /// The first pass through [palette] gives its colours unchanged, scheme
  /// slots included. A later pass `p` (`index ~/ palette.length`) gives each
  /// colour of the palette, as a fixed colour, derived by a fixed rule: an odd
  /// `p` multiplies each channel by `0.6^((p + 1) / 2)`, an even `p` moves
  /// each channel toward 255 by `1 - 0.6^(p / 2)`. No repeat within the
  /// first 24 series is checked for the office theme and for the five-colour
  /// palette of the tests. Other palettes, greys, and palettes with black or
  /// white can repeat derived colours, as scaling black or moving white toward
  /// 255 changes nothing. Any index is valid.
  ///
  /// This is this library's own rule. Excel's real rule for series 7 and up is
  /// checked in the oracle gallery later and this rule follows it then.
  ///
  /// Throws a [RangeError] when [index] is negative.
  ChartColor seriesColor(int index) {
    RangeError.checkNotNegative(index, 'index');
    final int pass = index ~/ palette.length;
    final ChartColor base = palette[index % palette.length];
    if (pass == 0) {
      return base;
    }
    final bool odd = pass.isOdd;
    final double factor =
        math.pow(0.6, odd ? (pass + 1) ~/ 2 : pass ~/ 2) as double;
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
    double? gapWidthPercent,
    double? lineWidth,
    double? markerSize,
    ChartSpacing? spacing,
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
      gapWidthPercent: gapWidthPercent ?? this.gapWidthPercent,
      lineWidth: lineWidth ?? this.lineWidth,
      markerSize: markerSize ?? this.markerSize,
      spacing: spacing ?? this.spacing,
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
        gapWidthPercent == other.gapWidthPercent &&
        lineWidth == other.lineWidth &&
        markerSize == other.markerSize &&
        spacing == other.spacing &&
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
    gapWidthPercent,
    lineWidth,
    markerSize,
    spacing,
    exportColors,
  );

  @override
  String toString() => 'ChartTheme(${palette.length} colours, $exportColors)';
}
