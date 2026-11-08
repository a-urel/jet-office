import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_core/src/scale/value_scale.dart'
    show excelMaxIntervals;
import 'package:test/test.dart';

/// The scale's three numbers, for compact expectations.
List<double> _of(ValueScale s) => <double>[s.min, s.max, s.majorUnit];

void main() {
  group('step 1: values', () {
    test('nan data gives 0 to 1', () {
      final ValueScale s = autoValueScale(
        dataMin: double.nan,
        dataMax: double.nan,
        maxIntervals: 10,
      );
      expect(_of(s), <double>[0, 1, 0.1]);
    });

    test('a non-finite end is ignored', () {
      expect(
        autoValueScale(dataMin: double.nan, dataMax: 5, maxIntervals: 10),
        autoValueScale(dataMin: 5, dataMax: 5, maxIntervals: 10),
      );
      expect(
        autoValueScale(
          dataMin: double.negativeInfinity,
          dataMax: double.infinity,
          maxIntervals: 10,
        ),
        autoValueScale(
          dataMin: double.nan,
          dataMax: double.nan,
          maxIntervals: 10,
        ),
      );
    });

    test('1e308 is clamped', () {
      final ValueScale s = autoValueScale(
        dataMin: 0,
        dataMax: 1e308,
        maxIntervals: 10,
      );
      expect(s.min, 0);
      expect(s.max.isFinite, isTrue);
      expect(s.max, greaterThanOrEqualTo(1e300));
      expect(s.max, lessThan(3e300));
      expect(s.ticks.first, 0);
      expect(s.ticks.last, s.max);
    });
  });

  group('step 2: all values equal', () {
    test('zero gives 0 to 1', () {
      expect(
        _of(autoValueScale(dataMin: 0, dataMax: 0, maxIntervals: 9)),
        <double>[0, 1, 0.2],
      );
    });

    test('a positive value is read as 0 to v', () {
      expect(
        autoValueScale(dataMin: 1000, dataMax: 1000, maxIntervals: 10),
        autoValueScale(dataMin: 0, dataMax: 1000, maxIntervals: 10),
      );
    });

    test('a negative value is read as v to 0', () {
      expect(
        autoValueScale(dataMin: -1000, dataMax: -1000, maxIntervals: 10),
        autoValueScale(dataMin: -1000, dataMax: 0, maxIntervals: 10),
      );
    });
  });

  group('step 3: whether the minimum is free', () {
    test('a spread of a sixth or more of the maximum pins it at 0', () {
      expect(autoValueScale(dataMin: 5, dataMax: 10, maxIntervals: 10).min, 0);
    });

    test('a narrow spread leaves the minimum free', () {
      // d03: 97 to 99 gives 96 to 99.5 by 0.5.
      expect(
        _of(autoValueScale(dataMin: 97, dataMax: 99, maxIntervals: 10)),
        <double>[96, 99.5, 0.5],
      );
    });

    test('all negative mirrors it: the maximum is pinned at 0', () {
      final ValueScale s = autoValueScale(
        dataMin: -10,
        dataMax: -5,
        maxIntervals: 10,
      );
      expect(s.max, 0);
      final ValueScale mirror = autoValueScale(
        dataMin: 5,
        dataMax: 10,
        maxIntervals: 10,
      );
      expect(_of(s), <double>[-mirror.max, 0, mirror.majorUnit]);
    });

    test('mixed signs leave both free', () {
      // d06: -5 to 3.
      expect(
        _of(autoValueScale(dataMin: -5, dataMax: 3, maxIntervals: 10)),
        <double>[-6, 4, 1],
      );
    });
  });

  group('step 4: the unit', () {
    test('d01: 1 to 3 gives 0 to 3.5 by 0.5', () {
      expect(
        _of(autoValueScale(dataMin: 1, dataMax: 3, maxIntervals: 10)),
        <double>[0, 3.5, 0.5],
      );
    });

    test('d07 at 9 intervals gives -102, -84, 2', () {
      expect(
        _of(autoValueScale(dataMin: -100, dataMax: -90, maxIntervals: 9)),
        <double>[-102, -84, 2],
      );
    });

    test('d05 at 9 gives 0, 1, 0.2', () {
      expect(
        _of(autoValueScale(dataMin: 0, dataMax: 0, maxIntervals: 9)),
        <double>[0, 1, 0.2],
      );
    });

    test('fewer intervals give a coarser unit', () {
      expect(
        autoValueScale(dataMin: -5, dataMax: 3, maxIntervals: 9).majorUnit,
        2,
      );
    });
  });

  group('step 5: percent', () {
    test('bounds are 0 to 1', () {
      expect(
        _of(
          autoValueScale(
            dataMin: 0.1,
            dataMax: 0.7,
            maxIntervals: 10,
            percent: true,
          ),
        ),
        <double>[0, 1, 0.1],
      );
    });

    test('with negatives they are -1 to 1', () {
      expect(
        _of(
          autoValueScale(
            dataMin: -0.5,
            dataMax: 0.5,
            maxIntervals: 10,
            percent: true,
          ),
        ),
        <double>[-1, 1, 0.2],
      );
    });
  });

  group('step 6: fixed values', () {
    test('fixed bounds win', () {
      expect(
        _of(
          autoValueScale(
            dataMin: 1,
            dataMax: 10,
            maxIntervals: 10,
            fixedMin: 2,
            fixedMax: 8,
          ),
        ),
        <double>[2, 8, 1],
      );
    });

    test('a fixed max below the data is ignored', () {
      expect(
        autoValueScale(dataMin: 6, dataMax: 10, maxIntervals: 10, fixedMax: 5),
        autoValueScale(dataMin: 6, dataMax: 10, maxIntervals: 10),
      );
    });

    test('fixed min equal to fixed max ignores the max', () {
      // The top follows the data, from the fixed minimum.
      expect(
        _of(
          autoValueScale(
            dataMin: 1,
            dataMax: 10,
            maxIntervals: 10,
            fixedMin: 5,
            fixedMax: 5,
          ),
        ),
        <double>[5, 11, 1],
      );
    });

    test('a fixed min alone leaves the top free', () {
      final ValueScale s = autoValueScale(
        dataMin: 1,
        dataMax: 10,
        maxIntervals: 10,
        fixedMin: 0,
      );
      expect(s.min, 0);
      expect(s.max, greaterThanOrEqualTo(10));
    });

    test('a fixed unit is kept', () {
      final ValueScale s = autoValueScale(
        dataMin: 0,
        dataMax: 10,
        maxIntervals: 10,
        fixedMajorUnit: 2.5,
      );
      expect(s.majorUnit, 2.5);
      expect(s.ticks.first, s.min);
      expect(s.ticks.last, s.max);
    });

    test('a fixed unit of more than 1,000 intervals is multiplied by 10', () {
      final ValueScale s = autoValueScale(
        dataMin: 0,
        dataMax: 1000,
        maxIntervals: 10,
        fixedMajorUnit: 0.001,
        fixedMin: 0,
        fixedMax: 1000,
      );
      expect(s.majorUnit, 1);
      expect(s.ticks, hasLength(1001));
    });

    test('a fixed unit that is not positive is ignored', () {
      expect(
        autoValueScale(
          dataMin: 1,
          dataMax: 3,
          maxIntervals: 10,
          fixedMajorUnit: 0,
        ),
        autoValueScale(dataMin: 1, dataMax: 3, maxIntervals: 10),
      );
    });
  });

  group('step 7: ticks', () {
    test('ticks are snapped', () {
      final ValueScale s = autoValueScale(
        dataMin: 0,
        dataMax: 0.28,
        maxIntervals: 3,
      );
      expect(s.majorUnit, 0.1);
      expect(s.ticks, <double>[0, 0.1, 0.2, 0.3]);
      expect(s.max, 0.3);
    });

    test('ticks run from min to max by the unit', () {
      final ValueScale s = autoValueScale(
        dataMin: -5,
        dataMax: 3,
        maxIntervals: 10,
      );
      expect(s.ticks, <double>[-6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4]);
    });

    test('the ticks list cannot be changed', () {
      final ValueScale s = autoValueScale(
        dataMin: 1,
        dataMax: 3,
        maxIntervals: 10,
      );
      expect(() => s.ticks.add(1), throwsUnsupportedError);
    });
  });

  group('ValueScale', () {
    test('equal scales are equal and hash alike', () {
      final ValueScale a = ValueScale(
        min: 0,
        max: 2,
        majorUnit: 1,
        ticks: <double>[0, 1, 2],
      );
      final ValueScale b = ValueScale(
        min: 0,
        max: 2,
        majorUnit: 1,
        ticks: <double>[0, 1, 2],
      );
      final ValueScale c = ValueScale(
        min: 0,
        max: 2,
        majorUnit: 1,
        ticks: <double>[0, 2],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a.toString(), contains('majorUnit: 1'));
    });

    test('the constructor copies the ticks', () {
      final List<double> ticks = <double>[0, 1];
      final ValueScale s = ValueScale(
        min: 0,
        max: 1,
        majorUnit: 1,
        ticks: ticks,
      );
      ticks.add(2);
      expect(s.ticks, <double>[0, 1]);
    });
  });

  group('excelMaxIntervals', () {
    int vertical(double length, double font) =>
        excelMaxIntervals(length, horizontal: false, fontSize: font);
    int horizontal(double length, double font) =>
        excelMaxIntervals(length, horizontal: true, fontSize: font);

    test('a vertical axis holds (length - font) / (font + 2), 1 to 10', () {
      // Excel's own plot heights (axis_oracle_full.tr-TR.csv).
      expect(vertical(23.93, 10), 1);
      expect(vertical(43.93, 10), 2);
      expect(vertical(63.93, 10), 4);
      expect(vertical(83.93, 10), 6);
      expect(vertical(123.93, 10), 9);
      expect(vertical(143.93, 10), 10);
      expect(vertical(763.93, 10), 10);
      expect(vertical(67.73, 8), 5);
      expect(vertical(94.28, 18), 3);
    });

    test('a horizontal axis holds (length + 2 font) / (3.9 font), 1 to 10', () {
      expect(horizontal(43.13, 10), 1);
      expect(horizontal(83.13, 10), 2);
      expect(horizontal(143.13, 10), 4);
      expect(horizontal(263.13, 10), 7);
      expect(horizontal(363.13, 10), 9);
      expect(horizontal(563.13, 10), 10);
      expect(horizontal(267, 8), 9);
      expect(horizontal(247.63, 18), 4);
    });

    test('no length gives 1, an infinite one 10', () {
      expect(vertical(0, 9), 1);
      expect(horizontal(0, 9), 1);
      expect(vertical(double.infinity, 9), 10);
      expect(horizontal(double.infinity, 9), 10);
    });

    test('a font size of 0 gives 10 on any length, 1 on none', () {
      expect(vertical(100, 0), 10);
      expect(horizontal(100, 0), 10);
      expect(horizontal(0, 0), 1);
    });

    test('a negative or NaN length or font size throws', () {
      expect(() => vertical(-1, 9), throwsArgumentError);
      expect(() => horizontal(double.nan, 9), throwsArgumentError);
      expect(() => vertical(100, -1), throwsArgumentError);
      expect(() => horizontal(100, double.nan), throwsArgumentError);
      expect(() => vertical(100, double.infinity), throwsArgumentError);
    });
  });

  group('dataExtent', () {
    test('clustered takes the finite values', () {
      final ({double min, double max}) e = dataExtent(<List<double?>>[
        <double?>[1, null, double.nan],
        <double?>[5, double.infinity, -2],
      ], ChartGrouping.clustered);
      expect((e.min, e.max), (-2.0, 5.0));
    });

    test('no finite value gives nan', () {
      final ({double min, double max}) e = dataExtent(<List<double?>>[
        <double?>[null, double.nan],
      ], ChartGrouping.clustered);
      expect(e.min.isNaN, isTrue);
      expect(e.max.isNaN, isTrue);
      expect(
        dataExtent(<List<double?>>[], ChartGrouping.stacked).max.isNaN,
        isTrue,
      );
    });

    test('stacked extent adds positives and negatives apart', () {
      final ({double min, double max}) e = dataExtent(<List<double?>>[
        <double?>[1, 2],
        <double?>[3, -4],
        <double?>[null, -1],
      ], ChartGrouping.stacked);
      expect((e.min, e.max), (-5.0, 4.0));
    });

    test('stacked includes 0', () {
      final ({double min, double max}) e = dataExtent(<List<double?>>[
        <double?>[5],
        <double?>[3],
      ], ChartGrouping.stacked);
      expect((e.min, e.max), (0.0, 8.0));
    });

    test('percent stacked has the stacked extent', () {
      final ({double min, double max}) e = dataExtent(<List<double?>>[
        <double?>[1, -2],
        <double?>[3, 1],
      ], ChartGrouping.percentStacked);
      expect((e.min, e.max), (-2.0, 4.0));
    });
  });

  group('review fixes', () {
    ValueScale scale(
      double dMin,
      double dMax, {
      double? fMin,
      double? fMax,
      double? unit,
      int n = 10,
    }) => autoValueScale(
      dataMin: dMin,
      dataMax: dMax,
      maxIntervals: n,
      fixedMin: fMin,
      fixedMax: fMax,
      fixedMajorUnit: unit,
    );

    test('a fixed min above the data reads the data as fixed to fixed + s', () {
      final ValueScale s = scale(1, 10, fMin: 50);
      expect(_of(s), <double>[50, 110, 10]);
      expect(s.ticks.length, greaterThanOrEqualTo(2));
    });

    test('a fixed min equal to the data max', () {
      expect(_of(scale(1, 10, fMin: 10)), <double>[10, 22, 2]);
    });

    test('a fixed min with no data', () {
      expect(_of(scale(double.nan, double.nan, fMin: 5)), <double>[5, 11, 1]);
      expect(_of(scale(double.nan, double.nan, fMin: 0)), <double>[
        0,
        1.2,
        0.2,
      ]);
    });

    test('the mirror: a fixed max with no data', () {
      expect(_of(scale(double.nan, double.nan, fMax: -50)), <double>[
        -110,
        -50,
        10,
      ]);
      expect(_of(scale(double.nan, double.nan, fMax: 0)), <double>[
        -1.2,
        0,
        0.2,
      ]);
    });

    test('a tiny fixed unit is multiplied by 10 without float error', () {
      expect(scale(0, 10, unit: 1e-300).majorUnit, 0.1);
      final ValueScale s = scale(0, 1, fMin: -1e308, fMax: 1e308, unit: 1);
      expect(s.majorUnit, 1e298);
      expect(s.ticks, hasLength(201));
    });

    test('an all-negative scale has no negative zero', () {
      final ValueScale s = scale(-10, -5);
      expect(s.max, 0);
      expect(s.max.isNegative, isFalse);
      expect(s.ticks.last.isNegative, isFalse);
    });

    test('quotients near 1e9 are guarded relatively', () {
      expect(_of(scale(1e9 + 1, 1e9 + 2)), <double>[
        1000000000.4,
        1000000002.2,
        0.2,
      ]);
    });

    test('data far below 1e-15 still gets a scale', () {
      final ValueScale s = scale(1e-20, 2e-20);
      expect(_of(s), <double>[0, 2.5e-20, 5e-21]);
      expect(s.ticks, hasLength(6));
    });
  });
  group('final review fixes', () {
    test('a fixed unit of 1e-300 over data to 1e300 returns quickly', () {
      final Stopwatch watch = Stopwatch()..start();
      final ValueScale s = autoValueScale(
        dataMin: 0,
        dataMax: 1e300,
        maxIntervals: 10,
        fixedMajorUnit: 1e-300,
      );
      expect(watch.elapsedMilliseconds, lessThan(2000));
      expect(s.ticks.length, lessThanOrEqualTo(1001));
      expect(s.majorUnit.isFinite, isTrue);
      expect((s.max - s.min) / s.majorUnit, lessThanOrEqualTo(1000 + 1e-6));
      expect(s.max, greaterThanOrEqualTo(1e300));
    });

    test('a fixed unit of 5e-324 over data 0 to 1 returns quickly', () {
      final Stopwatch watch = Stopwatch()..start();
      final ValueScale s = autoValueScale(
        dataMin: 0,
        dataMax: 1,
        maxIntervals: 10,
        fixedMajorUnit: 5e-324,
      );
      expect(watch.elapsedMilliseconds, lessThan(2000));
      expect(s.ticks.length, lessThanOrEqualTo(1001));
      expect(s.min, 0);
      expect(s.max, greaterThanOrEqualTo(1));
    });

    test('a fixed unit far below data far from 0 takes the first fitting '
        'power of ten', () {
      // The first x10 of the unit whose interval count is at most 1,000.
      final ValueScale near = autoValueScale(
        dataMin: 1000,
        dataMax: 1001,
        maxIntervals: 10,
        fixedMajorUnit: 1e-4,
      );
      expect(near.majorUnit, closeTo(0.01, 1e-15));
      expect(near.ticks.length, lessThanOrEqualTo(1001));
      final ValueScale far = autoValueScale(
        dataMin: 1e9,
        dataMax: 1e9 + 1,
        maxIntervals: 10,
        fixedMajorUnit: 1e-9,
      );
      expect(far.majorUnit, closeTo(0.01, 1e-15));
      expect(far.ticks.length, lessThanOrEqualTo(1001));
    });

    test('maxIntervals above 1,000 is read as 1,000', () {
      final ValueScale s = autoValueScale(
        dataMin: 0,
        dataMax: 1,
        maxIntervals: 1000000,
      );
      expect(s.ticks.length, lessThanOrEqualTo(1001));
      expect(s, autoValueScale(dataMin: 0, dataMax: 1, maxIntervals: 1000));
    });

    test('near-equal huge values give a top above the bottom', () {
      final ValueScale s = autoValueScale(
        dataMin: 1e15,
        dataMax: 1e15 + 3,
        maxIntervals: 10,
      );
      expect(s.max, greaterThan(s.min));
      expect(s.ticks.length, greaterThanOrEqualTo(2));
    });
  });
}
