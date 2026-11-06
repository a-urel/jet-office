// Architecture guard: jet_charts_core depends on jet_core only.
//
// `pubspec.yaml` lists exactly `jet_core` under `dependencies:`, and no file
// under lib/ imports a package other than jet_charts_core and jet_core
// (AGENTS.md, "Hard rules").
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'support/lib_sources.dart';

/// The names of the top-level entries of the `dependencies:` section of
/// [pubspec]: lines indented by two spaces, comments and blank lines aside.
/// Deeper lines (a `path:` of an entry) are not names.
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

/// A quoted `package:` URI that is neither `package:jet_charts_core/` nor
/// `package:jet_core/`.
final RegExp _foreign = RegExp(
  r'''['"]package:(?!jet_charts_core/|jet_core/)''',
);

List<String> _offenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (_foreign.hasMatch(source.code)) source.path,
];

void main() {
  test('pubspec.yaml depends on jet_core only', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    expect(_dependencyNames(pubspec), <String>['jet_core']);
  });

  test('the check finds the names of the dependencies section only', () {
    const String pubspec = '''
name: x
dependencies:
  # a comment

  archive: ^4.0.9
  foo:
    path: ../foo
dev_dependencies:
  test: ^1.26.0
''';
    expect(_dependencyNames(pubspec), <String>['archive', 'foo']);
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
      LibSource('lib/src/b.dart', 'export "package:xml/xml.dart";'),
      LibSource(
        'lib/src/c.dart',
        "import 'package:jet_office/jet_office.dart';",
      ),
      LibSource(
        'lib/src/fine.dart',
        "// import 'package:foo/foo.dart';\n"
            "import 'package:jet_core/jet_core.dart';\n"
            "import 'package:jet_charts_core/src/x.dart';\n"
            "import 'dart:convert';\n"
            "import 'x.dart';",
      ),
    ];
    expect(_offenders(fixtures), <String>[
      'lib/src/a.dart',
      'lib/src/b.dart',
      'lib/src/c.dart',
    ]);
  });
}
