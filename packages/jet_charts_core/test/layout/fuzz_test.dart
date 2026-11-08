import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

import 'support/chart_fuzz.dart';

/// The seeds the quality gate fuzzes, each with [_cases] cases.
const List<int> _seeds = <int>[1, 2, 3, 4];

/// The cases per seed in the quality gate.
const int _cases = 100;

/// The fingerprint of the gate's cases, computed once on the VM. The Chrome
/// leg compares it, which proves a browser draws the same cases.
const int _fingerprint = 884670020;

const ChartSize _size = ChartSize(100, 50);
final ChartTextStyle _style = ChartTheme.office.axisLabels;

List<String> _problems(List<ChartPrimitive> primitives) =>
    layoutProblems(ChartLayout(size: _size, primitives: primitives));

void main() {
  group('the check', () {
    test('passes a picture inside the size', () {
      expect(
        _problems(<ChartPrimitive>[
          const RectPrimitive('background', ChartRect(0, 0, 100, 50)),
          TextPrimitive('a', 'a', const ChartRect(1, 1, 10, 10), _style),
          TextPrimitive('b', 'b', const ChartRect(11, 1, 10, 10), _style),
        ]),
        isEmpty,
      );
    });

    test('finds a rectangle or path outside the size', () {
      expect(
        _problems(<ChartPrimitive>[
          const RectPrimitive('r', ChartRect(0, 0, 100.1, 50)),
          PathPrimitive('p', const <ChartPoint>[
            ChartPoint(0, 0),
            ChartPoint(10, -1),
          ]),
        ]),
        hasLength(2),
      );
    });

    test('allows 1e-6 past the edge', () {
      expect(
        _problems(<ChartPrimitive>[
          const RectPrimitive('r', ChartRect(-1e-7, 0, 100, 50 + 1e-7)),
        ]),
        isEmpty,
      );
    });

    test('finds a number that is not finite', () {
      expect(
        _problems(<ChartPrimitive>[
          ClipPrimitive('clip', const ChartRect(0, 0, 10, 10), <ChartPrimitive>[
            PathPrimitive('p', const <ChartPoint>[
              ChartPoint(0, 0),
              ChartPoint(double.nan, 1),
            ]),
          ]),
        ]),
        <String>['p: path is not finite (NaN)'],
      );
    });

    test('lets a clipped mark pass the size, but not a clipped text', () {
      final List<String> problems = _problems(<ChartPrimitive>[
        ClipPrimitive('clip', const ChartRect(0, 0, 10, 10), <ChartPrimitive>[
          const RectPrimitive('bar', ChartRect(0, -500, 10, 1000)),
          TextPrimitive('t', 't', const ChartRect(95, 0, 10, 10), _style),
        ]),
      ]);
      expect(problems, hasLength(1));
      expect(problems.single, startsWith('t: text bounds'));
    });

    test('finds a turned text whose bounds leave the size', () {
      expect(
        _problems(<ChartPrimitive>[
          TextPrimitive(
            't',
            't',
            const ChartRect(0, 35, 40, 10),
            _style,
            rotationDegrees: -90,
          ),
        ]),
        hasLength(1),
      );
    });

    test('finds overlapping texts', () {
      expect(
        _problems(<ChartPrimitive>[
          TextPrimitive('a', 'a', const ChartRect(1, 1, 10, 10), _style),
          TextPrimitive('b', 'b', const ChartRect(5, 5, 10, 10), _style),
        ]),
        <String>['overlap: ChartOverlap(textText, a, b)'],
      );
    });
  });

  test('the generator draws the same cases on every platform', () {
    int h = 0;
    for (final int seed in _seeds) {
      for (int i = 0; i < _cases; i++) {
        h =
            (h * 31 + layoutFuzzFingerprint(layoutFuzzCase(seed, i))) &
            0x3FFFFFFF;
      }
    }
    expect(h, _fingerprint);
  });

  for (final int seed in _seeds) {
    test('seed $seed: $_cases charts lay out without overlap, inside the '
        'size, finite and without a throw', () {
      final List<String> failures = <String>[];
      for (int i = 0; i < _cases; i++) {
        final LayoutFuzzCase c = layoutFuzzCase(seed, i);
        final List<String> problems = checkLayoutCase(c);
        if (problems.isNotEmpty) {
          failures.add(
            'seed $seed case $i: ${problems.join('\n  ')}\n${c.describe()}',
          );
        }
      }
      expect(failures, isEmpty, reason: failures.take(3).join('\n'));
    });
  }
}
