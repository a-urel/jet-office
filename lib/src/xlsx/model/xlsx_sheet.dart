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
import '../../opc/opaque_xml.dart';
import '../cell_encoder.dart';
import '../cell_ref.dart';
import '../format/format_kind.dart';
import '../hyperlink.dart';
import '../limits.dart';
import '../range.dart';
import '../raw_cell.dart';
import '../read/cell_decoder.dart';
import '../read/formula_groups.dart';
import '../read/package_reader.dart';
import '../read/read_cell.dart';
import '../read/read_exception.dart';
import '../read/styles_reader.dart';
import '../rich_text.dart';
import '../sheet_view.dart';
import '../values.dart';
import '../warnings.dart';
import 'cell_store.dart';
import 'primitives.dart';
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

  /// The shared strings by index, for decoding, or `null` when the workbook
  /// has none; [loadTables] must have run.
  List<String>? get sharedStringTexts;

  /// The style index for a date set on a cell of [style] in General: the
  /// writer's date-time format (id 22) with [withTime], else its short-date
  /// format (id 14).
  int dateStyle(int? style, {required bool withTime});
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
  /// whose reading was reported, so a value is reported once however often
  /// [rows] runs; a set cell is read afresh.
  final Set<int> _reported = <int>{};

  /// The sheet's name, as the workbook lists it.
  String get name => _entry.name;

  /// Whether the sheet is visible, hidden or very hidden.
  XlsxSheetVisibility get visibility => _entry.visibility;

  /// The cell at [row] and [column] as [XlsxReader] reads it, or `null`
  /// when the cell holds no value, formula or inline string (an empty
  /// styled cell included).
  ///
  /// A formula cell carries its [XlsxFormulaGroup], found from the sheet's
  /// group masters. Loads the sheet. Throws a [RangeError] outside Excel's
  /// grid and an [XlsxReadException] when the sheet cannot be read.
  XlsxReadCell? cellAt(int row, int column) {
    _checkCell(row, column);
    final CellStore? store = _load()?.cells;
    if (store == null) return null;
    final RawCell? cell = store.cellAt(row, column);
    if (cell == null || !_hasData(cell)) return null;
    return _view(column, cell, _indexedGroup(store, row, column, cell));
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
  /// A shared formula's follower may be set and leaves its group. Throws a
  /// [StateError] for a cell inside an array or data-table formula (Excel
  /// refuses that too) and for a sheet that is not a worksheet or has no
  /// part, an [UnsupportedError] for a shared formula's master (W5) and for
  /// [XlsxHyperlink] (W3), [XlsxRichText] (W4) and [XlsxCell] (W2) values,
  /// an [ArgumentError] for any other type or a value the encoder refuses,
  /// a [RangeError] outside Excel's grid, and an [XlsxReadException] when
  /// the sheet cannot be read. Whatever it throws, nothing has changed.
  void setCell(int row, int column, Object? value) {
    _checkCell(row, column);
    switch (value) {
      case XlsxHyperlink():
        throw UnsupportedError('XlsxHyperlink cells arrive in W3.');
      case XlsxRichText():
        throw UnsupportedError('XlsxRichText cells arrive in W4.');
      case XlsxCell():
        throw UnsupportedError('XlsxCell (styled) cells arrive in W2.');
    }
    final WorksheetPart? part = _load();
    if (part == null) {
      throw StateError(
        'The sheet "$name" has no worksheet part; its cells cannot be set.',
      );
    }
    if (!part.isTyped) {
      throw StateError(
        'The sheet "$name" is not a worksheet (a chartsheet, say); its '
        'cells cannot be set.',
      );
    }
    final CellStore store = part.cells;
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
    final RawCell? current = store.cellAt(row, column);
    if (value == null && current == null) return;
    final CellEncoder encoder = _host.loadTables();
    final ChangeLog log = _host.log;
    log.transaction(() {
      final RawCell prepared = encoder.prepare(
        value,
        sheet: name,
        row: row,
        column: column,
        current: current,
        currentFormat: _host.styleTable.formatOf(_styleText(current)),
        date1904: _host.date1904,
        dateStyle: _host.dateStyle,
      );
      final bool remove = value == null && prepared.style == null;
      setStoredCell(log, store, row, column, remove ? null : prepared);
    });
    _reported.remove(row * XlsxLimits.maxColumns + column);
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
        final bool report = _reported.add(row * XlsxLimits.maxColumns + column);
        final XlsxReadCell view = _view(
          column,
          cell,
          null,
          row: report ? row : null,
        );
        final FormulaGroupResult group = _passGroup(groups, row, column, cell);
        if (group.invalid && report) {
          _warn(XlsxWarningCode.formulaGroupInvalid, cellRef(row, column));
        }
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

  /// The typed view of [cell] in [column] with [group]; the decoder's
  /// warning is reported against the cell at [row] when given ([cellAt]
  /// reports none, [rows] each cell once).
  XlsxReadCell _view(
    int column,
    RawCell cell,
    XlsxFormulaGroup? group, {
    int? row,
  }) {
    final CellFormat format = _host.styleTable.formatOf(_styleText(cell));
    final DecodedCell decoded = decodeRawCell(
      cell,
      sharedStrings: _host.sharedStringTexts,
      format: format,
      date1904: _host.date1904,
    );
    final XlsxWarningCode? warning = decoded.warning;
    if (warning != null && row != null) {
      _warn(
        warning,
        cellRef(row, column),
        detail: warning == XlsxWarningCode.unresolvedNumberFormat
            ? '${format.id}'
            : null,
      );
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
