// Architecture guard: one cell encoder.
//
// A cell value becomes XML in exactly one place, which both the streaming
// writer and the workbook model call (decision 0002). Quds had two encoders
// and each bug lived in both. No file under lib/ but the encoder may write a
// cell element (<c ...>) or a value element (<v>).
@TestOn('vm')
library;

import 'package:test/test.dart';

import 'support/lib_sources.dart';

const String _encoder = 'lib/src/xlsx/cell_encoder.dart';

/// `<c`, `<v` followed by whitespace, `>` or (for `<c`) `/`.
///
/// Neighbouring SpreadsheetML elements such as `<cols>`, `<col>`, `<cfRule>`
/// and `<vertAlign>` do not match.
final RegExp _cellMarkup = RegExp(r'<c[\s>/]|<v[\s>]');

List<String> _offenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (source.path != _encoder && _cellMarkup.hasMatch(source.code))
      source.path,
];

void main() {
  test('only $_encoder writes <c or <v>', () {
    expect(_offenders(libSources()), isEmpty);
  });

  test('the guard flags cell markup outside the encoder', () {
    const List<LibSource> fixtures = <LibSource>[
      LibSource(_encoder, '''const String a = '<c r="A1"><v>1</v></c>';'''),
      LibSource(
        'lib/src/xlsx/xlsx_writer.dart',
        '''sink.write('<c r="\$ref" t="s">');''',
      ),
      LibSource('lib/src/xlsx/workbook.dart', "out.write('<v>\$n</v>');"),
      LibSource('lib/src/xlsx/empty.dart', "out.write('<c/>');"),
      LibSource(
        'lib/src/xlsx/columns.dart',
        '''out.write('<cols><col min="1" max="1"/></cols>');'''
            '''\nout.write('<vertAlign val="superscript"/>');''',
      ),
      LibSource(
        'lib/src/xlsx/doc.dart',
        '/// Rows hold <c r="A1"> elements, written by the encoder.\n'
            'const int x = 0;',
      ),
    ];
    expect(_offenders(fixtures), <String>[
      'lib/src/xlsx/xlsx_writer.dart',
      'lib/src/xlsx/workbook.dart',
      'lib/src/xlsx/empty.dart',
    ]);
  });
}
