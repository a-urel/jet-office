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
/// container, then apply through a [DocxEditSink]: the document's [DocxEdits]
/// records the change in a transaction of its own unless one is open, and
/// [DocxEditSink.none] only applies it, so a cell in no document edits the same
/// way. [insertChild] and [removeChild] do the same for the rows of a table
/// and the cells of a row. One change, [_ListEdit], undoes them all.
///
/// A block, a row or a cell knows what holds it (`parentOf`); put in a
/// container of a document, it and everything it holds report their edits to
/// the document's [DocxEdits], and taken out they report to
/// [DocxEditSink.none].
///
/// Paragraph and run edits are made by the model's own members, which
/// apply the edit and then report it to the paragraph's sink. [DocxEdits]
/// is that sink: it records each report, in a transaction of its own unless
/// one is open. To undo, it replays the opposite edit through the same
/// public members (or `replaceInlineAt` and `restoreRunText`) while it
/// ignores the reports they make, so nothing is recorded twice. A property
/// set (a style) is undone with `PropertySet.restore`, which reports
/// nothing.
///
/// The styles part records its own edits the same way: a style added is a
/// change applied with [applyChange], and a style's property sets report to
/// the same [DocxEdits], so they are recorded and reverted like a
/// paragraph's.
///
/// A style id set through the API is resolved against the document's styles
/// ([DocxEdits.resolveStyleId]) as it is set, or as the content that holds
/// it goes in ([insertBlock], [replaceBlock], [insertChild]), however deep in
/// a table it is, so the styles it adds are changes of the same transaction. A
/// replay resolves nothing.
///
/// @docImport 'edit_sink.dart';
library;

import '../../opc/change_log.dart';
import '../builtin_styles.dart' show DocxBuiltInStyle;
import '../docx_document.dart' show DocxHeaderFooter, DocxHeaderFooterType;
import 'blocks.dart';
import 'edit_sink.dart';
import 'inlines.dart';
import 'property_set.dart';
import 'sections.dart';
import 'styles.dart' show DocxStyleType;

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

  /// What resolves a style id set through the API, which the document
  /// provides (it loads the styles); `null` keeps every id as given.
  String Function(String id, DocxStyleType type)? styleResolver;

  /// What gives the id of a built-in style, adding it when the document lacks
  /// it, which the document provides; `null` adds none.
  String Function(DocxBuiltInStyle style)? styleEnsurer;

  /// What gives the header or footer a section reads, which the document
  /// provides.
  DocxHeaderFooter Function(
    DocxSection section,
    DocxHeaderFooterType type, {
    required bool isHeader,
  })?
  headerFooterResolver;

  /// What gives a section a story of its own, which the document provides.
  DocxHeaderFooter Function(
    DocxSection section,
    DocxHeaderFooterType type, {
    required bool isHeader,
  })?
  headerFooterOwner;

  /// What drops a section's references, which the document provides.
  void Function(
    DocxSection section,
    DocxHeaderFooterType type, {
    required bool isHeader,
  })?
  headerFooterRemover;

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
  void propertySet(
    PropertySet properties,
    String localName,
    PropertyState previous,
  ) => _reported(
    _PropertySet(
      properties,
      localName,
      previous,
      properties.stateOf(localName),
    ),
  );

  @override
  void apply(Change change) {
    if (_replaying) {
      change.reapply();
    } else {
      transaction(() => applyChange(this, change));
    }
  }

  @override
  void atomically(void Function() body) {
    if (_replaying) {
      body();
    } else {
      transaction(body);
    }
  }

  @override
  String resolveStyleId(String id, DocxStyleType type) {
    final String Function(String, DocxStyleType)? resolver = styleResolver;
    return _replaying || resolver == null ? id : resolver(id, type);
  }

  @override
  String? ensureStyle(DocxBuiltInStyle style) => styleEnsurer?.call(style);

  @override
  DocxHeaderFooter? headerFooterOf(
    DocxSection section,
    DocxHeaderFooterType type, {
    required bool isHeader,
  }) => headerFooterResolver?.call(section, type, isHeader: isHeader);

  @override
  DocxHeaderFooter? ownHeaderFooter(
    DocxSection section,
    DocxHeaderFooterType type, {
    required bool isHeader,
  }) => headerFooterOwner?.call(section, type, isHeader: isHeader);

  @override
  void removeHeaderFooter(
    DocxSection section,
    DocxHeaderFooterType type, {
    required bool isHeader,
  }) => headerFooterRemover?.call(section, type, isHeader: isHeader);

  @override
  bool isForeign(DocxEditSink? readIn) =>
      !_replaying && readIn != null && !identical(readIn, this);
}

/// Inserts [block] at [index] of [blocks], the blocks of [container], through
/// [sink], as one edit.
///
/// An [index] outside 0 to the number of blocks throws [RangeError], a [block]
/// already in a container (this one or another) throws [StateError], and a
/// table that does not fit ([checkFitsIn]) throws [ArgumentError]; all before
/// anything changes. The styles set on the block and on everything in it are
/// resolved against the document's ([resolveStylesIn]), which throws a
/// `DocxReadException` when the styles part cannot be read; the block is then
/// taken out again.
void insertBlock(
  DocxEditSink sink,
  Object container,
  List<DocxBlock> blocks,
  int index,
  DocxBlock block,
) {
  RangeError.checkValueInInterval(index, 0, blocks.length, 'index');
  _checkBlock(block, container);
  sink.atomically(() {
    sink.apply(
      _ListEdit<DocxBlock>(sink, container, blocks, index, null, block),
    );
    resolveStylesIn(block);
  });
}

/// Removes the block at [index] of [blocks], the blocks of [container],
/// through [sink]. The block is then in no container.
///
/// An [index] that is not one of a block throws [RangeError].
void removeBlock(
  DocxEditSink sink,
  Object container,
  List<DocxBlock> blocks,
  int index,
) {
  RangeError.checkValidIndex(index, blocks, 'index');
  sink.apply(
    _ListEdit<DocxBlock>(sink, container, blocks, index, blocks[index], null),
  );
}

/// Puts [block] in place of the block at [index] of [blocks], the blocks of
/// [container], through [sink], as one edit. The block replaced is then in no
/// container.
///
/// An [index] that is not one of a block throws [RangeError]; the rest is as
/// for [insertBlock], and a failure puts the block replaced back.
void replaceBlock(
  DocxEditSink sink,
  Object container,
  List<DocxBlock> blocks,
  int index,
  DocxBlock block,
) {
  RangeError.checkValidIndex(index, blocks, 'index');
  _checkBlock(block, container);
  sink.atomically(() {
    sink.apply(
      _ListEdit<DocxBlock>(
        sink,
        container,
        blocks,
        index,
        blocks[index],
        block,
      ),
    );
    resolveStylesIn(block);
  });
}

/// Inserts [item], a row or a cell, at [index] of [items], the typed items of
/// [children], the children of [parent], through [sink].
///
/// It goes directly before the item at [index], and after the last child for
/// the last index; that position is found once per edit.
///
/// An [index] outside 0 to the number of items throws [RangeError], an [item]
/// already in a parent throws [StateError], and one that does not fit
/// ([checkFitsIn]) throws [ArgumentError]; all before anything changes. The
/// styles set on what [item] holds are resolved as [insertBlock] says, and a
/// failure takes it out again.
void insertChild<T extends Object>(
  DocxEditSink sink,
  Object parent,
  List<Object> children,
  List<T> items,
  int index,
  T item,
) {
  RangeError.checkValueInInterval(index, 0, items.length, 'index');
  if (parentOf(item) != null) {
    throw StateError(
      'The row or cell is already in a table or a row; remove it there first.',
    );
  }
  checkFitsIn(item, parent);
  final int position = index == items.length
      ? children.length
      : children.indexOf(items[index]);
  sink.atomically(() {
    sink.apply(
      _ListEdit<T>(sink, parent, items, index, null, item, children, position),
    );
    resolveStylesIn(item);
  });
}

/// Removes the item at [index] of [items], the typed items of [children], the
/// children of [parent], through [sink]. The item is then in no parent.
///
/// An [index] that is not one of an item throws [RangeError], and the only
/// item throws [StateError]: a table keeps a row and a row a cell.
void removeChild<T extends Object>(
  DocxEditSink sink,
  Object parent,
  List<Object> children,
  List<T> items,
  int index,
) {
  RangeError.checkValidIndex(index, items, 'index');
  if (items.length == 1) {
    throw StateError(
      'The last row or cell cannot be removed; remove what holds it.',
    );
  }
  final T item = items[index];
  sink.apply(
    _ListEdit<T>(
      sink,
      parent,
      items,
      index,
      item,
      null,
      children,
      children.indexOf(item),
    ),
  );
}

/// Puts every block of [blocks] in [container], makes its paragraphs and those
/// in its cells report to [edits] and records that they and their runs were
/// read there: how a container read from a file is adopted.
///
/// Throws [StateError] for a block already in a container, before anything
/// changes.
void adoptBlocks(DocxEdits edits, Object container, List<DocxBlock> blocks) {
  blocks.forEach(_checkDetached);
  for (final DocxBlock block in blocks) {
    _attach(edits, container, block);
    markBlockReadIn(block, edits);
  }
}

void _checkDetached(DocxBlock block) {
  if (blockContainerOf(block) != null) {
    throw StateError(
      'The block is already in a body or a cell; remove it there first.',
    );
  }
}

/// Throws what [block] throws going in [container]: a paragraph fits anywhere,
/// at no cost.
void _checkBlock(DocxBlock block, Object container) {
  _checkDetached(block);
  if (block is DocxTable) {
    checkFitsIn(block, container);
  }
}

/// Applies [change] and records it in [edits]; if recording throws, reverts
/// it first. Must run inside `edits.transaction`.
///
/// It is how a primitive of another library records its edit, such as a
/// style added to the styles part (`model/styles.dart`).
void applyChange(DocxEdits edits, Change change) {
  change.reapply();
  try {
    edits.log.record(change);
  } catch (_) {
    change.revert();
    rethrow;
  }
  edits.afterRecord?.call();
}

/// Puts [item] (a block, a row or a cell) in [parent]: it and everything it
/// holds report to [sink] from now on.
void _attach(DocxEditSink sink, Object parent, Object item) {
  setParentOf(item, parent);
  attachSink(item, sink);
}

/// Takes [item] out of what holds it: it and everything it holds report to
/// nothing.
void _detach(Object item) {
  setParentOf(item, null);
  attachSink(item, DocxEditSink.none);
}

/// The one change of a list a container holds: an item inserted (no [_out]),
/// removed (no [_into]) or replaced, at [_index] of [_items].
///
/// A block is in one list. A row or a cell is in two: the typed [_items] and
/// [_children], where it is at [_position].
final class _ListEdit<T extends Object> implements Change {
  _ListEdit(
    this._sink,
    this._parent,
    this._items,
    this._index,
    this._out,
    this._into, [
    this._children,
    this._position = 0,
  ]);

  final DocxEditSink _sink;
  final Object _parent;
  final List<T> _items;
  final int _index;
  final T? _out;
  final T? _into;
  final List<Object>? _children;
  final int _position;

  @override
  void revert() => _put(_into, _out);

  @override
  void reapply() => _put(_out, _into);

  /// Takes [out] from the lists and puts [into] in its place.
  void _put(T? out, T? into) {
    if (out == null) {
      _items.insert(_index, into!);
      _children?.insert(_position, into);
    } else if (into == null) {
      _items.removeAt(_index);
      _children?.removeAt(_position);
    } else {
      // Only a block is replaced, and a block is in one list.
      _items[_index] = into;
    }
    if (out != null) _detach(out);
    if (into != null) _attach(_sink, _parent, into);
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

/// A typed property of a paragraph, a run or a style set: its state before
/// and after. Undoing and redoing restore the state silently, so it works on
/// properties no longer in the document as well.
final class _PropertySet implements Change {
  _PropertySet(this._properties, this._localName, this._previous, this._next);

  final PropertySet _properties;
  final String _localName;
  final PropertyState _previous;
  final PropertyState _next;

  @override
  void revert() => _properties.restore(_localName, _previous);

  @override
  void reapply() => _properties.restore(_localName, _next);
}
