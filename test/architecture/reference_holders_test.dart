// Architecture guard: every model file that stores a reference, a `sqref` or
// a formula is covered by a reference holder, so a structural edit (W5)
// cannot leave one pointing at the wrong cells.
//
// A file under lib/src/xlsx/model/ with a field typed `XlsxRange`, a
// `String sqref` field or a field named `formula...` must be listed in
// `referenceHolderSources` (lib/src/xlsx/model/reference_holders.dart) or in
// `_allowed` below, with the reason it needs no holder.
@TestOn('vm')
library;

import 'package:jet_office/src/xlsx/model/reference_holders.dart';
import 'package:test/test.dart';

import 'support/lib_sources.dart';

const String _model = 'lib/src/xlsx/model/';

/// Model files that match the scan but need no holder, each with a reason.
const Map<String, String> _allowed = <String, String>{};

/// A class field (two-space indent) that stores a reference or a formula.
final List<RegExp> _fields = <RegExp>[
  RegExp(
    r'^  (?:final |late )*(?:XlsxRange|List<XlsxRange>)\?? _?\w+\s*[;=]',
    multiLine: true,
  ),
  RegExp(r'^  (?:final |late )*String\?? _?sqref\s*[;=]', multiLine: true),
  RegExp(
    r'^  (?:final |late )*\w[\w<>?, ]* _?formula\w*\s*[;=]',
    multiLine: true,
  ),
];

bool _storesReference(String code) =>
    _fields.any((RegExp r) => r.hasMatch(code));

List<String> _unregistered(Iterable<LibSource> sources) => <String>[
  for (final LibSource s in sources)
    if (s.path.startsWith(_model) && _storesReference(s.code))
      if (!referenceHolderSources.containsKey(s.path.substring(_model.length)))
        if (!_allowed.containsKey(s.path.substring(_model.length))) s.path,
];

void main() {
  test(
    'every model file that stores a ref, sqref or formula is registered',
    () {
      expect(_unregistered(libSources()), isEmpty);
    },
  );

  test('every registered file exists and names a holder', () {
    final Set<String> files = <String>{
      for (final LibSource s in libSources())
        if (s.path.startsWith(_model)) s.path.substring(_model.length),
    };
    final Set<String> names = <String>{
      ...sheetHolderNames,
      ...workbookHolderNames,
    };
    referenceHolderSources.forEach((String file, String holder) {
      expect(files, contains(file));
      expect(names, contains(holder), reason: file);
    });
  });

  test('the guard flags each kind of field and ignores locals', () {
    const List<LibSource> fixtures = <LibSource>[
      LibSource('lib/src/xlsx/model/a.dart', '  final XlsxRange range;'),
      LibSource('lib/src/xlsx/model/b.dart', '  String? sqref;'),
      LibSource('lib/src/xlsx/model/c.dart', '  final String formula;'),
      LibSource('lib/src/xlsx/model/d.dart', '    final String formula = x;'),
      LibSource('lib/src/xlsx/model/cell_store.dart', '  String formula;'),
    ];
    expect(_unregistered(fixtures), <String>[
      'lib/src/xlsx/model/a.dart',
      'lib/src/xlsx/model/b.dart',
      'lib/src/xlsx/model/c.dart',
    ]);
  });
}
