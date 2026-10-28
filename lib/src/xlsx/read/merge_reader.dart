/// Reads the merged ranges of one worksheet part.
///
/// Ported from quds_office_engine `lib/src/sheet/serial/sheet_serial.dart`
/// at commit 15c5d29 (the `mergeCell` branch of `readSheet`) and
/// `SmlMerge.parse` in `lib/src/sheet/model/sml_workbook.dart`.
///
/// What changed: there is no model, a merge is an `XlsxRange`; a `ref` that
/// is missing or that `XlsxRange.parse` refuses is skipped with a
/// `mergeRangeInvalid` warning instead of `SmlRange.parse` throwing; a
/// `<mergeCell>` is matched by depth, local name and SpreadsheetML
/// namespace under a `<mergeCells>` of a `<worksheet>` root, so a foreign or
/// misplaced element is not mistaken for one and prefixed producers work;
/// `<sheetData>` is skipped without being read; a root in the Strict
/// namespace is refused.
library;

import '../../opc/ooxml.dart';
import '../../xml/xml_pull_reader.dart';
import '../range.dart';
import '../warnings.dart';
import 'package_reader.dart';

/// The merged ranges of the worksheet part [part] of [package], in file
/// order.
///
/// A `<mergeCell>` whose `ref` is missing or is not a cell range, as
/// `XlsxRange.parse` reads it, is skipped and passed to [warn] as
/// [XlsxWarningCode.mergeRangeInvalid], with no cell named. A single-cell
/// merge is kept as written. A part whose root is not a SpreadsheetML
/// `<worksheet>` has no merges.
///
/// Throws an `XlsxReadException`: `unsupportedFormat` for a root in the
/// Strict OOXML namespace and `malformedXml` for XML that cannot be read.
/// [part] must exist in [package].
List<XlsxRange> readMerges(
  PackageReader package,
  String part, {
  required void Function(XlsxWarningCode code, String? cell, {String? detail})
  warn,
}) {
  return package.guardXml(part, () {
    final XmlPullReader reader = package.openXml(part);
    while (reader.next()) {
      if (reader.eventType == XmlEventType.startElement) break;
    }
    if (reader.eventType == XmlEventType.startElement &&
        reader.namespaceUri == strictSpreadsheetNs) {
      throw strictUnsupported(part: part);
    }
    final List<XlsxRange> merges = <XlsxRange>[];
    if (reader.eventType != XmlEventType.startElement ||
        reader.localName != 'worksheet' ||
        reader.namespaceUri != Ns.main ||
        reader.isEmptyElement) {
      return merges;
    }
    bool inMergeCells = false;
    while (reader.next()) {
      if (reader.eventType == XmlEventType.endElement && reader.depth < 1) {
        break;
      }
      if (reader.eventType != XmlEventType.startElement) continue;
      if (reader.depth == 2) {
        inMergeCells =
            reader.localName == 'mergeCells' && reader.namespaceUri == Ns.main;
        if (!inMergeCells) reader.skip();
        continue;
      }
      if (reader.depth == 3 &&
          inMergeCells &&
          reader.localName == 'mergeCell' &&
          reader.namespaceUri == Ns.main) {
        final String? ref = reader.getAttribute('ref', namespaceUri: '');
        reader.skip();
        final XlsxRange? range = ref == null ? null : _parse(ref);
        if (range == null) {
          warn(XlsxWarningCode.mergeRangeInvalid, null);
        } else {
          merges.add(range);
        }
        continue;
      }
      reader.skip();
    }
    return merges;
  });
}

XlsxRange? _parse(String ref) {
  try {
    return XlsxRange.parse(ref);
  } on ArgumentError {
    // Includes RangeError.
    return null;
  }
}
