/// A worksheet part of an XLSX package: its cells in a [CellStore], its
/// `<dimension>` recomputed, everything else kept as written.
///
/// Not ported from Quds; written for jet_office.
///
/// A loaded part is always written from this model (spec §4.3). The rows of
/// the first `<sheetData>` are read by [RawRowReader] with extras kept, so
/// the store holds what the file stores: values, styles, formulas, inline
/// strings, styled empty cells, the attributes of rows and cells, and the
/// children of a row other than its cells (an `extLst`, written after the
/// cells). Children of `<sheetData>` other than rows, which the schema does
/// not allow, are kept too but written after the last row, so their position
/// among the rows is not kept. Every
/// other child of `<worksheet>` (`sheetPr`, `sheetViews`, `cols`,
/// `mergeCells`, `hyperlinks`, `pageMargins`, `extLst`, ...) is an
/// [OpaqueXml] at its original position, and the root keeps its namespace
/// declarations and `mc:Ignorable`.
///
/// Saving recomputes the bookkeeping (spec §4.4): `<dimension ref>` from the
/// store's bounds (`A1` without cells), and each row's `spans` as the first
/// and last 1-based column of its cells (none on a row without cells).
/// Each row gets its `r`; cells are written by [CellEncoder.writeRaw], the
/// one writer of cell elements (decision 0002).
///
/// Only the first `<dimension>` and the first `<sheetData>` are typed; a
/// repeated one is kept opaque, as the reader reads only the first sheet
/// data. A part without `<sheetData>` gets one in schema position; a part
/// without `<dimension>` gets none, since the element is optional. A part
/// with no root element, or whose root is not a SpreadsheetML `<worksheet>`
/// (a chartsheet, say), is *untyped*, as the reader reads such a part as no
/// rows: it is written back unchanged.
library;

import 'dart:typed_data';

import '../../opc/ooxml.dart';
import '../../opc/opaque_xml.dart';
import '../../opc/package.dart';
import '../../xml/utf8_buffer.dart';
import '../../xml/xml_pull_reader.dart';
import '../../xml/xml_writer.dart';
import '../cell_encoder.dart';
import '../cell_ref.dart';
import '../raw_cell.dart';
import '../read/package_reader.dart'
    show strictSpreadsheetNs, strictUnsupported;
import '../read/read_exception.dart';
import '../read/read_limits.dart';
import '../read/sheet_reader.dart' show RawRow, RawRowReader;
import '../warnings.dart';
import 'cell_store.dart';

/// The children of `<worksheet>` in the order of the schema's
/// `CT_Worksheet` sequence.
const List<String> worksheetChildOrder = <String>[
  'sheetPr',
  'dimension',
  'sheetViews',
  'sheetFormatPr',
  'cols',
  'sheetData',
  'sheetCalcPr',
  'sheetProtection',
  'protectedRanges',
  'scenarios',
  'autoFilter',
  'sortState',
  'dataConsolidate',
  'customSheetViews',
  'mergeCells',
  'phoneticPr',
  'conditionalFormatting',
  'dataValidations',
  'hyperlinks',
  'printOptions',
  'pageMargins',
  'pageSetup',
  'headerFooter',
  'rowBreaks',
  'colBreaks',
  'customProperties',
  'cellWatches',
  'ignoredErrors',
  'smartTags',
  'drawing',
  'legacyDrawing',
  'legacyDrawingHF',
  'drawingHF',
  'picture',
  'oleObjects',
  'controls',
  'webPublishItems',
  'tableParts',
  'extLst',
];

/// The typed `<dimension>`: its `ref` is recomputed on save.
final class _Dimension {
  _Dimension(this.qualifiedName, this.namespaces, this.attributes);

  final String qualifiedName;
  final Map<String, String> namespaces;

  /// The attributes but `ref`, as written.
  final List<KeptAttribute> attributes;

  void writeTo(XmlWriter w, Map<String, String> above, String ref) {
    w.start(qualifiedName);
    writeNamespaceDeclarations(w, namespaces);
    w.attribute('ref', ref);
    writeKeptAttributes(
      w,
      attributes,
      declaredAbove: mergeNamespaces(above, namespaces),
    );
    w.end();
  }
}

/// The typed `<sheetData>`: its element name, declarations and attributes;
/// the rows live in the part's [CellStore].
final class _SheetData {
  _SheetData(this.qualifiedName, this.namespaces, this.attributes);

  final String qualifiedName;
  final Map<String, String> namespaces;
  final List<KeptAttribute> attributes;

  /// The children other than rows, in source order. The schema allows
  /// none; they are kept so nothing is lost, and written after the rows.
  List<OpaqueXml> extraChildren = const <OpaqueXml>[];
}

/// A worksheet part: its cells in a [CellStore], the rest kept as written.
final class WorksheetPart implements PartContent {
  WorksheetPart._typed(XmlRoot this._root, this._children)
    : _untypedText = null;

  WorksheetPart._untyped(this._untypedText)
    : _root = null,
      _children = <Object>[];

  /// Reads a worksheet part from [r], which must not have been advanced.
  ///
  /// [part] names the part in warnings and errors. Problems with rows and
  /// cells go to [warn] as `readSheetRows` documents them: a misplaced or
  /// duplicate cell, a row out of order, a cell outside the sheet (dropped).
  /// Rows are stored in row order whatever their order in the file.
  ///
  /// A part with no root element, or whose root is not a SpreadsheetML
  /// `<worksheet>`, is untyped: [cells] starts empty and [encode] writes the
  /// text unchanged.
  ///
  /// Throws an [XlsxReadException] of reason `unsupportedFormat` for a Strict
  /// root and `limitExceeded` for a `<v>`, `<f>` or inline text longer than
  /// [XlsxReadLimits.maxTextLength]. An `XmlParseException` passes through.
  factory WorksheetPart.read(
    XmlPullReader r, {
    required String part,
    required XlsxReadLimits limits,
    required void Function(XlsxWarningCode code, String? cell, {String? detail})
    warn,
  }) {
    while (r.next()) {
      if (r.eventType == XmlEventType.startElement) break;
    }
    if (r.eventType != XmlEventType.startElement) {
      return WorksheetPart._untyped(r.sourceText(0, r.sourceLength));
    }
    if (r.namespaceUri == strictSpreadsheetNs) {
      throw strictUnsupported(part: part);
    }
    if (r.localName != 'worksheet' || r.namespaceUri != Ns.main) {
      return WorksheetPart._untyped(r.sourceText(0, r.sourceLength));
    }
    final WorksheetPart sheet = WorksheetPart._typed(
      XmlRoot.capture(r),
      <Object>[],
    );
    final List<Object> children = sheet._children;
    final int rootDepth = r.depth;
    while (r.next()) {
      if (r.eventType == XmlEventType.endElement && r.depth < rootDepth) {
        break;
      }
      if (r.eventType != XmlEventType.startElement) continue;
      final bool main = r.namespaceUri == Ns.main;
      if (main && r.localName == 'dimension' && sheet._dimension == null) {
        final _Dimension d = _Dimension(
          r.qualifiedName,
          Map<String, String>.of(r.declaredNamespaces),
          keepAttributes(r, except: const <String>{'ref'}),
        );
        r.skip();
        sheet._dimension = d;
        children.add(d);
      } else if (main &&
          r.localName == 'sheetData' &&
          sheet._sheetData == null) {
        final _SheetData data = _SheetData(
          r.qualifiedName,
          Map<String, String>.of(r.declaredNamespaces),
          keepAttributes(r),
        );
        sheet._sheetData = data;
        children.add(data);
        sheet._readRows(r, part, limits, warn);
      } else {
        children.add(OpaqueXml.capture(r));
      }
    }
    if (sheet._sheetData == null) sheet._insertSheetData();
    return sheet;
  }

  /// A new worksheet: a root declaring the SpreadsheetML and relationships
  /// namespaces, as the writer's, with `<dimension ref="A1"/>` and an empty
  /// `<sheetData>`.
  factory WorksheetPart.empty() {
    final XmlPullReader r = XmlPullReader(
      '<worksheet xmlns="${Ns.main}" xmlns:r="${Ns.rel}"/>',
    )..next();
    final _Dimension d = _Dimension(
      'dimension',
      const <String, String>{},
      const <KeptAttribute>[],
    );
    final WorksheetPart sheet = WorksheetPart._typed(
      XmlRoot.capture(r),
      <Object>[d],
    ).._dimension = d;
    sheet._insertSheetData();
    return sheet;
  }

  /// The text of an untyped part; `null` for a typed one.
  final String? _untypedText;
  final XmlRoot? _root;

  /// [_Dimension], [_SheetData] and [OpaqueXml] children, in order.
  final List<Object> _children;
  _Dimension? _dimension;
  _SheetData? _sheetData;
  CellEncoder? _encoder;

  /// The cells and row attributes of the sheet.
  ///
  /// For an untyped part the store stays empty; [encode] throws a
  /// [StateError] when anything was put in it, as there is no sheet data to
  /// write it to.
  final CellStore cells = CellStore();

  /// Sets the encoder that writes the cells; [encode] needs one.
  void bindEncoder(CellEncoder encoder) {
    _encoder = encoder;
  }

  void _readRows(
    XmlPullReader r,
    String part,
    XlsxReadLimits limits,
    void Function(XlsxWarningCode code, String? cell, {String? detail}) warn,
  ) {
    final RawRowReader rows = RawRowReader(
      r,
      part: part,
      keepExtras: true,
      limits: limits,
      warn: warn,
    );
    for (RawRow? row = rows.next(); row != null; row = rows.next()) {
      for (int i = 0; i < row.cells.length; i++) {
        cells.put(row.index, row.columns[i], row.cells[i]);
      }
      if (row.attributes.isNotEmpty) {
        cells.setRowAttributes(row.index, row.attributes);
      }
      if (row.extraChildren.isNotEmpty) {
        cells.setRowChildren(row.index, row.extraChildren);
      }
    }
    _sheetData!.extraChildren = rows.extraChildren;
  }

  void _insertSheetData() {
    final _SheetData data = _SheetData(
      '${_prefixOf(_root!.qualifiedName)}sheetData',
      const <String, String>{},
      const <KeptAttribute>[],
    );
    _sheetData = data;
    _children.insert(_positionFor('sheetData'), data);
  }

  /// The index in [_children] before the first element that follows [name]
  /// in [worksheetChildOrder], or the end.
  int _positionFor(String name) {
    final Set<String> after = worksheetChildOrder
        .skip(worksheetChildOrder.indexOf(name) + 1)
        .toSet();
    for (var i = 0; i < _children.length; i++) {
      final Object c = _children[i];
      if (c is _Dimension && after.contains('dimension') ||
          c is OpaqueXml &&
              c.namespaceUri == Ns.main &&
              after.contains(c.localName)) {
        return i;
      }
    }
    return _children.length;
  }

  /// Writes the part.
  ///
  /// Throws a [StateError] when no encoder is bound, or when cells were put
  /// in an untyped part.
  @override
  List<Uint8List> encode() {
    final Utf8Buffer buffer = Utf8Buffer();
    final String? untyped = _untypedText;
    if (untyped != null) {
      if (cells.rowIndexes.isNotEmpty) {
        throw StateError(
          'The worksheet part is not a SpreadsheetML worksheet; its cells '
          'cannot be written.',
        );
      }
      return (buffer..write(untyped)).takeChunks();
    }
    final CellEncoder? encoder = _encoder;
    if (encoder == null) {
      throw StateError('bindEncoder must be called before encode.');
    }
    final XmlWriter w = XmlWriter(buffer)..declaration();
    final XmlRoot root = _root!;
    root.writeStart(w);
    for (final Object c in _children) {
      switch (c) {
        case _Dimension():
          c.writeTo(w, root.namespaces, _dimensionRef());
        case _SheetData():
          _writeSheetData(w, c, root.namespaces, encoder);
        case OpaqueXml():
          c.writeTo(w, declaredAbove: root.namespaces);
      }
    }
    w.end();
    return buffer.takeChunks();
  }

  String _dimensionRef() {
    final ({int firstRow, int lastRow, int firstColumn, int lastColumn})? b =
        cells.bounds;
    if (b == null) return 'A1';
    final String first = cellRef(b.firstRow, b.firstColumn);
    if (b.firstRow == b.lastRow && b.firstColumn == b.lastColumn) {
      return first;
    }
    return '$first:${cellRef(b.lastRow, b.lastColumn)}';
  }

  /// Writes `<sheetData>` and its rows. Rows and cells are written without a
  /// prefix, so the SpreadsheetML namespace is declared as the default on
  /// `<sheetData>` when it is not the default there already.
  void _writeSheetData(
    XmlWriter w,
    _SheetData data,
    Map<String, String> above,
    CellEncoder encoder,
  ) {
    final Map<String, String> declared = <String, String>{...data.namespaces};
    if (mergeNamespaces(above, declared)[''] != Ns.main) {
      declared[''] = Ns.main;
    }
    final Map<String, String> inner = mergeNamespaces(above, declared);
    w.start(data.qualifiedName);
    writeNamespaceDeclarations(w, declared);
    writeKeptAttributes(w, data.attributes, declaredAbove: inner);
    final List<int> columns = <int>[];
    final List<RawCell> rowCells = <RawCell>[];
    for (final int row in cells.rowIndexes) {
      columns.clear();
      rowCells.clear();
      cells.forEachInRow(row, (int column, RawCell cell) {
        columns.add(column);
        rowCells.add(cell);
      });
      w
        ..start('row')
        ..attribute('r', '${row + 1}');
      if (columns.isNotEmpty) {
        w.attribute('spans', '${columns.first + 1}:${columns.last + 1}');
      }
      writeKeptAttributes(w, cells.rowAttributes(row), declaredAbove: inner);
      for (int i = 0; i < columns.length; i++) {
        encoder.writeRaw(
          w,
          row: row,
          column: columns[i],
          cell: rowCells[i],
          declaredAbove: inner,
        );
      }
      for (final OpaqueXml child in cells.rowChildren(row)) {
        child.writeTo(w, declaredAbove: inner);
      }
      w.end();
    }
    for (final OpaqueXml child in data.extraChildren) {
      child.writeTo(w, declaredAbove: inner);
    }
    w.end();
  }
}

String _prefixOf(String qualifiedName) {
  final int colon = qualifiedName.indexOf(':');
  return colon < 0 ? '' : qualifiedName.substring(0, colon + 1);
}
