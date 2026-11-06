/// Conversions between the points of the API and the units of the file.
///
/// Not ported from Quds; written for jet_office.
///
/// The API speaks points; WordprocessingML stores twips (20 per point),
/// half-points, eighths of a point and whole points. A value set is rounded
/// to the file's unit with `double.round()` (half away from zero, the same
/// on the VM and in JavaScript) and reads back rounded; a value that is not
/// finite throws [ArgumentError], one outside the range after rounding
/// throws [RangeError] (plan Ruling 4). The `min` and `max` of each
/// conversion are in the file's unit.
library;

/// The largest magnitude of a length in twips: 1584 points (plan Ruling 4).
const int maxTwips = 31680;

/// The largest list number (`w:numId`): nine digits, which every platform
/// reads exactly.
const int maxNumId = 999999999;

/// The largest magnitude a conversion rounds, so a huge but finite value
/// is a range error and not a platform-dependent rounding.
const double _roundable = 1e12;

int _stored(
  double value,
  double perPoint,
  String name, {
  required int min,
  required int max,
}) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, name, 'must be a finite number');
  }
  final double scaled = value * perPoint;
  final int n = scaled.abs() > _roundable
      ? (scaled < 0 ? min - 1 : max + 1)
      : scaled.round();
  if (n < min || n > max) {
    throw RangeError.range(
      n,
      min,
      max,
      name,
      'must be from ${min / perPoint} to ${max / perPoint} points',
    );
  }
  return n;
}

/// [pt] points in twips (twentieths of a point), from [min] to [max].
int twipsOf(double pt, String name, {required int min, required int max}) =>
    _stored(pt, 20, name, min: min, max: max);

/// [pt] points in half-points, from [min] to [max].
int halfPointsOf(
  double pt,
  String name, {
  required int min,
  required int max,
}) => _stored(pt, 2, name, min: min, max: max);

/// [pt] points in eighths of a point, from [min] to [max].
int eighthsOf(double pt, String name, {required int min, required int max}) =>
    _stored(pt, 8, name, min: min, max: max);

/// [pt] points in whole points, from [min] to [max].
int pointsOf(double pt, String name, {required int min, required int max}) =>
    _stored(pt, 1, name, min: min, max: max);

/// [lines] lines of spacing in 240ths of a line, from [min] to [max].
int lineUnitsOf(
  double lines,
  String name, {
  required int min,
  required int max,
}) => _stored(lines, 240, name, min: min, max: max);

/// [twips] in points.
double ptOfTwips(int twips) => twips / 20;

/// [halfPoints] in points.
double ptOfHalfPoints(int halfPoints) => halfPoints / 2;

/// [eighths] in points.
double ptOfEighths(int eighths) => eighths / 8;

/// [units] 240ths of a line in lines.
double linesOfLineUnits(int units) => units / 240;
