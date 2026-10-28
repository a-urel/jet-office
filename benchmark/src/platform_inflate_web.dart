/// The web has no synchronous platform inflate.
///
/// New in jet_office. The browser's `DecompressionStream` is asynchronous,
/// so it cannot stand in for the synchronous reader's inflate.
library;

import 'dart:typed_data';

/// Returns `null`: the web has no synchronous platform inflate for [raw].
Uint8List? platformInflate(Uint8List raw) => null;
