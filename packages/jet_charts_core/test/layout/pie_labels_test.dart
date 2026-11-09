import 'dart:math' as math;

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

const ChartSize _size = ChartSize(360, 216);
final ChartTheme _office = ChartTheme.office;

Chart _chart(
  List<double?> values, {
  ChartKind kind = ChartKind.pie,
  ChartDataLabels dataLabels = const ChartDataLabels(visible: true),
  String? formatCode,
  List<ChartColor?> pointColors = const <ChartColor?>[],
}) => Chart(
  kind: kind,
  series: <ChartSeries>[
    ChartSeries(
      name: ChartData<String>(values: <String?>['Share']),
      categories: ChartData<Object>(
        values: <Object?>[for (int i = 0; i < values.length; i++) 'C${i + 1}'],
      ),
      values: ChartData<double>(values: values),
      formatCode: formatCode,
      pointColors: pointColors,
    ),
  ],
  dataLabels: dataLabels,
);

ChartLayout _lay(Chart chart, [ChartSize size = _size]) => layoutChart(
  chart,
  theme: _office,
  size: size,
  measurer: const FixedWidthTextMeasurer(),
);

Iterable<ChartPrimitive> _flat(List<ChartPrimitive> list) sync* {
  for (final ChartPrimitive p in list) {
    yield p;
    if (p is ClipPrimitive) {
      yield* _flat(p.children);
    }
  }
}

Map<String, TextPrimitive> _labels(ChartLayout layout) =>
    <String, TextPrimitive>{
      for (final ChartPrimitive p in _flat(layout.primitives))
        if (p is TextPrimitive && p.id.startsWith('label/')) p.id: p,
    };

List<PathPrimitive> _leaders(ChartLayout layout) => <PathPrimitive>[
  for (final ChartPrimitive p in _flat(layout.primitives))
    if (p is PathPrimitive && p.id.endsWith('/leader')) p,
];

ArcPrimitive _slice(ChartLayout layout, int c) =>
    _flat(
          layout.primitives,
        ).firstWhere((ChartPrimitive p) => p.id == 'series/0/slice/$c')
        as ArcPrimitive;

ChartPoint _centre(ChartRect r) =>
    ChartPoint(r.left + r.width / 2, r.top + r.height / 2);

double _distance(ChartPoint a, ChartPoint b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

/// Whether [p] lies inside [arc]'s sector.
bool _inSector(ArcPrimitive arc, ChartPoint p) {
  final double d = _distance(arc.center, p);
  if (d > arc.radius || d < arc.innerRadius) {
    return false;
  }
  final double angle =
      math.atan2(p.y - arc.center.y, p.x - arc.center.x) * 180 / math.pi;
  return (angle - arc.startAngle) % 360 <= arc.sweepAngle;
}

void _expectInsideSize(ChartLayout layout) {
  for (final ChartPrimitive p in _flat(layout.primitives)) {
    if (p is TextPrimitive) {
      final ChartRect b = p.bounds;
      expect(b.left >= -1e-6 && b.top >= -1e-6, isTrue, reason: p.id);
      expect(
        b.right <= layout.size.width + 1e-6 &&
            b.bottom <= layout.size.height + 1e-6,
        isTrue,
        reason: p.id,
      );
    }
  }
}

void main() {
  test('percent labels of [40, 30, 20, 10] sit inside their slices', () {
    final ChartLayout layout = _lay(
      _chart(
        <double?>[40, 30, 20, 10],
        dataLabels: const ChartDataLabels(
          visible: true,
          showValue: false,
          showPercent: true,
        ),
      ),
    );
    final Map<String, TextPrimitive> labels = _labels(layout);
    expect(labels.values.map((TextPrimitive t) => t.text), <String>[
      '40%',
      '30%',
      '20%',
      '10%',
    ]);
    for (int c = 0; c < 4; c++) {
      final TextPrimitive label = labels['label/0/$c']!;
      final ArcPrimitive slice = _slice(layout, c);
      for (final ChartPoint corner in label.corners) {
        expect(_inSector(slice, corner), isTrue, reason: 'label/0/$c');
      }
    }
    expect(_leaders(layout), isEmpty);
    expect(layout.hidden, isEmpty);
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });

  test('a label inside a dark slice is white', () {
    final ChartLayout layout = _lay(_chart(<double?>[40, 30, 20, 10]));
    // Accent 1 of the Office theme is dark; accent 4 (gold) is light.
    expect(_labels(layout)['label/0/0']!.style.color, ChartColor.rgb(0xFFFFFF));
  });

  test('value and percent read on two lines', () {
    final ChartLayout layout = _lay(
      _chart(
        <double?>[40, 30, 20, 10],
        formatCode: '0.0',
        dataLabels: const ChartDataLabels(visible: true, showPercent: true),
      ),
    );
    expect(_labels(layout)['label/0/0']!.text, '40.0\n40%');
  });

  test('no label when neither value nor percent is shown', () {
    final ChartLayout layout = _lay(
      _chart(<double?>[
        40,
        30,
      ], dataLabels: const ChartDataLabels(visible: true, showValue: false)),
    );
    expect(_labels(layout), isEmpty);
    expect(layout.hidden, isEmpty);
  });

  test('small slices of [90, 4, 3, 2, 1] get labels outside', () {
    final ChartLayout layout = _lay(_chart(<double?>[90, 4, 3, 2, 1]));
    final Map<String, TextPrimitive> labels = _labels(layout);
    final ArcPrimitive big = _slice(layout, 0);
    expect(_inSector(big, _centre(labels['label/0/0']!.rect)), isTrue);
    int outside = 0;
    for (int c = 1; c < 5; c++) {
      final TextPrimitive? label = labels['label/0/$c'];
      if (label == null) {
        expect(
          layout.hidden.map((ChartHiddenLabel h) => h.id),
          contains('label/0/$c'),
        );
        continue;
      }
      // Each label sits wholly inside its slice, or wholly outside the pie.
      final bool inside = label.corners.every(
        (ChartPoint p) => _inSector(_slice(layout, c), p),
      );
      if (!inside) {
        for (final ChartPoint p in label.corners) {
          expect(_distance(big.center, p), greaterThan(big.radius));
        }
        outside++;
      }
    }
    expect(outside, greaterThan(0));
    final List<String> leaderIds = <String>[
      for (final PathPrimitive p in _leaders(layout)) p.id,
    ];
    expect(leaderIds.toSet(), hasLength(leaderIds.length));
    for (final PathPrimitive leader in _leaders(layout)) {
      expect(leader.closed, isFalse);
      expect(leader.points, hasLength(2));
      expect(labels.keys, contains(leader.id.replaceAll('/leader', '')));
    }
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
    _expectInsideSize(layout);
  });

  test('a small chart hides each label it cannot place', () {
    for (final List<double?> values in <List<double?>>[
      <double?>[40, 30, 20, 10],
      <double?>[90, 4, 3, 2, 1],
    ]) {
      final ChartLayout layout = _lay(_chart(values), const ChartSize(140, 90));
      final Set<String> drawn = _labels(layout).keys.toSet();
      final Set<String> hidden = <String>{
        for (final ChartHiddenLabel h in layout.hidden)
          if (h.id.startsWith('label/')) h.id,
      };
      expect(drawn.intersection(hidden), isEmpty);
      expect(drawn.union(hidden), <String>{
        for (int c = 0; c < values.length; c++) 'label/0/$c',
      });
      expect(findOverlaps(layout.primitives, layout.size), isEmpty);
      _expectInsideSize(layout);
    }
  });

  test('minShare leaves out the labels of small slices', () {
    final ChartLayout layout = _lay(
      _chart(
        <double?>[50, 30, 12, 8],
        dataLabels: const ChartDataLabels(
          visible: true,
          showValue: false,
          showPercent: true,
          minShare: 0.1,
        ),
      ),
    );
    expect(_labels(layout).keys, <String>[
      'label/0/0',
      'label/0/1',
      'label/0/2',
    ]);
    expect(
      layout.hidden.any((ChartHiddenLabel h) => h.id == 'label/0/3'),
      isFalse,
    );
  });

  test('a donut label that does not fit its ring is hidden', () {
    final ChartLayout layout = _lay(
      _chart(<double?>[90, 4, 3, 2, 1], kind: ChartKind.donut),
    );
    final Map<String, TextPrimitive> labels = _labels(layout);
    expect(_leaders(layout), isEmpty);
    for (int c = 0; c < 5; c++) {
      final TextPrimitive? label = labels['label/0/$c'];
      if (label == null) {
        expect(
          layout.hidden.map((ChartHiddenLabel h) => h.id),
          contains('label/0/$c'),
        );
      } else {
        for (final ChartPoint corner in label.corners) {
          expect(_inSector(_slice(layout, c), corner), isTrue);
        }
      }
    }
    expect(labels, contains('label/0/0'));
    expect(labels, isNot(contains('label/0/4')));
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
  });
}
