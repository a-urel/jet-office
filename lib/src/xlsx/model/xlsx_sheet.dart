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

import 'package:jet_core/jet_core.dart' show FormatKind;

import '../../common/image.dart'
    show OfficeImage, OfficeImageFormat, checkImage;
import '../../drawingml/media.dart';
import '../../drawingml/picture.dart' show DrawingPic, emuPerPixel;
import '../../opc/change_log.dart';
import '../../opc/ooxml.dart';
import '../../opc/opaque_xml.dart';
import '../../opc/package.dart' show OpcPackage, OpcRelationship;
import '../../xml/xml_escape.dart';
import '../../xml/xml_number.dart';
import '../../xml/xml_pull_reader.dart';
import '../../xml/xml_writer.dart';
import '../cell_encoder.dart';
import '../cell_ref.dart';
import '../color.dart';
import '../column.dart';
import '../conditional_format.dart';
import '../conditional_format_x14.dart'
    show hasX14Rule, writeX14ConditionalFormats;
import '../data_validation.dart';
import '../date_serial.dart';
import '../defined_name.dart';
import '../drawing.dart'
    show
        WorksheetPicture,
        XlsxAnchor,
        XlsxOneCellAnchor,
        XlsxPicture,
        checkAnchor,
        checkPicture;
import '../formula_text.dart' show quotedSheetRef;
import '../header_footer.dart';
import '../hyperlink.dart';
import '../limits.dart';
import '../merge_check.dart';
import '../note.dart';
import '../number_format.dart';
import '../page_setup.dart';
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
import '../shared_strings.dart';
import '../sheet_name.dart' show sheetNameKey;
import '../sheet_protection.dart';
import '../sheet_view.dart';
import '../sheet_writer.dart' show checkPrintAreaRanges, checkPrintTitles;
import '../style.dart';
import '../table.dart';
import '../values.dart';
import '../warnings.dart';
import '../workbook_parts.dart' show printAreaFormula, printTitlesFormula;
import '../worksheet_parts.dart'
    show
        checkColumnWidth,
        checkOutlineLevel,
        checkRowHeight,
        commentsPartName,
        drawingPartName,
        mediaPartName,
        paneAttributes,
        sheetViewAttributes,
        standardColumnWidth,
        standardRowHeight,
        vmlDrawingPartName,
        writeHyperlink;
import 'cell_store.dart';
import 'columns.dart';
import 'comments_part.dart';
import 'conditional_elements.dart';
import 'conditional_x14.dart';
import 'defined_names.dart';
import 'drawing_part.dart';
import 'element_node.dart';
import 'item_group.dart' show GroupItem, ItemGroup, readerOf, renderElements;
import 'page_elements.dart';
import 'primitives.dart';
import 'protection_elements.dart';
import 'style_elements.dart' show ReadStyleValue, readColor;
import 'styles_part.dart';
import 'table_part.dart';
import 'validation_elements.dart';
import 'vml_part.dart';
import 'workbook_part.dart';
import 'worksheet_part.dart';

part 'xlsx_sheet_layout.dart';
part 'xlsx_sheet_links.dart';
part 'xlsx_sheet_merges.dart';
part 'xlsx_sheet_names.dart';
part 'xlsx_sheet_notes.dart';
part 'xlsx_sheet_pictures.dart';
part 'xlsx_sheet_print.dart';
part 'xlsx_sheet_rules.dart';
part 'xlsx_sheet_tables.dart';
part 'xlsx_sheet_views.dart';

/// What a sheet needs from its workbook.
abstract interface class SheetHost {
  /// The change log every edit records in.
  ChangeLog get log;

  /// The workbook's warnings: open, edit and save.
  WarningCollector get warnings;

  /// Whether the workbook counts dates from 1904.
  bool get date1904;

  /// The workbook part, which holds the defined names.
  WorkbookPart get workbookPart;

  /// The tab index of [sheet] in `<sheets>`.
  int sheetIndexOf(XlsxSheet sheet);

  /// Throws an [ArgumentError] named `name` when a table of any sheet has
  /// [name], ignoring case.
  void checkNotTableName(String name);

  /// The opened package, for reading parts.
  PackageReader get reader;

  /// An id block for VML shapes that no `.vml` part of the package uses:
  /// the parts are scanned once, then the blocks are counted up, so a block
  /// is never given twice. Throws an [XlsxReadException] when a `.vml` part
  /// cannot be read.
  int takeVmlBlock();

  /// The images of the package's media parts, one `Uint8List` per part.
  DrawingMediaIndex get mediaIndex;

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

  /// The shared-string table with its kept items, or `null` when the
  /// workbook has none; [loadTables] must have run.
  SharedStrings? get sharedStrings;

  /// The style index for a date set on a cell of [style] in General: the
  /// writer's date-time format (id 22) with [withTime], else its short-date
  /// format (id 14); `null` when the styles part cannot take one (it is
  /// untyped).
  int? dateStyle(int? style, {required bool withTime});

  /// Sets the visibility of the sheet listed as [entry], with the
  /// workbook-wide rules (a visible sheet stays, the active sheet is
  /// visible).
  void setVisibility(SheetEntry entry, XlsxSheetVisibility value);
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

/// The display names of [sheet]'s tables; none for a sheet without a part.
/// Reads the table parts on first use.
Iterable<String> sheetTableNames(XlsxSheet sheet) => sheet._partName == null
    ? const <String>[]
    : <String>[
        for (final ({String partName, TablePart table}) t
            in sheet._sheetTables())
          t.table.displayName,
      ];

/// The workbook part's entry of [sheet].
SheetEntry entryOf(XlsxSheet sheet) => sheet._entry;

/// Whether [sheet]'s worksheet part is loaded.
bool isLoadedSheet(XlsxSheet sheet) => sheet._part != null;

/// Whether [sheet] has a worksheet part in the file.
bool sheetHasPart(XlsxSheet sheet) => sheet._partName != null;

/// The cells of [sheet], or `null` while its part is not loaded.
CellStore? cellStoreOf(XlsxSheet sheet) => sheet._part?.cells;

/// The number of cells of [sheet] whose reading problem was reported, for
/// tests: a cell read without a problem is not remembered.
int reportedCellCount(XlsxSheet sheet) => sheet._reported.length;

/// A note of a sheet with the cell it is on: the zero-based `row` and
/// `column`, and the `note`.
typedef XlsxCellNote = ({int row, int column, XlsxNote note});

/// One sheet of a workbook, opened or created.
///
/// Rows and columns are 0-based: row 0 is Excel's row 1 and column 0 is
/// `A`.
final class XlsxSheet
    with
        _SheetLayout,
        _SheetLinks,
        _SheetMerges,
        _SheetNames,
        _SheetNotes,
        _SheetPictures,
        _SheetPrint,
        _SheetRules,
        _SheetTablesApi,
        _SheetViews {
  XlsxSheet._(this._host, this._entry, this._partName, this._part);

  @override
  final SheetHost _host;
  final SheetEntry _entry;
  @override
  final String? _partName;
  WorksheetPart? _part;

  /// The positions (`row * XlsxLimits.maxColumns + column`) of the cells
  /// whose reading problem was reported, so a problem is reported once
  /// however often [rows] runs; a set cell is read afresh. A cell read
  /// without a problem is not added, so reading costs no entry per cell.
  final Set<int> _reported = <int>{};

  /// The layout problems reported (`layoutInvalid`), by detail, so a
  /// problem is reported once however often its element is read.
  @override
  final Set<String> _layoutReported = <String>{};

  /// The print and filter problems reported (`featureEntryInvalid`), by
  /// name, so a problem is reported once however often it is read.
  @override
  final Set<String> _featureReported = <String>{};

  /// The tables of the sheet the model can type, read on the first
  /// [setCell]; `null` until then.
  List<({String partName, TablePart table})>? _tables;

  /// The sheet's name, as the workbook lists it.
  @override
  String get name => _entry.name;

  /// Whether the sheet is visible, hidden or very hidden.
  XlsxSheetVisibility get visibility => _entry.visibility;

  /// Shows or hides the sheet: [XlsxSheetVisibility.visible] removes the
  /// `state` attribute of its tab. An equal value changes nothing.
  ///
  /// Hiding the active sheet makes the first visible sheet active, as Excel
  /// does. Throws a [StateError] when this is the last visible sheet and
  /// [value] is not visible; nothing changes then.
  set visibility(XlsxSheetVisibility value) =>
      _host.setVisibility(_entry, value);

  /// What the sheet's protection allows, or `null` when the sheet is not
  /// protected: it has no `<sheetProtection>`, or its `sheet` is `0`.
  ///
  /// The password always reads `null`: the file stores a hash, never the
  /// password ([hasStoredPassword] says whether it has one). Every flag has
  /// its schema meaning, so an attribute the file omits reads as Excel
  /// reads it. A boolean written `true` or `false` is read; any other text
  /// reads as the attribute's default. Only the first `<sheetProtection>`
  /// is read. Loads the sheet. Throws an [XlsxReadException] when the sheet
  /// cannot be read.
  XlsxSheetProtection? get protection {
    final Object? node = _load()?.layoutElement('sheetProtection');
    return node is XmlNode ? readSheetProtection(node) : null;
  }

  /// Protects the sheet as [value] says, or removes the `<sheetProtection>`
  /// with `null`, a stored hash with it.
  ///
  /// A new element is the text the writer writes for the same protection,
  /// in schema position. An existing element keeps its other attributes
  /// (`lockRevision`, ...) and changes an attribute only when its meaning
  /// changes, so `objects="0"` stays when objects stay editable. A
  /// [value] whose `password` is `null` keeps the stored hash, which is how
  /// a flag changes on a sheet whose password is not known; a password
  /// replaces every hash attribute. An element with `sheet="0"` is edited
  /// in place and gets `sheet="1"`. A value equal to [protection] changes
  /// nothing.
  ///
  /// Throws an [ArgumentError] named `password` for a password that is not
  /// 1 to 15 characters from U+0020 to U+007E (the message never repeats
  /// it), a [StateError] for a sheet that is not a worksheet or has no part
  /// and an [XlsxReadException] when the sheet cannot be read. Whatever it
  /// throws, nothing has changed.
  set protection(XlsxSheetProtection? value) {
    checkProtectionPassword(value?.password);
    final WorksheetPart part = _editablePart('protection');
    if (value == protection) return;
    final XmlNode? old = part.layoutElement('sheetProtection') as XmlNode?;
    final XmlNode? next = value == null
        ? null
        : applySheetProtection(old, value, part.elementPrefix);
    final ChangeLog log = _host.log;
    log.transaction(() {
      editLayout(
        log,
        part,
        'sheetProtection',
        () => part.setNode('sheetProtection', next),
      );
    });
  }

  /// Whether the sheet's `<sheetProtection>` stores a password: a `password`
  /// or a `hashValue`, whether or not the protection is on. The password
  /// itself is never read. Loads the sheet.
  bool get hasStoredPassword {
    final Object? node = _load()?.layoutElement('sheetProtection');
    return node is XmlNode && sheetHasStoredPassword(node);
  }

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
  @override
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
  /// [XlsxDate], [XlsxDecimal], [XlsxFormula], [XlsxHyperlink] or `null`.
  /// It is checked,
  /// repaired and reported as the writer does (`CellEncoder`), when it is
  /// set: text with characters XML forbids is cleaned with a warning, and a
  /// `NaN` throws now, so saving cannot fail on data. The cell keeps its
  /// style, except that a date in a General cell takes the writer's date
  /// format (appended to the styles), and its other attributes, which
  /// described the old value, are dropped. A cell the file lacks takes the
  /// style [styleAt] reports there, as a value typed in Excel does: the
  /// row's, else the column's; an index with no cell format gives it none,
  /// and a date in a General row or column takes a copy of that style with
  /// the date format. `null` clears the value: a styled cell stays as an
  /// empty styled cell, an unstyled one is removed, and nothing is made for
  /// a cell the file lacks.
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
  /// An [XlsxHyperlink] sets the cell to its text, a string, with the
  /// writer's hyperlink font (the theme's hyperlink color, underlined)
  /// beneath the cell's style: a plain link keeps the style the cell shows
  /// there (its fill and number format stay), and an [XlsxCell] of a link
  /// layers as an [XlsxCell] of a string does. The sheet gets the
  /// `<hyperlink>` the writer writes for it, replacing the one on exactly
  /// that cell; an address a link of the sheet already has shares its
  /// relationship, and the replaced link's relationship goes when no other
  /// link uses it. A value that is not a link leaves the cell's link, as
  /// Excel does ([removeHyperlink] removes it). A table's header cell takes
  /// no link, as it takes only text. All of it is one change. A link equal
  /// to the cell's [hyperlinkAt] changes nothing, neither the element nor
  /// the cell, and throws nothing for a link the writer would refuse; in an
  /// [XlsxCell] it leaves the element, and the cell takes the style as above.
  ///
  /// A shared formula's follower may be set and leaves its group. Throws a
  /// [StateError] for a cell inside an array or data-table formula (Excel
  /// refuses that too), for a sheet that is not a worksheet or has no part,
  /// and for an [XlsxCell] or a link when the styles part is not a
  /// SpreadsheetML `styleSheet` and for a link on a cell a link of several
  /// cells covers, an [UnsupportedError] for a shared formula's master (W5),
  /// an [ArgumentError] for any other type, a rich text without runs, a nested [XlsxCell], a value the
  /// encoder refuses, an invalid link (named by its field, as the writer's)
  /// or an invalid style (named by its field; an `XlsxLimitError` past the
  /// writer's limits, and for a sheet's 65,531st link), a
  /// [RangeError] outside Excel's grid, and an [XlsxReadException] when the
  /// sheet cannot be read (for a link, also the sheet's relationships).
  /// Whatever it throws, nothing has changed, except
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
        try {
          checkHyperlink(plain);
        } on ArgumentError {
          // A file may hold a link the writer refuses: set back, it is no
          // edit.
          if (hyperlinkAt(row, column) != plain) rethrow;
        }
      case XlsxCell():
        throw ArgumentError(
          'Cell ${cellRef(row, column)} on sheet "$name" nests an XlsxCell '
          'inside an XlsxCell.',
        );
      case null ||
          String() ||
          num() ||
          bool() ||
          XlsxRichText() ||
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
    final WorksheetPart part = _editablePart('cells');
    final bool sameLink =
        plain is XlsxHyperlink && hyperlinkAt(row, column) == plain;
    if (sameLink && !styled) return;
    if (plain is XlsxRichText && !styled && richTextAt(row, column) == plain) {
      return;
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
    // A link: the cell holds its text, and the sheet its element, found
    // before anything is recorded.
    final XlsxHyperlink? link = plain is XlsxHyperlink ? plain : null;
    final _LinkPlan? linkPlan = link == null
        ? null
        : _planLink(part, row, column, link);
    if (link != null) stored = link.text;
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
    final XlsxStyle? target = link != null
        ? withHyperlinkFont(
            styled
                ? layered
                : _styleOfIndex(
                    current == null
                        ? _inheritedIndex(store, row, column)
                        : current.style,
                  ),
          )
        : !styled
        ? null
        : stored == null
        ? (cellStyle == null ? null : layered)
        : _withDateFormat(layered, stored);
    final StylesPart? styles = target == null ? null : _stylesFor();
    final ChangeLog log = _host.log;
    log.transaction(() {
      if (link != null && !sameLink) {
        _applyLink(part, row, column, link, linkPlan!);
      }
      if (header != null && rename != null) {
        renameTableColumn(log, header.table, header.index, rename);
        _host.reader.package.setContent(header.partName, header.table);
      }
      RawCell? base = current ?? _cellOfInheritedStyle(store, row, column);
      int? Function(int? style, {required bool withTime}) dateStyle =
          _host.dateStyle;
      if (styled || link != null) {
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
        cellFont: stored is XlsxRichText
            ? (styled ? target : _styleOfIndex(base?.style))?.font
            : null,
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

  /// The runs of the rich text in the cell at [row] and [column], or `null`
  /// when the cell is no string, a plain string, or a string whose item has
  /// no `<r>` (phonetic runs alone do not make a rich text).
  ///
  /// A shared string reads from its `<si>` as kept, an inline string from
  /// its `<is>`; the runs are parsed when asked, so [rows] and [cellAt] cost
  /// nothing more for them. A run without an `<rPr>` has a `null` font; a
  /// run's font is as the file has it, so a rich text set by [setCell] on a
  /// styled cell reads back with the cell's font merged into each run. A
  /// value of an `<rPr>` that the font types cannot hold is read as absent
  /// and reported once, as `featureEntryInvalid` with the detail `rPr`.
  /// The value of the cell is the runs' text joined, as [cellAt] reads it.
  /// Loads the sheet. Throws a [RangeError] outside Excel's grid and an
  /// [XlsxReadException] when the sheet cannot be read.
  XlsxRichText? richTextAt(int row, int column) {
    _checkCell(row, column);
    final CellStore? store = _load()?.cells;
    final RawCell? cell = store?.cellAt(row, column);
    if (cell == null) return null;
    void warn(String detail) {
      if (_featureReported.add(detail)) {
        _warn(XlsxWarningCode.featureEntryInvalid, null, detail: detail);
      }
    }

    switch (cell.kind) {
      case RawCellKind.sharedString:
        final int? index = int.tryParse(cell.value ?? '');
        if (index == null) return null;
        _host.loadTables();
        return _host.sharedStrings?.richTextAt(index, warn);
      case RawCellKind.inlineString:
        final OpaqueXml? inline = cell.inline;
        return inline == null ? null : readRichTextOf(inline, warn);
      default:
        return null;
    }
  }

  /// The style Excel shows at [row] and [column], or `null` for the
  /// default.
  ///
  /// It is the cell's own style when the cell exists (even without a
  /// value), else the row's style when the row has `customFormat="1"`, else
  /// the style of the `<col>` holding the column; style index 0, and an
  /// index with no cell format in the styles part (which Excel shows as the
  /// default), give `null` in both. Read with
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
    return _styleOfIndex(_inheritedIndex(store, row, column));
  }

  /// The style index a cell the file lacks shows at [row] and [column]: the
  /// row's, else the column's, or `null` when neither has one.
  int? _inheritedIndex(CellStore store, int row, int column) =>
      _rowStyleIndex(store, row) ?? _columnStyleIndex(column);

  /// An empty cell of the style a cell the file lacks shows at [row] and
  /// [column], for a plain value to keep; `null` when that is the default
  /// or an index with no cell format, and when the styles part is missing
  /// or untyped (no index has a cell format then).
  RawCell? _cellOfInheritedStyle(CellStore store, int row, int column) {
    final int? index = _inheritedIndex(store, row, column);
    return _hasCellFormat(index)
        ? RawCell(kind: RawCellKind.number, style: index)
        : null;
  }

  /// Whether [index] is a style index above 0 with a cell format.
  bool _hasCellFormat(int? index) {
    final StylesPart? styles = _host.styles;
    return index != null &&
        index > 0 &&
        styles != null &&
        index < styles.cellFormatCount;
  }

  /// The style at cell format [index], or `null` for no index, index 0 and
  /// an index with no cell format (which Excel shows as the default).
  @override
  XlsxStyle? _styleOfIndex(int? index) =>
      _hasCellFormat(index) ? _host.styles!.styleOf(index!) : null;

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
  /// is removed; a cell already at index 0 stays as written, `s="0"`
  /// included.
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
    if (style == null && index == 0) return;
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

  /// The cells of the loaded worksheet part, to set their [what]. Throws a
  /// [StateError] for a sheet without a part or that is not a worksheet.
  @override
  CellStore _editableCells(String what) => _editablePart(what).cells;

  /// The loaded worksheet part, to set its [what]. Throws a [StateError]
  /// for a sheet without a part or that is not a worksheet.
  @override
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
  @override
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

  @override
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
  /// index 0, or an index with no cell format).
  XlsxStyle? _rowStyle(CellStore store, int row) =>
      _styleOfIndex(_rowStyleIndex(store, row));

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
  int? _columnStyleIndex(int column) =>
      parseStyleIndex(_part?.columnRunAt(column + 1)?.attribute('style'));

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
  @override
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
    for (final ({String partName, TablePart table}) t in found) {
      for (final String detail in t.table.problems) {
        if (_featureReported.add(detail)) {
          _warn(XlsxWarningCode.featureEntryInvalid, null, detail: detail);
        }
      }
    }
    return _tables = found;
  }

  /// The loaded part, loading it on first use; `null` for a sheet without
  /// a part.
  @override
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

  @override
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
