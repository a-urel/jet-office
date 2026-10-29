/// The VM's platform inflate: `dart:io`'s native zlib.
///
/// New in jet_office.
library;

import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

/// Inflates [raw], a raw deflate stream as a ZIP entry stores it, with
/// `ZLibCodec(raw: true)`; never `null` on the VM.
Uint8List? platformInflate(Uint8List raw) {
  final List<int> bytes = ZLibCodec(raw: true).decode(raw);
  return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
}
