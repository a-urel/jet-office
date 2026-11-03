/// Test helper: builds DOCX packages in memory, well-formed or hostile, for
/// the DOCX reader. Nothing touches the file system, so it runs in Chrome.
///
/// The ZIP itself is written by the XLSX tests' `buildZip`, which stores or
/// deflates each entry and stamps every entry with the same time.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:jet_office/src/opc/ooxml.dart';

import '../../xlsx/read/support/zip_builder.dart';

export '../../xlsx/read/support/zip_builder.dart'
    show buildZip, patchDeclaredSize, patchFlags;

/// The namespace of `[Content_Types].xml`.
const String contentTypesNs =
    'http://schemas.openxmlformats.org/package/2006/content-types';

/// The namespace of a relationships part.
const String packageRelsNs =
    'http://schemas.openxmlformats.org/package/2006/relationships';

/// A minimal `document.xml`: one empty paragraph.
const String minimalDocument =
    '<w:document xmlns:w="${Ns.w}"><w:body><w:p/></w:body></w:document>';

/// The signature of an OLE compound file (CFB), the container of a legacy
/// `.doc` and of an encrypted Office file.
const List<int> cfbSignature = <int>[
  0xD0,
  0xCF,
  0x11,
  0xE0,
  0xA1,
  0xB1,
  0x1A,
  0xE1,
];

/// A root relationships part with one relationship of [type] (by default
/// the transitional `officeDocument`) to [target].
String rootRels(String target, {String type = RelType.officeDocument}) =>
    '<Relationships xmlns="$packageRelsNs">'
    '<Relationship Id="rId1" Type="$type" Target="$target"/>'
    '</Relationships>';

/// The entries of a DOCX package, ready for [buildZip].
///
/// The main part is [mainPath] (a ZIP entry name, no leading `/`) holding
/// [document], named by a root relationship of [relType]. When
/// [contentType] is not null, `[Content_Types].xml` overrides the main
/// part's type with it; when it is null the part has no type at all, since
/// no `xml` default is declared. [rels] replaces the root relationships
/// part, and [extra] adds or replaces entries last.
Map<String, List<int>> docxEntries({
  String mainPath = 'word/document.xml',
  String document = minimalDocument,
  String? contentType = ContentType.wmlDocument,
  String relType = RelType.officeDocument,
  String? rels,
  Map<String, List<int>> extra = const <String, List<int>>{},
}) => <String, List<int>>{
  '[Content_Types].xml': utf8.encode(
    '<Types xmlns="$contentTypesNs">'
    '<Default Extension="rels" ContentType="${ContentType.relationships}"/>'
    '${contentType == null ? '' : '<Override PartName="/$mainPath" '
              'ContentType="$contentType"/>'}'
    '</Types>',
  ),
  '_rels/.rels': utf8.encode(rels ?? rootRels(mainPath, type: relType)),
  mainPath: utf8.encode(document),
  ...extra,
};

/// A DOCX package built from [docxEntries], deflated, or stored
/// uncompressed when [store] is true (so a test can find and change an
/// entry's bytes in the archive).
Uint8List buildDocx({
  String mainPath = 'word/document.xml',
  String document = minimalDocument,
  String? contentType = ContentType.wmlDocument,
  String relType = RelType.officeDocument,
  String? rels,
  Map<String, List<int>> extra = const <String, List<int>>{},
  bool store = false,
}) => buildZip(
  docxEntries(
    mainPath: mainPath,
    document: document,
    contentType: contentType,
    relType: relType,
    rels: rels,
    extra: extra,
  ),
  store: store,
);

/// An OLE compound file of about 600 bytes: [cfbSignature], padding and,
/// when [encrypted] is true, the stream name `EncryptedPackage` in
/// UTF-16LE, which marks an encrypted Office file.
Uint8List buildCfb({required bool encrypted}) => Uint8List.fromList(<int>[
  ...cfbSignature,
  ...List<int>.filled(500, 0),
  if (encrypted)
    for (final int unit in 'EncryptedPackage'.codeUnits) ...<int>[unit, 0]
  else
    for (final int unit in 'WordDocument'.codeUnits) ...<int>[unit, 0],
  ...List<int>.filled(100, 0),
]);

/// The offset of the first occurrence of [needle] in [bytes], or -1.
int indexOfBytes(List<int> bytes, List<int> needle) {
  for (int i = 0; i + needle.length <= bytes.length; i++) {
    bool same = true;
    for (int k = 0; k < needle.length; k++) {
      if (bytes[i + k] != needle[k]) {
        same = false;
        break;
      }
    }
    if (same) return i;
  }
  return -1;
}
