import 'dart:math' as math;

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_core/src/layout/overlap.dart' show arcShapeReach;
import 'package:jet_charts_core/src/layout/polar.dart' show polarPoint;
import 'package:test/test.dart';

import '../support/gallery.dart';

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

  test('in a dark theme a label inside a light slice takes the background', () {
    // The dark theme of docs/app-themes.md (jet_charts_flutter): the third
    // colour, FBBF24, is light, E5E7EB text on it would read at about 1.3:1.
    final ChartTheme dark = ChartTheme.fromColors(
      palette: <ChartColor>[
        ChartColor.rgb(0x60A5FA),
        ChartColor.rgb(0x34D399),
        ChartColor.rgb(0xFBBF24),
        ChartColor.rgb(0xF87171),
        ChartColor.rgb(0x1E3A8A),
      ],
      fontFamily: 'Inter',
      text: ChartColor.rgb(0xE5E7EB),
      background: ChartColor.rgb(0x111827),
    );
    final ChartLayout layout = layoutChart(
      _chart(<double?>[25, 20, 25, 15, 15]),
      theme: dark,
      size: _size,
      measurer: const FixedWidthTextMeasurer(),
    );
    final Map<String, TextPrimitive> labels = _labels(layout);
    expect(labels['label/0/2']!.style.color.rgb, 0x111827);
    expect(labels['label/0/4']!.style.color.rgb, 0xE5E7EB);
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
      expect(leader.points.length, greaterThanOrEqualTo(2));
      expect(labels.keys, contains(leader.id.replaceAll('/leader', '')));
    }
    expect(findOverlaps(layout.primitives, layout.size), isEmpty);
    _expectInsideSize(layout);
  });

  test('a leader line takes the theme\'s leaderLine colour', () {
    final ChartLayout layout = _lay(_chart(<double?>[90, 4, 3, 2, 1]));
    expect(_leaders(layout), isNotEmpty);
    for (final PathPrimitive leader in _leaders(layout)) {
      expect(leader.stroke, _office.leaderLine);
      expect(leader.stroke, isNot(_office.axisLine));
      expect(leader.strokeWidth, _office.spacing.axisLineWidth);
    }
  });

  test('the Office theme writes slice labels in its data label colour', () {
    // Excel writes a pie's labels 404040 whatever the slice (E1, chart 7).
    final ChartLayout layout = _lay(_chart(<double?>[40, 30, 20, 10]));
    final Map<String, TextPrimitive> labels = _labels(layout);
    expect(labels, isNotEmpty);
    for (final TextPrimitive label in labels.values) {
      expect(label.style, _office.dataLabels);
      expect(label.style.color.rgb, 0x404040);
    }
  });

  test('sliceLabelContrast keeps a slice label readable on a dark slice', () {
    final ChartLayout layout = layoutChart(
      _chart(<double?>[40, 30, 20, 10]),
      theme: _office.copyWith(sliceLabelContrast: true),
      size: _size,
      measurer: const FixedWidthTextMeasurer(),
    );
    // Accent 1 of the Office theme is dark: its label is white.
    expect(_labels(layout)['label/0/0']!.style.color, ChartColor.rgb(0xFFFFFF));
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

  test('the data labels format code wins over the series code', () {
    final ChartLayout layout = _lay(
      _chart(
        <double?>[40, 30, 20, 10],
        formatCode: '0.0',
        dataLabels: const ChartDataLabels(visible: true, formatCode: '0.00'),
      ),
    );
    expect(_labels(layout)['label/0/0']!.text, '40.00');
    final ChartLayout series = _lay(
      _chart(<double?>[40, 30, 20, 10], formatCode: '0.0'),
    );
    expect(_labels(series)['label/0/0']!.text, '40.0');
  });

  test('no leader line enters the pie', () {
    for (final ChartSize size in const <ChartSize>[
      _size,
      ChartSize(360, 240),
      ChartSize(640, 400),
      ChartSize(200, 140),
    ]) {
      for (final List<double?> values in <List<double?>>[
        <double?>[90, 4, 3, 2, 1],
        <double?>[60, 1, 1, 1, 1, 1, 1, 30, 1, 1, 1, 1],
        <double?>[1, 1, 1, 97],
      ]) {
        final ChartLayout layout = _lay(
          _chart(
            values,
            dataLabels: const ChartDataLabels(visible: true, showPercent: true),
          ),
          size,
        );
        final ArcPrimitive pie = _slice(layout, 0);
        for (final PathPrimitive leader in _leaders(layout)) {
          for (int i = 0; i + 1 < leader.points.length; i++) {
            expect(
              _segmentDistance(
                leader.points[i],
                leader.points[i + 1],
                pie.center,
              ),
              greaterThanOrEqualTo(pie.radius - 1e-9),
              reason: '$size $values ${leader.id}',
            );
          }
        }
        expect(findOverlaps(layout.primitives, layout.size), isEmpty);
      }
    }
  });

  test('no leader line of a gallery chart enters its pie', () {
    for (final (String name, ChartLayout layout) in goldenLayouts()) {
      for (final PathPrimitive leader in _leaders(layout)) {
        final ArcPrimitive pie = _slice(layout, 0);
        for (int i = 0; i + 1 < leader.points.length; i++) {
          expect(
            _segmentDistance(
              leader.points[i],
              leader.points[i + 1],
              pie.center,
            ),
            greaterThanOrEqualTo(pie.radius - 1e-9),
            reason: '$name ${leader.id}',
          );
        }
      }
    }
    expect(
      goldenLayouts().any(
        ((String, ChartLayout) e) => _leaders(e.$2).isNotEmpty,
      ),
      isTrue,
    );
  });

  test('a label outside gets a leader only when it moved past labelGap', () {
    final double gap = _office.spacing.labelGap;
    final ChartLayout layout = _lay(
      _chart(<double?>[
        60,
        1,
        1,
        1,
        1,
        1,
        1,
        30,
        1,
        1,
        1,
        1,
      ], dataLabels: const ChartDataLabels(visible: true, showPercent: true)),
      const ChartSize(640, 400),
    );
    final ArcPrimitive pie = _slice(layout, 0);
    final double reach = arcShapeReach(pie.radius, pie.strokeWidth) + gap;
    final Set<String> led = <String>{
      for (final PathPrimitive p in _leaders(layout))
        p.id.replaceAll('/leader', ''),
    };
    int outside = 0;
    for (final MapEntry<String, TextPrimitive> e in _labels(layout).entries) {
      final int c = int.parse(e.key.split('/')[2]);
      final ArcPrimitive slice = _slice(layout, c);
      if (e.value.corners.every((ChartPoint p) => _inSector(slice, p))) {
        continue;
      }
      outside++;
      // The first place: the label's middle height from the reach along the
      // middle angle, as close to the pie as the reach allows; and where it
      // would stand that close at its final height.
      final double clock = (slice.startAngle + 90 + slice.sweepAngle / 2) % 360;
      final bool right = clock < 180;
      final ChartPoint p = polarPoint(pie.center, reach, clock);
      final double w = e.value.rect.width;
      final double h = e.value.rect.height;
      final double firstTop =
          p.y - math.cos(clock * math.pi / 180) * h / 2 - h / 2;
      ChartPoint hug(double top) {
        final double cy = pie.center.y;
        final double dy = cy < top
            ? top - cy
            : cy > top + h
            ? cy - top - h
            : 0;
        final double dx = math.sqrt(math.max(0, reach * reach - dy * dy));
        return ChartPoint(
          right ? pie.center.x + dx : pie.center.x - dx - w,
          top,
        );
      }

      final bool moved = _distance(hug(firstTop), hug(e.value.rect.top)) > gap;
      expect(led.contains(e.key), moved, reason: e.key);
    }
    expect(outside, greaterThan(0));
    expect(led, isNotEmpty);
  });

  test('a label outside shrinks the radius once', () {
    final ChartLayout inside = _lay(_chart(<double?>[20, 20, 20, 20, 20]));
    final ChartLayout outside = _lay(_chart(<double?>[90, 4, 3, 2, 1]));
    final double full = _slice(inside, 0).radius;
    final double height = const FixedWidthTextMeasurer()
        .measure('1', _office.dataLabels)
        .height;
    expect(
      _slice(outside, 0).radius,
      closeTo(
        math.max(full / 2, full - height - _office.spacing.labelGap),
        1e-9,
      ),
    );
    expect(outside.plotArea!.width, lessThan(inside.plotArea!.width));
  });
}

double _segmentDistance(ChartPoint a, ChartPoint b, ChartPoint p) {
  final double dx = b.x - a.x;
  final double dy = b.y - a.y;
  final double l2 = dx * dx + dy * dy;
  final double t = l2 == 0
      ? 0
      : (((p.x - a.x) * dx + (p.y - a.y) * dy) / l2).clamp(0.0, 1.0);
  return _distance(ChartPoint(a.x + t * dx, a.y + t * dy), p);
}
