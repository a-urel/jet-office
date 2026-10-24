import 'dart:convert';
import 'dart:typed_data';

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

  test(
    'takeChunks returns the bytes takeBytes would and empties the buffer',
    () {
      Utf8Buffer fill() => Utf8Buffer(chunkSize: 4)
        ..write('abc')
        ..write('😀')
        ..write('ğüşİ')
        ..write('tail');
      final Utf8Buffer b = fill();
      final List<Uint8List> chunks = b.takeChunks();
      expect(chunks.length, greaterThan(1));
      expect(
        Uint8List.fromList(chunks.expand((Uint8List c) => c).toList()),
        fill().takeBytes(),
      );
      expect(b.lengthInBytes, 0);
      expect(b.takeChunks(), isEmpty);
      expect(b.takeBytes(), isEmpty);
    },
  );

  test('takeChunks encodes an unpaired trailing high surrogate as U+FFFD', () {
    final Utf8Buffer b = Utf8Buffer()..write('a\uD83D');
    final List<int> all = b.takeChunks().expand((Uint8List c) => c).toList();
    expect(all, utf8.encode('a\uFFFD'));
  });

  test('takeChunks result is independent of later writes', () {
    final Utf8Buffer b = Utf8Buffer(chunkSize: 2)..write('abcd');
    final List<Uint8List> first = b.takeChunks();
    b.write('zz');
    expect(first.expand((Uint8List c) => c), utf8.encode('abcd'));
    expect(b.takeBytes(), utf8.encode('zz'));
  });

  test('chunkSize must be between 1 and 2^30', () {
    expect(() => Utf8Buffer(chunkSize: 0), throwsRangeError);
    expect(() => Utf8Buffer(chunkSize: -1), throwsRangeError);
    expect(() => Utf8Buffer(chunkSize: (1 << 30) + 1), throwsRangeError);
    expect(Utf8Buffer(chunkSize: 1), isNotNull);
    expect(Utf8Buffer(chunkSize: 1 << 30), isNotNull);
  });

  test('writeCharCode holds a high surrogate back with chunkSize 1', () {
    final Utf8Buffer b = Utf8Buffer(chunkSize: 1);
    b.writeCharCode(0xD83D);
    expect(b.lengthInBytes, 0, reason: 'waiting for its pair');
    b.writeCharCode(0xDE00);
    expect(b.lengthInBytes, 4);
    b.writeCharCode(0x61);
    expect(b.takeBytes(), utf8.encode('😀a'));
  });

  test('a first test chunk that does not end on a low surrogate', () {
    final Utf8Buffer b = Utf8Buffer(chunkSize: 4);
    b.write('a😀c'); // flushes at 4 units, ending on a plain character
    b.write('d');
    expect(b.takeBytes(), utf8.encode('a😀cd'));
  });

  test('lengthInBytes while a high surrogate is held back', () {
    final Utf8Buffer b = Utf8Buffer(chunkSize: 2);
    b.write('a\uD83D');
    expect(b.lengthInBytes, 1);
    b.write('\uDE00');
    expect(b.lengthInBytes, 5);
  });

  test('lengthInBytes counts pending text and does not split the buffer', () {
    final Utf8Buffer b = Utf8Buffer()..write('aş');
    expect(b.lengthInBytes, 3);
    expect(b.lengthInBytes, 3);
    expect(
      b.takeChunks().length,
      1,
      reason: 'reading the length never flushes',
    );
  });
}
