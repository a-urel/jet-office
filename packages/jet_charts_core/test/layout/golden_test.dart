// Golden files of the primitives of a fixed gallery of charts
// (test/support/gallery.dart), laid out with the fixed-width measurer and the
// Office theme. A golden changes only when the layout does; review the
// difference, then rewrite the files with
//
//     UPDATE_GOLDENS=1 dart test test/layout/golden_test.dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

import '../support/gallery.dart';

const String _folder = 'test/goldens';

void main() {
  final bool update = Platform.environment['UPDATE_GOLDENS'] == '1';

  group('the primitives of each gallery chart', () {
    for (final (String name, ChartLayout layout) in goldenLayouts()) {
      test(name, () {
        final String actual = primitivesToText(layout.primitives);
        final File file = File('$_folder/$name.txt');
        if (update) {
          file.createSync(recursive: true);
          file.writeAsStringSync(actual);
          return;
        }
        if (!file.existsSync()) {
          fail(
            'No golden for $name. Create it with '
            '`UPDATE_GOLDENS=1 dart test test/layout/golden_test.dart` and '
            'read it before committing.',
          );
        }
        expect(
          actual,
          file.readAsStringSync(),
          reason:
              'The layout of $name changed. If that is intended, rewrite the '
              'goldens with UPDATE_GOLDENS=1 and review the difference.',
        );
      });
    }
  });

  test('every gallery chart lays out without an overlap', () {
    for (final (String name, ChartLayout layout) in goldenLayouts()) {
      expect(
        findOverlaps(layout.primitives, layout.size),
        isEmpty,
        reason: name,
      );
    }
  });

  test('there is a golden for each gallery chart and none without one', () {
    if (update) return;
    final Set<String> expected = <String>{
      for (final (String name, ChartLayout _) in goldenLayouts()) '$name.txt',
    };
    final Set<String> found = <String>{
      for (final FileSystemEntity e in Directory(_folder).listSync())
        e.uri.pathSegments.last,
    };
    expect(found, expected);
  });
}
