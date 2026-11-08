/// Reads a file of the package for a test that may run in a browser.
///
/// New in jet_office. A browser cannot read the owner's Word file from disk,
/// so the benchmark starts this library with `spawnHybridUri`: it always runs
/// on the VM, reads the file named by the message (a path relative to the
/// package root, where `dart test` runs) and sends its bytes back as a list of
/// integers, which is the same on both platforms. `channel` is a
/// `StreamChannel`; it is typed `dynamic` only because `stream_channel` is not
/// a dependency of this package.
library;

import 'dart:io' show File;

/// The entry point `spawnHybridUri` calls: sends the bytes of the file at the
/// path in [message] to [channel] and closes it.
// ignore: avoid_dynamic_calls
void hybridMain(dynamic channel, Object? message) {
  final List<int> bytes = File('$message').readAsBytesSync();
  // ignore: avoid_dynamic_calls
  channel.sink.add(bytes);
  // ignore: avoid_dynamic_calls
  channel.sink.close();
}
