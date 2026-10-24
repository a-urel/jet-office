/// Test helper: unzips an XLSX file into its parts.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// The parts of the XLSX file [bytes], keyed by entry name, decoded as UTF-8.
///
/// The map iterates in the order the entries appear in the archive.
Map<String, String> readXlsx(Uint8List bytes) {
  final Archive archive = ZipDecoder().decodeBytes(bytes);
  return <String, String>{
    for (final ArchiveFile file in archive.files)
      if (file.isFile) file.name: utf8.decode(file.content),
  };
}
