import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/src/zip/archive_adapter.dart';
import 'package:test/test.dart';

import '../xlsx/read/support/zip_builder.dart';

/// Opens [bytes] with the default limits of the reader ruling, or with the
/// given ones.
ZipReader _open(
  Uint8List bytes, {
  int maxEntries = 10000,
  int maxEntryBytes = 256 << 20,
  int maxTotalBytes = 1 << 30,
  int maxCompressionRatio = 1000,
}) => ZipReader(
  bytes,
  maxEntries: maxEntries,
  maxEntryBytes: maxEntryBytes,
  maxTotalBytes: maxTotalBytes,
  maxCompressionRatio: maxCompressionRatio,
);

/// Matches a [ZipReadError] of [kind], naming [entry] when one is given.
Matcher _throwsKind(ZipReadErrorKind kind, {String? entry}) => throwsA(
  isA<ZipReadError>()
      .having((ZipReadError e) => e.kind, 'kind', kind)
      .having(
        (ZipReadError e) => entry == null || e.entry == entry,
        'entry is $entry',
        isTrue,
      )
      .having((ZipReadError e) => e.message, 'message', isNotEmpty),
);

/// Whether the tests run compiled to JavaScript, where archive reads a
/// 64-bit size with 32-bit bit operations.
const bool _isWeb = identical(0, 0.0);

/// The OLE compound file signature.
const List<int> _ole = <int>[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];

/// [text] as UTF-16LE bytes.
List<int> _utf16le(String text) => <int>[
  for (final int unit in text.codeUnits) ...<int>[unit & 0xff, unit >> 8],
];

void main() {
  group('opening', () {
    test('lists file entries with backslashes turned into slashes', () {
      final ZipReader z = _open(
        buildZip(<String, List<int>>{
          'xl/': <int>[],
          r'xl\workbook.xml': utf8.encode('<w/>'),
          '[Content_Types].xml': utf8.encode('<t/>'),
        }),
      );
      expect(z.names, <String>['xl/workbook.xml', '[Content_Types].xml']);
    });

    test('reads an entry by any case and slash', () {
      final ZipReader z = _open(
        buildZip(<String, List<int>>{'xl/Workbook.xml': utf8.encode('<w/>')}),
      );
      expect(z.contains('/XL/workbook.xml'), isTrue);
      expect(z.contains('xl/other.xml'), isFalse);
      expect(utf8.decode(z.read(r'xl\workbook.xml')), '<w/>');
    });

    test('reads empty, stored and deflated entries', () {
      final List<int> big = List<int>.generate(100000, (int i) => i * 7 % 251);
      final ZipReader deflated = _open(
        buildZip(<String, List<int>>{'a.xml': big, 'e.xml': <int>[]}),
      );
      expect(deflated.read('a.xml'), big);
      expect(deflated.read('e.xml'), isEmpty);
      final ZipReader stored = _open(
        buildZip(<String, List<int>>{'a.xml': big}, store: true),
      );
      expect(stored.read('a.xml'), big);
    });

    test('reading an entry twice gives two equal, separate buffers', () {
      final ZipReader z = _open(
        buildZip(<String, List<int>>{'a.xml': utf8.encode('<a/>')}),
      );
      final Uint8List first = z.read('a.xml');
      first[0] = 0;
      expect(utf8.decode(z.read('a.xml')), '<a/>');
    });

    test('read of a missing entry is a programmer error', () {
      final ZipReader z = _open(
        buildZip(<String, List<int>>{
          'xl/': <int>[],
          'a.xml': <int>[1],
        }),
      );
      expect(() => z.read('b.xml'), throwsStateError);
      expect(() => z.read('xl/'), throwsStateError);
    });
  });

  group('limits', () {
    test('counts every entry, directories included', () {
      final Uint8List zip = buildZip(<String, List<int>>{
        'xl/': <int>[],
        'a.xml': <int>[1],
        'b.xml': <int>[2],
      });
      expect(_open(zip, maxEntries: 3).names, hasLength(2));
      expect(
        () => _open(zip, maxEntries: 2),
        _throwsKind(ZipReadErrorKind.tooManyEntries),
      );
    });

    test('refuses a declared size above maxEntryBytes before inflating', () {
      final Uint8List bomb = patchDeclaredSize(
        buildZip(<String, List<int>>{'a.xml': List<int>.filled(1024, 32)}),
        'a.xml',
        1 << 30,
      );
      expect(
        () => _open(bomb),
        _throwsKind(ZipReadErrorKind.entryTooLarge, entry: 'a.xml'),
      );
    });

    test('refuses declared sizes summing above maxTotalBytes', () {
      final Uint8List zip = buildZip(<String, List<int>>{
        'a.xml': List<int>.filled(600, 32),
        'b.xml': List<int>.filled(600, 32),
      });
      expect(_open(zip, maxTotalBytes: 1200).names, hasLength(2));
      expect(
        () => _open(zip, maxTotalBytes: 1199),
        _throwsKind(ZipReadErrorKind.totalTooLarge),
      );
    });

    test('refuses a high ratio on entries declaring over 1 MiB', () {
      final Uint8List zeros = buildZip(<String, List<int>>{
        'a.xml': Uint8List(2 << 20),
      });
      expect(
        () => _open(zeros, maxCompressionRatio: 10),
        _throwsKind(ZipReadErrorKind.ratioTooHigh, entry: 'a.xml'),
      );
      expect(_open(zeros).read('a.xml'), hasLength(2 << 20));
      final Uint8List small = buildZip(<String, List<int>>{
        'a.xml': Uint8List(1 << 20),
      });
      expect(_open(small, maxCompressionRatio: 10).names, <String>['a.xml']);
    });

    test('refuses duplicate names', () {
      final Uint8List zip = buildZip(<String, List<int>>{
        'a.xml': <int>[1],
        'A.XML': <int>[2],
      });
      expect(
        () => _open(zip),
        _throwsKind(ZipReadErrorKind.duplicateEntry, entry: 'A.XML'),
      );
    });

    test('refuses names equal after slash normalization', () {
      final Uint8List zip = buildZip(<String, List<int>>{
        'xl/a.xml': <int>[1],
        r'\xl\a.xml': <int>[2],
      });
      expect(() => _open(zip), _throwsKind(ZipReadErrorKind.duplicateEntry));
    });

    test('refuses an entry flagged as encrypted', () {
      final Uint8List zip = patchFlags(
        buildZip(<String, List<int>>{
          'a.xml': <int>[1, 2, 3],
        }),
        'a.xml',
        1,
      );
      expect(
        () => _open(zip),
        _throwsKind(ZipReadErrorKind.encrypted, entry: 'a.xml'),
      );
    });
  });

  group('Zip64 sizes', () {
    // high 0x90000000: a negative 64-bit int on the VM. On the web archive
    // keeps only the low 32 bits, here about 4 GiB, which is too large.
    const int low = 0xFFFFFFF0;
    const int high = 0x90000000;
    const ZipReadErrorKind kind = _isWeb
        ? ZipReadErrorKind.entryTooLarge
        : ZipReadErrorKind.corrupt;

    test('refuses a declared size that reads as negative', () {
      final Uint8List zip = patchZip64Size(
        buildZip(<String, List<int>>{
          'a.xml': <int>[1, 2, 3],
        }),
        'a.xml',
        low: low,
        high: high,
      );
      expect(() => _open(zip), _throwsKind(kind, entry: 'a.xml'));
    });

    test('a negative size cannot lower the declared total', () {
      final Uint8List zip = patchZip64Size(
        buildZip(<String, List<int>>{
          'a.xml': List<int>.filled(600, 32),
          'b.xml': List<int>.filled(600, 32),
          'c.xml': <int>[1],
        }),
        'c.xml',
        low: low,
        high: high,
      );
      expect(
        () => _open(zip, maxTotalBytes: 1199),
        _throwsKind(kind, entry: 'c.xml'),
      );
    });

    test('a well-formed Zip64 size is read', () {
      final Uint8List zip = patchZip64Size(
        buildZip(<String, List<int>>{
          'a.xml': <int>[1, 2, 3],
        }),
        'a.xml',
        low: 3,
        high: 0,
      );
      expect(_open(zip).read('a.xml'), <int>[1, 2, 3]);
    });
  });

  group('integrity', () {
    test('stops inflating at the declared size', () {
      final Uint8List lying = patchDeclaredSize(
        buildZip(<String, List<int>>{'a.xml': List<int>.filled(4 << 20, 32)}),
        'a.xml',
        1024,
      );
      expect(
        () => _open(lying).read('a.xml'),
        _throwsKind(ZipReadErrorKind.corrupt, entry: 'a.xml'),
      );
    });

    test('refuses an entry shorter than declared', () {
      final Uint8List lying = patchDeclaredSize(
        buildZip(<String, List<int>>{'a.xml': List<int>.filled(1024, 32)}),
        'a.xml',
        2048,
      );
      expect(
        () => _open(lying).read('a.xml'),
        _throwsKind(ZipReadErrorKind.corrupt, entry: 'a.xml'),
      );
    });

    test('checks the CRC', () {
      final List<int> content = utf8.encode('<worksheet>hello</worksheet>');
      final Uint8List zip = buildZip(<String, List<int>>{
        'a.xml': content,
      }, store: true);
      final int at = _indexOf(zip, utf8.encode('hello'));
      zip[at] ^= 0x01;
      expect(
        () => _open(zip).read('a.xml'),
        _throwsKind(ZipReadErrorKind.corrupt, entry: 'a.xml'),
      );
    });

    test('maps broken deflate data to corrupt', () {
      final Uint8List zip = buildZip(<String, List<int>>{
        'a.xml': List<int>.generate(5000, (int i) => i * 31 % 256),
      });
      // Overwrite the compressed data, which follows the 30-byte local
      // header and the 5-byte name.
      for (int i = 35; i < 35 + 40; i++) {
        zip[i] = 0xff;
      }
      expect(
        () => _open(zip).read('a.xml'),
        _throwsKind(ZipReadErrorKind.corrupt, entry: 'a.xml'),
      );
    });
  });

  group('not a ZIP', () {
    test('tells encrypted from legacy OLE files', () {
      final Uint8List encrypted = Uint8List.fromList(<int>[
        ..._ole,
        ...List<int>.filled(500, 0),
        ..._utf16le('EncryptedPackage'),
        ...List<int>.filled(100, 0),
      ]);
      expect(() => _open(encrypted), _throwsKind(ZipReadErrorKind.encrypted));
      final Uint8List legacy = Uint8List.fromList(<int>[
        ..._ole,
        ...List<int>.filled(500, 0),
        ...utf8.encode('Workbook'),
      ]);
      expect(() => _open(legacy), _throwsKind(ZipReadErrorKind.legacyXls));
    });

    test('maps garbage to notZip and a truncated file to corrupt', () {
      expect(() => _open(Uint8List(0)), _throwsKind(ZipReadErrorKind.notZip));
      expect(
        () => _open(Uint8List.fromList(utf8.encode('name,amount\nA,1\n'))),
        _throwsKind(ZipReadErrorKind.notZip),
      );
      final Uint8List zip = buildZip(<String, List<int>>{
        'a.xml': List<int>.filled(4000, 65),
        'b.xml': List<int>.generate(4000, (int i) => i % 256),
      });
      for (final int cut in <int>[10, zip.length ~/ 2, zip.length - 30]) {
        expect(
          () => _open(Uint8List.sublistView(zip, 0, cut)),
          _throwsKind(ZipReadErrorKind.corrupt),
          reason: 'cut at $cut of ${zip.length}',
        );
      }
    });
  });
}

/// The first index of [pattern] in [bytes].
int _indexOf(Uint8List bytes, List<int> pattern) {
  outer:
  for (int i = 0; i + pattern.length <= bytes.length; i++) {
    for (int k = 0; k < pattern.length; k++) {
      if (bytes[i + k] != pattern[k]) continue outer;
    }
    return i;
  }
  throw StateError('Pattern not found.');
}
