/// Test helper: unzips an XLSX file into its parts.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// The text parts of the XLSX file [bytes], keyed by entry name, decoded as
/// UTF-8.
///
/// The map iterates in the order the entries appear in the archive. The
/// media parts (`xl/media/`) are binary and left out; [readXlsxBytes]
/// returns every part, media included.
Map<String, String> readXlsx(Uint8List bytes) => <String, String>{
  for (final MapEntry<String, Uint8List> part in readXlsxBytes(bytes).entries)
    if (!part.key.startsWith('xl/media/')) part.key: utf8.decode(part.value),
};

/// Every part of the XLSX file [bytes], keyed by entry name, as bytes, in
/// the order the entries appear in the archive.
Map<String, Uint8List> readXlsxBytes(Uint8List bytes) {
  final Archive archive = ZipDecoder().decodeBytes(bytes);
  return <String, Uint8List>{
    for (final ArchiveFile file in archive.files)
      if (file.isFile) file.name: Uint8List.fromList(file.content),
  };
}
