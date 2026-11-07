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
library;

import '../opc/ooxml.dart' show Ns;
import '../opc/opaque_xml.dart';
import '../xml/xml_escape.dart' show scrubXmlText;
import '../xml/xml_writer.dart';
import 'model/blocks.dart';
import 'model/formatting.dart' show DocxNumberingRef;
import 'model/inlines.dart';
import 'model/property_set.dart';
import 'model/run_content.dart';
import 'model/styles.dart' show DocxStyleType;
import 'properties.dart' show PropertyContainer;
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
  /// API set.
  StoryWriter(
    this._w,
    this._p,
    this._prefix,
    this.scope,
    this._partName,
    this._warnings,
    this._listDefined,
    this._styleDefined,
  );

  final XmlWriter _w;

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
          _paragraph(block, '$path/p[${paragraphs++}]');
        case DocxTable():
          _table(block, '$path/tbl[${tables++}]');
        case DocxOpaqueBlock():
          opaqueBlockXml(block).writeTo(_w, declaredAbove: scope);
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
        _row(child, '$path/tr[${rows++}]');
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
    // read, so a location does not depend on what was typed as a field.
    int runs = 0;
    void write(DocxInline inline) {
      switch (inline) {
        case DocxRun():
          _run(inline, '$path/r[${runs++}]');
        case DocxOpaqueInline():
          opaqueInlineXml(inline).writeTo(w, declaredAbove: scope);
        case DocxField():
          throw StateError('visitInlines gives no field.');
      }
    }

    for (final DocxInline inline in p.inlines) {
      visitInlines(inline, write);
    }
    scope = outer;
    w.end();
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
      case DocxOpaqueRunContent():
        opaqueRunContentXml(c).writeTo(w, declaredAbove: scope);
    }
  }

  /// Writes `w:<localName>` with the attributes [c] kept and no content.
  void _empty(String localName, DocxRunContent c) {
    _w.start('$_p$localName');
    writeKeptAttributes(_w, contentAttributesOf(c), declaredAbove: scope);
    _w.end();
  }
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
