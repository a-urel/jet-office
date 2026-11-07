import 'dart:typed_data';

import 'package:jet_office/jet_office.dart';
import 'package:jet_office/src/drawingml/media.dart';
import 'package:jet_office/src/opc/package.dart';
import 'package:jet_office/src/zip/archive_adapter.dart';
import 'package:test/test.dart';

import '../fixtures/m4_fixtures.dart';
import '../xlsx/read/support/zip_builder.dart';

OpcPackage _package(Map<String, List<int>> parts) {
  final Uint8List zip = buildZip(<String, List<int>>{
    '[Content_Types].xml':
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                '<Default Extension="png" ContentType="image/png"/>'
                '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                '</Types>'
            .codeUnits,
    ...parts,
  });
  return OpcPackage.read(
    ZipReader(
      zip,
      maxEntries: 1000,
      maxEntryBytes: 1 << 24,
      maxTotalBytes: 1 << 26,
      maxCompressionRatio: 1000,
    ),
    maxDepth: 64,
  );
}

void main() {
  test('MediaIndex finds the same list and equal bytes, and not different '
      'bytes of equal length', () {
    final Uint8List other = Uint8List.fromList(png4x2)
      ..[png4x2.length - 1] ^= 1;
    final OpcPackage package = _package(<String, List<int>>{
      'xl/media/image1.png': png4x2,
      'xl/media/image7.png': other,
    });
    final DrawingMediaIndex index = DrawingMediaIndex(package);
    final OfficeImage first = index.imageOf('xl/media/image1.png');
    expect(
      identical(index.imageOf('/xl/media/image1.png').bytes, first.bytes),
      isTrue,
    );
    expect(index.partFor(first), 'xl/media/image1.png');
    expect(
      index.partFor(OfficeImage(Uint8List.fromList(png4x2))),
      'xl/media/image1.png',
    );
    expect(index.partFor(OfficeImage(other)), 'xl/media/image7.png');
    final Uint8List third = Uint8List.fromList(png4x2)..[10] ^= 1;
    expect(index.partFor(OfficeImage(third)), isNull);
    expect(index.nextNumber(), 8);
  });

  test('nextNumber is 1 for a package without media', () {
    expect(DrawingMediaIndex(_package(<String, List<int>>{})).nextNumber(), 1);
  });

  group('a part added or removed', () {
    final Uint8List png = Uint8List.fromList(<int>[1, 2, 3]);

    test('add makes an image found by its bytes, after a scan too', () {
      final OpcPackage package = OpcPackage.empty();
      final DrawingMediaIndex index = DrawingMediaIndex(package);
      expect(index.partFor(OfficeImage(png)), isNull);
      final String name = package.addPart(
        'xl/media/image1.png',
        'image/png',
        DrawingMediaContent(png),
      );
      final OfficeImage image = OfficeImage(png);
      index.add(name, image);
      expect(index.imageOf(name), same(image));
      expect(
        index.partFor(OfficeImage(Uint8List.fromList(png))),
        'xl/media/image1.png',
      );
    });

    test('forget stops finding it', () {
      final OpcPackage package = OpcPackage.empty();
      final DrawingMediaIndex index = DrawingMediaIndex(package);
      final String name = package.addPart(
        'xl/media/image1.png',
        'image/png',
        DrawingMediaContent(png),
      );
      final OfficeImage image = OfficeImage(png);
      index.add(name, image);
      index.partFor(image);
      expect(index.loaded(name), same(image));
      index.forget(name);
      package.removePart(name);
      expect(index.loaded(name), isNull);
      expect(index.partFor(OfficeImage(Uint8List.fromList(png))), isNull);
      expect(index.partFor(image), isNull);
    });

    test('forgetting what was never read does nothing', () {
      final DrawingMediaIndex index = DrawingMediaIndex(OpcPackage.empty());
      index.forget('xl/media/image9.png');
      expect(index.loaded('xl/media/image9.png'), isNull);
    });

    test('the content of a media part is its bytes', () {
      expect(DrawingMediaContent(png).encode(), <Uint8List>[png]);
    });
  });
}
