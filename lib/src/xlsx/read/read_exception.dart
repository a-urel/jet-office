/// The exception the XLSX reader throws for a file it cannot read at all.
library;

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
  const XlsxReadException(this.reason, this.message, {this.part});

  /// The category of the failure.
  final XlsxReadFailure reason;

  /// The package part the failure concerns, or `null`.
  final String? part;

  /// An English description for developers and logs. For
  /// [XlsxReadFailure.limitExceeded] it names the limit.
  final String message;

  @override
  String toString() =>
      'XlsxReadException(${reason.name}'
      '${part == null ? '' : ', $part'}): $message';
}
