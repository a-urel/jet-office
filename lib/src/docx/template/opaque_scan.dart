/// The tags and `MERGEFIELD` instructions in content the model keeps opaque.
///
/// New in jet_office (decision 0024, spec section 6, Ruling 14);
/// quds_office_engine has no template fill, so this is not ported from Quds.
/// The fill cannot edit a text box, an anchored drawing, `mc:AlternateContent`,
/// a block content control, or the footnotes, endnotes and comments parts, but
/// it must say what it left there. Text is joined per `w:p`, so a tag split
/// over two paragraphs is no tag, as it would be none in the body.
library;

import '../../opc/ooxml.dart' show Ns;
import '../../opc/opaque_xml.dart';
import '../../xml/xml_pull_reader.dart';
import '../docx_package.dart';
import '../story_reader.dart' show readerOfCaptured;
import 'merge_field.dart';
import 'tag_scanner.dart';

/// Every tag text and `MERGEFIELD` instruction found in [xml], in document
/// order: the `{{…}}` matches closed by `}}` in the `w:t` text of each `w:p`
/// (joined over its runs; text outside any `w:p` counts as one paragraph),
/// the text of each `w:instrText`, and each `w:fldSimple`'s `w:instr`, that
/// `parseMergeField` reads as a `MERGEFIELD`.
///
/// Without [outsideParagraphs], text outside any `w:p` is not scanned: for an
/// inline whose visible text the paragraph's own scan reads already, so only
/// what it holds out of sight (a text box's paragraphs) is found here.
///
/// `mc:Fallback` is skipped: it repeats its `mc:Choice`. A `w:instrText` or a
/// `w:p` nested in another, which the schema forbids but a file may hold, is
/// read without failing. [xml] is read again, nested at most [maxDepth] deep;
/// anything that cannot be read gives an empty list.
List<String> placeholdersIn(
  OpaqueXml xml, {
  int maxDepth = 256,
  bool outsideParagraphs = true,
}) {
  try {
    final XmlPullReader r = readerOfCaptured(xml, maxDepth);
    return _scan(r, outsideParagraphs: outsideParagraphs);
  } on Exception {
    return const <String>[];
  }
}

/// [placeholdersIn] for the whole XML part [part] of [package], or an empty
/// list when the package lacks it or it cannot be read.
List<String> placeholdersInPart(DocxPackage package, String part) {
  if (!package.package.hasPart(part)) return const <String>[];
  try {
    final XmlPullReader r = package.openXml(part);
    while (r.next()) {
      if (r.eventType == XmlEventType.startElement) {
        return _scan(r);
      }
    }
    return const <String>[];
  } on Exception {
    return const <String>[];
  }
}

/// What an open element is to the scan.
enum _Open { paragraph, text, instruction, skipped, other }

/// Scans the element [r] is on, from its start tag to its end.
List<String> _scan(XmlPullReader r, {bool outsideParagraphs = true}) {
  final List<String> found = <String>[];
  final List<_Open> open = <_Open>[];
  // The text of the paragraphs open, innermost last; the first is the text
  // outside any paragraph.
  final List<StringBuffer> paragraphs = <StringBuffer>[StringBuffer()];
  // The text of the outermost `w:instrText` open; one nested in it, which a
  // file may hold, adds to it.
  StringBuffer instruction = StringBuffer();
  int instructions = 0;
  int skipping = 0;

  void flush(StringBuffer text) {
    for (final TagMatch m in scanTags(text.toString())) {
      if (m.text.endsWith('}}')) found.add(m.text);
    }
  }

  void addInstruction(String text) {
    if (parseMergeField(text) != null) found.add(text);
  }

  while (true) {
    switch (r.eventType) {
      case XmlEventType.startElement:
        final bool w = r.namespaceUri == Ns.w;
        final String name = r.localName;
        _Open kind;
        if (skipping > 0 || (r.namespaceUri == Ns.mc && name == 'Fallback')) {
          kind = _Open.skipped;
          skipping++;
        } else if (w && name == 'p') {
          kind = _Open.paragraph;
          paragraphs.add(StringBuffer());
        } else if (w && name == 't') {
          kind = _Open.text;
        } else if (w && name == 'instrText') {
          kind = _Open.instruction;
          if (instructions++ == 0) instruction = StringBuffer();
        } else {
          kind = _Open.other;
          if (w && name == 'fldSimple') {
            final String? instr = r.getAttribute('instr', namespaceUri: Ns.w);
            if (instr != null) addInstruction(instr);
          }
        }
        open.add(kind);
      case XmlEventType.endElement:
        if (open.isEmpty) break;
        switch (open.removeLast()) {
          case _Open.skipped:
            skipping--;
          case _Open.paragraph:
            flush(paragraphs.removeLast());
          case _Open.instruction:
            if (--instructions == 0) addInstruction(instruction.toString());
          case _Open.text || _Open.other:
            break;
        }
      case XmlEventType.characters || XmlEventType.cdata:
        if (open.isEmpty) break;
        switch (open.last) {
          case _Open.text:
            paragraphs.last.write(r.text);
          case _Open.instruction:
            instruction.write(r.text);
          default:
            break;
        }
      default:
        break;
    }
    if (open.isEmpty || !r.next()) break;
  }
  if (outsideParagraphs) flush(paragraphs.first);
  return found;
}
