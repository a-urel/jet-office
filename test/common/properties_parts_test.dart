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

const String _rel = 'http://schemas.openxmlformats.org/';

/// A package holding [core] as its core properties part and, when given,
/// [app] and [custom] as its extended and custom ones.
OpcPackage _package(String core, {String? app, String? custom}) {
  String override(String part, String type) =>
      '<Override PartName="/docProps/$part.xml" ContentType="application/'
      'vnd.openxmlformats-$type+xml"/>';
  String relationship(String id, String type, String part) =>
      '<Relationship Id="$id" Type="$_rel$type" '
      'Target="docProps/$part.xml"/>';
  return OpcPackage.read(
    _reader(
      buildZipOrdered(<(String, List<int>)>[
        (
          '[Content_Types].xml',
          utf8.encode(
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Types xmlns="${_rel}package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/'
            'vnd.openxmlformats-package.relationships+xml"/>'
            '${override('core', 'package.core-properties')}'
            '${app == null ? '' : override('app', 'officedocument.extended-properties')}'
            '${custom == null ? '' : override('custom', 'officedocument.custom-properties')}'
            '</Types>',
          ),
        ),
        (
          '_rels/.rels',
          utf8.encode(
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="${_rel}package/2006/relationships">'
            '${relationship('rId1', 'package/2006/relationships/metadata/core-properties', 'core')}'
            '${app == null ? '' : relationship('rId2', 'officeDocument/2006/relationships/extended-properties', 'app')}'
            '${custom == null ? '' : relationship('rId3', 'officeDocument/2006/relationships/custom-properties', 'custom')}'
            '</Relationships>',
          ),
        ),
        ('docProps/core.xml', utf8.encode(core)),
        if (app != null) ('docProps/app.xml', utf8.encode(app)),
        if (custom != null) ('docProps/custom.xml', utf8.encode(custom)),
      ]),
    ),
    maxDepth: 64,
  );
}

const String _app =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Properties xmlns="${_rel}officeDocument/2006/extended-properties">\n'
    '  <Application>Microsoft Office Word</Application>\n</Properties>';

const String _custom =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Properties xmlns="${_rel}officeDocument/2006/custom-properties" '
    'xmlns:vt="${_rel}officeDocument/2006/docPropsVTypes">\n  <property '
    'fmtid="{D5CDD505-2E9C-101B-9397-08002B2CF9AE}" pid="2" name="P">'
    '<vt:lpwstr>v</vt:lpwstr></property>\n</Properties>';

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

  test('a swap that changes core leaves app and custom as stored', () {
    final OpcPackage package = _package(_core, app: _app, custom: _custom);
    final PropertiesState state = PropertiesState.load(
      _Source(package),
      (String element) => fail('no warning: $element'),
      encodeOnLoad: false,
    );
    final OfficeProperties now = state.parts.merged;
    expect(now.application, 'Microsoft Office Word');
    expect(now.custom, <String, Object>{'P': 'v'});
    final PropertyParts before = state.parts;
    state.swap(
      before.withProperties(
        OfficeProperties(
          title: 'U',
          revision: now.revision,
          application: now.application,
          custom: now.custom,
        ),
      ),
    );
    expect(package.isLoaded('docProps/core.xml'), isTrue);
    expect(package.isLoaded('docProps/app.xml'), isFalse);
    expect(package.isLoaded('docProps/custom.xml'), isFalse);
    state.swap(before);
    expect(package.isLoaded('docProps/app.xml'), isFalse);
    expect(package.isLoaded('docProps/custom.xml'), isFalse);
    final OpcPackage saved = OpcPackage.read(
      _reader(_saved(package)),
      maxDepth: 64,
    );
    expect(utf8.decode(saved.originalBytes('docProps/core.xml')), _core);
    expect(utf8.decode(saved.originalBytes('docProps/app.xml')), _app);
    expect(utf8.decode(saved.originalBytes('docProps/custom.xml')), _custom);
  });
}
