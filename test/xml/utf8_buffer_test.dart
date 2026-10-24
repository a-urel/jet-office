import 'dart:convert';

import 'package:jet_office/src/xml/utf8_buffer.dart';
import 'package:test/test.dart';

void main() {
  test('buffer encodes UTF-8 across chunk boundaries', () {
    final Utf8Buffer b = Utf8Buffer(chunkSize: 4);
    b.write('abc');
    b.write('😀'); // surrogate pair straddles the 4-unit boundary
    b.write('ğüşİ');
    expect(utf8.decode(b.takeBytes()), 'abc😀ğüşİ');
  });

  test('a high surrogate at the flush boundary is held back, not split', () {
    final Utf8Buffer b = Utf8Buffer(chunkSize: 4);
    b.write('abc\uD83D'); // reaches the chunk size ending in a high surrogate
    b.write('\uDE00z');
    expect(b.takeBytes(), utf8.encode('abc😀z'));
  });

  test('writeCharCode splitting a pair across flushes stays intact', () {
    final Utf8Buffer b = Utf8Buffer(chunkSize: 2);
    for (final int unit in '😀😀a'.codeUnits) {
      b.writeCharCode(unit);
    }
    expect(b.takeBytes(), utf8.encode('😀😀a'));
  });

  test('writeAll and writeln follow the StringSink contract', () {
    final Utf8Buffer b = Utf8Buffer(chunkSize: 3);
    b.writeAll(<Object>[1, 'b', 3], '-');
    b.writeln('x');
    b.writeln();
    expect(utf8.decode(b.takeBytes()), '1-b-3x\n\n');
  });

  test('lengthInBytes counts encoded bytes', () {
    final Utf8Buffer b = Utf8Buffer(chunkSize: 4);
    b.write('aş😀');
    expect(b.lengthInBytes, 1 + 2 + 4);
  });

  test('takeBytes empties the buffer', () {
    final Utf8Buffer b = Utf8Buffer()..write('x');
    b.takeBytes();
    expect(b.takeBytes(), isEmpty);
    expect(b.lengthInBytes, 0);
  });
}
