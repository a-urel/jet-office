/// Test helper: builds ZIP archives in memory and patches their headers, to
/// feed the reader well-formed, lying and broken packages.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';

/// The local file header signature, `PK\x03\x04`.
const int _localSignature = 0x04034b50;

/// The central directory file header signature, `PK\x01\x02`.
const int _centralSignature = 0x02014b50;

/// A ZIP archive holding [entries], in map order.
///
/// Entries are deflated, or stored uncompressed when [store] is true (so a
/// test can find and change an entry's bytes in the archive).
Uint8List buildZip(Map<String, List<int>> entries, {bool store = false}) {
  final Archive archive = Archive();
  for (final MapEntry<String, List<int>> entry in entries.entries) {
    final ArchiveFile file = ArchiveFile.bytes(entry.key, entry.value);
    if (store) file.compression = CompressionType.none;
    archive.addFile(file);
  }
  return ZipEncoder().encodeBytes(archive);
}

/// A copy of [zip] in which [entry] declares an uncompressed size of [size],
/// in both its local header and its central directory header.
///
/// Throws a [StateError] when [entry] is not in [zip].
Uint8List patchDeclaredSize(Uint8List zip, String entry, int size) {
  final Uint8List out = Uint8List.fromList(zip);
  final ByteData data = ByteData.sublistView(out);
  int patched = 0;
  for (final ({int offset, bool central}) header in _headersOf(out, entry)) {
    // Local header: size at 22. Central header: size at 24.
    final int field = header.offset + (header.central ? 24 : 22);
    data.setUint32(field, size, Endian.little);
    patched++;
  }
  if (patched == 0) throw StateError('No entry "$entry" in the archive.');
  return out;
}

/// A copy of [zip] in which [entry] has the general purpose flag bits
/// [flags] set, in both its local header and its central directory header.
///
/// Bit 0 marks an encrypted entry. Throws a [StateError] when [entry] is not
/// in [zip].
Uint8List patchFlags(Uint8List zip, String entry, int flags) {
  final Uint8List out = Uint8List.fromList(zip);
  final ByteData data = ByteData.sublistView(out);
  int patched = 0;
  for (final ({int offset, bool central}) header in _headersOf(out, entry)) {
    // Local header: flags at 6. Central header: flags at 8.
    final int field = header.offset + (header.central ? 8 : 6);
    data.setUint16(
      field,
      data.getUint16(field, Endian.little) | flags,
      Endian.little,
    );
    patched++;
  }
  if (patched == 0) throw StateError('No entry "$entry" in the archive.');
  return out;
}

/// The local and central directory headers of [zip] that name [entry].
///
/// Scans for header signatures and checks the name at each, which is enough
/// for archives this file builds.
Iterable<({int offset, bool central})> _headersOf(
  Uint8List zip,
  String entry,
) sync* {
  final ByteData data = ByteData.sublistView(zip);
  final List<int> name = entry.codeUnits;
  for (int i = 0; i + 46 <= zip.length; i++) {
    final int signature = data.getUint32(i, Endian.little);
    final bool central = signature == _centralSignature;
    if (!central && signature != _localSignature) continue;
    final int nameLength = data.getUint16(
      i + (central ? 28 : 26),
      Endian.little,
    );
    final int nameStart = i + (central ? 46 : 30);
    if (nameLength != name.length || nameStart + nameLength > zip.length) {
      continue;
    }
    bool same = true;
    for (int k = 0; k < nameLength; k++) {
      if (zip[nameStart + k] != name[k]) {
        same = false;
        break;
      }
    }
    if (same) yield (offset: i, central: central);
  }
}
