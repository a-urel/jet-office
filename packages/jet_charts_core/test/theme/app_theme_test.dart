import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

int blend(int text, int background) =>
    ((text - background) * 0.15 + background).round();

ChartTheme dark({
  ChartColor? gridLine,
  double fontSize = 9,
  List<ChartColor>? palette,
}) {
  return ChartTheme.fromColors(
    palette:
        palette ??
        <ChartColor>[ChartColor.rgb(0x2563EB), ChartColor.rgb(0x16A34A)],
    fontFamily: 'DM Sans',
    text: ChartColor.rgb(0xE5E7EB),
    background: ChartColor.rgb(0x0B0F19),
    gridLine: gridLine,
    fontSize: fontSize,
  );
}

void main() {
  test('fromColors builds an app theme', () {
    final ChartTheme theme = dark();
    expect(theme.axisLabels.fontFamily, 'DM Sans');
    expect(theme.axisLabels.color.rgb, 0xE5E7EB);
    expect(theme.axisLabels.size, 9);
    expect(theme.legendText.size, 9);
    expect(theme.dataLabels.size, 9);
    expect(theme.dataLabels.fontFamily, 'DM Sans');
    expect(theme.titleText.size, 14);
    expect(theme.titleText.color.rgb, 0xE5E7EB);
    final int expected =
        (blend(0xE5, 0x0B) << 16) |
        (blend(0xE7, 0x0F) << 8) |
        blend(0xEB, 0x19);
    expect(theme.gridLine.rgb, expected);
    expect(theme.axisLine.rgb, expected);
    expect(theme.border, isNull);
    expect(theme.valueAxisLine, isFalse);
    expect(theme.background.rgb, 0x0B0F19);
    expect(theme.tooltip.background.rgb, 0x0B0F19);
    expect(theme.tooltip.border.rgb, expected);
    expect(theme.tooltip.text.fontFamily, 'DM Sans');
    expect(theme.tooltip.text.size, 10);
    expect(theme.tooltip.text.color.rgb, 0xE5E7EB);
    expect(theme.exportColors, ChartExportColors.fixed);
    expect(theme.seriesColor(0).rgb, 0x2563EB);
    expect(theme.lineWidth, ChartTheme.office.lineWidth);
    expect(theme.spacing, ChartTheme.office.spacing);
  });

  test('semantic colours are kept', () {
    final ChartTheme theme = ChartTheme.fromColors(
      palette: <ChartColor>[ChartColor.rgb(1)],
      fontFamily: 'X',
      text: ChartColor.rgb(0),
      background: ChartColor.rgb(0xFFFFFF),
      semantic: <String, ChartColor>{'income': ChartColor.rgb(0x00FF00)},
    );
    expect(theme.semantic['income']?.rgb, 0x00FF00);
  });

  test('an explicit grid line wins', () {
    final ChartTheme theme = dark(gridLine: ChartColor.rgb(0x123456));
    expect(theme.gridLine.rgb, 0x123456);
    expect(theme.axisLine.rgb, 0x123456);
    expect(theme.tooltip.border.rgb, 0x123456);
  });

  test('font size scales the title and the tooltip', () {
    final ChartTheme theme = dark(fontSize: 11);
    expect(theme.titleText.size, 11 * 14 / 9);
    expect(theme.axisLabels.size, 11);
    expect(theme.tooltip.text.size, 12);
  });

  test('bad arguments throw', () {
    expect(() => dark(palette: <ChartColor>[]), throwsArgumentError);
    for (final double bad in <double>[0, -1, double.nan, double.infinity]) {
      expect(() => dark(fontSize: bad), throwsArgumentError);
    }
  });
}
