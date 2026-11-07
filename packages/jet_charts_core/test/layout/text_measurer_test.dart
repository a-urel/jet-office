import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

ChartTextStyle sized(double size) =>
    ChartTextStyle(fontFamily: 'Test', size: size, color: ChartColor.rgb(0));

void main() {
  const FixedWidthTextMeasurer measurer = FixedWidthTextMeasurer();

  test('measures runes', () {
    final ChartSize turkish = measurer.measure('İı', sized(10));
    expect(turkish.width, closeTo(12, 1e-9));
    final ChartSize empty = measurer.measure('', sized(10));
    expect(empty.width, 0);
    expect(empty.height, closeTo(12, 1e-9));
  });

  test('counts a surrogate pair as one rune', () {
    expect(measurer.measure('😀', sized(10)).width, closeTo(6, 1e-9));
  });

  test('measures lines', () {
    final ChartSize two = measurer.measure('ab\ncd', sized(10));
    expect(two.height, closeTo(24, 1e-9));
    expect(two.width, closeTo(12, 1e-9));
    expect(measurer.measure('a\nlonger', sized(10)).width, closeTo(36, 1e-9));
    expect(measurer.measure('\n', sized(10)).height, closeTo(24, 1e-9));
  });

  test('all results are finite and non-negative', () {
    for (final String text in <String>['', '\n', '\n\n', 'İı', 'abc\n', '😀']) {
      final ChartSize size = measurer.measure(text, sized(10));
      expect(size.width.isFinite && size.width >= 0, isTrue, reason: text);
      expect(size.height.isFinite && size.height >= 0, isTrue, reason: text);
    }
  });

  test('factors are configurable', () {
    const FixedWidthTextMeasurer wide = FixedWidthTextMeasurer(
      charWidthFactor: 1,
      lineHeightFactor: 2,
    );
    final ChartSize size = wide.measure('abc', sized(10));
    expect(size.width, 30);
    expect(size.height, 20);
  });
}
