/// Paints the primitives `jet_charts_core` lays out on a Flutter [Canvas].
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:jet_charts_core/jet_charts_core.dart';

import 'text_measurer.dart';

/// Paints [primitives] on [canvas] in order, drawing text with [measurer]'s
/// painters.
///
/// The rules, one per primitive kind:
///
/// * a [RectPrimitive] is filled, then stroked;
/// * a [PathPrimitive] is a path through its points, closed when it says so,
///   filled, then stroked with round caps and joins (as Excel draws lines); a
///   `dash` cuts the stroke into dashes and gaps, and a dash with no positive
///   length, or a negative or non-finite one, is drawn solid;
/// * an [ArcPrimitive] runs along the outer circle from its start angle by
///   its sweep, then back along the inner circle (or to the centre when the
///   inner radius is 0), in degrees clockwise from three o'clock; a sweep of a
///   full turn or more is a whole circle or ring. It is filled, then stroked
///   its stroke width wide;
/// * a [TextPrimitive] is the measurer's laid-out painter for its text and
///   style, painted at its rect's top left, the canvas turned by its rotation
///   about the rect's centre;
/// * a [ClipPrimitive] draws its children clipped to its rect.
///
/// Colours are drawn opaque. The painters come from [measurer] at each call,
/// so none is kept across paints.
void paintChartPrimitives(
  Canvas canvas,
  List<ChartPrimitive> primitives,
  FlutterTextMeasurer measurer,
) {
  for (final ChartPrimitive p in primitives) {
    switch (p) {
      case RectPrimitive():
        _paintRect(canvas, p);
      case PathPrimitive():
        _paintPath(canvas, p);
      case ArcPrimitive():
        _paintArc(canvas, p);
      case TextPrimitive():
        _paintText(canvas, p, measurer);
      case ClipPrimitive():
        canvas
          ..save()
          ..clipRect(_rect(p.rect));
        paintChartPrimitives(canvas, p.children, measurer);
        canvas.restore();
    }
  }
}

Color _color(ChartColor c) => Color(0xFF000000 | c.rgb);

Rect _rect(ChartRect r) => Rect.fromLTWH(r.left, r.top, r.width, r.height);

Paint _fill(ChartColor c) => Paint()
  ..style = PaintingStyle.fill
  ..color = _color(c);

Paint _stroke(ChartColor c, double width) => Paint()
  ..style = PaintingStyle.stroke
  ..color = _color(c)
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

void _paintRect(Canvas canvas, RectPrimitive p) {
  final Rect rect = _rect(p.rect);
  if (p.fill != null) canvas.drawRect(rect, _fill(p.fill!));
  if (p.stroke != null) {
    // A rect's outline keeps square corners.
    canvas.drawRect(
      rect,
      _stroke(p.stroke!, p.strokeWidth)..strokeJoin = StrokeJoin.miter,
    );
  }
}

void _paintPath(Canvas canvas, PathPrimitive p) {
  if (p.points.isEmpty) return;
  final Path path = Path()..moveTo(p.points.first.x, p.points.first.y);
  for (final ChartPoint q in p.points.skip(1)) {
    path.lineTo(q.x, q.y);
  }
  if (p.closed) path.close();
  if (p.fill != null) canvas.drawPath(path, _fill(p.fill!));
  if (p.stroke != null) {
    final List<double>? dash = p.dash;
    canvas.drawPath(
      dash == null || !_usableDash(dash, path) ? path : _dashed(path, dash),
      _stroke(p.stroke!, p.strokeWidth),
    );
  }
}

/// The most dashes and gaps a path is cut into; a finer pattern is drawn
/// solid, so a tiny dash cannot stall a paint.
const int _maxDashPieces = 10000;

/// Whether [dash] has only finite lengths of zero or more, some above zero,
/// and cuts [path] into at most [_maxDashPieces] pieces.
bool _usableDash(List<double> dash, Path path) {
  if (dash.isEmpty) return false;
  double cycle = 0;
  for (final double d in dash) {
    if (!d.isFinite || d < 0) return false;
    cycle += d;
  }
  if (cycle <= 0) return false;
  double length = 0;
  for (final PathMetric metric in path.computeMetrics()) {
    length += metric.length;
  }
  return length / cycle * dash.length <= _maxDashPieces;
}

/// The dashes of [path]: [dash]'s lengths alternate between drawn and not,
/// continuing from one contour to the next.
Path _dashed(Path path, List<double> dash) {
  final Path out = Path();
  int index = 0;
  double left = dash[0];
  for (final PathMetric metric in path.computeMetrics()) {
    double at = 0;
    while (at < metric.length) {
      final double step = math.min(left, metric.length - at);
      if (index.isEven && step > 0) {
        out.addPath(metric.extractPath(at, at + step), Offset.zero);
      }
      at += step;
      left -= step;
      if (left <= 0) {
        index =
            (index + 1) % (dash.length.isEven ? dash.length : 2 * dash.length);
        left = dash[index % dash.length];
      }
    }
  }
  return out;
}

void _paintArc(Canvas canvas, ArcPrimitive p) {
  if (p.fill == null && p.stroke == null) return;
  final Offset centre = Offset(p.center.x, p.center.y);
  final Rect outer = Rect.fromCircle(center: centre, radius: p.radius);
  final double inner = math.max(0, p.innerRadius);
  final Path path;
  if (p.sweepAngle.abs() >= 360) {
    path = Path()..addOval(outer);
    if (inner > 0) {
      path
        ..addOval(Rect.fromCircle(center: centre, radius: inner))
        ..fillType = PathFillType.evenOdd;
    }
  } else {
    final double start = p.startAngle * math.pi / 180;
    final double sweep = p.sweepAngle * math.pi / 180;
    path = Path()..arcTo(outer, start, sweep, true);
    if (inner > 0) {
      path.arcTo(
        Rect.fromCircle(center: centre, radius: inner),
        start + sweep,
        -sweep,
        false,
      );
    } else {
      path.lineTo(centre.dx, centre.dy);
    }
    path.close();
  }
  if (p.fill != null) canvas.drawPath(path, _fill(p.fill!));
  if (p.stroke != null) {
    canvas.drawPath(path, _stroke(p.stroke!, p.strokeWidth));
  }
}

void _paintText(Canvas canvas, TextPrimitive p, FlutterTextMeasurer measurer) {
  final TextPainter painter = measurer.textPainter(p.text, p.style);
  final Offset topLeft = Offset(p.rect.left, p.rect.top);
  if (p.rotationDegrees == 0) {
    painter.paint(canvas, topLeft);
    return;
  }
  final double cx = p.rect.left + p.rect.width / 2;
  final double cy = p.rect.top + p.rect.height / 2;
  canvas
    ..save()
    ..translate(cx, cy)
    ..rotate(p.rotationDegrees * math.pi / 180)
    ..translate(-cx, -cy);
  painter.paint(canvas, topLeft);
  canvas.restore();
}
