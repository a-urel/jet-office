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
}
