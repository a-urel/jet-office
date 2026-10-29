/// The pieces a formatted cell value is made of.
///
/// New in jet_office; Quds has no number format engine. A format code can
/// ask for space as wide as a character (`_)`) and for a character repeated
/// to fill the cell (`* `). Neither has a fixed width in plain text, so the
/// renderers return the result as parts: text, padding and fill, in the
/// order shown. Joined with each padding as one space and each fill left
/// out, the parts are the result's text. [XlsxFormattedValue] holds both,
/// with the section's color and what Excel would show differently.
library;

import '../color.dart';
import '../warnings.dart';

/// A cell value as Excel shows it: what `XlsxNumberFormatter.format`
/// returns.
final class XlsxFormattedValue {
  /// Creates a result of [parts]; [text] is derived from them.
  XlsxFormattedValue(
    List<XlsxFormatPart> parts, {
    this.color,
    this.overflow = false,
    this.warning,
  }) : parts = List<XlsxFormatPart>.unmodifiable(parts),
       text = _join(parts);

  /// The text with each padding as one space and each fill left out: what
  /// a cell exactly as wide as its content shows.
  ///
  /// `#` when [overflow] is true.
  final String text;

  /// The pieces of [text] with padding and fill marked, for a viewer that
  /// lays the cell out. Unmodifiable.
  final List<XlsxFormatPart> parts;

  /// The section's color: [XlsxColor.rgb] for a named color such as
  /// `[Red]`, [XlsxColor.indexed] for `[ColorN]` (index N + 7), or null
  /// when the section has none.
  ///
  /// Resolving an index to RGB needs the workbook's palette; the default
  /// palette is right unless the file customises its indexed colors.
  final XlsxColor? color;

  /// Whether Excel shows `#` across the cell whatever its width, such as
  /// for a value no conditional section takes.
  final bool overflow;

  /// Why the result may differ from Excel, or null when the engine knows
  /// of no reason.
  final XlsxWarningCode? warning;

  static String _join(List<XlsxFormatPart> parts) {
    final StringBuffer out = StringBuffer();
    for (final XlsxFormatPart part in parts) {
      switch (part) {
        case XlsxFormatText(:final String text):
          out.write(text);
        case XlsxFormatPadding():
          out.write(' ');
        case XlsxFormatFill():
          break;
      }
    }
    return out.toString();
  }

  @override
  bool operator ==(Object other) {
    if (other is! XlsxFormattedValue ||
        other.text != text ||
        other.color != color ||
        other.overflow != overflow ||
        other.warning != warning ||
        other.parts.length != parts.length) {
      return false;
    }
    for (int i = 0; i < parts.length; i++) {
      if (other.parts[i] != parts[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(parts), color, overflow, warning);

  @override
  String toString() {
    final StringBuffer out = StringBuffer('XlsxFormattedValue("$text"');
    if (parts.any((XlsxFormatPart p) => p is! XlsxFormatText)) {
      out.write(', parts: $parts');
    }
    if (color != null) out.write(', color: $color');
    if (overflow) out.write(', overflow: true');
    if (warning != null) out.write(', warning: $warning');
    out.write(')');
    return out.toString();
  }
}

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
