import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/src/common/properties.dart';
import 'package:jet_office/src/common/properties_parts.dart';
import 'package:jet_office/src/opc/package.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';
import 'package:jet_office/src/zip/archive_adapter.dart';
import 'package:test/test.dart';

import '../xlsx/read/support/zip_builder.dart';

ZipReader _reader(Uint8List bytes) => ZipReader(
  bytes,
  maxEntries: 1000,
  maxEntryBytes: 1 << 24,
  maxTotalBytes: 1 << 26,
  maxCompressionRatio: 1000,
);

/// A package holding [core] as its core properties part.
OpcPackage _package(String core) => OpcPackage.read(
  _reader(
    buildZipOrdered(<(String, List<int>)>[
      (
        '[Content_Types].xml',
        utf8.encode(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
          'content-types"><Default Extension="rels" ContentType="application/'
          'vnd.openxmlformats-package.relationships+xml"/><Override '
          'PartName="/docProps/core.xml" ContentType="application/'
          'vnd.openxmlformats-package.core-properties+xml"/></Types>',
        ),
      ),
      (
        '_rels/.rels',
        utf8.encode(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/'
          '2006/relationships"><Relationship Id="rId1" Type="http://schemas.'
          'openxmlformats.org/package/2006/relationships/metadata/'
          'core-properties" Target="docProps/core.xml"/></Relationships>',
        ),
      ),
      ('docProps/core.xml', utf8.encode(core)),
    ]),
  ),
  maxDepth: 64,
);

const String _core =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/'
    '2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/'
    '1.1/">\n  <dc:title>T</dc:title>\n  <cp:revision>4</cp:revision>\n'
    '</cp:coreProperties>';

final class _Source implements PropertiesSource {
  _Source(this.package);

  @override
  final OpcPackage package;

  @override
  int get maxChildren => 100;

  @override
  int get maxTextLength => 1000;

  @override
  T guard<T>(String part, T Function() body) => body();

  @override
  XmlPullReader openXml(String part) => package.openXml(part);

  @override
  Never limitExceeded(String part, String message) => throw StateError(message);
}

Uint8List _saved(OpcPackage package) {
  final ZipWriter zip = ZipWriter();
  package.writeTo(zip);
  return zip.close()!;
}

String _corePart(Uint8List bytes) => utf8.decode(
  OpcPackage.read(
    _reader(bytes),
    maxDepth: 64,
  ).originalBytes('docProps/core.xml'),
);

void main() {
  test('encodeOnLoad: false keeps a loaded part as read until a swap', () {
    final OpcPackage package = _package(_core);
    final PropertiesState state = PropertiesState.load(
      _Source(package),
      (String element) => fail('no warning: $element'),
      encodeOnLoad: false,
    );
    expect(state.parts.merged.title, 'T');
    expect(state.parts.merged.revision, 4);
    expect(_corePart(_saved(package)), _core);
    final PropertyParts before = state.parts;
    state.swap(
      before.withProperties(const OfficeProperties(title: 'U', revision: 4)),
    );
    expect(_corePart(_saved(package)), contains('<dc:title>U</dc:title>'));
    state.swap(before);
    expect(_corePart(_saved(package)), _core);
  });

  test('encodeOnLoad by default re-encodes a loaded part', () {
    final OpcPackage package = _package(_core);
    PropertiesState.load(_Source(package), (String element) {});
    expect(_corePart(_saved(package)), isNot(_core));
  });
}
