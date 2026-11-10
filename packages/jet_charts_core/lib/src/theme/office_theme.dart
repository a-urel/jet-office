/// Builds the Office theme of `ChartTheme.office`.
library;

import 'chart_color.dart';
import 'chart_theme.dart';
import 'chart_tooltip_style.dart';

/// Builds the theme `ChartTheme.office` holds; its values are documented there.
ChartTheme buildOfficeTheme() {
  final ChartColor text = ChartColor.scheme(
    ChartSchemeColor.dark1,
    rgb: 0x595959,
    lumMod: 0.65,
    lumOff: 0.35,
  );
  ChartTextStyle style(double size) =>
      ChartTextStyle(fontFamily: 'Aptos Narrow', size: size, color: text);
  final ChartColor line = ChartColor.scheme(
    ChartSchemeColor.dark1,
    rgb: 0xD9D9D9,
    lumMod: 0.15,
    lumOff: 0.85,
  );
  return ChartTheme(
    palette: <ChartColor>[
      ChartColor.scheme(ChartSchemeColor.accent1, rgb: 0x156082),
      ChartColor.scheme(ChartSchemeColor.accent2, rgb: 0xE97132),
      ChartColor.scheme(ChartSchemeColor.accent3, rgb: 0x196B24),
      ChartColor.scheme(ChartSchemeColor.accent4, rgb: 0x0F9ED5),
      ChartColor.scheme(ChartSchemeColor.accent5, rgb: 0xA02B93),
      ChartColor.scheme(ChartSchemeColor.accent6, rgb: 0x4EA72E),
    ],
    axisLabels: style(9),
    titleText: style(14),
    legendText: style(9),
    dataLabels: ChartTextStyle(
      fontFamily: 'Aptos Narrow',
      size: 9,
      color: ChartColor.scheme(
        ChartSchemeColor.dark1,
        rgb: 0x404040,
        lumMod: 0.75,
        lumOff: 0.25,
      ),
    ),
    gridLine: line,
    axisLine: line,
    leaderLine: ChartColor.scheme(
      ChartSchemeColor.dark1,
      rgb: 0xA6A6A6,
      lumMod: 0.35,
      lumOff: 0.65,
    ),
    background: ChartColor.scheme(ChartSchemeColor.light1, rgb: 0xFFFFFF),
    border: line,
    valueAxisLine: false,
    tooltip: buildOfficeTooltipStyle(),
    exportColors: ChartExportColors.fileTheme,
    sliceBorderWidth: 1.5,
    combinationLineMarkers: false,
    combinationGapWidthPercent: 150,
    sliceLabelContrast: false,
    scatterAxisLine: ChartColor.scheme(
      ChartSchemeColor.dark1,
      rgb: 0xBFBFBF,
      lumMod: 0.25,
      lumOff: 0.75,
    ),
  );
}

/// The Office theme's tooltip look, also the default of `ChartTheme`'s
/// constructor; its values are documented on `ChartTheme.tooltip`.
ChartTooltipStyle buildOfficeTooltipStyle() => ChartTooltipStyle(
  background: ChartColor.rgb(0xFFFFFF),
  border: ChartColor.rgb(0xD9D9D9),
  text: ChartTextStyle(
    fontFamily: 'Aptos Narrow',
    size: 10,
    color: ChartColor.rgb(0x404040),
  ),
  padding: 6,
);
