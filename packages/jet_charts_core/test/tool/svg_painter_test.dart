// Tests the SVG painter of the gallery (tool/src/svg_painter.dart): the exact
// text of each primitive kind. It reads no files, so it runs on the web too.
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:test/test.dart';

import '../../tool/src/gallery_html.dart';
import '../../tool/src/svg_painter.dart';

final ChartTextStyle _style = ChartTextStyle(
  fontFamily: 'Calibri',
  size: 9,
  color: ChartColor.rgb(0x595959),
);

String _body(List<ChartPrimitive> primitives) {
  final String svg = primitivesToSvg(primitives, const ChartSize(100, 50));
  const String open =
      '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50" '
      'viewBox="0 0 100 50">';
  expect(svg, startsWith('$open\n'));
  expect(svg, endsWith('\n</svg>'));
  return svg.substring(open.length + 1, svg.length - '\n</svg>'.length);
}

void main() {
  group('svg of each primitive kind', () {
    test('a rectangle', () {
      expect(
        _body(<ChartPrimitive>[
          RectPrimitive(
            'r',
            const ChartRect(1, 2.5, 30, 4.125),
            fill: ChartColor.rgb(0x4472C4),
            stroke: ChartColor.rgb(0x000000),
            strokeWidth: 0.75,
          ),
          const RectPrimitive('n', ChartRect(0, 0, 5, 5)),
        ]),
        '<rect x="1" y="2.5" width="30" height="4.13" fill="#4472C4" '
        'stroke="#000000" stroke-width="0.75"/>\n'
        '<rect x="0" y="0" width="5" height="5" fill="none"/>',
      );
    });

    test('a path, open and dashed, and a closed one', () {
      expect(
        _body(<ChartPrimitive>[
          PathPrimitive(
            'p',
            const <ChartPoint>[ChartPoint(0, 0), ChartPoint(10, 5.5)],
            stroke: ChartColor.rgb(0xD9D9D9),
            dash: const <double>[4, 2],
          ),
          PathPrimitive(
            'q',
            const <ChartPoint>[
              ChartPoint(0, 0),
              ChartPoint(10, 0),
              ChartPoint(10, 10),
            ],
            closed: true,
            fill: ChartColor.rgb(0xFF0000),
          ),
        ]),
        '<path d="M0 0L10 5.5" fill="none" stroke="#D9D9D9" '
        'stroke-width="1" stroke-dasharray="4 2"/>\n'
        '<path d="M0 0L10 0L10 10Z" fill="#FF0000"/>',
      );
    });

    test('a pie slice and a donut segment', () {
      expect(
        _body(<ChartPrimitive>[
          ArcPrimitive(
            'a',
            const ChartPoint(50, 25),
            20,
            0,
            0,
            90,
            fill: ChartColor.rgb(0x00FF00),
          ),
          ArcPrimitive(
            'b',
            const ChartPoint(50, 25),
            20,
            10,
            0,
            90,
            stroke: ChartColor.rgb(0xFFFFFF),
          ),
        ]),
        '<path d="M70 25A20 20 0 0 1 50 45L50 25Z" fill="#00FF00"/>\n'
        '<path d="M70 25A20 20 0 0 1 50 45L50 35A10 10 0 0 0 60 25Z" '
        'fill="none" stroke="#FFFFFF"/>',
      );
    });

    test('a full circle is two half arcs', () {
      expect(
        _body(<ChartPrimitive>[
          ArcPrimitive(
            'a',
            const ChartPoint(50, 25),
            10,
            0,
            0,
            360,
            fill: ChartColor.rgb(0x00FF00),
          ),
        ]),
        '<path d="M60 25A10 10 0 0 1 40 25A10 10 0 0 1 60 25Z" '
        'fill="#00FF00"/>',
      );
    });

    test('text, rotated text and a text of two lines', () {
      expect(
        _body(<ChartPrimitive>[
          TextPrimitive('t', 'A & <B>', const ChartRect(2, 4, 30, 10), _style),
          TextPrimitive(
            'u',
            'Up',
            const ChartRect(2, 4, 30, 10),
            _style,
            rotationDegrees: -45,
          ),
          TextPrimitive(
            'v',
            'a\nb',
            const ChartRect(2, 4, 30, 10),
            ChartTextStyle(
              fontFamily: 'Calibri',
              size: 9,
              color: ChartColor.rgb(0x000000),
              bold: true,
            ),
          ),
        ]),
        '<text x="2" y="9" font-family="Calibri" font-size="9" '
        'fill="#595959" dominant-baseline="middle" textLength="30" '
        'lengthAdjust="spacingAndGlyphs">A &amp; &lt;B&gt;</text>\n'
        '<text x="2" y="9" font-family="Calibri" font-size="9" '
        'fill="#595959" dominant-baseline="middle" textLength="30" '
        'lengthAdjust="spacingAndGlyphs" transform="rotate(-45 17 9)">Up'
        '</text>\n'
        '<text font-family="Calibri" font-size="9" fill="#000000" '
        'font-weight="bold" dominant-baseline="middle">'
        '<tspan x="2" y="6.5">a</tspan><tspan x="2" y="11.5">b</tspan>'
        '</text>',
      );
    });

    test('a clip, with its children inside', () {
      expect(
        _body(<ChartPrimitive>[
          ClipPrimitive(
            'plot clip',
            const ChartRect(5, 6, 40, 20),
            <ChartPrimitive>[const RectPrimitive('c', ChartRect(0, 0, 9, 9))],
          ),
        ]),
        '<clipPath id="clip-plot_clip"><rect x="5" y="6" width="40" '
        'height="20"/></clipPath>\n'
        '<g clip-path="url(#clip-plot_clip)">\n'
        '<rect x="0" y="0" width="9" height="9" fill="none"/>\n'
        '</g>',
      );
    });

    test('an id prefix keeps clip ids apart in one page', () {
      final String svg = primitivesToSvg(
        <ChartPrimitive>[
          ClipPrimitive('c', const ChartRect(0, 0, 1, 1), <ChartPrimitive>[]),
        ],
        const ChartSize(10, 10),
        idPrefix: 'g3-',
      );
      expect(svg, contains('id="g3-clip-c"'));
      expect(svg, contains('url(#g3-clip-c)'));
    });
  });

  group('the gallery page', () {
    final String html = galleryHtml();

    test('has a heading and an svg for each chart and size', () {
      expect('<svg '.allMatches(html).length, 14 * 3);
      expect(html, contains('<h3>column_clustered, 360 x 240</h3>'));
      expect(html, contains('<h3>tile, 160 x 100</h3>'));
    });

    test('is self-contained and has no clip id twice', () {
      expect(html, isNot(contains('http://www.w3.org/1999/xlink')));
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('<link')));
      final List<String> ids = RegExp(
        r'<clipPath id="([^"]+)"',
      ).allMatches(html).map((RegExpMatch m) => m.group(1)!).toList();
      expect(ids, isNotEmpty);
      expect(ids.toSet().length, ids.length);
    });
  });
}
