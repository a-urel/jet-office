/// A header or footer part, `word/header1.xml` or `word/footer1.xml`, read
/// into blocks and written back from them.
///
/// Not ported from Quds; written for jet_office.
///
/// [StoryPart.read] walks the part once with the pull reader. The root must
/// be `w:hdr` for a header and `w:ftr` for a footer; its children are the
/// blocks of the story, read by [StoryReader] under the location of the part,
/// so a block is typed and kept as one of the body is.
///
/// [StoryPart.encode] writes the root as read, with every namespace
/// declaration and `mc:Ignorable`, then the blocks ([StoryWriter]). What it
/// writes for a part read and not edited means the same as the part, without
/// the comments between the blocks, so a part the model did not change goes
/// out as the file's bytes (`RelatedPart.load`).
///
/// A story ends in a paragraph, as a cell does (plan Ruling 11): an empty `w:p`
/// follows blocks that do not, an empty story's too, unless they are all as
/// read ([needsClosingParagraph]).
///
/// [StoryPart.create] is a part for a new story, whose name the save gives it.
///
/// Locations in errors and warnings start with the part's name without the
/// leading slash: `word/header1.xml/p[0]/r[1]`.
library;

import 'dart:typed_data';

import '../common/image.dart' show OfficeImage;
import '../opc/ooxml.dart' show Ns;
import '../opc/opaque_xml.dart';
import '../opc/package.dart' show PartContent;
import '../xml/utf8_buffer.dart';
import '../xml/xml_pull_reader.dart';
import '../xml/xml_writer.dart';
import 'model/blocks.dart';
import 'model/inlines.dart' show DocxBookmarkStart;
import 'model/styles.dart' show DocxStyleType;
import 'part_root.dart';
import 'read_exception.dart';
import 'read_limits.dart';
import 'story_reader.dart';
import 'story_writer.dart';
import 'warnings.dart';

/// A header or footer part: the root's start tag and the story's blocks.
final class StoryPart implements PartContent {
  StoryPart._(this.partName, this.root, this.blocks)
    : _readUnclosed = readUnclosedOf(blocks);

  /// A part with no blocks and no name yet: a `w:hdr` when [isHeader], else a
  /// `w:ftr`, that declares `w` and `r`. It writes one empty paragraph until
  /// blocks go in. Nothing was read, so [blocks] have no state as read.
  StoryPart.create({required bool isHeader})
    : partName = '',
      root = XmlRoot.of(isHeader ? 'w:hdr' : 'w:ftr', const <String, String>{
        'w': Ns.w,
        'r': Ns.rel,
      }),
      blocks = <DocxBlock>[],
      _readUnclosed = null;

  /// Reads the part from [r], which must not have been advanced, and
  /// consumes it to the end of the root element.
  ///
  /// [partName] is the part's absolute name, for errors; [isHeader] says
  /// which root it must have, and one it does not have throws a
  /// [DocxReadException] of [DocxReadFailure.malformedXml]. [limits] bounds
  /// every text, as `DocumentPart.read` says, with the part's location in
  /// place of `body`; [resolveUrl] and [resolveImage] are as `DocumentPart.read` has them.
  ///
  /// XML that is not well-formed, nested deeper than the reader allows or
  /// holds an entity that cannot be decoded throws [XmlParseException]: call
  /// this inside `DocxPackage.guard`, which turns it into a
  /// [DocxReadException].
  static StoryPart read(
    XmlPullReader r,
    String partName, {
    required bool isHeader,
    required DocxReadLimits limits,
    String? Function(String id)? resolveUrl,
    OfficeImage? Function(String id)? resolveImage,
  }) {
    while (r.next()) {
      if (r.eventType == XmlEventType.startElement) break;
    }
    final String rootName = isHeader ? 'hdr' : 'ftr';
    if (r.eventType != XmlEventType.startElement || !isW(r, rootName)) {
      throw DocxReadException(
        DocxReadFailure.malformedXml,
        'The ${isHeader ? 'header' : 'footer'} part has no w:$rootName root '
        'element.',
        part: partName,
      );
    }
    final XmlRoot root = XmlRoot.capture(r);
    final List<DocxBlock> blocks = <DocxBlock>[];
    final BlockReader into = BlockReader(_locationOf(partName), blocks);
    final StoryReader story = StoryReader(
      r,
      partName,
      limits.maxTextLength,
      limits.maxDepth,
      resolveUrl: resolveUrl,
      resolveImage: resolveImage,
    );
    eachChild(r, () => story.readBlock(into));
    return StoryPart._(partName, root, blocks);
  }

  /// [partName] without its leading slash.
  static String _locationOf(String partName) =>
      partName.startsWith('/') ? partName.substring(1) : partName;

  /// The part's absolute name, such as `/word/header1.xml`: the part of the
  /// warnings [encode] raises. The save sets it on a new part.
  String partName;

  /// The location of the blocks: [partName] without its leading slash.
  String get _location => _locationOf(partName);

  /// The root element's start tag: its name, namespace declarations and
  /// attributes, so the part is written back with every binding its kept
  /// content uses.
  final XmlRoot root;

  /// The story's blocks in order.
  final List<DocxBlock> blocks;

  /// The blocks read, when they did not end in a paragraph
  /// ([readUnclosedOf]).
  final List<DocxBlock>? _readUnclosed;

  DocxWarningCollector _encodeWarnings = DocxWarningCollector();

  /// Whether the document defines the list instance a numId names, as
  /// `DocumentPart.listDefined` says. The save sets it before it writes the
  /// part.
  bool Function(int numId)? listDefined;

  /// Whether the document defines a style of that id and type, as
  /// `DocumentPart.styleDefined` says. The save sets it before it writes the
  /// part.
  bool Function(String id, DocxStyleType type)? styleDefined;

  /// The id this save gives the bookmark a built start begins, the same for
  /// its end wherever it is written; `null` outside a save. The save sets it
  /// before it writes the part.
  int Function(DocxBookmarkStart start)? bookmarkId;

  /// The id of the relationship this save gave the part for what the API
  /// built in it, such as a hyperlink to an address; `null` outside a save.
  /// The save sets it before it writes the part.
  String? Function(Object built)? relationshipId;

  /// The warnings the last [encode] raised, as
  /// `DocumentPart.encodeWarnings` says, at locations under the part's name,
  /// such as `word/header1.xml/p[0]/r[1]`.
  DocxWarningCollector get encodeWarnings => _encodeWarnings;

  /// Throws [StateError] naming the first table the API left without rows,
  /// at its location; a table read with no rows is kept.
  void checkBuiltTables() => checkTablesHaveRows(blocks, _location);

  /// Writes the part, and replaces [encodeWarnings] with the warnings of
  /// this write.
  @override
  List<Uint8List> encode() {
    final DocxWarningCollector warnings = DocxWarningCollector();
    final Utf8Buffer buffer = Utf8Buffer();
    final XmlWriter w = XmlWriter(buffer)..declaration();
    final (:String prefix, :Map<String, String> scope) = openWordRoot(w, root);
    StoryWriter(
      w,
      '$prefix:',
      prefix,
      scope,
      partName,
      warnings,
      listDefined,
      styleDefined,
      bookmarkId: bookmarkId,
      relationshipId: relationshipId,
    ).writeBlocks(blocks, _location);
    if (needsClosingParagraph(blocks, _readUnclosed)) {
      w
        ..start('$prefix:p')
        ..end();
    }
    w.end();
    _encodeWarnings = warnings;
    return buffer.takeChunks();
  }
}
