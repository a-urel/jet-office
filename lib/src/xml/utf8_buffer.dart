/// A [StringSink] that stores what is written to it as UTF-8 bytes.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Collects text as UTF-8 bytes without holding the whole document as a
/// string.
///
/// Text accumulates in a small pending string. Once it reaches `chunkSize`
/// UTF-16 code units it is encoded into the byte store. A high surrogate at
/// the end of the pending text is held back until the next flush, so a
/// surrogate pair is always encoded in one piece.
final class Utf8Buffer implements StringSink {
  /// Creates a buffer that encodes its pending text every [chunkSize] UTF-16
  /// code units.
  ///
  /// [chunkSize] must be between 1 and 2^30 (inclusive); otherwise this
  /// throws a [RangeError]. The upper bound only keeps the value sane: the
  /// pending text is a `StringBuffer`, so a huge size defeats the purpose of
  /// chunking.
  Utf8Buffer({int chunkSize = 16384}) : _chunkSize = chunkSize {
    RangeError.checkValueInInterval(chunkSize, 1, 1 << 30, 'chunkSize');
  }

  final int _chunkSize;
  final List<Uint8List> _chunks = <Uint8List>[];
  int _encodedLength = 0;
  StringBuffer _pending = StringBuffer();

  /// The number of bytes [takeBytes] would return, except that a trailing
  /// high surrogate still waiting for its pair is not counted yet.
  ///
  /// Reading it never encodes or flushes anything.
  int get lengthInBytes {
    final String text = _pending.toString();
    final int length = text.length;
    int extra = 0;
    for (int i = 0; i < length; i++) {
      final int unit = text.codeUnitAt(i);
      if (unit < 0x80) {
        extra += 1;
      } else if (unit < 0x800) {
        extra += 2;
      } else if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (i + 1 == length) {
          break; // Held back until its pair arrives.
        }
        final int next = text.codeUnitAt(i + 1);
        if (next >= 0xDC00 && next <= 0xDFFF) {
          extra += 4;
          i++;
        } else {
          extra += 3; // A lone high surrogate encodes as U+FFFD.
        }
      } else {
        extra += 3; // Includes a lone low surrogate (U+FFFD).
      }
    }
    return _encodedLength + extra;
  }

  /// Encodes everything written so far, returns it and empties the buffer.
  ///
  /// A high surrogate that never received its pair is encoded as U+FFFD.
  Uint8List takeBytes() {
    final List<Uint8List> chunks = takeChunks();
    if (chunks.length == 1) {
      return chunks.single;
    }
    final BytesBuilder builder = BytesBuilder(copy: false);
    chunks.forEach(builder.add);
    return builder.takeBytes();
  }

  /// Encodes everything written so far and returns the bytes as chunks,
  /// without concatenating them, then empties the buffer.
  ///
  /// The chunks, in order, hold the same bytes [takeBytes] would return. The
  /// buffer keeps no reference to them. A high surrogate that never received
  /// its pair is encoded as U+FFFD.
  List<Uint8List> takeChunks() {
    _flush(force: true);
    final List<Uint8List> chunks = List<Uint8List>.of(_chunks);
    _chunks.clear();
    _encodedLength = 0;
    return chunks;
  }

  @override
  void write(Object? object) {
    _pending.write(object);
    _flushIfFull();
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    _pending.writeAll(objects, separator);
    _flushIfFull();
  }

  @override
  void writeCharCode(int charCode) {
    _pending.writeCharCode(charCode);
    _flushIfFull();
  }

  @override
  void writeln([Object? object = '']) {
    _pending.writeln(object);
    _flushIfFull();
  }

  void _flushIfFull() {
    if (_pending.length >= _chunkSize) {
      _flush(force: false);
    }
  }

  void _flush({required bool force}) {
    if (_pending.isEmpty) {
      return;
    }
    String text = _pending.toString();
    String carry = '';
    if (!force) {
      final int last = text.codeUnitAt(text.length - 1);
      if (last >= 0xD800 && last <= 0xDBFF) {
        carry = text.substring(text.length - 1);
        text = text.substring(0, text.length - 1);
      }
    }
    _pending = StringBuffer(carry);
    if (text.isNotEmpty) {
      _chunks.add(utf8.encode(text));
      _encodedLength += _chunks.last.length;
    }
  }
}
