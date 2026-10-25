// The checker's header lists every rule it reports.
//
// Each violation starts with `rule N:`, N being the rule's number in the
// numbered list of the header doc of `test/support/xlsx_checker.dart`. A
// rule added without its list entry leaves a reader of a violation with
// nothing to look up.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

const String _checker = 'test/support/xlsx_checker.dart';

void main() {
  test('every rule the checker reports is in its header list, in order', () {
    final String source = File(_checker).readAsStringSync();
    final Set<int> reported = <int>{
      for (final RegExpMatch m in RegExp(r"'rule (\d+):").allMatches(source))
        int.parse(m.group(1)!),
    };
    final List<int> listed = <int>[
      for (final RegExpMatch m in RegExp(
        r'^/// (\d+)\. ',
        multiLine: true,
      ).allMatches(source))
        int.parse(m.group(1)!),
    ];
    expect(reported, isNotEmpty);
    expect(listed, <int>[for (int n = 1; n <= listed.length; n++) n]);
    expect(
      listed.toSet().containsAll(reported),
      isTrue,
      reason: 'reported ${reported.toList()..sort()}, listed $listed',
    );
  });
}
