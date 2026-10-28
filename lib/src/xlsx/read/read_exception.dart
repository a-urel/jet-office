/// The exception the XLSX reader throws for a file it cannot read at all.
library;

import '../../xml/xml_pull_reader.dart' show isUnsafeInMessage;

/// Why an [XlsxReadException] was thrown.
enum XlsxReadFailure {
  /// The bytes are not a ZIP archive.
  notZip,

  /// The ZIP archive is damaged: bad structure, size or CRC, or an entry
  /// that cannot be inflated.
  corruptZip,

  /// The file is an encrypted (password protected) Office file.
  encrypted,

  /// The file is a legacy binary `.xls` workbook.
  legacyXls,

  /// The package is a format the reader does not read: Strict OOXML or a
  /// binary `.xlsb` workbook.
  unsupportedFormat,

  /// The package has no workbook part.
  missingWorkbook,

  /// An XML part is not well-formed, has a `DOCTYPE` or is not UTF-8.
  malformedXml,

  /// A limit of `XlsxReadLimits` was exceeded.
  limitExceeded,
}

/// Thrown when a file cannot be read at all.
///
/// A problem with one cell or sheet is a warning, not this exception. The
/// bytes come from outside the program, so this is a data problem.
final class XlsxReadException implements Exception {
  /// Creates an exception of [reason], described by [message], about the
  /// package part [part] (`null` when it concerns the file as a whole).
  ///
  /// [part] is shortened and cleaned for display, see [part].
  XlsxReadException(this.reason, this.message, {String? part})
    : part = part == null ? null : _displayPart(part);

  /// The category of the failure.
  final XlsxReadFailure reason;

  /// The package part the failure concerns, or `null`.
  ///
  /// This is for display only. An entry name comes from the file, so it is
  /// cut to 256 UTF-16 code units (a surrogate pair is never split) followed
  /// by `…`, and control characters, line and paragraph separators and
  /// bidirectional controls are replaced by U+FFFD. It may therefore differ
  /// from the ZIP entry name; the reader never looks it up again.
  final String? part;

  /// An English description for developers and logs. For
  /// [XlsxReadFailure.limitExceeded] it names the limit.
  ///
  /// Text taken from the file (an element name, an entity, a declared
  /// encoding) is quoted as at most 32 characters followed by `…`, with
  /// control characters replaced by U+FFFD, so the message stays short and
  /// on one line whatever the file holds. [part] is not repeated in it.
  final String message;

  @override
  String toString() =>
      'XlsxReadException(${reason.name}'
      '${part == null ? '' : ', $part'}): $message';
}

/// The most UTF-16 code units of a part name an exception keeps.
const int _partLength = 256;

/// [name] cut to [_partLength] code units plus `…` and made safe to print.
String _displayPart(String name) {
  int end = name.length;
  bool cut = false;
  if (end > _partLength) {
    end = _partLength;
    final int last = name.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    cut = true;
  }
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < end; i++) {
    final int ch = name.codeUnitAt(i);
    out.writeCharCode(isUnsafeInMessage(ch) ? 0xFFFD : ch);
  }
  if (cut) out.write('…');
  return out.toString();
}
