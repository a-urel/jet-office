/// [XlsxHyperlink], a cell value that links somewhere, and the checks and
/// URI encoding the writer applies to it.
///
/// New in jet_office. Quds had no hyperlink support: a URL was plain text.
/// A link is a cell value like a string; the cell shows [XlsxHyperlink.text]
/// and Excel follows the link when it is clicked.
library;

import 'dart:convert';

import '../xml/xml_escape.dart';
import 'formula_text.dart';
import 'limits.dart';
import 'range.dart';

/// A cell that links to a web address, an e-mail, a place in the workbook or
/// a defined name.
///
/// Use it as a cell value, bare or inside an `XlsxCell` to style it: the
/// cell holds [text] as a string, and the sheet gets a `hyperlink` for it.
/// Unless the cell, its row or its column sets a font field, the text is
/// shown the way Excel shows a link, in the theme's hyperlink color
/// (theme color 10) and underlined; a field those styles set wins, so a red
/// font stays red and `XlsxFont(underline: XlsxUnderline.none)` removes the
/// line.
///
/// A link is external when it has an [address] and internal when it has a
/// [location]; with both, it opens the external file at that place. Build
/// one with a factory, or with the constructor for any link the XML can
/// hold. Neither validates (the factories derive text); the writer checks
/// the link when the cell is written and throws [ArgumentError] for a link
/// with neither an address nor a location, an empty or too long address,
/// an empty location, a [tooltip] of more than
/// [XlsxLimits.maxScreenTipLength] code units, or text in any field that
/// XML forbids, and [XlsxLimitError] for a sheet's 65,531st link.
final class XlsxHyperlink {
  /// A link with every field given, as a reader builds it from a parsed
  /// file: [address] an external target, [location] a place (in this
  /// workbook, or in the target when both are set), or both.
  ///
  /// [address] is written as given, so it must already be a valid URI;
  /// [XlsxHyperlink.url] percent-encodes one. Nothing is checked here: the
  /// writer checks the link when the cell is written, and throws
  /// [ArgumentError] when neither [address] nor [location] is set.
  const XlsxHyperlink({
    this.address,
    this.location,
    required this.text,
    this.tooltip,
  });

  /// A link to a web address (or any other URL).
  ///
  /// [url] is percent-encoded with [encodeUriText] (a space becomes `%20`,
  /// an existing `%20` stays, a `%` that starts no escape becomes `%25`) to
  /// make the [address]. [text], the cell's
  /// text, defaults to [url] as given. [tooltip] is the text Excel shows on
  /// hover.
  factory XlsxHyperlink.url(String url, {String? text, String? tooltip}) =>
      XlsxHyperlink(
        address: encodeUriText(url),
        text: text ?? url,
        tooltip: tooltip,
      );

  /// A link that starts a new e-mail to [address].
  ///
  /// The [XlsxHyperlink.address] is `mailto:<address>` with the address
  /// percent-encoded by [encodeUriText] (which keeps the `@`), followed by
  /// `?subject=` and the [subject] percent-encoded as a URI component when
  /// a subject is given: `&`, `=`, `?`, `#` and spaces are encoded, so
  /// `Q&A` stays one subject. [text] defaults to the bare [address].
  factory XlsxHyperlink.email(
    String address, {
    String? subject,
    String? text,
    String? tooltip,
  }) => XlsxHyperlink(
    address:
        'mailto:${encodeUriText(address)}'
        '${subject == null ? '' : '?subject=${Uri.encodeComponent(subject)}'}',
    text: text ?? address,
    tooltip: tooltip,
  );

  /// A link to a place in this workbook: [location] is a reference such as
  /// `Sheet2!A1` (quote a sheet name that needs it) or a defined name.
  /// [text] defaults to [location].
  factory XlsxHyperlink.location(
    String location, {
    String? text,
    String? tooltip,
  }) => XlsxHyperlink(
    location: location,
    text: text ?? location,
    tooltip: tooltip,
  );

  /// A link to the sheet named [sheetName], to [range] or to `A1`.
  ///
  /// The [location] is `'<name>'!<range>`, always quoted. [sheetName] must
  /// be the name the sheet has in the file: the writer renames a name
  /// Excel does not accept, and a link to the name as asked for then finds
  /// no sheet. [text] defaults to [sheetName].
  factory XlsxHyperlink.sheet(
    String sheetName, {
    XlsxRange? range,
    String? text,
    String? tooltip,
  }) => XlsxHyperlink(
    location: quotedSheetRef(sheetName, range?.ref ?? 'A1'),
    text: text ?? sheetName,
    tooltip: tooltip,
  );

  /// The external target, already percent-encoded, or `null` for a link
  /// inside the workbook.
  final String? address;

  /// The place the link goes to: in this workbook, or in the [address]'s
  /// file when both are set; `null` for a link to the target as a whole.
  final String? location;

  /// The text the cell shows.
  final String text;

  /// The text Excel shows when the pointer rests on the cell, or `null`.
  final String? tooltip;

  @override
  bool operator ==(Object other) =>
      other is XlsxHyperlink &&
      other.address == address &&
      other.location == location &&
      other.text == text &&
      other.tooltip == tooltip;

  @override
  int get hashCode => Object.hash(address, location, text, tooltip);

  @override
  String toString() =>
      'XlsxHyperlink(address: $address, location: $location, text: $text, '
      'tooltip: $tooltip)';
}

/// The characters [encodeUriText] leaves as they are: the unreserved and
/// reserved characters of RFC 3986. A `%` is kept only when it starts an
/// existing escape.
final Set<int> _uriKept = <int>{
  for (final int c in "-._~:/?#[]@!\$&'()*+,;=".codeUnits) c,
  for (int c = 0x30; c <= 0x39; c++) c,
  for (int c = 0x41; c <= 0x5A; c++) c,
  for (int c = 0x61; c <= 0x7A; c++) c,
};

const int _percent = 0x25;

bool _isHexDigit(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x46) ||
    (c >= 0x61 && c <= 0x66);

/// Whether the `%` at [i] in [bytes] starts an escape: two hex digits
/// follow it.
bool _startsEscape(List<int> bytes, int i) =>
    i + 2 < bytes.length &&
    _isHexDigit(bytes[i + 1]) &&
    _isHexDigit(bytes[i + 2]);

/// Percent-encodes [text] for use as a URI, as uppercase `%XX` of its UTF-8
/// bytes, every character outside `A-Z a-z 0-9` and
/// `` - . _ ~ : / ? # [ ] @ ! $ & ' ( ) * + , ; = ``.
///
/// A `%` followed by two hex digits is an existing escape and is kept as it
/// is, so text that is already encoded is not encoded twice (`a%20b` stays,
/// in either case of hex digit). Any other `%` is encoded as `%25`:
/// `100% done` becomes `100%25%20done`, `%zz` becomes `%25zz` and a
/// trailing `%` becomes `%25`.
String encodeUriText(String text) {
  StringBuffer? out;
  final List<int> bytes = utf8.encode(text);
  for (int i = 0; i < bytes.length; i++) {
    final int b = bytes[i];
    if (_uriKept.contains(b) || (b == _percent && _startsEscape(bytes, i))) {
      out?.writeCharCode(b);
      continue;
    }
    // Start the buffer at the first character that needs encoding.
    out ??= StringBuffer(utf8.decode(bytes.sublist(0, i)));
    out
      ..write('%')
      ..write(b.toRadixString(16).toUpperCase().padLeft(2, '0'));
  }
  return out?.toString() ?? text;
}

/// Throws [ArgumentError] unless [link] can be written.
///
/// The fields are named as the error reports them: `address`, `location`,
/// `text` and `tooltip`. The address is checked as it is written, after
/// encoding. Every field must hold no character XML forbids, because the
/// text is written into attributes where such a character cannot be
/// removed without changing what the link says.
void checkHyperlink(XlsxHyperlink link) {
  final String? address = link.address;
  final String? location = link.location;
  if (address != null) {
    if (address.isEmpty) {
      throw ArgumentError.value(address, 'address', 'Must not be empty.');
    }
    if (address.length > XlsxLimits.maxHyperlinkAddressLength) {
      throw ArgumentError.value(
        '${address.length} characters',
        'address',
        'A hyperlink address has at most '
            '${XlsxLimits.maxHyperlinkAddressLength} characters.',
      );
    }
    _checkClean(address, 'address');
  }
  if (location != null) {
    if (location.isEmpty) {
      throw ArgumentError.value(location, 'location', 'Must not be empty.');
    }
    _checkClean(location, 'location');
  }
  if (address == null && location == null) {
    throw ArgumentError.value(
      address,
      'address',
      'A hyperlink needs an address, a location or both.',
    );
  }
  _checkClean(link.text, 'text');
  final String? tooltip = link.tooltip;
  if (tooltip != null) {
    if (tooltip.length > XlsxLimits.maxScreenTipLength) {
      throw ArgumentError.value(
        '${tooltip.length} characters',
        'tooltip',
        'A tooltip has at most ${XlsxLimits.maxScreenTipLength} characters.',
      );
    }
    _checkClean(tooltip, 'tooltip');
  }
}

void _checkClean(String value, String field) {
  if (scrubXmlText(value).removed > 0) {
    throw ArgumentError.value(
      value,
      field,
      'Must not contain characters XML forbids.',
    );
  }
}
