/// Paints a layout's primitives as SVG, so a person can look at a layout in a
/// browser (`tool/write_gallery.dart`); there is no Flutter renderer before J3.
///
/// The painter is pure Dart and reads no file. Its text rules:
///
/// * a text is put at its rectangle's left edge and vertical middle
///   (`dominant-baseline="middle"`), with `textLength` set to the rectangle's
///   width and `lengthAdjust="spacingAndGlyphs"`, so a browser keeps the
///   width the layout measured, whatever font it falls back to;
/// * a rotation is `transform="rotate(deg cx cy)"` about the rectangle's
///   centre, clockwise as the primitive says;
/// * a text of several lines writes one `<tspan>` per line, each in its share
///   of the rectangle's height, without a `textLength` (the layout measured
///   the longest line, not each).
///
/// An arc is a path: the outer arc, then the inner arc back (or the centre for
/// a pie slice), in degrees clockwise from three o'clock on a y-down canvas. A
/// clip is a `<clipPath>` with an id made from the primitive's id and then a
/// `<g clip-path>` for its children.
library;

import 'dart:math' as math;

import 'package:jet_charts_core/jet_charts_core.dart';

/// [primitives] as one SVG document of [size].
///
/// [idPrefix] goes in front of every `clipPath` id, so several documents in
/// one HTML page do not share ids.
String primitivesToSvg(
  List<ChartPrimitive> primitives,
  ChartSize size, {
  String idPrefix = '',
}) {
  final StringBuffer out = StringBuffer()
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" width="${_n(size.width)}" '
      'height="${_n(size.height)}" '
      'viewBox="0 0 ${_n(size.width)} ${_n(size.height)}">',
    );
  _paint(primitives, out, idPrefix);
  out.write('</svg>');
  return out.toString();
}

void _paint(List<ChartPrimitive> primitives, StringBuffer out, String prefix) {
  for (final ChartPrimitive p in primitives) {
    switch (p) {
      case RectPrimitive():
        out.writeln(_rect(p));
      case PathPrimitive():
        out.writeln(_path(p));
      case ArcPrimitive():
        out.writeln(_arc(p));
      case TextPrimitive():
        out.writeln(_text(p));
      case ClipPrimitive():
        final String id = '$prefix${'clip-${_idPart(p.id)}'}';
        out
          ..writeln(
            '<clipPath id="$id"><rect x="${_n(p.rect.left)}" '
            'y="${_n(p.rect.top)}" width="${_n(p.rect.width)}" '
            'height="${_n(p.rect.height)}"/></clipPath>',
          )
          ..writeln('<g clip-path="url(#$id)">');
        _paint(p.children, out, prefix);
        out.writeln('</g>');
    }
  }
}

String _rect(RectPrimitive p) {
  final StringBuffer b = StringBuffer()
    ..write(
      '<rect x="${_n(p.rect.left)}" y="${_n(p.rect.top)}" '
      'width="${_n(p.rect.width)}" height="${_n(p.rect.height)}"',
    );
  _paintAttributes(b, p.fill, p.stroke, p.strokeWidth, null);
  b.write('/>');
  return b.toString();
}

String _path(PathPrimitive p) {
  final StringBuffer d = StringBuffer();
  for (int i = 0; i < p.points.length; i++) {
    d.write('${i == 0 ? 'M' : 'L'}${_n(p.points[i].x)} ${_n(p.points[i].y)}');
  }
  if (p.closed && p.points.isNotEmpty) d.write('Z');
  final StringBuffer b = StringBuffer()..write('<path d="$d"');
  _paintAttributes(b, p.fill, p.stroke, p.strokeWidth, p.dash);
  b.write('/>');
  return b.toString();
}

String _arc(ArcPrimitive p) {
  final double r = p.radius;
  final double ri = p.innerRadius;
  final double sweep = p.sweepAngle.clamp(-360.0, 360.0);
  final bool clockwise = sweep >= 0;
  ChartPoint at(double radius, double degrees) {
    final double a = degrees * math.pi / 180;
    return ChartPoint(
      p.center.x + radius * math.cos(a),
      p.center.y + radius * math.sin(a),
    );
  }

  String move(String command, ChartPoint q) => '$command${_n(q.x)} ${_n(q.y)}';
  String arc(double radius, ChartPoint to, bool large, bool forward) =>
      'A${_n(radius)} ${_n(radius)} 0 ${large ? 1 : 0} ${forward ? 1 : 0} '
      '${_n(to.x)} ${_n(to.y)}';

  final StringBuffer d = StringBuffer();
  final double start = p.startAngle;
  if (sweep.abs() >= 360) {
    // A full circle cannot be one SVG arc (start and end are the same point).
    final double half = start + (clockwise ? 180 : -180);
    d
      ..write(move('M', at(r, start)))
      ..write(arc(r, at(r, half), false, clockwise))
      ..write(arc(r, at(r, start), false, clockwise));
    if (ri > 0) {
      d
        ..write(move('M', at(ri, start)))
        ..write(arc(ri, at(ri, half), false, !clockwise))
        ..write(arc(ri, at(ri, start), false, !clockwise));
    }
  } else {
    final double end = start + sweep;
    final bool large = sweep.abs() > 180;
    d
      ..write(move('M', at(r, start)))
      ..write(arc(r, at(r, end), large, clockwise));
    if (ri > 0) {
      d
        ..write(move('L', at(ri, end)))
        ..write(arc(ri, at(ri, start), large, !clockwise));
    } else {
      d.write(move('L', p.center));
    }
  }
  d.write('Z');
  final StringBuffer b = StringBuffer()..write('<path d="$d"');
  _paintAttributes(b, p.fill, p.stroke, p.strokeWidth, null);
  b.write('/>');
  return b.toString();
}

String _text(TextPrimitive p) {
  final ChartRect r = p.rect;
  final StringBuffer b = StringBuffer()..write('<text');
  final List<String> lines = p.text.split('\n');
  final bool single = lines.length == 1;
  if (single) {
    b.write(' x="${_n(r.left)}" y="${_n(r.top + r.height / 2)}"');
  }
  b.write(
    ' font-family="${_escape(p.style.fontFamily)}" '
    'font-size="${_n(p.style.size)}" fill="${_hex(p.style.color)}"',
  );
  if (p.style.bold) b.write(' font-weight="bold"');
  b.write(' dominant-baseline="middle"');
  if (single) {
    b.write(' textLength="${_n(r.width)}" lengthAdjust="spacingAndGlyphs"');
  }
  if (p.rotationDegrees != 0) {
    b.write(
      ' transform="rotate(${_n(p.rotationDegrees)} '
      '${_n(r.left + r.width / 2)} ${_n(r.top + r.height / 2)})"',
    );
  }
  b.write('>');
  if (single) {
    b.write(_escape(p.text));
  } else {
    final double h = r.height / lines.length;
    for (int i = 0; i < lines.length; i++) {
      b.write(
        '<tspan x="${_n(r.left)}" y="${_n(r.top + h * (i + 0.5))}">'
        '${_escape(lines[i])}</tspan>',
      );
    }
  }
  b.write('</text>');
  return b.toString();
}

void _paintAttributes(
  StringBuffer b,
  ChartColor? fill,
  ChartColor? stroke,
  double? strokeWidth,
  List<double>? dash,
) {
  b.write(' fill="${fill == null ? 'none' : _hex(fill)}"');
  if (stroke != null) {
    b.write(' stroke="${_hex(stroke)}"');
    if (strokeWidth != null) b.write(' stroke-width="${_n(strokeWidth)}"');
  }
  if (dash != null && dash.isNotEmpty) {
    b.write(' stroke-dasharray="${dash.map(_n).join(' ')}"');
  }
}

String _hex(ChartColor c) =>
    '#${c.rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// A number to at most two decimals, without trailing zeros or `-0`.
String _n(double v) {
  if (!v.isFinite) return '0';
  String s = v.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s == '-0' ? '0' : s;
}

String _idPart(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
