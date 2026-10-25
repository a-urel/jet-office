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
/// A [ZipWriter] streaming to a sink made by [make], with that sink.
///
/// The writer closes the sink in `close` (or after a failure), so the
/// `close_sinks` lint is silenced here, once, instead of at every test.
(ZipWriter, T) _sinkWriter<T extends Sink<List<int>>>(T Function() make) {
  // ignore: close_sinks (ZipWriter closes it)
  final T sink = make();
  return (ZipWriter(sink: sink), sink);
}

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
  });

  test('sink mode streams the same archive and closes the sink', () {
    final (ZipWriter z, _CollectingSink sink) = _sinkWriter(
      _CollectingSink.new,
    );
    z.add('a.xml', utf8.encode('<a/>'));
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
      final (ZipWriter z, _CollectingSink sink) = _sinkWriter(
        _CollectingSink.new,
      );
      z
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
    final (ZipWriter z, _ThrowingSink sink) = _sinkWriter(_ThrowingSink.new);
    expect(() => z.add('big.bin', _noise(300 * 1024)), throwsFormatException);
    expect(sink.closed, isTrue);
    expect(() => z.add('b.xml', <int>[1]), throwsStateError);
    expect(z.close, throwsStateError);
  });

  test('a sink that throws in close is closed and the error rethrown', () {
    final (ZipWriter z, _ThrowingSink sink) = _sinkWriter(_ThrowingSink.new);
    z.add('a.xml', utf8.encode('<a/>'));
    expect(z.close, throwsFormatException);
    expect(sink.closed, isTrue);
    expect(z.close, throwsStateError);
  });

  test('the central directory carries the 1980-01-01 timestamp too', () {
    final Uint8List bytes = (ZipWriter()..add('a.xml', utf8.encode('<a/>')))
        .close()!;
    final ByteData d = ByteData.sublistView(bytes);
    int at = -1;
    for (int i = 0; i + 4 <= bytes.length; i++) {
      if (d.getUint32(i, Endian.little) == 0x02014b50) {
        at = i;
        break;
      }
    }
    expect(at, isNonNegative, reason: 'central directory header found');
    // Central header: DOS time at 12, DOS date at 14.
    expect(d.getUint16(at + 12, Endian.little), 0);
    expect(d.getUint16(at + 14, Endian.little), (0 << 9) | (1 << 5) | 1);
  });

  test('chunks reach the sink before close()', () {
    final (ZipWriter z, _CollectingSink sink) = _sinkWriter(
      _CollectingSink.new,
    );
    z.add('big.bin', _noise(300 * 1024));
    expect(sink.chunks, isNotEmpty);
    expect(sink.closed, isFalse);
    z.close();
    expect(sink.closed, isTrue);
  });

  group('addChunks', () {
    final List<Uint8List> parts = <Uint8List>[
      Uint8List.fromList(utf8.encode('<a>')),
      _noise(100 * 1024),
      Uint8List(0),
      Uint8List.fromList(utf8.encode('</a>')),
    ];
    final Uint8List whole = Uint8List.fromList(
      parts.expand((Uint8List c) => c).toList(),
    );

    test('is byte-identical to add with the concatenation, in memory', () {
      final Uint8List viaChunks =
          (ZipWriter()
                ..addChunks('s.xml', parts)
                ..add('t.xml', utf8.encode('<t/>')))
              .close()!;
      final Uint8List viaAdd =
          (ZipWriter()
                ..add('s.xml', whole)
                ..add('t.xml', utf8.encode('<t/>')))
              .close()!;
      expect(viaChunks, viaAdd);
      expect(
        ZipDecoder().decodeBytes(viaChunks).findFile('s.xml')!.content,
        whole,
      );
    });

    test('is byte-identical to add with the concatenation, to a sink', () {
      final (ZipWriter za, _CollectingSink a) = _sinkWriter(
        _CollectingSink.new,
      );
      final (ZipWriter zb, _CollectingSink b) = _sinkWriter(
        _CollectingSink.new,
      );
      za
        ..addChunks('s.xml', parts)
        ..close();
      zb
        ..add('s.xml', whole)
        ..close();
      expect(a.bytes, b.bytes);
    });

    test('accepts no chunks and one chunk', () {
      expect(
        (ZipWriter()..addChunks('e', <Uint8List>[])).close(),
        (ZipWriter()..add('e', <int>[])).close(),
      );
      final Uint8List one = Uint8List.fromList(<int>[1, 2, 3]);
      expect(
        (ZipWriter()..addChunks('o', <Uint8List>[one])).close(),
        (ZipWriter()..add('o', one)).close(),
      );
    });

    test('lifecycle errors match add', () {
      final ZipWriter z = ZipWriter()..close();
      expect(() => z.addChunks('x', <Uint8List>[]), throwsStateError);
    });
  });
}
