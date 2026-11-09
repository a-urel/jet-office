// paintChartPrimitives draws each primitive kind as the core describes it.
//
// Each test paints into a picture on a white canvas and reads pixels back at
// known points. Text uses a family no test installs, so it falls back to the
// test font, whose glyphs are solid boxes: ink is easy to find.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jet_charts_core/jet_charts_core.dart';
import 'package:jet_charts_flutter/jet_charts_flutter.dart';

const int _white = 0xFFFFFF;
final ChartColor _red = ChartColor.rgb(0xFF0000);
final ChartColor _blue = ChartColor.rgb(0x0000FF);
final ChartColor _green = ChartColor.rgb(0x00FF00);

/// The pixels of a picture painted on a white canvas of [width] by
/// [height], read back.
final class _Pixels {
  _Pixels(this.width, this.height, this._bytes);

  final int width;
  final int height;
  final ByteData _bytes;

  /// The colour at ([x], [y]) as 0xRRGGBB.
  int at(int x, int y) {
    final int offset = (y * width + x) * 4;
    return (_bytes.getUint8(offset) << 16) |
        (_bytes.getUint8(offset + 1) << 8) |
        _bytes.getUint8(offset + 2);
  }
}

Future<_Pixels> _paint(
  List<ChartPrimitive> primitives, {
  int width = 100,
  int height = 100,
  FlutterTextMeasurer? measurer,
}) async {
  final FlutterTextMeasurer m = measurer ?? FlutterTextMeasurer();
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  paintChartPrimitives(canvas, primitives, m);
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(width, height);
  final ByteData bytes = (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!;
  image.dispose();
  picture.dispose();
  if (measurer == null) m.dispose();
  return _Pixels(width, height, bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a rect is filled inside and stroked on its edge', () async {
    final _Pixels p = await _paint(<ChartPrimitive>[
      RectPrimitive(
        'r',
        const ChartRect(20, 20, 60, 60),
        fill: _red,
        stroke: _blue,
        strokeWidth: 4,
      ),
    ]);
    expect(p.at(50, 50), 0xFF0000);
    expect(p.at(20, 50), 0x0000FF);
    expect(p.at(50, 79), 0x0000FF);
    expect(p.at(10, 10), _white);
  });

  test('a closed path is filled inside', () async {
    final _Pixels p = await _paint(<ChartPrimitive>[
      PathPrimitive(
        'p',
        const <ChartPoint>[
          ChartPoint(10, 10),
          ChartPoint(90, 10),
          ChartPoint(90, 90),
        ],
        closed: true,
        fill: _green,
      ),
    ]);
    expect(p.at(70, 30), 0x00FF00);
    expect(p.at(30, 70), _white);
  });

  test('a dashed line is drawn at a dash and not at a gap', () async {
    final _Pixels p = await _paint(<ChartPrimitive>[
      PathPrimitive(
        'd',
        const <ChartPoint>[ChartPoint(0, 50), ChartPoint(100, 50)],
        stroke: _blue,
        strokeWidth: 4,
        dash: const <double>[10, 10],
      ),
    ]);
    // Dashes cover 0-10, 20-30, ...; round caps add 2 on each end.
    expect(p.at(5, 50), 0x0000FF);
    expect(p.at(25, 50), 0x0000FF);
    expect(p.at(15, 50), _white);
    expect(p.at(35, 50), _white);
  });

  test('a solid line has round caps past its end points', () async {
    final _Pixels p = await _paint(<ChartPrimitive>[
      PathPrimitive(
        'l',
        const <ChartPoint>[ChartPoint(20, 50), ChartPoint(80, 50)],
        stroke: _blue,
        strokeWidth: 10,
      ),
    ]);
    // A butt cap would end at x 80; a round one reaches 85 on the axis only.
    expect(p.at(83, 50), 0x0000FF);
    expect(p.at(84, 45), _white);
  });

  test('a dash of no length is drawn solid', () async {
    final _Pixels p = await _paint(<ChartPrimitive>[
      PathPrimitive(
        'd',
        const <ChartPoint>[ChartPoint(0, 50), ChartPoint(100, 50)],
        stroke: _blue,
        strokeWidth: 4,
        dash: const <double>[0, 0],
      ),
    ]);
    expect(p.at(15, 50), 0x0000FF);
    expect(p.at(55, 50), 0x0000FF);
  });

  test('an arc is filled inside its sweep and not outside', () async {
    // A quarter from three o'clock clockwise to six: the lower right.
    final _Pixels p = await _paint(<ChartPrimitive>[
      ArcPrimitive('a', const ChartPoint(50, 50), 40, 0, 0, 90, fill: _red),
    ]);
    expect(p.at(65, 65), 0xFF0000);
    expect(p.at(35, 65), _white);
    expect(p.at(65, 35), _white);
    expect(p.at(35, 35), _white);
  });

  test('a donut segment leaves its middle empty', () async {
    final _Pixels p = await _paint(<ChartPrimitive>[
      ArcPrimitive('a', const ChartPoint(50, 50), 40, 20, -90, 180, fill: _red),
    ]);
    expect(p.at(80, 50), 0xFF0000);
    expect(p.at(55, 50), _white);
    expect(p.at(20, 50), _white);
  });

  test('a full donut is a ring', () async {
    final _Pixels p = await _paint(<ChartPrimitive>[
      ArcPrimitive('a', const ChartPoint(50, 50), 40, 20, 0, 360, fill: _red),
    ]);
    expect(p.at(80, 50), 0xFF0000);
    expect(p.at(20, 50), 0xFF0000);
    expect(p.at(50, 50), _white);
  });

  test('a clip hides the part of a child outside it', () async {
    final _Pixels p = await _paint(<ChartPrimitive>[
      ClipPrimitive('c', const ChartRect(0, 0, 50, 100), <ChartPrimitive>[
        RectPrimitive('r', const ChartRect(20, 20, 60, 60), fill: _red),
      ]),
      RectPrimitive('after', const ChartRect(85, 85, 10, 10), fill: _blue),
    ]);
    expect(p.at(30, 50), 0xFF0000);
    expect(p.at(70, 50), _white);
    // The clip ends with its children.
    expect(p.at(90, 90), 0x0000FF);
  });

  test(
    'a text rotated -90 has ink inside its bounds and none outside',
    () async {
      final FlutterTextMeasurer measurer = FlutterTextMeasurer();
      addTearDown(measurer.dispose);
      final ChartTextStyle style = ChartTextStyle(
        fontFamily: 'No Such Font',
        size: 10,
        color: ChartColor.rgb(0x000000),
      );
      final ChartSize size = measurer.measure('ABCD', style);
      final ChartRect rect = ChartRect(30, 45, size.width, size.height);
      final TextPrimitive text = TextPrimitive(
        't',
        'ABCD',
        rect,
        style,
        rotationDegrees: -90,
      );
      final _Pixels p = await _paint(<ChartPrimitive>[
        text,
      ], measurer: measurer);
      final ChartRect bounds = text.bounds;
      expect(bounds.height, greaterThan(bounds.width));
      int inside = 0;
      final List<String> outside = <String>[];
      for (int y = 0; y < p.height; y++) {
        for (int x = 0; x < p.width; x++) {
          if (p.at(x, y) == _white) continue;
          final bool within =
              x + 1 >= bounds.left &&
              x <= bounds.right &&
              y + 1 >= bounds.top &&
              y <= bounds.bottom;
          if (within) {
            inside++;
          } else {
            outside.add('($x, $y)');
          }
        }
      }
      expect(inside, greaterThan(0));
      expect(outside, isEmpty);
    },
  );

  test('an unrotated text is painted at its rect', () async {
    final FlutterTextMeasurer measurer = FlutterTextMeasurer();
    addTearDown(measurer.dispose);
    final ChartTextStyle style = ChartTextStyle(
      fontFamily: 'No Such Font',
      size: 10,
      color: ChartColor.rgb(0xFF0000),
    );
    final ChartSize size = measurer.measure('AB', style);
    final _Pixels p = await _paint(<ChartPrimitive>[
      TextPrimitive(
        't',
        'AB',
        ChartRect(40, 40, size.width, size.height),
        style,
      ),
    ], measurer: measurer);
    expect(p.at(45, 45), 0xFF0000);
    expect(p.at(35, 45), _white);
  });

  group('ChartLayoutPainter', () {
    test('repaints when the primitives or the measurer change', () {
      final FlutterTextMeasurer a = FlutterTextMeasurer();
      final FlutterTextMeasurer b = FlutterTextMeasurer();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final List<ChartPrimitive> one = <ChartPrimitive>[
        RectPrimitive('r', const ChartRect(0, 0, 1, 1), fill: _red),
      ];
      final List<ChartPrimitive> two = List<ChartPrimitive>.of(one);
      final ChartLayoutPainter painter = ChartLayoutPainter(
        primitives: one,
        measurer: a,
      );
      expect(
        painter.shouldRepaint(ChartLayoutPainter(primitives: one, measurer: a)),
        isFalse,
      );
      expect(
        painter.shouldRepaint(ChartLayoutPainter(primitives: two, measurer: a)),
        isTrue,
      );
      expect(
        painter.shouldRepaint(ChartLayoutPainter(primitives: one, measurer: b)),
        isTrue,
      );
    });

    test('paints its primitives', () async {
      final FlutterTextMeasurer measurer = FlutterTextMeasurer();
      addTearDown(measurer.dispose);
      final ChartLayoutPainter painter = ChartLayoutPainter(
        primitives: <ChartPrimitive>[
          RectPrimitive('r', const ChartRect(10, 10, 20, 20), fill: _red),
        ],
        measurer: measurer,
      );
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(40, 40));
      final ui.Picture picture = recorder.endRecording();
      final ui.Image image = await picture.toImage(40, 40);
      final ByteData bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      const int offset = (20 * 40 + 20) * 4;
      expect(bytes.getUint8(offset), 0xFF);
      expect(bytes.getUint8(offset + 1), 0);
      expect(bytes.getUint8(offset + 3), 0xFF);
      image.dispose();
      picture.dispose();
    });
  });
}
