// Architecture guard: the package layer knows nothing of spreadsheets.
//
// lib/src/opc holds the Open Packaging Conventions code (parts, content types,
// relationships, opaque XML) that a later DOCX model shares. It must not
// import anything under lib/src/xlsx, or the layering runs backwards.
@TestOn('vm')
library;

import 'package:test/test.dart';

import 'support/lib_sources.dart';

const String _opc = 'lib/src/opc/';

/// An `import` or `export` directive whose URI names the xlsx layer, by a
/// relative path (`../xlsx/...`) or a package URI.
final RegExp _xlsxImport = RegExp(
  r'''^\s*(?:import|export)\s+['"][^'"]*(?:\.\./xlsx/|src/xlsx/)''',
  multiLine: true,
);

List<String> _offenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (source.path.startsWith(_opc) && _xlsxImport.hasMatch(source.code))
      source.path,
];

void main() {
  test('nothing under lib/src/opc imports lib/src/xlsx', () {
    expect(_offenders(libSources()), isEmpty);
  });

  test('the guard flags an import', () {
    const List<LibSource> fixtures = <LibSource>[
      LibSource('lib/src/opc/a.dart', "import '../xlsx/workbook.dart';"),
      LibSource(
        'lib/src/opc/b.dart',
        "import 'package:jet_office/src/xlsx/cell_encoder.dart';",
      ),
      LibSource('lib/src/opc/c.dart', "export '../xlsx/read/reader.dart';"),
      LibSource('lib/src/opc/d.dart', "import '../xml/xml_writer.dart';"),
      LibSource(
        'lib/src/opc/e.dart',
        "// import '../xlsx/workbook.dart';\nconst int x = 0;",
      ),
      LibSource('lib/src/xlsx/f.dart', "import '../xlsx/workbook.dart';"),
    ];
    expect(_offenders(fixtures), <String>[
      'lib/src/opc/a.dart',
      'lib/src/opc/b.dart',
      'lib/src/opc/c.dart',
    ]);
  });
}
