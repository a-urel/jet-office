/// The edit primitives of the body model, recorded in a document's
/// `ChangeLog`.
///
/// Not ported from Quds; written for jet_office. It follows the workbook
/// model's primitives (`lib/src/xlsx/model/primitives.dart`): a primitive
/// applies its edit, then records a [Change] that reverts and reapplies it,
/// and every public edit runs in a [ChangeLog.transaction], so an edit that
/// fails is rolled back.
///
/// Block edits are primitives here: [insertBlock], [removeBlock] and
/// [replaceBlock] check the index and that a block to put in is in no
/// container, apply, and record. A block in a container knows it
/// (`blockContainerOf`); a paragraph put in one reports its edits to the
/// document's [DocxEdits], and one taken out reports to
/// [DocxEditSink.none].
///
/// Paragraph and run edits are made by the model's own members, which
/// apply the edit and then report it to the paragraph's sink. [DocxEdits]
/// is that sink: it records each report, in a transaction of its own unless
/// one is open. To undo, it replays the opposite edit through the same
/// public members (or `replaceInlineAt` and `restoreRunText`) while it
/// ignores the reports they make, so nothing is recorded twice.
///
/// @docImport 'edit_sink.dart';
library;

import '../../opc/change_log.dart';
import 'blocks.dart';
import 'edit_sink.dart';
import 'inlines.dart';

/// The edits of one document: its [ChangeLog], and the sink its body's
/// paragraphs report to.
final class DocxEdits implements DocxEditSink {
  /// The log every edit of the document is recorded in.
  final ChangeLog log = ChangeLog();

  /// A test hook, called after each change is recorded, inside its
  /// transaction. A hook that throws makes the edit fail after it was
  /// applied and recorded, so a test can watch the transaction roll it
  /// back. `null` in normal use.
  void Function()? afterRecord;

  /// True while a change is reverted or reapplied: the reports the model
  /// makes then are the replay, not new edits.
  bool _replaying = false;

  /// Runs [body] as one transaction of [log]: if it throws, every change it
  /// recorded is reverted and the error is rethrown.
  ChangeSet transaction(void Function() body) => log.transaction(body);

  /// Records [change], which its primitive has applied, then calls
  /// [afterRecord]. Throws [StateError] outside a transaction.
  void record(Change change) {
    log.record(change);
    afterRecord?.call();
  }

  /// Runs [body], ignoring the reports the model makes meanwhile.
  void _replay(void Function() body) {
    final bool was = _replaying;
    _replaying = true;
    try {
      body();
    } finally {
      _replaying = was;
    }
  }

  /// Records [change], which the model applied, in a transaction of its own
  /// (folded into the open one, if any); a replay is not recorded.
  void _reported(Change change) {
    if (_replaying) return;
    transaction(() => record(change));
  }

  @override
  void inlineInserted(DocxParagraph paragraph, int index, DocxInline inline) =>
      _reported(_InlineInserted(this, paragraph, index, inline));

  @override
  void inlineRemoved(DocxParagraph paragraph, int index, DocxInline inline) =>
      _reported(_InlineRemoved(this, paragraph, index, inline));

  @override
  void inlineReplaced(
    DocxParagraph paragraph,
    int index,
    DocxInline previous,
    DocxInline replacement,
  ) =>
      _reported(_InlineReplaced(this, paragraph, index, previous, replacement));

  @override
  void runTextSet(DocxRun run, DocxRunText previous) =>
      _reported(_RunTextSet(run, previous, runTextOf(run)));

  @override
  void paragraphStyleSet(DocxParagraph paragraph, String? previous) =>
      _reported(_ParagraphStyleSet(this, paragraph, previous, paragraph.style));

  @override
  void runStyleSet(DocxRun run, String? previous) =>
      _reported(_RunStyleSet(this, run, previous, run.style));
}

/// Inserts [block] at [index] of [blocks], the blocks of [container], and
/// records the change in [edits].
///
/// An [index] outside 0 to the number of blocks throws [RangeError], and a
/// [block] already in a container (this one or another) throws
/// [StateError]; both before anything changes. Must run inside
/// `edits.transaction`. If recording throws, the block is taken out again
/// before the error leaves.
void insertBlock(
  DocxEdits edits,
  Object container,
  List<DocxBlock> blocks,
  int index,
  DocxBlock block,
) {
  RangeError.checkValueInInterval(index, 0, blocks.length, 'index');
  _checkDetached(block);
  _apply(edits, _BlockInserted(edits, container, blocks, index, block));
}

/// Removes the block at [index] of [blocks], the blocks of [container], and
/// records the change in [edits]. The block is then in no container.
///
/// An [index] that is not one of a block throws [RangeError]. Must run
/// inside `edits.transaction`.
void removeBlock(
  DocxEdits edits,
  Object container,
  List<DocxBlock> blocks,
  int index,
) {
  RangeError.checkValidIndex(index, blocks, 'index');
  _apply(edits, _BlockRemoved(edits, container, blocks, index, blocks[index]));
}

/// Puts [block] in place of the block at [index] of [blocks], the blocks of
/// [container], and records the change in [edits]. The block replaced is
/// then in no container.
///
/// An [index] that is not one of a block throws [RangeError], and a [block]
/// already in a container throws [StateError]; both before anything
/// changes. Must run inside `edits.transaction`.
void replaceBlock(
  DocxEdits edits,
  Object container,
  List<DocxBlock> blocks,
  int index,
  DocxBlock block,
) {
  RangeError.checkValidIndex(index, blocks, 'index');
  _checkDetached(block);
  _apply(
    edits,
    _BlockReplaced(edits, container, blocks, index, blocks[index], block),
  );
}

/// Puts every block of [blocks] in [container] and makes its paragraphs
/// report to [edits]: how a container read from a file is adopted.
///
/// Throws [StateError] for a block already in a container, before anything
/// changes.
void adoptBlocks(DocxEdits edits, Object container, List<DocxBlock> blocks) {
  blocks.forEach(_checkDetached);
  for (final DocxBlock block in blocks) {
    _attach(edits, container, block);
  }
}

void _checkDetached(DocxBlock block) {
  if (blockContainerOf(block) != null) {
    throw StateError('The block is already in a body; remove it there first.');
  }
}

/// Applies [change] and records it; if recording throws, reverts it first.
void _apply(DocxEdits edits, Change change) {
  change.reapply();
  try {
    edits.log.record(change);
  } catch (_) {
    change.revert();
    rethrow;
  }
  edits.afterRecord?.call();
}

/// Puts [block] in [container]: a paragraph reports to [edits] from now on.
void _attach(DocxEdits edits, Object container, DocxBlock block) {
  setBlockContainerOf(block, container);
  if (block is DocxParagraph) attachEditSink(block, edits);
}

/// Takes [block] out of its container: a paragraph reports to nothing.
void _detach(DocxBlock block) {
  setBlockContainerOf(block, null);
  if (block is DocxParagraph) attachEditSink(block, DocxEditSink.none);
}

/// A block inserted into a container's blocks.
final class _BlockInserted implements Change {
  _BlockInserted(
    this._edits,
    this._container,
    this._blocks,
    this._index,
    this._block,
  );

  final DocxEdits _edits;
  final Object _container;
  final List<DocxBlock> _blocks;
  final int _index;
  final DocxBlock _block;

  @override
  void revert() {
    _blocks.removeAt(_index);
    _detach(_block);
  }

  @override
  void reapply() {
    _blocks.insert(_index, _block);
    _attach(_edits, _container, _block);
  }
}

/// A block removed from a container's blocks.
final class _BlockRemoved implements Change {
  _BlockRemoved(
    this._edits,
    this._container,
    this._blocks,
    this._index,
    this._block,
  );

  final DocxEdits _edits;
  final Object _container;
  final List<DocxBlock> _blocks;
  final int _index;
  final DocxBlock _block;

  @override
  void revert() {
    _blocks.insert(_index, _block);
    _attach(_edits, _container, _block);
  }

  @override
  void reapply() {
    _blocks.removeAt(_index);
    _detach(_block);
  }
}

/// A block of a container replaced by another.
final class _BlockReplaced implements Change {
  _BlockReplaced(
    this._edits,
    this._container,
    this._blocks,
    this._index,
    this._previous,
    this._replacement,
  );

  final DocxEdits _edits;
  final Object _container;
  final List<DocxBlock> _blocks;
  final int _index;
  final DocxBlock _previous;
  final DocxBlock _replacement;

  @override
  void revert() => _put(_replacement, _previous);

  @override
  void reapply() => _put(_previous, _replacement);

  void _put(DocxBlock out, DocxBlock into) {
    _blocks[_index] = into;
    _detach(out);
    _attach(_edits, _container, into);
  }
}

/// An inline inserted into a paragraph.
final class _InlineInserted implements Change {
  _InlineInserted(this._edits, this._paragraph, this._index, this._inline);

  final DocxEdits _edits;
  final DocxParagraph _paragraph;
  final int _index;
  final DocxInline _inline;

  @override
  void revert() => _edits._replay(() => _paragraph.removeInlineAt(_index));

  @override
  void reapply() =>
      _edits._replay(() => _paragraph.insertInline(_index, _inline));
}

/// An inline removed from a paragraph.
final class _InlineRemoved implements Change {
  _InlineRemoved(this._edits, this._paragraph, this._index, this._inline);

  final DocxEdits _edits;
  final DocxParagraph _paragraph;
  final int _index;
  final DocxInline _inline;

  @override
  void revert() =>
      _edits._replay(() => _paragraph.insertInline(_index, _inline));

  @override
  void reapply() => _edits._replay(() => _paragraph.removeInlineAt(_index));
}

/// An inline of a paragraph replaced by another.
final class _InlineReplaced implements Change {
  _InlineReplaced(
    this._edits,
    this._paragraph,
    this._index,
    this._previous,
    this._replacement,
  );

  final DocxEdits _edits;
  final DocxParagraph _paragraph;
  final int _index;
  final DocxInline _previous;
  final DocxInline _replacement;

  @override
  void revert() =>
      _edits._replay(() => replaceInlineAt(_paragraph, _index, _previous));

  @override
  void reapply() =>
      _edits._replay(() => replaceInlineAt(_paragraph, _index, _replacement));
}

/// A run's text set: its content and removed count before and after.
final class _RunTextSet implements Change {
  _RunTextSet(this._run, this._previous, this._next);

  final DocxRun _run;
  final DocxRunText _previous;
  final DocxRunText _next;

  @override
  void revert() => restoreRunText(_run, _previous);

  @override
  void reapply() => restoreRunText(_run, _next);
}

/// A paragraph's style set.
final class _ParagraphStyleSet implements Change {
  _ParagraphStyleSet(this._edits, this._paragraph, this._previous, this._next);

  final DocxEdits _edits;
  final DocxParagraph _paragraph;
  final String? _previous;
  final String? _next;

  @override
  void revert() => _edits._replay(() => _paragraph.style = _previous);

  @override
  void reapply() => _edits._replay(() => _paragraph.style = _next);
}

/// A run's style set.
final class _RunStyleSet implements Change {
  _RunStyleSet(this._edits, this._run, this._previous, this._next);

  final DocxEdits _edits;
  final DocxRun _run;
  final String? _previous;
  final String? _next;

  @override
  void revert() => _edits._replay(() => _run.style = _previous);

  @override
  void reapply() => _edits._replay(() => _run.style = _next);
}
