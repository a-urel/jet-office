/// Writes the workbook of the owner's side-by-side check against Excel.
///
/// ```bash
/// dart run packages/jet_charts_flutter/example/tool/write_excel_gallery.dart build/excel_gallery
/// ```
///
/// It writes `gallery.xlsx` to the directory given: every chart of the
/// app's gallery (`lib/gallery.dart`) as Excel's own default chart, by
/// `buildExcelGallery` (`lib/src/excel_gallery.dart`). `TALIMATLAR.md` says
/// how the owner compares it with the app. Exit 2 on unusable arguments.
library;

import 'dart:io';

import 'package:jet_charts_gallery/gallery.dart';
import 'package:jet_charts_gallery/src/excel_gallery.dart';

void main(List<String> args) {
  if (args.length != 1 || args.single.startsWith('-')) {
    stderr.writeln('Usage: dart run tool/write_excel_gallery.dart <dir>');
    exitCode = 2;
    return;
  }
  final List<GalleryEntry> entries = galleryEntries();
  final Directory dir = Directory(args.single)..createSync(recursive: true);
  File('${dir.path}/gallery.xlsx').writeAsBytesSync(buildExcelGallery(entries));
  stdout.writeln(
    'Wrote gallery.xlsx with ${entries.length} charts to ${dir.path}.',
  );
}
