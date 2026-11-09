import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

void main() {
  group('ChartDataLabels percent and value', () {
    test('defaults show the value and not the percent', () {
      const ChartDataLabels labels = ChartDataLabels();
      expect(labels.showValue, isTrue);
      expect(labels.showPercent, isFalse);
    });

    test('copyWith sets and keeps them', () {
      const ChartDataLabels labels = ChartDataLabels(visible: true);
      final ChartDataLabels set = labels.copyWith(
        showValue: false,
        showPercent: true,
      );
      expect(set.showValue, isFalse);
      expect(set.showPercent, isTrue);
      final ChartDataLabels kept = set.copyWith(visible: false);
      expect(kept.showValue, isFalse);
      expect(kept.showPercent, isTrue);
    });

    test('they change == and hashCode', () {
      const ChartDataLabels a = ChartDataLabels();
      const ChartDataLabels b = ChartDataLabels(showValue: false);
      const ChartDataLabels c = ChartDataLabels(showPercent: true);
      expect(a, isNot(b));
      expect(a, isNot(c));
      expect(a.hashCode, isNot(b.hashCode));
      expect(a.hashCode, isNot(c.hashCode));
      expect(a, const ChartDataLabels());
    });
  });
}
