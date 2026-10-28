// Architecture guard: one cell decoder.
//
// A cell's XML becomes a value in exactly one place (decision 0007), the
// mirror of the one cell encoder of decision 0002. No file under lib/ but
// the decoder may read a cell's `t` attribute.
@TestOn('vm')
library;

import 'package:test/test.dart';

import 'support/lib_sources.dart';

const String _decoder = 'lib/src/xlsx/read/cell_decoder.dart';

/// A `t` attribute read: `getAttribute('t'`, `Attribute("t"` and the like.
final RegExp _typeRead = RegExp(r"""Attribute\(\s*['"]t['"]""");

List<String> _offenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (source.path != _decoder && _typeRead.hasMatch(source.code)) source.path,
];

void main() {
  test('only $_decoder reads a t attribute', () {
    expect(_offenders(libSources()), isEmpty);
  });

  test('the guard flags a t attribute read outside the decoder', () {
    const List<LibSource> fixtures = <LibSource>[
      LibSource(_decoder, '''final t = r.getAttribute('t');'''),
      LibSource(
        'lib/src/xlsx/read/row_walker.dart',
        '''final t = r.getAttribute('t');''',
      ),
      LibSource(
        'lib/src/xlsx/read/other.dart',
        '''final t = r.getAttribute( "t", namespaceUri: '');''',
      ),
      LibSource(
        'lib/src/xlsx/read/fine.dart',
        '''final s = r.getAttribute('s');\n'''
            '''final r2 = r.getAttribute('r');\n'''
            '''final tt = r.getAttribute('tt');\n'''
            '''// reads r.getAttribute('t') through decodeCellType''',
      ),
    ];
    expect(_offenders(fixtures), <String>[
      'lib/src/xlsx/read/row_walker.dart',
      'lib/src/xlsx/read/other.dart',
    ]);
  });
}
