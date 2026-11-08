import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_core/src/layout/chart_ids.dart' as ids;
import 'package:test/test.dart';

ChartTextStyle style() =>
    ChartTextStyle(fontFamily: 'Test', size: 10, color: ChartColor.rgb(0));

TextPrimitive text(String id, ChartRect rect, {double rotationDegrees = 0}) =>
    TextPrimitive(id, id, rect, style(), rotationDegrees: rotationDegrees);

const ChartSize size = ChartSize(200, 100);

void main() {
  test('side by side texts do not overlap', () {
    expect(
      findOverlaps(<ChartPrimitive>[
        text('a', const ChartRect(0, 0, 20, 10)),
        text('b', const ChartRect(20, 0, 20, 10)),
      ], size),
      isEmpty,
    );
  });

  test('stacked texts overlap', () {
    expect(
      findOverlaps(<ChartPrimitive>[
        text('a', const ChartRect(0, 0, 20, 10)),
        text('b', const ChartRect(5, 5, 20, 10)),
      ], size),
      <ChartOverlap>[const ChartOverlap(ChartOverlapKind.textText, 'a', 'b')],
    );
  });

  test('a text with no area overlaps nothing', () {
    expect(
      findOverlaps(<ChartPrimitive>[
        text('a', const ChartRect(0, 0, 20, 10)),
        text('b', const ChartRect(5, 5, 0, 10)),
      ], size),
      isEmpty,
    );
  });

  test('turned texts whose boxes touch but rectangles do not', () {
    const ChartRect a = ChartRect(40, 40, 20, 4);
    final TextPrimitive first = text('a', a, rotationDegrees: 45);
    final TextPrimitive apart = text(
      'b',
      const ChartRect(50, 40, 20, 4),
      rotationDegrees: 45,
    );
    expect(first.bounds.intersects(apart.bounds), isTrue);
    expect(findOverlaps(<ChartPrimitive>[first, apart], size), isEmpty);

    final TextPrimitive near = text(
      'b',
      const ChartRect(44, 40, 20, 4),
      rotationDegrees: 45,
    );
    expect(findOverlaps(<ChartPrimitive>[first, near], size), <ChartOverlap>[
      const ChartOverlap(ChartOverlapKind.textText, 'a', 'b'),
    ]);
  });

  test('text outside the chart', () {
    expect(
      findOverlaps(<ChartPrimitive>[
        text('a', const ChartRect(190, 0, 20, 10)),
        text('b', const ChartRect(0, 0, 20, 10)),
        text('c', const ChartRect(0, -1, 0, 10)),
      ], size),
      <ChartOverlap>[
        const ChartOverlap(ChartOverlapKind.textOutside, 'a'),
        const ChartOverlap(ChartOverlapKind.textOutside, 'c'),
      ],
    );
  });

  test('legend text is not a legend overlap', () {
    final List<ChartPrimitive> primitives = <ChartPrimitive>[
      const RectPrimitive(ids.legend, ChartRect(0, 0, 50, 50)),
      text(ids.legendTextId(0), const ChartRect(5, 5, 20, 10)),
    ];
    expect(findOverlaps(primitives, size), isEmpty);
  });

  test('an axis label in the legend is', () {
    final List<ChartPrimitive> primitives = <ChartPrimitive>[
      const RectPrimitive(ids.legend, ChartRect(0, 0, 50, 50)),
      text(ids.axisLabelId(ids.valueAxis, 0), const ChartRect(5, 5, 20, 10)),
    ];
    expect(findOverlaps(primitives, size), <ChartOverlap>[
      const ChartOverlap(
        ChartOverlapKind.textLegend,
        'axis/value/label/0',
        'legend',
      ),
    ]);
  });

  test('legend over plot', () {
    expect(
      findOverlaps(<ChartPrimitive>[
        const RectPrimitive(ids.legend, ChartRect(0, 0, 50, 50)),
        const RectPrimitive(ids.plot, ChartRect(40, 40, 50, 50)),
      ], size),
      <ChartOverlap>[
        const ChartOverlap(ChartOverlapKind.legendPlot, 'legend', 'plot'),
      ],
    );
    expect(
      findOverlaps(<ChartPrimitive>[
        const RectPrimitive(ids.legend, ChartRect(0, 0, 50, 50)),
        const RectPrimitive(ids.plot, ChartRect(50, 0, 50, 50)),
      ], size),
      isEmpty,
    );
  });

  test('texts in a clip are checked', () {
    final List<ChartPrimitive> primitives = <ChartPrimitive>[
      text('a', const ChartRect(0, 0, 20, 10)),
      ClipPrimitive(
        ids.plotClip,
        const ChartRect(0, 0, 100, 100),
        <ChartPrimitive>[text('b', const ChartRect(5, 5, 20, 10))],
      ),
    ];
    expect(findOverlaps(primitives, size), <ChartOverlap>[
      const ChartOverlap(ChartOverlapKind.textText, 'a', 'b'),
    ]);
  });

  test('a chart without a legend or plot has nothing to compare', () {
    expect(
      findOverlaps(<ChartPrimitive>[
        const RectPrimitive(ids.plot, ChartRect(0, 0, 50, 50)),
        text('a', const ChartRect(0, 0, 20, 10)),
      ], size),
      isEmpty,
    );
  });

  test('ChartOverlap is a value', () {
    const ChartOverlap a = ChartOverlap(ChartOverlapKind.textText, 'a', 'b');
    expect(a, const ChartOverlap(ChartOverlapKind.textText, 'a', 'b'));
    expect(
      a.hashCode,
      const ChartOverlap(ChartOverlapKind.textText, 'a', 'b').hashCode,
    );
    expect(a, isNot(const ChartOverlap(ChartOverlapKind.textText, 'a')));
    expect(a.toString(), contains('textText'));
    expect(a.toString(), contains('a'));
  });

  test('the id builders follow the scheme', () {
    expect(ids.seriesBarId(1, 2), 'series/1/bar/2');
    expect(ids.seriesLineId(0, 1), 'series/0/line/1');
    expect(ids.seriesMarkerId(0, 3), 'series/0/marker/3');
    expect(ids.seriesAreaId(2), 'series/2/area');
    expect(ids.dataLabelId(1, 4), 'label/1/4');
    expect(ids.gridId(ids.valueAxis, 3), 'grid/value/3');
    expect(ids.axisLineId(ids.categoryAxis), 'axis/category/line');
    expect(ids.axisTitleId(ids.valueAxis), 'axis/value/title');
    expect(ids.legendSymbolId(0), 'legend/0/symbol');
  });
}
