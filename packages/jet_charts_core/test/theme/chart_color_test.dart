import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

void main() {
  test('luminance defaults are 1 and 0', () {
    final ChartColor fixed = ChartColor.rgb(0x112233);
    expect(fixed.lumMod, 1);
    expect(fixed.lumOff, 0);
    final ChartColor scheme = ChartColor.scheme(
      ChartSchemeColor.accent1,
      rgb: 0x156082,
    );
    expect(scheme.lumMod, 1);
    expect(scheme.lumOff, 0);
  });

  test('equality and hashCode include lumMod and lumOff', () {
    final ChartColor a = ChartColor.scheme(
      ChartSchemeColor.dark1,
      rgb: 0x595959,
      lumMod: 0.65,
      lumOff: 0.35,
    );
    final ChartColor same = ChartColor.scheme(
      ChartSchemeColor.dark1,
      rgb: 0x595959,
      lumMod: 0.65,
      lumOff: 0.35,
    );
    final ChartColor otherMod = ChartColor.scheme(
      ChartSchemeColor.dark1,
      rgb: 0x595959,
      lumMod: 0.5,
      lumOff: 0.35,
    );
    final ChartColor otherOff = ChartColor.scheme(
      ChartSchemeColor.dark1,
      rgb: 0x595959,
      lumMod: 0.65,
      lumOff: 0.3,
    );
    expect(a, same);
    expect(a.hashCode, same.hashCode);
    expect(a, isNot(otherMod));
    expect(a, isNot(otherOff));
  });

  test('toString shows lumMod and lumOff as percent when not 1 and 0', () {
    expect(
      ChartColor.scheme(
        ChartSchemeColor.dark1,
        rgb: 0x595959,
        lumMod: 0.65,
        lumOff: 0.35,
      ).toString(),
      'ChartColor(595959, dark1 65/35)',
    );
    expect(
      ChartColor.scheme(ChartSchemeColor.accent1, rgb: 0x156082).toString(),
      'ChartColor(156082, accent1)',
    );
  });

  test('lumMod and lumOff outside 0 to 1 or not finite throw', () {
    for (final double bad in <double>[-0.1, 1.1, double.nan, double.infinity]) {
      expect(
        () => ChartColor.scheme(ChartSchemeColor.dark1, rgb: 0, lumMod: bad),
        throwsArgumentError,
        reason: 'lumMod $bad',
      );
      expect(
        () => ChartColor.scheme(ChartSchemeColor.dark1, rgb: 0, lumOff: bad),
        throwsArgumentError,
        reason: 'lumOff $bad',
      );
    }
  });

  test('the Office theme binds text, lines and background to the theme', () {
    final ChartTheme office = ChartTheme.office;
    final ChartColor text = office.axisLabels.color;
    expect(text.slot, ChartSchemeColor.dark1);
    expect(text.rgb, 0x595959);
    expect(text.lumMod, 0.65);
    expect(text.lumOff, 0.35);
    expect(office.titleText.color, text);
    for (final ChartColor line in <ChartColor>[
      office.gridLine,
      office.axisLine,
    ]) {
      expect(line.slot, ChartSchemeColor.dark1);
      expect(line.rgb, 0xD9D9D9);
      expect(line.lumMod, 0.15);
      expect(line.lumOff, 0.85);
    }
    expect(office.background.slot, ChartSchemeColor.light1);
    expect(office.background.rgb, 0xFFFFFF);
  });
}
