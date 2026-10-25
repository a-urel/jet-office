/// [XlsxHeaderFooter], the text printed in the top and bottom margins of a
/// sheet, its checks and its `headerFooter` XML.
///
/// Ported from quds_office_engine `lib/src/sheet/serial/sheet_serial.dart` at commit 15c5d29.
/// Only the `&L`/`&C`/`&R` section idea of Quds' `_applyHeaderFooterSection`
/// is kept, and that is a reader. Quds wrote section text raw, so a literal
/// `&` was read as a field code and `R&D` printed the date;
/// `XlsxHeaderFooter.literal` doubles it. The value type describes
/// SpreadsheetML (six texts and four flags), not the writer; the writer
/// checks it when it is registered.
library;

import '../xml/xml_escape.dart';
import '../xml/xml_writer.dart';
import 'limits.dart';

/// The headers and footers of a printed sheet (`CT_HeaderFooter`): odd or
/// all pages, even pages and the first page.
///
/// A text is written as given, so it holds Excel's section and field codes:
/// `&L`, `&C` and `&R` start the left, center and right section, `&P` is the
/// page number, `&N` the page count, `&D` the date, `&T` the time, `&A` the
/// sheet name, `&F` the file name and `&Z` its path; `&&` is a literal `&`.
/// Build one with [sections], the code constants and [literal]. A text of
/// plain words is in the center section.
///
/// [differentOddEven] and [differentFirst] say whether even pages and the
/// first page have texts of their own. `null` derives them: on when any even
/// (or first) text is set. An explicit `true` writes the flag even without
/// such a text; an explicit `false` leaves the texts unused.
///
/// The `const` constructor cannot check its fields; the writer does when the
/// value is registered and throws [ArgumentError] naming the field: a text
/// is at most [XlsxLimits.maxHeaderFooterLength] UTF-16 code units, holds no
/// character XML forbids and does not end in a lone `&` (an odd run of `&`
/// at the very end, which Excel cannot read).
final class XlsxHeaderFooter {
  /// Headers and footers with the given texts; absent ones print nothing.
  const XlsxHeaderFooter({
    this.oddHeader,
    this.oddFooter,
    this.evenHeader,
    this.evenFooter,
    this.firstHeader,
    this.firstFooter,
    this.differentOddEven,
    this.differentFirst,
    this.scaleWithDocument = true,
    this.alignWithMargins = true,
  });

  /// The code for the page number (`&P`).
  static const String pageNumber = '&P';

  /// The code for the number of pages (`&N`).
  static const String pageCount = '&N';

  /// The code for the current date (`&D`).
  static const String date = '&D';

  /// The code for the current time (`&T`).
  static const String time = '&T';

  /// The code for the sheet name (`&A`).
  static const String sheetName = '&A';

  /// The code for the file name (`&F`).
  static const String fileName = '&F';

  /// The code for the file path (`&Z`).
  static const String filePath = '&Z';

  /// Joins the three sections of a header or footer: `&L` [left], `&C`
  /// [center] and `&R` [right], leaving out the absent ones.
  ///
  /// The section texts are used as given; pass user text through [literal].
  static String sections({String? left, String? center, String? right}) =>
      '${left == null ? '' : '&L$left'}'
      '${center == null ? '' : '&C$center'}'
      '${right == null ? '' : '&R$right'}';

  /// Escapes [text] so that it prints as written: every `&` is doubled, so
  /// `R&D` is not read as `R` and the date code.
  static String literal(String text) => text.replaceAll('&', '&&');

  /// The header of odd pages, or of every page without [differentOddEven].
  final String? oddHeader;

  /// The footer of odd pages, or of every page without [differentOddEven].
  final String? oddFooter;

  /// The header of even pages.
  final String? evenHeader;

  /// The footer of even pages.
  final String? evenFooter;

  /// The header of the first page.
  final String? firstHeader;

  /// The footer of the first page.
  final String? firstFooter;

  /// Whether even pages have their own texts; `null` is on when
  /// [evenHeader] or [evenFooter] is set.
  final bool? differentOddEven;

  /// Whether the first page has its own texts; `null` is on when
  /// [firstHeader] or [firstFooter] is set.
  final bool? differentFirst;

  /// Whether the text scales with the sheet's print scale (XML
  /// `scaleWithDoc`, on by default).
  final bool scaleWithDocument;

  /// Whether the text lines up with the page margins (XML
  /// `alignWithMargins`, on by default).
  final bool alignWithMargins;

  @override
  bool operator ==(Object other) =>
      other is XlsxHeaderFooter &&
      other.oddHeader == oddHeader &&
      other.oddFooter == oddFooter &&
      other.evenHeader == evenHeader &&
      other.evenFooter == evenFooter &&
      other.firstHeader == firstHeader &&
      other.firstFooter == firstFooter &&
      other.differentOddEven == differentOddEven &&
      other.differentFirst == differentFirst &&
      other.scaleWithDocument == scaleWithDocument &&
      other.alignWithMargins == alignWithMargins;

  @override
  int get hashCode => Object.hash(
    oddHeader,
    oddFooter,
    evenHeader,
    evenFooter,
    firstHeader,
    firstFooter,
    differentOddEven,
    differentFirst,
    scaleWithDocument,
    alignWithMargins,
  );

  @override
  String toString() =>
      'XlsxHeaderFooter(oddHeader: $oddHeader, oddFooter: $oddFooter, '
      'evenHeader: $evenHeader, evenFooter: $evenFooter, '
      'firstHeader: $firstHeader, firstFooter: $firstFooter, '
      'differentOddEven: $differentOddEven, differentFirst: $differentFirst, '
      'scaleWithDocument: $scaleWithDocument, '
      'alignWithMargins: $alignWithMargins)';
}

/// Checks [headerFooter] before it is recorded.
///
/// Throws [ArgumentError] naming the first bad text field: longer than
/// [XlsxLimits.maxHeaderFooterLength], holding a character XML forbids or
/// ending in a lone `&`.
void checkHeaderFooter(XlsxHeaderFooter headerFooter) {
  _checkText(headerFooter.oddHeader, 'oddHeader');
  _checkText(headerFooter.oddFooter, 'oddFooter');
  _checkText(headerFooter.evenHeader, 'evenHeader');
  _checkText(headerFooter.evenFooter, 'evenFooter');
  _checkText(headerFooter.firstHeader, 'firstHeader');
  _checkText(headerFooter.firstFooter, 'firstFooter');
}

void _checkText(String? text, String name) {
  if (text == null) return;
  if (text.length > XlsxLimits.maxHeaderFooterLength) {
    throw ArgumentError.value(
      '${text.length} characters',
      name,
      'A header or footer has at most '
          '${XlsxLimits.maxHeaderFooterLength} characters.',
    );
  }
  if (scrubXmlText(text).removed > 0) {
    throw ArgumentError.value(
      text,
      name,
      'A header or footer must not contain characters XML forbids.',
    );
  }
  int run = 0;
  for (int i = text.length - 1; i >= 0 && text.codeUnitAt(i) == 0x26; i--) {
    run++;
  }
  if (run.isOdd) {
    throw ArgumentError.value(
      text,
      name,
      'A header or footer must not end in a lone "&"; use '
      'XlsxHeaderFooter.literal for text.',
    );
  }
}

/// Writes `headerFooter` for [headerFooter], or nothing when it has no text
/// and no flag that differs from the defaults.
///
/// Attributes and children follow `CT_HeaderFooter`. The flags
/// `differentOddEven` and `differentFirst` are written as `1` when they are
/// on (explicitly, or derived from the even and first texts); `false` is the
/// schema default and is not written. `scaleWithDoc` and `alignWithMargins`
/// are written only as `0`.
void writeHeaderFooter(XmlWriter w, XlsxHeaderFooter headerFooter) {
  final bool oddEven =
      headerFooter.differentOddEven ??
      (headerFooter.evenHeader != null || headerFooter.evenFooter != null);
  final bool first =
      headerFooter.differentFirst ??
      (headerFooter.firstHeader != null || headerFooter.firstFooter != null);
  final List<(String, String?)> texts = <(String, String?)>[
    ('oddHeader', headerFooter.oddHeader),
    ('oddFooter', headerFooter.oddFooter),
    ('evenHeader', headerFooter.evenHeader),
    ('evenFooter', headerFooter.evenFooter),
    ('firstHeader', headerFooter.firstHeader),
    ('firstFooter', headerFooter.firstFooter),
  ];
  final bool hasText = texts.any(((String, String?) t) => t.$2 != null);
  if (!hasText &&
      !oddEven &&
      !first &&
      headerFooter.scaleWithDocument &&
      headerFooter.alignWithMargins) {
    return;
  }
  w.start('headerFooter');
  if (oddEven) w.attribute('differentOddEven', '1');
  if (first) w.attribute('differentFirst', '1');
  if (!headerFooter.scaleWithDocument) w.attribute('scaleWithDoc', '0');
  if (!headerFooter.alignWithMargins) w.attribute('alignWithMargins', '0');
  for (final (String, String?) t in texts) {
    final String? text = t.$2;
    if (text == null) continue;
    w.start(t.$1);
    w.text(escapeXstring(text));
    w.end();
  }
  w.end();
}
