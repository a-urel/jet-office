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

  group('text over marks', () {
    final ChartColor ink = ChartColor.rgb(0x156082);
    ClipPrimitive clip(List<ChartPrimitive> marks) =>
        ClipPrimitive(ids.plotClip, const ChartRect(0, 0, 200, 100), marks);

    test('a data label over another series\' bar is a mark overlap', () {
      expect(
        findOverlaps(<ChartPrimitive>[
          clip(<ChartPrimitive>[
            RectPrimitive(
              ids.seriesBarId(0, 0),
              const ChartRect(10, 20, 20, 80),
              fill: ink,
            ),
          ]),
          text(ids.dataLabelId(1, 0), const ChartRect(25, 30, 20, 10)),
        ], size),
        <ChartOverlap>[
          const ChartOverlap(
            ChartOverlapKind.textMark,
            'label/1/0',
            'series/0/bar/0',
          ),
        ],
      );
    });

    test('a data label over its own bar is not, nor one touching a bar', () {
      expect(
        findOverlaps(<ChartPrimitive>[
          clip(<ChartPrimitive>[
            RectPrimitive(
              ids.seriesBarId(0, 0),
              const ChartRect(10, 20, 20, 80),
              fill: ink,
            ),
            RectPrimitive(
              ids.seriesBarId(1, 0),
              const ChartRect(30, 50, 20, 50),
              fill: ink,
            ),
          ]),
          text(ids.dataLabelId(0, 0), const ChartRect(12, 24, 16, 10)),
          text(ids.dataLabelId(1, 0), const ChartRect(30, 40, 20, 10)),
        ], size),
        isEmpty,
      );
    });

    test('an axis label over a bar is a mark overlap', () {
      expect(
        findOverlaps(<ChartPrimitive>[
          clip(<ChartPrimitive>[
            RectPrimitive(
              ids.seriesBarId(0, 0),
              const ChartRect(10, 20, 20, 80),
              fill: ink,
            ),
          ]),
          text(
            ids.axisLabelId(ids.valueAxis, 0),
            const ChartRect(5, 30, 20, 10),
          ),
        ], size),
        <ChartOverlap>[
          const ChartOverlap(
            ChartOverlapKind.textMark,
            'axis/value/label/0',
            'series/0/bar/0',
          ),
        ],
      );
    });

    test('only the part of a mark inside its clip counts', () {
      final List<ChartPrimitive> marks = <ChartPrimitive>[
        ClipPrimitive(
          ids.plotClip,
          const ChartRect(0, 50, 200, 50),
          <ChartPrimitive>[
            RectPrimitive(
              ids.seriesBarId(0, 0),
              const ChartRect(10, 0, 20, 100),
              fill: ink,
            ),
          ],
        ),
      ];
      expect(
        findOverlaps(<ChartPrimitive>[
          ...marks,
          text(ids.dataLabelId(1, 0), const ChartRect(10, 38, 20, 12)),
        ], size),
        isEmpty,
      );
      expect(
        findOverlaps(<ChartPrimitive>[
          ...marks,
          text(ids.dataLabelId(1, 0), const ChartRect(10, 40, 20, 12)),
        ], size),
        hasLength(1),
      );
    });

    test('a line counts within half its stroke width of its path', () {
      final PathPrimitive line = PathPrimitive(
        ids.seriesLineId(0, 0),
        const <ChartPoint>[ChartPoint(0, 50), ChartPoint(100, 50)],
        stroke: ink,
        strokeWidth: 2,
      );
      expect(
        findOverlaps(<ChartPrimitive>[
          clip(<ChartPrimitive>[line]),
          text(ids.dataLabelId(0, 0), const ChartRect(40, 40, 20, 10)),
        ], size),
        <ChartOverlap>[
          const ChartOverlap(
            ChartOverlapKind.textMark,
            'label/0/0',
            'series/0/line/0',
          ),
        ],
      );
      expect(
        findOverlaps(<ChartPrimitive>[
          clip(<ChartPrimitive>[line]),
          text(ids.dataLabelId(0, 0), const ChartRect(40, 38, 20, 11)),
        ], size),
        isEmpty,
      );
      // A slanted line through the box, with no point inside it.
      expect(
        findOverlaps(<ChartPrimitive>[
          clip(<ChartPrimitive>[
            PathPrimitive(ids.seriesLineId(0, 0), const <ChartPoint>[
              ChartPoint(0, 0),
              ChartPoint(100, 100),
            ], stroke: ink),
          ]),
          text(ids.dataLabelId(1, 0), const ChartRect(40, 40, 20, 10)),
        ], size),
        hasLength(1),
      );
    });

    test('a marker counts by its box, outline included', () {
      final ArcPrimitive marker = ArcPrimitive(
        ids.seriesMarkerId(0, 0),
        const ChartPoint(50, 50),
        2.5,
        0,
        0,
        360,
        fill: ink,
        stroke: ink,
        strokeWidth: 1,
      );
      expect(
        findOverlaps(<ChartPrimitive>[
          clip(<ChartPrimitive>[marker]),
          text(ids.dataLabelId(0, 0), const ChartRect(40, 37, 20, 10.5)),
        ], size),
        <ChartOverlap>[
          const ChartOverlap(
            ChartOverlapKind.textMark,
            'label/0/0',
            'series/0/marker/0',
          ),
        ],
      );
      expect(
        findOverlaps(<ChartPrimitive>[
          clip(<ChartPrimitive>[marker]),
          text(ids.dataLabelId(0, 0), const ChartRect(40, 37, 20, 10)),
        ], size),
        isEmpty,
      );
    });

    test('an area counts by its outline, except under its own labels', () {
      // An L: the box in its notch overlaps nothing.
      final PathPrimitive area = PathPrimitive(
        ids.seriesAreaId(0),
        const <ChartPoint>[
          ChartPoint(0, 0),
          ChartPoint(50, 0),
          ChartPoint(50, 50),
          ChartPoint(100, 50),
          ChartPoint(100, 100),
          ChartPoint(0, 100),
        ],
        closed: true,
        fill: ink,
      );
      expect(
        findOverlaps(<ChartPrimitive>[
          clip(<ChartPrimitive>[area]),
          text(ids.dataLabelId(1, 0), const ChartRect(60, 10, 20, 10)),
          text(ids.dataLabelId(0, 0), const ChartRect(10, 10, 20, 10)),
        ], size),
        isEmpty,
      );
      expect(
        findOverlaps(<ChartPrimitive>[
          clip(<ChartPrimitive>[area]),
          // Wholly inside the area.
          text(ids.dataLabelId(1, 0), const ChartRect(10, 10, 20, 10)),
          // Across its edge.
          text(ids.dataLabelId(1, 1), const ChartRect(45, 30, 20, 10)),
        ], size),
        <ChartOverlap>[
          const ChartOverlap(
            ChartOverlapKind.textMark,
            'label/1/0',
            'series/0/area',
          ),
          const ChartOverlap(
            ChartOverlapKind.textMark,
            'label/1/1',
            'series/0/area',
          ),
        ],
      );
    });

    test(
      'grid lines, axis lines, the plot and legend symbols do not count',
      () {
        expect(
          findOverlaps(<ChartPrimitive>[
            const RectPrimitive(ids.background, ChartRect(0, 0, 200, 100)),
            const RectPrimitive(ids.plot, ChartRect(0, 0, 200, 100)),
            PathPrimitive(ids.gridId(ids.valueAxis, 0), const <ChartPoint>[
              ChartPoint(0, 15),
              ChartPoint(200, 15),
            ], stroke: ink),
            PathPrimitive(ids.axisLineId(ids.categoryAxis), const <ChartPoint>[
              ChartPoint(0, 15),
              ChartPoint(200, 15),
            ], stroke: ink),
            RectPrimitive(
              ids.legendSymbolId(0),
              const ChartRect(10, 10, 7, 7),
              fill: ink,
            ),
            text(ids.dataLabelId(0, 0), const ChartRect(5, 10, 20, 10)),
          ], size),
          isEmpty,
        );
      },
    );
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
