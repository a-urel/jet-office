// Architecture guard: one tokenizer of number format codes.
//
// A number format code is scanned in exactly one place (decision 0008),
// `parseFormatCode`; the classifier and the renderers read its tokens. A
// scanner of its own needs the markers `AM/PM` and `A/P` as literals, so no
// file under lib/ but the parser may hold one.
@TestOn('vm')
library;

import 'package:test/test.dart';

import 'support/lib_sources.dart';

const String _parser = 'lib/src/xlsx/format/format_code.dart';

/// A string literal `am/pm` or `a/p`, in any case and either quote.
final RegExp _marker = RegExp(
  r"""['"](?:am/pm|a/p)['"]""",
  caseSensitive: false,
);

List<String> _offenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (source.path != _parser && _marker.hasMatch(source.code)) source.path,
];

void main() {
  test('only $_parser holds the AM/PM markers', () {
    expect(_offenders(libSources()), isEmpty);
  });

  test('the guard flags an AM/PM marker outside the parser', () {
    const List<LibSource> fixtures = <LibSource>[
      LibSource(_parser, '''const String _amPm = 'am/pm';'''),
      LibSource(
        'lib/src/xlsx/format/format_kind.dart',
        '''const String _amPm = 'am/pm';''',
      ),
      LibSource(
        'lib/src/xlsx/number_format.dart',
        '''const String _aP = "A/P";''',
      ),
      LibSource('lib/src/xlsx/other.dart', '''if (w == 'AM/PM') {}'''),
      LibSource(
        'lib/src/xlsx/fine.dart',
        '''// shows AM/PM and A/P\n'''
            '''const String s = 'h:mm AM/PM';\n'''
            '''const String t = 'a/pm';''',
      ),
    ];
    expect(_offenders(fixtures), <String>[
      'lib/src/xlsx/format/format_kind.dart',
      'lib/src/xlsx/number_format.dart',
      'lib/src/xlsx/other.dart',
    ]);
  });
}
