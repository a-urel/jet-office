// Architecture guard: jet_office holds no tokenizer of number format codes.
//
// A number format code is scanned in exactly one place (decision 0008), the
// parser of jet_core (decision 0012); jet_office only calls its classifier.
// A scanner of its own needs the markers `AM/PM` and `A/P` as literals, so no
// file under lib/ may hold one.
@TestOn('vm')
library;

import 'package:test/test.dart';

import 'support/lib_sources.dart';

/// A string literal `am/pm` or `a/p`, in any case and either quote.
final RegExp _marker = RegExp(
  r"""['"](?:am/pm|a/p)['"]""",
  caseSensitive: false,
);

/// Files allowed to hold the markers: `merge_field.dart` translates Word date
/// pictures into an Excel code and writes the AM/PM marker into that code. It
/// scans no Excel format code, so decisions 0008 and 0012's single scanner
/// stays in jet_core.
const Set<String> _allowed = <String>{'lib/src/docx/template/merge_field.dart'};

List<String> _offenders(Iterable<LibSource> sources) => <String>[
  for (final LibSource source in sources)
    if (!_allowed.contains(source.path) && _marker.hasMatch(source.code))
      source.path,
];

void main() {
  test('no file under lib/ holds the AM/PM markers', () {
    expect(_offenders(libSources()), isEmpty);
  });

  test('the guard flags an AM/PM marker', () {
    const List<LibSource> fixtures = <LibSource>[
      LibSource(
        'lib/src/xlsx/format_kind.dart',
        '''const String _amPm = 'am/pm';''',
      ),
      LibSource(
        'lib/src/xlsx/number_format.dart',
        '''const String _aP = "A/P";''',
      ),
      LibSource('lib/src/xlsx/other.dart', '''if (w == 'AM/PM') {}'''),
      LibSource(
        'lib/src/docx/template/merge_field.dart',
        '''const String _amPm = 'AM/PM';''',
      ),
      LibSource(
        'lib/src/docx/template/values.dart',
        '''const String _amPm = 'AM/PM';''',
      ),
      LibSource(
        'lib/src/xlsx/fine.dart',
        '''// shows AM/PM and A/P\n'''
            '''const String s = 'h:mm AM/PM';\n'''
            '''const String t = 'a/pm';''',
      ),
    ];
    expect(_offenders(fixtures), <String>[
      'lib/src/xlsx/format_kind.dart',
      'lib/src/xlsx/number_format.dart',
      'lib/src/xlsx/other.dart',
      'lib/src/docx/template/values.dart',
    ]);
  });
}
