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
/// [location]. Build one with a factory. The factories derive text but do
/// not validate; the writer checks the link when the cell is written and
/// throws [ArgumentError] for an empty or too long address, an empty
/// location, a [tooltip] of more than [XlsxLimits.maxScreenTipLength] code
/// units, or text in any field that XML forbids, and
/// [XlsxLimitError] for a sheet's 65,531st link.
final class XlsxHyperlink {
  const XlsxHyperlink._({
    this.address,
    this.location,
    required this.text,
    this.tooltip,
  });

  /// A link to a web address (or any other URL).
  ///
  /// [url] is percent-encoded with [encodeUriText] (a space becomes `%20`,
  /// an existing `%20` stays) to make the [address]. [text], the cell's
  /// text, defaults to [url] as given. [tooltip] is the text Excel shows on
  /// hover.
  factory XlsxHyperlink.url(String url, {String? text, String? tooltip}) =>
      XlsxHyperlink._(
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
  }) => XlsxHyperlink._(
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
  }) => XlsxHyperlink._(
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
  }) => XlsxHyperlink._(
    location: quotedSheetRef(sheetName, range?.ref ?? 'A1'),
    text: text ?? sheetName,
    tooltip: tooltip,
  );

  /// The external target, already percent-encoded, or `null` for a link
  /// inside the workbook.
  final String? address;

  /// The place in the workbook the link goes to, or `null` for an external
  /// link.
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
/// reserved characters of RFC 3986 and the `%` of an existing escape.
final Set<int> _uriKept = <int>{
  for (final int c in "-._~:/?#[]@!\$&'()*+,;=%".codeUnits) c,
  for (int c = 0x30; c <= 0x39; c++) c,
  for (int c = 0x41; c <= 0x5A; c++) c,
  for (int c = 0x61; c <= 0x7A; c++) c,
};

/// Percent-encodes [text] for use as a URI, as uppercase `%XX` of its UTF-8
/// bytes, every character outside `A-Z a-z 0-9` and
/// `` - . _ ~ : / ? # [ ] @ ! $ & ' ( ) * + , ; = % ``.
///
/// The `%` is kept, so text that is already encoded is not encoded twice;
/// a bare `%` is the caller's mistake.
String encodeUriText(String text) {
  StringBuffer? out;
  final List<int> bytes = utf8.encode(text);
  for (int i = 0; i < bytes.length; i++) {
    final int b = bytes[i];
    if (_uriKept.contains(b)) {
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
    throw ArgumentError('A hyperlink needs an address or a location.');
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
