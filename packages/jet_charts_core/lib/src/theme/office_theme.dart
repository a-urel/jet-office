/// Builds the Office theme of `ChartTheme.office`.
library;

import 'chart_color.dart';
import 'chart_theme.dart';

/// Builds the theme `ChartTheme.office` holds; its values are documented there.
ChartTheme buildOfficeTheme() {
  final ChartColor text = ChartColor.rgb(0x595959);
  ChartTextStyle style(double size) =>
      ChartTextStyle(fontFamily: 'Aptos Narrow', size: size, color: text);
  final ChartColor line = ChartColor.rgb(0xD9D9D9);
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
    dataLabels: style(9),
    gridLine: line,
    axisLine: line,
    background: ChartColor.rgb(0xFFFFFF),
    border: line,
    valueAxisLine: false,
    exportColors: ChartExportColors.fileTheme,
  );
}
