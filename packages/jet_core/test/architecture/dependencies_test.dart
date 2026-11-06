// Architecture guard: jet_core has no dependencies.
//
// `pubspec.yaml` lists nothing under `dependencies:`, and no file under lib/
// imports a package other than jet_core itself (AGENTS.md, "Hard rules").
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'support/lib_sources.dart';

/// The entries of the top-level `dependencies:` section of [pubspec]:
/// indented lines that are not comments, up to the next top-level key.
List<String> _dependencies(String pubspec) {
  final List<String> entries = <String>[];
  bool inSection = false;
  for (final String line in pubspec.split('\n')) {
    if (line.startsWith('dependencies:')) {
      inSection = true;
    } else if (line.isNotEmpty && !line.startsWith(RegExp(r'[ #]'))) {
      inSection = false;
    } else if (inSection &&
        line.trim().isNotEmpty &&
        !line.trimLeft().startsWith('#')) {
      entries.add(line.trim());
    }
  }
  return entries;
}

/// A quoted `package:` URI that is not `package:jet_core/`.
final RegExp _foreign = RegExp(r'''['"]package:(?!jet_core/)''');

List<String> _offenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (_foreign.hasMatch(source.code)) source.path,
];

void main() {
  test('pubspec.yaml has no dependencies', () {
    final String pubspec = File('pubspec.yaml').readAsStringSync();
    expect(_dependencies(pubspec), isEmpty);
  });

  test('the check finds entries of the dependencies section only', () {
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
    expect(_dependencies(pubspec), <String>[
      'archive: ^4.0.9',
      'foo:',
      'path: ../foo',
    ]);
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
      LibSource('lib/src/a.dart', "import 'package:archive/archive.dart';"),
      LibSource('lib/src/b.dart', 'export "package:xml/xml.dart";'),
      LibSource('lib/src/c.dart', "import 'package:meta/meta.dart';"),
      LibSource(
        'lib/src/fine.dart',
        "// import 'package:foo/foo.dart';\n"
            "import 'package:jet_core/src/x.dart';\n"
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
