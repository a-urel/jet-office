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
import '../../opc/opaque_xml.dart';
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
/// of reason `malformedXml` when the XML cannot be read. [part] must exist in
/// [package]: a missing part throws a [StateError], so check
/// [PackageReader.hasPart] first.
List<String> readSharedStrings(
  PackageReader package,
  String part,
  XlsxReadLimits limits,
) {
  return package.guardXml(part, () => _walk(package, part, limits).texts);
}

/// The shared strings of a table and the entries that are more than text.
///
/// `texts` is as [readSharedStrings] returns it. `raw` holds, by index, each
/// `<si>` that has a child other than its `<t>`, as written: runs (`<r>`),
/// phonetic runs (`<rPh>`), phonetic properties (`<phoneticPr>`), an
/// `<extLst>` or an element of another namespace. `root` is the `<sst>`
/// start tag (`null` when the part has no root element) and `trailing` the
/// root's children other than `<si>`, as written and in order, so the
/// model can write the part back with nothing lost.
typedef SharedStringsRead = ({
  List<String> texts,
  Map<int, OpaqueXml> raw,
  XmlRoot? root,
  List<OpaqueXml> trailing,
});

/// Reads the shared strings of [part] in [package] like [readSharedStrings],
/// and keeps each `<si>` that is more than text as written (see
/// [SharedStringsRead]). The limits and failures are those of
/// [readSharedStrings].
SharedStringsRead readSharedStringsRaw(
  PackageReader package,
  String part,
  XlsxReadLimits limits,
) {
  return package.guardXml(part, () {
    final _Walked walked = _walk(package, part, limits, keep: true);
    final Map<int, OpaqueXml> raw = <int, OpaqueXml>{};
    if (walked.rich.isNotEmpty) {
      // A second pass captures the kept items: whether an item is rich is
      // known only after it has been read.
      final XmlPullReader reader = package.openXml(part);
      int index = 0;
      while (reader.next()) {
        if (!_isSi(reader)) continue;
        if (walked.rich.contains(index)) {
          raw[index] = OpaqueXml.capture(reader);
        } else {
          reader.skip();
        }
        index++;
      }
    }
    return (
      texts: walked.texts,
      raw: raw,
      root: walked.root,
      trailing: walked.trailing,
    );
  });
}

bool _isSi(XmlPullReader reader) =>
    reader.eventType == XmlEventType.startElement &&
    reader.depth == 2 &&
    reader.localName == 'si' &&
    reader.namespaceUri == Ns.main;

/// What one pass over the table gives.
typedef _Walked = ({
  List<String> texts,
  Set<int> rich,
  XmlRoot? root,
  List<OpaqueXml> trailing,
});

/// The texts of the table and the indexes of its rich items, read once;
/// with [keep], also the root's start tag and its children other than
/// `<si>`.
_Walked _walk(
  PackageReader package,
  String part,
  XlsxReadLimits limits, {
  bool keep = false,
}) {
  final XmlPullReader reader = package.openXml(part);
  final List<String> strings = <String>[];
  final Set<int> rich = <int>{};
  XmlRoot? root;
  final List<OpaqueXml> trailing = <OpaqueXml>[];
  while (reader.next()) {
    if (keep && reader.eventType == XmlEventType.startElement) {
      if (reader.depth == 1) {
        root = XmlRoot.capture(reader);
        continue;
      }
      if (reader.depth == 2 && !_isSi(reader)) {
        trailing.add(OpaqueXml.capture(reader));
        continue;
      }
    }
    if (!_isSi(reader)) continue;
    if (strings.length >= limits.maxSharedStrings) {
      throw XlsxReadException(
        XlsxReadFailure.limitExceeded,
        'Limit maxSharedStrings (${limits.maxSharedStrings}) exceeded.',
        part: part,
      );
    }
    final _Rich flag = _Rich();
    final String? text = _readItem(reader, limits.maxTextLength, flag);
    if (text == null) {
      throw XlsxReadException(
        XlsxReadFailure.limitExceeded,
        'Limit maxTextLength (${limits.maxTextLength}) exceeded by shared '
        'string ${strings.length}.',
        part: part,
      );
    }
    if (flag.seen) rich.add(strings.length);
    strings.add(text);
  }
  return (texts: strings, rich: rich, root: root, trailing: trailing);
}

/// Set when an item has a child other than its `<t>`.
final class _Rich {
  bool seen = false;
}

/// The text of the string item the reader is on, a shared string's `<si>`
/// or an inline string's `<is>`: its `<t>` and its runs' `<t>`, each
/// XML-string decoded on its own, then joined; phonetic runs (`<rPh>`) and
/// elements of other namespaces are skipped. An empty element is `''`.
///
/// Returns `null` as soon as the text passes [maxLength] characters;
/// otherwise leaves the reader on the end of the item.
String? readStringItem(XmlPullReader reader, int maxLength) =>
    _readItem(reader, maxLength, null);

String? _readItem(XmlPullReader reader, int maxLength, _Rich? rich) {
  if (reader.isEmptyElement) return '';
  final StringBuffer buffer = StringBuffer();
  final int siDepth = reader.depth;
  while (reader.next()) {
    if (reader.eventType == XmlEventType.endElement && reader.depth < siDepth) {
      break;
    }
    if (reader.eventType != XmlEventType.startElement) continue;
    if (reader.depth != siDepth + 1 || reader.namespaceUri != Ns.main) {
      // A child the text model does not know (another namespace's element)
      // makes the item more than text, so the model keeps it as written.
      if (reader.depth == siDepth + 1) rich?.seen = true;
      reader.skip();
    } else if (reader.localName == 't') {
      buffer.write(_readT(reader));
    } else if (reader.localName == 'r') {
      rich?.seen = true;
      _readRun(reader, buffer, siDepth + 1);
    } else {
      // Phonetic runs and properties, or any other child (an `extLst`):
      // not part of the text, kept by the model with the item.
      rich?.seen = true;
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
