@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

// Decision 0009: the library keeps no undo stack. ChangeLog keeps ids of
// kept sets, never the sets, so a set the editor drops can be collected.
void main() {
  test('ChangeLog holds no reference to a change set', () {
    final String code = File('lib/src/opc/change_log.dart').readAsStringSync();
    final int start = code.indexOf('final class ChangeLog');
    expect(start, isNot(-1));
    final String body = code.substring(start);
    final Iterable<String> fields = RegExp(
      r'^  (?:final |late )*[\w<>?, ]+ _\w+\s*[;=]',
      multiLine: true,
    ).allMatches(body).map((Match m) => m[0]!);
    expect(fields, isNotEmpty);
    expect(fields.where((String f) => f.contains('ChangeSet')), isEmpty);
    expect(fields.where((String f) => f.contains('Change>')), <String>[
      '  final List<Change> _open =',
    ]);
  });
}
