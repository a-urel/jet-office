/// Writes the layout gallery as one HTML page, to look at in a browser.
///
/// ```bash
/// dart run tool/write_gallery.dart build/gallery
/// ```
///
/// Writes `gallery.html` in the given folder (made when missing): every chart
/// of `test/support/gallery.dart` at 360 x 240, 640 x 400 and 160 x 100, as
/// inline SVG under a heading, with no external resource. It prints the file's
/// path and exits 2 on arguments it does not understand.
library;

import 'dart:io';

import 'src/gallery_html.dart';

void main(List<String> args) {
  if (args.length != 1 || args.first.startsWith('-')) {
    stderr.writeln('Usage: dart run tool/write_gallery.dart <output folder>');
    exitCode = 2;
    return;
  }
  final Directory folder = Directory(args.first)..createSync(recursive: true);
  final File file = File('${folder.path}/gallery.html')
    ..writeAsStringSync(galleryHtml());
  stdout.writeln(file.absolute.path);
}
