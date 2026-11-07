/// The hook through which the body model reports its edits.
///
/// Not ported from Quds; written for jet_office.
///
/// Every mutating member of [DocxParagraph] and [DocxRun] applies its edit
/// and then calls the [DocxEditSink] of the paragraph it is in, with what it
/// needs to undo the edit. A paragraph that belongs to no document has
/// [DocxEditSink.none], which ignores every call. A document attaches its own
/// sink (`attachEditSink`) to record each call as a change; to undo one, it
/// uses the silent helpers of the model (`replaceInlineAt` and the public
/// members while it ignores its own calls, `restoreRunText` for a run's
/// text), so the public signatures never change.
///
/// A property set ([PropertySet], such as a paragraph's style) reports its
/// own edits, with the state from before; it undoes one with
/// `PropertySet.restore`, which reports nothing.
///
/// An edit that changes nothing (a style set to the value it has) is not
/// reported.
///
/// A style id set through the API asks the sink which id to store
/// ([DocxEditSink.resolveStyleId]): the document's own for a built-in style
/// under a localized id (plan Ruling 5). A paragraph that belongs to no
/// document stores what it was given, and is asked again when it goes in.
///
/// What was read from a file stays as it is in that document, but counts as
/// set once it goes in another ([DocxEditSink.isForeign]), since the ids it
/// names were the other document's.
///
/// @docImport 'blocks.dart';
library;

import '../../opc/change_log.dart';
import '../builtin_styles.dart' show DocxBuiltInStyle;
import '../docx_document.dart' show DocxHeaderFooter, DocxHeaderFooterType;
import 'blocks.dart';
import 'inlines.dart';
import 'property_set.dart';
import 'sections.dart';
import 'styles.dart' show DocxStyleType;

/// Receives each edit of the body model after it was applied.
abstract interface class DocxEditSink {
  /// The sink of a paragraph that belongs to no document: it ignores every
  /// call.
  static const DocxEditSink none = _NoEdits();

  /// [inline] was inserted into [paragraph] at [index].
  void inlineInserted(DocxParagraph paragraph, int index, DocxInline inline);

  /// [inline] was removed from [paragraph]; it was at [index].
  void inlineRemoved(DocxParagraph paragraph, int index, DocxInline inline);

  /// [replacement] took the place of [previous] at [index] of [paragraph].
  void inlineReplaced(
    DocxParagraph paragraph,
    int index,
    DocxInline previous,
    DocxInline replacement,
  );

  /// The text of [run] was set; [previous] is its content and removed count
  /// from before, for `restoreRunText`.
  void runTextSet(DocxRun run, DocxRunText previous);

  /// The typed child [localName] of [properties] was set; [previous] is
  /// its state from before, for `PropertySet.restore`.
  void propertySet(
    PropertySet properties,
    String localName,
    PropertyState previous,
  );

  /// Applies [change] and records it: how an edit that is none of the above
  /// (the grid of a table, a block, a row or a cell put in or taken out) is
  /// made undoable. In a replay, and for the sink of no document, it only
  /// applies [change] ([Change.reapply]).
  void apply(Change change);

  /// Runs [body] as one edit: if it throws, everything it reported is
  /// undone before the error leaves.
  void atomically(void Function() body);

  /// The id to store for the style [id] of [type], set through the API
  /// (plan Ruling 5): [id] itself when the document defines it or no
  /// built-in style has it, otherwise the id of that built-in in the
  /// document, added if it lacks it. Call it inside [atomically].
  String resolveStyleId(String id, DocxStyleType type);

  /// The id of the built-in [style] in the document, added if it lacks it
  /// (`DocxStyles.ensure`); `null` for the sink of no document, which has no
  /// styles. Call it inside [atomically].
  String? ensureStyle(DocxBuiltInStyle style);

  /// The header (when [isHeader]) or footer of [type] that [section] of the
  /// document reads; `null` for the sink of no document.
  DocxHeaderFooter? headerFooterOf(
    DocxSection section,
    DocxHeaderFooterType type, {
    required bool isHeader,
  });

  /// Whether content read in the document of [readIn] (`null`: not read
  /// from a file) now belongs to another document, this one: never in a
  /// replay, nor for the sink of no document.
  bool isForeign(DocxEditSink? readIn);
}

/// The sink that ignores every call.
final class _NoEdits implements DocxEditSink {
  const _NoEdits();

  @override
  void inlineInserted(DocxParagraph paragraph, int index, DocxInline inline) {}

  @override
  void inlineRemoved(DocxParagraph paragraph, int index, DocxInline inline) {}

  @override
  void inlineReplaced(
    DocxParagraph paragraph,
    int index,
    DocxInline previous,
    DocxInline replacement,
  ) {}

  @override
  void runTextSet(DocxRun run, DocxRunText previous) {}

  @override
  void propertySet(
    PropertySet properties,
    String localName,
    PropertyState previous,
  ) {}

  @override
  void apply(Change change) => change.reapply();

  @override
  void atomically(void Function() body) => body();

  @override
  String resolveStyleId(String id, DocxStyleType type) => id;

  @override
  String? ensureStyle(DocxBuiltInStyle style) => null;

  @override
  DocxHeaderFooter? headerFooterOf(
    DocxSection section,
    DocxHeaderFooterType type, {
    required bool isHeader,
  }) => null;

  @override
  bool isForeign(DocxEditSink? readIn) => false;
}
