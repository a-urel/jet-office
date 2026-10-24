/// The single place where `package:archive` is used.
///
/// Wraps [ZipEncoder] behind a small incremental writer so the rest of the
/// library never depends on the archive package. Entries use a fixed
/// 1980-01-01 00:00:00 timestamp and deflate level 6, so two writes of the
/// same parts produce identical bytes.
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
