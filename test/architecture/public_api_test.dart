// Architecture guard: what W5 (structural editing) makes public is exactly
// the plan's list, and the formula machinery behind it stays private.
@TestOn('vm')
library;

import 'package:test/test.dart';

import 'support/lib_sources.dart';

/// The public names W5 adds beside the members of `XlsxSheet` and
/// `XlsxWorkbook`.
const Set<String> _w5Names = <String>{
  'XlsxChange',
  'XlsxChangeKind',
  'XlsxChangeSet',
  'XlsxFormulaToken',
  'XlsxFormulaTokenKind',
  'lexFormula',
};

/// The names a barrel `export ... show` directive lists, by exported path.
Map<String, Set<String>> _exports(String barrel) => <String, Set<String>>{
  for (final RegExpMatch m in RegExp(
    r'''export\s+'([^']*)'\s+show\s+([^;]*);''',
  ).allMatches(barrel))
    m.group(1)!: <String>{
      for (final String n in m.group(2)!.split(','))
        if (n.trim().isNotEmpty) n.trim(),
    },
};

void main() {
  final List<LibSource> sources = libSources();
  final String barrel = sources
      .firstWhere((LibSource s) => s.path == 'lib/jet_office.dart')
      .code;
  final Map<String, Set<String>> exports = _exports(barrel);

  test('the barrel exports the W5 types and function, and only them from '
      'the formula and change set files', () {
    final Set<String> fromW5Files = <String>{
      for (final MapEntry<String, Set<String>> e in exports.entries)
        if (e.key.startsWith('src/xlsx/formula/') ||
            e.key == 'src/xlsx/model/change_set.dart')
          ...e.value,
    };
    expect(fromW5Files, _w5Names);
  });

  test('no other name of the formula, reference or change files is public', () {
    final Set<String> exported = <String>{
      for (final Set<String> names in exports.values) ...names,
    };
    final RegExp declaration = RegExp(
      r'^(?:abstract |final |sealed |base |interface |mixin )*'
      r'(?:class|enum|typedef|extension type|mixin)\s+([A-Za-z]\w*)',
      multiLine: true,
    );
    int seen = 0;
    for (final LibSource s in sources) {
      final bool internal =
          s.path.startsWith('lib/src/xlsx/formula/') ||
          s.path == 'lib/src/xlsx/model/reference_holders.dart' ||
          s.path == 'lib/src/xlsx/model/change_set.dart';
      if (!internal) continue;
      for (final RegExpMatch m in declaration.allMatches(s.code)) {
        final String name = m.group(1)!;
        if (name.startsWith('_') || _w5Names.contains(name)) continue;
        seen++;
        expect(exported, isNot(contains(name)), reason: '$name in ${s.path}');
      }
    }
    expect(seen, greaterThan(5), reason: 'the scan found the internals');
    // The functions of the formula layer.
    for (final String name in <String>[
      'rewriteFormula',
      'rewriteSqref',
      'ReferenceShift',
      'ReferenceRegistry',
      'referenceRegistryOf',
    ]) {
      expect(exported, isNot(contains(name)), reason: name);
    }
  });

  test('every export of the barrel has a show list', () {
    final int directives = RegExp(
      r'^export\s',
      multiLine: true,
    ).allMatches(barrel).length;
    expect(directives, greaterThan(0));
    expect(
      exports.length,
      directives,
      reason: 'an export without show would make a whole file public',
    );
  });

  test('the barrel exports no part of the change log', () {
    expect(barrel, isNot(contains('opc/change_log.dart')));
  });
}
