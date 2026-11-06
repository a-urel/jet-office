/// The blocks of a body or a table cell: paragraphs, tables, and opaque blocks
/// for everything else.
///
/// Not ported from Quds; written for jet_office.
///
/// A [DocxParagraph] holds its inlines and its properties (`w:pPr`, a
/// [DocxParagraphProperties]). A [DocxTable] holds [DocxTableRow]s, a row
/// [DocxTableCell]s and a cell blocks again, so a table nests in a cell. A
/// [DocxOpaqueBlock] keeps an element the model does not type, such as a
/// content control, as written.
///
/// `w:tbl` and `w:tr` may hold other children between rows and cells (`w:sdt`,
/// `w:customXml`, bookmarks, `w:tblPrEx`). A table and a row keep them in a
/// private list in file order, with the rows or cells and the properties, and
/// show only the typed rows and cells: rows inside a `w:sdt` are not in
/// [DocxTable.rows]. [visitBlocks] is the walk of the tree.
///
/// The top-level functions are the model's internal surface for the reader,
/// the writer and the document; none of them is exported.
library;

import 'dart:collection';

import '../../opc/opaque_xml.dart';
import '../properties.dart';
import 'edit_sink.dart';
import 'inlines.dart';
import 'paragraph_properties.dart';
import 'property_set.dart';
import 'styles.dart' show DocxStyleType;

/// One child of a body or of a table cell.
///
/// A block is in at most one container at a time: inserting one that is
/// already in a body throws [StateError]; remove it there first.
sealed class DocxBlock {
  DocxBlock._();

  /// The container the block is in, such as a document's body, or `null`
  /// while it is in none.
  Object? _container;
}

/// A paragraph, `w:p`.
final class DocxParagraph extends DocxBlock {
  /// An empty paragraph: no inlines, no style and no other properties.
  ///
  /// It belongs to no document until it is inserted into one.
  DocxParagraph()
    : _source = const PropertyContainer.empty(),
      _attributes = const <KeptAttribute>[],
      super._();

  /// A paragraph with one run that holds [text], or none when [text] is
  /// empty. The text is split and scrubbed as [DocxRun.text] is when set.
  DocxParagraph.text(String text)
    : _source = const PropertyContainer.empty(),
      _attributes = const <KeptAttribute>[],
      super._() {
    if (text.isNotEmpty) {
      addRun(text);
    }
  }

  DocxParagraph._read(this._source, this._attributes) : super._();

  /// The paragraph's `w:pPr` as read.
  final PropertyContainer _source;

  /// The paragraph's properties: [_source] with the values set.
  late final DocxParagraphProperties _properties = newParagraphProperties(
    _source,
    () => _sink,
  );

  /// The attributes of `w:p` the reader kept, such as `w14:paraId`.
  final List<KeptAttribute> _attributes;

  final List<DocxInline> _inlines = <DocxInline>[];

  late final List<DocxInline> _inlinesView = UnmodifiableListView<DocxInline>(
    _inlines,
  );

  DocxEditSink _sink = DocxEditSink.none;

  /// The sink of the document the paragraph was read in; `null` for a new
  /// paragraph.
  DocxEditSink? _readIn;

  /// The formatting of the paragraph: its `w:pPr`.
  ///
  /// It is the same object every time.
  DocxParagraphProperties get properties => _properties;

  /// The id of the paragraph's style (`w:pStyle`), or `null` for none; a
  /// shortcut for [DocxParagraphProperties.style].
  ///
  /// A `w:pStyle` read from a file that the model does not type (no
  /// `w:val`, an empty one, another `w:` attribute, child elements) reads
  /// `null` and is written back as read until a style is set.
  ///
  /// Setting the empty string, or an id holding a character XML forbids,
  /// throws [ArgumentError]; set `null` to remove the style. The id set may
  /// read back as the document's own id for that style, and a set on a
  /// paragraph of a document throws a `DocxReadException` when its styles
  /// part cannot be read ([DocxParagraphProperties.style] has the rules).
  String? get style => _properties.style;

  set style(String? value) => _properties.style = value;

  /// The paragraph's inlines, in order. The list cannot be modified; use
  /// [addRun], [insertInline] and [removeInlineAt].
  List<DocxInline> get inlines => _inlinesView;

  /// The paragraph's visible text: the [DocxInline.text] of each inline, in
  /// order. A run gives its text and an opaque inline the visible text
  /// inside it, so inserted text counts and deleted text does not.
  String get text {
    final StringBuffer out = StringBuffer();
    for (final DocxInline inline in _inlines) {
      out.write(inline.text);
    }
    return out.toString();
  }

  /// Appends a new run that holds [text] and returns it. The text is split
  /// and scrubbed as [DocxRun.text] is when set.
  DocxRun addRun([String text = '']) {
    final DocxRun run = DocxRun(text);
    insertInline(_inlines.length, run);
    return run;
  }

  /// Inserts [inline] at [index], from 0 to the number of inlines.
  ///
  /// An [index] out of that range throws [RangeError]. An [inline] that is
  /// already in a paragraph, this one or another, throws [StateError]:
  /// remove it there first. In a paragraph of a document, the style set on
  /// a run is resolved against the document's styles (`DocxRun.style` has
  /// the rules), in the same edit; a styles part that cannot be read throws
  /// a `DocxReadException` naming it, and nothing changes. The `w:rStyle` of
  /// a run read in another document counts as set; `DocxBody.insertBlock`
  /// says what such a move does and does not do.
  void insertInline(int index, DocxInline inline) {
    RangeError.checkValueInInterval(index, 0, _inlines.length, 'index');
    _checkDetached(inline);
    _sink.atomically(() {
      _inlines.insert(index, inline);
      setParagraphOf(inline, this);
      _sink.inlineInserted(this, index, inline);
      if (inline is DocxRun) {
        _resolveRunStyle(inline, _sink);
      }
    });
  }

  /// Removes the inline at [index].
  ///
  /// An [index] that is not one of an inline throws [RangeError].
  void removeInlineAt(int index) {
    RangeError.checkValidIndex(index, _inlines, 'index');
    final DocxInline removed = _inlines.removeAt(index);
    setParagraphOf(removed, null);
    _sink.inlineRemoved(this, index, removed);
  }

  static void _checkDetached(DocxInline inline) {
    if (paragraphOf(inline) != null) {
      throw StateError('The inline is already in a paragraph.');
    }
  }
}

/// A table, `w:tbl`: its grid and its rows.
///
/// A table read from a file is written as read: the children it does not show
/// stay where they were, and a grid that does not fit its rows is kept.
final class DocxTable extends DocxBlock {
  DocxTable._read(
    this._source,
    this._attributes,
    this._gridColumnsPt,
    this._children,
  ) : _rows = _ofType<DocxTableRow>(_children),
      super._();

  /// The table's `w:tblPr` as read, by `tablePropertiesSchema`.
  final PropertyContainer _source;

  /// The attributes of `w:tbl` the reader kept, such as `w:rsidR`.
  final List<KeptAttribute> _attributes;

  final List<double?>? _gridColumnsPt;

  /// The children of `w:tbl` in file order: the [_source] when the file has
  /// a `w:tblPr`, each [DocxTableRow], and an [OpaqueXml] for any other,
  /// `w:tblGrid` among them.
  final List<Object> _children;

  /// The typed rows of [_children], in order.
  final List<DocxTableRow> _rows;

  late final List<DocxTableRow> _rowsView = UnmodifiableListView<DocxTableRow>(
    _rows,
  );

  /// The table's rows, in order. The list cannot be modified.
  ///
  /// Only the `w:tr` children of `w:tbl` are rows: one inside a content
  /// control or another kept element is not listed, and is written as read.
  List<DocxTableRow> get rows => _rowsView;

  /// The width of each column of the grid (`w:tblGrid`), in points, or `null`
  /// for a table without a grid. The list cannot be modified.
  ///
  /// An entry is `null` for a `w:gridCol` whose `w:w` is missing or is not a
  /// whole number of twips.
  List<double?>? get gridColumnsPt => _gridColumnsPt;
}

/// A row of a table, `w:tr`.
final class DocxTableRow {
  DocxTableRow._read(this._source, this._attributes, this._children)
    : _cells = _ofType<DocxTableCell>(_children);

  /// The row's `w:trPr` as read, by `tableRowPropertiesSchema`.
  final PropertyContainer _source;

  /// The attributes of `w:tr` the reader kept, such as `w14:paraId`.
  final List<KeptAttribute> _attributes;

  /// The children of `w:tr` in file order: the [_source] when the file has a
  /// `w:trPr`, each [DocxTableCell], and an [OpaqueXml] for any other,
  /// `w:tblPrEx` among them.
  final List<Object> _children;

  /// The typed cells of [_children], in order.
  final List<DocxTableCell> _cells;

  late final List<DocxTableCell> _cellsView =
      UnmodifiableListView<DocxTableCell>(_cells);

  /// The row's cells, in order. The list cannot be modified.
  ///
  /// Only the `w:tc` children of `w:tr` are cells: one inside a content
  /// control or another kept element is not listed, and is written as read.
  List<DocxTableCell> get cells => _cellsView;
}

/// A cell of a table row, `w:tc`.
final class DocxTableCell {
  DocxTableCell._read(this._source, this._attributes, this._blocks)
    : _readUnclosed = _blocks.lastOrNull is DocxParagraph
          ? null
          : List<DocxBlock>.of(_blocks);

  /// The cell's `w:tcPr` as read, by `tableCellPropertiesSchema`.
  final PropertyContainer _source;

  /// The attributes of `w:tc` the reader kept, such as `w:rsidR`.
  final List<KeptAttribute> _attributes;

  final List<DocxBlock> _blocks;

  late final List<DocxBlock> _blocksView = UnmodifiableListView<DocxBlock>(
    _blocks,
  );

  /// The blocks read, when the cell was read without a paragraph last; `null`
  /// for a cell read with one, which needs no such copy.
  final List<DocxBlock>? _readUnclosed;

  /// The cell's blocks, in order: paragraphs, tables and opaque blocks. The
  /// list cannot be modified.
  List<DocxBlock> get blocks => _blocksView;

  /// The cell's text: the text of its paragraphs joined by `\n`. A nested
  /// table adds the text of its cells, row by row, in their place; an opaque
  /// block adds nothing.
  String get text {
    final List<String> lines = <String>[];
    _addLines(lines);
    return lines.join('\n');
  }

  void _addLines(List<String> lines) {
    for (final DocxBlock block in _blocks) {
      switch (block) {
        case DocxParagraph():
          lines.add(block.text);
        case DocxTable():
          for (final DocxTableRow row in block._rows) {
            for (final DocxTableCell cell in row._cells) {
              cell._addLines(lines);
            }
          }
        case DocxOpaqueBlock():
          break;
      }
    }
  }
}

/// A block the model does not type, kept as written.
final class DocxOpaqueBlock extends DocxBlock {
  DocxOpaqueBlock._(this._xml) : super._();

  final OpaqueXml _xml;

  /// The element's local name, such as `sdt` or `bookmarkStart`.
  String get localName => _xml.localName;

  /// The element's namespace URI, or the empty string.
  String get namespaceUri => _xml.namespaceUri;

  @override
  String toString() => 'DocxOpaqueBlock($localName)';
}

/// A paragraph as the reader builds it: its `w:pPr` as read (by
/// `paragraphPropertiesSchema`), the kept attributes of `w:p`, and its
/// inlines as read. Each inline must be in no paragraph, or [StateError] is
/// thrown.
DocxParagraph readParagraph({
  required PropertyContainer properties,
  required List<KeptAttribute> attributes,
  required List<DocxInline> inlines,
}) {
  final DocxParagraph p = DocxParagraph._read(properties, attributes);
  for (final DocxInline inline in inlines) {
    DocxParagraph._checkDetached(inline);
    p._inlines.add(inline);
    setParagraphOf(inline, p);
  }
  return p;
}

/// A table as the reader builds it: its `w:tblPr` as read (by
/// `tablePropertiesSchema`; an empty container for none), the kept attributes
/// of `w:tbl`, the widths of its grid, and its children in file order: the
/// [properties] when read, each [DocxTableRow], and an [OpaqueXml] for any
/// other.
DocxTable readTable({
  required PropertyContainer properties,
  required List<KeptAttribute> attributes,
  required List<double?>? gridColumnsPt,
  required List<Object> children,
}) => DocxTable._read(properties, attributes, gridColumnsPt, children);

/// A row as the reader builds it: its `w:trPr` as read (by
/// `tableRowPropertiesSchema`; an empty container for none), the kept
/// attributes of `w:tr`, and its children in file order: the [properties]
/// when read, each [DocxTableCell], and an [OpaqueXml] for any other.
DocxTableRow readTableRow({
  required PropertyContainer properties,
  required List<KeptAttribute> attributes,
  required List<Object> children,
}) => DocxTableRow._read(properties, attributes, children);

/// A cell as the reader builds it: its `w:tcPr` as read (by
/// `tableCellPropertiesSchema`; an empty container for none), the kept
/// attributes of `w:tc`, and its blocks as read, which are in the cell from
/// now on. Each block must be in no container, or [StateError] is thrown.
DocxTableCell readTableCell({
  required PropertyContainer properties,
  required List<KeptAttribute> attributes,
  required List<DocxBlock> blocks,
}) {
  final DocxTableCell cell = DocxTableCell._read(
    properties,
    attributes,
    blocks,
  );
  for (final DocxBlock block in blocks) {
    if (block._container != null) {
      throw StateError('The block is already in a container.');
    }
    block._container = cell;
  }
  return cell;
}

/// The elements of type [T] among [children], in order.
List<T> _ofType<T>(List<Object> children) => children.whereType<T>().toList();

/// Calls [visit] with [block], then with every block in the cells of a table,
/// nested tables included, in document order.
///
/// Rows and cells inside a kept element are not part of the tree.
void visitBlocks(DocxBlock block, void Function(DocxBlock block) visit) {
  visit(block);
  if (block is! DocxTable) return;
  for (final DocxTableRow row in block._rows) {
    for (final DocxTableCell cell in row._cells) {
      for (final DocxBlock inner in cell._blocks) {
        visitBlocks(inner, visit);
      }
    }
  }
}

/// Resolves the style set through the API on [run], which is in a paragraph
/// of the document of [sink] now; one read in another document counts as set.
void _resolveRunStyle(DocxRun run, DocxEditSink sink) {
  final PropertySet properties = runPropertySetOf(run);
  if (sink.isForeign(runReadInOf(run))) {
    properties.countReadAsSet('rStyle');
  }
  properties.resolveStyleIdSet('rStyle', DocxStyleType.character);
}

/// Resolves the styles set through the API on [paragraph] and its runs,
/// which are in a document now; what was read from that document's file
/// stays (plan Ruling 5), and what was read in another counts as set: the
/// `w:pStyle`, the `w:numPr` that the save checks, and each run's
/// `w:rStyle`.
void resolveStylesSet(DocxParagraph paragraph) {
  final DocxEditSink sink = paragraph._sink;
  final PropertySet properties = paragraphPropertySetOf(paragraph);
  if (sink.isForeign(paragraph._readIn)) {
    properties
      ..countReadAsSet('pStyle')
      ..countReadAsSet('numPr');
  }
  properties.resolveStyleIdSet('pStyle', DocxStyleType.paragraph);
  for (final DocxInline inline in paragraph._inlines) {
    if (inline is DocxRun) {
      _resolveRunStyle(inline, sink);
    }
  }
}

/// Records that [paragraph] and its runs were read in the document of
/// [sink], so what they name counts as set in any other.
void markReadIn(DocxParagraph paragraph, DocxEditSink sink) {
  paragraph._readIn = sink;
  for (final DocxInline inline in paragraph._inlines) {
    if (inline is DocxRun) {
      setRunReadIn(inline, sink);
    }
  }
}

/// Records that [block] and everything in its cells were read in the document
/// of [sink] ([markReadIn]).
void markBlockReadIn(DocxBlock block, DocxEditSink sink) {
  visitBlocks(block, (DocxBlock b) {
    if (b is DocxParagraph) markReadIn(b, sink);
  });
}

/// The sink of the document [paragraph] was read in, or `null` for a new one.
DocxEditSink? paragraphReadInOf(DocxParagraph paragraph) => paragraph._readIn;

/// The `w:pPr` of [paragraph] as read, without the values set since.
PropertyContainer paragraphPropertiesOf(DocxParagraph paragraph) =>
    paragraph._source;

/// The properties of [paragraph], for the writer.
PropertySet paragraphPropertySetOf(DocxParagraph paragraph) =>
    propertySetOfParagraphProperties(paragraph._properties);

/// The attributes of `w:p` the reader kept on [paragraph], in source order.
List<KeptAttribute> paragraphAttributesOf(DocxParagraph paragraph) =>
    paragraph._attributes;

/// The sink [paragraph] and its runs report their edits to.
DocxEditSink editSinkOf(DocxParagraph paragraph) => paragraph._sink;

/// Makes [sink] receive the edits of [paragraph] and its runs from now on;
/// [DocxEditSink.none] detaches it.
void attachEditSink(DocxParagraph paragraph, DocxEditSink sink) {
  paragraph._sink = sink;
}

/// Puts [inline] in place of the inline at [index] of [paragraph], and
/// reports it to the paragraph's sink.
///
/// An [index] that is not one of an inline throws [RangeError], and an
/// [inline] already in a paragraph throws [StateError].
void replaceInlineAt(DocxParagraph paragraph, int index, DocxInline inline) {
  final List<DocxInline> inlines = paragraph._inlines;
  RangeError.checkValidIndex(index, inlines, 'index');
  DocxParagraph._checkDetached(inline);
  final DocxInline previous = inlines[index];
  inlines[index] = inline;
  setParagraphOf(previous, null);
  setParagraphOf(inline, paragraph);
  paragraph._sink.inlineReplaced(paragraph, index, previous, inline);
}

/// The `w:tblPr` of [table] as read; an empty container for none.
PropertyContainer tablePropertiesOf(DocxTable table) => table._source;

/// The attributes of `w:tbl` the reader kept on [table], in source order.
List<KeptAttribute> tableAttributesOf(DocxTable table) => table._attributes;

/// The children of `w:tbl` of [table] in file order, for the writer: its
/// [tablePropertiesOf] when read, each [DocxTableRow], and an [OpaqueXml] for
/// any other.
List<Object> tableChildrenOf(DocxTable table) => table._children;

/// The `w:trPr` of [row] as read; an empty container for none.
PropertyContainer rowPropertiesOf(DocxTableRow row) => row._source;

/// The attributes of `w:tr` the reader kept on [row], in source order.
List<KeptAttribute> rowAttributesOf(DocxTableRow row) => row._attributes;

/// The children of `w:tr` of [row] in file order, for the writer: its
/// [rowPropertiesOf] when read, each [DocxTableCell], and an [OpaqueXml] for
/// any other.
List<Object> rowChildrenOf(DocxTableRow row) => row._children;

/// The `w:tcPr` of [cell] as read; an empty container for none.
PropertyContainer cellPropertiesOf(DocxTableCell cell) => cell._source;

/// The attributes of `w:tc` the reader kept on [cell], in source order.
List<KeptAttribute> cellAttributesOf(DocxTableCell cell) => cell._attributes;

/// The list of the blocks of [cell], for the block primitives.
List<DocxBlock> cellBlocksOf(DocxTableCell cell) => cell._blocks;

/// Whether [cell] must be written with an empty `w:p` after its blocks: Word
/// repairs a cell that does not end in a paragraph.
///
/// A cell read without one, whose blocks are still all the ones read, is
/// written as read; the blocks compare by identity, so an undo restores that,
/// and a cell read with no blocks stays empty. The paragraph added is not in
/// [DocxTableCell.blocks] until the file is read again.
bool cellNeedsClosingParagraph(DocxTableCell cell) {
  return cell._blocks.lastOrNull is! DocxParagraph && !_blocksAsRead(cell);
}

/// Whether [cell] was read without a closing paragraph and holds exactly the
/// blocks it read, in order.
bool _blocksAsRead(DocxTableCell cell) {
  final List<DocxBlock>? read = cell._readUnclosed;
  final List<DocxBlock> blocks = cell._blocks;
  if (read == null || read.length != blocks.length) return false;
  for (int i = 0; i < read.length; i++) {
    if (!identical(read[i], blocks[i])) return false;
  }
  return true;
}

/// The container [block] is in, such as a document's body or a table cell, or
/// `null`.
Object? blockContainerOf(DocxBlock block) => block._container;

/// Records that [block] is now in [container] (`null`: in none). Only the
/// block primitives call it.
void setBlockContainerOf(DocxBlock block, Object? container) {
  block._container = container;
}

/// An opaque block for the element [xml] captured.
DocxOpaqueBlock opaqueBlock(OpaqueXml xml) => DocxOpaqueBlock._(xml);

/// The element [block] keeps, for the writer.
OpaqueXml opaqueBlockXml(DocxOpaqueBlock block) => block._xml;
