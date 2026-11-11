# Changelog

## Unreleased

### Added

#### Phase 3, the workbook model, W1 (foundation)

- `XlsxWorkbook` opens an XLSX file from bytes (`XlsxWorkbook.open`, within
  `XlsxReadLimits`) or starts an empty one (`XlsxWorkbook()`), reads cells
  (`XlsxSheet.cellAt`, `rows`), sets them (`setCell`: `String`, `num`, `bool`,
  `DateTime`, `XlsxDate`, `XlsxDecimal`, `XlsxFormula`, `null`) and saves
  (`save`, `saveTo`). A sheet loads on first use into a compact cell store;
  what the model does not type is kept as written, so an opened file saved
  without a change is semantically equal to the input (decision 0009).

#### Phase 3, the workbook model, W2 (styles and layout)

- Cell styles (`styleAt`, `setStyle`, `XlsxCell`), rows (`XlsxRowFormat`),
  columns, merges, views and panes, tab colours, the active sheet and colour
  resolution, with the writer's types. Styles are append-only.

#### Phase 3, the workbook model, W3 (sheet and workbook features)

- Defined names, print settings, auto filters, sheet and workbook protection,
  hyperlinks, data validations, conditional formats (Excel 2010's too) and
  document properties, typed with the writer's types and checks.

#### Phase 3, the workbook model, W4 (objects)

- Rich text cells, notes, pictures and tables (`richTextAt`, `setNote`,
  `addPicture`, `addTable`, `setTableStyle`, `resizeTable`, `removeTable`);
  charts, shapes, form controls and threaded comments beside them are kept as
  written.

#### Phase 3, the workbook model, W5 (structural editing)

- `insertRows`, `deleteRows`, `insertColumns`, `deleteColumns`, `renameTable`,
  `renameSheet`, `moveSheet` and `addSheet(position:)`, rewriting every
  reference to what moved as Excel does; `transaction`, `undo` and `redo` with
  `XlsxChangeSet` and `XlsxChange` (no undo stack in the library); the public
  formula lexer `lexFormula`. Two warning codes: `referenceNotShifted` and
  `formulaUnlexable`.

#### Phase 3, the workbook model, W6 (proof and release; the names are fixed)

- A shape's `textlink` is a held reference and shifts with structural edits;
  anchors inside `mc:AlternateContent` move like bare ones (a mixed or
  anchorless alternate content stays whole and warns `referenceNotShifted`).
- Writer parity holds over every fixture of `allFixtures()` except `c1_kinds`
  and `c1_options`, whose charts come with C2.
- Benchmarks of generating workbooks with the model: 100,000 rows of 12
  columns in 3.7 s on the VM and 6.8 s in Chrome (the writers 1.7 s and
  3.9 s), 1,000,000 rows in 38.6 s and 72.1 s, about 30.7 bytes per cell
  retained (`docs/benchmark.md`, "Model generation figures").
- The README has a "Workbook model" section and the example opens, edits and
  generates a workbook with the model.
- The model's names are fixed as of W6: a rename later is a breaking change.
  Known gaps that remain: nothing is compacted, there is no `removeSheet`,
  charts stay opaque until C2. The rules, each with its test, are in
  `docs/xlsx-model.md`.

#### Phase 4, DOCX, D1 (foundation)

- `DocxDocument` opens a DOCX file from bytes (`DocxDocument.open`, within
  `DocxReadLimits`), reads and edits the paragraphs of its body, and saves
  (`save`, `saveTo`) with nothing lost: a body never accessed or never
  edited is copied byte for byte, an edited one is written from the model,
  and what the model does not type (tables, content controls, tracked changes, hyperlinks, drawings,
  fields, the final section) is kept as written in `DocxOpaqueBlock`,
  `DocxOpaqueInline` and `DocxOpaqueRunContent`.
- Typed: `DocxBody`, `DocxParagraph`, `DocxRun` and `DocxRunContent`
  (`DocxText`, `DocxTab`, `DocxBreak`, `DocxCarriageReturn`), with the
  paragraph and run style. Edits are atomic.
- Text rules: `\t` and `\n` become a tab and a break, characters XML forbids
  are removed with a `DocxWarning` (`invalidCharactersRemoved`),
  `xml:space` is set only for text set through the API.
- `DocxDocument()` starts a document like Word for Mac's blank one: A4
  portrait, Aptos 12 through the theme, Word's en-US style ids, no locale and
  no document properties yet.
- The file is untrusted input: `DocxReadException` with a `DocxReadFailure`
  (`notZip`, `corruptZip`, `encrypted`, `legacyDoc`, `unsupportedFormat` for
  Strict OOXML, XLSX and PPTX, `missingDocument`, `malformedXml`,
  `limitExceeded`). Warnings come in English, German and Turkish.
- `pPr` and `rPr` children are written in schema order. Once a part is
  written from the model that holds for every container in it, not only the
  one edited; a document with no edit saves its main part as it was.
- Known gaps: the visible text of an opaque inline holding
  `mc:AlternateContent` or a text box is empty; tables are opaque until D3;
  the final section is opaque until D4; new documents have no `docProps`
  until D5. Whether the Word XML in a new document may ship under the
  package's licence is an open question (`NOTICE`).
- Verification: round trips of generated files, LibreOffice's re-save,
  packaging variants of other producers and the owner's Word for Mac files;
  Open XML SDK validation and LibreOffice's text export in CI; a seeded fuzz
  test in the gate. The owner's Word check is recorded in
  `docs/word-checks.md`; the rules are in `docs/docx-model.md`.

#### Phase 4, DOCX, D2 (formatting, styles and lists)

- Run and paragraph properties are typed: `DocxRun.properties`
  (`DocxRunProperties`: fonts, bold, italic, caps, small caps, strike,
  underline, colour, highlight, shading, size, vertical alignment, character
  spacing, language) and `DocxParagraph.properties`
  (`DocxParagraphProperties`: alignment, indentation, spacing, keep options,
  outline level, borders, shading, tab stops, numbering), with the values
  `DocxColor`, `DocxFonts`, `DocxUnderline`, `DocxShading`, `DocxBorder`,
  `DocxIndentation`, `DocxSpacing`, `DocxTabStop` and their enumerations.
  Lengths are points at the API; a value out of range throws before
  anything changes. A property the model does not understand, or a value it
  cannot read, is kept as written and reads `null`.
- `DocxDocument.styles` (`DocxStyles`): the document defaults and every
  style by id or name, `add` for a custom style, and Word's built-in styles
  (`DocxBuiltInStyle`, `idOf`, `ensure`) added on demand with Word's own
  definitions. Built-ins are recognized by their English name, so
  `style = 'Heading1'` lands on `Balk1` or `berschrift1` in a Turkish or
  German document and adds no second heading.
- `DocxDocument.numbering` (`DocxNumbering`): definitions and instances,
  `addBulletList`, `addNumberedList` and `addInstance` (with start
  overrides) with the lists Word's toolbar writes, and `DocxBody.addListItem`.
- Two warnings, for references set through the API or moved in from another
  document: `styleNotFound` and `numberingNotFound`, in English, German and
  Turkish.
- A styles or numbering part that was loaded and not changed is saved with
  its original bytes; a part with a change is written from the model, which
  drops comments directly under its root and its definitions, and those
  between the children of a properties container. A theme colour
  is written with `w:val="auto"` beside its theme attributes (the Open XML
  SDK accepts it; a reader that ignores `themeColor` shows automatic).
- Known gaps: the paragraph mark's `rPr`, table style parts, `...Chars` and
  universal measures (read as `null`), complex-script formatting and art
  borders are not typed; a dangling reference read from a file is not
  reported; `numberingNotFound` does not check a style's `numPr`.
- Verification: four D2 fixtures validated by the Open XML SDK and compared
  with LibreOffice's text export and re-save, the owner's `builtins.docx`,
  edited owner files validated in CI, and a fuzz test aimed at typed
  attributes. The owner's Word check is in `docs/word-checks.md`; the rules,
  each with its test, are in `docs/docx-model.md`.

#### Phase 4, DOCX, D3 (tables)

- `DocxTable`, `DocxTableRow` and `DocxTableCell` type a `w:tbl` in the body or
  in a cell, so tables nest. `DocxTable.gridColumnsPt` is the grid in points
  and `DocxTableCell.text` the text of a cell; what lies between the typed
  `w:tr` and `w:tc` is kept as written.
- Typed properties, each a nullable get and set: `DocxTable.properties`
  (`style`, `width`, `layout`, `alignment`, `indentationPt`, `borders`,
  `cellMargins`, `look`), `DocxTableRow.properties` (`height`, `cantSplit`,
  `repeatAsHeader`, and `isHeader` on the row) and `DocxTableCell.properties`
  (`width`, `gridSpan`, `verticalMerge`, `verticalAlignment`, `shading`,
  `borders`, `textDirection`), with the values `DocxTableWidth`,
  `DocxTableBorders`, `DocxCellBorders`, `DocxTableMargins`, `DocxTableLook`,
  `DocxRowHeight` and their enumerations.
- Building: `DocxBody.addTable` writes what Word's Insert Table writes (the
  style `Table Grid`, an automatic width, the look `04A0`, equal column
  widths); `DocxTable.addRow` adds a row of text, `DocxTableCell.addTable`
  nests a table, and `DocxTable.new`, `DocxTableRow.new` and
  `DocxTableCell.new` build parts to insert later. Editing: rows, cells and the
  blocks of a cell, and `DocxTable.mergeCells`, which merges across and down as
  Word does. Each edit is atomic.
- Kept as written, never typed: floating tables, table cell spacing, a table's
  own shading, captions, `w:cnfStyle`, `w:hMerge` and the revision children.
- Verification: five D3 fixtures, a table that ends a body
  (`tool/write_table_last.dart`, for Word alone), edited owner files with a
  table, and a fuzz corpus entry with every element of the table values. The
  rules and the known gaps are in `docs/docx-model.md`; the owner's Word check
  is in `docs/word-checks.md`.

#### Phase 4, DOCX, D4 (sections, headers, footers and fields)

- `DocxDocument.sections` lists each `DocxSection`: its `pageSize`, `margins`,
  `columns`, `start`, `titlePage`, `verticalAlignment`, `pageNumbering` and
  `lineNumbering`, each a nullable get and set, and `textWidthPt`.
  `DocxBody.addSection` ends the last section and starts a new one, as Word's
  Insert Break does; the final `w:sectPr`, opaque in D1, is typed.
- Headers and footers: a section's `header`, `firstHeader`, `evenHeader`,
  `footer`, `firstFooter` and `evenFooter` give a `DocxHeaderFooter`, its own
  story or the nearest previous section's (`isInherited`); it is a `DocxStory`
  like the body, so tables and lists go in it. `ownHeader`, `ownFooter`,
  `removeHeader` and `removeFooter` unlink and link a section, and
  `DocxDocument.evenAndOddHeaders` is the one typed child of `settings.xml`.
  Story parts, their relationships and content types are created at save.
- `DocxField` types a complex field of one paragraph (`instruction`, `name`,
  `result`, `resultText`, `properties`), with `.page()`, `.numPages()`,
  `.sectionPages()`, `.date()` and `.time()` and `DocxParagraph.addField`;
  `DocxFieldMark` and `DocxFieldInstruction` are the run content around it.
  The model does not evaluate a field: its text is the cached result.
- No new warning code and no new read limit.
- Verification: three D4 fixtures (`d4_sections`, `d4_headers`, `d4_fields`),
  a document whose last block carries a section break (for Word alone), the
  stories in the round trip and in LibreOffice's re-save text, edited owner
  files with a footer and a landscape section, and a fuzz corpus entry of
  every section child and six stories. The rules and the known gaps are in
  `docs/docx-model.md`; the owner's Word check is in `docs/word-checks.md`.

#### Phase 4, DOCX, D5 (pictures, hyperlinks, bookmarks and properties)

- `DocxDocument.properties`: the core, extended and custom document
  properties as `OfficeProperties`, the type `XlsxWorkbook.properties` gives
  too, with `revision` and `application` added. Found by their package
  relationships, loaded on first use; a part nothing changed is saved byte
  for byte, a set re-encodes only what it changes, and a new document gets
  `docProps` only once a property is set.
- `DocxPicture`: an inline picture, typed run content with its size, name,
  description and image; `DocxParagraph.addPicture` adds a PNG or JPEG in the
  body, a cell, a header or a footer, at its pixel size or a size given, with
  media shared by equal bytes. Floating pictures and charts stay opaque.
- `DocxHyperlink`: an inline holding inlines, with `url`, `anchor` and
  `tooltip`; `DocxParagraph.addHyperlink` adds an external or internal link
  in the `Hyperlink` style.
- `DocxBookmarkStart` and `DocxBookmarkEnd`, with `addBookmarkStart`,
  `addBookmarkEnd` and `repairBookmarkName`.
- Media parts, relationships, drawing ids and bookmark ids are allocated at
  each save and never stored in the model, so two saves agree and an undo
  leaves nothing behind.
- Two warnings: `propertyValueInvalid` and `bookmarkNameRepaired`, in
  English, German and Turkish.
- Verification: three D5 fixtures, the tools reading pictures, links,
  bookmarks and properties and encoding the properties parts, edited owner
  files with a picture, two links, a bookmark and a title, and a fuzz corpus
  entry of broken pictures, links and properties. The rules, each with its
  test, and the known gaps are in `docs/docx-model.md`; the owner's Word check
  is in `docs/word-checks.md`.

#### Phase 4, DOCX, D6 (the list export; the names are fixed)

- `DocxListExport` and `DocxListColumn`: the Word counterpart of
  `XlsxListExport`. `writeTo(document, rows, {totals})` writes a list into the
  last section of a document, `toDocx(rows, {totals, properties})` returns a
  document of its own. Every page has a header (a logo at the left, the
  report's name centred in bold, the date at the right) and a footer with the
  page number and the number of pages (`Page 2 of 3`, or the caller's text);
  an optional caption stands above the table. The table is `Table Grid`, with a
  header row that is bold, shaded, repeated on every page and never split, the
  data rows and a totals row; a column with a number format is aligned to the
  end. The page is A4 portrait with Word's blank-document margins unless the
  caller gives others. In a document that is opened, the last section's even
  header and footer are written too when the document has odd and even
  headers, and a section of several text columns is set to one.
- Values show as Excel shows them: a `num`, `FormatDecimal` (so an
  `XlsxDecimal`), `DateTime`, `Duration` or `bool` goes through jet_core's
  `NumberFormatter` with the column's number format code and the export's
  locale. The totals are the caller's values (Word has no formulas), and the
  date is fixed text, not a `DATE` field. A bad column, header, width, number
  or date format code, logo height, header shading, totals value, row that is
  too long or value that cannot be shown throws `ArgumentError` naming the
  field, and always before the document changes: every row is turned into its
  cell texts first, so a bad row leaves the document as it was. The one error
  that can come after the document changed is the `DocxReadException` of a
  header or footer part of an opened file that cannot be read. No new warning
  code.
- `OfficeProperties.copyWith` replaces the given fields and keeps the others
  (settles D5's gap; `tool/edit_docx.dart` and `tool/edit_model.dart` use it).
- Renamed, with no aliases (none had been released): `DocxTable.insertRowAt` is
  now `insertRow`, `DocxTableRow.insertCellAt` is now `insertCell`, and
  `DocxCellAlignment` is now `DocxCellVerticalAlignment`. The dartdoc review of
  the whole DOCX surface found no other change; `DocxVerticalAlign`, the short
  `DocxTextDirection` values and `DocxAlignment` keep their names, with the
  reasons in `docs/docx-model.md`. Update uses. The names are fixed as of D6.
- Verification: two D6 fixtures (`d6_list`, a Turkish list of 120 rows with a
  logo, a date, a totals row and `Sayfa 1 / 3`; `d6_list_landscape`, twelve
  columns on landscape A4), a benchmark that opens, changes and saves a Word
  document of about 40,000 paragraphs (figures in `docs/benchmark.md`), and a
  fuzz run of 900 cases a seed. The rules and the known gaps are in
  `docs/docx-model.md`; the owner's Word check is in `docs/word-checks.md`,
  which also holds the German and Turkish check of the DOCX warning messages.

### Changed

- Workbook model (W6): `XlsxSheet.removePicture` is now `removePictureAt`,
  `XlsxSheet.movePicture` is now `movePictureAt`,
  `XlsxFormulaTokenKind.open` and `close` are now `parenOpen` and
  `parenClose`, and `XlsxChange`'s constructor is private, with no aliases
  (none had been released). The workbook model's names are fixed as of W6.
- Renamed the format-neutral public types, with no aliases: `XlsxLocale` is
  now `OfficeLocale`, `XlsxImage` is now `OfficeImage`, `XlsxImageFormat`
  is now `OfficeImageFormat` and `XlsxProperties` is now `OfficeProperties`
  (D5). Update imports and uses. One behaviour changed with it: setting the
  properties of an XLSX workbook to a value whose `revision` or `application`
  is null now removes `cp:revision` and `Application`, which were kept, untyped,
  before.
- DOCX (D6): `DocxTable.insertRowAt` is now `insertRow`,
  `DocxTableRow.insertCellAt` is now `insertCell` and `DocxCellAlignment` is
  now `DocxCellVerticalAlignment`, with no aliases; the DOCX names are fixed.
- The number format engine moved to the new package `jet_core` (decision
  0012), with neutral names and no aliases: `XlsxNumberFormatter` is now
  `NumberFormatter`, `XlsxFormatLocale` is `FormatLocale`,
  `XlsxFormattedValue` is `FormattedValue` (`color` is a `FormatColor?`,
  `warning` a `FormatWarning?`), `XlsxFormatPart` and its kin are
  `FormatPart`, `FormatText`, `FormatPadding` and `FormatFill`.
  `jet_office` re-exports them. `XlsxDecimal` and `XlsxErrorValue` extend
  `FormatDecimal` and `FormatErrorValue`, so values from the reader go to the
  formatter as they are. `formatCell` is an extension on `NumberFormatter`,
  and `FormatWarning.xlsxCode` and `FormatColor.xlsxColor` map the warning and
  the colour back to `XlsxWarningCode` and `XlsxColor`. What Excel shows is
  unchanged. `jet_core` is a package of this repository's workspace (`packages/jet_core`). (decision 0013)

## 0.1.0-dev.1 (unreleased)

Phase 1, the XLSX writer, and phase 2, the XLSX reader. Not published yet.

### Phase 2: the XLSX reader

#### R1, foundation

- `XlsxReader` reads an XLSX file from bytes: the sheet list
  (`XlsxReadSheet`, with its visibility) and the date system on opening,
  then each sheet's rows lazily, as `XlsxReadRow`s of `XlsxReadCell`s.
- Cell values: text (shared and inline), numbers as `XlsxDecimal` with the
  file's digits, booleans and formula text with its cached result.
- The file is untrusted input: ZIP entries are inflated within
  `XlsxReadLimits` (entry count and size, total size, compression ratio,
  shared strings, XML depth, text length, sheets) with CRC checks, and the
  XML parser refuses a `DOCTYPE` and anything but UTF-8.
- A file that cannot be read throws `XlsxReadException`, whose
  `XlsxReadFailure` says why (`notZip`, `corruptZip`, `encrypted`,
  `legacyXls`, `unsupportedFormat` for Strict OOXML and `.xlsb`,
  `missingWorkbook`, `malformedXml`, `limitExceeded`).
- A cell or sheet that cannot be read exactly is a warning in
  `XlsxReader.warnings`, with the writer's `XlsxWarning` type and messages
  in English, German and Turkish.
- Every phase 1 fixture reads back to what the writer stored.

#### R2, types

- Number formats and cell formats from the styles part: each cell carries
  `numberFormatId`, `numberFormat` and `isDate`.
- A number in a date format reads as a UTC `DateTime`, one in a time format
  as a `Duration`, in the 1900 and 1904 date systems; ISO dates (`t="d"`)
  and inline strings are read.
- Error values (`XlsxErrorValue`), shared, array and data-table formula
  groups (`XlsxFormulaGroup`) and merged ranges (`XlsxReader.merges`,
  `mergesAt`).
- `XlsxDecimal.toDouble()` and `XlsxDecimal.toIntOrNull()`.

#### R3, other producers and hostile files

- Packages shaped like those of LibreOffice, Google Sheets, the .NET Open
  XML SDK and an ERP export are read, and CI reads LibreOffice's re-save of
  every fixture against the expected values.
- A hostile-file test per limit and per kind of damage, and a seeded fuzz
  test that requires the reader to throw nothing but `XlsxReadException`.
- A harness for files saved by Excel and Google Sheets, with values the
  owner confirms; the files themselves are still pending.
- `XlsxReadException`'s constructor is no longer `const` (it was in R1):
  its `part` is shortened and cleaned for display.

#### R4, release

- A read benchmark of the 100,000-row workload and of the largest single
  sheet the default limits accept (`docs/benchmark.md`). Reading is slower
  than writing on the VM (2.7 s against 1.5 s on the machine measured).
- The public API review, the README's "Reading" section, the example's read
  back and this changelog.

#### Changed since the M5 merge

- `XlsxWarning` gains `detail`, the parameter of a code that has one (the
  number format id of `unresolvedNumberFormat`); warnings of one code on one
  sheet are kept apart by detail, up to ten details.
- `XlsxWarningCode` gains the reader's 18 codes, from `sheetPartMissing` to
  `mergeRangeInvalid`, each with a message in English, German and Turkish.
- A warning may name no cell: `sheetPartMissing` concerns a whole sheet and
  `mergeRangeInvalid` counts skipped ranges, not cells.
- `XlsxDecimal` gains `toDouble()` and `toIntOrNull()`.

### Phase 1: the XLSX writer

#### M1, foundation

- `XlsxWriter` (in memory) and `XlsxStreamWriter` (to a sink), with the same
  calls and the same bytes on one platform.
- Cell values: text, numbers, booleans, `DateTime`, `XlsxDate`,
  `XlsxDecimal`, empty cells and `XlsxFormula` with a cached value.
- Sheets with sanitized, unique names, tab order and the active sheet.
- Document properties.
- Warnings for data the writer repairs, in English, German and Turkish.

#### M2, styling and layout

- Fonts, pattern and gradient fills, borders, alignment, protection and
  number formats, merged in the order column, row, cell.
- Column widths, row heights, hidden rows and columns, outlines.
- Sheet views, freeze and split panes, tab colors, hidden sheets.
- Merged cells and the auto filter.

#### M3, sheet and workbook features

- Defined names, print areas and print titles.
- Hyperlinks to web, e-mail, sheet and location targets.
- Data validation and conditional formatting (including data bars and icon
  sets).
- Page setup, headers and footers.
- Sheet and workbook protection.
- More document properties: manager, content status and custom properties.

#### M4, objects

- Rich text cells, notes, PNG and JPEG pictures and tables with totals.

#### M5, release

- `XlsxListExport`: a caption, a frozen header repeated on every printed
  page, an auto filter or an Excel table, and a totals row, in one call.
  A Count total is shown as a plain number, whatever the column format.
- A benchmark of 100,000 rows on the VM and in Chrome (`docs/benchmark.md`).
- The README, an example and this changelog.
- Phase 1 writes XLSX only; phase 2 above adds the reader. Modifying files,
  and DOCX, are later phases.

#### Changed since the M4 merge

- Style errors: a bad fill, border or alignment in a style is now named
  `fill.<field>`, `border.<field>` or `alignment.<field>`. It was the bare
  field (`foreground`, `left`, `indent`). A bad font in a row or cell style
  is named `font.<field>` (`font.size`, `font.name`); on main it was the bare
  field (`size`, `name`). Column styles name
  `columns[i].style.font.<field>`, `columns[i].style.fill.foreground` and so
  on (was `columns[i].style.<field>`). The name now says which part failed.
- Conditional format style errors: `rules[i].style.<field>` is now
  `rules[i].style.<part>.<field>`. For example `rules[0].style.foreground`
  became `rules[0].style.fill.foreground`, `rules[2].style.size` became
  `rules[2].style.font.size` and `rules[0].style.left` became
  `rules[0].style.border.left`. `rules[i].style.numFmt`, `.alignment` and
  `.protection` are unchanged.
- A `DateTime` is cut to whole seconds, with no warning. Excel shows a serial
  rounded to the second, so 23:59:59.999 used to show as the next day. To keep
  milliseconds, write the serial as a `double` with an `ss.000` format.
- A finite `double` is written in its shortest form (5.0 as 5), the same on
  the VM and the web.
- A table without a header row is refused once its totals row is written, and
  huge picture offsets and sizes throw `ArgumentError`.
- A data bar without `negativeBorderColor` writes none, so Excel draws the
  negative border in the positive border color; the `XlsxDataBar` dartdoc
  says so.
