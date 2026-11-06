// Architecture guard: the format layers depend on each other one way only.
//
// lib/src/common holds what XLSX and DOCX share: the warning aggregator, the
// read guard, the ZIP limits and the message locale. It must import neither
// lib/src/xlsx nor lib/src/docx. lib/src/docx may import nothing of
// lib/src/xlsx: the number formatter is in jet_core (decision 0012). Neither
// layer may import the public barrel, lib/jet_office.dart, which exports
// xlsx. No file under lib/ may reach into jet_core's `src/`: its public
// barrel, `package:jet_core/jet_core.dart`, is the only way in.
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

/// Whether [uri] names the public barrel, `lib/jet_office.dart`, which
/// exports the xlsx layer.
bool _namesBarrel(String uri) =>
    uri == 'package:jet_office/jet_office.dart' ||
    (!uri.startsWith('package:') && uri.endsWith('jet_office.dart'));

/// Whether [uri] reaches into jet_core's private `src/`.
bool _namesCoreSource(String uri) => uri.startsWith('package:jet_core/src/');

Iterable<String> _uris(LibSource source) =>
    _directive.allMatches(source.code).map((RegExpMatch m) => m.group(1)!);

List<String> _commonOffenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (source.path.startsWith(_common) &&
        _uris(source).any(
          (String uri) =>
              _names(uri, 'xlsx') || _names(uri, 'docx') || _namesBarrel(uri),
        ))
      source.path,
];

List<String> _docxOffenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (source.path.startsWith(_docx) &&
        _uris(
          source,
        ).any((String uri) => _names(uri, 'xlsx') || _namesBarrel(uri)))
      source.path,
];

List<String> _coreSourceOffenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (_uris(source).any(_namesCoreSource)) source.path,
];

void main() {
  test('lib/src/docx does not import lib/src/xlsx', () {
    expect(_docxOffenders(libSources()), isEmpty);
  });

  test('no file under lib/ imports package:jet_core/src/', () {
    expect(_coreSourceOffenders(libSources()), isEmpty);
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
      LibSource('lib/src/docx/g.dart', "import '../xlsx/color.dart';"),
      LibSource(
        'lib/src/docx/m.dart',
        "import 'package:jet_core/jet_core.dart' show NumberFormatter;",
      ),
      LibSource(
        'lib/src/xlsx/n.dart',
        "import 'package:jet_core/src/format/formatter.dart';",
      ),
      LibSource(
        'lib/src/xlsx/o.dart',
        "// import 'package:jet_core/src/format/formatter.dart';\n"
            "export 'package:jet_core/jet_core.dart';",
      ),
      LibSource(
        'lib/src/docx/read/h.dart',
        "import '../../xlsx/read/read_limits.dart';",
      ),
      LibSource('lib/src/docx/i.dart', "import '../common/locale.dart';"),
      LibSource(
        'lib/src/common/j.dart',
        "import 'package:jet_office/jet_office.dart';",
      ),
      LibSource('lib/src/docx/k.dart', "import '../../jet_office.dart';"),
      LibSource(
        'lib/src/docx/l.dart',
        "import 'package:jet_office/jet_office.dart' show OfficeLocale;",
      ),
    ];
    expect(_commonOffenders(fixtures), <String>[
      'lib/src/common/a.dart',
      'lib/src/common/b.dart',
      'lib/src/common/c.dart',
      'lib/src/common/j.dart',
    ]);
    expect(_coreSourceOffenders(fixtures), <String>['lib/src/xlsx/n.dart']);
    expect(_docxOffenders(fixtures), <String>[
      'lib/src/docx/f.dart',
      'lib/src/docx/g.dart',
      'lib/src/docx/read/h.dart',
      'lib/src/docx/k.dart',
      'lib/src/docx/l.dart',
    ]);
  });
}
