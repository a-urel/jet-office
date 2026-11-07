/// The limits that keep a hostile DOCX upload from exhausting memory.
///
/// New in jet_office; not ported from Quds. The fields and defaults are
/// those of `XlsxReadLimits` that a document needs, so both formats refuse
/// the same archive the same way.
///
/// @docImport 'read_exception.dart';
library;

/// Limits applied while reading a DOCX file.
///
/// The defaults suit user uploads and are the XLSX reader's: a document
/// part may inflate to 256 MiB, the whole package to 1 GiB. Exceeding a
/// limit throws a [DocxReadException] of reason
/// [DocxReadFailure.limitExceeded] that names the limit; [check] throws an
/// [ArgumentError] for a limit below 1.
final class DocxReadLimits {
  /// Creates limits; every value must be at least 1 (see [check]).
  const DocxReadLimits({
    this.maxEntries = 10000,
    this.maxEntryBytes = 256 * 1024 * 1024,
    this.maxTotalBytes = 1024 * 1024 * 1024,
    this.maxCompressionRatio = 1000,
    this.maxDepth = 256,
    this.maxTextLength = 1048576,
  });

  /// The most entries the ZIP archive may hold.
  final int maxEntries;

  /// The most bytes one entry may declare uncompressed.
  final int maxEntryBytes;

  /// The most bytes all entries may declare uncompressed together.
  final int maxTotalBytes;

  /// The highest uncompressed-to-compressed ratio of an entry that declares
  /// more than 1 MiB uncompressed; smaller entries are not checked.
  final int maxCompressionRatio;

  /// The deepest element nesting an XML part may have.
  ///
  /// Raising it does not raise how deep tables may nest in the main document
  /// part: past `maxTableNesting` (256) a read fails as
  /// [DocxReadFailure.limitExceeded] whatever this value is.
  final int maxDepth;

  /// The most characters one text value of the document may have.
  final int maxTextLength;

  /// Throws an [ArgumentError] naming the first field below 1.
  void check() {
    final Map<String, int> fields = <String, int>{
      'maxEntries': maxEntries,
      'maxEntryBytes': maxEntryBytes,
      'maxTotalBytes': maxTotalBytes,
      'maxCompressionRatio': maxCompressionRatio,
      'maxDepth': maxDepth,
      'maxTextLength': maxTextLength,
    };
    for (final MapEntry<String, int> field in fields.entries) {
      if (field.value < 1) {
        throw ArgumentError.value(
          field.value,
          field.key,
          '${field.key} must be at least 1',
        );
      }
    }
  }
}
