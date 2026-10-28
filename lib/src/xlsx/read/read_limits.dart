/// The limits that keep a hostile XLSX upload from exhausting memory.
library;

/// Limits applied while reading an XLSX file.
///
/// The defaults suit user uploads: a 100,000 row by 12 column sheet is about
/// 50 MB of XML, so [maxEntryBytes] leaves four times that. Exceeding a
/// limit throws an `XlsxReadException` of reason `limitExceeded` that names
/// the limit.
final class XlsxReadLimits {
  /// Creates limits; every value must be at least 1 (see [check]).
  const XlsxReadLimits({
    this.maxEntries = 10000,
    this.maxEntryBytes = 256 * 1024 * 1024,
    this.maxTotalBytes = 1024 * 1024 * 1024,
    this.maxCompressionRatio = 1000,
    this.maxSharedStrings = 2000000,
    this.maxDepth = 256,
    this.maxTextLength = 1048576,
    this.maxSheets = 10000,
    this.maxCellFormats = 1000000,
    this.maxMerges = 1000000,
  });

  /// The most entries the ZIP archive may hold.
  final int maxEntries;

  /// The most bytes one entry may declare uncompressed.
  final int maxEntryBytes;

  /// The most bytes all entries may declare uncompressed together.
  final int maxTotalBytes;

  /// The highest uncompressed-to-compressed ratio of a large entry.
  final int maxCompressionRatio;

  /// The most items a shared strings table may hold.
  final int maxSharedStrings;

  /// The deepest element nesting an XML part may have.
  final int maxDepth;

  /// The most characters one text value (a shared string, a `<v>` or an
  /// `<f>`) may have.
  final int maxTextLength;

  /// The most `<sheet>` entries a workbook may list.
  ///
  /// Each listed sheet costs memory when the reader opens, even one without
  /// a part, so a small workbook part could otherwise list millions.
  final int maxSheets;

  /// The most `<numFmt>` entries, and the most `<xf>` entries of
  /// `<cellXfs>`, a styles part may hold (each counted on its own).
  ///
  /// Every `<xf>` costs a table slot, so a small styles part could
  /// otherwise list millions.
  final int maxCellFormats;

  /// The most merged ranges one reader may hold in its cache, counted across
  /// every sheet whose merges it has read.
  ///
  /// The cache lives as long as the reader, so a small sheet part listing
  /// millions of `<mergeCell>`s could otherwise fill memory.
  final int maxMerges;

  /// Throws an [ArgumentError] naming the first field below 1.
  void check() {
    final Map<String, int> fields = <String, int>{
      'maxEntries': maxEntries,
      'maxEntryBytes': maxEntryBytes,
      'maxTotalBytes': maxTotalBytes,
      'maxCompressionRatio': maxCompressionRatio,
      'maxSharedStrings': maxSharedStrings,
      'maxDepth': maxDepth,
      'maxTextLength': maxTextLength,
      'maxSheets': maxSheets,
      'maxCellFormats': maxCellFormats,
      'maxMerges': maxMerges,
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
