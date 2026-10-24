// Architecture guard: package:archive stays behind one adapter.
//
// ZIP comes from package:archive, and only the adapter may import it
// (AGENTS.md; decision 0001). Swapping or patching the ZIP layer then touches
// one file, and whether entries stream or buffer stays the adapter's business
// (decision 0002).
@TestOn('vm')
library;

import 'package:test/test.dart';

import 'support/lib_sources.dart';

const String _adapter = 'lib/src/zip/archive_adapter.dart';

final RegExp _archive = RegExp(r'''['"]package:archive/''');

List<String> _offenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (source.path != _adapter && _archive.hasMatch(source.code)) source.path,
];

void main() {
  test('only $_adapter imports package:archive', () {
    expect(_offenders(libSources()), isEmpty);
  });

  test('the guard flags archive imports outside the adapter', () {
    const List<LibSource> fixtures = <LibSource>[
      LibSource(_adapter, "import 'package:archive/archive.dart';"),
      LibSource(
        'lib/src/xlsx/xlsx_writer.dart',
        "import 'package:archive/archive.dart';",
      ),
      LibSource(
        'lib/jet_office.dart',
        'export "package:archive/archive.dart";',
      ),
      LibSource(
        'lib/src/opc/package.dart',
        "/// Zipped by 'package:archive/' through the adapter.\n"
            "import '../zip/archive_adapter.dart';",
      ),
    ];
    expect(_offenders(fixtures), <String>[
      'lib/src/xlsx/xlsx_writer.dart',
      'lib/jet_office.dart',
    ]);
  });
}
