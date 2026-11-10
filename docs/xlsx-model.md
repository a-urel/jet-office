# XLSX workbook model

`XlsxWorkbook` opens an XLSX file from bytes, or starts empty, lets a caller
read and set cell values, and saves the file again. Saving keeps everything
the caller did not change: the model is the single source of every save.
Decision [`0009`](decisions/0009-phase-3-workbook-model.md) sets the scope
and the fidelity standard.

This page covers milestone W1, the foundation: open and save with no loss, and
generate values; milestone W2, styles and layout typed; milestone W3,
sheet and workbook features typed (defined names, print settings, filters,
protection, hyperlinks, data validations, conditional formats and document
properties); and milestone W4, objects (rich text, notes, pictures and
tables). Structural editing (W5) remains.

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
merges, views and tab colours; W3 adds the features listed under "What W3
adds"; W4 adds rich text, notes, pictures and tables) is kept as opaque XML at its position and
written back, with the namespace declarations it needs.

## What W1 does and does not do

- **Edits.** `setCell` takes a `String`, `num`, `bool`, `DateTime`,
  `XlsxDate`, `XlsxDecimal`, an `XlsxFormula` without a group, or `null`.
  Rich text is typed since W4 (`richTextAt`, `setCell` of an `XlsxRichText`);
  hyperlinks are typed since W3
  (see "What W3 adds"). Editing a shared formula's master throws until W5.
  Since W2 `setCell` also takes an `XlsxCell`, layered as the writer layers it
  (see "What W2 adds").
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

## What W3 adds

`XlsxSheet` and `XlsxWorkbook` read and set the features of a sheet and of the
workbook. Decision [`0009`](decisions/0009-phase-3-workbook-model.md) lists
them; the values are the writer's types, checked by the writer's checks.

```dart
final XlsxSheet sheet = book.sheet('Prices');
book.defineName(const XlsxDefinedName('TaxRate', '0.18'));
sheet
  ..setCell(0, 0, XlsxHyperlink.url('https://example.com', text: 'Home'))
  ..autoFilter = XlsxRange.parse('A2:D20')
  ..printArea = <XlsxRange>[XlsxRange.parse('A1:D20')]
  ..pageSetup = const XlsxPageSetup(orientation: XlsxOrientation.landscape)
  ..headerFooter = const XlsxHeaderFooter(oddFooter: '&CPage &P of &N')
  ..addDataValidation(
    XlsxDataValidation(<XlsxRange>[XlsxRange.parse('B3:B20')],
        XlsxValidationType.list, formula1: '"yes,no"'),
  )
  ..addConditionalFormat(conditionalFormat)
  ..protection = const XlsxSheetProtection(password: 'secret');
book.properties = const OfficeProperties(title: 'Prices');
```

- **Reading and setting.** On a sheet: `definedNames`, `defineName`,
  `removeName`, `printArea`, `setPrintTitles`, `autoFilter`, `pageSetup`,
  `headerFooter`, `protection`, `hasStoredPassword`, `hyperlinks`,
  `hyperlinkAt`, `removeHyperlink` (and `setCell` with an `XlsxHyperlink`),
  `dataValidations`, `addDataValidation`, `removeDataValidation`,
  `conditionalFormats`, `addConditionalFormat`, `removeConditionalFormat`.
  On the workbook: `definedNames`, `defineName`, `removeName`, `protection`
  and `properties`.
- **Entries are kept.** A feature that holds a list (names, links,
  validations, conditional formats) keeps every entry of the file in order.
  An entry the types can hold is read as a value; one they cannot (a bad
  `ref`, a dangling `dxfId`, an unknown rule type) stays as written, is left
  out of the getter and is reported once as `featureEntryInvalid`. An edit
  writes only what changed; a new entry is written as the writer writes it.
- **An equal set is no edit.** Setting what a getter returns changes nothing,
  records nothing and leaves the file's own spelling.
- **Added entries read back as the file says them.** A conditional format
  added is stored as the file would say it (leading `=` removed, default
  thresholds collapsed, the fields Excel 2010 repeats read from the Excel 2010
  rule), so the getter
  after an add equals the getter after a reopen, and `removeConditionalFormat`
  takes either the value that was added or the one that was read.
- **Recalculation.** A change of a user-defined name asks Excel to recalculate
  (R1); no other W3 edit does.
- **One warning code.** `featureEntryInvalid`, with the feature in its detail;
  its messages are in `en`, `de` and `tr`.
- **Undo.** Every edit is one change of the log; undoing it puts the element
  and the relationship back where they were.

Five rulings fill a silence of the spec (plan R1 to R5):

- **R1 Names and recalculation.** `defineName` and `removeName` of a user name
  make the save set `fullCalcOnLoad` (when the workbook has formulas);
  `calcChain` stays. Print and filter names do not count.
- **R2 Stored passwords.** A protection read from a file gives `password:
  null` whatever hash it stores. Setting a protection with `password: null`
  keeps the stored hash; `protection = null` removes the element with it; a
  new password replaces every hash attribute.
- **R3 Built-in names.** `definedNames` lists no `_xlnm.` name; they stay as
  written. The three with typed members (print area, print titles, filter)
  are read and set through those members.
- **R4 Other Excel rule types.** `timePeriod`, `containsBlanks`,
  `notContainsBlanks`, `containsErrors` and `notContainsErrors` carry a
  formula: they read as `XlsxExpressionRule`, kept as written.
- **R5 Excel 2010 data validation.** `x14:dataValidations` stays opaque: the
  spec names only conditional formats' `extLst` forms.

## What W4 adds

`XlsxSheet` reads and edits the four kinds of object a sheet holds besides
values and features: rich text cells, notes, pictures and tables. The values
are the writer's types (`XlsxRichText`, `XlsxNote`, `XlsxPicture`,
`XlsxTable`), checked by the writer's checks, and a new object is rendered by
the writer's own functions, so the model forks no writer.

```dart
final XlsxSheet sheet = book.sheet('Prices');
sheet
  ..setCell(0, 0, XlsxRichText(<XlsxTextRun>[
    const XlsxTextRun('Total ', font: XlsxFont(bold: true)),
    const XlsxTextRun('due'),
  ]))
  ..setNote(1, 1, XlsxNote.plain('Checked.', author: 'Ayse'))
  ..addPicture(XlsxPicture(
    OfficeImage(pngBytes),
    const XlsxOneCellAnchor(XlsxAnchorPoint(3, 3), width: 120, height: 60),
  ))
  ..addTable(XlsxTable('Sales', XlsxRange.parse('A10:B14'), columns));
```

- **Reading and setting.** On a sheet: `richTextAt` (and `setCell` with an
  `XlsxRichText`, plain or in an `XlsxCell`); `notes`, `noteAt`, `setNote`
  (`null` removes); `pictures`, `addPicture`, `movePicture`, `removePicture`;
  `tables`, `addTable`, `setTableStyle`, `resizeTable`, `removeTable`.
- **What is read is typed, the rest is kept.** A drawing with charts, shapes
  and groups beside pictures, a VML part with form controls beside notes and a
  table with calculated columns, `xr:uid` or a query table keep everything the
  types do not hold, as written. Adding or removing one object changes
  nothing else.
- **Parts come and go inside the transaction.** Unlike W3's features, an object
  needs a part (comments, VML, drawing, media, table) and a relationship the
  moment it is set. The package can detach and restore a part, so an edit that
  adds or removes one is a single change of the log: a failed edit and an undo
  give the part, its relationships, its content type and its bytes back.
- **Names follow the writer's.** A new comments, VML or drawing part takes
  the number of the sheet's own part (`sheet3.xml` gives `comments3.xml`,
  `vmlDrawing3.xml`, `drawing3.xml`), the next number when that name is taken;
  media take `xl/media/image{n}`, tables `xl/tables/table{id}.xml`, so a
  workbook the model generates equals the writer's.
- **The DrawingML layer.** What DOCX shares with the sheet drawing (the `pic`
  element and the de-duplication of media by their bytes) lives in
  `lib/src/drawingml/`, which imports the OPC, XML and common layers only.
- **An equal set is no edit**, as in W3: a rich text, note, picture anchor or
  table style set back as read records nothing and leaves the file's spelling.
- **Recalculation.** `setCell` of a rich text drops `calcChain` and sets
  `fullCalcOnLoad`, as any value does; so does `addTable` (it writes header
  and totals cells). Setting, moving, restyling, resizing or removing an
  object alone does not (W2's Ruling 15), except that `resizeTable` sets
  `fullCalcOnLoad` as a name edit does and keeps `calcChain`.
- **Warnings.** One code, `featureEntryInvalid`, with the detail `rPr`,
  `comment`, `legacyDrawing`, `pic`, `drawing` or `table`, once per sheet.

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
| A table's header cell | takes only text: the column's `name` in the table part is set to it (`tableColumnRenamed`), the rest of the part kept character for character; empty text or `null` becomes `ColumnN`, a name another column has (ignoring case) gets a number (`tableHeaderAdjusted`); another value is a `StateError`, over 255 characters an `ArgumentError`; every structured reference to the column (`Sales[Amount]`, `[@Amount]` inside the table) takes the new name (W5, `StructuredRename`); undo restores the name | Excel repairs a table whose header cell and column name differ (W1 Excel check, 2026-11-03) | `test/xlsx/model/table_header_test.dart` |
| A cell inside an array or data-table formula, its master included | `StateError`, permanent | Excel refuses it too | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("editing formula groups"), `test/xlsx/model/primitives_test.dart` |
| A shared formula's child | leaves the group; the others stay | the child's formula stays correct | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("editing formula groups") |
| A shared formula's master | `UnsupportedError` until W5 | the children need reference shifting | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("editing formula groups") |
| `XlsxRichText` (also inside an `XlsxCell`) | stored as the writer stores it (runs cleaned with `invalidCharactersRemoved`/`textTruncated`, run fonts merged over the cell's font, `ArgumentError` for no runs); equal to `richTextAt` with no style it is no edit, so a phonetic `<si>` survives; a table header cell refuses it (`StateError`) | the writer's rich text, without losing phonetic runs | `test/xlsx/model/xlsx_sheet_rich_text_test.dart` |
| `XlsxCell(value, style: s)` | the value is set as a bare one; the style is the writer's layering, the row's style (with `customFormat="1"`) merged with `s`, appended when no cell format matches; a date takes the writer's date format only when that style sets none; an `XlsxCell` of `null` leaves an empty cell of that style, or none when it has no style or the default | the model and the writer give the same cell format | `test/xlsx/model/xlsx_sheet_style_test.dart` ("XlsxCell layers like the writer", "XlsxCell dates take the writer format rule", "an XlsxCell of null") |
| `styleAt` | the cell's own style when the cell exists, else the row's with `customFormat="1"`; index 0 is `null` | what Excel shows there | `test/xlsx/model/xlsx_sheet_style_test.dart` ("styleAt reads cell and row styles") |
| `setStyle` | sets exactly the style, no layering; an equal style keeps its index; a new one is appended, so no index moves and an unloaded sheet's styles stay; `null` gives index 0 and removes a cell left with nothing | appending keeps every other cell's format | `test/xlsx/model/xlsx_sheet_style_test.dart` |
| A style edit that throws (an invalid field, the writer's limits, an untyped styles part) | the registry's `ArgumentError` or `XlsxLimitError`, or a `StateError`; the styles a failed transaction appended are rolled back (`StylesAppendChange`) | atomic edits | `test/xlsx/model/xlsx_sheet_style_test.dart` ("a failed setStyle changes nothing", "rolls back the styles"), `test/xlsx/model/primitives_test.dart` ("appendStyle") |
| A style set, or a date given a format, in a file without `xl/styles.xml` | the writer's empty styles are made in memory and join the package on save only when they hold an appended entry; an edit that throws or is undone adds no part | atomic edits, spec 4.8 | `test/xlsx/model/xlsx_sheet_style_test.dart` ("a workbook without styles") |
| `styleAt` on an `s` with no cell format | `null`, and `setStyle` does not keep that index | Excel shows the default | `test/xlsx/model/xlsx_sheet_style_test.dart` ("an index outside cellXfs") |
| A style no cell format matches | appended to `cellXfs`, with the font, fill, border and number format it needs reused when equal to an exact entry and appended otherwise; a new code takes a `numFmt` id no entry uses | append-only: no index moves | `test/xlsx/model/styles_part_test.dart` ("a new style appends", "a style matching an exact entry reuses it", "a new code never takes a numFmt id the file uses") |
| A cell format the value types cannot hold in full (`quotePrefix`, a named style `xfId`, unknown children) | reads as far as it can, stays as written and is never reused for a style that looks like it | reuse would change what the cell shows | `test/xlsx/model/styles_part_test.dart` ("an inexact xf reads but stays as written") |
| A file already past a writer limit (more fonts than `XlsxLimits.maxFonts`, say) | opens and saves; reuse still works; `XlsxLimitError` only when an edit must append to a table at or over its limit | a data condition must not become a programmer error, and only appends can pass a limit | `test/xlsx/model/styles_part_test.dart` ("a file past the font limit reuses fonts and throws to add one", "withNumberFormat at the cell format limit reuses or throws"), `test/xlsx/model/xlsx_sheet_layout_test.dart` ("at the cell format limit") |
| `setStyle` of what `styleAt` read, on a dangling or invalid `s` | the `s` is dropped, so this is a change and not a no-op, unlike on every other cell; `setStyle(null)` drops it too | `styleAt` says none, and the model never keeps an index it cannot read | `test/xlsx/model/xlsx_sheet_style_test.dart` ("re-setting a dangling or invalid s drops it", "setStyle(null) on an empty styled cell removes it") |
| A style entry that cannot be read exactly | `styleEntryInvalid` in `XlsxWorkbook.warnings`, a workbook warning (sheet `''`), when the entry is first read, even by a call that then throws | data problems warn | `test/xlsx/model/xlsx_sheet_style_test.dart` ("warns on the workbook") |
| `rowFormat` | the row's `ht` (only with `customHeight="1"`), `hidden`, `outlineLevel`, `collapsed` and style (`s` with `customFormat="1"`, as `styleAt` reads a row's) as an `XlsxRowFormat`; a row the file lacks is the default | what Excel shows for the row | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("rowFormat reads m2_columns_rows") |
| `setRowFormat` | the writer's attributes in the writer's order (`ht`, `hidden`, `customHeight`, `outlineLevel`, `collapsed`; `s` with `customFormat="1"` first); a changed field is replaced where it stood, any other attribute (`x14ac:dyDescent`, `thickBot`) and any field equal to the current one is kept as written; a row left with nothing is removed; checked with `checkRowHeight` and `checkOutlineLevel` (`ArgumentError` named `height` or `outlineLevel`) | a row format the writer would write | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("setRowFormat writes what the writer writes", "unknown row attributes are kept") |
| `XlsxRowFormat.style` | written as the row's `s` with `customFormat="1"`, which styles the row's empty cells as Excel's row format does; the writer never writes a row `s` and merges a row style into each cell instead, so the same look differs in the XML | Excel's model of a row format | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("setRowFormat writes what the writer writes"), `test/xlsx/model/parity_test.dart` ("fixtures built with the model equal the writer's") |
| `sheetFormatPr/@outlineLevelRow` on save | as the file has it, present, absent or lower than the rows need, until an edit goes deeper than both the kept value and the file's deepest row `outlineLevel`; then it is that level, the rest of the element kept; a missing element is made (with the required `defaultRowHeight`) only when an edit goes deeper than the file's rows or columns did | Excel needs the level to draw the outline, and an unchanged file changes nothing | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("outlineLevelRow") |
| A row attribute that cannot be read (an `ht` of `abc`, a level of 9) | `layoutInvalid` once per attribute, a sheet warning; the typed value is the default and the attribute is saved as written until that field is set | data problems warn | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("a bad ht warns layoutInvalid and stays as written") |
| `column` | the `<col>` holding the column: `width` (whenever it is a width; `customWidth` only says it was set by hand, so writer columns without a width read 9.140625), `style`, `hidden`, `outlineLevel`, `collapsed` as an `XlsxColumn`; `null` for a default column or one whose `<col>` sets nothing the model reads | what Excel shows for the column | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("column reads widths, styles, hidden and outline") |
| `setColumn` | the `<col>` is split into up to three; the outer runs keep every attribute (`bestFit`, ...), the column replaces changed fields where they stood and keeps the rest, a new `<col>` is written as the writer writes it (`width` always), and a column that ends up writing the same `<col>` as a neighbour joins it; `null` resets; `setColumn(i, column(i))` changes nothing, and a value that writes the same `<col>`s records no change; checked with `checkColumnWidth` and `checkOutlineLevel` (`ArgumentError` named `column.width`, `column.outlineLevel`, `column.style.<field>`) | a column the writer would write | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("setting one column of a range splits it", "new columns write what the writer writes") |
| A `<cols>` that is not plain (a `<col>` with children or declarations, an invalid, unsorted or overlapping `min`/`max`, none at all), and a second `<cols>` | kept as written; `column` reads none of it and `setColumn` throws `StateError` | the model never rewrites what it cannot type | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("a cols that is not plain is kept and cannot be edited") |
| `styleAt` and `XlsxCell` layers with columns | `styleAt` is the cell's own style, else the row's (`customFormat="1"`), else the column's; `setCell` of an `XlsxCell` layers the column, then the row, then the cell, as the writer does (a row with an explicit `s="0"` shows the default and takes no column style) | what Excel shows; the writer's layers | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("styleAt: cell, then row, then column", "an XlsxCell over a column style takes the writer cell formats") |
| `defaultSizes`, `setDefaultSizes` | `sheetFormatPr/@defaultRowHeight` (only with `customHeight="1"`) and `@defaultColWidth`; set exactly (`null` is Excel's own) and written as the writer writes them, the rest of the element (`baseColWidth`, ...) kept; a `sheetFormatPr` with element children reads but throws `StateError` on set | the writer's `defaultSizes` | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("default sizes read and set") |
| `sheetFormatPr/@outlineLevelCol` on save | as `outlineLevelRow`: as the file has it until an edit goes deeper than the kept value and the file's deepest column `outlineLevel` of the first plain `<cols>` | Excel needs the level to draw the outline, and an unchanged file changes nothing | `test/xlsx/model/xlsx_sheet_layout_test.dart` ("outlineLevelCol is the larger of the kept and the deepest") |
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
| `XlsxReadLimits.maxMerges` | applied per sheet when the sheet loads (`limitExceeded`, naming the part); the reader counts across the sheets whose merges it has cached. It bounds in the same way, each list on its own, a sheet's hyperlinks, data validations, conditional formats and Excel 2010 conditional formats (for each of the two, the elements, and the rules across them), when the sheet loads; the workbook's defined names, at `open`; and the differential styles, when the styles part loads | a loaded sheet holds its own merges; a small part could list millions of kept entries | `test/xlsx/model/xlsx_sheet_merge_test.dart` ("maxMerges applies on load", "maxMerges counts per sheet"), the "maxMerges bounds" test of each list |

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

### Sheet and workbook features (W3)

| Case | Behaviour | Why | Test |
|---|---|---|---|
| An entry the types can hold | read as a value, written back as the file wrote it unless edited; the group's `count` is recomputed when the group is edited | nothing lost | `test/xlsx/model/item_group_test.dart`, `test/xlsx/model/worksheet_part_test.dart` ("feature slots") |
| An entry that cannot be read exactly (a bad `ref` or `sqref`, a dangling `dxfId` or `r:id`, an out-of-range value) | kept as written, `featureEntryInvalid` once per feature and sheet; out of the getter, except a dangling `dxfId` or `r:id`, whose entry stays listed (a rule with no style, a link with no address); the getter never throws on it, save never throws | data problems warn, and save must not throw on a file that opened | `test/xlsx/model/item_group_test.dart` ("an entry with a problem is kept, counted and reported"), the "bad values are kept and reported" test of each feature |
| An equal set (`autoFilter`, `printArea`, `pageSetup`, `headerFooter`, `protection`, `properties`, ...; `setCell` with the cell's `hyperlinkAt`) | no edit, no change recorded, the element's own spelling stays; for a link, neither the element nor the cell changes, also on a cell inside a link of several cells and for a link the writer would refuse; an `XlsxCell` of an equal link leaves the element and sets the style | typing must not alter output | `test/xlsx/model/xlsx_sheet_print_test.dart` ("an equal set records nothing"), `test/xlsx/model/page_setup_test.dart` ("an equal set is no edit"), `test/xlsx/model/xlsx_sheet_links_test.dart` ("an equal link is no edit"), `test/xlsx/model/round_trip_test.dart` ("re-setting what was read changes nothing") |
| R1: a name edit | `fullCalcOnLoad` when the workbook has formulas; `calcChain` stays; a print or filter name asks nothing; undoing the edit asks nothing | a name changes results as a cell does | `test/xlsx/model/defined_names_test.dart` ("recalculation"), `test/xlsx/model/xlsx_sheet_print_test.dart` ("print and filter names do not ask for recalculation") |
| R2: a stored password hash | `password` reads `null`; a flag change keeps every hash attribute; `password: null` keeps them; a new password replaces them; `protection = null` removes the element | the model never sees a password, and must not weaken one | `test/xlsx/model/protection_test.dart` ("a stored hash survives a flag change", "a new password replaces the hash attributes") |
| R3: built-in names | `definedNames` lists none; `printArea`, `setPrintTitles` and `autoFilter` read and write them; `removeName` of one is an `ArgumentError` | one typed way to each | `test/xlsx/model/defined_names_test.dart` ("reads m3_names"), `test/xlsx/model/xlsx_sheet_print_test.dart` |
| R4: other Excel rule types | read as `XlsxExpressionRule`, kept as written | they carry a formula | `test/xlsx/model/conditional_format_test.dart` ("other rule types read as expressions, kept as written") |
| R5: `x14:dataValidations` | stays opaque in its `ext` | spec names only conditional formats' `extLst` forms | `test/xlsx/model/conditional_x14_test.dart` ("other exts survive") |
| Names and the parts that hold them | a sheet's print area, titles and filter are names of `workbook.xml` and elements of the sheet part, changed in one transaction: a failure in the second part leaves the first as it was, and undo puts both back | one feature, two parts | `test/xlsx/model/xlsx_sheet_print_test.dart` ("a failure in the second part leaves the first as it was", "undo puts the element and the name back") |
| A filter set on a narrower or wider range | the `filterColumn`s whose `colId` lies inside the new width stay when the first column is the same; every other child goes, all of them when the first column moves; the buttons' choices are not applied | a filter keeps its choices while its columns stay | `test/xlsx/model/xlsx_sheet_print_test.dart` ("narrowing a filter") |
| A print area, titles or filter name that changes | only its text changes, and `hidden` for a filter name that was not hidden: `publishToServer`, `description`, `xr:*` and the element's prefix stay | a typed member edits what it types | `test/xlsx/model/xlsx_sheet_print_test.dart` ("a changed name keeps what it does not type") |
| `printArea` or `setPrintTitles` on a chartsheet or a sheet without a part | `StateError`, as `autoFilter`, `pageSetup` and `protection`; no name is written | a name for cells the sheet does not have is a broken name | `test/xlsx/model/xlsx_sheet_print_test.dart` ("a sheet that is not a worksheet") |
| Rows a filter hid | stay hidden when the filter changes or goes; the model never rewrites rows for a filter | the choices are not applied or removed | `test/xlsx/model/xlsx_sheet_print_test.dart` ("rows a filter hid stay hidden when it narrows and when it goes") |
| Links with the same address | share one relationship; replacing or removing a link drops its relationship when no other link uses it; undo restores the id | one target, one relationship | `test/xlsx/model/xlsx_sheet_links_test.dart` ("a repeated address shares one relationship", "replacing and removing drop an unused relationship", "undo restores the link, the id and the cell") |
| A plain value set in a cell with a link | the cell keeps its link; `removeHyperlink` removes it | Excel keeps the link under a typed value | `test/xlsx/model/xlsx_sheet_links_test.dart` ("a plain value keeps the link") |
| A link's text | the string of the first cell it covers, else its `display`, else empty; a `display` the cell no longer says stays in the file | Excel shows the cell, and `display` goes stale | `test/xlsx/model/xlsx_sheet_links_test.dart` ("the text is the cell string, else the display, else empty", "a plain value set in the cell is the text the link reads") |
| A link over several cells | read as one link covering them; `removeHyperlink` on any of its cells removes it whole; a link set on a cell inside it throws | a partial change would split a link the file wrote as one | `test/xlsx/model/xlsx_sheet_links_test.dart` ("A1:B2 reads as one link covering four cells", "removing a multi-cell link removes it whole", "a multi-cell link throws and nothing changes") |
| A style of a conditional format | reuses a `dxf` that says exactly the same, else is appended; nothing is renumbered | indexes the file's cells name must not move | `test/xlsx/model/conditional_format_test.dart` ("a style the file has is reused, a new one appended"), `test/xlsx/model/styles_part_test.dart` ("differential styles") |
| Priorities of added rules | continue past the file's highest, counting rules the model does not list (Excel 2010 ones included); a priority past the schema's `int` throws | priorities are unique per sheet | `test/xlsx/model/conditional_format_test.dart` ("priorities continue the file's", "priorities count what is not listed"), `test/xlsx/model/conditional_x14_test.dart` ("priorities continue past the Excel 2010 rules") |
| A data bar | its two halves, the 2007 `dataBar` and the Excel 2010 `x14:dataBar` linked by an id, are added and removed together, undo restores both; an id collides with no other | one rule in the file, two elements | `test/xlsx/model/conditional_x14_test.dart` ("a data bar's halves leave together; undo restores both", "ids do not collide") |
| Other `ext`s of `extLst` | stay, and so do other children of the conditional format `ext`; the ext and `extLst` go only when nothing else is in them | one `extLst` holds many features | `test/xlsx/model/conditional_x14_test.dart` ("other exts survive", "other children of the ext survive", "the last format takes the element, the ext and extLst with it") |
| An Excel 2010 rule the types cannot hold (a custom icon set, another kind of rule) | stays kept, unlisted and unreported | the getter lists only what it can hold | `test/xlsx/model/conditional_x14_test.dart` ("a custom icon set stays kept and unlisted", "another kind of rule stays kept and unlisted, unreported") |
| Properties | `custom.xml` joins when a custom property is set (part, relationship, content type) and leaves when no property is left in it; a part that holds a kept property stays; other elements and variants stay | the part follows the content | `test/xlsx/model/properties_test.dart` ("custom part joins and leaves", "a custom part leaves when no property is left", "a custom part holding a kept property stays") |
| `modified` and `lastModifiedBy` | a save never touches them; only a set changes them | the model does not invent a time | `test/xlsx/model/properties_test.dart` ("modified and lastModifiedBy are not touched by a save") |
| `revision` and `application` (`OfficeProperties`, shared with DOCX) | `cp:revision` reads as a number (digits only, at most 2^53 - 1, so the VM and the web agree); another text reads `null`, stays and is reported as `featureEntryInvalid` (`cp:revision`); a set writes it after `cp:lastModifiedBy` or in place. `Application` reads as text; a set writes it, a `null` removes it, so a new workbook, whose part names `jet_office`, loses it when set to a value without one. The writers write `application ?? 'jet_office'` | one properties type for both formats; Word counts saves in `cp:revision` | `test/xlsx/model/properties_test.dart` ("revision and application"), `test/common/properties_test.dart` ("revision and application"), `test/common/properties_parts_test.dart` |
| Fuzzing and undo | the feature corpus, mutated, opens, then reads, sets, undoes and saves every W3 and W4 member with nothing thrown but `XlsxReadException`; undoing every edit of a corpus file restores it | the file is untrusted input | `test/xlsx/model/feature_fuzz_test.dart` |

### Objects (W4)

| Case | Behaviour | Why | Test |
|---|---|---|---|
| Rich text read | `richTextAt` gives the runs of a shared or inline string, a plain cell `null`; each run's font is read as stored (the writer fills the cell's font into a run without one); a bad `rPr` value keeps the font's readable fields and warns once | the runs of a file are its own | `test/xlsx/model/xlsx_sheet_rich_text_test.dart` ("reads runs of a shared string", "a phonetic-only item reads null", "a run with a bad size warns once") |
| Rich text set | repaired as a string is (dirty characters removed, text past 32,767 code units cut, with the writer's warnings); no runs, or a table header cell, throws and nothing changes; an `XlsxCell` keeps its style; the value equal to `richTextAt` is no edit and a phonetic `<si>` survives | one way to write a value | `test/xlsx/model/xlsx_sheet_rich_text_test.dart` ("dirty text repairs as the writer", "no runs throws and changes nothing", "a header cell refuses it", "setting back what was read changes nothing") |
| Excel's rich run colour `indexed="81"` | reads as no colour, without a warning, in every rich text run (notes, shared strings, inline strings); another index past the palette (82 and up) warns `featureEntryInvalid` (`rPr`); the writer still refuses 81 | Excel writes 81 (the system colour of tooltip text) in every note it makes, so warning would flag every Excel file; the font keeps its other fields and the file keeps what it wrote | `test/xlsx/model/xlsx_sheet_notes_test.dart` ("Excel's indexed 81 reads as no colour, without a warning", "another index past the palette warns", "the writer still refuses indexed 81") |
| Notes read | `notes` lists each `<comment>` with its cell, author and runs; `visible` is the VML shape of the same row and column with `<x:Visible/>`; a `ref` that is bad or repeated is kept as written, unlisted and warned (`comment`); a bad `authorId` reads an empty author; VML that is not XML reads every note hidden and warns (`legacyDrawing`); a comments part that is not SpreadsheetML reads none | nothing lost, nothing thrown on a file that opened | `test/xlsx/model/xlsx_sheet_notes_test.dart` ("a repeated ref is kept and warned", "a bad authorId reads an empty author", "VML that is not XML warns and reads visible false", "visible comes from the shape of the same row and column", "a comments part that is not SpreadsheetML reads no notes") |
| `setNote` equal set | a note equal to `noteAt` is no edit, and throws nothing even for a note the writer would refuse or repair (an over-long author, text past the limit) or the note of a thread; the check comes before the part checks, so it holds on malformed VML too | typing must not alter output, and a note read must be settable back | `test/xlsx/model/xlsx_sheet_notes_test.dart` ("equal set is no edit", "a note set back as read is no edit") |
| A thread's placeholder note | Excel keeps a legacy note `[Threaded comment]` by author `tc={GUID}` beside each thread; the thread is opaque (decision 0009), so `setNote` (also with `null`) on such a cell with a different note throws `StateError`, nothing changes; an equal set is no edit; a new note whose author starts `tc=` on a cell without one throws `ArgumentError` named `author` (model only; the writer is unchanged) | setting or removing it would orphan the thread, and a copy is a placeholder with no thread | `test/xlsx/model/xlsx_sheet_notes_test.dart` ("a tc= note throws StateError and nothing changes", "the note of a thread"); `test/xlsx/model/round_trip_test.dart` ("a note of a thread cannot be copied to a cell without one") |
| `setNote` of a new note | checked and repaired as `XlsxSheetWriter.note` does, with `invalidCharactersRemoved` and `textTruncated`; goes in row-major order; the first note creates the comments part and, unless the sheet has one, the VML part and `<legacyDrawing>`; an author is reused, else appended; a replaced note keeps its other attributes (`xr:uid`) and its box; `visible` shows or hides the box; a note whose text and author equal the cell's and only `visible` differs changes the box alone, so the comments part keeps its bytes (Excel's `indexed="81"` runs stay) | what changes is what was set | `test/xlsx/model/xlsx_sheet_notes_test.dart` ("adds to a sheet without notes", "a new comment goes in row-major order", "replaces text and keeps xr:uid and the shape", "an author is reused and a new one appended", "visible toggles the shape", `round_trip_test.dart` ("a visibility-only setNote leaves the comments part as written"), "more VML shapes than maxMerges leave the part as written" (shapes are bounded by `maxMerges` as the comments are: `limitExceeded` on first read of the notes, the file saves as written), "text is repaired with the warnings of the writer", "notes set in order are what the writer writes") |
| VML beside notes | a VML part that holds form controls or another kind of element takes the boxes beside them and stays when the last note goes; shape ids come from one block per 1,024 and are unique across sheets, unloaded ones included; a part with no `o:idmap` gets one | a note must not disturb the other objects of the part | `test/xlsx/model/xlsx_sheet_notes_test.dart` ("adds beside a form control shape", "removing keeps VML with a form control", "removing keeps VML that holds another kind of element", "shape ids and blocks stay unique across sheets, unloaded ones included", "1,100 notes take a second block", "the VML of a sheet with shapes but no idmap gets one") |
| Removing a note | removing the last note removes the comments part; the VML part and `<legacyDrawing>` go too unless the drawing holds something else or another relationship names it; the text between shapes goes with the shape before it | nothing that is left empty stays | `test/xlsx/model/xlsx_sheet_notes_test.dart` ("removing the last note removes both parts and legacyDrawing", "removing one of several keeps the text between shapes") |
| Malformed note parts | `setNote` throws `StateError` for VML that is not well formed or a comments part that is not SpreadsheetML, with nothing changed; a malformed relationships part is an `XlsxReadException` | the model does not guess what it cannot read | `test/xlsx/model/xlsx_sheet_notes_test.dart` ("malformed VML throws StateError", "a comments part that is not SpreadsheetML throws StateError") |
| Pictures read | `pictures` lists each `oneCellAnchor` or `twoCellAnchor` that directly holds a `pic` embedding a part of the file, with sizes and offsets in pixels; a GIF or EMF is listed with `format` `null`; a chart, a shape, a group, an absolute anchor, a picture in `mc:AlternateContent` or a linked picture is kept, unlisted, without a warning; a dangling embed, a marker or size that is not a number or a `cNvPr` without an id is kept, unlisted and warned (`pic`); a drawing that is not a spreadsheet drawing reads none and warns (`drawing`) | the getter lists what it can hold | `test/xlsx/model/xlsx_sheet_pictures_test.dart` ("a chart and a shape beside a picture stay kept and unlisted", "a linked picture is unlisted without a warning", "a dangling embed warns once", "a GIF is listed with format null", "editAs maps to the resize modes") |
| `addPicture` | checked as `XlsxSheetWriter.picture`; goes after everything the drawing holds, creating the drawing when there is none; a `cNvPr` id one above the highest (at least 2), counting a group's inner ids; a default name `Picture {k}`; bytes equal to a media part of the file (any sheet, any extension spelling) share it and the drawing's relationship to it; else a part `xl/media/image{n}` with its extension declared as a default content type; a relationship takes the lowest id no entry of the drawing names, so a dangling id does not start to resolve | one picture changes nothing else | `test/xlsx/model/xlsx_sheet_pictures_test.dart` ("renders as the writer does", "adds beside a chart, keeping it character for character", "ids stay unique over a group's inner cNvPr", "the same bytes share one media part", "a new extension adds a Default and takes the next number", "a new relationship takes no id a dangling entry names") |
| `movePicture` | the anchor element takes the new markers, `ext` and `editAs` (and the other kind's name); its `pic`, `clientData` and other attributes stay as written; an equal anchor is no edit; an unsizable image (GIF, EMF) moved to a size-less anchor throws `ArgumentError` | one edit, one change | `test/xlsx/model/xlsx_sheet_pictures_test.dart` ("moves one-cell to two-cell keeping pic and clientData", "an equal anchor is no edit", "an unsizable image moved to a size-less anchor throws") |
| A stale `a:xfrm` after `movePicture` | the `pic` stays verbatim, so a one-cell picture written with `a:xfrm` keeps its old size there after a resize; Excel is expected to take the size from the anchor, which only the owner's Excel check confirms (`docs/excel-checks.md`, "W4") | rewriting `pic` would break the rule that a move changes only the anchor | `test/xlsx/model/xlsx_sheet_pictures_test.dart` ("moves one-cell to two-cell keeping pic and clientData"); the check is Excel's |
| `removePicture` | removes the entry; every relationship the entry names goes when no other entry or opaque entry names it, and the part it pointed at goes when no relationship anywhere points at it (unloaded sheets' drawings included); the drawing and its relationship go with the last entry unless it holds something else | a removed picture's bytes do not stay in the file | `test/xlsx/model/xlsx_sheet_pictures_test.dart` ("removes and keeps media another sheet's unloaded drawing shows", "removes the media nothing else uses", "keeps the relationship an opaque entry names", "the relationships of the picture's other names go too", "removing the last entry removes the drawing", "a drawing that holds something else stays") |
| A broken `<drawing>` | `addPicture`, `movePicture` and `removePicture` throw `StateError` when the part is missing or is not a spreadsheet drawing, nothing changed | the model does not edit what it cannot read | `test/xlsx/model/xlsx_sheet_pictures_test.dart` ("a broken drawing throws StateError", "a drawing whose root is not wsDr warns and cannot be edited") |
| Tables read | `tables` lists each table part of the sheet's table relationships in order; a part the model cannot type (a root that is not `table`, a bad `ref`, columns that do not match it) is kept, unlisted, and its name and id stay taken; an unknown `totalsRowFunction` reads none and warns (`table`); calculated columns, `dataDxfId`, `xr:uid`, filter criteria and sort state stay as written | nothing lost | `test/xlsx/model/xlsx_sheet_tables_test.dart` ("reads the fixture's tables", "an untypable part stays unlisted and its name stays taken", "a bad function warns once and reads none") |
| `addTable` | rendered by the writer with the `id` one above the highest of the package, the part `xl/tables/table{id}.xml` (the next number when taken); `<tableParts>` made in schema position, `count` recomputed; an empty header cell takes the column's name, an empty totals cell the label or `SUBTOTAL`; a header cell that holds another text, a formula in a header cell or a name taken (a table of any sheet, loaded or not, listed or not; a defined name) throws `ArgumentError` with nothing changed; an overlap with a table, the auto filter or a merge throws naming both | a table is cells, a part and a name in one | `test/xlsx/model/xlsx_sheet_tables_test.dart` ("adds a table and writes its header and totals", "tableParts is made in schema position", "a name taken by a table on an unloaded sheet throws", "a defined name throws", "an overlap with merge, filter and table throw naming both", "ids stay unique over the package", "a part name taken by another part is bumped") |
| `setTableStyle` | the `name` and the flags that differ are set in place, everything else of the part stays; a table without `<tableStyleInfo>` gains it after `<tableColumns>`, `null` removes it; an equal style is no edit; a style Excel lacks throws `ArgumentError` (a custom style the table already has may change its flags) | a typed member edits what it types | `test/xlsx/model/xlsx_sheet_tables_test.dart` ("restyle keeps xr:uid", "null style removes tableStyleInfo", "a table without a style gains the element after its columns", "equal is no edit", "a custom style of the file takes new flags") |
| `resizeTable` | moves the last row: `ref` of the table and its `<autoFilter>` change, cells stay; the first row and the columns stay; an overlap with another table, a merge or the auto filter throws; a totals row's cells move, as they are, to the new last row (a target cell that is not empty, or a shared or array totals formula, throws `StateError`; the save drops `calcChain`); the filter leaves out the totals row; a `sortState` and its conditions ending on the last body row follow (W5); an equal range is no edit. It rewrites no cached result, so a recorded count (`WorkbookPart.tableEdits`, as `nameEdits`) makes the save set `fullCalcOnLoad` when the workbook has formulas; `calcChain` stays, undo takes the count back, and `setTableStyle` and an equal resize ask nothing | a `SUM(T[A])` over a resized table has another result, as a name edit's formulas do; W5 owns what moves with it | `test/xlsx/model/xlsx_sheet_tables_test.dart` ("resize moves both refs", "resizeTable asks for recalculation, keeps calcChain, undo clears it", "an equal resize asks for nothing", "resize refuses totals, sortState, other corners and no data row", "resize refuses an overlap with a table, a merge or the filter", "addTable drops calcChain, setTableStyle does not") |
| `removeTable` converts users to ranges | it removes the `<tablePart>`, the relationship and the part, and the cells stay; as Excel's "Convert to Range" (W5 Ruling 6) every structured reference becomes a plain range: `Sales[Amount]` is `Data!$B$2:$B$4` from another sheet or a defined name, `$B$2:$B$4` from its own sheet, `[@Amount]` in a cell that row's `B3`, an item the table lacks `#REF!`; a reference behind a workbook prefix (`[1]!T[A]`) and text in a string stay. A column the table lacks, an unreadable span or a this-row reference without a cell throws `StateError`; so do a query table, a tab on the same part that removed it, a slicer cache (`tableSlicerCache tableId`) and a pivot cache (`worksheetSource name`) naming it; nothing changes and no warning is kept | Excel repairs a file whose formula names a table it lacks | `test/xlsx/model/xlsx_sheet_tables_test.dart` ("removeTable converts users to ranges", "a defined name using it becomes a range", "what may stand before the name converts; another workbook stays", "a string holding the name no longer refuses", "a pivot cache naming the table refuses", "a slicer cache naming the table refuses removal", "a query table refuses") |
| `renameTable` | sets `displayName` (and `name`) in place; every structured reference to the table, in cells of every sheet, defined names, other tables' column formulas, rules and charts, follows; a taken or invalid name throws `ArgumentError` (`newName`), a pivot cache naming the table `StateError`; one change, undone whole | a table's name is its formulas' | `test/xlsx/model/xlsx_sheet_tables_test.dart` ("renameTable rewrites every structured ref, across sheets, in names and column formulas", "renameTable undoes as one change") |
| A part name used again after a removal | every cache keyed by a part name is edited in a recorded change (`markStoredPart`, `forgetTablePart`), so a part that takes a removed name starts clean and an undo restores the old state: a later restyle, rename, note or picture edit reaches the file | a removed part's name is free for the next part | `test/xlsx/model/xlsx_sheet_tables_test.dart` ("a part name used again after a removal", "a later restyle reaches the file", "a later header rename reaches the part"), `test/xlsx/model/xlsx_sheet_notes_test.dart` and `test/xlsx/model/xlsx_sheet_pictures_test.dart` ("a part name used again after a removal keeps later edits") |
| Undo across parts | adding or removing a note, picture or table, one or the last, and undoing it restores the file: parts, relationships, content types and the parts' bytes (by `attachStoredPart`), also after a failed edit | one change per edit, parts included | `test/xlsx/model/round_trip_test.dart` ("undoing object edits restores the file"), `test/xlsx/model/xlsx_sheet_notes_test.dart`, `xlsx_sheet_pictures_test.dart` and `xlsx_sheet_tables_test.dart` (groups "undo of ...", "the bytes of ...") |
| A file with more than this model types | a drawing with charts and shapes, a VML part with form controls, a table with calculated columns: adding or removing one picture, note or table changes only its own parts; the thread's note cannot be set or removed; the table its own formulas use cannot be removed | the owner's files hold much the model does not type | `test/xlsx/model/round_trip_test.dart` ("a file with more than the model types") |
| Fuzzing | the feature fuzz also reads, sets, undoes and saves every W4 member over `m4_*` and `excel_objects` | the file is untrusted input | `test/xlsx/model/feature_fuzz_test.dart` |

### What W3 reads and edits less than it might

| Case | Behaviour | Why | Test |
|---|---|---|---|
| A name read from a file that `defineName` would refuse (an empty formula, say) | stays listed by `definedNames`; once removed, `defineName` refuses it, so it cannot be added back | the file holds it, and listing it is the truth | `test/xlsx/model/defined_names_test.dart` ("a hidden name and a comment read" lists `e` with an empty formula, "a name as Excel writes it goes back when removed") |
| A print name or filter `ref` that cannot be read | reads empty (`printArea` empty, `autoFilter` `null`), is reported, stays in the file; setting empty or `null` is an equal set, so only a non-empty set replaces it | an equal set is no edit | `test/xlsx/model/xlsx_sheet_print_test.dart` ("bad values", "setting replaces them") |
| A whole-column print area (`$A:$A`) or whole-row one | reads empty and is reported (`featureEntryInvalid`), stays in the file. `XlsxRange` can hold a whole column as rows 0 to `XlsxLimits.maxRows - 1`, but `XlsxRange.parse` takes only cell references and writing that range back would give `$A$1:$A$1048576`, a different formula; so the print area reads only plain cell ranges, and a whole-column area is replaced only by a non-empty set | what is read must write back as it was | `test/xlsx/model/xlsx_sheet_print_test.dart` ("bad values", "plain references of this sheet read, in any form Excel writes") |
| `protection = null` on `<sheetProtection sheet="0">` | an equal set (it reads `null`); the element and its hash stay | `sheet="0"` protects nothing, and the hash is the owner's | `test/xlsx/model/protection_test.dart` (group `sheet="0"`) |
| `pageSetup = null` when only `fitToPage` is left | an equal set: it reads `null` and nothing changes | a lone `fitToPage` says nothing without a fit axis | `test/xlsx/model/page_setup_test.dart` ("null removes", "fit and first page number are read only when they apply") |
| A header or footer edit | drops a text child that read as bad (not XML text); the kept flags stay | the edit replaces the texts | `test/xlsx/model/page_setup_test.dart` ("a header or footer", "setting replaces the texts and keeps the rest") |
| An Excel 2010-only format added on an existing `sqref` | reads merged into the format that has that `sqref`, so it is removed only with the merged value | the getter after an add equals the getter after a reopen | `test/xlsx/model/conditional_x14_test.dart` ("an unlinked rule joins the format with an equal sqref") |
| The data bar colours the writer fills (negative fill, axis, borders) | read `null` | the file cannot tell a default from an explicit colour; `normalizedConditionalFormat` says it | `test/xlsx/model/conditional_x14_test.dart` ("what the writer fills reads as none") |
| An undo after a save | leaves the new `xl/sharedStrings.xml` the save made, its entries unused, not wrong; `xl/styles.xml` as a save writes it afresh (group `count`s recomputed, the meaning the same); and `fullCalcOnLoad`, as an undone edit still counts as a change | a save is not part of the change log | `test/xlsx/model/feature_fuzz_test.dart` ("undo restores every corpus entry") |
| An undo of a file that is not schema-valid (a rels part that does not parse, stray text between elements) | the part is normalized on re-encode, so it differs from the input | the model keeps what it reads; invalid input is outside the guarantee | `test/xlsx/model/feature_fuzz_test.dart` |
| Comments and stray text inside an element the model types and writes new (`pageMargins`, `sheetProtection`, `printOptions`, ...) | not kept when the element is typed; a schema-valid file has none | a typed element is written from its values | `test/xlsx/model/page_setup_test.dart`, `test/xlsx/model/protection_test.dart` |
| The number of custom properties | bounded by `XlsxReadLimits.maxSheets` (no new public limit) | one limit for the many small parts | `test/xlsx/model/properties_test.dart` ("a huge custom part is bounded by the limits") |
| A dangling `dxfId` when a later add appends a `dxf` at that index | the old rule then names the new style and reads with it, also after a reopen; nothing renumbers it | invalid input only: a valid file has no dangling id | `test/xlsx/model/conditional_format_test.dart` ("a dangling dxfId goes live when an add appends at its index") |
| A link on a styled cell | keeps the cell's explicit font colour, as the writer: a cell whose font states a colour (most fonts Excel writes do) shows the link underlined in that colour, not the theme's hyperlink colour | a field the cell's style sets wins; `XlsxFont(color: ...)` in an `XlsxCell` chooses another | `test/xlsx/model/xlsx_sheet_links_test.dart` ("the model writes what the writer writes (m3_hyperlinks)") |
| The cost of `setCell` with a link and of `addConditionalFormat` | grows with the number the sheet already has: the groups are immutable, so each add copies its list; adding very many is quadratic | an undo restores a group by swapping it | measured in W6's generation benchmarks |

### Parity with the writer

| Case | Behaviour | Why | Test |
|---|---|---|---|
| A fixture rebuilt with the model | semantically equal to the writer's: `m1_values`, `m1_dates`, `m1_sheets`, `m1_properties`, `m2_styles`, `m2_columns_rows`, `m2_style_precedence`, `m2_views`, `m2_merges_filter`, `m2_formula_xstring`, `m3_names`, `m3_hyperlinks`, `m3_validation`, `m3_conditional`, `m3_conditional_x14`, `m3_page_setup`, `m3_header_footer`, `m3_protection`, `m3_properties`, `m4_rich_text`, `m4_notes`, `m4_images`, `m4_tables` and `m4_objects`, apart from the two named differences below | one way to write a value | `test/xlsx/model/parity_test.dart` ("fixtures built with the model equal the writer's") |
| `tabSelected` (named difference) | setting the model's `activeSheet` to another sheet writes `tabSelected="1"`, the writer never does; Excel selects the active tab either way (`m1_sheets` and `m2_views`) | an opened file's old `tabSelected` must move, and the writer's output is pinned | `test/xlsx/model/parity_test.dart` ("fixtures built with the model equal the writer's") |
| The tab position of `m1_sheets` (named difference) | the writer's `addSheet(position: 0)` has no model equivalent until W5, so the expected `workbook.xml` moves the first tab last and lowers `activeTab` | structural editing is W5 | `test/xlsx/model/parity_test.dart` ("fixtures built with the model equal the writer's") |
| Re-setting what was read | every style, row format, column, default size, view, tab colour, outline summary and merge, and of W3 `protection`, `pageSetup`, `headerFooter`, `autoFilter`, `printArea`, `setPrintTitles` and the workbook's `protection` and `properties`, set back to what it reads changes nothing, on every writer fixture and producer file; a dangling or invalid `s` is the exception (see "Setting cells"). Validations and conditional formats have no setter of their list: removing each and adding it back keeps the getters' values, in the model and after a reopen. Links have their own test | typing must not alter output | `test/xlsx/model/round_trip_test.dart` ("re-setting what was read changes nothing", "removing and re-adding keeps the meaning"), `test/xlsx/model/xlsx_sheet_links_test.dart` ("an equal link is no edit") |

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
the new row's height, a merge, a frozen first row and a tab colour, defines
the workbook name `Model_edit`, links the new string cell, adds a list
validation, a cell-value rule and a data bar on free cells of the new row,
sets a landscape A4 page setup that fits one page wide, a footer, an auto
filter over the new row (when no filter or table is in the way) and the
workbook's title, sets a rich text cell (`Rich ` bold, `text` plain), a note
by `jet_office` and a 4 by 2 pixel PNG picture on the next free columns of the
new row and a table `Model_table` (a number added when taken) of two columns
over the two rows below it, adds a sheet, saves to `<outDir>` and reads the
edits back with `XlsxReader` and the model; it also writes the generated
workbooks of `tool/write_model_sample.dart`, `w1_generated.xlsx`,
`w2_generated.xlsx`, `w3_generated.xlsx` and `w4_generated.xlsx`, there. CI
runs it on the writer fixtures and validates the output with the Open XML SDK
(spec section 9).

## Port map

W1 to W4 port nothing from Quds (spec section 8): every file is new and
says "Not ported from Quds; written for jet_office." Ports start in W5
(formula reference shifting) and are listed here when they land.
