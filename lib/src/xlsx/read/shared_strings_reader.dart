/// Reads the shared-string table of an XLSX workbook.
///
/// Ported from quds_office_engine `lib/src/builders/xlsx_io.dart` at commit
/// 15c5d29: `XlsxGridReader._sharedStrings` and `_readSi`.
///
/// What changed: a string is its direct `<t>` plus the `<t>` of every `<r>`,
/// in order, then XML-string decoded; `<rPh>` and `<phoneticPr>` contents are
/// skipped (Quds appended the phonetic text); only `<si>` elements that are
/// children of the root count; elements match by local name and SpreadsheetML
/// namespace; the table size and each string's length are limited.
library;

import '../../opc/ooxml.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import 'package_reader.dart';
import 'read_exception.dart';
import 'read_limits.dart';

/// Reads the shared strings of [part] in [package], in table order.
///
/// A string is the text of its direct `<t>` and of every run's `<t>`, joined
/// in order and XML-string decoded (`_x0041_` becomes `A`). Phonetic runs
/// (`<rPh>`) are not part of the string. An empty `<si/>` is `''`.
///
/// Throws an [XlsxReadException] of reason `limitExceeded` when the table
/// holds more than [XlsxReadLimits.maxSharedStrings] strings, or a string is
/// longer than [XlsxReadLimits.maxTextLength] characters after decoding, and
/// of reason `malformedXml` when the XML cannot be read.
List<String> readSharedStrings(
  PackageReader package,
  String part,
  XlsxReadLimits limits,
) {
  return package.guardXml(part, () {
    final XmlPullReader reader = package.openXml(part);
    final List<String> strings = <String>[];
    while (reader.next()) {
      if (reader.eventType != XmlEventType.startElement ||
          reader.depth != 2 ||
          reader.localName != 'si' ||
          reader.namespaceUri != Ns.main) {
        continue;
      }
      if (strings.length >= limits.maxSharedStrings) {
        throw XlsxReadException(
          XlsxReadFailure.limitExceeded,
          'Limit maxSharedStrings (${limits.maxSharedStrings}) exceeded.',
          part: part,
        );
      }
      final String text = decodeXstring(_readSi(reader));
      if (text.length > limits.maxTextLength) {
        throw XlsxReadException(
          XlsxReadFailure.limitExceeded,
          'Limit maxTextLength (${limits.maxTextLength}) exceeded by shared '
          'string ${strings.length}.',
          part: part,
        );
      }
      strings.add(text);
    }
    return strings;
  });
}

/// The raw text of the `<si>` the reader is on: its `<t>` and its runs'
/// `<t>`, leaving the reader on the end of the `<si>`.
String _readSi(XmlPullReader reader) {
  if (reader.isEmptyElement) return '';
  final StringBuffer buffer = StringBuffer();
  final int siDepth = reader.depth;
  while (reader.next()) {
    if (reader.eventType == XmlEventType.endElement && reader.depth < siDepth) {
      break;
    }
    if (reader.eventType != XmlEventType.startElement ||
        reader.namespaceUri != Ns.main) {
      continue;
    }
    if (reader.depth == siDepth + 1 && reader.localName == 't') {
      _readT(reader, buffer);
    } else if (reader.depth == siDepth + 1 && reader.localName == 'r') {
      _readRun(reader, buffer, siDepth + 1);
    } else {
      reader.skip();
    }
  }
  return buffer.toString();
}

void _readRun(XmlPullReader reader, StringBuffer buffer, int runDepth) {
  if (reader.isEmptyElement) return;
  while (reader.next()) {
    if (reader.eventType == XmlEventType.endElement &&
        reader.depth < runDepth) {
      return;
    }
    if (reader.eventType != XmlEventType.startElement) continue;
    if (reader.depth == runDepth + 1 &&
        reader.localName == 't' &&
        reader.namespaceUri == Ns.main) {
      _readT(reader, buffer);
    } else {
      reader.skip();
    }
  }
}

void _readT(XmlPullReader reader, StringBuffer buffer) {
  if (reader.isEmptyElement) return;
  final int depth = reader.depth;
  while (reader.next()) {
    if (reader.eventType == XmlEventType.endElement && reader.depth < depth) {
      return;
    }
    if (reader.eventType == XmlEventType.characters ||
        reader.eventType == XmlEventType.cdata) {
      buffer.write(reader.text);
    }
  }
}
