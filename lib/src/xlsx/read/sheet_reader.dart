/// Walks the rows of one worksheet part and turns them into values.
///
/// Ported from quds_office_engine `lib/src/builders/xlsx_io.dart` at commit
/// 15c5d29: `XlsxGridReader._sheetRows` and `_readText`.
///
/// What changed: rows are yielded lazily, as typed cells in column order,
/// instead of filling a dense grid of strings; cells are decoded by
/// `decodeCell` (decision 0007) instead of inline; rows and
/// cells without `r`, references that do not match their row, duplicate
/// cells, rows out of order and cells outside the sheet are placed and
/// reported as warnings instead of being trusted; huge `r` values are never
/// parsed to an `int`; every `<v>` and `<f>` text is limited to
/// `maxTextLength`; elements match by local name and SpreadsheetML namespace
/// so prefixed producers work; a part that is not a `<worksheet>` reads as
/// no rows, and one in the Strict namespace is refused; and cells that come
/// out of column order are sorted once per row instead of inserted one by
/// one.
library;

import '../../opc/ooxml.dart';
import '../../xml/xml_pull_reader.dart';
import '../cell_ref.dart';
import '../limits.dart';
import '../warnings.dart';
import 'cell_decoder.dart';
import 'package_reader.dart';
import 'read_cell.dart';
import 'read_exception.dart';
import 'read_limits.dart';
import 'styles_reader.dart';

final RegExp _digits = RegExp(r'^[0-9]+$');

final RegExp _leadingZeros = RegExp('^0+');

/// What a reference outside the sheet may look like to be named in a
/// warning: letters and digits only, so the file cannot put arbitrary text
/// into a message.
final RegExp _outsideRef = RegExp(r'^\$?[A-Za-z]{1,4}\$?[0-9]{1,10}$');

/// The rows of the worksheet part [part] of [package], in file order.
///
/// Yields one [XlsxReadRow] per `<row>` of `<sheetData>` that holds at least
/// one cell with a `<v>`, `<f>` or `<is>`, or that is hidden. Problems with
/// single cells and rows are added to [warnings] under [sheet].
/// A cell gets at most one warning for its contents: `cellTypeUnsupported`
/// for an `<is>` when `t` is not `inlineStr` (its text is not read), else
/// `cellDuplicated` for a repeated `<v>`, `<f>` or `<is>` (the last is
/// kept), else the decoder's warning. A part whose root is not a
/// SpreadsheetML `<worksheet>` (a chartsheet, say), or that has no
/// `<sheetData>`, has no rows.
///
/// The part is opened when iteration starts and read as rows are taken, so
/// throws an [XlsxReadException] only then: `unsupportedFormat` for a root
/// in the Strict OOXML namespace, `malformedXml` for XML that cannot be read
/// and `limitExceeded` for a `<v>` or `<f>` text longer than
/// [XlsxReadLimits.maxTextLength]. [part] must exist in [package].
Iterable<XlsxReadRow> readSheetRows(
  PackageReader package,
  String part, {
  required String sheet,
  required List<String>? sharedStrings,
  required XlsxReadLimits limits,
  required WarningCollector warnings,
}) sync* {
  final _SheetWalker walker = package.guardXml(
    part,
    () => _SheetWalker(
      package.openXml(part),
      part,
      sheet,
      sharedStrings,
      limits,
      warnings,
    ),
  );
  while (true) {
    // Every read from the XML, `.text` included, runs inside the guard.
    final XlsxReadRow? row = package.guardXml(part, walker.nextRow);
    if (row == null) return;
    yield row;
  }
}

/// The position and data of one `<c>`, before it is decoded.
final class _RawCell {
  _RawCell(this.column, this.ref);

  /// The 0-based column; may be past the last column.
  final int column;

  /// The `r` attribute as written, or `null`.
  final String? ref;

  /// Whether `r` was absent, did not parse or named another row.
  bool refInvalid = false;

  String? value;
  String? formula;
  bool hasFormula = false;
  bool hasInline = false;

  /// Whether a `<v>`, `<f>` or `<is>` occurs more than once; the last one
  /// is kept.
  bool repeated = false;

  bool get hasData => value != null || hasFormula || hasInline;
}

/// The cells of one row as they are read, put in column order at the end.
///
/// Cells usually come in column order and are appended. The first one that
/// does not starts a column-to-position map, so a duplicate is still found
/// in constant time, and the row is sorted once when it ends: a row written
/// right to left costs O(n log n), not O(n²).
final class _RowCells {
  final List<XlsxReadCell> _cells = <XlsxReadCell>[];

  /// Column to position in [_cells], built at the first cell out of order.
  Map<int, int>? _positions;

  /// Adds [cell]; returns `false` when it replaced a cell already at its
  /// column (the last one wins).
  bool place(XlsxReadCell cell) {
    Map<int, int>? positions = _positions;
    if (positions == null) {
      if (_cells.isEmpty || _cells.last.column < cell.column) {
        _cells.add(cell);
        return true;
      }
      positions = _positions = <int, int>{
        for (int i = 0; i < _cells.length; i++) _cells[i].column: i,
      };
    }
    final int? at = positions[cell.column];
    if (at != null) {
      _cells[at] = cell;
      return false;
    }
    positions[cell.column] = _cells.length;
    _cells.add(cell);
    return true;
  }

  /// The cells in column order, one per column.
  List<XlsxReadCell> inColumnOrder() {
    if (_positions != null) {
      _cells.sort((XlsxReadCell a, XlsxReadCell b) => a.column - b.column);
    }
    return _cells;
  }
}

/// The state of one pass over a worksheet part.
final class _SheetWalker {
  _SheetWalker(
    this._reader,
    this._part,
    this._sheet,
    this._sharedStrings,
    this._limits,
    this._warnings,
  );

  final XmlPullReader _reader;
  final String _part;
  final String _sheet;
  final List<String>? _sharedStrings;
  final XlsxReadLimits _limits;
  final WarningCollector _warnings;

  bool _started = false;
  bool _done = false;

  /// The 0-based index of the previous `<row>`, capped at
  /// [XlsxLimits.maxRows] for a row past the last.
  int _previousRow = -1;

  /// The next row to yield, or `null` when the sheet has no more.
  XlsxReadRow? nextRow() {
    if (_done) return null;
    if (!_started) {
      _started = true;
      if (!_enterSheetData()) {
        _done = true;
        return null;
      }
    }
    while (_reader.next()) {
      if (_reader.eventType == XmlEventType.endElement && _reader.depth < 2) {
        break;
      }
      if (_reader.eventType != XmlEventType.startElement) continue;
      if (_reader.depth == 3 &&
          _reader.localName == 'row' &&
          _reader.namespaceUri == Ns.main) {
        final XlsxReadRow? row = _readRow();
        if (row != null) return row;
      } else {
        _reader.skip();
      }
    }
    _done = true;
    return null;
  }

  /// Moves the reader onto the start of a non-empty `<sheetData>` of a
  /// `<worksheet>` root; `false` when there is none.
  bool _enterSheetData() {
    while (_reader.next()) {
      if (_reader.eventType == XmlEventType.startElement) break;
    }
    if (_reader.eventType == XmlEventType.startElement &&
        _reader.namespaceUri == strictSpreadsheetNs) {
      throw strictUnsupported(part: _part);
    }
    if (_reader.eventType != XmlEventType.startElement ||
        _reader.localName != 'worksheet' ||
        _reader.namespaceUri != Ns.main ||
        _reader.isEmptyElement) {
      return false;
    }
    while (_reader.next()) {
      if (_reader.eventType == XmlEventType.endElement && _reader.depth < 1) {
        return false;
      }
      if (_reader.eventType != XmlEventType.startElement) continue;
      if (_reader.depth == 2 &&
          _reader.localName == 'sheetData' &&
          _reader.namespaceUri == Ns.main) {
        return !_reader.isEmptyElement;
      }
      _reader.skip();
    }
    return false;
  }

  /// Reads the `<row>` the reader is on, leaving it on the row's end.
  ///
  /// Returns `null` for a row that is not yielded: one without data that is
  /// not hidden, or one past the last row (its cells are reported).
  XlsxReadRow? _readRow() {
    final String? hiddenText = _reader.getAttribute('hidden', namespaceUri: '');
    final bool hidden = hiddenText == '1' || hiddenText == 'true';
    final ({int index, bool invalid}) position = _rowPosition(
      _reader.getAttribute('r', namespaceUri: ''),
    );
    final int index = position.index;
    final bool outOfOrder = index <= _previousRow;
    _previousRow = index;
    final bool inside = index < XlsxLimits.maxRows;
    bool pendingInvalid = position.invalid;

    final _RowCells cells = _RowCells();
    if (!_reader.isEmptyElement) {
      int previousColumn = -1;
      while (_reader.next()) {
        if (_reader.eventType == XmlEventType.endElement && _reader.depth < 3) {
          break;
        }
        if (_reader.eventType != XmlEventType.startElement) continue;
        if (_reader.depth != 4 ||
            _reader.localName != 'c' ||
            _reader.namespaceUri != Ns.main) {
          _reader.skip();
          continue;
        }
        final String? type = decodeCellType(_reader);
        final _RawCell raw = _readCell(index, previousColumn, inside);
        previousColumn = raw.column;
        if (!raw.hasData) continue;
        if (!inside || raw.column >= XlsxLimits.maxColumns) {
          _warn(XlsxWarningCode.cellOutsideSheet, _outsideName(raw.ref));
          continue;
        }
        final String name = cellRef(index, raw.column);
        if (raw.refInvalid || pendingInvalid) {
          _warn(XlsxWarningCode.cellReferenceInvalid, name);
        }
        pendingInvalid = false;
        final DecodedCell decoded = decodeCell(
          type: type,
          value: raw.value,
          formula: raw.formula,
          hasFormula: raw.hasFormula,
          inlineText: null,
          sharedStrings: _sharedStrings,
          format: CellFormat.general,
          date1904: false,
        );
        // The text of an `<is>` is not read yet, so an inline string cell
        // that has one stays unsupported, as in R1.
        final bool inlineUnread = raw.hasInline && type == 'inlineStr';
        // One warning per cell for its contents: an inline string the type
        // does not announce (its text is not read), then a repeated child,
        // then an unread inline string, then whatever the decoder found.
        final XlsxWarningCode? contentWarning =
            raw.hasInline && type != 'inlineStr'
            ? XlsxWarningCode.cellTypeUnsupported
            : raw.repeated
            ? XlsxWarningCode.cellDuplicated
            : inlineUnread
            ? XlsxWarningCode.cellTypeUnsupported
            : decoded.warning;
        if (contentWarning != null) _warn(contentWarning, name);
        if (!cells.place(
          XlsxReadCell(
            raw.column,
            inlineUnread ? null : decoded.value,
            formula: decoded.formula,
          ),
        )) {
          _warn(XlsxWarningCode.cellDuplicated, name);
        }
      }
    }
    final List<XlsxReadCell> ordered = cells.inColumnOrder();
    if (!inside || (ordered.isEmpty && !hidden)) return null;
    if (outOfOrder) {
      _warn(
        XlsxWarningCode.rowOutOfOrder,
        cellRef(index, ordered.isEmpty ? 0 : ordered.first.column),
      );
    }
    return XlsxReadRow(index, ordered, hidden: hidden);
  }

  /// The 0-based index of a row whose `r` is [r], and whether `r` was
  /// invalid (then the row follows the previous one).
  ///
  /// A row past the last row is [XlsxLimits.maxRows]; `r` is never parsed
  /// when it has more than 7 significant digits.
  ({int index, bool invalid}) _rowPosition(String? r) {
    final int next = _previousRow + 1;
    if (r == null) return (index: next, invalid: false);
    if (!_digits.hasMatch(r)) return (index: next, invalid: true);
    final String significant = r.replaceFirst(_leadingZeros, '');
    if (significant.isEmpty) return (index: next, invalid: true);
    if (significant.length > 7) {
      return (index: XlsxLimits.maxRows, invalid: false);
    }
    final int number = int.parse(significant);
    return (
      index: number > XlsxLimits.maxRows ? XlsxLimits.maxRows : number - 1,
      invalid: false,
    );
  }

  /// Reads the `<c>` the reader is on, in the row at [row], leaving the
  /// reader on its end. Texts are read only when [inside] the sheet.
  _RawCell _readCell(int row, int previousColumn, bool inside) {
    final String? ref = _reader.getAttribute('r', namespaceUri: '');
    final ({int row, int column})? parsed = ref == null
        ? null
        : matchCellRef(ref);
    final bool matches = parsed != null && parsed.row == row;
    final _RawCell raw = _RawCell(
      matches ? parsed.column : previousColumn + 1,
      ref,
    )..refInvalid = ref != null && !matches;
    if (_reader.isEmptyElement) return raw;
    final bool readText = inside && raw.column < XlsxLimits.maxColumns;
    while (_reader.next()) {
      if (_reader.eventType == XmlEventType.endElement && _reader.depth < 4) {
        break;
      }
      if (_reader.eventType != XmlEventType.startElement) continue;
      final bool child = _reader.depth == 5 && _reader.namespaceUri == Ns.main;
      switch (child ? _reader.localName : null) {
        case 'v':
          if (raw.value != null) raw.repeated = true;
          raw.value = _readText(row, raw.column, keep: readText);
        case 'f':
          if (raw.hasFormula) raw.repeated = true;
          raw.hasFormula = true;
          final String formula = _readText(row, raw.column, keep: readText);
          raw.formula = formula.isEmpty ? null : formula;
        case 'is':
          if (raw.hasInline) raw.repeated = true;
          raw.hasInline = true;
          _reader.skip();
        default:
          _reader.skip();
      }
    }
    return raw;
  }

  /// The character data of the element the reader is on, leaving the
  /// reader on its end. Throws when it passes `maxTextLength`.
  ///
  /// Unless [keep], the element is skipped unread and the result is `''`.
  String _readText(int row, int column, {required bool keep}) {
    if (!keep || _reader.isEmptyElement) {
      _reader.skip();
      return '';
    }
    final StringBuffer buffer = StringBuffer();
    final int depth = _reader.depth;
    while (_reader.next()) {
      if (_reader.eventType == XmlEventType.endElement &&
          _reader.depth < depth) {
        break;
      }
      if (_reader.eventType == XmlEventType.characters ||
          _reader.eventType == XmlEventType.cdata) {
        buffer.write(_reader.text);
        if (buffer.length > _limits.maxTextLength) {
          throw XlsxReadException(
            XlsxReadFailure.limitExceeded,
            'Limit maxTextLength (${_limits.maxTextLength}) exceeded by '
            'cell ${cellRef(row, column)}.',
            part: _part,
          );
        }
      } else if (_reader.eventType == XmlEventType.startElement) {
        _reader.skip();
      }
    }
    return buffer.toString();
  }

  void _warn(XlsxWarningCode code, String? cell) =>
      _warnings.add(code, sheet: _sheet, cell: cell);

  /// The name of a cell outside the sheet: its `r`, upper-cased without
  /// `$`, when that looks like a reference; otherwise `null`.
  static String? _outsideName(String? ref) {
    if (ref == null || !_outsideRef.hasMatch(ref)) return null;
    return ref.replaceAll(r'$', '').toUpperCase();
  }
}
