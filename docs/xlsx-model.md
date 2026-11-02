# XLSX workbook model

`XlsxWorkbook` opens an XLSX file from bytes, or starts empty, lets a caller
read and set cell values, and saves the file again. Saving keeps everything
the caller did not change: the model is the single source of every save.
Decision [`0009`](decisions/0009-phase-3-workbook-model.md) sets the scope
and the fidelity standard.

This page covers milestone W1, the foundation: open and save with no loss, and
generate values. Styles, layout, sheet and workbook features, objects and
structural editing arrive in W2 to W5.

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
number formats of the styles) is kept as opaque XML at its position and
written back, with the namespace declarations it needs.

## What W1 does and does not do

- **Edits.** `setCell` takes a `String`, `num`, `bool`, `DateTime`,
  `XlsxDate`, `XlsxDecimal`, an `XlsxFormula` without a group, or `null`.
  Styled cells, hyperlinks and rich text throw `UnsupportedError` until W2,
  W3 and W4. Editing a shared formula's master throws until W5.
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
- **Merges are not typed or limited.** `<mergeCells>` stays opaque until W2,
  so `XlsxReadLimits.maxMerges` is not applied by the model in W1; memory is
  still bounded by the limit on the sheet part's XML.
- **A workbook with no sheet, or only hidden ones, saves as it came** when it
  was opened. Only a workbook started with `XlsxWorkbook()` needs a visible
  sheet to save.
- **Formulas stay stale until Excel recalculates.** A change in a workbook
  with formulas sets `fullCalcOnLoad="1"`, and the cached results of formulas
  the model did not change are kept. Excel recomputes on open; `XlsxReader`
  and the model's own `cellAt` read the stale values.
- **Memory.** A loaded sheet's store takes less memory than its sheet XML
  in the 100,000 by 12 benchmark: an estimate of 35.5 MB of store (30 bytes
  a cell) against 43.6 MB of XML, 0.81 times, the same on the VM and in
  Chrome (see [`benchmark.md`](benchmark.md), "Model figures"; process memory
  is higher but includes the XML and garbage). A sheet with many formulas
  costs more per cell: each formula cell keeps one side entry for its
  formula (not measured).

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
| Any cell change | `calcChain` is dropped (part, relationship, content type), touching only the workbook's relationships; `fullCalcOnLoad="1"` is set when the workbook has formulas | a stale chain makes Excel repair the file; Excel must recompute | `test/xlsx/model/xlsx_workbook_bookkeeping_test.dart` |
| A change in a workbook without formulas that is fully loaded | no `calcPr` change | nothing to recalculate | `test/xlsx/model/xlsx_workbook_bookkeeping_test.dart` |

### Setting cells

| Case | Behaviour | Why | Test |
|---|---|---|---|
| A value the encoder repairs (forbidden XML characters, text over 32,767 characters) | repaired when set, with the writer's warning; a `NaN` throws then | saving cannot fail on data | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("text escaping"), `test/xlsx/cell_encoder_model_test.dart` |
| Setting a cell | replaces its content and the attributes that described the old value (`cm`, `vm`, `ph`, children); a valid style stays | the old metadata described the old value | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("replaces the value-tied attributes") |
| `null` | a styled cell stays as an empty styled cell; an unstyled one is removed | clearing keeps the format | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("clearing keeps the style") |
| A date in a General cell | takes the writer's date format, appended to `numFmts` and `cellXfs`; a date format stays; another format stays with the writer's date warning; a broken style counts as General | spec 4.12: dates behave as the writer does | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("a date on a General cell", "a broken style"), `test/xlsx/model/styles_part_test.dart` ("withNumberFormat") |
| A cell inside an array or data-table formula, its master included | `StateError`, permanent | Excel refuses it too | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("editing formula groups"), `test/xlsx/model/primitives_test.dart` |
| A shared formula's child | leaves the group; the others stay | the child's formula stays correct | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("editing formula groups") |
| A shared formula's master | `UnsupportedError` until W5 | the children need reference shifting | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("editing formula groups") |
| `XlsxHyperlink`, `XlsxRichText`, `XlsxCell` | `UnsupportedError` naming the milestone (W3, W4, W2) | not typed yet | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("unsupported value types") |
| Any other type, or a position outside the grid | `ArgumentError`, `RangeError` | programmer errors | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` |
| A sheet that is not a worksheet (a chartsheet) | `StateError` at the call | its cells cannot be set | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("not a worksheet") |
| Anything `setCell` throws | nothing has changed, the change log's `hasChanges` included; every mutation runs in a transaction | atomic edits | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("a failed setCell changes nothing"), `test/opc/change_log_test.dart` |
| 10,000 cells on a sheet with formulas | linear time | the formula-group index is kept, not scanned per cell | `test/xlsx/model/xlsx_workbook_set_cell_test.dart` ("takes linear time"), `test/xlsx/model/cell_store_test.dart` ("group masters") |
| A change recorded outside a transaction | `StateError`: every mutation runs in a transaction, so it is always undoable as a set | an unrecorded change cannot be undone | `test/opc/change_log_test.dart` ("record outside a transaction throws") |
| A revert that throws while a transaction rolls back | the other reverts still run, then a `StateError` names the original error and the failed reverts; the model may be inconsistent | a silent half-revert would break atomicity | `test/opc/change_log_test.dart` ("a revert that throws does not stop the rollback") |

### Reading

| Case | Behaviour | Why | Test |
|---|---|---|---|
| `cellAt` and `rows` | show what `XlsxReader` shows for the saved file | one decoder | `test/xlsx/model/xlsx_workbook_reading_test.dart` |
| A value that cannot be read exactly | a warning, once per cell however often it is read, again after it is set | as the reader | `test/xlsx/model/xlsx_workbook_reading_test.dart` |
| A sheet the workbook lists without a part | kept, reads as empty, `sheetPartMissing` | the model must open what the reader opens | `test/xlsx/model/xlsx_workbook_open_save_test.dart` |
| A sheet broken on first access, or a broken styles part | `XlsxReadException` from the first call that loads it, not from `open`; a broken sheet nobody loads is saved from its bytes | spec 4.12: laziness moves the failure to first use | `test/xlsx/model/xlsx_workbook_open_save_test.dart` ("a broken sheet throws on first access") |
| A styles part whose root is not `<styleSheet>` | loads as untyped: General formats, written back unchanged; a date set there keeps its style | the model opens what the reader opens | `test/xlsx/model/styles_part_test.dart` ("an untyped part") |

### Untrusted input

| Case | Behaviour | Why | Test |
|---|---|---|---|
| Every limit of `XlsxReadLimits` but `maxMerges` | applied as the reader applies it, by `open` or on first use of a sheet | the file is untrusted input (decision 0007) | `test/xlsx/read/hostile_files_test.dart` |
| A damaged, truncated or CRC-mismatching entry, even one no sheet reads | `XlsxReadException` (`corruptZip`) from `open` | the model verifies every entry up front | `test/xlsx/model/xlsx_workbook_open_save_test.dart` ("open checks every entry"), `test/xlsx/read/hostile_files_test.dart` |
| Not a ZIP, encrypted, Strict, `.xlsb`, no workbook, a DOCTYPE | `XlsxReadException` as in the reader; a relationship or override pointing at `[Content_Types].xml` or a `.rels` part is never the workbook | metadata is never a document part | `test/xlsx/read/hostile_files_test.dart`, `test/xlsx/read/package_reader_test.dart` ("metadata parts are not workbooks") |
| Mutated files | `open` throws only `XlsxReadException`, and whatever opens reads, sets a cell and saves without throwing | spec 4.9 | `test/xlsx/read/fuzz_test.dart` ("mutated files raise only XlsxReadException") |
| `m1_corrupt.xlsx` (schema-invalid but readable) | the model keeps the stray content faithfully; the Open XML SDK rejects the model's output | preserving is the model's job, validating the validator's | `test/tool/round_trip_model_test.dart` ("the --corrupt workbook keeps its fault"), CI's `validate` job |

## Checking the round trip

`dart run tool/round_trip_model.dart <inDir> <outDir>` opens every `.xlsx` of
a directory, loads every sheet, saves it, writes the bytes to `<outDir>` and
compares the saved package with the input by `comparePackages`
(`tool/src/part_compare.dart`, `ignoreBookkeeping`). CI runs it on the writer
fixtures and on LibreOffice's re-save of them, then validates the output with
the Open XML SDK. Every normalization the comparer makes is pinned in
`test/tool/part_compare_test.dart`.

## Port map

W1 ports nothing from Quds (spec section 8): every file is new and says "Not
ported from Quds; written for jet_office." Ports start in W5 (formula
reference shifting) and are listed here when they land.
