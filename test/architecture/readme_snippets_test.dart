@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Keeps README.md and test/readme_test.dart in step: every line of every
/// fenced `dart` block of the README, trimmed, must occur as one contiguous
/// run in the test file's lines, trimmed.
void main() {
  test('every README Dart block appears verbatim in test/readme_test.dart', () {
    final List<String> testLines = _trimmed(
      File('test/readme_test.dart').readAsLinesSync(),
    );
    final List<List<String>> blocks = readmeDartBlocks(
      File('README.md').readAsLinesSync(),
    );
    expect(blocks, isNotEmpty);
    for (final List<String> block in blocks) {
      expect(
        containsRun(testLines, block),
        isTrue,
        reason:
            'README block not found in test/readme_test.dart:\n'
            '${block.join('\n')}',
      );
    }
  });

  test('a changed README line is detected', () {
    final List<String> testLines = _trimmed(
      File('test/readme_test.dart').readAsLinesSync(),
    );
    final List<List<String>> blocks = readmeDartBlocks(
      File('README.md').readAsLinesSync(),
    );
    final List<String> broken = <String>[...blocks.first]..[1] = 'broken();';
    expect(containsRun(testLines, broken), isFalse);
  });
}

List<String> _trimmed(List<String> lines) => <String>[
  for (final String l in lines) l.trim(),
];

/// The trimmed lines of each fenced dart block in [readme].
List<List<String>> readmeDartBlocks(List<String> readme) {
  final List<List<String>> blocks = <List<String>>[];
  List<String>? open;
  for (final String line in readme) {
    if (open == null) {
      if (line.trim() == '```dart') open = <String>[];
    } else if (line.trim() == '```') {
      blocks.add(open);
      open = null;
    } else {
      open.add(line.trim());
    }
  }
  return blocks;
}

/// Whether [run] occurs as consecutive elements of [lines].
bool containsRun(List<String> lines, List<String> run) {
  for (int i = 0; i + run.length <= lines.length; i++) {
    int k = 0;
    while (k < run.length && lines[i + k] == run[k]) {
      k++;
    }
    if (k == run.length) return true;
  }
  return false;
}
