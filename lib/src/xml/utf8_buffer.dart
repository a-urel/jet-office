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
  /// [chunkSize] must be positive.
  Utf8Buffer({int chunkSize = 16384}) : _chunkSize = chunkSize {
    RangeError.checkValueInInterval(chunkSize, 1, 1 << 30, 'chunkSize');
  }

  final int _chunkSize;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  StringBuffer _pending = StringBuffer();

  /// The number of bytes encoded so far. A trailing high surrogate that is
  /// still waiting for its pair is not counted yet.
  int get lengthInBytes {
    _flush(force: false);
    return _bytes.length;
  }

  /// Encodes everything written so far, returns it and empties the buffer.
  ///
  /// A high surrogate that never received its pair is encoded as U+FFFD.
  Uint8List takeBytes() {
    _flush(force: true);
    return _bytes.takeBytes();
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
      _bytes.add(utf8.encode(text));
    }
  }
}
