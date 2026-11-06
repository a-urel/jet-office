// Architecture guard: jet_core knows no file format.
//
// A name such as `XlsxColor` or `XlsxReader` in `lib/` means the engine has
// grown a dependency on the XLSX layer of jet_office (AGENTS.md, "Hard
// rules"). Lowercase paths such as `lib/src/xlsx/format/` in provenance
// comments are history and do not match.
@TestOn('vm')
library;

import 'package:test/test.dart';

import 'support/lib_sources.dart';

/// `Xlsx` followed by a capital: a type or constant name, comments included.
final RegExp _xlsxName = RegExp('Xlsx[A-Z]');

List<String> _offenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (_xlsxName.hasMatch(source.text)) source.path,
];

void main() {
  test('no file under lib/ names an Xlsx type', () {
    expect(_offenders(libSources()), isEmpty);
  });

  test('the guard flags an Xlsx name, in code or in a comment', () {
    const List<LibSource> fixtures = <LibSource>[
      LibSource('lib/src/a.dart', 'final XlsxColor color = red;'),
      LibSource(
        'lib/src/b.dart',
        '/// Shown by [XlsxNumberFormatter].\nint b;',
      ),
      LibSource('lib/src/c.dart', 'const String s = "XlsxReader";'),
      LibSource(
        'lib/src/fine.dart',
        '/// Moved from jet_office\'s lib/src/xlsx/format/ at commit 632115d.\n'
            '// The xlsx reader and Xlsx files are history.\n'
            'int fine;',
      ),
    ];
    expect(_offenders(fixtures), <String>[
      'lib/src/a.dart',
      'lib/src/b.dart',
      'lib/src/c.dart',
    ]);
  });
}
