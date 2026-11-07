/// The media parts of a package (`xl/media`, `word/media`), read as images
/// and found again by their bytes.
///
/// Not ported from Quds; written for jet_office.
///
/// Both formats keep a picture's bytes in a part of their own, which several
/// pictures may show through relationships. [DrawingMediaIndex] gives one
/// [OfficeImage] (so one `Uint8List`) per part however many pictures show it,
/// and answers which part holds a given image, so a picture added with bytes
/// the file already holds shares that part instead of writing a copy.
///
/// This layer imports `opc`, `xml` and `common` only (decision 0014).
library;

import 'dart:typed_data';

import '../common/image.dart';
import '../opc/package.dart';

final RegExp _mediaFolder = RegExp(
  r'^(?:xl|word)/media/',
  caseSensitive: false,
);
final RegExp _trailingNumber = RegExp(r'(\d+)\.[^/.]*$');

/// The images of a package's media parts.
final class DrawingMediaIndex {
  /// An index over the media of a package; nothing is read until a method needs it.
  DrawingMediaIndex(this._package);

  final OpcPackage _package;
  final Map<String, OfficeImage> _images = <String, OfficeImage>{};
  Map<int, List<String>>? _byHash;

  /// The image held by the media part [partName] (with or without a leading
  /// slash, any case), the same [OfficeImage] on every call.
  ///
  /// Throws an [OpcFormatException] when the package has no such part or its
  /// entry is corrupt.
  OfficeImage imageOf(String partName) {
    final String name = _package.canonicalPartName(partName) ?? partName;
    final String key = _plain(name).toLowerCase();
    return _images[key] ??= OfficeImage(_package.originalBytes(name));
  }

  /// The name (no leading slash) of a media part holding [image]: the one
  /// whose bytes are the same list or, else, equal bytes; `null` when none
  /// does.
  ///
  /// The first call reads every media part. Hashes narrow the candidates and
  /// the bytes of a candidate are compared, so different bytes of equal
  /// length and hash are never taken for one image.
  String? partFor(OfficeImage image) {
    for (final MapEntry<String, OfficeImage> e in _images.entries) {
      if (identical(e.value.bytes, image.bytes)) return _nameOf(e.key);
    }
    final Map<int, List<String>> byHash = _byHash ??= _scan();
    final List<String>? candidates = byHash[_hash(image.bytes)];
    if (candidates == null) return null;
    for (final String name in candidates) {
      if (imageOf(name) == image) return _plain(name);
    }
    return null;
  }

  /// One above the highest number a part of `xl/media` or `word/media` ends
  /// its name with (`image7.png` is 7), or 1 when there is none.
  int nextNumber() {
    int highest = 0;
    for (final String name in _package.partNames) {
      final String plain = _plain(name);
      if (!_mediaFolder.hasMatch(plain)) continue;
      final String? digits = _trailingNumber.firstMatch(plain)?.group(1);
      if (digits == null) continue;
      final int number = int.tryParse(digits) ?? 0;
      if (number > highest) highest = number;
    }
    return highest + 1;
  }

  Map<int, List<String>> _scan() {
    final Map<int, List<String>> byHash = <int, List<String>>{};
    for (final String name in _package.partNames.toList()) {
      if (!_mediaFolder.hasMatch(_plain(name))) continue;
      final OfficeImage image = imageOf(name);
      byHash.putIfAbsent(_hash(image.bytes), () => <String>[]).add(name);
    }
    return byHash;
  }

  String _nameOf(String key) => _plain(_package.canonicalPartName(key) ?? key);

  static String _plain(String name) =>
      name.startsWith('/') ? name.substring(1) : name;

  /// FNV-1a over every byte, truncated to 32 bits.
  static int _hash(Uint8List bytes) {
    int h = 0x811C9DC5;
    for (final int b in bytes) {
      h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }
}
