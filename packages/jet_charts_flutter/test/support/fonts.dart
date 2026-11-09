/// Loads the Roboto fonts the golden tests draw with.
///
/// It reads `test/fonts/` with `dart:io`, so only VM tests (`@TestOn('vm')`)
/// import it. The tests run from the package root.
library;

import 'dart:io';

import 'package:flutter/services.dart';

bool _loaded = false;

/// Registers `test/fonts/Roboto-Regular.ttf` and `Roboto-Bold.ttf` as the
/// family `Roboto`, once per test isolate.
Future<void> loadTestFonts() async {
  if (_loaded) return;
  final FontLoader loader = FontLoader('Roboto');
  for (final String name in <String>['Roboto-Regular.ttf', 'Roboto-Bold.ttf']) {
    final Uint8List bytes = File('test/fonts/$name').readAsBytesSync();
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
  _loaded = true;
}
