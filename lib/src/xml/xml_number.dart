/// Number formatting for XML attribute values.
///
/// New in jet_office; Quds interpolates doubles directly, which prints
/// `12.0` on the VM and `12` in the browser.
library;

/// The largest magnitude below which every whole `double` is exact: 2^53.
const double _maxExactInteger = 9007199254740992;

/// Formats [value] for an XML attribute (a width, height, tint or position)
/// so that the VM and the browser give the same text.
///
/// A whole value within ±2^53 prints as an integer (`12`, `-3`; negative
/// zero prints `0`). Anything else uses `double.toString`, which both
/// platforms render as the shortest text that parses back to [value].
///
/// Throws [ArgumentError] when [value] is NaN or infinite.
String formatXmlDouble(double value) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, 'value', 'Must be finite.');
  }
  if (value == value.truncateToDouble() && value.abs() <= _maxExactInteger) {
    // `toInt` is exact here and prints without a fraction on both platforms;
    // the cast to int also turns -0.0 into 0.
    return value.toInt().toString();
  }
  return value.toString();
}

/// [value] as [formatXmlDouble] prints it, or as `NaN`, `Infinity` or
/// `-Infinity` when it is not finite, for a `toString` that must not throw
/// on a value the writer has not validated yet.
String describeDouble(double value) =>
    value.isFinite ? formatXmlDouble(value) : '$value';
