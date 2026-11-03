# XLSX workbook model

`XlsxWorkbook` opens an XLSX file from bytes, or starts empty, lets a caller
read and set cell values, and saves the file again. Saving keeps everything
the caller did not change: the model is the single source of every save.
Decision [`0009`](decisions/0009-phase-3-workbook-model.md) sets the scope
and the fidelity standard.

This page covers milestone W1, the foundation: open and save with no loss, and
generate values; and milestone W2, styles and layout typed. Sheet and workbook
features, objects and structural editing arrive in W3 to W5.

```dart
final XlsxWorkbook book = XlsxWorkbook.open(bytes);
book.sheet('Prices').setCell(0, 1, 42);
final Uint8List saved = book.save().bytes;
```

A sheet loads when it is first used; until then its part is saved from its
original bytes. A loaded sheet is held in a compact cell store (no object per
cell) and saved through the one cell encoder (`cell_encoder.dart`), so it
writes values as the writers do. What the model does not type (W1 types only
cells, the workbook's sheet list and `date1904`, the shared strings and the
number formats of the styles; W2 adds the rest of the styles, rows, columns,
merges, views and tab colours) is kept as opaque XML at its position and
written back, with the namespace declarations it needs.

## What W1 does and does not do

- **Edits.** `setCell` takes a `String`, `num`, `bool`, `DateTime`,
  `XlsxDate`, `XlsxDecimal`, an `XlsxFormula` without a group, or `null`.
  Hyperlinks and rich text throw `UnsupportedError` until W3 and W4. Editing
  a shared formula's master throws until W5. Since W2 `setCell` also takes an
  `XlsxCell`, layered as the writer layers it (see "What W2 adds").
- **Fidelity.** An opened workbook saved without a change is semantically
  equal to the input, part by part, as the test-side comparer
  (`tool/src/part_compare.dart`) defines it. Byte identity is not a goal.
  What was repaired or could not be read exactly is in `XlsxWorkbook.warnings`
  (the reader's and the writer's codes); W1 adds no warning code.
- **Stricter than `XlsxReader` on entries nothing reads.** `open` inflates
  every ZIP entry once, checks its declared size and CRC-32 and discards it,
  so a damaged part the reader would never touch is an `XlsxReadException`
  (`corruptZip`) from `open`: the model writes the whole package and must be
  able to read all of it. The cost is one extra inflate of every entry, shown
  in [`benchmark.md`](benchmark.md), "Model figures". Parts the model did not
  load are inflated again when saving.
- **No owner round trip yet.** `test/fixtures/owner/` holds no XLSX files
  (they arrive with R5), so no Excel or Google Sheets file the owner made is
  round-tripped by a test. The owner's Excel check for W1 opens two of their
  own files, edits a cell and saves ([`excel-checks.md`](excel-checks.md),
  "W1").
- **Merges are typed since W2.** The first `<mergeCells>` of a sheet is read
  when the sheet loads, and `XlsxReadLimits.maxMerges` applies to it (see
  "Merges").
- **A workbook with no sheet, or only hidden ones, saves as it came** when it
  was opened. Only a workbook started with `XlsxWorkbook()` needs a visible
  sheet to save.
- **Formulas stay stale until Excel recalculates.** A cell change in a
  workbook with formulas sets `fullCalcOnLoad="1"`, and the cached results
  of formulas the model did not change are kept. Excel recomputes on open;
  `XlsxReader` and the model's own `cellAt` read the stale values.
- **Memory.** A loaded sheet's store takes less memory than its sheet XML
  in the 100,000 by 12 benchmark: an estimate of 33.9 MB of store (29 bytes
  a cell) against 43.6 MB of XML, 0.78 times, the same on the VM and in
  Chrome (see [`benchmark.md`](benchmark.md), "Model figures"; process memory
  is higher but includes the XML and garbage). A formula-dense sheet (50,000
  by 12 formulas, half shared-formula followers, half normal formulas each
  with its own text) takes 23.7 MB against 32.4 MB of XML, 0.73 times:
  formulas are kept as interned templates and pooled text, with a 4-byte
  reference per cell. Reading every row leaves nothing per cell behind; only
  a cell with a reading problem is remembered, to report it once.
- **`addSheet` is not yet a change.** It does not go through the change log
  until W5, so a workbook opened, given a sheet with `addSheet` and saved
  without a `setCell` keeps its `calcChain` and gets no `fullCalcOnLoad`.
- **Nothing is compacted.** Shared strings and cell formats that no cell
  uses any more stay in their parts; W1 appends and never removes.

## What W2 adds

`XlsxSheet` reads and sets what a cell, a row, a column and a sheet look like.
`XlsxWorkbook` sets which sheet is active and resolves colours.

```dart
final XlsxSheet sheet = book.sheet('Prices');
sheet
  ..setCell(1, 0, const XlsxCell(42, style: bold))
  ..setStyle(1, 1, money)
  ..setColumn(1, const XlsxColumn(width: 30))
  ..setRowFormat(1, const XlsxRowFormat(height: 24))
  ..merge(const XlsxRange(0, 0, 0, 3))
  ..view = const XlsxSheetView(pane: XlsxPane.frozen(rows: 1))
  ..tabColor = const XlsxColor.rgb(0x00B050);
book.sheets.last.visibility = XlsxSheetVisibility.hidden;
book.activeSheet = sheet;
```

- **Reading and setting.** `styleAt`, `setStyle`, `rowFormat`, `setRowFormat`,
  `column`, `setColumn`, `defaultSizes`, `setDefaultSizes`, `merges`, `merge`,
  `unmerge`, `view`, `tabColor`, `outlineSummary`, `setOutlineSummary` and
  `visibility` on a sheet; `activeSheet`, `indexedColors` and `resolveColor`
  on the workbook. `XlsxRowFormat`, `XlsxColorKind` and the `XlsxColor`
  getters are the new public types. The values are the writer's, checked by
  the writer's checks.
- **Styles are append-only.** A style a cell needs reuses an entry that says
  exactly the same, or is added at the end. No index moves, so a sheet that
  was never loaded keeps its meaning. Nothing is compacted: an entry no cell
  uses any more stays.
- **Named cell styles and what the model does not type stay.** `cellStyleXfs`,
  `cellStyles`, `dxfs` and the rest of the part are kept as written. An entry
  that holds more than the value types can say is read as far as it can be,
  stays as written and is never reused.
- **Two new warning codes.** `styleEntryInvalid` (a workbook warning, sheet
  `''`) and `layoutInvalid` (a sheet warning).
- **Theme colours.** The theme's colour scheme and Excel's tint are read by
  `lib/src/common/theme_colors.dart`, which DOCX shares. It knows slots by
  their DrawingML names (`dk1`, `lt1`, ...). The public colour types stay per
  format: `XlsxColor` here, `DocxColor` in DOCX; phase 4 decides on any neutral
  names.
- **Parity.** A fixture rebuilt with the model saves semantically equal to the
  writer's, apart from the differences named under "Parity with the writer".
- **Recalculation.** Only a cell value or formula change touches `calcChain`
  and `fullCalcOnLoad`. A style or layout edit does not.

## Rules the model enforces

A file the model cannot open throws `XlsxReadException` with the reader's
`reason`. A cell or part it cannot read exactly is a warning. A programmer's
error (a value type that is not supported, a position outside the grid, a
cell inside an array formula) throws, and a failed `setCell` changes nothing.
Nothing is dropped silently.

### Opening and saving

| Case | Behaviour | Why | Test |
|---|---|---|---|
| Open, then save with no change | every part of the saved file is semantically equal to the input's, none added or lost (writer fixtures, producer files, and a workbook whose sheets were never loaded) | spec 4.2: behaves the same in Excel | `test/xlsx/model/round_trip_test.dart` |
| A part the model never loaded | written from its original bytes | nothing can have changed it, so there is no dirty flag to get wrong | `test/opc/package_test.dart` ("unloaded parts are written from their original bytes"), `test/xlsx/model/xlsx_workbook_open_save_test.dart` |
| A part the model loaded | always serialized from the model, changed or not; what it does not type is kept opaque at its position, with the namespace declarations it needs | every open-save then exercises the serializer | `test/xlsx/model/worksheet_part_test.dart`, `test/xlsx/model/workbook_part_test.dart`, `test/xlsx/model/styles_part_test.dart`, `test/opc/opaque_xml_test.dart` |
| A relationships part nobody read or changed | written from its original bytes, even when empty; a parsed or changed one is serialized from the model | an odd but untouched file stays intact | `test/opc/package_test.dart` ("input relationships parts") |
| Unknown attributes on typed elements (`x14ac:dyDescent`, `xr:uid`, `cm`, `vm`), children of `<c>`, `<row>` and `<sheetData>` it does not type, `mc:Ignorable` | kept, with the prefixes they use declared; a foreign child of `<sheetData>` moves to its end | the anti-goal: nothing lost on open-then-save | `test/xlsx/model/worksheet_part_test.dart`, `test/xlsx/read/raw_rows_test.dart`, `test/xlsx/cell_encoder_model_test.dart` |
| `<sheetId>` missing, unparsable or `0` on an opened sheet | written back as it was; `addSheet` takes the largest parsable id plus 1 | read then write changes nothing the caller did not change | `test/xlsx/model/workbook_part_test.dart` ("a sheetId that is not an unsigned int") |
| Part names and relationship ids of an opened file | kept; a new part takes a name and an id nobody uses | opaque parts may refer to the old names | `test/opc/package_test.dart` ("free names"), `test/xlsx/model/workbook_part_test.dart` |
| `dimension` and row `spans` of a loaded sheet | recomputed on save (the comparer ignores them in the round trip only) | spec 4.4 | `test/xlsx/model/worksheet_part_test.dart` ("dimension and spans") |
| `date1904` workbook | dates are set and read in the 1904 system, and the flag is kept | Quds shifted every date by four years | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("dates in a 1904 workbook"), `test/xlsx/model/workbook_part_test.dart` |
| A macro-enabled workbook | `vbaProject.bin` and the content types are kept; the macros are never read, run or edited | pass-through, not macro support (decision 0003) | `test/xlsx/model/xlsx_workbook_open_save_test.dart` ("an xlsm keeps vbaProject.bin") |
| An opened workbook with no sheet, or only hidden ones | saves as it came | the model must not refuse to write back a file it opened unchanged | `test/xlsx/model/xlsx_workbook_open_save_test.dart` |
| `XlsxWorkbook()` saved with no sheet, or no visible one | `StateError` with the writer's messages | the writer's rule for a new file | `test/xlsx/model/xlsx_workbook_open_save_test.dart` |
| `saveTo` | sends the bytes `save` returns and closes the sink; with no sheet to save the sink stays open | same bytes as the in-memory path | `test/xlsx/model/xlsx_workbook_open_save_test.dart` |
| A new workbook with values | equals what `XlsxWriter` writes for the same values, fixture by fixture | one encoder, one behaviour | `test/xlsx/model/parity_test.dart` |

### Tables and bookkeeping

| Case | Behaviour | Why | Test |
|---|---|---|---|
| Strings set while a sheet is unloaded | appended to the shared strings; existing indexes stay, unused entries stay | an unloaded sheet keeps its original indexes | `test/xlsx/model/xlsx_workbook_open_save_test.dart` ("an unloaded sheet keeps its strings") |
| `count` of the shared strings | left out while a sheet is unloaded, recounted when every sheet is loaded | the unloaded sheets' references are not counted | `test/xlsx/model/xlsx_workbook_open_save_test.dart` ("shared strings count") |
| Root attributes and extra children of `<sst>` | kept when the strings load | nothing lost | `test/xlsx/model/xlsx_workbook_open_save_test.dart` ("keeps the sst root and its extras") |
| Any change of a cell's value or formula | `calcChain` is dropped (part, relationship, content type), touching only the workbook's relationships; `fullCalcOnLoad="1"` is set when the workbook has formulas | a stale chain makes Excel repair the file; Excel must recompute | `test/xlsx/model/xlsx_workbook_bookkeeping_test.dart` |
| A change in a workbook without formulas that is fully loaded | no `calcPr` change | nothing to recalculate | `test/xlsx/model/xlsx_workbook_bookkeeping_test.dart` |
| A style, row, column, merge, view, tab colour, visibility or active sheet edit | `calcChain` and `calcPr` stay; nothing else changes | spec 4.4 says "when any cell changes", and only what a change touches differs; a stale chain matters only when cells change | `test/xlsx/model/xlsx_workbook_tabs_test.dart` ("calcChain and fullCalcOnLoad follow cell changes only") |

### Setting cells

| Case | Behaviour | Why | Test |
|---|---|---|---|
| A value the encoder repairs (forbidden XML characters, text over 32,767 characters) | repaired when set, with the writer's warning; a `NaN` throws then | saving cannot fail on data | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("text escaping"), `test/xlsx/cell_encoder_model_test.dart` |
| Setting a cell | replaces its content and the attributes that described the old value (`cm`, `vm`, `ph`, children); a valid style stays | the old metadata described the old value | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("replaces the value-tied attributes"), `test/xlsx/model/xlsx_workbook_bookkeeping_test.dart` ("setting one cell changes only that cell") |
| A plain value in a cell the file lacks | takes the style `styleAt` reports there, the row's (`customFormat="1"`) over the column's, so `styleAt` is the same before and after; a date in a General row or column takes a copy of that format with the date format, and everything but the number format stays; a style index of 0 or one with no cell format, and a missing or untyped styles part, give no style; `null` makes no cell | Excel's own behaviour when you type there, and the writer's layers | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("a plain value in a cell the file lacks") |
| `null` | a styled cell stays as an empty styled cell; an unstyled one is removed | clearing keeps the format | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("clearing keeps the style") |
| A date in a General cell | takes the writer's date format, appended to `numFmts` and `cellXfs`; a date format stays; another format stays with the writer's date warning; a broken style counts as General | spec 4.12: dates behave as the writer does | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("a date on a General cell", "a broken style"), `test/xlsx/model/styles_part_test.dart` ("withNumberFormat") |
| A table's header cell | takes only text: the column's `name` in the table part is set to it (`tableColumnRenamed`), the rest of the part kept character for character; empty text or `null` becomes `ColumnN`, a name another column has (ignoring case) gets a number (`tableHeaderAdjusted`); another value is a `StateError`, over 255 characters an `ArgumentError`; formulas that use the old name are not rewritten (W5); undo restores the name | Excel repairs a table whose header cell and column name differ (W1 Excel check, 2026-11-03) | `test/xlsx/model/table_header_test.dart` |
| A cell inside an array or data-table formula, its master included | `StateError`, permanent | Excel refuses it too | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("editing formula groups"), `test/xlsx/model/primitives_test.dart` |
| A shared formula's child | leaves the group; the others stay | the child's formula stays correct | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("editing formula groups") |
| A shared formula's master | `UnsupportedError` until W5 | the children need reference shifting | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("editing formula groups") |
| `XlsxHyperlink`, `XlsxRichText` (also inside an `XlsxCell`) | `UnsupportedError` naming the milestone (W3, W4) | not typed yet | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("unsupported value types") |
| `XlsxCell(value, style: s)` | the value is set as a bare one; the style is the writer's layering, the row's style (with `customFormat="1"`) merged with `s`, appended when no cell format matches; a date takes the writer's date format only when that style sets none; an `XlsxCell` of `null` leaves an empty cell of that style, or none when it has no style or the default | the model and the writer give the same cell format | `test/xlsx/model/xlsx_sheet_style_test.dart` ("XlsxCell layers like the writer", "XlsxCell dates take the writer format rule", "an XlsxCell of null") |
| `styleAt` | the cell's own style when the cell exists, else the row's with `customFormat="1"`; index 0 is `null` | what Excel shows there | `test/xlsx/model/xlsx_sheet_style_test.dart` ("styleAt reads cell and row styles") |
| `setStyle` | sets exactly the style, no layering; an equal style keeps its index; a new one is appended, so no index moves and an unloaded sheet's styles stay; `null` gives index 0 and removes a cell left with nothing | appending keeps every other cell's format | `test/xlsx/model/xlsx_sheet_style_test.dart` |
| A style edit that throws (an invalid field, the writer's limits, an untyped styles part) | the registry's `ArgumentError` or `XlsxLimitError`, or a `StateError`; the styles a failed transaction appended are rolled back (`StylesAppendChange`) | atomic edits | `test/xlsx/model/xlsx_sheet_style_test.dart` ("a failed setStyle changes nothing", "rolls back the styles"), `test/xlsx/model/primitives_test.dart` ("appendStyle") |
| A style set, or a date given a format, in a file without `xl/styles.xml` | the writer's empty styles are made in memory and join the package on save only when they hold an appended entry; an edit that throws or is undone adds no part | atomic edits, spec 4.8 | `test/xlsx/model/xlsx_sheet_style_test.dart` ("a workbook without styles") |
| `styleAt` on an `s` with no cell format | `null`, and `setStyle` does not keep that index | Excel shows the default | `test/xlsx/model/xlsx_sheet_style_test.dart` ("an index outside cellXfs") |
| A style no cell format matches | appended to `cellXfs`, with the font, fill, border and number format it needs reused when equal to an exact entry and appended otherwise; a new code takes a `numFmt` id no entry uses | append-only: no index moves | `test/xlsx/model/styles_part_test.dart` ("a new style appends", "a style matching an exact entry reuses it", "a new code never takes a numFmt id the file uses") |
| A cell format the value types cannot hold in full (`quotePrefix`, a named style `xfId`, unknown children) | reads as far as it can, stays as written and is never reused for a style that looks like it | reuse would change what the cell shows | `test/xlsx/model/styles_part_test.dart` ("an inexact xf reads but stays as written") |
| A file already past a writer limit (more fonts than `XlsxLimits.maxFonts`, say) | opens and saves; reuse still works; `XlsxLimitError` only when an edit must append to a table at or over its limit | a data condition must not become a programmer error, and only appends can pass a limit | `test/xlsx/model/styles_part_test.dart` ("a file past the font limit reuses fonts and throws to add one") |
| `setStyle` of what `styleAt` read, on a dangling or invalid `s` | the `s` is dropped, so this is a change and not a no-op, unlike on every other cell; `setStyle(null)` drops it too | `styleAt` says none, and the model never keeps an index it cannot read | `test/xlsx/model/xlsx_sheet_style_test.dart` ("re-setting a dangling or invalid s drops it", "setStyle(null) on an empty styled cell removes it") |
| A style entry that cannot be read exactly | `styleEntryInvalid` in `XlsxWorkbook.warnings`, a workbook warning (sheet `''`), when the entry is first read, even by a call that then throws | data problems warn | `test/xlsx/model/xlsx_sheet_style_test.dart` ("warns on the workbook") |
| `rowFormat` | the row's `ht` (only with `customHeight="1"`), `hidden`, `outlineLevel`, `collapsed` and style (`s` with `customFormat="1"`, as `styleAt` reads a row's) as an `XlsxRowFormat`; a row the file lacks is the default | what Excel shows for the row | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("rowFormat reads m2_columns_rows") |
| `setRowFormat` | the writer's attributes in the writer's order (`ht`, `hidden`, `customHeight`, `outlineLevel`, `collapsed`; `s` with `customFormat="1"` first); a changed field is replaced where it stood, any other attribute (`x14ac:dyDescent`, `thickBot`) and any field equal to the current one is kept as written; a row left with nothing is removed; checked with `checkRowHeight` and `checkOutlineLevel` (`ArgumentError` named `height` or `outlineLevel`) | a row format the writer would write | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("setRowFormat writes what the writer writes", "unknown row attributes are kept") |
| `XlsxRowFormat.style` | written as the row's `s` with `customFormat="1"`, which styles the row's empty cells as Excel's row format does; the writer never writes a row `s` and merges a row style into each cell instead, so the same look differs in the XML | Excel's model of a row format | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("setRowFormat writes what the writer writes"), `test/xlsx/model/parity_test.dart` ("fixtures built with the model equal the writer's") |
| `sheetFormatPr/@outlineLevelRow` on save | the larger of the kept value and the deepest row `outlineLevel`, the rest of the element kept; a missing element is made (with the required `defaultRowHeight`) only when an edit goes deeper than the file's rows and columns did, so an unchanged file gains nothing | Excel needs the level to draw the outline; a file that had none opened without it | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("outlineLevelRow") |
| A row attribute that cannot be read (an `ht` of `abc`, a level of 9) | `layoutInvalid` once per attribute, a sheet warning; the typed value is the default and the attribute is saved as written until that field is set | data problems warn | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("a bad ht warns layoutInvalid and stays as written") |
| `column` | the `<col>` holding the column: `width` (whenever it is a width; `customWidth` only says it was set by hand, so writer columns without a width read 9.140625), `style`, `hidden`, `outlineLevel`, `collapsed` as an `XlsxColumn`; `null` for a default column or one whose `<col>` sets nothing the model reads | what Excel shows for the column | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("column reads widths, styles, hidden and outline") |
| `setColumn` | the `<col>` is split into up to three; the outer runs keep every attribute (`bestFit`, ...), the column replaces changed fields where they stood and keeps the rest, a new `<col>` is written as the writer writes it (`width` always), and a column that ends up writing the same `<col>` as a neighbour joins it; `null` resets; `setColumn(i, column(i))` changes nothing, and a value that writes the same `<col>`s records no change; checked with `checkColumnWidth` and `checkOutlineLevel` (`ArgumentError` named `column.width`, `column.outlineLevel`, `column.style.<field>`) | a column the writer would write | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("setting one column of a range splits it", "new columns write what the writer writes") |
| A `<cols>` that is not plain (a `<col>` with children or declarations, an invalid, unsorted or overlapping `min`/`max`, none at all), and a second `<cols>` | kept as written; `column` reads none of it and `setColumn` throws `StateError` | the model never rewrites what it cannot type | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("a cols that is not plain is kept and cannot be edited") |
| `styleAt` and `XlsxCell` layers with columns | `styleAt` is the cell's own style, else the row's (`customFormat="1"`), else the column's; `setCell` of an `XlsxCell` layers the column, then the row, then the cell, as the writer does (a row with an explicit `s="0"` shows the default and takes no column style) | what Excel shows; the writer's layers | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("styleAt: cell, then row, then column", "an XlsxCell over a column style takes the writer cell formats") |
| `defaultSizes`, `setDefaultSizes` | `sheetFormatPr/@defaultRowHeight` (only with `customHeight="1"`) and `@defaultColWidth`; set exactly (`null` is Excel's own) and written as the writer writes them, the rest of the element (`baseColWidth`, ...) kept; a `sheetFormatPr` with element children reads but throws `StateError` on set | the writer's `defaultSizes` | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("default sizes read and set") |
| `sheetFormatPr/@outlineLevelCol` on save | as `outlineLevelRow`, from the deepest column `outlineLevel` of the first plain `<cols>` | Excel needs the level to draw the outline | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("outlineLevelCol is the larger of the kept and the deepest") |
| Any other type, or a position outside the grid | `ArgumentError`, `RangeError` | programmer errors | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` |
| A sheet that is not a worksheet (a chartsheet) | `StateError` at the call | its cells cannot be set | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("not a worksheet") |
| Anything `setCell` throws | nothing has changed, the change log's `hasChanges` included; every mutation runs in a transaction | atomic edits | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("a failed setCell changes nothing"), `test/opc/change_log_test.dart` |
| 10,000 cells on a sheet with formulas | linear time | the formula-group index is kept, not scanned per cell | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("takes linear time"), `test/xlsx/model/cell_store_test.dart` ("group masters") |
| A change recorded outside a transaction | `StateError`: every mutation runs in a transaction, so it is always undoable as a set | an unrecorded change cannot be undone | `test/opc/change_log_test.dart` ("record outside a transaction throws") |
| A revert that throws while a transaction rolls back | the other reverts still run, then a `StateError` names the original error and the failed reverts; the model may be inconsistent | a silent half-revert would break atomicity | `test/opc/change_log_test.dart` ("a revert that throws does not stop the rollback") |

### Merges

| Case | Behaviour | Why | Test |
|---|---|---|---|
| `merges` | the first `<mergeCells>`, as `XlsxReader.mergesAt` reads it; empty without one | one reading of a file | `test/xlsx/model/xlsx_sheet_merge_test.dart` ("merges read like XlsxReader.mergesAt") |
| A second `<mergeCells>` | kept as written, in place; only the first is typed, read and edited | Excel has one; the model never rewrites what it cannot type | `test/xlsx/model/xlsx_sheet_merge_test.dart` ("only the first mergeCells is typed") |
| `merge`, `unmerge` | written as the writer writes them, the group in schema position, `count` recomputed; cells keep their values; the group goes with its last child | a merge the writer would write | `test/xlsx/model/xlsx_sheet_merge_test.dart` ("merge and unmerge write what the writer writes", "unmerge keeps the cell values") |
| A single cell, a range outside the sheet or reversed, an overlap with a merge or a table | `ArgumentError` named `range`, an overlap naming both ranges; nothing changes | the writer's rule | `test/xlsx/model/xlsx_sheet_merge_test.dart` ("an overlap throws naming both ranges", "merge refuses an overlap with a typed table") |
| A `<mergeCell>` that cannot be read | left out of `merges`, kept as written, `mergeRangeInvalid` | data problems warn | `test/xlsx/model/xlsx_sheet_merge_test.dart` ("an unreadable mergeCell is kept and warned") |
| `XlsxReadLimits.maxMerges` | applied per sheet when the sheet loads (`limitExceeded`); the reader counts across the sheets whose merges it has cached | a loaded sheet holds its own merges | `test/xlsx/model/xlsx_sheet_merge_test.dart` ("maxMerges applies on load", "maxMerges counts per sheet") |

### Views, tab colours and sheets

| Case | Behaviour | Why | Test |
|---|---|---|---|
| `view` | the first `<sheetView>` of the first `<sheetViews>`; none is the default view; an attribute that cannot be read is its default, `layoutInvalid` once, saved as written until set | data problems warn | `test/xlsx/model/xlsx_sheet_view_test.dart` ("view reads m2_views", "unreadable view attributes read as defaults and warn once") |
| Setting `view` | only the attributes of fields that change are written, as the writer writes them; `tabSelected`, `topLeftCell` and other children stay; an equal view keeps the element as written | only what the change touches differs | `test/xlsx/model/xlsx_sheet_view_test.dart` ("setting a view writes what the writer writes", "a view change edits the attributes and keeps the rest", "an equal view keeps the element as written") |
| A `<selection>` when the pane changes | one that names a part the new pane lacks is dropped; the others stay; a new pane gets a selection of its active part when none names it | a selection must name a part the pane has | `test/xlsx/model/xlsx_sheet_view_test.dart` ("removing a pane drops the selections that name its parts", "changing a pane keeps the selections of parts that remain", "a new pane gets a selection of its active part") |
| `tabColor`, `outlineSummary` | read from and written to `<sheetPr>`, made in schema position, removed when nothing is left in it; its attributes and other children stay; a bad tab colour reads as none and warns `layoutInvalid`, and `tabColor = null` removes it; setting one throws `ArgumentError` | the writer's limits | `test/xlsx/model/xlsx_sheet_view_test.dart` ("tab colour and outline summary read and set", "sheetPr keeps its attributes and other children", "a bad tab colour throws", "tabColor = null removes a colour that cannot be read") |
| `visibility` | a tab's `state`; `visible` removes the attribute; hiding the active sheet makes the first visible sheet active, as Excel does | Excel opens on a visible sheet | `test/xlsx/model/xlsx_workbook_tabs_test.dart` ("visibility round-trips through XlsxReader.sheets", "hiding the active sheet moves the active tab") |
| Hiding the last visible sheet | `StateError`; nothing changes; a sheet already hidden can change to very hidden | Excel needs a visible sheet | `test/xlsx/model/xlsx_workbook_tabs_test.dart` ("hiding the last visible sheet throws", "the guard only applies to hiding a visible sheet") |
| `activeSheet` | the first `workbookView`'s `activeTab`, the first sheet past the last tab or without one | what Excel opens on | `test/xlsx/model/xlsx_workbook_tabs_test.dart` ("activeSheet matches the writer's active tab", "activeSheet defaults to the first sheet") |
| Setting `activeSheet` | sets `activeTab` and moves `tabSelected` from the sheet that was active to the new one, loading both; the sheet that is active already writes nothing, even on a file without `activeTab` or `tabSelected`; a sheet of another workbook is an `ArgumentError`, one that is not visible a `StateError` | an opened file's old `tabSelected` must move, or Excel groups the sheets | `test/xlsx/model/xlsx_workbook_tabs_test.dart` ("setting activeSheet moves activeTab and tabSelected", "setting the active sheet again is a no-op", "an invalid activeSheet changes nothing") |
| The active sheet on a chartsheet or a sheet without a part | only `activeTab` changes: `tabSelected` is set and cleared on worksheets only, so a chartsheet may keep its own `tabSelected="1"` | its part is not typed; Excel reads several selected tabs as a group | `test/xlsx/model/xlsx_workbook_tabs_test.dart` ("a sheet without a worksheet part only changes activeTab") |

### Colours

| Case | Behaviour | Why | Test |
|---|---|---|---|
| A theme colour's index | SpreadsheetML's order: 0 `lt1`, 1 `dk1`, 2 `lt2`, 3 `dk2`, 4 to 9 `accent1` to `accent6`, 10 `hlink`, 11 `folHlink`; the first four are swapped against the theme part's own order | what Excel shows for `theme="0"` | `test/xlsx/model/palette_test.dart` ("theme colours resolve with the swapped first four") |
| A tint | Excel's: Windows' integer HLS with `HLSMAX` 240, on the shared `applyTint`; one that is not finite or not within -1 to 1 is ignored | all six of Excel's palette pins hold | `test/common/theme_colors_test.dart` ("tint matches Excel"), `test/xlsx/model/palette_test.dart` ("a tint that is not finite or not in -1..1 is ignored") |
| No theme, an unreadable one, a missing slot, `auto` | `resolveColor` gives `null` and throws nothing; the theme part stays unloaded, so saving writes its bytes | nothing to resolve | `test/xlsx/model/palette_test.dart` ("a missing slot, an unknown index or no theme resolves as null", "a theme that cannot be parsed resolves as missing", "resolving does not load the theme") |
| `indexedColors` | the file's `<indexedColors>`, missing entries filled from the default palette (ECMA-376 Part 1, 18.8.27); indexed 64 and 65 and anything past them resolve as `null` | the palette `<color indexed>` shows | `test/xlsx/model/palette_test.dart` ("a custom palette wins", "indexed colours outside the palette resolve as null"), `test/xlsx/model/styles_part_test.dart` ("indexedColors fills missing entries from the default palette") |
| `indexedColors` or an indexed `resolveColor` on a broken styles part | `XlsxReadException`, like any call that first loads a part; an `rgb` colour loads nothing | spec 4.12: laziness moves the failure to first use | `test/xlsx/model/palette_test.dart` ("a broken styles part throws from the palette") |

### Parity with the writer

| Case | Behaviour | Why | Test |
|---|---|---|---|
| A fixture rebuilt with the model | semantically equal to the writer's: `m1_values`, `m1_dates`, `m1_sheets`, `m2_styles`, `m2_columns_rows`, `m2_style_precedence`, `m2_views`, `m2_merges_filter`, `m2_formula_xstring` | one way to write a value | `test/xlsx/model/parity_test.dart` ("fixtures built with the model equal the writer's") |
| `tabSelected` (named difference) | setting the model's `activeSheet` to another sheet writes `tabSelected="1"`, the writer never does; Excel selects the active tab either way | an opened file's old `tabSelected` must move, and the writer's output is pinned | `test/xlsx/model/parity_test.dart` ("fixtures built with the model equal the writer's") |
| The tab position of `m1_sheets` (named difference) | the writer's `addSheet(position: 0)` has no model equivalent until W5, so the expected `workbook.xml` moves the first tab last and lowers `activeTab` | structural editing is W5 | `test/xlsx/model/parity_test.dart` ("fixtures built with the model equal the writer's") |
| Auto filters (named difference) | `m2_merges_filter` and `m2_formula_xstring` are compared without `<autoFilter>` and the defined names that hold it | auto filters are W3 | `test/xlsx/model/parity_test.dart` ("fixtures built with the model equal the writer's") |
| Re-setting what was read | every style, row format, column, default size, view, tab colour, outline summary and merge set back to what it reads changes nothing, on every writer fixture and producer file; a dangling or invalid `s` is the exception (see "Setting cells") | typing must not alter output | `test/xlsx/model/round_trip_test.dart` ("re-setting what was read changes nothing") |

### Reading

| Case | Behaviour | Why | Test |
|---|---|---|---|
| `cellAt` and `rows` | show what `XlsxReader` shows for the saved file | one decoder | `test/xlsx/model/xlsx_workbook_reading_test.dart` |
| A value that cannot be read exactly | a warning, once per cell however often it is read, again after it is set; only such a cell is remembered, so reading clean cells costs nothing per cell | as the reader | `test/xlsx/model/xlsx_workbook_reading_test.dart` ("reading clean cells remembers nothing per cell") |
| A formula cell's group from `cellAt` | found from the sheet's group masters; on malformed groups (overlaps, a follower outside its master's range) it may differ from the group `rows` gives, which follows the reader's pass | a lookup must not scan the sheet | `test/xlsx/model/xlsx_workbook_reading_test.dart` |
| A sheet the workbook lists without a part | kept, reads as empty, `sheetPartMissing` | the model must open what the reader opens | `test/xlsx/model/xlsx_workbook_open_save_test.dart` |
| A sheet broken on first access, or a broken styles part | `XlsxReadException` from the first call that loads it, not from `open`; a broken sheet nobody loads is saved from its bytes | spec 4.12: laziness moves the failure to first use | `test/xlsx/model/xlsx_workbook_open_save_test.dart` ("a broken sheet throws on first access") |
| A styles part whose root is not `<styleSheet>` | loads as untyped: General formats, written back unchanged; a date set there keeps its style and warns `dateInNonDateFormat` | the model opens what the reader opens; data problems warn | `test/xlsx/model/styles_part_test.dart` ("an untyped part"), `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("a date where no date style can be added warns") |

### Untrusted input

| Case | Behaviour | Why | Test |
|---|---|---|---|
| Every limit of `XlsxReadLimits` | applied as the reader applies it, by `open` or on first use of a sheet (`maxMerges` per sheet, see "Merges") | the file is untrusted input (decision 0007) | `test/xlsx/read/hostile_files_test.dart` |
| A damaged, truncated or CRC-mismatching entry, even one no sheet reads | `XlsxReadException` (`corruptZip`) from `open` | the model verifies every entry up front | `test/xlsx/model/xlsx_workbook_open_save_test.dart` ("open checks every entry"), `test/xlsx/read/hostile_files_test.dart` |
| Not a ZIP, encrypted, Strict, `.xlsb`, no workbook, a DOCTYPE | `XlsxReadException` as in the reader; a relationship or override pointing at `[Content_Types].xml` or a `.rels` part is never the workbook | metadata is never a document part | `test/xlsx/read/hostile_files_test.dart`, `test/xlsx/read/package_reader_test.dart` ("metadata parts are not workbooks") |
| Mutated files | `open` throws only `XlsxReadException`, and whatever opens reads, sets a cell, a style, a column, a row format and a frozen pane and saves without throwing; the saved bytes open again and every sheet reads unless the input's same sheet could not | spec 4.9: the model makes nothing worse | `test/xlsx/read/fuzz_test.dart` ("mutated files raise only XlsxReadException") |
| `m1_corrupt.xlsx` (schema-invalid but readable) | the model keeps the stray content faithfully; the Open XML SDK rejects the model's output | preserving is the model's job, validating the validator's | `test/tool/round_trip_model_test.dart` ("the --corrupt workbook keeps its fault"), CI's `validate` job |

## Checking the round trip

`dart run tool/round_trip_model.dart <inDir> <outDir>` opens every `.xlsx` of
a directory, loads every sheet, saves it, writes the bytes to `<outDir>` and
compares the saved package with the input by `comparePackages`
(`tool/src/part_compare.dart`, `ignoreBookkeeping`). CI runs it on the writer
fixtures and on LibreOffice's re-save of them, then validates the output with
the Open XML SDK. Every normalization the comparer makes is pinned in
`test/tool/part_compare_test.dart`.

`dart run tool/edit_model.dart <inDir> <outDir>` checks what the model saves
after a change: in every `.xlsx` of a directory it sets a `DateTime`, an
`XlsxDate`, a formula and a string in the row after the first sheet's last
row, gives those cells a bold style with a red fill, sets column B's width,
the new row's height, a merge, a frozen first row and a tab colour, adds a
sheet, saves to `<outDir>` and reads the edits back with `XlsxReader` and the
model; it also writes the generated workbooks of
`tool/write_model_sample.dart`, `w1_generated.xlsx` and `w2_generated.xlsx`,
there. CI runs it on the writer fixtures and validates the output with the
Open XML SDK (spec section 9).

## Port map

W1 and W2 port nothing from Quds (spec section 8): every file is new and
says "Not ported from Quds; written for jet_office." Ports start in W5
(formula reference shifting) and are listed here when they land.
