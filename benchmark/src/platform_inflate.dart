/// A platform inflate, to compare with the reader's pure-Dart one.
///
/// New in jet_office. The VM's inflate imports `dart:io`, so it sits behind a
/// conditional export that the Chrome compile never follows, as the memory
/// probes do. The browser's `DecompressionStream` is asynchronous and cannot
/// serve a synchronous reader, so the web has none (plan ruling 4).
library;

export 'platform_inflate_vm.dart'
    if (dart.library.js_interop) 'platform_inflate_web.dart';
