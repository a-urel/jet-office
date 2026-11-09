// Architecture guard: the format layers depend on each other one way only.
//
// lib/src/common holds what XLSX and DOCX share: the warning aggregator, the
// read guard, the ZIP limits and the message locale. It must import neither
// lib/src/xlsx nor lib/src/docx. lib/src/docx may import nothing of
// lib/src/xlsx: the number formatter is in jet_core (decision 0012). Neither
// layer may import the public barrel, lib/jet_office.dart, which exports
// xlsx. lib/src/drawingml holds what XLSX and DOCX share of DrawingML. It
// imports only an allow-list (decision 0015): dart: libraries, its own files,
// ../opc/, ../xml/, ../common/ and the barrels of jet_charts_core and
// jet_core; so it imports neither format layer. No file under lib/ may reach
// into jet_core's `src/` or jet_charts_core's `src/`: their public barrels
// (`package:jet_core/jet_core.dart`,
// `package:jet_charts_core/jet_charts_core.dart`) are the only way in.
@TestOn('vm')
library;

import 'package:test/test.dart';

import 'support/lib_sources.dart';

const String _common = 'lib/src/common/';
const String _docx = 'lib/src/docx/';
const String _drawingml = 'lib/src/drawingml/';

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

/// Whether [uri] reaches into the private `src/` of jet_core or
/// jet_charts_core.
bool _namesCoreSource(String uri) =>
    uri.startsWith('package:jet_core/src/') ||
    uri.startsWith('package:jet_charts_core/src/');

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

/// Whether [uri] is one the drawingml layer may import (decision 0015): a
/// `dart:` library, a relative path that stays in `drawingml/` or names
/// `../opc/`, `../xml/` or `../common/`, or exactly the two package barrels.
bool _drawingmlAllows(String uri) {
  if (uri.startsWith('dart:')) return true;
  if (uri == 'package:jet_charts_core/jet_charts_core.dart' ||
      uri == 'package:jet_core/jet_core.dart') {
    return true;
  }
  if (uri.contains(':')) return false;
  // Resolve against a file directly in lib/src/drawingml/.
  final String path = Uri.parse('lib/src/drawingml/x.dart').resolve(uri).path;
  return path.startsWith(_drawingml) ||
      path.startsWith('lib/src/opc/') ||
      path.startsWith('lib/src/xml/') ||
      path.startsWith(_common);
}

List<String> _drawingmlOffenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (source.path.startsWith(_drawingml) &&
        !_uris(source).every(_drawingmlAllows))
      source.path,
];

List<String> _coreSourceOffenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (_uris(source).any(_namesCoreSource)) source.path,
];

/// The files under `lib/src/docx/` that the barrel, `lib/jet_office.dart`,
/// exports, as paths relative to the package root.
Set<String> _barrelDocxFiles(Iterable<LibSource> sources) {
  final LibSource barrel = sources.firstWhere(
    (LibSource s) => s.path == 'lib/jet_office.dart',
  );
  return <String>{
    for (final String uri in _uris(barrel))
      if (uri.startsWith('src/docx/')) 'lib/$uri',
  };
}

/// The files under `lib/src/docx/` that [source] imports, as paths relative
/// to the package root, or a path under `lib/src/` for any other relative
/// import. Package imports are not resolved.
Iterable<String> _relativeImports(LibSource source) => <String>[
  for (final String uri in _uris(source))
    if (!uri.startsWith('package:') && !uri.startsWith('dart:'))
      Uri.parse(source.path).resolve(uri).path,
];

/// The imports of [source] that break the list export's rule: a file under
/// `lib/src/docx/` the barrel does not export, or a relative import outside
/// `lib/src/docx/` and `lib/src/common/`, or a package other than
/// `package:jet_core/jet_core.dart` and the Dart SDK.
List<String> _listExportOffenders(LibSource source, Set<String> exported) =>
    <String>[
      for (final String uri in _uris(source))
        if (uri.startsWith('package:')
            ? uri != 'package:jet_core/jet_core.dart'
            : !uri.startsWith('dart:') &&
                  !_allowedRelative(
                    Uri.parse(source.path).resolve(uri).path,
                    exported,
                  ))
          uri,
    ];

bool _allowedRelative(String path, Set<String> exported) =>
    path.startsWith(_common) ||
    (path.startsWith(_docx) && exported.contains(path));

void main() {
  test('lib/src/docx/list_export.dart imports only exported docx files', () {
    final List<LibSource> sources = libSources();
    final LibSource export = sources.firstWhere(
      (LibSource s) => s.path == '${_docx}list_export.dart',
    );
    final Set<String> exported = _barrelDocxFiles(sources);
    expect(
      exported,
      contains('${_docx}docx_document.dart'),
      reason: 'the barrel must export docx files, or the guard allows none.',
    );
    expect(_relativeImports(export), isNotEmpty);
    expect(_listExportOffenders(export, exported), isEmpty);
  });

  test('the list export guard flags an import', () {
    const Set<String> exported = <String>{'lib/src/docx/docx_document.dart'};
    List<String> offenders(String code) => _listExportOffenders(
      LibSource('lib/src/docx/list_export.dart', code),
      exported,
    );
    expect(
      offenders(
        "import 'docx_document.dart';\n"
        "import '../common/image.dart';\n"
        "import 'dart:typed_data';\n"
        "import 'package:jet_core/jet_core.dart';",
      ),
      isEmpty,
    );
    expect(
      offenders(
        "import 'save_plan.dart';\n"
        "import 'model/edit_sink.dart';\n"
        "import '../xml/xml_number.dart';\n"
        "import '../xlsx/range.dart';\n"
        "import 'package:archive/archive.dart';\n"
        "import 'package:jet_core/src/format/formatter.dart';",
      ),
      <String>[
        'save_plan.dart',
        'model/edit_sink.dart',
        '../xml/xml_number.dart',
        '../xlsx/range.dart',
        'package:archive/archive.dart',
        'package:jet_core/src/format/formatter.dart',
      ],
    );
    expect(offenders("// import 'save_plan.dart';\nconst int x = 0;"), isEmpty);
  });

  test('lib/src/docx does not import lib/src/xlsx', () {
    expect(_docxOffenders(libSources()), isEmpty);
  });

  test('drawingml imports only what decision 0015 allows', () {
    final List<LibSource> sources = libSources();
    expect(
      sources.map((LibSource s) => s.path),
      contains('${_drawingml}picture.dart'),
      reason: 'lib/src/drawingml must exist, or the guard scans nothing.',
    );
    expect(_drawingmlOffenders(sources), isEmpty);
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
      LibSource('lib/src/drawingml/p.dart', "import '../xlsx/range.dart';"),
      LibSource('lib/src/drawingml/q.dart', "export '../docx/x.dart';"),
      LibSource(
        'lib/src/drawingml/r.dart',
        "import 'package:jet_office/jet_office.dart';",
      ),
      LibSource('lib/src/drawingml/s.dart', "import '../opc/package.dart';"),
      LibSource(
        'lib/src/drawingml/t.dart',
        "import 'package:jet_charts_core/src/a.dart';",
      ),
      LibSource(
        'lib/src/drawingml/u.dart',
        "import 'package:archive/archive.dart';",
      ),
      LibSource(
        'lib/src/drawingml/v.dart',
        "import 'dart:typed_data';\n"
            "import 'package:jet_charts_core/jet_charts_core.dart';\n"
            "import 'package:jet_core/jet_core.dart';\n"
            "import 'chart/x.dart';\n"
            "import '../xml/xml_writer.dart';\n"
            "import '../common/image.dart';",
      ),
      LibSource(
        'lib/src/drawingml/w.dart',
        "import '../zip/archive_adapter.dart';",
      ),
      LibSource(
        'lib/src/drawingml/y.dart',
        "// import '../xlsx/x.dart';\nconst int x = 0;",
      ),
    ];
    expect(_drawingmlOffenders(fixtures), <String>[
      'lib/src/drawingml/p.dart',
      'lib/src/drawingml/q.dart',
      'lib/src/drawingml/r.dart',
      'lib/src/drawingml/t.dart',
      'lib/src/drawingml/u.dart',
      'lib/src/drawingml/w.dart',
    ]);
    expect(_commonOffenders(fixtures), <String>[
      'lib/src/common/a.dart',
      'lib/src/common/b.dart',
      'lib/src/common/c.dart',
      'lib/src/common/j.dart',
    ]);
    expect(_coreSourceOffenders(fixtures), <String>[
      'lib/src/xlsx/n.dart',
      'lib/src/drawingml/t.dart',
    ]);
    expect(_docxOffenders(fixtures), <String>[
      'lib/src/docx/f.dart',
      'lib/src/docx/g.dart',
      'lib/src/docx/read/h.dart',
      'lib/src/docx/k.dart',
      'lib/src/docx/l.dart',
    ]);
  });
}
