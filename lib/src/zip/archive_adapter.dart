/// The single place where `package:archive` is used.
///
/// Writing: [ZipWriter] wraps [ZipEncoder] behind a small incremental writer
/// so the rest of the library never depends on the archive package. Entries
/// use a fixed 1980-01-01 00:00:00 timestamp and deflate level 6, so two
/// writes of the same parts produce identical bytes.
///
/// Reading: [ZipReader] opens an untrusted archive. It reads the central
/// directory without inflating anything and refuses, as a [ZipReadError],
/// what breaks the limits it is given (a ZIP bomb) or is not a readable ZIP.
/// Entries are inflated one at a time, never past their declared size, and
/// checked against their CRC-32.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';

/// The fixed modification time written into every ZIP entry.
final DateTime _fixedTime = DateTime(1980);

/// The deflate level used for every entry.
const int _deflateLevel = 6;

/// The smallest chunk handed to the sink while streaming.
const int _chunkSize = 64 * 1024;

/// Writes a ZIP archive one entry at a time.
///
/// Without a `sink` the archive is built in memory and returned by [close].
/// With a `sink`, bytes are forwarded to it in chunks of at least 64 KiB
/// (the last chunk may be smaller) as entries are added, and [close] closes
/// the sink and returns `null`.
///
/// When the sink throws, the writer closes it (ignoring a second error from
/// `close`), rethrows the original error and accepts no further calls; the
/// archive in the sink is then incomplete.
final class ZipWriter {
  /// Creates a writer, streaming to [sink] when one is given.
  ZipWriter({Sink<List<int>>? sink})
    : _output = sink == null ? OutputMemoryStream() : _SinkOutputStream(sink) {
    _encoder = ZipEncoder()
      ..startEncode(_output, level: _deflateLevel, modified: _fixedTime);
  }

  final OutputStream _output;
  late final ZipEncoder _encoder;
  bool _closed = false;

  Sink<List<int>>? get _sink {
    final OutputStream out = _output;
    return out is _SinkOutputStream ? out._sink : null;
  }

  /// Adds one entry named [name] holding [bytes].
  ///
  /// Throws a [StateError] after [close] or after an earlier failure, and
  /// rethrows what the sink throws.
  void add(String name, List<int> bytes) {
    if (_closed) {
      throw StateError('Cannot add "$name": the ZIP writer is closed.');
    }
    try {
      _encoder.add(ArchiveFile.bytes(name, bytes));
    } on Object {
      _abandon();
      rethrow;
    }
  }

  /// Adds one entry named [name] holding the concatenation of [chunks].
  ///
  /// The entry, and so the archive, is byte-identical to the one `add`
  /// produces for the concatenated bytes. The chunks are copied once, into
  /// a single buffer for the encoder; they are not concatenated twice.
  void addChunks(String name, List<Uint8List> chunks) {
    if (_closed) {
      throw StateError('Cannot add "$name": the ZIP writer is closed.');
    }
    int total = 0;
    for (final Uint8List chunk in chunks) {
      total += chunk.length;
    }
    final Uint8List joined = Uint8List(total);
    int offset = 0;
    for (final Uint8List chunk in chunks) {
      joined.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    add(name, joined);
  }

  /// Finishes the archive.
  ///
  /// Returns the archive bytes in memory mode, or `null` in sink mode after
  /// closing the sink. Throws a [StateError] when called twice or after an
  /// earlier failure, and rethrows what the sink throws.
  Uint8List? close() {
    if (_closed) {
      throw StateError('The ZIP writer is already closed.');
    }
    _closed = true;
    final OutputStream out = _output;
    try {
      _encoder.endEncode();
      if (out is _SinkOutputStream) out.finish();
    } on Object {
      _abandon();
      rethrow;
    }
    if (out is _SinkOutputStream) {
      _sink!.close();
      return null;
    }
    return out.getBytes();
  }

  /// After a failure: refuses further calls and closes the sink, ignoring
  /// an error from `close` so the caller sees the original one.
  void _abandon() {
    _closed = true;
    try {
      _sink?.close();
    } on Object {
      // The original error is the one worth reporting.
    }
  }
}

/// An [OutputStream] that forwards everything to a sink in large chunks.
///
/// [ZipEncoder] only appends to its output and reads [length], so random
/// access ([subset]) and [clear] are unsupported.
final class _SinkOutputStream extends OutputStream {
  _SinkOutputStream(this._sink) : super(byteOrder: ByteOrder.littleEndian);

  final Sink<List<int>> _sink;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  int _length = 0;

  @override
  int get length => _length;

  @override
  void clear() => throw UnsupportedError('A sink stream cannot be cleared.');

  @override
  Uint8List subset(int start, [int? end]) =>
      throw UnsupportedError('A sink stream cannot be read back.');

  @override
  void flush() {}

  @override
  void writeByte(int value) {
    _buffer.addByte(value & 0xff);
    _length++;
    _drain();
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final int n = length ?? bytes.length;
    // Copy: the caller may reuse its buffer after this call returns.
    _buffer.add(
      Uint8List.fromList(n == bytes.length ? bytes : bytes.sublist(0, n)),
    );
    _length += n;
    _drain();
  }

  @override
  void writeStream(InputStream stream) => writeBytes(stream.toUint8List());

  void _drain() {
    if (_buffer.length >= _chunkSize) {
      _sink.add(_buffer.takeBytes());
    }
  }

  /// Sends whatever is still buffered.
  void finish() {
    if (_buffer.isNotEmpty) {
      _sink.add(_buffer.takeBytes());
    }
  }
}

/// Why a [ZipReader] refused an archive or an entry.
enum ZipReadErrorKind {
  /// The bytes are not a ZIP archive.
  notZip,

  /// The archive is damaged: truncated, inconsistent, or an entry that does
  /// not inflate to its declared size and CRC-32.
  corrupt,

  /// The file is password protected: an OLE file holding an
  /// `EncryptedPackage`, or a ZIP entry flagged as encrypted.
  encrypted,

  /// The file is an OLE compound file, the legacy `.xls` format.
  legacyXls,

  /// The archive has more entries than allowed.
  tooManyEntries,

  /// An entry declares more uncompressed bytes than allowed.
  entryTooLarge,

  /// The declared uncompressed sizes add up to more than allowed.
  totalTooLarge,

  /// An entry declares too many uncompressed bytes per compressed byte.
  ratioTooHigh,

  /// Two entry names are equal once case and slashes are normalized.
  duplicateEntry,
}

/// A [ZipReader] refused an archive or one of its entries.
///
/// The bytes came from outside the program, so this is a data problem, not
/// a programmer error; the reader maps it to its public exception.
final class ZipReadError implements Exception {
  /// Creates an error of [kind] about [entry] (`null` for the whole
  /// archive), described by [message].
  const ZipReadError(this.kind, this.message, {this.entry});

  /// Why the archive or entry was refused.
  final ZipReadErrorKind kind;

  /// The entry name as stored in the archive, or `null` when the problem is
  /// the archive as a whole.
  final String? entry;

  /// An English description for developers and logs.
  final String message;

  @override
  String toString() =>
      'ZipReadError(${kind.name}'
      '${entry == null ? '' : ', $entry'}): $message';
}

/// The OLE compound file signature, shared by legacy `.xls` files and
/// encrypted Office files.
const List<int> _oleSignature = <int>[
  0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, //
];

/// The UTF-16LE stream name an encrypted Office file stores in its OLE
/// container.
final List<int> _encryptedPackage = <int>[
  for (final int unit in 'EncryptedPackage'.codeUnits) ...<int>[unit, 0],
];

/// The local file header signature, `PK\x03\x04`, which starts a ZIP.
const List<int> _zipSignature = <int>[0x50, 0x4B, 0x03, 0x04];

/// Entries declaring at most this many bytes skip the ratio check: a small
/// part may compress very well without being a threat.
const int _ratioThreshold = 1 << 20;

/// The ZIP compression method of a stored entry.
const int _methodStore = 0;

/// The ZIP compression method of a deflated entry.
const int _methodDeflate = 8;

/// Reads the entries of an untrusted ZIP archive within fixed limits.
///
/// The constructor reads the central directory only and refuses the archive
/// with a [ZipReadError] when, checked in this order: it is an OLE file
/// ([ZipReadErrorKind.encrypted] or [ZipReadErrorKind.legacyXls]); it is not
/// a ZIP or its directory is damaged; it has more than `maxEntries` entries
/// (directories included); an entry declares more than `maxEntryBytes`
/// uncompressed bytes; the declared sizes add up to more than
/// `maxTotalBytes`; an entry declaring more than 1 MiB declares more than
/// `maxCompressionRatio` bytes per compressed byte; two names are equal once
/// normalized; or an entry is flagged as encrypted.
///
/// Names are matched ignoring ASCII and Unicode case, with `\` read as `/`
/// and without a leading `/`.
final class ZipReader {
  /// Opens the archive [bytes] within the given limits.
  ///
  /// Throws a [ZipReadError] when the archive is refused. Nothing is
  /// inflated here; [read] inflates one entry.
  ZipReader(
    Uint8List bytes, {
    required int maxEntries,
    required int maxEntryBytes,
    required int maxTotalBytes,
    required int maxCompressionRatio,
  }) {
    if (_startsWith(bytes, _oleSignature)) {
      if (_indexOf(bytes, _encryptedPackage) >= 0) {
        throw const ZipReadError(
          ZipReadErrorKind.encrypted,
          'The file is an encrypted (password protected) Office file.',
        );
      }
      throw const ZipReadError(
        ZipReadErrorKind.legacyXls,
        'The file is an OLE compound file (legacy .xls), not a ZIP.',
      );
    }
    final List<ZipFileHeader> headers = _readDirectory(bytes);

    if (headers.length > maxEntries) {
      throw ZipReadError(
        ZipReadErrorKind.tooManyEntries,
        'The archive has ${headers.length} entries; at most $maxEntries '
        'are allowed.',
      );
    }
    for (final ZipFileHeader header in headers) {
      if (header.uncompressedSize > maxEntryBytes) {
        throw ZipReadError(
          ZipReadErrorKind.entryTooLarge,
          'The entry declares ${header.uncompressedSize} bytes; at most '
          '$maxEntryBytes are allowed.',
          entry: header.filename,
        );
      }
    }
    int total = 0;
    for (final ZipFileHeader header in headers) {
      total += header.uncompressedSize;
    }
    if (total > maxTotalBytes) {
      throw ZipReadError(
        ZipReadErrorKind.totalTooLarge,
        'The entries declare $total bytes in all; at most $maxTotalBytes '
        'are allowed.',
      );
    }
    for (final ZipFileHeader header in headers) {
      final int size = header.uncompressedSize;
      if (size > _ratioThreshold &&
          size > header.compressedSize * maxCompressionRatio) {
        throw ZipReadError(
          ZipReadErrorKind.ratioTooHigh,
          'The entry declares $size bytes from ${header.compressedSize} '
          'compressed bytes, more than $maxCompressionRatio to 1.',
          entry: header.filename,
        );
      }
    }
    final Set<String> seen = <String>{};
    for (final ZipFileHeader header in headers) {
      if (!seen.add(_key(header.filename))) {
        throw ZipReadError(
          ZipReadErrorKind.duplicateEntry,
          'Another entry has the same name once case and slashes are '
          'normalized.',
          entry: header.filename,
        );
      }
    }
    for (final ZipFileHeader header in headers) {
      final int localFlags = header.file?.flags ?? 0;
      if ((header.generalPurposeBitFlag | localFlags) & 1 != 0) {
        throw ZipReadError(
          ZipReadErrorKind.encrypted,
          'The entry is encrypted.',
          entry: header.filename,
        );
      }
    }
    for (final ZipFileHeader header in headers) {
      if (!header.filename.endsWith('/')) {
        _entries[_key(header.filename)] = header;
      }
    }
  }

  /// The file entries by normalized name; directories are left out.
  final Map<String, ZipFileHeader> _entries = <String, ZipFileHeader>{};

  /// The names of the file entries, in archive order, as stored except that
  /// `\` is turned into `/`. Directory entries are left out.
  Iterable<String> get names => _entries.values.map(
    (ZipFileHeader header) => header.filename.replaceAll(r'\', '/'),
  );

  /// Whether the archive has a file entry named [name], compared as the
  /// class documentation describes.
  bool contains(String name) => _entries.containsKey(_key(name));

  /// The uncompressed bytes of the entry named [name], in a new buffer the
  /// caller owns.
  ///
  /// Throws a [ZipReadError] of kind [ZipReadErrorKind.corrupt] when the
  /// entry inflates to more or fewer bytes than it declares, its CRC-32 does
  /// not match, or its data cannot be decoded. Inflation stops as soon as
  /// the declared size is passed. Throws a [StateError] when there is no
  /// such entry; check [contains] first.
  Uint8List read(String name) {
    final ZipFileHeader? header = _entries[_key(name)];
    if (header == null) {
      throw StateError('The archive has no entry "$name".');
    }
    final String entry = header.filename;
    final int size = header.uncompressedSize;
    final _BoundedOutputStream output;
    try {
      // Inside the try: whatever the sizes, only a ZipReadError escapes.
      output = _BoundedOutputStream(size, header.compressedSize, entry);
      final Uint8List raw = header.file?.getRawContent() ?? Uint8List(0);
      switch (header.compressionMethod) {
        case _methodStore:
          output.writeBytes(raw);
        case _methodDeflate:
          // Inflate writes straight into the bounded stream. The decoders
          // behind ZipFile.decompress may first inflate the whole entry
          // into a buffer of their own, which would defeat the bound.
          Inflate.stream(InputMemoryStream(raw), output: output);
        default:
          throw ZipReadError(
            ZipReadErrorKind.corrupt,
            'The entry uses compression method ${header.compressionMethod}; '
            'only stored and deflated entries are supported.',
            entry: entry,
          );
      }
    } on ArchiveException catch (e) {
      throw ZipReadError(
        ZipReadErrorKind.corrupt,
        'The entry cannot be decoded: ${e.message}',
        entry: entry,
      );
    } on RangeError {
      throw ZipReadError(
        ZipReadErrorKind.corrupt,
        'The entry data is truncated or malformed.',
        entry: entry,
      );
    }
    if (output.length != size) {
      throw ZipReadError(
        ZipReadErrorKind.corrupt,
        'The entry inflates to ${output.length} bytes but declares $size.',
        entry: entry,
      );
    }
    final Uint8List bytes = output.getBytes();
    if (getCrc32(bytes) != header.crc32) {
      throw ZipReadError(
        ZipReadErrorKind.corrupt,
        'The CRC-32 of the entry does not match the stored one.',
        entry: entry,
      );
    }
    return bytes;
  }

  /// [name] normalized for lookup: `\` read as `/`, no leading `/`, lower
  /// case.
  static String _key(String name) {
    String key = name.replaceAll(r'\', '/');
    while (key.startsWith('/')) {
      key = key.substring(1);
    }
    return key.toLowerCase();
  }

  /// The central directory headers of [bytes], each with its local file.
  ///
  /// Throws [ZipReadErrorKind.notZip] when [bytes] neither start like a ZIP
  /// nor end with a directory, and [ZipReadErrorKind.corrupt] when they
  /// start like one but the directory is missing, truncated or inconsistent,
  /// or an entry declares a size that does not fit a 64-bit signed int.
  static List<ZipFileHeader> _readDirectory(Uint8List bytes) {
    final bool looksLikeZip = _startsWith(bytes, _zipSignature);
    final ZipDirectory directory = ZipDirectory();
    try {
      directory.read(InputMemoryStream(bytes));
    } on ArchiveException {
      throw _damaged(looksLikeZip);
    } on RangeError {
      throw _damaged(looksLikeZip);
    }
    if (directory.filePosition < 0) throw _damaged(looksLikeZip);
    final List<ZipFileHeader> headers = directory.fileHeaders;
    if (headers.length != directory.totalCentralDirectoryEntries) {
      throw const ZipReadError(
        ZipReadErrorKind.corrupt,
        'The central directory is truncated: it lists fewer entries than '
        'it declares.',
      );
    }
    for (final ZipFileHeader header in headers) {
      // archive reads a Zip64 size with the top bit set as a negative int,
      // which would pass every limit and lower the declared total.
      if (header.uncompressedSize < 0 || header.compressedSize < 0) {
        throw ZipReadError(
          ZipReadErrorKind.corrupt,
          'The entry declares a size beyond 2^63 bytes.',
          entry: header.filename,
        );
      }
    }
    return headers;
  }

  /// The error for an archive whose directory cannot be read: corrupt when
  /// the file [looksLikeZip], otherwise not a ZIP at all.
  static ZipReadError _damaged(bool looksLikeZip) => looksLikeZip
      ? const ZipReadError(
          ZipReadErrorKind.corrupt,
          'The ZIP archive is truncated or damaged: its central directory '
          'cannot be read.',
        )
      : const ZipReadError(
          ZipReadErrorKind.notZip,
          'The file is not a ZIP archive.',
        );

  /// Whether [bytes] start with [prefix].
  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (int i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  /// The first index of [pattern] in [bytes], or -1.
  static int _indexOf(Uint8List bytes, List<int> pattern) {
    final int first = pattern[0];
    final int last = bytes.length - pattern.length;
    outer:
    for (int i = 0; i <= last; i++) {
      if (bytes[i] != first) continue;
      for (int k = 1; k < pattern.length; k++) {
        if (bytes[i + k] != pattern[k]) continue outer;
      }
      return i;
    }
    return -1;
  }
}

/// An [OutputStream] that holds at most a declared number of bytes.
///
/// Writing past the declared size throws a [ZipReadError] of kind
/// [ZipReadErrorKind.corrupt] before the bytes are stored, so a lying entry
/// never inflates past a size the reader has checked. The buffer starts
/// small and doubles, capped at the declared size, so an entry that
/// declares much more than it holds does not reserve it all up front.
/// [subset] reads back what was written, which inflation needs for
/// back-references.
final class _BoundedOutputStream extends OutputStream {
  _BoundedOutputStream(this._limit, int compressedSize, this._entry)
    : _buffer = Uint8List(_initialCapacity(_limit, compressedSize)),
      super(byteOrder: ByteOrder.littleEndian);

  final int _limit;
  final String _entry;
  Uint8List _buffer;
  int _length = 0;

  /// A first guess at the size: four times the compressed size, at least
  /// 64 KiB, never more than [limit].
  static int _initialCapacity(int limit, int compressedSize) {
    final int guess = compressedSize * 4;
    final int capacity = guess < _chunkSize ? _chunkSize : guess;
    return capacity < limit ? capacity : limit;
  }

  @override
  int get length => _length;

  @override
  void clear() => _length = 0;

  @override
  void flush() {}

  @override
  void writeByte(int value) {
    _reserve(1);
    _buffer[_length++] = value & 0xff;
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final int n = length ?? bytes.length;
    _reserve(n);
    _buffer.setRange(_length, _length + n, bytes);
    _length += n;
  }

  @override
  void writeStream(InputStream stream) => writeBytes(stream.toUint8List());

  @override
  Uint8List subset(int start, [int? end]) {
    final int from = start < 0 ? _length + start : start;
    final int to = end == null ? _length : (end < 0 ? _length + end : end);
    if (from < 0 || to > _length || from > to) {
      throw ZipReadError(
        ZipReadErrorKind.corrupt,
        'The entry refers back to data before its start.',
        entry: _entry,
      );
    }
    return Uint8List.sublistView(_buffer, from, to);
  }

  /// The bytes written, in a buffer the stream no longer refers to once
  /// the caller drops the stream.
  @override
  Uint8List getBytes() => _buffer.length == _length
      ? _buffer
      : Uint8List.fromList(Uint8List.sublistView(_buffer, 0, _length));

  /// Makes room for [n] more bytes, refusing to pass the declared size.
  void _reserve(int n) {
    final int needed = _length + n;
    if (needed > _limit) {
      throw ZipReadError(
        ZipReadErrorKind.corrupt,
        'The entry inflates to more than the $_limit bytes it declares.',
        entry: _entry,
      );
    }
    if (needed <= _buffer.length) return;
    int capacity = _buffer.length * 2;
    if (capacity < needed) capacity = needed;
    if (capacity > _limit) capacity = _limit;
    final Uint8List grown = Uint8List(capacity);
    grown.setRange(0, _length, _buffer);
    _buffer = grown;
  }
}
