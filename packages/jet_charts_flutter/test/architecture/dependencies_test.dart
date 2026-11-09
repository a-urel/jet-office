// Architecture guard: jet_charts_flutter depends on flutter, jet_charts_core
// and jet_core only.
//
// `pubspec.yaml` lists exactly those under `dependencies:`, and no file under
// lib/ imports a package other than them and jet_charts_flutter itself
// (AGENTS.md, "Hard rules").
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/lib_sources.dart';

/// The names of the top-level entries of the `dependencies:` section of
/// [pubspec]: lines indented by two spaces, comments and blank lines aside.
/// Deeper lines (a `path:` or `sdk:` of an entry) are not names.
List<String> _dependencyNames(String pubspec) {
  final List<String> names = <String>[];
  bool inSection = false;
  for (final String line in pubspec.split('\n')) {
    if (line.startsWith('dependencies:')) {
      inSection = true;
    } else if (line.isNotEmpty && !line.startsWith(RegExp(r'[ #]'))) {
      inSection = false;
    } else if (inSection &&
        line.trim().isNotEmpty &&
        !line.trimLeft().startsWith('#') &&
        RegExp(r'^ {1,2}\S').hasMatch(line)) {
      names.add(line.trim().split(':').first);
    }
  }
  return names;
}

/// The packages lib/ may import from.
const Set<String> _allowedPackages = <String>{
  'flutter',
  'jet_charts_core',
  'jet_core',
  'jet_charts_flutter',
};

/// Whether [uri] names a package other than the allowed ones.
bool _foreign(String uri) {
  if (!uri.startsWith('package:')) {
    return false;
  }
  final String name = uri.substring('package:'.length).split('/').first;
  return !_allowedPackages.contains(name);
}

List<String> _offenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (directiveUris(source).any(_foreign)) source.path,
];

void main() {
  test('pubspec.yaml depends on flutter, jet_charts_core and jet_core', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    expect(_dependencyNames(pubspec), <String>[
      'flutter',
      'jet_charts_core',
      'jet_core',
    ]);
  });

  test('the check finds the names of the dependencies section only', () {
    const String pubspec = '''
name: x
dependencies:
  # a comment

  flutter:
    sdk: flutter
  foo:
    path: ../foo
dev_dependencies:
  flutter_test:
    sdk: flutter
''';
    expect(_dependencyNames(pubspec), <String>['flutter', 'foo']);
    expect(
      _dependencyNames('name: x\ndependencies:\n\ndev_dependencies:\n'),
      isEmpty,
    );
  });

  test('no file under lib/ imports another package', () {
    expect(_offenders(libSources()), isEmpty);
  });

  test('the guard flags a foreign package import and nothing else', () {
    const List<LibSource> fixtures = <LibSource>[
      LibSource('lib/src/a.dart', "import 'package:archive/archive.dart';"),
      LibSource('lib/src/b.dart', 'export "package:fl_chart/fl_chart.dart";'),
      LibSource(
        'lib/src/c.dart',
        "import 'package:jet_office/jet_office.dart';",
      ),
      LibSource(
        'lib/src/d.dart',
        "import 'package:flutter_test/flutter_test.dart';",
      ),
      LibSource(
        'lib/src/fine.dart',
        "// import 'package:foo/foo.dart';\n"
            "import 'package:flutter/widgets.dart';\n"
            "import 'package:jet_core/jet_core.dart';\n"
            "import 'package:jet_charts_core/jet_charts_core.dart';\n"
            "import 'package:jet_charts_flutter/src/x.dart';\n"
            "import 'dart:ui';\n"
            "import 'x.dart';",
      ),
    ];
    expect(_offenders(fixtures), <String>[
      'lib/src/a.dart',
      'lib/src/b.dart',
      'lib/src/c.dart',
      'lib/src/d.dart',
    ]);
  });
}
