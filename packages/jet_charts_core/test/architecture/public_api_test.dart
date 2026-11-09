// Architecture guard: the public API is what lib/jet_charts_core.dart exports.
//
// The barrel holds a library doc comment and `export` lines only; each names a
// file under `src/` and lists what it shows (AGENTS.md, "Hard rules").
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// What is wrong with the barrel [source], one line each; empty when it is as
/// the rule demands.
List<String> _problems(String source) {
  final List<String> problems = <String>[];
  final List<String> lines = source.split('\n');
  if (!lines.any((String l) => l.startsWith('///') && l.trim().length > 3)) {
    problems.add('no library doc comment');
  }
  // Join each statement (an export may span lines) up to its `;`.
  final String code = lines
      .where((String l) => !l.trimLeft().startsWith('//'))
      .join('\n');
  for (final String raw in code.split(';')) {
    final String statement = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (statement.isEmpty || statement == 'library') {
      continue;
    }
    if (!RegExp(r'''^export '[^']+' show \w+(, \w+)*$''').hasMatch(statement)) {
      problems.add('not an export with a show list: $statement');
    } else if (!statement.contains("'src/")) {
      problems.add('does not export a src/ file: $statement');
    }
  }
  return problems;
}

void main() {
  test('the public API is what the library exports', () {
    final File barrel = File('lib/jet_charts_core.dart');
    expect(barrel.existsSync(), isTrue);
    expect(_problems(barrel.readAsStringSync()), isEmpty);
  });

  test('the ids API and hit testing are public', () {
    final String source = File('lib/jet_charts_core.dart').readAsStringSync();
    expect(
      source,
      contains(
        "export 'src/interaction/element_id.dart'\n"
        '    show ChartAxisRole, ChartElementId, ChartElementKind;',
      ),
    );
    expect(
      source,
      contains("export 'src/interaction/hit_test.dart' show hitTestLayout;"),
    );
    // The writing side of the scheme stays private.
    expect(source, isNot(contains('chart_ids.dart')));
  });

  test('the interval rule is not public', () {
    // excelMaxIntervals is the layout's own; only the package's code and
    // tests use it, through src/. The provisional rule it replaced is gone.
    final String source = File('lib/jet_charts_core.dart').readAsStringSync();
    expect(source, isNot(contains('excelMaxIntervals')));
    expect(source, isNot(contains('provisionalMaxIntervals')));
  });

  test('the check flags a missing doc comment, show list or src/ path', () {
    const String good = '''
/// Doc.
library;

export 'src/a.dart' show A, B;
export 'src/b.dart'
    show C;
''';
    expect(_problems(good), isEmpty);
    expect(_problems(good.replaceFirst('/// Doc.\n', '')), <String>[
      'no library doc comment',
    ]);
    expect(_problems("/// Doc.\nlibrary;\nexport 'src/a.dart';"), <String>[
      "not an export with a show list: export 'src/a.dart'",
    ]);
    expect(
      _problems("/// Doc.\nlibrary;\nexport 'src/a.dart' hide A;"),
      hasLength(1),
    );
    expect(
      _problems("/// Doc.\nlibrary;\nimport 'src/a.dart' show A;"),
      hasLength(1),
    );
    expect(
      _problems("/// Doc.\nlibrary;\nexport 'other.dart' show A;"),
      <String>["does not export a src/ file: export 'other.dart' show A"],
    );
  });
}
