// Architecture guard: lib/ stays pure Dart and runs everywhere.
//
// jet_office is bytes in, bytes out (AGENTS.md, "Pure Dart, web-safe";
// decision 0001). No file under lib/ may import or export a library that is
// missing on the web, missing on the VM, or ties the package to Flutter.
@TestOn('vm')
library;

import 'package:test/test.dart';

import 'support/lib_sources.dart';

/// A quoted URI no file under lib/ may name.
final RegExp _forbidden = RegExp(
  r'''['"]('''
  // VM only: missing in a browser.
  r'dart:(io|ffi|isolate|mirrors|cli)'
  // Web only: missing on the VM, so missing in a Dart server.
  r'''|dart:(html|indexed_db|svg|web_audio|web_gl|js|js_util|js_interop|js_interop_unsafe|ui_web)['"]'''
  r'|package:web/'
  // Flutter.
  r'''|dart:ui['"]|package:(flutter|flutter_test|sky_engine)/'''
  r')',
);

List<String> _offenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (_forbidden.hasMatch(source.code)) source.path,
];

void main() {
  test('no file under lib/ imports a platform-bound library', () {
    expect(_offenders(libSources()), isEmpty);
  });

  test('the guard flags platform imports and nothing else', () {
    const List<LibSource> fixtures = <LibSource>[
      LibSource('lib/src/io.dart', "import 'dart:io';"),
      LibSource('lib/src/ui.dart', 'import "dart:ui" as ui;'),
      LibSource('lib/src/html.dart', "import 'dart:html';"),
      LibSource('lib/src/isolate.dart', "import 'dart:isolate';"),
      LibSource(
        'lib/src/flutter.dart',
        "import 'package:flutter/foundation.dart';",
      ),
      LibSource(
        'lib/src/reexport.dart',
        "export 'package:flutter/widgets.dart';",
      ),
      LibSource(
        'lib/src/fine.dart',
        "import 'dart:convert';\nimport 'dart:typed_data';",
      ),
      LibSource(
        'lib/src/doc.dart',
        "/// Unlike a 'dart:io' File, this takes bytes.\nconst int x = 0;",
      ),
    ];
    expect(_offenders(fixtures), <String>[
      'lib/src/io.dart',
      'lib/src/ui.dart',
      'lib/src/html.dart',
      'lib/src/isolate.dart',
      'lib/src/flutter.dart',
      'lib/src/reexport.dart',
    ]);
  });
}
