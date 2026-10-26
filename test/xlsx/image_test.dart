import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/opc/ooxml.dart';
import 'package:jet_office/src/xlsx/image.dart' show checkImage;
import 'package:test/test.dart';

import '../fixtures/m4_fixtures.dart' show jpeg3x5, png4x2;

/// A real 6 × 4 progressive JPEG, 989 bytes: its frame header is SOF2.
///
/// Made from `python3 png.py 6 4` (see `png4x2` in `m4_fixtures.dart`),
/// turned into a JPEG with `sips -s format jpeg` and re-encoded by
/// `swift prog.swift base6x4.jpeg prog6x4.jpeg` (Apple Swift 6.4, macOS
/// 27.0.1), `prog.swift` being:
///
/// ```swift
/// import Foundation
/// import ImageIO
/// let a = CommandLine.arguments
/// let src = CGImageSourceCreateWithURL(
///   URL(fileURLWithPath: a[1]) as CFURL, nil)!
/// let dst = CGImageDestinationCreateWithURL(
///   URL(fileURLWithPath: a[2]) as CFURL,
///   "public.jpeg" as CFString, 1, nil)!
/// let jfif = [kCGImagePropertyJFIFIsProgressive: true]
/// CGImageDestinationAddImage(
///   dst, CGImageSourceCreateImageAtIndex(src, 0, nil)!,
///   [kCGImagePropertyJFIFDictionary: jfif] as CFDictionary)
/// CGImageDestinationFinalize(dst)
/// ```
///
/// Checked with decoders: `sips -g pixelWidth -g pixelHeight` reads 6 × 4
/// and `djpeg` (libjpeg-turbo 3.2.0) decodes it to a 6 × 4 image.
final Uint8List _progressive6x4 = base64Decode(
  '/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAA'
  'AAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAABqADAAQAAAABAAAABAAAAAD/wgARCAAEAAYD'
  'ASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAwIEAQUABgcICQoL/8QAwxAAAQMDAgQD'
  'BAYEBwYECAZzAQIAAxEEEiEFMRMiEAZBUTIUYXEjB4EgkUIVoVIzsSRiMBbBctFDkjSCCOFT'
  'QCVjFzXwk3OiUESyg/EmVDZklHTCYNKEoxhw4idFN2WzVXWklcOF8tNGdoDjR1ZmtAkKGRoo'
  'KSo4OTpISUpXWFlaZ2hpand4eXqGh4iJipCWl5iZmqClpqeoqaqwtba3uLm6wMTFxsfIycrQ'
  '1NXW19jZ2uDk5ebn6Onq8/T19vf4+fr/xAAfAQADAQEBAQEBAQEBAAAAAAABAgADBAUGBwgJ'
  'Cgv/xADDEQACAgEDAwMCAwUCBQIEBIcBAAIRAxASIQQgMUETBTAiMlEUQAYzI2FCFXFSNIFQ'
  'JJGhQ7EWB2I1U/DRJWDBROFy8ReCYzZwJkVUkiei0ggJChgZGigpKjc4OTpGR0hJSlVWV1hZ'
  'WmRlZmdoaWpzdHV2d3h5eoCDhIWGh4iJipCTlJWWl5iZmqCjpKWmp6ipqrCys7S1tre4ubrA'
  'wsPExcbHyMnK0NPU1dbX2Nna4OLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwICAwUD'
  'AwMFBgUFBQUGCAYGBgYGCAoICAgICAgKCgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//b'
  'AEMBAgMDBAQEBwQEBxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQ'
  'EBAQEBAQEBAQEBAQEP/aAAwDAQACEQMRAAAB9c7qx7n4v0v/2gAIAQEAAQUC2TwlsnJ//9oA'
  'CAEDEQE/Afgus6j+7sP8w+PzL//aAAgBAhEBPwHquqz+9L7z/rv/2gAIAQEABj8C/cv/xAAz'
  'EAEAAwACAgICAgMBAQAAAgsBEQAhMUFRYXGBkaGxwfDREOHxIDBAUGBwgJCgsMDQ4P/aAAgB'
  'AQABPyH6L6/1f//aAAwDAQACEQMRAAAQi//EADMRAQEBAAMAAQIFBQEBAAEBCQEAESExEEFR'
  'YSBx8JGBobHRweHxMEBQYHCAkKCwwNDg/9oACAEDEQE/EP1/y/e//9oACAECEQE/EPuD+r/N'
  '/9oACAEBAAE/EJ709+lf/9k=',
);

/// The bytes [bytes] with [edit] applied to a copy.
Uint8List _edited(Uint8List bytes, void Function(Uint8List copy) edit) {
  final Uint8List copy = Uint8List.fromList(bytes);
  edit(copy);
  return copy;
}

/// The offset of the first SOF0 marker (`FF C0`) of the baseline JPEG.
int _sof0Offset() {
  for (int i = 2; i + 1 < jpeg3x5.length; i++) {
    if (jpeg3x5[i] == 0xFF && jpeg3x5[i + 1] == 0xC0) return i;
  }
  throw StateError('no SOF0');
}

Matcher _imageError(String message) => throwsA(
  isA<ArgumentError>()
      .having((ArgumentError e) => e.name, 'name', 'image')
      .having((ArgumentError e) => e.message, 'message', contains(message)),
);

void main() {
  group('XlsxImageFormat', () {
    test('names the file extension and the content type', () {
      expect(XlsxImageFormat.png.extension, 'png');
      expect(XlsxImageFormat.png.contentType, ContentType.png);
      expect(XlsxImageFormat.jpeg.extension, 'jpeg');
      expect(XlsxImageFormat.jpeg.contentType, ContentType.jpeg);
      expect(ContentType.png, 'image/png');
      expect(ContentType.jpeg, 'image/jpeg');
    });
  });

  group('XlsxImage', () {
    test('holds the bytes as given, not a copy', () {
      expect(identical(XlsxImage(png4x2).bytes, png4x2), isTrue);
    });

    test('sniffs PNG and JPEG from the signature', () {
      expect(XlsxImage(png4x2).format, XlsxImageFormat.png);
      expect(XlsxImage(jpeg3x5).format, XlsxImageFormat.jpeg);
      expect(XlsxImage(_progressive6x4).format, XlsxImageFormat.jpeg);
      expect(
        XlsxImage(
          Uint8List.fromList(<int>[
            0x89,
            0x50,
            0x4E,
            0x47,
            0x0D,
            0x0A,
            0x1A,
            0x0A,
          ]),
        ).format,
        XlsxImageFormat.png,
      );
      expect(
        XlsxImage(Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF])).format,
        XlsxImageFormat.jpeg,
      );
    });

    test('knows no other format', () {
      final List<List<int>> others = <List<int>>[
        <int>[],
        <int>[0xFF, 0xD8],
        <int>[0xFF, 0xD8, 0x00],
        <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A],
        <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0B],
        ascii.encode('GIF89a'),
        <int>[...ascii.encode('RIFF'), 0, 0, 0, 0, ...ascii.encode('WEBP')],
      ];
      for (final List<int> bytes in others) {
        expect(XlsxImage(Uint8List.fromList(bytes)).format, isNull);
      }
    });

    test('== compares the bytes', () {
      final XlsxImage image = XlsxImage(png4x2);
      expect(image, XlsxImage(Uint8List.fromList(png4x2)));
      expect(image.hashCode, XlsxImage(Uint8List.fromList(png4x2)).hashCode);
      expect(image, isNot(XlsxImage(jpeg3x5)));
      expect(
        image,
        isNot(XlsxImage(_edited(png4x2, (Uint8List b) => b[80] ^= 1))),
      );
      expect(image, isNot(XlsxImage(Uint8List.sublistView(png4x2, 0, 86))));
    });

    test('toString shows the format and the length, not the bytes', () {
      expect(XlsxImage(png4x2).toString(), 'XlsxImage(png, 87 bytes)');
      expect(XlsxImage(jpeg3x5).toString(), 'XlsxImage(jpeg, 852 bytes)');
      expect(
        XlsxImage(Uint8List.fromList(ascii.encode('GIF89a'))).toString(),
        'XlsxImage(unknown, 6 bytes)',
      );
    });
  });

  group('checkImage', () {
    test('reads the size of a PNG from its IHDR', () {
      expect(checkImage(XlsxImage(png4x2)), (width: 4, height: 2));
    });

    test('reads the size of a baseline JPEG from its SOF0', () {
      expect(checkImage(XlsxImage(jpeg3x5)), (width: 3, height: 5));
    });

    test('reads the size of a progressive JPEG from its SOF2', () {
      expect(checkImage(XlsxImage(_progressive6x4)), (width: 6, height: 4));
    });

    test('reads the size from SOF0, SOF1 and SOF2', () {
      final int sof = _sof0Offset();
      for (final int marker in <int>[0xC0, 0xC1, 0xC2]) {
        final Uint8List bytes = _edited(
          jpeg3x5,
          (Uint8List b) => b[sof + 1] = marker,
        );
        expect(checkImage(XlsxImage(bytes)), (width: 3, height: 5));
      }
    });

    test('refuses the frame headers Excel cannot show', () {
      // Lossless (SOF3), hierarchical (SOF5-7) and arithmetic-coded
      // (SOF9-11, SOF13-15) JPEGs.
      final int sof = _sof0Offset();
      for (final int marker in <int>[
        0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF, //
      ]) {
        final Uint8List bytes = _edited(
          jpeg3x5,
          (Uint8List b) => b[sof + 1] = marker,
        );
        expect(
          () => checkImage(XlsxImage(bytes)),
          _imageError('SOF${marker - 0xC0}'),
          reason: 'marker ${marker.toRadixString(16)}',
        );
      }
    });

    test('refuses a frame header shorter than 8 bytes', () {
      // The length counts itself, the precision, the height and the width;
      // 7 ends inside the width. The bytes after it still hold a width.
      final int sof = _sof0Offset();
      for (final int length in <int>[2, 5, 7]) {
        final Uint8List bytes = _edited(jpeg3x5, (Uint8List b) {
          b[sof + 2] = 0;
          b[sof + 3] = length;
        });
        expect(
          () => checkImage(XlsxImage(bytes)),
          _imageError(
            'frame header at byte $sof of the JPEG has the length '
            '$length, below 8',
          ),
          reason: 'length $length',
        );
      }
    });

    test('skips fill bytes and the markers without a length', () {
      // SOI, then TEM (FF 01), RST0 (FF D0) and two fill bytes before the
      // APP0 marker of the baseline JPEG.
      final Uint8List bytes = Uint8List.fromList(<int>[
        0xFF, 0xD8, 0xFF, 0x01, 0xFF, 0xD0, 0xFF, 0xFF, //
        ...Uint8List.sublistView(jpeg3x5, 2),
      ]);
      expect(checkImage(XlsxImage(bytes)), (width: 3, height: 5));
    });

    test('skips the segments that are not frame headers', () {
      // C4 (Huffman table), C8 (reserved) and CC (arithmetic conditioning)
      // look like SOF markers but are not; the walk passes over them.
      final int sof = _sof0Offset();
      for (final int marker in <int>[0xC4, 0xC8, 0xCC]) {
        final Uint8List bytes = _edited(
          jpeg3x5,
          (Uint8List b) => b[sof + 1] = marker,
        );
        expect(
          () => checkImage(XlsxImage(bytes)),
          _imageError('no frame header'),
          reason: 'marker ${marker.toRadixString(16)}',
        );
      }
    });

    test('refuses a GIF and a WebP', () {
      expect(
        () => checkImage(XlsxImage(Uint8List.fromList(ascii.encode('GIF89a')))),
        _imageError('neither a PNG nor a JPEG'),
      );
      expect(
        () => checkImage(
          XlsxImage(
            Uint8List.fromList(<int>[
              ...ascii.encode('RIFF'),
              0x24,
              0,
              0,
              0,
              ...ascii.encode('WEBPVP8 '),
            ]),
          ),
        ),
        _imageError('neither a PNG nor a JPEG'),
      );
    });

    test('refuses a PNG cut short before its size', () {
      expect(
        () => checkImage(XlsxImage(Uint8List.sublistView(png4x2, 0, 20))),
        _imageError('cut short'),
      );
      expect(
        () => checkImage(XlsxImage(Uint8List.sublistView(png4x2, 0, 23))),
        _imageError('cut short'),
      );
      expect(checkImage(XlsxImage(Uint8List.sublistView(png4x2, 0, 24))), (
        width: 4,
        height: 2,
      ));
    });

    test('refuses a PNG whose first chunk is not IHDR', () {
      expect(
        () => checkImage(
          XlsxImage(_edited(png4x2, (Uint8List b) => b[15] = 0x58)),
        ),
        _imageError('IHDR'),
      );
    });

    test('refuses a PNG of width or height 0', () {
      expect(
        () =>
            checkImage(XlsxImage(_edited(png4x2, (Uint8List b) => b[19] = 0))),
        _imageError('0 × 2'),
      );
      expect(
        () =>
            checkImage(XlsxImage(_edited(png4x2, (Uint8List b) => b[23] = 0))),
        _imageError('4 × 0'),
      );
    });

    test('refuses a JPEG with no frame header before its end', () {
      // SOI, an APP0 segment, EOI.
      final Uint8List noFrame = Uint8List.fromList(<int>[
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00, 0xFF, 0xD9, //
      ]);
      expect(
        () => checkImage(XlsxImage(noFrame)),
        _imageError('no frame header'),
      );
      // The baseline JPEG cut right before its SOF0.
      expect(
        () => checkImage(
          XlsxImage(Uint8List.sublistView(jpeg3x5, 0, _sof0Offset())),
        ),
        _imageError('no frame header'),
      );
      // A scan (SOS) before any frame header.
      final Uint8List scanFirst = Uint8List.fromList(<int>[
        0xFF, 0xD8, 0xFF, 0xDA, 0x00, 0x02, 0x00, 0x00, //
      ]);
      expect(
        () => checkImage(XlsxImage(scanFirst)),
        _imageError('no frame header'),
      );
    });

    test('refuses a JPEG cut short in a segment or its frame header', () {
      final int sof = _sof0Offset();
      for (final int end in <int>[3, 5, 30, sof + 1, sof + 3, sof + 8]) {
        expect(
          () => checkImage(XlsxImage(Uint8List.sublistView(jpeg3x5, 0, end))),
          _imageError('cut short'),
          reason: 'cut at $end',
        );
      }
      expect(
        checkImage(XlsxImage(Uint8List.sublistView(jpeg3x5, 0, sof + 9))),
        (width: 3, height: 5),
      );
    });

    test('refuses a JPEG whose segments do not start with FF', () {
      // Byte 20 starts the second segment (FF E1), after the 16-byte APP0.
      final Uint8List bytes = _edited(jpeg3x5, (Uint8List b) => b[20] = 0x00);
      expect(() => checkImage(XlsxImage(bytes)), _imageError('marker'));
    });

    test('refuses a JPEG segment length below 2', () {
      final Uint8List bytes = _edited(jpeg3x5, (Uint8List b) {
        b[4] = 0;
        b[5] = 1;
      });
      expect(() => checkImage(XlsxImage(bytes)), _imageError('length'));
    });

    test('refuses a JPEG of width or height 0', () {
      final int sof = _sof0Offset();
      expect(
        () => checkImage(
          XlsxImage(_edited(jpeg3x5, (Uint8List b) => b[sof + 6] = 0)),
        ),
        _imageError('3 × 0'),
      );
      expect(
        () => checkImage(
          XlsxImage(_edited(jpeg3x5, (Uint8List b) => b[sof + 8] = 0)),
        ),
        _imageError('0 × 5'),
      );
    });
  });
}
