/// The writer of a story's blocks: paragraphs, tables, rows, cells and runs.
///
/// Not ported from Quds; written for jet_office.
///
/// [StoryWriter] writes the blocks of a body, or of any part that holds
/// blocks as `w:body` does, inside the open root of that part. Typed elements
/// use the root's own prefix for WordprocessingML; every kept element and
/// attribute is written with the root's bindings as the ones in scope. It
/// reports, at the location of the paragraph, the run or the table, a list
/// set through the API that the document does not define
/// ([DocxWarningCode.numberingNotFound]), a style it does not define
/// ([DocxWarningCode.styleNotFound]) and the characters a run lost when its
/// text was set ([DocxWarningCode.invalidCharactersRemoved]).
///
/// A unit the template fill copied (`isTemplateCopy`: an inline, a row or a
/// block) is written as any other, then renewed (plan T2, Ruling 9): its
/// drawings get new `wp:docPr` ids (and their `pic:cNvPr` the same), its
/// revisions new `w:id`s, its content controls new `w:sdtPr/w:id`s, and its
/// elements lose `w14:paraId`, `w14:textId`, `wp14:anchorId` and
/// `wp14:editId`. Within one unit one old id gives one new id; a copy inside
/// a copy is renewed by its own mark alone. A unit that is no copy is
/// written exactly as before.
library;

import '../opc/ooxml.dart' show Ns;
import '../opc/opaque_xml.dart';
import '../xml/xml_escape.dart' show escapeXmlAttribute, scrubXmlText;
import '../xml/xml_pull_reader.dart';
import '../xml/xml_writer.dart';
import 'drawing.dart' show writeInlineDrawing;
import 'model/blocks.dart';
import 'model/formatting.dart' show DocxNumberingRef;
import 'model/inlines.dart';
import 'model/property_set.dart';
import 'model/run_content.dart';
import 'model/styles.dart' show DocxStyleType;
import 'model/template_copies.dart' show isTemplateCopy;
import 'properties.dart' show PropertyContainer;
import 'save_ids.dart' show parseOfficeId, revisionNames;
import 'warnings.dart';

/// The list [paragraph] was put in through the API: the value of a
/// `w:numPr` set on it that names a list other than 0, or `null` (nothing
/// set, removed, or read from the file).
DocxNumberingRef? listSetOf(DocxParagraph paragraph) {
  final PropertySet pPr = paragraphPropertySetOf(paragraph);
  if (!pPr.isSet('numPr')) {
    return null;
  }
  final Object? value = pPr.valueOf('numPr');
  return value is DocxNumberingRef && value.numId != 0 ? value : null;
}

/// Throws [StateError] naming the first table of [blocks], at the location
/// [path], that the API left without rows: Word repairs a table without rows,
/// and a save must find that out before it writes anything. A table read with
/// no rows is kept.
void checkTablesHaveRows(List<DocxBlock> blocks, String path) {
  int tables = 0;
  for (final DocxBlock block in blocks) {
    if (block is! DocxTable) continue;
    final String at = '$path/tbl[${tables++}]';
    final List<DocxTableRow> rows = block.rows;
    if (rows.isEmpty && tableIsNew(block)) {
      throw StateError(
        'The table at $at has no rows: add one with addRow, or remove the '
        'table.',
      );
    }
    for (int r = 0; r < rows.length; r++) {
      final List<DocxTableCell> cells = rows[r].cells;
      for (int c = 0; c < cells.length; c++) {
        checkTablesHaveRows(cells[c].blocks, '$at/tr[$r]/tc[$c]');
      }
    }
  }
}

/// The new ids a save gives what the template fill's copies hold (plan T2,
/// Ruling 9): a `wp:docPr` id, an annotation id for a revision and a content
/// control id, each new on every call.
final class CopyIds {
  /// Ids from [drawing], [annotation] and [contentControl].
  CopyIds(this.drawing, this.annotation, this.contentControl);

  /// A new `wp:docPr` id.
  final int Function() drawing;

  /// A new `w:id` of a revision, in the id space bookmarks share.
  final int Function() annotation;

  /// A new `w:sdtPr/w:id/@w:val`.
  final int Function() contentControl;
}

/// One write of the blocks of a story, inside the open root of its part.
///
/// A story is a part's run of blocks: the body of the main part, and later
/// the content of a header or a footer part. [writeBlocks] writes them under
/// a location prefix, as `body` or a part's own name, and reports what it
/// repairs there.
final class StoryWriter {
  /// Writes to [_w] with the WordprocessingML prefix [_prefix] (with its colon
  /// as [_p]), the root's bindings [scope], and warnings for the part
  /// [_partName], asking [_listDefined] and [_styleDefined] about what the
  /// API set, [bookmarkId] for the id of a built bookmark, [drawingId] for
  /// the `wp:docPr` id of a built picture, [relationshipId] for the
  /// relationship of a built hyperlink or picture and [copyIds] for the ids
  /// of the template fill's copies.
  StoryWriter(
    this._w,
    this._p,
    this._prefix,
    this.scope,
    this._partName,
    this._warnings,
    this._listDefined,
    this._styleDefined, {
    int Function(DocxBookmarkStart start)? bookmarkId,
    int Function(DocxPicture picture)? drawingId,
    String? Function(Object built)? relationshipId,
    CopyIds? copyIds,
  }) : _bookmarkId = bookmarkId,
       _drawingId = drawingId,
       _relationshipId = relationshipId,
       _copyIds = copyIds;

  /// The writer of the part, or a scratch writer while a copy is written.
  XmlWriter _w;

  /// The WordprocessingML prefix with its colon, such as `w:`.
  final String _p;

  /// The WordprocessingML prefix, such as `w`.
  final String _prefix;

  /// The bindings in scope where the writer is: those of the root, and those
  /// the kept attributes of the elements open around it declared. What
  /// surrounds the blocks sets them when it declares some.
  Map<String, String> scope;

  final String _partName;
  final DocxWarningCollector _warnings;
  final bool Function(int numId)? _listDefined;
  final bool Function(String id, DocxStyleType type)? _styleDefined;

  /// The id of the bookmark a built start begins, in this save (the same for
  /// its end); `null` outside a save, when the writer numbers them itself
  /// from 0.
  final int Function(DocxBookmarkStart start)? _bookmarkId;

  /// The `wp:docPr` id of a built picture in this save; `null` outside a
  /// save, when the writer numbers them itself from 1.
  final int Function(DocxPicture picture)? _drawingId;

  /// The id of the relationship this save gave the part for what the API
  /// built, such as a hyperlink or a picture; `null` outside a save, and for
  /// what has none, which is then written without one.
  final String? Function(Object built)? _relationshipId;

  final Map<DocxBookmarkStart, int> _ownBookmarkIds =
      Map<DocxBookmarkStart, int>.identity();

  final Map<DocxPicture, int> _ownDrawingIds = Map<DocxPicture, int>.identity();

  /// The new ids of this save for the template fill's copies; `null` outside
  /// a save, when the writer numbers each kind itself, from one more than the
  /// highest id of that kind it has met in a copy.
  final CopyIds? _copyIds;

  /// The highest drawing, annotation and content control ids the writer met
  /// in a copy or gave one, when it numbers them itself.
  int _ownDrawing = 0;
  int _ownAnnotation = -1;
  int _ownContentControl = 0;

  /// The part's writer while a copy is written to a scratch one; `null`
  /// outside a copy.
  XmlWriter? _outsideCopy;

  /// The writer of the part's XML, for what surrounds the blocks.
  XmlWriter get writer => _w;

  /// The WordprocessingML prefix with its colon, such as `w:`.
  String get wordPrefix => _p;

  /// Writes [blocks], of the story or the cell at the location [path].
  void writeBlocks(List<DocxBlock> blocks, String path) {
    int paragraphs = 0;
    int tables = 0;
    for (final DocxBlock block in blocks) {
      switch (block) {
        case DocxParagraph():
          final String at = '$path/p[${paragraphs++}]';
          _unit(block, () => _paragraph(block, at));
        case DocxTable():
          final String at = '$path/tbl[${tables++}]';
          _unit(block, () => _table(block, at));
        case DocxOpaqueBlock():
          _unit(
            block,
            () => opaqueBlockXml(block).writeTo(_w, declaredAbove: scope),
          );
      }
    }
  }

  /// Writes the table [t] at the location [path].
  void _table(DocxTable t, String path) {
    _w.start('${_p}tbl');
    writeKeptAttributes(_w, tableAttributesOf(t), declaredAbove: scope);
    final Map<String, String> outer = scope;
    scope = scopeInside(tableAttributesOf(t), outer);
    final PropertySet tblPr = tablePropertySetOf(t);
    _checkStyle(tblPr, 'tblStyle', DocxStyleType.table, path);
    // A table read without a w:tblPr writes one first when a value was set; a
    // new table always does, as the schema requires it.
    if (tableIsNew(t) ||
        (!tablePropertiesOf(t).isRead && !tblPr.writesNothing)) {
      writePropertySet(tblPr, 'tblPr');
    }
    final List<Object> children = tableChildrenOf(t);
    final List<double?>? widths = tableGridWidthsOf(t);
    // A table read without a grid writes one before its first row when the
    // widths were set.
    bool gridPending = widths != null && !children.any((c) => c is TableGrid);
    int rows = 0;
    for (final Object child in children) {
      if (child is DocxTableRow) {
        if (gridPending) {
          _newGrid(widths!);
          gridPending = false;
        }
        final String at = '$path/tr[${rows++}]';
        _unit(child, () => _row(child, at));
      } else if (child is PropertyContainer) {
        writePropertySet(tblPr, 'tblPr');
      } else if (child is TableGrid) {
        if (tableGridAsRead(t)) {
          child.xml.writeTo(_w, declaredAbove: scope);
        } else {
          _grid(child, widths!);
        }
      } else {
        (child as OpaqueXml).writeTo(_w, declaredAbove: scope);
      }
    }
    if (gridPending) {
      _newGrid(widths!);
    }
    scope = outer;
    _w.end();
  }

  /// Writes a `w:tblGrid` of [widths], in points.
  void _newGrid(List<double?> widths) {
    _w.start('${_p}tblGrid');
    _gridCols(widths);
    _w.end();
  }

  /// Writes the grid [grid] with the widths [widths], in points, and the
  /// children that are no `w:gridCol` as they were.
  void _grid(TableGrid grid, List<double?> widths) {
    _w.start('${_p}tblGrid');
    writeNamespaceDeclarations(_w, grid.declared);
    grid.xml.inheritedNamespaces.forEach((String prefix, String uri) {
      if (grid.declared.containsKey(prefix)) return;
      final String? above = scope[prefix] ?? (prefix.isEmpty ? '' : null);
      if (above != uri) {
        _w.attribute(prefix.isEmpty ? 'xmlns' : 'xmlns:$prefix', uri);
      }
    });
    _gridCols(widths);
    grid.keptChildren.forEach(_w.raw);
    _w.end();
  }

  void _gridCols(List<double?> widths) {
    for (final double? width in widths) {
      _w
        ..start('${_p}gridCol')
        ..attribute('${_p}w', '${(width! * 20).round()}')
        ..end();
    }
  }

  /// Writes the row [row] at the location [path].
  void _row(DocxTableRow row, String path) {
    _w.start('${_p}tr');
    writeKeptAttributes(_w, rowAttributesOf(row), declaredAbove: scope);
    final Map<String, String> outer = scope;
    scope = scopeInside(rowAttributesOf(row), outer);
    final PropertySet trPr = rowPropertySetOf(row);
    // A row read without a w:trPr writes one when a value was set: after
    // any w:tblPrEx, before everything else.
    bool pending = !rowPropertiesOf(row).isRead && !trPr.writesNothing;
    int cells = 0;
    for (final Object child in rowChildrenOf(row)) {
      if (pending && !_isTblPrEx(child)) {
        writePropertySet(trPr, 'trPr');
        pending = false;
      }
      if (child is DocxTableCell) {
        _cell(child, '$path/tc[${cells++}]');
      } else if (child is PropertyContainer) {
        writePropertySet(trPr, 'trPr');
      } else {
        (child as OpaqueXml).writeTo(_w, declaredAbove: scope);
      }
    }
    if (pending) {
      writePropertySet(trPr, 'trPr');
    }
    scope = outer;
    _w.end();
  }

  /// Whether [child] is a kept `w:tblPrEx`.
  bool _isTblPrEx(Object child) =>
      child is OpaqueXml &&
      child.localName == 'tblPrEx' &&
      child.namespaceUri == Ns.w;

  /// Writes [properties] as `w:<localName>`.
  void writePropertySet(PropertySet properties, String localName) => properties
      .writeTo(_w, '$_p$localName', prefix: _prefix, declaredAbove: scope);

  /// Writes the cell [cell] at the location [path], and the paragraph that
  /// closes it when it needs one.
  void _cell(DocxTableCell cell, String path) {
    _w.start('${_p}tc');
    writeKeptAttributes(_w, cellAttributesOf(cell), declaredAbove: scope);
    final Map<String, String> outer = scope;
    scope = scopeInside(cellAttributesOf(cell), outer);
    final PropertySet tcPr = cellPropertySetOf(cell);
    if (!tcPr.writesNothing) {
      writePropertySet(tcPr, 'tcPr');
    }
    writeBlocks(cell.blocks, path);
    if (cellNeedsClosingParagraph(cell)) {
      _w
        ..start('${_p}p')
        ..end();
    }
    scope = outer;
    _w.end();
  }

  /// Writes the paragraph [p] at the location [path].
  void _paragraph(DocxParagraph p, String path) {
    final XmlWriter w = _w;
    w.start('${_p}p');
    writeKeptAttributes(w, paragraphAttributesOf(p), declaredAbove: scope);
    final Map<String, String> outer = scope;
    scope = scopeInside(paragraphAttributesOf(p), outer);
    final PropertySet pPr = paragraphPropertySetOf(p);
    final bool Function(int)? listDefined = _listDefined;
    final DocxNumberingRef? list = listDefined == null ? null : listSetOf(p);
    if (list != null && !listDefined!(list.numId)) {
      _warnings.add(
        DocxWarningCode.numberingNotFound,
        part: _partName,
        location: path,
        detail: '${list.numId}',
      );
    }
    _checkStyle(pPr, 'pStyle', DocxStyleType.paragraph, path);
    if (!pPr.writesNothing) {
      pPr.writeTo(w, '${_p}pPr', prefix: _prefix, declaredAbove: scope);
    }
    // A field writes its inlines in order, and its runs count as they did when
    // read, so a location does not depend on what was typed as a field. A
    // hyperlink writes its start tag as read around its inlines, whose runs
    // count among the paragraph's in file order.
    int runs = 0;
    late final void Function(DocxInline inline) write;
    void writeInline(DocxInline inline) {
      switch (inline) {
        case DocxRun():
          _run(inline, '$path/r[${runs++}]');
        case DocxOpaqueInline():
          opaqueInlineXml(inline).writeTo(_w, declaredAbove: scope);
        case DocxBookmarkStart():
          _bookmarkStart(inline, path);
        case DocxBookmarkEnd():
          _bookmarkEnd(inline);
        case DocxField():
          heldInlinesOf(inline)!.forEach(write);
        case DocxHyperlink():
          if (hyperlinkIsBuilt(inline)) {
            _builtHyperlinkStart(inline);
            inline.inlines.forEach(write);
            _w.end();
            break;
          }
          final List<KeptAttribute> attributes = hyperlinkAttributesOf(inline);
          _w.start('${_p}hyperlink');
          writeKeptAttributes(_w, attributes, declaredAbove: scope);
          final Map<String, String> around = scope;
          scope = scopeInside(attributes, around);
          inline.inlines.forEach(write);
          scope = around;
          _w.end();
      }
    }

    write = (DocxInline inline) => _unit(inline, () => writeInline(inline));
    p.inlines.forEach(write);
    scope = outer;
    w.end();
  }

  /// Opens the `w:hyperlink` of [link], which the API built, as Word writes
  /// one: `r:id` (the relationship of this save, for an address), then
  /// `w:anchor`, `w:tooltip` and `w:history="1"`. A prefix for the
  /// relationships namespace is declared on it when none is in scope.
  void _builtHyperlinkStart(DocxHyperlink link) {
    final XmlWriter w = _w;
    w.start('${_p}hyperlink');
    final String? id = link.url == null ? null : _relationshipId?.call(link);
    if (id != null) {
      String? rel = scope['r'] == Ns.rel ? 'r' : null;
      for (final MapEntry<String, String> e in scope.entries) {
        if (rel != null) break;
        if (e.key.isNotEmpty && e.value == Ns.rel) rel = e.key;
      }
      if (rel == null) {
        rel = 'r';
        for (int i = 1; scope.containsKey(rel); i++) {
          rel = 'r$i';
        }
        w.attribute('xmlns:$rel', Ns.rel);
      }
      w.attribute('$rel:id', id);
    }
    final String? anchor = link.anchor;
    if (anchor != null) w.attribute('${_p}anchor', anchor);
    final String? tooltip = link.tooltip;
    if (tooltip != null) w.attribute('${_p}tooltip', tooltip);
    w.attribute('${_p}history', '1');
  }

  /// The id a save writes for the bookmark [start] begins.
  int _idOf(DocxBookmarkStart start) =>
      start.id ?? (_bookmarkId ?? _ownBookmarkId)(start);

  int _ownBookmarkId(DocxBookmarkStart start) =>
      _ownBookmarkIds.putIfAbsent(start, () => _ownBookmarkIds.length);

  /// Writes the bookmark start [start] of the paragraph at [path]: as read
  /// when it was read, else with the id of this save, reporting a name the
  /// API repaired.
  void _bookmarkStart(DocxBookmarkStart start, String path) {
    final OpaqueXml? xml = bookmarkXml(start);
    if (xml != null) {
      xml.writeTo(_w, declaredAbove: scope);
      return;
    }
    final String? given = bookmarkRepairedFrom(start);
    if (given != null) {
      _warnings.add(
        DocxWarningCode.bookmarkNameRepaired,
        part: _partName,
        location: path,
        detail: given,
      );
    }
    _w
      ..start('${_p}bookmarkStart')
      ..attribute('${_p}id', '${_idOf(start)}')
      ..attribute('${_p}name', start.name)
      ..end();
  }

  /// Writes the bookmark end [end]: as read when it was read, else with the
  /// id of its start in this save.
  void _bookmarkEnd(DocxBookmarkEnd end) {
    final OpaqueXml? xml = bookmarkXml(end);
    if (xml != null) {
      xml.writeTo(_w, declaredAbove: scope);
      return;
    }
    _w
      ..start('${_p}bookmarkEnd')
      ..attribute('${_p}id', '${_idOf(end.start!)}')
      ..end();
  }

  /// Reports the style reference [localName] of [properties] at [path] if
  /// it was set through the API and names no style of [type].
  void _checkStyle(
    PropertySet properties,
    String localName,
    DocxStyleType type,
    String path,
  ) {
    final bool Function(String, DocxStyleType)? defined = _styleDefined;
    if (defined == null || !properties.isSet(localName)) {
      return;
    }
    final Object? id = properties.valueOf(localName);
    if (id is String && !defined(id, type)) {
      _warnings.add(
        DocxWarningCode.styleNotFound,
        part: _partName,
        location: path,
        detail: id,
      );
    }
  }

  /// Writes the run [r] at the location [path], and reports the characters
  /// removed from its text there.
  void _run(DocxRun r, String path) {
    final int removed = removedCharactersOf(r);
    if (removed > 0) {
      _warnings.add(
        DocxWarningCode.invalidCharactersRemoved,
        part: _partName,
        location: path,
        count: removed,
      );
    }
    final XmlWriter w = _w;
    w.start('${_p}r');
    writeKeptAttributes(w, runAttributesOf(r), declaredAbove: scope);
    final PropertySet rPr = runPropertySetOf(r);
    _checkStyle(rPr, 'rStyle', DocxStyleType.character, path);
    if (!rPr.writesNothing) {
      rPr.writeTo(w, '${_p}rPr', prefix: _prefix, declaredAbove: scope);
    }
    for (final DocxRunContent c in r.content) {
      _content(c);
    }
    w.end();
  }

  /// Writes one piece of run content.
  void _content(DocxRunContent c) {
    final XmlWriter w = _w;
    switch (c) {
      case DocxText(:final String text):
        w.start('${_p}t');
        if (textWasRead(c)) {
          writeKeptAttributes(w, contentAttributesOf(c), declaredAbove: scope);
        } else if (_needsPreserve(text)) {
          w.attribute('xml:space', 'preserve');
        }
        w.text(scrubXmlText(text).text);
        w.end();
      case DocxTab():
        _empty('tab', c);
      case DocxBreak(:final DocxBreakType type):
        w.start('${_p}br');
        if (type != DocxBreakType.line) {
          w.attribute('${_p}type', type.name);
        }
        writeKeptAttributes(w, contentAttributesOf(c), declaredAbove: scope);
        w.end();
      case DocxCarriageReturn():
        _empty('cr', c);
      case DocxFieldMark(:final DocxFieldMarkType type):
        final OpaqueXml? xml = fieldMarkXml(c);
        if (xml != null) {
          xml.writeTo(w, declaredAbove: scope);
        } else {
          w.start('${_p}fldChar');
          w.attribute('${_p}fldCharType', type.name);
          w.end();
        }
      case DocxFieldInstruction(:final String text):
        final OpaqueXml? xml = fieldInstructionXml(c);
        if (xml != null) {
          xml.writeTo(w, declaredAbove: scope);
        } else {
          w.start('${_p}instrText');
          w.attribute('xml:space', 'preserve');
          w.text(text);
          w.end();
        }
      case DocxPicture():
        final OpaqueXml? xml = pictureXml(c);
        if (xml != null) {
          xml.writeTo(w, declaredAbove: scope);
        } else {
          _builtPicture(c);
        }
      case DocxOpaqueRunContent():
        opaqueRunContentXml(c).writeTo(w, declaredAbove: scope);
    }
  }

  /// Writes the `w:drawing` of [picture], which the API built: the
  /// `wp:docPr` id of this save, the name given or `Picture <id>`, and the
  /// relationship this save gave its media in the part.
  void _builtPicture(DocxPicture picture) {
    final int id = (_drawingId ?? _ownDrawingId)(picture);
    _w.start('${_p}drawing');
    writeInlineDrawing(_w, (
      id: id,
      name: builtPictureName(picture) ?? 'Picture $id',
      description: picture.description,
      embedId: _relationshipId?.call(picture),
      cx: _emu(picture.widthPt!),
      cy: _emu(picture.heightPt!),
    ), declaredAbove: scope);
    _w.end();
  }

  int _ownDrawingId(DocxPicture picture) =>
      _ownDrawingIds.putIfAbsent(picture, () => _ownDrawingIds.length + 1);

  /// Writes [unit] by [write]: as it is when it is no copy, else renewed as
  /// the library comment says. A copy inside a copy is written between two
  /// processing instructions ([_copyStart], [_copyEnd]) that the renewal of
  /// the outer copy reads as its own mark and takes out.
  void _unit(Object unit, void Function() write) {
    if (!isTemplateCopy(unit)) {
      write();
      return;
    }
    if (_outsideCopy != null) {
      _w.raw('<?$_copyStart?>');
      write();
      _w.raw('<?$_copyEnd?>');
      return;
    }
    final XmlWriter outer = _w;
    final Map<String, String> around = scope;
    final StringBuffer scratch = StringBuffer();
    _outsideCopy = outer;
    _w = XmlWriter(scratch);
    try {
      write();
    } finally {
      _w = outer;
      _outsideCopy = null;
    }
    outer.raw(_renewed(scratch.toString(), around));
  }

  /// [xml], a copy written with the bindings [scope] in scope, with its ids
  /// renewed and the attributes Word regenerates taken out.
  String _renewed(String xml, Map<String, String> scope) {
    final CopyIds ids = _copyIds ?? _ownIds(xml, scope);
    final XmlPullReader r = _readerOf(xml, scope);
    final StringBuffer out = StringBuffer();
    int copied = r.eventEnd;
    void flush(int to) {
      if (to > copied) out.write(r.sourceText(copied, to));
    }

    final List<_CopyMaps> maps = <_CopyMaps>[_CopyMaps()];
    // The namespace and local name of each open element, innermost last.
    final List<(String, String)> open = <(String, String)>[];
    int? drawing;
    while (r.next()) {
      switch (r.eventType) {
        case XmlEventType.processingInstruction:
          final String target = r.localName;
          if (target != _copyStart && target != _copyEnd) break;
          flush(r.eventStart);
          copied = r.eventEnd;
          if (target == _copyStart) {
            maps.add(_CopyMaps());
          } else if (maps.length > 1) {
            // A kept element of a file may hold such an instruction too; it
            // can never take the copy's own maps.
            maps.removeLast();
          }
        case XmlEventType.startElement:
          final String ns = r.namespaceUri;
          final String name = r.localName;
          final (String, String)? parent = open.lastOrNull;
          if (!r.isEmptyElement) open.add((ns, name));
          final _CopyMaps m = maps.last;
          String? Function(int i)? renew;
          if (ns == Ns.wp && name == 'docPr') {
            renew = (int i) {
              if (r.attributeNamespace(i) != '' ||
                  r.attributeLocalName(i) != 'id') {
                return null;
              }
              final int id = m.drawing.putIfAbsent(
                r.attributeValue(i),
                ids.drawing,
              );
              drawing = id;
              return '$id';
            };
          } else if (ns == _pic && name == 'cNvPr' && drawing != null) {
            final int id = drawing!;
            renew = (int i) =>
                r.attributeNamespace(i) == '' && r.attributeLocalName(i) == 'id'
                ? '$id'
                : null;
          } else if (ns == Ns.w && revisionNames.contains(name)) {
            renew = (int i) =>
                r.attributeNamespace(i) == Ns.w &&
                    r.attributeLocalName(i) == 'id'
                ? '${m.annotation.putIfAbsent(r.attributeValue(i), ids.annotation)}'
                : null;
          } else if (ns == Ns.w && name == 'id' && parent == (Ns.w, 'sdtPr')) {
            renew = (int i) =>
                r.attributeNamespace(i) == Ns.w &&
                    r.attributeLocalName(i) == 'val'
                ? '${m.contentControl.putIfAbsent(r.attributeValue(i), ids.contentControl)}'
                : null;
          }
          final String? tag = _renewedStartTag(r, renew);
          if (tag != null) {
            flush(r.eventStart);
            out.write(tag);
            copied = r.eventEnd;
          }
        case XmlEventType.endElement:
          if (r.depth == 0) {
            flush(r.eventStart);
            return out.toString();
          }
          // An empty element's end is its `/>`, and it was never open.
          if (r.eventEnd - r.eventStart == 2) break;
          final (String ns, String name) = open.removeLast();
          if (ns == Ns.wp && (name == 'inline' || name == 'anchor')) {
            drawing = null;
          }
        default:
          break;
      }
    }
    flush(r.eventEnd);
    return out.toString();
  }

  /// The ids of a copy when the writer numbers them itself: one more than the
  /// highest it met in a copy, [xml] included, or gave one.
  CopyIds _ownIds(String xml, Map<String, String> scope) {
    final XmlPullReader r = _readerOf(xml, scope);
    final List<(String, String)> open = <(String, String)>[];
    while (r.next()) {
      if (r.eventType == XmlEventType.endElement) {
        // An empty element's end is its `/>`, and it was never open.
        if (r.eventEnd - r.eventStart != 2 && open.isNotEmpty) {
          open.removeLast();
        }
        continue;
      }
      if (r.eventType != XmlEventType.startElement) continue;
      final String ns = r.namespaceUri;
      final String name = r.localName;
      final (String, String)? parent = open.lastOrNull;
      if (!r.isEmptyElement) open.add((ns, name));
      int? id;
      if (ns == Ns.wp && name == 'docPr') {
        id = parseOfficeId(r.getAttribute('id', namespaceUri: ''));
        if (id != null && id > _ownDrawing) _ownDrawing = id;
      } else if (ns == Ns.w && revisionNames.contains(name)) {
        id = parseOfficeId(r.getAttribute('id', namespaceUri: Ns.w));
        if (id != null && id > _ownAnnotation) _ownAnnotation = id;
      } else if (ns == Ns.w && name == 'id' && parent == (Ns.w, 'sdtPr')) {
        id = parseOfficeId(r.getAttribute('val', namespaceUri: Ns.w));
        if (id != null && id > _ownContentControl) _ownContentControl = id;
      }
    }
    return CopyIds(
      () => ++_ownDrawing,
      () => ++_ownAnnotation,
      () => ++_ownContentControl,
    );
  }

  /// [xml] inside a root that declares [scope], on that root's start.
  static XmlPullReader _readerOf(String xml, Map<String, String> scope) {
    final StringBuffer source = StringBuffer('<r');
    scope.forEach((String prefix, String uri) {
      source
        ..write(prefix.isEmpty ? ' xmlns="' : ' xmlns:$prefix="')
        ..write(escapeXmlAttribute(scrubXmlText(uri).text))
        ..write('"');
    });
    source
      ..write('>')
      ..write(xml)
      ..write('</r>');
    // The model wrote it, so it nests as deep as the model holds, which the
    // read limits and the table nesting bound already.
    final XmlPullReader r = XmlPullReader(
      source.toString(),
      maxDepth: _copyMaxDepth,
    );
    r.next();
    return r;
  }

  /// Writes `w:<localName>` with the attributes [c] kept and no content.
  void _empty(String localName, DocxRunContent c) {
    _w.start('$_p$localName');
    writeKeptAttributes(_w, contentAttributesOf(c), declaredAbove: scope);
    _w.end();
  }
}

/// [points] in EMU, 12,700 to the point, rounded, and at least 1, so a side
/// that rounds to nothing still shows.
int _emu(double points) {
  final int emu = (points * 12700).round();
  return emu < 1 ? 1 : emu;
}

/// Whether text set through the API needs `xml:space="preserve"`: it starts
/// or ends with whitespace, or holds two spaces in a row, which a reader
/// would otherwise be free to collapse.
bool _needsPreserve(String text) {
  if (text.isEmpty) return false;
  return _isSpace(text.codeUnitAt(0)) ||
      _isSpace(text.codeUnitAt(text.length - 1)) ||
      text.contains('  ');
}

/// Whether [unit] is XML whitespace.
bool _isSpace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;

/// The processing instructions around a copy written inside a copy.
const String _copyStart = 'jet-office-copy';
const String _copyEnd = 'jet-office-copy-end';

/// How deep the writer reads a copy back: far beyond what a part may nest
/// when it is read, and what the API may build.
const int _copyMaxDepth = 1 << 16;

/// The DrawingML picture namespace, of `pic:cNvPr`.
const String _pic = 'http://schemas.openxmlformats.org/drawingml/2006/picture';

/// The Word 2010 drawing namespace, of `wp14:anchorId` and `wp14:editId`.
const String _wp14 =
    'http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing';

/// The old ids of one copy and the new ids they became, by kind.
final class _CopyMaps {
  final Map<String, int> drawing = <String, int>{};
  final Map<String, int> annotation = <String, int>{};
  final Map<String, int> contentControl = <String, int>{};
}

/// Whether the attribute [i] of the element [r] is on is one Word
/// regenerates and a copy leaves out: `w14:paraId`, `w14:textId`,
/// `wp14:anchorId`, `wp14:editId`.
bool _regenerated(XmlPullReader r, int i) {
  final String ns = r.attributeNamespace(i);
  final String name = r.attributeLocalName(i);
  return (ns == Ns.w14 && (name == 'paraId' || name == 'textId')) ||
      (ns == _wp14 && (name == 'anchorId' || name == 'editId'));
}

/// The start tag of the element [r] is on, with each attribute [renew] gives
/// a value for renewed and the [_regenerated] ones left out; `null` when
/// nothing changes, so the tag is copied as written.
String? _renewedStartTag(XmlPullReader r, String? Function(int i)? renew) {
  bool changed = false;
  final List<String?> values = List<String?>.filled(r.attributeCount, null);
  for (int i = 0; i < r.attributeCount; i++) {
    if (_regenerated(r, i)) {
      changed = true;
      continue;
    }
    final String value = r.attributeValue(i);
    final String? renewed = renew?.call(i);
    if (renewed != null && renewed != value) changed = true;
    values[i] = renewed ?? value;
  }
  if (!changed) return null;
  final StringBuffer tag = StringBuffer('<')..write(r.qualifiedName);
  for (int i = 0; i < r.attributeCount; i++) {
    final String? value = values[i];
    if (value == null) continue;
    tag
      ..write(' ')
      ..write(r.attributeQualifiedName(i))
      ..write('="')
      ..write(escapeXmlAttribute(scrubXmlText(value).text))
      ..write('"');
  }
  tag.write(r.isEmptyElement ? '/>' : '>');
  return tag.toString();
}
