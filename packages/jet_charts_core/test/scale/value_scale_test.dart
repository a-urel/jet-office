import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_core/src/scale/value_scale.dart'
    show provisionalMaxIntervals;
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

  group('provisionalMaxIntervals', () {
    test('is the length over 12.5, between 2 and 10', () {
      expect(provisionalMaxIntervals(150), 10);
      expect(provisionalMaxIntervals(100), 8);
      expect(provisionalMaxIntervals(10), 2);
      expect(provisionalMaxIntervals(0), 2);
      expect(provisionalMaxIntervals(double.infinity), 10);
    });

    test('a negative or NaN length throws', () {
      expect(() => provisionalMaxIntervals(-1), throwsArgumentError);
      expect(() => provisionalMaxIntervals(double.nan), throwsArgumentError);
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
