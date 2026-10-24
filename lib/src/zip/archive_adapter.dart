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
final class ZipWriter {
  /// Creates a writer, streaming to [sink] when one is given.
  ZipWriter({Sink<List<int>>? sink})
    : _sink = sink,
      _output = sink == null ? OutputMemoryStream() : _SinkOutputStream(sink) {
    _encoder = ZipEncoder()
      ..startEncode(_output, level: _deflateLevel, modified: _fixedTime);
  }

  final Sink<List<int>>? _sink;
  final OutputStream _output;
  late final ZipEncoder _encoder;
  bool _closed = false;

  /// Adds one entry named [name] holding [bytes].
  ///
  /// Throws a [StateError] after [close].
  void add(String name, List<int> bytes) {
    if (_closed) {
      throw StateError('Cannot add "$name": the ZIP writer is closed.');
    }
    _encoder.add(ArchiveFile.bytes(name, bytes));
  }

  /// Finishes the archive.
  ///
  /// Returns the archive bytes in memory mode, or `null` in sink mode after
  /// closing the sink. Throws a [StateError] when called twice.
  Uint8List? close() {
    if (_closed) {
      throw StateError('The ZIP writer is already closed.');
    }
    _closed = true;
    _encoder.endEncode();
    final OutputStream out = _output;
    if (out is _SinkOutputStream) {
      out.finish();
      _sink!.close();
      return null;
    }
    return out.getBytes();
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
