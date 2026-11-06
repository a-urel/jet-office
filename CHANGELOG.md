# Changelog

## Unreleased

### Added

#### Phase 4, DOCX, D1 (foundation; the API may change before D6)

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

#### Phase 4, DOCX, D2 (formatting, styles and lists; the API may change before D6)

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

### Changed

- Renamed the format-neutral public types, with no aliases: `XlsxLocale` is
  now `OfficeLocale`, `XlsxImage` is now `OfficeImage` and `XlsxImageFormat`
  is now `OfficeImageFormat`. Update imports and uses; nothing else changed.
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
  unchanged. `jet_core` is a `path: ../jet-core` dependency until its GitHub
  repository exists.

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
