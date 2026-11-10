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

  group('ChartDataLabels.minShare', () {
    test('defaults to 0', () {
      expect(const ChartDataLabels().minShare, 0);
    });

    test('copyWith sets and keeps it', () {
      final ChartDataLabels set = const ChartDataLabels().copyWith(
        minShare: 0.1,
      );
      expect(set.minShare, 0.1);
      expect(set.copyWith(visible: true).minShare, 0.1);
    });

    test('copyWith throws outside 0 to 1 or when not finite', () {
      for (final double bad in <double>[
        -0.01,
        1.01,
        double.nan,
        double.infinity,
      ]) {
        expect(
          () => const ChartDataLabels().copyWith(minShare: bad),
          throwsArgumentError,
          reason: '$bad',
        );
      }
      expect(const ChartDataLabels().copyWith(minShare: 1).minShare, 1);
    });

    test('the constructor, being const, takes any value', () {
      expect(const ChartDataLabels(minShare: 2).minShare, 2);
    });

    test('a chart throws for data labels with a bad minShare', () {
      for (final double bad in <double>[-0.5, 2, double.nan]) {
        expect(
          () => Chart(
            kind: ChartKind.pie,
            series: const <ChartSeries>[],
            dataLabels: ChartDataLabels(minShare: bad),
          ),
          throwsArgumentError,
          reason: '$bad',
        );
      }
    });

    test('it changes ==, hashCode and toString', () {
      const ChartDataLabels a = ChartDataLabels();
      const ChartDataLabels b = ChartDataLabels(minShare: 0.1);
      expect(a, isNot(b));
      expect(a.hashCode, isNot(b.hashCode));
      expect(b, const ChartDataLabels(minShare: 0.1));
      expect(b.toString(), contains('minShare: 0.1'));
    });
  });
}
