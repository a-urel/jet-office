/// The pieces a formatted cell value is made of.
///
/// New in jet_office; Quds has no number format engine. A format code can
/// ask for space as wide as a character (`_)`) and for a character repeated
/// to fill the cell (`* `). Neither has a fixed width in plain text, so the
/// renderers return the result as parts: text, padding and fill, in the
/// order shown. Joined with each padding as one space and each fill left
/// out, the parts are the result's text.
library;

/// One piece of a formatted value: [XlsxFormatText], [XlsxFormatPadding]
/// or [XlsxFormatFill].
sealed class XlsxFormatPart {
  const XlsxFormatPart();
}

/// Text shown as it is.
///
/// Two text parts never stand next to each other in a result; they are
/// merged into one.
final class XlsxFormatText extends XlsxFormatPart {
  /// Creates a text part of [text].
  const XlsxFormatText(this.text);

  /// The text, never empty in a result.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is XlsxFormatText && other.text == text;

  @override
  int get hashCode => Object.hash(XlsxFormatText, text);

  @override
  String toString() => 'XlsxFormatText("$text")';
}

/// `_x` in a format code: a space as wide as [char].
///
/// A viewer that lays the cell out makes `_)` as wide as `)`, so positive
/// numbers line up with negatives in parentheses; plain text shows one
/// space.
final class XlsxFormatPadding extends XlsxFormatPart {
  /// Creates padding as wide as [char].
  const XlsxFormatPadding(this.char);

  /// The character whose width the space takes.
  final String char;

  @override
  bool operator ==(Object other) =>
      other is XlsxFormatPadding && other.char == char;

  @override
  int get hashCode => Object.hash(XlsxFormatPadding, char);

  @override
  String toString() => 'XlsxFormatPadding("$char")';
}

/// `*x` in a format code: [char] repeated, where the fill stands, until
/// the cell is full.
///
/// A result holds at most one. Plain text, which has no cell width, leaves
/// it out.
final class XlsxFormatFill extends XlsxFormatPart {
  /// Creates a fill of [char].
  const XlsxFormatFill(this.char);

  /// The character repeated.
  final String char;

  @override
  bool operator ==(Object other) =>
      other is XlsxFormatFill && other.char == char;

  @override
  int get hashCode => Object.hash(XlsxFormatFill, char);

  @override
  String toString() => 'XlsxFormatFill("$char")';
}
