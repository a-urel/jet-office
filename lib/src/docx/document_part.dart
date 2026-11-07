/// The main document part, `word/document.xml`, read into the body model.
///
/// Not ported from Quds; written for jet_office.
///
/// [DocumentPart.read] walks the part once with the pull reader. It types
/// `w:p`, its `w:pPr` and its runs; a run's `w:rPr`, text, tabs, breaks and
/// carriage returns; `w:tbl`, `w:tr` and `w:tc` with their `w:tblPr`, `w:trPr`
/// and `w:tcPr`, the blocks of a cell being read as those of the body.
/// Everything else is kept as written, in place: other blocks (content
/// controls, bookmarks) as opaque blocks, other children of `w:tbl` and
/// `w:tr` (`w:tblGrid`, `w:tblPrEx`, content controls, bookmarks) as kept
/// children, other paragraph children (tracked changes, hyperlinks, proofing
/// marks) as opaque inlines, other run children (drawings, fields,
/// `mc:AlternateContent`) as opaque run content, and unknown attributes on
/// `w:body`, `w:tbl`, `w:tr`, `w:tc`, `w:p`, `w:r`, `w:t`, `w:tab`, `w:br` and
/// `w:cr` as kept attributes. A `w:tbl` inside a kept element stays kept. The
/// visible text of an opaque inline is collected while it is captured, so its
/// slice is parsed once, under the part's own depth limit.
///
/// The body's last child, when it is a `w:sectPr`, is the last section
/// ([DocumentPart.finalSection]); a `w:sectPr` before another child stays an
/// opaque block. It is captured like any other element, because only what
/// follows tells, and its slice is read as a container once it is last.
///
/// A property element is typed only before the rows, cells or blocks of its
/// parent, and only the first of its name; one elsewhere is kept in place.
/// A table nested past [maxTableNesting] is refused.
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
import '../xml/xml_escape.dart';
import '../xml/xml_pull_reader.dart';
import '../xml/xml_writer.dart';
import 'model/blocks.dart';
import 'model/formatting.dart' show DocxNumberingRef;
import 'model/inlines.dart';
import 'model/property_set.dart';
import 'model/run_content.dart';
import 'model/sections.dart';
import 'model/styles.dart' show DocxStyleType;
import 'paragraph_property_codecs.dart' show paragraphPropertiesSchema;
import 'part_root.dart';
import 'properties.dart';
import 'property_codec.dart' show parseDecimal;
import 'read_exception.dart';
import 'read_limits.dart';
import 'run_property_codecs.dart' show runPropertiesSchema;
import 'section_property_codecs.dart' show sectionPropertiesSchema;
import 'table_property_codecs.dart'
    show
        tableCellPropertiesSchema,
        tablePropertiesSchema,
        tableRowPropertiesSchema;
import 'units.dart' show ptOfTwips;
import 'warnings.dart';

/// The largest width of a `w:gridCol`, in twips: what `parseDecimal` reads.
const int _maxGridColumnTwips = 999999999;

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
  }) => _PartReader(r, partName, limits.maxTextLength, limits.maxDepth).read();

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
  void checkBuiltTables() => _checkBuiltTables(blocks, 'body');

  static void _checkBuiltTables(List<DocxBlock> blocks, String path) {
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
          _checkBuiltTables(cells[c].blocks, '$at/tr[$r]/tc[$c]');
        }
      }
    }
  }

  /// Writes the part, and replaces [encodeWarnings] with the warnings of
  /// this write.
  @override
  List<Uint8List> encode() {
    final DocxWarningCollector warnings = DocxWarningCollector();
    final Utf8Buffer buffer = Utf8Buffer();
    final XmlWriter w = XmlWriter(buffer)..declaration();
    final (:String prefix, :Map<String, String> scope) = openWordRoot(w, root);
    _Writer(
      w,
      '$prefix:',
      prefix,
      scope,
      partName,
      warnings,
      listDefined,
      styleDefined,
    ).write(this);
    w.end();
    _encodeWarnings = warnings;
    return buffer.takeChunks();
  }
}

/// One write of a document part's content, inside the open root.
final class _Writer {
  _Writer(
    this._w,
    this._p,
    this._prefix,
    this._scope,
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

  /// The bindings in scope inside the root.
  final Map<String, String> _scope;

  final String _partName;
  final DocxWarningCollector _warnings;
  final bool Function(int numId)? _listDefined;
  final bool Function(String id, DocxStyleType type)? _styleDefined;

  void write(DocumentPart part) {
    for (final OpaqueXml x in part.beforeBody) {
      x.writeTo(_w, declaredAbove: _scope);
    }
    final PropertySet sectPr = sectionPropertySetOf(part.finalSection);
    if (part._hasBody ||
        part.blocks.isNotEmpty ||
        part.bodyAttributes.isNotEmpty ||
        !sectPr.writesNothing) {
      _w.start('${_p}body');
      writeKeptAttributes(_w, part.bodyAttributes, declaredAbove: _scope);
      _blocks(part.blocks, 'body');
      if (!sectPr.writesNothing) {
        _propertySet(sectPr, 'sectPr');
      }
      _w.end();
    }
    for (final OpaqueXml x in part.afterBody) {
      x.writeTo(_w, declaredAbove: _scope);
    }
  }

  /// Writes [blocks], of the body or the cell at the location [path].
  void _blocks(List<DocxBlock> blocks, String path) {
    int paragraphs = 0;
    int tables = 0;
    for (final DocxBlock block in blocks) {
      switch (block) {
        case DocxParagraph():
          _paragraph(block, '$path/p[${paragraphs++}]');
        case DocxTable():
          _table(block, '$path/tbl[${tables++}]');
        case DocxOpaqueBlock():
          opaqueBlockXml(block).writeTo(_w, declaredAbove: _scope);
      }
    }
  }

  /// Writes the table [t] at the location [path].
  void _table(DocxTable t, String path) {
    _w.start('${_p}tbl');
    writeKeptAttributes(_w, tableAttributesOf(t), declaredAbove: _scope);
    final PropertySet tblPr = tablePropertySetOf(t);
    _checkStyle(tblPr, 'tblStyle', DocxStyleType.table, path);
    // A table read without a w:tblPr writes one first when a value was set; a
    // new table always does, as the schema requires it.
    if (tableIsNew(t) ||
        (!tablePropertiesOf(t).isRead && !tblPr.writesNothing)) {
      _propertySet(tblPr, 'tblPr');
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
        _propertySet(tblPr, 'tblPr');
      } else if (child is TableGrid) {
        if (tableGridAsRead(t)) {
          child.xml.writeTo(_w, declaredAbove: _scope);
        } else {
          _grid(child, widths!);
        }
      } else {
        (child as OpaqueXml).writeTo(_w, declaredAbove: _scope);
      }
    }
    if (gridPending) {
      _newGrid(widths!);
    }
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
      final String? above = _scope[prefix] ?? (prefix.isEmpty ? '' : null);
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
    writeKeptAttributes(_w, rowAttributesOf(row), declaredAbove: _scope);
    final PropertySet trPr = rowPropertySetOf(row);
    // A row read without a w:trPr writes one when a value was set: after
    // any w:tblPrEx, before everything else.
    bool pending = !rowPropertiesOf(row).isRead && !trPr.writesNothing;
    int cells = 0;
    for (final Object child in rowChildrenOf(row)) {
      if (pending && !_isTblPrEx(child)) {
        _propertySet(trPr, 'trPr');
        pending = false;
      }
      if (child is DocxTableCell) {
        _cell(child, '$path/tc[${cells++}]');
      } else if (child is PropertyContainer) {
        _propertySet(trPr, 'trPr');
      } else {
        (child as OpaqueXml).writeTo(_w, declaredAbove: _scope);
      }
    }
    if (pending) {
      _propertySet(trPr, 'trPr');
    }
    _w.end();
  }

  /// Whether [child] is a kept `w:tblPrEx`.
  bool _isTblPrEx(Object child) =>
      child is OpaqueXml &&
      child.localName == 'tblPrEx' &&
      child.namespaceUri == Ns.w;

  /// Writes [properties] as `w:<localName>`.
  void _propertySet(PropertySet properties, String localName) => properties
      .writeTo(_w, '$_p$localName', prefix: _prefix, declaredAbove: _scope);

  /// Writes the cell [cell] at the location [path], and the paragraph that
  /// closes it when it needs one.
  void _cell(DocxTableCell cell, String path) {
    _w.start('${_p}tc');
    writeKeptAttributes(_w, cellAttributesOf(cell), declaredAbove: _scope);
    final PropertySet tcPr = cellPropertySetOf(cell);
    if (!tcPr.writesNothing) {
      _propertySet(tcPr, 'tcPr');
    }
    _blocks(cell.blocks, path);
    if (cellNeedsClosingParagraph(cell)) {
      _w
        ..start('${_p}p')
        ..end();
    }
    _w.end();
  }

  /// Writes the paragraph [p] at the location [path].
  void _paragraph(DocxParagraph p, String path) {
    final XmlWriter w = _w;
    w.start('${_p}p');
    writeKeptAttributes(w, paragraphAttributesOf(p), declaredAbove: _scope);
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
      pPr.writeTo(w, '${_p}pPr', prefix: _prefix, declaredAbove: _scope);
    }
    int runs = 0;
    for (final DocxInline inline in p.inlines) {
      switch (inline) {
        case DocxRun():
          _run(inline, '$path/r[${runs++}]');
        case DocxOpaqueInline():
          opaqueInlineXml(inline).writeTo(w, declaredAbove: _scope);
      }
    }
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
    writeKeptAttributes(w, runAttributesOf(r), declaredAbove: _scope);
    final PropertySet rPr = runPropertySetOf(r);
    _checkStyle(rPr, 'rStyle', DocxStyleType.character, path);
    if (!rPr.writesNothing) {
      rPr.writeTo(w, '${_p}rPr', prefix: _prefix, declaredAbove: _scope);
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
          writeKeptAttributes(w, contentAttributesOf(c), declaredAbove: _scope);
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
        writeKeptAttributes(w, contentAttributesOf(c), declaredAbove: _scope);
        w.end();
      case DocxCarriageReturn():
        _empty('cr', c);
      case DocxOpaqueRunContent():
        opaqueRunContentXml(c).writeTo(w, declaredAbove: _scope);
    }
  }

  /// Writes `w:<localName>` with the attributes [c] kept and no content.
  void _empty(String localName, DocxRunContent c) {
    _w.start('$_p$localName');
    writeKeptAttributes(_w, contentAttributesOf(c), declaredAbove: _scope);
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

/// One read of a document part.
final class _PartReader {
  _PartReader(this._r, this._partName, this._maxTextLength, this._maxDepth);

  final XmlPullReader _r;
  final String _partName;
  final int _maxTextLength;
  final int _maxDepth;

  /// The body or cell of the paragraph being read, for errors.
  late _BlockReader _paragraphIn;

  /// How many tables are open around the element being read.
  int _tableNesting = 0;

  DocumentPart read() {
    final XmlPullReader r = _r;
    while (r.next()) {
      if (r.eventType == XmlEventType.startElement) break;
    }
    if (r.eventType != XmlEventType.startElement || !_isW(r, 'document')) {
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
    _children(r, () {
      if (!bodySeen && _isW(r, 'body')) {
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
    final XmlPullReader r = _r;
    final _BlockReader reader = _BlockReader('body', blocks);
    // A sectPr is final only if nothing follows it.
    OpaqueXml? sectPr;
    _children(r, () {
      if (sectPr != null) {
        blocks.add(opaqueBlock(sectPr!));
        sectPr = null;
      }
      if (_isW(r, 'sectPr')) {
        sectPr = OpaqueXml.capture(r);
      } else {
        _readBlock(reader);
      }
    });
    final OpaqueXml? last = sectPr;
    return last == null ? const PropertyContainer.empty() : _readSectPr(last);
  }

  /// Reads the `w:sectPr` [xml] captured as a container, under a root that
  /// declares the bindings it inherited, so its prefixes resolve as they did
  /// in the part.
  PropertyContainer _readSectPr(OpaqueXml xml) {
    final StringBuffer source = StringBuffer('<r');
    xml.inheritedNamespaces.forEach((String prefix, String uri) {
      source
        ..write(prefix.isEmpty ? ' xmlns="' : ' xmlns:$prefix="')
        ..write(escapeXmlAttribute(scrubXmlText(uri).text))
        ..write('"');
    });
    source
      ..write('>')
      ..write(xml.xml)
      ..write('</r>');
    final XmlPullReader r = XmlPullReader(
      source.toString(),
      maxDepth: _maxDepth + 1,
    );
    r.nextTag();
    r.nextTag();
    return PropertyContainer.read(r, sectionPropertiesSchema);
  }

  /// Reads the block the reader is on, a child of `w:body` or `w:tc`.
  void _readBlock(_BlockReader into) {
    final XmlPullReader r = _r;
    if (_isW(r, 'p')) {
      _paragraphIn = into;
      into.blocks.add(_readParagraph());
      into.paragraphs++;
    } else if (_isW(r, 'tbl')) {
      into.blocks.add(_readTable('${into.path}/tbl[${into.tables++}]'));
    } else {
      into.blocks.add(opaqueBlock(OpaqueXml.capture(r)));
    }
  }

  /// Reads the `w:tbl` the reader is on, at the location [path].
  DocxTable _readTable(String path) {
    if (_tableNesting == maxTableNesting) {
      throw DocxReadException(
        DocxReadFailure.limitExceeded,
        'Limit table nesting ($maxTableNesting) exceeded by $path.',
        part: _partName,
      );
    }
    _tableNesting++;
    final XmlPullReader r = _r;
    final List<KeptAttribute> attributes = List<KeptAttribute>.unmodifiable(
      keepAttributes(r),
    );
    PropertyContainer? properties;
    List<double?>? grid;
    final List<Object> children = <Object>[];
    int rows = 0;
    _children(r, () {
      if (_isW(r, 'tr')) {
        children.add(_readRow('$path/tr[${rows++}]'));
      } else if (rows == 0 && properties == null && _isW(r, 'tblPr')) {
        children.add(
          properties = PropertyContainer.read(r, tablePropertiesSchema),
        );
      } else if (rows == 0 && grid == null && _isW(r, 'tblGrid')) {
        final List<double?> columns = <double?>[];
        children.add(_captureGrid(columns));
        grid = List<double?>.unmodifiable(columns);
      } else {
        children.add(OpaqueXml.capture(r));
      }
    });
    _tableNesting--;
    return readTable(
      properties: properties ?? const PropertyContainer.empty(),
      attributes: attributes,
      gridColumnsPt: grid,
      children: children,
    );
  }

  /// Captures the `w:tblGrid` the reader is on, adding the width of each
  /// `w:gridCol` child to [columns] in the same walk, and keeping the text of
  /// each other child for a grid written with new widths.
  TableGrid _captureGrid(List<double?> columns) {
    final int depth = _r.depth;
    final Map<String, String> declared = <String, String>{};
    final List<String> kept = <String>[];
    int? keptStart;
    final OpaqueXml xml = OpaqueXml.capture(
      _r,
      onEvent: (XmlPullReader r) {
        if (r.eventType == XmlEventType.startElement) {
          if (r.depth == depth) {
            declared.addAll(r.declaredNamespaces);
          } else if (r.depth == depth + 1) {
            if (_isW(r, 'gridCol')) {
              final int? twips = parseDecimal(
                r.getAttribute('w', namespaceUri: Ns.w),
                min: 0,
                max: _maxGridColumnTwips,
              );
              columns.add(twips == null ? null : ptOfTwips(twips));
            } else if (r.isEmptyElement) {
              kept.add(r.sourceText(r.eventStart, r.eventEnd));
            } else {
              keptStart = r.eventStart;
            }
          }
        } else if (r.eventType == XmlEventType.endElement &&
            r.depth == depth &&
            keptStart != null) {
          kept.add(r.sourceText(keptStart!, r.eventEnd));
          keptStart = null;
        }
      },
    );
    return TableGrid(xml, Map<String, String>.unmodifiable(declared), kept);
  }

  /// Reads the `w:tr` the reader is on, at the location [path].
  DocxTableRow _readRow(String path) {
    final XmlPullReader r = _r;
    final List<KeptAttribute> attributes = List<KeptAttribute>.unmodifiable(
      keepAttributes(r),
    );
    PropertyContainer? properties;
    final List<Object> children = <Object>[];
    int cells = 0;
    _children(r, () {
      if (_isW(r, 'tc')) {
        children.add(_readCell('$path/tc[${cells++}]'));
      } else if (cells == 0 && properties == null && _isW(r, 'trPr')) {
        children.add(
          properties = PropertyContainer.read(r, tableRowPropertiesSchema),
        );
      } else {
        children.add(OpaqueXml.capture(r));
      }
    });
    return readTableRow(
      properties: properties ?? const PropertyContainer.empty(),
      attributes: attributes,
      children: children,
    );
  }

  /// Reads the `w:tc` the reader is on, at the location [path].
  ///
  /// Only a first child `w:tcPr` is the cell's properties: the writer puts
  /// them first, so one anywhere else stays a block, in place.
  DocxTableCell _readCell(String path) {
    final XmlPullReader r = _r;
    final List<KeptAttribute> attributes = List<KeptAttribute>.unmodifiable(
      keepAttributes(r),
    );
    PropertyContainer? properties;
    final List<DocxBlock> blocks = <DocxBlock>[];
    final _BlockReader reader = _BlockReader(path, blocks);
    _children(r, () {
      if (properties == null && blocks.isEmpty && _isW(r, 'tcPr')) {
        properties = PropertyContainer.read(r, tableCellPropertiesSchema);
      } else {
        _readBlock(reader);
      }
    });
    return readTableCell(
      properties: properties ?? const PropertyContainer.empty(),
      attributes: attributes,
      blocks: blocks,
    );
  }

  /// Reads the `w:p` the reader is on.
  DocxParagraph _readParagraph() {
    final XmlPullReader r = _r;
    final List<KeptAttribute> attributes = List<KeptAttribute>.unmodifiable(
      keepAttributes(r),
    );
    PropertyContainer? properties;
    final List<DocxInline> inlines = <DocxInline>[];
    _children(r, () {
      if (properties == null && _isW(r, 'pPr')) {
        properties = PropertyContainer.read(r, paragraphPropertiesSchema);
      } else if (_isW(r, 'r')) {
        inlines.add(_readRun());
      } else {
        inlines.add(_readOpaqueInline());
      }
    });
    return readParagraph(
      properties: properties ?? const PropertyContainer.empty(),
      attributes: attributes,
      inlines: inlines,
    );
  }

  /// Captures the inline the reader is on, collecting its visible text in
  /// the same walk.
  DocxOpaqueInline _readOpaqueInline() {
    final VisibleTextCollector text = VisibleTextCollector();
    final OpaqueXml xml = OpaqueXml.capture(
      _r,
      onEvent: (XmlPullReader r) {
        text.add(r);
        if (text.length > _maxTextLength) throw _tooLong();
      },
    );
    return opaqueInline(xml, text: text.text);
  }

  /// Reads the `w:r` the reader is on.
  DocxRun _readRun() {
    final XmlPullReader r = _r;
    final List<KeptAttribute> attributes = List<KeptAttribute>.unmodifiable(
      keepAttributes(r),
    );
    PropertyContainer? properties;
    final List<DocxRunContent> content = <DocxRunContent>[];
    _children(r, () {
      if (r.namespaceUri != Ns.w) {
        content.add(opaqueRunContent(OpaqueXml.capture(r)));
        return;
      }
      switch (r.localName) {
        case 'rPr' when properties == null:
          properties = PropertyContainer.read(r, runPropertiesSchema);
        case 't':
          final List<KeptAttribute> kept = keepAttributes(r);
          content.add(readText(_readText(), kept));
        case 'tab':
          content.add(readTab(keepAttributes(r)));
          r.skip();
        case 'br':
          content.add(_readBreak());
          r.skip();
        case 'cr':
          content.add(readCarriageReturn(keepAttributes(r)));
          r.skip();
        default:
          content.add(opaqueRunContent(OpaqueXml.capture(r)));
      }
    });
    return readRun(
      properties: properties ?? const PropertyContainer.empty(),
      attributes: attributes,
      content: content,
    );
  }

  /// The `w:br` the reader is on; the reader stays on it.
  ///
  /// `w:type` `page` and `column` are typed and not kept. Any other value,
  /// such as `textWrapping`, reads as a line break and is kept as written.
  DocxBreak _readBreak() {
    final XmlPullReader r = _r;
    final DocxBreakType type = switch (r.getAttribute(
      'type',
      namespaceUri: Ns.w,
    )) {
      'page' => DocxBreakType.page,
      'column' => DocxBreakType.column,
      _ => DocxBreakType.line,
    };
    List<KeptAttribute> kept = keepAttributes(r);
    if (type != DocxBreakType.line) {
      kept = <KeptAttribute>[
        for (final KeptAttribute a in kept)
          if (a.namespaceUri != Ns.w || !a.qualifiedName.endsWith(':type')) a,
      ];
    }
    return readBreak(type, kept);
  }

  /// The character data of the `w:t` the reader is on, entities and CDATA
  /// decoded and joined, leaving the reader on its end event. Child
  /// elements, which the schema does not allow, are skipped.
  String _readText() {
    final XmlPullReader r = _r;
    if (r.isEmptyElement) {
      r.next();
      return '';
    }
    final StringBuffer buffer = StringBuffer();
    final int depth = r.depth;
    while (r.next()) {
      final XmlEventType type = r.eventType;
      if (type == XmlEventType.endElement && r.depth < depth) break;
      if (type == XmlEventType.characters || type == XmlEventType.cdata) {
        buffer.write(r.text);
        if (buffer.length > _maxTextLength) throw _tooLong();
      } else if (type == XmlEventType.startElement) {
        r.skip();
      }
    }
    return buffer.toString();
  }

  /// The `limitExceeded` failure of a text in the paragraph being read,
  /// named as a warning names it (`body/p[i]`,
  /// `body/tbl[i]/tr[j]/tc[k]/p[m]`): other blocks do not shift the index.
  DocxReadException _tooLong() => DocxReadException(
    DocxReadFailure.limitExceeded,
    'Limit maxTextLength ($_maxTextLength) exceeded by '
    '${_paragraphIn.path}/p[${_paragraphIn.paragraphs}].',
    part: _partName,
  );
}

/// The blocks of a body or a cell being read, with the location of the
/// container and the count of each kind of block that has a location.
final class _BlockReader {
  _BlockReader(this.path, this.blocks);

  /// The location of the container, such as `body`.
  final String path;

  /// The blocks read so far.
  final List<DocxBlock> blocks;

  /// How many paragraphs were read.
  int paragraphs = 0;

  /// How many tables were read.
  int tables = 0;
}

/// Whether the element [r] is on is `w:<localName>`.
bool _isW(XmlPullReader r, String localName) =>
    r.namespaceUri == Ns.w && r.localName == localName;

/// Calls [onChild] with [r] on the start of each child element of the
/// element [r] is on; [onChild] must leave [r] on that child's end event.
/// Character data, comments and processing instructions between the
/// children are dropped. Leaves [r] on the element's end event.
void _children(XmlPullReader r, void Function() onChild) {
  if (r.isEmptyElement) {
    r.next();
    return;
  }
  final int depth = r.depth;
  while (r.next()) {
    final XmlEventType type = r.eventType;
    if (type == XmlEventType.endElement && r.depth < depth) return;
    if (type == XmlEventType.startElement) onChild();
  }
}
