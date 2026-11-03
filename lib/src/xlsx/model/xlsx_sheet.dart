/// One sheet of an [XlsxWorkbook]: its cells read as the reader reads them
/// and set with the writer's values.
///
/// Not ported from Quds; written for jet_office.
///
/// A sheet loads its worksheet part on first use (spec §4.5): `open` reads
/// none, and the first [XlsxSheet.cellAt], [XlsxSheet.rows] or
/// [XlsxSheet.setCell] reads the whole part into a `CellStore`, together with
/// the workbook's shared strings and styles. A part that turns out broken
/// then throws an [XlsxReadException] naming it (spec §4.12), and nothing is
/// kept, so a later call tries again; a broken sheet that is never touched is
/// saved from its bytes.
///
/// Views are built on access from what the store holds, by the decoder's
/// typed step, so a value reads back exactly as [XlsxReader] reads it from
/// the saved file. [XlsxSheet.setCell] turns a value into the stored form
/// with `CellEncoder.prepare`, the encoder's checks, repairs and warnings
/// included, and stores it with the set-cell primitive in one transaction of
/// the workbook's change log.
///
/// @docImport '../read/xlsx_reader.dart';
/// @docImport 'xlsx_workbook.dart';
library;

import '../../opc/change_log.dart';
import '../../opc/ooxml.dart';
import '../../opc/opaque_xml.dart';
import '../../xml/xml_escape.dart';
import '../../xml/xml_number.dart';
import '../cell_encoder.dart';
import '../cell_ref.dart';
import '../column.dart';
import '../date_serial.dart';
import '../format/format_kind.dart';
import '../hyperlink.dart';
import '../limits.dart';
import '../number_format.dart';
import '../range.dart';
import '../raw_cell.dart';
import '../read/cell_decoder.dart';
import '../read/formula_groups.dart';
import '../read/package_reader.dart';
import '../read/read_cell.dart';
import '../read/read_exception.dart';
import '../read/styles_reader.dart';
import '../rich_text.dart';
import '../row_format.dart';
import '../sheet_view.dart';
import '../style.dart';
import '../values.dart';
import '../warnings.dart';
import '../worksheet_parts.dart'
    show
        checkColumnWidth,
        checkOutlineLevel,
        checkRowHeight,
        standardColumnWidth,
        standardRowHeight;
import 'cell_store.dart';
import 'columns.dart';
import 'primitives.dart';
import 'styles_part.dart';
import 'table_part.dart';
import 'workbook_part.dart';
import 'worksheet_part.dart';

/// What a sheet needs from its workbook.
abstract interface class SheetHost {
  /// The change log every edit records in.
  ChangeLog get log;

  /// The workbook's warnings: open, edit and save.
  WarningCollector get warnings;

  /// Whether the workbook counts dates from 1904.
  bool get date1904;

  /// The opened package, for reading parts.
  PackageReader get reader;

  /// Loads the shared strings and styles, once, and returns the encoder that
  /// prepares and writes cells. Throws an [XlsxReadException] when either
  /// part cannot be read; nothing is kept then.
  CellEncoder loadTables();

  /// The cell formats by style index; [loadTables] must have run.
  StyleTable get styleTable;

  /// The styles part, or `null` when the workbook has none; [loadTables]
  /// must have run.
  StylesPart? get styles;

  /// The styles part to append to: the workbook's, or, when it has none,
  /// the writer's empty styles, which join the package on save only once
  /// something was appended to them.
  StylesPart stylesForEdit();

  /// The shared strings by index, for decoding, or `null` when the workbook
  /// has none; [loadTables] must have run.
  List<String>? get sharedStringTexts;

  /// The style index for a date set on a cell of [style] in General: the
  /// writer's date-time format (id 22) with [withTime], else its short-date
  /// format (id 14); `null` when the styles part cannot take one (it is
  /// untyped).
  int? dateStyle(int? style, {required bool withTime});
}

/// A sheet of [host] listed as [entry], whose worksheet part is [partName]
/// (absolute; `null` when the file lacks it), already loaded as [part] for a
/// new sheet.
XlsxSheet newSheet(
  SheetHost host,
  SheetEntry entry,
  String? partName, {
  WorksheetPart? part,
}) => XlsxSheet._(host, entry, partName, part);

/// Whether [sheet]'s worksheet part is loaded.
bool isLoadedSheet(XlsxSheet sheet) => sheet._part != null;

/// Whether [sheet] has a worksheet part in the file.
bool sheetHasPart(XlsxSheet sheet) => sheet._partName != null;

/// The cells of [sheet], or `null` while its part is not loaded.
CellStore? cellStoreOf(XlsxSheet sheet) => sheet._part?.cells;

/// The number of cells of [sheet] whose reading problem was reported, for
/// tests: a cell read without a problem is not remembered.
int reportedCellCount(XlsxSheet sheet) => sheet._reported.length;

/// One sheet of a workbook, opened or created.
///
/// Rows and columns are 0-based: row 0 is Excel's row 1 and column 0 is
/// `A`.
final class XlsxSheet {
  XlsxSheet._(this._host, this._entry, this._partName, this._part);

  final SheetHost _host;
  final SheetEntry _entry;
  final String? _partName;
  WorksheetPart? _part;

  /// The positions (`row * XlsxLimits.maxColumns + column`) of the cells
  /// whose reading problem was reported, so a problem is reported once
  /// however often [rows] runs; a set cell is read afresh. A cell read
  /// without a problem is not added, so reading costs no entry per cell.
  final Set<int> _reported = <int>{};

  /// The layout problems reported (`layoutInvalid`), by detail, so a
  /// problem is reported once however often its element is read.
  final Set<String> _layoutReported = <String>{};

  /// The tables of the sheet the model can type, read on the first
  /// [setCell]; `null` until then.
  List<({String partName, TablePart table})>? _tables;

  /// The sheet's name, as the workbook lists it.
  String get name => _entry.name;

  /// Whether the sheet is visible, hidden or very hidden.
  XlsxSheetVisibility get visibility => _entry.visibility;

  /// The cell at [row] and [column] as [XlsxReader] reads it, or `null`
  /// when the cell holds no value, formula or inline string (an empty
  /// styled cell included).
  ///
  /// A formula cell carries its [XlsxFormulaGroup], found from the sheet's
  /// group masters; on a sheet whose formula groups are malformed (an
  /// overlap, a follower outside its master's range) it may differ from the
  /// group [rows] gives, which follows the reader's pass over the rows. A
  /// value that cannot be read exactly is reported in the workbook's
  /// warnings once, shared with [rows]. Loads the sheet. Throws a
  /// [RangeError] outside Excel's grid and an [XlsxReadException] when the
  /// sheet cannot be read.
  XlsxReadCell? cellAt(int row, int column) {
    _checkCell(row, column);
    final CellStore? store = _load()?.cells;
    if (store == null) return null;
    final RawCell? cell = store.cellAt(row, column);
    if (cell == null || !_hasData(cell)) return null;
    return _view(row, column, cell, _indexedGroup(store, row, column, cell));
  }

  /// The rows that hold a cell with data or are hidden, in row order, as
  /// [XlsxReader.rows] returns them for the saved file.
  ///
  /// Loads the sheet when called, so it throws an [XlsxReadException] then
  /// for a sheet that cannot be read. The rows are built as they are taken;
  /// changing the sheet while iterating is not supported. A value that
  /// cannot be read exactly is reported in the workbook's warnings once,
  /// however often the rows are read, and again after it is set.
  Iterable<XlsxReadRow> get rows {
    final CellStore? store = _load()?.cells;
    return store == null ? const <XlsxReadRow>[] : _rows(store);
  }

  /// Sets the cell at [row] and [column] to [value].
  ///
  /// [value] is a `String`, `int`, `double`, `bool`, `DateTime`,
  /// [XlsxDate], [XlsxDecimal], [XlsxFormula] or `null`. It is checked,
  /// repaired and reported as the writer does (`CellEncoder`), when it is
  /// set: text with characters XML forbids is cleaned with a warning, and a
  /// `NaN` throws now, so saving cannot fail on data. The cell keeps its
  /// style, except that a date in a General cell takes the writer's date
  /// format (appended to the styles), and its other attributes, which
  /// described the old value, are dropped. `null` clears the value: a styled
  /// cell stays as an empty styled cell, an unstyled one is removed.
  ///
  /// A table's header cell holds its column's name, which Excel requires to
  /// equal the cell's text, so setting it renames the column too
  /// (`tableColumnRenamed`; formulas that use the old name are not
  /// updated). It takes only text: an empty text or `null` becomes
  /// `ColumnN` (N the column's place in the table), and a name another
  /// column has, ignoring case, gets a number appended, as Excel does
  /// (`tableHeaderAdjusted`). Any other value throws a [StateError], and
  /// text of more than 255 characters an [ArgumentError].
  ///
  /// An [XlsxCell] sets its value as above and gives the cell the style the
  /// writer gives it: the row's style (when the row has
  /// `customFormat="1"`) with the [XlsxCell]'s style laid over it by
  /// [XlsxStyle.merge], appended to the styles when no cell format matches
  /// it; the cell's old style is not kept. A date takes the writer's date
  /// format when that style sets no number format, and keeps any format it
  /// sets (warning `dateInNonDateFormat` when it shows no date). An
  /// [XlsxCell] of `null` leaves an empty cell of that style, or no cell
  /// when it has no style or its style is the default, as the writer does.
  ///
  /// A shared formula's follower may be set and leaves its group. Throws a
  /// [StateError] for a cell inside an array or data-table formula (Excel
  /// refuses that too), for a sheet that is not a worksheet or has no part,
  /// and for an [XlsxCell] when the styles part is not a SpreadsheetML
  /// `styleSheet`, an [UnsupportedError] for a shared formula's master (W5)
  /// and for [XlsxHyperlink] (W3) and [XlsxRichText] (W4) values, also
  /// inside an [XlsxCell], an [ArgumentError] for any other type, a nested
  /// [XlsxCell], a value the encoder refuses or an invalid style (named by
  /// its field; an `XlsxLimitError` past the writer's limits), a
  /// [RangeError] outside Excel's grid, and an [XlsxReadException] when the
  /// sheet cannot be read. Whatever it throws, nothing has changed, except
  /// that reading warnings (such as `styleEntryInvalid` for a style entry
  /// read for the first time) are reported on first read.
  void setCell(int row, int column, Object? value) {
    _checkCell(row, column);
    // Programmer errors first, so they throw whatever the sheet holds.
    final bool styled = value is XlsxCell;
    final XlsxStyle? cellStyle = value is XlsxCell ? value.style : null;
    final Object? plain = value is XlsxCell ? value.value : value;
    switch (plain) {
      case XlsxHyperlink():
        throw UnsupportedError('XlsxHyperlink cells arrive in W3.');
      case XlsxRichText():
        throw UnsupportedError('XlsxRichText cells arrive in W4.');
      case XlsxCell():
        throw ArgumentError(
          'Cell ${cellRef(row, column)} on sheet "$name" nests an XlsxCell '
          'inside an XlsxCell.',
        );
      case null ||
          String() ||
          num() ||
          bool() ||
          DateTime() ||
          XlsxDate() ||
          XlsxDecimal() ||
          XlsxFormula():
        break;
      default:
        throw ArgumentError(
          'Cell ${cellRef(row, column)} on sheet "$name" holds a '
          '${plain.runtimeType}, which is not a supported cell value.',
        );
    }
    final CellStore store = _editableCells('cells');
    switch (groupRoleAt(store, row, column)) {
      case GroupRole.arrayOrTableMember:
        throw StateError(
          'Cannot change part of an array or data table formula at '
          '${cellRef(row, column)}.',
        );
      case GroupRole.sharedMaster:
        throw UnsupportedError(
          'Changing a shared formula master arrives in W5.',
        );
      case GroupRole.sharedChild || GroupRole.none:
        break;
    }
    Object? stored = plain;
    final ({String partName, TablePart table, int index})? header = _headerAt(
      row,
      column,
    );
    String? rename;
    bool adjusted = false;
    if (header != null) {
      final String text = switch (plain) {
        null => '',
        final String text => scrubXmlText(text).text,
        _ => throw StateError(
          'Cell ${cellRef(row, column)} on sheet "$name" is a header cell of '
          'the table "${header.table.displayName}"; it holds the column name '
          'and takes only text.',
        ),
      };
      // Excel's limit for a table column name.
      if (text.length > 255) {
        throw ArgumentError(
          'Cell ${cellRef(row, column)} on sheet "$name" is a header cell of '
          'the table "${header.table.displayName}"; a column name has at most '
          '255 characters.',
        );
      }
      final String unique = _uniqueColumnName(
        header.table,
        header.index,
        text.isEmpty ? 'Column${header.index + 1}' : text,
      );
      adjusted = unique != text;
      stored = unique;
      if (unique != header.table.columnName(header.index)) rename = unique;
    }
    final RawCell? current = store.cellAt(row, column);
    if (stored == null && current == null && cellStyle == null) return;
    final CellEncoder encoder = _host.loadTables();
    // The writer's layers, column under row under cell, and the style the
    // cell takes:
    // none for an XlsxCell of null without a style, as the writer; the
    // date format for a date that sets none. Without a style the styles
    // part is not needed.
    final XlsxStyle? layered = styled
        ? _layer(
            _columnLayer(store, row, column),
            _rowStyle(store, row),
            cellStyle,
          )
        : null;
    final XlsxStyle? target = !styled
        ? null
        : stored == null
        ? (cellStyle == null ? null : layered)
        : _withDateFormat(layered, stored);
    final StylesPart? styles = target == null ? null : _stylesFor();
    final ChangeLog log = _host.log;
    log.transaction(() {
      if (header != null && rename != null) {
        renameTableColumn(log, header.table, header.index, rename);
        _host.reader.package.setContent(header.partName, header.table);
      }
      RawCell? base = current;
      int? Function(int? style, {required bool withTime}) dateStyle =
          _host.dateStyle;
      if (styled) {
        final int id = styles == null ? 0 : appendStyle(log, styles, target);
        if (stored == null) {
          // As the writer: an XlsxCell of null writes an empty cell of the
          // layered style, or nothing when that is the default or the
          // XlsxCell has no style.
          setStoredCell(
            log,
            store,
            row,
            column,
            id == 0 ? null : RawCell(kind: RawCellKind.number, style: id),
          );
          return;
        }
        base = RawCell(kind: RawCellKind.number, style: id == 0 ? null : id);
        // The date format is in the style already, or the layers set a
        // format, which a date keeps as in the writer.
        dateStyle = (int? style, {required bool withTime}) => null;
      }
      final RawCell prepared = encoder.prepare(
        stored,
        sheet: name,
        row: row,
        column: column,
        current: base,
        currentFormat: _host.styleTable.formatOf(_styleText(base)),
        date1904: _host.date1904,
        dateStyle: dateStyle,
      );
      final bool remove = stored == null && prepared.style == null;
      setStoredCell(log, store, row, column, remove ? null : prepared);
    });
    _reported.remove(row * XlsxLimits.maxColumns + column);
    if (rename != null) {
      _warn(XlsxWarningCode.tableColumnRenamed, cellRef(row, column));
    }
    if (adjusted) {
      _warn(XlsxWarningCode.tableHeaderAdjusted, cellRef(row, column));
    }
  }

  /// The style Excel shows at [row] and [column], or `null` for the
  /// default.
  ///
  /// It is the cell's own style when the cell exists (even without a
  /// value), else the row's style when the row has `customFormat="1"`, else
  /// the style of the `<col>` holding the column; style index 0, and an index with no cell format in the styles part
  /// (which Excel shows as the default), give `null` in both. Read with
  /// [StylesPart.styleOf], so a part of the cell format the value types
  /// cannot hold is left out. A style entry read for the first time that
  /// cannot be read exactly is reported then (`styleEntryInvalid`).
  /// Loads the sheet. Throws a [RangeError] outside Excel's grid and an
  /// [XlsxReadException] when the sheet cannot be read.
  XlsxStyle? styleAt(int row, int column) {
    _checkCell(row, column);
    final CellStore? store = _load()?.cells;
    if (store == null) return null;
    final RawCell? cell = store.cellAt(row, column);
    if (cell != null) return _styleOfIndex(cell.style);
    final int? rowIndex = _rowStyleIndex(store, row);
    return _styleOfIndex(rowIndex ?? _columnStyleIndex(column));
  }

  /// The style at cell format [index], or `null` for no index, index 0 and
  /// an index with no cell format (which Excel shows as the default).
  XlsxStyle? _styleOfIndex(int? index) {
    final StylesPart? styles = _host.styles;
    if (index == null ||
        index == 0 ||
        styles == null ||
        index >= styles.cellFormatCount) {
      return null;
    }
    return styles.styleOf(index);
  }

  /// Sets the style of the cell at [row] and [column] to exactly [style]:
  /// the row's style is not layered under it.
  ///
  /// The cell keeps its value; a cell that does not exist becomes an empty
  /// styled cell. A [style] equal to the cell's current style (by
  /// [StylesPart.styleOf]; an index with no cell format, or an invalid
  /// `s`, is never kept) keeps its index, so a cell format the value
  /// types cannot hold in full is not replaced; any other is appended to
  /// the styles when no cell format of the file or appended before matches
  /// it, so no existing index moves. `null` gives index 0 (also dropping
  /// an invalid `s`), and a cell left with no value and no other attribute
  /// is removed.
  ///
  /// Throws a [StateError] for a sheet that is not a worksheet or has no
  /// part and when the workbook's styles part is not a SpreadsheetML
  /// `styleSheet`, an [ArgumentError] naming the field of an invalid style
  /// and an `XlsxLimitError` past the writer's limits (as
  /// `XlsxWriter` does), a [RangeError] outside Excel's grid, and an
  /// [XlsxReadException] when the sheet cannot be read. Whatever it throws,
  /// nothing has changed, except that a style entry read for the first
  /// time that cannot be read exactly has been reported
  /// (`styleEntryInvalid`): reading warnings are reported on first read.
  void setStyle(int row, int column, XlsxStyle? style) {
    _checkCell(row, column);
    final CellStore store = _editableCells('styles');
    final RawCell? current = store.cellAt(row, column);
    final StylesPart? loaded = _host.styles;
    if (loaded != null && !loaded.isTyped) throw _untypedStyles();
    final int? index = _hasInvalidStyle(current) ? null : current?.style ?? 0;
    if (style != null &&
        loaded != null &&
        index != null &&
        index < loaded.cellFormatCount &&
        loaded.styleOf(index) == style) {
      return;
    }
    final StylesPart? styles = style == null ? null : _stylesFor();
    final ChangeLog log = _host.log;
    log.transaction(() {
      final int id = styles == null ? 0 : appendStyle(log, styles, style);
      final RawCell base = current ?? const RawCell(kind: RawCellKind.number);
      final RawCell cell = RawCell(
        kind: base.kind,
        style: id == 0 ? null : id,
        value: base.value,
        formula: base.formula,
        inline: base.inline,
        typeText: base.typeText,
        attributes: <KeptAttribute>[
          for (final KeptAttribute a in base.attributes)
            if (a.qualifiedName != 's' || a.namespaceUri.isNotEmpty) a,
        ],
        extraChildren: base.extraChildren,
      );
      final bool remove = id == 0 && cell.isEmpty && cell.attributes.isEmpty;
      if (remove && current == null) return;
      setStoredCell(log, store, row, column, remove ? null : cell);
    });
    _reported.remove(row * XlsxLimits.maxColumns + column);
  }

  /// How [row] looks: its height, visibility, outline level, collapsed mark
  /// and style, read from the row's `ht` (with `customHeight`), `hidden`,
  /// `outlineLevel`, `collapsed` and `s` (with `customFormat`).
  ///
  /// A row the file lacks has the default format. An `ht` without
  /// `customHeight="1"` is Excel's automatic height, so `height` is `null`;
  /// the style is read as [styleAt] reads a row's. An attribute that cannot
  /// be read (an `ht` of `abc`, an outline level of 9) reads as its default
  /// and is reported once (`layoutInvalid`); it is saved as written until
  /// [setRowFormat] sets that field. Loads the sheet. Throws a
  /// [RangeError] outside Excel's rows and an [XlsxReadException] when the
  /// sheet cannot be read.
  XlsxRowFormat rowFormat(int row) {
    RangeError.checkValueInInterval(row, 0, XlsxLimits.maxRows - 1, 'row');
    final CellStore? store = _load()?.cells;
    if (store == null) return const XlsxRowFormat();
    return _readRowFormat(store, row);
  }

  /// Sets how [row] looks to exactly [format].
  ///
  /// The row keeps its cells and every attribute the format does not cover
  /// (`x14ac:dyDescent`, `thickBot`, ...); a field equal to the row's
  /// current one is left as written, even when it cannot be read. A new
  /// attribute is written as the writer writes a row (`ht` with
  /// `customHeight="1"`, `hidden="1"`, `outlineLevel`, `collapsed="1"`, and
  /// the style as `s` with `customFormat="1"`); a changed one is replaced
  /// where it stood. A style is appended to the styles when no cell format
  /// matches it, so no existing index moves, and a style that is the default
  /// writes no `s`. A row left with no cells, no attributes and no other
  /// content is removed. On save, `sheetFormatPr/@outlineLevelRow` is the
  /// larger of the kept value and the deepest row outline level.
  ///
  /// Throws an [ArgumentError] named `height` for a height outside 0 to
  /// 409.5 (or not finite) or `outlineLevel` for a level outside 0 to 7, an
  /// [ArgumentError] naming the field of an invalid style and an
  /// `XlsxLimitError` past the writer's limits, a [StateError] for a sheet
  /// that is not a worksheet or has no part and, when [XlsxRowFormat.style]
  /// changes, when the styles part is not a SpreadsheetML `styleSheet`, a
  /// [RangeError] outside Excel's rows, and an [XlsxReadException] when the
  /// sheet cannot be read. Whatever it throws, nothing has changed, except
  /// that reading warnings are reported on first read.
  void setRowFormat(int row, XlsxRowFormat format) {
    RangeError.checkValueInInterval(row, 0, XlsxLimits.maxRows - 1, 'row');
    final double? height = format.height;
    if (height != null) checkRowHeight(height, 'height');
    checkOutlineLevel(format.outlineLevel, 'outlineLevel');
    final CellStore store = _editableCells('row formats');
    final StylesPart? loaded = _host.styles;
    if (loaded != null && !loaded.isTyped && format.style != null) {
      throw _untypedStyles();
    }
    final XlsxRowFormat current = _readRowFormat(store, row);
    if (current == format) return;
    final bool styleChanged = format.style != current.style;
    final StylesPart? styles = styleChanged && format.style != null
        ? _stylesFor()
        : null;
    final List<KeptAttribute> old = store.rowAttributes(row);
    final ChangeLog log = _host.log;
    log.transaction(() {
      final int id = styles == null
          ? 0
          : appendStyle(log, styles, format.style);
      final List<KeptAttribute> next = _rowAttributesFor(
        old,
        current,
        format,
        styleId: styleChanged ? id : null,
      );
      if (sameAttributes(old, next)) return;
      setStoredRowAttributes(log, store, row, next);
    });
  }

  /// How column [index] (0 for A) looks: its width, style, visibility,
  /// outline level and collapsed mark, read from the `<col>` holding it
  /// (`width` with `customWidth`, `style`, `hidden`, `outlineLevel`,
  /// `collapsed`), or `null` for a default column.
  ///
  /// A column no `<col>` holds, and one whose `<col>` sets nothing the
  /// model reads, is a default column. A `width` without `customWidth="1"`
  /// is Excel's automatic width (the default or best fit), so `width` is
  /// `null` then. The style is read as [styleAt] reads a row's. An
  /// attribute that cannot be read (a `width` of `abc`, an outline level of
  /// 9) reads as its default and is reported once (`layoutInvalid`); it is
  /// saved as written until [setColumn] sets that field. A `<cols>` that
  /// is not plain (see [setColumn]) reads as no columns. Loads the sheet.
  /// Throws a [RangeError] outside Excel's columns and an
  /// [XlsxReadException] when the sheet cannot be read.
  XlsxColumn? column(int index) {
    RangeError.checkValueInInterval(
      index,
      0,
      XlsxLimits.maxColumns - 1,
      'index',
    );
    final ColRun? run = _load()?.columnRunAt(index + 1);
    if (run == null) return null;
    final XlsxColumn column = _readColumn(run);
    return column == const XlsxColumn() ? null : column;
  }

  /// Sets how column [index] (0 for A) looks to exactly [column]; `null`,
  /// like an [XlsxColumn] that sets nothing, resets it to the default.
  ///
  /// The `<col>` holding the column is split into up to three, the columns
  /// before it, the column itself and the columns after it, and the outer
  /// runs keep every attribute (`bestFit`, ...); a column of the same
  /// `<col>` as a neighbour joins it again. The column keeps every attribute
  /// the column does not cover; a field equal to the current one is left as
  /// written, even when it cannot be read, and setting a column to what
  /// [column] reads changes nothing. A new attribute is written as the
  /// writer writes a `<col>` (`width` always, then `style`, `hidden`,
  /// `customWidth="1"`, `outlineLevel`, `collapsed="1"`); a changed one is
  /// replaced where it stood. A width reset to the default writes the
  /// sheet's default column width without `customWidth`. A style is
  /// appended to the styles when no cell format matches it, so no existing
  /// index moves. A `<cols>` left with no `<col>` is removed, and a sheet
  /// without one gets it in schema position. On save,
  /// `sheetFormatPr/@outlineLevelCol` is the larger of the kept value and
  /// the deepest column outline level, made when needed.
  ///
  /// Only the first `<cols>` is edited, and only when it is plain: its
  /// `<col>` elements have no children or declarations of their own, whole
  /// `min` and `max` inside the grid, and are sorted and do not overlap.
  /// Any other `<cols>` is kept as written, and [setColumn] throws a
  /// [StateError].
  ///
  /// Throws an [ArgumentError] named `column.width` for a width outside 0
  /// to 255 (or not finite) or `column.outlineLevel` for a level outside 0
  /// to 7, an [ArgumentError] naming the field of an invalid style
  /// (`column.style.font.name`, ...) and an `XlsxLimitError` past the
  /// writer's limits, a [StateError] for a sheet that is not a worksheet or
  /// has no part, for a `<cols>` that is not plain and, when
  /// [XlsxColumn.style] changes, when the styles part is not a
  /// SpreadsheetML `styleSheet`, a [RangeError] outside Excel's columns, and
  /// an [XlsxReadException] when the sheet cannot be read. Whatever it
  /// throws, nothing has changed, except that reading warnings are reported
  /// on first read.
  void setColumn(int index, XlsxColumn? column) {
    RangeError.checkValueInInterval(
      index,
      0,
      XlsxLimits.maxColumns - 1,
      'index',
    );
    if (column != null) {
      final double? width = column.width;
      if (width != null) checkColumnWidth(width, 'column.width');
      checkOutlineLevel(column.outlineLevel, 'column.outlineLevel');
    }
    final WorksheetPart part = _editablePart('columns');
    if (!part.columnsEditable) {
      throw StateError(
        'The sheet "$name" has a <cols> that is not plain (a <col> with '
        'children, an invalid or overlapping range, ...); its columns '
        'cannot be set.',
      );
    }
    final StylesPart? loaded = _host.styles;
    if (loaded != null && !loaded.isTyped && column?.style != null) {
      throw _untypedStyles();
    }
    final ColRun? run = part.columnRunAt(index + 1);
    final XlsxColumn current = run == null
        ? const XlsxColumn()
        : _readColumn(run);
    final XlsxColumn next = column ?? const XlsxColumn();
    if (current == next) return;
    final bool styleChanged = next.style != current.style;
    final StylesPart? styles = styleChanged && next.style != null
        ? _stylesFor()
        : null;
    final String defaultWidth = formatXmlDouble(_defaultColumnWidth(part));
    final ChangeLog log = _host.log;
    log.transaction(() {
      int id = 0;
      if (styles != null) {
        try {
          id = appendStyle(log, styles, next.style);
        } on ArgumentError catch (error, stack) {
          final String? field = error.name;
          Error.throwWithStackTrace(
            ArgumentError.value(
              error.invalidValue,
              field == null ? 'column.style' : 'column.style.$field',
              error.message,
            ),
            stack,
          );
        }
      }
      editLayout(log, part, () {
        part.setColumnRuns(
          setColumnInRuns(
            part.columnRuns,
            index + 1,
            '${part.elementPrefix}col',
            (List<KeptAttribute>? old) => next == const XlsxColumn()
                ? null
                : _columnAttributesFor(
                    old,
                    current,
                    next,
                    styleId: styleChanged ? id : null,
                    defaultWidth: defaultWidth,
                  ),
          ),
        );
      });
    });
  }

  /// The column a `<col>` describes, reporting what cannot be read.
  XlsxColumn _readColumn(ColRun run) {
    final String element = run.min == run.max
        ? 'column ${columnName(run.min - 1)}'
        : 'columns ${columnName(run.min - 1)}:${columnName(run.max - 1)}';
    String? width;
    bool customWidth = false;
    bool hidden = false;
    bool collapsed = false;
    int outlineLevel = 0;
    int? styleIndex;
    for (final KeptAttribute a in run.attributes) {
      if (a.namespaceUri.isNotEmpty) continue;
      final String v = a.value;
      switch (a.qualifiedName) {
        case 'width':
          width = v;
        case 'customWidth':
          customWidth = _layoutBool(element, 'customWidth', v) ?? false;
        case 'hidden':
          hidden = _layoutBool(element, 'hidden', v) ?? false;
        case 'collapsed':
          collapsed = _layoutBool(element, 'collapsed', v) ?? false;
        case 'outlineLevel':
          final int? level = parseOutlineLevel(v);
          outlineLevel = level ?? 0;
          if (level == null) {
            _layoutProblem(
              element,
              'outlineLevel "$v" is not an outline level from 0 to '
              '${XlsxLimits.maxOutlineLevel}.',
            );
          }
        case 'style':
          if (v.isNotEmpty && v.length <= 9 && _plainInt.hasMatch(v)) {
            styleIndex = int.tryParse(v);
          } else {
            styleIndex = null;
            _layoutProblem(element, 'style "$v" is not a cell format index.');
          }
      }
    }
    double? custom;
    if (width != null) {
      final double? w = _plainNumber.hasMatch(width)
          ? double.tryParse(width)
          : null;
      if (w == null || !w.isFinite || w < 0 || w > XlsxLimits.maxColumnWidth) {
        _layoutProblem(element, 'width "$width" is not a column width.');
      } else if (customWidth) {
        custom = w;
      }
    }
    return XlsxColumn(
      width: custom,
      style: _styleOfIndex(styleIndex),
      hidden: hidden,
      outlineLevel: outlineLevel,
      collapsed: collapsed,
    );
  }

  /// The attributes [next] gives a `<col>` whose attributes were [old]
  /// (`null` for a new one) and whose column was [current]: each changed
  /// field replaced where it stood, or added in the writer's order after
  /// the others, and `width` (which the schema requires) always.
  ///
  /// [styleId] is the cell format index of a changed style (0 for none);
  /// `null` leaves the style attribute as it is.
  static List<KeptAttribute> _columnAttributesFor(
    List<KeptAttribute>? old,
    XlsxColumn current,
    XlsxColumn next, {
    required int? styleId,
    required String defaultWidth,
  }) {
    final bool created = old == null;
    final bool widthChanged = created || next.width != current.width;
    final Map<String, String?> changed = <String, String?>{};
    if (widthChanged) {
      final double? w = next.width;
      changed['width'] = w == null ? defaultWidth : formatXmlDouble(w);
    }
    if (styleId != null) {
      changed['style'] = styleId == 0 ? null : '$styleId';
    }
    if (next.hidden != current.hidden) {
      changed['hidden'] = next.hidden ? '1' : null;
    }
    if (widthChanged) {
      changed['customWidth'] = next.width == null ? null : '1';
    }
    if (next.outlineLevel != current.outlineLevel) {
      changed['outlineLevel'] = next.outlineLevel == 0
          ? null
          : '${next.outlineLevel}';
    }
    if (next.collapsed != current.collapsed) {
      changed['collapsed'] = next.collapsed ? '1' : null;
    }
    final List<KeptAttribute> attributes = replaceAttributes(
      old ?? const <KeptAttribute>[],
      changed,
    );
    if (attributes.any(
      (KeptAttribute a) => a.namespaceUri.isEmpty && a.qualifiedName == 'width',
    )) {
      return attributes;
    }
    return <KeptAttribute>[
      (qualifiedName: 'width', namespaceUri: '', value: defaultWidth),
      ...attributes,
    ];
  }

  /// The sheet's default column width: its `defaultColWidth` when that is a
  /// column width, else Excel's standard one, as the writer writes it.
  static double _defaultColumnWidth(WorksheetPart part) {
    final String? text = part.sheetFormatAttribute('defaultColWidth');
    final double? width = text != null && _plainNumber.hasMatch(text)
        ? double.tryParse(text)
        : null;
    return width != null && width.isFinite && _isColumnWidth(width)
        ? width
        : standardColumnWidth;
  }

  static bool _isColumnWidth(double width) =>
      width >= 0 && width <= XlsxLimits.maxColumnWidth;

  /// The sheet's default row height in points and default column width in
  /// characters, or `null` for each that the sheet leaves to Excel.
  ///
  /// They are read from `sheetFormatPr`: the row height is `defaultRowHeight`
  /// when `customHeight="1"` (Excel's own default is not a setting), the
  /// column width is `defaultColWidth`; `baseColWidth` is not read. An
  /// attribute that cannot be read reads as `null` and is reported once
  /// (`layoutInvalid`). Loads the sheet. Throws an [XlsxReadException] when
  /// the sheet cannot be read.
  ({double? rowHeight, double? columnWidth}) get defaultSizes {
    final WorksheetPart? part = _load();
    if (part == null) return (rowHeight: null, columnWidth: null);
    return _readDefaultSizes(part);
  }

  ({double? rowHeight, double? columnWidth}) _readDefaultSizes(
    WorksheetPart part,
  ) {
    const String element = 'sheetFormatPr';
    double? number(String name, num max) {
      final String? text = part.sheetFormatAttribute(name);
      if (text == null) return null;
      final double? v = _plainNumber.hasMatch(text)
          ? double.tryParse(text)
          : null;
      if (v == null || !v.isFinite || v < 0 || v > max) {
        _layoutProblem(element, '$name "$text" is not a size.');
        return null;
      }
      return v;
    }

    final double? height = number('defaultRowHeight', XlsxLimits.maxRowHeight);
    final String? custom = part.sheetFormatAttribute('customHeight');
    final bool customHeight = custom == null
        ? false
        : _layoutBool(element, 'customHeight', custom) ?? false;
    return (
      rowHeight: customHeight ? height : null,
      columnWidth: number('defaultColWidth', XlsxLimits.maxColumnWidth),
    );
  }

  /// Sets the sheet's default row height and default column width to
  /// exactly [rowHeight] and [columnWidth]; `null` is Excel's own.
  ///
  /// They are written as the writer's `defaultSizes` writes them:
  /// `defaultRowHeight` with `customHeight="1"` and `defaultColWidth`. A
  /// size equal to the current one is left as written; the rest of
  /// `sheetFormatPr` (`baseColWidth`, ...) is kept, and a sheet without the
  /// element gets it in schema position. A `sheetFormatPr` with element
  /// children is kept as written and cannot be edited.
  ///
  /// Throws an [ArgumentError] named `rowHeight` for a height outside 0 to
  /// 409.5 or `columnWidth` for a width outside 0 to 255 (or not finite), a
  /// [StateError] for a sheet that is not a worksheet or has no part and for
  /// a `sheetFormatPr` with element children, and an [XlsxReadException]
  /// when the sheet cannot be read. Whatever it throws, nothing has
  /// changed, except that reading warnings are reported on first read.
  void setDefaultSizes({double? rowHeight, double? columnWidth}) {
    if (rowHeight != null) checkRowHeight(rowHeight, 'rowHeight');
    if (columnWidth != null) checkColumnWidth(columnWidth, 'columnWidth');
    final WorksheetPart part = _editablePart('default sizes');
    final ({double? rowHeight, double? columnWidth}) current =
        _readDefaultSizes(part);
    if (current.rowHeight == rowHeight && current.columnWidth == columnWidth) {
      return;
    }
    if (!part.sheetFormatEditable) {
      throw StateError(
        'The sheet "$name" has a sheetFormatPr with element children; its '
        'default sizes cannot be set.',
      );
    }
    final Map<String, String?> changes = <String, String?>{};
    if (columnWidth != current.columnWidth) {
      changes['defaultColWidth'] = columnWidth == null
          ? null
          : formatXmlDouble(columnWidth);
    }
    if (rowHeight != current.rowHeight || !part.hasSheetFormat) {
      if (rowHeight != null) {
        changes['defaultRowHeight'] = formatXmlDouble(rowHeight);
        changes['customHeight'] = '1';
      } else {
        // The schema requires defaultRowHeight, which stays when it is there.
        if (part.sheetFormatAttribute('defaultRowHeight') == null) {
          changes['defaultRowHeight'] = formatXmlDouble(standardRowHeight);
        }
        changes['customHeight'] = null;
      }
    }
    final ChangeLog log = _host.log;
    log.transaction(() {
      editLayout(log, part, () => part.changeSheetFormat(changes));
    });
  }

  /// The format of [row] from its attributes, reporting what cannot be
  /// read.
  XlsxRowFormat _readRowFormat(CellStore store, int row) {
    final List<KeptAttribute> attributes = store.rowAttributes(row);
    if (attributes.isEmpty) return const XlsxRowFormat();
    final String element = 'row ${row + 1}';
    String? ht;
    bool customHeight = false;
    bool hidden = false;
    bool collapsed = false;
    int outlineLevel = 0;
    for (final KeptAttribute a in attributes) {
      if (a.namespaceUri.isNotEmpty) continue;
      final String v = a.value;
      switch (a.qualifiedName) {
        case 'ht':
          ht = v;
        case 'customHeight':
          customHeight = _layoutBool(element, 'customHeight', v) ?? false;
        case 'hidden':
          hidden = _layoutBool(element, 'hidden', v) ?? false;
        case 'collapsed':
          collapsed = _layoutBool(element, 'collapsed', v) ?? false;
        case 'outlineLevel':
          final int? level = _plainInt.hasMatch(v) ? int.tryParse(v) : null;
          if (level != null &&
              level >= 0 &&
              level <= XlsxLimits.maxOutlineLevel) {
            outlineLevel = level;
          } else {
            outlineLevel = 0;
            _layoutProblem(
              element,
              'outlineLevel "$v" is not an outline level from 0 to '
              '${XlsxLimits.maxOutlineLevel}.',
            );
          }
      }
    }
    double? height;
    if (ht != null) {
      final double? h = _plainNumber.hasMatch(ht) ? double.tryParse(ht) : null;
      if (h == null || !h.isFinite || h < 0 || h > XlsxLimits.maxRowHeight) {
        _layoutProblem(element, 'ht "$ht" is not a row height.');
      } else if (customHeight) {
        height = h;
      }
    }
    return XlsxRowFormat(
      height: height,
      hidden: hidden,
      outlineLevel: outlineLevel,
      collapsed: collapsed,
      style: _styleOfIndex(_rowStyleIndex(store, row)),
    );
  }

  /// The attributes [format] gives a row whose attributes were [old] and
  /// whose format was [current]: each changed field replaced where it
  /// stood, or added in the writer's order after the others.
  ///
  /// [styleId] is the cell format index of a changed style (0 for none);
  /// `null` leaves the style attributes as they are.
  static List<KeptAttribute> _rowAttributesFor(
    List<KeptAttribute> old,
    XlsxRowFormat current,
    XlsxRowFormat format, {
    required int? styleId,
  }) {
    // The attributes that change, in the order the writer writes them
    // (`CT_Row`): an absent name is removed.
    final Map<String, String?> changed = <String, String?>{};
    if (styleId != null) {
      changed['s'] = styleId == 0 ? null : '$styleId';
      changed['customFormat'] = styleId == 0 ? null : '1';
    }
    if (format.height != current.height) {
      final double? h = format.height;
      changed['ht'] = h == null ? null : formatXmlDouble(h);
    }
    if (format.hidden != current.hidden) {
      changed['hidden'] = format.hidden ? '1' : null;
    }
    if (format.height != current.height) {
      changed['customHeight'] = format.height == null ? null : '1';
    }
    if (format.outlineLevel != current.outlineLevel) {
      changed['outlineLevel'] = format.outlineLevel == 0
          ? null
          : '${format.outlineLevel}';
    }
    if (format.collapsed != current.collapsed) {
      changed['collapsed'] = format.collapsed ? '1' : null;
    }
    return replaceAttributes(old, changed);
  }

  /// Reads a boolean attribute of [element]: `1` or `true`, `0` or
  /// `false`; anything else is reported and reads as `null`.
  bool? _layoutBool(String element, String name, String value) {
    switch (value) {
      case '1' || 'true':
        return true;
      case '0' || 'false':
        return false;
    }
    _layoutProblem(element, '$name "$value" is not a boolean.');
    return null;
  }

  /// Reports that an attribute of [element] (`row 3`, ...) cannot be read,
  /// once however often it is read.
  void _layoutProblem(String element, String problem) {
    final String detail = '$element: $problem';
    if (_layoutReported.add(detail)) {
      _warn(XlsxWarningCode.layoutInvalid, null, detail: detail);
    }
  }

  static final RegExp _plainInt = RegExp(r'^[+-]?\d+$');
  static final RegExp _plainNumber = RegExp(
    r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$',
  );

  /// The cells of the loaded worksheet part, to set their [what]. Throws a
  /// [StateError] for a sheet without a part or that is not a worksheet.
  CellStore _editableCells(String what) => _editablePart(what).cells;

  /// The loaded worksheet part, to set its [what]. Throws a [StateError]
  /// for a sheet without a part or that is not a worksheet.
  WorksheetPart _editablePart(String what) {
    final WorksheetPart? part = _load();
    if (part == null) {
      throw StateError(
        'The sheet "$name" has no worksheet part; its $what cannot be set.',
      );
    }
    if (!part.isTyped) {
      throw StateError(
        'The sheet "$name" is not a worksheet (a chartsheet, say); its '
        '$what cannot be set.',
      );
    }
    return part;
  }

  /// The styles part to append to; throws a [StateError] for an untyped
  /// part.
  StylesPart _stylesFor() {
    final StylesPart styles = _host.stylesForEdit();
    if (!styles.isTyped) throw _untypedStyles();
    return styles;
  }

  /// Whether [cell] keeps an `s` that is not a style index among its
  /// attributes.
  static bool _hasInvalidStyle(RawCell? cell) =>
      cell != null &&
      cell.attributes.any(
        (KeptAttribute a) => a.qualifiedName == 's' && a.namespaceUri.isEmpty,
      );

  StateError _untypedStyles() => StateError(
    'The styles part of the workbook is not a SpreadsheetML styleSheet; '
    'cell styles cannot be set.',
  );

  /// The style index of [row] when the row has `customFormat="1"`: its
  /// `s`, or `null` when it has none that is a style index.
  static int? _rowStyleIndex(CellStore store, int row) {
    String? s;
    bool custom = false;
    for (final KeptAttribute a in store.rowAttributes(row)) {
      if (a.namespaceUri.isNotEmpty) continue;
      if (a.qualifiedName == 's') s = a.value;
      if (a.qualifiedName == 'customFormat') {
        custom = a.value == '1' || a.value == 'true';
      }
    }
    if (!custom || s == null || s.isEmpty || s.length > 9) return null;
    return int.tryParse(s);
  }

  /// The style of [row] for layering, or `null` when the row has none (or
  /// index 0).
  XlsxStyle? _rowStyle(CellStore store, int row) {
    final int? index = _rowStyleIndex(store, row);
    final StylesPart? styles = _host.styles;
    if (index == null || index <= 0 || styles == null) return null;
    return styles.styleOf(index);
  }

  /// The column's style under a cell of [row] and [column] that is being
  /// set, or `null`: a row that is formatted by an explicit style 0
  /// (`customFormat="1"` and `s="0"`) shows the default, so no column style
  /// goes under it.
  XlsxStyle? _columnLayer(CellStore store, int row, int column) {
    if (_rowStyleIndex(store, row) == 0) return null;
    return _styleOfIndex(_columnStyleIndex(column));
  }

  /// The `style` of the `<col>` holding [column], or `null` when none does
  /// or it is not a cell format index.
  int? _columnStyleIndex(int column) {
    final String? s = _part?.columnRunAt(column + 1)?.attribute('style');
    if (s == null || s.isEmpty || s.length > 9 || !_plainInt.hasMatch(s)) {
      return null;
    }
    return int.tryParse(s);
  }

  /// [column], [row] and [cell] laid over each other with
  /// [XlsxStyle.merge], bottom first, as the writer's encoder layers them.
  static XlsxStyle? _layer(XlsxStyle? column, XlsxStyle? row, XlsxStyle? cell) {
    XlsxStyle? merged = column;
    for (final XlsxStyle? layer in <XlsxStyle?>[row, cell]) {
      if (layer != null) merged = merged == null ? layer : merged.merge(layer);
    }
    return merged;
  }

  /// [style] with the writer's date format when [value] is a date Excel can
  /// store and [style] sets no number format: the date-time format for a
  /// `DateTime`, the short-date one for an [XlsxDate].
  XlsxStyle? _withDateFormat(XlsxStyle? style, Object value) {
    if (style?.numFmt != null) return style;
    final XlsxNumFmt? format = switch (value) {
      DateTime() when dateTimeSerial(value, date1904: _host.date1904) != null =>
        XlsxNumFmt.localeDateTime,
      XlsxDate() when _hasSerial(value) => XlsxNumFmt.localeShortDate,
      _ => null,
    };
    if (format == null) return style;
    return (style ?? const XlsxStyle()).copyWith(numFmt: format);
  }

  /// Whether [date] has a serial in the workbook's date system; an
  /// impossible date counts as having one, since setting it throws.
  bool _hasSerial(XlsxDate date) {
    try {
      return dateSerial(
            date.year,
            date.month,
            date.day,
            date1904: _host.date1904,
          ) !=
          null;
    } on ArgumentError {
      return true;
    }
  }

  /// The table whose header row holds the cell at [row] and [column], with
  /// the column's index in it, or `null`.
  ({String partName, TablePart table, int index})? _headerAt(
    int row,
    int column,
  ) {
    for (final ({String partName, TablePart table}) t in _sheetTables()) {
      final XlsxRange range = t.table.range;
      if (t.table.hasHeader &&
          row == range.firstRow &&
          column >= range.firstColumn &&
          column <= range.lastColumn) {
        return (
          partName: t.partName,
          table: t.table,
          index: column - range.firstColumn,
        );
      }
    }
    return null;
  }

  /// The sheet's tables, read once. A table part that cannot be read or
  /// typed is left out, and so kept as written.
  List<({String partName, TablePart table})> _sheetTables() {
    final List<({String partName, TablePart table})>? cached = _tables;
    if (cached != null) return cached;
    final List<({String partName, TablePart table})> found =
        <({String partName, TablePart table})>[];
    final PackageReader reader = _host.reader;
    try {
      for (final PartRelationship rel in reader.relationshipsOf(
        _partName!.substring(1),
      )) {
        if (rel.type != RelType.table || !reader.hasPart(rel.target)) {
          continue;
        }
        try {
          final TablePart? table = reader.guardXml(
            rel.target,
            () => TablePart.read(reader.openXml(rel.target)),
          );
          if (table != null) found.add((partName: rel.target, table: table));
        } on XlsxReadException {
          // Kept as written.
        }
      }
    } on XlsxReadException {
      // The sheet's relationships cannot be read: no table is typed.
    }
    return _tables = found;
  }

  /// The loaded part, loading it on first use; `null` for a sheet without
  /// a part.
  WorksheetPart? _load() {
    final WorksheetPart? loaded = _part;
    if (loaded != null) return loaded;
    final String? partName = _partName;
    if (partName == null) return null;
    final CellEncoder encoder = _host.loadTables();
    final PackageReader reader = _host.reader;
    final String plain = partName.substring(1);
    // Warnings are kept only once the part has loaded, so a failed load
    // that is retried does not count them twice.
    final List<(XlsxWarningCode, String?, String?)> found =
        <(XlsxWarningCode, String?, String?)>[];
    final WorksheetPart part = reader.guardXml(
      plain,
      () => WorksheetPart.read(
        reader.openXml(plain),
        part: plain,
        limits: reader.limits,
        warn: (XlsxWarningCode code, String? cell, {String? detail}) =>
            found.add((code, cell, detail)),
      ),
    );
    part.bindEncoder(encoder);
    reader.package.setContent(partName, part);
    for (final (XlsxWarningCode code, String? cell, String? detail) in found) {
      _warn(code, cell, detail: detail);
    }
    return _part = part;
  }

  void _warn(XlsxWarningCode code, String? cell, {String? detail}) => _host
      .warnings
      .add(code, sheet: name, cell: cell, detail: detail, key: this);

  Iterable<XlsxReadRow> _rows(CellStore store) sync* {
    final FormulaGroups groups = FormulaGroups();
    for (final int row in store.rowIndexes) {
      groups.startRow(row);
      final List<XlsxReadCell> cells = <XlsxReadCell>[];
      store.forEachInRow(row, (int column, RawCell cell) {
        if (!_hasData(cell)) return;
        final FormulaGroupResult group = _passGroup(groups, row, column, cell);
        final XlsxReadCell view = _view(
          row,
          column,
          cell,
          null,
          groupInvalid: group.invalid,
        );
        cells.add(
          group.group == null
              ? view
              : XlsxReadCell(
                  column,
                  view.value,
                  formula: view.formula,
                  formulaGroup: group.group,
                  numberFormatId: view.numberFormatId,
                  numberFormat: view.numberFormat,
                  isDate: view.isDate,
                ),
        );
      });
      final bool hidden = _isHidden(store.rowAttributes(row));
      if (cells.isNotEmpty || hidden) {
        yield XlsxReadRow(row, cells, hidden: hidden);
      }
    }
  }

  /// The typed view of [cell] at [row] and [column] with [group].
  ///
  /// The decoder's warning, and `formulaGroupInvalid` when [groupInvalid],
  /// are reported against the cell once, by whichever of [cellAt] and
  /// [rows] reads it first; only a cell with something to report is
  /// remembered.
  XlsxReadCell _view(
    int row,
    int column,
    RawCell cell,
    XlsxFormulaGroup? group, {
    bool groupInvalid = false,
  }) {
    final CellFormat format = _host.styleTable.formatOf(_styleText(cell));
    final DecodedCell decoded = decodeRawCell(
      cell,
      sharedStrings: _host.sharedStringTexts,
      format: format,
      date1904: _host.date1904,
    );
    final XlsxWarningCode? warning = decoded.warning;
    if ((warning != null || groupInvalid) &&
        _reported.add(row * XlsxLimits.maxColumns + column)) {
      if (warning != null) {
        _warn(
          warning,
          cellRef(row, column),
          detail: warning == XlsxWarningCode.unresolvedNumberFormat
              ? '${format.id}'
              : null,
        );
      }
      if (groupInvalid) {
        _warn(XlsxWarningCode.formulaGroupInvalid, cellRef(row, column));
      }
    }
    return XlsxReadCell(
      column,
      decoded.value,
      formula: decoded.formula,
      formulaGroup: group,
      numberFormatId: format.id,
      numberFormat: format.code,
      isDate: format.kind == FormatKind.date || format.kind == FormatKind.time,
    );
  }

  /// The group of [cell] at [row], [column] in a pass over the rows, as the
  /// reader computes it.
  static FormulaGroupResult _passGroup(
    FormulaGroups groups,
    int row,
    int column,
    RawCell cell,
  ) {
    final RawFormula? f = cell.formula;
    if (f == null) {
      return (group: groups.coveredBy(row, column), invalid: false);
    }
    if (groups.coveredBy(row, column) != null) {
      return (group: null, invalid: true);
    }
    return switch (f.type) {
      FormulaType.normal => (group: null, invalid: false),
      FormulaType.shared when f.ref == null => groups.follower(
        f.si,
        row: row,
        column: column,
      ),
      final FormulaType type => groups.master(
        type,
        row: row,
        column: column,
        ref: f.ref,
        si: f.si,
      ),
    };
  }

  /// The group of [cell] at [row], [column], from the store's group masters
  /// (for a well-formed sheet the same as [_passGroup]'s).
  static XlsxFormulaGroup? _indexedGroup(
    CellStore store,
    int row,
    int column,
    RawCell cell,
  ) {
    final RawFormula? own = cell.formula;
    if (own != null && own.type == FormulaType.normal) return null;
    if (own != null && (own.type != FormulaType.shared || own.ref != null)) {
      final XlsxRange? range = own.ref == null
          ? (own.type == FormulaType.array ? XlsxRange(row, column) : null)
          : _range(own.ref!);
      if (range == null || !_inside(range, row, column)) return null;
      return XlsxFormulaGroup(_kindOf(own.type), range, isMaster: true);
    }
    for (final ({int row, int column, RawFormula formula}) m
        in store.groupMasters) {
      final RawFormula f = m.formula;
      final XlsxRange? range = _range(f.ref!);
      if (range == null || !_inside(range, row, column)) continue;
      final bool matches = own == null
          ? f.type != FormulaType.shared
          : f.type == FormulaType.shared && _sameSi(f.si, own.si);
      if (matches) {
        return XlsxFormulaGroup(_kindOf(f.type), range, isMaster: false);
      }
    }
    return null;
  }

  static XlsxFormulaGroupKind _kindOf(FormulaType type) => switch (type) {
    FormulaType.shared => XlsxFormulaGroupKind.shared,
    FormulaType.dataTable => XlsxFormulaGroupKind.dataTable,
    FormulaType.array || FormulaType.normal => XlsxFormulaGroupKind.array,
  };

  static bool _sameSi(String? a, String? b) {
    if (a == null || b == null) return false;
    return int.tryParse(a) != null && int.tryParse(a) == int.tryParse(b);
  }

  static bool _inside(XlsxRange r, int row, int column) =>
      row >= r.firstRow &&
      row <= r.lastRow &&
      column >= r.firstColumn &&
      column <= r.lastColumn;

  static XlsxRange? _range(String ref) {
    try {
      return XlsxRange.parse(ref);
    } on ArgumentError {
      return null;
    }
  }

  /// Whether [cell] holds what makes the reader list it: a value, a
  /// formula or an inline string.
  static bool _hasData(RawCell cell) =>
      cell.value != null || cell.formula != null || cell.inline != null;

  /// The `s` text of [cell] as written: its valid style, else an invalid
  /// `s` it keeps among its attributes, else `null`.
  static String? _styleText(RawCell? cell) {
    if (cell == null) return null;
    final int? style = cell.style;
    if (style != null) return '$style';
    for (final KeptAttribute a in cell.attributes) {
      if (a.qualifiedName == 's' && a.namespaceUri.isEmpty) return a.value;
    }
    return null;
  }

  /// Whether a row's attributes hide it (`hidden` is `1` or `true`).
  static bool _isHidden(List<KeptAttribute> attributes) {
    for (final KeptAttribute a in attributes) {
      if (a.qualifiedName == 'hidden' && a.namespaceUri.isEmpty) {
        return a.value == '1' || a.value == 'true';
      }
    }
    return false;
  }

  static void _checkCell(int row, int column) {
    RangeError.checkValueInInterval(row, 0, XlsxLimits.maxRows - 1, 'row');
    RangeError.checkValueInInterval(
      column,
      0,
      XlsxLimits.maxColumns - 1,
      'column',
    );
  }
}

/// [name], or [name] with the smallest number from 2 up appended, so that no
/// other column of [table] than [index] has it, ignoring case.
String _uniqueColumnName(TablePart table, int index, String name) {
  final Set<String> taken = <String>{
    for (int i = 0; i < table.columnCount; i++)
      if (i != index) table.columnName(i).toLowerCase(),
  };
  String candidate = name;
  for (int n = 2; taken.contains(candidate.toLowerCase()); n++) {
    candidate = '$name$n';
  }
  return candidate;
}
