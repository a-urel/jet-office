/// Scrubbing and escaping of text that is written into XML.
///
/// Ported from quds_office_engine `lib/src/xml/xml_reader.dart` at commit
/// 15c5d29 (`encodeXmlText`, `encodeXmlAttribute`, `_escape`). What changed:
/// Quds let control characters and lone surrogates through, which produces
/// XML that Excel refuses to open. Here [scrubXmlText] removes every
/// character XML 1.0 forbids, the escape functions refuse text that was
/// not scrubbed first, and character data keeps a CR as `&#13;`. Entity
/// decoding (the reader half of the Quds file) is not ported.
library;

/// The result of [scrubXmlText].
final class ScrubResult {
  /// Creates a result holding the scrubbed [text] and the number of UTF-16
  /// code units [removed] from the input.
  const ScrubResult(this.text, this.removed);

  /// The input without forbidden characters. The very same string instance
  /// as the input when [removed] is zero.
  final String text;

  /// How many UTF-16 code units were removed.
  final int removed;
}

bool _isHigh(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

bool _isLow(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

bool _isForbiddenControl(int unit) =>
    (unit < 0x20 && unit != 0x09 && unit != 0x0A && unit != 0x0D) ||
    unit == 0xFFFE ||
    unit == 0xFFFF;

/// Removes the characters XML 1.0 cannot represent from [raw].
///
/// Removed are U+0000 to U+001F except tab, LF and CR, U+FFFE, U+FFFF, and
/// lone surrogates. A high surrogate is kept only when a low surrogate
/// follows it immediately, and a low surrogate only when a high one precedes
/// it. Returns the same string instance when nothing is removed.
ScrubResult scrubXmlText(String raw) {
  StringBuffer? buffer;
  int removed = 0;
  final int length = raw.length;
  for (int i = 0; i < length; i++) {
    final int unit = raw.codeUnitAt(i);
    if (_isHigh(unit) && i + 1 < length && _isLow(raw.codeUnitAt(i + 1))) {
      // A valid pair: keep both units.
      buffer?.writeCharCode(unit);
      buffer?.writeCharCode(raw.codeUnitAt(i + 1));
      i++;
      continue;
    }
    if (_isHigh(unit) || _isLow(unit) || _isForbiddenControl(unit)) {
      buffer ??= StringBuffer(raw.substring(0, i));
      removed++;
    } else {
      buffer?.writeCharCode(unit);
    }
  }
  if (buffer == null) {
    return ScrubResult(raw, 0);
  }
  return ScrubResult(buffer.toString(), removed);
}

/// Throws [ArgumentError] when [text] holds a character [scrubXmlText] would
/// remove. Callers must scrub first, so this is a programmer error.
void _requireScrubbed(String text) {
  if (scrubXmlText(text).removed != 0) {
    throw ArgumentError.value(
      text,
      'text',
      'Contains characters XML forbids; call scrubXmlText first.',
    );
  }
}

/// Escapes [text] for XML character data: `&`, `<` and `>`, plus CR as
/// `&#13;`, because every XML reader turns a literal CR (and CRLF) into LF.
///
/// [text] must already be scrubbed with [scrubXmlText]; otherwise this
/// throws [ArgumentError].
String escapeXmlText(String text) {
  _requireScrubbed(text);
  return _escape(text, attribute: false);
}

/// Escapes [text] for a double-quoted XML attribute: `&`, `<`, `>` and `"`,
/// plus tab, LF and CR as numeric references so they survive attribute value
/// normalisation.
///
/// [text] must already be scrubbed with [scrubXmlText]; otherwise this
/// throws [ArgumentError].
String escapeXmlAttribute(String text) {
  _requireScrubbed(text);
  return _escape(text, attribute: true);
}

/// An `_` that starts an `_xHHHH_` sequence (four hex digits).
final RegExp _xstringStart = RegExp(r'_(?=x[0-9A-Fa-f]{4}_)');

/// Protects [text] from ST_Xstring decoding.
///
/// Excel and LibreOffice read `_xHHHH_` in cell text and sheet names as the character
/// U+HHHH, so the text `_x0041_` would show as `A`. Every `_` that starts
/// such a sequence becomes `_x005F_` (the escape of `_` itself), which makes
/// a reader show the text as given: `_x0041_` is written `_x005F_x0041_`.
/// Overlapping sequences are covered too: `_x0041_x0042_` becomes
/// `_x005F_x0041_x005F_x0042_`.
///
/// Apply it to shared-string, cached formula text and sheet names when
/// writing, then [escapeXmlText] (or [escapeXmlAttribute] for a name). The result is longer than [text] when anything is
/// escaped; Excel's cell limit applies to the decoded text.
String escapeXstring(String text) =>
    text.contains('_x') ? text.replaceAll(_xstringStart, '_x005F_') : text;

String _escape(String text, {required bool attribute}) {
  StringBuffer? buffer;
  for (int i = 0; i < text.length; i++) {
    final int unit = text.codeUnitAt(i);
    final String? replacement = switch (unit) {
      0x26 => '&amp;',
      0x3C => '&lt;',
      0x3E => '&gt;',
      0x22 when attribute => '&quot;',
      0x09 when attribute => '&#9;',
      0x0A when attribute => '&#10;',
      0x0D => '&#13;',
      _ => null,
    };
    if (replacement != null) {
      buffer ??= StringBuffer(text.substring(0, i));
      buffer.write(replacement);
    } else {
      buffer?.writeCharCode(unit);
    }
  }
  return buffer?.toString() ?? text;
}
