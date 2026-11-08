/// The gallery page: every chart of `test/support/gallery.dart` at each of
/// the gallery sizes, as inline SVG with a heading, in one self-contained
/// HTML text. Pure Dart; `tool/write_gallery.dart` writes it to a file.
library;

import 'package:jet_charts_core/jet_charts_core.dart';

import '../../test/support/gallery.dart';
import 'svg_painter.dart';

/// The whole gallery as one HTML document with no external resource.
String galleryHtml() {
  final StringBuffer out = StringBuffer()
    ..writeln('<!DOCTYPE html>')
    ..writeln('<html lang="en">')
    ..writeln('<head>')
    ..writeln('<meta charset="utf-8">')
    ..writeln('<title>jet_charts_core layout gallery</title>')
    ..writeln('<style>')
    ..writeln('body { font-family: sans-serif; margin: 16px; }')
    ..writeln('h2 { margin: 24px 0 4px; font-size: 16px; }')
    ..writeln('h3 { margin: 12px 0 4px; font-size: 13px; color: #555; }')
    ..writeln('svg { border: 1px solid #ccc; display: block; }')
    ..writeln('</style>')
    ..writeln('</head>')
    ..writeln('<body>')
    ..writeln('<h1>jet_charts_core layout gallery</h1>')
    ..writeln(
      '<p>Fixed-width measurer, Office theme, en-US. Text is stretched to '
      'the width the layout measured, so a browser font does not move it.</p>',
    );
  int index = 0;
  for (final GalleryChart g in galleryCharts()) {
    out.writeln('<h2>${g.name}</h2>');
    for (final ChartSize size in gallerySizes) {
      final ChartLayout layout = g.layout(size);
      out
        ..writeln(
          '<h3>${g.name}, ${size.width.round()} x ${size.height.round()}</h3>',
        )
        ..writeln(
          primitivesToSvg(layout.primitives, size, idPrefix: 'g${index++}-'),
        );
    }
  }
  out
    ..writeln('</body>')
    ..write('</html>');
  return out.toString();
}
