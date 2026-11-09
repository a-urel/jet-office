// Architecture guard: jet_office's runtime dependencies are archive, jet_core
// and jet_charts_core.
//
// `pubspec.yaml` lists exactly these three under `dependencies:` (decisions
// 0001, 0012 and 0014), and no file under lib/ imports another package. Only
// lib/src/zip/archive_adapter.dart may import archive
// (`archive_isolation_test.dart`).
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'support/lib_sources.dart';

/// The names of the entries of the top-level `dependencies:` section of
/// [pubspec]: its lines indented by exactly two spaces, comments aside.
List<String> _dependencies(String pubspec) {
  final List<String> names = <String>[];
  bool inSection = false;
  for (final String line in pubspec.split('\n')) {
    if (line.startsWith('dependencies:')) {
      inSection = true;
    } else if (line.isNotEmpty && !line.startsWith(RegExp(r'[ #]'))) {
      inSection = false;
    } else if (inSection) {
      final RegExpMatch? entry = RegExp(r'^  ([a-z_0-9]+):').firstMatch(line);
      if (entry != null) names.add(entry.group(1)!);
    }
  }
  return names;
}

/// A quoted `package:` URI of a package other than archive, jet_core and jet_charts_core.
final RegExp _foreign = RegExp(
  r'''['"]package:(?!archive/|jet_core/|jet_charts_core/)''',
);

List<String> _offenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (_foreign.hasMatch(source.code)) source.path,
];

void main() {
  test(
    'pubspec.yaml depends on archive, jet_core and jet_charts_core only',
    () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      expect(_dependencies(pubspec), <String>[
        'archive',
        'jet_core',
        'jet_charts_core',
      ]);
    },
  );

  test('the check reads the names of the dependencies section only', () {
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
    expect(_dependencies(pubspec), <String>['archive', 'foo']);
    expect(
      _dependencies('name: x\ndependencies:\n\ndev_dependencies:\n'),
      isEmpty,
    );
  });

  test('no file under lib/ imports another package', () {
    expect(_offenders(libSources()), isEmpty);
  });

  test('the guard flags a foreign package import and nothing else', () {
    const List<LibSource> fixtures = <LibSource>[
      LibSource('lib/src/a.dart', "import 'package:xml/xml.dart';"),
      LibSource('lib/src/b.dart', 'export "package:meta/meta.dart";'),
      LibSource(
        'lib/src/fine.dart',
        "// import 'package:foo/foo.dart';\n"
            "import 'package:archive/archive.dart';\n"
            "import 'package:jet_core/jet_core.dart';\n"
            "import 'package:jet_charts_core/jet_charts_core.dart';\n"
            "import 'dart:convert';\n"
            "import 'x.dart';",
      ),
    ];
    expect(_offenders(fixtures), <String>['lib/src/a.dart', 'lib/src/b.dart']);
  });
}
