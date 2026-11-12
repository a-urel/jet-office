/// Test helpers: the chart parts and theme colours of an owner's Excel
/// workbook on disk.
///
/// Apart from `excel_charts.dart`, whose constants the Chrome tests import,
/// because these read files with `dart:io`: only `@TestOn('vm')` tests may
/// import this library.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:jet_office/src/common/theme_colors.dart';
import 'package:jet_office/src/xml/xml_pull_reader.dart';

import '../../../support/read_xlsx.dart';

/// `xl/charts/chart<n>.xml` of the XLSX file at [xlsxPath], as bytes.
///
/// Throws a [StateError] when the file has no such part.
Uint8List chartPartOf(String xlsxPath, int n) {
  final Uint8List? part = _parts(xlsxPath)['xl/charts/chart$n.xml'];
  if (part == null) {
    throw StateError('$xlsxPath has no xl/charts/chart$n.xml');
  }
  return part;
}

/// The colours of `xl/theme/theme1.xml` of the XLSX file at [xlsxPath].
///
/// Throws a [StateError] when the file has no theme or its colours cannot be
/// read.
ThemeColors themeColorsOf(String xlsxPath) {
  final Uint8List? part = _parts(xlsxPath)['xl/theme/theme1.xml'];
  final ThemeColors? colors = part == null
      ? null
      : ThemeColors.read(XmlPullReader.fromBytes(part));
  if (colors == null) {
    throw StateError('$xlsxPath has no readable xl/theme/theme1.xml');
  }
  return colors;
}

final Map<String, Map<String, Uint8List>> _cache =
    <String, Map<String, Uint8List>>{};

Map<String, Uint8List> _parts(String xlsxPath) => _cache.putIfAbsent(
  xlsxPath,
  () => readXlsxBytes(File(xlsxPath).readAsBytesSync()),
);
