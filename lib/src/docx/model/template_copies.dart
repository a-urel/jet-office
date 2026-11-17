/// What the model's copies for the template fill share: the result of a copy,
/// the annotations a copy leaves out, the mark a copy carries, and the removal
/// of annotations from a kept element (T2, decision 0024; plan T2, Rulings 9
/// and 10).
///
/// Not ported from Quds; written for jet_office.
///
/// A section that repeats keeps its content in place as the first copy and
/// makes the others from it (`copyInlines` in `inlines.dart`, `copyRows` and
/// `copyBlocks` in `blocks.dart`). A copy leaves out what may be anchored only
/// once in a document: bookmarks, comment ranges and references, note
/// references, permission ranges and move ranges ([copyDroppedNames]),
/// wherever they are, typed or inside a kept element ([withoutAnnotations]).
/// Each unit a copy function makes (an inline, a row or a block, the items of
/// its result) is marked ([isTemplateCopy]), and a save gives what a marked
/// unit holds new drawing, revision and content control ids (`StoryWriter`).
///
/// Nothing here is exported.
library;

import '../../opc/ooxml.dart' show Ns;
import '../../opc/opaque_xml.dart';
import '../../xml/xml_escape.dart' show escapeXmlAttribute, scrubXmlText;
import '../../xml/xml_pull_reader.dart';
import '../read_exception.dart';
import '../story_reader.dart' show readerOfCaptured;

/// What a copy function returns: the copies, in order, and the local names
/// (in WordprocessingML) of the annotations it left out, empty when none.
typedef CopyResult<T> = ({List<T> items, Set<String> dropped});

/// The local names, in WordprocessingML, of the elements a copy leaves out
/// (plan T2, Ruling 10): bookmarks (typed or kept), comment ranges and
/// references, note references, permission ranges, move ranges and the
/// range marks of tracked custom XML.
const Set<String> copyDroppedNames = <String>{
  'bookmarkStart',
  'bookmarkEnd',
  'commentRangeStart',
  'commentRangeEnd',
  'commentReference',
  'footnoteReference',
  'endnoteReference',
  'permStart',
  'permEnd',
  'moveFromRangeStart',
  'moveFromRangeEnd',
  'moveToRangeStart',
  'moveToRangeEnd',
  'customXmlInsRangeStart',
  'customXmlInsRangeEnd',
  'customXmlDelRangeStart',
  'customXmlDelRangeEnd',
  'customXmlMoveFromRangeStart',
  'customXmlMoveFromRangeEnd',
  'customXmlMoveToRangeStart',
  'customXmlMoveToRangeEnd',
};

/// Whether a kept element of [namespaceUri] and [localName] is one a copy
/// leaves out whole.
bool isDroppedByCopy(String namespaceUri, String localName) =>
    namespaceUri == Ns.w && copyDroppedNames.contains(localName);

final Expando<bool> _copies = Expando<bool>('template copy');

/// Whether a copy function ever marked a unit, so a writer of a part can skip
/// looking for copies until one exists.
bool get templateCopiesMade => _copiesMade;
bool _copiesMade = false;

/// Whether [unit] (a `DocxInline`, `DocxTableRow` or `DocxBlock`) was made by
/// a copy function, as one of the items of its result: a save renews the
/// ids of what it holds.
bool isTemplateCopy(Object unit) => _copies[unit] ?? false;

/// Marks [unit] as made by a copy function; only those call it.
void markTemplateCopy(Object unit) {
  _copies[unit] = true;
  _copiesMade = true;
}

/// [xml] without the elements of [copyDroppedNames] inside it, re-captured
/// with the same inherited namespaces, and the local names of those it
/// removed; [xml] itself when it holds none. [xml] is unchanged, and its own
/// element is never removed: the caller leaves out an element that is one
/// of them.
///
/// The slice is read again, nested at most [maxDepth] deep: give the
/// document's `DocxReadLimits.maxDepth`, under which the slice was read
/// already. A slice deeper than [maxDepth] throws a [DocxReadException] of
/// `DocxReadFailure.limitExceeded`, and one that does not parse (which a
/// slice the reader captured never does) one of
/// `DocxReadFailure.malformedXml`; nothing else comes out.
({OpaqueXml xml, Set<String> dropped}) withoutAnnotations(
  OpaqueXml xml,
  int maxDepth,
) {
  // A slice that names none of them cannot hold one, and is not parsed.
  if (!copyDroppedNames.any(xml.xml.contains)) {
    return (xml: xml, dropped: const <String>{});
  }
  try {
    return _withoutAnnotations(xml, maxDepth);
  } on XmlParseException catch (e) {
    throw DocxReadException(
      e.kind == XmlParseKind.tooDeep
          ? DocxReadFailure.limitExceeded
          : DocxReadFailure.malformedXml,
      'A kept element could not be read again for a copy: ${e.message}',
    );
  }
}

({OpaqueXml xml, Set<String> dropped}) _withoutAnnotations(
  OpaqueXml xml,
  int maxDepth,
) {
  final XmlPullReader r = readerOfCaptured(xml, maxDepth);
  final int depth = r.depth;
  int copied = r.eventStart;
  final StringBuffer out = StringBuffer();
  final Set<String> dropped = <String>{};
  int end = r.eventEnd;
  if (!r.isEmptyElement) {
    while (r.next()) {
      if (r.eventType == XmlEventType.endElement && r.depth < depth) {
        end = r.eventEnd;
        break;
      }
      if (r.eventType != XmlEventType.startElement ||
          !isDroppedByCopy(r.namespaceUri, r.localName)) {
        continue;
      }
      dropped.add(r.localName);
      out.write(r.sourceText(copied, r.eventStart));
      r.skip();
      copied = r.eventEnd;
    }
  }
  if (dropped.isEmpty) return (xml: xml, dropped: const <String>{});
  out.write(r.sourceText(copied, end));
  return (xml: _recapture(out.toString(), xml, maxDepth), dropped: dropped);
}

/// [text], an element written where [like] was, captured with the bindings
/// [like] inherited.
OpaqueXml _recapture(String text, OpaqueXml like, int maxDepth) {
  final StringBuffer source = StringBuffer('<r');
  like.inheritedNamespaces.forEach((String prefix, String uri) {
    source
      ..write(prefix.isEmpty ? ' xmlns="' : ' xmlns:$prefix="')
      ..write(escapeXmlAttribute(scrubXmlText(uri).text))
      ..write('"');
  });
  source
    ..write('>')
    ..write(text)
    ..write('</r>');
  // Removing elements made the slice no deeper than it was read.
  final XmlPullReader r =
      XmlPullReader(source.toString(), maxDepth: maxDepth + 1)
        ..nextTag()
        ..nextTag();
  return OpaqueXml.capture(r);
}
