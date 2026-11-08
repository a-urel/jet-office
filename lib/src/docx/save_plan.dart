/// What one save adds to the package for what the model built: the
/// relationships of built hyperlinks and pictures, by the part they are in,
/// and the media parts of built pictures (plan D5, Rulings 7, 9, 12 and A).
///
/// Not ported from Quds; written for jet_office.
///
/// A built object holds no relationship in the model. Before the package is
/// written, the save walks every part it writes from the model
/// ([SavePlan.planPart]): the blocks of the body, of each header and footer,
/// and of their table cells and nested tables, the inlines of each paragraph
/// with those of its fields and hyperlinks. Each built hyperlink to an
/// address gets a relationship of the part it is in now, from
/// [SaveIds.addRelationship], so the relationships part, which the package
/// writes before the part, holds it, and the part's writer reads its id
/// through [SavePlan.relationshipIdsOf]. [SaveIds.restoreRelationships]
/// takes every one back once the package is written: the next save adds them
/// again, with the same ids.
///
/// [SavePlan.relate] is the one way to add a relationship for a built
/// object: one per part and key, so a key that stands for something shared
/// (an image's media part, for pictures) gives one relationship however many
/// objects use it, while a hyperlink, its own key, gets one of its own, as
/// Word writes two links to one address.
///
/// A built picture's image goes in a media part: one of the package that
/// holds the same image ([DrawingMediaIndex.partFor]: the same bytes, then
/// equal ones), else a new `word/media/image<n>.png` or `.jpeg` with the
/// next free number and a default content type for its extension. A part of
/// the file already related from the picture's part as an image keeps that
/// relationship, and the picture uses it. What the plan adds to the package
/// is this save's alone: [SavePlan.restore] takes the new media parts and
/// content type defaults back after the package is written, as
/// [SaveIds.restoreRelationships] does the relationships, so the package and
/// the media index are as they were and the next save adds them again.
library;

import '../common/image.dart';
import '../drawingml/media.dart';
import '../opc/ooxml.dart' show RelType;
import '../opc/package.dart'
    show OpcFormatException, OpcPackage, OpcRelationship;
import 'docx_package.dart';
import 'model/blocks.dart';
import 'model/inlines.dart';
import 'model/run_content.dart';
import 'read_exception.dart' show DocxReadException;
import 'related_part.dart' show relationshipTargetFrom, relationshipsPartOf;
import 'save_ids.dart';

/// The relationships one save gives what the model built.
final class SavePlan {
  /// A plan for a save of `_package`, whose ids are `_ids` and whose media
  /// parts `_media` knows.
  SavePlan(this._package, this._ids, this._media);

  final DocxPackage _package;
  final SaveIds _ids;
  final DrawingMediaIndex _media;

  /// The media parts this save added, each with the extension of the
  /// content type default it declared (`null` when the extension had one),
  /// in the order added.
  final List<({String part, String? extension})> _added =
      <({String part, String? extension})>[];

  /// The relationships added, by part name and then key.
  final Map<String, Map<Object, String>> _relationships =
      <String, Map<Object, String>>{};

  /// Relates what the API built in [blocks], the story of [part] (a part
  /// name), from that part: a relationship for each built hyperlink to an
  /// address, and for each media part of a built picture, which is added to
  /// the package when none holds its image. Throws a [DocxReadException]
  /// naming the part's relationships part when it cannot be read, and one
  /// naming the main part when a media part of the package, which is read to
  /// find the image, cannot be.
  void planPart(String part, List<DocxBlock> blocks) {
    visitStoryInlines(blocks, (DocxInline inline) {
      if (inline is DocxRun) {
        for (final DocxRunContent content in inline.content) {
          if (content is DocxPicture) _planPicture(part, content);
        }
        return;
      }
      if (inline is! DocxHyperlink || !hyperlinkIsBuilt(inline)) return;
      final String? url = inline.url;
      if (url == null) return;
      relate(
        part,
        inline,
        type: RelType.hyperlink,
        target: url,
        external: true,
      );
    });
  }

  /// The id of the relationship of [part] for [key]: the one added for it in
  /// this save, else a new one of [type] to [target] (outside the package
  /// when [external]). Throws a [DocxReadException] naming the part's
  /// relationships part when it cannot be read.
  String relate(
    String part,
    Object key, {
    required String type,
    required String target,
    bool external = false,
  }) {
    final Map<Object, String> ids = _relationships.putIfAbsent(
      part,
      () => <Object, String>{},
    );
    return ids[key] ??= _package.guard(
      relationshipsPartOf(part),
      () => _ids.addRelationship(
        part,
        type: type,
        target: target,
        external: external,
      ),
    );
  }

  /// Gives the built [picture] of [part] its media part and the image
  /// relationship of [part] to it, under the picture for the writer.
  void _planPicture(String part, DocxPicture picture) {
    final OfficeImage? image = builtPictureImage(picture);
    if (image == null) return;
    final String media = _mediaPartFor(image);
    final Map<Object, String> ids = _relationships.putIfAbsent(
      part,
      () => <Object, String>{},
    );
    final String key = media.toLowerCase();
    ids[picture] = ids[key] ??=
        _fileImageRelationship(part, media) ??
        relate(
          part,
          key,
          type: RelType.image,
          target: relationshipTargetFrom(part, media),
        );
  }

  /// The id of a relationship of [part] in the file that relates it to the
  /// image part [media], internal and of the image type, which a reference
  /// by that id finds (the first relationship of that id); `null` for none.
  String? _fileImageRelationship(String part, String media) {
    final OpcPackage opc = _package.package;
    final List<OpcRelationship> relationships = _package.guard(
      relationshipsPartOf(part),
      () => opc.peekRelationships(part),
    );
    final String key = media.toLowerCase();
    final Set<String> seen = <String>{};
    for (final OpcRelationship rel in relationships) {
      if (!seen.add(rel.id) || rel.external || rel.type != RelType.image) {
        continue;
      }
      final String? target = opc.canonicalPartName(
        opc.resolve(part, rel.target),
      );
      if (target != null && target.toLowerCase() == key) return rel.id;
    }
    return null;
  }

  /// The absolute name of the media part that holds [image]: one of the
  /// package holding the same image, else one this save adds.
  String _mediaPartFor(OfficeImage image) {
    final OpcPackage opc = _package.package;
    final String? shared = _package.guard(
      _package.mainPart,
      () => _media.partFor(image),
    );
    if (shared != null) return opc.canonicalPartName(shared) ?? '/$shared';
    // The format was checked when the picture was built; bytes changed since
    // are written as a PNG's.
    final OfficeImageFormat format = image.format ?? OfficeImageFormat.png;
    final String extension = format.extension;
    final String folder = opc.isNewPartName('/word/media/_')
        ? '/word/media/'
        : '/';
    int n = _media.nextNumber();
    // A name a relationship targets, a dangling one, is not free: the
    // reference would come to show the new image (Ruling M).
    final Set<String> targets = _relationshipTargets();
    while (!opc.isNewPartName('${folder}image$n.$extension') ||
        targets.contains('${folder}image$n.$extension'.toLowerCase())) {
      n++;
    }
    final bool declared = opc.ensureDefault(extension, format.contentType);
    final String name = opc.addPart(
      '${folder}image$n.$extension',
      format.contentType,
      DrawingMediaContent(image.bytes),
      byExtension: true,
    );
    _media.add(name, image);
    _added.add((part: name, extension: declared ? extension : null));
    return name;
  }

  /// The lower-cased absolute names every internal relationship of the
  /// package targets, found once per save; relationships parts are peeked,
  /// never marked for rewriting, and one that cannot be read is passed over
  /// (it targets nothing that blocks a name): a broken part elsewhere must
  /// not keep a picture from the file.
  Set<String> _relationshipTargets() {
    final Set<String>? known = _targets;
    if (known != null) return known;
    final OpcPackage opc = _package.package;
    final Set<String> targets = <String>{};
    for (final String source in <String>['', ...opc.partNames]) {
      final List<OpcRelationship> relationships;
      try {
        relationships = opc.peekRelationships(source);
      } on OpcFormatException {
        continue;
      }
      for (final OpcRelationship rel in relationships) {
        if (rel.external) continue;
        final String target = opc.resolve(source, rel.target);
        targets.add(
          (target.startsWith('/') ? target : '/$target').toLowerCase(),
        );
      }
    }
    return _targets = targets;
  }

  Set<String>? _targets;

  /// Takes back what the plan added to the package, newest first: each
  /// media part, the content type default it declared, and its entry in the
  /// media index. The relationships to them are [SaveIds]'s to take back.
  void restore() {
    final OpcPackage opc = _package.package;
    for (final ({String part, String? extension}) added in _added.reversed) {
      opc.removePart(added.part, sources: const <String>[]);
      final String? extension = added.extension;
      if (extension != null) opc.removeDefault(extension);
      _media.forget(added.part);
    }
    _added.clear();
  }

  /// What the writer of [part] asks for the relationship of a built object:
  /// its id, or `null` when this save gave it none in that part.
  String? Function(Object built) relationshipIdsOf(String part) {
    final Map<Object, String> ids = _relationships.putIfAbsent(
      part,
      () => <Object, String>{},
    );
    return (Object built) => ids[built];
  }
}

/// Calls [visit] with every inline of the paragraphs of [blocks], those in
/// table cells and nested tables among them, in document order: each inline
/// of a paragraph, and after a field or a hyperlink every inline it holds.
void visitStoryInlines(
  List<DocxBlock> blocks,
  void Function(DocxInline inline) visit,
) {
  void inline(DocxInline i) {
    visit(i);
    heldInlinesOf(i)?.forEach(inline);
  }

  for (final DocxBlock block in blocks) {
    visitBlocks(block, (DocxBlock b) {
      if (b is DocxParagraph) b.inlines.forEach(inline);
    });
  }
}
