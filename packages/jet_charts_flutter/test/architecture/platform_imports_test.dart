// Architecture guard: lib/ imports Flutter's widgets layer and nothing bound to
// one platform.
//
// jet_charts_flutter draws on every platform Flutter runs on, the web
// included. It may use Flutter's libraries other than `material.dart` and
// `cupertino.dart` (Monépro has its own design system), `dart:ui`,
// `dart:math`, `dart:async` and `dart:collection`, and never `dart:io` or
// `dart:html` (AGENTS.md, "Hard rules").
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/lib_sources.dart';

/// The `dart:` libraries lib/ may name.
const Set<String> _allowedDart = <String>{
  'dart:ui',
  'dart:math',
  'dart:async',
  'dart:collection',
};

/// The Flutter libraries lib/ may not name, though they are in the package.
const Set<String> _forbiddenFlutter = <String>{
  'package:flutter/material.dart',
  'package:flutter/cupertino.dart',
};

/// Whether lib/ may name [uri] as far as platforms go. Other packages are the
/// dependency guard's matter.
bool _allowed(String uri) {
  if (uri.startsWith('dart:')) {
    return _allowedDart.contains(uri);
  }
  if (uri.startsWith('package:flutter/')) {
    return !_forbiddenFlutter.contains(uri);
  }
  return true;
}

List<String> _offenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (!directiveUris(source).every(_allowed)) source.path,
];

void main() {
  test('no file under lib/ imports a platform-bound library', () {
    expect(_offenders(libSources()), isEmpty);
  });

  test('the guard flags platform imports and nothing else', () {
    const List<LibSource> fixtures = <LibSource>[
      LibSource('lib/src/io.dart', "import 'dart:io';"),
      LibSource('lib/src/html.dart', 'import "dart:html";'),
      LibSource('lib/src/convert.dart', "import 'dart:convert';"),
      LibSource(
        'lib/src/material.dart',
        "import 'package:flutter/material.dart';",
      ),
      LibSource(
        'lib/src/cupertino.dart',
        "export 'package:flutter/cupertino.dart' show CupertinoColors;",
      ),
      LibSource(
        'lib/src/conditional.dart',
        "import 'stub.dart'\n    if (dart.library.io) 'dart:io';",
      ),
      LibSource(
        'lib/src/fine.dart',
        "import 'dart:async';\n"
            "import 'dart:collection';\n"
            "import 'dart:math' as math;\n"
            "import 'dart:ui' as ui;\n"
            "import 'package:flutter/painting.dart';\n"
            "import 'package:flutter/widgets.dart';\n"
            "import 'package:jet_charts_core/jet_charts_core.dart';\n"
            "import 'text_measurer.dart';",
      ),
      LibSource(
        'lib/src/doc.dart',
        "/// Unlike 'package:flutter/material.dart', this has no theme.\n"
            "// import 'dart:io';\n"
            'const int x = 0;',
      ),
    ];
    expect(_offenders(fixtures), <String>[
      'lib/src/io.dart',
      'lib/src/html.dart',
      'lib/src/convert.dart',
      'lib/src/material.dart',
      'lib/src/cupertino.dart',
      'lib/src/conditional.dart',
    ]);
  });
}
