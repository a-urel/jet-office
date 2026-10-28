/// Reads the shared-string table of an XLSX workbook.
///
/// Ported from quds_office_engine `lib/src/builders/xlsx_io.dart` at commit
/// 15c5d29: `XlsxGridReader._sharedStrings` and `_readSi`.
///
/// What changed: a string is its direct `<t>` plus the `<t>` of every `<r>`,
/// in order, each XML-string decoded on its own (an escape split across two
/// runs stays literal, as in Excel); `<rPh>` and `<phoneticPr>` contents are
/// skipped (Quds appended the phonetic text); only `<si>` elements that are
/// children of the root count; elements match by local name and SpreadsheetML
/// namespace; the table size and each string's length are limited; and
/// `_readSi` is public as [readStringItem], which also reads the `<is>` of
/// an inline string cell.
library;

import '../../opc/ooxml.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_pull_reader.dart';
import 'package_reader.dart';
import 'read_exception.dart';
import 'read_limits.dart';

/// Reads the shared strings of [part] in [package], in table order.
///
/// A string is the text of its direct `<t>` and of every run's `<t>`, each
/// XML-string decoded on its own (`_x0041_` becomes `A`, but `_x00` in one
/// run and `41_` in the next stay as written), joined in order. Elements of
/// other namespaces are skipped with their contents. Phonetic runs
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
      final String? text = readStringItem(reader, limits.maxTextLength);
      if (text == null) {
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

/// The text of the string item the reader is on, a shared string's `<si>`
/// or an inline string's `<is>`: its `<t>` and its runs' `<t>`, each
/// XML-string decoded on its own, then joined; phonetic runs (`<rPh>`) and
/// elements of other namespaces are skipped. An empty element is `''`.
///
/// Returns `null` as soon as the text passes [maxLength] characters;
/// otherwise leaves the reader on the end of the item.
String? readStringItem(XmlPullReader reader, int maxLength) {
  if (reader.isEmptyElement) return '';
  final StringBuffer buffer = StringBuffer();
  final int siDepth = reader.depth;
  while (reader.next()) {
    if (reader.eventType == XmlEventType.endElement && reader.depth < siDepth) {
      break;
    }
    if (reader.eventType != XmlEventType.startElement) continue;
    if (reader.depth != siDepth + 1 || reader.namespaceUri != Ns.main) {
      reader.skip();
    } else if (reader.localName == 't') {
      buffer.write(_readT(reader));
    } else if (reader.localName == 'r') {
      _readRun(reader, buffer, siDepth + 1);
    } else {
      reader.skip();
    }
    if (buffer.length > maxLength) return null;
  }
  return buffer.toString();
}

/// Appends the decoded `<t>` of the `<r>` the reader is on to [buffer],
/// leaving the reader on the end of the run.
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
      buffer.write(_readT(reader));
    } else {
      reader.skip();
    }
  }
}

/// The text of the `<t>` the reader is on, XML-string decoded (`_x0041_`
/// becomes `A`), leaving the reader on its end.
String _readT(XmlPullReader reader) {
  if (reader.isEmptyElement) return '';
  final StringBuffer buffer = StringBuffer();
  final int depth = reader.depth;
  while (reader.next()) {
    if (reader.eventType == XmlEventType.endElement && reader.depth < depth) {
      break;
    }
    if (reader.eventType == XmlEventType.characters ||
        reader.eventType == XmlEventType.cdata) {
      buffer.write(reader.text);
    }
  }
  return decodeXstring(buffer.toString());
}
