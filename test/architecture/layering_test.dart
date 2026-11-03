// Architecture guard: the format layers depend on each other one way only.
//
// lib/src/common holds what XLSX and DOCX share: the warning aggregator, the
// read guard, the ZIP limits and the message locale. It must import neither
// lib/src/xlsx nor lib/src/docx. lib/src/docx may use the number formatter
// under lib/src/xlsx/format, and nothing else of lib/src/xlsx.
@TestOn('vm')
library;

import 'package:test/test.dart';

import 'support/lib_sources.dart';

const String _common = 'lib/src/common/';
const String _docx = 'lib/src/docx/';

/// The URI of every `import` or `export` directive of a source.
final RegExp _directive = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]*)['"]''',
  multiLine: true,
);

/// Whether [uri] names a file under the [layer] folder of `lib/src`
/// (`xlsx` or `docx`), by a relative path or a package URI.
bool _names(String uri, String layer) =>
    uri.contains('src/$layer/') ||
    uri.contains('../$layer/') ||
    uri.startsWith('$layer/');

/// Whether [uri] names the number formatter under `lib/src/xlsx/format`.
bool _namesFormat(String uri) => uri.contains('xlsx/format/');

Iterable<String> _uris(LibSource source) =>
    _directive.allMatches(source.code).map((RegExpMatch m) => m.group(1)!);

List<String> _commonOffenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (source.path.startsWith(_common) &&
        _uris(
          source,
        ).any((String uri) => _names(uri, 'xlsx') || _names(uri, 'docx')))
      source.path,
];

List<String> _docxOffenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (source.path.startsWith(_docx) &&
        _uris(
          source,
        ).any((String uri) => _names(uri, 'xlsx') && !_namesFormat(uri)))
      source.path,
];

void main() {
  test('lib/src/docx does not import lib/src/xlsx except xlsx/format', () {
    expect(_docxOffenders(libSources()), isEmpty);
  });

  test('lib/src/common imports neither xlsx nor docx', () {
    final List<LibSource> sources = libSources();
    expect(
      sources.map((LibSource s) => s.path),
      contains('${_common}locale.dart'),
      reason: 'lib/src/common must exist, or the guard scans nothing.',
    );
    expect(_commonOffenders(sources), isEmpty);
  });

  test('the guards flag an import', () {
    const List<LibSource> fixtures = <LibSource>[
      LibSource('lib/src/common/a.dart', "import '../xlsx/warnings.dart';"),
      LibSource(
        'lib/src/common/b.dart',
        "import 'package:jet_office/src/docx/document.dart';",
      ),
      LibSource('lib/src/common/c.dart', "export '../docx/x.dart';"),
      LibSource(
        'lib/src/common/d.dart',
        "import '../zip/archive_adapter.dart';",
      ),
      LibSource(
        'lib/src/common/e.dart',
        "// import '../xlsx/warnings.dart';\nconst int x = 0;",
      ),
      LibSource('lib/src/docx/f.dart', "import '../xlsx/warnings.dart';"),
      LibSource(
        'lib/src/docx/g.dart',
        "import '../xlsx/format/number_formatter.dart';",
      ),
      LibSource(
        'lib/src/docx/read/h.dart',
        "import '../../xlsx/read/read_limits.dart';",
      ),
      LibSource('lib/src/docx/i.dart', "import '../common/locale.dart';"),
    ];
    expect(_commonOffenders(fixtures), <String>[
      'lib/src/common/a.dart',
      'lib/src/common/b.dart',
      'lib/src/common/c.dart',
    ]);
    expect(_docxOffenders(fixtures), <String>[
      'lib/src/docx/f.dart',
      'lib/src/docx/read/h.dart',
    ]);
  });
}
