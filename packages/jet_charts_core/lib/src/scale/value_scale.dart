/// Excel's automatic value axis scale: where the axis starts and ends and how
/// far apart its ticks are, for given data.
///
/// The rule follows Jon Peltier's published reading of Excel's automatic axis
/// ("How Excel Calculates Automatic Chart Axis Limits", peltiertech.com) and
/// was checked against all 60 rows of the owner's run of Excel for Mac on
/// 2026-11-08 (`test/fixtures/owner/axis/`). Excel for Mac is the oracle; the
/// run found the minimum and maximum to depend on the data only, and the
/// major unit also on the axis length, which is why [autoValueScale] takes
/// the most intervals the axis can hold.
///
/// The steps, in order:
///
/// 1. Non-finite values are ignored and the rest clamped to plus or minus
///    1e300. With no values the data is `0` to `0`.
/// 2. All values equal: `0` gives the fixed bounds `0` to `1`; a positive `v`
///    is read as `0` to `v`, a negative one as `v` to `0`.
/// 3. With the minimum at or above 0, the minimum is free when
///    `(max - min) / max` is under one sixth, else it is `0`. With the maximum
///    at or below 0 the same holds mirrored. With mixed signs both are free.
/// 4. For each step of 1, 2 or 5 times a power of ten, from fine to coarse, a
///    free top is the data's maximum plus 5 percent of the span, rounded up to
///    the step, and a free bottom is rounded down to it (half a span below the
///    minimum when the data is positive, 5 percent of the span below it when
///    the signs are mixed, and never below 0 when the data is positive). The
///    first step that fits in the most intervals wins.
/// 5. A percent axis is fixed at `0` to `1`, or `-1` to `1` when the data has
///    negatives; step 4 picks the unit.
/// 6. Fixed values win; the free parts follow step 4 with the fixed bound in
///    place of the data's. A fixed maximum not above the minimum is ignored.
///    A fixed unit giving more than 1,000 intervals is multiplied by 10 until
///    it does not.
/// 7. Ticks are `min + i * unit`, each rounded to the unit's decimal places
///    plus two, so `0.1 * 3` prints `0.3`.
library;

import 'dart:math' as math;

import '../model/chart_kind.dart';
import '../model/equality.dart';

/// The largest magnitude a data value may have; larger ones are clamped.
const double _limit = 1e300;

/// Above this, a double is a whole number and rounding it changes nothing.
const double _wholeAbove = 9e15;

/// The most intervals a fixed major unit may give.
const int _fixedUnitIntervals = 1000;

/// An axis scale: the bounds, the major unit and the ticks between them.
///
/// Excel's automatic one comes from [autoValueScale]. The ticks run from
/// [min] to [max] by [majorUnit], snapped so that float error does not show.
final class ValueScale {
  /// Creates a scale; [ticks] is copied into an unmodifiable list.
  ValueScale({
    required this.min,
    required this.max,
    required this.majorUnit,
    required List<double> ticks,
  }) : ticks = List<double>.unmodifiable(ticks);

  /// The axis' lowest value.
  final double min;

  /// The axis' highest value.
  final double max;

  /// The distance between two ticks.
  final double majorUnit;

  /// The tick values from [min] up by [majorUnit]; unmodifiable.
  final List<double> ticks;

  @override
  bool operator ==(Object other) =>
      other is ValueScale &&
      valueEquals(min, other.min) &&
      valueEquals(max, other.max) &&
      valueEquals(majorUnit, other.majorUnit) &&
      listValueEquals(ticks, other.ticks);

  @override
  int get hashCode => Object.hash(
    valueHash(min),
    valueHash(max),
    valueHash(majorUnit),
    listValueHash(ticks),
  );

  @override
  String toString() =>
      'ValueScale(min: $min, max: $max, majorUnit: $majorUnit, '
      'ticks: ${ticks.length})';
}

/// The most major intervals an axis of [axisLength] can hold.
///
/// This is `(axisLength / 12.5).floor()` between 2 and 10. It is provisional:
/// the owner's run did not record the plot length, and Task 11 replaces this
/// with the rule the oracle gives.
///
/// Throws an [ArgumentError] for a negative or `NaN` length.
int provisionalMaxIntervals(double axisLength) {
  if (axisLength.isNaN || axisLength < 0) {
    throw ArgumentError.value(axisLength, 'axisLength', 'must not be negative');
  }
  if (axisLength.isInfinite) {
    return 10;
  }
  return math.min(10, math.max(2, (axisLength / 12.5).floor()));
}

/// The lowest and highest value a chart's [series] reach under [grouping].
///
/// Clustered, it is that of the finite values. Stacked, and percent stacked,
/// each category adds its positive values and its negative values apart, with
/// 0 included, and the extent is that of the sums; for percent stacked the
/// caller also sets `percent` of [autoValueScale] (a negative minimum there
/// means the axis runs from -1). With no finite value both ends are `NaN`,
/// which [autoValueScale] reads as no data.
({double min, double max}) dataExtent(
  List<List<double?>> series,
  ChartGrouping grouping,
) {
  double min = double.infinity;
  double max = double.negativeInfinity;
  bool any = false;
  if (grouping == ChartGrouping.clustered) {
    for (final List<double?> values in series) {
      for (final double? value in values) {
        if (value != null && value.isFinite) {
          any = true;
          min = math.min(min, value);
          max = math.max(max, value);
        }
      }
    }
  } else {
    int categories = 0;
    for (final List<double?> values in series) {
      categories = math.max(categories, values.length);
    }
    for (int i = 0; i < categories; i++) {
      double positive = 0;
      double negative = 0;
      for (final List<double?> values in series) {
        final double? value = i < values.length ? values[i] : null;
        if (value != null && value.isFinite) {
          any = true;
          if (value > 0) {
            positive += value;
          } else {
            negative += value;
          }
        }
      }
      min = math.min(min, negative);
      max = math.max(max, positive);
    }
  }
  if (!any) {
    return (min: double.nan, max: double.nan);
  }
  return (min: min, max: max);
}

/// Excel's automatic scale for data from [dataMin] to [dataMax], with at most
/// [maxIntervals] major intervals (see the library comment for the rule).
///
/// [dataMin] and [dataMax] may be `NaN` or infinite (no data). [fixedMin],
/// [fixedMax] and [fixedMajorUnit] are the chart's own settings and win over
/// the rule; a [fixedMajorUnit] that is not a positive finite number is
/// ignored. [percent] is a percent stacked axis. A [maxIntervals] below 1 is
/// read as 1.
ValueScale autoValueScale({
  required double dataMin,
  required double dataMax,
  required int maxIntervals,
  double? fixedMin,
  double? fixedMax,
  double? fixedMajorUnit,
  bool percent = false,
}) {
  final int limit = math.max(1, maxIntervals);
  final double? fMin = _fixed(fixedMin);
  double? fMax = _fixed(fixedMax);
  final double? fUnit =
      fixedMajorUnit != null && fixedMajorUnit.isFinite && fixedMajorUnit > 0
      ? fixedMajorUnit
      : null;

  // Step 1.
  double lo;
  double hi;
  if (!dataMin.isFinite && !dataMax.isFinite) {
    lo = hi = 0;
  } else if (!dataMin.isFinite) {
    lo = hi = _clamp(dataMax);
  } else if (!dataMax.isFinite) {
    lo = hi = _clamp(dataMin);
  } else {
    lo = _clamp(math.min(dataMin, dataMax));
    hi = _clamp(math.max(dataMin, dataMax));
  }
  final bool negatives = lo < 0;

  // Step 6: a fixed bound stands in for the data's.
  if (fMax != null && fMax <= (fMin ?? lo)) {
    fMax = null;
  }
  if (fMin != null) {
    lo = fMin;
  }
  if (fMax != null) {
    hi = fMax;
  }
  if (lo > hi) {
    hi = lo;
  }

  // Steps 2 and 5: bounds the rule fixes.
  double? ruleMin;
  double? ruleMax;
  if (percent) {
    ruleMin = negatives ? -1 : 0;
    ruleMax = 1;
  } else if (lo == hi) {
    if (lo == 0) {
      ruleMin = 0;
      ruleMax = 1;
    } else if (lo > 0) {
      lo = 0;
    } else {
      hi = 0;
    }
  }
  final double? fixB = fMin ?? ruleMin;
  final double? fixT = fMax ?? ruleMax;

  // All negative is the mirror of all positive.
  final bool mirrored = hi <= 0 && lo < 0;
  final double a = mirrored ? -hi : lo;
  final double c = mirrored ? -lo : hi;
  final double? mFixB = mirrored ? _negate(fixT) : fixB;
  final double? mFixT = mirrored ? _negate(fixB) : fixT;

  double u;
  ({double bottom, double top}) bounds;
  if (fUnit != null) {
    u = fUnit;
    bounds = _bounds(u, a, c, mFixB, mFixT);
    while ((bounds.top - bounds.bottom) / u > _fixedUnitIntervals) {
      u *= 10;
      bounds = _bounds(u, a, c, mFixB, mFixT);
    }
  } else {
    u = 1;
    bounds = _bounds(u, a, c, mFixB, mFixT);
    bool found = false;
    for (int k = -15; k <= 302 && !found; k++) {
      for (final int m in const <int>[1, 2, 5]) {
        u = k < 0
            ? m / math.pow(10.0, -k).toDouble()
            : m * math.pow(10.0, k).toDouble();
        bounds = _bounds(u, a, c, mFixB, mFixT);
        if ((bounds.top - bounds.bottom) / u <= limit + 1e-9) {
          found = true;
          break;
        }
      }
    }
  }

  final double min = mirrored ? -bounds.top : bounds.bottom;
  final double max = mirrored ? -bounds.bottom : bounds.top;
  return ValueScale(
    min: min,
    max: max,
    majorUnit: u,
    ticks: _ticks(min, max, u),
  );
}

/// [value] clamped to plus or minus [_limit].
double _clamp(double value) => value.clamp(-_limit, _limit);

/// A fixed bound as given, clamped, or `null` when it is not finite.
double? _fixed(double? value) =>
    value != null && value.isFinite ? _clamp(value) : null;

double? _negate(double? value) => value == null ? null : -value;

/// The bottom and top of the axis for step [u], over the non-negative or
/// mixed span [a] to [c] (the mirror of an all-negative span), with the fixed
/// [fixB] and [fixT] where there are any (step 4).
({double bottom, double top}) _bounds(
  double u,
  double a,
  double c,
  double? fixB,
  double? fixT,
) {
  double bottom;
  double top;
  if (a < 0 && c > 0) {
    top = fixT ?? _snap(_ceil((c + 0.05 * (c - a)) / u) * u, u);
    bottom = fixB ?? _snap(_floor((a - 0.05 * (c - a)) / u) * u, u);
  } else {
    final bool pinned = c == 0 || (c - a) / c >= 1 / 6;
    final double base = fixB ?? (pinned ? 0 : a);
    top = fixT ?? _snap(_ceil((c + 0.05 * (c - base)) / u) * u, u);
    bottom =
        fixB ??
        (pinned ? 0 : _snap(math.max(0, _floor((a - (c - a) / 2) / u) * u), u));
  }
  if (top <= bottom) {
    top = _snap(bottom + u, u);
  }
  return (bottom: bottom, top: top);
}

/// The quotient [q] to 9 decimals, so float error never adds a step.
double _guard(double q) {
  if (!q.isFinite || q.abs() >= 1e6) {
    return q;
  }
  return (q * 1e9).round() / 1e9;
}

double _ceil(double q) => _guard(q).ceilToDouble();

double _floor(double q) => _guard(q).floorToDouble();

/// How many decimal places [value] needs, up to 15.
int _decimals(double value) {
  final double v = value.abs();
  if (!v.isFinite || v == 0) {
    return 0;
  }
  for (int d = 0; d < 15; d++) {
    final double s = v * math.pow(10, d);
    final double whole = s.roundToDouble();
    if (s >= 1e15 || (whole >= 1 && (s - whole).abs() <= 1e-9 * whole)) {
      return d;
    }
  }
  return 15;
}

/// [value] rounded to [digits] decimal places; a whole number stays as is.
double _round(double value, int digits) {
  final double scale = math.pow(10, digits).toDouble();
  final double x = value * scale;
  if (!x.isFinite || x.abs() >= _wholeAbove) {
    return value;
  }
  return x.roundToDouble() / scale + 0.0;
}

/// [value] snapped to the decimals of the unit [u] plus two.
double _snap(double value, double u) => _round(value, _decimals(u) + 2);

/// The ticks from [min] to [max] by [u], snapped.
List<double> _ticks(double min, double max, double u) {
  final int digits = math.min(17, math.max(_decimals(u), _decimals(min)) + 2);
  final int count = _guard((max - min) / u).floor();
  return <double>[for (int i = 0; i <= count; i++) _round(min + i * u, digits)];
}
