import 'dart:math' as math;

import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

const ChartSize _size = ChartSize(360, 216);
final ChartTheme _office = ChartTheme.office;

ChartSeries _series(
  List<double?> values, {
  String name = 'Share',
  List<Object?>? categories,
  List<ChartColor?> pointColors = const <ChartColor?>[],
}) => ChartSeries(
  name: ChartData<String>(values: <String?>[name]),
  categories: ChartData<Object>(
    values:
        categories ??
        <Object?>[for (int i = 0; i < values.length; i++) 'C${i + 1}'],
  ),
  values: ChartData<double>(values: values),
  pointColors: pointColors,
);

Chart _chart(
  List<ChartSeries> series, {
  ChartKind kind = ChartKind.pie,
  double holeSizePercent = 75,
  String? centerText,
  String? title,
  ChartDataLabels dataLabels = const ChartDataLabels(),
}) => Chart(
  kind: kind,
  series: series,
  holeSizePercent: holeSizePercent,
  centerText: centerText,
  title: title == null ? null : ChartTitle(text: title),
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

List<ArcPrimitive> _slices(ChartLayout layout, [int series = 0]) =>
    <ArcPrimitive>[
      for (final ChartPrimitive p in _flat(layout.primitives))
        if (p is ArcPrimitive && p.id.startsWith('series/$series/slice/')) p,
    ];

/// Every problem of [layout]: an overlap, or a primitive outside its size.
List<String> _problems(ChartLayout layout) {
  final List<String> found = <String>[
    for (final ChartOverlap o in findOverlaps(layout.primitives, layout.size))
      '$o',
  ];
  bool outside(double l, double t, double r, double b) =>
      l < -1e-6 ||
      t < -1e-6 ||
      r > layout.size.width + 1e-6 ||
      b > layout.size.height + 1e-6;
  for (final ChartPrimitive p in _flat(layout.primitives)) {
    switch (p) {
      case ArcPrimitive():
        final double reach = p.radius + p.strokeWidth / 2;
        if (outside(
          p.center.x - reach,
          p.center.y - reach,
          p.center.x + reach,
          p.center.y + reach,
        )) {
          found.add('outside: ${p.id}');
        }
      case TextPrimitive():
        final ChartRect b = p.bounds;
        if (outside(b.left, b.top, b.right, b.bottom)) {
          found.add('outside: ${p.id}');
        }
      case PathPrimitive():
        for (final ChartPoint q in p.points) {
          if (outside(q.x, q.y, q.x, q.y)) {
            found.add('outside: ${p.id}');
          }
        }
      case RectPrimitive():
        if (outside(p.rect.left, p.rect.top, p.rect.right, p.rect.bottom)) {
          found.add('outside: ${p.id}');
        }
      case ClipPrimitive():
        break;
    }
  }
  return found;
}

void main() {
  group('a pie', () {
    test(
      'of [1, 1, 2] has slices of 90, 90 and 180 degrees from 12 o clock',
      () {
        final ChartLayout layout = _lay(
          _chart(<ChartSeries>[
            _series(<double?>[1, 1, 2]),
          ]),
        );
        final List<ArcPrimitive> slices = _slices(layout);
        expect(slices.map((ArcPrimitive a) => a.id), <String>[
          'series/0/slice/0',
          'series/0/slice/1',
          'series/0/slice/2',
        ]);
        expect(slices[0].startAngle, closeTo(-90, 1e-9));
        for (int i = 0; i < 3; i++) {
          expect(slices[i].sweepAngle, closeTo(<double>[90, 90, 180][i], 1e-9));
          expect(slices[i].fill, _office.seriesColor(i));
          expect(slices[i].stroke, _office.background);
          expect(slices[i].strokeWidth, 0.75);
          expect(slices[i].innerRadius, 0);
          if (i > 0) {
            expect(
              slices[i].startAngle,
              closeTo(
                slices[i - 1].startAngle + slices[i - 1].sweepAngle,
                1e-9,
              ),
            );
          }
        }
        expect(layout.valueScale, isNull);
        expect(layout.categoryBands, isEmpty);
        final ChartRect plot = layout.plotArea!;
        expect(plot.width, closeTo(plot.height, 1e-9));
        expect(slices[0].center.x, closeTo(plot.left + plot.width / 2, 1e-9));
        expect(slices[0].center.y, closeTo(plot.top + plot.height / 2, 1e-9));
        expect(_problems(layout), isEmpty);
      },
    );

    test('the plot is the largest square of the space left, centred', () {
      final ChartLayout layout = _lay(
        _chart(<ChartSeries>[
          _series(<double?>[1, 2]),
        ]),
      );
      final ChartRect plot = layout.plotArea!;
      final TextPrimitive legend = _flat(layout.primitives)
          .whereType<TextPrimitive>()
          .firstWhere((TextPrimitive t) => t.id == 'legend/0/text');
      // The legend is at the bottom, so the square takes the height above it.
      expect(plot.bottom, lessThan(legend.rect.top));
      expect(plot.top, closeTo(_office.spacing.padding, 1e-9));
      expect(plot.left + plot.width / 2, closeTo(_size.width / 2, 1e-9));
      final ArcPrimitive slice = _slices(layout).first;
      expect(
        slice.radius + slice.strokeWidth / 2,
        closeTo(plot.width / 2, 1e-9),
      );
    });

    test('takes a point colour for its slice', () {
      final ChartLayout layout = _lay(
        _chart(<ChartSeries>[
          _series(
            <double?>[1, 1, 2],
            pointColors: <ChartColor?>[null, ChartColor.rgb(0x00FF00)],
          ),
        ]),
      );
      final List<ArcPrimitive> slices = _slices(layout);
      expect(slices[0].fill, _office.seriesColor(0));
      expect(slices[1].fill, ChartColor.rgb(0x00FF00));
      expect(slices[2].fill, _office.seriesColor(2));
      final RectPrimitive symbol = _flat(layout.primitives)
          .whereType<RectPrimitive>()
          .firstWhere((RectPrimitive r) => r.id == 'legend/1/symbol');
      expect(symbol.fill, ChartColor.rgb(0x00FF00));
    });

    test('takes a point colour key from the theme, light or dark', () {
      final Chart chart = _chart(<ChartSeries>[
        _series(<double?>[
          1,
          1,
          2,
        ]).copyWith(pointColorKeys: <String?>['paid', null, 'overdue']),
      ], kind: ChartKind.donut);
      ChartLayout lay(ChartTheme theme) => layoutChart(
        chart,
        theme: theme,
        size: _size,
        measurer: const FixedWidthTextMeasurer(),
      );
      final ChartTheme light = _office.copyWith(
        semantic: <String, ChartColor>{
          'paid': ChartColor.rgb(0x16A34A),
          'overdue': ChartColor.rgb(0xDC2626),
        },
      );
      final ChartTheme dark = _office.copyWith(
        semantic: <String, ChartColor>{
          'paid': ChartColor.rgb(0x4ADE80),
          'overdue': ChartColor.rgb(0xF87171),
        },
      );
      final List<ArcPrimitive> lit = _slices(lay(light));
      expect(lit[0].fill, ChartColor.rgb(0x16A34A));
      expect(lit[1].fill, _office.seriesColor(1));
      expect(lit[2].fill, ChartColor.rgb(0xDC2626));
      final ChartLayout night = lay(dark);
      expect(_slices(night)[0].fill, ChartColor.rgb(0x4ADE80));
      expect(
        _flat(night.primitives)
            .whereType<RectPrimitive>()
            .firstWhere((RectPrimitive r) => r.id == 'legend/2/symbol')
            .fill,
        ChartColor.rgb(0xF87171),
      );
    });

    test('of one value is a full disc', () {
      final List<ArcPrimitive> slices = _slices(
        _lay(
          _chart(<ChartSeries>[
            _series(<double?>[5]),
          ]),
        ),
      );
      expect(slices, hasLength(1));
      expect(slices.single.sweepAngle, closeTo(360, 1e-9));
    });

    test('of zero, null and NaN draws no slice and lists three entries', () {
      final ChartLayout layout = _lay(
        _chart(<ChartSeries>[
          _series(<double?>[0, null, double.nan]),
        ]),
      );
      expect(_slices(layout), isEmpty);
      expect(
        _flat(layout.primitives)
            .where((ChartPrimitive p) => p.id.endsWith('/text'))
            .map((ChartPrimitive p) => p.id),
        <String>['legend/0/text', 'legend/1/text', 'legend/2/text'],
      );
      expect(_problems(layout), isEmpty);
    });

    test('draws a negative value as its absolute value', () {
      final List<ArcPrimitive> slices = _slices(
        _lay(
          _chart(<ChartSeries>[
            _series(<double?>[3, -1]),
          ]),
        ),
      );
      expect(slices[0].sweepAngle, closeTo(270, 1e-9));
      expect(slices[1].sweepAngle, closeTo(90, 1e-9));
    });

    test('draws the first series only', () {
      final ChartLayout layout = _lay(
        _chart(<ChartSeries>[
          _series(<double?>[1, 2]),
          _series(<double?>[3, 4], name: 'Other'),
        ]),
      );
      expect(_slices(layout), hasLength(2));
      expect(_slices(layout, 1), isEmpty);
    });

    test('of nine categories has nine colours', () {
      final List<ArcPrimitive> slices = _slices(
        _lay(
          _chart(<ChartSeries>[
            _series(<double?>[for (int i = 1; i <= 9; i++) i.toDouble()]),
          ]),
        ),
      );
      expect(slices, hasLength(9));
      expect(slices.map((ArcPrimitive a) => a.fill).toSet(), hasLength(9));
    });

    test('draws no centre text', () {
      final ChartLayout layout = _lay(
        _chart(<ChartSeries>[
          _series(<double?>[1, 2]),
        ], centerText: 'Toplam'),
      );
      expect(
        _flat(layout.primitives).any((ChartPrimitive p) => p.id == 'center'),
        isFalse,
      );
      expect(
        layout.hidden.any((ChartHiddenLabel h) => h.id == 'center'),
        isFalse,
      );
    });

    test('a slice outline of 0 draws none', () {
      final ChartLayout layout = layoutChart(
        _chart(<ChartSeries>[
          _series(<double?>[1, 2]),
        ]),
        theme: _office.copyWith(sliceBorderWidth: 0),
        size: _size,
        measurer: const FixedWidthTextMeasurer(),
      );
      expect(
        _slices(layout).every((ArcPrimitive a) => a.stroke == null),
        isTrue,
      );
    });

    test('too small for a square draws the background only', () {
      final Chart chart = _chart(
        <ChartSeries>[
          _series(<double?>[1, 2]),
        ],
        title: 'Share',
        dataLabels: const ChartDataLabels(visible: true),
      );
      final ChartLayout layout = _lay(chart, const ChartSize(14, 14));
      expect(layout.primitives.map((ChartPrimitive p) => p.id), <String>[
        'background',
      ]);
      expect(layout.plotArea, isNull);
      expect(layout.hidden.map((ChartHiddenLabel h) => h.id), <String>[
        'label/0/0',
        'label/0/1',
        'legend/0/text',
        'legend/1/text',
        'title',
      ]);
    });
  });

  group('a donut', () {
    test('of two series has two rings, the first innermost', () {
      final ChartLayout layout = _lay(
        _chart(<ChartSeries>[
          _series(<double?>[1, 3]),
          _series(<double?>[2, 2], name: 'Two'),
        ], kind: ChartKind.donut),
      );
      final List<ArcPrimitive> inner = _slices(layout);
      final List<ArcPrimitive> outer = _slices(layout, 1);
      expect(inner, hasLength(2));
      expect(outer, hasLength(2));
      final double r = outer.first.radius;
      final double hole = inner.first.innerRadius;
      expect(hole, closeTo(0.75 * r, 1e-9));
      final double ring = (r - hole) / 2;
      expect(inner.first.radius, closeTo(hole + ring, 1e-9));
      expect(outer.first.innerRadius, closeTo(hole + ring, 1e-9));
      expect(inner[0].sweepAngle, closeTo(90, 1e-9));
      expect(outer[0].sweepAngle, closeTo(180, 1e-9));
      // Every ring takes the category colours.
      expect(outer[1].fill, _office.seriesColor(1));
      expect(_problems(layout), isEmpty);
    });

    test('a hole size of 50 gives a hole of half the radius', () {
      final List<ArcPrimitive> slices = _slices(
        _lay(
          _chart(
            <ChartSeries>[
              _series(<double?>[1, 3]),
            ],
            kind: ChartKind.donut,
            holeSizePercent: 50,
          ),
        ),
      );
      expect(slices.first.innerRadius, closeTo(slices.first.radius / 2, 1e-9));
    });

    test('draws its centre text in the hole', () {
      final ChartLayout layout = _lay(
        _chart(
          <ChartSeries>[
            _series(<double?>[1, 3, 2]),
          ],
          kind: ChartKind.donut,
          centerText: 'Toplam 12.450 ₺',
        ),
      );
      final TextPrimitive text = _flat(layout.primitives)
          .whereType<TextPrimitive>()
          .firstWhere((TextPrimitive t) => t.id == 'center');
      expect(text.text, 'Toplam 12.450 ₺');
      expect(text.style, _office.centerTextStyle);
      final ArcPrimitive slice = _slices(layout).first;
      for (final ChartPoint c in text.corners) {
        final double d = math.sqrt(
          math.pow(c.x - slice.center.x, 2) + math.pow(c.y - slice.center.y, 2),
        );
        // It keeps the minimum text gap from the ring and its outline.
        expect(
          d,
          lessThanOrEqualTo(
            slice.innerRadius -
                slice.strokeWidth / 2 -
                _office.spacing.minTextGap,
          ),
        );
      }
      expect(_problems(layout), isEmpty);
    });

    test('hides a centre text that does not fit the hole', () {
      final ChartLayout layout = _lay(
        _chart(
          <ChartSeries>[
            _series(<double?>[1, 3, 2]),
          ],
          kind: ChartKind.donut,
          centerText: 'Toplam 12.450 ₺',
        ),
        const ChartSize(120, 80),
      );
      expect(
        _flat(layout.primitives).any((ChartPrimitive p) => p.id == 'center'),
        isFalse,
      );
      expect(
        layout.hidden,
        contains(const ChartHiddenLabel('center', 'Toplam 12.450 ₺')),
      );
      expect(_problems(layout), isEmpty);
    });
  });

  test('a centre text that would come closer than minTextGap is hidden', () {
    // The fixed-width measurer makes 'MMMM' 33.6 by 16.8 at 14 pt: a half
    // diagonal of 18.78. A hole whose free radius is between that and that
    // plus the gap must hide it.
    const String text = 'MMMM';
    bool shown(double side) => _flat(
      _lay(
        _chart(
          <ChartSeries>[
            _series(<double?>[1, 2]),
          ],
          kind: ChartKind.donut,
          centerText: text,
        ).copyWith(legend: const ChartLegend(visible: false)),
        ChartSize(side + 16, side + 16),
      ).primitives,
    ).any((ChartPrimitive p) => p.id == 'center');
    // Hole radius = 0.75 * (side / 2 - 0.375); free radius about that less
    // 0.375. Half diagonal 18.78, plus 2 pt gap: 20.78.
    expect(shown(58), isTrue); // free radius about 21.2
    expect(shown(54), isFalse); // free radius about 19.7, less than 20.78
  });
}
