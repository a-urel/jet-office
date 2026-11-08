/// The main document part, `word/document.xml`, read into the body model.
///
/// Not ported from Quds; written for jet_office.
///
/// [DocumentPart.read] walks the part once with the pull reader. It reads the
/// root, what surrounds the body (`w:background`, a second `w:body`) as opaque
/// elements kept in place, and the attributes of `w:body` as kept attributes;
/// the blocks of the body are read by [StoryReader], whose library says what
/// is typed and what is kept, and written back by [StoryWriter].
///
/// The body's last child, when it is a `w:sectPr`, is the last section
/// ([DocumentPart.finalSection]); a `w:sectPr` before another child stays an
/// opaque block. It is captured like any other element, because only what
/// follows tells, and its slice is read as a container once it is last.
///
/// A table nested past [maxTableNesting] is refused, by its path.
///
/// Elements match by namespace URI and local name, never by prefix: a
/// document written with `ns0:` or a default namespace reads the same.
/// Strict WordprocessingML never gets here; the package refuses it.
///
/// [DocumentPart.encode] writes the part back from the model. The root is
/// written as read, with every namespace declaration and `mc:Ignorable`, and
/// every kept element and attribute is written with the root's bindings as
/// the ones in scope, so it declares only what it needs and never redeclares
/// `w`. Typed elements use the root's own prefix for WordprocessingML. What
/// it writes for a part read and not edited means the same as the part (see
/// `tool/src/part_compare.dart`), with the children of each `w:pPr`, `w:rPr`,
/// `w:tblPr`, `w:trPr`, `w:tcPr` and `w:sectPr` in schema order and without
/// comments between them; a document with no edit therefore saves the file's
/// bytes instead (`DocxDocument`).
library;

import 'dart:typed_data';

import '../opc/ooxml.dart' show Ns;
import '../opc/opaque_xml.dart';
import '../opc/package.dart' show PartContent;
import '../xml/utf8_buffer.dart';
import '../xml/xml_pull_reader.dart';
import '../xml/xml_writer.dart';
import 'model/blocks.dart';
import 'model/inlines.dart' show DocxBookmarkStart;
import 'model/property_set.dart';
import 'model/sections.dart';
import 'model/styles.dart' show DocxStyleType;
import 'part_root.dart';
import 'properties.dart';
import 'read_exception.dart';
import 'read_limits.dart';
import 'section_property_codecs.dart' show sectionPropertiesSchema;
import 'story_reader.dart';
import 'story_writer.dart';
import 'warnings.dart';

/// The main document part: the root's start tag, what surrounds the body,
/// and the body's blocks.
final class DocumentPart implements PartContent {
  DocumentPart._(
    this.partName,
    this.root,
    this.beforeBody,
    this.bodyAttributes,
    this.blocks,
    this.finalSection,
    this.afterBody, {
    required bool hasBody,
  }) : _hasBody = hasBody;

  /// The main document part of a new document: a `w:document` that declares
  /// only `w`, with an empty body and a last section of no values. Add
  /// paragraphs to [blocks].
  DocumentPart.create({String partName = '/word/document.xml'})
    : this._(
        partName,
        const XmlRoot.of('w:document', <String, String>{'w': Ns.w}),
        const <OpaqueXml>[],
        const <KeptAttribute>[],
        <DocxBlock>[],
        newSection(const PropertyContainer.empty()),
        const <OpaqueXml>[],
        hasBody: true,
      );

  /// Reads the part from [r], which must not have been advanced, and
  /// consumes it to the end of the root element.
  ///
  /// [partName] is the part's absolute name, for errors. [limits] bounds
  /// every text: a `w:t`, or the visible text of an opaque inline, longer
  /// than [DocxReadLimits.maxTextLength] throws a [DocxReadException] of
  /// [DocxReadFailure.limitExceeded] that names the paragraph, as
  /// `body/p[i]` or `body/tbl[i]/tr[j]/tc[k]/p[m]`; so does a table nested
  /// past [maxTableNesting], by its own path. A root that is not
  /// `w:document` throws one of [DocxReadFailure.malformedXml]. [warnings]
  /// receives the problems the reader repairs; D1 repairs none in this part.
  ///
  /// XML that is not well-formed, nested deeper than the reader allows or
  /// holds an entity that cannot be decoded throws [XmlParseException]:
  /// call this inside `DocxPackage.guard`, which turns it into a
  /// [DocxReadException].
  static DocumentPart read(
    XmlPullReader r,
    DocxWarningCollector warnings,
    String partName, {
    required DocxReadLimits limits,
  }) => _PartReader(
    StoryReader(r, partName, limits.maxTextLength, limits.maxDepth),
    partName,
  ).read();

  /// The part's absolute name, such as `/word/document.xml`: the part of
  /// the warnings [encode] raises.
  final String partName;

  /// Whether the part has a `w:body`. A document read without one is
  /// written without one, unless blocks were added.
  final bool _hasBody;

  DocxWarningCollector _encodeWarnings = DocxWarningCollector();

  /// Whether the document defines the list instance a numId names, so a
  /// `w:numPr` set through the API that names another is reported at
  /// [encode] (plan Ruling 8); `null` reports none. The save sets it
  /// before it writes the part.
  bool Function(int numId)? listDefined;

  /// Whether the document defines a style of that id and type, so a
  /// `w:pStyle`, `w:rStyle` or `w:tblStyle` set through the API that names
  /// another is reported at [encode] (plan Ruling 8); `null` reports none.
  /// The save sets it before it writes the part.
  bool Function(String id, DocxStyleType type)? styleDefined;

  /// The id this save gives the bookmark a built start begins, the same for
  /// its end wherever it is written; `null` outside a save. The save sets it
  /// before it writes the part.
  int Function(DocxBookmarkStart start)? bookmarkId;

  /// The warnings the last [encode] raised; empty before the first.
  ///
  /// Each [encode] starts a new collector, so encoding twice reports each
  /// problem once: the save reads this after it encoded the part. The
  /// characters a run lost when its text was set are reported here, with
  /// [DocxWarningCode.invalidCharactersRemoved] at the run's location at
  /// that time, `body/p[i]/r[j]`, where `i` counts only the paragraphs of
  /// the body and `j` only the runs of the paragraph. In a table the
  /// location is `body/tbl[i]/tr[j]/tc[k]/p[m]/r[n]`, each index counting
  /// its own kind in its container, and `tbl[a]/tr[b]/tc[c]` repeats for a
  /// nested table. A run that is no longer in the body is not reported. A
  /// paragraph whose `w:numPr` was set through the API to a list other than
  /// 0 that [listDefined] denies is reported with
  /// [DocxWarningCode.numberingNotFound] at its location, with the list's id
  /// as the detail. A style set through the API that [styleDefined] denies
  /// is reported with [DocxWarningCode.styleNotFound] at the location of the
  /// paragraph, the run or the table, with the style's id as the detail.
  DocxWarningCollector get encodeWarnings => _encodeWarnings;

  /// The root element's start tag: its name, namespace declarations and
  /// attributes (`mc:Ignorable` among them), so the part is written back
  /// with every binding its kept content uses.
  final XmlRoot root;

  /// The children of `w:document` before `w:body`, such as `w:background`,
  /// in order.
  final List<OpaqueXml> beforeBody;

  /// The attributes of `w:body`, in source order; empty without a body.
  final List<KeptAttribute> bodyAttributes;

  /// The body's blocks in order: paragraphs, tables and opaque blocks. The
  /// final `w:sectPr` is not one of them; see [finalSection].
  final List<DocxBlock> blocks;

  /// The last section: the body's last child when it is a `w:sectPr`, else
  /// a section of no values, written once one is set. A `w:sectPr` anywhere
  /// else in the body is an opaque block, and one in a paragraph's `w:pPr`
  /// is that paragraph's section. Only `DocxBody.addSection` changes it.
  DocxSection finalSection;

  /// The children of `w:document` after `w:body`, in order. A second
  /// `w:body` is one of them.
  final List<OpaqueXml> afterBody;

  /// Throws [StateError] naming the first table the API left without rows,
  /// at its location: Word repairs a table without rows, and a save must find
  /// that out before it writes anything. A table read with no rows is kept.
  void checkBuiltTables() => checkTablesHaveRows(blocks, 'body');

  /// Writes the part, and replaces [encodeWarnings] with the warnings of
  /// this write.
  @override
  List<Uint8List> encode() {
    final DocxWarningCollector warnings = DocxWarningCollector();
    final Utf8Buffer buffer = Utf8Buffer();
    final XmlWriter w = XmlWriter(buffer)..declaration();
    final (:String prefix, :Map<String, String> scope) = openWordRoot(w, root);
    _writePart(
      StoryWriter(
        w,
        '$prefix:',
        prefix,
        scope,
        partName,
        warnings,
        listDefined,
        styleDefined,
        bookmarkId,
      ),
      this,
    );
    w.end();
    _encodeWarnings = warnings;
    return buffer.takeChunks();
  }
}

/// Writes the part's content inside the open root: what precedes the body,
/// the body with its blocks and final `w:sectPr`, and what follows it.
void _writePart(StoryWriter story, DocumentPart part) {
  final XmlWriter w = story.writer;
  final Map<String, String> scope = story.scope;
  for (final OpaqueXml x in part.beforeBody) {
    x.writeTo(w, declaredAbove: scope);
  }
  final PropertySet sectPr = sectionPropertySetOf(part.finalSection);
  if (part._hasBody ||
      part.blocks.isNotEmpty ||
      part.bodyAttributes.isNotEmpty ||
      !sectPr.writesNothing) {
    w.start('${story.wordPrefix}body');
    writeKeptAttributes(w, part.bodyAttributes, declaredAbove: scope);
    story.scope = scopeInside(part.bodyAttributes, scope);
    story.writeBlocks(part.blocks, 'body');
    if (!sectPr.writesNothing) {
      story.writePropertySet(sectPr, 'sectPr');
    }
    story.scope = scope;
    w.end();
  }
  for (final OpaqueXml x in part.afterBody) {
    x.writeTo(w, declaredAbove: scope);
  }
}

/// One read of a document part: the root, what surrounds the body, and the
/// body's final `w:sectPr`. The blocks are the [StoryReader]'s.
final class _PartReader {
  _PartReader(this._story, this._partName);

  final StoryReader _story;
  final String _partName;

  DocumentPart read() {
    final XmlPullReader r = _story.r;
    while (r.next()) {
      if (r.eventType == XmlEventType.startElement) break;
    }
    if (r.eventType != XmlEventType.startElement || !isW(r, 'document')) {
      throw DocxReadException(
        DocxReadFailure.malformedXml,
        'The main document part has no w:document root element.',
        part: _partName,
      );
    }
    final XmlRoot root = XmlRoot.capture(r);
    final List<OpaqueXml> before = <OpaqueXml>[];
    final List<OpaqueXml> after = <OpaqueXml>[];
    List<KeptAttribute> bodyAttributes = const <KeptAttribute>[];
    final List<DocxBlock> blocks = <DocxBlock>[];
    PropertyContainer finalSectPr = const PropertyContainer.empty();
    bool bodySeen = false;
    eachChild(r, () {
      if (!bodySeen && isW(r, 'body')) {
        bodySeen = true;
        bodyAttributes = List<KeptAttribute>.unmodifiable(keepAttributes(r));
        finalSectPr = _readBody(blocks);
      } else {
        (bodySeen ? after : before).add(OpaqueXml.capture(r));
      }
    });
    return DocumentPart._(
      _partName,
      root,
      List<OpaqueXml>.unmodifiable(before),
      bodyAttributes,
      blocks,
      newSection(finalSectPr),
      List<OpaqueXml>.unmodifiable(after),
      hasBody: bodySeen,
    );
  }

  /// Reads the children of `w:body` into [blocks] and returns the final
  /// `w:sectPr`, or an empty container when the last child is no `w:sectPr`.
  PropertyContainer _readBody(List<DocxBlock> blocks) {
    final XmlPullReader r = _story.r;
    final BlockReader reader = BlockReader('body', blocks);
    // A sectPr is final only if nothing follows it.
    OpaqueXml? sectPr;
    eachChild(r, () {
      if (sectPr != null) {
        blocks.add(opaqueBlock(sectPr!));
        sectPr = null;
      }
      if (isW(r, 'sectPr')) {
        sectPr = OpaqueXml.capture(r);
      } else {
        _story.readBlock(reader);
      }
    });
    final OpaqueXml? last = sectPr;
    return last == null ? const PropertyContainer.empty() : _readSectPr(last);
  }

  /// Reads the `w:sectPr` [xml] captured as a container.
  PropertyContainer _readSectPr(OpaqueXml xml) => PropertyContainer.read(
    readerOfCaptured(xml, _story.maxDepth),
    sectionPropertiesSchema,
  );
}
