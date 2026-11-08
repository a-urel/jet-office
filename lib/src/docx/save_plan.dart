/// What one save adds to the package for what the model built: the
/// relationships of built hyperlinks, by the part they are in (plan D5,
/// Rulings 9, 12 and A).
///
/// Not ported from Quds; written for jet_office.
///
/// A built object holds no relationship in the model. Before the package is
/// written, the save walks every part it writes from the model ([SavePlan.planPart]):
/// the blocks of the body, of each header and footer, and of their table
/// cells and nested tables, the inlines of each paragraph with those of its
/// fields and hyperlinks. Each built hyperlink to an address gets a
/// relationship of the part it is in now, from [SaveIds.addRelationship], so
/// the relationships part, which the package writes before the part, holds
/// it, and the part's writer reads its id through [SavePlan.relationshipIdsOf].
/// [SaveIds.restoreRelationships] takes every one back once the package is
/// written: the next save adds them again, with the same ids.
///
/// [SavePlan.relate] is the one way to add a relationship for a built object: one per
/// part and key, so a key that stands for something shared (an image's media
/// part, for pictures) gives one relationship however many objects use it,
/// while a hyperlink, its own key, gets one of its own, as Word writes two
/// links to one address.
library;

import '../opc/ooxml.dart' show RelType;
import 'docx_package.dart';
import 'model/blocks.dart';
import 'model/inlines.dart';
import 'read_exception.dart' show DocxReadException;
import 'related_part.dart' show relationshipsPartOf;
import 'save_ids.dart';

/// The relationships one save gives what the model built.
final class SavePlan {
  /// A plan for a save of `_package`, whose ids are `_ids`.
  SavePlan(this._package, this._ids);

  final DocxPackage _package;
  final SaveIds _ids;

  /// The relationships added, by part name and then key.
  final Map<String, Map<Object, String>> _relationships =
      <String, Map<Object, String>>{};

  /// Relates what the API built in [blocks], the story of [part] (a part
  /// name), from that part: a relationship for each built hyperlink to an
  /// address. Throws a [DocxReadException] naming the part's relationships
  /// part when it cannot be read.
  void planPart(String part, List<DocxBlock> blocks) {
    visitStoryInlines(blocks, (DocxInline inline) {
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
