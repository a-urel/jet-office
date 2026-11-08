/// Excel's automatic value axis scale: where the axis starts and ends and how
/// far apart its ticks are, for given data.
///
/// The rule follows Jon Peltier's published reading of Excel's automatic axis
/// ("How Excel Calculates Automatic Chart Axis Limits", peltiertech.com) and
/// was checked against all 60 rows of the owner's run of Excel for Mac on
/// 2026-11-08 (`test/fixtures/owner/axis/`). Excel for Mac is the oracle; the
/// run found the minimum and maximum to depend on the data only, and the
/// major unit also on the axis length, which is why [autoValueScale] takes
/// the most intervals the axis can hold ([excelMaxIntervals], fitted on the
/// owner's full run of 2026-11-08, `test/fixtures/owner/axis_full/`).
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
///    it does not (computed on the decimal exponent, so even `5e-324` gets
///    there in a few steps).
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

/// The most intervals [autoValueScale] takes; more are read as this.
const int _maxIntervals = 1000;

/// The most ticks a scale has: one more than [_fixedUnitIntervals].
const int _maxTicks = _fixedUnitIntervals + 1;

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

/// The most major intervals Excel gives a value axis of [axisLength] whose
/// tick labels are [fontSize] points.
///
/// Fitted on the owner's full run of Excel for Mac (2026-11-08, `tr-TR`,
/// `test/fixtures/owner/axis_full/`): every L, B, W, M, G and F row, with
/// Excel's own plot height (vertical) or plot width (horizontal) as
/// [axisLength] and the case's font size, gives Excel's unit through
/// [autoValueScale] (`test/scale/axis_parity_test.dart`).
///
/// - A vertical axis (column, line, area) holds
///   `(axisLength - fontSize) / (fontSize + 2)` intervals: its labels, one
///   font size tall each, stacked 2 points apart, fit the axis. Fonts 8, 10
///   and 18 agree; the gap may lie anywhere from 1.96 to 2.32 points.
/// - A horizontal axis (bar) holds `(axisLength + 2 * fontSize) /
///   (3.9 * fontSize)` intervals. Fonts 8, 10 and 18 agree; the factors may
///   lie from 3.83 to 3.93 and 1.85 to 2.38. The labels' width does not
///   enter: the percent axes of G08 and G11, whose labels are twice as wide
///   as the B sets', fit the same rule.
///
/// The result is rounded down and kept between 1 and 10: Excel took one
/// interval on the shortest plots and never more than 10 (a 264 pt column
/// plot that could hold 20 gave 10). Width never changed a column chart's
/// scale (W). No length gives 1 and an infinite one 10; a font size of 0
/// gives 10 on any length.
///
/// Throws an [ArgumentError] for a negative or `NaN` length, or a negative or
/// non-finite font size.
int excelMaxIntervals(
  double axisLength, {
  required bool horizontal,
  required double fontSize,
}) {
  if (axisLength.isNaN || axisLength < 0) {
    throw ArgumentError.value(axisLength, 'axisLength', 'must not be negative');
  }
  if (!fontSize.isFinite || fontSize < 0) {
    throw ArgumentError.value(
      fontSize,
      'fontSize',
      'must be finite and not negative',
    );
  }
  if (axisLength.isInfinite) {
    return _excelIntervals;
  }
  final double q = horizontal
      ? (axisLength + 2 * fontSize) / (3.9 * fontSize)
      : (axisLength - fontSize) / (fontSize + 2);
  if (q.isNaN) {
    return 1;
  }
  if (q >= _excelIntervals) {
    return _excelIntervals;
  }
  return math.max(1, q.floor());
}

/// The most intervals Excel's automatic unit takes.
const int _excelIntervals = 10;

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
/// read as 1 and one above 1,000 as 1,000; a scale never has more than 1,001
/// ticks. A unit so fine that the top rounds onto the bottom (data near
/// `1e15` a few units apart) is passed over for the next coarser one.
///
/// A fixed maximum is ignored when it is not above the fixed minimum or, with
/// no fixed minimum, not above the data's minimum (when there is data). A fixed
/// minimum at or above the data's maximum, or with no data, reads the data as
/// `fixedMin` to `fixedMin + s`, where `s` is `|fixedMin|` or 1 for 0; a fixed
/// maximum with no data and no fixed minimum reads it as `fixedMax - s` to
/// `fixedMax`. Step 2 never applies to a fixed bound.
ValueScale autoValueScale({
  required double dataMin,
  required double dataMax,
  required int maxIntervals,
  double? fixedMin,
  double? fixedMax,
  double? fixedMajorUnit,
  bool percent = false,
}) {
  final int limit = maxIntervals.clamp(1, _maxIntervals);
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
  final bool hasData = dataMin.isFinite || dataMax.isFinite;
  final double dataHi = hi;

  // Step 6: a fixed bound stands in for the data's.
  if (fMax != null && fMax <= (fMin ?? (hasData ? lo : -double.infinity))) {
    fMax = null;
  }
  // A fixed bound the data does not reach: the data is read as a span from it.
  bool derived = false;
  if (fMin != null && fMax == null && (!hasData || fMin >= dataHi)) {
    lo = fMin;
    hi = fMin + (fMin != 0 ? fMin.abs() : 1);
    derived = true;
  } else if (fMax != null && fMin == null && !hasData) {
    hi = fMax;
    lo = fMax - (fMax != 0 ? fMax.abs() : 1);
    derived = true;
  }
  if (!derived) {
    if (fMin != null) {
      lo = fMin;
    }
    if (fMax != null) {
      hi = fMax;
    }
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
  } else if (lo == hi && !derived) {
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
    if (!(_intervals(bounds, u) <= _fixedUnitIntervals)) {
      // Jump a little below the first power of ten that fits, then step up
      // by 10: the axis spans at most a little over the data's or fixed
      // span, so that is a few steps, and the unit stays finite. The
      // estimate is the span itself, not the distance from 0, so data far
      // from 0 still get the finest unit that fits; |highest| stands in
      // only when the span is 0.
      final double lowest = math.min(a, mFixB ?? a);
      final double highest = math.max(c, mFixT ?? c);
      final double width = highest - lowest;
      final double span = width > 0 ? width : highest.abs();
      int n = 1;
      if (span > 0 && span.isFinite) {
        final double decades =
            math.log(span) / math.ln10 -
            math.log(_fixedUnitIntervals) / math.ln10 -
            math.log(fUnit) / math.ln10;
        n = math.max(1, decades.floor() - 2);
      }
      for (int step = 0; step < 700; step++, n++) {
        final double next = _decadesUp(fUnit, n);
        if (!next.isFinite) {
          break;
        }
        u = next;
        bounds = _bounds(u, a, c, mFixB, mFixT);
        if (_intervals(bounds, u) <= _fixedUnitIntervals) {
          break;
        }
      }
    }
  } else {
    u = 1;
    bounds = _bounds(u, a, c, mFixB, mFixT);
    bool found = false;
    // Start two decades below the span, so tiny data still gets a unit.
    final double span = mFixB != null && mFixT != null ? mFixT - mFixB : c - a;
    final int start = span > 0 && span.isFinite
        ? math.max(-300, (math.log(span) / math.ln10).floor() - 2)
        : -15;
    for (int k = start; k <= 302 && !found; k++) {
      for (final int m in const <int>[1, 2, 5]) {
        u = k < 0
            ? m / math.pow(10.0, -k).toDouble()
            : m * math.pow(10.0, k).toDouble();
        bounds = _bounds(u, a, c, mFixB, mFixT);
        // A unit too fine for the bounds' float precision leaves the top
        // on the bottom; the next coarser one is taken then.
        if (bounds.top > bounds.bottom &&
            (bounds.top - bounds.bottom) / u <= limit + 1e-9) {
          found = true;
          break;
        }
      }
    }
  }

  final double min = (mirrored ? -bounds.top : bounds.bottom) + 0.0;
  final double max = (mirrored ? -bounds.bottom : bounds.top) + 0.0;
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

/// The number of intervals of [bounds] at the unit [u]; `NaN` or infinite
/// when the bounds are.
double _intervals(({double bottom, double top}) bounds, double u) =>
    (bounds.top - bounds.bottom) / u;

/// [unit] times `10^n`, to 15 significant digits, computed on the decimal
/// exponent so that no power of ten overflows on the way; infinite when the
/// result is.
double _decadesUp(double unit, int n) {
  final List<String> parts = unit.toStringAsExponential(14).split('e');
  return double.parse('${parts.first}e${int.parse(parts.last) + n}');
}

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
///
/// Beyond 1e6 float error exceeds 1e-9 and `q * 1e9` would lose its meaning,
/// so there the guard is relative: [q] to 14 significant digits (a deviation
/// from the brief's absolute 9 decimals, which cannot hold at that size).
double _guard(double q) {
  if (!q.isFinite) {
    return q;
  }
  if (q.abs() >= 1e6) {
    return _significant(q, 14);
  }
  return (q * 1e9).round() / 1e9;
}

/// [value] to [digits] significant digits.
double _significant(double value, [int digits = 15]) =>
    value.isFinite && value != 0
    ? double.parse(value.toStringAsPrecision(digits))
    : value;

double _ceil(double q) => _guard(q).ceilToDouble();

double _floor(double q) => _guard(q).floorToDouble();

/// How many decimal places [value] needs, from its 15 significant digits.
int _decimals(double value) {
  final double v = value.abs();
  if (!v.isFinite || v == 0) {
    return 0;
  }
  final List<String> parts = v.toStringAsExponential(14).split('e');
  final String fraction = parts.first
      .split('.')
      .last
      .replaceFirst(RegExp(r'0+$'), '');
  return math.max(0, fraction.length - int.parse(parts.last));
}

/// [value] rounded to [digits] decimal places; a whole number stays as is.
double _round(double value, int digits) {
  final double scale = math.pow(10.0, digits).toDouble();
  final double x = value * scale;
  if (!x.isFinite || x.abs() >= _wholeAbove) {
    return value;
  }
  // Parsing the decimal text rounds correctly where dividing by an inexact
  // power of ten would not.
  return double.parse('${x.roundToDouble().toInt()}e-$digits') + 0.0;
}

/// [value] snapped to the decimals of the unit [u] plus two.
double _snap(double value, double u) => _round(value, _decimals(u) + 2);

/// The ticks from [min] to [max] by [u], snapped.
List<double> _ticks(double min, double max, double u) {
  final int digits = math.max(_decimals(u), _decimals(min)) + 2;
  final double q = _guard((max - min) / u);
  // A hard cap, so no scale can ask for an unbounded list.
  final int count = q.isFinite && q >= 0
      ? math.min(q.floor(), _maxTicks - 1)
      : 0;
  return <double>[for (int i = 0; i <= count; i++) _round(min + i * u, digits)];
}
