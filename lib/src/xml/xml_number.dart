/// Number formatting for XML attribute values.
///
/// New in jet_office; Quds interpolates doubles directly, which prints
/// `12.0` on the VM and `12` in the browser.
library;

/// Formats [value] as the one text both platforms agree on: the shortest
/// text that parses back to [value], with no `.0` on a whole number.
///
/// A whole value prints as an integer (`12`, `-3`, `123456789012345680000`;
/// negative zero prints `0`). Anything else uses `double.toString`, which the
/// VM and dart2js render identically for the shortest digits: a fraction as
/// `0.1`, and a magnitude of 1e21 or more or below 1e-6 as one normalized
/// exponent form, `1.5e+21` or `1e-7` (lower-case `e`, a sign on a positive
/// exponent, no padding). Excel reads that form in an `xsd:double`.
///
/// Used for XML attributes and for the cell encoder's `<v>` (ruling R9).
///
/// Throws [ArgumentError] when [value] is NaN or infinite.
String formatXmlDouble(double value) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, 'value', 'Must be finite.');
  }
  if (value == 0) return '0'; // Also negative zero.
  final String text = value.toString();
  // The VM spells a whole double `5.0` below 1e21; the web spells it `5`.
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// [value] as [formatXmlDouble] prints it, or as `NaN`, `Infinity` or
/// `-Infinity` when it is not finite, for a `toString` that must not throw
/// on a value the writer has not validated yet.
String describeDouble(double value) =>
    value.isFinite ? formatXmlDouble(value) : '$value';
