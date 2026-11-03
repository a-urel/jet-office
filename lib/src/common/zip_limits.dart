/// The ZIP limits every format opens an untrusted file with.
///
/// Moved from `lib/src/xlsx/read/package_reader.dart`, where the reader
/// passed `XlsxReadLimits` fields to `ZipReader` itself; not ported from
/// Quds. Each format keeps its own limits class and builds a [ZipLimits]
/// from it.
library;

import 'dart:typed_data';

import '../zip/archive_adapter.dart';

/// The limits a [ZipReader] enforces on an archive.
///
/// `maxEntries` is the most entries the archive may hold, `maxEntryBytes`
/// the most bytes one entry may declare uncompressed, `maxTotalBytes` the
/// most all entries may declare together, and `maxCompressionRatio` the
/// highest uncompressed-to-compressed ratio of a large entry.
typedef ZipLimits = ({
  int maxEntries,
  int maxEntryBytes,
  int maxTotalBytes,
  int maxCompressionRatio,
});

/// Opens [bytes] as a ZIP archive within [limits].
///
/// Throws a [ZipReadError] when the bytes are not a readable archive or
/// exceed a limit; `mapZipError` turns it into a `ReadProblem`.
ZipReader openZip(Uint8List bytes, ZipLimits limits) => ZipReader(
  bytes,
  maxEntries: limits.maxEntries,
  maxEntryBytes: limits.maxEntryBytes,
  maxTotalBytes: limits.maxTotalBytes,
  maxCompressionRatio: limits.maxCompressionRatio,
);
