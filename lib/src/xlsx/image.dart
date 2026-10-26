/// Images a picture shows: [XlsxImage], its [XlsxImageFormat] sniffed from
/// the bytes, and [checkImage], which reads its size in pixels.
///
/// New in jet_office. quds_office_engine's picture writer
/// (`XlsxWorkbookBuilder.build` in `lib/src/builders/xlsx_io.dart` at
/// commit 15c5d29) looked only for a leading `FF D8` and took everything
/// else for a PNG, so a GIF or a WebP went into the package as
/// `image/png`, and it read no size from the image: the caller gave one in
/// points. Here the format comes from the full signature, anything but a
/// PNG or a JPEG is refused, and the size comes from the PNG's `IHDR` or
/// the JPEG's frame header. No image library is used.
library;

import 'dart:typed_data';

import '../opc/ooxml.dart';

/// The image formats a picture can hold.
enum XlsxImageFormat {
  /// Portable Network Graphics, signature `89 50 4E 47 0D 0A 1A 0A`.
  png,

  /// JPEG (JFIF or Exif), signature `FF D8 FF`.
  jpeg;

  /// The file extension of the media part, without the dot: `png` or
  /// `jpeg`.
  String get extension => switch (this) {
    png => 'png',
    jpeg => 'jpeg',
  };

  /// The content type of the media part: `image/png` or `image/jpeg`.
  String get contentType => switch (this) {
    png => ContentType.png,
    jpeg => ContentType.jpeg,
  };
}

/// The bytes of a PNG or JPEG file, shown by an `XlsxPicture`.
///
/// The bytes are held as given, not copied: an image can be megabytes, and
/// a copy would double the memory. Do not change them while a writer holds
/// the image. The same `Uint8List` used by several pictures of a workbook
/// is written once; equal bytes in two lists are written twice (see
/// `XlsxSheetWriter.picture`).
///
/// The constructor checks nothing; the sheet writer checks the bytes when
/// the picture is added (see [checkImage]).
final class XlsxImage {
  /// Creates an image of the file [bytes], a PNG or a JPEG.
  XlsxImage(this.bytes);

  /// The bytes of the image file, as given.
  final Uint8List bytes;

  /// The format the signature at the start of [bytes] names: `png` for
  /// `89 50 4E 47 0D 0A 1A 0A`, `jpeg` for `FF D8 FF`, and `null` for
  /// anything else.
  XlsxImageFormat? get format {
    if (_startsWith(bytes, _pngSignature)) return XlsxImageFormat.png;
    if (_startsWith(bytes, _jpegSignature)) return XlsxImageFormat.jpeg;
    return null;
  }

  @override
  bool operator ==(Object other) {
    if (other is! XlsxImage) return false;
    if (identical(other.bytes, bytes)) return true;
    if (other.bytes.length != bytes.length) return false;
    for (int i = 0; i < bytes.length; i++) {
      if (other.bytes[i] != bytes[i]) return false;
    }
    return true;
  }

  /// A hash of the length and the first 64 bytes, so a large image is not
  /// read in full.
  @override
  int get hashCode => Object.hash(
    bytes.length,
    Object.hashAll(
      Uint8List.sublistView(bytes, 0, bytes.length < 64 ? bytes.length : 64),
    ),
  );

  /// The format and the length, such as `XlsxImage(png, 87 bytes)`; never
  /// the bytes.
  @override
  String toString() =>
      'XlsxImage(${format?.name ?? 'unknown'}, ${bytes.length} bytes)';
}

const List<int> _pngSignature = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

const List<int> _jpegSignature = <int>[0xFF, 0xD8, 0xFF];

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (int i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

/// The size in pixels of [image], read from its bytes.
///
/// A PNG's size is the width and height of its `IHDR` chunk, big-endian at
/// offsets 16 and 20, which must be the first chunk. A JPEG's size is the
/// height and width of its first frame header (an SOF marker: `C0`–`C3`,
/// `C5`–`C7`, `C9`–`CB` or `CD`–`CF`), found by walking the segments from
/// offset 2 by their lengths; fill bytes (`FF`) before a marker are
/// skipped, and so are the markers that carry no length (`01`, `D0`–`D7`).
///
/// Throws [ArgumentError] named `image` when [image] is neither a PNG nor
/// a JPEG (see [XlsxImage.format]); when its bytes end before its size or
/// inside a JPEG segment (`cut short`); when a PNG's first chunk is not
/// `IHDR`; when a JPEG's segments do not start with `FF`, have a length
/// below 2, or reach a scan (`DA`), its end (`D9`) or the end of the bytes
/// before a frame header; and when the width or height is 0.
({int width, int height}) checkImage(XlsxImage image) {
  final ({int width, int height}) size = switch (image.format) {
    XlsxImageFormat.png => _pngSize(image),
    XlsxImageFormat.jpeg => _jpegSize(image),
    null => throw _invalid(image, 'it is neither a PNG nor a JPEG'),
  };
  if (size.width == 0 || size.height == 0) {
    throw _invalid(
      image,
      'its size is ${size.width} × ${size.height} pixels; both must be at '
      'least 1',
    );
  }
  return size;
}

ArgumentError _invalid(XlsxImage image, String problem) =>
    ArgumentError.value(image, 'image', 'The image cannot be used: $problem.');

int _uint16(Uint8List b, int i) => b[i] << 8 | b[i + 1];

int _uint32(Uint8List b, int i) =>
    b[i] * 0x1000000 + (b[i + 1] << 16 | b[i + 2] << 8 | b[i + 3]);

({int width, int height}) _pngSize(XlsxImage image) {
  final Uint8List b = image.bytes;
  const int sizeEnd = 24;
  if (b.length < sizeEnd) {
    throw _invalid(
      image,
      'the PNG is cut short: ${b.length} bytes end before its size',
    );
  }
  // Offset 12: the type of the first chunk.
  if (b[12] != 0x49 || b[13] != 0x48 || b[14] != 0x44 || b[15] != 0x52) {
    throw _invalid(image, 'the first chunk of the PNG is not IHDR');
  }
  return (width: _uint32(b, 16), height: _uint32(b, 20));
}

({int width, int height}) _jpegSize(XlsxImage image) {
  final Uint8List b = image.bytes;
  Never cutShort() => throw _invalid(
    image,
    'the JPEG is cut short: ${b.length} bytes end inside a segment',
  );
  int i = 2;
  while (i < b.length) {
    if (b[i] != 0xFF) {
      throw _invalid(
        image,
        'byte $i of the JPEG should start a marker (FF) but is '
        '${b[i].toRadixString(16).toUpperCase().padLeft(2, '0')}',
      );
    }
    // Fill bytes: any number of FF may come before the marker code.
    while (i + 1 < b.length && b[i + 1] == 0xFF) {
      i++;
    }
    if (i + 1 >= b.length) cutShort();
    final int marker = b[i + 1];
    if (marker == 0xD9 || marker == 0xDA) break;
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    if (i + 3 >= b.length) cutShort();
    final int length = _uint16(b, i + 2);
    if (length < 2) {
      throw _invalid(
        image,
        'the segment at byte $i of the JPEG has the length $length, below 2',
      );
    }
    if (_isFrameHeader(marker)) {
      // Length, precision, height, width.
      if (i + 8 >= b.length) cutShort();
      return (width: _uint16(b, i + 7), height: _uint16(b, i + 5));
    }
    if (i + 2 + length > b.length) cutShort();
    i += 2 + length;
  }
  throw _invalid(image, 'the JPEG has no frame header (SOF)');
}

/// Whether [marker] starts a frame header: `C0`–`CF` except `C4` (Huffman
/// tables), `C8` (reserved) and `CC` (arithmetic conditioning).
bool _isFrameHeader(int marker) =>
    marker >= 0xC0 &&
    marker <= 0xCF &&
    marker != 0xC4 &&
    marker != 0xC8 &&
    marker != 0xCC;
