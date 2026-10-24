// ignore_for_file: close_sinks (ZipWriter.close closes the test sinks)
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jet_office/src/zip/archive_adapter.dart';
import 'package:test/test.dart';

/// Collects every chunk written to it, like a file or network sink would.
class _CollectingSink implements Sink<List<int>> {
  final List<List<int>> chunks = <List<int>>[];
  bool closed = false;

  Uint8List get bytes =>
      Uint8List.fromList(chunks.expand((List<int> c) => c).toList());

  @override
  void add(List<int> data) {
    expect(closed, isFalse, reason: 'write after close');
    chunks.add(List<int>.of(data));
  }

  @override
  void close() => closed = true;
}

/// Throws on every add, like a full disk, and records close().
class _ThrowingSink implements Sink<List<int>> {
  bool closed = false;

  @override
  void add(List<int> data) => throw const FormatException('disk full');

  @override
  void close() => closed = true;
}

/// Bytes that deflate poorly, so the archive is large enough to span chunks.
Uint8List _noise(int length) {
  final Random r = Random(42);
  return Uint8List.fromList(List<int>.generate(length, (_) => r.nextInt(256)));
}

void main() {
  test('round trip in memory', () {
    final ZipWriter z = ZipWriter()
      ..add('a.xml', utf8.encode('<a/>'))
      ..add('b/c.xml', utf8.encode('ç'));
    final Archive arc = ZipDecoder().decodeBytes(z.close()!);
    expect(arc.files.map((ArchiveFile f) => f.name), <String>[
      'a.xml',
      'b/c.xml',
    ]);
    expect(utf8.decode(arc.findFile('b/c.xml')!.content), 'ç');
  });

  test('deterministic: same input, same bytes', () {
    Uint8List build() =>
        (ZipWriter()
              ..add('a.xml', utf8.encode('<a>${'x' * 500}</a>'))
              ..add('b.xml', utf8.encode('<b/>')))
            .close()!;
    expect(build(), build());
  });

  test('entries carry the fixed 1980-01-01 timestamp', () {
    final Uint8List bytes = (ZipWriter()..add('a.xml', utf8.encode('<a/>')))
        .close()!;
    // Local file header: signature at 0, DOS time at 10, DOS date at 12.
    final ByteData d = ByteData.sublistView(bytes);
    expect(d.getUint32(0, Endian.little), 0x04034b50);
    expect(d.getUint16(10, Endian.little), 0, reason: 'time 00:00:00');
    // DOS date: ((year - 1980) << 9) | (month << 5) | day.
    expect(d.getUint16(12, Endian.little), (0 << 9) | (1 << 5) | 1);
    final ArchiveFile f = ZipDecoder().decodeBytes(bytes).files.single;
    expect(f.name, 'a.xml');
  });

  test('sink mode streams the same archive and closes the sink', () {
    final _CollectingSink sink = _CollectingSink();
    final ZipWriter z = ZipWriter(sink: sink)
      ..add('a.xml', utf8.encode('<a/>'));
    expect(z.close(), isNull);
    expect(sink.closed, isTrue);
    expect(
      sink.bytes,
      (ZipWriter()..add('a.xml', utf8.encode('<a/>'))).close(),
    );
  });

  test(
    'sink mode with a large archive: chunked, identical, no subset/clear',
    () {
      final Uint8List big = _noise(300 * 1024);
      final _CollectingSink sink = _CollectingSink();
      final ZipWriter z = ZipWriter(sink: sink)
        ..add('big.bin', big)
        ..add('small.xml', utf8.encode('<s/>'));
      expect(z.close(), isNull);
      expect(sink.closed, isTrue);
      expect(sink.chunks.length, greaterThan(1));
      for (final List<int> c in sink.chunks.take(sink.chunks.length - 1)) {
        expect(c.length, greaterThanOrEqualTo(64 * 1024));
      }
      final Uint8List memory =
          (ZipWriter()
                ..add('big.bin', big)
                ..add('small.xml', utf8.encode('<s/>')))
              .close()!;
      expect(sink.bytes, memory);
      final Archive arc = ZipDecoder().decodeBytes(sink.bytes);
      expect(arc.findFile('big.bin')!.content, big);
    },
  );

  test('lifecycle errors', () {
    final ZipWriter z = ZipWriter()..add('a.xml', utf8.encode('<a/>'));
    z.close();
    expect(() => z.add('b.xml', <int>[1]), throwsStateError);
    expect(z.close, throwsStateError);
  });

  test('a sink that throws in add is closed and the error rethrown', () {
    final _ThrowingSink sink = _ThrowingSink();
    final ZipWriter z = ZipWriter(sink: sink);
    expect(() => z.add('big.bin', _noise(300 * 1024)), throwsFormatException);
    expect(sink.closed, isTrue);
    expect(() => z.add('b.xml', <int>[1]), throwsStateError);
    expect(z.close, throwsStateError);
  });

  test('a sink that throws in close is closed and the error rethrown', () {
    final _ThrowingSink sink = _ThrowingSink();
    final ZipWriter z = ZipWriter(sink: sink)
      ..add('a.xml', utf8.encode('<a/>'));
    expect(z.close, throwsFormatException);
    expect(sink.closed, isTrue);
    expect(z.close, throwsStateError);
  });
}
