// Tests that tool/gate.sh runs exactly the commands of AGENTS.md's quality
// gate, in the same order, so the two cannot drift apart.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// The commands of the fenced block under "## The quality gate".
List<String> _agentsGate() {
  final List<String> lines = File('AGENTS.md').readAsLinesSync();
  final int heading = lines.indexOf('## The quality gate');
  final int open = lines.indexOf('```bash', heading);
  final int close = lines.indexOf('```', open + 1);
  return lines.sublist(open + 1, close);
}

/// The commands of `leg '<command>'` lines in tool/gate.sh.
List<String> _scriptLegs() {
  final RegExp leg = RegExp(r"^leg '(.*)'$");
  return <String>[
    for (final String line in File('tool/gate.sh').readAsLinesSync())
      if (leg.firstMatch(line) case final RegExpMatch m) m[1]!,
  ];
}

void main() {
  test('tool/gate.sh runs the commands of the AGENTS.md gate in order', () {
    final List<String> gate = _agentsGate();
    expect(gate, hasLength(8));
    expect(_scriptLegs(), gate);
  });

  test('tool/gate.sh writes Flutter\'s version file back before each dart '
      'command, the second of a leg too', () {
    final String script = File('tool/gate.sh').readAsStringSync();
    // A shell function shadows `dart` in every leg, so each `dart` of a
    // leg such as `(cd packages/jet_core && dart test && dart test -p
    // chrome)` runs after `flutter --version`.
    expect(
      script,
      contains(
        'dart() { flutter --version >/dev/null 2>&1; command dart "\$@"; }',
      ),
    );
  });
}
