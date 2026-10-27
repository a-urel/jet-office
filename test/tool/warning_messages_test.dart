// Tests that docs/warning-messages.md is what tool/warning_messages.dart
// prints, so the sheet for the native-speaker check cannot drift.
@TestOn('vm')
library;

import 'dart:io';

import 'package:jet_office/jet_office.dart';
import 'package:test/test.dart';

import '../../tool/warning_messages.dart';

void main() {
  final String markdown = warningMessagesMarkdown();

  test('the committed docs/warning-messages.md equals the tool output', () {
    expect(
      File('docs/warning-messages.md').readAsStringSync(),
      markdown,
      reason:
          'regenerate: dart run tool/warning_messages.dart '
          '> docs/warning-messages.md',
    );
  });

  test('has a row for every warning code with three messages', () {
    for (final XlsxWarningCode code in XlsxWarningCode.values) {
      final List<String> rows = markdown
          .split('\n')
          .where((String l) => l.startsWith('| `${code.name}` |'))
          .toList();
      expect(rows, hasLength(1), reason: code.name);
      // code, en, de, tr between four pipes plus the outer ones.
      expect(rows.single.split(' | '), hasLength(4), reason: code.name);
    }
  });

  test('names the sample warning and the native-speaker check', () {
    expect(markdown, contains('Daten'));
    expect(markdown, contains('A1, B2'));
    expect(markdown, contains('native-speaker'));
    expect(markdown, contains('dart run tool/warning_messages.dart'));
  });
}
