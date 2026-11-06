/// The pieces a formatted cell value is made of.
///
/// Moved from jet_office's lib/src/xlsx/format/ at commit 632115d; written
/// there, not ported from Quds.
///
/// A format code can
/// ask for space as wide as a character (`_)`) and for a character repeated
/// to fill the cell (`* `). Neither has a fixed width in plain text, so the
/// renderers return the result as parts: text, padding and fill, in the
/// order shown. Joined with each padding as one space and each fill left
/// out, the parts are the result's text. [FormattedValue] holds both,
/// with the section's color and what Excel would show differently.
library;

import 'format_code.dart';

/// Why a [FormattedValue] may differ from what Excel shows.
///
/// A result carries at most one.
enum FormatWarning {
  /// The formatter cannot read the number format code (an unterminated
  /// quote or bracket, more than four sections, more than two conditions,
  /// two conditions in one section, a condition without a number, a
  /// `[ColorN]` with N outside 1 to 56, more than 255 characters) or the
  /// code would add more than 1,000 characters to the value. The value
  /// shows with the General format.
  invalidCode,

  /// The code asks for a calendar other than the Gregorian (`B2`, a locale
  /// tag's calendar), a numeral system (`[DBNum1]`, `[NatNum1]`, a locale
  /// tag's numeral system), a language no format locale serves (`[$-40C]`
  /// in a date) or another bracket the formatter does not render. The value
  /// shows with Gregorian dates, Western digits and the default language.
  unsupported,

  /// The value uses a built-in number format whose code depends on the
  /// locale (ids 23 to 36 and 50 to 163) and the caller gives no code for
  /// it. The value shows with the closest built-in format: the format
  /// locale's short date (id 14) for ids 27 to 31, 36 and 50 to 58, its
  /// time (id 21) for ids 32 to 35, and the General format for the others.
  localeDependent,

  /// The value uses a number format id whose code the caller does not give
  /// and the formatter cannot know, such as an id of 164 and up. The value
  /// shows with the General format.
  unresolved,
}

/// A cell value as Excel shows it: what `NumberFormatter.format`
/// returns.
final class FormattedValue {
  /// Creates a result of [parts]; [text] is derived from them.
  FormattedValue(
    List<FormatPart> parts, {
    this.color,
    this.overflow = false,
    this.warning,
  }) : parts = List<FormatPart>.unmodifiable(parts),
       text = _join(parts);

  /// The text with each padding as one space and each fill left out: what
  /// a cell exactly as wide as its content shows.
  ///
  /// `#` when [overflow] is true.
  final String text;

  /// The pieces of [text] with padding and fill marked, for a viewer that
  /// lays the cell out. Unmodifiable.
  final List<FormatPart> parts;

  /// The section's color: a [FormatColor] with [FormatColor.rgb] for a named
  /// color such as `[Red]`, with [FormatColor.index] for `[ColorN]` (index
  /// N + 7), or null when the section has none.
  ///
  /// Resolving an index to RGB needs the file's palette; the default palette
  /// is right unless the file customises its indexed colors.
  final FormatColor? color;

  /// Whether Excel shows `#` across the cell whatever its width, such as
  /// for a value no conditional section takes.
  final bool overflow;

  /// Why the result may differ from Excel, or null when the engine knows
  /// of no reason.
  final FormatWarning? warning;

  static String _join(List<FormatPart> parts) {
    final StringBuffer out = StringBuffer();
    for (final FormatPart part in parts) {
      switch (part) {
        case FormatText(:final String text):
          out.write(text);
        case FormatPadding():
          out.write(' ');
        case FormatFill():
          break;
      }
    }
    return out.toString();
  }

  @override
  bool operator ==(Object other) {
    if (other is! FormattedValue ||
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
    final StringBuffer out = StringBuffer('FormattedValue("$text"');
    if (parts.any((FormatPart p) => p is! FormatText)) {
      out.write(', parts: $parts');
    }
    if (color != null) out.write(', color: $color');
    if (overflow) out.write(', overflow: true');
    if (warning != null) out.write(', warning: $warning');
    out.write(')');
    return out.toString();
  }
}

/// One piece of a formatted value: [FormatText], [FormatPadding]
/// or [FormatFill].
sealed class FormatPart {
  const FormatPart();
}

/// Text shown as it is.
///
/// Two text parts never stand next to each other in a result; they are
/// merged into one.
final class FormatText extends FormatPart {
  /// Creates a text part of [text].
  const FormatText(this.text);

  /// The text, never empty in a result.
  final String text;

  @override
  bool operator ==(Object other) => other is FormatText && other.text == text;

  @override
  int get hashCode => Object.hash(FormatText, text);

  @override
  String toString() => 'FormatText("$text")';
}

/// `_x` in a format code: a space as wide as [char].
///
/// A viewer that lays the cell out makes `_)` as wide as `)`, so positive
/// numbers line up with negatives in parentheses; plain text shows one
/// space.
final class FormatPadding extends FormatPart {
  /// Creates padding as wide as [char].
  const FormatPadding(this.char);

  /// The character whose width the space takes.
  final String char;

  @override
  bool operator ==(Object other) =>
      other is FormatPadding && other.char == char;

  @override
  int get hashCode => Object.hash(FormatPadding, char);

  @override
  String toString() => 'FormatPadding("$char")';
}

/// `*x` in a format code: [char] repeated, where the fill stands, until
/// the cell is full.
///
/// A result holds at most one. Plain text, which has no cell width, leaves
/// it out.
final class FormatFill extends FormatPart {
  /// Creates a fill of [char].
  const FormatFill(this.char);

  /// The character repeated.
  final String char;

  @override
  bool operator ==(Object other) => other is FormatFill && other.char == char;

  @override
  int get hashCode => Object.hash(FormatFill, char);

  @override
  String toString() => 'FormatFill("$char")';
}

/// The parts of a result as a renderer builds them, with adjacent text
/// merged and empty text left out.
///
/// Internal to the renderers; not exported.
final class FormatPartsBuilder {
  final List<FormatPart> _parts = <FormatPart>[];
  final StringBuffer _text = StringBuffer();

  /// Appends [text] to the current text part.
  void text(String text) => _text.write(text);

  /// Appends [part] after the current text.
  void add(FormatPart part) {
    _flush();
    _parts.add(part);
  }

  void _flush() {
    if (_text.isEmpty) return;
    _parts.add(FormatText(_text.toString()));
    _text.clear();
  }

  /// The parts, the last text included.
  List<FormatPart> get result {
    _flush();
    return _parts;
  }
}
